-- ============================================================================
-- ui/AchievementPanel.lua
-- 里程碑列表面板（覆盖式弹窗）
-- 使用 VirtualList 虚拟化网格布局，行数据扁平化：分类标题 + 图标网格行
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local AchievementDefs = require("config.AchievementDefs")
local KittenUpgrades = require("config.KittenUpgrades")
local Tooltip = require("ui.Tooltip")

local AchievementPanel = {}

-- ======== 引用 ========
local uiRoot_ = nil
local panel_ = nil
local statsLabel_ = nil
local milkLabel_ = nil
local kittenLabel_ = nil
local virtualList_ = nil
local kittenContainer_ = nil
local visible_ = false

-- 外部注入
local achievementManager_ = nil
local onBuyKitten_ = nil

-- 增量刷新缓存
local lastStatsFP_ = ""
local lastKittenFP_ = ""
local lastAchFP_ = ""
local kittenRowCache_ = {}

-- ======== 颜色 ========
local COLOR_UNLOCKED_BG       = { 50, 45, 25, 255 }
local COLOR_LOCKED_BG         = { 30, 30, 40, 255 }
local COLOR_UNLOCKED_BORDER   = { 255, 200, 50, 120 }
local COLOR_LOCKED_BORDER     = { 50, 50, 65, 100 }

-- ======== 网格常量 ========
local GRID_COLS = 8
local ICON_SIZE = 40
local ICON_GAP = 4
local ROW_HEIGHT = ICON_SIZE + ICON_GAP  -- 44px：统一行高（标题行和图标行都用这个）

-- ======== 扁平化数据 ========
-- flatData_[i] = { type="header", label="...", count="3/20" }
--             或 { type="icons", items={ {achievement, unlocked}, ... } }
local flatData_ = {}

-- ============================================================================
-- 扁平化：将成就数据按分类拆成行数据
-- ============================================================================

local CATEGORIES = {
    { key = "production",  label = "营收里程碑" },
    { key = "building",    label = "产业里程碑" },
    { key = "click",       label = "签单里程碑" },
    { key = "lucky",       label = "商机里程碑" },
    { key = "upgrade",     label = "升级里程碑" },
}

