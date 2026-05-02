-- ============================================================================
-- ui/HeavenlyShop.lua
-- 经验商店（全屏覆盖式弹窗）
-- 使用经验值购买永久升级
-- 使用 AddChild/RemoveChild 控制显隐
-- ============================================================================

local UI = require("urhox-libs/UI")
local AD = require("config.AscensionDefs")
local GameState = require("core.GameState")

local HS = {}

-- ======== 引用 ========
local uiRoot_ = nil
local panel_ = nil
local listContainer_ = nil
local chipRow_ = nil
local chipIcon_ = nil
local chipCountText_ = nil
local chipBonusText_ = nil
local visible_ = false

-- 外部注入
local ascensionManager_ = nil
local onBuyUpgrade_ = nil     -- function(upgradeId)

-- ======== 增量刷新缓存 ========
local rowCache_ = {}           -- rowCache_[upgradeId] = { row, nameLabel, statusLabel, lastFP }
local lastChipText_ = ""
local initialized_ = false

-- ======== 升级分组定义 ========
local GROUPS = {
    { title = "品牌传承链", ids = { "legacy", "heavenlyChipSecret", "heavenlyCookieStand", "heavenlyBakery", "heavenlyKey" } },
    { title = "产量加成", ids = { "heavenlyCookies", "tinOfBiscuits", "boxOfBiscuits", "boxOfMacarons" } },
    { title = "老关系", ids = { "starterKit", "starterKitchen" } },
    { title = "商机加成", ids = { "heavenlyLuck", "lastingFortune" } },
    { title = "签单 & 顾问", ids = { "santasHelpers", "santasMilk" } },
    { title = "AI 合伙人", ids = { "howToBakeDragon" } },
    { title = "周期切换", ids = { "seasonSwitcher" } },
    { title = "核心资产槽", ids = { "permSlot1", "permSlot2" } },
}

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

    listContainer_ = UI.Panel {
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
-- 构建升级行（带缓存）
-- ============================================================================

local function BuildUpgradeRow(status)
    local u = status.def
    local bgColor, borderColor, clickable

    if status.bought then
        bgColor = { 25, 45, 30, 255 }
        borderColor = { 80, 180, 80, 150 }
        clickable = false
    elseif status.unlocked then
        if status.canAfford then
            bgColor = { 50, 40, 65, 255 }
            borderColor = { 200, 170, 255, 200 }
        else
            bgColor = { 35, 30, 50, 255 }
            borderColor = { 100, 80, 140, 120 }
        end
        clickable = status.canAfford
    else
        bgColor = { 20, 18, 30, 200 }
        borderColor = { 40, 35, 55, 100 }
        clickable = false
    end

    local effectDesc = u.desc or ""

    local nameLabel = UI.Label { text = u.name, fontSize = 13,
        fontColor = status.bought and { 100, 200, 100, 255 }
            or (status.unlocked and { 230, 220, 255, 255 }
            or { 100, 95, 120, 200 }) }

    -- 状态区域：按钮样式（图标+数字）或纯文字
    local statusLabel   -- 用于增量更新文字
    local statusWidget  -- 行内实际挂载的 widget
    if status.bought then
        statusLabel = UI.Label { text = "✓ 已购买", fontSize = 11,
            fontColor = { 100, 200, 100, 200 }, textAlign = "center" }
        statusWidget = UI.Panel {
            flexDirection = "row", alignItems = "center", justifyContent = "center",
            paddingLeft = 6, paddingRight = 6, paddingTop = 3, paddingBottom = 3,
            borderRadius = 6,
            backgroundColor = { 40, 70, 45, 200 },
            borderWidth = 1, borderColor = { 80, 180, 80, 120 },
            children = { statusLabel },
        }
    elseif status.unlocked then
        statusLabel = UI.Label { text = GameState.FormatNumber(u.cost), fontSize = 12,
            fontColor = { 255, 255, 255, 240 } }
        local upgradeId = u.id
        statusWidget = UI.Panel {
            flexDirection = "row", alignItems = "center", justifyContent = "center",
            paddingLeft = 6, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
            borderRadius = 6, gap = 4,
            backgroundColor = clickable and { 80, 50, 120, 255 } or { 50, 45, 60, 200 },
            borderWidth = 1,
            borderColor = clickable and { 180, 130, 255, 200 } or { 70, 60, 90, 120 },
            pointerEvents = clickable and "auto" or "none",
            onPointerDown = clickable and function()
                if onBuyUpgrade_ then
                    onBuyUpgrade_(upgradeId)
                    HS.Refresh()
                end
            end or nil,
            children = {
                UI.Panel { width = 18, height = 18,
                    backgroundImage = "image/icon_管理经验.png", backgroundFit = "contain",
                    opacity = clickable and 1.0 or 0.4 },
                statusLabel,
            },
        }
    else
        -- 锁定状态
        local lockText = "需要: " .. (u.prereq or "")
        if u.prereq then
            local prereqDef = AD.FindById(u.prereq)
            if prereqDef then
                lockText = "需要: " .. prereqDef.name
            end
        end
        statusLabel = UI.Label { text = lockText, fontSize = 11,
            fontColor = { 120, 110, 140, 180 } }
        statusWidget = statusLabel
    end

    local row = UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        padding = 10, gap = 8, borderRadius = 8, borderWidth = 1,
        backgroundColor = bgColor,
        borderColor = borderColor,
        opacity = (status.bought or status.unlocked) and 1.0 or 0.35,
        children = {
            UI.Panel { width = 32, height = 32,
                backgroundImage = u.iconImage or "image/icon_管理经验.png",
                backgroundFit = "contain",
                opacity = (status.bought or status.unlocked) and 1.0 or 0.4 },
            UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                nameLabel,
                UI.Label { text = effectDesc, fontSize = 10,
                    fontColor = { 150, 140, 170, 200 } },
            }},
            statusWidget,
        },
    }

    -- 指纹：加入状态类别，状态变化时触发重建
    local state = status.bought and "B" or (status.unlocked and "U" or "L")
    local fp = state .. (status.canAfford and "A" or "")

    rowCache_[u.id] = {
        row = row,
        nameLabel = nameLabel,
        statusLabel = statusLabel,
        def = u,
        lastFP = fp,
        lastState = state,
    }

    return row
