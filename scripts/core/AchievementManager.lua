-- ============================================================================
-- core/AchievementManager.lua
-- 成就判定 + 牛奶百分比 + Kitten CpS 倍率
-- 每帧由 GameManager 调用 Update()，检查未解锁的成就条件
-- ============================================================================

local GameState = require("core.GameState")
local Buildings = require("config.Buildings")
local Upgrades = require("config.Upgrades")
local AchievementDefs = require("config.AchievementDefs")
local KittenUpgrades = require("config.KittenUpgrades")
local BuildingUpgrades = require("config.BuildingUpgrades")

local AM = {}

-- ======== 状态 ========
local unlocked_ = {}          -- { [id] = true } 已解锁的成就
local unlockedCount_ = 0      -- 已解锁普通成就数
local milkDecimal_ = 0        -- 牛奶小数 (如 2.0 = 200%)
local kittenMul_ = 1          -- Kitten 总倍率
local checkCooldown_ = 0      -- 检查间隔节流
local CHECK_INTERVAL = 0.5    -- 每 0.5 秒检查一次

-- 回调
local onUnlock_ = nil         -- function(achievement) 成就解锁时调用

-- 缓存：建筑 id → index 映射
local buildingIdIndex_ = {}

-- ============================================================================
-- 初始化
-- ============================================================================

function AM.Init()
    unlocked_ = {}
    unlockedCount_ = 0
    milkDecimal_ = 0
    kittenMul_ = 1
    checkCooldown_ = 0

    -- 构建建筑 id → index 映射
    for i, b in ipairs(Buildings.buildings) do
        buildingIdIndex_[b.id] = i
    end

    print("[AchievementManager] 初始化完成，总成就数: " .. AchievementDefs.totalCount)
end

--- 设置成就解锁回调
---@param callback function(achievement: table)
function AM.SetOnUnlock(callback)
    onUnlock_ = callback
end

-- ============================================================================
-- 成就条件检查
-- ============================================================================

--- 获取总金币产出（当前持有 + 所有建筑累计产出）
local function GetTotalProduced()
    local total = GameState.coins
    for _, b in ipairs(Buildings.buildings) do
        total = total + (b.totalProduced or 0)
    end
    return total
end

--- 获取已购买的总升级数（建筑效率 + 点击升级 + Kitten）
local function GetTotalUpgradesBought(buildingUpgrades)
    local count = 0
    -- 建筑效率升级
    if buildingUpgrades then
        for _, bUpgrades in ipairs(buildingUpgrades) do
            for _, u in ipairs(bUpgrades) do
                if u.bought then count = count + 1 end
            end
        end
    end
    -- 点击升级
    for _, u in ipairs(Upgrades.clickUpgrades) do
        count = count + u.count
    end
    -- Kitten 升级
    for _, u in ipairs(KittenUpgrades.upgrades) do
        if u.bought then count = count + 1 end
    end
    return count
end

--- 检查季节相关成就
---@param a table 成就定义
---@return boolean
local function CheckSeasonAchievement(a)
    local SM = require("core.SeasonManager")
    local SD = require("config.SeasonDefs")

    -- 季节收集品全收集
    if a.seasonCollection then
        local list
        if a.seasonCollection == "christmas" then
            list = SD.christmasCookies
        elseif a.seasonCollection == "halloween" then
            list = SD.halloweenCookies
        elseif a.seasonCollection == "valentine" then
            list = SD.valentineCookies
        end
        if list then
            local collected, total = SM.GetCollectionProgress(list)
            return collected >= total
        end
    end

    -- 创新潮专利收集数量
    if a.seasonEggCount then
        local colN, totN = SM.GetCollectionProgress(SD.easterEggsNormal)
        local colR, totR = SM.GetCollectionProgress(SD.easterEggsRare)
        return (colN + colR) >= a.seasonEggCount
    end

    -- 市场信心等级
    if a.santaLevel then
        return SM.GetSantaLevel() >= a.santaLevel
    end

    return false
end

