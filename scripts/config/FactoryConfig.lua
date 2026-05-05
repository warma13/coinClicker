-- ============================================================================
-- config/FactoryConfig.lua
-- 制造工厂 —— 采集 + 合成 + 订单 + 内置等级系统（等级驱动概率/速度）
-- ============================================================================

local FC = {}

-- ============================================================================
-- 建筑 ID（解锁条件）
-- ============================================================================
FC.BUILDING_ID = "factory"

-- ============================================================================
-- 物品定义（5 阶 14 种）
-- ============================================================================

---@class FactoryItemDef
---@field id string
---@field name string
---@field icon string
---@field tier number       1=原料 2=加工品 3=组件 4=产品 5=精品
---@field unlockLevel number 工厂内部等级需求
---@field stackMax number    单格上限（0=无特殊限制，用全局cap）

FC.items = {
    -- T1 原料（采集获得）
    { id = "wood",   name = "木材", icon = "image/factory_wood_20260505002326.png", tier = 1, unlockLevel = 0 },
    { id = "stone",  name = "石料", icon = "image/factory_stone_20260505002310.png", tier = 1, unlockLevel = 0 },
    { id = "iron",   name = "铁矿", icon = "image/factory_iron_20260505002301.png",  tier = 1, unlockLevel = 0 },
    { id = "copper", name = "铜矿", icon = "image/factory_copper_20260505002748.png", tier = 1, unlockLevel = 0 },
    -- T2 加工品
    { id = "plank",      name = "木板",   icon = "image/factory_plank_20260505002257.png", tier = 2, unlockLevel = 1 },
    { id = "brick",      name = "砖块",   icon = "image/factory_brick_20260505002301.png", tier = 2, unlockLevel = 1 },
    { id = "iron_ingot", name = "铁锭",   icon = "image/factory_iron_ingot_20260505002328.png", tier = 2, unlockLevel = 2 },
    { id = "copper_ingot", name = "铜锭", icon = "image/factory_copper_ingot_20260505002304.png", tier = 2, unlockLevel = 2 },
    -- T3 组件
    { id = "gear",    name = "齿轮", icon = "image/factory_gear_20260505002256.png",  tier = 3, unlockLevel = 5 },
    { id = "circuit", name = "电路", icon = "image/factory_circuit_20260505002250.png", tier = 3, unlockLevel = 6 },
    { id = "alloy",   name = "合金", icon = "image/factory_alloy_20260505004621.png", tier = 3, unlockLevel = 7 },
    -- T4 产品
    { id = "machine",    name = "机器",   icon = "image/factory_machine_20260505004459.png", tier = 4, unlockLevel = 10 },
    { id = "instrument", name = "仪器",   icon = "image/factory_instrument_20260505004530.png", tier = 4, unlockLevel = 12 },
    -- T5 精品
    { id = "precision",  name = "精密装置", icon = "image/factory_precision_20260505004554.png", tier = 5, unlockLevel = 16 },
}

-- 快查
FC.itemMap = {}
FC.itemIndex = {}
for i, item in ipairs(FC.items) do
    FC.itemMap[item.id] = item
    FC.itemIndex[item.id] = i
end

