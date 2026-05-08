-- ============================================================================
-- core/InventoryManager.lua
-- 仓库管理器 —— 道具存储、使用、丢弃、持久化
-- ============================================================================

local SaveBridge = require("core.SaveBridge")
local ItemDefs   = require("config.ItemDefs")
local GameState  = require("core.GameState")

local IM = {}

-- ============================================================================
-- 常量
-- ============================================================================
local MAX_SLOTS     = 20   -- 固定格子数
local DEFAULT_STACK = 99   -- 默认最大堆叠

-- ============================================================================
-- 内部状态
-- ============================================================================

--- slots_[i] = { itemId = string, count = number } 或 nil（空格）
local slots_ = {}

--- 回调
local onItemUsed_  = nil   -- function(slotIndex, itemDef, effectResult)
local onItemAdded_ = nil   -- function(itemId, count)


-- ============================================================================
-- 初始化
-- ============================================================================

function IM.Init()
    -- 初始化空格子
    for i = 1, MAX_SLOTS do
        if not slots_[i] then
            slots_[i] = nil
        end
    end

    -- 注册存档
    SaveBridge.Register("inventory",
        function() return IM.Serialize() end,
        function(data) IM.Deserialize(data) end
    )
end

-- ============================================================================
-- 核心 API
-- ============================================================================

--- 添加道具到仓库
---@param itemId string  道具 ID
---@param count number|nil  数量（默认 1）
---@return boolean success
---@return string|nil reason  失败原因
function IM.AddItem(itemId, count)
    count = count or 1
    local def = ItemDefs.ITEM_MAP[itemId]
    if not def then
        return false, "unknown_item"
    end

    local origCount = count
    local maxStack = def.maxStack or DEFAULT_STACK

    -- 第一遍：尝试堆叠到已有格子
    for i = 1, MAX_SLOTS do
        if slots_[i] and slots_[i].itemId == itemId then
            local space = maxStack - slots_[i].count
            if space > 0 then
                local add = math.min(count, space)
                slots_[i].count = slots_[i].count + add
                count = count - add
                if count <= 0 then
                    if onItemAdded_ then onItemAdded_(def, origCount) end
                    return true
                end
            end
        end
    end

    -- 第二遍：找空格子放剩余
    for i = 1, MAX_SLOTS do
        if not slots_[i] then
            local add = math.min(count, maxStack)
            slots_[i] = { itemId = itemId, count = add }
            count = count - add
            if count <= 0 then
                if onItemAdded_ then onItemAdded_(def, origCount) end
                return true
            end
        end
    end

    -- 还有剩余 → 仓库已满（部分可能已添加）
    if count > 0 then
        return false, "inventory_full"
    end

    return true
end

--- 移除指定格子中的道具
---@param slotIndex number
---@param count number|nil  移除数量（默认 1）
---@return boolean success
function IM.RemoveItem(slotIndex, count)
    count = count or 1
    local slot = slots_[slotIndex]
    if not slot then return false end

    if slot.count <= count then
        slots_[slotIndex] = nil
    else
        slot.count = slot.count - count
    end
    return true
end

