-- ============================================================================
-- ui/MiningPanel.lua
-- 挖矿探险面板 —— 矿区网格、镐头耐久、道具栏
-- 右侧抽屉栏，与其他小游戏面板一致
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local MC = require("config.MiningConfig")
local AudioManager = require("core.AudioManager")
local MP = {}

-- 内部引用
local uiRoot_       = nil
local overlay_      = nil
local panel_        = nil
local visible_      = false
local miningMgr_    = nil   -- MiningManager 引用
local manager_      = nil   -- GameManager 引用

-- UI 缓存
local gridContainer_ = nil
local pickLabel_     = nil
local timerLabel_    = nil
local streakLabel_   = nil
local toolsContainer_ = nil

-- 网格 cell 缓存: cellCache_[row][col] = { panel, iconImg, hintLabel }
local cellCache_     = {}
local cachedCols_    = 0
local cachedRows_    = 0

local refreshLabel_  = nil

-- 刷新指纹
local lastFingerprint_ = ""

-- 当前选中的道具（nil = 普通挖掘模式）
local selectedTool_ = nil

-- ============================================================================
-- 颜色常量
-- ============================================================================

local C_BG      = { 28, 32, 45, 245 }
local C_TEXT    = { 220, 220, 240, 255 }
local C_DIM     = { 140, 140, 160, 200 }
local C_GOLD    = { 255, 215, 0, 255 }
local C_GREEN   = { 80, 220, 120, 255 }
local C_RED     = { 220, 80, 80, 255 }

-- 矿石颜色映射
local ORE_COLORS = {
    empty    = { 60, 60, 70, 255 },
    copper   = { 180, 120, 60, 255 },
    iron     = { 180, 190, 200, 255 },
    gold     = { 255, 215, 0, 255 },
    gem      = { 100, 200, 255, 255 },
    fossil   = { 200, 180, 140, 255 },
    collapse = { 200, 60, 60, 255 },
}

-- 提示数字颜色
local HINT_COLORS = {
    [0] = { 80, 80, 90, 180 },
    [1] = { 120, 160, 200, 255 },
    [2] = { 220, 200, 60, 255 },
    [3] = { 255, 100, 100, 255 },
}

-- ============================================================================
-- 前向声明
-- ============================================================================
local BuildPanel
local RebuildGrid
local UpdateGrid
local RebuildTools

-- ============================================================================
-- 工具
-- ============================================================================

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

local function FormatCoins(v)
    return GameState.FormatNumber(v)
end

-- ============================================================================
-- 初始化
-- ============================================================================

function MP.Init(root, gm)
    uiRoot_ = root
    manager_ = gm
    miningMgr_ = require("core.MiningManager")

    -- 挖矿事件音效回调
    miningMgr_.SetOnDig(function(row, col, oreDef, coins, isStreakBonus)
        -- 根据矿石类型播放对应音效
        local sfxKey = "mining_ore_" .. (oreDef.id or "copper")
        AudioManager.PlaySFX(sfxKey)
        -- 连击触发额外音效
        if isStreakBonus then
            AudioManager.PlaySFX("mining_streak")
        end
    end)
    miningMgr_.SetOnCollapse(function(row, col, lostCoins)
        AudioManager.PlaySFX("mining_collapse")
    end)
    miningMgr_.SetOnFullClear(function(bonusCoins)
        AudioManager.PlaySFX("mining_full_clear")
    end)
    miningMgr_.SetOnRefresh(function()
        AudioManager.PlaySFX("mining_refresh")
    end)

    BuildPanel()
end

-- ============================================================================
-- 显示 / 隐藏
-- ============================================================================

function MP.Show()
    if not overlay_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    lastFingerprint_ = ""
    selectedTool_ = nil
    uiRoot_:AddChild(overlay_)
    MP.Refresh()
end

function MP.Hide()
    if not overlay_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(overlay_)
end

function MP.Toggle()
    if visible_ then MP.Hide() else MP.Show() end
end

function MP.IsVisible()
    return visible_
end

--- 强制重建网格（外部调用，如调试面板重置矿场后）
function MP.ForceRebuild()
    cachedCols_ = 0
    cachedRows_ = 0
    lastFingerprint_ = ""
    if visible_ then
        MP.Refresh()
    end
