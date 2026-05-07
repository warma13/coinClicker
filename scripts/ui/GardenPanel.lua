-- ============================================================================
-- ui/GardenPanel.lua
-- 项目孵化园面板 —— 种植网格、种子选择、土壤切换、图鉴
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local GC = require("config.GardenConfig")
local GP = {}

-- 内部引用
local uiRoot_   = nil
local overlay_  = nil   -- 全屏覆盖层
local panel_    = nil
local visible_  = false
local manager_  = nil   -- GameManager 引用
local gardenMgr_ = nil  -- GardenManager 引用

-- UI 缓存
local gridContainer_ = nil
local cellCache_     = {}   -- cellCache_[r][c] = { panel, icon, label }
local seedPicker_    = nil
local seedDetail_    = nil  -- 选中种子的详情说明
local crossbreedGuide_ = nil  -- 杂交图鉴
local soilRow_       = nil
local statusLabel_   = nil
local collectionLabel_ = nil
local expandBtn_     = nil
local expandLabel_   = nil

-- 种植状态
local selectedSeed_  = nil  -- 当前选中的种子 id
local seedBtnCache_  = {}   -- seedBtnCache_[seedId] = btn widget

-- 确认弹窗
local confirmOverlay_ = nil
local confirmShowing_ = false

-- 上次刷新快照
local lastFingerprint_ = ""

-- ============================================================================
-- 阶段显示
-- ============================================================================
-- 前向声明（local 化内部函数，防止全局污染）
-- ============================================================================
local BuildPanel
local RebuildGrid
local RebuildSeedPicker
local RebuildSeedDetail
local RebuildCrossbreedGuide
local RebuildSoilRow
local UpdateStatus
local UpdateExpandBtn
local OnCellClick
local OnSeedSelect
local ShowSoilConfirm
local HideSoilConfirm

-- ============================================================================

local STAGE_INFO = {
    [GC.STAGE_EMPTY]   = { icon = "",   color = { 60, 55, 80, 120 },  text = "空地" },
    [GC.STAGE_SPROUT]  = { icon = "🌱", color = { 60, 100, 60, 200 }, text = "萌芽" },
    [GC.STAGE_GROWING] = { icon = "🌿", color = { 50, 130, 50, 200 }, text = "生长" },
    [GC.STAGE_BLOOM]   = { icon = "🌸", color = { 130, 80, 130, 200 },text = "开花" },
    [GC.STAGE_MATURE]  = { icon = "✨", color = { 200, 180, 50, 200 },text = "成熟" },
    [GC.STAGE_WILTING] = { icon = "🍂", color = { 180, 120, 50, 200 },text = "枯萎" },
    [GC.STAGE_DEAD]    = { icon = "💀", color = { 100, 50, 50, 200 }, text = "死亡" },
}

-- ============================================================================
-- 工具
-- ============================================================================

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 3600 then
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        return string.format("%dh%02dm", h, m)
    end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

-- ============================================================================
-- 初始化
-- ============================================================================

function GP.Init(root, gm)
    uiRoot_ = root
    manager_ = gm
    gardenMgr_ = gm.GetGardenManager()
    BuildPanel()
end

-- ============================================================================
-- 显示 / 隐藏（全屏覆盖式弹窗）
-- ============================================================================

function GP.Show()
    if not overlay_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    lastFingerprint_ = ""
    uiRoot_:AddChild(overlay_)
    GP.Refresh()
end

function GP.Hide()
    if not overlay_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(overlay_)
    -- 关闭确认弹窗
    HideSoilConfirm()
end

function GP.Toggle()
    if visible_ then GP.Hide() else GP.Show() end
end

function GP.IsVisible()
    return visible_
end

-- ============================================================================
-- 刷新（增量）
-- ============================================================================

