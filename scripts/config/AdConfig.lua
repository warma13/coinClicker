-- ============================================================================
-- config/AdConfig.lua
-- 广告系统配置表
-- ============================================================================

local AdConfig = {}

-- ============================================================================
-- 基础参数
-- ============================================================================

--- 每日观看广告总上限
AdConfig.DAILY_LIMIT = 30

-- ============================================================================
-- 里程碑奖励（10 档，每日30次全领）
-- ============================================================================
-- reward.type:
--   "item"   → 仓库道具, id = 道具ID, n = 数量
AdConfig.MILESTONES = {
    {
        count   = 3,
        label   = "瞬息胶囊",
        rewards = { { type = "item", id = "flash_capsule", n = 1 } },
    },
    {
        count   = 6,
        label   = "加速齿轮",
        rewards = { { type = "item", id = "speed_gear", n = 1 } },
    },
    {
        count   = 9,
        label   = "双倍药水",
        rewards = { { type = "item", id = "double_potion", n = 1 } },
    },
    {
        count   = 12,
        label   = "幸运符",
        rewards = { { type = "item", id = "lucky_charm", n = 1 } },
    },
    {
        count   = 15,
        label   = "时光沙漏 + 瞬息胶囊",
        rewards = {
            { type = "item", id = "time_hourglass", n = 1 },
            { type = "item", id = "flash_capsule", n = 1 },
        },
    },
    {
        count   = 18,
        label   = "双倍药水 x2",
        rewards = { { type = "item", id = "double_potion", n = 2 } },
    },
    {
        count   = 21,
        label   = "加速齿轮 + 点击风暴",
        rewards = {
            { type = "item", id = "speed_gear", n = 1 },
            { type = "item", id = "click_storm", n = 1 },
        },
    },
    {
        count   = 24,
        label   = "幸运符 x2",
        rewards = { { type = "item", id = "lucky_charm", n = 2 } },
    },
    {
        count   = 27,
        label   = "时光沙漏 + 双倍药水",
        rewards = {
            { type = "item", id = "time_hourglass", n = 1 },
            { type = "item", id = "double_potion", n = 1 },
        },
    },
    {
        count   = 30,
        label   = "随机藏品箱 + 加速齿轮 x3",
        rewards = {
            { type = "item", id = "collectible_box", n = 1 },
            { type = "item", id = "speed_gear", n = 3 },
        },
    },
}

-- ============================================================================
-- 特权卡系统
-- ============================================================================
-- 每天看满 DAILY_LIMIT 次广告获得 1 点特权点数
-- 累积点数提升卡等级，获得永久 CPS 加成

AdConfig.PRIVILEGE_CARD = {
    -- 等级列表
    -- points    = 升级所需累积总点数
    -- cpsMul    = CPS 加成百分比
    -- cpcMul    = CPC(点击收益) 加成百分比
    -- dailyItems = 每日自动发放道具 (登录/跨天时发到仓库)
    levels = {
        { name = "铜卡",     points = 3,    cpsMul = 0.01, cpcMul = 0.02, color = { 180, 120, 60 },  glow = { 200, 140, 70 },
          dailyItems = { { id = "flash_capsule", n = 1 } } },
        { name = "银卡",     points = 10,   cpsMul = 0.03, cpcMul = 0.05, color = { 180, 190, 210 }, glow = { 200, 210, 230 },
          dailyItems = { { id = "flash_capsule", n = 2 } } },
        { name = "金卡",     points = 25,   cpsMul = 0.05, cpcMul = 0.08, color = { 255, 200, 60 },  glow = { 255, 220, 80 },
          dailyItems = { { id = "flash_capsule", n = 2 }, { id = "speed_gear", n = 1 } } },
        { name = "铂金卡",   points = 50,   cpsMul = 0.08, cpcMul = 0.12, color = { 160, 230, 255 }, glow = { 180, 240, 255 },
          dailyItems = { { id = "speed_gear", n = 2 }, { id = "double_potion", n = 1 } } },
        { name = "钻石卡",   points = 100,  cpsMul = 0.12, cpcMul = 0.18, color = { 180, 130, 255 }, glow = { 200, 150, 255 },
          dailyItems = { { id = "speed_gear", n = 2 }, { id = "double_potion", n = 1 }, { id = "lucky_charm", n = 1 } } },
        { name = "至尊卡",   points = 200,  cpsMul = 0.18, cpcMul = 0.25, color = { 255, 80, 120 },  glow = { 255, 100, 140 },
          dailyItems = { { id = "time_hourglass", n = 1 }, { id = "double_potion", n = 1 }, { id = "lucky_charm", n = 1 }, { id = "click_storm", n = 1 } } },
    },
}

return AdConfig
