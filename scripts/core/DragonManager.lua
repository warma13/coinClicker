-- ============================================================================
-- core/DragonManager.lua
-- AI合伙人核心逻辑（K1）
-- AI等级、策略模块装备、AI洞察、经验值、天赋树
-- ============================================================================

local GameState = require("core.GameState")
local Buildings = require("config.Buildings")
local DD = require("config.DragonDefs")
local SaveBridge = require("core.SaveBridge")

local DM = {}

-- ============================================================================
-- 内部状态 —— 基础系统
-- ============================================================================

--- AI等级 (0-24)
local dragonLevel_ = -1  -- -1 = 未购买

--- 已解锁的策略模块 id 集合 { [auraId] = true }
local unlockedAuras_ = {}

--- 装备的策略模块 (最多2个槽位)
local equippedAuras_ = { nil, nil }

--- 副策略槽是否解锁
local secondSlotUnlocked_ = false

--- 已收集的AI洞察 { [dropId] = true }
local collectedDrops_ = {}

--- AI洞察是否解锁
local dropsUnlocked_ = false

--- 洞察轮换计时器
local dropRotateTimer_ = 0

--- 当前可掉落的物品索引 (1-based)
local currentDropIndex_ = 1

-- ============================================================================
-- 内部状态 —— 经验值系统
-- ============================================================================

--- 当前累计经验值
local currentXP_ = 0

--- 当前等级已积累的经验值（用于进度条显示）
local levelXP_ = 0

-- ============================================================================
-- 内部状态 —— 天赋系统
-- ============================================================================

--- 已学习的天赋 { [talentId] = true }
local learnedTalents_ = {}

--- 可用天赋点数
local talentPoints_ = 0

-- ============================================================================
-- 内部状态 —— 派遣任务系统
-- ============================================================================

--- 当前进行中的任务 { missionId, startTime, duration } 或 nil
local activeMission_ = nil

--- 任务刷新冷却计时器
local missionRefreshTimer_ = 0

--- 已完成的任务计数（统计用）
local completedMissionCount_ = 0

-- ============================================================================
-- 回调
-- ============================================================================

local onLevelUp_ = nil          -- function(newLevel, auraUnlocked)
local onEquipAura_ = nil        -- function(slot, auraId)
local onDrop_ = nil             -- function(dropItem)
local onTalentLearn_ = nil      -- function(talentId)
local onMissionComplete_ = nil  -- function(missionDef, rewards)

-- ============================================================================
-- 初始化
-- ============================================================================

function DM.Init()
    dragonLevel_ = -1
    unlockedAuras_ = {}
    equippedAuras_ = { nil, nil }
    secondSlotUnlocked_ = false
    collectedDrops_ = {}
    dropsUnlocked_ = false
    dropRotateTimer_ = 0
    currentDropIndex_ = 1

    currentXP_ = 0
    levelXP_ = 0
    learnedTalents_ = {}
    talentPoints_ = 0

    activeMission_ = nil
    missionRefreshTimer_ = 0
    completedMissionCount_ = 0

    SaveBridge.Register("dragon", DM.GetSaveData, DM.LoadSaveData, function()
        dragonLevel_ = -1
        unlockedAuras_ = {}
        equippedAuras_ = { nil, nil }
        secondSlotUnlocked_ = false
        collectedDrops_ = {}
        dropsUnlocked_ = false
        dropRotateTimer_ = 0
        currentDropIndex_ = 1
        currentXP_ = 0
        levelXP_ = 0
        learnedTalents_ = {}
        talentPoints_ = 0
        activeMission_ = nil
        missionRefreshTimer_ = 0
        completedMissionCount_ = 0
    end)
end

-- ============================================================================
-- 回调设置
-- ============================================================================

function DM.SetOnLevelUp(fn) onLevelUp_ = fn end
function DM.SetOnEquipAura(fn) onEquipAura_ = fn end
function DM.SetOnDrop(fn) onDrop_ = fn end
function DM.SetOnTalentLearn(fn) onTalentLearn_ = fn end
function DM.SetOnMissionComplete(fn) onMissionComplete_ = fn end

-- ============================================================================
-- 查询接口 —— 基础
-- ============================================================================

function DM.IsUnlocked() return dragonLevel_ >= 0 end
function DM.GetLevel() return dragonLevel_ end

