-- ============================================================================
-- core/SubsystemActions.lua
-- Subsystem delegator functions & manager callback registrations
-- Extracted from GameManager.lua
-- ============================================================================

local AchievementManager = require("core.AchievementManager")
local GrandmapoManager   = require("core.GrandmapoManager")
local WrinklerManager    = require("core.WrinklerManager")
local SugarLumpManager   = require("core.SugarLumpManager")
local AscensionManager   = require("core.AscensionManager")
local SeasonManager      = require("core.SeasonManager")
local DragonManager      = require("core.DragonManager")
local GardenManager      = require("core.GardenManager")
local PantheonManager    = require("core.PantheonManager")
local GrimoireManager    = require("core.GrimoireManager")
local StockMarketManager = require("core.StockMarketManager")
local MiningManager      = require("core.MiningManager")
local FactoryManager     = require("core.FactoryManager")
local ShipmentManager    = require("core.ShipmentManager")
local ECommerceManager   = require("core.ECommerceManager")
local ECommerceConfig    = require("config.ECommerceConfig")
local SkillManager       = require("core.SkillManager")
local InventoryManager   = require("core.InventoryManager")
local AdManager          = require("core.AdManager")
local AudioManager       = require("core.AudioManager")
local SlotSaveSystem     = require("core.SlotSaveSystem")
local GameState          = require("core.GameState")
local SaveBridge         = require("core.SaveBridge")
local Buildings          = require("config.Buildings")
local BuildingUpgrades   = require("config.BuildingUpgrades")

local M = {}