function GP.Refresh()
    if not visible_ or not gardenMgr_ then return end

    -- 构建指纹
    local gridSize = gardenMgr_.GetGridSize()
    local fp = "sz" .. gridSize .. ":soil" .. gardenMgr_.GetSoilId()
             .. ":disc" .. gardenMgr_.GetDiscoveredCount()
             .. ":sel" .. tostring(selectedSeed_)
             .. ":cps" .. math.floor(GameState.coinsPerSecond)

    -- 网格状态指纹
    for r = 1, gridSize do
        for c = 1, gridSize do
            local plot = gardenMgr_.GetPlot(r, c)
            if plot then
                fp = fp .. ":" .. r .. c
                   .. (plot.seedId or "x")
                   .. plot.stage
            end
        end
    end

    -- 计时器指纹（粗粒度，每 5 秒变化）
    local soilCD = math.floor(gardenMgr_.GetSoilCooldown() / 5)
    local bugImm = math.floor(gardenMgr_.GetBugImmunityTimer() / 5)
    local growBst = math.floor(gardenMgr_.GetGrowthBoostTimer() / 5)
    fp = fp .. ":sc" .. soilCD .. ":bi" .. bugImm .. ":gb" .. growBst

    if fp == lastFingerprint_ then return end
    lastFingerprint_ = fp

    -- 全量重建内容
    RebuildGrid()
    RebuildSeedPicker()
    RebuildSeedDetail()
    RebuildCrossbreedGuide()
    RebuildSoilRow()
    UpdateStatus()
    UpdateExpandBtn()
end

-- ============================================================================
-- 内部：构建面板骨架
-- ============================================================================

BuildPanel = function()
    gridContainer_ = UI.Panel {
        width = "100%",
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        paddingTop = 4, paddingBottom = 4,
    }

    seedPicker_ = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 4,
        paddingLeft = 4, paddingRight = 4,
    }

    seedDetail_ = UI.Panel {
        width = "100%",
        paddingLeft = 6, paddingRight = 6,
    }

    crossbreedGuide_ = UI.Panel {
        width = "100%",
        gap = 3,
        paddingLeft = 4, paddingRight = 4,
    }

    soilRow_ = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 4,
        alignItems = "center",
        paddingTop = 4,
    }

    statusLabel_ = UI.Label {
        text = "",
        fontSize = 10,
        fontColor = { 150, 180, 150, 200 },
        textAlign = "center",
        width = "100%",
    }

    collectionLabel_ = UI.Label {
        text = "",
        fontSize = 11,
        fontColor = { 200, 200, 150, 220 },
        textAlign = "center",
    }

    expandLabel_ = UI.Label {
        text = "扩建",
        fontSize = 11,
        fontColor = { 255, 255, 255, 220 },
    }

    expandBtn_ = UI.Panel {
        flexDirection = "row", alignItems = "center", justifyContent = "center",
        gap = 4,
        paddingLeft = 10, paddingRight = 10, paddingTop = 5, paddingBottom = 5,
        borderRadius = 6,
        backgroundColor = { 80, 60, 120, 220 },
        borderWidth = 1, borderColor = { 160, 130, 220, 180 },
        pointerEvents = "auto",
        onPointerDown = function()
            if manager_ then
                manager_.OnGardenExpand()
            end
        end,
        children = {
            expandLabel_,
        },
    }

    panel_ = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        alignItems = "center",
        paddingTop = 10, paddingLeft = 6, paddingRight = 6,
        paddingBottom = 6,
        pointerEvents = "auto",
        children = {
            -- 标题行（含关闭按钮）
            UI.Panel {
                width = "100%",
                flexDirection = "row", alignItems = "center",
                justifyContent = "space-between",
                marginBottom = 2,
                paddingLeft = 6, paddingRight = 4,
                children = {
                    -- 左侧：图标+标题
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Panel { width = 22, height = 22,
                                backgroundImage = "image/侧栏_孵化园.png",
                                backgroundFit = "contain" },
                            UI.Label {
                                text = "项目孵化园",
                                fontSize = 17,
                                fontColor = { 150, 220, 130, 255 },
                            },
                        },
                    },
                    -- 右侧：关闭按钮
                    UI.Panel {
                        width = 28, height = 28,
                        justifyContent = "center", alignItems = "center",
                        borderRadius = 14,
                        backgroundColor = { 60, 55, 80, 180 },
                        pointerEvents = "auto",
                        onPointerDown = function()
                            GP.Hide()
                        end,
                        children = {
                            UI.Label {
                                text = "X",
                                fontSize = 14,
                                fontColor = { 200, 200, 220, 220 },
                                textAlign = "center",
                            },
                        },
                    },
                },
            },

            -- 图鉴进度
            collectionLabel_,

            -- 可滚动内容
            UI.ScrollView {
                flex = 1,
                width = "100%",
                showScrollbar = false,
                children = {
                    UI.Panel {
                        width = "100%",
                        gap = 8,
                        paddingBottom = 20,
                        alignItems = "center",
                        children = {
                            -- 种植网格
                            gridContainer_,
                            -- 种子选择
                            UI.Label {
                                text = "选择种子",
                                fontSize = 12,
                                fontColor = { 180, 170, 200, 180 },
                                width = "100%",
                                textAlign = "center",
                                marginTop = 4,
                            },
                            seedPicker_,
                            -- 种子详情
                            seedDetail_,
                            -- 杂交图鉴
                            UI.Label {
                                text = "杂交图鉴",
                                fontSize = 12,
                                fontColor = { 180, 170, 200, 180 },
                                width = "100%",
                                textAlign = "center",
                                marginTop = 4,
                            },
                            crossbreedGuide_,
                            -- 土壤切换
                            UI.Label {
                                text = "团队模式",
                                fontSize = 12,
                                fontColor = { 180, 170, 200, 180 },
                                width = "100%",
                                textAlign = "center",
                                marginTop = 4,
                            },
                            soilRow_,
                            -- 状态
                            statusLabel_,
                            -- 扩建
                            expandBtn_,
                        },
                    },
                },
            },
        },
    }

    -- 右侧抽屉栏（定位在商店面板左侧）
    local dpr = graphics:GetDPR()
    local logicalW = graphics:GetWidth() / dpr
    local drawerW = math.floor(logicalW * 0.3)

    overlay_ = UI.Panel {
        position = "absolute",
        top = 0,
        right = "30%",
        width = drawerW,
        height = "100%",
        backgroundColor = { 28, 26, 38, 245 },
        borderColor = { 80, 120, 80, 100 },
        borderWidth = { 0, 1, 0, 1 },
        pointerEvents = "auto",
        zIndex = 100,
        children = {
            panel_,
        },
    }