function DM.GetCurrentLevelDef()
    return DD.GetLevel(dragonLevel_)
end

function DM.GetNextLevelDef()
    if dragonLevel_ >= DD.MAX_LEVEL then return nil end
    return DD.GetLevel(dragonLevel_ + 1)
end

function DM.IsMaxLevel() return dragonLevel_ >= DD.MAX_LEVEL end
function DM.IsSecondSlotUnlocked() return secondSlotUnlocked_ end

function DM.GetEquippedAura(slot)
    local auraId = equippedAuras_[slot]
    if not auraId then return nil end
    return DD.FindAura(auraId)
end

function DM.GetEquippedAuraId(slot) return equippedAuras_[slot] end

function DM.GetUnlockedAuras()
    local result = {}
    for _, a in ipairs(DD.auras) do
        if unlockedAuras_[a.id] then
            result[#result + 1] = a
        end
    end
    return result
end

function DM.IsAuraUnlocked(auraId) return unlockedAuras_[auraId] == true end
function DM.IsDropsUnlocked() return dropsUnlocked_ end
function DM.SetDropsUnlocked(unlocked) dropsUnlocked_ = unlocked end
function DM.GetCollectedDrops() return collectedDrops_ end
function DM.HasDrop(dropId) return collectedDrops_[dropId] == true end

-- ============================================================================
-- 查询接口 —— 经验值
-- ============================================================================

--- 获取当前累计XP
function DM.GetCurrentXP() return currentXP_ end

--- 获取当前等级已积累的XP（用于进度条）
function DM.GetLevelXP() return levelXP_ end

--- 获取下一级所需XP
function DM.GetNextLevelXP()
    if dragonLevel_ >= DD.MAX_LEVEL then return 0 end
    -- 5级之前升级不需要XP
    if dragonLevel_ < DD.TALENT_UNLOCK_LEVEL then return 0 end
    return DD.GetXPRequired(dragonLevel_ + 1)
end

--- XP是否满足下一级
function DM.IsXPReady()
    local needed = DM.GetNextLevelXP()
    if needed <= 0 then return true end
    return levelXP_ >= needed
end

--- 获取当前XP每秒增长速率
function DM.GetXPPerSecond()
    if dragonLevel_ < DD.TALENT_UNLOCK_LEVEL then return 0 end
    local cps = GameState.cps or 0
    return math.log(math.max(cps, 10), 10) * DD.XP_RATE_BASE
end

-- ============================================================================
-- 查询接口 —— 天赋
-- ============================================================================

--- 获取可用天赋点
function DM.GetTalentPoints() return talentPoints_ end

--- 获取已学习的天赋集合
function DM.GetLearnedTalents() return learnedTalents_ end

--- 天赋是否已学习
function DM.IsTalentLearned(talentId) return learnedTalents_[talentId] == true end

--- 获取已消耗的天赋点数
function DM.GetUsedTalentPoints()
    local used = 0
    for talentId, _ in pairs(learnedTalents_) do
        local branch, tierIdx = DD.FindTalent(talentId)
        if branch and tierIdx then
            used = used + branch.tiers[tierIdx].cost
        end
    end
    return used
end

--- 获取已获得的总天赋点数（含已用 + 可用）
function DM.GetTotalTalentPoints()
    return DM.GetUsedTalentPoints() + talentPoints_
end

--- 检查某天赋是否可以学习
---@return boolean canLearn, string|nil reason
function DM.CanLearnTalent(talentId)
    if learnedTalents_[talentId] then
        return false, "已学习"
    end

    local branch, tierIdx = DD.FindTalent(talentId)
    if not branch or not tierIdx then
        return false, "天赋不存在"
    end

    local tier = branch.tiers[tierIdx]

    -- 检查天赋点
    if talentPoints_ < tier.cost then
        return false, "天赋点不足 (需要 " .. tier.cost .. ")"
    end

    -- 检查前置：前一层必须已学习
    if tierIdx > 1 then
        local prevTier = branch.tiers[tierIdx - 1]
        if not learnedTalents_[prevTier.id] then
            return false, "需要先学习 " .. prevTier.name
        end
    end

    return true, nil
end

--- 学习天赋
---@return boolean
function DM.LearnTalent(talentId)
    local canLearn, reason = DM.CanLearnTalent(talentId)
    if not canLearn then
        print("[Dragon] 天赋学习失败: " .. (reason or ""))
        return false
    end

    local branch, tierIdx = DD.FindTalent(talentId)
    local tier = branch.tiers[tierIdx]

    talentPoints_ = talentPoints_ - tier.cost
    learnedTalents_[talentId] = true

    print("[Dragon] 天赋学习: " .. tier.name .. " (" .. branch.name .. " T" .. tierIdx .. ")")

    if onTalentLearn_ then
        onTalentLearn_(talentId)
    end

    return true
end

--- 重置天赋（全部退回）
function DM.ResetTalents()
    local refund = DM.GetUsedTalentPoints()
    learnedTalents_ = {}
    talentPoints_ = talentPoints_ + refund
    print("[Dragon] 天赋重置，退回 " .. refund .. " 点")
end

--- 获取某分支已学习的层数
function DM.GetBranchProgress(branchId)
    for _, branch in ipairs(DD.TALENT_BRANCHES) do
        if branch.id == branchId then
            local count = 0
            for _, tier in ipairs(branch.tiers) do
                if learnedTalents_[tier.id] then count = count + 1 end
            end
            return count
        end
    end
    return 0
end

-- ============================================================================
-- 查询接口 —— 派遣任务
-- ============================================================================

--- 获取当前进行中的任务（nil = 无）
function DM.GetActiveMission() return activeMission_ end

--- 获取当前任务的已用时间（秒）
function DM.GetMissionElapsed()
    if not activeMission_ then return 0 end
    return activeMission_.elapsed or 0
end

--- 获取当前任务的总时长
function DM.GetMissionDuration()
    if not activeMission_ then return 0 end
    return activeMission_.duration or 0
end

--- 获取任务进度 0~1
function DM.GetMissionProgress()
    if not activeMission_ then return 0 end
    local dur = activeMission_.duration or 1
    return math.min((activeMission_.elapsed or 0) / dur, 1.0)
end

--- 任务是否已完成（等待领取）
function DM.IsMissionDone()
    if not activeMission_ then return false end
    return (activeMission_.elapsed or 0) >= (activeMission_.duration or 1)
end

--- 获取可派遣的任务列表
function DM.GetAvailableMissions()
    if dragonLevel_ < DD.MISSION_UNLOCK_LEVEL then return {} end
    return DD.GetAvailableMissions(dragonLevel_)
end

--- 是否有任务进行中
function DM.HasActiveMission() return activeMission_ ~= nil end

--- 获取已完成任务总数
function DM.GetCompletedMissionCount() return completedMissionCount_ end

--- 是否正在刷新冷却中
function DM.IsMissionOnCooldown() return missionRefreshTimer_ > 0 end
function DM.GetMissionCooldown() return missionRefreshTimer_ end

--- 派遣任务
---@param missionId string
---@return boolean
function DM.StartMission(missionId)
    if activeMission_ then
        print("[Dragon] 已有任务进行中")
        return false
    end
    if dragonLevel_ < DD.MISSION_UNLOCK_LEVEL then
        print("[Dragon] 等级不足，无法派遣")
        return false
    end

    local def = DD.FindMission(missionId)
    if not def then
        print("[Dragon] 任务不存在: " .. tostring(missionId))
        return false
    end
    if dragonLevel_ < def.unlockLevel then
        print("[Dragon] 任务等级不足")
        return false
    end

    activeMission_ = {
        missionId = def.id,
        duration = def.duration,
        elapsed = 0,
    }
    missionRefreshTimer_ = 0
    print("[Dragon] 派遣任务: " .. def.name .. " (" .. def.duration .. "s)")
    return true
end

--- 领取任务奖励
---@return table|nil rewards  { xp, coins }
function DM.ClaimMission()
    if not activeMission_ then return nil end
    if not DM.IsMissionDone() then return nil end

    local def = DD.FindMission(activeMission_.missionId)
    if not def then
        activeMission_ = nil
        return nil
    end

    -- 计算奖励
    local rewards = {}
    rewards.xp = def.rewards.xp or 0
    local cps = GameState.cps or 0
    rewards.coins = math.floor(cps * (def.rewards.coinMul or 0) * def.duration)
    if rewards.coins < 1 then rewards.coins = math.floor(def.rewards.xp * 10) end

    -- 发放奖励
    if rewards.xp > 0 then
        DM.AddXP(rewards.xp)
    end
    if rewards.coins > 0 then
        GameState.coins = GameState.coins + rewards.coins
    end

    completedMissionCount_ = completedMissionCount_ + 1
    print("[Dragon] 任务完成: " .. def.name ..
          " | XP+" .. rewards.xp .. " 金币+" .. GameState.FormatNumber(rewards.coins))

    activeMission_ = nil
    missionRefreshTimer_ = DD.MISSION_REFRESH_CD

    if onMissionComplete_ then
        onMissionComplete_(def, rewards)
    end

    return rewards
end

--- 放弃当前任务
function DM.AbandonMission()
    if not activeMission_ then return false end
    local def = DD.FindMission(activeMission_.missionId)
    print("[Dragon] 放弃任务: " .. (def and def.name or "?"))
    activeMission_ = nil
    missionRefreshTimer_ = DD.MISSION_REFRESH_CD
    return true
end

-- ============================================================================
-- 升级
-- ============================================================================

--- 检查是否能升级到下一级
---@return boolean canUpgrade
---@return string|nil reason
function DM.CanUpgrade()
    if dragonLevel_ >= DD.MAX_LEVEL then
        return false, "已满级"
    end

    local nextDef = DD.GetLevel(dragonLevel_ + 1)
    if not nextDef then return false, "无下一级定义" end

    -- 已达5级后，继续升级需要XP条件（4→5不需要XP）
    if dragonLevel_ >= DD.TALENT_UNLOCK_LEVEL then
        local xpNeeded = DD.GetXPRequired(dragonLevel_ + 1)
        if xpNeeded > 0 and levelXP_ < xpNeeded then
            return false, "经验不足 (" .. math.floor(levelXP_) .. "/" .. xpNeeded .. ")"
        end
    end

    if nextDef.costType == "none" then
        return true, nil
    elseif nextDef.costType == "cookie" then
        if GameState.coins < nextDef.cost then
            return false, "金币不足"
        end
        return true, nil
    elseif nextDef.costType == "building" then
        local b = Buildings.buildings[nextDef.buildIdx]
        if not b then return false, "建筑不存在" end
        if b.count < nextDef.need then
            return false, "需要 " .. nextDef.need .. " 个 " .. b.name .. "（当前 " .. b.count .. "）"
        end
        return true, nil
    elseif nextDef.costType == "building_all" then
        for _, b in ipairs(Buildings.buildings) do
            if b.count < nextDef.need then
                return false, "需要每种建筑 " .. nextDef.need .. " 个（" .. b.name .. " 仅 " .. b.count .. "）"
            end
        end
        return true, nil
    end

    return false, "未知成本类型"
end

--- 获取升级描述
function DM.GetUpgradeCostText()
    local nextDef = DM.GetNextLevelDef()
    if not nextDef then return "已满级" end

    if nextDef.costType == "none" then
        return "免费"
    elseif nextDef.costType == "cookie" then
        return GameState.FormatNumber(nextDef.cost)
    elseif nextDef.costType == "building" then
        local b = Buildings.buildings[nextDef.buildIdx]
        if b then return nextDef.need .. " 个 " .. b.name end
        return "???"
    elseif nextDef.costType == "building_all" then
        return "每种建筑 " .. nextDef.need .. " 个"
    end
    return "???"
end

--- 获取升级费用图标
function DM.GetUpgradeCostIcon()
    local nextDef = DM.GetNextLevelDef()
    if not nextDef then return nil end
    if nextDef.costType == "cookie" then
        return "image/金币.png"
    elseif nextDef.costType == "building" then
        local b = Buildings.buildings[nextDef.buildIdx]
        if b then return b.iconImage end
    end
    return nil
end

--- 执行升级
---@return boolean success
function DM.Upgrade()
    local canUpgrade, reason = DM.CanUpgrade()
    if not canUpgrade then
        print("[Dragon] 升级失败: " .. (reason or ""))
        return false
    end

    local nextDef = DD.GetLevel(dragonLevel_ + 1)
    if not nextDef then return false end

    -- 扣除费用
    if nextDef.costType == "cookie" then
        GameState.coins = GameState.coins - nextDef.cost
    elseif nextDef.costType == "building" then
        local b = Buildings.buildings[nextDef.buildIdx]
        b.count = b.count - nextDef.need
    elseif nextDef.costType == "building_all" then
        for _, b in ipairs(Buildings.buildings) do
            b.count = b.count - nextDef.need
        end
    end

    -- 扣除本级XP（重置进度条）
    local xpNeeded = DD.GetXPRequired(dragonLevel_ + 1)
    if xpNeeded > 0 then
        levelXP_ = levelXP_ - xpNeeded
        if levelXP_ < 0 then levelXP_ = 0 end
    end

    dragonLevel_ = dragonLevel_ + 1

    -- 5级起每级获得 1 天赋点
    if dragonLevel_ >= DD.TALENT_UNLOCK_LEVEL then
        talentPoints_ = talentPoints_ + 1
        print("[Dragon] 获得 1 天赋点 (可用: " .. talentPoints_ .. ")")
    end

    -- 解锁策略模块
    local auraUnlocked = nil
    if nextDef.auraUnlock then
        unlockedAuras_[nextDef.auraUnlock] = true
        auraUnlocked = DD.FindAura(nextDef.auraUnlock)
        print("[Dragon] 策略模块解锁: " .. (auraUnlocked and auraUnlocked.name or nextDef.auraUnlock))
    end

    -- 解锁副策略槽
    if nextDef.secondSlot then
        secondSlotUnlocked_ = true
        print("[Dragon] 副策略槽解锁！")
    end

    print("[Dragon] 升级至 Lv." .. dragonLevel_ .. " " .. nextDef.name)

    if onLevelUp_ then
        onLevelUp_(dragonLevel_, auraUnlocked)
    end

    return true
end

--- 购买AI原型机（-1 → 0）
function DM.BuyEgg()
    if dragonLevel_ >= 0 then return false end
    local eggDef = DD.GetLevel(0)
    if not eggDef then return false end
    if GameState.coins < eggDef.cost then return false end

    GameState.coins = GameState.coins - eggDef.cost
    dragonLevel_ = 0
    print("[Dragon] AI原型机已购买！")

    if onLevelUp_ then onLevelUp_(0, nil) end
    return true
end

-- ============================================================================
-- 策略模块装备
-- ============================================================================

function DM.EquipAura(slot, auraId)
    if slot < 1 or slot > 2 then return false end
    if slot == 2 and not secondSlotUnlocked_ then return false end
    if auraId and not unlockedAuras_[auraId] then return false end

    local otherSlot = slot == 1 and 2 or 1
    if auraId and equippedAuras_[otherSlot] == auraId then
        equippedAuras_[otherSlot] = nil
    end

    equippedAuras_[slot] = auraId

    local aura = auraId and DD.FindAura(auraId)
    print("[Dragon] 槽位 " .. slot .. " 装备: " .. (aura and aura.name or "空"))

    if onEquipAura_ then onEquipAura_(slot, auraId) end
    return true
end

-- ============================================================================
-- AI洞察
-- ============================================================================

function DM.PetDragon()
    if not dropsUnlocked_ then return nil end
    if dragonLevel_ < 23 then return nil end

    if math.random() > DD.DROP_CHANCE then return nil end

    local drop = DD.drops[currentDropIndex_]
    if not drop then return nil end

    if collectedDrops_[drop.id] then
        for _, d in ipairs(DD.drops) do
            if not collectedDrops_[d.id] then
                drop = d
                break
            end
        end
        if collectedDrops_[drop.id] then return nil end
    end

    collectedDrops_[drop.id] = true
    print("[Dragon] 洞察获得: " .. drop.name)

    if onDrop_ then onDrop_(drop) end
    return drop
end

-- ============================================================================
-- 经验值 —— 增减
-- ============================================================================

--- 添加经验值（任务奖励等）
---@param amount number
function DM.AddXP(amount)
    if dragonLevel_ < 0 then return end
    currentXP_ = currentXP_ + amount
    levelXP_ = levelXP_ + amount
end

-- ============================================================================
-- 效果计算 —— 策略模块 + 洞察 + 天赋 三合一
-- ============================================================================

--- 获取某效果值（策略模块 + 洞察 + 天赋叠加）
---@param fieldName string
---@param defaultVal number 0=加法聚合, 1=乘法聚合
---@return number
local function GetCombinedEffect(fieldName, defaultVal)
    local val = defaultVal

    -- 1) 策略模块（装备的光环）
    for slot = 1, 2 do
        local auraId = equippedAuras_[slot]
        if auraId then
            local aura = DD.FindAura(auraId)
            if aura and aura[fieldName] then
                if defaultVal == 1 then
                    val = val * aura[fieldName]
                else
                    val = val + aura[fieldName]
                end
            end
        end
    end

    -- 2) AI洞察（已收集的掉落物）
    for _, drop in ipairs(DD.drops) do
        if collectedDrops_[drop.id] and drop[fieldName] then
            if defaultVal == 1 then
                val = val * drop[fieldName]
            else
                val = val + drop[fieldName]
            end
        end
    end

    -- 3) 天赋加成
    for talentId, _ in pairs(learnedTalents_) do
        local branch, tierIdx = DD.FindTalent(talentId)
        if branch and tierIdx then
            local effect = branch.tiers[tierIdx].effect
            if effect and effect[fieldName] then
                if defaultVal == 1 then
                    val = val * effect[fieldName]
                else
                    val = val + effect[fieldName]
                end
            end
        end
    end

    return val
