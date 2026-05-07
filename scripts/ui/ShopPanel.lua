-- ============================================================================
-- ui/ShopPanel.lua
-- 右侧商店面板：升级图标栏 + 建筑列表（无标签页）
-- 升级图标栏统一展示建筑效率升级和点击升级
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local BuildingUpgrades = require("config.BuildingUpgrades")
local Tooltip = require("ui.Tooltip")

local ShopPanel = {}

-- ======== 数据引用 ========
local buildings_ = nil
local clickUpgrades_ = nil
local callbacks_ = nil
local uiRoot_ = nil

-- ======== 按条目缓存 ========
local buildingCache_ = {}

-- ======== 批量购买 ========
local buyAmount_ = 1   -- 当前购买数量: 1 / 10 / 100
local amountBtnCache_ = {}  -- { [1]=widget, [10]=widget, [100]=widget }

-- ======== 升级图标栏 ========
local buildingUpgrades_ = nil
local upgradeContainer_ = nil
local lastVisibleSnap_ = ""

-- ======== 小游戏解锁跟踪 ========
-- 有小游戏的建筑索引集合，用于检测 count 从 0 变 >=1 时触发列表重建
local MINIGAME_INDICES = { [3]=true, [4]=true, [5]=true, [6]=true, [7]=true, [8]=true, [9]=true, [11]=true }
local minigameUnlocked_ = {}  -- { [index] = true/false } 上次已知解锁状态

-- ======== 升级图标缓存 ========
local iconCache_ = {}  -- { [id_string] = widget }
local iconAffordCache_ = {} -- { [id_string] = bool } 上次 afford 状态

-- ======== 颜色常量 ========
local COLOR_AFFORD_BG       = { 45, 50, 70, 255 }
local COLOR_UNAFFORD_BG     = { 35, 35, 50, 255 }
local COLOR_AFFORD_BORDER   = { 255, 200, 50, 100 }
local COLOR_UNAFFORD_BORDER = { 60, 60, 80, 100 }
local COLOR_COST_GREEN      = { 100, 255, 100, 255 }
local COLOR_COST_RED        = { 255, 100, 100, 255 }

-- ======== 图标栏常量 ========
local ICON_SIZE = 42
local ICON_GAP = 4
local MAX_ROWS = 4

-- ============================================================================
-- 创建建筑条目
-- ============================================================================

local function BuildingTooltipConfig(item, buildingIndex)
    return function()
        local tipAmt = buyAmount_
        local c = GameState.GetBulkCost(item, tipAmt)
        local afford = GameState.coins >= c
        local F = GameState.FormatNumber
        local mul = 1
        if buildingUpgrades_ and buildingUpgrades_[buildingIndex] then
            mul = BuildingUpgrades.GetMultiplier(buildingUpgrades_[buildingIndex])
        end
        local perUnit = item.cpsAdd * mul
        local totalCps = perUnit * item.count
        local pct = 0
        if GameState.coinsPerSecond > 0 then
            pct = totalCps / GameState.coinsPerSecond * 100
        end
        local details = {}
        details[#details + 1] = "· 每个" .. item.name .. "产生 " .. F(perUnit) .. " 金币/秒"
        if item.count > 0 then
            details[#details + 1] = "· " .. item.count .. " 个" .. item.name .. "产生 "
                .. F(totalCps) .. " 金币/秒 (" .. string.format("%.1f", pct) .. "% 总产出)"
        end
        details[#details + 1] = "· " .. F(item.totalProduced or 0) .. " 到目前为止生产的金币"
        local costLabel = tipAmt > 1 and ("购买 " .. tipAmt .. " 个费用") or nil
        return {
            icon = item.icon,
            iconImage = item.iconImage,
            title = item.name,
            cost = c,
            costLabel = costLabel,
            subtitle = "[拥有: " .. item.count .. "]",
            details = details,
            action = afford and "点击购买。" or "金币不足。",
            actionColor = afford and "green" or "red",
        }
    end
end

local function CreateBuildingItem(item, idPrefix, onBuy, buildingIndex)
    local amt = buyAmount_
    local cost = GameState.GetBulkCost(item, amt)
    local canAfford = GameState.coins >= cost
    local F = GameState.FormatNumber
    local tooltipFn = BuildingTooltipConfig(item, buildingIndex)
    return UI.Panel {
        id = idPrefix .. item.id,
        width = "100%", flexDirection = "row", alignItems = "center",
        padding = 8, gap = 8, borderRadius = 8, borderWidth = 1,
        backgroundColor = canAfford and COLOR_AFFORD_BG or COLOR_UNAFFORD_BG,
        borderColor = canAfford and COLOR_AFFORD_BORDER or COLOR_UNAFFORD_BORDER,
        pointerEvents = "auto",
        -- 长按显示浮窗
        onLongPressStart = function(event)
            Tooltip.Show(tooltipFn, event.y)
        end,
        onLongPressEnd = function()
            Tooltip.Hide()
        end,
        -- hover 显示浮窗（PC 端）
        onPointerEnter = function(event)
            Tooltip.Show(tooltipFn, event.y)
        end,
        onPointerLeave = function() Tooltip.Hide() end,
        children = {
            UI.Panel {
                width = 36, height = 36,
                backgroundImage = item.iconImage,
                backgroundFit = "contain",
            },
            UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                UI.Label { text = item.name, fontSize = 13, fontColor = { 230, 230, 240, 255 } },
                UI.Label { text = item.desc, fontSize = 10, fontColor = { 140, 140, 160, 200 } },
            } },
            UI.Panel { alignItems = "flex-end", gap = 2, children = {
                -- 购买按钮（独立可点击区域）
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 2,
                    paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
                    borderRadius = 6,
                    backgroundColor = canAfford and { 45, 60, 45, 255 } or { 40, 40, 55, 255 },
                    borderWidth = 1,
                    borderColor = canAfford and { 100, 180, 100, 180 } or { 60, 60, 80, 100 },
                    pointerEvents = "auto",
                    onTap = function(self, event)
                        if event and event.stopPropagation then
                            event:stopPropagation()
                        end
                        onBuy(self)
                    end,
                    children = {
                        UI.Panel { width = 14, height = 14,
                            backgroundImage = "image/金币.png", backgroundFit = "contain" },
                        UI.Label { id = idPrefix .. "cost_" .. item.id,
                            text = F(cost), fontSize = 12,
                            fontColor = canAfford and COLOR_COST_GREEN or COLOR_COST_RED },
                    },
                },
                UI.Label { id = idPrefix .. "count_" .. item.id,
                    text = "x" .. item.count, fontSize = 11,
                    fontColor = { 180, 180, 200, 180 } },
            } },
        },
    }
