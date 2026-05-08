-- ============================================================================
-- core/AscensionManager.lua
-- 飞升/声望系统核心逻辑：声望计算、天堂升级、飞升重置
-- ============================================================================

local GameState = require("core.GameState")
local Buildings = require("config.Buildings")
local Upgrades = require("config.Upgrades")
local AD = require("config.AscensionDefs")
local SaveBridge = require("core.SaveBridge")

local AM = {}

-- ============================================================================
-- 内部状态（跨飞升保留的数据）
-- ============================================================================

--- 天堂芯片（可消费货币）
local heavenlyChips_ = 0

--- 已消费的天堂芯片
local spentChips_ = 0

--- 声望等级（当前）
local prestigeLevel_ = 0

--- 历史总烘焙量（跨所有飞升的累计）
local totalBakedAllTime_ = 0

--- 本轮烘焙量追踪
local bakedThisAscension_ = 0

--- 飞升次数
local ascensionCount_ = 0

--- 已购买的天堂升级 { [id] = true }
local boughtUpgrades_ = {}

--- 回调
local onAscend_ = nil          -- function(newPrestige, gainedChips)
local onBuyUpgrade_ = nil      -- function(upgrade)

-- ============================================================================
-- 初始化
-- ============================================================================

function AM.Init()
    heavenlyChips_ = 0
    spentChips_ = 0
    prestigeLevel_ = 0
    totalBakedAllTime_ = 0
    bakedThisAscension_ = 0
    ascensionCount_ = 0
    boughtUpgrades_ = {}

    SaveBridge.Register("progression", AM.GetSaveData, AM.LoadSaveData)
end

-- ============================================================================
-- 回调设置
-- ============================================================================

function AM.SetOnAscend(fn)
    onAscend_ = fn
end

function AM.SetOnBuyUpgrade(fn)
    onBuyUpgrade_ = fn
end

-- ============================================================================
-- 声望查询
-- ============================================================================

--- 获取当前声望等级
---@return number
function AM.GetPrestigeLevel()
    return prestigeLevel_
end

--- 获取天堂芯片余额
---@return number
function AM.GetHeavenlyChips()
    return heavenlyChips_
end

--- 获取已消费的天堂芯片
---@return number
function AM.GetSpentChips()
    return spentChips_
end

--- 获取飞升次数
---@return number
function AM.GetAscensionCount()
    return ascensionCount_
end

--- 获取历史总烘焙量
---@return number
function AM.GetTotalBakedAllTime()
    return totalBakedAllTime_
end

--- 获取本轮累计烘焙量
---@return number
function AM.GetBakedThisAscension()
    return bakedThisAscension_
end

--- 计算如果现在飞升，将获得的新声望等级
---@return number 新声望等级
function AM.GetPotentialPrestige()
    local totalBaked = totalBakedAllTime_ + bakedThisAscension_
    return AD.CalcPrestigeLevel(totalBaked)
end

--- 计算如果现在飞升，将获得的天堂芯片数
---@return number 新增芯片数
function AM.GetPotentialChips()
    local newPrestige = AM.GetPotentialPrestige()
    local gained = newPrestige - prestigeLevel_
    return math.max(0, gained)
end

--- 获取到下一声望等级需要的剩余烘焙量
---@return number
function AM.GetBakedToNextLevel()
    local currentTotal = totalBakedAllTime_ + bakedThisAscension_
    local nextLevel = AM.GetPotentialPrestige() + 1
    local required = AD.CalcRequiredBaked(nextLevel)
    return math.max(0, required - currentTotal)
end

-- ============================================================================
-- 声望加成计算
-- ============================================================================

--- 获取声望解锁比例（由天堂升级链决定）
---@return number 0~1
function AM.GetPrestigeUnlockRatio()
    local ratio = 0
    for _, u in ipairs(AD.heavenlyUpgrades) do
        if u.prestigeUnlock and boughtUpgrades_[u.id] then
            ratio = math.max(ratio, u.prestigeUnlock)
        end
    end
    return ratio
end

--- 获取声望 CpS 倍率
---@return number 如 1.5 表示 +50%
function AM.GetPrestigeMultiplier()
    local ratio = AM.GetPrestigeUnlockRatio()
    return 1 + prestigeLevel_ * 0.01 * ratio
end