end

--- 以下所有 Get* 方法保持原有接口签名，内部改用三合一计算

function DM.GetKittenBonus()      return GetCombinedEffect("kittenBonus", 0) end
function DM.GetClickBonus()       return GetCombinedEffect("clickBonus", 0) end
function DM.GetCostReduction()    return GetCombinedEffect("costReduction", 0) end
function DM.GetPrestigeBonus()    return GetCombinedEffect("prestigeBonus", 0) end
function DM.GetLuckyFreqMul()     return GetCombinedEffect("luckyFreqMul", 1) end
function DM.GetLuckyDurMul()      return GetCombinedEffect("luckyDurMul", 1) end
function DM.GetLuckyRewardMul()   return GetCombinedEffect("luckyRewardMul", 1) end
function DM.GetProductionMul()    return GetCombinedEffect("productionMul", 1) end
function DM.GetCpsMul()           return GetCombinedEffect("cpsMul", 0) end
function DM.GetSugarBonus()       return GetCombinedEffect("sugarBonus", 0) end

function DM.HasDragonHarvest()
    for slot = 1, 2 do
        local auraId = equippedAuras_[slot]
        if auraId then
            local aura = DD.FindAura(auraId)
            if aura and aura.dragonHarvest then return true end
        end
    end
    return false