end

-- ============================================================================
-- 点击升级解锁判断
-- ============================================================================

--- 判断点击升级是否解锁（可见）
local function IsClickUpgradeVisible(u)
    -- 已购买的不显示
    if u.maxCount and u.count >= u.maxCount then return false end
    -- 鼠标升级线：需要足够点击次数
    if u.needClicks and GameState.totalClicks < u.needClicks then return false end
    -- 幸运升级线：需要足够幸运金币点击次数
    if u.needLuckyClicks and GameState.luckyClicks < u.needLuckyClicks then return false end
    -- 手指升级线：需要足够光标数量
    if u.needCursor then
        local cursor = buildings_ and buildings_[1]
        if cursor and cursor.count < u.needCursor then return false end
    end
    return true
end

-- ============================================================================
-- 升级图标栏（建筑效率升级 + 点击升级统一展示）
-- ============================================================================

--- 生成快照（用于 diff 检测）
local function MakeVisibleSnap(bldVisible, clkVisible)
    local parts = {}
    for _, u in ipairs(bldVisible) do
        parts[#parts + 1] = "B" .. u.buildingIndex .. "." .. u.tierIndex .. (u.bought and "Y" or "N")
    end
    for _, info in ipairs(clkVisible) do
        parts[#parts + 1] = "C" .. info.index
    end
    return table.concat(parts, ",")
end

--- 创建建筑效率升级图标
local function CreateBuildingUpgradeIcon(u, onBuy)
    local bought = u.bought
    local canAfford = (not bought) and (GameState.coins >= u.cost)

    local bgColor, borderColor, opacity
    if bought then
        bgColor = { 30, 60, 35, 255 }
        borderColor = { 80, 180, 80, 150 }
        opacity = 0.6
    elseif canAfford then
        bgColor = { 60, 55, 30, 255 }
        borderColor = { 255, 215, 0, 220 }
        opacity = 1.0
    else
        bgColor = { 35, 35, 50, 255 }
        borderColor = { 60, 60, 80, 100 }
        opacity = 0.5
    end

    local iconId = "bu_" .. u.buildingIndex .. "_" .. u.tierIndex

    return UI.Panel {
        id = iconId,
        width = ICON_SIZE, height = ICON_SIZE,
        justifyContent = "center", alignItems = "center",
        backgroundColor = bgColor,
        borderRadius = 6, borderWidth = bought and 1 or 2,
        borderColor = borderColor,
        opacity = opacity,
        pointerEvents = "auto",
        onTap = (not bought) and function(event, widget)
            onBuy(widget)
        end or nil,
        onLongPressStart = function(event)
            Tooltip.Show(function()
                local F = GameState.FormatNumber
                local mulNow = 1
                if buildingUpgrades_ and buildingUpgrades_[u.buildingIndex] then
                    mulNow = BuildingUpgrades.GetMultiplier(buildingUpgrades_[u.buildingIndex])
                end
                local statusText, statusColor
                if bought then
                    statusText = "已购买。"
                    statusColor = "green"
                elseif GameState.coins >= u.cost then
                    statusText = "点击购买。"
                    statusColor = "green"
                else
                    statusText = "金币不足。"
                    statusColor = "red"
                end
                local isCursor = (u.buildingIndex == 1)
                local descText
                if isCursor then
                    descText = "使 " .. u.buildingName .. " 效率和点击力量同时翻倍（x2）"
                else
                    descText = "使 " .. u.buildingName .. " 效率翻倍（x2）"
                end
                return {
                    icon = u.buildingIcon,
                    iconImage = u.buildingIconImage,
                    title = u.buildingName,
                    cost = (not bought) and u.cost or nil,
                    desc = descText,
                    extra = "当前效率倍率: x" .. mulNow .. "  |  需要: " .. u.needCount .. " 个",
                    action = statusText,
                    actionColor = statusColor,
                }
            end, event.y)
        end,
        onLongPressEnd = function() Tooltip.Hide() end,
        onPointerEnter = function(event)
            Tooltip.Show(function()
                local F = GameState.FormatNumber
                local mulNow = 1
                if buildingUpgrades_ and buildingUpgrades_[u.buildingIndex] then
                    mulNow = BuildingUpgrades.GetMultiplier(buildingUpgrades_[u.buildingIndex])
                end
                local statusText, statusColor
                if bought then
                    statusText = "已购买。"
                    statusColor = "green"
                elseif GameState.coins >= u.cost then
                    statusText = "点击购买。"
                    statusColor = "green"
                else
                    statusText = "金币不足。"
                    statusColor = "red"
                end
                local isCursor = (u.buildingIndex == 1)
                local descText
                if isCursor then
                    descText = "使 " .. u.buildingName .. " 效率和点击力量同时翻倍（x2）"
                else
                    descText = "使 " .. u.buildingName .. " 效率翻倍（x2）"
                end
                return {
                    icon = u.buildingIcon,
                    iconImage = u.buildingIconImage,
                    title = u.buildingName,
                    cost = (not bought) and u.cost or nil,
                    desc = descText,
                    extra = "当前效率倍率: x" .. mulNow .. "  |  需要: " .. u.needCount .. " 个",
                    action = statusText,
                    actionColor = statusColor,
                }
            end, event.y)
        end,
        onPointerLeave = function() Tooltip.Hide() end,
        children = {
            UI.Panel {
                width = 22, height = 22,
                backgroundImage = u.buildingIconImage,
                backgroundFit = "contain",
            },
            UI.Label {
                text = bought and "✓" or ("T" .. u.tierIndex),
                fontSize = 8,
                fontColor = bought and { 100, 200, 100, 200 } or
                    (canAfford and { 255, 215, 0, 255 } or { 120, 120, 140, 180 }),
                textAlign = "center",
            },
        },
    }
end

--- 创建点击升级图标
local function CreateClickUpgradeIcon(u, index, onBuy)
    local canAfford = GameState.coins >= u.baseCost

    local bgColor, borderColor, opacity
    if canAfford then
        bgColor = { 60, 55, 30, 255 }
        borderColor = { 255, 215, 0, 220 }
        opacity = 1.0
    else
        bgColor = { 35, 35, 50, 255 }
        borderColor = { 60, 60, 80, 100 }
        opacity = 0.5
    end

    local iconId = "cu_" .. index

    return UI.Panel {
        id = iconId,
        width = ICON_SIZE, height = ICON_SIZE,
        justifyContent = "center", alignItems = "center",
        backgroundColor = bgColor,
        borderRadius = 6, borderWidth = 2,
        borderColor = borderColor,
        opacity = opacity,
        pointerEvents = "auto",
        onTap = function(event, widget)
            onBuy(widget)
        end,
        onLongPressStart = function(event)
            Tooltip.Show(function()
                local afford = GameState.coins >= u.baseCost
                local extraText = nil
                if u.needClicks then
                    extraText = "需要: " .. u.needClicks .. " 次点击"
                elseif u.needLuckyClicks then
                    extraText = "需要: 点击 " .. u.needLuckyClicks .. " 次幸运金币"
                elseif u.needCursor then
                    extraText = "需要: " .. u.needCursor .. " 个临时工"
                end
                return {
                    icon = u.icon,
                    iconImage = u.iconImage,
                    title = u.name,
                    cost = u.baseCost,
                    desc = u.desc,
                    extra = extraText,
                    action = afford and "点击购买。" or "金币不足。",
                    actionColor = afford and "green" or "red",
                }
            end, event.y)
        end,
        onLongPressEnd = function() Tooltip.Hide() end,
        onPointerEnter = function(event)
            Tooltip.Show(function()
                local afford = GameState.coins >= u.baseCost
                local extraText = nil
                if u.needClicks then
                    extraText = "需要: " .. u.needClicks .. " 次点击"
                elseif u.needLuckyClicks then
                    extraText = "需要: 点击 " .. u.needLuckyClicks .. " 次幸运金币"
                elseif u.needCursor then
                    extraText = "需要: " .. u.needCursor .. " 个临时工"
                end
                return {
                    icon = u.icon,
                    iconImage = u.iconImage,
                    title = u.name,
                    cost = u.baseCost,
                    desc = u.desc,
                    extra = extraText,
                    action = afford and "点击购买。" or "金币不足。",
                    actionColor = afford and "green" or "red",
                }
            end, event.y)
        end,
        onPointerLeave = function() Tooltip.Hide() end,
        children = {
            UI.Panel { width = 28, height = 28, backgroundImage = u.iconImage, backgroundFit = "contain" },
        },
    }
end

--- 获取可见的点击升级列表
local function GetVisibleClickUpgrades()
    local visible = {}
    if not clickUpgrades_ then return visible end
    for i, u in ipairs(clickUpgrades_) do
        if IsClickUpgradeVisible(u) then
            visible[#visible + 1] = { upgrade = u, index = i }
        end
    end
    return visible
end

--- 构建统一升级图标栏
local function BuildUnifiedIconBar(container)
    if not container then return end
    container:RemoveAllChildren()

    local bldVisible = {}
    if buildingUpgrades_ and buildings_ then
        bldVisible = BuildingUpgrades.GetVisible(buildingUpgrades_, buildings_)
    end
    local clkVisible = GetVisibleClickUpgrades()

    -- 如果没有任何可见升级，不显示标题
    if #bldVisible == 0 and #clkVisible == 0 then
        lastVisibleSnap_ = ""
        return
    end

    -- 图标网格
    local grid = UI.Panel {
        id = "upgradeGrid",
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = ICON_GAP,
        minHeight = ICON_SIZE,
        maxHeight = (ICON_SIZE + ICON_GAP) * MAX_ROWS,
        overflow = "scroll",
    }

    -- 建筑效率升级图标
    for _, u in ipairs(bldVisible) do
        grid:AddChild(CreateBuildingUpgradeIcon(u, function(self)
            if callbacks_ and callbacks_.onBuyBuildingUpgrade then
                callbacks_.onBuyBuildingUpgrade(u.buildingIndex, u.tierIndex)
            end
        end))
    end

    -- 点击升级图标
    for _, info in ipairs(clkVisible) do
        grid:AddChild(CreateClickUpgradeIcon(info.upgrade, info.index, function(self)
            if callbacks_ and callbacks_.onBuyClickUpgrade then
                callbacks_.onBuyClickUpgrade(info.index)
            end
        end))
    end

    container:AddChild(grid)
    lastVisibleSnap_ = MakeVisibleSnap(bldVisible, clkVisible)

    -- 重建图标缓存 + afford 缓存
    iconCache_ = {}
    iconAffordCache_ = {}
    local coins = GameState.coins
    if uiRoot_ then
        for _, u in ipairs(bldVisible) do
            local kid = "bu_" .. u.buildingIndex .. "_" .. u.tierIndex
            iconCache_[kid] = uiRoot_:FindById(kid)
            iconAffordCache_[kid] = u.bought or (coins >= u.cost)
        end
        for _, info in ipairs(clkVisible) do
            local kid = "cu_" .. info.index
            iconCache_[kid] = uiRoot_:FindById(kid)
            iconAffordCache_[kid] = coins >= info.upgrade.baseCost
        end
    end
end

--- 刷新图标栏（diff 检测）
local function RefreshIconBar()
    if not upgradeContainer_ then return end

    local bldVisible = {}
    if buildingUpgrades_ and buildings_ then
        bldVisible = BuildingUpgrades.GetVisible(buildingUpgrades_, buildings_)
    end
    local clkVisible = GetVisibleClickUpgrades()
    local newSnap = MakeVisibleSnap(bldVisible, clkVisible)

    -- 结构变化 → 重建
    if newSnap ~= lastVisibleSnap_ then
        BuildUnifiedIconBar(upgradeContainer_)
        return
    end

    -- 仅 afford 变化 → diff 更新样式（使用缓存引用，避免 FindById）
    local coins = GameState.coins

    for _, u in ipairs(bldVisible) do
        if not u.bought then
            local kid = "bu_" .. u.buildingIndex .. "_" .. u.tierIndex
            local canAfford = coins >= u.cost
            if canAfford ~= iconAffordCache_[kid] then
                iconAffordCache_[kid] = canAfford
                local icon = iconCache_[kid]
                if icon then
                    if canAfford then
                        icon:SetStyle({
                            backgroundColor = { 60, 55, 30, 255 },
                            borderColor = { 255, 215, 0, 220 },
                            opacity = 1.0,
                        })
                    else
                        icon:SetStyle({
                            backgroundColor = { 35, 35, 50, 255 },
                            borderColor = { 60, 60, 80, 100 },
                            opacity = 0.5,
                        })
                    end
                end
            end
        end
    end

    for _, info in ipairs(clkVisible) do
        local kid = "cu_" .. info.index
        local canAfford = coins >= info.upgrade.baseCost
        if canAfford ~= iconAffordCache_[kid] then
            iconAffordCache_[kid] = canAfford
            local icon = iconCache_[kid]
            if icon then
                if canAfford then
                    icon:SetStyle({
                        backgroundColor = { 60, 55, 30, 255 },
                        borderColor = { 255, 215, 0, 220 },
                        opacity = 1.0,
                    })
                else
                    icon:SetStyle({
                        backgroundColor = { 35, 35, 50, 255 },
                        borderColor = { 60, 60, 80, 100 },
                        opacity = 0.5,
                    })
                end
            end
        end
    end
end

-- ============================================================================
-- 缓存构建
-- ============================================================================

local function CacheBuildingWidgets()
    buildingCache_ = {}
    if not uiRoot_ or not buildings_ then return end
    for i, b in ipairs(buildings_) do
        local cost = GameState.GetCost(b)
        local canAfford = GameState.coins >= cost
        buildingCache_[i] = {
            btn        = uiRoot_:FindById("bld_" .. b.id),
            costLabel  = uiRoot_:FindById("bld_cost_" .. b.id),
            countLabel = uiRoot_:FindById("bld_count_" .. b.id),
            lastCost   = cost,
            lastCount  = b.count,
            lastAfford = canAfford,
        }
    end
end

-- ============================================================================
-- 批量购买按钮行
-- ============================================================================

local COLOR_BTN_ACTIVE   = { 255, 200, 50, 255 }
local COLOR_BTN_INACTIVE = { 80, 80, 100, 255 }
local COLOR_TEXT_ACTIVE   = { 30, 30, 40, 255 }
local COLOR_TEXT_INACTIVE = { 180, 180, 200, 255 }

--- 刷新按钮高亮状态
local function RefreshAmountButtons()
    for _, amt in ipairs({ 1, 10, 100 }) do
        local btn = amountBtnCache_[amt]
        if btn then
            local active = (buyAmount_ == amt)
            btn:SetStyle({
                backgroundColor = active and COLOR_BTN_ACTIVE or COLOR_BTN_INACTIVE,
            })
            -- 更新文字颜色
            local label = btn:FindById("amtLabel_" .. amt)
            if label then
                label:SetFontColor(active and COLOR_TEXT_ACTIVE or COLOR_TEXT_INACTIVE)
            end
        end
    end
end

-- ============================================================================
-- 特殊建筑（小游戏入口）配置表 + 统一工厂函数
-- ============================================================================

--- 特殊建筑差异化配置
--- key = 建筑索引, value = 差异化样式/回调
local SPECIAL_BUILDING_CONFIGS = {
    [3]  = { emoji = "🌱", callback = "onOpenGarden",
             bg = { 35, 55, 40, 255 },  border = { 80, 160, 90, 150 },
             descColor = { 140, 160, 140, 200 }, countColor = { 180, 200, 180, 180 },
             buyBg = { 50, 80, 50, 255 }, buyBorder = { 100, 200, 100, 180 } },
    [4]  = { emoji = "⛏️", callback = "onOpenMining",
             bg = { 45, 38, 28, 255 },  border = { 180, 140, 60, 150 },
             descColor = { 170, 150, 120, 200 }, countColor = { 200, 180, 140, 180 },
             buyBg = { 65, 55, 35, 255 }, buyBorder = { 200, 160, 60, 180 } },
    [5]  = { emoji = "🏭", callback = "onOpenFactory",
             bg = { 35, 40, 55, 255 },  border = { 80, 130, 200, 150 },
             descColor = { 120, 150, 190, 200 }, countColor = { 160, 180, 210, 180 },
             buyBg = { 40, 55, 75, 255 }, buyBorder = { 90, 150, 220, 180 } },
    [6]  = { emoji = "📈", callback = "onOpenStockMarket",
             bg = { 30, 45, 55, 255 },  border = { 60, 140, 180, 150 },
             descColor = { 120, 160, 180, 200 }, countColor = { 160, 190, 210, 180 },
             buyBg = { 35, 60, 70, 255 }, buyBorder = { 80, 170, 200, 180 } },
    [7]  = { emoji = "🏛️", callback = "onOpenPantheon",
             bg = { 50, 42, 30, 255 },  border = { 180, 150, 60, 150 },
             descColor = { 160, 150, 120, 200 }, countColor = { 200, 190, 150, 180 },
             buyBg = { 70, 60, 30, 255 }, buyBorder = { 200, 170, 60, 180 } },
    [8]  = { emoji = "🔮", callback = "onOpenGrimoire",
             bg = { 38, 30, 55, 255 },  border = { 130, 90, 200, 150 },
             descColor = { 150, 130, 180, 200 }, countColor = { 180, 170, 210, 180 },
             buyBg = { 55, 40, 80, 255 }, buyBorder = { 150, 100, 220, 180 } },
    [9]  = { emoji = "🐫", callback = "onOpenShipment",
             bg = { 30, 45, 55, 255 },  border = { 60, 160, 180, 150 },
             descColor = { 120, 170, 180, 200 }, countColor = { 150, 195, 210, 180 },
             buyBg = { 35, 60, 70, 255 }, buyBorder = { 70, 180, 200, 180 } },
    [11] = { emoji = "🌀", callback = "onOpenECommerce",
             bg = { 40, 30, 55, 255 },  border = { 150, 90, 220, 150 },
             descColor = { 150, 120, 190, 200 }, countColor = { 170, 150, 210, 180 },
             buyBg = { 50, 35, 70, 255 }, buyBorder = { 150, 90, 220, 180 } },
}

--- 通用特殊建筑行创建函数（配置驱动，替代 8 个独立函数）
---@param item table 建筑数据
---@param buildingIndex number 建筑索引
---@param cfg table SPECIAL_BUILDING_CONFIGS[index]
local function CreateSpecialBuildingItem(item, buildingIndex, cfg)
    local amt = buyAmount_
    local cost = GameState.GetBulkCost(item, amt)
    local canAfford = GameState.coins >= cost
    local F = GameState.FormatNumber
    local tooltipFn = BuildingTooltipConfig(item, buildingIndex)
    local cbName = cfg.callback

    return UI.Panel {
        id = "bld_" .. item.id,
        width = "100%", flexDirection = "row", alignItems = "center",
        padding = 8, gap = 8, borderRadius = 8, borderWidth = 1,
        backgroundColor = cfg.bg,
        borderColor = cfg.border,
        pointerEvents = "auto",
        onTap = function()
            if callbacks_ and callbacks_[cbName] then
                callbacks_[cbName]()
            end
        end,
        onLongPressStart = function(event) Tooltip.Show(tooltipFn, event.y) end,
        onLongPressEnd = function() Tooltip.Hide() end,
        onPointerEnter = function(event) Tooltip.Show(tooltipFn, event.y) end,
        onPointerLeave = function() Tooltip.Hide() end,
        children = {
            UI.Panel {
                width = 36, height = 36,
                backgroundImage = item.iconImage,
                backgroundFit = "contain",
            },
            UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = {
                        UI.Label { text = item.name, fontSize = 13, fontColor = { 230, 230, 240, 255 } },
                        UI.Label { text = cfg.emoji, fontSize = 10 },
                    },
                },
                UI.Label { text = item.desc, fontSize = 10, fontColor = cfg.descColor },
            } },
            UI.Panel { alignItems = "flex-end", gap = 2, children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 2,
                    paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
                    borderRadius = 6,
                    backgroundColor = canAfford and cfg.buyBg or { 40, 40, 55, 255 },
                    borderWidth = 1,
                    borderColor = canAfford and cfg.buyBorder or { 60, 60, 80, 100 },
                    pointerEvents = "auto",
                    onTap = function(self, event)
                        if event and event.stopPropagation then event:stopPropagation() end
                        if callbacks_ and callbacks_.onBuyBuilding then
                            callbacks_.onBuyBuilding(buildingIndex)
                        end
                    end,
                    children = {
                        UI.Panel { width = 14, height = 14,
                            backgroundImage = "image/金币.png", backgroundFit = "contain" },
                        UI.Label { id = "bld_cost_" .. item.id,
                            text = F(cost), fontSize = 12,
                            fontColor = canAfford and COLOR_COST_GREEN or COLOR_COST_RED },
                    },
                },
                UI.Label { id = "bld_count_" .. item.id,
                    text = "x" .. item.count, fontSize = 11,
                    fontColor = cfg.countColor },
            } },
        },
    }