--- 获取天堂升级的总产量加成倍率
---@return number
function AM.GetProductionMultiplier()
    local bonus = 0
    for _, u in ipairs(AD.heavenlyUpgrades) do
        if u.productionMul and boughtUpgrades_[u.id] then
            bonus = bonus + u.productionMul
        end
    end
    return 1 + bonus
end

--- 获取天堂升级的点击加成
---@return number
function AM.GetClickBonus()
    local bonus = 0
    for _, u in ipairs(AD.heavenlyUpgrades) do
        if u.clickBonus and boughtUpgrades_[u.id] then
            bonus = bonus + u.clickBonus
        end
    end
    return bonus
end

--- 获取天堂升级的幸运频率倍率
---@return number
function AM.GetLuckyFreqMul()
    local mul = 1
    for _, u in ipairs(AD.heavenlyUpgrades) do
        if u.luckyFreqMul and boughtUpgrades_[u.id] then
            mul = mul * u.luckyFreqMul
        end
    end
    return mul
end

--- 获取天堂升级的幸运持续倍率
---@return number
function AM.GetLuckyDurMul()
    local mul = 1
    for _, u in ipairs(AD.heavenlyUpgrades) do
        if u.luckyDurMul and boughtUpgrades_[u.id] then
            mul = mul * u.luckyDurMul
        end
    end
    return mul
end

--- 获取 Kitten 额外加成
---@return number
function AM.GetKittenBonus()
    local bonus = 0
    for _, u in ipairs(AD.heavenlyUpgrades) do
        if u.kittenBonus and boughtUpgrades_[u.id] then
            bonus = bonus + u.kittenBonus
        end
    end
    return bonus
end

-- ============================================================================
-- 天堂升级购买
-- ============================================================================

--- 获取天堂升级状态列表（供 UI 使用）
---@return table[]
function AM.GetUpgradeStatus()
    local result = {}
    for _, u in ipairs(AD.heavenlyUpgrades) do
        local bought = boughtUpgrades_[u.id] == true
        local prereqMet = true
        if u.prereq then
            prereqMet = boughtUpgrades_[u.prereq] == true
        end
        local canAfford = heavenlyChips_ >= u.cost
        result[#result + 1] = {
            def = u,
            bought = bought,
            unlocked = prereqMet and not bought,
            canAfford = canAfford and prereqMet and not bought,
        }
    end
    return result
end

--- 购买天堂升级
---@param upgradeId string
---@return boolean
function AM.BuyUpgrade(upgradeId)
    local u = AD.FindById(upgradeId)
    if not u then return false end

    -- 已购买
    if boughtUpgrades_[u.id] then return false end

    -- 前置检查
    if u.prereq and not boughtUpgrades_[u.prereq] then return false end

    -- 芯片不够
    if heavenlyChips_ < u.cost then return false end

    heavenlyChips_ = heavenlyChips_ - u.cost
    spentChips_ = spentChips_ + u.cost
    boughtUpgrades_[u.id] = true

    print("[Ascension] 购买天堂升级: " .. u.name .. " | 剩余芯片: " .. heavenlyChips_)

    if onBuyUpgrade_ then
        onBuyUpgrade_(u)
    end

    return true
end

--- 检查是否已购买指定升级
---@param upgradeId string
---@return boolean
function AM.HasUpgrade(upgradeId)
    return boughtUpgrades_[upgradeId] == true
end

-- ============================================================================
-- 飞升（重置）
-- ============================================================================

--- 执行飞升
---@return number gainedChips 获得的天堂芯片
---@return number newPrestige 新声望等级
function AM.DoAscend()
    -- 计算新声望
    local totalBaked = totalBakedAllTime_ + bakedThisAscension_
    local newPrestige = AD.CalcPrestigeLevel(totalBaked)
    local gainedChips = math.max(0, newPrestige - prestigeLevel_)

    -- 更新永久数据
    totalBakedAllTime_ = totalBaked
    prestigeLevel_ = newPrestige
    heavenlyChips_ = heavenlyChips_ + gainedChips
    ascensionCount_ = ascensionCount_ + 1
    bakedThisAscension_ = 0

    print("[Ascension] 飞升! 声望: " .. prestigeLevel_ ..
          " | 获得芯片: " .. gainedChips ..
          " | 总芯片: " .. heavenlyChips_ ..
          " | 飞升次数: " .. ascensionCount_)

    -- 重置游戏状态
    AM.ResetGameState()

    if onAscend_ then
        onAscend_(newPrestige, gainedChips)
    end

    return gainedChips, newPrestige
