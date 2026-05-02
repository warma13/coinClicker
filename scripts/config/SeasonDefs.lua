-- ============================================================================
-- config/SeasonDefs.lua
-- 市场周期系统数据定义（周期、收集品、市场信心、风投快车）
-- 金币帝国 · 现实商业主题
-- 纯数据，无游戏逻辑
-- ============================================================================

local SD = {}

-- ============================================================================
-- 市场周期 ID
-- ============================================================================
SD.SEASON_NONE      = "none"
SD.SEASON_CHRISTMAS = "christmas"    -- 牛市
SD.SEASON_HALLOWEEN = "halloween"    -- 熊市
SD.SEASON_EASTER    = "easter"       -- 创新潮
SD.SEASON_VALENTINE = "valentine"    -- 合作季
SD.SEASON_BUSINESS  = "business"     -- 清仓促销（商业日）

-- ============================================================================
-- 市场周期定义
-- ============================================================================
SD.seasons = {
    {
        id = SD.SEASON_VALENTINE,
        name = "合作季",
        icon = "🤝",
        iconImage = "image/周期_合作季.png",
        desc = "按累计金币自动解锁合作协议(7种，各+2% CpS)",
        switchCookie = "Lovesick biscuit",
        startMonth = 2, startDay = 10,
        endMonth   = 2, endDay   = 15,
    },
    {
        id = SD.SEASON_EASTER,
        name = "创新潮",
        icon = "💡",
        iconImage = "image/周期_创新潮.png",
        desc = "点击黄金商机/清除灰色渠道获取专利技术(20种，含特殊效果)",
        switchCookie = "Bunny biscuit",
        startMonth = 3, startDay = 25,
        endMonth   = 4, endDay   = 15,
    },
    {
        id = SD.SEASON_BUSINESS,
        name = "清仓促销",
        icon = "📋",
        iconImage = "image/周期_清仓促销.png",
        desc = "黄金商机可触发清仓大促，所有产业价格-5%(8秒)",
        switchCookie = "Fool's biscuit",
        startMonth = 3, startDay = 31,
        endMonth   = 4, endDay   = 2,
    },
    {
        id = SD.SEASON_HALLOWEEN,
        name = "熊市",
        icon = "📉",
        iconImage = "image/周期_熊市.png",
        desc = "清除灰色渠道掉落不良资产(7种，各+2% CpS)",
        switchCookie = "Ghostly biscuit",
        startMonth = 10, startDay = 24,
        endMonth   = 10, endDay   = 31,
    },
    {
        id = SD.SEASON_CHRISTMAS,
        name = "牛市",
        icon = "📈",
        iconImage = "image/周期_牛市.png",
        desc = "升级市场信心解锁强力加成，风投快车掉落分红收益(7种，各+2% CpS)",
        switchCookie = "Festive biscuit",
        startMonth = 12, startDay = 15,
        endMonth   = 12, endDay   = 31,
    },
}

--- 按 id 查找市场周期
---@param id string
---@return table|nil
function SD.FindSeason(id)
    for _, s in ipairs(SD.seasons) do
        if s.id == id then return s end
    end
    return nil
end

-- ============================================================================
-- 手动切换
-- ============================================================================
SD.MANUAL_SWITCH_DURATION = 24 * 60 * 60   -- 24 小时

--- 切换价格 = SWITCH_BASE_COST + CpS × 60 × 1.5^n （n = 已购买切换次数）
SD.SWITCH_BASE_COST = 1e9

-- ============================================================================
-- 市场信心指数（0-14，共 15 级）
-- ============================================================================
SD.SANTA_MAX_LEVEL = 14

--- 市场信心升级价格：2525 × 3^level
---@param level number 当前等级 (0-14)
---@return number
function SD.GetSantaUpgradeCost(level)
    return math.floor(2525 * (3 ^ level))
end

