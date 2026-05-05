-- ============================================================================
-- config/PantheonConfig.lua
-- 商业顾问团配置：顾问定义、槽位定义、常量
-- 对应 Cookie Clicker 的 Temple / Pantheon 小游戏
-- 绑定建筑：商业地产（id="temple"，index 7）
-- ============================================================================

local PC = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
PC.SLOT_COUNT         = 3       -- 3 个顾问席位
PC.SWAP_COOLDOWN      = 1800    -- 更换顾问冷却（秒）：30 分钟 —— 策略性选择，长周期
PC.UNLOCK_BUILDING_COUNT = 1    -- 需要多少个商业地产才能解锁

-- ---------------------------------------------------------------------------
-- 槽位定义（钻石/红宝石/翡翠 → 金席/银席/铜席）
-- multiplier: 效果强度乘数（1.0 / 0.6 / 0.3）
-- ---------------------------------------------------------------------------
PC.slots = {
    {
        id       = "gold",
        name     = "金席",
        icon     = "🥇",
        color    = { 255, 215, 0, 255 },
        effectMul = 1.0,
        desc     = "效果 100%",
    },
    {
        id       = "silver",
        name     = "银席",
        icon     = "🥈",
        color    = { 192, 192, 192, 255 },
        effectMul = 0.6,
        desc     = "效果 60%",
    },
    {
        id       = "bronze",
        name     = "铜席",
        icon     = "🥉",
        color    = { 205, 127, 50, 255 },
        effectMul = 0.3,
        desc     = "效果 30%",
    },
}

-- ---------------------------------------------------------------------------
-- 顾问定义（11 位，对标 Cookie Clicker 的 11 个神灵）
--
-- effectType: 效果类型
--   "cps"           → 每秒产出加成
--   "cpc"           → 每次点击加成
--   "buildingCost"  → 建筑费用折扣
--   "luckyDuration" → 幸运金币持续时间加成
--   "sugarSpeed"    → 糖块(人脉)成长加速
--   "wrinkler"      → 渠道收益加成
--   "goldenFreq"    → 幸运金币出现频率
--   "cpsDecay"      → 每秒产出负面（副作用）
--   "cpcDecay"      → 每次点击负面（副作用）
--
-- baseEffect: 基础效果值（金席时的效果），实际效果 = baseEffect × slotMul
-- sideEffect: 副作用（可选），{ type, value } 金席时的副作用值
--
-- 商业主题化：每个顾问是一位商业领域的传奇人物 / 策略类型
-- ---------------------------------------------------------------------------
PC.spirits = {
    {
        id          = "mogul",
        name        = "地产大亨",
        icon        = "🏗️",
        desc        = "商业地产专家，提升整体产出",
        effectType  = "cps",
        baseEffect  = 0.15,       -- +15% CPS (金席)
        sideEffect  = { type = "cpc", value = -0.10 },  -- -10% 点击
        unlockCount = 1,          -- 需要商业地产数量
    },
    {
        id          = "trader",
        name        = "华尔街操盘手",
        icon        = "📈",
        desc        = "金融高手，提升点击收益",
        effectType  = "cpc",
        baseEffect  = 0.20,       -- +20% CPC (金席)
        sideEffect  = { type = "cps", value = -0.05 },  -- -5% CPS
        unlockCount = 1,
    },
    {
        id          = "negotiator",
        name        = "谈判专家",
        icon        = "🤝",
        desc        = "压低采购成本，降低建筑费用",
        effectType  = "buildingCost",
        baseEffect  = -0.10,      -- -10% 建筑费用 (金席)
        sideEffect  = nil,        -- 无副作用
        unlockCount = 1,
    },
    {
        id          = "publicist",
        name        = "公关总监",
        icon        = "📣",
        desc        = "制造热点话题，幸运金币出现更频繁",
        effectType  = "goldenFreq",
        baseEffect  = 0.15,       -- +15% 幸运金币频率
        sideEffect  = { type = "cps", value = -0.03 },  -- -3% CPS
        unlockCount = 1,
    },
    {
        id          = "lobbyist",
        name        = "政商掮客",
        icon        = "🎩",
        desc        = "延长优惠政策时效，幸运金币持续更久",
        effectType  = "luckyDuration",
        baseEffect  = 0.20,       -- +20% 幸运持续时间
        sideEffect  = { type = "buildingCost", value = 0.03 },  -- +3% 建筑费用
        unlockCount = 1,
    },
    {
        id          = "mentor",
        name        = "创业导师",
        icon        = "🎓",
        desc        = "加速人脉积累，糖块成长更快",
        effectType  = "sugarSpeed",
        baseEffect  = 0.10,       -- +10% 糖块速度
        sideEffect  = nil,
        unlockCount = 1,
    },
    {
        id          = "tycoon",
        name        = "产业巨头",
        icon        = "🏭",
        desc        = "规模效应，大幅提升产出但高消耗",
        effectType  = "cps",
        baseEffect  = 0.25,       -- +25% CPS (金席)
        sideEffect  = { type = "buildingCost", value = 0.08 },  -- +8% 建筑费用
        unlockCount = 1,
    },
    {
        id          = "analyst",
        name        = "首席分析师",
        icon        = "📊",
        desc        = "数据驱动决策，小幅全面提升",
        effectType  = "cps",
        baseEffect  = 0.08,       -- +8% CPS
        sideEffect  = nil,        -- 无副作用（效果较弱作为平衡）
        unlockCount = 1,
    },
    {
        id          = "vulture",
        name        = "秃鹫资本家",
        icon        = "🦅",
        desc        = "擅长从危机中获利，增强渠道收益",
        effectType  = "wrinkler",
        baseEffect  = 0.15,       -- +15% 渠道收益加成
        sideEffect  = { type = "goldenFreq", value = -0.05 },  -- -5% 幸运频率
        unlockCount = 1,
    },
    {
        id          = "minimalist",
        name        = "极简主义者",
        icon        = "🧘",
        desc        = "削减一切开支，大幅降低建筑费用",
        effectType  = "buildingCost",
        baseEffect  = -0.18,      -- -18% 建筑费用
        sideEffect  = { type = "cpc", value = -0.08 },  -- -8% 点击
        unlockCount = 1,
    },
    {
        id          = "visionary",
        name        = "远见者",
        icon        = "🔮",
        desc        = "预见未来趋势，全方位被动加成",
        effectType  = "cps",
        baseEffect  = 0.10,       -- +10% CPS
        sideEffect  = nil,
        -- 特殊：额外给 +3% CPC
        extraEffect = { type = "cpc", value = 0.03 },
        unlockCount = 1,
    },
}

