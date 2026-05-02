-- ============================================================================
-- ui/SeasonPanel.lua
-- 市场周期面板（全屏覆盖式弹窗）
-- 周期切换 + 收集品展示 + 市场信心升级
-- 使用 AddChild/RemoveChild 控制显隐
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local SD = require("config.SeasonDefs")

local SP = {}

-- ======== 引用 ========
local uiRoot_ = nil
local panel_ = nil
local visible_ = false
local contentContainer_ = nil
local seasonInfoLabel_ = nil

-- 外部注入
local seasonManager_ = nil
local onSwitchSeason_ = nil    -- function(seasonId)
local onUpgradeSanta_ = nil    -- function()

-- ======== 增量刷新缓存 ========
local lastSnapshot_ = ""       -- 结构快照（活跃季节+圣诞等级+收集状态）
local lastInfoText_ = ""
-- 季节按钮缓存
local seasonBtnCache_ = {}     -- seasonBtnCache_[seasonId] = { btn, statusLabel }
-- 圣诞升级缓存
local santaCache_ = nil        -- { panel, nameLabel, costLabel, lastFP }
local xmasUpgradeCache_ = {}   -- xmasUpgradeCache_[i] = { row, statusLabel, lastUnlocked }

local initialized_ = false

-- 辅助：取名称首个 UTF-8 字符（用于缩略图标显示）
local function FirstChar(name)
    if not name or #name == 0 then return "?" end
    local b = name:byte(1)
    if b >= 0xF0 then return name:sub(1, 4)     -- 4字节 UTF-8
    elseif b >= 0xE0 then return name:sub(1, 3)  -- 3字节（中文）
    elseif b >= 0xC0 then return name:sub(1, 2)  -- 2字节
    else return name:sub(1, 1) end               -- ASCII
end

--- 辅助：收集品图标（有 icon 字段用图片，否则用首字）
local function ItemIcon(item, got, size)
    size = size or 22
    if got and item.icon then
        return UI.Panel { width = size, height = size,
            backgroundImage = item.icon, backgroundFit = "contain" }
    end
    return UI.Label { text = got and FirstChar(item.name) or "?",
        fontSize = size - 9, width = size, textAlign = "center" }
end

-- ============================================================================
-- 快照生成（用于结构变化检测）
-- ============================================================================

