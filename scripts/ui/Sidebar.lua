-- ============================================================================
-- Sidebar.lua  —  左侧抽屉式菜单栏
--   状态管理 / 图标解锁检测 / 面板互斥切换
-- ============================================================================
local UI = require("urhox-libs/UI")
local GameManager = require("core.GameManager")

local Sidebar = {}

-- ============================================================================
-- 配置
-- ============================================================================
local SIDEBAR_ITEMS = {
    { iconImage = "image/侧栏_里程碑_20260414105503.png", label = "里程碑", color = { 255, 200, 50 } },
    { iconImage = "image/侧栏_劳资_20260414105509.png",   label = "劳资",   color = { 180, 100, 255 } },
    { iconImage = "image/侧栏_人脉_20260414105508.png",   label = "人脉",   color = { 255, 180, 220 } },
    { iconImage = "image/侧栏_转型_20260414105515.png",   label = "转型",   color = { 180, 150, 255 } },
    { iconImage = "image/侧栏_经验_20260414105524.png",   label = "经验",   color = { 150, 130, 220 } },
    { iconImage = "image/侧栏_周期_20260414105505.png",   label = "周期",   color = { 100, 200, 130 } },
    { iconImage = "image/侧栏_AI_20260414105511.png",     label = "AI",     color = { 220, 170, 60 } },
    { iconImage = "image/侧栏_技能.png",                  label = "技能",   color = { 80, 200, 220 } },
}

-- ============================================================================
-- 状态
-- ============================================================================
local drawerContainer_ = nil   -- 整个抽屉容器（图标列 + 内容区）
local drawerContent_   = nil   -- 内容区容器
local activeDrawerIdx_ = nil   -- 当前打开的面板索引（nil=全部关闭）
local iconBtns_        = {}    -- 图标按钮引用，用于高亮
local sugarLumpWidget_ = nil   -- 人脉图标引用（侧栏开关时隐藏/显示）
local iconsCol_        = nil   -- 图标列容器引用
local btnAttached_     = {}    -- btnAttached_[i] = true/false 跟踪按钮是否已解锁

--- 面板模块引用列表，由 AppLayout 调用 SetPanels 注册
local drawerPanels_    = {}

--- FloatingText 引用（显示"未解锁"提示）
local floatingText_    = nil

-- ============================================================================
-- 侧栏图标解锁条件（返回 true = 已解锁可显示）
-- ============================================================================
local function IsSidebarUnlocked(index)
    -- 1: 里程碑 → 始终显示
    if index == 1 then return true end
    -- 2: 劳资 → 第一项研究已解锁（奶奶≥6 且类型≥7）
    if index == 2 then
        local gm = GameManager.GetGrandmapoManager()
        return gm and gm.IsResearchUnlocked(1)
    end
    -- 3: 人脉 → 糖块系统已解锁（总产出≥1e9）
    if index == 3 then
        local slm = GameManager.GetSugarLumpManager()
        return slm and slm.IsUnlocked()
    end
    -- 4: 转型 → 有可获得的声望（总烘焙足够）
    if index == 4 then
        local am = GameManager.GetAscensionManager()
        return am and am.GetPotentialPrestige() > 0
    end
    -- 5: 经验 → 已飞升过（当前声望>0）
    if index == 5 then
        local am = GameManager.GetAscensionManager()
        return am and am.GetPrestigeLevel() > 0
    end
    -- 6: 周期 → 拥有「周期切换器」升级
    if index == 6 then
        local am = GameManager.GetAscensionManager()
        return am and am.HasUpgrade("seasonSwitcher")
    end
    -- 7: AI → 拥有「龙蛋配方」升级
    if index == 7 then
        local am = GameManager.GetAscensionManager()
        return am and am.HasUpgrade("howToBakeDragon")
    end
    -- 8: 技能 → 始终显示
    if index == 8 then return true end
    return true
end

-- ============================================================================
-- 内部：高亮刷新 + 面板切换
-- ============================================================================
local ToggleDrawerPanel  -- 前向声明

local function UpdateIconHighlights()
    if not iconsCol_ then return end

    for i, btn in ipairs(iconBtns_) do
        local c = SIDEBAR_ITEMS[i].color
        if i == activeDrawerIdx_ then
            btn:SetStyle({ backgroundColor = { c[1], c[2], c[3], 100 } })
        else
            btn:SetStyle({ backgroundColor = { c[1], c[2], c[3], 25 } })
        end
    end

    -- 动态置灰/恢复图标按钮
    for i = 1, #SIDEBAR_ITEMS do
        local btn = iconBtns_[i]
        if btn then
            local unlocked = IsSidebarUnlocked(i)
            local wasUnlocked = btnAttached_[i]
            if unlocked and not wasUnlocked then
                btn:SetStyle({ opacity = 1.0 })
                btnAttached_[i] = true
            elseif not unlocked and wasUnlocked then
                if activeDrawerIdx_ == i then
                    ToggleDrawerPanel(i)
                end
                btn:SetStyle({ opacity = 0.3 })
                btnAttached_[i] = false
            end
        end
    end
end

