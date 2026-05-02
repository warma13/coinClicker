-- ============================================================================
-- config/DragonDefs.lua
-- AI 合伙人系统数据定义（K1）
-- AI 等级、策略模块、迭代训练成本、AI 洞察
-- 金币帝国 · 现实商业主题
-- 纯数据，无游戏逻辑
-- ============================================================================

local Buildings = require("config.Buildings")

local DD = {}

-- ============================================================================
-- AI 等级定义
-- ============================================================================
DD.MAX_LEVEL = 24

--- AI 等级阶段
DD.levels = {
    -- 原型机阶段（资金投入）
    { level = 0,  name = "AI 原型机",       phase = "egg",     costType = "cookie", cost = 25,        desc = "购买 AI 硬件基础设施",       iconImage = "image/icon_ai_prototype.png" },
    { level = 1,  name = "安装系统",         phase = "hatch",   costType = "cookie", cost = 1e6,       desc = "投入资金安装基础系统",       iconImage = "image/icon_ai_prototype.png" },
    { level = 2,  name = "加载数据",         phase = "hatch",   costType = "cookie", cost = 2e6,       desc = "导入商业数据集",             iconImage = "image/icon_ai_prototype.png" },
    { level = 3,  name = "训练模型",         phase = "hatch",   costType = "cookie", cost = 4e6,       desc = "初步模型训练",               iconImage = "image/icon_ai_prototype.png" },
    { level = 4,  name = "上线运行！",        phase = "hatch",   costType = "cookie", cost = 8e6,       desc = "AI 系统正式上线",            iconImage = "image/icon_ai_robot.png" },
    -- 迭代训练阶段（用产业数据训练）
    { level = 5,  name = "基础优化",          phase = "train",   costType = "cookie", cost = 16e6,      desc = "基础商业策略优化",                auraUnlock = "breathOfMilk",   iconImage = "image/icon_ai_robot.png" },
    { level = 6,  name = "劳务分析",          phase = "train",   costType = "building", buildIdx = 1, need = 100, desc = "分析 100 个临时工数据",   auraUnlock = "dragonCursor",    iconImage = "image/icon_ai_robot.png" },
    { level = 7,  name = "作坊优化",          phase = "train",   costType = "building", buildIdx = 2, need = 100, desc = "分析 100 个小作坊数据",   auraUnlock = "elderBattalion", iconImage = "image/icon_ai_robot.png" },
    { level = 8,  name = "农业智能",          phase = "train",   costType = "building", buildIdx = 3, need = 100, desc = "分析 100 个种植园数据",   auraUnlock = "reaperOfFields", iconImage = "image/icon_ai_robot.png" },
    { level = 9,  name = "矿业优化",          phase = "train",   costType = "building", buildIdx = 4, need = 100, desc = "分析 100 个采矿场数据",   auraUnlock = "earthShatterer", iconImage = "image/icon_ai_robot.png" },
    { level = 10, name = "制造分析",          phase = "train",   costType = "building", buildIdx = 5, need = 100, desc = "分析 100 个工厂数据",     auraUnlock = "masterArmory",   iconImage = "image/icon_ai_robot.png" },
    { level = 11, name = "金融建模",          phase = "train",   costType = "building", buildIdx = 6, need = 100, desc = "分析 100 个银行数据",     auraUnlock = "fierceHoarder",  iconImage = "image/icon_ai_robot.png" },
    { level = 12, name = "地产估值",          phase = "train",   costType = "building", buildIdx = 7, need = 100, desc = "分析 100 个地产数据",     auraUnlock = "dragonGod",      iconImage = "image/icon_ai_robot.png" },
    { level = 13, name = "技术预测",          phase = "train",   costType = "building", buildIdx = 8, need = 100, desc = "分析 100 个研发中心数据", auraUnlock = "arcaneAura",     iconImage = "image/icon_ai_robot.png" },
    { level = 14, name = "物流优化",          phase = "train",   costType = "building", buildIdx = 9, need = 100, desc = "分析 100 个物流数据",     auraUnlock = "dragonflight",   iconImage = "image/icon_ai_robot.png" },
    { level = 15, name = "能源规划",          phase = "train",   costType = "building", buildIdx = 10, need = 100, desc = "分析 100 个能源数据",    auraUnlock = "ancestralMeta",  iconImage = "image/icon_ai_robot.png" },
    { level = 16, name = "电商算法",          phase = "train",   costType = "building", buildIdx = 11, need = 100, desc = "分析 100 个电商数据",    auraUnlock = "unholyDominion", iconImage = "image/icon_ai_robot.png" },
    { level = 17, name = "期货预测",          phase = "train",   costType = "building", buildIdx = 12, need = 100, desc = "分析 100 个交易所数据",  auraUnlock = "epochManip",     iconImage = "image/icon_ai_robot.png" },
    { level = 18, name = "核能调度",          phase = "train",   costType = "building", buildIdx = 13, need = 100, desc = "分析 100 个核能数据",    auraUnlock = "radiantAppetite",iconImage = "image/icon_ai_robot.png" },
    -- 后续等级用资金训练
    { level = 19, name = "深度学习",          phase = "train",   costType = "cookie", cost = 100e6,    desc = "高级深度学习训练",                 auraUnlock = "dragonFortune",  iconImage = "image/icon_ai_robot.png" },
    { level = 20, name = "神经进化",          phase = "train",   costType = "cookie", cost = 500e6,    desc = "神经网络自主进化",                 auraUnlock = "dragonCurve",    iconImage = "image/icon_ai_robot.png" },
    -- 终极阶段
    { level = 21, name = "全产业整合",        phase = "final",   costType = "building_all", need = 50,  desc = "整合 50 个各类产业数据",          auraUnlock = "dragonCookie",   iconImage = "image/icon_ai_robot.png" },
    { level = 22, name = "副策略训练",        phase = "final",   costType = "building_all", need = 200, desc = "整合 200 个各类产业数据",         secondSlot = true,             iconImage = "image/icon_ai_robot.png" },
    -- AI 洞察（点击 AI 触发）
    { level = 23, name = "启发灵感",          phase = "drops",   costType = "cookie", cost = 1e9,       desc = "解锁 AI 洞察",                iconImage = "image/icon_ai_brain.png" },
    { level = 24, name = "通用商业智能",      phase = "complete", costType = "none",                     desc = "K1 已成为通用商业智能！",     iconImage = "image/icon_ai_brain.png" },
}