--- 获取某阶的所有物品
---@param tier number
---@return FactoryItemDef[]
function FC.GetItemsByTier(tier)
    local result = {}
    for _, item in ipairs(FC.items) do
        if item.tier == tier then
            result[#result + 1] = item
        end
    end
    return result
end

-- ============================================================================
-- 采集系统
-- ============================================================================

--- 采集T1原料权重
FC.GATHER_WEIGHTS = {
    wood   = 35,
    stone  = 28,
    iron   = 22,
    copper = 15,
}
FC.GATHER_TOTAL_WEIGHT = 100

--- 基础成功率（Lv.0 = 42%）
FC.GATHER_BASE_SUCCESS = 0.42
--- 每工厂等级加成采集成功率（Lv.20 → +20%×0.012 = +24% → 66%）
FC.GATHER_SUCCESS_PER_LEVEL = 0.012
--- 每建筑数量加成（微弱）
FC.GATHER_SUCCESS_PER_BUILDING = 0.001
--- 成功率上限
FC.GATHER_SUCCESS_CAP = 0.85

--- 采集限速（每秒最多次数，人类手速约 3~5 次/秒）
FC.GATHER_MAX_PER_SECOND = 5

--- 每次采集获得的原料数量（基础固定 1 个）
FC.GATHER_AMOUNT_MIN = 1
FC.GATHER_AMOUNT_MAX = 1
--- 每8级额外+1最大采集量（Lv.8→1~2, Lv.16→1~3, Lv.24→1~4）
FC.GATHER_AMOUNT_BONUS_INTERVAL = 8

--- 随机采集一个T1原料
---@return string itemId
function FC.RollGatherItem()
    local r = math.random() * FC.GATHER_TOTAL_WEIGHT
    local acc = 0
    for id, w in pairs(FC.GATHER_WEIGHTS) do
        acc = acc + w
        if r <= acc then return id end
    end
    return "wood"
end

-- ============================================================================
-- 合成配方
-- ============================================================================

---@class FactoryRecipeDef
---@field id string           配方ID = 产出物品ID
---@field output string       产出物品ID
---@field outputCount number  产出数量
---@field inputs table        { [itemId] = count }
---@field time number         基础合成时间（秒）
---@field unlockLevel number  需要的工厂等级
---@field xp number           合成完成给予的经验

FC.recipes = {
    -- T2 加工品（从T1原料合成）—— 需 6 原料，耗时 18~20s
    { id = "plank",        output = "plank",        outputCount = 1, inputs = { wood = 6 },   time = 18,  unlockLevel = 1, xp = 5 },
    { id = "brick",        output = "brick",        outputCount = 1, inputs = { stone = 6 },  time = 18,  unlockLevel = 1, xp = 5 },
    { id = "iron_ingot",   output = "iron_ingot",   outputCount = 1, inputs = { iron = 6 },   time = 20,  unlockLevel = 2, xp = 8 },
    { id = "copper_ingot", output = "copper_ingot", outputCount = 1, inputs = { copper = 6 }, time = 20,  unlockLevel = 2, xp = 8 },
    -- T3 组件（从T2合成）—— 耗时 50~60s
    { id = "gear",    output = "gear",    outputCount = 1, inputs = { iron_ingot = 3, copper_ingot = 2 }, time = 50, unlockLevel = 5,  xp = 20 },
    { id = "circuit", output = "circuit", outputCount = 1, inputs = { copper_ingot = 3, plank = 2 },     time = 50, unlockLevel = 6,  xp = 20 },
    { id = "alloy",   output = "alloy",   outputCount = 1, inputs = { iron_ingot = 2, copper_ingot = 2, brick = 1 }, time = 55, unlockLevel = 7, xp = 25 },
    -- T4 产品（从T3合成）—— 耗时 100~110s
    { id = "machine",    output = "machine",    outputCount = 1, inputs = { gear = 2, alloy = 2 },    time = 100, unlockLevel = 10, xp = 55 },
    { id = "instrument", output = "instrument", outputCount = 1, inputs = { circuit = 2, gear = 2 },  time = 100, unlockLevel = 12, xp = 55 },
    -- T5 精品（从T4合成）—— 耗时 180s
    { id = "precision", output = "precision", outputCount = 1, inputs = { machine = 1, instrument = 1, alloy = 3 }, time = 180, unlockLevel = 16, xp = 120 },
}

--- 合成速度加成：每等级降低合成时间（Lv.20 → 1 + 0.03*20 = 1.6倍速）
FC.CRAFT_SPEED_PER_LEVEL = 0.03

FC.recipeMap = {}
for _, r in ipairs(FC.recipes) do
    FC.recipeMap[r.id] = r
end

-- ============================================================================
-- 订单系统（消耗物品获得金币+经验）
-- ============================================================================

---@class FactoryOrderDef
---@field id string
---@field name string
---@field icon string
---@field items table         { [itemId] = count }
---@field cpsSeconds number   奖励 = CPS × 秒
---@field xp number           完成获得经验
---@field weight number       出现权重
---@field unlockLevel number  需要的工厂等级
---@field tier number         订单阶级

FC.orders = {
    -- T1 订单（消耗T1原料）—— 奖励≈3s CPS，需要较多原料
    { id = "ord_wood_bundle",   name = "木材捆",     icon = "image/factory_wood_20260505002326.png", tier = 1, items = { wood = 8 },               cpsSeconds = 3,   xp = 10,  weight = 25, unlockLevel = 0 },
    { id = "ord_stone_pile",    name = "石料堆",     icon = "image/factory_stone_20260505002310.png", tier = 1, items = { stone = 8 },              cpsSeconds = 3,   xp = 10,  weight = 25, unlockLevel = 0 },
    { id = "ord_ore_mix",       name = "混合矿石",   icon = "image/factory_iron_20260505002301.png",  tier = 1, items = { iron = 5, copper = 5 },   cpsSeconds = 4,   xp = 12,  weight = 20, unlockLevel = 0 },
    -- T2 订单（消耗T2加工品）—— 奖励≈10~12s CPS
    { id = "ord_furniture",     name = "家具",       icon = "image/factory_furniture_20260505004724.png", tier = 2, items = { plank = 3, brick = 2 },   cpsSeconds = 10,  xp = 25,  weight = 18, unlockLevel = 2 },
    { id = "ord_tools",         name = "工具套装",   icon = "image/factory_tools_20260505004751.png", tier = 2, items = { iron_ingot = 2, plank = 2 }, cpsSeconds = 12,  xp = 25, weight = 18, unlockLevel = 3 },
    { id = "ord_wiring",        name = "线缆组件",   icon = "image/factory_wiring_20260505004828.png", tier = 2, items = { copper_ingot = 3 },       cpsSeconds = 10,  xp = 22,  weight = 16, unlockLevel = 3 },
    -- T3 订单（消耗T3组件）—— 奖励≈30~35s CPS
    { id = "ord_engine",        name = "发动机",     icon = "image/factory_engine_20260505004851.png", tier = 3, items = { gear = 2, alloy = 1 },    cpsSeconds = 30,  xp = 55,  weight = 14, unlockLevel = 7 },
    { id = "ord_electronics",   name = "电子设备",   icon = "image/factory_electronics_20260505004939.png", tier = 3, items = { circuit = 2, gear = 1 },  cpsSeconds = 30,  xp = 55,  weight = 14, unlockLevel = 8 },
    { id = "ord_armor",         name = "装甲板",     icon = "image/factory_armor_20260505005020.png",  tier = 3, items = { alloy = 3 },              cpsSeconds = 35,  xp = 60,  weight = 12, unlockLevel = 8 },
    -- T4 订单（消耗T4产品）—— 奖励≈90~120s CPS
    { id = "ord_vehicle",       name = "载具",       icon = "image/factory_vehicle_20260505005043.png", tier = 4, items = { machine = 1, gear = 2 },  cpsSeconds = 90,  xp = 120, weight = 10, unlockLevel = 11 },
    { id = "ord_lab_equip",     name = "实验装备",   icon = "image/factory_lab_equip_20260505005111.png", tier = 4, items = { instrument = 1, circuit = 2 }, cpsSeconds = 90,  xp = 120, weight = 10, unlockLevel = 13 },
    { id = "ord_factory_line",  name = "生产线",     icon = "image/factory_factory_line_20260505005251.png",  tier = 4, items = { machine = 1, instrument = 1 }, cpsSeconds = 120, xp = 150, weight = 8, unlockLevel = 14 },
    -- T5 订单（消耗T5精品）—— 奖励≈250~400s CPS
    { id = "ord_satellite",     name = "卫星",       icon = "image/factory_satellite_20260505005313.png",  tier = 5, items = { precision = 1, circuit = 2 }, cpsSeconds = 250, xp = 300, weight = 5, unlockLevel = 17 },
    { id = "ord_supercomputer", name = "超级计算机", icon = "image/factory_supercomputer_20260505005353.png",  tier = 5, items = { precision = 1, machine = 1 }, cpsSeconds = 300, xp = 300, weight = 5, unlockLevel = 18 },
    { id = "ord_space_probe",   name = "太空探测器", icon = "image/factory_space_probe_20260505005924.png", tier = 5, items = { precision = 2, alloy = 3 },   cpsSeconds = 400, xp = 500, weight = 3, unlockLevel = 20 },
}

FC.orderMap = {}
for _, o in ipairs(FC.orders) do
    FC.orderMap[o.id] = o
end

--- 根据当前工厂等级可用的订单列表和权重
---@param factoryLevel number
---@return FactoryOrderDef
function FC.RandomOrder(factoryLevel)
    local available = {}
    local totalW = 0
    for _, o in ipairs(FC.orders) do
        if factoryLevel >= o.unlockLevel then
            available[#available + 1] = o
            totalW = totalW + o.weight
        end
    end
    if #available == 0 then return FC.orders[1] end

    local r = math.random() * totalW
    local acc = 0
    for _, o in ipairs(available) do
        acc = acc + o.weight
        if r <= acc then return o end
    end
    return available[1]
end

-- ============================================================================
-- 订单槽位
-- ============================================================================

FC.BASE_ORDER_SLOTS = 3
FC.ORDER_SLOT_UNLOCK = { [5] = 1, [10] = 1, [15] = 1 }  -- 工厂等级→额外槽
FC.MAX_ORDER_SLOTS = 6

---@param factoryLevel number
---@return number
function FC.GetOrderSlots(factoryLevel)
    local slots = FC.BASE_ORDER_SLOTS
    for lvl, extra in pairs(FC.ORDER_SLOT_UNLOCK) do
        if factoryLevel >= lvl then
            slots = slots + extra
        end
    end
    return math.min(FC.MAX_ORDER_SLOTS, slots)
end

--- 订单自动补充间隔（秒）
FC.ORDER_AUTO_FILL_INTERVAL = 90

-- ============================================================================
-- 工厂内部等级系统
-- ============================================================================

FC.MAX_FACTORY_LEVEL = 20

--- 每级所需经验 = 60 + N * 40
---@param level number 当前等级（0-based，即 0→1 需要 100 XP）
---@return number
function FC.GetXPForLevel(level)
    return 60 + level * 40
end

--- 等级解锁内容摘要
FC.LEVEL_UNLOCKS = {
    [1]  = { desc = "解锁 木板/砖块 合成" },
    [2]  = { desc = "解锁 铁锭/铜锭 合成, T2订单" },
    [3]  = { desc = "解锁 工具套装/线缆组件 订单" },
    [5]  = { desc = "解锁 齿轮 合成, +1订单槽" },
    [6]  = { desc = "解锁 电路 合成" },
    [7]  = { desc = "解锁 合金 合成, T3订单" },
    [8]  = { desc = "采集量上限+1" },
    [10] = { desc = "解锁 机器 合成, +1订单槽" },
    [12] = { desc = "解锁 仪器 合成" },
    [14] = { desc = "解锁 生产线 订单" },
    [15] = { desc = "+1订单槽" },
    [16] = { desc = "解锁 精密装置 合成, 采集量上限+1" },
    [17] = { desc = "解锁 卫星 订单" },
    [18] = { desc = "解锁 超级计算机 订单" },
    [20] = { desc = "解锁 太空探测器 订单" },
}

-- ============================================================================
-- 物品容量
-- ============================================================================

--- 背包容量 = 50 + factoryLevel*5 + floor(buildingCount/3), max 300
---@param factoryLevel number
---@param buildingCount number
---@return number
function FC.GetItemCap(factoryLevel, buildingCount)
    return math.min(300, 50 + factoryLevel * 5 + math.floor(buildingCount / 3))
end

-- ============================================================================
-- 合成队列
-- ============================================================================

FC.MAX_CRAFT_QUEUE = 5

-- ============================================================================
-- 连续交付奖励（保留）
-- ============================================================================

FC.STREAK_REWARDS = {
    { threshold = 3,  buff = { id = "fstreak3",  name = "流水线效率", mul = 1.03, duration = 60 } },
    { threshold = 5,  buff = { id = "fstreak5",  name = "产能爆发",   mul = 1.08, duration = 120 } },
    { threshold = 10, buff = { id = "fstreak10", name = "大师工匠",   mul = 1.15, duration = 180 } },
}

return FC
