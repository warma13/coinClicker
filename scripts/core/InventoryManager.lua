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
local MAX_SLOTS     = 40   -- 固定格子数
local DEFAULT_STACK = 99   -- 默认最大堆叠

-- ============================================================================
-- 内部状态
-- ============================================================================

--- slots_[i] = { itemId = string, count = number } 或 nil（空格）
local slots_ = {}

--- 回调
local onItemUsed_  = nil   -- function(slotIndex, itemDef, effectResult)
local onItemAdded_ = nil   -- function(itemId, count)
local suppressNotify_ = false  -- 开箱期间抑制逐条通知


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
        function(data) IM.Deserialize(data) end,
        function()
            for i = 1, MAX_SLOTS do
                slots_[i] = nil
            end
        end
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
                    if onItemAdded_ and not suppressNotify_ then onItemAdded_(def, origCount) end
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
                if onItemAdded_ and not suppressNotify_ then onItemAdded_(def, origCount) end
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

    elseif effect.type == "random_collectible" then
        -- 随机藏品箱 O(1)：按稀有度累积权重抽取
        local picked = IM.RollCollectible()
        if picked then
            suppressNotify_ = true
            local ok = IM.AddItem(picked, 1)
            suppressNotify_ = false
            if ok then
                local d = ItemDefs.ITEM_MAP[picked]
                local rn = ItemDefs.RARITY[d.rarity]
                effectDesc = "开出 " .. (rn and rn.name or "") .. "·" .. d.name
            else
                effectDesc = "仓库已满"
                return false, effectDesc
            end
        else
            effectDesc = "没有可用的收藏品"
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
-- O(1) 收藏品抽取（按稀有度分桶，累积权重）
-- ============================================================================

-- 预构建稀有度分桶（模块加载时执行一次）
local RARITY_WEIGHTS = { [1] = 50, [2] = 30, [3] = 15, [4] = 4, [5] = 1 }
local rarityBuckets_ = {}   -- { [rarity] = { id1, id2, ... } }
local cumWeights_    = {}   -- { { rarity, cumW }, ... }  排序后的累积权重
local totalWeight_   = 0

