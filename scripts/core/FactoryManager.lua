-- ============================================================================
-- core/FactoryManager.lua
-- 制造工厂 —— 采集 + 合成 + 订单 + 内置等级系统（等级驱动概率/速度）
-- ============================================================================

local FC = require("config.FactoryConfig")
local Buildings = require("config.Buildings")
local GameState = require("core.GameState")

--- 向全局 buff 列表添加一个 CPS 倍率 buff
---@param buffDef table { id, name, mul, duration }
local function ApplyFactoryBuff(buffDef)
    for _, existing in ipairs(GameState.activeBuffs) do
        if existing.id == buffDef.id then
            existing.remaining = existing.remaining + buffDef.duration
            existing.duration = math.max(existing.duration, buffDef.duration)
            return
        end
    end
    GameState.activeBuffs[#GameState.activeBuffs + 1] = {
        id = buffDef.id,
        name = buffDef.name or buffDef.id,
        icon = "🏭",
        color = { 100, 160, 220, 255 },
        remaining = buffDef.duration,
        duration = buffDef.duration,
        multiplierKey = "cps",
        multiplierVal = buffDef.mul,
    }
end

local FM = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

-- 工厂内部等级
local factoryLevel_ = 0
local factoryXP_ = 0

-- 物品背包 { [itemId] = count }
local inventory_ = {}

-- 合成队列 { { recipeId, elapsed, totalTime }, ... }
local craftQueue_ = {}

-- 订单列表 { { orderId, ... }, ... }
local orders_ = {}
local orderRefreshTimer_ = 0    -- 自动补充计时

-- 采集限速（每秒最多 FC.GATHER_MAX_PER_SECOND 次）
local gatherCount_ = 0    -- 当前秒已采集次数
local gatherTimer_ = 0    -- 限速重置计时器

-- 统计
local streak_ = 0
local totalDelivered_ = 0
local totalGathered_ = 0

-- 回调
local onDeliver_ = nil
local onGather_ = nil
local onCraftComplete_ = nil
local onLevelUp_ = nil

-- ============================================================================
-- 工具函数
-- ============================================================================

---@return number
local function GetFactoryCount()
    for _, b in ipairs(Buildings.buildings) do
        if b.id == FC.BUILDING_ID then
            return b.count
        end
    end
    return 0
end

---@return number
local function GetBuildingCount()
    local total = 0
    for _, b in ipairs(Buildings.buildings) do
        total = total + (b.count or 0)
    end
    return total
end

--- 获取当前物品容量上限
---@return number
local function GetItemCap()
    return FC.GetItemCap(factoryLevel_, GetBuildingCount())
end

--- 获取某物品的当前数量
---@param itemId string
---@return number
local function GetItemCount(itemId)
    return inventory_[itemId] or 0
end

--- 尝试添加物品到背包
---@param itemId string
---@param amount number
---@return number actualAdded
local function AddItem(itemId, amount)
    local cap = GetItemCap()
    local current = inventory_[itemId] or 0
    local canAdd = math.max(0, cap - current)
    local actual = math.min(amount, canAdd)
    if actual > 0 then
        inventory_[itemId] = current + actual
    end
    return actual
end

--- 尝试消耗物品
---@param itemId string
---@param amount number
---@return boolean
local function ConsumeItem(itemId, amount)
    local current = inventory_[itemId] or 0
    if current < amount then return false end
    inventory_[itemId] = current - amount
    return true
end

--- 检查多个物品是否充足
---@param items table { [itemId] = count }
---@return boolean, table|nil missing
local function CheckItems(items)
    local missing = {}
    local ok = true
    for itemId, need in pairs(items) do
        local has = inventory_[itemId] or 0
        if has < need then
            missing[itemId] = need - has
            ok = false
        end
    end
    return ok, ok and nil or missing
end

--- 扣除多个物品
---@param items table { [itemId] = count }
---@return boolean
local function DeductItems(items)
    -- 先检查
    for itemId, need in pairs(items) do
        if (inventory_[itemId] or 0) < need then return false end
    end
    -- 再扣除
    for itemId, need in pairs(items) do
        inventory_[itemId] = (inventory_[itemId] or 0) - need
    end
    return true
