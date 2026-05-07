-- ============================================================================
-- core/GrimoireManager.lua
-- 研发实验室核心逻辑：研发能量管理、研发项目施放、效果计算、存档
-- 对齐 Cookie Clicker 原版 Grimoire 的 7 个法术效果
-- ============================================================================

local GameState = require("core.GameState")
local GC        = require("config.GrimoireConfig")
local SaveBridge = require("core.SaveBridge")

local GM = {}

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------

local currentMana_    = 0       ---@type number 当前研发能量
local globalCooldown_ = 0       ---@type number 全局冷却剩余（秒）
local totalCasts_     = 0       ---@type number 累计施法次数（成就用）

-- 活跃的临时 buff 列表
-- 每个 buff: { id=string, type=string, value=number, remaining=number, duration=number }
-- type: "cps" | "building_price" | "upgrade_price"
local activeBuffs_    = {}      ---@type table[]

-- 回调
local onSpellCast_ = nil        ---@type fun(spellId: string, success: boolean, desc: string)|nil

-- ---------------------------------------------------------------------------
-- 前向声明
-- ---------------------------------------------------------------------------
local ApplySpellSuccess
local ApplySpellFailure
local AddBuff

-- ---------------------------------------------------------------------------
-- 初始化
-- ---------------------------------------------------------------------------

function GM.Init()
    currentMana_    = GC.BASE_MANA  -- 初始满法力
    globalCooldown_ = 0
    totalCasts_     = 0
    activeBuffs_    = {}

    SaveBridge.Register("grimoire", GM.GetSaveData, GM.LoadSaveData)
end

-- ---------------------------------------------------------------------------
-- 回调注册
-- ---------------------------------------------------------------------------

---@param fn fun(spellId: string, success: boolean, desc: string)
function GM.SetOnSpellCast(fn) onSpellCast_ = fn end

-- ---------------------------------------------------------------------------
-- 查询接口
-- ---------------------------------------------------------------------------

--- 获取研发中心数量
---@return number
function GM.GetWizardCount()
    local Buildings = require("config.Buildings")
    for _, b in ipairs(Buildings.buildings) do
        if b.id == "wizard" then
            return b.count
        end
    end
    return 0
end

--- 是否已解锁研发实验室
---@return boolean
function GM.IsUnlocked()
    return GM.GetWizardCount() >= GC.UNLOCK_BUILDING_COUNT
end

--- [调试] 补满魔力
function GM.RefillMana()
    currentMana_ = GM.GetMaxMana()
end

--- [调试] 清除全局冷却
function GM.ClearCooldown()
    globalCooldown_ = 0
end

--- [调试] 清除所有 Buff
function GM.ClearBuffs()
    activeBuffs_ = {}
end

--- 获取最大研发能量
---@return number
function GM.GetMaxMana()
    return GC.CalcMaxMana(GM.GetWizardCount())
end

--- 获取当前研发能量
---@return number
function GM.GetCurrentMana()
    return currentMana_
end

--- 获取研发能量百分比
---@return number 0~1
function GM.GetManaPercent()
    local max = GM.GetMaxMana()
    if max <= 0 then return 0 end
    return math.min(1, currentMana_ / max)
end

--- 获取全局冷却剩余
---@return number
function GM.GetGlobalCooldown()
    return globalCooldown_
end

--- 是否可以施放指定法术
---@param spellId string
---@return boolean
---@return string|nil reason
function GM.CanCast(spellId)
    local spell = GC.FindSpell(spellId)
    if not spell then return false, "invalid_spell" end
    if globalCooldown_ > 0 then return false, "cooling" end
    if currentMana_ < spell.manaCost then return false, "no_mana" end
    return true
end

--- 获取活跃 buff 列表（只读）
---@return table[]
function GM.GetActiveBuffs()
    return activeBuffs_
end

--- 获取累计施法次数
---@return number
function GM.GetTotalCasts()
    return totalCasts_
end

-- ---------------------------------------------------------------------------
-- 价格乘数接口（供 GameManager 购买逻辑调用）
-- ---------------------------------------------------------------------------

