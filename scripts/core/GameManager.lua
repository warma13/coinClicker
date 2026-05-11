-- ============================================================================
-- core/GameManager.lua
-- 游戏逻辑调度器（精简版 - 委托子模块处理具体逻辑）
-- ============================================================================

-- 核心依赖
local GameState = require("core.GameState")
local Buildings = require("config.Buildings")
local BuildingUpgrades = require("config.BuildingUpgrades")
local AudioManager = require("core.AudioManager")
local SlotSaveSystem = require("core.SlotSaveSystem")
local AchievementManager = require("core.AchievementManager")

-- 子系统 Manager（Update 调度需要）
local GrandmapoManager = require("core.GrandmapoManager")
local WrinklerManager = require("core.WrinklerManager")
local SugarLumpManager = require("core.SugarLumpManager")
local AscensionManager = require("core.AscensionManager")
local SeasonManager = require("core.SeasonManager")
local DragonManager = require("core.DragonManager")
local GardenManager = require("core.GardenManager")
local PantheonManager = require("core.PantheonManager")
local GrimoireManager = require("core.GrimoireManager")
local StockMarketManager = require("core.StockMarketManager")
local MiningManager = require("core.MiningManager")
local FactoryManager = require("core.FactoryManager")
local ShipmentManager = require("core.ShipmentManager")
local ECommerceManager = require("core.ECommerceManager")
local SkillManager = require("core.SkillManager")
local OnlineRewardManager = require("core.OnlineRewardManager")
-- 拆分出的子模块
local ProductionCalculator = require("core.ProductionCalculator")
local LuckyCoinSystem = require("core.LuckyCoinSystem")
local PurchaseHandler = require("core.PurchaseHandler")
local SubsystemActions = require("core.SubsystemActions")

local GM = {}

-- 共享 UI 引用表（所有子模块通过 ctx.ui 共享同一引用）
local ui_ = {
    statsBar = nil,
    coinArea = nil,
    shopPanel = nil,
    luckyCoin = nil,
    floatingText = nil,
    coinParticle = nil,
    achievementNotify = nil,
    uiRoot = nil,
    wrinklerDisplay = nil,
    researchPanel = nil,
    sugarLumpDisplay = nil,
    buildingLevelPanel = nil,
    heavenlyShop = nil,
    ascensionPanel = nil,
    seasonPanel = nil,
    reindeerDisplay = nil,
    dragonPanel = nil,
    achievementPanel = nil,
    gardenPanel = nil,
    pantheonPanel = nil,
    grimoirePanel = nil,
    stockMarketPanel = nil,
    miningPanel = nil,
    factoryPanel = nil,
    shipmentPanel = nil,
    ecommercePanel = nil,
    skillPanel = nil,
    inventoryPanel = nil,

}

-- 面板刷新定时器
local timers_ = {
    garden = 0,
    pantheon = 0,
    grimoire = 0,
    stockMarket = 0,
    mining = 0,
    factory = 0,
    shipment = 0,
    ecommerce = 0,
    sugarLump = 0,
    grandmapo = 0,
    ascension = 0,
    season = 0,
    dragon = 0,
    skill = 0,

    shop = 0,
}

-- 缓存的高频 UI 引用
local achieveCountLabel_ = nil
local lastAchCountText_ = ""

--- 建筑效率升级数据（所有模块共享）
GM.buildingUpgrades = nil

-- ============================================================================
-- 初始化
-- ============================================================================

--- 初始化游戏管理器
function GM.Init()
    -- 生成建筑效率升级数据
    GM.buildingUpgrades = BuildingUpgrades.Generate(Buildings.buildings)

    -- 构建共享上下文
    local ctx = {
        ui = ui_,
        GameState = GameState,
        Buildings = Buildings,
        AudioManager = AudioManager,
        SlotSaveSystem = SlotSaveSystem,
        GM = GM,
        buildingUpgrades = GM.buildingUpgrades,
    }

    -- 初始化子模块
    LuckyCoinSystem.Init(ctx)
    PurchaseHandler.Setup(GM, ctx)
    SubsystemActions.Setup(GM, ctx)
    SubsystemActions.InitCallbacks(GM, ctx)
