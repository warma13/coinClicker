-- ============================================================================
-- config/GrandmapocalypseDefs.lua
-- 工会危机系统数据定义（劳资研究链 + 阶段配置 + 地下交易效果池）
-- 金币帝国 · 现实商业主题
-- 纯数据，无游戏逻辑
-- ============================================================================

local GD = {}

-- ============================================================================
-- 阶段常量
-- ============================================================================

GD.PHASE_NONE      = 0   -- 未触发
GD.PHASE_APPEASED  = -1  -- 已安抚（临时协议生效中）
GD.PHASE_AWOKEN    = 1   -- 员工维权
GD.PHASE_DISPLEASED = 2  -- 集体谈判
GD.PHASE_ANGERED   = 3   -- 全面罢工

GD.phaseNames = {
    [GD.PHASE_NONE]      = "正常",
    [GD.PHASE_APPEASED]  = "临时协议",
    [GD.PHASE_AWOKEN]    = "员工维权",
    [GD.PHASE_DISPLEASED] = "集体谈判",
    [GD.PHASE_ANGERED]   = "全面罢工",
}

GD.phaseIcons = {
    [GD.PHASE_NONE]      = "😊",
    [GD.PHASE_APPEASED]  = "🤝",
    [GD.PHASE_AWOKEN]    = "😠",
    [GD.PHASE_DISPLEASED] = "📢",
    [GD.PHASE_ANGERED]   = "🚫",
}

GD.phaseIconImages = {
    [GD.PHASE_NONE]       = "image/icon_phase_normal_20260415012723.png",
    [GD.PHASE_APPEASED]   = "image/icon_phase_appeased_20260415012809.png",
    [GD.PHASE_AWOKEN]     = "image/icon_phase_awoken_20260415012714.png",
    [GD.PHASE_DISPLEASED] = "image/icon_phase_displeased_20260415012724.png",
    [GD.PHASE_ANGERED]    = "image/icon_phase_angered_20260415012722.png",
}

GD.phaseColors = {
    [GD.PHASE_NONE]       = { 100, 200, 100, 255 },
    [GD.PHASE_APPEASED]   = { 100, 180, 255, 255 },
    [GD.PHASE_AWOKEN]     = { 255, 200, 80, 255 },
    [GD.PHASE_DISPLEASED] = { 255, 120, 60, 255 },
    [GD.PHASE_ANGERED]    = { 255, 50, 50, 255 },
}

-- ============================================================================
-- 劳资研究链
-- 价格公式: 1e15 × 2^(n-1)
-- ============================================================================

GD.researchChain = {
    {
        id = "bingoCenter",
        name = "人力资源部",
        iconImage = "image/人力资源部_20260414103106.png",
        desc = "启用劳资研究链",
        cost = 1e15,
        productionMul = 0,
        phaseTriggered = nil,
        needGrandmas = 6,      -- 需要 6 个小作坊
        needGrandmaTypes = 7,  -- 需要解锁 7 种作坊类型
    },
    {
        id = "chocolateChips",
        name = "绩效考核制度",
        iconImage = "image/绩效考核制度_20260414103110.png",
        desc = "总产量 +1%",
        cost = 2e15,
        productionMul = 0.01,
    },
    {
        id = "cocoaBeans",
        name = "薪酬优化方案",
        iconImage = "image/薪酬优化方案_20260414103112.png",
        desc = "总产量 +2%",
        cost = 4e15,
        productionMul = 0.02,
    },
    {
        id = "ritualRollingPins",
        name = "员工福利计划",
        iconImage = "image/员工福利计划_20260414103113.png",
        desc = "小作坊效率 ×2",
        cost = 8e15,
        grandmaMultiplier = 2,
    },
    {
        id = "oneMind",
        name = "团队协作系统",
        iconImage = "image/团队协作系统_20260414103109.png",
        desc = "作坊协同增效。触发员工维权阶段",
        cost = 16e15,
        phaseTriggered = GD.PHASE_AWOKEN,
        grandmaSynergy = 0.02,
    },
    {
        id = "exoticNuts",
        name = "弹性工时制度",
        iconImage = "image/弹性工时制度_20260414103107.png",
        desc = "总产量 +4%",
        cost = 32e15,
        productionMul = 0.04,
    },
    {
        id = "communalBrainsweep",
        name = "全员动员令",
        iconImage = "image/全员动员令_20260414103108.png",
        desc = "深度协同。触发集体谈判阶段",
        cost = 64e15,
        phaseTriggered = GD.PHASE_DISPLEASED,
        grandmaSynergy = 0.02,
    },
    {
        id = "arcaneSugar",
        name = "股权激励计划",
        iconImage = "image/股权激励计划_20260414103114.png",
        desc = "总产量 +5%",
        cost = 128e15,
        productionMul = 0.05,
    },
    {
        id = "elderPact",
        name = "劳资契约",
        iconImage = "image/劳资契约_20260414103108.png",
        desc = "与电商平台协同。触发全面罢工阶段",
        cost = 256e15,
        phaseTriggered = GD.PHASE_ANGERED,
        portalSynergy = 0.05,
    },
}

