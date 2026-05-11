-- ============================================================================
-- config/OnlineRewardConfig.lua
-- 每日在线时长奖励配置表
-- ============================================================================

local OnlineRewardConfig = {}

-- ============================================================================
-- 在线时长里程碑（7 档）
-- ============================================================================
-- seconds   = 所需在线秒数
-- label     = 里程碑标签
-- rewards   = 奖励列表 { type="item", id=道具ID, n=数量 }
-- bonus     = 当日加成（领取后生效，跨天清零）
--   bonus.cpsPct   = CPS 加算百分比（如 0.02 = +2%）
--   bonus.cpcPct   = CPC 加算百分比（如 0.03 = +3%）

OnlineRewardConfig.MILESTONES = {
    {
        seconds = 60,          -- 1 分钟
        label   = "1分钟",
        rewards = { { type = "item", id = "flash_capsule", n = 1 } },
        bonus   = { cpsPct = 0.01, cpcPct = 0.01 },
    },
    {
        seconds = 180,         -- 3 分钟
        label   = "3分钟",
        rewards = { { type = "item", id = "speed_gear", n = 1 } },
        bonus   = { cpsPct = 0.02, cpcPct = 0.02 },
    },
    {
        seconds = 600,         -- 10 分钟
        label   = "10分钟",
        rewards = { { type = "item", id = "double_potion", n = 1 } },
        bonus   = { cpsPct = 0.03, cpcPct = 0.03 },
    },
    {
        seconds = 1800,        -- 30 分钟
        label   = "30分钟",
        rewards = {
            { type = "item", id = "lucky_charm", n = 1 },
            { type = "item", id = "flash_capsule", n = 1 },
        },
        bonus   = { cpsPct = 0.05, cpcPct = 0.05 },
    },
    {
        seconds = 3600,        -- 1 小时
        label   = "1小时",
        rewards = {
            { type = "item", id = "time_hourglass", n = 1 },
        },
        bonus   = { cpsPct = 0.08, cpcPct = 0.08 },
    },
    {
        seconds = 7200,        -- 2 小时
        label   = "2小时",
        rewards = {
            { type = "item", id = "double_potion", n = 1 },
            { type = "item", id = "speed_gear", n = 1 },
        },
        bonus   = { cpsPct = 0.12, cpcPct = 0.10 },
    },
    {
        seconds = 10800,       -- 3 小时
        label   = "3小时",
        rewards = {
            { type = "item", id = "collectible_box", n = 1 },
            { type = "item", id = "speed_gear", n = 1 },
            { type = "item", id = "click_storm", n = 1 },
        },
        bonus   = { cpsPct = 0.18, cpcPct = 0.15 },
    },
}

return OnlineRewardConfig