--- 检查工会危机成就
---@param a table 成就定义
---@return boolean
local function CheckGrandmapoAchievement(a)
    local GPM = require("core.GrandmapoManager")
    local GD = require("config.GrandmapocalypseDefs")
    if a.id == "gpo_awaken" then
        return GPM.GetRawPhase() >= GD.PHASE_DISPLEASED
    elseif a.id == "gpo_pledge1" then
        return GPM.GetPledgePurchases() >= 1
    elseif a.id == "gpo_pledge5" then
        return GPM.GetPledgePurchases() >= (a.threshold or 5)
    elseif a.id == "gpo_elder" then
        -- 全部研究已解锁
        local allBought = true
        for i = 1, #GD.researchChain do
            if not GPM.IsResearchBought(i) then allBought = false; break end
        end
        return allBought
    end
    return false
end

--- 检查排行榜成就
---@param a table 成就定义
---@return boolean
local function CheckLeaderboardAchievement(a)
    local lb = GameState.leaderboard
    local MIN_PLAYERS = 100  -- 最低100人才计算排名/百分比类成就
    local lbType = a.lbType

    -- 参与类（不需要最低人数限制）
    if lbType == "on_board" then
        return lb.myRank > 0
    end
    if lbType == "total_players" then
        return lb.totalPlayers >= a.threshold
    end

    -- 以下成就需要排行榜总人数 >= 100
    if lb.totalPlayers < MIN_PLAYERS then
        return false
    end

    -- 排名到达类
    if lbType == "rank1_reached" then
        return lb.rank1Reached
    end
    if lbType == "top3_reached" then
        return lb.top3Reached
    end
    if lbType == "top10_reached" then
        return lb.top10Reached
    end
    if lbType == "top1p_reached" then
        return lb.top1pReached
    end
    if lbType == "top10p_reached" then
        return lb.top10pReached
    end
    if lbType == "top50p_reached" then
        return lb.top50pReached
    end

    -- 第1名时长类
    if lbType == "rank1_time" then
        return lb.rank1Time >= a.threshold
    end

    -- 历史最佳排名类
    if lbType == "best_rank" then
        return lb.bestRank > 0 and lb.bestRank <= a.threshold
    end

    return false
end

--- 检查龙成就
---@param a table 成就定义
---@return boolean
local function CheckDragonAchievement(a)
    local DM = require("core.DragonManager")
    if a.id == "drg_aura2" then
        return DM.IsSecondSlotUnlocked()
    end
    -- 等级检查
    if a.threshold then
        return DM.GetLevel() >= a.threshold
    end
    return false
end

--- 检查小游戏成就
---@param a table 成就定义
---@return boolean
local function CheckMinigameAchievement(a)
    local mgType = a.mgType
    if not mgType then return false end

    -- 挖矿探险
    if mgType == "mine_clear" then
        local MiningMgr = require("core.MiningManager")
        return MiningMgr.GetBoardsCleared() >= a.threshold
    elseif mgType == "mine_streak" then
        local MiningMgr = require("core.MiningManager")
        return MiningMgr.GetStreak() >= a.threshold
    -- 孵化园
    elseif mgType == "garden_seed" then
        local GardenMgr = require("core.GardenManager")
        return GardenMgr.GetDiscoveredCount() >= a.threshold
    elseif mgType == "garden_all" then
        local GardenMgr = require("core.GardenManager")
        local GardenCfg = require("config.GardenConfig")
        local totalSeeds = #GardenCfg.seeds
        return GardenMgr.GetDiscoveredCount() >= totalSeeds
    -- 制造工厂
    elseif mgType == "factory_deliver" then
        local FactoryMgr = require("core.FactoryManager")
        return FactoryMgr.GetTotalDelivered() >= a.threshold
    elseif mgType == "factory_gather" then
        local FactoryMgr = require("core.FactoryManager")
        return FactoryMgr.GetTotalGathered() >= a.threshold
    elseif mgType == "factory_level" then
        local FactoryMgr = require("core.FactoryManager")
        return FactoryMgr.GetFactoryLevel() >= a.threshold
    -- 期货交易所
    elseif mgType == "stock_profit" then
        local StockMgr = require("core.StockMarketManager")
        return StockMgr.GetTotalProfit() >= a.threshold
    -- 电商平台
    elseif mgType == "ecom_sold" then
        local EComMgr = require("core.ECommerceManager")
        return EComMgr.GetTotalSold() >= a.threshold
    elseif mgType == "ecom_streak" then
        local EComMgr = require("core.ECommerceManager")
        return EComMgr.GetStreak() >= a.threshold
    -- 国际物流
    elseif mgType == "ship_deliver" then
        local ShipMgr = require("core.ShipmentManager")
        return ShipMgr.GetTotalShipped() >= a.threshold
    elseif mgType == "ship_streak" then
        local ShipMgr = require("core.ShipmentManager")
        return ShipMgr.GetSafeStreak() >= a.threshold
    -- 研发实验室
    elseif mgType == "grimoire_cast" then
        local GrimMgr = require("core.GrimoireManager")
        return GrimMgr.GetTotalCasts() >= a.threshold
    end

    return false
