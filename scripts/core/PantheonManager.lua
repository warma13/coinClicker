-- ============================================================================
-- core/PantheonManager.lua
-- 商业顾问团核心逻辑：槽位管理、顾问装备/更换、效果计算、存档
-- 对应 Cookie Clicker 的 Temple / Pantheon 小游戏
-- ============================================================================

local GameState = require("core.GameState")
local PC        = require("config.PantheonConfig")
local SaveBridge = require("core.SaveBridge")

local PM = {}

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------

-- 槽位（1~3），每个槽位存储顾问 id 或 nil
local slotSpirits_ = { nil, nil, nil }   ---@type (string|nil)[]

-- 每个槽位的更换冷却剩余
local slotCooldowns_ = { 0, 0, 0 }      ---@type number[]

-- 已解锁的顾问（根据商业地产数量自动计算，不存档）
-- 在 Update 中定期刷新

-- 回调
local onSlotChanged_ = nil  ---@type fun()|nil

-- ---------------------------------------------------------------------------
-- 初始化
-- ---------------------------------------------------------------------------

function PM.Init()
    slotSpirits_ = { nil, nil, nil }
    slotCooldowns_ = { 0, 0, 0 }

    SaveBridge.Register("pantheon", PM.GetSaveData, PM.LoadSaveData)
end

-- ---------------------------------------------------------------------------
-- 回调注册
-- ---------------------------------------------------------------------------

---@param fn fun()
function PM.SetOnSlotChanged(fn) onSlotChanged_ = fn end

-- ---------------------------------------------------------------------------
-- 查询接口
-- ---------------------------------------------------------------------------

--- 获取指定槽位的顾问 id
---@param slotIndex number 1~3
---@return string|nil
function PM.GetSlotSpirit(slotIndex)
    return slotSpirits_[slotIndex]
end

--- 获取指定槽位的冷却剩余
---@param slotIndex number 1~3
---@return number
function PM.GetSlotCooldown(slotIndex)
    return slotCooldowns_[slotIndex] or 0
end

--- 获取商业地产数量（从 GameState 的建筑列表）
---@return number
function PM.GetTempleCount()
    local Buildings = require("config.Buildings")
    for _, b in ipairs(Buildings.buildings) do
        if b.id == "temple" then
            return b.count
        end
    end
    return 0
end

--- 获取商业地产的建筑索引
---@return number
local function GetTempleIndex()
    local Buildings = require("config.Buildings")
    for i, b in ipairs(Buildings.buildings) do
        if b.id == "temple" then return i end
    end
    return 0
end

--- 获取商业地产等级（通过 SugarLumpManager）
---@return number
function PM.GetTempleLevel()
    local SLM = require("core.SugarLumpManager")
    local idx = GetTempleIndex()
    if idx > 0 then
        return SLM.GetBuildingLevel(idx)
    end
    return 0
end

--- 是否已解锁万神殿
---@return boolean
function PM.IsUnlocked()
    return PM.GetTempleCount() >= PC.UNLOCK_BUILDING_COUNT
end

--- [调试] 清除所有槽位冷却
function PM.ClearCooldowns()
    slotCooldowns_ = { 0, 0, 0 }
end

--- 获取可用槽位数量（按商业地产等级解锁：1/3/5级）
---@return number
function PM.GetAvailableSlots()
    return PC.GetAvailableSlots(PM.GetTempleLevel())
end

--- 获取已解锁的顾问列表
---@return table[]
function PM.GetUnlockedSpirits()
    return PC.GetUnlockedSpirits(PM.GetTempleCount())
end

--- 判断某顾问是否已被装备（在任何槽位中）
---@param spiritId string
---@return boolean, number|nil slotIndex
function PM.IsSpiritEquipped(spiritId)
    for i = 1, PC.SLOT_COUNT do
        if slotSpirits_[i] == spiritId then
            return true, i
        end
    end
    return false, nil
end

--- 判断某顾问是否已解锁
---@param spiritId string
---@return boolean
function PM.IsSpiritUnlocked(spiritId)
    local spirit = PC.FindSpirit(spiritId)
    if not spirit then return false end
    return PM.GetTempleCount() >= spirit.unlockCount
end

-- ---------------------------------------------------------------------------
-- 操作接口
-- ---------------------------------------------------------------------------

--- 装备顾问到槽位
---@param slotIndex number 1~3
---@param spiritId string|nil  nil 表示移除
---@return boolean success
---@return string|nil reason
function PM.EquipSpirit(slotIndex, spiritId)
    -- 检查槽位有效
    if slotIndex < 1 or slotIndex > PC.SLOT_COUNT then
        return false, "invalid_slot"
    end

    -- 检查槽位是否已解锁
    local available = PM.GetAvailableSlots()
    if slotIndex > available then
        return false, "slot_locked"
    end

    -- 移除操作
    if spiritId == nil then
        if slotSpirits_[slotIndex] == nil then
            return false, "already_empty"
        end
        slotSpirits_[slotIndex] = nil
        slotCooldowns_[slotIndex] = PC.SWAP_COOLDOWN
        if onSlotChanged_ then onSlotChanged_() end
        return true
    end

    -- 检查冷却
    if slotCooldowns_[slotIndex] > 0 then
        return false, "cooling"
    end

    -- 检查顾问是否解锁
    if not PM.IsSpiritUnlocked(spiritId) then
        return false, "spirit_locked"
    end

    -- 检查顾问是否已在其他槽位
    local equipped, existingSlot = PM.IsSpiritEquipped(spiritId)
    if equipped then
        -- 如果在同一槽位，不做操作
        if existingSlot == slotIndex then
            return false, "same_slot"
        end
        -- 从原槽位移除
        slotSpirits_[existingSlot] = nil
        slotCooldowns_[existingSlot] = PC.SWAP_COOLDOWN
    end

    -- 如果目标槽位有其他顾问，先移除
    local oldSpirit = slotSpirits_[slotIndex]
    if oldSpirit then
        -- 旧顾问被换下
    end

    -- 装备
    slotSpirits_[slotIndex] = spiritId
    slotCooldowns_[slotIndex] = PC.SWAP_COOLDOWN

    if onSlotChanged_ then onSlotChanged_() end
    return true