end

--- 重置游戏状态（飞升时调用）
function AM.ResetGameState()
    local S = GameState

    -- 清零金币
    S.coins = 0

    -- 重置建筑
    for _, b in ipairs(Buildings.buildings) do
        b.count = 0
        b.totalProduced = 0
    end

    -- 应用 Starter 升级（免费建筑）
    for _, u in ipairs(AD.heavenlyUpgrades) do
        if u.starterBuilding and boughtUpgrades_[u.id] then
            for _, b in ipairs(Buildings.buildings) do
                if b.id == u.starterBuilding then
                    b.count = b.count + u.starterCount
                    print("[Ascension] Starter: +" .. u.starterCount .. " " .. b.name)
                    break
                end
            end
        end
    end

    -- 重置点击升级
    for _, u in ipairs(Upgrades.clickUpgrades) do
        u.count = 0
    end

    -- 重置点击相关
    S.totalClicks = 0
    S.luckyClicks = 0
    S.lastClickTime = 0
    S.coinsPerClick = S.clickBase
    S.coinsPerSecond = 0

    -- 重置 Buff
    S.activeBuffs = {}
    S.buffCpsMul = 1
    S.buffCpcMul = 1

    -- 重置幸运金币
    S.luckyActive = false
    S.luckyTimer = 10 + math.random() * 20
    S.effectLabelTimer = 0

    -- 重置光标计时器
    S.cursorTimer = 0

    -- 重置 UI 刷新
    S.lastRefreshCoins = -1
    S.buffRefreshCooldown = 0
end

-- ============================================================================
-- 帧更新
-- ============================================================================

--- 调试：直接增加天堂芯片（经验值）
--- 声望等级不直接修改，由公式从 totalBaked 计算
---@param amount number
function AM.DebugAddPrestige(amount)
    heavenlyChips_ = heavenlyChips_ + amount
    print("[Ascension] DEBUG: +chips " .. amount ..
          " | 声望: " .. prestigeLevel_ ..
          " | 芯片: " .. heavenlyChips_)
end

--- 每帧追踪烘焙量（在 GameManager.Update 中调用）
---@param earned number 本帧产出的金币总量
function AM.TrackProduction(earned)
    if earned > 0 then
        bakedThisAscension_ = bakedThisAscension_ + earned
    end
end

-- ============================================================================
-- 存档/读档
-- ============================================================================

--- 导出存档数据
---@return table
function AM.GetSaveData()
    local upgrades = {}
    for id, _ in pairs(boughtUpgrades_) do
        upgrades[#upgrades + 1] = id
    end
    return {
        heavenlyChips = heavenlyChips_,
        spentChips = spentChips_,
        prestigeLevel = prestigeLevel_,
        totalBakedAllTime = totalBakedAllTime_,
        bakedThisAscension = bakedThisAscension_,
        ascensionCount = ascensionCount_,
        boughtUpgrades = upgrades,
    }
end

--- 从存档恢复数据
---@param data table
function AM.LoadSaveData(data)
    if not data then return end
    heavenlyChips_ = data.heavenlyChips or 0
    spentChips_ = data.spentChips or 0
    prestigeLevel_ = data.prestigeLevel or 0
    totalBakedAllTime_ = data.totalBakedAllTime or 0
    bakedThisAscension_ = data.bakedThisAscension or 0
    ascensionCount_ = data.ascensionCount or 0
    boughtUpgrades_ = {}
    if data.boughtUpgrades then
        for _, id in ipairs(data.boughtUpgrades) do
            boughtUpgrades_[id] = true
        end
    end

    -- 一致性校验（仅日志警告，不强制降级，避免浮点精度导致误修正）
    local realPrestige = AD.CalcPrestigeLevel(totalBakedAllTime_ + bakedThisAscension_)
    if prestigeLevel_ > realPrestige + 1 then
        print("[AscensionManager] 警告: 声望异常 saved=" .. prestigeLevel_
              .. " calc=" .. realPrestige .. " totalBaked=" .. totalBakedAllTime_)
    end

    print("[AscensionManager] 存档恢复 | 声望:" .. prestigeLevel_ ..
          " 芯片:" .. heavenlyChips_ .. " 飞升:" .. ascensionCount_ ..
          " 总烘焙:" .. totalBakedAllTime_)
end

return AM
