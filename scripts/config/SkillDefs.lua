-- ============================================================================
-- config/SkillDefs.lua
-- 技能系统数据定义 —— 全部为主动技能（看广告解锁/升级/释放，无CD）
-- ============================================================================

local SkillDefs = {}

-- ============================================================================
-- 疾速签单（主动）：极速自动点击一段时间
-- ============================================================================
SkillDefs.speedClick = {
    id       = "speedClick",
    name     = "疾速签单",
    desc     = "激活后自动签单，持续半小时",
    icon     = "image/skill_speed.png",
    maxLevel = 10,
    baseCost = 5e6,
    costMul  = 1000,
    staminaBase = 150,
    staminaPerLv = 15,
    -- 每级参数: duration=持续秒(固定1800=30分钟), rate=每秒点击次数(随等级提升)
    levels = {
        [1]  = { duration = 1800, rate = 8 },
        [2]  = { duration = 1800, rate = 9 },
        [3]  = { duration = 1800, rate = 10 },
        [4]  = { duration = 1800, rate = 12 },
        [5]  = { duration = 1800, rate = 14 },
        [6]  = { duration = 1800, rate = 16 },
        [7]  = { duration = 1800, rate = 18 },
        [8]  = { duration = 1800, rate = 20 },
        [9]  = { duration = 1800, rate = 22 },
        [10] = { duration = 1800, rate = 24 },
    },
}

-- ============================================================================
-- 高效运转（主动）：激活后 CPS 提升一段时间
-- ============================================================================
SkillDefs.cpsDouble = {
    id       = "cpsDouble",
    name     = "高效运转",
    desc     = "激活后每秒产出提升，持续半小时",
    icon     = "image/skill_cps.png",
    maxLevel = 10,
    baseCost = 2e6,
    costMul  = 1000,
    staminaBase = 100,
    staminaPerLv = 10,
    -- 每级参数: duration=持续秒(固定1800=30分钟), multiplier=CPS倍率(随等级提升)
    levels = {
        [1]  = { duration = 1800, multiplier = 1.8 },
        [2]  = { duration = 1800, multiplier = 2.2 },
        [3]  = { duration = 1800, multiplier = 2.8 },
        [4]  = { duration = 1800, multiplier = 3.4 },
        [5]  = { duration = 1800, multiplier = 4.0 },
        [6]  = { duration = 1800, multiplier = 5.0 },
        [7]  = { duration = 1800, multiplier = 6.0 },
        [8]  = { duration = 1800, multiplier = 7.0 },
        [9]  = { duration = 1800, multiplier = 8.0 },
        [10] = { duration = 1800, multiplier = 9.0 },
    },
}

-- ============================================================================
-- 点击收益增加（主动）：激活后每次点击收益翻倍一段时间
-- ============================================================================
SkillDefs.clickBoost = {
    id       = "clickBoost",
    name     = "签单加成",
    desc     = "激活后每次签单收益提升，持续半小时",
    icon     = "image/skill_crit.png",
    maxLevel = 10,
    baseCost = 3e6,
    costMul  = 1000,
    staminaBase = 120,
    staminaPerLv = 12,
    -- 每级参数: duration=持续秒(固定1800=30分钟), multiplier=点击收益倍率
    levels = {
        [1]  = { duration = 1800, multiplier = 1.8 },
        [2]  = { duration = 1800, multiplier = 2.2 },
        [3]  = { duration = 1800, multiplier = 2.8 },
        [4]  = { duration = 1800, multiplier = 3.4 },
        [5]  = { duration = 1800, multiplier = 4.0 },
        [6]  = { duration = 1800, multiplier = 5.0 },
        [7]  = { duration = 1800, multiplier = 6.0 },
        [8]  = { duration = 1800, multiplier = 7.0 },
        [9]  = { duration = 1800, multiplier = 8.0 },
        [10] = { duration = 1800, multiplier = 9.0 },
    },
}

-- ============================================================================
-- 随机扩张（即时）：立即获得三个已解锁建筑各+1
-- ============================================================================
SkillDefs.randomBuildings = {
    id       = "randomBuildings",
    name     = "随机扩张",
    desc     = "立即随机获得数个已解锁的产业+1",
    icon     = "image/skill_mass.png",
    maxLevel = 10,
    baseCost = 8e6,
    costMul  = 1000,
    staminaBase = 200,
    staminaPerLv = 20,
    instant  = true,  -- 标记为即时技能
    -- 每级参数: count=获得的建筑数量
    levels = {
        [1]  = { count = 2 },
        [2]  = { count = 2 },
        [3]  = { count = 3 },
        [4]  = { count = 3 },
        [5]  = { count = 4 },
        [6]  = { count = 5 },
        [7]  = { count = 6 },
        [8]  = { count = 7 },
        [9]  = { count = 8 },
        [10] = { count = 10 },
    },
}

-- ============================================================================
-- 立即收割（即时）：立即获取30分钟CPS收益
-- ============================================================================
SkillDefs.cpsHarvest = {
    id       = "cpsHarvest",
    name     = "立即收割",
    desc     = "立即获取数分钟的每秒产出收益",
    icon     = "image/skill_swipe.png",
    maxLevel = 10,
    baseCost = 10e6,
    costMul  = 1000,
    staminaBase = 180,
    staminaPerLv = 18,
    instant  = true,  -- 标记为即时技能
    -- 每级参数: minutes=获取多少分钟的CPS
    levels = {
        [1]  = { minutes = 5 },
        [2]  = { minutes = 7 },
        [3]  = { minutes = 10 },
        [4]  = { minutes = 14 },
        [5]  = { minutes = 18 },
        [6]  = { minutes = 24 },
        [7]  = { minutes = 32 },
        [8]  = { minutes = 40 },
        [9]  = { minutes = 50 },
        [10] = { minutes = 60 },
    },
}

-- ============================================================================
-- 技能列表（按显示顺序）
-- ============================================================================
SkillDefs.list = {
    SkillDefs.speedClick,
    SkillDefs.cpsDouble,
    SkillDefs.clickBoost,
    SkillDefs.randomBuildings,
    SkillDefs.cpsHarvest,
}

--- 计算技能当前等级的体力消耗
---@param def table 技能定义
---@param level number 当前等级（>= 1）
---@return number stamina 体力消耗
function SkillDefs.GetStaminaCost(def, level)
    if level <= 0 then return 0 end
    return def.staminaBase + def.staminaPerLv * (level - 1)
end

--- 计算技能升级费用（从当前 level 升到 level+1）
---@param def table 技能定义
---@param currentLevel number 当前等级（>= 1）
---@return number cost 升级费用（满级返回 0）
function SkillDefs.GetUpgradeCost(def, currentLevel)
    if currentLevel <= 0 or currentLevel >= def.maxLevel then return 0 end
    return math.floor(def.baseCost * (def.costMul ^ (currentLevel - 1)))
end

return SkillDefs