local function BuildRarityBuckets()
    rarityBuckets_ = {}
    cumWeights_ = {}
    totalWeight_ = 0
    for _, cid in ipairs(ItemDefs.COLLECTIBLE_IDS) do
        local def = ItemDefs.ITEM_MAP[cid]
        if def then
            local r = def.rarity
            if not rarityBuckets_[r] then rarityBuckets_[r] = {} end
            rarityBuckets_[r][#rarityBuckets_[r] + 1] = cid
        end
    end
    -- 构建累积权重表（最多 5 项）
    for r = 1, 5 do
        if rarityBuckets_[r] and #rarityBuckets_[r] > 0 then
            totalWeight_ = totalWeight_ + RARITY_WEIGHTS[r] * #rarityBuckets_[r]
            cumWeights_[#cumWeights_ + 1] = { rarity = r, cumW = totalWeight_ }
        end
    end
end
BuildRarityBuckets()

--- O(1) 抽取一件随机收藏品
---@return string|nil itemId
function IM.RollCollectible()
    if totalWeight_ <= 0 then return nil end
    local roll = math.random(1, totalWeight_)
    for _, entry in ipairs(cumWeights_) do
        if roll <= entry.cumW then
            local bucket = rarityBuckets_[entry.rarity]
            return bucket[math.random(1, #bucket)]
        end
    end
    return nil
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

    elseif effect.type == "random_collectible" then
        -- 藏品箱批量 O(1)：多项式分配 + 桶内随机
        if totalWeight_ <= 0 then
            return false, "没有可用的收藏品"
        end

        -- 1) 按权重比例将 useCount 分配到各稀有度桶（O(K), K≤5）
        local rarityAlloc = {}   -- { [rarity] = count }
        local remaining = useCount
        for idx, entry in ipairs(cumWeights_) do
            local prevCum = (idx > 1) and cumWeights_[idx - 1].cumW or 0
            local bucketW = entry.cumW - prevCum
            if idx == #cumWeights_ then
                -- 最后一个桶取余数，避免浮点舍入丢失
                rarityAlloc[entry.rarity] = remaining
            else
                local n = math.floor(useCount * bucketW / totalWeight_ + 0.5)
                n = math.min(n, remaining)
                rarityAlloc[entry.rarity] = n
                remaining = remaining - n
            end
        end

        -- 2) 在每个桶内均匀分配具体物品（O(K×B), K≤5, B=桶内种类数，均为常数）
        local counts = {}  -- { [itemId] = n }
        local opened = 0
        for r, n in pairs(rarityAlloc) do
            if n > 0 then
                local bucket = rarityBuckets_[r]
                local bLen = #bucket
                -- 每种物品至少分 base 个，随机选 extra 种各多分 1 个
                local base = math.floor(n / bLen)
                local extra = n % bLen  -- extra < bLen，需从桶中选 extra 种 +1
                -- 先给所有物品 base 个
                for bi = 1, bLen do
                    if base > 0 then
                        counts[bucket[bi]] = (counts[bucket[bi]] or 0) + base
                    end
                end
                -- Fisher-Yates 部分洗牌选 extra 个索引（O(extra), extra < bLen 常数级）
                if extra > 0 then
                    local perm = {}
                    for bi = 1, bLen do perm[bi] = bi end
                    for ei = 1, extra do
                        local j = math.random(ei, bLen)
                        perm[ei], perm[j] = perm[j], perm[ei]
                        local id = bucket[perm[ei]]
                        counts[id] = (counts[id] or 0) + 1
                    end
                end
                opened = opened + n
            end
        end

        -- 3) 批量添加道具（O(M), M=不同物品种类数）
        suppressNotify_ = true
        local added = 0
        for id, n in pairs(counts) do
            local ok = IM.AddItem(id, n)
            if ok then
                added = added + n
            else
                -- 仓库满，尝试逐个添加尽可能多的
                for _ = 1, n do
                    if IM.AddItem(id, 1) then
                        added = added + 1
                    else
                        break
                    end
                end
            end
        end
        suppressNotify_ = false

        if added > 0 then
            local parts = {}
            for id, n in pairs(counts) do
                local d = ItemDefs.ITEM_MAP[id]
                parts[#parts + 1] = d.name .. (n > 1 and ("x" .. n) or "")
            end
            effectDesc = "开出 " .. added .. " 件: " .. table.concat(parts, " ")
        else
            return false, "仓库已满"
        end
        IM.RemoveItem(slotIndex, added)
        if onItemUsed_ then
            onItemUsed_(slotIndex, def, effectDesc)
        end
        return true, effectDesc
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

    -- 统计每件收藏品的被动（数量越多效果越强）
    for _, cid in ipairs(ItemDefs.COLLECTIBLE_IDS) do
        local cnt = IM.GetItemCount(cid)
        if cnt > 0 then
            result.ownedCount = result.ownedCount + 1
            result.ownedIds[cid] = true
            local def = ItemDefs.ITEM_MAP[cid]
            if def and def.passive then
                local p = def.passive
                local val = p.value * cnt  -- 按持有数量叠加
                if p.type == "cps_percent" then
                    result.cps_percent = result.cps_percent + val
                elseif p.type == "cpc_percent" then
                    result.cpc_percent = result.cpc_percent + val
                elseif p.type == "lucky_freq" then
                    result.lucky_freq = result.lucky_freq + val
                elseif p.type == "lucky_dur" then
                    result.lucky_dur = result.lucky_dur + val
                elseif p.type == "global_percent" then
                    result.global_percent = result.global_percent + val
                end
            end
        end
    end

    -- 套装奖励（取已达成的最高阶段，不叠加；与个体 global_percent 累加）
    for i = #ItemDefs.SET_BONUSES, 1, -1 do
        local sb = ItemDefs.SET_BONUSES[i]
        if result.ownedCount >= sb.need then
            local b = sb.bonus
            if b.type == "global_percent" then
                result.global_percent = result.global_percent + b.value
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
    -- 飞升后保留仓库所有道具，不做清除
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
