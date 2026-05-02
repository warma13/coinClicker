-- ============================================================================
-- config/KittenUpgrades.lua
-- 管理顾问升级定义（管理经验 → CpS 加成）
-- 金币帝国 · 现实商业主题
-- 每个管理顾问升级的效果: CpS × (1 + milkFactor × milkDecimal)
-- 多个管理顾问升级之间乘法叠加
-- ============================================================================

local KittenUpgrades = {}

--- 管理顾问升级列表（按解锁顺序）
KittenUpgrades.upgrades = {
    -- 第一阶段：基础顾问
    {
        id = "kitten_helpers",
        name = "初级顾问",
        icon = "👔",
        desc = "每1%管理经验增加0.1%产出",
        milkFactor = 0.10,
        baseCost = 9e6,
        needAchievements = 1,
        bought = false,
    },
    {
        id = "kitten_workers",
        name = "运营顾问",
        icon = "👔",
        desc = "每1%管理经验增加0.125%产出",
        milkFactor = 0.125,
        baseCost = 9e8,
        needAchievements = 25,
        bought = false,
    },
    {
        id = "kitten_engineers",
        name = "技术顾问",
        icon = "👔",
        desc = "每1%管理经验增加0.15%产出",
        milkFactor = 0.15,
        baseCost = 9e11,
        needAchievements = 50,
        bought = false,
    },
    {
        id = "kitten_overseers",
        name = "战略顾问",
        icon = "👔",
        desc = "每1%管理经验增加0.175%产出",
        milkFactor = 0.175,
        baseCost = 9e14,
        needAchievements = 75,
        bought = false,
    },
    {
        id = "kitten_managers",
        name = "麦肯锡顾问",
        icon = "👔",
        desc = "每1%管理经验增加0.2%产出",
        milkFactor = 0.20,
        baseCost = 9e17,
        needAchievements = 100,
        bought = false,
    },
    -- 第二阶段：高级顾问
    {
        id = "kitten_accountants",
        name = "高盛分析师",
        icon = "💼",
        desc = "每1%管理经验增加0.2%产出",
        milkFactor = 0.20,
        baseCost = 9e20,
        needAchievements = 125,
        bought = false,
    },
    {
        id = "kitten_specialists",
        name = "行业专家",
        icon = "💼",
        desc = "每1%管理经验增加0.2%产出",
        milkFactor = 0.20,
        baseCost = 9e23,
        needAchievements = 150,
        bought = false,
    },
    {
        id = "kitten_experts",
        name = "资深合伙人",
        icon = "💼",
        desc = "每1%管理经验增加0.2%产出",
        milkFactor = 0.20,
        baseCost = 9e26,
        needAchievements = 175,
        bought = false,
    },
    {
        id = "kitten_consultants",
        name = "首席顾问",
        icon = "💼",
        desc = "每1%管理经验增加0.2%产出",
        milkFactor = 0.20,
        baseCost = 9e29,
        needAchievements = 200,
        bought = false,
    },
    -- 第三阶段：顶级顾问
    {
        id = "kitten_assistants",
        name = "区域总监",
        icon = "🏆",
        desc = "每1%管理经验增加0.175%产出",
        milkFactor = 0.175,
        baseCost = 9e32,
        needAchievements = 225,
        bought = false,
    },
    {
        id = "kitten_marketeers",
        name = "市场操盘手",
        icon = "🏆",
        desc = "每1%管理经验增加0.15%产出",
        milkFactor = 0.15,
        baseCost = 9e35,
        needAchievements = 250,
        bought = false,
    },
    {
        id = "kitten_analysts",
        name = "量化分析师",
        icon = "🏆",
        desc = "每1%管理经验增加0.125%产出",
        milkFactor = 0.125,
        baseCost = 9e38,
        needAchievements = 300,
        bought = false,
    },
    {
        id = "kitten_executives",
        name = "集团CEO",
        icon = "🏆",
        desc = "每1%管理经验增加0.115%产出",
        milkFactor = 0.115,
        baseCost = 9e41,
        needAchievements = 350,
        bought = false,
    },
    {
        id = "kitten_angels",
        name = "天使投资人",
        icon = "👼",
        desc = "每1%管理经验增加0.1%产出",
        milkFactor = 0.10,
        baseCost = 9e44,
        needAchievements = 400,
        bought = false,
    },
    {
        id = "kitten_wages",
        name = "财富之神",
        icon = "👼",
        desc = "每1%管理经验增加0.1%产出",
        milkFactor = 0.10,
        baseCost = 9e47,
        needAchievements = 450,
        bought = false,
    },
}

--- 判断管理顾问升级是否可见（已解锁且未购买）
---@param upgrade table
---@param achievementCount number 当前里程碑数
---@return boolean
function KittenUpgrades.IsVisible(upgrade, achievementCount)
    if upgrade.bought then return false end
    return achievementCount >= upgrade.needAchievements
end

--- 计算所有已聘用管理顾问的总 CpS 倍率
---@param milkDecimal number 管理经验小数（如 200% = 2.0）
---@return number 总倍率
function KittenUpgrades.GetMultiplier(milkDecimal)
    local mul = 1
    for _, u in ipairs(KittenUpgrades.upgrades) do
        if u.bought then
            mul = mul * (1 + u.milkFactor * milkDecimal)
        end
    end
    return mul
end

return KittenUpgrades
