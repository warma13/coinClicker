-- ============================================================================
-- config/ECommerceConfig.lua
-- 限时秒杀 —— 电商平台(#11)小游戏配置
-- ============================================================================

local EC = {}

-- ============================================================================
-- 建筑 ID（解锁条件）
-- ============================================================================
EC.BUILDING_ID = "portal"

-- ============================================================================
-- 商品槽位阶梯（根据电商平台数量）
-- ============================================================================

EC.SLOT_TIERS = {
    { minCount = 1,  slots = 3 },
    { minCount = 6,  slots = 4 },
    { minCount = 16, slots = 5 },
    { minCount = 31, slots = 6 },
}

--- 获取当前商品槽位数
---@param portalCount number
---@return number
function EC.GetItemSlots(portalCount)
    local slots = 3
    for _, tier in ipairs(EC.SLOT_TIERS) do
        if portalCount >= tier.minCount then
            slots = tier.slots
        end
    end
    return slots
end

-- ============================================================================
-- 商品类型定义
-- ============================================================================

---@class ECommerceItemDef
---@field id string
---@field name string
---@field icon string
---@field saleTime number        秒杀倒计时（秒）
---@field investCpsMul number    进货成本 = CPS × 此值
---@field profitCpsMul number    销售利润 = CPS × 此值
---@field weight number          出现权重
---@field hotChance number       爆款概率(0-1)，爆款利润 ×2
---@field buff table|nil         特殊商品带 buff

-- ROI 对齐花园系统（基础种子 ≈ 2.0×）
-- 电商作为后期建筑(#11)，基础 ROI ≈ 2.2-2.5×
-- 爆款/广告使用加法叠加：bonus = 1 + hotBonus + adBonus
-- 爆款单独：ROI ≈ 2.2 × 1.8 = 3.96×（作为保留的高额奖励）
-- 广告单独：ROI ≈ 2.2 × 1.4 = 3.08×
-- 两者叠加：ROI ≈ 2.2 × 2.2 = 4.84×（加法上限，不再出现 ×3 乘法爆炸）
EC.items = {
    {
        id = "food",
        name = "生鲜食品",
        icon = "🍎",
        saleTime = 420,          -- 7 分钟
        investCpsMul = 10,       -- 成本 CPS×10
        profitCpsMul = 22,       -- 利润 CPS×22 → ROI 2.2×
        weight = 28,
        hotChance = 0.03,
    },
    {
        id = "daily",
        name = "日用百货",
        icon = "🧴",
        saleTime = 480,          -- 8 分钟
        investCpsMul = 15,       -- 成本 CPS×15
        profitCpsMul = 33,       -- 利润 CPS×33 → ROI 2.2×
        weight = 30,
        hotChance = 0.05,
    },
    {
        id = "fashion",
        name = "时尚服饰",
        icon = "👗",
        saleTime = 540,          -- 9 分钟
        investCpsMul = 30,       -- 成本 CPS×30
        profitCpsMul = 68,       -- 利润 CPS×68 → ROI 2.27×
        weight = 22,
        hotChance = 0.08,
    },
    {
        id = "electronics",
        name = "数码电子",
        icon = "📱",
        saleTime = 600,          -- 10 分钟
        investCpsMul = 50,       -- 成本 CPS×50
        profitCpsMul = 115,      -- 利润 CPS×115 → ROI 2.3×
        weight = 25,
        hotChance = 0.10,
    },
    {
        id = "luxury",
        name = "奢侈品",
        icon = "💎",
        saleTime = 900,          -- 15 分钟
        investCpsMul = 120,      -- 成本 CPS×120
        profitCpsMul = 280,      -- 利润 CPS×280 → ROI 2.33×
        weight = 10,
        hotChance = 0.15,
    },
    {
        id = "limited",
        name = "限定联名",
        icon = "🎁",
        saleTime = 480,          -- 8 分钟（提高以匹配投资额）
        investCpsMul = 80,       -- 成本 CPS×80
        profitCpsMul = 200,      -- 利润 CPS×200 → ROI 2.5×（含 buff 补偿）
        weight = 5,
        hotChance = 0.25,
        buff = {
            id = "limited_cps",
            name = "联名热度",
            mul = 1.08,
            duration = 300,
        },
    },
}

-- 快速查找
EC.itemMap = {}
for _, it in ipairs(EC.items) do
    EC.itemMap[it.id] = it
end

-- 总权重
EC.totalWeight = 0
for _, it in ipairs(EC.items) do
    EC.totalWeight = EC.totalWeight + it.weight
end

--- 按权重随机选取商品
---@return ECommerceItemDef
function EC.RandomItem()
    local r = math.random() * EC.totalWeight
    local acc = 0
    for _, it in ipairs(EC.items) do
        acc = acc + it.weight
        if r <= acc then return it end
    end
    return EC.items[1]
end

-- ============================================================================
-- 促销等级（连续成功销售可解锁）
-- ============================================================================

EC.PROMO_TIERS = {
    { threshold = 3, discount = 0.10, label = "满减优惠" },   -- 进货成本 -10%
    { threshold = 5, discount = 0.20, label = "限时大促" },   -- 进货成本 -20%
    { threshold = 8, discount = 0.30, label = "超级秒杀" },   -- 进货成本 -30%
}

-- ============================================================================
-- 连续成功奖励
-- ============================================================================

EC.STREAK_REWARDS = {
    { threshold = 3, buff = { id = "sales3_cps", name = "营销势能", mul = 1.05, duration = 300 } },
    { threshold = 6, buff = { id = "sales6_cps", name = "爆款效应", mul = 1.12, duration = 420 } },
}

-- ============================================================================
-- 广告推广（花费金币增加销售成功率）
-- ============================================================================

EC.AD_BOOST_CPS_MUL = 20           -- 广告费 = CPS × 20（高于低价商品利润，形成策略选择）
EC.HOT_BONUS = 0.8                 -- 爆款加成（加法）：利润 = base × (1 + 0.8) = ×1.8
EC.AD_BONUS = 0.4                  -- 广告加成（加法）：利润 = base × (1 + 0.4) = ×1.4
                                   -- 爆款+广告：利润 = base × (1 + 0.8 + 0.4) = ×2.2

-- ============================================================================
-- 商品自动刷新
-- ============================================================================

EC.ITEM_REFRESH_INTERVAL = 1800    -- 每 1800 秒(30分钟)刷新未购买的商品 —— 长周期高回报

return EC
