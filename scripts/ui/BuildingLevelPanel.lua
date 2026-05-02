-- ============================================================================
-- ui/BuildingLevelPanel.lua
-- 产业等级升级面板（全屏覆盖式弹窗）
-- 使用人脉升级产业等级，每级 +1% CpS
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
local listContainer_ = nil
local infoLabel_ = nil
local infoCountLabel_ = nil
local infoBonusLabel_ = nil
local visible_ = false

-- 外部注入
local sugarLumpManager_ = nil
local onUpgrade_ = nil         -- function(buildingIndex)

-- ======== 增量刷新缓存 ========
local rowCache_ = {}            -- rowCache_[bi] = { row, levelLabel, bonusLabel, statusLabel, dots, lastFP }
local lastInfoText_ = ""
local initialized_ = false

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

    listContainer_ = UI.Panel {
        width = "100%",
        gap = 4,
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

            -- 可滚动内容区
            UI.ScrollView {
                flex = 1,
                width = "100%",
                showScrollbar = false,
                children = {
                    listContainer_,
                },
            },
        },
    }
end

-- ============================================================================
-- 构建建筑行（带缓存引用）
-- ============================================================================

local function BuildBuildingRow(bi, building)
    local level = sugarLumpManager_.GetBuildingLevel(bi)
    local maxLevel = SD.MAX_BUILDING_LEVEL
    local cost = sugarLumpManager_.GetUpgradeCost(bi)
    local lumps = sugarLumpManager_.GetLumps()
    local isMaxed = level >= maxLevel
    local hasBuilding = building.count > 0
    local canAfford = lumps >= cost

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

    -- 等级条（小圆点）
    local levelDots = {}
    local dotRefs = {}
    for lv = 1, maxLevel do
        local dot = UI.Panel {
            width = 8, height = 8,
            borderRadius = 4,
            backgroundColor = lv <= level
                and { 255, 215, 0, 255 }
                or  { 50, 40, 60, 200 },
            marginRight = 2,
        }
        levelDots[#levelDots + 1] = dot
        dotRefs[lv] = dot
    end

    -- 加成文字
    local bonusText = ""
    if level > 0 then
        bonusText = "+" .. level .. "%"
    end

    local clickable = hasBuilding and not isMaxed and canAfford

    local levelLabel = UI.Label { text = "Lv." .. level, fontSize = 11,
        fontColor = level > 0
            and { 255, 215, 0, 220 }
            or  { 100, 100, 120, 160 } }

    local bonusLabel = UI.Label { text = bonusText, fontSize = 12,
        fontColor = { 100, 255, 100, 220 },
        textAlign = "right",
        width = 50 }

    -- 状态区域：按钮（图标+数字）或 纯文字
    local statusLabel  -- 用于增量刷新时更新文字
    local statusWidget -- 行内实际挂载的 widget
    if not hasBuilding then
        statusLabel = UI.Label { text = "未拥有", fontSize = 10,
            fontColor = { 120, 120, 140, 160 }, textAlign = "right" }
        statusWidget = statusLabel
    elseif isMaxed then
        statusLabel = UI.Label { text = "MAX", fontSize = 11,
            fontColor = { 100, 200, 100, 200 }, textAlign = "center" }
        statusWidget = UI.Panel {
            flexDirection = "row", alignItems = "center", justifyContent = "center",
            paddingLeft = 6, paddingRight = 6, paddingTop = 3, paddingBottom = 3,
            borderRadius = 6,
            backgroundColor = { 40, 70, 45, 200 },
            borderWidth = 1, borderColor = { 80, 180, 80, 120 },
            children = { statusLabel },
        }
    else
        statusLabel = UI.Label { text = tostring(cost), fontSize = 12,
            fontColor = { 255, 255, 255, 240 } }
        local idx = bi
        statusWidget = UI.Panel {
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
                statusLabel,
            },
        }
    end

    local row = UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        padding = 8, gap = 6, borderRadius = 6, borderWidth = 1,
        backgroundColor = bgColor,
        borderColor = borderColor,
        opacity = hasBuilding and 1.0 or 0.35,
        children = {
            -- 建筑图标
            UI.Panel {
                width = 30, height = 30,
                backgroundImage = building.iconImage,
                backgroundFit = "contain",
            },
            -- 名称 + 等级条
            UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, children = {
                    UI.Label { text = building.name, fontSize = 13,
                        fontColor = isMaxed and { 100, 200, 100, 255 }
                            or { 220, 210, 240, 255 } },
                    levelLabel,
                }},
                UI.Panel { flexDirection = "row", alignItems = "center", children = levelDots },
            }},
            -- 加成 + 费用按钮
            UI.Panel { alignItems = "flex-end", gap = 4, children = {
                bonusLabel,
                statusWidget,
            }},
        },
    }

    -- 生成指纹
    local fp = level .. ":" .. building.count .. ":" .. lumps

    -- 缓存引用
    rowCache_[bi] = {
        row = row,
        levelLabel = levelLabel,
        bonusLabel = bonusLabel,
        statusLabel = statusLabel,
        dots = dotRefs,
        lastFP = fp,
        lastLevel = level,
        lastCount = building.count,
    }

    return row