end

function DM.HasDragonflight()
    for slot = 1, 2 do
        local auraId = equippedAuras_[slot]
        if auraId then
            local aura = DD.FindAura(auraId)
            if aura and aura.dragonflightBuff then return true end
        end
    end
    return false
end

function DM.HasGrandmaSynergy()
    for slot = 1, 2 do
        local auraId = equippedAuras_[slot]
        if auraId then
            local aura = DD.FindAura(auraId)
            if aura and aura.grandmaSynergy then return true end
        end
    end
    return false
end

function DM.GetGrandmaSynergyMul()
    if not DM.HasGrandmaSynergy() then return 1 end
    local nonGrandmaCount = 0
    for _, b in ipairs(Buildings.buildings) do
        if b.id ~= "grandma" then
            nonGrandmaCount = nonGrandmaCount + b.count
        end
    end
    return 1 + nonGrandmaCount * 0.01
end

-- ============================================================================
-- 升级费用折扣（天赋中的 upgradeCostReduction）
-- ============================================================================

function DM.GetUpgradeCostReduction()
    return GetCombinedEffect("upgradeCostReduction", 0)
end

-- ============================================================================
-- 帧更新
-- ============================================================================

function DM.Update(dt)
    -- 经验值累积（5级起）
    if dragonLevel_ >= DD.TALENT_UNLOCK_LEVEL and dragonLevel_ < DD.MAX_LEVEL then
        local xpGain = DM.GetXPPerSecond() * dt
        if xpGain > 0 then
            currentXP_ = currentXP_ + xpGain
            levelXP_ = levelXP_ + xpGain
        end
    end

    -- 洞察轮换
    if dropsUnlocked_ then
        dropRotateTimer_ = dropRotateTimer_ + dt
        if dropRotateTimer_ >= DD.DROP_ROTATE_INTERVAL then
            dropRotateTimer_ = dropRotateTimer_ - DD.DROP_ROTATE_INTERVAL
            currentDropIndex_ = currentDropIndex_ + 1
            if currentDropIndex_ > #DD.drops then
                currentDropIndex_ = 1
            end
        end
    end

    -- 派遣任务计时
    if activeMission_ and not DM.IsMissionDone() then
        activeMission_.elapsed = (activeMission_.elapsed or 0) + dt
    end

    -- 任务刷新冷却
    if missionRefreshTimer_ > 0 then
        missionRefreshTimer_ = missionRefreshTimer_ - dt
        if missionRefreshTimer_ < 0 then missionRefreshTimer_ = 0 end
    end