SD.santaNames = {
    [0]  = "市场调研",
    [1]  = "行业分析报告",
    [2]  = "初步商业计划",
    [3]  = "种子轮融资",
    [4]  = "天使轮融资",
    [5]  = "A轮融资",
    [6]  = "B轮融资",
    [7]  = "C轮融资",
    [8]  = "Pre-IPO",
    [9]  = "IPO上市",
    [10] = "蓝筹企业",
    [11] = "行业龙头",
    [12] = "市值千亿",
    [13] = "全球500强",
    [14] = "市场之王",
}

-- ============================================================================
-- 牛市升级（每升一级市场信心随机解锁一个）
-- ============================================================================
SD.christmasUpgrades = {
    { id = "xmas_merriness",    name = "市场乐观情绪",      icon = "image/icon_xmas_merriness.png",  desc = "产量 +15%",            cpsMul = 0.15 },
    { id = "xmas_jolliness",    name = "消费信心指数上升",   icon = "image/icon_xmas_jolliness.png",  desc = "产量 +15%",            cpsMul = 0.15 },
    { id = "xmas_coal",         name = "大宗商品期货",       icon = "image/icon_xmas_coal.png",       desc = "产量 +1%",             cpsMul = 0.01 },
    { id = "xmas_sweater",      name = "日用品分红",        icon = "image/icon_xmas_sweater.png",    desc = "产量 +1%",             cpsMul = 0.01 },
    { id = "xmas_reindeer",     name = "风投活跃度提升",     icon = "image/icon_xmas_reindeer.png",   desc = "风投快车出现频率 ×2",    reindeerFreqMul = 2 },
    { id = "xmas_sleighs",      name = "投资窗口延长",       icon = "image/icon_xmas_sleighs.png",    desc = "风投快车停留时间 ×2",    reindeerStayMul = 2 },
    { id = "xmas_hohoho",       name = "风投估值倍增",       icon = "image/icon_xmas_hohoho.png",     desc = "风投快车奖励 ×2",        reindeerRewardMul = 2 },
    { id = "xmas_helpers",      name = "私募顾问团",         icon = "image/icon_xmas_helpers.png",    desc = "点击力量 +10%",         clickBonus = 0.10 },
    { id = "xmas_legacy",       name = "市场信心传承",       icon = "image/icon_xmas_legacy.png",     desc = "每市场信心等级 +3% CpS", santaLevelBonus = 0.03 },
    { id = "xmas_milk",         name = "管理效率优化",       icon = "image/icon_xmas_milk.png",       desc = "管理顾问效果 +5%",      kittenBonus = 0.05 },
    { id = "xmas_bag",          name = "渠道拓展基金",       icon = "image/icon_xmas_bag.png",        desc = "收集品掉落率提升",       dropBoost = true },
    { id = "xmas_naughty",      name = "供应商黑名单",       icon = "image/icon_xmas_naughty.png",    desc = "小作坊效率 ×2",         grandmaMul = 2 },
    { id = "xmas_workshop",     name = "供应链优化",         icon = "image/icon_xmas_workshop.png",   desc = "升级/产业 -5% 费用",    costReduction = 0.05 },
    { id = "xmas_dominion",     name = "市场垄断红利",       icon = "image/icon_xmas_dominion.png",   desc = "+20% CpS（市场之王专属）", cpsMul = 0.20, needFinalClaus = true },
}

-- ============================================================================
-- 牛市分红（风投快车掉落，每个 +2% CpS）
-- ============================================================================
SD.christmasCookies = {
    { id = "xc_tree",      name = "蓝筹股分红",      icon = "image/icon_xc_tree.png",      cpsMul = 0.02 },
    { id = "xc_snowflake", name = "优先股收益",       icon = "image/icon_xc_snowflake.png", cpsMul = 0.02 },
    { id = "xc_snowman",   name = "信托收益",         icon = "image/icon_xc_snowman.png",   cpsMul = 0.02 },
    { id = "xc_holly",     name = "ETF定投回报",      icon = "image/icon_xc_holly.png",     cpsMul = 0.02 },
    { id = "xc_candy",     name = "国债利息",          icon = "image/icon_xc_candy.png",     cpsMul = 0.02 },
    { id = "xc_bell",      name = "上市敲钟奖金",     icon = "image/icon_xc_bell.png",      cpsMul = 0.02 },
    { id = "xc_present",   name = "年终奖金",         icon = "image/icon_xc_present.png",   cpsMul = 0.02 },
}

