-- ============================================================================
-- AppLayout.lua  —  UI 树构建 + 互斥面板回调 + 模块初始化接线
-- ============================================================================
local UI = require("urhox-libs/UI")
local Buildings = require("config.Buildings")
local Upgrades  = require("config.Upgrades")
local GameState = require("core.GameState")
local GameManager = require("core.GameManager")
local AudioManager = require("core.AudioManager")
local SaveBridge   = require("core.SaveBridge")
local SlotSaveSystem = require("core.SlotSaveSystem")

-- UI 模块
local StatsBar          = require("ui.StatsBar")
local CoinArea          = require("ui.CoinArea")
local ShopPanel         = require("ui.ShopPanel")
local LuckyCoin         = require("ui.LuckyCoin")
local FloatingText      = require("ui.FloatingText")
local CoinParticle      = require("ui.CoinParticle")
local Tooltip           = require("ui.Tooltip")
local AchievementNotify = require("ui.AchievementNotify")
local AchievementPanel  = require("ui.AchievementPanel")
local WrinklerDisplay   = require("ui.WrinklerDisplay")
local ResearchPanel     = require("ui.ResearchPanel")
local SugarLumpDisplay  = require("ui.SugarLumpDisplay")
local BuildingLevelPanel= require("ui.BuildingLevelPanel")
local HeavenlyShop      = require("ui.HeavenlyShop")
local AscensionPanel    = require("ui.AscensionPanel")
local SeasonPanel       = require("ui.SeasonPanel")
local ReindeerDisplay   = require("ui.ReindeerDisplay")
local DragonPanel       = require("ui.DragonPanel")
local SkillPanel        = require("ui.SkillPanel")
local GardenPanel       = require("ui.GardenPanel")
local PantheonPanel     = require("ui.PantheonPanel")
local GrimoirePanel     = require("ui.GrimoirePanel")
local StockMarketPanel  = require("ui.StockMarketPanel")
local MiningPanel       = require("ui.MiningPanel")
local FactoryPanel      = require("ui.FactoryPanel")
local ShipmentPanel     = require("ui.ShipmentPanel")
local ECommercePanel    = require("ui.ECommercePanel")
local InventoryPanel    = require("ui.InventoryPanel")
-- local AdPanel           = require("ui.AdPanel")  -- 福利入口已隐藏
local SkillBar          = require("ui.SkillBar")
local LeaderboardPanel  = require("ui.LeaderboardPanel")
local SettingsPanel     = require("ui.SettingsPanel")
local DebugPanel        = require("ui.DebugPanel")
local Sidebar           = require("ui.Sidebar")

local AppLayout = {}

-- ============================================================================
-- 互斥面板系统
-- ============================================================================
-- 所有右侧抽屉式小游戏面板列表（统一互斥管理）
local MINIGAME_PANELS = {
    GardenPanel, PantheonPanel, GrimoirePanel, StockMarketPanel,
    MiningPanel, FactoryPanel, ShipmentPanel, ECommercePanel,
}

--- 关闭除了 except 以外的所有小游戏面板
local function CloseOtherMinigames(except)
    for _, p in ipairs(MINIGAME_PANELS) do
        if p ~= except and p.IsVisible() then p.Hide() end
    end
end