end

-- ============================================================================
-- 内部：重建网格
-- ============================================================================

RebuildGrid = function()
    if not gridContainer_ or not gardenMgr_ then return end
    gridContainer_:RemoveAllChildren()
    cellCache_ = {}

    local gridSize = gardenMgr_.GetGridSize()
    local cellSize = math.floor(math.min(38, 180 / gridSize))

    for r = 1, gridSize do
        cellCache_[r] = {}
        local rowPanel = UI.Panel {
            flexDirection = "row",
            gap = 2,
            justifyContent = "center",
        }

        for c = 1, gridSize do
            local plot = gardenMgr_.GetPlot(r, c)
            local stageInfo = STAGE_INFO[plot and plot.stage or GC.STAGE_EMPTY]
            local seedDef = plot and plot.seedId and GC.FindSeed(plot.seedId) or nil

            local cellIcon = UI.Label {
                text = stageInfo.icon,
                fontSize = math.floor(cellSize * 0.5),
                textAlign = "center",
                width = "100%",
            }

            local cellLabel = UI.Label {
                text = seedDef and string.sub(seedDef.name, 1, 6) or "",
                fontSize = 8,
                fontColor = { 220, 220, 220, 180 },
                textAlign = "center",
                width = "100%",
            }

            -- 进度条（生长中显示）
            local progressText = ""
            if seedDef and plot.stage >= GC.STAGE_SPROUT and plot.stage <= GC.STAGE_BLOOM then
                local pct = math.min(100, math.floor(plot.elapsed / seedDef.growthTime * 100))
                progressText = pct .. "%"
            elseif plot and plot.stage == GC.STAGE_MATURE then
                progressText = "收获!"
            elseif plot and plot.stage == GC.STAGE_WILTING then
                progressText = "快收!"
            elseif plot and plot.stage == GC.STAGE_DEAD then
                progressText = "清理"
            end

            local progressLabel = UI.Label {
                text = progressText,
                fontSize = 7,
                fontColor = (plot and plot.stage == GC.STAGE_MATURE)
                    and { 255, 220, 50, 255 }
                    or (plot and plot.stage == GC.STAGE_WILTING)
                    and { 255, 150, 50, 255 }
                    or { 150, 200, 150, 180 },
                textAlign = "center",
                width = "100%",
            }

            -- 交互背景色
            local bgColor = { stageInfo.color[1], stageInfo.color[2], stageInfo.color[3], stageInfo.color[4] }
            if not plot or not plot.seedId then
                -- 空地：如果选中了种子，高亮可种植
                if selectedSeed_ then
                    bgColor = { 60, 100, 60, 150 }
                end
            end

            local row, col = r, c  -- 闭包捕获
            local cell = UI.Panel {
                width = cellSize, height = cellSize,
                justifyContent = "center", alignItems = "center",
                borderRadius = 6,
                borderWidth = 1,
                backgroundColor = bgColor,
                borderColor = { 80, 75, 100, 150 },
                pointerEvents = "auto",
                onPointerDown = function()
                    OnCellClick(row, col)
                end,
                children = {
                    cellIcon,
                    cellLabel,
                    progressLabel,
                },
            }

            cellCache_[r][c] = { panel = cell, icon = cellIcon, label = cellLabel }
            rowPanel:AddChild(cell)
        end

        gridContainer_:AddChild(rowPanel)
    end