-- ============================================================================
-- 不良资产（灰色渠道清算掉落，每个 +2% CpS）
-- ============================================================================
SD.halloweenCookies = {
    { id = "hw_skull",   name = "破产企业资产",   cpsMul = 0.02, icon = "image/icon_hw_skull_20260415020858.png" },
    { id = "hw_ghost",   name = "壳公司收购",     cpsMul = 0.02, icon = "image/icon_hw_ghost_20260415020855.png" },
    { id = "hw_bat",     name = "不良债权包",     cpsMul = 0.02, icon = "image/icon_hw_bat_20260415020856.png" },
    { id = "hw_slime",   name = "清仓打折股",     cpsMul = 0.02, icon = "image/icon_hw_slime_20260415020901.png" },
    { id = "hw_pumpkin", name = "法拍地产",       cpsMul = 0.02, icon = "image/icon_hw_pumpkin_20260415020900.png" },
    { id = "hw_eyeball", name = "内幕交易利润",   cpsMul = 0.02, icon = "image/icon_hw_eyeball_20260415020858.png" },
    { id = "hw_spider",  name = "黑市套汇",      cpsMul = 0.02, icon = "image/icon_hw_spider_20260415020857.png" },
}

--- 不良资产掉落率
SD.HALLOWEEN_DROP_BASE = 0.05
SD.HALLOWEEN_DROP_BOOSTED = 0.20

-- ============================================================================
-- 专利技术（商机/灰色渠道掉落）
-- ============================================================================

--- 普通专利（12 种，每个 +1% CpS）
SD.easterEggsNormal = {
    { id = "egg_chicken",  name = "通信专利",      cpsMul = 0.01, icon = "image/icon_egg_chicken_20260415021607.png" },
    { id = "egg_duck",     name = "电池技术专利",   cpsMul = 0.01, icon = "image/icon_egg_duck_20260415021556.png" },
    { id = "egg_turkey",   name = "生物制药专利",   cpsMul = 0.01, icon = "image/icon_egg_turkey_20260415021554.png" },
    { id = "egg_quail",    name = "机器人技术专利", cpsMul = 0.01, icon = "image/icon_egg_quail_20260415021553.png" },
    { id = "egg_robin",    name = "绿色能源专利",   cpsMul = 0.01, icon = "image/icon_egg_robin_20260415021602.png" },
    { id = "egg_ostrich",  name = "卫星通信专利",   cpsMul = 0.01, icon = "image/icon_egg_ostrich_20260415021559.png" },
    { id = "egg_salmon",   name = "新材料专利",     cpsMul = 0.01, icon = "image/icon_egg_salmon_20260415021606.png" },
    { id = "egg_frog",     name = "医疗器械专利",    cpsMul = 0.01, icon = "image/icon_egg_frog_20260415021804.png" },
    { id = "egg_shark",    name = "自动驾驶专利",    cpsMul = 0.01, icon = "image/icon_egg_shark_20260415021601.png" },
    { id = "egg_turtle",   name = "建筑工艺专利",   cpsMul = 0.01, icon = "image/icon_egg_turtle_20260415021556.png" },
    { id = "egg_ant",      name = "物联网专利",      cpsMul = 0.01, icon = "image/icon_egg_ant_20260415022421.png" },
    { id = "egg_casso",    name = "游戏引擎专利",    cpsMul = 0.01, icon = "image/icon_egg_casso_20260415022440.png" },
}