end

--- 检查单个成就是否满足条件
---@param a table 成就定义
---@param ctx table 上下文数据（避免重复计算）
---@return boolean
local function CheckAchievement(a, ctx)
    local cat = a.category
    local C = AchievementDefs.CATEGORY

    if cat == C.PRODUCTION then
        -- 产量成就：检查总产出
        if a.id:sub(1, 4) == "prod" then
            return ctx.totalProduced >= a.threshold
        end
        -- CpS 成就
        if a.id:sub(1, 3) == "cps" then
            return GameState.coinsPerSecond >= a.threshold
        end
        -- 持有金币成就
        if a.id:sub(1, 4) == "bank" then
            return GameState.coins >= a.threshold
        end
    elseif cat == C.BUILDING then
        -- 单个建筑数量成就
        if a.buildingId then
            local bi = buildingIdIndex_[a.buildingId]
            if bi then
                return Buildings.buildings[bi].count >= a.threshold
            end
        end
        -- 产业总数成就
        if a.id:sub(1, 4) == "tbld" then
            return ctx.totalBuildings >= a.threshold
        end
    elseif cat == C.CLICK then
        -- 签单次数成就
        if a.id:sub(1, 5) == "click" then
            return GameState.totalClicks >= a.threshold
        end
        -- 每次签单收益成就
        if a.id:sub(1, 3) == "cpc" then
            return GameState.coinsPerClick >= a.threshold
        end
        -- 手动签单总产出成就
        if a.id:sub(1, 4) == "hand" then
            return GameState.handmadeCoins >= a.threshold
        end
    elseif cat == C.LUCKY then
        return GameState.luckyClicks >= a.threshold
    elseif cat == C.UPGRADE then
        return ctx.totalUpgrades >= a.threshold
    elseif cat == C.MISC then
        -- 季节相关成就
        if a.seasonCollection or a.seasonEggCount or a.santaLevel then
            return CheckSeasonAchievement(a)
        end
        -- 转型重启成就
        if a.id:sub(1, 3) == "asc" then
            local AM2 = require("core.AscensionManager")
            return AM2.GetAscensionCount() >= a.threshold
        end
        -- 声望等级成就
        if a.id:sub(1, 4) == "pres" then
            local AM2 = require("core.AscensionManager")
            return AM2.GetPrestigeLevel() >= a.threshold
        end
        -- 人脉成就
        if a.id:sub(1, 4) == "lump" then
            local SLM = require("core.SugarLumpManager")
            return SLM.GetTotalHarvested() >= a.threshold
        end
        -- 工会危机成就
        if a.id:sub(1, 3) == "gpo" then
            return CheckGrandmapoAchievement(a)
        end
        -- 龙成就
        if a.id:sub(1, 3) == "drg" then
            return CheckDragonAchievement(a)
        end
        -- 黑洞成就
        if a.id:sub(1, 3) == "wrk" then
            return GameState.wrinklersPopped >= a.threshold
        end

    elseif cat == C.LEADERBOARD then
        return CheckLeaderboardAchievement(a)

    elseif cat == C.MINIGAME then
        return CheckMinigameAchievement(a)
    end

    return false
end

-- ============================================================================
-- 牛奶 & Kitten
-- ============================================================================

--- 重新计算牛奶和 Kitten 倍率
local function RecalcMilk()
    milkDecimal_ = unlockedCount_ * AchievementDefs.MILK_PER_ACHIEVEMENT
    kittenMul_ = KittenUpgrades.GetMultiplier(milkDecimal_)
end

--- 获取牛奶百分比（显示用）
---@return number 百分比值（如 200）
function AM.GetMilkPercent()
    return milkDecimal_ * 100
end

--- 获取牛奶小数值
---@return number 小数值（如 2.0）
function AM.GetMilkDecimal()
    return milkDecimal_