end

-- ============================================================================
-- 存档/读档（向后兼容）
-- ============================================================================

function DM.GetSaveData()
    local auras = {}
    for id, _ in pairs(unlockedAuras_) do auras[#auras + 1] = id end
    local drops = {}
    for id, _ in pairs(collectedDrops_) do drops[#drops + 1] = id end
    local talents = {}
    for id, _ in pairs(learnedTalents_) do talents[#talents + 1] = id end

    return {
        dragonLevel = dragonLevel_,
        unlockedAuras = auras,
        equippedAuras = { equippedAuras_[1], equippedAuras_[2] },
        secondSlotUnlocked = secondSlotUnlocked_,
        collectedDrops = drops,
        dropsUnlocked = dropsUnlocked_,
        -- 新增字段（旧存档不会有这些，读取时给默认值）
        currentXP = currentXP_,
        levelXP = levelXP_,
        learnedTalents = talents,
        talentPoints = talentPoints_,
        -- 派遣任务
        activeMission = activeMission_,
        completedMissionCount = completedMissionCount_,
    }
end

function DM.LoadSaveData(data)
    if not data then return end
    dragonLevel_ = data.dragonLevel or -1
    secondSlotUnlocked_ = data.secondSlotUnlocked or false
    dropsUnlocked_ = data.dropsUnlocked or false
    dropRotateTimer_ = 0
    currentDropIndex_ = 1

    unlockedAuras_ = {}
    if data.unlockedAuras then
        for _, id in ipairs(data.unlockedAuras) do unlockedAuras_[id] = true end
    end

    equippedAuras_ = { nil, nil }
    if data.equippedAuras then
        equippedAuras_[1] = data.equippedAuras[1]
        equippedAuras_[2] = data.equippedAuras[2]
    end

    collectedDrops_ = {}
    if data.collectedDrops then
        for _, id in ipairs(data.collectedDrops) do collectedDrops_[id] = true end
    end

    -- 经验值（向后兼容：旧存档为 0）
    currentXP_ = data.currentXP or 0
    levelXP_ = data.levelXP or 0

    -- 天赋（向后兼容）
    learnedTalents_ = {}
    if data.learnedTalents then
        for _, id in ipairs(data.learnedTalents) do learnedTalents_[id] = true end
    end
    talentPoints_ = data.talentPoints or 0

    -- 向后兼容：旧存档中5级以上的用户应补偿天赋点
    if talentPoints_ == 0 and not data.learnedTalents and dragonLevel_ >= DD.TALENT_UNLOCK_LEVEL then
        local compensate = dragonLevel_ - DD.TALENT_UNLOCK_LEVEL + 1
        talentPoints_ = compensate
        print("[Dragon] 旧存档兼容：补偿 " .. compensate .. " 天赋点")
    end

    -- 派遣任务（向后兼容）
    activeMission_ = data.activeMission or nil
    completedMissionCount_ = data.completedMissionCount or 0
    missionRefreshTimer_ = 0

    print("[DragonManager] 存档恢复 | 等级:" .. dragonLevel_ ..
          " 策略:" .. #(data.unlockedAuras or {}) ..
          " 洞察:" .. #(data.collectedDrops or {}) ..
          " XP:" .. math.floor(currentXP_) ..
          " 天赋点:" .. talentPoints_ ..
          " 任务完成:" .. completedMissionCount_)
end

return DM