end

-- ============================================================================
-- 内部：重建种子选择器
-- ============================================================================

RebuildSeedPicker = function()
    if not seedPicker_ or not gardenMgr_ then return end
    seedPicker_:RemoveAllChildren()
    seedBtnCache_ = {}

    local plantable = gardenMgr_.GetPlantableSeeds()
    for _, seedDef in ipairs(plantable) do
        local sid = seedDef.id
        local isSelected = (selectedSeed_ == sid)
        local tierColor = seedDef.tier == 2
            and { 180, 130, 255, 255 }
            or { 130, 200, 130, 255 }

        -- 种植成本
        local costMul = seedDef.costMul or 0
        local costText = ""
        local canAfford = true
        if costMul > 0 then
            local cost = GameState.coinsPerSecond * costMul
            costText = GameState.FormatNumber(cost)
            canAfford = GameState.coins >= cost
        end

        local btn = UI.Panel {
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            width = 52, height = 56,
            borderRadius = 6, borderWidth = 1,
            backgroundColor = isSelected and { 60, 100, 60, 220 } or { 35, 32, 50, 200 },
            borderColor = isSelected and { 120, 220, 120, 220 } or { 60, 55, 80, 120 },
            opacity = canAfford and 1.0 or 0.5,
            pointerEvents = "auto",
            onPointerDown = function()
                OnSeedSelect(sid)
            end,
            children = {
                UI.Label {
                    text = seedDef.tier == 2 and "🌟" or "🌱",
                    fontSize = 14,
                },
                UI.Label {
                    text = string.sub(seedDef.name, 1, 6),
                    fontSize = 9,
                    fontColor = tierColor,
                    textAlign = "center",
                },
                UI.Label {
                    text = costText,
                    fontSize = 7,
                    fontColor = canAfford and { 200, 200, 150, 180 } or { 255, 100, 100, 200 },
                    textAlign = "center",
                },
            },
        }
        seedBtnCache_[sid] = btn
        seedPicker_:AddChild(btn)
    end
end

-- ============================================================================
-- 内部：重建种子详情
-- ============================================================================

local BUFF_TYPE_NAMES = {
    cps = "每秒产出",
    cpc = "每次点击",
    buildingCost = "建筑费用",
}