end

--- 获取 Kitten 总倍率
---@return number
function AM.GetKittenMultiplier()
    return kittenMul_
end

--- 获取已解锁成就数
---@return number
function AM.GetUnlockedCount()
    return unlockedCount_
end

--- 获取总成就数
---@return number
function AM.GetTotalCount()
    return AchievementDefs.totalCount
end

--- 判断成就是否已解锁
---@param id string
---@return boolean
function AM.IsUnlocked(id)
    return unlocked_[id] == true
end

--- 获取所有成就及其状态（用于 UI 展示）
---@return table[] { achievement, unlocked }
function AM.GetAllWithStatus()
    local result = {}
    for _, a in ipairs(AchievementDefs.all) do
        result[#result + 1] = {
            achievement = a,
            unlocked = unlocked_[a.id] == true,
        }
    end
    return result
end

--- 获取牛奶口味名称（纯视觉）
---@return string
function AM.GetMilkFlavor()
    local count = unlockedCount_
    local flavors = {
        { 0,   "实习生" },
        { 25,  "初级经理" },
        { 50,  "高级经理" },
        { 75,  "总监" },
        { 100, "副总裁" },
        { 125, "总裁" },
        { 150, "董事长" },
    }
    local name = "实习生"
    for _, f in ipairs(flavors) do
        if count >= f[1] then
            name = f[2]
        end
    end
    return name
end

-- ============================================================================
-- Kitten 升级购买
-- ============================================================================

--- 购买 Kitten 升级
---@param index number 升级索引
---@return boolean 是否成功
function AM.BuyKitten(index)
    local upgrade = KittenUpgrades.upgrades[index]
    if not upgrade then return false end
    if upgrade.bought then return false end
    if unlockedCount_ < upgrade.needAchievements then return false end
    if GameState.coins < upgrade.baseCost then return false end

    GameState.coins = GameState.coins - upgrade.baseCost
    upgrade.bought = true
    RecalcMilk()
    print("[AchievementManager] 购买 Kitten 升级: " .. upgrade.name ..
          " | Kitten倍率: x" .. string.format("%.2f", kittenMul_))
    return true
end

-- ============================================================================
-- 帧更新
-- ============================================================================

--- 每帧检查（由 GameManager 调用）
---@param dt number
---@param buildingUpgrades table|nil 建筑效率升级数据
function AM.Update(dt, buildingUpgrades)
    checkCooldown_ = checkCooldown_ - dt
    if checkCooldown_ > 0 then return end
    checkCooldown_ = CHECK_INTERVAL

    -- 计算产业总数
    local totalBuildings = 0
    for _, b in ipairs(Buildings.buildings) do
        totalBuildings = totalBuildings + b.count
    end

    -- 构建检查上下文（避免每个成就重复计算）
    local ctx = {
        totalProduced = GetTotalProduced(),
        totalUpgrades = GetTotalUpgradesBought(buildingUpgrades),
        totalBuildings = totalBuildings,
    }

    local newUnlocks = false

    for _, a in ipairs(AchievementDefs.all) do
        if not unlocked_[a.id] then
            if CheckAchievement(a, ctx) then
                unlocked_[a.id] = true
                unlockedCount_ = unlockedCount_ + 1
                newUnlocks = true
                print("[Achievement] 🏆 解锁: " .. a.name .. " (" .. a.desc .. ")")
                if onUnlock_ then
                    onUnlock_(a)
                end
            end
        end
    end

    if newUnlocks then
        RecalcMilk()
    end
end

-- ============================================================================
-- 存档/读档
-- ============================================================================

--- 导出存档数据
---@return table
function AM.GetSaveData()
    local ids = {}
    for id, _ in pairs(unlocked_) do
        ids[#ids + 1] = id
    end
    return { unlocked = ids }
end

--- 从存档恢复数据
---@param data table
function AM.LoadSaveData(data)
    if not data then return end
    unlocked_ = {}
    unlockedCount_ = 0
    if data.unlocked then
        for _, id in ipairs(data.unlocked) do
            unlocked_[id] = true
            unlockedCount_ = unlockedCount_ + 1
        end
    end
    RecalcMilk()
    print("[AchievementManager] 存档恢复: " .. unlockedCount_ .. " 个成就")
end

return AM
