-- ============================================================================
-- Coin Clicker - 放置类点击游戏
-- 模块化入口
-- ============================================================================

local UI = require("urhox-libs/UI")
local Buildings = require("config.Buildings")
local Upgrades = require("config.Upgrades")
local GameState = require("core.GameState")
local GameManager = require("core.GameManager")
local AudioManager = require("core.AudioManager")
local StatsBar = require("ui.StatsBar")
local CoinArea = require("ui.CoinArea")
local ShopPanel = require("ui.ShopPanel")
local LuckyCoin = require("ui.LuckyCoin")
local FloatingText = require("ui.FloatingText")
local CoinParticle = require("ui.CoinParticle")
local Tooltip = require("ui.Tooltip")
local AchievementNotify = require("ui.AchievementNotify")
local AchievementPanel = require("ui.AchievementPanel")
local WrinklerDisplay = require("ui.WrinklerDisplay")
local ResearchPanel = require("ui.ResearchPanel")
local SugarLumpDisplay = require("ui.SugarLumpDisplay")
local BuildingLevelPanel = require("ui.BuildingLevelPanel")
local HeavenlyShop = require("ui.HeavenlyShop")
local AscensionPanel = require("ui.AscensionPanel")
local SeasonPanel = require("ui.SeasonPanel")
local ReindeerDisplay = require("ui.ReindeerDisplay")
local DragonPanel = require("ui.DragonPanel")
local SkillPanel = require("ui.SkillPanel")
local SkillBar = require("ui.SkillBar")
local LeaderboardPanel = require("ui.LeaderboardPanel")
local SettingsPanel = require("ui.SettingsPanel")
local SaveBridge = require("core.SaveBridge")
local SlotSaveSystem = require("core.SlotSaveSystem")

-- ============================================================================
-- 左侧抽屉式菜单栏
-- ============================================================================
local drawerContainer_ = nil   -- 整个抽屉容器（图标列 + 内容区）
local drawerContent_   = nil   -- 内容区容器
local activeDrawerIdx_ = nil   -- 当前打开的面板索引（nil=全部关闭）
local iconBtns_        = {}    -- 图标按钮引用，用于高亮
local sugarLumpWidget_ = nil   -- 人脉图标引用（侧栏开关时隐藏/显示）

local SIDEBAR_ITEMS = {
    { iconImage = "image/侧栏_里程碑_20260414105503.png", label = "里程碑", color = { 255, 200, 50 } },
    { iconImage = "image/侧栏_劳资_20260414105509.png",   label = "劳资", color = { 180, 100, 255 } },
    { iconImage = "image/侧栏_人脉_20260414105508.png",   label = "人脉", color = { 255, 180, 220 } },
    { iconImage = "image/侧栏_转型_20260414105515.png",   label = "转型", color = { 180, 150, 255 } },
    { iconImage = "image/侧栏_经验_20260414105524.png",   label = "经验", color = { 150, 130, 220 } },
    { iconImage = "image/侧栏_周期_20260414105505.png",   label = "周期", color = { 100, 200, 130 } },
    { iconImage = "image/侧栏_AI_20260414105511.png",     label = "AI",   color = { 220, 170, 60 } },
    { iconImage = "image/侧栏_技能.png",                  label = "技能", color = { 80, 200, 220 } },
}

-- 面板模块引用表（在 Start() 中填充）
local DRAWER_PANELS = {}

local iconsCol_       = nil -- 图标列容器引用
local btnAttached_    = {} -- btnAttached_[i] = true/false 跟踪按钮是否在 DOM 中
local ToggleDrawerPanel    -- 前向声明（UpdateIconHighlights 中引用）

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