RebuildSeedDetail = function()
    if not seedDetail_ then return end
    seedDetail_:RemoveAllChildren()

    if not selectedSeed_ then return end
    local seedDef = GC.FindSeed(selectedSeed_)
    if not seedDef then return end

    local lines = {}

    -- 描述
    lines[#lines + 1] = { text = seedDef.desc or "", color = { 190, 190, 210, 220 }, size = 10 }

    -- 生长时间
    lines[#lines + 1] = {
        text = "⏱ 生长 " .. FormatTime(seedDef.growthTime),
        color = { 160, 200, 160, 200 }, size = 10,
    }

    -- 种植成本
    local costMul = seedDef.costMul or 0
    if costMul > 0 then
        local cost = GameState.coinsPerSecond * costMul
        local canAfford = GameState.coins >= cost
        lines[#lines + 1] = {
            text = "💰 种植成本 " .. GameState.FormatNumber(cost) .. "（" .. costMul .. "秒产出）",
            color = canAfford and { 200, 200, 150, 200 } or { 255, 120, 120, 220 },
            size = 10,
        }
    end

    -- 收获金币
    if seedDef.harvestCpsMul then
        local harvest = GameState.coinsPerSecond * seedDef.harvestCpsMul
        lines[#lines + 1] = {
            text = "🪙 收获 " .. GameState.FormatNumber(harvest) .. "（" .. seedDef.harvestCpsMul .. "秒产出）",
            color = { 255, 220, 100, 200 }, size = 10,
        }
    end

    -- Buff 效果
    if seedDef.buffType and seedDef.buffValue then
        local typeName = BUFF_TYPE_NAMES[seedDef.buffType] or seedDef.buffType
        local valText
        if seedDef.buffValue >= 1 then
            valText = "+" .. math.floor((seedDef.buffValue - 1) * 100 + 0.5) .. "%"
        else
            valText = "-" .. math.floor((1 - seedDef.buffValue) * 100 + 0.5) .. "%"
        end
        lines[#lines + 1] = {
            text = "✨ " .. typeName .. " " .. valText .. "  持续" .. FormatTime(seedDef.buffDuration or 0),
            color = { 180, 160, 255, 220 }, size = 10,
        }
    end

    -- 罢工防护
    if seedDef.bugImmunity then
        lines[#lines + 1] = {
            text = "🛡 罢工防护 " .. FormatTime(seedDef.bugImmunity),
            color = { 120, 200, 180, 200 }, size = 10,
        }
    end

    -- 杂交来源（进阶种子）
    if seedDef.parents then
        local pA = GC.FindSeed(seedDef.parents[1])
        local pB = GC.FindSeed(seedDef.parents[2])
        local nameA = pA and pA.name or seedDef.parents[1]
        local nameB = pB and pB.name or seedDef.parents[2]
        lines[#lines + 1] = {
            text = "🧬 杂交 " .. nameA .. " × " .. nameB,
            color = { 160, 140, 200, 180 }, size = 9,
        }
    end

    -- 构建 UI
    local detailPanel = UI.Panel {
        width = "100%",
        backgroundColor = { 30, 28, 45, 200 },
        borderRadius = 6,
        borderWidth = 1,
        borderColor = { 70, 65, 100, 150 },
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 6, paddingBottom = 6,
        gap = 3,
    }

    -- 标题行
    local tierIcon = seedDef.tier == 2 and "🌟" or "🌱"
    detailPanel:AddChild(UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", gap = 4,
        children = {
            UI.Label { text = tierIcon, fontSize = 13 },
            UI.Label {
                text = seedDef.name,
                fontSize = 12,
                fontColor = seedDef.tier == 2
                    and { 200, 160, 255, 255 }
                    or { 150, 220, 150, 255 },
            },
        },
    })

    -- 分隔线
    detailPanel:AddChild(UI.Panel {
        width = "100%", height = 1,
        backgroundColor = { 60, 55, 80, 120 },
    })

    -- 各行信息
    for _, line in ipairs(lines) do
        detailPanel:AddChild(UI.Label {
            text = line.text,
            fontSize = line.size,
            fontColor = line.color,
            width = "100%",
        })
    end

    seedDetail_:AddChild(detailPanel)
end

-- ============================================================================
-- 内部：重建杂交图鉴
-- ============================================================================