local function MakeSnapshot()
    local parts = {}
    local active = seasonManager_.GetActiveSeason()
    parts[#parts + 1] = "S:" .. (active or "none")

    if active == SD.SEASON_CHRISTMAS then
        parts[#parts + 1] = "SL:" .. seasonManager_.GetSantaLevel()
        local xmasStatus = seasonManager_.GetXmasUpgradeStatus()
        parts[#parts + 1] = "XC:" .. #xmasStatus
    end

    -- 金币影响 santa affordability
    local santaLevel = seasonManager_.GetSantaLevel()
    local isMaxed = santaLevel >= SD.SANTA_MAX_LEVEL
    if not isMaxed and active == SD.SEASON_CHRISTMAS then
        local cost = SD.GetSantaUpgradeCost(santaLevel)
        parts[#parts + 1] = "CA:" .. (GameState.coins >= cost and "Y" or "N")
    end

    -- 手动计时器（取整数秒）
    local manualTimer = seasonManager_.GetManualTimer()
    if manualTimer > 0 then
        local t = math.floor(manualTimer)
        local h = math.floor(t / 3600)
        local m = math.floor((t % 3600) / 60)
        local s = t % 60
        parts[#parts + 1] = string.format("%02d:%02d:%02d", h, m, s)
    end

    -- 切换器解锁状态 + 切换价格可负担性
    local hasSwitcher = seasonManager_.HasSeasonSwitcher()
    parts[#parts + 1] = "SW:" .. (hasSwitcher and "Y" or "N")
    if hasSwitcher then
        local switchCost = seasonManager_.GetSwitchCost(GameState.coinsPerSecond)
        parts[#parts + 1] = "SC:" .. (GameState.coins >= switchCost and "Y" or "N")
    end

    return table.concat(parts, "|")
end

-- ============================================================================
-- 内部：构建面板
-- ============================================================================

local function BuildPanel()
    seasonInfoLabel_ = UI.Label {
        text = "",
        fontSize = 13,
        fontColor = { 200, 190, 230, 220 },
        textAlign = "center",
        whiteSpace = "normal",
        marginBottom = 8,
    }

    contentContainer_ = UI.Panel {
        width = "100%",
        gap = 6,
        paddingBottom = 20,
    }

    panel_ = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        alignItems = "center",
        paddingTop = 12, paddingLeft = 8, paddingRight = 8,
        pointerEvents = "auto",
        children = {
            -- 标题
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                marginBottom = 4,
                children = {
                    UI.Panel { width = 22, height = 22,
                        backgroundImage = "image/侧栏_周期_20260414105505.png",
                        backgroundFit = "contain" },
                    UI.Label {
                        text = "市场周期",
                        fontSize = 18,
                        fontColor = { 220, 210, 240, 255 },
                    },
                },
            },

            -- 季节信息
            seasonInfoLabel_,

            -- 可滚动内容区
            UI.ScrollView {
                flex = 1,
                width = "100%",
                showScrollbar = false,
                children = {
                    contentContainer_,
                },
            },
        },
    }
end

-- ============================================================================
-- 全量构建内容（结构变化时调用）
-- ============================================================================

local function RebuildContent()
    if not contentContainer_ then return end
    contentContainer_:RemoveAllChildren()
    seasonBtnCache_ = {}
    santaCache_ = nil
    xmasUpgradeCache_ = {}

    local F = GameState.FormatNumber
    local active = seasonManager_.GetActiveSeason()

    -- ===== 季节切换按钮 =====
    local hasSwitcher = seasonManager_.HasSeasonSwitcher()

    contentContainer_:AddChild(UI.Label {
        text = "切换周期",
        fontSize = 12,
        fontColor = { 170, 160, 200, 200 },
        marginBottom = 4,
    })

    -- 未解锁周期切换器时显示提示
    if not hasSwitcher then
        contentContainer_:AddChild(UI.Panel {
            width = "100%", padding = 8, borderRadius = 6, borderWidth = 1,
            backgroundColor = { 40, 30, 30, 200 },
            borderColor = { 100, 60, 60, 150 },
            marginBottom = 4,
            children = {
                UI.Label { text = "需要经验商店「周期切换器」升级", fontSize = 11,
                    fontColor = { 200, 150, 100, 200 } },
            },
        })
    end

    for _, s in ipairs(SD.seasons) do
        local isActive = active == s.id
        local sid = s.id
        local canSwitch = hasSwitcher and not isActive

        -- 计算切换价格
        local switchCost = canSwitch and seasonManager_.GetSwitchCost(GameState.coinsPerSecond) or 0
        local canAfford = canSwitch and GameState.coins >= switchCost

        -- 右侧状态区域
        local rightWidget
        if isActive then
            rightWidget = UI.Panel {
                paddingLeft = 12, paddingRight = 12, paddingTop = 5, paddingBottom = 5,
                borderRadius = 5, borderWidth = 1,
                backgroundColor = { 35, 60, 40, 255 },
                borderColor = { 80, 170, 80, 200 },
                alignItems = "center",
                children = {
                    UI.Label { text = "激活中", fontSize = 11,
                        fontColor = { 100, 220, 100, 255 } },
                },
            }
        elseif not hasSwitcher then
            rightWidget = UI.Label { text = "未解锁", fontSize = 11,
                fontColor = { 100, 80, 80, 150 } }
        else
            -- 切换按钮样式：包含文字 + 金币图标 + 价格
            rightWidget = UI.Panel {
                flexDirection = "column", alignItems = "center", gap = 2,
                paddingLeft = 10, paddingRight = 10, paddingTop = 5, paddingBottom = 5,
                borderRadius = 5, borderWidth = 1,
                backgroundColor = canAfford and { 50, 70, 100, 255 } or { 40, 35, 50, 200 },
                borderColor = canAfford and { 80, 130, 200, 200 } or { 60, 50, 70, 120 },
                children = {
                    UI.Label { text = "切换", fontSize = 11,
                        fontColor = canAfford and { 200, 220, 255, 255 } or { 120, 110, 130, 160 } },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 3,
                        children = {
                            UI.Panel { width = 11, height = 11,
                                backgroundImage = "image/金币.png", backgroundFit = "contain" },
                            UI.Label { text = F(switchCost), fontSize = 9,
                                fontColor = canAfford and { 150, 200, 100, 220 } or { 200, 100, 100, 160 } },
                        },
                    },
                },
            }
        end

        local btn = UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            padding = 8, gap = 8, borderRadius = 6, borderWidth = 1,
            backgroundColor = isActive and { 30, 45, 55, 255 }
                or (not hasSwitcher and { 25, 22, 30, 180 } or { 30, 28, 40, 220 }),
            borderColor = isActive and { 100, 180, 255, 200 }
                or (not hasSwitcher and { 40, 35, 50, 80 } or { 50, 45, 65, 100 }),
            opacity = (isActive or hasSwitcher) and 1.0 or 0.5,
            pointerEvents = canAfford and "auto" or "none",
            onPointerDown = canAfford and function()
                if onSwitchSeason_ then
                    onSwitchSeason_(sid)
                    initialized_ = false
                    SP.Refresh()
                end
            end or nil,
            children = {
                UI.Panel { width = 30, height = 30, backgroundImage = s.iconImage, backgroundFit = "contain" },
                UI.Panel { flex = 1, flexShrink = 1, gap = 1, children = {
                    UI.Label { text = s.name, fontSize = 13,
                        fontColor = isActive and { 100, 200, 255, 255 }
                            or (hasSwitcher and { 200, 195, 215, 230 } or { 120, 115, 135, 150 }) },
                    UI.Label { text = string.format("%d/%d - %d/%d", s.startMonth, s.startDay, s.endMonth, s.endDay),
                        fontSize = 9, fontColor = { 120, 115, 140, 140 } },
                }},
                rightWidget,
            },
        }
        contentContainer_:AddChild(btn)
        seasonBtnCache_[s.id] = { btn = btn }
    end

    -- ===== 当前周期效果展示 =====
    local seasonDef = SD.FindSeason(active)
    if seasonDef then
        contentContainer_:AddChild(UI.Panel {
            width = "100%", height = 1,
            backgroundColor = { 80, 70, 110, 80 },
            marginTop = 10, marginBottom = 6,
        })

        contentContainer_:AddChild(UI.Label {
            text = seasonDef.name .. " - 周期效果",
            fontSize = 12,
            fontColor = { 170, 160, 200, 200 },
            marginBottom = 4,
        })

        -- 周期描述
        if seasonDef.desc then
            contentContainer_:AddChild(UI.Label {
                text = seasonDef.desc,
                fontSize = 10,
                fontColor = { 160, 155, 180, 180 },
                marginBottom = 6,
            })
        end
    end

    -- ===== 牛市：市场信心 + 升级列表 =====
    if active == SD.SEASON_CHRISTMAS then
        local santaLevel = seasonManager_.GetSantaLevel()
        local santaName = seasonManager_.GetSantaName()
        local isMaxed = santaLevel >= SD.SANTA_MAX_LEVEL
        local cost = isMaxed and 0 or SD.GetSantaUpgradeCost(santaLevel)
        local canAfford = not isMaxed and GameState.coins >= cost

        local santaNameLabel = UI.Label { text = "Lv." .. santaLevel .. " " .. santaName,
            fontSize = 14,
            fontColor = isMaxed and { 100, 220, 100, 255 }
                or { 230, 200, 180, 255 } }

        local santaCostLabel
        if isMaxed then
            santaCostLabel = UI.Label { text = "最高等级！", fontSize = 11, fontColor = { 160, 140, 140, 200 } }
        else
            santaCostLabel = UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                paddingLeft = 10, paddingRight = 10, paddingTop = 4, paddingBottom = 4,
                borderRadius = 5, borderWidth = 1,
                backgroundColor = canAfford and { 60, 140, 60, 255 } or { 40, 35, 50, 200 },
                borderColor = canAfford and { 100, 200, 100, 200 } or { 60, 50, 70, 120 },
                children = {
                    UI.Panel { width = 13, height = 13,
                        backgroundImage = "image/金币.png", backgroundFit = "contain" },
                    UI.Label { text = F(cost), fontSize = 11,
                        fontColor = canAfford and { 255, 255, 255, 255 } or { 150, 150, 170, 180 } },
                },
            }
        end

        local santaPanel = UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            padding = 10, gap = 8, borderRadius = 8, borderWidth = 1,
            backgroundColor = isMaxed and { 40, 55, 35, 255 }
                or (canAfford and { 55, 35, 35, 255 } or { 35, 28, 35, 220 }),
            borderColor = isMaxed and { 100, 200, 80, 200 }
                or (canAfford and { 255, 150, 100, 200 } or { 70, 50, 70, 120 }),
            pointerEvents = canAfford and "auto" or "none",
            onPointerDown = canAfford and function()
                if onUpgradeSanta_ then
                    onUpgradeSanta_()
                    initialized_ = false
                    SP.Refresh()
                end
            end or nil,
            children = {
                UI.Panel { width = 36, height = 36,
                    backgroundImage = "image/icon_market_research.png", backgroundFit = "contain" },
                UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                    santaNameLabel,
                    santaCostLabel,
                }},
            },
        }
        contentContainer_:AddChild(santaPanel)

        santaCache_ = {
            panel = santaPanel,
            nameLabel = santaNameLabel,
            costLabel = santaCostLabel,
            lastFP = santaLevel .. ":" .. (canAfford and "Y" or "N"),
        }

        -- 牛市升级列表
        local xmasStatus = seasonManager_.GetXmasUpgradeStatus()
        for xi, s in ipairs(xmasStatus) do
            local statusLabel = UI.Label { text = s.unlocked and "✓" or "-", fontSize = 11,
                width = 20, textAlign = "center",
                fontColor = s.unlocked and { 100, 200, 100, 200 }
                    or { 80, 75, 90, 120 } }

            local row = UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                padding = 6, gap = 6, borderRadius = 4, borderWidth = 1,
                backgroundColor = s.unlocked and { 30, 45, 30, 255 } or { 25, 22, 30, 180 },
                borderColor = s.unlocked and { 80, 160, 80, 120 } or { 40, 35, 50, 60 },
                opacity = s.unlocked and 1.0 or 0.35,
                children = {
                    s.def.icon
                        and UI.Panel { width = 24, height = 24,
                            backgroundImage = s.def.icon, backgroundFit = "contain" }
                        or UI.Label { text = FirstChar(s.def.name), fontSize = 14,
                            width = 24, textAlign = "center" },
                    UI.Panel { flex = 1, flexShrink = 1, gap = 1, children = {
                        UI.Label { text = s.def.name, fontSize = 11,
                            fontColor = s.unlocked and { 150, 220, 150, 255 }
                                or { 100, 95, 115, 160 } },
                        UI.Label { text = s.def.desc, fontSize = 9,
                            fontColor = { 130, 125, 145, 160 } },
                    }},
                    statusLabel,
                },
            }
            contentContainer_:AddChild(row)
            xmasUpgradeCache_[xi] = {
                row = row,
                statusLabel = statusLabel,
                lastUnlocked = s.unlocked,
            }
        end

        -- 牛市分红收集进度（逐条列表）
        local colC, totC = seasonManager_.GetCollectionProgress(SD.christmasCookies)
        contentContainer_:AddChild(UI.Label {
            text = "分红收益 (" .. colC .. "/" .. totC .. ")",
            fontSize = 11,
            fontColor = colC >= totC and { 100, 200, 100, 200 } or { 170, 160, 200, 200 },
            marginTop = 8, marginBottom = 3,
        })
        for _, item in ipairs(SD.christmasCookies) do
            local got = seasonManager_.HasCollected(item.id)
            contentContainer_:AddChild(UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                paddingLeft = 6, paddingRight = 6, paddingTop = 4, paddingBottom = 4,
                gap = 6, borderRadius = 4,
                backgroundColor = got and { 30, 45, 30, 200 } or { 25, 22, 35, 160 },
                opacity = got and 1.0 or 0.5,
                children = {
                    ItemIcon(item, got),
                    UI.Label { text = got and item.name or "???", fontSize = 10, flex = 1, flexShrink = 1,
                        fontColor = got and { 150, 220, 150, 230 } or { 100, 95, 115, 160 } },
                    UI.Label { text = "+2% CpS", fontSize = 9, fontColor = { 130, 125, 145, 140 } },
                    UI.Label { text = got and "✓" or "-", fontSize = 10, width = 16, textAlign = "center",
                        fontColor = got and { 100, 200, 100, 200 } or { 80, 75, 90, 120 } },
                },
            })
        end
        contentContainer_:AddChild(UI.Label {
            text = "获取方式: 点击风投快车时掉落",
            fontSize = 9,
            fontColor = { 120, 115, 140, 140 },
            marginTop = 3,
        })
    end

    -- ===== 熊市：不良资产收集 =====
    if active == SD.SEASON_HALLOWEEN then
        local colH, totH = seasonManager_.GetCollectionProgress(SD.halloweenCookies)
        contentContainer_:AddChild(UI.Label {
            text = "不良资产 (" .. colH .. "/" .. totH .. ")",
            fontSize = 11,
            fontColor = colH >= totH and { 100, 200, 100, 200 } or { 170, 160, 200, 200 },
            marginBottom = 3,
        })
        for _, item in ipairs(SD.halloweenCookies) do
            local got = seasonManager_.HasCollected(item.id)
            contentContainer_:AddChild(UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                paddingLeft = 6, paddingRight = 6, paddingTop = 4, paddingBottom = 4,
                gap = 6, borderRadius = 4,
                backgroundColor = got and { 30, 45, 30, 200 } or { 25, 22, 35, 160 },
                opacity = got and 1.0 or 0.5,
                children = {
                    ItemIcon(item, got),
                    UI.Label { text = got and item.name or "???", fontSize = 10, flex = 1, flexShrink = 1,
                        fontColor = got and { 150, 220, 150, 230 } or { 100, 95, 115, 160 } },
                    UI.Label { text = "+2% CpS", fontSize = 9, fontColor = { 130, 125, 145, 140 } },
                    UI.Label { text = got and "✓" or "-", fontSize = 10, width = 16, textAlign = "center",
                        fontColor = got and { 100, 200, 100, 200 } or { 80, 75, 90, 120 } },
                },
            })
        end
        contentContainer_:AddChild(UI.Label {
            text = "获取方式: 清除灰色渠道时掉落",
            fontSize = 9,
            fontColor = { 120, 115, 140, 140 },
            marginTop = 3,
        })
    end

    -- ===== 创新潮：专利技术收集 =====
    if active == SD.SEASON_EASTER then
        -- 普通专利列表
        local colN, totN = seasonManager_.GetCollectionProgress(SD.easterEggsNormal)
        contentContainer_:AddChild(UI.Label {
            text = "普通专利 (" .. colN .. "/" .. totN .. ")",
            fontSize = 11,
            fontColor = colN >= totN and { 100, 200, 100, 200 } or { 170, 160, 200, 200 },
            marginBottom = 3,
        })
        for _, item in ipairs(SD.easterEggsNormal) do
            local got = seasonManager_.HasCollected(item.id)
            contentContainer_:AddChild(UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                paddingLeft = 6, paddingRight = 6, paddingTop = 4, paddingBottom = 4,
                gap = 6, borderRadius = 4,
                backgroundColor = got and { 30, 45, 30, 200 } or { 25, 22, 35, 160 },
                opacity = got and 1.0 or 0.5,
                children = {
                    ItemIcon(item, got),
                    UI.Label { text = got and item.name or "???", fontSize = 10, flex = 1, flexShrink = 1,
                        fontColor = got and { 150, 220, 150, 230 } or { 100, 95, 115, 160 } },
                    UI.Label { text = "+1% CpS", fontSize = 9, fontColor = { 130, 125, 145, 140 } },
                    UI.Label { text = got and "✓" or "-", fontSize = 10, width = 16, textAlign = "center",
                        fontColor = got and { 100, 200, 100, 200 } or { 80, 75, 90, 120 } },
                },
            })
        end

        -- 核心技术列表
        local colR, totR = seasonManager_.GetCollectionProgress(SD.easterEggsRare)
        contentContainer_:AddChild(UI.Label {
            text = "核心技术 (" .. colR .. "/" .. totR .. ")",
            fontSize = 11,
            fontColor = colR >= totR and { 100, 200, 100, 200 } or { 170, 160, 200, 200 },
            marginTop = 8, marginBottom = 3,
        })
        for _, item in ipairs(SD.easterEggsRare) do
            local got = seasonManager_.HasCollected(item.id)
            contentContainer_:AddChild(UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                paddingLeft = 6, paddingRight = 6, paddingTop = 4, paddingBottom = 4,
                gap = 6, borderRadius = 4,
                backgroundColor = got and { 35, 40, 30, 200 } or { 25, 22, 35, 160 },
                opacity = got and 1.0 or 0.5,
                children = {
                    ItemIcon(item, got),
                    UI.Panel { flex = 1, flexShrink = 1, gap = 1, children = {
                        UI.Label { text = got and item.name or "???", fontSize = 10,
                            fontColor = got and { 180, 200, 130, 230 } or { 100, 95, 115, 160 } },
                        UI.Label { text = item.desc, fontSize = 9,
                            fontColor = { 130, 125, 145, 150 } },
                    }},
                    UI.Label { text = got and "✓" or "-", fontSize = 10, width = 16, textAlign = "center",
                        fontColor = got and { 100, 200, 100, 200 } or { 80, 75, 90, 120 } },
                },
            })
        end

        local centuryBonus = seasonManager_.GetCenturyEggBonus()
        if centuryBonus > 0 then
            contentContainer_:AddChild(UI.Label {
                text = "百年老字号: +" .. string.format("%.1f", centuryBonus * 100) .. "% CpS",
                fontSize = 9,
                fontColor = { 180, 160, 100, 180 },
                marginTop = 4,
            })
        end
        contentContainer_:AddChild(UI.Label {
            text = "获取方式: 点击黄金商机 / 清除灰色渠道",
            fontSize = 9,
            fontColor = { 120, 115, 140, 140 },
            marginTop = 3,
        })
    end

    -- ===== 合作季：合作协议解锁 =====
    if active == SD.SEASON_VALENTINE then
        local colV, totV = seasonManager_.GetCollectionProgress(SD.valentineCookies)
        contentContainer_:AddChild(UI.Label {
            text = "合作协议 (" .. colV .. "/" .. totV .. ")",
            fontSize = 11,
            fontColor = colV >= totV and { 100, 200, 100, 200 } or { 170, 160, 200, 200 },
            marginBottom = 3,
        })
        for _, item in ipairs(SD.valentineCookies) do
            local got = seasonManager_.HasCollected(item.id)
            local threshText = item.threshold > 0
                and ("需 " .. F(item.threshold) .. " 金币")
                or "自动获得"
            contentContainer_:AddChild(UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                paddingLeft = 6, paddingRight = 6, paddingTop = 4, paddingBottom = 4,
                gap = 6, borderRadius = 4,
                backgroundColor = got and { 30, 45, 30, 200 } or { 25, 22, 35, 160 },
                opacity = got and 1.0 or 0.5,
                children = {
                    ItemIcon(item, got),
                    UI.Panel { flex = 1, flexShrink = 1, gap = 1, children = {
                        UI.Label { text = got and item.name or "???", fontSize = 10,
                            fontColor = got and { 150, 220, 150, 230 } or { 100, 95, 115, 160 } },
                        UI.Label { text = threshText, fontSize = 9,
                            fontColor = { 130, 125, 145, 150 } },
                    }},
                    UI.Label { text = "+2% CpS", fontSize = 9, fontColor = { 130, 125, 145, 140 } },
                    UI.Label { text = got and "✓" or "-", fontSize = 10, width = 16, textAlign = "center",
                        fontColor = got and { 100, 200, 100, 200 } or { 80, 75, 90, 120 } },
                },
            })
        end
        contentContainer_:AddChild(UI.Label {
            text = "获取方式: 达到累计金币阈值自动解锁",
            fontSize = 9,
            fontColor = { 120, 115, 140, 140 },
            marginTop = 3,
        })
    end

    -- ===== 清仓促销：效果说明 =====
    if active == SD.SEASON_BUSINESS then
        local eff = SD.BUSINESS_DAY_EFFECT
        contentContainer_:AddChild(UI.Panel {
            width = "100%", padding = 8, borderRadius = 6, borderWidth = 1,
            backgroundColor = { 30, 35, 45, 220 },
            borderColor = { 60, 70, 100, 120 },
            gap = 2,
            children = {
                UI.Label { text = eff.name, fontSize = 12,
                    fontColor = { 200, 195, 215, 230 } },
                UI.Label { text = eff.desc .. "，持续 " .. eff.duration .. " 秒", fontSize = 10,
                    fontColor = { 150, 200, 100, 180 } },
                UI.Label { text = "黄金商机随机触发", fontSize = 9,
                    fontColor = { 120, 115, 140, 140 } },
            },
        })
    end

    initialized_ = true
