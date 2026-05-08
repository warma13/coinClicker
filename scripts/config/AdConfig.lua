-- ============================================================================
-- config/AdConfig.lua
-- 广告系统配置表
-- ============================================================================

local AdConfig = {}

-- ============================================================================
-- 基础参数
-- ============================================================================

--- 每日看满多少次激活"免广卡"（当天后续广告自动跳过）
AdConfig.AD_FREE_THRESHOLD = 20

--- 每天看满多少次算"有效天"（用于连续天数统计）
AdConfig.DAILY_EFFECTIVE_MIN = 3

-- ============================================================================
-- 里程碑奖励（7 档）
-- ============================================================================
-- reward.type:
--   "coins"  → 金币奖励, cpsSec = CPS × 秒数
--   "item"   → 仓库道具, id = 道具ID, n = 数量
AdConfig.MILESTONES = {
    {
        count   = 3,
        label   = "5 分钟产出",
        rewards = { { type = "coins", cpsSec = 300 } },
    },
    {
        count   = 6,
        label   = "瞬息胶囊",
        rewards = { { type = "item", id = "flash_capsule", n = 1 } },
    },
    {
        count   = 9,
        label   = "30 分钟产出",
        rewards = { { type = "coins", cpsSec = 1800 } },
    },
    {
        count   = 12,
        label   = "双倍药水 x2",
        rewards = { { type = "item", id = "double_potion", n = 2 } },
    },
    {
        count   = 15,
        label   = "1 小时产出 + 齿轮",
        rewards = {
            { type = "coins", cpsSec = 3600 },
            { type = "item", id = "speed_gear", n = 1 },
        },
    },
    {
        count   = 18,
        label   = "时光沙漏",
        rewards = { { type = "item", id = "time_hourglass", n = 1 } },
    },
    {
        count   = 20,
        label   = "2 小时产出 + 幸运符 x2",
        rewards = {
            { type = "coins", cpsSec = 7200 },
            { type = "item", id = "lucky_charm", n = 2 },
        },
    },
}

-- ============================================================================
-- 连续天数加速
-- ============================================================================
-- 按连续有效天数查表，返回离线加速小时数
AdConfig.STREAK_TIERS = {
    { days = 7, hours = 5 },
    { days = 3, hours = 3 },
    { days = 1, hours = 2 },
}

--- 无连续天数时的保底小时数
AdConfig.STREAK_BASE_HOURS = 1

--- 中断后每天衰减的小时数
AdConfig.STREAK_DECAY_PER_DAY = 1

return AdConfig
