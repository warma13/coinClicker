-- ============================================================================
-- config/StockMarketConfig.lua
-- 证券交易所配置：商品定义、经纪人、办公室、贷款
-- 对应 Cookie Clicker 的 Stock Market 小游戏
-- 绑定建筑：商业银行（id="bank"，index 6）
-- ============================================================================

local SC = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
SC.TICK_INTERVAL      = 60     -- 每 60 秒一次价格更新（CC 原版也是 60s）
SC.BASE_OVERHEAD      = 0.20   -- 基础手续费 20%
SC.BROKER_OVERHEAD_MUL = 0.95  -- 每个经纪人把手续费乘以 0.95（CC: 5% 递减）
SC.BROKER_BASE_COST   = 1200   -- 第 n 个经纪人 = $1200 * n（CC 原版递增）
SC.BASE_STORAGE_PER_BUILDING = 1   -- 每个对应建筑 +1 仓位
SC.MODE_SWITCH_MIN    = 300    -- 模式最短持续 tick 数
SC.MODE_SWITCH_MAX    = 900    -- 模式最长持续 tick 数
SC.DELTA_DECAY        = 0.03   -- delta 每 tick 衰减 3%（CC 原版）
SC.LOW_PRICE_THRESHOLD = 5     -- 价格低于此值时触发低价保护
SC.MARKET_CAP_DECAY   = 0.10   -- 超过天花板时 delta 额外衰减 10%

-- $1 = 本轮飞升中最高无 buff CPS 的 1 秒产出
-- 实际价值在 Manager 中动态计算

-- ---------------------------------------------------------------------------
-- 价格波动模式（6种，对齐 CC 原版）
-- ---------------------------------------------------------------------------
SC.MODE_SLOW_RISE  = 1  -- 缓涨：稳步上涨，偶有小跌
SC.MODE_SLOW_FALL  = 2  -- 缓跌：稳步下跌，偶有小涨
SC.MODE_FAST_RISE  = 3  -- 暴涨：快速上冲
SC.MODE_FAST_FALL  = 4  -- 暴跌：快速下跌
SC.MODE_CHAOTIC    = 5  -- 混沌：随机波动
SC.MODE_STABLE     = 6  -- 平稳：围绕静息值小幅波动

SC.MODE_NAMES = {
    [1] = "缓涨", [2] = "缓跌", [3] = "暴涨",
    [4] = "暴跌", [5] = "混沌", [6] = "平稳",
}

-- CC 原版模式权重（概率）
-- stable 12.5%, slowRise 25%, slowFall 25%, fastRise 12.5%, fastFall 12.5%, chaotic 12.5%
SC.MODE_WEIGHTS = {
    [SC.MODE_SLOW_RISE] = 2,  -- 25%
    [SC.MODE_SLOW_FALL] = 2,  -- 25%
    [SC.MODE_FAST_RISE] = 1,  -- 12.5%
    [SC.MODE_FAST_FALL] = 1,  -- 12.5%
    [SC.MODE_CHAOTIC]   = 1,  -- 12.5%
    [SC.MODE_STABLE]    = 1,  -- 12.5%
}
SC.MODE_TOTAL_WEIGHT = 8

-- CC 原版 delta 模型参数
-- deltaDecay: delta 每 tick 的衰减系数（乘法）
-- valueLo/valueHi: 每 tick 价格直接加的随机范围
-- deltaLo/deltaHi: 每 tick delta 加的随机范围
SC.MODE_PARAMS = {
    [SC.MODE_STABLE]    = { deltaDecay = 0.05, valueLo = -0.025, valueHi = 0.025, deltaLo = -0.02,  deltaHi = 0.02  },
    [SC.MODE_SLOW_RISE] = { deltaDecay = 0.01, valueLo = -0.005, valueHi = 0.045, deltaLo = -0.005, deltaHi = 0.015 },
    [SC.MODE_SLOW_FALL] = { deltaDecay = 0.01, valueLo = -0.045, valueHi = 0.005, deltaLo = -0.015, deltaHi = 0.005 },
    [SC.MODE_FAST_RISE] = { deltaDecay = 0.03, valueLo =  0,     valueHi = 5,     deltaLo = -0.015, deltaHi = 0.135 },
    [SC.MODE_FAST_FALL] = { deltaDecay = 0.03, valueLo = -5,     valueHi = 0,     deltaLo = -0.135, deltaHi = 0.015 },
    [SC.MODE_CHAOTIC]   = { deltaDecay = 0.01, valueLo = -0.15,  valueHi = 0.15,  deltaLo = -0.15,  deltaHi = 0.15  },
}