-- ---------------------------------------------------------------------------
-- M.Setup(GM, ctx)
-- Registers all subsystem delegator functions directly on the GM table.
-- ctx = { ui = { floatingText, heavenlyShop, ascensionPanel, gardenPanel,
--                pantheonPanel, grimoirePanel, stockMarketPanel, miningPanel,
--                factoryPanel, shipmentPanel, ecommercePanel, skillPanel,
--                sugarLumpDisplay, uiRoot, wrinklerDisplay, researchPanel,
--                dragonPanel, seasonPanel, reindeerDisplay, achievementPanel } }
-- ---------------------------------------------------------------------------
function M.Setup(GM, ctx)

    -- ========================================================================
    -- 成就 / 研究 / 糖块
    -- ========================================================================

    function GM.OnBuyKitten(index)
        if AchievementManager.BuyKitten(index) then
            GM.RecalcProduction()
            GM.RefreshAllUI()
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
        end
    end

    ---@return table AchievementManager
    function GM.GetAchievementManager()
        return AchievementManager
    end

    ---@param index number
    function GM.OnBuyResearch(index)
        if GrandmapoManager.BuyResearch(index) then
            GM.RecalcProduction()
            GM.RefreshAllUI()
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
        end
    end

    function GM.OnBuyPledge()
        if GrandmapoManager.BuyPledge() then
            GM.RefreshAllUI()
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
        end
    end

    ---@return table GrandmapoManager
    function GM.GetGrandmapoManager()
        return GrandmapoManager
    end

    ---@return table WrinklerManager
    function GM.GetWrinklerManager()
        return WrinklerManager
    end

    ---@return table SugarLumpManager
    function GM.GetSugarLumpManager()
        return SugarLumpManager
    end

    function GM.OnHarvestSugarLump()
        local success, amount, reason = SugarLumpManager.TryHarvest()
        if success then
            GM.RecalcProduction()
            GM.RefreshAllUI()
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
        elseif reason == "碎裂" then
            if ctx.ui.floatingText then
                local dpr = graphics:GetDPR()
                local cx = (graphics:GetWidth() / dpr - 310) / 2
                local cy = graphics:GetHeight() / dpr / 2 - 80
                ctx.ui.floatingText.Show("碎裂了!", cx, cy, { 255, 100, 100, 255 })
            end
        elseif reason == "尚未成熟" then
            if ctx.ui.floatingText then
                local dpr = graphics:GetDPR()
                local cx = (graphics:GetWidth() / dpr - 310) / 2
                local cy = graphics:GetHeight() / dpr / 2 - 80
                ctx.ui.floatingText.Show("还没成熟", cx, cy, { 180, 180, 200, 200 })
            end
        end
    end

    ---@param buildingIndex number
    function GM.OnUpgradeBuildingLevel(buildingIndex)
        if SugarLumpManager.UpgradeBuilding(buildingIndex) then
            GM.RecalcProduction()
            GM.RefreshAllUI()
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
        end
    end

    -- ========================================================================
    -- 飞升系统
    -- ========================================================================

    ---@return table AscensionManager
    function GM.GetAscensionManager()
        return AscensionManager
    end

    ---@param upgradeId string
    function GM.OnBuyHeavenlyUpgrade(upgradeId)
        if AscensionManager.BuyUpgrade(upgradeId) then
            GM.RecalcProduction()
            GM.RefreshAllUI()
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
            if ctx.ui.heavenlyShop and ctx.ui.heavenlyShop.IsVisible() then
                ctx.ui.heavenlyShop.Refresh()
            end
        end
    end

    function GM.OnAscend()
        local gainedChips, newPrestige = AscensionManager.DoAscend()

        -- 关闭飞升面板
        if ctx.ui.ascensionPanel and ctx.ui.ascensionPanel.IsVisible() then
            ctx.ui.ascensionPanel.Hide()
        end

        -- 显示浮动提示
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 50
            if gainedChips > 0 then
                ctx.ui.floatingText.Show("飞升! +" .. gainedChips .. " 经验值", cx, cy, { 200, 170, 255, 255 })
            end
        end

        -- 飞升是关键事件，立即保存
        SlotSaveSystem.SaveNow()
    end

    -- ========================================================================
    -- 季节系统
    -- ========================================================================

    ---@return table SeasonManager
    function GM.GetSeasonManager()
        return SeasonManager
    end

    ---@param seasonId string
    function GM.OnSwitchSeason(seasonId)
        local success, reason = SeasonManager.SwitchSeason(seasonId)
        if success then
            GM.RecalcProduction()
            GM.RefreshAllUI()
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
        else
            if ctx.ui.floatingText and reason then
                local dpr = graphics:GetDPR()
                local cx = (graphics:GetWidth() / dpr - 310) / 2
                local cy = graphics:GetHeight() / dpr / 2 - 40
                local msg = "切换失败"
                if reason == "no_switcher" then
                    msg = "需先购买「周期切换器」"
                elseif reason == "not_enough" then
                    msg = "金币不足"
                end
                ctx.ui.floatingText.Show(msg, cx, cy, { 255, 100, 100, 255 })
            end
        end
    end

    function GM.OnUpgradeSanta()
        local success, unlocked = SeasonManager.UpgradeSanta()
        if success then
            GM.RecalcProduction()
            GM.RefreshAllUI()
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
        end
    end

    function GM.OnClickReindeer()
        SeasonManager.ClickReindeer()
        AudioManager.PlayBtnClick()
    end

    -- ========================================================================
    -- 龙系统
    -- ========================================================================

    ---@return table DragonManager
    function GM.GetDragonManager()
        return DragonManager
    end

    function GM.OnUpgradeDragon()
        local dm = DragonManager
        if dm.GetLevel() < 0 then
            dm.BuyEgg()
        else
            dm.Upgrade()
        end
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        AudioManager.PlayBtnClick()
    end

    ---@param slot number 1 or 2
    ---@param auraId string|nil
    function GM.OnEquipDragonAura(slot, auraId)
        DragonManager.EquipAura(slot, auraId)
        SlotSaveSystem.MarkDirty()
        AudioManager.PlayBtnClick()
    end

    function GM.OnPetDragon()
        DragonManager.PetDragon()
        AudioManager.PlayBtnClick()
    end

    -- ========================================================================
    -- 花园系统
    -- ========================================================================

    ---@return table GardenManager
    function GM.GetGardenManager()
        return GardenManager
    end

    ---@param panel table GardenPanel 模块
    function GM.SetGardenPanel(panel)
        ctx.ui.gardenPanel = panel
    end

    -- ========================================================================
    -- 万神殿系统
    -- ========================================================================

    ---@return table PantheonManager
    function GM.GetPantheonManager()
        return PantheonManager
    end

    ---@param panel table PantheonPanel 模块
    function GM.SetPantheonPanel(panel)
        ctx.ui.pantheonPanel = panel
    end

    -- ========================================================================
    -- 研发实验室系统
    -- ========================================================================

    ---@return table GrimoireManager
    function GM.GetGrimoireManager()
        return GrimoireManager
    end

    ---@param panel table GrimoirePanel 模块
    function GM.SetGrimoirePanel(panel)
        ctx.ui.grimoirePanel = panel
    end

    -- ========================================================================
    -- 证券交易所系统
    -- ========================================================================

    ---@return table StockMarketManager
    function GM.GetStockMarketManager()
        return StockMarketManager
    end

    ---@param panel table StockMarketPanel 模块
    function GM.SetStockMarketPanel(panel)
        ctx.ui.stockMarketPanel = panel
    end

    -- ========================================================================
    -- 研发施法 / 花园操作
    -- ========================================================================

    ---@param spellId string
    ---@return table|nil result
    function GM.OnCastSpell(spellId)
        local result = GrimoireManager.CastSpell(spellId)
        if result then
            -- 同步建筑费用乘数到 GameState（供 OnBuyBuilding 使用）
            GameState.buffBuildingCostMul = GrimoireManager.GetBuildingPriceMul()
            GM.RecalcProduction()
            GM.RefreshAllUI()
            SlotSaveSystem.MarkDirty()
        end
        return result
    end

    ---@param row number
    ---@param col number
    ---@param seedId string
    function GM.OnGardenPlant(row, col, seedId)
        if GardenManager.Plant(row, col, seedId) then
            SlotSaveSystem.MarkDirty()
            if ctx.ui.gardenPanel and ctx.ui.gardenPanel.IsVisible() then
                ctx.ui.gardenPanel.Refresh()
            end
        end
    end

    ---@param row number
    ---@param col number
    function GM.OnGardenHarvest(row, col)
        if GardenManager.Harvest(row, col) then
            -- 回调已处理 RecalcProduction/RefreshAllUI/MarkDirty
            if ctx.ui.gardenPanel and ctx.ui.gardenPanel.IsVisible() then
                ctx.ui.gardenPanel.Refresh()
            end
        end
    end

    ---@param row number
    ---@param col number
    function GM.OnGardenClear(row, col)
        if GardenManager.ClearPlot(row, col) then
            SlotSaveSystem.MarkDirty()
            if ctx.ui.gardenPanel and ctx.ui.gardenPanel.IsVisible() then
                ctx.ui.gardenPanel.Refresh()
            end
        end
    end

    ---@param soilId string
    function GM.OnGardenSwitchSoil(soilId)
        local ok, reason = GardenManager.SwitchSoil(soilId)
        if ok then
            SlotSaveSystem.MarkDirty()
            if ctx.ui.gardenPanel and ctx.ui.gardenPanel.IsVisible() then
                ctx.ui.gardenPanel.Refresh()
            end
        elseif ctx.ui.floatingText and reason then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 40
            local msg = "切换失败"
            if reason == "cooling" then msg = "冷却中" end
            ctx.ui.floatingText.Show(msg, cx, cy, { 255, 100, 100, 255 })
        end
    end

    function GM.OnGardenExpand()
        local GC = require("config.GardenConfig")
        local currentSize = GardenManager.GetGridSize()
        local cost = GC.GetExpandCost(currentSize + 1)
        if not cost then
            if ctx.ui.floatingText then
                local dpr = graphics:GetDPR()
                local cx = (graphics:GetWidth() / dpr - 310) / 2
                local cy = graphics:GetHeight() / dpr / 2 - 40
                ctx.ui.floatingText.Show("已达最大尺寸", cx, cy, { 180, 180, 200, 200 })
            end
            return
        end
        if SugarLumpManager.GetLumps() < cost then
            if ctx.ui.floatingText then
                local dpr = graphics:GetDPR()
                local cx = (graphics:GetWidth() / dpr - 310) / 2
                local cy = graphics:GetHeight() / dpr / 2 - 40
                ctx.ui.floatingText.Show("经验不足 (需要 " .. cost .. ")", cx, cy, { 255, 100, 100, 255 })
            end
            return
        end
        SugarLumpManager.AddLumps(-cost)
        if GardenManager.ExpandGrid() then
            SlotSaveSystem.MarkDirty()
            if ctx.ui.gardenPanel and ctx.ui.gardenPanel.IsVisible() then
                ctx.ui.gardenPanel.Refresh()
            end
            if ctx.ui.floatingText then
                local dpr = graphics:GetDPR()
                local cx = (graphics:GetWidth() / dpr - 310) / 2
                local cy = graphics:GetHeight() / dpr / 2 - 60
                ctx.ui.floatingText.Show("花园扩展到 " .. GardenManager.GetGridSize() .. "x" .. GardenManager.GetGridSize(),
                    cx, cy, { 100, 220, 200, 255 })
            end
        end
    end

    -- ========================================================================
    -- 技能系统
    -- ========================================================================

    ---@return table SkillManager
    function GM.GetSkillManager()
        return SkillManager
    end

    ---@param panel table SkillPanel 模块
    function GM.SetSkillPanel(panel)
        ctx.ui.skillPanel = panel
    end

    ---@param skillId string
    function GM.OnActivateSkill(skillId)
        SkillManager.ActivateWithAd(skillId, function(ok)
            if ok then
                AudioManager.PlayBtnClick()
                if ctx.ui.skillPanel and ctx.ui.skillPanel.Refresh then
                    ctx.ui.skillPanel.Refresh()
                end
            end
        end)
    end

    -- ========================================================================
    -- 挖矿探险系统
    -- ========================================================================

    ---@return table MiningManager
    function GM.GetMiningManager()
        return MiningManager
    end

    ---@param panel table MiningPanel 模块
    function GM.SetMiningPanel(panel)
        ctx.ui.miningPanel = panel
    end

    -- ========================================================================
    -- 制造工厂系统
    -- ========================================================================

    ---@return table FactoryManager
    function GM.GetFactoryManager()
        return FactoryManager
    end

    ---@param panel table FactoryPanel 模块
    function GM.SetFactoryPanel(panel)
        ctx.ui.factoryPanel = panel
    end

    -- ========================================================================
    -- 国际物流系统
    -- ========================================================================

    ---@return table ShipmentManager
    function GM.GetShipmentManager()
        return ShipmentManager
    end

    ---@param panel table ShipmentPanel 模块
    function GM.SetShipmentPanel(panel)
        ctx.ui.shipmentPanel = panel
    end

    -- ========================================================================
    -- 电商平台系统
    -- ========================================================================

    ---@return table ECommerceManager
    function GM.GetECommerceManager()
        return ECommerceManager
    end

    ---@param panel table ECommercePanel 模块
    function GM.SetECommercePanel(panel)
        ctx.ui.ecommercePanel = panel
    end

    -- ========================================================================
    -- 技能升级 / 解锁
    -- ========================================================================

    ---@param skillId string
    function GM.OnUpgradeSkill(skillId)
        local info = SkillManager.GetSkillInfo(skillId)
        if not info then return end

        if info.level <= 0 then
            -- 解锁（免费）
            SkillManager.UnlockSkill(skillId, function(ok)
                if ok then
                    GM.RecalcProduction()
                    SlotSaveSystem.MarkDirty()
                    AudioManager.PlayBtnClick()
                    if ctx.ui.skillPanel and ctx.ui.skillPanel.Refresh then
                        ctx.ui.skillPanel.Refresh()
                    end
                end
            end)
        else
            -- 升级：免费
            if SkillManager.UpgradeSkill(skillId) then
                GM.RecalcProduction()
                SlotSaveSystem.MarkDirty()
                AudioManager.PlayBtnClick()
                if ctx.ui.skillPanel and ctx.ui.skillPanel.Refresh then
                    ctx.ui.skillPanel.Refresh()
                end
            end
        end
    end

    -- ========================================================================
    -- 仓库系统
    -- ========================================================================

    ---@return table InventoryManager
    function GM.GetInventoryManager()
        return InventoryManager
    end

    ---@param panel table InventoryPanel 模块
    function GM.SetInventoryPanel(panel)
        ctx.ui.inventoryPanel = panel
    end

    ---@param slotIndex number
    function GM.OnUseItem(slotIndex)
        local ok, msg = InventoryManager.UseItem(slotIndex)
        if ok then
            GM.RecalcProduction()
            GM.RefreshAllUI()
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
            if ctx.ui.inventoryPanel and ctx.ui.inventoryPanel.IsVisible() then
                ctx.ui.inventoryPanel.Refresh()
            end
            -- 浮动文字由 SetOnItemUsed 回调统一处理，此处不再重复显示
        end
    end

    ---@param itemId string
    ---@param count number
    function GM.OnAddItem(itemId, count)
        local ok = InventoryManager.AddItem(itemId, count or 1)
        if ok then
            SlotSaveSystem.MarkDirty()
            if ctx.ui.inventoryPanel and ctx.ui.inventoryPanel.IsVisible() then
                ctx.ui.inventoryPanel.Refresh()
            end
        end
        return ok
    end

    ---@param slotIndex number
    ---@param count number|nil
    function GM.OnDiscardItem(slotIndex, count)
        local ok = InventoryManager.RemoveItem(slotIndex, count or 1)
        if ok then
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
            if ctx.ui.inventoryPanel and ctx.ui.inventoryPanel.IsVisible() then
                ctx.ui.inventoryPanel.Refresh()
            end
        end
        return ok
    end
