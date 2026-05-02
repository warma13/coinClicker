-- ============================================================================
-- ui/BuildingLevelPanel.lua
-- 产业等级升级面板（全屏覆盖式弹窗）
-- 使用人脉升级产业等级，每级 +1% CpS
-- 使用 VirtualList 虚拟化列表
-- 使用 AddChild/RemoveChild 控制显隐
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local Buildings = require("config.Buildings")
local SD = require("config.SugarLumpDefs")

local BLP = {}

-- ======== 引用 ========
local uiRoot_ = nil
local panel_ = nil
local virtualList_ = nil
local infoLabel_ = nil
local infoCountLabel_ = nil
local infoBonusLabel_ = nil
local visible_ = false

-- 外部注入
local sugarLumpManager_ = nil
local onUpgrade_ = nil         -- function(buildingIndex)

-- ======== 增量刷新缓存 ========
local lastInfoText_ = ""
local lastDataFP_ = ""

-- ======== 行常量 ========
local ROW_HEIGHT = 56

-- ======== 扁平化数据 ========
-- flatData_[i] = { bi, building, level, cost, lumps, isMaxed, hasBuilding, canAfford }
local flatData_ = {}

-- ============================================================================
-- 重建扁平数据
-- ============================================================================

local function RebuildFlatData()
    flatData_ = {}
    if not sugarLumpManager_ then return end
    local lumps = sugarLumpManager_.GetLumps()
    for bi, building in ipairs(Buildings.buildings) do
        local level = sugarLumpManager_.GetBuildingLevel(bi)
        local maxLevel = SD.MAX_BUILDING_LEVEL
        local cost = sugarLumpManager_.GetUpgradeCost(bi)
        local isMaxed = level >= maxLevel
        local hasBuilding = building.count > 0
        local canAfford = lumps >= cost
        flatData_[#flatData_ + 1] = {
            bi = bi,
            building = building,
            level = level,
            cost = cost,
            lumps = lumps,
            isMaxed = isMaxed,
            hasBuilding = hasBuilding,
            canAfford = canAfford,
        }
    end
end

-- ============================================================================
-- VirtualList createItem / bindItem
-- ============================================================================

local function CreateRowWidget()
    -- 建筑图标
    local iconPanel = UI.Panel {
        width = 30, height = 30,
        backgroundFit = "contain",
    }

    -- 名称
    local nameLabel = UI.Label { text = "", fontSize = 13 }
    -- 等级
    local levelLabel = UI.Label { text = "", fontSize = 11 }

    -- 等级圆点容器
    local dotsContainer = UI.Panel {
        flexDirection = "row", alignItems = "center",
    }
    -- 预创建 MAX_BUILDING_LEVEL 个圆点
    local dots = {}
    for lv = 1, SD.MAX_BUILDING_LEVEL do
        local dot = UI.Panel {
            width = 8, height = 8,
            borderRadius = 4,
            backgroundColor = { 50, 40, 60, 200 },
            marginRight = 2,
        }
        dotsContainer:AddChild(dot)
        dots[lv] = dot
    end

    -- 加成文字
    local bonusLabel = UI.Label { text = "", fontSize = 12,
        fontColor = { 100, 255, 100, 220 },
        textAlign = "right", width = 50 }

    -- 状态区域：放一个容器，bindItem 时填充
    local statusContainer = UI.Panel {
        alignItems = "flex-end",
    }

    -- 行容器
    local row = UI.Panel {
        width = "100%", height = ROW_HEIGHT,
        flexDirection = "row", alignItems = "center",
        padding = 8, gap = 6, borderRadius = 6, borderWidth = 1,
        backgroundColor = { 35, 30, 45, 255 },
        borderColor = { 80, 60, 100, 120 },
        children = {
            iconPanel,
            UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, children = {
                    nameLabel,
                    levelLabel,
                }},
                dotsContainer,
            }},
            UI.Panel { alignItems = "flex-end", gap = 4, children = {
                bonusLabel,
                statusContainer,
            }},
        },
    }

    row._iconPanel = iconPanel
    row._nameLabel = nameLabel
    row._levelLabel = levelLabel
    row._dots = dots
    row._bonusLabel = bonusLabel
    row._statusContainer = statusContainer
    row._lastStatusType = nil  -- "none" | "maxed" | "cost" | "unavail"

    return row