local function UpdateIconHighlights()
    if not iconsCol_ then return end

    -- 更新高亮色
    for i, btn in ipairs(iconBtns_) do
        local c = SIDEBAR_ITEMS[i].color
        if i == activeDrawerIdx_ then
            btn:SetStyle({ backgroundColor = { c[1], c[2], c[3], 100 } })
        else
            btn:SetStyle({ backgroundColor = { c[1], c[2], c[3], 25 } })
        end
    end

    -- 动态置灰/恢复图标按钮（未解锁 → 置灰 + 禁止点击）
    for i = 1, #SIDEBAR_ITEMS do
        local btn = iconBtns_[i]
        if btn then
            local unlocked = IsSidebarUnlocked(i)
            local wasUnlocked = btnAttached_[i]
            if unlocked and not wasUnlocked then
                -- 解锁：恢复不透明度
                btn:SetStyle({ opacity = 1.0 })
                btnAttached_[i] = true
            elseif not unlocked and wasUnlocked then
                -- 锁定：置灰
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
        local dpr = graphics:GetDPR()
        local x = input.mousePosition.x / dpr
        local y = input.mousePosition.y / dpr
        FloatingText.Show("未解锁", x, y, { 200, 200, 200, 255 })
        return
    end

    -- 如果点击的是已打开的面板 → 关闭（移除内容区）
    if activeDrawerIdx_ == index then
        local panel = DRAWER_PANELS[activeDrawerIdx_]
        if panel then panel.Hide() end
        activeDrawerIdx_ = nil
        if drawerContainer_ and drawerContent_ then
            drawerContainer_:RemoveChild(drawerContent_)
        end
        UpdateIconHighlights()
        -- 侧栏关闭 → 恢复人脉显示
        if sugarLumpWidget_ then sugarLumpWidget_:SetVisible(true) end
        return
    end

    -- 如果有其他面板打开 → 先关闭
    if activeDrawerIdx_ then
        local oldPanel = DRAWER_PANELS[activeDrawerIdx_]
        if oldPanel then oldPanel.Hide() end
    end

    -- 打开新面板（重新挂载内容区）
    activeDrawerIdx_ = index
    if drawerContainer_ and drawerContent_ then
        drawerContainer_:AddChild(drawerContent_)
    end
    local panel = DRAWER_PANELS[index]
    if panel then panel.Show() end
    UpdateIconHighlights()
    -- 侧栏打开 → 隐藏人脉显示
    if sugarLumpWidget_ then sugarLumpWidget_:SetVisible(false) end
end