end

-- ============================================================================
-- UI 注入
-- ============================================================================

--- 注册 UI 模块引用（table 传参）
---@param refs table { uiRoot, statsBar, coinArea, shopPanel, luckyCoin, floatingText, coinParticle, achievementNotify, wrinklerDisplay, researchPanel, sugarLumpDisplay, buildingLevelPanel, heavenlyShop, ascensionPanel, seasonPanel, reindeerDisplay, dragonPanel, achievementPanel }
function GM.SetUI(refs)
    ui_.uiRoot              = refs.uiRoot
    ui_.statsBar            = refs.statsBar
    ui_.coinArea            = refs.coinArea
    ui_.shopPanel           = refs.shopPanel
    ui_.luckyCoin           = refs.luckyCoin
    ui_.floatingText        = refs.floatingText
    ui_.coinParticle        = refs.coinParticle
    ui_.achievementNotify   = refs.achievementNotify
    ui_.wrinklerDisplay     = refs.wrinklerDisplay
    ui_.researchPanel       = refs.researchPanel
    ui_.sugarLumpDisplay    = refs.sugarLumpDisplay
    ui_.buildingLevelPanel  = refs.buildingLevelPanel
    ui_.heavenlyShop        = refs.heavenlyShop
    ui_.ascensionPanel      = refs.ascensionPanel
    ui_.seasonPanel         = refs.seasonPanel
    ui_.reindeerDisplay     = refs.reindeerDisplay
    ui_.dragonPanel         = refs.dragonPanel
    ui_.achievementPanel    = refs.achievementPanel
    ui_.inventoryPanel      = refs.inventoryPanel
    -- 缓存高频访问的 UI 引用（避免每帧 FindById）
    achieveCountLabel_ = refs.uiRoot and refs.uiRoot:FindById("achieveCountLabel") or nil

    -- 注入 FloatingText 到 AdManager / OnlineRewardManager（SetUI 时已可用）
    local AdManager = require("core.AdManager")
    AdManager.SetFloatingText(refs.floatingText)
    OnlineRewardManager.SetFloatingText(refs.floatingText)
end

-- ============================================================================
-- 产出计算（委托 ProductionCalculator）
-- ============================================================================

--- 重新计算每秒/每次点击产出
function GM.RecalcProduction()
    ProductionCalculator.Recalculate(GM.buildingUpgrades)
end

--- 在屏幕中央显示浮动提示文字
---@param text string
---@param color? table {r,g,b,a}
---@param icon? string
function GM.ShowFloatingText(text, color, icon)
    if not ui_.floatingText then return end
    local dpr = graphics:GetDPR()
    local cx = (graphics:GetWidth() / dpr - 310) / 2
    local cy = graphics:GetHeight() / dpr / 2 - 50
    ui_.floatingText.Show(text, cx, cy, color or { 255, 220, 80, 255 }, icon)
end

-- ============================================================================
-- 幸运金币效果（委托 LuckyCoinSystem）
-- ============================================================================

--- 触发幸运金币效果（由 LuckyCoin UI 的点击回调调用）
function GM.TriggerLuckyEffect()
    LuckyCoinSystem.TriggerEffect()
end

-- ============================================================================
-- UI 刷新
-- ============================================================================

--- 刷新所有 UI
function GM.RefreshAllUI()
    if ui_.coinArea then
        ui_.coinArea.RefreshStats()
        ui_.coinArea.RefreshFormula()
    end
    if ui_.shopPanel then
        ui_.shopPanel.MarkIconBarDirty()
        ui_.shopPanel.Refresh()
    end
    if ui_.achievementPanel and ui_.achievementPanel.IsVisible() then
        ui_.achievementPanel.Refresh()
    end
    -- 状态变化后刷新 Tooltip，显示最新数据
    local Tooltip = require("ui.Tooltip")
    Tooltip.Refresh()
end

-- ============================================================================
-- 帧更新
-- ============================================================================

