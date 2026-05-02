-- ============================================================================
-- core/GrandmapoManager.lua
-- 奶奶末日管理器：研究升级链 + 阶段管理 + 愤怒金币 + Elder Pledge
-- ============================================================================

local GameState = require("core.GameState")
local Buildings = require("config.Buildings")
local GD = require("config.GrandmapocalypseDefs")

local GM = {}

-- ======== 状态 ========
local phase_ = GD.PHASE_NONE           -- 当前阶段
local researchBought_ = {}              -- researchBought_[i] = true
local researchUnlocked_ = {}            -- researchUnlocked_[i] = true（可见可购买）
local researchTimer_ = 0                -- 下一个研究解锁倒计时

-- Elder Pledge
local pledgeActive_ = false
local pledgeTimer_ = 0                  -- 剩余安抚时间
local pledgePurchases_ = 0             -- 累计购买次数
local hasSacrificialPins_ = false       -- 是否有双倍持续升级

-- 回调
local onPhaseChange_ = nil              -- function(newPhase)
local onResearchUnlock_ = nil           -- function(index)

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 计算当前应处的阶段（基于已购买的研究）
local function CalcPhase()
    for i = #GD.researchChain, 1, -1 do
        if researchBought_[i] and GD.researchChain[i].phaseTriggered then
            return GD.researchChain[i].phaseTriggered
        end
    end
    return GD.PHASE_NONE
end

--- 获取奶奶数量
local function GetGrandmaCount()
    for _, b in ipairs(Buildings.buildings) do
        if b.id == "grandma" then return b.count end
    end
    return 0
end

--- 获取已解锁的奶奶类型数量（简化：每种建筑>=15且有>=1奶奶 即算一种）
local function GetGrandmaTypes()
    local count = 0
    local hasGrandma = GetGrandmaCount() >= 1
    if not hasGrandma then return 0 end
    -- 从 farm(index 3) 开始，每种建筑 >= 15 个算解锁一种奶奶类型
    for i = 3, #Buildings.buildings do
        if Buildings.buildings[i].count >= 15 then
            count = count + 1
        end
    end
    return count
end

--- 获取最新已购买的研究索引
local function GetLastBoughtIndex()
    for i = #GD.researchChain, 1, -1 do
        if researchBought_[i] then return i end
    end
    return 0
end

-- ============================================================================
-- 初始化
-- ============================================================================

function GM.Init()
    phase_ = GD.PHASE_NONE
    researchBought_ = {}
    researchUnlocked_ = {}
    researchTimer_ = 0
    pledgeActive_ = false
    pledgeTimer_ = 0
    pledgePurchases_ = 0
    hasSacrificialPins_ = false
end

function GM.SetOnPhaseChange(fn) onPhaseChange_ = fn end
function GM.SetOnResearchUnlock(fn) onResearchUnlock_ = fn end

-- ============================================================================
-- 查询接口
-- ============================================================================

function GM.GetPhase() return pledgeActive_ and GD.PHASE_APPEASED or phase_ end
function GM.GetRawPhase() return phase_ end
function GM.GetPhaseName() return GD.phaseNames[GM.GetPhase()] or "未知" end
function GM.GetPhaseIcon() return GD.phaseIcons[GM.GetPhase()] or "" end
function GM.GetPhaseColor() return GD.phaseColors[GM.GetPhase()] or { 200, 200, 200, 255 } end

function GM.IsResearchBought(i) return researchBought_[i] == true end
function GM.IsResearchUnlocked(i) return researchUnlocked_[i] == true end

function GM.IsPledgeActive() return pledgeActive_ end
function GM.GetPledgeTimer() return pledgeTimer_ end
function GM.GetPledgePurchases() return pledgePurchases_ end
function GM.GetResearchTimer() return researchTimer_ end

--- 获取当前 Elder Pledge 价格
function GM.GetPledgeCost()
    return GD.GetPledgeCost(pledgePurchases_)
end

--- 获取研究链数据（带状态）
function GM.GetResearchStatus()
    local result = {}
    local nextIdx = GetLastBoughtIndex() + 1
    for i, r in ipairs(GD.researchChain) do
        local bought = researchBought_[i] == true
        local unlocked = researchUnlocked_[i] == true
        result[i] = {
            def = r,
            bought = bought,
            unlocked = unlocked,
            isNext = (not bought and not unlocked and i == nextIdx),
        }
    end
    return result
end

--- 获取研究产量加成总倍率
function GM.GetProductionMultiplier()
    local mul = 0
    for i, r in ipairs(GD.researchChain) do
        if researchBought_[i] and r.productionMul then
            mul = mul + r.productionMul
        end
    end
    return 1 + mul