--- 使用指定格子中的道具
---@param slotIndex number
---@return boolean success
---@return string|nil effectDesc  效果描述
function IM.UseItem(slotIndex)
    local slot = slots_[slotIndex]
    if not slot then return false, "empty_slot" end

    local def = ItemDefs.ITEM_MAP[slot.itemId]
    if not def then return false, "unknown_item" end
    if not def.useEffect then return false, "not_usable" end

    local effect = def.useEffect
    local effectDesc = ""

    if effect.type == "buff" then
        -- 添加 Buff
        local S = GameState
        -- 检查是否已有相同 buff，如果有则刷新持续时间
        local found = false
        for _, b in ipairs(S.activeBuffs) do
            if b.id == effect.buffId then
                b.remaining = effect.duration
                found = true
                break
            end
        end
        if not found then
            S.activeBuffs[#S.activeBuffs + 1] = {
                id            = effect.buffId,
                name          = effect.buffName,
                icon          = effect.buffIcon,
                color         = effect.color,
                remaining     = effect.duration,
                duration      = effect.duration,
                multiplierKey = effect.key,
                multiplierVal = effect.value,
            }
        end
        local durText = effect.duration >= 60
            and (math.floor(effect.duration / 60) .. " 分钟")
            or (effect.duration .. " 秒")
        effectDesc = "效果持续 " .. durText

    elseif effect.type == "instant_cps" then
        -- 立即获得 N 秒产出
        local cps = GameState.coinsPerSecond or 0
        local mul = GameState.buffCpsMul or 1
        local gain = cps * mul * effect.seconds
        if gain > 0 then
            GameState.coins = GameState.coins + gain
            effectDesc = "获得 " .. GameState.FormatNumber(gain) .. " 金币"
        else
            effectDesc = "当前无产出"
        end

    elseif effect.type == "reset_cooldowns" then
        -- 重置技能冷却
        local SkillManager = require("core.SkillManager")
        if SkillManager.ResetAllCooldowns then
            SkillManager.ResetAllCooldowns()
        end
        effectDesc = "所有技能冷却已重置"

    elseif effect.type == "unlock_upgrade" then
        -- 随机解锁升级（简化实现：给予等价金币）
        local cps = GameState.coinsPerSecond or 0
        local mul = GameState.buffCpsMul or 1
        local gain = cps * mul * 300
        if gain > 0 then
            GameState.coins = GameState.coins + gain
            effectDesc = "获得 " .. GameState.FormatNumber(gain) .. " 金币"
        else
            effectDesc = "当前无产出"
        end
    end

    -- 消耗道具
    IM.RemoveItem(slotIndex, 1)

    -- 回调
    if onItemUsed_ then
        onItemUsed_(slotIndex, def, effectDesc)
    end

    return true, effectDesc
end

-- ============================================================================
-- 查询 API
-- ============================================================================

--- 获取所有格子
---@return table slots  slots_[i] = { itemId, count } 或 nil
function IM.GetSlots()
    return slots_
end

--- 获取格子总数
---@return number
function IM.GetSlotCount()
    return MAX_SLOTS
end

--- 获取已使用格子数
---@return number
function IM.GetUsedSlotCount()
    local n = 0
    for i = 1, MAX_SLOTS do
        if slots_[i] then n = n + 1 end
    end
    return n
end

--- 检查是否拥有某道具
---@param itemId string
---@return boolean has
---@return number totalCount
function IM.HasItem(itemId)
    local total = 0
    for i = 1, MAX_SLOTS do
        if slots_[i] and slots_[i].itemId == itemId then
            total = total + slots_[i].count
        end
    end
    return total > 0, total
end

--- 获取某道具总数量
---@param itemId string
---@return number
function IM.GetItemCount(itemId)
    local total = 0
    for i = 1, MAX_SLOTS do
        if slots_[i] and slots_[i].itemId == itemId then
            total = total + slots_[i].count
        end
    end
    return total
end

-- ============================================================================
-- 自动整理
-- ============================================================================

--- 分类排序优先级
local CATEGORY_ORDER = { boost = 1, skip = 2, tool = 3, collectible = 4 }