--- 每帧更新（由 main.lua 的 HandleUpdate 调用）
---@param dt number 帧间隔时间
function GM.Update(dt)
    local S = GameState

    -- ========== Buff 倒计时 + buff 栏刷新 ==========
    LuckyCoinSystem.UpdateBuffs(dt)

    -- ========== 幸运金币计时 ==========
    LuckyCoinSystem.UpdateLuckyCoin(dt)

    -- ========== 自动产出（逐建筑累加，追踪 totalProduced） ==========
    -- 使用 globalCpsMul 保证实际产出与 CPS 显示一致
    -- globalCpsMul 由 ProductionCalculator 计算，包含所有全局倍率
    -- 光标（建筑索引 1）：每 10 秒批量结算一次，其余建筑逐帧累加
    local gMul = S.globalCpsMul
    for bi, b in ipairs(Buildings.buildings) do
        if b.count > 0 and bi ~= 1 then
            local mul = 1
            if GM.buildingUpgrades and GM.buildingUpgrades[bi] then
                mul = BuildingUpgrades.GetMultiplier(GM.buildingUpgrades[bi])
            end
            -- 奶奶专属倍率（与 ProductionCalculator 一致）
            if b.id == "grandma" then
                mul = mul * GrandmapoManager.GetGrandmaMultiplier()
            end
            -- 糖块建筑等级加成（每级 +1%）
            mul = mul * SugarLumpManager.GetBuildingLevelMultiplier(bi)
            local bMul = LuckyCoinSystem.GetBuildingBuffMul(bi)
            local produced = b.cpsAdd * b.count * mul * gMul * S.buffCpsMul * bMul * dt
            S.coins = S.coins + produced
            b.totalProduced = b.totalProduced + produced
        end
    end

    -- 光标每 10 秒自动点击一次（结算 10 秒累计产出）
    local cursor = Buildings.buildings[1]
    if cursor and cursor.count > 0 then
        S.cursorTimer = (S.cursorTimer or 0) + dt
        if S.cursorTimer >= 10 then
            S.cursorTimer = S.cursorTimer - 10
            local mul = 1
            if GM.buildingUpgrades and GM.buildingUpgrades[1] then
                mul = BuildingUpgrades.GetMultiplier(GM.buildingUpgrades[1])
            end
            -- 糖块建筑等级加成
            mul = mul * SugarLumpManager.GetBuildingLevelMultiplier(1)
            local bMul = LuckyCoinSystem.GetBuildingBuffMul(1)
            local produced = cursor.cpsAdd * cursor.count * mul * gMul * S.buffCpsMul * bMul * 10
            S.coins = S.coins + produced
            cursor.totalProduced = cursor.totalProduced + produced
        end
    end

    -- ========== 非建筑来源的 CPS 产出（协同 + 固定加成） ==========
    local extraCps = GrandmapoManager.GetGrandmaSynergyCps()
                   + GrandmapoManager.GetPortalSynergyCps()
                   + SeasonManager.GetFixedCpsBonus()
    -- 龙光环：奶奶协同额外产出
    local grandmaSynMul = DragonManager.GetGrandmaSynergyMul()
    if grandmaSynMul > 1 then
        local grandma = Buildings.buildings[2]
        if grandma and grandma.count > 0 then
            extraCps = extraCps + grandma.cpsAdd * grandma.count * (grandmaSynMul - 1)
        end
    end
    if extraCps > 0 then
        local extraProduced = extraCps * gMul * S.buffCpsMul * dt
        S.coins = S.coins + extraProduced
    end

    -- ========== 奶奶末日 + 皱巴虫更新 ==========
    GrandmapoManager.Update(dt)

    local spawnRate = GrandmapoManager.GetWrinklerSpawnRate()
    local effectiveCps = S.coinsPerSecond * S.buffCpsMul
    local drained = WrinklerManager.Update(dt, spawnRate, effectiveCps)
    if drained > 0 then
        S.coins = math.max(0, S.coins - drained)
    end

    -- 皱巴虫显示更新
    if ui_.wrinklerDisplay then
        ui_.wrinklerDisplay.Update(dt)
    end

    -- ========== 糖块系统更新 ==========
    SugarLumpManager.Update(dt)

    timers_.sugarLump = timers_.sugarLump - dt
    if timers_.sugarLump <= 0 then
        timers_.sugarLump = 1.0
        if ui_.sugarLumpDisplay and ui_.sugarLumpDisplay.IsVisible() then
            ui_.sugarLumpDisplay.Refresh()
        end
        if ui_.buildingLevelPanel and ui_.buildingLevelPanel.IsVisible() then
            ui_.buildingLevelPanel.Refresh()
        end
    end

    -- 奶奶末日状态 + 研究面板定期刷新（每 0.5 秒）
    timers_.grandmapo = timers_.grandmapo - dt
    if timers_.grandmapo <= 0 then
        timers_.grandmapo = 0.5
        if ui_.wrinklerDisplay then
            ui_.wrinklerDisplay.RefreshStatus(
                GrandmapoManager.GetPhase(),
                WrinklerManager.GetCount(),
                WrinklerManager.GetTotalAbsorbed()
            )
        end
        if ui_.researchPanel and ui_.researchPanel.IsVisible() then
            ui_.researchPanel.Refresh()
        end
    end

    -- ========== 飞升烘焙追踪 ==========
    local frameCps = S.coinsPerSecond * S.buffCpsMul
    if frameCps > 0 then
        AscensionManager.TrackProduction(frameCps * dt)
    end

    -- 飞升面板定期刷新
    timers_.ascension = timers_.ascension - dt
    if timers_.ascension <= 0 then
        timers_.ascension = 1.0
        if ui_.ascensionPanel and ui_.ascensionPanel.IsVisible() then
            ui_.ascensionPanel.Refresh()
        end
        if ui_.heavenlyShop and ui_.heavenlyShop.IsVisible() then
            ui_.heavenlyShop.Refresh()
        end
    end

    -- ========== 季节系统更新 ==========
    SeasonManager.Update(dt)

    -- 驯鹿动画更新
    if ui_.reindeerDisplay and SeasonManager.IsReindeerActive() then
        local rx, ry = SeasonManager.GetReindeerPos()
        local stay = SeasonManager.GetReindeerStayTimer()
        ui_.reindeerDisplay.UpdateAnimation(dt, rx, ry, stay)
    end

    -- 季节面板定期刷新
    timers_.season = timers_.season - dt
    if timers_.season <= 0 then
        timers_.season = 1.0
        if ui_.seasonPanel and ui_.seasonPanel.IsVisible() then
            ui_.seasonPanel.Refresh()
        end
    end

    -- ========== 龙系统更新 ==========
    DragonManager.Update(dt)

    -- 龙面板定期刷新
    timers_.dragon = timers_.dragon - dt
    if timers_.dragon <= 0 then
        timers_.dragon = 1.0
        if ui_.dragonPanel and ui_.dragonPanel.IsVisible() then
            ui_.dragonPanel.Refresh()
        end
    end

    -- ========== 花园系统更新 ==========
    GardenManager.Update(dt)

    -- 花园面板定期刷新
    timers_.garden = timers_.garden - dt
    if timers_.garden <= 0 then
        timers_.garden = 1.0
        if ui_.gardenPanel and ui_.gardenPanel.IsVisible() then
            ui_.gardenPanel.Refresh()
        end
    end

    -- ========== 万神殿系统更新 ==========
    PantheonManager.Update(dt)

    -- 万神殿面板定期刷新
    timers_.pantheon = timers_.pantheon - dt
    if timers_.pantheon <= 0 then
        timers_.pantheon = 1.0
        if ui_.pantheonPanel and ui_.pantheonPanel.IsVisible() then
            ui_.pantheonPanel.Refresh()
        end
    end

    -- ========== 研发实验室系统更新 ==========
    GrimoireManager.Update(dt)

    -- 研发实验室面板定期刷新
    timers_.grimoire = timers_.grimoire - dt
    if timers_.grimoire <= 0 then
        timers_.grimoire = 1.0
        if ui_.grimoirePanel and ui_.grimoirePanel.IsVisible() then
            ui_.grimoirePanel.Refresh()
        end
    end

    -- ========== 证券交易所系统更新 ==========
    StockMarketManager.Update(dt)

    -- 证券交易所面板定期刷新
    timers_.stockMarket = timers_.stockMarket - dt
    if timers_.stockMarket <= 0 then
        timers_.stockMarket = 1.0
        if ui_.stockMarketPanel and ui_.stockMarketPanel.IsVisible() then
            ui_.stockMarketPanel.Refresh()
        end
    end

    -- ========== 挖矿探险系统更新 ==========
    MiningManager.Update(dt)

    -- 挖矿面板定期刷新
    timers_.mining = timers_.mining - dt
    if timers_.mining <= 0 then
        timers_.mining = 1.0
        if ui_.miningPanel and ui_.miningPanel.IsVisible() then
            ui_.miningPanel.Refresh()
        end
    end

    -- ========== 制造工厂系统更新 ==========
    FactoryManager.Update(dt)

    -- 制造工厂面板定期刷新
    timers_.factory = timers_.factory - dt
    if timers_.factory <= 0 then
        timers_.factory = 1.0
        if ui_.factoryPanel and ui_.factoryPanel.IsVisible() then
            ui_.factoryPanel.Refresh()
        end
    end

    -- ========== 国际物流系统更新 ==========
    ShipmentManager.Update(dt)

    -- 国际物流面板定期刷新
    timers_.shipment = timers_.shipment - dt
    if timers_.shipment <= 0 then
        timers_.shipment = 1.0
        if ui_.shipmentPanel and ui_.shipmentPanel.IsVisible() then
            ui_.shipmentPanel.Refresh()
        end
    end

    -- ========== 电商平台系统更新 ==========
    ECommerceManager.Update(dt)

    -- 电商平台面板定期刷新
    timers_.ecommerce = timers_.ecommerce - dt
    if timers_.ecommerce <= 0 then
        timers_.ecommerce = 1.0
        if ui_.ecommercePanel and ui_.ecommercePanel.IsVisible() then
            ui_.ecommercePanel.Refresh()
        end
    end

    -- ========== 点击缩放动画 ==========
    if ui_.coinArea then
        ui_.coinArea.Update(dt)
    end

    -- ========== 金币粒子更新 ==========
    if ui_.coinParticle then
        ui_.coinParticle.Update(dt)
    end

    -- ========== 浮动文本更新 ==========
    if ui_.floatingText then
        ui_.floatingText.Update(dt)
    end

    -- ========== 更新金币区域显示 ==========
    if ui_.coinArea then
        ui_.coinArea.RefreshStats()
        ui_.coinArea.RefreshFormula()
    end

    -- ========== 更新成就计数标签（增量） ==========
    if achieveCountLabel_ then
        local achText = AchievementManager.GetUnlockedCount() .. "/" .. AchievementManager.GetTotalCount()
        if achText ~= lastAchCountText_ then
            lastAchCountText_ = achText
            achieveCountLabel_:SetText(achText)
        end
    end

    -- ========== 技能系统更新 ==========
    SkillManager.Update(dt)

    -- 技能面板定期刷新
    timers_.skill = timers_.skill - dt
    if timers_.skill <= 0 then
        timers_.skill = 0.3
        if ui_.skillPanel and ui_.skillPanel.IsVisible() then
            ui_.skillPanel.Refresh()
        end
    end

    -- ========== 在线奖励计时 ==========
    OnlineRewardManager.Update(dt)

    -- ========== 成就检查 ==========
    AchievementManager.Update(dt, GM.buildingUpgrades)

    -- ========== 成就通知更新 ==========
    if ui_.achievementNotify then
        ui_.achievementNotify.Update(dt)
    end

    -- ========== 定期刷新商店（降频：0.3 秒一次） ==========
    timers_.shop = timers_.shop - dt
    if timers_.shop <= 0 then
        timers_.shop = 0.3
        if ui_.shopPanel then
            -- 标记图标栏脏，确保新解锁的升级能及时出现
            ui_.shopPanel.MarkIconBarDirty()
            -- 每次都刷新（图标栏 afford 检查 + 建筑列表增量更新）
            ui_.shopPanel.Refresh()
        end
    end

    -- ========== 更新历史最高金币（用于排行榜） ==========
    if S.coins > S.maxCoins then
        S.maxCoins = S.coins
    end
end

return GM