end

-- ============================================================================
-- 刷新
-- ============================================================================

function MP.Refresh()
    if not visible_ or not miningMgr_ then return end

    -- 构建指纹
    local fpParts = {}
    fpParts[#fpParts + 1] = "p" .. math.floor(miningMgr_.GetPicks())
    fpParts[#fpParts + 1] = "t" .. math.floor(miningMgr_.GetRefreshTimer())
    fpParts[#fpParts + 1] = "s" .. miningMgr_.GetStreak()
    fpParts[#fpParts + 1] = "r" .. miningMgr_.GetTotalRevealed()
    fpParts[#fpParts + 1] = "g" .. miningMgr_.GetCols() .. "x" .. miningMgr_.GetRows()
    fpParts[#fpParts + 1] = "tl" .. (selectedTool_ or "none")

    local fp = table.concat(fpParts, "|")
    if fp == lastFingerprint_ then return end
    lastFingerprint_ = fp

    -- 更新顶部信息
    if pickLabel_ then
        local picks = miningMgr_.GetPicks()
        local maxPicks = miningMgr_.GetMaxPicks()
        pickLabel_:SetStyle({ text = picks .. " / " .. maxPicks })
    end
    if timerLabel_ then
        timerLabel_:SetStyle({ text = FormatTime(miningMgr_.GetRefreshTimer()) })
    end
    if streakLabel_ then
        local streak = miningMgr_.GetStreak()
        if streak >= MC.STREAK_THRESHOLD then
            streakLabel_:SetStyle({
                text = "连击 x" .. MC.STREAK_MULTIPLIER,
                fontColor = C_GOLD,
            })
        elseif streak > 0 then
            streakLabel_:SetStyle({
                text = "连续 " .. streak,
                fontColor = C_DIM,
            })
        else
            streakLabel_:SetStyle({ text = "", fontColor = C_DIM })
        end
    end

    -- 更新刷新按钮花费
    if refreshLabel_ then
        local cost = GameState.coinsPerSecond * MC.MANUAL_REFRESH_CPS_MUL
        refreshLabel_:SetStyle({
            text = "刷新矿区 -" .. FormatCoins(cost),
        })
    end

    -- 更新网格
    local cols = miningMgr_.GetCols()
    local rows = miningMgr_.GetRows()
    if cols ~= cachedCols_ or rows ~= cachedRows_ then
        RebuildGrid()
    else
        UpdateGrid()
    end

    -- 更新道具栏
    RebuildTools()
end

-- ============================================================================
-- 网格构建与更新
-- ============================================================================

RebuildGrid = function()
    if not gridContainer_ or not miningMgr_ then return end
    gridContainer_:RemoveAllChildren()
    cellCache_ = {}

    local cols = miningMgr_.GetCols()
    local rows = miningMgr_.GetRows()
    cachedCols_ = cols
    cachedRows_ = rows

    -- 计算格子大小
    local dpr = graphics:GetDPR()
    local logicalW = graphics:GetWidth() / dpr
    local drawerW = math.floor(logicalW * 0.3) - 20 -- 面板宽度减去 padding
    local cellSize = math.floor(math.min(drawerW / cols, 48))
    cellSize = math.max(24, math.min(cellSize, 44))

    for r = 1, rows do
        cellCache_[r] = {}
        local rowPanel = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            gap = 2,
        }

        for c = 1, cols do
            local cell = miningMgr_.GetCell(r, c)
            local bgColor = { 55, 50, 65, 255 }
            local oreImage = nil
            local hintText = ""

            local hasHint = (not cell.revealed and cell.hint ~= nil)
            if cell.revealed then
                local oreDef = MC.oreMap[cell.oreId]
                oreImage = oreDef and oreDef.iconImage or nil
                bgColor = ORE_COLORS[cell.oreId] or { 60, 60, 70, 255 }
                bgColor = { math.floor(bgColor[1] * 0.4), math.floor(bgColor[2] * 0.4),
                    math.floor(bgColor[3] * 0.4), 255 }
            elseif hasHint then
                hintText = tostring(cell.hint)
                bgColor = { 50, 48, 68, 255 }
            end

            local imgSize = math.floor(cellSize * 0.7)
            local imgOffset = math.floor((cellSize - imgSize) / 2)
            local iconImg = UI.Panel {
                position = "absolute",
                left = imgOffset, top = imgOffset,
                width = imgSize, height = imgSize,
                backgroundImage = oreImage or "",
                backgroundFit = "contain",
                display = oreImage and "flex" or "none",
            }

            local hintFontSize = math.max(14, math.floor(cellSize * 0.5))
            local hintLabel = UI.Label {
                position = "absolute",
                left = 0, top = 0,
                width = cellSize, height = cellSize,
                text = hintText,
                fontSize = hintFontSize,
                fontWeight = "bold",
                fontColor = HINT_COLORS[cell.hint] or { 200, 200, 200, 255 },
                textAlign = "center",
                verticalAlign = "middle",
                display = hasHint and "flex" or "none",
            }

            local cellBg = cell.revealed and bgColor
                or (hasHint and bgColor or { 70, 65, 85, 255 })
            local cellBorder = cell.revealed
                and { 40, 40, 50, 100 }
                or (hasHint and { 100, 90, 140, 200 }
                    or (selectedTool_ and { 120, 100, 200, 200 } or { 90, 85, 110, 150 }))

            local cellPanel = UI.Panel {
                width = cellSize, height = cellSize,
                borderRadius = 4,
                backgroundColor = cellBg,
                borderWidth = 1,
                borderColor = cellBorder,
                overflow = "hidden",
                pointerEvents = "auto",
                onTap = function(self, event)
                    if event and event.stopPropagation then event:stopPropagation() end
                    MP.OnCellTap(r, c)
                end,
                children = { iconImg, hintLabel },
            }

            rowPanel:AddChild(cellPanel)
            cellCache_[r][c] = { panel = cellPanel, iconImg = iconImg, hintLabel = hintLabel }
        end

        gridContainer_:AddChild(rowPanel)
    end
end

UpdateGrid = function()
    if not miningMgr_ then return end

    local cols = miningMgr_.GetCols()
    local rows = miningMgr_.GetRows()

    for r = 1, rows do
        for c = 1, cols do
            local cache = cellCache_[r] and cellCache_[r][c]
            if cache then
                local cell = miningMgr_.GetCell(r, c)
                if cell.revealed then
                    local oreDef = MC.oreMap[cell.oreId]
                    local oreColor = ORE_COLORS[cell.oreId] or { 60, 60, 70, 255 }
                    local darkBg = {
                        math.floor(oreColor[1] * 0.4),
                        math.floor(oreColor[2] * 0.4),
                        math.floor(oreColor[3] * 0.4), 255
                    }
                    cache.panel:SetStyle({
                        backgroundColor = darkBg,
                        borderColor = { 40, 40, 50, 100 },
                    })
                    local oreImage = oreDef and oreDef.iconImage or nil
                    cache.iconImg:SetStyle({
                        backgroundImage = oreImage or "",
                        display = oreImage and "flex" or "none",
                    })
                    cache.hintLabel:SetStyle({ text = "", display = "none" })
                elseif cell.hint ~= nil then
                    cache.panel:SetStyle({
                        backgroundColor = { 50, 48, 68, 255 },
                        borderColor = { 100, 90, 140, 200 },
                    })
                    cache.iconImg:SetStyle({ backgroundImage = "", display = "none" })
                    cache.hintLabel:SetStyle({
                        text = tostring(cell.hint),
                        fontColor = HINT_COLORS[cell.hint] or { 200, 200, 200, 255 },
                        display = "flex",
                    })
                else
                    cache.panel:SetStyle({
                        backgroundColor = { 70, 65, 85, 255 },
                        borderColor = selectedTool_
                            and { 120, 100, 200, 200 }
                            or { 90, 85, 110, 150 },
                    })
                    cache.iconImg:SetStyle({ backgroundImage = "", display = "none" })
                    cache.hintLabel:SetStyle({ text = "", display = "none" })
                end
            end
        end
    end
end

-- ============================================================================
-- 道具栏
-- ============================================================================

RebuildTools = function()
    if not toolsContainer_ or not miningMgr_ then return end
    toolsContainer_:RemoveAllChildren()

    local tools = miningMgr_.GetUnlockedTools()
    if #tools == 0 then return end

    for _, toolDef in ipairs(tools) do
        local isSelected = (selectedTool_ == toolDef.id)
        local canUse = miningMgr_.GetPicks() >= toolDef.pickCost

        if toolDef.passive then
            -- 矿车：开关按钮
            local isActive = miningMgr_.HasMinecart()
            toolsContainer_:AddChild(UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                paddingLeft = 6, paddingRight = 6, paddingTop = 4, paddingBottom = 4,
                borderRadius = 4,
                backgroundColor = isActive and { 40, 60, 40, 255 } or { 45, 45, 55, 255 },
                borderWidth = 1,
                borderColor = isActive and { 80, 160, 80, 180 } or { 60, 60, 70, 100 },
                pointerEvents = "auto",
                onTap = function(self, event)
                    if event and event.stopPropagation then event:stopPropagation() end
                    miningMgr_.ToggleMinecart()
                    AudioManager.PlaySFX("mining_tool_select")
                    lastFingerprint_ = ""
                    MP.Refresh()
                end,
                children = {
                    UI.Panel {
                        width = 18, height = 18,
                        backgroundImage = toolDef.iconImage or "",
                        backgroundFit = "contain",
                    },
                    UI.Label { text = toolDef.name, fontSize = 10,
                        fontColor = isActive and C_GREEN or C_DIM },
                    UI.Label { text = isActive and "ON" or "OFF", fontSize = 9,
                        fontColor = isActive and C_GREEN or C_DIM },
                },
            })
        else
            -- 主动道具：选中切换
            toolsContainer_:AddChild(UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                paddingLeft = 6, paddingRight = 6, paddingTop = 4, paddingBottom = 4,
                borderRadius = 4,
                backgroundColor = isSelected and { 50, 40, 70, 255 } or { 45, 45, 55, 255 },
                borderWidth = 1,
                borderColor = isSelected and { 140, 100, 220, 220 }
                    or (canUse and { 80, 80, 100, 150 } or { 50, 50, 60, 100 }),
                pointerEvents = "auto",
                onTap = function(self, event)
                    if event and event.stopPropagation then event:stopPropagation() end
                    if selectedTool_ == toolDef.id then
                        selectedTool_ = nil
                    else
                        selectedTool_ = toolDef.id
                    end
                    AudioManager.PlaySFX("mining_tool_select")
                    lastFingerprint_ = ""
                    MP.Refresh()
                end,
                children = {
                    UI.Panel {
                        width = 18, height = 18,
                        backgroundImage = toolDef.iconImage or "",
                        backgroundFit = "contain",
                    },
                    UI.Label { text = toolDef.name, fontSize = 10,
                        fontColor = canUse and C_TEXT or C_DIM },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 1,
                        children = {
                            UI.Panel {
                                width = 10, height = 10,
                                backgroundImage = "image/UI_镐头_20260504021456.png",
                                backgroundFit = "contain",
                            },
                            UI.Label { text = tostring(toolDef.pickCost), fontSize = 9,
                                fontColor = canUse and C_DIM or C_RED },
                        },
                    },
                },
            })
        end
    end
end

-- ============================================================================
-- 交互
-- ============================================================================

function MP.OnCellTap(row, col)
    if not miningMgr_ then return end

    local ok = false
    local forceRebuild = false
    if selectedTool_ == "scanner" then
        ok = miningMgr_.UseScanner(row, col)
        if ok then
            AudioManager.PlaySFX("mining_scanner")
            selectedTool_ = nil
        end
    elseif selectedTool_ == "dynamite" then
        ok = miningMgr_.UseDynamite(row, col)
        if ok then
            AudioManager.PlaySFX("mining_dynamite")
            selectedTool_ = nil
            forceRebuild = true  -- 炸药改变多个格子，强制重建
        end
    else
        -- 普通挖掘：先记录格子状态，挖完后判断是否空岩
        local cell = miningMgr_.GetCell(row, col)
        local wasRevealed = cell and cell.revealed
        ok = miningMgr_.Dig(row, col)
        if ok and not wasRevealed and cell then
            if cell.oreId == "empty" then
                AudioManager.PlaySFX("mining_empty")
            end
            -- 非 empty 的音效由 onDig_/onCollapse_ 回调处理
        end
    end

    if ok then
        lastFingerprint_ = ""
        if forceRebuild then
            cachedCols_ = 0  -- 强制 RebuildGrid
        end
        MP.Refresh()
    end
end

-- ============================================================================
-- 构建面板骨架
-- ============================================================================

BuildPanel = function()
    pickLabel_ = UI.Label {
        text = "10 / 10",
        fontSize = 12,
        fontColor = C_TEXT,
    }

    timerLabel_ = UI.Label {
        text = "5:00",
        fontSize = 11,
        fontColor = C_DIM,
    }

    streakLabel_ = UI.Label {
        text = "",
        fontSize = 11,
        fontColor = C_DIM,
    }

    gridContainer_ = UI.Panel {
        width = "100%",
        alignItems = "center",
        gap = 2,
    }

    toolsContainer_ = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 4,
    }

    -- 手动刷新按钮
    refreshLabel_ = UI.Label { text = "刷新矿区", fontSize = 10, fontColor = C_GOLD }
    local refreshBtn = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 4,
        paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
        borderRadius = 4,
        backgroundColor = { 50, 45, 35, 255 },
        borderWidth = 1,
        borderColor = { 160, 140, 80, 180 },
        pointerEvents = "auto",
        onTap = function(self, event)
            if event and event.stopPropagation then event:stopPropagation() end
            if miningMgr_ then
                local ok = miningMgr_.ManualRefresh()
                if ok then
                    lastFingerprint_ = ""
                    cachedCols_ = 0  -- 强制重建网格
                    MP.Refresh()
                end
            end
        end,
        children = { refreshLabel_ },
    }

    panel_ = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        paddingTop = 10, paddingLeft = 6, paddingRight = 6,
        paddingBottom = 6,
        pointerEvents = "auto",
        children = {
            -- 标题行
            UI.Panel {
                width = "100%",
                flexDirection = "row", alignItems = "center",
                justifyContent = "space-between",
                marginBottom = 6,
                paddingLeft = 6, paddingRight = 4,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Panel {
                                width = 22, height = 22,
                                backgroundImage = "image/UI_镐头_20260504021456.png",
                                backgroundFit = "contain",
                            },
                            UI.Label {
                                text = "挖矿探险",
                                fontSize = 17,
                                fontColor = { 200, 160, 100, 255 },
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 8,
                        children = {
                            timerLabel_,
                            UI.Panel {
                                paddingLeft = 8, paddingRight = 8,
                                paddingTop = 4, paddingBottom = 4,
                                borderRadius = 4,
                                backgroundColor = { 60, 40, 40, 255 },
                                pointerEvents = "auto",
                                onTap = function() MP.Hide() end,
                                children = {
                                    UI.Label { text = "✕", fontSize = 14, fontColor = C_TEXT },
                                },
                            },
                        },
                    },
                },
            },
            -- 状态栏
            UI.Panel {
                width = "100%",
                flexDirection = "row", alignItems = "center",
                justifyContent = "space-between",
                paddingLeft = 6, paddingRight = 6,
                marginBottom = 6,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Panel {
                                width = 14, height = 14,
                                backgroundImage = "image/UI_镐头_20260504021456.png",
                                backgroundFit = "contain",
                            },
                            pickLabel_,
                        },
                    },
                    streakLabel_,
                },
            },
            -- 网格区域（可滚动）
            UI.Panel {
                width = "100%", flex = 1, flexShrink = 1,
                overflow = "scroll",
                paddingLeft = 2, paddingRight = 2,
                paddingBottom = 8,
                children = {
                    gridContainer_,
                    -- 道具栏
                    UI.Panel {
                        width = "100%", marginTop = 8, gap = 6,
                        children = {
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row", alignItems = "center",
                                justifyContent = "space-between",
                                children = {
                                    UI.Panel {
                                        flexDirection = "row", alignItems = "center", gap = 4,
                                        children = {
                                            UI.Panel {
                                                width = 16, height = 16,
                                                backgroundImage = "image/UI_道具箱_20260504021454.png",
                                                backgroundFit = "contain",
                                            },
                                            UI.Label { text = "道具", fontSize = 12, fontColor = C_GOLD },
                                        },
                                    },
                                    refreshBtn,
                                },
                            },
                            toolsContainer_,
                            -- 道具说明
                            UI.Panel {
                                width = "100%", marginTop = 2, gap = 2,
                                children = {
                                    UI.Label { text = "探测仪: 点击格子显示一个数字，代表周围8格中最高矿石等级 (0=无矿 1=铜/铁 2=金/化石 3=宝石)",
                                        fontSize = 9, fontColor = C_DIM },
                                    UI.Label { text = "炸药: 点击格子，炸开十字形5格并收获其中矿石",
                                        fontSize = 9, fontColor = C_DIM },
                                    UI.Label { text = "矿车: 开启后每次刷新矿区自动挖开2格(消耗耐久)",
                                        fontSize = 9, fontColor = C_DIM },
                                },
                            },
                            -- 矿石说明
                            UI.Panel {
                                width = "100%", marginTop = 6, gap = 4,
                                children = (function()
                                    local items = {}
                                    -- 标题
                                    items[#items + 1] = UI.Label {
                                        text = "矿石说明", fontSize = 11,
                                        fontColor = C_GOLD, marginBottom = 2,
                                    }
                                    -- 每种矿石一行
                                    local oreDescs = {
                                        { id = "copper",   desc = "挖到获得 10秒 CPS 金币" },
                                        { id = "iron",     desc = "挖到获得 45秒 CPS 金币" },
                                        { id = "gold",     desc = "挖到获得 3分钟 CPS 金币" },
                                        { id = "fossil",   desc = "获得 1.5分钟 CPS 金币 + 产出+5% 2分钟" },
                                        { id = "gem",      desc = "获得 10分钟 CPS 金币 + 产出+10% 1分钟" },
                                        { id = "collapse", desc = "塌方！损失 2分钟 CPS 金币" },
                                    }
                                    for _, info in ipairs(oreDescs) do
                                        local oreDef = MC.oreMap[info.id]
                                        if oreDef then
                                            local nameColor = ORE_COLORS[info.id] or C_TEXT
                                            local row = UI.Panel {
                                                width = "100%",
                                                flexDirection = "row", alignItems = "center",
                                                gap = 4,
                                                children = {
                                                    -- 矿石小图标
                                                    UI.Panel {
                                                        width = 16, height = 16,
                                                        backgroundImage = oreDef.iconImage or "",
                                                        backgroundFit = "contain",
                                                    },
                                                    -- 矿石名称
                                                    UI.Label {
                                                        text = oreDef.name,
                                                        fontSize = 10, fontColor = nameColor,
                                                        width = 28,
                                                    },
                                                    -- 说明
                                                    UI.Label {
                                                        text = info.desc,
                                                        fontSize = 9, fontColor = C_DIM,
                                                        flex = 1, flexShrink = 1,
                                                    },
                                                },
                                            }
                                            items[#items + 1] = row
                                        end
                                    end
                                    -- 分隔
                                    items[#items + 1] = UI.Panel {
                                        width = "100%", height = 1,
                                        backgroundColor = { 80, 75, 100, 80 },
                                        marginTop = 2, marginBottom = 2,
                                    }
                                    -- 规则提示
                                    items[#items + 1] = UI.Label {
                                        text = "连续挖到3个矿石触发连击，后续奖励×2",
                                        fontSize = 9, fontColor = C_DIM,
                                    }
                                    items[#items + 1] = UI.Label {
                                        text = "全部挖完额外奖励 10分钟 CPS 金币",
                                        fontSize = 9, fontColor = C_DIM,
                                    }
                                    return items
                                end)(),
                            },
                        },
                    },
                },
            },
        },
    }

    -- 创建右侧抽屉容器
    local dpr = graphics:GetDPR()
    local logicalW = graphics:GetWidth() / dpr
    local drawerW = math.floor(logicalW * 0.3)

    overlay_ = UI.Panel {
        position = "absolute",
        top = 0,
        right = "30%",
        width = drawerW,
        height = "100%",
        zIndex = 100,
        backgroundColor = C_BG,
        borderColor = { 120, 100, 60, 120 },
        borderWidth = { 0, 1, 0, 1 },
        pointerEvents = "auto",
        children = { panel_ },
    }
end

return MP