end

--- 获取奶奶效率额外倍率（Ritual Rolling Pins）
function GM.GetGrandmaMultiplier()
    local mul = 1
    for i, r in ipairs(GD.researchChain) do
        if researchBought_[i] and r.grandmaMultiplier then
            mul = mul * r.grandmaMultiplier
        end
    end
    return mul
end

--- 获取奶奶协同加成额外 CpS（One Mind / Communal Brainsweep）
function GM.GetGrandmaSynergyCps()
    local grandmaCount = GetGrandmaCount()
    local bonus = 0
    for i, r in ipairs(GD.researchChain) do
        if researchBought_[i] and r.grandmaSynergy then
            -- 每奶奶 +synergy 基础CpS × 奶奶数
            bonus = bonus + r.grandmaSynergy * grandmaCount * grandmaCount
        end
    end
    return bonus
end

--- 获取传送门协同加成额外 CpS（Elder Pact）
function GM.GetPortalSynergyCps()
    local grandmaCount = GetGrandmaCount()
    local portalCount = 0
    for _, b in ipairs(Buildings.buildings) do
        if b.id == "portal" then portalCount = b.count break end
    end
    local bonus = 0
    for i, r in ipairs(GD.researchChain) do
        if researchBought_[i] and r.portalSynergy then
            bonus = bonus + r.portalSynergy * grandmaCount * portalCount
        end
    end
    return bonus
end

--- 判断愤怒金币是否替换正常金币
---@return boolean isWrath, string coinType
function GM.RollWrathCoin()
    local effectivePhase = GM.GetPhase()
    local chance = GD.wrathChance[effectivePhase] or 0
    if chance <= 0 then
        return false, "lucky"
    end
    if math.random() < chance then
        return true, "wrath"
    end
    return false, "lucky"
end

--- 从愤怒效果池按权重抽取一个效果
---@return table effect
function GM.PickWrathEffect()
    local pool = GD.wrathEffects
    local totalWeight = 0
    for _, e in ipairs(pool) do
        totalWeight = totalWeight + e.weight
    end
    local roll = math.random() * totalWeight
    local cumulative = 0
    for _, e in ipairs(pool) do
        cumulative = cumulative + e.weight
        if roll <= cumulative then
            return e
        end
    end
    return pool[1]
end

--- 获取皱巴虫生成速率倍率
function GM.GetWrinklerSpawnRate()
    local effectivePhase = GM.GetPhase()
    return GD.wrinkler.spawnRateMul[effectivePhase] or 0
end

-- ============================================================================
-- 操作
-- ============================================================================

--- 购买研究升级
---@param index number
---@return boolean success
function GM.BuyResearch(index)
    local r = GD.researchChain[index]
    if not r then return false end
    if researchBought_[index] then return false end
    if not researchUnlocked_[index] then return false end
    if GameState.coins < r.cost then return false end

    GameState.coins = GameState.coins - r.cost
    researchBought_[index] = true

    print("[Grandmapocalypse] 购买研究: " .. r.name)

    -- 检查阶段变化
    if r.phaseTriggered then
        local oldPhase = phase_
        phase_ = CalcPhase()
        if phase_ ~= oldPhase and onPhaseChange_ then
            onPhaseChange_(phase_)
        end
        print("[Grandmapocalypse] 阶段变更: " .. (GD.phaseNames[oldPhase] or "?") ..
              " → " .. (GD.phaseNames[phase_] or "?"))
    end

    -- 启动下一个研究的解锁倒计时
    local nextIdx = index + 1
    if nextIdx <= #GD.researchChain and not researchBought_[nextIdx] then
        -- 简化：使用较短间隔方便游戏体验
        researchTimer_ = GD.RESEARCH_INTERVAL
        print("[Grandmapocalypse] 下一个研究将在 " .. researchTimer_ .. " 秒后解锁")
    end

    return true
end

--- 购买 Elder Pledge（安抚奶奶）
---@return boolean success
function GM.BuyPledge()
    if pledgeActive_ then return false end
    if phase_ == GD.PHASE_NONE then return false end

    local cost = GM.GetPledgeCost()
    if GameState.coins < cost then return false end

    GameState.coins = GameState.coins - cost
    pledgePurchases_ = pledgePurchases_ + 1
    pledgeActive_ = true

    -- 持续时间
    local dur = GD.elderPledge.duration
    if hasSacrificialPins_ then
        dur = GD.elderPledge.durationExtended
    end
    pledgeTimer_ = dur

    print("[Grandmapocalypse] Elder Pledge 激活! 持续 " ..
          math.floor(dur / 60) .. " 分钟 (第 " .. pledgePurchases_ .. " 次)")

    -- 购买 10 次后解锁加倍
    if pledgePurchases_ >= GD.elderPledge.unlockAfterPurchases then
        hasSacrificialPins_ = true
    end

    if onPhaseChange_ then
        onPhaseChange_(GD.PHASE_APPEASED)
    end

    return true
