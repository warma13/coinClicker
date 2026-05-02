-- ============================================================================
-- config/SugarLumpDefs.lua
-- 人脉系统数据定义（积累周期 + 类型 + 产业升级 + 人脉效应）
-- 金币帝国 · 现实商业主题
-- 纯数据，无游戏逻辑
-- ============================================================================

local SD = {}

-- ============================================================================
-- 解锁条件
-- ============================================================================

--- 累计总产出达到此值后解锁人脉系统
SD.UNLOCK_TOTAL_PRODUCED = 1e9

-- ============================================================================
-- 积累阶段
-- ============================================================================

SD.STAGE_NONE       = 0   -- 未解锁
SD.STAGE_COALESCING = 1   -- 接触中（正在积累）
SD.STAGE_MATURE     = 2   -- 熟识（可发展，50% 失败）
SD.STAGE_RIPE       = 3   -- 深交（保证成功）

SD.stageNames = {
    [SD.STAGE_NONE]       = "未解锁",
    [SD.STAGE_COALESCING] = "接触中",
    [SD.STAGE_MATURE]     = "已熟识",
    [SD.STAGE_RIPE]       = "深交",
}

SD.stageIcons = {
    [SD.STAGE_NONE]       = "⬜",
    [SD.STAGE_COALESCING] = "🫧",
    [SD.STAGE_MATURE]     = "🤝",
    [SD.STAGE_RIPE]       = "✨",
}

SD.stageColors = {
    [SD.STAGE_NONE]       = { 120, 120, 120, 255 },
    [SD.STAGE_COALESCING] = { 180, 140, 255, 255 },
    [SD.STAGE_MATURE]     = { 255, 180, 220, 255 },
    [SD.STAGE_RIPE]       = { 255, 215, 0, 255 },
}

-- ============================================================================
-- 积累时长（秒）
-- ============================================================================

--- 接触阶段时长（秒）— Cookie Clicker 原版 20 小时
SD.COALESCING_DURATION = 20 * 60 * 60

--- 熟识阶段时长（秒）— Cookie Clicker 原版 1 小时
SD.MATURE_DURATION = 1 * 60 * 60

--- 深交后自动建立时间（秒）— Cookie Clicker 原版 1 小时
SD.RIPE_DURATION = 1 * 60 * 60

--- 总积累周期
SD.TOTAL_CYCLE = SD.COALESCING_DURATION + SD.MATURE_DURATION + SD.RIPE_DURATION

-- ============================================================================
-- 人脉类型
-- ============================================================================

SD.types = {
    {
        id = "normal",
        name = "普通人脉",
        icon = "🤝",
        color = { 255, 200, 230, 255 },
        weight = 80,
        -- Cookie Clicker: 正常收获得 1；熟识阶段 50% 概率得 0；深交阶段 50% 概率额外+1
        yieldNormal = 1,
    },
    {
        id = "bifurcated",
        name = "互荐人脉",
        icon = "🔗",
        color = { 200, 150, 255, 255 },
        weight = 10,
        -- Cookie Clicker: 收获得 50/50 → 1 或 2
        yieldNormal = 1,
        yieldBonus = function()
            return math.random() < 0.5 and 1 or 0
        end,
    },
    {
        id = "golden",
        name = "黄金人脉",
        icon = "⭐",
        color = { 255, 215, 0, 255 },
        weight = 5,
        -- Cookie Clicker Golden: 收获得 2~7
        yieldNormal = 2,
        yieldBonus = function()
            return math.random(0, 5)
        end,
    },
    {
        id = "meaty",
        name = "草根人脉",
        icon = "🍖",
        color = { 200, 120, 100, 255 },
        weight = 3,
        -- Cookie Clicker Meaty: 收获得 0~2，但收获时 40% 概率触发一次黄金商机
        yieldNormal = 0,
        yieldBonus = function()
            return math.random(0, 2)
        end,
        triggerLucky = true,  -- 收获时概率触发黄金商机
        triggerLuckyChance = 0.4,
    },
    {
        id = "caramelized",
        name = "贵人人脉",
        icon = "👑",
        color = { 210, 160, 60, 255 },
        weight = 2,
        -- Cookie Clicker Caramelized: 收获得 1~3，重置冷却到熟识阶段
        yieldNormal = 1,
        yieldBonus = function()
            return math.random(0, 2)
        end,
        resetCooldown = true,
    },
}

-- ============================================================================
-- 收获计算（统一逻辑，对应 Cookie Clicker 原版）
-- ============================================================================

--- 计算某类型糖块在指定阶段的收获数量
---@param lumpType table 糖块类型定义
---@param stage number 收获时的阶段
---@return number 收获数量
function SD.CalcYield(lumpType, stage)
    local base = lumpType.yieldNormal or 1
    local bonus = 0

    if lumpType.yieldBonus then
        bonus = lumpType.yieldBonus()
    end

    -- Cookie Clicker 规则：
    -- 熟识阶段收获：50% 概率少得 1 个
    -- 深交阶段收获：50% 概率额外得 1 个
    -- 自动掉落：固定得 1 个（不受类型影响）
    if stage == SD.STAGE_MATURE then
        if math.random() < 0.5 then
            base = base - 1
        end
    elseif stage == SD.STAGE_RIPE then
        if math.random() < 0.5 then
            bonus = bonus + 1
        end
    end

    return math.max(0, base + bonus)
end

--- 按权重随机选择人脉类型
---@return table 人脉类型定义
function SD.RollType()
    local totalWeight = 0
    for _, t in ipairs(SD.types) do
        totalWeight = totalWeight + t.weight
    end
    local roll = math.random() * totalWeight
    local cumulative = 0
    for _, t in ipairs(SD.types) do
        cumulative = cumulative + t.weight
        if roll <= cumulative then
            return t
        end
    end
    return SD.types[1]
end

-- ============================================================================
-- 产业升级
-- ============================================================================

--- 升到第 N 级需要 N 条人脉
---@param level number 目标等级（当前等级 + 1）
---@return number 所需人脉数
function SD.GetUpgradeCost(level)
    return level
end

--- 每级 CpS 加成百分比
SD.LEVEL_CPS_BONUS = 0.01

--- 产业最大等级
SD.MAX_BUILDING_LEVEL = 10

-- ============================================================================
-- 人脉效应（未使用人脉加成）
-- ============================================================================

--- 每条未使用人脉的 CpS 加成百分比
SD.SUGAR_BAKING_BONUS = 0.01

--- 人脉效应最大加成数
SD.SUGAR_BAKING_CAP = 100

-- ============================================================================
-- 显示配置
-- ============================================================================

--- 人脉显示尺寸
SD.DISPLAY_SIZE = 32

return SD