RebuildCrossbreedGuide = function()
    if not crossbreedGuide_ or not gardenMgr_ then return end
    crossbreedGuide_:RemoveAllChildren()

    for _, adv in ipairs(GC.advancedSeeds) do
        local discovered = gardenMgr_.IsDiscovered(adv.id)
        local pA = GC.FindSeed(adv.parents[1])
        local pB = GC.FindSeed(adv.parents[2])
        local nameA = pA and pA.name or adv.parents[1]
        local nameB = pB and pB.name or adv.parents[2]

        local resultName = discovered and adv.name or "???"
        local resultDesc = discovered and adv.desc or "尚未发现，尝试杂交吧"

        -- buff 摘要
        local buffText = ""
        if discovered and adv.buffType and adv.buffValue then
            local typeName = BUFF_TYPE_NAMES[adv.buffType] or adv.buffType
            local valText
            if adv.buffValue >= 1 then
                valText = "+" .. math.floor((adv.buffValue - 1) * 100 + 0.5) .. "%"
            else
                valText = "-" .. math.floor((1 - adv.buffValue) * 100 + 0.5) .. "%"
            end
            buffText = typeName .. " " .. valText
        end

        local row = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 4,
            backgroundColor = discovered
                and { 35, 32, 55, 200 }
                or { 30, 28, 42, 150 },
            borderRadius = 5,
            borderWidth = 1,
            borderColor = discovered
                and { 80, 65, 130, 150 }
                or { 50, 45, 65, 100 },
            paddingLeft = 6, paddingRight = 6,
            paddingTop = 4, paddingBottom = 4,
        }

        -- 配方列：父本A × 父本B
        row:AddChild(UI.Panel {
            width = 80,
            flexDirection = "column", alignItems = "center",
            children = {
                UI.Label {
                    text = nameA .. " × " .. nameB,
                    fontSize = 8,
                    fontColor = { 160, 150, 180, 200 },
                    textAlign = "center",
                },
            },
        })

        -- 箭头
        row:AddChild(UI.Label {
            text = "→",
            fontSize = 11,
            fontColor = { 120, 110, 150, 180 },
        })

        -- 结果列
        local resultChildren = {
            UI.Label {
                text = (discovered and "🌟 " or "❓ ") .. resultName,
                fontSize = 10,
                fontColor = discovered
                    and { 200, 160, 255, 255 }
                    or { 120, 110, 140, 180 },
            },
            UI.Label {
                text = resultDesc,
                fontSize = 8,
                fontColor = { 150, 145, 170, 160 },
            },
        }

        if discovered and buffText ~= "" then
            resultChildren[#resultChildren + 1] = UI.Label {
                text = "✨ " .. buffText,
                fontSize = 8,
                fontColor = { 180, 160, 255, 180 },
            }
        end

        row:AddChild(UI.Panel {
            flex = 1,
            flexDirection = "column",
            gap = 1,
            children = resultChildren,
        })

        crossbreedGuide_:AddChild(row)
    end
end

-- ============================================================================
-- 内部：重建土壤行
-- ============================================================================

-- 土壤描述缩写（原文太长会溢出按钮）
local SOIL_SHORT_DESC = {
    normal   = "均衡发展",
    overtime = "速长x1.5 枯萎快",
    remote   = "慢长 杂交x1.5",
}

RebuildSoilRow = function()
    if not soilRow_ or not gardenMgr_ then return end
    soilRow_:RemoveAllChildren()

    local currentSoil = gardenMgr_.GetSoilId()
    local cooldown = gardenMgr_.GetSoilCooldown()

    -- 内层行：放 3 个按钮
    local btnRow = UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 4,
    }

    for _, soil in ipairs(GC.soils) do
        local isActive = (soil.id == currentSoil)
        local canSwitch = (cooldown <= 0 and not isActive)

        local soilId = soil.id  -- 闭包捕获
        local btn = UI.Panel {
            flex = 1,
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            paddingTop = 5, paddingBottom = 5,
            paddingLeft = 2, paddingRight = 2,
            borderRadius = 6, borderWidth = 1,
            backgroundColor = isActive and { 50, 90, 50, 220 } or { 35, 32, 50, 200 },
            borderColor = isActive and { 100, 200, 100, 200 }
                or (canSwitch and { 80, 75, 100, 150 } or { 50, 45, 60, 100 }),
            opacity = canSwitch and 1.0 or (isActive and 1.0 or 0.5),
            pointerEvents = canSwitch and "auto" or "none",
            onPointerDown = function()
                if canSwitch then
                    ShowSoilConfirm(soil)
                end
            end,
            children = {
                UI.Label {
                    text = soil.name,
                    fontSize = 11,
                    fontColor = isActive and { 150, 255, 150, 255 } or { 180, 170, 200, 200 },
                    textAlign = "center",
                },
                UI.Label {
                    text = SOIL_SHORT_DESC[soil.id] or "",
                    fontSize = 8,
                    fontColor = { 140, 135, 160, 160 },
                    textAlign = "center",
                },
            },
        }
        btnRow:AddChild(btn)
    end

    soilRow_:AddChild(btnRow)

    -- 冷却提示（放在按钮行下方）
    if cooldown > 0 then
        soilRow_:AddChild(UI.Label {
            text = "冷却 " .. FormatTime(cooldown),
            fontSize = 10,
            fontColor = { 255, 180, 80, 220 },
            textAlign = "center",
        })
    end
