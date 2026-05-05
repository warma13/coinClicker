-- ============================================================================
-- config/ShipmentConfig.lua
-- 货运航线 —— 国际物流(#9)小游戏配置
-- ============================================================================

local SC = {}

-- ============================================================================
-- 建筑 ID（解锁条件）
-- ============================================================================
SC.BUILDING_ID = "shipment"

-- ============================================================================
-- 航线槽位阶梯（根据国际物流数量）
-- ============================================================================

SC.ROUTE_TIERS = {
    { minCount = 1,  routes = 2 },
    { minCount = 6,  routes = 3 },
    { minCount = 16, routes = 4 },
    { minCount = 31, routes = 5 },
}

--- 获取当前可用航线数
---@param shipmentCount number
---@return number
function SC.GetRouteSlots(shipmentCount)
    local routes = 2
    for _, tier in ipairs(SC.ROUTE_TIERS) do
        if shipmentCount >= tier.minCount then
            routes = tier.routes
        end
    end
    return routes
end

-- ============================================================================
-- 货物类型定义
-- ============================================================================

---@class ShipmentCargoDef
---@field id string
---@field name string
---@field icon string
---@field travelTime number     运输时间（秒）
---@field cpsSeconds number     奖励 = CPS × 秒
---@field weight number         出现权重
---@field hazard boolean|nil    是否危险品（延误概率更高）

-- investCpsMul: 运输成本 = CPS × 此值（发货时扣除）
-- 设计目标：单条净利/航时 ≈ 0.2~0.35× 挂机
-- 航时匹配 25 分钟刷新周期，最长组合（军需+极地 2.0x）≈24 分钟
-- 4 槽满发/周期 ≈ +0.24× 挂机，不会碾压自然 CPS
-- 净利 = cpsSeconds - investCpsMul, 比值 = 净利/travelTime
SC.cargos = {
    {
        id = "consumer",
        name = "日用百货",
        icon = "📦",
        travelTime = 180,
        investCpsMul = 135,      -- 净利 35, 35/180=0.19× 挂机
        cpsSeconds = 170,
        weight = 30,
    },
    {
        id = "electronics",
        name = "电子产品",
        icon = "💻",
        travelTime = 300,
        investCpsMul = 275,      -- 净利 75, 75/300=0.25× 挂机
        cpsSeconds = 350,
        weight = 25,
    },
    {
        id = "machinery",
        name = "重型机械",
        icon = "⚙️",
        travelTime = 420,
        investCpsMul = 420,      -- 净利 90, 90/420=0.21× 挂机
        cpsSeconds = 510,
        weight = 20,
    },
    {
        id = "luxury",
        name = "奢侈品",
        icon = "💎",
        travelTime = 540,
        investCpsMul = 630,      -- 净利 160, 160/540=0.30× 挂机
        cpsSeconds = 790,
        weight = 12,
    },
    {
        id = "military_supply",
        name = "军需物资",
        icon = "🛡️",
        travelTime = 720,
        investCpsMul = 880,      -- 净利 240, 240/720=0.33× 挂机（保留为最高奖励）
        cpsSeconds = 1120,
        weight = 8,
        buff = {
            id = "supply_line",
            name = "补给线",
            mul = 1.08,
            duration = 300,
        },
    },
    {
        id = "hazmat",
        name = "危险化学品",
        icon = "☢️",
        travelTime = 240,
        investCpsMul = 480,      -- 净利 100, 100/240=0.42× 挂机（高风险溢价）
        cpsSeconds = 580,
        weight = 5,
        hazard = true,
    },
}

-- cargo id → def 快速查找
SC.cargoMap = {}
for _, c in ipairs(SC.cargos) do
    SC.cargoMap[c.id] = c
end

-- ============================================================================
-- 总权重
-- ============================================================================

SC.totalWeight = 0
for _, c in ipairs(SC.cargos) do
    SC.totalWeight = SC.totalWeight + c.weight
end

--- 按权重随机选取一个货物类型
---@return ShipmentCargoDef
function SC.RandomCargo()
    local r = math.random() * SC.totalWeight
    local acc = 0
    for _, c in ipairs(SC.cargos) do
        acc = acc + c.weight
        if r <= acc then
            return c
        end
    end
    return SC.cargos[1]
end

-- ============================================================================
-- 航线定义（目的地）
-- ============================================================================

---@class ShipmentRouteDef
---@field id string
---@field name string
---@field icon string
---@field timeMul number        运输时间倍率
---@field rewardMul number      奖励倍率
---@field delayChance number    延误概率(0-1)

SC.routes = {
    { id = "domestic",  name = "国内",     icon = "🏠", timeMul = 0.8, rewardMul = 0.8, delayChance = 0.05 },
    { id = "asia",      name = "亚太",     icon = "🌏", timeMul = 1.0, rewardMul = 1.0, delayChance = 0.10 },
    { id = "europe",    name = "欧洲",     icon = "🏰", timeMul = 1.3, rewardMul = 1.4, delayChance = 0.15 },
    { id = "americas",  name = "美洲",     icon = "🗽", timeMul = 1.5, rewardMul = 1.6, delayChance = 0.20 },
    { id = "arctic",    name = "极地",     icon = "❄️", timeMul = 2.0, rewardMul = 2.0, delayChance = 0.30 },  -- 2.5→2.0 与时间倍率持平
}

-- route id → def
SC.routeMap = {}
for _, r in ipairs(SC.routes) do
    SC.routeMap[r.id] = r
end

-- ============================================================================
-- 延误事件
-- ============================================================================

SC.DELAY_TIME_ADD = 0.3             -- 延误增加运输时间的比例 +30%
SC.HAZARD_DELAY_EXTRA = 0.15        -- 危险品额外延误概率

-- ============================================================================
-- 加急 / 保险
-- ============================================================================

SC.EXPRESS_CPS_MUL = 120             -- 加急费 = CPS × 120
SC.EXPRESS_TIME_MUL = 0.5            -- 加急后时间 ×0.5

SC.INSURANCE_CPS_MUL = 50            -- 保险费 = CPS × 50（防止延误损失）

-- ============================================================================
-- 连续安全送达奖励
-- ============================================================================

SC.STREAK_REWARDS = {
    { threshold = 3, buff = { id = "safe3_cps", name = "安全运输", mul = 1.05, duration = 300 } },
    { threshold = 5, buff = { id = "safe5_cps", name = "物流之王", mul = 1.12, duration = 420 } },
}

-- ============================================================================
-- 航线刷新
-- ============================================================================

SC.CARGO_REFRESH_INTERVAL = 1500   -- 每 1500 秒(25分钟)刷新待发货物

return SC
