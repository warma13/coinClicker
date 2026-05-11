-- ============================================================================
-- core/ProductionCalculator.lua
-- 产量重算逻辑：从 GameManager 提取，负责计算 CpS / CpC / 各类倍率
-- ============================================================================

local GameState         = require("core.GameState")
local Buildings         = require("config.Buildings")
local Upgrades          = require("config.Upgrades")
local BuildingUpgrades  = require("config.BuildingUpgrades")
local MultiplierPool    = require("core.MultiplierPool")

local GrandmapoManager  = require("core.GrandmapoManager")
local SugarLumpManager   = require("core.SugarLumpManager")
local AscensionManager   = require("core.AscensionManager")
local SeasonManager      = require("core.SeasonManager")
local DragonManager      = require("core.DragonManager")
local PantheonManager    = require("core.PantheonManager")
local GrimoireManager    = require("core.GrimoireManager")
local StockMarketManager = require("core.StockMarketManager")
local AchievementManager = require("core.AchievementManager")
local AdManager          = require("core.AdManager")
local SkillManager       = require("core.SkillManager")
local InventoryManager   = require("core.InventoryManager")
local OnlineRewardManager = require("core.OnlineRewardManager")

local M = {}

--- 重算全局产量（CpS / CpC / 幸运倍率等）
---@param buildingUpgrades table|nil 运行时生成的建筑效率升级数据（由 GameManager 传入）
function M.Recalculate(buildingUpgrades)
    local S = GameState
    S.coinsPerSecond = 0
    S.cpsPercent = 0
    S.fingerBonus = 0
    S.luckyFreqMul = 1
    S.luckyStayMul = 1
    S.luckyDurMul = 1

    -- 建筑产出（含效率升级倍率 + 奶奶研究倍率）
    for bi, b in ipairs(Buildings.buildings) do
        local mul = 1
        if buildingUpgrades and buildingUpgrades[bi] then
            mul = BuildingUpgrades.GetMultiplier(buildingUpgrades[bi])
        end
        -- 奶奶额外效率倍率（Ritual Rolling Pins 等研究）
        if b.id == "grandma" then
            mul = mul * GrandmapoManager.GetGrandmaMultiplier()
        end
        -- 糖块建筑等级加成（每级 +1%）
        mul = mul * SugarLumpManager.GetBuildingLevelMultiplier(bi)
        S.coinsPerSecond = S.coinsPerSecond + b.cpsAdd * b.count * mul
    end

    -- 奶奶协同加成 CpS（One Mind / Communal Brainsweep / Elder Pact）
    S.coinsPerSecond = S.coinsPerSecond + GrandmapoManager.GetGrandmaSynergyCps()
    S.coinsPerSecond = S.coinsPerSecond + GrandmapoManager.GetPortalSynergyCps()

    -- 计算非光标建筑总数（手指升级线用）
    local nonCursorCount = 0
    for _, b in ipairs(Buildings.buildings) do
        if b.id ~= "cursor" then
            nonCursorCount = nonCursorCount + b.count
        end
    end

    -- 点击升级（三条线）
    local bestFingerMul = 0
    local fingerBase = 0.1
    for _, u in ipairs(Upgrades.clickUpgrades) do
        if u.count > 0 then
            if u.category == "mouse" then
                -- 鼠标升级线: 累加 CpS 百分比
                S.cpsPercent = S.cpsPercent + u.cpsPercentAdd
            elseif u.category == "finger" then
                -- 手指升级线: 取最高倍率（后续替换前级）
                if u.fingerMul > bestFingerMul then
                    bestFingerMul = u.fingerMul
                    fingerBase = u.fingerBase
                end
            elseif u.category == "lucky" then
                -- 幸运升级线
                if u.luckyFreqMul then
                    S.luckyFreqMul = S.luckyFreqMul * u.luckyFreqMul
                end
                if u.luckyStayMul then
                    S.luckyStayMul = S.luckyStayMul * u.luckyStayMul
                end
                if u.luckyDurMul then
                    S.luckyDurMul = S.luckyDurMul * u.luckyDurMul
                end
            end
        end
    end

    -- 手指加成 = fingerBase * bestFingerMul * 非光标建筑数
    if bestFingerMul > 0 then
        S.fingerBonus = fingerBase * bestFingerMul * nonCursorCount
    end

    -- 光标建筑效率升级同时翻倍点击力量
    local cursorMul = 1
    if buildingUpgrades and buildingUpgrades[1] then
        cursorMul = BuildingUpgrades.GetMultiplier(buildingUpgrades[1])
    end

    -- ====================================================================
    -- 全局倍率（使用 MultiplierPool 统一管理加算/乘算）
    -- ====================================================================
    local pool = MultiplierPool.New()

    -- ---- 加算层（百分比加成，汇总后统一 1+sum） ----
    pool:Add(GrandmapoManager.GetProductionMultiplier())   -- 研究产量
    pool:Add(SugarLumpManager.GetSugarBakingMultiplier())  -- 糖块烘焙
    pool:Add(AscensionManager.GetPrestigeMultiplier())     -- 飞升声望
    pool:Add(AscensionManager.GetProductionMultiplier())   -- 天堂升级

    -- 天堂升级幸运加成
    S.luckyFreqMul = S.luckyFreqMul * AscensionManager.GetLuckyFreqMul()
    S.luckyDurMul = S.luckyDurMul * AscensionManager.GetLuckyDurMul()

    -- 季节
    pool:AddRaw(SeasonManager.GetCollectionCpsMul())       -- 季节收集
    pool:AddRaw(SeasonManager.GetXmasUpgradeCpsMul())      -- 圣诞升级
    S.coinsPerSecond = S.coinsPerSecond + SeasonManager.GetFixedCpsBonus() -- 固定 +9
    S.luckyFreqMul = S.luckyFreqMul * SeasonManager.GetLuckyFreqMul()

    -- AI 合伙人（龙）
    pool:AddRaw(DragonManager.GetCpsMul())                 -- CpS 百分比
    pool:AddRaw(DragonManager.GetPrestigeBonus())           -- 声望加成

    -- 万神殿
    if PantheonManager.IsUnlocked() then
        pool:Add(PantheonManager.GetCPSMultiplier())
        S.luckyFreqMul = S.luckyFreqMul * PantheonManager.GetGoldenFreqMultiplier()
        S.luckyDurMul = S.luckyDurMul * PantheonManager.GetLuckyDurationMultiplier()
    end

    -- 研发实验室
    if GrimoireManager.IsUnlocked() then
        pool:Add(GrimoireManager.GetCPSMultiplier())
    end

    -- 证券交易所贷款
    pool:Add(StockMarketManager.GetLoanCPSMultiplier())

    -- 收藏品被动加成
    local colBonus = InventoryManager.GetCollectibleBonuses()
    if colBonus.cps_percent > 0 then
        pool:Add(colBonus.cps_percent)
    end
    if colBonus.global_percent > 0 then
        pool:Add(colBonus.global_percent)
    end
    -- 收藏品幸运加成
    if colBonus.lucky_freq > 0 then
        S.luckyFreqMul = S.luckyFreqMul * (1 + colBonus.lucky_freq)
    end
    if colBonus.lucky_dur > 0 then
        S.luckyDurMul = S.luckyDurMul * (1 + colBonus.lucky_dur)
    end

    -- 广告特权卡
    local cardCpsMul = AdManager.GetCardCpsMul()
    if cardCpsMul > 0 then
        pool:AddRaw(cardCpsMul)                                -- 特权卡 CPS%
    end

    -- 在线奖励 CPS 加成
    local onlineCpsPct = OnlineRewardManager.GetCpsBonusPct()
    if onlineCpsPct > 0 then
        pool:AddRaw(onlineCpsPct)                              -- 在线奖励 CPS%
    end

    -- ---- 乘算层（独立机制，保持乘法） ----
    pool:Mul(DragonManager.GetProductionMul())              -- 产量 ×2

    local kittenMul = AchievementManager.GetKittenMultiplier()
    local kittenBonus = AscensionManager.GetKittenBonus() + SeasonManager.GetKittenBonus() + DragonManager.GetKittenBonus()
    pool:Mul(kittenMul + kittenBonus)                       -- Kitten 牛奶

    -- 合并
    local globalMul = pool:Result()

    -- 龙光环：奶奶协同（Elder Battalion）— 加到基础 CPS 上（不进全局乘）
    local grandmaSynergyMul = DragonManager.GetGrandmaSynergyMul()
    if grandmaSynergyMul > 1 then
        local grandma = Buildings.buildings[2]
        if grandma and grandma.count > 0 then
            local grandmaCps = grandma.cpsAdd * grandma.count
            local extraCps = grandmaCps * (grandmaSynergyMul - 1)
            S.coinsPerSecond = S.coinsPerSecond + extraCps
        end
    end

    -- 龙光环：幸运频率/持续加成
    S.luckyFreqMul = S.luckyFreqMul * DragonManager.GetLuckyFreqMul()
    S.luckyDurMul = S.luckyDurMul * DragonManager.GetLuckyDurMul()

    -- ====================================================================
    -- 应用全局倍率到 CPS
    -- ====================================================================
    S.globalCpsMul = globalMul
    S.coinsPerSecond = S.coinsPerSecond * globalMul

    -- 最终点击产出 = (基础值 * 光标倍率) + CpS百分比加成 + 手指加成 + 天堂/季节/龙点击加成
    local clickBonus = AscensionManager.GetClickBonus() + SeasonManager.GetClickBonus() + DragonManager.GetClickBonus()
    S.coinsPerClick = S.clickBase * cursorMul + S.cpsPercent * S.coinsPerSecond + S.fingerBonus
    S.coinsPerClick = S.coinsPerClick * (1 + clickBonus)

    -- 收藏品 CPC 加成
    if colBonus.cpc_percent > 0 then
        S.coinsPerClick = S.coinsPerClick * (1 + colBonus.cpc_percent)
    end

    -- 万神殿 CPC 乘数
    if PantheonManager.IsUnlocked() then
        S.coinsPerClick = S.coinsPerClick * PantheonManager.GetCPCMultiplier()
    end

    -- 研发实验室 CPC 乘数
    if GrimoireManager.IsUnlocked() then
        S.coinsPerClick = S.coinsPerClick * GrimoireManager.GetCPCMultiplier()
    end

    -- 广告特权卡 CPC 加成
    local cardCpcMul = AdManager.GetCardCpcMul()
    if cardCpcMul > 0 then
        S.coinsPerClick = S.coinsPerClick * (1 + cardCpcMul)
    end

    -- 在线奖励 CPC 加成
    local onlineCpcPct = OnlineRewardManager.GetCpcBonusPct()
    if onlineCpcPct > 0 then
        S.coinsPerClick = S.coinsPerClick * (1 + onlineCpcPct)
    end
end

return M