end

-- ---------------------------------------------------------------------------
-- M.InitCallbacks(GM, ctx)
-- Registers all manager Init() calls and SetOnXxx callback registrations.
-- Must be called during GM.Init() after basic setup is done.
-- ---------------------------------------------------------------------------
function M.InitCallbacks(GM, ctx)

    -- 初始化成就系统
    AchievementManager.Init()
    AchievementManager.SetOnUnlock(function(achievement)
        if ctx.ui.achievementNotify then
            ctx.ui.achievementNotify.Enqueue(achievement)
        end
        -- 成就解锁后重新计算产出（Kitten 倍率可能变化）
        GM.RecalcProduction()
        GM.RefreshAllUI()
    end)

    -- 初始化奶奶末日系统
    GrandmapoManager.Init()
    WrinklerManager.Init()

    GrandmapoManager.SetOnPhaseChange(function(newPhase)
        GM.RecalcProduction()
    end)

    -- 初始化糖块系统
    SugarLumpManager.Init()
    SugarLumpManager.SetOnHarvest(function(amount, lumpType)
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 80
            ctx.ui.floatingText.Show("人脉 +" .. amount, cx, cy, lumpType.color or { 255, 200, 230, 255 })
        end
        GM.RecalcProduction()
    end)
    SugarLumpManager.SetOnUnlock(function()
        print("[GameManager] 糖块系统已解锁！")
        if ctx.ui.sugarLumpDisplay and ctx.ui.uiRoot then
            ctx.ui.sugarLumpDisplay.Show(ctx.ui.uiRoot)
            ctx.ui.sugarLumpDisplay.Refresh()
        end
    end)

    -- 初始化飞升系统
    AscensionManager.Init()
    AscensionManager.SetOnAscend(function(newPrestige, gainedChips)
        print("[GameManager] 飞升完成! 声望:" .. newPrestige .. " 芯片+" .. gainedChips)
        -- 飞升后重置附属系统
        GrandmapoManager.Init()
        WrinklerManager.Init()
        GardenManager.ResetForAscension()
        PantheonManager.ResetForAscension()
        GrimoireManager.ResetForAscension()
        StockMarketManager.ResetForAscension()
        MiningManager.ResetForAscension()
        FactoryManager.ResetForAscension()
        ShipmentManager.ResetForAscension()
        ECommerceManager.ResetForAscension()
        InventoryManager.ResetForAscension()
        -- 重新生成建筑升级数据（建筑已重置）
        GM.buildingUpgrades = BuildingUpgrades.Generate(Buildings.buildings)
        -- 同步更新 SaveBridge 的引用（飞升后 buildingUpgrades 已重新生成）
        SaveBridge.SetBuildingUpgrades(GM.buildingUpgrades)
        GM.RecalcProduction()
        GM.RefreshAllUI()
    end)
    AscensionManager.SetOnBuyUpgrade(function(upgrade)
        GM.RecalcProduction()
        GM.RefreshAllUI()
    end)

    -- 初始化季节系统
    SeasonManager.Init()
    SeasonManager.SetOnSeasonChange(function(newSeason)
        GM.RecalcProduction()
        GM.RefreshAllUI()
        if ctx.ui.seasonPanel and ctx.ui.seasonPanel.IsVisible() then
            ctx.ui.seasonPanel.Refresh()
        end
    end)
    SeasonManager.SetOnCollect(function(item)
        GM.RecalcProduction()
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 60
            ctx.ui.floatingText.Show("收获 " .. item.name, cx, cy, { 255, 220, 100, 255 }, item.icon)
        end
    end)
    SeasonManager.SetOnSantaLevelUp(function(newLevel, unlockedUpgrade)
        GM.RecalcProduction()
        if ctx.ui.floatingText and unlockedUpgrade then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 60
            ctx.ui.floatingText.Show("解锁 " .. unlockedUpgrade.name, cx, cy, { 255, 180, 100, 255 }, unlockedUpgrade.icon)
        end
    end)
    SeasonManager.SetOnReindeerSpawn(function(x, y)
        if ctx.ui.reindeerDisplay then
            ctx.ui.reindeerDisplay.Show(x, y)
        end
    end)
    SeasonManager.SetOnReindeerClick(function(reward, droppedCookie)
        if ctx.ui.reindeerDisplay then
            ctx.ui.reindeerDisplay.Hide()
        end
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 40
            ctx.ui.floatingText.Show("+" .. GameState.FormatNumber(reward), cx, cy, { 139, 200, 80, 255 }, "image/icon_reindeer.png")
        end
    end)
    SeasonManager.SetOnReindeerExpire(function()
        if ctx.ui.reindeerDisplay then
            ctx.ui.reindeerDisplay.Hide()
        end
    end)

    -- 初始化龙系统
    DragonManager.Init()
    DragonManager.SetOnLevelUp(function(newLevel, auraUnlocked)
        GM.RecalcProduction()
        GM.RefreshAllUI()
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 60
            local text = "龙 Lv." .. newLevel
            if auraUnlocked then
                text = text .. " " .. auraUnlocked.name
            end
            ctx.ui.floatingText.Show(text, cx, cy, { 240, 200, 80, 255 })
        end
    end)
    DragonManager.SetOnEquipAura(function(slot, auraId)
        GM.RecalcProduction()
        GM.RefreshAllUI()
    end)
    DragonManager.SetOnDrop(function(dropItem)
        GM.RecalcProduction()
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 40
            ctx.ui.floatingText.Show(dropItem.name .. "!", cx, cy, { 220, 180, 80, 255 })
        end
    end)

    -- 皱巴虫弹出时尝试万圣节/复活节掉落
    WrinklerManager.SetOnPop(function(wrinkler, reward)
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 30
            ctx.ui.floatingText.Show("+" .. GameState.FormatNumber(reward), cx, cy, { 100, 255, 100, 255 }, "image/金币.png")
        end
        -- 季节掉落
        SeasonManager.TryHalloweenDrop()
        SeasonManager.TryEasterDrop("wrinkler")
    end)

    -- 初始化花园系统
    GardenManager.Init()
    GardenManager.SetOnHarvest(function(seedDef, coins, buff)
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 60
            ctx.ui.floatingText.Show("收获 " .. seedDef.name .. " +" .. GameState.FormatNumber(coins),
                cx, cy, { 100, 220, 120, 255 })
        end
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
    end)
    GardenManager.SetOnDiscover(function(seedId)
        local seedDef = require("config.GardenConfig").FindSeed(seedId)
        if ctx.ui.floatingText and seedDef then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 80
            ctx.ui.floatingText.Show("新品种: " .. seedDef.name .. "!", cx, cy, { 255, 220, 80, 255 })
        end
        SlotSaveSystem.MarkDirty()
    end)
    GardenManager.SetOnBugAttack(function(count)
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 40
            ctx.ui.floatingText.Show("罢工! 损失 " .. count .. " 个项目", cx, cy, { 255, 80, 80, 255 })
        end
        SlotSaveSystem.MarkDirty()
    end)

    -- 初始化万神殿系统
    PantheonManager.Init()
    PantheonManager.SetOnSlotChanged(function()
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        if ctx.ui.pantheonPanel and ctx.ui.pantheonPanel.IsVisible() then
            ctx.ui.pantheonPanel.Refresh()
        end
    end)

    -- 初始化研发实验室系统
    GrimoireManager.Init()
    GrimoireManager.SetOnSpellCast(function(spellId, success, desc)
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        if ctx.ui.grimoirePanel and ctx.ui.grimoirePanel.IsVisible() then
            ctx.ui.grimoirePanel.Refresh()
        end
    end)

    -- 初始化证券交易所系统
    StockMarketManager.Init()
    StockMarketManager.SetOnTradeComplete(function()
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        if ctx.ui.stockMarketPanel and ctx.ui.stockMarketPanel.IsVisible() then
            ctx.ui.stockMarketPanel.Refresh()
        end
    end)
    StockMarketManager.SetOnTickUpdate(function()
        if ctx.ui.stockMarketPanel and ctx.ui.stockMarketPanel.IsVisible() then
            ctx.ui.stockMarketPanel.Refresh()
        end
    end)

    -- 初始化挖矿探险系统
    MiningManager.Init()
    MiningManager.SetOnDig(function(row, col, cell, reward)
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = graphics:GetWidth() / dpr * 0.5
            local cy = graphics:GetHeight() / dpr * 0.15
            if reward > 0 then
                ctx.ui.floatingText.Show("挖到矿石 +" .. GameState.FormatNumber(reward), cx, cy, { 255, 200, 80, 255 })
            end
        end
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        if ctx.ui.miningPanel and ctx.ui.miningPanel.IsVisible() then
            ctx.ui.miningPanel.Refresh()
        end
    end)
    MiningManager.SetOnCollapse(function()
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = graphics:GetWidth() / dpr * 0.5
            local cy = graphics:GetHeight() / dpr * 0.15
            ctx.ui.floatingText.Show("矿区塌方! 损失金币", cx, cy, { 255, 80, 80, 255 })
        end
        SlotSaveSystem.MarkDirty()
        if ctx.ui.miningPanel and ctx.ui.miningPanel.IsVisible() then
            ctx.ui.miningPanel.Refresh()
        end
    end)
    MiningManager.SetOnRefresh(function()
        SlotSaveSystem.MarkDirty()
        if ctx.ui.miningPanel and ctx.ui.miningPanel.IsVisible() then
            ctx.ui.miningPanel.Refresh()
        end
    end)
    MiningManager.SetOnFullClear(function(bonus)
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = graphics:GetWidth() / dpr * 0.5
            local cy = graphics:GetHeight() / dpr * 0.15
            ctx.ui.floatingText.Show("矿区全清! +" .. GameState.FormatNumber(bonus), cx, cy, { 100, 255, 200, 255 })
        end
        SlotSaveSystem.MarkDirty()
        if ctx.ui.miningPanel and ctx.ui.miningPanel.IsVisible() then
            ctx.ui.miningPanel.Refresh()
        end
    end)

    -- 初始化制造工厂系统
    FactoryManager.Init()
    FactoryManager.SetOnDeliver(function(order, reward, streakBuff, def)
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = graphics:GetWidth() / dpr * 0.5
            local cy = graphics:GetHeight() / dpr * 0.15
            local orderName = def and def.name or "订单"
            ctx.ui.floatingText.Show("交付 " .. orderName .. " +" .. GameState.FormatNumber(reward), cx, cy, { 100, 200, 255, 255 })
        end
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        if ctx.ui.factoryPanel and ctx.ui.factoryPanel.IsVisible() then
            ctx.ui.factoryPanel.Refresh()
        end
    end)
    FactoryManager.SetOnGather(function(success, itemId, amount)
        if ctx.ui.floatingText and success and itemId then
            local dpr = graphics:GetDPR()
            local cx = graphics:GetWidth() / dpr * 0.5
            local cy = graphics:GetHeight() / dpr * 0.20
            local FC = require("config.FactoryConfig")
            local item = FC.itemMap[itemId]
            local itemName = item and item.name or itemId
            local itemIcon = item and item.icon or nil
            ctx.ui.floatingText.Show(itemName .. " +" .. amount, cx, cy, { 80, 200, 120, 255 }, itemIcon)
        end
        SlotSaveSystem.MarkDirty()
        if ctx.ui.factoryPanel and ctx.ui.factoryPanel.IsVisible() then
            ctx.ui.factoryPanel.Refresh()
        end
    end)
    FactoryManager.SetOnCraftComplete(function(recipe, actualAmount)
        if ctx.ui.floatingText and recipe then
            local dpr = graphics:GetDPR()
            local cx = graphics:GetWidth() / dpr * 0.5
            local cy = graphics:GetHeight() / dpr * 0.20
            local FC = require("config.FactoryConfig")
            local item = FC.itemMap[recipe.output]
            local itemName = item and item.name or recipe.output
            local itemIcon = item and item.icon or nil
            ctx.ui.floatingText.Show("合成完成 " .. itemName, cx, cy, { 80, 200, 200, 255 }, itemIcon)
        end
        SlotSaveSystem.MarkDirty()
        if ctx.ui.factoryPanel and ctx.ui.factoryPanel.IsVisible() then
            ctx.ui.factoryPanel.Refresh()
        end
    end)
    FactoryManager.SetOnLevelUp(function(newLevel)
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = graphics:GetWidth() / dpr * 0.5
            local cy = graphics:GetHeight() / dpr * 0.12
            ctx.ui.floatingText.Show("🏭 工厂升级 Lv." .. newLevel, cx, cy, { 255, 215, 0, 255 })
        end
        SlotSaveSystem.MarkDirty()
        if ctx.ui.factoryPanel and ctx.ui.factoryPanel.IsVisible() then
            ctx.ui.factoryPanel.Refresh()
        end
    end)
    -- 初始化国际物流系统
    ShipmentManager.Init()
    ShipmentManager.SetOnDeliver(function(cargo, reward, wasDelayed)
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = graphics:GetWidth() / dpr * 0.5
            local cy = graphics:GetHeight() / dpr * 0.15
            local cargoName = cargo.name or cargo.defId or "货物"
            local msg = wasDelayed and ("延误送达 " .. cargoName .. " +" .. GameState.FormatNumber(reward))
                or ("安全送达 " .. cargoName .. " +" .. GameState.FormatNumber(reward))
            local color = wasDelayed and { 255, 180, 80, 255 } or { 100, 200, 255, 255 }
            ctx.ui.floatingText.Show(msg, cx, cy, color)
        end
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        if ctx.ui.shipmentPanel and ctx.ui.shipmentPanel.IsVisible() then
            ctx.ui.shipmentPanel.Refresh()
        end
    end)
    ShipmentManager.SetOnDelay(function(cargo)
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = graphics:GetWidth() / dpr * 0.5
            local cy = graphics:GetHeight() / dpr * 0.2
            ctx.ui.floatingText.Show("⚠ " .. (cargo.name or "货物") .. " 运输延误!", cx, cy, { 255, 150, 50, 255 })
        end
        if ctx.ui.shipmentPanel and ctx.ui.shipmentPanel.IsVisible() then
            ctx.ui.shipmentPanel.Refresh()
        end
    end)
    ShipmentManager.SetOnRefresh(function()
        SlotSaveSystem.MarkDirty()
        if ctx.ui.shipmentPanel and ctx.ui.shipmentPanel.IsVisible() then
            ctx.ui.shipmentPanel.Refresh()
        end
    end)

    -- 初始化电商平台系统
    ECommerceManager.Init()
    ECommerceManager.SetOnSold(function(product, reward)
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = graphics:GetWidth() / dpr * 0.5
            local cy = graphics:GetHeight() / dpr * 0.15
            local itemDef = ECommerceConfig.itemMap[product.itemId]
            local itemName = itemDef and itemDef.name or "商品"
            ctx.ui.floatingText.Show("售出 " .. itemName .. " +" .. GameState.FormatNumber(reward), cx, cy, { 180, 120, 255, 255 })
        end
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        if ctx.ui.ecommercePanel and ctx.ui.ecommercePanel.IsVisible() then
            ctx.ui.ecommercePanel.Refresh()
        end
    end)
    ECommerceManager.SetOnExpired(function(product)
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = graphics:GetWidth() / dpr * 0.5
            local cy = graphics:GetHeight() / dpr * 0.15
            local itemDef = ECommerceConfig.itemMap[product.itemId]
            local itemName = itemDef and itemDef.name or "商品"
            ctx.ui.floatingText.Show("商品过期: " .. itemName, cx, cy, { 255, 150, 80, 255 })
        end
        SlotSaveSystem.MarkDirty()
        if ctx.ui.ecommercePanel and ctx.ui.ecommercePanel.IsVisible() then
            ctx.ui.ecommercePanel.Refresh()
        end
    end)
    ECommerceManager.SetOnRefresh(function()
        SlotSaveSystem.MarkDirty()
        if ctx.ui.ecommercePanel and ctx.ui.ecommercePanel.IsVisible() then
            ctx.ui.ecommercePanel.Refresh()
        end
    end)

    -- 初始化仓库系统
    InventoryManager.Init()
    InventoryManager.SetOnItemUsed(function(slotIndex, itemDef, effectDesc)
        if ctx.ui.floatingText and itemDef then
            local dpr = graphics:GetDPR()
            local cx = graphics:GetWidth() / dpr * 0.5
            local cy = graphics:GetHeight() / dpr * 0.15
            local msg = "使用了 " .. itemDef.name
            if effectDesc and effectDesc ~= "" then
                msg = msg .. "，" .. effectDesc
            end
            ctx.ui.floatingText.Show(msg, cx, cy, { 255, 220, 100, 255 })
        end
    end)
    InventoryManager.SetOnItemAdded(function(itemDef, count)
        if ctx.ui.floatingText then
            local dpr = graphics:GetDPR()
            local cx = graphics:GetWidth() / dpr * 0.5
            local cy = graphics:GetHeight() / dpr * 0.15
            ctx.ui.floatingText.Show("获得 " .. itemDef.name .. " x" .. count, cx, cy, { 255, 220, 100, 255 })
        end
    end)

    -- 首次幸运金币出现快一些
    GameState.luckyTimer = 10 + math.random() * 20

    -- 初始化广告福利系统
    AdManager.Init()

    -- 初始化技能系统
    SkillManager.Init(function(x, y, skipRateLimit)
        -- 技能触发的点击（跳过频率限制）
        -- 注意：不播放单次动画（粒子/浮动文字/图标缩放），
        -- 否则高频自动点击会耗尽对象池，导致玩家手动点击的动画被立即覆盖
        if skipRateLimit then
            local S = GameState
            S.totalClicks = S.totalClicks + 1
            local gain = S.coinsPerClick * S.buffCpcMul
            S.coins = S.coins + gain
            S.handmadeCoins = S.handmadeCoins + gain
        else
            GM.OnCoinClick(x, y)
        end
    end)
end

return M