-- 研究间隔（秒）：购买前一个后多久出现下一个
GD.RESEARCH_INTERVAL = 30 * 60  -- 30 分钟（原版）
-- 简化版可缩短为 60 秒方便测试
GD.RESEARCH_INTERVAL_FAST = 60

-- ============================================================================
-- 地下交易效果池（替换黄金商机的效果）
-- ============================================================================

-- 各阶段地下交易出现概率（替换正常商机的比例）
GD.wrathChance = {
    [GD.PHASE_NONE]       = 0,
    [GD.PHASE_APPEASED]   = 0,
    [GD.PHASE_AWOKEN]     = 0.34,
    [GD.PHASE_DISPLEASED] = 0.67,
    [GD.PHASE_ANGERED]    = 1.0,
}

-- 地下交易效果定义（权重用于随机抽取）
GD.wrathEffects = {
    {
        id = "lucky",
        name = "意外订单",
        icon = "🍀",
        iconImage = "image/icon_wrath_lucky_20260415012715.png",
        color = { 50, 205, 50, 255 },
        weight = 29,
        type = "instant",
    },
    {
        id = "clot",
        name = "资金冻结",
        icon = "🩸",
        iconImage = "image/icon_wrath_clot_20260415012728.png",
        color = { 180, 40, 40, 255 },
        weight = 29,
        type = "buff",
        duration = 66,
        multiplierKey = "cps",
        multiplierVal = 0.5,
    },
    {
        id = "ruin",
        name = "资产损失",
        icon = "💥",
        iconImage = "image/icon_wrath_ruin_20260415012725.png",
        color = { 255, 60, 30, 255 },
        weight = 29,
        type = "instant",
    },
    {
        id = "elderFrenzy",
        name = "工会狂潮",
        icon = "👵‍🔥",
        iconImage = "image/icon_wrath_frenzy_20260415012744.png",
        color = { 200, 50, 255, 255 },
        weight = 6,
        type = "buff",
        duration = 6,
        multiplierKey = "cps",
        multiplierVal = 666,
    },
    {
        id = "clickFrenzyWrath",
        name = "疯狂交易",
        icon = "⚡",
        iconImage = "image/icon_wrath_clickfrenzy_20260415012722.png",
        color = { 255, 215, 0, 255 },
        weight = 1,
        type = "buff",
        duration = 13,
        multiplierKey = "cpc",
        multiplierVal = 777,
    },
}

-- ============================================================================
-- 灰色渠道配置
-- ============================================================================

GD.wrinkler = {
    maxCount = 10,
    drainPercent = 0.05,
    popMultiplier = 1.1,
    spawnInterval = 60,
    spawnRateMul = {
        [GD.PHASE_NONE]       = 0,
        [GD.PHASE_APPEASED]   = 0,
        [GD.PHASE_AWOKEN]     = 1,
        [GD.PHASE_DISPLEASED] = 2,
        [GD.PHASE_ANGERED]    = 3,
    },
}

-- ============================================================================
-- 临时协议（原 Elder Pledge）
-- ============================================================================

GD.elderPledge = {
    baseCost = 64,
    costMul = 8,
    maxCostPower = 14,
    duration = 30 * 60,
    durationExtended = 60 * 60,
    unlockAfterPurchases = 10,
}

--- 计算临时协议当前价格
---@param purchaseCount number 已购买次数
---@return number
function GD.GetPledgeCost(purchaseCount)
    local power = math.min(purchaseCount, GD.elderPledge.maxCostPower)
    local GameState = require("core.GameState")
    return GameState.SafeFloor(GD.elderPledge.baseCost * (GD.elderPledge.costMul ^ power))
end

return GD
