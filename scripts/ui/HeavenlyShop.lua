-- ============================================================================
-- ui/HeavenlyShop.lua
-- 经验商店（全屏覆盖式弹窗）
-- 使用经验值购买永久升级
-- 使用 VirtualList 虚拟化列表
-- 使用 AddChild/RemoveChild 控制显隐
-- ============================================================================

local UI = require("urhox-libs/UI")
local AD = require("config.AscensionDefs")
local GameState = require("core.GameState")
local Tooltip = require("ui.Tooltip")

local HS = {}

-- ======== 引用 ========
local uiRoot_ = nil
local panel_ = nil
local virtualList_ = nil
local chipRow_ = nil
local chipIcon_ = nil
local chipCountText_ = nil
local chipBonusText_ = nil
local visible_ = false

-- 外部注入
local ascensionManager_ = nil
local onBuyUpgrade_ = nil     -- function(upgradeId)

-- ======== 增量刷新缓存 ========
local lastChipText_ = ""
local lastDataFP_ = ""

-- ======== 行常量 ========
local HEADER_HEIGHT = 30
local ITEM_HEIGHT = 56

-- ======== 升级分组定义 ========
local GROUPS = {
    { title = "品牌传承链", ids = { "legacy", "heavenlyChipSecret", "heavenlyCookieStand", "heavenlyBakery", "heavenlyKey" } },
    { title = "产量加成", ids = { "heavenlyCookies", "tinOfBiscuits", "boxOfBiscuits", "boxOfMacarons", "industrialKey", "globalOptimize" } },
    { title = "老关系", ids = { "starterKit", "starterKitchen" } },
    { title = "商机加成", ids = { "heavenlyLuck", "lastingFortune" } },
    { title = "签单 & 顾问", ids = { "santasHelpers", "santasMilk" } },
    { title = "自动化", ids = { "autoClick" } },
    { title = "规模经济", ids = { "costReduce", "purchaseOpt" } },
    { title = "AI 合伙人", ids = { "howToBakeDragon" } },
    { title = "周期切换", ids = { "seasonSwitcher" } },
    { title = "核心资产槽", ids = { "permSlot1", "permSlot2" } },

}

-- ======== 扁平化数据 ========
-- flatData_[i] = { type="header", title="..." }
--             或 { type="item", status={def,bought,unlocked,canAfford} }
local flatData_ = {}

-- 统一行高：header 和 item 不同高度，VirtualList 要求统一行高
-- 这里统一使用 ITEM_HEIGHT 作为行高
local ROW_HEIGHT = ITEM_HEIGHT

-- ============================================================================
-- 重建扁平数据
-- ============================================================================

local function RebuildFlatData()
    flatData_ = {}
    if not ascensionManager_ then return end

    local statusList = ascensionManager_.GetUpgradeStatus()
    local statusById = {}
    for _, s in ipairs(statusList) do
        statusById[s.def.id] = s
    end

    for _, group in ipairs(GROUPS) do
        -- 标题行
        flatData_[#flatData_ + 1] = {
            type = "header",
            title = group.title,
        }
        -- 升级行
        for _, id in ipairs(group.ids) do
            local s = statusById[id]
            if s then
                flatData_[#flatData_ + 1] = {
                    type = "item",
                    status = s,
                }
            end
        end
    end
end

-- ============================================================================
-- VirtualList createItem / bindItem
-- ============================================================================

local function CreateRowWidget()
    -- 标题模式
    local headerLabel = UI.Label {
        text = "",
        fontSize = 12,
        fontColor = { 170, 160, 200, 200 },
    }
    local headerRow = UI.Panel {
        width = "100%", height = ROW_HEIGHT,
        position = "absolute",
        justifyContent = "flex-end",
        paddingBottom = 4,
        children = { headerLabel },
    }

    -- 升级行模式
    local iconPanel = UI.Panel {
        width = 32, height = 32,
        backgroundFit = "contain",
    }
    local nameLabel = UI.Label { text = "", fontSize = 13 }
    local descLabel = UI.Label { text = "", fontSize = 10,
        fontColor = { 150, 140, 170, 200 } }
    local statusContainer = UI.Panel {}

    local itemRow = UI.Panel {
        width = "100%", height = ROW_HEIGHT,
        position = "absolute",
        flexDirection = "row", alignItems = "center",
        padding = 10, gap = 8, borderRadius = 8, borderWidth = 1,
        backgroundColor = { 35, 30, 50, 255 },
        borderColor = { 100, 80, 140, 120 },
        children = {
            iconPanel,
            UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                nameLabel,
                descLabel,
            }},
            statusContainer,
        },
    }

    -- 主容器
    local row = UI.Panel {
        width = "100%",
        height = ROW_HEIGHT,
    }
    row:AddChild(headerRow)
    row:AddChild(itemRow)

    row._headerRow = headerRow
    row._headerLabel = headerLabel
    row._itemRow = itemRow
    row._iconPanel = iconPanel
    row._nameLabel = nameLabel
    row._descLabel = descLabel
    row._statusContainer = statusContainer
    row._lastStatusType = nil

    return row