--- 自动整理仓库：合并同类堆叠 → 按分类/稀有度排序 → 压缩到前排
function IM.SortItems()
    -- 1) 收集所有道具，合并同 ID 的数量
    local merged = {} -- { [itemId] = totalCount }
    local order  = {} -- 保持首次出现顺序
    for i = 1, MAX_SLOTS do
        local s = slots_[i]
        if s then
            if not merged[s.itemId] then
                merged[s.itemId] = 0
                order[#order + 1] = s.itemId
            end
            merged[s.itemId] = merged[s.itemId] + s.count
        end
    end

    -- 2) 按分类优先级 → 稀有度降序 → ID 字母序排列
    table.sort(order, function(a, b)
        local da = ItemDefs.ITEM_MAP[a]
        local db = ItemDefs.ITEM_MAP[b]
        local ca = CATEGORY_ORDER[da.category] or 99
        local cb = CATEGORY_ORDER[db.category] or 99
        if ca ~= cb then return ca < cb end
        if da.rarity ~= db.rarity then return da.rarity > db.rarity end
        return a < b
    end)

    -- 3) 清空所有格子
    for i = 1, MAX_SLOTS do
        slots_[i] = nil
    end

    -- 4) 按排序顺序重新填入，自动拆分超出堆叠上限的
    local idx = 1
    for _, itemId in ipairs(order) do
        local total = merged[itemId]
        local def = ItemDefs.ITEM_MAP[itemId]
        local maxStack = def.maxStack or DEFAULT_STACK
        while total > 0 and idx <= MAX_SLOTS do
            local put = math.min(total, maxStack)
            slots_[idx] = { itemId = itemId, count = put }
            total = total - put
            idx = idx + 1
        end
    end
end

-- ============================================================================
-- 批量使用
-- ============================================================================

--- 批量使用指定格子的道具
---@param slotIndex number  格子索引
---@param useCount number   使用数量
---@return boolean success
---@return string|nil effectDesc  效果描述
function IM.UseItemMulti(slotIndex, useCount)
    local slot = slots_[slotIndex]
    if not slot then return false, "empty_slot" end

    local def = ItemDefs.ITEM_MAP[slot.itemId]
    if not def then return false, "unknown_item" end
    if not def.useEffect then return false, "not_usable" end

    -- 限制使用数量不超过持有量
    useCount = math.min(useCount, slot.count)
    if useCount <= 0 then return false, "no_items" end

    local effect = def.useEffect
    local effectDesc = ""

    if effect.type == "buff" then
        -- buff 类：只刷新/添加一次，不叠加时长，但消耗 useCount 个
        local S = GameState
        local found = false
        for _, b in ipairs(S.activeBuffs) do
            if b.id == effect.buffId then
                b.remaining = effect.duration
                found = true
                break
            end
        end
        if not found then
            S.activeBuffs[#S.activeBuffs + 1] = {
                id            = effect.buffId,
                name          = effect.buffName,
                icon          = effect.buffIcon,
                color         = effect.color,
                remaining     = effect.duration,
                duration      = effect.duration,
                multiplierKey = effect.key,
                multiplierVal = effect.value,
            }
        end
        local durText = effect.duration >= 60
            and (math.floor(effect.duration / 60) .. " 分钟")
            or (effect.duration .. " 秒")
        effectDesc = "使用 " .. useCount .. " 个，效果持续 " .. durText

    elseif effect.type == "instant_cps" then
        -- 立即获得 N 秒产出 × useCount
        local cps = GameState.coinsPerSecond or 0
        local mul = GameState.buffCpsMul or 1
        local gain = cps * mul * effect.seconds * useCount
        if gain > 0 then
            GameState.coins = GameState.coins + gain
            effectDesc = "使用 " .. useCount .. " 个，获得 " .. GameState.FormatNumber(gain) .. " 金币"
        else
            effectDesc = "当前无产出"
        end

    elseif effect.type == "reset_cooldowns" then
        local SkillManager = require("core.SkillManager")
        if SkillManager.ResetAllCooldowns then
            SkillManager.ResetAllCooldowns()
        end
        effectDesc = "使用 " .. useCount .. " 个，所有技能冷却已重置"

    elseif effect.type == "unlock_upgrade" then
        local cps = GameState.coinsPerSecond or 0
        local mul = GameState.buffCpsMul or 1
        local gain = cps * mul * 300 * useCount
        if gain > 0 then
            GameState.coins = GameState.coins + gain
            effectDesc = "使用 " .. useCount .. " 个，获得 " .. GameState.FormatNumber(gain) .. " 金币"
        else
            effectDesc = "当前无产出"
        end
    end

    -- 消耗道具
    IM.RemoveItem(slotIndex, useCount)

    -- 回调
    if onItemUsed_ then
        onItemUsed_(slotIndex, def, effectDesc)
    end

    return true, effectDesc