end

-- ============================================================================
-- 增量更新（结构不变时）
-- ============================================================================

local function IncrementalUpdate()
    local F = GameState.FormatNumber
    local active = seasonManager_.GetActiveSeason()

    -- 更新圣诞老人区域
    if active == SD.SEASON_CHRISTMAS and santaCache_ then
        local santaLevel = seasonManager_.GetSantaLevel()
        local isMaxed = santaLevel >= SD.SANTA_MAX_LEVEL
        local cost = isMaxed and 0 or SD.GetSantaUpgradeCost(santaLevel)
        local canAfford = not isMaxed and GameState.coins >= cost
        local fp = santaLevel .. ":" .. (canAfford and "Y" or "N")

        if fp ~= santaCache_.lastFP then
            santaCache_.lastFP = fp
            local santaName = seasonManager_.GetSantaName()
            santaCache_.nameLabel:SetText("Lv." .. santaLevel .. " " .. santaName)
            santaCache_.nameLabel:SetFontColor(isMaxed and { 100, 220, 100, 255 }
                or { 230, 200, 180, 255 })
            -- costLabel 是 Panel，费用变化时触发全量重建
            initialized_ = false
            santaCache_.panel:SetStyle({
                backgroundColor = isMaxed and { 40, 55, 35, 255 }
                    or (canAfford and { 55, 35, 35, 255 } or { 35, 28, 35, 220 }),
                borderColor = isMaxed and { 100, 200, 80, 200 }
                    or (canAfford and { 255, 150, 100, 200 } or { 70, 50, 70, 120 }),
                pointerEvents = canAfford and "auto" or "none",
            })
        end

        -- 圣诞升级状态
        local xmasStatus = seasonManager_.GetXmasUpgradeStatus()
        for xi, s in ipairs(xmasStatus) do
            local cache = xmasUpgradeCache_[xi]
            if cache and s.unlocked ~= cache.lastUnlocked then
                cache.lastUnlocked = s.unlocked
                cache.statusLabel:SetText(s.unlocked and "✓" or "-")
                cache.statusLabel:SetFontColor(s.unlocked and { 100, 200, 100, 200 }
                    or { 80, 75, 90, 120 })
                cache.row:SetStyle({
                    backgroundColor = s.unlocked and { 30, 45, 30, 255 } or { 25, 22, 30, 180 },
                    borderColor = s.unlocked and { 80, 160, 80, 120 } or { 40, 35, 50, 60 },
                    opacity = s.unlocked and 1.0 or 0.35,
                })
            end
        end
    end