--- 获取建筑价格乘数（来自精灵助手 buff）
---@return number 1.0 = 无变化, 0.98 = 便宜2%, 1.02 = 贵2%
function GM.GetBuildingPriceMul()
    local mul = 1.0
    for _, buf in ipairs(activeBuffs_) do
        if buf.type == "building_price" and buf.remaining > 0 then
            mul = mul + buf.value
        end
    end
    return mul
end

--- 获取升级价格乘数（来自谈判专家 buff）
---@return number 1.0 = 无变化, 0.98 = 便宜2%, 1.02 = 贵2%
function GM.GetUpgradePriceMul()
    local mul = 1.0
    for _, buf in ipairs(activeBuffs_) do
        if buf.type == "upgrade_price" and buf.remaining > 0 then
            mul = mul + buf.value
        end
    end
    return mul
end

-- ---------------------------------------------------------------------------
-- 效果计算（供 GameManager.RecalcProduction 调用）
-- ---------------------------------------------------------------------------

--- 获取 CPS 乘数（来自时间加速 buff）
---@return number
function GM.GetCPSMultiplier()
    local mul = 1.0
    for _, buf in ipairs(activeBuffs_) do
        if buf.type == "cps" and buf.remaining > 0 then
            mul = mul + buf.value
        end
    end
    return mul
end

--- 获取 CPC 乘数（当前无点击相关法术，固定返回 1.0）
---@return number
function GM.GetCPCMultiplier()
    return 1.0
end

--- 每次点击时调用（当前无点击消耗型 buff）
function GM.OnClick()
    -- CC 原版 Grimoire 无点击相关法术，留作接口备用
end

-- ---------------------------------------------------------------------------
-- 施法核心逻辑
-- ---------------------------------------------------------------------------

--- 施放研发项目
---@param spellId string
---@return table|nil result  { success=bool, desc=string }
function GM.CastSpell(spellId)
    local canCast, reason = GM.CanCast(spellId)
    if not canCast then
        print("[Grimoire] 无法施放 " .. spellId .. ": " .. (reason or "unknown"))
        return nil
    end

    local spell = GC.FindSpell(spellId)
    local maxMana = GM.GetMaxMana()

    -- 计算失败率（施法前的法力）
    local failRate = GC.CalcFailRate(spell, currentMana_, maxMana)

    -- 扣除法力
    currentMana_ = currentMana_ - spell.manaCost
    totalCasts_ = totalCasts_ + 1

    -- 设置全局冷却
    globalCooldown_ = GC.SPELL_COOLDOWN

    -- 判定成功/失败
    local roll = math.random()
    local success = roll >= failRate

    local desc
    if success then
        desc = ApplySpellSuccess(spell)
        print("[Grimoire] " .. spell.name .. " 成功! (" .. string.format("%.0f%%", failRate * 100) .. " 失败率)")
    else
        desc = ApplySpellFailure(spell)
        print("[Grimoire] " .. spell.name .. " 失败! (" .. string.format("%.0f%%", failRate * 100) .. " 失败率)")
    end

    -- 触发回调
    if onSpellCast_ then
        onSpellCast_(spellId, success, desc)
    end

    return { success = success, desc = desc }
end

--- 内部：直接执行法术效果（供赌徒直觉调用，不扣法力、不触发冷却/回调）
---@param spell GrimoireSpell
---@param forceSuccess boolean
---@return string desc
local function ExecuteSpellEffect(spell, forceSuccess)
    if forceSuccess then
        return ApplySpellSuccess(spell)
    else
        return ApplySpellFailure(spell)
    end
end

-- ---------------------------------------------------------------------------
-- 法术效果实现（成功）
-- ---------------------------------------------------------------------------