end

local function BindRowWidget(widget, data, index)
    local building = data.building
    local level = data.level
    local isMaxed = data.isMaxed
    local hasBuilding = data.hasBuilding
    local canAfford = data.canAfford
    local cost = data.cost
    local bi = data.bi

    -- 背景色
    local bgColor, borderColor
    if not hasBuilding then
        bgColor = { 25, 25, 30, 200 }
        borderColor = { 40, 40, 50, 100 }
    elseif isMaxed then
        bgColor = { 30, 50, 35, 255 }
        borderColor = { 80, 180, 80, 120 }
    elseif canAfford then
        bgColor = { 55, 40, 60, 255 }
        borderColor = { 200, 150, 255, 200 }
    else
        bgColor = { 35, 30, 45, 255 }
        borderColor = { 80, 60, 100, 120 }
    end

    widget:SetStyle({
        backgroundColor = bgColor,
        borderColor = borderColor,
        opacity = hasBuilding and 1.0 or 0.35,
    })

    -- 图标
    widget._iconPanel:SetStyle({ backgroundImage = building.iconImage })

    -- 名称
    widget._nameLabel:SetText(building.name)
    widget._nameLabel:SetFontColor(isMaxed and { 100, 200, 100, 255 } or { 220, 210, 240, 255 })

    -- 等级
    widget._levelLabel:SetText("Lv." .. level)
    widget._levelLabel:SetFontColor(level > 0
        and { 255, 215, 0, 220 }
        or  { 100, 100, 120, 160 })

    -- 等级圆点
    for lv = 1, SD.MAX_BUILDING_LEVEL do
        local dot = widget._dots[lv]
        if dot then
            dot:SetStyle({
                backgroundColor = lv <= level
                    and { 255, 215, 0, 255 }
                    or  { 50, 40, 60, 200 },
            })
        end
    end

    -- 加成
    local bonusText = level > 0 and ("+" .. level .. "%") or ""
    widget._bonusLabel:SetText(bonusText)

    -- 状态区域：根据状态类型重建子元素
    local statusType
    if not hasBuilding then
        statusType = "unavail"
    elseif isMaxed then
        statusType = "maxed"
    else
        statusType = "cost:" .. (canAfford and "Y" or "N")
    end

    -- 仅当状态类型改变时重建
    if statusType ~= widget._lastStatusType then
        widget._lastStatusType = statusType
        widget._statusContainer:RemoveAllChildren()

        if not hasBuilding then
            widget._statusContainer:AddChild(
                UI.Label { text = "未拥有", fontSize = 10,
                    fontColor = { 120, 120, 140, 160 }, textAlign = "right" }
            )
        elseif isMaxed then
            widget._statusContainer:AddChild(
                UI.Panel {
                    flexDirection = "row", alignItems = "center", justifyContent = "center",
                    paddingLeft = 6, paddingRight = 6, paddingTop = 3, paddingBottom = 3,
                    borderRadius = 6,
                    backgroundColor = { 40, 70, 45, 200 },
                    borderWidth = 1, borderColor = { 80, 180, 80, 120 },
                    children = {
                        UI.Label { text = "MAX", fontSize = 11,
                            fontColor = { 100, 200, 100, 200 }, textAlign = "center" },
                    },
                }
            )
        else
            local idx = bi
            widget._statusContainer:AddChild(
                UI.Panel {
                    flexDirection = "row", alignItems = "center", justifyContent = "center",
                    paddingLeft = 6, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
                    borderRadius = 6, gap = 4,
                    backgroundColor = canAfford and { 80, 50, 120, 255 } or { 50, 45, 60, 200 },
                    borderWidth = 1,
                    borderColor = canAfford and { 180, 130, 255, 200 } or { 70, 60, 90, 120 },
                    pointerEvents = canAfford and "auto" or "none",
                    onPointerDown = canAfford and function()
                        if onUpgrade_ then
                            onUpgrade_(idx)
                            BLP.Refresh()
                        end
                    end or nil,
                    children = {
                        UI.Panel { width = 18, height = 18,
                            backgroundImage = "image/人脉.png", backgroundFit = "contain",
                            opacity = canAfford and 1.0 or 0.4 },
                        UI.Label { text = tostring(cost), fontSize = 12,
                            fontColor = { 255, 255, 255, 240 } },
                    },
                }
            )
        end
    end
