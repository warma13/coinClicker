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
    desc     = "激活后极速自动签单半小时",
    icon     = "image/skill_speed.png",
    maxLevel = 10,
    baseCost = 10e15,
    costMul  = 8,
    staminaBase = 150,
    staminaPerLv = 15,
    -- 每级参数: duration=持续秒(固定1800=30分钟), rate=每秒点击次数(随等级提升)
    levels = {
        [1]  = { duration = 1800, rate = 10 },
        [2]  = { duration = 1800, rate = 12 },
        [3]  = { duration = 1800, rate = 14 },
        [4]  = { duration = 1800, rate = 15 },
        [5]  = { duration = 1800, rate = 15 },
        [6]  = { duration = 1800, rate = 15 },
        [7]  = { duration = 1800, rate = 15 },
        [8]  = { duration = 1800, rate = 15 },
        [9]  = { duration = 1800, rate = 15 },
        [10] = { duration = 1800, rate = 15 },
    },
}

-- ============================================================================
-- CPS翻倍（主动）：激活后 CPS 翻倍一段时间
-- ============================================================================
SkillDefs.cpsDouble = {
    id       = "cpsDouble",
    name     = "CPS翻倍",
    desc     = "激活后每秒产出翻倍，持续半小时",
    icon     = "image/skill_cps.png",
    maxLevel = 10,
    baseCost = 5e15,
    costMul  = 8,
    staminaBase = 100,
    staminaPerLv = 10,
    -- 每级参数: duration=持续秒(固定1800=30分钟), multiplier=CPS倍率(随等级提升)
    levels = {
        [1]  = { duration = 1800, multiplier = 2 },
        [2]  = { duration = 1800, multiplier = 2.5 },
        [3]  = { duration = 1800, multiplier = 3 },
        [4]  = { duration = 1800, multiplier = 3.5 },
        [5]  = { duration = 1800, multiplier = 4 },
        [6]  = { duration = 1800, multiplier = 5 },
        [7]  = { duration = 1800, multiplier = 6 },
        [8]  = { duration = 1800, multiplier = 7 },
        [9]  = { duration = 1800, multiplier = 8 },
        [10] = { duration = 1800, multiplier = 10 },
    },
}

-- ============================================================================
-- 技能列表（按显示顺序）
-- ============================================================================
SkillDefs.list = {
    SkillDefs.speedClick,
    SkillDefs.cpsDouble,
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