function Start()
    graphics.windowTitle = "Coin Clicker"

    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 初始化音频（需要 Scene 挂载 SoundSource）
    ---@type Scene
    local audioScene = Scene()
    AudioManager.Init(audioScene)
    AudioManager.PlayBGM()

    -- 初始化游戏管理器
    GameManager.Init()

    -- 注入建筑效率升级引用到存档桥接层
    SaveBridge.SetBuildingUpgrades(GameManager.buildingUpgrades)

    -- 创建幸运金币 UI（返回两个元素）
    local luckyPanel, luckyEffectLabel = LuckyCoin.Create(function()
        GameManager.TriggerLuckyEffect()
    end)

    -- 构建 UI 树
    local root = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = { 25, 25, 35, 255 },
        children = {
            -- 主体区域：左侧点击区 + 右侧商店
            UI.Panel {
                flex = 1,
                flexDirection = "row",
                width = "100%",
                overflow = "hidden",
                children = {
                    CoinArea.Create(function(x, y)
                        GameManager.OnCoinClick(x, y)
                    end),
                    ShopPanel.Create(Buildings.buildings, Upgrades.clickUpgrades, {
                        onBuyBuilding = function(index)
                            GameManager.OnBuyBuilding(index)
                        end,
                        onBuyClickUpgrade = function(index)
                            GameManager.OnBuyClickUpgrade(index)
                        end,
                        onBuyBuildingUpgrade = function(bi, ti)
                            GameManager.OnBuyBuildingUpgrade(bi, ti)
                        end,
                        onBuyAll = function()
                            GameManager.OnBuyAll()
                        end,
                        onBuyAllBuildings = function()
                            GameManager.OnBuyAllBuildings()
                        end,
                    }, GameManager.buildingUpgrades),
                },
            },
            -- 排行榜按钮（absolute 浮动）
            LeaderboardPanel.Create(),
            -- 设置按钮（absolute 浮动，排行榜左侧）
            SettingsPanel.Create(),

            -- 底部技能快捷栏（absolute 底部浮动）
            SkillBar.Create(),
            -- 左侧抽屉式菜单栏
            UI.Panel {
                id = "drawer",
                position = "absolute",
                top = 0, left = 0,
                height = "100%",
                flexDirection = "row",
                pointerEvents = "auto",
                children = {
                    -- 图标列
                    UI.Panel {
                        id = "drawerIcons",
                        width = 48,
                        height = "100%",
                        flexDirection = "column",
                        alignItems = "center",
                        backgroundColor = { 22, 20, 32, 240 },
                        paddingTop = 8, paddingBottom = 8,
                        borderColor = { 60, 55, 80, 100 },
                        pointerEvents = "auto",
                        children = (function()
                            local items = {}
                            for i, item in ipairs(SIDEBAR_ITEMS) do
                                local c = item.color
                                local idx = i  -- 闭包捕获
                                items[#items + 1] = UI.Panel {
                                    id = "iconBtn_" .. i,
                                    width = 40, height = 40,
                                    justifyContent = "center", alignItems = "center",
                                    borderRadius = 10,
                                    marginBottom = 4,
                                    backgroundColor = { c[1], c[2], c[3], 25 },
                                    pointerEvents = "auto",
                                    onPointerDown = function()
                                        ToggleDrawerPanel(idx)
                                    end,
                                    children = {
                                        UI.Panel { width = 28, height = 28,
                                            backgroundImage = item.iconImage },
                                    },
                                }
                            end
                            return items
                        end)(),
                    },
                    -- 内容区（默认隐藏，宽度为屏幕逻辑宽度的 30%）
                    UI.Panel {
                        id = "drawerContent",
                        width = math.floor(graphics:GetWidth() / graphics:GetDPR() * 0.3),
                        height = "100%",
                        backgroundColor = { 28, 26, 38, 240 },
                        borderColor = { 60, 55, 80, 80 },
                        flexDirection = "column",
                        overflow = "hidden",
                        pointerEvents = "auto",
                        children = {},
                    },
                },
            },
            -- 驯鹿浮动面板（absolute 定位）
            ReindeerDisplay.Create(function()
                GameManager.OnClickReindeer()
            end),
            -- 幸运金币浮动面板（absolute 定位）
            luckyPanel,
            -- 效果提示标签（absolute 定位）
            luckyEffectLabel,
            -- 金币粒子容器（absolute 定位）
            CoinParticle.Create(),
            -- 悬停提示框（absolute 定位）
            Tooltip.Create(),
            -- 浮动文本容器（absolute 定位）
            FloatingText.Create(),
            -- 成就解锁通知（顶部居中）
            AchievementNotify.Create(),
        },
    }

    UI.SetRoot(root)

    -- 初始化抽屉式菜单栏
    drawerContainer_ = root:FindById("drawer")
    drawerContent_ = root:FindById("drawerContent")
    -- 初始状态：移除内容区，只保留图标列
    if drawerContainer_ and drawerContent_ then
        drawerContainer_:RemoveChild(drawerContent_)
    end
    for i = 1, #SIDEBAR_ITEMS do
        local btn = root:FindById("iconBtn_" .. i)
        if btn then iconBtns_[i] = btn end
    end

    -- 缓存图标列容器，初始时移除未解锁的侧栏按钮
    iconsCol_ = root:FindById("drawerIcons")
    for i = 1, #SIDEBAR_ITEMS do
        btnAttached_[i] = true  -- 初始都在 DOM 中
    end
    if iconsCol_ then
        -- 未解锁的按钮置灰（保留在 DOM 中，点击时提示）
        for i = 1, #SIDEBAR_ITEMS do
            if not IsSidebarUnlocked(i) and iconBtns_[i] then
                iconBtns_[i]:SetStyle({ opacity = 0.3 })
                btnAttached_[i] = false
            end
        end
    end

    -- 初始化 UI 模块（FindById 缓存）
    StatsBar.Init(root)
    CoinArea.Init(root)
    ShopPanel.Init(root, Buildings.buildings, Upgrades.clickUpgrades, GameManager.buildingUpgrades)
    Tooltip.Init(root)
    LuckyCoin.Init(root)
    FloatingText.Init(root)
    CoinParticle.Init(root)
    AchievementNotify.Init(root)
    AchievementPanel.Init(drawerContent_, GameManager.GetAchievementManager(), function(index)
        GameManager.OnBuyKitten(index)
    end)

    -- 初始化皱巴虫显示
    WrinklerDisplay.Init(root, GameManager.GetWrinklerManager(), function(wrinklerId)
        GameManager.GetWrinklerManager().PopById(wrinklerId)
    end)

    -- 在金币区添加奶奶末日状态指示器
    local coinAreaPanel = root:FindById("coinArea")
    if coinAreaPanel then
        coinAreaPanel:AddChild(WrinklerDisplay.CreateStatusWidget())
    end

    -- 初始化研究面板
    ResearchPanel.Init(drawerContent_, GameManager.GetGrandmapoManager(), function(index)
        GameManager.OnBuyResearch(index)
    end, function()
        GameManager.OnBuyPledge()
    end)

    -- 初始化糖块显示（顶部图标，挂载到 root）
    local sugarWidget = SugarLumpDisplay.CreateWidget()
    SugarLumpDisplay.Init(root, GameManager.GetSugarLumpManager(), function()
        GameManager.OnHarvestSugarLump()
    end)
    -- 如果糖块已解锁，立即显示
    if GameManager.GetSugarLumpManager().IsUnlocked() then
        SugarLumpDisplay.Show(root)
    end
    -- 缓存人脉图标引用，供侧栏开关时隐藏/显示
    sugarLumpWidget_ = root:FindById("sugarLumpWidget")

    -- 初始化建筑等级升级面板
    BuildingLevelPanel.Init(drawerContent_, GameManager.GetSugarLumpManager(), function(buildingIndex)
        GameManager.OnUpgradeBuildingLevel(buildingIndex)
    end)

    -- 初始化天堂升级商店
    HeavenlyShop.Init(drawerContent_, GameManager.GetAscensionManager(), function(upgradeId)
        GameManager.OnBuyHeavenlyUpgrade(upgradeId)
        UpdateIconHighlights()  -- 购买天堂升级后刷新侧边栏（AI 合伙人解锁）
    end)

    -- 初始化飞升确认面板
    AscensionPanel.Init(drawerContent_, GameManager.GetAscensionManager(), function()
        GameManager.OnAscend()
    end, function()
        ToggleDrawerPanel(5)  -- 通过抽屉系统切换到天堂商店（索引5）
    end)

    -- 初始化季节面板
    SeasonPanel.Init(drawerContent_, GameManager.GetSeasonManager(), function(seasonId)
        GameManager.OnSwitchSeason(seasonId)
    end, function()
        GameManager.OnUpgradeSanta()
    end)

    -- 初始化驯鹿显示
    ReindeerDisplay.Init(root)

    -- 初始化龙面板
    DragonPanel.Init(drawerContent_, GameManager.GetDragonManager(), function()
        GameManager.OnUpgradeDragon()
    end, function(slot, auraId)
        GameManager.OnEquipDragonAura(slot, auraId)
    end, function()
        GameManager.OnPetDragon()
    end)

    -- 初始化技能面板（侧栏面板：查看详情 + 升级）
    SkillPanel.Init(drawerContent_, GameManager)
    GameManager.SetSkillPanel(SkillPanel)

    -- 初始化底部技能快捷栏（解锁后显示，点击释放）
    SkillBar.Init(root, GameManager)

    -- 初始化排行榜面板
    LeaderboardPanel.Init(root)

    -- 初始化设置面板
    SettingsPanel.Init(root)

    -- 注册面板模块到抽屉系统
    DRAWER_PANELS = {
        AchievementPanel,     -- 1: 成就
        ResearchPanel,        -- 2: 研究
        BuildingLevelPanel,   -- 3: 糖块
        AscensionPanel,       -- 4: 飞升
        HeavenlyShop,         -- 5: 商店
        SeasonPanel,          -- 6: 季节
        DragonPanel,          -- 7: 龙
        SkillPanel,           -- 8: 技能
    }

    -- 注入 UI 引用到游戏管理器
    GameManager.SetUI(root, StatsBar, CoinArea, ShopPanel, LuckyCoin, FloatingText, CoinParticle, AchievementNotify, WrinklerDisplay, ResearchPanel, SugarLumpDisplay, BuildingLevelPanel, HeavenlyShop, AscensionPanel, SeasonPanel, ReindeerDisplay, DragonPanel, AchievementPanel)

    -- 初始化侧边栏按钮可见性（AI 合伙人需解锁）
    UpdateIconHighlights()

    -- 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    -- 初始化存档系统（云端加载 → 本地回退 → 新玩家）
    SlotSaveSystem.Init(function(ok, offlineTime)
        if ok then
            -- 飞升后 buildingUpgrades 可能被重新生成，同步引用
            SaveBridge.SetBuildingUpgrades(GameManager.buildingUpgrades)

            -- 存档加载成功，重新计算产出并刷新所有 UI
            GameManager.RecalcProduction()
            GameManager.RefreshAllUI()
            UpdateIconHighlights()

            -- 重新初始化商店面板（建筑/升级数据已从存档恢复）
            ShopPanel.Init(root, Buildings.buildings, Upgrades.clickUpgrades, GameManager.buildingUpgrades)

            -- 刷新糖块显示（存档中可能已解锁）
            if GameManager.GetSugarLumpManager().IsUnlocked() then
                SugarLumpDisplay.Show(root)
            end

            -- 恢复音量设置
            AudioManager.SetBGMVolume(GameState.settings.bgmVolume)
            AudioManager.SetSFXVolume(GameState.settings.sfxVolume)

            if offlineTime > 0 then
                print("[SaveSystem] 离线 " .. offlineTime .. " 秒")
            end
        end
        print("[SaveSystem] 初始化完成, ok=" .. tostring(ok))
    end)

    print("=== Coin Clicker Started ===")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- 事件处理（转发到 GameManager）
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    GameManager.Update(dt)

    -- 存档系统帧更新（自动保存 / 脏数据 / 重试）
    SlotSaveSystem.Update(dt)

    -- 刷新底部技能栏（降频：0.2 秒一次）
    skillBarTimer_ = (skillBarTimer_ or 0) - dt
    if skillBarTimer_ <= 0 then
        skillBarTimer_ = 0.2
        SkillBar.Refresh()
    end

    -- 排行榜定时上传 + 刷新
    LeaderboardPanel.Update(dt)

    -- BGM 循环守护
    AudioManager.Update(dt)
end

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseButtonDown(eventType, eventData)
    -- 金币点击已由 CoinArea 的 pointerEvents 处理
end

---@param eventType string
---@param eventData TouchBeginEventData
function HandleTouchBegin(eventType, eventData)
    -- 金币点击已由 CoinArea 的 pointerEvents 处理
end