end

-- ============================================================================
-- 内部：更新状态标签
-- ============================================================================

UpdateStatus = function()
    if not statusLabel_ or not gardenMgr_ then return end

    local parts = {}

    local bugImm = gardenMgr_.GetBugImmunityTimer()
    if bugImm > 0 then
        parts[#parts + 1] = "🛡 防罢工 " .. FormatTime(bugImm)
    end

    local growBst = gardenMgr_.GetGrowthBoostTimer()
    if growBst > 0 then
        parts[#parts + 1] = "⚡ 加速 " .. FormatTime(growBst)
    end

    statusLabel_:SetText(table.concat(parts, "  "))

    -- 图鉴
    if collectionLabel_ then
        local disc = gardenMgr_.GetDiscoveredCount()
        local total = GC.GetTotalSeedCount()
        collectionLabel_:SetText("图鉴 " .. disc .. "/" .. total)
    end
end

-- ============================================================================
-- 内部：更新扩建按钮
-- ============================================================================

UpdateExpandBtn = function()
    if not expandBtn_ or not expandLabel_ or not gardenMgr_ then return end

    local gridSize = gardenMgr_.GetGridSize()
    if gridSize >= GC.GRID_MAX_SIZE then
        expandLabel_:SetText("已满 " .. gridSize .. "×" .. gridSize)
        expandBtn_:SetStyle({
            backgroundColor = { 50, 45, 60, 150 },
            borderColor = { 60, 55, 80, 100 },
            pointerEvents = "none",
            opacity = 0.5,
        })
    else
        local cost = GC.GetExpandCost(gridSize + 1) or 0
        expandLabel_:SetText("扩建→" .. (gridSize + 1) .. "×" .. (gridSize + 1) .. "  🍬" .. cost)
        expandBtn_:SetStyle({
            backgroundColor = { 80, 60, 120, 220 },
            borderColor = { 160, 130, 220, 180 },
            pointerEvents = "auto",
            opacity = 1.0,
        })
    end
end

-- ============================================================================
-- 交互回调
-- ============================================================================

OnCellClick = function(row, col)
    if not gardenMgr_ or not manager_ then return end

    local plot = gardenMgr_.GetPlot(row, col)
    if not plot then return end

    if not plot.seedId then
        -- 空地 → 种植选中的种子
        if selectedSeed_ then
            manager_.OnGardenPlant(row, col, selectedSeed_)
        end
    elseif plot.stage == GC.STAGE_MATURE or plot.stage == GC.STAGE_WILTING then
        -- 成熟/枯萎 → 收获
        manager_.OnGardenHarvest(row, col)
    elseif plot.stage == GC.STAGE_DEAD then
        -- 死亡 → 清理
        manager_.OnGardenClear(row, col)
    end
    -- 生长中的植物不做操作
end

OnSeedSelect = function(seedId)
    if selectedSeed_ == seedId then
        selectedSeed_ = nil  -- 取消选择
    else
        selectedSeed_ = seedId
    end
    lastFingerprint_ = ""  -- 强制刷新
    GP.Refresh()
end

-- ============================================================================
-- 确认弹窗
-- ============================================================================

local SOIL_FULL_DESC = {
    normal   = "标准效率，均衡发展",
    overtime = "生长速度 ×1.5，枯萎也快 ×1.5\n杂交概率 ×0.8",
    remote   = "生长速度 ×0.7，枯萎慢 ×0.5\n杂交概率 ×1.5，收益 ×1.2",
}

ShowSoilConfirm = function(soil)
    if confirmShowing_ then return end
    if not uiRoot_ then return end

    local soilId = soil.id

    confirmOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = "100%", height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        pointerEvents = "auto",
        zIndex = 9000,
        onPointerDown = function()
            HideSoilConfirm()
        end,
        children = {
            UI.Panel {
                width = 260,
                flexDirection = "column",
                backgroundColor = { 30, 28, 48, 250 },
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 100, 80, 160, 180 },
                paddingTop = 14, paddingBottom = 14,
                paddingLeft = 16, paddingRight = 16,
                gap = 10,
                pointerEvents = "auto",
                onPointerDown = function(self, event)
                    if event and event.stopPropagation then
                        event:stopPropagation()
                    end
                end,
                children = {
                    -- 标题
                    UI.Label {
                        text = "切换团队模式",
                        fontSize = 15,
                        fontColor = { 255, 220, 80, 255 },
                        textAlign = "center",
                        width = "100%",
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 60, 55, 80, 150 },
                    },
                    -- 目标模式名
                    UI.Label {
                        text = "切换为：" .. soil.name,
                        fontSize = 13,
                        fontColor = { 180, 220, 180, 255 },
                        textAlign = "center",
                        width = "100%",
                    },
                    -- 描述
                    UI.Label {
                        text = SOIL_FULL_DESC[soilId] or soil.desc or "",
                        fontSize = 11,
                        fontColor = { 180, 175, 200, 220 },
                        textAlign = "center",
                        width = "100%",
                    },
                    -- 冷却提示
                    UI.Label {
                        text = "⚠ 切换后冷却 " .. FormatTime(GC.SOIL_COOLDOWN),
                        fontSize = 10,
                        fontColor = { 255, 180, 80, 200 },
                        textAlign = "center",
                        width = "100%",
                    },
                    -- 按钮行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 10,
                        justifyContent = "center",
                        marginTop = 4,
                        children = {
                            -- 取消
                            UI.Panel {
                                flex = 1,
                                paddingTop = 8, paddingBottom = 8,
                                borderRadius = 6,
                                backgroundColor = { 60, 55, 80, 200 },
                                borderWidth = 1,
                                borderColor = { 80, 75, 100, 150 },
                                justifyContent = "center", alignItems = "center",
                                pointerEvents = "auto",
                                onPointerDown = function()
                                    HideSoilConfirm()
                                end,
                                children = {
                                    UI.Label {
                                        text = "取消",
                                        fontSize = 12,
                                        fontColor = { 180, 175, 200, 220 },
                                        textAlign = "center",
                                    },
                                },
                            },
                            -- 确认
                            UI.Panel {
                                flex = 1,
                                paddingTop = 8, paddingBottom = 8,
                                borderRadius = 6,
                                backgroundColor = { 60, 100, 60, 220 },
                                borderWidth = 1,
                                borderColor = { 100, 200, 100, 180 },
                                justifyContent = "center", alignItems = "center",
                                pointerEvents = "auto",
                                onPointerDown = function()
                                    HideSoilConfirm()
                                    if manager_ then
                                        manager_.OnGardenSwitchSoil(soilId)
                                    end
                                end,
                                children = {
                                    UI.Label {
                                        text = "确认切换",
                                        fontSize = 12,
                                        fontColor = { 150, 255, 150, 255 },
                                        textAlign = "center",
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }

    uiRoot_:AddChild(confirmOverlay_)
    confirmShowing_ = true
end

HideSoilConfirm = function()
    if not confirmShowing_ then return end
    if confirmOverlay_ and uiRoot_ then
        uiRoot_:RemoveChild(confirmOverlay_)
    end
    confirmOverlay_ = nil
    confirmShowing_ = false
end

return GP