-- ---------------------------------------------------------------------------
-- 商品定义（对齐 CC 的 15 个商品，商业主题化）
-- 每个商品与一个建筑绑定（从 index 3 开始，跳过 cursor/grandma）
-- restingBase: 静息价格基础值 = 10*(id+1)，id 从 0 开始
-- buildingId: 对应建筑 id（决定仓位上限）
-- ---------------------------------------------------------------------------
SC.goods = {
    {
        id = "grain",
        name = "农产品期货",
        ticker = "AGR",
        icon = "🌾",
        buildingId = "farm",      -- 种植园
        restingBase = 10,         -- 10*(0+1) = 10
    },
    {
        id = "ore",
        name = "矿石原料",
        ticker = "ORE",
        icon = "⛏️",
        buildingId = "mine",      -- 采矿场
        restingBase = 20,         -- 10*(1+1) = 20
    },
    {
        id = "steel",
        name = "工业制品",
        ticker = "STL",
        icon = "🏭",
        buildingId = "factory",   -- 制造工厂
        restingBase = 30,         -- 10*(2+1) = 30
    },
    {
        id = "bond",
        name = "金融债券",
        ticker = "BND",
        icon = "🏦",
        buildingId = "bank",      -- 商业银行
        restingBase = 40,
    },
    {
        id = "realty",
        name = "地产信托",
        ticker = "REI",
        icon = "⛩️",
        buildingId = "temple",    -- 商业地产
        restingBase = 50,
    },
    {
        id = "tech",
        name = "科技专利",
        ticker = "TEC",
        icon = "🧙",
        buildingId = "wizard",    -- 研发中心
        restingBase = 60,
    },
    {
        id = "shipping",
        name = "物流运力",
        ticker = "LOG",
        icon = "🐫",
        buildingId = "shipment",  -- 国际物流
        restingBase = 70,
    },
    {
        id = "energy",
        name = "能源合约",
        ticker = "NRG",
        icon = "⚗️",
        buildingId = "alchemy",   -- 能源集团
        restingBase = 80,
    },
    {
        id = "ecommerce",
        name = "电商股份",
        ticker = "ECM",
        icon = "🌀",
        buildingId = "portal",    -- 电商平台
        restingBase = 90,
    },
    {
        id = "futures",
        name = "衍生品",
        ticker = "DRV",
        icon = "⏳",
        buildingId = "timeMachine", -- 期货交易所
        restingBase = 100,
    },
    {
        id = "uranium",
        name = "核能指数",
        ticker = "NUC",
        icon = "⚛️",
        buildingId = "antimatter",  -- 核能电站
        restingBase = 110,
    },
    {
        id = "space",
        name = "太空资源",
        ticker = "SPC",
        icon = "🔮",
        buildingId = "prism",       -- 太空采矿
        restingBase = 120,
    },
    {
        id = "sovereign",
        name = "主权债",
        ticker = "SOV",
        icon = "🏺",
        buildingId = "chancemaker", -- 主权基金
        restingBase = 130,
    },
    {
        id = "quant",
        name = "量化基金",
        ticker = "QNT",
        icon = "🔷",
        buildingId = "fractal",     -- 量化交易
        restingBase = 140,
    },
    {
        id = "crypto",
        name = "数字资产",
        ticker = "CRY",
        icon = "💻",
        buildingId = "console",     -- 数字货币
        restingBase = 150,
    },
    {
        id = "metaverse",
        name = "元宇宙",
        ticker = "MET",
        icon = "🌐",
        buildingId = "idleverse",   -- 平行宇宙
        restingBase = 160,
    },
    {
        id = "neuro",
        name = "神经网络",
        ticker = "NEU",
        icon = "🧠",
        buildingId = "cortex",      -- 脑机接口
        restingBase = 170,
    },
    {
        id = "self",
        name = "个人品牌",
        ticker = "YOU",
        icon = "👤",
        buildingId = "you",         -- 你自己
        restingBase = 180,
    },
}