end

-- ============================================================================
-- 帧更新
-- ============================================================================

function GM.Update(dt)
    -- ===== 研究解锁倒计时 =====
    if researchTimer_ > 0 then
        researchTimer_ = researchTimer_ - dt
        if researchTimer_ <= 0 then
            researchTimer_ = 0
            -- 解锁下一个未购买的研究
            local lastBought = GetLastBoughtIndex()
            local nextIdx = lastBought + 1
            if nextIdx <= #GD.researchChain and not researchBought_[nextIdx] then
                researchUnlocked_[nextIdx] = true
                print("[Grandmapocalypse] 研究解锁: " .. GD.researchChain[nextIdx].name)
                if onResearchUnlock_ then
                    onResearchUnlock_(nextIdx)
                end
            end
        end
    end

    -- ===== 检查第一个研究是否可解锁 =====
    if not researchUnlocked_[1] and not researchBought_[1] then
        local r1 = GD.researchChain[1]
        local grandmaCount = GetGrandmaCount()
        local grandmaTypes = GetGrandmaTypes()
        if grandmaCount >= (r1.needGrandmas or 6) and grandmaTypes >= (r1.needGrandmaTypes or 7) then
            researchUnlocked_[1] = true
            print("[Grandmapocalypse] 金币研究所已解锁! (奶奶:" .. grandmaCount ..
                  " 类型:" .. grandmaTypes .. ")")
            if onResearchUnlock_ then
                onResearchUnlock_(1)
            end
        end
    end

    -- ===== Elder Pledge 倒计时 =====
    if pledgeActive_ then
        pledgeTimer_ = pledgeTimer_ - dt
        if pledgeTimer_ <= 0 then
            pledgeActive_ = false
            pledgeTimer_ = 0
            print("[Grandmapocalypse] Elder Pledge 过期，奶奶末日恢复")
            if onPhaseChange_ then
                onPhaseChange_(phase_)
            end
        end
    end
end

--- 调试：强制推进到愤怒阶段并解锁所有研究
function GM.DebugForceAngered()
    for i = 1, #GD.researchChain do
        researchBought_[i] = true
        researchUnlocked_[i] = true
    end
    pledgeActive_ = false
    phase_ = CalcPhase()
    if onPhaseChange_ then onPhaseChange_(phase_) end
    print("[Grandmapocalypse][Debug] 强制进入阶段: " .. (GD.phaseNames[phase_] or "?"))
end

-- ============================================================================
-- 存档/读档
-- ============================================================================

--- 导出存档数据
---@return table
function GM.GetSaveData()
    local bought = {}
    local unlocked = {}
    for i = 1, #GD.researchChain do
        if researchBought_[i] then bought[#bought + 1] = i end
        if researchUnlocked_[i] then unlocked[#unlocked + 1] = i end
    end
    return {
        phase = phase_,
        researchBought = bought,
        researchUnlocked = unlocked,
        researchTimer = researchTimer_,
        pledgeActive = pledgeActive_,
        pledgeTimer = pledgeTimer_,
        pledgePurchases = pledgePurchases_,
        hasSacrificialPins = hasSacrificialPins_,
    }
end

--- 从存档恢复数据
---@param data table
function GM.LoadSaveData(data)
    if not data then return end
    phase_ = data.phase or GD.PHASE_NONE
    researchTimer_ = data.researchTimer or 0
    pledgeActive_ = data.pledgeActive or false
    pledgeTimer_ = data.pledgeTimer or 0
    pledgePurchases_ = data.pledgePurchases or 0
    hasSacrificialPins_ = data.hasSacrificialPins or false

    researchBought_ = {}
    if data.researchBought then
        for _, i in ipairs(data.researchBought) do
            researchBought_[i] = true
        end
    end
    researchUnlocked_ = {}
    if data.researchUnlocked then
        for _, i in ipairs(data.researchUnlocked) do
            researchUnlocked_[i] = true
        end
    end
    print("[GrandmapoManager] 存档恢复 | 阶段:" .. (GD.phaseNames[phase_] or "?") ..
          " 安抚:" .. tostring(pledgeActive_))
end

return GM