end

-- ============================================================================
-- 收藏品被动加成
-- ============================================================================

--- 计算当前持有收藏品的被动加成汇总
---@return table bonuses { cps_percent, cpc_percent, lucky_freq, lucky_dur, global_percent, ownedCount, totalCount }
function IM.GetCollectibleBonuses()
    local result = {
        cps_percent    = 0,
        cpc_percent    = 0,
        lucky_freq     = 0,
        lucky_dur      = 0,
        global_percent = 0,
        ownedCount     = 0,
        totalCount     = ItemDefs.GetCollectibleTotal(),
        ownedIds       = {},  -- 已拥有的收藏品 ID 集合
    }

    -- 统计每件收藏品的被动
    for _, cid in ipairs(ItemDefs.COLLECTIBLE_IDS) do
        if IM.HasItem(cid) then
            result.ownedCount = result.ownedCount + 1
            result.ownedIds[cid] = true
            local def = ItemDefs.ITEM_MAP[cid]
            if def and def.passive then
                local p = def.passive
                if p.type == "cps_percent" then
                    result.cps_percent = result.cps_percent + p.value
                elseif p.type == "cpc_percent" then
                    result.cpc_percent = result.cpc_percent + p.value
                elseif p.type == "lucky_freq" then
                    result.lucky_freq = result.lucky_freq + p.value
                elseif p.type == "lucky_dur" then
                    result.lucky_dur = result.lucky_dur + p.value
                end
            end
        end
    end

    -- 套装奖励（取已达成的最高阶段，不叠加）
    for i = #ItemDefs.SET_BONUSES, 1, -1 do
        local sb = ItemDefs.SET_BONUSES[i]
        if result.ownedCount >= sb.need then
            local b = sb.bonus
            if b.type == "global_percent" then
                result.global_percent = b.value
            end
            break
        end
    end

    return result
end

-- ============================================================================
-- 飞升重置
-- ============================================================================

--- 飞升时重置仓库（保留收藏类道具）
function IM.ResetForAscension()
    for i = 1, MAX_SLOTS do
        if slots_[i] then
            local def = ItemDefs.ITEM_MAP[slots_[i].itemId]
            if not def or def.category ~= "collectible" then
                slots_[i] = nil
            end
        end
    end
end

-- ============================================================================
-- 回调设置
-- ============================================================================

---@param fn function(slotIndex, itemDef, effectDesc)
function IM.SetOnItemUsed(fn)
    onItemUsed_ = fn
end

---@param fn function(itemId, count)
function IM.SetOnItemAdded(fn)
    onItemAdded_ = fn
end

-- ============================================================================
-- 序列化 / 反序列化（稀疏编码）
-- ============================================================================

function IM.Serialize()
    local data = {}
    for i = 1, MAX_SLOTS do
        if slots_[i] then
            data[tostring(i)] = { id = slots_[i].itemId, n = slots_[i].count }
        end
    end
    return data
end

function IM.Deserialize(data)
    -- 清空
    for i = 1, MAX_SLOTS do
        slots_[i] = nil
    end
    if not data then return end

    for k, v in pairs(data) do
        if k ~= "_sg" then
            local idx = tonumber(k)
            if idx and idx >= 1 and idx <= MAX_SLOTS and v.id then
                -- 验证道具 ID 是否仍然有效
                if ItemDefs.ITEM_MAP[v.id] then
                    slots_[idx] = { itemId = v.id, count = v.n or 1 }
                end
            end
        end
    end
end

return IM