--- 获取当前等级定义
---@param level number
---@return table|nil
function DD.GetLevel(level)
    for _, l in ipairs(DD.levels) do
        if l.level == level then return l end
    end
    return nil
end

-- ============================================================================
-- AI 策略模块定义
-- ============================================================================
DD.auras = {
    { id = "breathOfMilk",    name = "员工增效",        desc = "管理顾问效果 +5%",              kittenBonus = 0.05,        iconImage = "image/icon_chart.png" },
    { id = "dragonCursor",    name = "自动化点击",      desc = "点击效果 +5%",                  clickBonus = 0.05,         iconImage = "image/icon_auto_click.png" },
    { id = "elderBattalion",  name = "作坊联盟",        desc = "每个非作坊产业给作坊 +1% CpS",   grandmaSynergy = true,     iconImage = "image/icon_factory_alliance.png" },
    { id = "reaperOfFields",  name = "农业AI",          desc = "商机可触发丰收模式",             dragonHarvest = true,      iconImage = "image/icon_agri_ai.png" },
    { id = "earthShatterer",  name = "成本压缩",        desc = "产业费用 -2%",                  costReduction = 0.02,      iconImage = "image/icon_cost_reduce.png" },
    { id = "masterArmory",    name = "采购优化",        desc = "升级费用 -2%",                  upgradeCostReduction = 0.02, iconImage = "image/icon_purchase_opt.png" },
    { id = "fierceHoarder",   name = "资金管理",        desc = "产业费用 -2%",                  costReduction = 0.02,      iconImage = "image/icon_fund_manage.png" },
    { id = "dragonGod",       name = "品牌溢价",        desc = "声望 CpS 加成 +5%",             prestigeBonus = 0.05,      iconImage = "image/icon_brand_premium.png" },
    { id = "arcaneAura",      name = "市场预判",        desc = "商机频率 +5%",                  luckyFreqMul = 1.05,       iconImage = "image/icon_market_predict.png" },
    { id = "dragonflight",    name = "量化风暴",        desc = "商机可触发量化风暴",             dragonflightBuff = true,   iconImage = "image/icon_quant_storm.png" },
    { id = "ancestralMeta",   name = "数据挖掘",        desc = "商机奖励 +10%",                 luckyRewardMul = 1.10,     iconImage = "image/icon_data_mining.png" },
    { id = "unholyDominion",  name = "趋势追踪",        desc = "商机效果持续 +5%",               luckyDurMul = 1.05,        iconImage = "image/icon_trend_track.png" },
    { id = "epochManip",      name = "时间套利",         desc = "商机频率 +5% 且持续 +5%",       luckyFreqMul = 1.05, luckyDurMul = 1.05, iconImage = "image/icon_time_arb.png" },
    { id = "radiantAppetite", name = "全局优化",         desc = "所有产量 ×2",                   productionMul = 2.0,       iconImage = "image/icon_global_opt.png" },
    { id = "dragonFortune",   name = "风险评估",         desc = "+3% CpS",                      cpsMul = 0.03,             iconImage = "image/icon_risk_eval.png" },
    { id = "dragonCurve",     name = "人脉加速",         desc = "人脉成熟速度 +5%",              sugarBonus = 0.05,         iconImage = "image/icon_network_accel.png" },
    { id = "dragonCookie",    name = "商业直觉",         desc = "+5% CpS",                      cpsMul = 0.05,             iconImage = "image/icon_biz_instinct.png" },
}

--- 按 id 查找策略模块
---@param auraId string
---@return table|nil
function DD.FindAura(auraId)
    for _, a in ipairs(DD.auras) do
        if a.id == auraId then return a end
    end
    return nil
end

-- ============================================================================
-- AI 洞察
-- ============================================================================
DD.drops = {
    { id = "dragonScale",     name = "市场报告",     desc = "产量 +3%",           cpsMul = 0.03,          iconImage = "image/icon_market_report.png" },
    { id = "dragonClaw",      name = "行业密码",     desc = "点击 +3%",           clickBonus = 0.03,      iconImage = "image/icon_industry_key.png" },
    { id = "dragonFang",      name = "创新方案",     desc = "商机奖励 +3%",       luckyRewardMul = 1.03,  iconImage = "image/icon_innovation.png" },
    { id = "dragonTeddy",     name = "精准预测",     desc = "随机掉落率 +3%",     dropBonus = 0.03,       iconImage = "image/icon_precision.png" },
}

DD.DROP_CHANCE = 0.05
DD.DROP_ROTATE_INTERVAL = 900

-- ============================================================================
-- 丰收模式 / 量化风暴 Buff 参数
-- ============================================================================
DD.DRAGON_HARVEST_MUL = 15
DD.DRAGON_HARVEST_DUR = 60
DD.DRAGONFLIGHT_MUL = 1111
DD.DRAGONFLIGHT_DUR = 10

return DD