end

-- ============================================================================
-- 增量更新单行
-- ============================================================================

local function UpdateRow(bi, building)
    local cache = rowCache_[bi]
    if not cache or not cache.row then return end

    local level = sugarLumpManager_.GetBuildingLevel(bi)
    local maxLevel = SD.MAX_BUILDING_LEVEL
    local cost = sugarLumpManager_.GetUpgradeCost(bi)
    local lumps = sugarLumpManager_.GetLumps()
    local isMaxed = level >= maxLevel
    local hasBuilding = building.count > 0
    local canAfford = lumps >= cost

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

    local clickable = hasBuilding and not isMaxed and canAfford

    -- 更新行样式
    cache.row:SetStyle({
        backgroundColor = bgColor,
        borderColor = borderColor,
        opacity = hasBuilding and 1.0 or 0.35,
    })

    -- 更新等级标签
    cache.levelLabel:SetText("Lv." .. level)
    cache.levelLabel:SetFontColor(level > 0
        and { 255, 215, 0, 220 }
        or  { 100, 100, 120, 160 })

    -- 更新加成标签
    local bonusText = level > 0 and ("+" .. level .. "%") or ""
    cache.bonusLabel:SetText(bonusText)

    -- 更新状态标签文字
    local statusText
    if not hasBuilding then
        statusText = "未拥有"
    elseif isMaxed then
        statusText = "MAX"
    else
        statusText = tostring(cost)
    end
    cache.statusLabel:SetText(statusText)

    -- 更新等级圆点
    for lv = 1, maxLevel do
        local dot = cache.dots[lv]
        if dot then
            dot:SetStyle({
                backgroundColor = lv <= level
                    and { 255, 215, 0, 255 }
                    or  { 50, 40, 60, 200 },
            })
        end
    end

    -- 更新指纹
    cache.lastFP = level .. ":" .. building.count .. ":" .. lumps
    cache.lastLevel = level
    cache.lastCount = building.count
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
    -- 重置缓存，确保 Show 时完全重建一次
    initialized_ = false
    rowCache_ = {}
    lastInfoText_ = ""
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

    if not listContainer_ then return end

    -- 首次构建：创建所有行并缓存
    if not initialized_ then
        initialized_ = true
        listContainer_:RemoveAllChildren()
        for bi, building in ipairs(Buildings.buildings) do
            listContainer_:AddChild(BuildBuildingRow(bi, building))
        end
        return
    end

    -- 增量更新：仅更新变化的行
    local lumps = sugarLumpManager_.GetLumps()
    for bi, building in ipairs(Buildings.buildings) do
        local cache = rowCache_[bi]
        if cache then
            local level = sugarLumpManager_.GetBuildingLevel(bi)
            local fp = level .. ":" .. building.count .. ":" .. lumps
            if fp ~= cache.lastFP then
                -- 拥有状态或满级状态变化时，重建整行（widget 结构不同）
                local wasOwned = (cache.lastCount or 0) > 0
                local nowOwned = building.count > 0
                local wasMaxed = (cache.lastLevel or 0) >= SD.MAX_BUILDING_LEVEL
                local nowMaxed = level >= SD.MAX_BUILDING_LEVEL
                if wasOwned ~= nowOwned or wasMaxed ~= nowMaxed then
                    local newRow = BuildBuildingRow(bi, building)
                    listContainer_:RemoveChild(cache.row)
                    listContainer_:InsertChild(newRow, bi)
                else
                    UpdateRow(bi, building)
                end
            end
        end
    end
end

return BLP
