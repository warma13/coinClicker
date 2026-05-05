-- ============================================================================
-- config/MiningConfig.lua
-- 挖矿探险 —— 商品/矿石/网格/道具 配置
-- ============================================================================

local MC = {}

-- ============================================================================
-- 建筑 ID（解锁条件）
-- ============================================================================
MC.BUILDING_ID = "mine"

-- ============================================================================
-- 网格尺寸阶梯（根据采矿场数量）
-- ============================================================================
MC.GRID_TIERS = {
    { minCount = 1,  cols = 5, rows = 4 },   -- 20 格
    { minCount = 11, cols = 6, rows = 5 },   -- 30 格
    { minCount = 31, cols = 7, rows = 5 },   -- 35 格
    { minCount = 61, cols = 8, rows = 6 },   -- 48 格
}

--- 根据采矿场数量获取网格尺寸
---@param mineCount number
---@return number cols, number rows
function MC.GetGridSize(mineCount)
    local cols, rows = 5, 4
    for _, tier in ipairs(MC.GRID_TIERS) do
        if mineCount >= tier.minCount then
            cols, rows = tier.cols, tier.rows
        end
    end
    return cols, rows
end

-- ============================================================================
-- 矿石类型定义
-- ============================================================================

---@class MiningOreDef
---@field id string
---@field name string
---@field icon string
---@field cpsSeconds number   CPS×秒 的金币奖励
---@field buff table|nil      可选 buff { id, desc, mul, duration }
---@field penalty boolean|nil 是否是负面格子

MC.ORE_EMPTY = "empty"

MC.ores = {
    {
        id = "empty",
        name = "空岩",
        icon = "",
        cpsSeconds = 0,
    },
    {
        id = "copper",
        name = "铜矿",
        icon = "",
        iconImage = "image/矿石_铜矿_20260503233747.png",
        cpsSeconds = 40,
    },
    {
        id = "iron",
        name = "铁矿",
        icon = "",
        iconImage = "image/矿石_铁矿_20260503233750.png",
        cpsSeconds = 150,
    },
    {
        id = "gold",
        name = "金矿",
        icon = "",
        iconImage = "image/矿石_金矿_20260503233814.png",
        cpsSeconds = 600,
    },
    {
        id = "gem",
        name = "宝石",
        icon = "",
        iconImage = "image/矿石_宝石_20260503233805.png",
        cpsSeconds = 2000,
        buff = {
            id = "gem_cps",
            name = "宝石光辉",
            mul = 1.15,
            duration = 300,
        },
    },
    {
        id = "fossil",
        name = "化石",
        icon = "",
        iconImage = "image/矿石_化石_20260503233745.png",
        cpsSeconds = 300,
        buff = {
            id = "fossil_luck",
            name = "远古祝福",
            mul = 1.08,
            duration = 420,
        },
    },
    {
        id = "collapse",
        name = "塌方",
        icon = "",
        iconImage = "image/矿石_塌方_20260503233750.png",
        cpsSeconds = 0,
        penalty = true,
    },
}

-- 矿石 id → def 快速查找
MC.oreMap = {}
for _, o in ipairs(MC.ores) do
    MC.oreMap[o.id] = o
end

-- ============================================================================
-- 矿石分布权重（基础 / 高级）
-- 高级权重在采矿场等级 ≥ 3 时使用
-- ============================================================================

MC.ORE_WEIGHTS_BASIC = {
    { id = "empty",    weight = 40 },
    { id = "copper",   weight = 22 },
    { id = "iron",     weight = 16 },
    { id = "gold",     weight = 10 },
    { id = "gem",      weight = 4 },
    { id = "fossil",   weight = 4 },
    { id = "collapse", weight = 4 },
}

MC.ORE_WEIGHTS_ADVANCED = {
    { id = "empty",    weight = 32 },
    { id = "copper",   weight = 20 },
    { id = "iron",     weight = 18 },
    { id = "gold",     weight = 13 },
    { id = "gem",      weight = 7 },
    { id = "fossil",   weight = 6 },
    { id = "collapse", weight = 4 },
}

--- 获取当前矿石权重表
---@param mineLevel number 采矿场建筑等级
---@return table weights
function MC.GetOreWeights(mineLevel)
    if mineLevel >= 3 then
        return MC.ORE_WEIGHTS_ADVANCED
    end
    return MC.ORE_WEIGHTS_BASIC
end

-- ============================================================================
-- 镐头耐久
-- ============================================================================

MC.PICK_BASE = 4                 -- 基础耐久上限
MC.PICK_PER_MINE = 0.3           -- 每个采矿场 +0.3 耐久
MC.PICK_REGEN_INTERVAL = 300     -- 每 300 秒(5分钟)回复 1 点 —— 25分钟攒约5个，配合长周期
MC.PICK_COST_DIG = 1             -- 挖掘消耗

--- 计算最大镐头耐久
---@param mineCount number
---@return number
function MC.GetMaxPicks(mineCount)
    return MC.PICK_BASE + math.floor(mineCount * MC.PICK_PER_MINE)
end

-- ============================================================================
-- 矿区刷新
-- ============================================================================

MC.REFRESH_INTERVAL = 1500       -- 自动刷新间隔（秒）—— 25分钟，长周期高回报
MC.MANUAL_REFRESH_CPS_MUL = 200 -- 手动刷新花费 = CPS × 200（提高以匹配更高的矿石价值）

-- ============================================================================
-- 扫雷提示：价值等级映射
-- ============================================================================

MC.HINT_VALUES = {
    empty    = 0,
    copper   = 1,
    iron     = 1,
    gold     = 2,
    gem      = 3,
    fossil   = 2,
    collapse = 0,
}

-- ============================================================================
-- 特殊道具
-- ============================================================================

MC.TOOLS = {
    {
        id = "scanner",
        name = "探测仪",
        icon = "",
        iconImage = "image/道具_探测仪_20260504021455.png",
        desc = "揭示 3×3 区域提示数字（不挖开）",
        pickCost = 3,
        unlockMineCount = 20,
    },
    {
        id = "dynamite",
        name = "炸药",
        icon = "",
        iconImage = "image/道具_炸药_20260504021452.png",
        desc = "炸开十字形 5 格并收获",
        pickCost = 5,
        unlockMineCount = 40,
    },
    {
        id = "minecart",
        name = "矿车",
        icon = "",
        iconImage = "image/道具_矿车_20260504021456.png",
        desc = "每次刷新自动挖开 2 个随机格子",
        pickCost = 0,
        unlockMineCount = 60,
        passive = true,
    },
}

-- 道具 id → def
MC.toolMap = {}
for _, t in ipairs(MC.TOOLS) do
    MC.toolMap[t.id] = t
end

-- ============================================================================
-- 连击 & 全清奖励
-- ============================================================================

MC.STREAK_THRESHOLD = 3          -- 连续挖到矿石 ≥3 触发连击
MC.STREAK_MULTIPLIER = 2.0       -- 连击奖励倍数
MC.FULL_CLEAR_CPS_SECONDS = 800  -- 全清奖励 = CPS×≈13分钟 —— 与矿区自然产出持平

-- ============================================================================
-- 塌方惩罚
-- ============================================================================

MC.COLLAPSE_CPS_LOSS_SECONDS = 400  -- 损失 CPS×400秒 的金币（与矿石价值匹配）

return MC