-- ---------------------------------------------------------------------------
-- 办公室升级（决定仓位容量 + 解锁贷款）
-- 对齐 CC: 升级需要临时工(cursor)数量和等级
-- ---------------------------------------------------------------------------
SC.offices = {
    {
        level = 0,
        name = "车库办公室",
        storagePlus = 0,
        loanSlots = 0,
        cursorReq = 0,
        cursorLevel = 0,
    },
    {
        level = 1,
        name = "小型营业部",
        storagePlus = 25,
        loanSlots = 0,
        cursorReq = 100,
        cursorLevel = 2,
    },
    {
        level = 2,
        name = "借贷公司",
        storagePlus = 50,
        loanSlots = 1,
        cursorReq = 200,
        cursorLevel = 4,
    },
    {
        level = 3,
        name = "金融总部",
        storagePlus = 75,
        loanSlots = 1,
        cursorReq = 350,
        cursorLevel = 8,
    },
    {
        level = 4,
        name = "国际交易中心",
        storagePlus = 100,
        loanSlots = 2,
        cursorReq = 500,
        cursorLevel = 10,
    },
    {
        level = 5,
        name = "财富宫殿",
        storagePlus = 100,
        loanSlots = 3,
        cursorReq = 700,
        cursorLevel = 12,
        storagePerBuilding = 1.5, -- 升级后每建筑 1.5 仓位
    },
}

-- ---------------------------------------------------------------------------
-- 贷款定义
-- ---------------------------------------------------------------------------
-- CC 原版 3 种贷款（时间按比例缩短以适配手游节奏：原版小时→分钟）
SC.loans = {
    {
        id = "loan1",
        name = "温和贷款",       -- CC: Modest loan
        boostMul    = 1.5,      -- CPS +50%
        boostDur    = 120,      -- CC: 2h → 120秒（2分钟）
        penaltyMul  = 0.25,     -- CPS -75%（CC 原版）
        penaltyDur  = 240,      -- CC: 4h → 240秒（4分钟）
        downpayment = 0.20,     -- 预付 20%
    },
    {
        id = "loan2",
        name = "典当贷款",       -- CC: Pawnshop loan
        boostMul    = 2.0,      -- CPS +100%
        boostDur    = 40,       -- CC: 40s → 40秒
        penaltyMul  = 0.10,     -- CPS -90%（CC 原版）
        penaltyDur  = 600,      -- CC: 40min → 600秒（10分钟）
        downpayment = 0.40,     -- 预付 40%
    },
    {
        id = "loan3",
        name = "退休贷款",       -- CC: Retirement loan
        boostMul    = 1.2,      -- CPS +20%（CC 原版）
        boostDur    = 600,      -- CC: 2d → 600秒（10分钟）
        penaltyMul  = 0.80,     -- CPS -20%（CC 原版）
        penaltyDur  = 1200,     -- CC: 5d → 1200秒（20分钟）
        downpayment = 0.50,     -- 预付 50%（CC 原版）
    },
}

-- ---------------------------------------------------------------------------
-- 工具函数
-- ---------------------------------------------------------------------------

--- 按 id 查找商品
---@param goodId string
---@return table|nil, number|nil
function SC.FindGood(goodId)
    for i, g in ipairs(SC.goods) do
        if g.id == goodId then return g, i end
    end
    return nil, nil
end

--- 按 ticker 查找商品
---@param ticker string
---@return table|nil, number|nil
function SC.FindByTicker(ticker)
    for i, g in ipairs(SC.goods) do
        if g.ticker == ticker then return g, i end
    end
    return nil, nil
end

--- 获取静息价格（CC: 10*(id+1) + bankLevel - 1）
---@param goodIndex number 1-based
---@param bankLevel number
---@return number
function SC.GetRestingValue(goodIndex, bankLevel)
    local good = SC.goods[goodIndex]
    if not good then return 10 end
    return good.restingBase + math.max(0, bankLevel - 1)
end

--- 获取当前办公室等级定义
---@param level number 0~5
---@return table
function SC.GetOffice(level)
    for _, o in ipairs(SC.offices) do
        if o.level == level then return o end
    end
    return SC.offices[1]
end

--- 获取下一级办公室
---@param level number
---@return table|nil
function SC.GetNextOffice(level)
    return SC.GetOffice(level + 1)
end

return SC