end

local function BindRowWidget(widget, data, index)
    if data.type == "header" then
        widget._headerRow:SetVisible(true)
        widget._itemRow:SetVisible(false)
        widget._headerLabel:SetText(data.title)
        return
    end

    -- item 模式
    widget._headerRow:SetVisible(false)
    widget._itemRow:SetVisible(true)

    local s = data.status
    local u = s.def

    local bgColor, borderColor, clickable

    if s.bought then
        bgColor = { 25, 45, 30, 255 }
        borderColor = { 80, 180, 80, 150 }
        clickable = false
    elseif s.unlocked then
        if s.canAfford then
            bgColor = { 50, 40, 65, 255 }
            borderColor = { 200, 170, 255, 200 }
        else
            bgColor = { 35, 30, 50, 255 }
            borderColor = { 100, 80, 140, 120 }
        end
        clickable = s.canAfford
    else
        bgColor = { 20, 18, 30, 200 }
        borderColor = { 40, 35, 55, 100 }
        clickable = false
    end

    widget._itemRow:SetStyle({
        backgroundColor = bgColor,
        borderColor = borderColor,
        opacity = (s.bought or s.unlocked) and 1.0 or 0.35,
    })

    widget._iconPanel:SetStyle({
        backgroundImage = u.iconImage or "image/icon_管理经验.png",
        opacity = (s.bought or s.unlocked) and 1.0 or 0.4,
    })

    widget._nameLabel:SetText(u.name)
    widget._nameLabel:SetFontColor(s.bought and { 100, 200, 100, 255 }
        or (s.unlocked and { 230, 220, 255, 255 }
        or { 100, 95, 120, 200 }))

    widget._descLabel:SetText(u.desc or "")

    -- 状态区域
    local statusType
    if s.bought then
        statusType = "bought"
    elseif s.unlocked then
        statusType = "unlocked:" .. (s.canAfford and "Y" or "N")
    else
        statusType = "locked:" .. (u.prereq or "")
    end

    if statusType ~= widget._lastStatusType then
        widget._lastStatusType = statusType
        widget._statusContainer:RemoveAllChildren()

        if s.bought then
            widget._statusContainer:AddChild(
                UI.Panel {
                    flexDirection = "row", alignItems = "center", justifyContent = "center",
                    paddingLeft = 6, paddingRight = 6, paddingTop = 3, paddingBottom = 3,
                    borderRadius = 6,
                    backgroundColor = { 40, 70, 45, 200 },
                    borderWidth = 1, borderColor = { 80, 180, 80, 120 },
                    children = {
                        UI.Label { text = "✓ 已购买", fontSize = 11,
                            fontColor = { 100, 200, 100, 200 }, textAlign = "center" },
                    },
                }
            )
        elseif s.unlocked then
            local upgradeId = u.id
            widget._statusContainer:AddChild(
                UI.Panel {
                    flexDirection = "row", alignItems = "center", justifyContent = "center",
                    paddingLeft = 6, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
                    borderRadius = 6, gap = 4,
                    backgroundColor = clickable and { 80, 50, 120, 255 } or { 50, 45, 60, 200 },
                    borderWidth = 1,
                    borderColor = clickable and { 180, 130, 255, 200 } or { 70, 60, 90, 120 },
                    pointerEvents = clickable and "auto" or "none",
                    onTap = clickable and function()
                        if onBuyUpgrade_ then
                            onBuyUpgrade_(upgradeId)
                            HS.Refresh()
                        end
                    end or nil,
                    onLongPressStart = clickable and function(event)
                        local tooltipFn = function()
                            return {
                                title = u.name,
                                desc = u.desc or "",
                                cost = GameState.FormatNumber(u.cost) .. " 经验",
                            }
                        end
                        Tooltip.Show(tooltipFn, event.y)
                    end or nil,
                    onLongPressEnd = function() Tooltip.Hide() end,
                    children = {
                        UI.Panel { width = 18, height = 18,
                            backgroundImage = "image/icon_管理经验.png", backgroundFit = "contain",
                            opacity = clickable and 1.0 or 0.4 },
                        UI.Label { text = GameState.FormatNumber(u.cost), fontSize = 12,
                            fontColor = { 255, 255, 255, 240 } },
                    },
                }
            )
        else
            -- 锁定
            local lockText = "需要: " .. (u.prereq or "")
            if u.prereq then
                local prereqDef = AD.FindById(u.prereq)
                if prereqDef then
                    lockText = "需要: " .. prereqDef.name
                end
            end
            widget._statusContainer:AddChild(
                UI.Label { text = lockText, fontSize = 11,
                    fontColor = { 120, 110, 140, 180 } }
            )
        end
    end