end

-- ============================================================================
-- 公共接口
-- ============================================================================

function SP.Init(root, manager, switchCb, santaCb)
    uiRoot_ = root
    seasonManager_ = manager
    onSwitchSeason_ = switchCb
    onUpgradeSanta_ = santaCb
    BuildPanel()
end

function SP.Show()
    if not panel_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    uiRoot_:AddChild(panel_)
    -- 重置缓存
    initialized_ = false
    lastSnapshot_ = ""
    lastInfoText_ = ""
    seasonBtnCache_ = {}
    santaCache_ = nil
    xmasUpgradeCache_ = {}
    SP.Refresh()
end

function SP.Hide()
    if not panel_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(panel_)
end

function SP.Toggle()
    if visible_ then SP.Hide() else SP.Show() end
end

function SP.IsVisible() return visible_ end

-- ============================================================================
-- 刷新（增量）
-- ============================================================================

function SP.Refresh()
    if not visible_ or not seasonManager_ then return end

    -- 季节信息标签
    if seasonInfoLabel_ then
        local active = seasonManager_.GetActiveSeason()
        local seasonDef = SD.FindSeason(active)
        local manualTimer = seasonManager_.GetManualTimer()

        local text = "当前周期: "
        if seasonDef then
            text = text .. seasonDef.name
        else
            text = text .. "无"
        end
        if manualTimer > 0 then
            local t = math.floor(manualTimer)
            local h = math.floor(t / 3600)
            local m = math.floor((t % 3600) / 60)
            local s = t % 60
            text = text .. string.format(" (%02d:%02d:%02d)", h, m, s)
        end
        local bonus = seasonManager_.GetCollectionCpsMul()
        if bonus > 0 then
            text = text .. " | 收集加成: +" .. math.floor(bonus * 100) .. "% CpS"
        end
        if text ~= lastInfoText_ then
            seasonInfoLabel_:SetText(text)
            lastInfoText_ = text
        end
    end

    -- 快照检测
    local snap = MakeSnapshot()
    if snap == lastSnapshot_ then return end

    -- 判断是否需要结构重建
    -- 简易判断：活跃季节或圣诞等级变化 → 结构重建
    local active = seasonManager_.GetActiveSeason()
    local needRebuild = not initialized_

    if not needRebuild and initialized_ then
        -- 检查关键结构是否变化
        local oldActive = lastSnapshot_:match("S:([^|]*)")
        local newActive = snap:match("S:([^|]*)")
        if oldActive ~= newActive then
            needRebuild = true
        end
        if not needRebuild and active == SD.SEASON_CHRISTMAS then
            local oldSL = lastSnapshot_:match("SL:(%d+)")
            local newSL = snap:match("SL:(%d+)")
            if oldSL ~= newSL then
                needRebuild = true
            end
        end
    end

    lastSnapshot_ = snap

    if needRebuild then
        RebuildContent()
    else
        IncrementalUpdate()
    end
end

return SP