local function RebuildFlatData()
    flatData_ = {}
    if not achievementManager_ then return end

    local allStatus = achievementManager_.GetAllWithStatus()

    for _, cat in ipairs(CATEGORIES) do
        local items = {}
        for _, entry in ipairs(allStatus) do
            if entry.achievement.category == cat.key then
                items[#items + 1] = entry
            end
        end

        if #items > 0 then
            local unlockedInCat = 0
            for _, e in ipairs(items) do
                if e.unlocked then unlockedInCat = unlockedInCat + 1 end
            end

            -- 标题行
            flatData_[#flatData_ + 1] = {
                type = "header",
                label = cat.label,
                count = unlockedInCat .. "/" .. #items,
            }

            -- 按 GRID_COLS 切分为多行
            for row = 1, math.ceil(#items / GRID_COLS) do
                local rowItems = {}
                local startIdx = (row - 1) * GRID_COLS + 1
                local endIdx = math.min(row * GRID_COLS, #items)
                for i = startIdx, endIdx do
                    rowItems[#rowItems + 1] = items[i]
                end
                flatData_[#flatData_ + 1] = {
                    type = "icons",
                    items = rowItems,
                }
            end
        end
    end
end

-- ============================================================================
-- VirtualList createItem / bindItem
-- ============================================================================

--- 创建可复用行 widget（包含标题和图标两种模式的子元素）
local function CreateRowWidget()
    -- 标题模式元素
    local headerLabel = UI.Label {
        text = "",
        fontSize = 12,
        fontColor = { 180, 170, 120, 200 },
    }

    -- 图标模式：预创建 GRID_COLS 个图标槽位
    local iconSlots = {}
    for c = 1, GRID_COLS do
        local iconImage = UI.Panel {
            width = "100%", height = "100%",
            position = "absolute",
            backgroundFit = "cover",
            pointerEvents = "none",
            borderRadius = 5,
        }
        local iconEmoji = UI.Label {
            text = "",
            fontSize = 22,
            textAlign = "center",
            width = "100%", height = "100%",
            position = "absolute",
            justifyContent = "center",
            pointerEvents = "none",
        }
        local slot = UI.Panel {
            width = ICON_SIZE, height = ICON_SIZE,
            justifyContent = "center", alignItems = "center",
            borderRadius = 6, borderWidth = 1,
            backgroundColor = COLOR_LOCKED_BG,
            borderColor = COLOR_LOCKED_BORDER,
            overflow = "hidden",
            pointerEvents = "auto",
            children = { iconImage, iconEmoji },
        }
        iconSlots[c] = {
            panel = slot,
            iconImage = iconImage,
            iconEmoji = iconEmoji,
        }
    end

    -- 图标容器（absolute 定位，避免与 headerRow 互相挤占空间）
    local iconsRow = UI.Panel {
        width = "100%",
        height = ROW_HEIGHT,
        position = "absolute",
        flexDirection = "row",
        alignItems = "center",
        gap = ICON_GAP,
    }
    for c = 1, GRID_COLS do
        iconsRow:AddChild(iconSlots[c].panel)
    end

    -- 标题容器（absolute 定位）
    local headerRow = UI.Panel {
        width = "100%",
        height = ROW_HEIGHT,
        position = "absolute",
        justifyContent = "flex-end",
        paddingBottom = 2,
        children = { headerLabel },
    }

    -- 主容器
    local row = UI.Panel {
        width = "100%",
        height = ROW_HEIGHT,
    }
    row:AddChild(headerRow)
    row:AddChild(iconsRow)

    -- 存储引用
    row._headerRow = headerRow
    row._headerLabel = headerLabel
    row._iconsRow = iconsRow
    row._iconSlots = iconSlots

    return row
end

--- 绑定数据到行 widget
local function BindRowWidget(widget, data, index)
    if data.type == "header" then
        -- 显示标题，隐藏图标
        widget._headerRow:SetVisible(true)
        widget._iconsRow:SetVisible(false)
        widget._headerLabel:SetText(data.label .. "  (" .. data.count .. ")")
    else
        -- 显示图标，隐藏标题
        widget._headerRow:SetVisible(false)
        widget._iconsRow:SetVisible(true)

        local items = data.items
        for c = 1, GRID_COLS do
            local slot = widget._iconSlots[c]
            local entry = items[c]
            if entry then
                slot.panel:SetVisible(true)
                local a = entry.achievement
                local isUnlocked = entry.unlocked

                local bgColor = isUnlocked and COLOR_UNLOCKED_BG or COLOR_LOCKED_BG

                -- 品质边框颜色
                local tier = a.tier or 1
                local tierColors = AchievementDefs.TIER_COLORS
                local tierColor = tierColors[tier] or tierColors[1]

                local borderColor, borderWidth
                if isUnlocked then
                    borderColor = tierColor
                    borderWidth = tier >= 5 and 3 or (tier >= 3 and 2 or 1)
                else
                    borderColor = COLOR_LOCKED_BORDER
                    borderWidth = 1
                end

                slot.panel:SetStyle({
                    backgroundColor = bgColor,
                    borderColor = borderColor,
                    borderWidth = borderWidth,
                    opacity = isUnlocked and 1.0 or 0.4,
                })

                -- 图标内容
                if not isUnlocked then
                    slot.iconImage:SetStyle({ backgroundImage = "image/问号.png" })
                    slot.iconImage:SetVisible(true)
                    slot.iconEmoji:SetVisible(false)
                elseif a.iconImage then
                    slot.iconImage:SetStyle({ backgroundImage = a.iconImage })
                    slot.iconImage:SetVisible(true)
                    slot.iconEmoji:SetVisible(false)
                else
                    slot.iconEmoji:SetText(a.icon or "?")
                    slot.iconEmoji:SetVisible(true)
                    slot.iconImage:SetVisible(false)
                end

                -- Tooltip 事件
                local achId = a.id
                local achRef = a
                slot.panel:SetStyle({
                    onPointerEnter = function(event, w)
                        local layout = w:GetAbsoluteLayout()
                        local centerX = layout.x + layout.w / 2
                        local topY = layout.y
                        Tooltip.Show(function()
                            local nowUnlocked = achievementManager_ and achievementManager_.IsUnlocked(achId) or isUnlocked
                            return {
                                icon = nowUnlocked and achRef.icon or nil,
                                iconImage = nowUnlocked and achRef.iconImage or "image/问号.png",
                                title = nowUnlocked and achRef.name or "???",
                                desc = nowUnlocked and achRef.desc or nil,
                                action = nowUnlocked and "✓ 已达成" or "未达成",
                                actionColor = nowUnlocked and "green" or "gray",
                            }
                        end, topY, centerX)
                    end,
                    onPointerLeave = function()
                        Tooltip.Hide()
                    end,
                })
            else
                slot.panel:SetVisible(false)
            end
        end
    end
end

-- ============================================================================
-- 内部：构建面板控件树（只调用一次）
-- ============================================================================

local function BuildPanel()
    statsLabel_ = UI.Label {
        text = "0 / 0 里程碑",
        fontSize = 14,
        fontColor = { 220, 220, 230, 255 },
    }
    milkLabel_ = UI.Label {
        text = "管理经验: 0%",
        fontSize = 13,
        fontColor = { 200, 220, 255, 255 },
    }
    kittenLabel_ = UI.Label {
        text = "管理顾问产出加成: x1.00",
        fontSize = 13,
        fontColor = { 255, 200, 150, 255 },
    }
    kittenContainer_ = UI.Panel {
        width = "90%", maxWidth = 600,
        marginBottom = 10,
    }

    -- 计算屏幕高度作为 viewportHeight
    local dpr = graphics:GetDPR()
    local screenH = graphics:GetHeight() / dpr

    virtualList_ = UI.VirtualList {
        width = "100%",
        flex = 1,
        data = {},
        itemHeight = ROW_HEIGHT,
        itemGap = 0,
        viewportHeight = screenH,
        poolBuffer = 5,
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
                marginBottom = 8,
                children = {
                    UI.Panel { width = 22, height = 22,
                        backgroundImage = "image/侧栏_里程碑_20260414105503.png",
                        backgroundFit = "contain" },
                    UI.Label {
                        text = "里程碑",
                        fontSize = 18,
                        fontColor = { 255, 215, 0, 255 },
                    },
                },
            },

            -- 统计信息
            UI.Panel {
                width = "100%",
                padding = 8, borderRadius = 6,
                backgroundColor = { 35, 35, 50, 255 },
                gap = 3,
                marginBottom = 8,
                children = {
                    statsLabel_,
                    milkLabel_,
                    kittenLabel_,
                },
            },

            -- Kitten 升级区
            kittenContainer_,

            -- 成就列表（VirtualList）
            virtualList_,
        },
    }
end

-- ============================================================================
-- 公共接口
-- ============================================================================

function AchievementPanel.Init(root, am, buyKittenCallback)
    uiRoot_ = root
    achievementManager_ = am
    onBuyKitten_ = buyKittenCallback
    BuildPanel()
end

function AchievementPanel.Show()
    if not panel_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    lastStatsFP_ = ""
    lastKittenFP_ = ""
    lastAchFP_ = ""
    kittenRowCache_ = {}
    uiRoot_:AddChild(panel_)
    AchievementPanel.Refresh()
end

function AchievementPanel.Hide()
    if not panel_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    Tooltip.Hide()
    uiRoot_:RemoveChild(panel_)
end

function AchievementPanel.Toggle()
    if visible_ then
        AchievementPanel.Hide()
    else
        AchievementPanel.Show()
    end
end

function AchievementPanel.IsVisible()
    return visible_
end

-- ============================================================================
-- 刷新
-- ============================================================================

--- 创建 Kitten 升级按钮
local function CreateKittenItem(upgrade, index)
    local canAfford = GameState.coins >= upgrade.baseCost
    local needCount = upgrade.needAchievements
    local hasEnough = achievementManager_ and achievementManager_.GetUnlockedCount() >= needCount
    local buyable = (not upgrade.bought) and canAfford and hasEnough

    local F = GameState.FormatNumber

    local bgColor, borderColor
    if upgrade.bought then
        bgColor = { 30, 60, 35, 255 }
        borderColor = { 80, 180, 80, 150 }
    elseif buyable then
        bgColor = { 60, 55, 30, 255 }
        borderColor = { 255, 215, 0, 200 }
    else
        bgColor = { 30, 30, 40, 255 }
        borderColor = { 50, 50, 65, 100 }
    end

    -- 右侧状态区域
    local statusChild
    if upgrade.bought then
        statusChild = UI.Label { text = "✓ 已购买", fontSize = 11,
            fontColor = { 100, 200, 100, 200 } }
    elseif not hasEnough then
        statusChild = UI.Label { text = "需要 " .. needCount .. " 个里程碑", fontSize = 10,
            fontColor = { 150, 150, 170, 180 } }
    else
        -- 按钮样式：金币图标 + 价格
        statusChild = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 3,
            paddingLeft = 10, paddingRight = 10, paddingTop = 5, paddingBottom = 5,
            borderRadius = 5, borderWidth = 1,
            backgroundColor = canAfford and { 60, 140, 60, 255 } or { 40, 35, 50, 200 },
            borderColor = canAfford and { 100, 200, 100, 200 } or { 60, 50, 70, 120 },
            children = {
                UI.Panel { width = 14, height = 14,
                    backgroundImage = "image/金币.png", backgroundFit = "contain" },
                UI.Label { text = F(upgrade.baseCost), fontSize = 11,
                    fontColor = canAfford and { 255, 255, 255, 255 } or { 150, 150, 170, 180 } },
            },
        }
    end

    return UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        padding = 8, gap = 8, borderRadius = 6, borderWidth = 1,
        backgroundColor = bgColor,
        borderColor = borderColor,
        opacity = (upgrade.bought or buyable) and 1.0 or 0.5,
        pointerEvents = "auto",
        onPointerDown = buyable and function()
            if onBuyKitten_ then
                onBuyKitten_(index)
                AchievementPanel.Refresh()
            end
        end or nil,
        children = {
            UI.Panel { width = 32, height = 32,
                backgroundImage = "image/icon_管理顾问.png", backgroundFit = "contain" },
            UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                UI.Label { text = upgrade.name, fontSize = 13,
                    fontColor = upgrade.bought and { 100, 200, 100, 255 } or { 230, 230, 240, 255 } },
                UI.Label { text = upgrade.desc, fontSize = 10,
                    fontColor = { 140, 140, 160, 200 } },
            }},
            statusChild,
        },
    }