--- 核心技术（8 种，特殊效果）
SD.easterEggsRare = {
    { id = "egg_golden",    name = "商机感知算法",      desc = "黄金商机频率 +5%",      luckyFreqMul = 1.05, icon = "image/icon_egg_golden_20260415022422.png" },
    { id = "egg_faberge",   name = "成本优化AI",        desc = "产业/升级 -1% 费用",    costReduction = 0.01, icon = "image/icon_egg_faberge_20260415022413.png" },
    { id = "egg_wrinkler",  name = "灰色渠道优化",      desc = "灰色渠道清算 +5%",      wrinklerBonus = 0.05, icon = "image/icon_egg_wrinkler_20260415022419.png" },
    { id = "egg_cookie",    name = "自动化点击工具",     desc = "点击 +10%",             clickBonus = 0.10, icon = "image/icon_egg_cookie_20260415022530.png" },
    { id = "egg_omelette",  name = "研发加速器",        desc = "其他专利出现 +10%",     eggDropBonus = 0.10, icon = "image/icon_egg_omelette_20260415022523.png" },
    { id = "egg_century",   name = "百年老字号配方",    desc = "CpS 随时间递增（最大 +10%）", centuryEgg = true, maxBonus = 0.10, icon = "image/icon_egg_century_20260415022524.png" },
    { id = "egg_chocolate", name = "现金回购计划",      desc = "获得银行余额 5%",       chocolateEgg = true, icon = "image/icon_egg_chocolate_20260415022706.png" },
    { id = "egg_egg",       name = "营业执照",          desc = "固定 +9 CpS",           fixedCps = 9, icon = "image/icon_egg_egg_20260415022525.png" },
}

--- 核心技术概率
SD.RARE_EGG_CHANCE = 0.10

--- 专利掉落率（商机 10%，灰色渠道 2%）
SD.EGG_DROP_LUCKY = 0.10
SD.EGG_DROP_WRINKLER = 0.02

-- ============================================================================
-- 合作协议（按营业额顺序解锁，每个 +2% CpS）
-- ============================================================================
SD.valentineCookies = {
    { id = "val_pure",    name = "初步合作意向",     cpsMul = 0.02, threshold = 0,    icon = "image/icon_val_pure_20260415022813.png" },
    { id = "val_ardent",  name = "战略合作协议",     cpsMul = 0.02, threshold = 1e6,  icon = "image/icon_val_ardent_20260415022826.png" },
    { id = "val_sour",    name = "技术互授协议",     cpsMul = 0.02, threshold = 1e8,  icon = "image/icon_val_sour_20260415022833.png" },
    { id = "val_weeping", name = "独家供货协议",     cpsMul = 0.02, threshold = 1e10, icon = "image/icon_val_weeping_20260415022922.png" },
    { id = "val_golden",  name = "资本联盟协议",     cpsMul = 0.02, threshold = 1e12, icon = "image/icon_val_golden_20260415022923.png" },
    { id = "val_eternal", name = "永久合伙人协议",   cpsMul = 0.02, threshold = 1e14, icon = "image/icon_val_eternal_20260415022829.png" },
    { id = "val_prism",   name = "跨国并购协议",     cpsMul = 0.02, threshold = 1e16, icon = "image/icon_val_prism_20260415023005.png" },
}

-- ============================================================================
-- 清仓促销（商业日）特殊效果
-- ============================================================================
SD.BUSINESS_DAY_EFFECT = {
    id = "everythingMustGo",
    name = "清仓大促",
    desc = "所有产业价格 -5%",
    buildingCostMul = 0.95,    -- 产业价格乘以 0.95
    duration = 8,              -- 持续 8 秒
    weight = 5,                -- 加入黄金商机效果池的权重
}

-- ============================================================================
-- 风投快车参数
-- ============================================================================
SD.REINDEER_MIN_INTERVAL = 180
SD.REINDEER_MAX_INTERVAL = 360
SD.REINDEER_STAY_DURATION = 6
SD.REINDEER_MIN_REWARD_CPS = 60
SD.REINDEER_MIN_REWARD_FLAT = 25
SD.REINDEER_COOKIE_DROP_CHANCE = 0.20

return SD