end

-- ============================================================================
-- 内部：构建面板
-- ============================================================================

local function BuildPanel()
    local infoIcon = UI.Panel {
        width = 14, height = 14,
        backgroundImage = "image/人脉.png",
        backgroundFit = "contain",
    }
    infoCountLabel_ = UI.Label {
        id = "blpInfoCount",
        text = "0",
        fontSize = 12,
        fontColor = { 200, 180, 140, 200 },
    }
    infoBonusLabel_ = UI.Label {
        id = "blpInfoBonus",
        text = "",
        fontSize = 12,
        fontColor = { 200, 180, 140, 200 },
    }
    infoLabel_ = UI.Panel {
        id = "blpInfoLabel",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        gap = 4,
        marginBottom = 8,
        children = {
            UI.Label { text = "持有", fontSize = 12, fontColor = { 200, 180, 140, 200 } },
            infoIcon,
            infoCountLabel_,
            UI.Label { text = "人脉", fontSize = 12, fontColor = { 200, 180, 140, 200 } },
            infoBonusLabel_,
        },
    }

    -- 计算屏幕高度作为 viewportHeight
    local dpr = graphics:GetDPR()
    local screenH = graphics:GetHeight() / dpr

    virtualList_ = UI.VirtualList {
        width = "100%",
        flex = 1,
        data = {},
        itemHeight = ROW_HEIGHT,
        itemGap = 4,
        viewportHeight = screenH,
        poolBuffer = 3,
        createItem = CreateRowWidget,
        bindItem = BindRowWidget,
        showScrollbar = false,
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
                        backgroundImage = "image/侧栏_人脉_20260414105508.png",
                        backgroundFit = "contain" },
                    UI.Label {
                        text = "产业升级",
                        fontSize = 18,
                        fontColor = { 255, 200, 230, 255 },
                    },
                },
            },

            -- 信息标签
            infoLabel_,

            -- VirtualList 替代 ScrollView
            virtualList_,
        },
    }
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 初始化面板
---@param root table UI 根节点
---@param manager table SugarLumpManager 引用
---@param upgradeCb function 升级回调 function(buildingIndex)
function BLP.Init(root, manager, upgradeCb)
    uiRoot_ = root
    sugarLumpManager_ = manager
    onUpgrade_ = upgradeCb
    BuildPanel()
end

function BLP.Show()
    if not panel_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    uiRoot_:AddChild(panel_)
    lastInfoText_ = ""
    lastDataFP_ = ""
    BLP.Refresh()
end

function BLP.Hide()
    if not panel_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(panel_)
end

function BLP.Toggle()
    if visible_ then BLP.Hide() else BLP.Show() end
end

function BLP.IsVisible() return visible_ end

-- ============================================================================
-- 刷新（增量）
-- ============================================================================

function BLP.Refresh()
    if not visible_ or not sugarLumpManager_ then return end

    -- 更新信息标签
    if infoCountLabel_ and infoBonusLabel_ then
        local lumps = sugarLumpManager_.GetLumps()
        local bakingMul = sugarLumpManager_.GetSugarBakingMultiplier()
        local bakingBonus = math.floor((bakingMul - 1) * 100)
        local countText = tostring(lumps)
        local bonusText = bakingBonus > 0 and (" | 人脉效应: +" .. bakingBonus .. "% CpS") or ""
        local fp = countText .. bonusText
        if fp ~= lastInfoText_ then
            infoCountLabel_:SetText(countText)
            infoBonusLabel_:SetText(bonusText)
            lastInfoText_ = fp
        end
    end

    if not virtualList_ then return end

    -- 生成数据指纹
    local lumps = sugarLumpManager_.GetLumps()
    local parts = {}
    for bi, building in ipairs(Buildings.buildings) do
        local level = sugarLumpManager_.GetBuildingLevel(bi)
        parts[bi] = level .. ":" .. building.count .. ":" .. lumps
    end
    local dataFP = table.concat(parts, "|")

    if dataFP ~= lastDataFP_ then
        lastDataFP_ = dataFP
        RebuildFlatData()
        virtualList_:SetData(flatData_)
    end
end

return BLP