end

--- 重建建筑列表（切换购买数量后调用）
local function RebuildBuildingList()
    if not uiRoot_ or not buildings_ then return end
    local container = uiRoot_:FindById("buildingListInner")
    if not container then return end
    container:RemoveAllChildren()
    for i, b in ipairs(buildings_) do
        local cfg = SPECIAL_BUILDING_CONFIGS[i]
        if cfg and b.count >= 1 and callbacks_ and callbacks_[cfg.callback] then
            container:AddChild(CreateSpecialBuildingItem(b, i, cfg))
        else
            container:AddChild(CreateBuildingItem(b, "bld_", function(self)
                if callbacks_ then callbacks_.onBuyBuilding(i) end
            end, i))
        end
    end
    CacheBuildingWidgets()
end

--- 创建购买数量选择器行
local function CreateAmountBar()
    local buttons = {}
    -- 一键购买建筑按钮（直接操作，不是模式切换）
    local buyAllBldBtn = UI.Panel {
        id = "amtBtn_buyAll",
        flex = 1, height = 26,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 220, 160, 30, 255 },
        borderRadius = 4,
        pointerEvents = "auto",
        onPointerDown = function(self)
            if callbacks_ and callbacks_.onBuyAllBuildings then
                callbacks_.onBuyAllBuildings()
            end
        end,
        children = {
            UI.Label {
                text = "一键购买",
                fontSize = 12,
                fontColor = { 30, 30, 30, 255 },
            },
        },
    }
    buttons[#buttons + 1] = buyAllBldBtn
    -- 数量模式选择 x1 / x10 / x100
    for _, amt in ipairs({ 1, 10, 100 }) do
        local active = (buyAmount_ == amt)
        local label = "x" .. amt
        local btn = UI.Panel {
            id = "amtBtn_" .. amt,
            flex = 1, height = 26,
            justifyContent = "center", alignItems = "center",
            backgroundColor = active and COLOR_BTN_ACTIVE or COLOR_BTN_INACTIVE,
            borderRadius = 4,
            pointerEvents = "auto",
            onPointerDown = function(self)
                if buyAmount_ ~= amt then
                    buyAmount_ = amt
                    RefreshAmountButtons()
                    RebuildBuildingList()
                end
            end,
            children = {
                UI.Label {
                    id = "amtLabel_" .. amt,
                    text = label,
                    fontSize = 12,
                    fontColor = active and COLOR_TEXT_ACTIVE or COLOR_TEXT_INACTIVE,
                },
            },
        }
        amountBtnCache_[amt] = btn
        buttons[#buttons + 1] = btn
    end
    return UI.Panel {
        id = "amountBar",
        width = "100%",
        flexDirection = "row",
        gap = 4,
        paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
        children = buttons,
    }
end

-- ============================================================================
-- 创建 & 初始化
-- ============================================================================

function ShopPanel.Create(buildings, clickUpgrades, callbacks, bldUpgrades)
    buildings_ = buildings
    clickUpgrades_ = clickUpgrades
    callbacks_ = callbacks
    buildingUpgrades_ = bldUpgrades

    local buildingItems = {}

    for i, b in ipairs(buildings) do
        local cfg = SPECIAL_BUILDING_CONFIGS[i]
        if cfg and b.count >= 1 and callbacks[cfg.callback] then
            buildingItems[#buildingItems + 1] = CreateSpecialBuildingItem(b, i, cfg)
        else
            buildingItems[#buildingItems + 1] = CreateBuildingItem(b, "bld_", function(self)
                callbacks.onBuyBuilding(i)
            end, i)
        end
    end

    -- 安全区右侧偏移（背景延伸到边缘，内容向内缩进）
    local safeInsets = UI.GetSafeAreaInsets()
    local safeRight = safeInsets.right

    return UI.Panel {
        id = "shopPanel", width = "30%", flexDirection = "column",
        backgroundColor = { 30, 30, 45, 255 },
        borderColor = { 255, 200, 50, 40 },
        borderWidth = { 0, 0, 0, 1 },
        paddingRight = safeRight,
        children = {
            -- 一键购买升级按钮行
            UI.Panel {
                id = "buyAllRow",
                width = "100%",
                flexDirection = "row",
                paddingLeft = 8, paddingRight = 8, paddingTop = 6, paddingBottom = 2,
                children = {
                    UI.Panel {
                        id = "buyAllBtn",
                        paddingLeft = 16, paddingRight = 16, height = 32,
                        justifyContent = "center", alignItems = "center",
                        backgroundColor = { 220, 160, 30, 255 },
                        borderRadius = 6,
                        pointerEvents = "auto",
                        onPointerDown = function(self)
                            if callbacks_ and callbacks_.onBuyAll then
                                callbacks_.onBuyAll()
                            end
                        end,
                        children = {
                            UI.Label {
                                text = "一键购买升级",
                                fontSize = 14,
                                fontColor = { 30, 30, 30, 255 },
                            },
                        },
                    },
                },
            },
            -- 升级图标栏（固定在顶部，不滚动）
            UI.Panel {
                id = "upgradeBar",
                width = "100%",
                minHeight = ICON_SIZE + 8,
                padding = 8,
                paddingBottom = 2,
            },
            -- 购买数量选择器（x1 / x10 / x100）
            CreateAmountBar(),
            -- 建筑列表（可滚动）
            UI.ScrollView {
                id = "shopContent", flex = 1, width = "100%",
                children = {
                    UI.Panel { id = "buildingListInner", width = "100%", padding = 8, paddingTop = 4, gap = 6, children = buildingItems },
                },
            },
        },
    }
end

function ShopPanel.Init(root, buildings, clickUpgrades, bldUpgrades)
    buildings_ = buildings
    clickUpgrades_ = clickUpgrades
    buildingUpgrades_ = bldUpgrades
    uiRoot_ = root

    -- 同步小游戏解锁状态（存档加载后建筑 count 可能已 >= 1）
    minigameUnlocked_ = {}
    for idx in pairs(MINIGAME_INDICES) do
        local b = buildings_[idx]
        if b and b.count >= 1 then
            minigameUnlocked_[idx] = true
        end
    end

    -- 重建建筑列表以反映当前解锁状态（存档加载后 count 可能已变化）
    RebuildBuildingList()

    CacheBuildingWidgets()

    upgradeContainer_ = root:FindById("upgradeBar")
    if upgradeContainer_ then
        BuildUnifiedIconBar(upgradeContainer_)
    end
end

-- ============================================================================
-- 增量刷新
-- ============================================================================

function ShopPanel.Refresh()
    if not buildings_ then return end

    -- 检测小游戏建筑解锁状态变化（count 从 0 变 >=1），触发列表重建
    local needRebuild = false
    for idx in pairs(MINIGAME_INDICES) do
        local b = buildings_[idx]
        if b then
            local wasUnlocked = minigameUnlocked_[idx]
            local nowUnlocked = b.count >= 1
            if nowUnlocked and not wasUnlocked then
                minigameUnlocked_[idx] = true
                needRebuild = true
            end
        end
    end
    if needRebuild then
        RebuildBuildingList()
    end

    local F = GameState.FormatNumber
    local coins = GameState.coins
    local amt = buyAmount_

    -- 刷新升级图标栏
    RefreshIconBar()

    -- 刷新建筑列表
    for i, b in ipairs(buildings_) do
        local c = buildingCache_[i]
        if not c or not c.btn then goto continue end

        local realAmt = amt
        local cost = GameState.GetBulkCost(b, realAmt)
        local canAfford = coins >= cost

        if b.count ~= c.lastCount or cost ~= c.lastCost then
            c.lastCount = b.count
            if c.countLabel then c.countLabel:SetText("x" .. b.count) end
            c.lastCost = cost
            if c.costLabel then c.costLabel:SetText(F(cost)) end
            c.lastAfford = canAfford
            if c.costLabel then
                c.costLabel:SetFontColor(canAfford and COLOR_COST_GREEN or COLOR_COST_RED)
            end
            -- 特殊建筑保持自定义颜色，普通建筑用通用颜色
            local cfg = SPECIAL_BUILDING_CONFIGS[i]
            if cfg and b.count >= 1 then
                -- 特殊建筑行颜色不随 afford 变化，始终使用配置色
            else
                c.btn:SetStyle({
                    backgroundColor = canAfford and COLOR_AFFORD_BG or COLOR_UNAFFORD_BG,
                    borderColor = canAfford and COLOR_AFFORD_BORDER or COLOR_UNAFFORD_BORDER,
                })
            end
        elseif canAfford ~= c.lastAfford then
            c.lastAfford = canAfford
            if c.costLabel then
                c.costLabel:SetFontColor(canAfford and COLOR_COST_GREEN or COLOR_COST_RED)
            end
            local cfg = SPECIAL_BUILDING_CONFIGS[i]
            if cfg and b.count >= 1 then
                -- 特殊建筑行颜色不随 afford 变化
            else
                c.btn:SetStyle({
                    backgroundColor = canAfford and COLOR_AFFORD_BG or COLOR_UNAFFORD_BG,
                    borderColor = canAfford and COLOR_AFFORD_BORDER or COLOR_UNAFFORD_BORDER,
                })
            end
        end

        ::continue::
    end
end

--- 获取当前购买数量
---@return number
function ShopPanel.GetBuyAmount()
    return buyAmount_
end

return ShopPanel