-- ---------------------------------------------------------------------------
-- 工具函数
-- ---------------------------------------------------------------------------

--- 按 id 查找顾问定义
---@param spiritId string
---@return table|nil
function PC.FindSpirit(spiritId)
    for _, s in ipairs(PC.spirits) do
        if s.id == spiritId then return s end
    end
    return nil
end

--- 按 id 查找槽位定义
---@param slotId string
---@return table|nil, number|nil
function PC.FindSlot(slotId)
    for i, s in ipairs(PC.slots) do
        if s.id == slotId then return s, i end
    end
    return nil, nil
end

--- 获取顾问在指定槽位的实际效果值
---@param spirit table 顾问定义
---@param slotIndex number 槽位索引 1~3
---@return number effectValue
function PC.GetEffectValue(spirit, slotIndex)
    local slot = PC.slots[slotIndex]
    if not slot then return 0 end
    return spirit.baseEffect * slot.effectMul
end

--- 获取顾问在指定槽位的副作用值
---@param spirit table 顾问定义
---@param slotIndex number 槽位索引 1~3
---@return string|nil type, number|nil value
function PC.GetSideEffectValue(spirit, slotIndex)
    if not spirit.sideEffect then return nil, nil end
    local slot = PC.slots[slotIndex]
    if not slot then return nil, nil end
    return spirit.sideEffect.type, spirit.sideEffect.value * slot.effectMul
end

--- 获取可解锁的顾问列表（给定商业地产数量）
---@param templeCount number 商业地产数量
---@return table[]
function PC.GetUnlockedSpirits(templeCount)
    local list = {}
    for _, s in ipairs(PC.spirits) do
        if templeCount >= s.unlockCount then
            list[#list + 1] = s
        end
    end
    return list
end

--- 获取可用槽位数量（根据商业地产等级：1/3/5 级）
---@param templeLevel number 商业地产等级
---@return number 1~3
function PC.GetAvailableSlots(templeLevel)
    if templeLevel >= 5 then return 3 end
    if templeLevel >= 3 then return 2 end
    return 1
end

--- 格式化效果文本
---@param effectType string
---@param value number
---@return string
function PC.FormatEffect(effectType, value)
    local names = {
        cps = "每秒产出",
        cpc = "每次点击",
        buildingCost = "建筑费用",
        goldenFreq = "幸运频率",
        luckyDuration = "幸运时长",
        sugarSpeed = "人脉速度",
        wrinkler = "渠道收益",
    }
    local name = names[effectType] or effectType
    if value > 0 then
        return name .. " +" .. math.floor(value * 100 + 0.5) .. "%"
    else
        return name .. " " .. math.floor(value * 100 - 0.5) .. "%"
    end
end

return PC