end

--- 增加经验，处理升级
---@param xp number
local function AddXP(xp)
    if factoryLevel_ >= FC.MAX_FACTORY_LEVEL then return end
    factoryXP_ = factoryXP_ + xp
    local leveledUp = false
    while factoryLevel_ < FC.MAX_FACTORY_LEVEL do
        local needed = FC.GetXPForLevel(factoryLevel_)
        if factoryXP_ >= needed then
            factoryXP_ = factoryXP_ - needed
            factoryLevel_ = factoryLevel_ + 1
            leveledUp = true
        else
            break
        end
    end
    if factoryLevel_ >= FC.MAX_FACTORY_LEVEL then
        factoryXP_ = 0
    end
    if leveledUp and onLevelUp_ then
        onLevelUp_(factoryLevel_)
    end
end

--- 获取采集成功率（等级驱动）
---@return number 0~1
local function GetGatherSuccessRate()
    local rate = FC.GATHER_BASE_SUCCESS
        + factoryLevel_ * FC.GATHER_SUCCESS_PER_LEVEL
        + GetBuildingCount() * FC.GATHER_SUCCESS_PER_BUILDING
    return math.min(FC.GATHER_SUCCESS_CAP, rate)
end

--- 获取采集数量上限（等级每 GATHER_AMOUNT_BONUS_INTERVAL 级+1）
---@return number min, number max
local function GetGatherAmountRange()
    local bonus = math.floor(factoryLevel_ / FC.GATHER_AMOUNT_BONUS_INTERVAL)
    return FC.GATHER_AMOUNT_MIN, FC.GATHER_AMOUNT_MAX + bonus
end

--- 获取采集剩余可用次数
---@return number
local function GetGatherRemaining()
    return math.max(0, FC.GATHER_MAX_PER_SECOND - gatherCount_)
end

--- 获取合成速度倍率（等级驱动）
---@return number
local function GetCraftSpeedMul()
    return 1.0 + FC.CRAFT_SPEED_PER_LEVEL * factoryLevel_
end

--- 创建随机订单
---@return table
local function CreateRandomOrder()
    local def = FC.RandomOrder(factoryLevel_)
    local reward = math.max(GameState.coinsPerSecond, 1) * def.cpsSeconds
    return {
        orderId = def.id,
        reward = reward,
    }
end