end

-- ============================================================================
-- 内部：构建面板
-- ============================================================================

local function BuildPanel()
    chipIcon_ = UI.Panel {
        width = 14, height = 14,
        backgroundImage = "image/icon_管理经验.png",
        backgroundFit = "contain",
    }
    chipCountText_ = UI.Label {
        text = "0",
        fontSize = 13,
        fontColor = { 255, 230, 180, 220 },
    }
    chipBonusText_ = UI.Label {
        text = "",
        fontSize = 13,
        fontColor = { 255, 230, 180, 220 },
    }
    chipRow_ = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        gap = 3,
        marginBottom = 8,
        children = {
            UI.Label { text = "经验值:", fontSize = 13, fontColor = { 255, 230, 180, 220 } },
            chipIcon_,
            chipCountText_,
            chipBonusText_,
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
        itemGap = 6,
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
                        backgroundImage = "image/侧栏_经验_20260414105524.png",
                        backgroundFit = "contain" },
                    UI.Label {
                        text = "经验商店",
                        fontSize = 18,
                        fontColor = { 220, 200, 255, 255 },
                    },
                },
            },

            -- 经验值信息
            chipRow_,

            -- VirtualList 替代 ScrollView
            virtualList_,
        },
    }
end

-- ============================================================================
-- 公共接口
-- ============================================================================

function HS.Init(root, manager, buyCb)
    uiRoot_ = root
    ascensionManager_ = manager
    onBuyUpgrade_ = buyCb
    BuildPanel()
end

function HS.Show()
    if not panel_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    uiRoot_:AddChild(panel_)
    lastChipText_ = ""
    lastDataFP_ = ""
    HS.Refresh()
end

function HS.Hide()
    if not panel_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(panel_)
end

function HS.Toggle()
    if visible_ then HS.Hide() else HS.Show() end
end

function HS.IsVisible() return visible_ end

-- ============================================================================
-- 刷新（增量）
-- ============================================================================

function HS.Refresh()
    if not visible_ or not ascensionManager_ then return end

    -- 更新经验值信息
    if chipCountText_ and chipBonusText_ then
        local chips = ascensionManager_.GetHeavenlyChips()
        local prestige = math.floor(ascensionManager_.GetPrestigeLevel())
        local ratio = ascensionManager_.GetPrestigeUnlockRatio()
        local bonus = math.floor(prestige * ratio)
        local F = GameState.FormatNumber
        local countText = F(chips) .. " | 商业声望 Lv." .. F(prestige)
        local bonusText = bonus > 0 and (" (+" .. F(bonus) .. "% CpS)") or ""
        local fp = countText .. bonusText
        if fp ~= lastChipText_ then
            chipCountText_:SetText(countText)
            chipBonusText_:SetText(bonusText)
            lastChipText_ = fp
        end
    end

    if not virtualList_ then return end

    -- 生成数据指纹
    local statusList = ascensionManager_.GetUpgradeStatus()
    local chips = ascensionManager_.GetHeavenlyChips()
    local parts = {}
    for i, s in ipairs(statusList) do
        local state = s.bought and "B" or (s.unlocked and "U" or "L")
        parts[i] = s.def.id .. state .. (s.canAfford and "A" or "")
    end
    parts[#parts + 1] = "C:" .. tostring(chips)
    local dataFP = table.concat(parts, "|")

    if dataFP ~= lastDataFP_ then
        lastDataFP_ = dataFP
        local prevCount = #flatData_
        RebuildFlatData()
        if prevCount == #flatData_ and prevCount > 0 then
            -- 行数不变：就地更新数据，保持滚动位置
            virtualList_.props.data = flatData_
            virtualList_:Refresh()
        else
            -- 首次加载或行数变化：完整重建
            virtualList_:SetData(flatData_)
        end
    end
end

return HS