end

--- 移除槽位中的顾问
---@param slotIndex number 1~3
---@return boolean
function PM.RemoveSpirit(slotIndex)
    return PM.EquipSpirit(slotIndex, nil)
end

-- ---------------------------------------------------------------------------
-- 效果计算（供 GameManager 调用）
-- ---------------------------------------------------------------------------

--- 获取所有当前生效的效果汇总
--- 返回 { cps = 0.xx, cpc = 0.xx, buildingCost = 0.xx, ... }
--- 值为乘数偏移量，如 0.15 表示 +15%，-0.10 表示 -10%
---@return table<string, number>
function PM.GetActiveEffects()
    local effects = {}
    local available = PM.GetAvailableSlots()

    for i = 1, math.min(available, PC.SLOT_COUNT) do
        local spiritId = slotSpirits_[i]
        if spiritId then
            local spirit = PC.FindSpirit(spiritId)
            if spirit then
                -- 主效果
                local val = PC.GetEffectValue(spirit, i)
                effects[spirit.effectType] = (effects[spirit.effectType] or 0) + val

                -- 副作用
                if spirit.sideEffect then
                    local seType, seVal = PC.GetSideEffectValue(spirit, i)
                    if seType then
                        effects[seType] = (effects[seType] or 0) + seVal
                    end
                end

                -- 额外效果
                if spirit.extraEffect then
                    local slot = PC.slots[i]
                    local extraVal = spirit.extraEffect.value * (slot and slot.effectMul or 1)
                    effects[spirit.extraEffect.type] = (effects[spirit.extraEffect.type] or 0) + extraVal
                end
            end
        end
    end

    return effects
end

--- 获取指定效果类型的总加成
---@param effectType string
---@return number 乘数偏移量
function PM.GetEffect(effectType)
    local effects = PM.GetActiveEffects()
    return effects[effectType] or 0
end

--- 获取 CPS 乘数（1 + 偏移量）
---@return number
function PM.GetCPSMultiplier()
    return 1 + PM.GetEffect("cps")
end

--- 获取 CPC 乘数（1 + 偏移量）
---@return number
function PM.GetCPCMultiplier()
    return 1 + PM.GetEffect("cpc")
end

--- 获取建筑费用乘数（1 + 偏移量）
---@return number
function PM.GetBuildingCostMultiplier()
    return 1 + PM.GetEffect("buildingCost")
end

--- 获取幸运金币持续时间乘数
---@return number
function PM.GetLuckyDurationMultiplier()
    return 1 + PM.GetEffect("luckyDuration")
end

--- 获取幸运金币出现频率乘数
---@return number
function PM.GetGoldenFreqMultiplier()
    return 1 + PM.GetEffect("goldenFreq")
end

--- 获取糖块速度乘数
---@return number
function PM.GetSugarSpeedMultiplier()
    return 1 + PM.GetEffect("sugarSpeed")
end

--- 获取皱巴虫收益乘数
---@return number
function PM.GetWrinklerMultiplier()
    return 1 + PM.GetEffect("wrinkler")
end

-- ---------------------------------------------------------------------------
-- 帧更新
-- ---------------------------------------------------------------------------

function PM.Update(dt)
    -- 冷却倒计时
    for i = 1, PC.SLOT_COUNT do
        if slotCooldowns_[i] > 0 then
            slotCooldowns_[i] = math.max(0, slotCooldowns_[i] - dt)
        end
    end
end

-- ---------------------------------------------------------------------------
-- 存档
-- ---------------------------------------------------------------------------

---@return table
function PM.GetSaveData()
    return {
        slots = { slotSpirits_[1], slotSpirits_[2], slotSpirits_[3] },
        cooldowns = { slotCooldowns_[1], slotCooldowns_[2], slotCooldowns_[3] },
    }
end

---@param data table|nil
function PM.LoadSaveData(data)
    if not data then
        PM.Init()
        return
    end

    slotSpirits_ = { nil, nil, nil }
    slotCooldowns_ = { 0, 0, 0 }

    if data.slots then
        for i = 1, PC.SLOT_COUNT do
            local sid = data.slots[i]
            -- 验证顾问 id 有效
            if sid and PC.FindSpirit(sid) then
                slotSpirits_[i] = sid
            end
        end
    end

    if data.cooldowns then
        for i = 1, PC.SLOT_COUNT do
            slotCooldowns_[i] = data.cooldowns[i] or 0
        end
    end

    print("[PantheonManager] 存档加载完成 (slots: "
        .. tostring(slotSpirits_[1]) .. ", "
        .. tostring(slotSpirits_[2]) .. ", "
        .. tostring(slotSpirits_[3]) .. ")")
end

--- 飞升重置（清空槽位和冷却）
function PM.ResetForAscension()
    slotSpirits_ = { nil, nil, nil }
    slotCooldowns_ = { 0, 0, 0 }
    print("[PantheonManager] 飞升重置")
end

return PM
