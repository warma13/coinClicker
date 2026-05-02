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

-- ======== 升级图标缓存 ========
local iconCache_ = {}  -- { [id_string] = widget }

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

local function CreateBuildingItem(item, idPrefix, onBuy, buildingIndex)
    local amt = buyAmount_
    local cost = GameState.GetBulkCost(item, amt)
    local canAfford = GameState.coins >= cost
    local F = GameState.FormatNumber
    return UI.Panel {
        id = idPrefix .. item.id,
        width = "100%", flexDirection = "row", alignItems = "center",
        padding = 8, gap = 8, borderRadius = 8, borderWidth = 1,
        backgroundColor = canAfford and COLOR_AFFORD_BG or COLOR_UNAFFORD_BG,
        borderColor = canAfford and COLOR_AFFORD_BORDER or COLOR_UNAFFORD_BORDER,
        pointerEvents = "auto", onPointerDown = onBuy,
        onPointerEnter = function(event)
            Tooltip.Show(function()
                local tipAmt = buyAmount_
                local c = GameState.GetBulkCost(item, tipAmt)
                local afford = GameState.coins >= c
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
            end, event.y)
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
                UI.Panel { flexDirection = "row", alignItems = "center", gap = 2, children = {
                    UI.Panel { width = 14, height = 14,
                        backgroundImage = "image/金币.png", backgroundFit = "contain" },
                    UI.Label { id = idPrefix .. "cost_" .. item.id,
                        text = F(cost), fontSize = 12,
                        fontColor = canAfford and COLOR_COST_GREEN or COLOR_COST_RED },
                } },
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
        onPointerDown = (not bought) and onBuy or nil,
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
        onPointerDown = onBuy,
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

    -- 重建图标缓存
    iconCache_ = {}
    if uiRoot_ then
        for _, u in ipairs(bldVisible) do
            local kid = "bu_" .. u.buildingIndex .. "_" .. u.tierIndex
            iconCache_[kid] = uiRoot_:FindById(kid)
        end
        for _, info in ipairs(clkVisible) do
            local kid = "cu_" .. info.index
            iconCache_[kid] = uiRoot_:FindById(kid)
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
            local canAfford = coins >= u.cost
            local icon = iconCache_["bu_" .. u.buildingIndex .. "_" .. u.tierIndex]
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

    for _, info in ipairs(clkVisible) do
        local canAfford = coins >= info.upgrade.baseCost
        local icon = iconCache_["cu_" .. info.index]
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

--- 重建建筑列表（切换购买数量后调用）
local function RebuildBuildingList()
    if not uiRoot_ or not buildings_ then return end
    local container = uiRoot_:FindById("buildingListInner")
    if not container then return end
    container:RemoveAllChildren()
    for i, b in ipairs(buildings_) do
        container:AddChild(CreateBuildingItem(b, "bld_", function(self)
            if callbacks_ then callbacks_.onBuyBuilding(i) end
        end, i))
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
        buildingItems[#buildingItems + 1] = CreateBuildingItem(b, "bld_", function(self)
            callbacks.onBuyBuilding(i)
        end, i)
    end

    return UI.Panel {
        id = "shopPanel", width = "30%", flexDirection = "column",
        backgroundColor = { 30, 30, 45, 255 },
        borderColor = { 255, 200, 50, 40 },
        borderWidth = { 0, 0, 0, 1 },
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
            c.btn:SetStyle({
                backgroundColor = canAfford and COLOR_AFFORD_BG or COLOR_UNAFFORD_BG,
                borderColor = canAfford and COLOR_AFFORD_BORDER or COLOR_UNAFFORD_BORDER,
            })
        elseif canAfford ~= c.lastAfford then
            c.lastAfford = canAfford
            if c.costLabel then
                c.costLabel:SetFontColor(canAfford and COLOR_COST_GREEN or COLOR_COST_RED)
            end
            c.btn:SetStyle({
                backgroundColor = canAfford and COLOR_AFFORD_BG or COLOR_UNAFFORD_BG,
                borderColor = canAfford and COLOR_AFFORD_BORDER or COLOR_UNAFFORD_BORDER,
            })
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