end

function AchievementPanel.Refresh()
    if not visible_ or not achievementManager_ then return end

    local F = GameState.FormatNumber
    local unlocked = achievementManager_.GetUnlockedCount()
    local total = achievementManager_.GetTotalCount()

    -- ── 统计信息（快照检测） ──
    local milkPct = string.format("%.0f", achievementManager_.GetMilkPercent())
    local kittenMul = string.format("%.2f", achievementManager_.GetKittenMultiplier())
    local statsFP = unlocked .. ":" .. total .. ":" .. milkPct .. ":" .. kittenMul
    if statsFP ~= lastStatsFP_ then
        lastStatsFP_ = statsFP
        if statsLabel_ then
            statsLabel_:SetText(unlocked .. " / " .. total .. " 里程碑  |  " ..
                achievementManager_.GetMilkFlavor())
        end
        if milkLabel_ then
            milkLabel_:SetText("管理经验: " .. milkPct .. "%")
        end
        if kittenLabel_ then
            kittenLabel_:SetText("管理顾问产出加成: x" .. kittenMul)
        end
    end

    -- ── Kitten 升级区（只显示最新已买 + 下一个待买） ──
    if kittenContainer_ then
        -- 找到最后一个已买的和第一个未买但可见的
        local lastBoughtIdx = nil
        local nextIdx = nil
        for i, u in ipairs(KittenUpgrades.upgrades) do
            if u.bought then
                lastBoughtIdx = i
            elseif not nextIdx and KittenUpgrades.IsVisible(u, unlocked) then
                nextIdx = i
            end
        end

        local canAfford = ""
        if nextIdx then
            canAfford = GameState.coins >= KittenUpgrades.upgrades[nextIdx].baseCost and "Y" or "N"
        end
        local kittenFP = (lastBoughtIdx or "0") .. ":" .. (nextIdx or "0") .. ":" .. canAfford

        if kittenFP ~= lastKittenFP_ then
            lastKittenFP_ = kittenFP
            kittenContainer_:RemoveAllChildren()
            kittenRowCache_ = {}
            local hasVisible = false

            -- 优先显示下一个待购买的，否则显示最后已买的
            local showIdx = nextIdx or lastBoughtIdx
            if showIdx then
                local widget = CreateKittenItem(KittenUpgrades.upgrades[showIdx], showIdx)
                kittenContainer_:AddChild(widget)
                kittenRowCache_[showIdx] = widget
                hasVisible = true
            end

            if hasVisible then
                kittenContainer_:InsertChild(UI.Label {
                    text = "管理顾问升级",
                    fontSize = 12,
                    fontColor = { 200, 180, 120, 200 },
                    marginBottom = 4,
                }, 0)
            end
        end
    end

    -- ── 成就列表（VirtualList） ──
    if virtualList_ then
        local allStatus = achievementManager_.GetAllWithStatus()

        local achParts = {}
        for idx, entry in ipairs(allStatus) do
            achParts[idx] = entry.unlocked and "1" or "0"
        end
        local achFP = table.concat(achParts)

        if achFP ~= lastAchFP_ then
            lastAchFP_ = achFP
            RebuildFlatData()
            virtualList_:SetData(flatData_)
        end
    end
end

return AchievementPanel