ToggleDrawerPanel = function(index)
    if not drawerContent_ then return end

    -- 未解锁时提示
    if not IsSidebarUnlocked(index) then
        if floatingText_ then
            local dpr = graphics:GetDPR()
            local x = input.mousePosition.x / dpr
            local y = input.mousePosition.y / dpr
            floatingText_.Show("未解锁", x, y, { 200, 200, 200, 255 })
        end
        return
    end

    -- 如果点击的是已打开的面板 → 关闭
    if activeDrawerIdx_ == index then
        local panel = drawerPanels_[activeDrawerIdx_]
        if panel then panel.Hide() end
        activeDrawerIdx_ = nil
        if drawerContainer_ and drawerContent_ then
            drawerContainer_:RemoveChild(drawerContent_)
        end
        UpdateIconHighlights()
        if sugarLumpWidget_ then sugarLumpWidget_:SetVisible(true) end
        return
    end

    -- 如果有其他面板打开 → 先关闭
    if activeDrawerIdx_ then
        local oldPanel = drawerPanels_[activeDrawerIdx_]
        if oldPanel then oldPanel.Hide() end
    end

    -- 打开新面板
    activeDrawerIdx_ = index
    if drawerContainer_ and drawerContent_ then
        drawerContainer_:AddChild(drawerContent_)
    end
    local panel = drawerPanels_[index]
    if panel then panel.Show() end
    UpdateIconHighlights()
    if sugarLumpWidget_ then sugarLumpWidget_:SetVisible(false) end
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 注册面板模块列表和 FloatingText 引用
---@param panels table  有序列表，按 SIDEBAR_ITEMS 对应的面板模块
---@param floatingText table  FloatingText 模块引用
function Sidebar.SetPanels(panels, floatingText)
    drawerPanels_ = panels
    floatingText_ = floatingText
end

--- 构建侧栏 UI 节点（返回一个 UI.Panel 供挂载到 root.children 中）
function Sidebar.CreateWidget()
    local dpr = graphics:GetDPR()
    local logW = graphics:GetWidth() / dpr
    local logH = graphics:GetHeight() / dpr
    local shortSide = math.min(logW, logH)
    local colW = math.floor(math.max(48, math.min(80, shortSide * 0.14)))
    local btnSize = colW - 8
    local iconSize = math.floor(btnSize * 0.68)

    -- 安全区左侧偏移（背景延伸到边缘，图标向内缩进）
    local safeInsets = UI.GetSafeAreaInsets()
    local safeLeft = safeInsets.left

    return UI.Panel {
        id = "drawer",
        position = "absolute",
        top = 0, left = 0,
        height = "100%",
        flexDirection = "row",
        pointerEvents = "auto",
        zIndex = 20,
        children = {
            -- 图标列
            UI.Panel {
                id = "drawerIcons",
                width = colW + safeLeft,
                height = "100%",
                flexDirection = "column",
                alignItems = "center",
                backgroundColor = { 22, 20, 32, 240 },
                paddingTop = 8, paddingBottom = 8,
                paddingLeft = safeLeft,
                borderColor = { 60, 55, 80, 100 },
                pointerEvents = "auto",
                children = (function()
                    local items = {}
                    for i, item in ipairs(SIDEBAR_ITEMS) do
                        local c = item.color
                        local idx = i
                        items[#items + 1] = UI.Panel {
                            id = "iconBtn_" .. i,
                            width = btnSize, height = btnSize,
                            justifyContent = "center", alignItems = "center",
                            borderRadius = math.floor(btnSize * 0.22),
                            marginBottom = 2,
                            backgroundColor = { c[1], c[2], c[3], 25 },
                            pointerEvents = "auto",
                            onTap = function()
                                ToggleDrawerPanel(idx)
                            end,
                            children = {
                                UI.Panel { width = iconSize, height = iconSize,
                                    backgroundImage = item.iconImage,
                                    pointerEvents = "none" },
                            },
                        }
                    end
                    return items
                end)(),
            },
            -- 内容区（默认隐藏，宽度为屏幕逻辑宽度的 30%）
            UI.Panel {
                id = "drawerContent",
                width = math.floor(logW * 0.3),
                height = "100%",
                backgroundColor = { 28, 26, 38, 240 },
                borderColor = { 60, 55, 80, 80 },
                flexDirection = "column",
                overflow = "hidden",
                pointerEvents = "auto",
                children = {},
            },
        },
    }
end

--- 初始化侧栏（在 UI.SetRoot 之后调用）
---@param root table  UI root 节点
function Sidebar.Init(root)
    drawerContainer_ = root:FindById("drawer")
    drawerContent_ = root:FindById("drawerContent")

    -- 初始状态：移除内容区，只保留图标列
    if drawerContainer_ and drawerContent_ then
        drawerContainer_:RemoveChild(drawerContent_)
    end

    iconBtns_ = {}
    for i = 1, #SIDEBAR_ITEMS do
        local btn = root:FindById("iconBtn_" .. i)
        if btn then iconBtns_[i] = btn end
    end

    iconsCol_ = root:FindById("drawerIcons")
    for i = 1, #SIDEBAR_ITEMS do
        btnAttached_[i] = true
    end
    if iconsCol_ then
        for i = 1, #SIDEBAR_ITEMS do
            if not IsSidebarUnlocked(i) and iconBtns_[i] then
                iconBtns_[i]:SetStyle({ opacity = 0.3 })
                btnAttached_[i] = false
            end
        end
    end

    sugarLumpWidget_ = root:FindById("sugarLumpWidget")
end

--- 刷新图标高亮（解锁/激活状态变化时调用）
function Sidebar.UpdateHighlights()
    UpdateIconHighlights()
end

--- 程序化切换面板（供外部调用，如飞升面板"打开天堂商店"按钮）
function Sidebar.Toggle(index)
    ToggleDrawerPanel(index)
end

--- 获取内容区容器（供面板 Init 时 drawerContent 参数使用）
function Sidebar.GetContentPanel()
    return drawerContent_
end

return Sidebar