--- 创建一个互斥的 onOpen 回调
local function MakeOpenCallback(panel)
    return function()
        CloseOtherMinigames(panel)
        panel.Toggle()
    end
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 构建整棵 UI 树并初始化所有模块
---@return table root  UI root 节点（已 SetRoot）
function AppLayout.Build()
    -- 创建幸运金币 UI
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
                        onOpenGarden      = MakeOpenCallback(GardenPanel),
                        onOpenPantheon     = MakeOpenCallback(PantheonPanel),
                        onOpenGrimoire     = MakeOpenCallback(GrimoirePanel),
                        onOpenStockMarket  = MakeOpenCallback(StockMarketPanel),
                        onOpenMining       = MakeOpenCallback(MiningPanel),
                        onOpenFactory      = MakeOpenCallback(FactoryPanel),
                        onOpenShipment     = MakeOpenCallback(ShipmentPanel),
                        onOpenECommerce    = MakeOpenCallback(ECommercePanel),
                    }, GameManager.buildingUpgrades),
                },
            },
            -- 排行榜 + 设置按钮
            LeaderboardPanel.Create(),
            SettingsPanel.Create(),
            -- 底部技能快捷栏
            SkillBar.Create(),
            -- 左侧抽屉式菜单栏
            Sidebar.CreateWidget(),
            -- 驯鹿浮动面板
            ReindeerDisplay.Create(function()
                GameManager.OnClickReindeer()
            end),
            -- 幸运金币
            luckyPanel,
            luckyEffectLabel,
            -- 金币粒子
            CoinParticle.Create(),
            -- 悬停提示框
            Tooltip.Create(),
            -- 浮动文本
            FloatingText.Create(),
            -- 成就解锁通知
            AchievementNotify.Create(),
            -- 版本号
            UI.Label {
                position = "absolute",
                left = 6, bottom = 4,
                zIndex = 9999,
                text = "v1.0.7",
                fontSize = 9,
                fontColor = { 100, 100, 120, 120 },
                pointerEvents = "none",
            },
            -- 用户 ID
            UI.Label {
                position = "absolute",
                right = 6, top = 4,
                text = "ID: " .. tostring(clientCloud and clientCloud.userId or "---"),
                fontSize = 9,
                fontColor = { 100, 100, 120, 120 },
                pointerEvents = "none",
            },
            -- 调试面板
            DebugPanel.Create(),
        },
    }

    UI.SetRoot(root)

    -- ==== 初始化侧栏 ====
    Sidebar.SetPanels({
        AchievementPanel,     -- 1: 成就
        ResearchPanel,        -- 2: 研究
        BuildingLevelPanel,   -- 3: 糖块
        AscensionPanel,       -- 4: 飞升
        HeavenlyShop,         -- 5: 商店
        SeasonPanel,          -- 6: 季节
        DragonPanel,          -- 7: 龙
        SkillPanel,           -- 8: 技能
        InventoryPanel,       -- 9: 仓库
    }, FloatingText)
    Sidebar.Init(root)

    -- ==== 初始化各 UI 模块（FindById 缓存）====
    local drawerContent = Sidebar.GetContentPanel()

    StatsBar.Init(root)
    CoinArea.Init(root)
    ShopPanel.Init(root, Buildings.buildings, Upgrades.clickUpgrades, GameManager.buildingUpgrades)
    Tooltip.Init(root)
    LuckyCoin.Init(root)
    FloatingText.Init(root)
    CoinParticle.Init(root)
    AchievementNotify.Init(root)

    AchievementPanel.Init(drawerContent, GameManager.GetAchievementManager(), function(index)
        GameManager.OnBuyKitten(index)
    end)

    WrinklerDisplay.Init(root, GameManager.GetWrinklerManager(), function(wrinklerId)
        GameManager.GetWrinklerManager().PopById(wrinklerId)
    end)

    -- 在金币区添加奶奶末日状态指示器
    local coinAreaPanel = root:FindById("coinArea")
    if coinAreaPanel then
        coinAreaPanel:AddChild(WrinklerDisplay.CreateStatusWidget())
    end

    ResearchPanel.Init(drawerContent, GameManager.GetGrandmapoManager(), function(index)
        GameManager.OnBuyResearch(index)
    end, function()
        GameManager.OnBuyPledge()
    end)

    -- 糖块显示
    local sugarWidget = SugarLumpDisplay.CreateWidget()
    SugarLumpDisplay.Init(root, GameManager.GetSugarLumpManager(), function()
        GameManager.OnHarvestSugarLump()
    end)
    if GameManager.GetSugarLumpManager().IsUnlocked() then
        SugarLumpDisplay.Show(root)
    end

    BuildingLevelPanel.Init(drawerContent, GameManager.GetSugarLumpManager(), function(buildingIndex)
        GameManager.OnUpgradeBuildingLevel(buildingIndex)
    end)

    HeavenlyShop.Init(drawerContent, GameManager.GetAscensionManager(), function(upgradeId)
        GameManager.OnBuyHeavenlyUpgrade(upgradeId)
        Sidebar.UpdateHighlights()
    end)

    AscensionPanel.Init(drawerContent, GameManager.GetAscensionManager(), function()
        GameManager.OnAscend()
    end, function()
        Sidebar.Toggle(5)  -- 通过抽屉系统切换到天堂商店（索引5）
    end)

    SeasonPanel.Init(drawerContent, GameManager.GetSeasonManager(), function(seasonId)
        GameManager.OnSwitchSeason(seasonId)
    end, function()
        GameManager.OnUpgradeSanta()
    end)

    ReindeerDisplay.Init(root)

    DragonPanel.Init(drawerContent, GameManager.GetDragonManager(), function()
        GameManager.OnUpgradeDragon()
    end, function(slot, auraId)
        GameManager.OnEquipDragonAura(slot, auraId)
    end, function()
        GameManager.OnPetDragon()
    end)

    SkillPanel.Init(drawerContent, GameManager)
    GameManager.SetSkillPanel(SkillPanel)

    InventoryPanel.Init(drawerContent, GameManager)
    GameManager.SetInventoryPanel(InventoryPanel)

    GardenPanel.Init(root, GameManager)
    GameManager.SetGardenPanel(GardenPanel)

    PantheonPanel.Init(root, GameManager)
    GameManager.SetPantheonPanel(PantheonPanel)

    GrimoirePanel.Init(root, GameManager)
    GameManager.SetGrimoirePanel(GrimoirePanel)

    StockMarketPanel.Init(root, GameManager)
    GameManager.SetStockMarketPanel(StockMarketPanel)

    MiningPanel.Init(root, GameManager)
    GameManager.SetMiningPanel(MiningPanel)

    FactoryPanel.Init(root, GameManager)
    GameManager.SetFactoryPanel(FactoryPanel)

    ShipmentPanel.Init(root, GameManager)
    GameManager.SetShipmentPanel(ShipmentPanel)

    ECommercePanel.Init(root, GameManager)
    GameManager.SetECommercePanel(ECommercePanel)

    SkillBar.Init(root, GameManager)

    LeaderboardPanel.Init(root)
    SettingsPanel.Init(root)

    DebugPanel.Init(root, GameManager)
    DebugPanel.SetPanelRefs({ mining = MiningPanel })

    -- 注册云存档保存成功提示
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    SlotSaveSystem.OnSaved(function()
        FloatingText.Show("已保存", screenW / 2, 68, { 120, 220, 140, 255 }, nil, 4)
    end)

    -- 注入 UI 引用到游戏管理器
    GameManager.SetUI({
        uiRoot             = root,
        statsBar           = StatsBar,
        coinArea           = CoinArea,
        shopPanel          = ShopPanel,
        luckyCoin          = LuckyCoin,
        floatingText       = FloatingText,
        coinParticle       = CoinParticle,
        achievementNotify  = AchievementNotify,
        wrinklerDisplay    = WrinklerDisplay,
        researchPanel      = ResearchPanel,
        sugarLumpDisplay   = SugarLumpDisplay,
        buildingLevelPanel = BuildingLevelPanel,
        heavenlyShop       = HeavenlyShop,
        ascensionPanel     = AscensionPanel,
        seasonPanel        = SeasonPanel,
        reindeerDisplay    = ReindeerDisplay,
        dragonPanel        = DragonPanel,
        achievementPanel   = AchievementPanel,
        inventoryPanel     = InventoryPanel,
    })

    Sidebar.UpdateHighlights()

    return root
end

--- 存档加载成功后的 UI 重刷（需要 root 引用）
function AppLayout.OnSaveLoaded(root)
    SaveBridge.SetBuildingUpgrades(GameManager.buildingUpgrades)
    GameManager.RecalcProduction()
    GameManager.RefreshAllUI()
    Sidebar.UpdateHighlights()
    ShopPanel.Init(root, Buildings.buildings, Upgrades.clickUpgrades, GameManager.buildingUpgrades)
    if GameManager.GetSugarLumpManager().IsUnlocked() then
        SugarLumpDisplay.Show(root)
    end
    AudioManager.SetBGMVolume(GameState.settings.bgmVolume)
    AudioManager.SetSFXVolume(GameState.settings.sfxVolume)
end

return AppLayout