---@param spell GrimoireSpell
---@return string desc
ApplySpellSuccess = function(spell)
    local S = GameState
    local id = spell.id

    if id == "market_surge" then
        -- #1 Conjure Baked Goods: 获得 CPS × 10分钟 的金币
        local gain = S.coinsPerSecond * 10 * 60
        S.coins = S.coins + gain
        return "获得 " .. S.FormatNumber(gain) .. " 金币"

    elseif id == "force_hand" then
        -- #2 Force the Hand of Fate: 立即生成一个幸运金币
        S.luckyTimer = 0
        return "幸运金币即将出现"

    elseif id == "stretch_time" then
        -- #3 Stretch Time: CPS +20%，持续 60 秒
        AddBuff("stretch_time_up", "cps", 0.20, GC.BUFF_DURATION)
        return "CPS +20%，持续 60 秒"

    elseif id == "talent_hunt" then
        -- #4 Spontaneous Edifice: 随机一种已拥有的建筑 +1
        local Buildings = require("config.Buildings")
        local candidates = {}
        for i, b in ipairs(Buildings.buildings) do
            if b.count > 0 and i > 1 then
                candidates[#candidates + 1] = { index = i, building = b }
            end
        end
        if #candidates > 0 then
            local pick = candidates[math.random(1, #candidates)]
            pick.building.count = pick.building.count + 1
            return pick.building.name .. " +1（免费）"
        else
            return "没有可增加的建筑"
        end

    elseif id == "haggler_charm" then
        -- #5 Haggler's Charm: 升级价格 -2%，持续 60 秒
        AddBuff("haggler_down", "upgrade_price", -0.02, GC.BUFF_DURATION)
        return "升级价格 -2%，持续 60 秒"

    elseif id == "crafty_pixie" then
        -- #6 Summon Crafty Pixies: 建筑价格 -2%，持续 60 秒
        AddBuff("crafty_down", "building_price", -0.02, GC.BUFF_DURATION)
        return "建筑价格 -2%，持续 60 秒"

    elseif id == "gambler_dream" then
        -- #7 Gambler's Fever Dream: 随机施放一个其他法术（成功效果）
        local others = {}
        for _, sp in ipairs(GC.spells) do
            if sp.id ~= "gambler_dream" then
                others[#others + 1] = sp
            end
        end
        if #others > 0 then
            local pick = others[math.random(1, #others)]
            local result = ExecuteSpellEffect(pick, true)
            return pick.name .. "（成功）: " .. result
        end
        return "无可用法术"
    end

    return ""
end

-- ---------------------------------------------------------------------------
-- 法术效果实现（失败）
-- ---------------------------------------------------------------------------

---@param spell GrimoireSpell
---@return string desc
ApplySpellFailure = function(spell)
    local S = GameState
    local id = spell.id

    if id == "market_surge" then
        -- #1 失败: 损失 CPS × 5分钟 的金币
        local loss = S.coinsPerSecond * 5 * 60
        S.coins = math.max(0, S.coins - loss)
        return "损失 " .. S.FormatNumber(loss) .. " 金币"

    elseif id == "force_hand" then
        -- #2 失败: 损失 CPS × 5分钟 的金币（模拟负面金币效果）
        local loss = S.coinsPerSecond * 5 * 60
        S.coins = math.max(0, S.coins - loss)
        return "损失 " .. S.FormatNumber(loss) .. " 金币"

    elseif id == "stretch_time" then
        -- #3 失败: CPS -20%，持续 60 秒
        AddBuff("stretch_time_down", "cps", -0.20, GC.BUFF_DURATION)
        return "CPS -20%，持续 60 秒"

    elseif id == "talent_hunt" then
        -- #4 失败: 随机一种已拥有的建筑 -1
        local Buildings = require("config.Buildings")
        local candidates = {}
        for i, b in ipairs(Buildings.buildings) do
            if b.count > 0 and i > 1 then
                candidates[#candidates + 1] = { index = i, building = b }
            end
        end
        if #candidates > 0 then
            local pick = candidates[math.random(1, #candidates)]
            pick.building.count = math.max(0, pick.building.count - 1)
            return pick.building.name .. " -1"
        else
            return "没有可减少的建筑"
        end

    elseif id == "haggler_charm" then
        -- #5 失败: 升级价格 +2%，持续 60 秒
        AddBuff("haggler_up", "upgrade_price", 0.02, GC.BUFF_DURATION)
        return "升级价格 +2%，持续 60 秒"

    elseif id == "crafty_pixie" then
        -- #6 失败: 建筑价格 +2%，持续 60 秒
        AddBuff("crafty_up", "building_price", 0.02, GC.BUFF_DURATION)
        return "建筑价格 +2%，持续 60 秒"

    elseif id == "gambler_dream" then
        -- #7 失败: 随机施放一个其他法术（失败效果）
        local others = {}
        for _, sp in ipairs(GC.spells) do
            if sp.id ~= "gambler_dream" then
                others[#others + 1] = sp
            end
        end
        if #others > 0 then
            local pick = others[math.random(1, #others)]
            local result = ExecuteSpellEffect(pick, false)
            return pick.name .. "（失败）: " .. result
        end
        return "无可用法术"
    end

    return ""
end

-- ---------------------------------------------------------------------------
-- Buff 管理
-- ---------------------------------------------------------------------------

--- 添加临时 buff
---@param id string buff 唯一标识
---@param buffType string "cps" | "building_price" | "upgrade_price"
---@param value number 乘数偏移量（-0.02 = -2%，0.20 = +20%）
---@param duration number 持续时间（秒）
AddBuff = function(id, buffType, value, duration)
    -- 同 id 覆盖
    for i, buf in ipairs(activeBuffs_) do
        if buf.id == id then
            activeBuffs_[i] = {
                id = id, type = buffType, value = value,
                remaining = duration, duration = duration,
            }
            return
        end
    end
    activeBuffs_[#activeBuffs_ + 1] = {
        id = id, type = buffType, value = value,
        remaining = duration, duration = duration,
    }
end

-- ---------------------------------------------------------------------------
-- 帧更新
-- ---------------------------------------------------------------------------

---@param dt number
function GM.Update(dt)
    if not GM.IsUnlocked() then return end

    -- 法力恢复
    local maxMana = GM.GetMaxMana()
    if currentMana_ < maxMana then
        currentMana_ = math.min(maxMana, currentMana_ + maxMana * GC.MANA_REGEN_RATE * dt)
    end

    -- 全局冷却
    if globalCooldown_ > 0 then
        globalCooldown_ = math.max(0, globalCooldown_ - dt)
    end

    -- Buff 倒计时
    local needRecalc = false
    local i = 1
    while i <= #activeBuffs_ do
        local buf = activeBuffs_[i]
        buf.remaining = buf.remaining - dt
        if buf.remaining <= 0 then
            table.remove(activeBuffs_, i)
            needRecalc = true
            print("[Grimoire] Buff 结束: " .. buf.id)
        else
            i = i + 1
        end
    end

    -- buff 过期需要重新计算产出/价格
    if needRecalc then
        -- 更新 GameState 中的建筑费用乘数
        GameState.buffBuildingCostMul = GM.GetBuildingPriceMul()
        if onSpellCast_ then
            onSpellCast_("_buff_expired", true, "")
        end
    end
end

-- ---------------------------------------------------------------------------
-- 存档
-- ---------------------------------------------------------------------------

---@return table
function GM.GetSaveData()
    local buffs = {}
    for _, buf in ipairs(activeBuffs_) do
        buffs[#buffs + 1] = {
            id = buf.id, type = buf.type, value = buf.value,
            remaining = buf.remaining, duration = buf.duration,
        }
    end
    return {
        mana       = currentMana_,
        cooldown   = globalCooldown_,
        buffs      = buffs,
        totalCasts = totalCasts_,
    }
end

---@param data table|nil
function GM.LoadSaveData(data)
    if not data then
        GM.Init()
        return
    end
    currentMana_    = data.mana or GC.BASE_MANA
    globalCooldown_ = data.cooldown or 0
    totalCasts_     = data.totalCasts or 0

    activeBuffs_ = {}
    if data.buffs then
        for _, buf in ipairs(data.buffs) do
            activeBuffs_[#activeBuffs_ + 1] = {
                id = buf.id, type = buf.type, value = buf.value,
                remaining = buf.remaining, duration = buf.duration,
            }
        end
    end

    -- 恢复建筑费用乘数
    GameState.buffBuildingCostMul = GM.GetBuildingPriceMul()
end

--- 飞升重置
function GM.ResetForAscension()
    GM.Init()
    GameState.buffBuildingCostMul = 1
end

return GM