--- 填充订单槽到上限
local function FillOrders()
    local maxSlots = FC.GetOrderSlots(factoryLevel_)
    while #orders_ < maxSlots do
        orders_[#orders_ + 1] = CreateRandomOrder()
    end
end

-- ============================================================================
-- 初始化
-- ============================================================================

function FM.Init()
    factoryLevel_ = 0
    factoryXP_ = 0
    inventory_ = {}
    craftQueue_ = {}
    orders_ = {}
    orderRefreshTimer_ = FC.ORDER_AUTO_FILL_INTERVAL
    gatherCount_ = 0
    gatherTimer_ = 0
    streak_ = 0
    totalDelivered_ = 0
    totalGathered_ = 0
    FillOrders()
end

-- ============================================================================
-- 回调设置
-- ============================================================================

function FM.SetOnDeliver(fn) onDeliver_ = fn end
function FM.SetOnGather(fn) onGather_ = fn end
function FM.SetOnCraftComplete(fn) onCraftComplete_ = fn end
function FM.SetOnLevelUp(fn) onLevelUp_ = fn end

-- ============================================================================
-- 查询接口
-- ============================================================================

function FM.IsUnlocked()
    return GetFactoryCount() >= 1
end

function FM.GetFactoryLevel() return factoryLevel_ end
function FM.GetFactoryXP() return factoryXP_ end
function FM.GetXPForNextLevel()
    if factoryLevel_ >= FC.MAX_FACTORY_LEVEL then return 0 end
    return FC.GetXPForLevel(factoryLevel_)
end

function FM.GetInventory() return inventory_ end
function FM.GetItemCount(itemId) return GetItemCount(itemId) end
function FM.GetItemCap() return GetItemCap() end

function FM.GetCraftQueue() return craftQueue_ end
function FM.GetOrders() return orders_ end
function FM.GetGatherRemaining() return GetGatherRemaining() end
function FM.GetOrderRefreshTimer() return orderRefreshTimer_ end
function FM.GetGatherSuccessRate() return GetGatherSuccessRate() end
function FM.GetCraftSpeedMul() return GetCraftSpeedMul() end

function FM.GetStreak() return streak_ end
function FM.GetTotalDelivered() return totalDelivered_ end
function FM.GetTotalGathered() return totalGathered_ end

function FM.GetMaxSlots()
    return FC.GetOrderSlots(factoryLevel_)
end

--- 获取当前等级可用的配方列表
---@return FactoryRecipeDef[]
function FM.GetAvailableRecipes()
    local result = {}
    for _, r in ipairs(FC.recipes) do
        if factoryLevel_ >= r.unlockLevel then
            result[#result + 1] = r
        end
    end
    return result
end

--- 检查订单的材料是否充足
---@param orderId string
---@return boolean, table|nil
function FM.CheckOrderItems(orderId)
    local def = FC.orderMap[orderId]
    if not def then return false, nil end
    return CheckItems(def.items)
end

--- 检查配方的材料是否充足
---@param recipeId string
---@return boolean, table|nil
function FM.CheckRecipeItems(recipeId)
    local recipe = FC.recipeMap[recipeId]
    if not recipe then return false, nil end
    return CheckItems(recipe.inputs)
end

-- ============================================================================
-- 采集操作
-- ============================================================================

--- 主动采集
---@return boolean success, string|nil itemId, number|nil amount
function FM.Gather()
    -- 限速：每秒最多 N 次
    if gatherCount_ >= FC.GATHER_MAX_PER_SECOND then return false, nil, nil end
    gatherCount_ = gatherCount_ + 1

    -- 概率判定
    local rate = GetGatherSuccessRate()
    local success = math.random() <= rate

    if not success then
        if onGather_ then onGather_(false, nil, 0) end
        return false, nil, 0
    end

    -- 成功：按权重选一个T1原料
    local itemId = FC.RollGatherItem()
    local gMin, gMax = GetGatherAmountRange()
    local amount = math.random(gMin, gMax)
    local actual = AddItem(itemId, amount)
    totalGathered_ = totalGathered_ + actual

    if onGather_ then onGather_(true, itemId, actual) end
    return true, itemId, actual
end

-- ============================================================================
-- 合成操作
-- ============================================================================

--- 将配方加入合成队列
---@param recipeId string
---@return boolean success, string|nil reason
function FM.StartCraft(recipeId)
    local recipe = FC.recipeMap[recipeId]
    if not recipe then return false, "配方不存在" end

    -- 等级检查
    if factoryLevel_ < recipe.unlockLevel then return false, "等级不足" end

    -- 队列上限
    if #craftQueue_ >= FC.MAX_CRAFT_QUEUE then return false, "队列已满" end

    -- 材料检查
    if not DeductItems(recipe.inputs) then return false, "材料不足" end

    -- 计算实际合成时间
    local speedMul = GetCraftSpeedMul()
    local actualTime = recipe.time / speedMul

    craftQueue_[#craftQueue_ + 1] = {
        recipeId = recipeId,
        elapsed = 0,
        totalTime = actualTime,
    }

    return true, nil
end

--- 取消合成（退回材料）
---@param queueIndex number
---@return boolean
function FM.CancelCraft(queueIndex)
    if queueIndex < 1 or queueIndex > #craftQueue_ then return false end
    local craft = craftQueue_[queueIndex]
    local recipe = FC.recipeMap[craft.recipeId]
    if recipe then
        -- 退回材料
        for itemId, count in pairs(recipe.inputs) do
            AddItem(itemId, count)
        end
    end
    table.remove(craftQueue_, queueIndex)
    return true
end

-- ============================================================================
-- 订单操作
-- ============================================================================

--- 完成订单（即时消耗物品获得金币+经验）
---@param orderIndex number
---@return boolean success
function FM.FulfillOrder(orderIndex)
    if orderIndex < 1 or orderIndex > #orders_ then return false end
    local order = orders_[orderIndex]
    local def = FC.orderMap[order.orderId]
    if not def then return false end

    -- 检查并扣除物品
    if not DeductItems(def.items) then return false end

    -- 锁定奖励（基于当前CPS重新计算）
    local reward = math.max(GameState.coinsPerSecond, 1) * def.cpsSeconds
    GameState.coins = GameState.coins + reward

    -- 经验
    AddXP(def.xp)

    -- 连续交付
    streak_ = streak_ + 1
    totalDelivered_ = totalDelivered_ + 1

    local streakBuff = nil
    for _, sr in ipairs(FC.STREAK_REWARDS) do
        if streak_ == sr.threshold then
            ApplyFactoryBuff(sr.buff)
            streakBuff = sr.buff
        end
    end

    -- 移除订单
    table.remove(orders_, orderIndex)

    if onDeliver_ then onDeliver_(order, reward, streakBuff, def) end
    return true
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

function FM.Update(dt)
    local factoryCount = GetFactoryCount()
    if factoryCount < 1 then return end

    -- ── 采集限速重置（每秒重置计数） ──
    gatherTimer_ = gatherTimer_ + dt
    if gatherTimer_ >= 1.0 then
        gatherTimer_ = gatherTimer_ - 1.0
        gatherCount_ = 0
    end

    -- ── 合成队列推进（只合成队首）──
    if #craftQueue_ > 0 then
        local craft = craftQueue_[1]
        craft.elapsed = craft.elapsed + dt

        if craft.elapsed >= craft.totalTime then
            -- 合成完成
            local recipe = FC.recipeMap[craft.recipeId]
            if recipe then
                local actual = AddItem(recipe.output, recipe.outputCount)
                AddXP(recipe.xp)
                if onCraftComplete_ then
                    onCraftComplete_(recipe, actual)
                end
            end
            table.remove(craftQueue_, 1)
        end
    end

    -- ── 订单自动补充 ──
    orderRefreshTimer_ = orderRefreshTimer_ - dt
    if orderRefreshTimer_ <= 0 then
        orderRefreshTimer_ = FC.ORDER_AUTO_FILL_INTERVAL
        -- 补充空槽
        FillOrders()
    end
end

-- ============================================================================
-- 存档 / 读档
-- ============================================================================

function FM.GetSaveData()
    local queueData = {}
    for i, c in ipairs(craftQueue_) do
        queueData[i] = { rid = c.recipeId, el = c.elapsed, tt = c.totalTime }
    end

    local ordersData = {}
    for i, o in ipairs(orders_) do
        ordersData[i] = { oid = o.orderId, rw = o.reward }
    end

    return {
        level = factoryLevel_,
        xp = factoryXP_,
        inventory = inventory_,
        craftQueue = queueData,
        orders = ordersData,
        orderRefreshTimer = orderRefreshTimer_,
        streak = streak_,
        totalDelivered = totalDelivered_,
        totalGathered = totalGathered_,
    }
end

function FM.LoadSaveData(data)
    if not data then return end

    factoryLevel_ = data.level or 0
    factoryXP_ = data.xp or 0
    inventory_ = data.inventory or {}
    streak_ = data.streak or 0
    totalDelivered_ = data.totalDelivered or 0
    totalGathered_ = data.totalGathered or 0

    orderRefreshTimer_ = data.orderRefreshTimer or FC.ORDER_AUTO_FILL_INTERVAL

    -- 合成队列
    craftQueue_ = {}
    if data.craftQueue then
        for _, cd in ipairs(data.craftQueue) do
            craftQueue_[#craftQueue_ + 1] = {
                recipeId = cd.rid or "",
                elapsed = cd.el or 0,
                totalTime = cd.tt or 10,
            }
        end
    end

    -- 订单
    orders_ = {}
    if data.orders then
        for _, od in ipairs(data.orders) do
            orders_[#orders_ + 1] = {
                orderId = od.oid or "",
                reward = od.rw or 0,
            }
        end
    end

    FillOrders()
end

function FM.ResetForAscension()
    FM.Init()
end

return FM