end

-- ============================================================================
-- 增量更新单行
-- ============================================================================

local function UpdateUpgradeRow(status)
    local u = status.def
    local cache = rowCache_[u.id]
    if not cache or not cache.row then return end

    local bgColor, borderColor, clickable

    if status.bought then
        bgColor = { 25, 45, 30, 255 }
        borderColor = { 80, 180, 80, 150 }
        clickable = false
    elseif status.unlocked then
        if status.canAfford then
            bgColor = { 50, 40, 65, 255 }
            borderColor = { 200, 170, 255, 200 }
        else
            bgColor = { 35, 30, 50, 255 }
            borderColor = { 100, 80, 140, 120 }
        end
        clickable = status.canAfford
    else
        bgColor = { 20, 18, 30, 200 }
        borderColor = { 40, 35, 55, 100 }
        clickable = false
    end

    cache.row:SetStyle({
        backgroundColor = bgColor,
        borderColor = borderColor,
        opacity = (status.bought or status.unlocked) and 1.0 or 0.35,
    })

    cache.nameLabel:SetFontColor(status.bought and { 100, 200, 100, 255 }
        or (status.unlocked and { 230, 220, 255, 255 }
        or { 100, 95, 120, 200 }))

    -- 注意：状态类别变化（bought/unlocked/locked 之间切换）时
    -- 由 Refresh 触发重建整行，这里只处理同类别内的变化（如 canAfford 变化）

    local state = status.bought and "B" or (status.unlocked and "U" or "L")
    cache.lastFP = state .. (status.canAfford and "A" or "")
    cache.lastState = state
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
    -- 重置缓存
    initialized_ = false
    rowCache_ = {}
    lastChipText_ = ""
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

    -- 升级列表
    if not listContainer_ then return end

    local statusList = ascensionManager_.GetUpgradeStatus()

    -- 首次构建
    if not initialized_ then
        initialized_ = true
        listContainer_:RemoveAllChildren()

        -- 建索引
        local statusById = {}
        for _, s in ipairs(statusList) do
            statusById[s.def.id] = s
        end

        for _, group in ipairs(GROUPS) do
            listContainer_:AddChild(UI.Label {
                text = group.title,
                fontSize = 12,
                fontColor = { 170, 160, 200, 200 },
                marginTop = 8,
                marginBottom = 4,
            })

            for _, id in ipairs(group.ids) do
                local s = statusById[id]
                if s then
                    listContainer_:AddChild(BuildUpgradeRow(s))
                end
            end
        end
        return
    end

    -- 增量更新
    local statusById = {}
    for _, s in ipairs(statusList) do
        statusById[s.def.id] = s
    end

    for _, group in ipairs(GROUPS) do
        for _, id in ipairs(group.ids) do
            local s = statusById[id]
            local cache = rowCache_[id]
            if s and cache then
                local state = s.bought and "B" or (s.unlocked and "U" or "L")
                local fp = state .. (s.canAfford and "A" or "")
                if fp ~= cache.lastFP then
                    -- 状态类别变化时（bought/unlocked/locked 切换），widget 结构不同，需全量重建
                    if state ~= cache.lastState then
                        initialized_ = false
                        HS.Refresh()
                        return
                    else
                        UpdateUpgradeRow(s)
                    end
                end
            end
        end
    end
end

return HS
