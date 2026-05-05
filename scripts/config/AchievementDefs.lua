-- ============================================================================
-- config/AchievementDefs.lua
-- 里程碑定义（纯数据，不含逻辑）
-- 每个里程碑 4% 管理经验（对齐 Cookie Clicker）
-- ============================================================================

local AchievementDefs = {}

--- 管理经验常量
AchievementDefs.MILK_PER_ACHIEVEMENT = 0.04  -- 每个里程碑 4% 管理经验

--- 里程碑类别
AchievementDefs.CATEGORY = {
    PRODUCTION   = "production",    -- 营收里程碑
    BUILDING     = "building",      -- 产业规模
    CLICK        = "click",         -- 签单相关
    LUCKY        = "lucky",         -- 黄金商机
    UPGRADE      = "upgrade",       -- 升级相关
    MISC         = "misc",          -- 杂项
    LEADERBOARD  = "leaderboard",   -- 排行榜
    MINIGAME     = "minigame",      -- 小游戏
}

local C = AchievementDefs.CATEGORY

--- 品质等级定义（1~7）
--- 1=普通(灰) 2=优秀(绿) 3=稀有(蓝) 4=史诗(紫) 5=传说(橙) 6=神话(红) 7=永恒(金)
AchievementDefs.TIER_NAMES = { "普通", "优秀", "稀有", "史诗", "传说", "神话", "永恒" }
AchievementDefs.TIER_COLORS = {
    { 160, 160, 170, 200 },   -- 1 普通 灰
    { 100, 200, 100, 220 },   -- 2 优秀 绿
    { 80,  140, 255, 230 },   -- 3 稀有 蓝
    { 180, 80,  255, 240 },   -- 4 史诗 紫
    { 255, 215, 0,   250 },   -- 5 传说 金
    { 255, 165, 0,   255 },   -- 6 神话 橙
    { 255, 60,  60,  255 },   -- 7 永恒 红
}

--- 营收里程碑（按总金币产出）
local productionAchievements = {
    { id = "prod_1",       name = "起步",         icon = "🪙",  iconImage = "image/总产出金币.png", desc = "总产出达到 1 金币",            threshold = 1,    tier = 1 },
    { id = "prod_100",     name = "小有积蓄",     icon = "🪙",  iconImage = "image/总产出金币.png", desc = "总产出达到 100 金币",          threshold = 100,  tier = 1 },
    { id = "prod_1k",      name = "千金散尽",     icon = "💰",  iconImage = "image/总产出金币.png", desc = "总产出达到 1,000 金币",        threshold = 1e3,  tier = 2 },
    { id = "prod_10k",     name = "万贯家财",     icon = "💰",  iconImage = "image/总产出金币.png", desc = "总产出达到 10,000 金币",       threshold = 1e4,  tier = 2 },
    { id = "prod_100k",    name = "十万大关",     icon = "💎",  iconImage = "image/总产出金币.png", desc = "总产出达到 100,000 金币",      threshold = 1e5,  tier = 3 },
    { id = "prod_1m",      name = "百万富翁",     icon = "💎",  iconImage = "image/总产出金币.png", desc = "总产出达到 1,000,000 金币",    threshold = 1e6,  tier = 3 },
    { id = "prod_10m",     name = "千万身家",     icon = "👑",  iconImage = "image/总产出金币.png", desc = "总产出达到 10,000,000 金币",   threshold = 1e7,  tier = 4 },
    { id = "prod_100m",    name = "亿万金主",     icon = "👑",  iconImage = "image/总产出金币.png", desc = "总产出达到 100,000,000 金币",  threshold = 1e8,  tier = 4 },
    { id = "prod_1b",      name = "十亿帝国",     icon = "🏆",  iconImage = "image/总产出金币.png", desc = "总产出达到 1B 金币",           threshold = 1e9,  tier = 5 },
    { id = "prod_10b",     name = "百亿王朝",     icon = "🏆",  iconImage = "image/总产出金币.png", desc = "总产出达到 10B 金币",          threshold = 1e10, tier = 5 },
    { id = "prod_100b",    name = "千亿宇宙",     icon = "🏆",  iconImage = "image/总产出金币.png", desc = "总产出达到 100B 金币",         threshold = 1e11, tier = 6 },
    { id = "prod_1t",      name = "万亿传说",     icon = "⭐",  iconImage = "image/总产出金币.png", desc = "总产出达到 1T 金币",           threshold = 1e12, tier = 6 },
    { id = "prod_10t",     name = "十万亿神话",   icon = "⭐",  iconImage = "image/总产出金币.png", desc = "总产出达到 10T 金币",          threshold = 1e13, tier = 7 },
    { id = "prod_100t",    name = "无尽金海",     icon = "⭐",  iconImage = "image/总产出金币.png", desc = "总产出达到 100T 金币",         threshold = 1e14, tier = 7 },
    { id = "prod_1qa",     name = "金币之神",     icon = "🌟",  iconImage = "image/总产出金币.png", desc = "总产出达到 1Qa 金币",          threshold = 1e15, tier = 7 },
}

--- 产业规模里程碑（每种产业在指定数量时解锁）
--- 使用 buildingId 关联，在 AchievementManager 中根据 Buildings 动态检查
local buildingThresholds = { 1, 50, 100, 150, 200, 250, 300 }

local buildingNames = {
    { id = "cursor",     name = "临时工",     icon = "👆", iconImage = "image/临时工.png" },
    { id = "grandma",    name = "小作坊",     icon = "🏠", iconImage = "image/小作坊.png" },
    { id = "farm",       name = "种植园",     icon = "🌾", iconImage = "image/种植园.png" },
    { id = "mine",       name = "采矿场",     icon = "⛏️", iconImage = "image/采矿场.png" },
    { id = "factory",    name = "制造工厂",   icon = "🏭", iconImage = "image/制造工厂.png" },
    { id = "bank",       name = "商业银行",   icon = "🏦", iconImage = "image/商业银行.png" },
    { id = "temple",     name = "商业地产",   icon = "🏢", iconImage = "image/商业地产.png" },
    { id = "wizard",     name = "研发中心",   icon = "🔬", iconImage = "image/研发中心.png" },
    { id = "shipment",   name = "国际物流",   icon = "🚢", iconImage = "image/国际物流.png" },
    { id = "alchemy",    name = "能源集团",   icon = "⚡", iconImage = "image/能源集团.png" },
    { id = "portal",     name = "电商平台",   icon = "🛒", iconImage = "image/电商平台.png" },
    { id = "timeMachine",name = "期货交易所", icon = "📈", iconImage = "image/期货交易所.png" },
    { id = "antimatter", name = "核能电站",   icon = "⚛️", iconImage = "image/核能电站.png" },
    { id = "prism",      name = "太空采矿",   icon = "🚀", iconImage = "image/太空采矿.png" },
    { id = "chancemaker",name = "主权基金",   icon = "🏛️", iconImage = "image/主权基金.png" },
    { id = "fractal",    name = "量化交易",   icon = "📊", iconImage = "image/量化交易.png" },
    { id = "console",    name = "数字货币",   icon = "💻", iconImage = "image/数字货币.png" },
    { id = "idleverse",  name = "星际殖民",   icon = "🌌", iconImage = "image/星际殖民.png" },
    { id = "cortex",     name = "脑机接口",   icon = "🧠", iconImage = "image/脑机接口.png" },
    { id = "you",        name = "宇宙财团",   icon = "👑", iconImage = "image/宇宙财团.png" },
}

local buildingTierMap = { [1] = 1, [50] = 2, [100] = 3, [150] = 4, [200] = 5, [250] = 6, [300] = 7 }
local buildingSuffixMap = { [1] = "初次", [50] = "老手", [100] = "大师", [150] = "专家", [200] = "传奇", [250] = "神话", [300] = "永恒" }

local buildingAchievements = {}
for _, bInfo in ipairs(buildingNames) do
    for _, threshold in ipairs(buildingThresholds) do
        buildingAchievements[#buildingAchievements + 1] = {
            id = "bld_" .. bInfo.id .. "_" .. threshold,
            name = bInfo.name .. (buildingSuffixMap[threshold] or ""),
            icon = bInfo.icon,
            iconImage = bInfo.iconImage,
            desc = "拥有 " .. threshold .. " 个" .. bInfo.name,
            category = C.BUILDING,
            buildingId = bInfo.id,
            threshold = threshold,
            tier = buildingTierMap[threshold] or 1,
        }
    end
end

--- 签单里程碑
local clickAchievements = {
    { id = "click_1",      name = "第一单",       icon = "👆", iconImage = "image/临时工.png", desc = "签单 1 次",                threshold = 1,    tier = 1 },
    { id = "click_100",    name = "勤劳之手",     icon = "👆", iconImage = "image/临时工.png", desc = "签单 100 次",              threshold = 100,  tier = 1 },
    { id = "click_1k",     name = "千单破",       icon = "✊", iconImage = "image/临时工.png", desc = "签单 1,000 次",            threshold = 1e3,  tier = 2 },
    { id = "click_5k",     name = "铁腕",         icon = "✊", iconImage = "image/临时工.png", desc = "签单 5,000 次",            threshold = 5e3,  tier = 3 },
    { id = "click_10k",    name = "万单不灭",     icon = "💪", iconImage = "image/临时工.png", desc = "签单 10,000 次",           threshold = 1e4,  tier = 4 },
    { id = "click_50k",    name = "钢铁之手",     icon = "💪", iconImage = "image/临时工.png", desc = "签单 50,000 次",           threshold = 5e4,  tier = 5 },
    { id = "click_100k",   name = "十万次疯狂",   icon = "🔥", iconImage = "image/临时工.png", desc = "签单 100,000 次",          threshold = 1e5,  tier = 5 },
    { id = "click_500k",   name = "永不停歇",     icon = "🔥", iconImage = "image/临时工.png", desc = "签单 500,000 次",          threshold = 5e5,  tier = 6 },
    { id = "click_1m",     name = "百万暴击",     icon = "⚡", iconImage = "image/临时工.png", desc = "签单 1,000,000 次",        threshold = 1e6,  tier = 7 },
}

--- 黄金商机里程碑
local luckyAchievements = {
    { id = "lucky_1",      name = "初次商机",     icon = "🍀", iconImage = "image/icon_商机.png", desc = "抓住黄金商机 1 次",        threshold = 1,    tier = 1 },
    { id = "lucky_7",      name = "七星高照",     icon = "🍀", iconImage = "image/icon_商机.png", desc = "抓住黄金商机 7 次",        threshold = 7,    tier = 2 },
    { id = "lucky_27",     name = "三生有幸",     icon = "🌟", iconImage = "image/icon_商机.png", desc = "抓住黄金商机 27 次",       threshold = 27,   tier = 4 },
    { id = "lucky_77",     name = "商机之神",     icon = "🌟", iconImage = "image/icon_商机.png", desc = "抓住黄金商机 77 次",       threshold = 77,   tier = 5 },
    { id = "lucky_777",    name = "天选之人",     icon = "✨", iconImage = "image/icon_商机.png", desc = "抓住黄金商机 777 次",      threshold = 777,  tier = 7 },
}

--- 每秒营收里程碑
local cpsAchievements = {
    { id = "cps_1",        name = "涓涓细流",     icon = "💧", iconImage = "image/每秒营收.png", desc = "每秒营收达到 1",           threshold = 1,    tier = 1 },
    { id = "cps_10",       name = "小溪",         icon = "💧", iconImage = "image/每秒营收.png", desc = "每秒营收达到 10",          threshold = 10,   tier = 1 },
    { id = "cps_100",      name = "小河",         icon = "🌊", iconImage = "image/每秒营收.png", desc = "每秒营收达到 100",         threshold = 100,  tier = 2 },
    { id = "cps_1k",       name = "大河",         icon = "🌊", iconImage = "image/每秒营收.png", desc = "每秒营收达到 1,000",       threshold = 1e3,  tier = 3 },
    { id = "cps_10k",      name = "急流",         icon = "🌊", iconImage = "image/每秒营收.png", desc = "每秒营收达到 10,000",      threshold = 1e4,  tier = 4 },
    { id = "cps_100k",     name = "瀑布",         icon = "🏞️", iconImage = "image/每秒营收.png", desc = "每秒营收达到 100,000",     threshold = 1e5,  tier = 5 },
    { id = "cps_1m",       name = "洪流",         icon = "🏞️", iconImage = "image/每秒营收.png", desc = "每秒营收达到 1,000,000",   threshold = 1e6,  tier = 5 },
    { id = "cps_1b",       name = "资金海啸",     icon = "🌊", iconImage = "image/每秒营收.png", desc = "每秒营收达到 1B",          threshold = 1e9,  tier = 6 },
    { id = "cps_1t",       name = "资金银河",     icon = "🌌", iconImage = "image/每秒营收.png", desc = "每秒营收达到 1T",          threshold = 1e12, tier = 7 },
}

--- 升级里程碑
local upgradeAchievements = {
    { id = "upg_1",   name = "初步强化",   icon = "⚡", iconImage = "image/icon_升级.png", desc = "购买 1 个升级",   threshold = 1,  tier = 1 },
    { id = "upg_5",   name = "升级达人",   icon = "⚡", iconImage = "image/icon_升级.png", desc = "购买 5 个升级",   threshold = 5,  tier = 2 },
    { id = "upg_10",  name = "升级专家",   icon = "⚡", iconImage = "image/icon_升级.png", desc = "购买 10 个升级",  threshold = 10, tier = 4 },
    { id = "upg_25",  name = "升级大师",   icon = "⚡", iconImage = "image/icon_升级.png", desc = "购买 25 个升级",  threshold = 25, tier = 5 },
    { id = "upg_50",  name = "升级王者",   icon = "⚡", iconImage = "image/icon_升级.png", desc = "购买 50 个升级",  threshold = 50, tier = 7 },
}

--- 每次签单收益里程碑
local cpcAchievements = {
    { id = "cpc_100",    name = "小笔交易",     icon = "💵", iconImage = "image/icon_cpc_20260415033235.png",       desc = "每次签单收益达到 100",          threshold = 100,    tier = 1 },
    { id = "cpc_10k",    name = "中等订单",     icon = "💵", iconImage = "image/icon_cpc_20260415033235.png",       desc = "每次签单收益达到 10,000",       threshold = 1e4,    tier = 2 },
    { id = "cpc_1m",     name = "大宗合同",     icon = "💵", iconImage = "image/icon_cpc_20260415033235.png",       desc = "每次签单收益达到 1,000,000",    threshold = 1e6,    tier = 3 },
    { id = "cpc_1b",     name = "天价订单",     icon = "💵", iconImage = "image/icon_cpc_20260415033235.png",       desc = "每次签单收益达到 1B",           threshold = 1e9,    tier = 5 },
    { id = "cpc_1t",     name = "世纪大单",     icon = "💵", iconImage = "image/icon_cpc_20260415033235.png",       desc = "每次签单收益达到 1T",           threshold = 1e12,   tier = 7 },
}

--- 手动签单总产出里程碑
local handmadeAchievements = {
    { id = "hand_1k",     name = "亲力亲为",     icon = "✋", iconImage = "image/icon_handmade_20260415033225.png",  desc = "手动签单累计产出 1,000",         threshold = 1e3,    tier = 1 },
    { id = "hand_1m",     name = "勤奋企业家",   icon = "✋", iconImage = "image/icon_handmade_20260415033225.png",  desc = "手动签单累计产出 1,000,000",     threshold = 1e6,    tier = 2 },
    { id = "hand_1b",     name = "签单狂魔",     icon = "✋", iconImage = "image/icon_handmade_20260415033225.png",  desc = "手动签单累计产出 1B",            threshold = 1e9,    tier = 4 },
    { id = "hand_1t",     name = "手工帝王",     icon = "✋", iconImage = "image/icon_handmade_20260415033225.png",  desc = "手动签单累计产出 1T",            threshold = 1e12,   tier = 6 },
    { id = "hand_1qa",    name = "亲签之神",     icon = "✋", iconImage = "image/icon_handmade_20260415033225.png",  desc = "手动签单累计产出 1Qa",           threshold = 1e15,   tier = 7 },
}

--- 持有金币里程碑
local bankAchievements = {
    { id = "bank_1m",     name = "小金库",       icon = "🏦", iconImage = "image/icon_bank_balance_20260415033217.png", desc = "同时持有 1,000,000 金币",        threshold = 1e6,    tier = 1 },
    { id = "bank_1b",     name = "大金库",       icon = "🏦", iconImage = "image/icon_bank_balance_20260415033217.png", desc = "同时持有 1B 金币",               threshold = 1e9,    tier = 2 },
    { id = "bank_1t",     name = "金山银山",     icon = "🏦", iconImage = "image/icon_bank_balance_20260415033217.png", desc = "同时持有 1T 金币",               threshold = 1e12,   tier = 3 },
    { id = "bank_1qa",    name = "富可敌国",     icon = "🏦", iconImage = "image/icon_bank_balance_20260415033217.png", desc = "同时持有 1Qa 金币",              threshold = 1e15,   tier = 5 },
    { id = "bank_1sx",    name = "宇宙首富",     icon = "🏦", iconImage = "image/icon_bank_balance_20260415033217.png", desc = "同时持有 1Sx 金币",              threshold = 1e21,   tier = 7 },
}

--- 产业总数里程碑
local totalBuildingAchievements = {
    { id = "tbld_100",    name = "初具规模",     icon = "🏗️", iconImage = "image/icon_total_buildings_20260415033216.png", desc = "产业总数达到 100",             threshold = 100,   tier = 1 },
    { id = "tbld_500",    name = "产业集群",     icon = "🏗️", iconImage = "image/icon_total_buildings_20260415033216.png", desc = "产业总数达到 500",             threshold = 500,   tier = 2 },
    { id = "tbld_1000",   name = "商业版图",     icon = "🏗️", iconImage = "image/icon_total_buildings_20260415033216.png", desc = "产业总数达到 1,000",           threshold = 1000,  tier = 3 },
    { id = "tbld_2000",   name = "产业帝国",     icon = "🏗️", iconImage = "image/icon_total_buildings_20260415033216.png", desc = "产业总数达到 2,000",           threshold = 2000,  tier = 4 },
    { id = "tbld_3000",   name = "万业之王",     icon = "🏗️", iconImage = "image/icon_total_buildings_20260415033216.png", desc = "产业总数达到 3,000",           threshold = 3000,  tier = 5 },
    { id = "tbld_4000",   name = "商业奇迹",     icon = "🏗️", iconImage = "image/icon_total_buildings_20260415033216.png", desc = "产业总数达到 4,000",           threshold = 4000,  tier = 6 },
    { id = "tbld_5000",   name = "无尽版图",     icon = "🏗️", iconImage = "image/icon_total_buildings_20260415033216.png", desc = "产业总数达到 5,000",           threshold = 5000,  tier = 7 },
}

--- 转型重启里程碑
local ascensionAchievements = {
    { id = "asc_1",       name = "浴火重生",     icon = "🔥", iconImage = "image/icon_ascend_20260415033115.png",    desc = "完成第 1 次转型重启",            threshold = 1,     tier = 2 },
    { id = "asc_5",       name = "轮回老手",     icon = "🔥", iconImage = "image/icon_ascend_20260415033115.png",    desc = "完成第 5 次转型重启",            threshold = 5,     tier = 3 },
    { id = "asc_10",      name = "转型专家",     icon = "🔥", iconImage = "image/icon_ascend_20260415033115.png",    desc = "完成第 10 次转型重启",           threshold = 10,    tier = 4 },
    { id = "asc_25",      name = "永恒轮回",     icon = "🔥", iconImage = "image/icon_ascend_20260415033115.png",    desc = "完成第 25 次转型重启",           threshold = 25,    tier = 6 },
    { id = "asc_50",      name = "涅槃之主",     icon = "🔥", iconImage = "image/icon_ascend_20260415033115.png",    desc = "完成第 50 次转型重启",           threshold = 50,    tier = 7 },
}

--- 声望等级里程碑
local prestigeAchievements = {
    { id = "pres_1",      name = "初入商界",     icon = "⭐", iconImage = "image/icon_ascend_20260415033115.png",    desc = "商业声望达到 Lv.1",              threshold = 1,      tier = 1 },
    { id = "pres_10",     name = "崭露头角",     icon = "⭐", iconImage = "image/icon_ascend_20260415033115.png",    desc = "商业声望达到 Lv.10",             threshold = 10,     tier = 2 },
    { id = "pres_100",    name = "声名鹊起",     icon = "⭐", iconImage = "image/icon_ascend_20260415033115.png",    desc = "商业声望达到 Lv.100",            threshold = 100,    tier = 3 },
    { id = "pres_1000",   name = "业界传奇",     icon = "⭐", iconImage = "image/icon_ascend_20260415033115.png",    desc = "商业声望达到 Lv.1,000",          threshold = 1000,   tier = 5 },
    { id = "pres_10000",  name = "永恒丰碑",     icon = "⭐", iconImage = "image/icon_ascend_20260415033115.png",    desc = "商业声望达到 Lv.10,000",         threshold = 10000,  tier = 7 },
}

--- 人脉（糖块）里程碑
local sugarLumpAchievements = {
    { id = "lump_1",      name = "人脉初建",     icon = "🤝", iconImage = "image/icon_lump_20260415033116.png",      desc = "累计获得 1 人脉",                threshold = 1,     tier = 1 },
    { id = "lump_10",     name = "社交达人",     icon = "🤝", iconImage = "image/icon_lump_20260415033116.png",      desc = "累计获得 10 人脉",               threshold = 10,    tier = 2 },
    { id = "lump_50",     name = "人脉广阔",     icon = "🤝", iconImage = "image/icon_lump_20260415033116.png",      desc = "累计获得 50 人脉",               threshold = 50,    tier = 3 },
    { id = "lump_100",    name = "人脉帝国",     icon = "🤝", iconImage = "image/icon_lump_20260415033116.png",      desc = "累计获得 100 人脉",              threshold = 100,   tier = 5 },
    { id = "lump_500",    name = "社交之王",     icon = "🤝", iconImage = "image/icon_lump_20260415033116.png",      desc = "累计获得 500 人脉",              threshold = 500,   tier = 7 },
}

--- 工会危机里程碑
local grandmapoAchievements = {
    { id = "gpo_awaken",  name = "工会抗议",     icon = "😠", iconImage = "image/icon_grandmapo_20260415033117.png", desc = "首次触发工会危机",               tier = 3 },
    { id = "gpo_pledge1", name = "劳资调停",     icon = "😠", iconImage = "image/icon_grandmapo_20260415033117.png", desc = "首次签署劳资和约",               tier = 2 },
    { id = "gpo_pledge5", name = "和平大使",     icon = "😠", iconImage = "image/icon_grandmapo_20260415033117.png", desc = "累计签署 5 次劳资和约",           threshold = 5, tier = 4 },
    { id = "gpo_elder",   name = "驾驭危机",     icon = "😠", iconImage = "image/icon_grandmapo_20260415033117.png", desc = "解锁全部工会研究",               tier = 6 },
}

--- AI 合伙人（K1）里程碑
local dragonAchievements = {
    { id = "drg_hatch",   name = "AI 上线",       icon = "🤖", iconImage = "image/icon_ai_partner_20260505071305.png",    desc = "AI 合伙人正式上线运行",           threshold = 4,  tier = 2 },
    { id = "drg_mid",     name = "智能进化",      icon = "🤖", iconImage = "image/icon_ai_partner_20260505071305.png",    desc = "AI 合伙人成长到 Lv.10",          threshold = 10, tier = 4 },
    { id = "drg_max",     name = "超级智能",      icon = "🤖", iconImage = "image/icon_ai_partner_20260505071305.png",    desc = "AI 合伙人达到最高等级",           threshold = 21, tier = 6 },
    { id = "drg_aura2",   name = "双核驱动",      icon = "🤖", iconImage = "image/icon_ai_partner_20260505071305.png",    desc = "解锁 AI 第二策略模块槽",          tier = 7 },
}

--- 黑洞（Wrinkler）里程碑
local wrinklerAchievements = {
    { id = "wrk_pop1",    name = "黑洞猎人",     icon = "🕳️", iconImage = "image/icon_wrinkler_20260415033134.png",  desc = "首次消灭黑洞",                   threshold = 1,    tier = 1 },
    { id = "wrk_pop50",   name = "黑洞终结者",   icon = "🕳️", iconImage = "image/icon_wrinkler_20260415033134.png",  desc = "累计消灭 50 个黑洞",             threshold = 50,   tier = 3 },
    { id = "wrk_pop200",  name = "虚空支配者",   icon = "🕳️", iconImage = "image/icon_wrinkler_20260415033134.png",  desc = "累计消灭 200 个黑洞",            threshold = 200,  tier = 5 },
    { id = "wrk_pop500",  name = "黑洞屠夫",     icon = "🕳️", iconImage = "image/icon_wrinkler_20260415033134.png",  desc = "累计消灭 500 个黑洞",            threshold = 500,  tier = 7 },
}

--- 市场周期里程碑（季节收集、市场信心等级）
local seasonAchievements = {
    -- 牛市：分红收益全收集
    { id = "season_xmas_all",    name = "牛市丰收",     icon = "📈", desc = "收集全部 7 种分红收益",           category = C.MISC, tier = 4, seasonCollection = "christmas" },
    -- 熊市：不良资产全收集
    { id = "season_hw_all",      name = "逆市淘金",     icon = "📉", desc = "收集全部 7 种不良资产",           category = C.MISC, tier = 4, seasonCollection = "halloween" },
    -- 创新潮：专利技术收集阶梯
    { id = "season_egg_1",       name = "初涉研发",     icon = "💡", desc = "获得 1 项专利技术",               category = C.MISC, tier = 1, seasonEggCount = 1 },
    { id = "season_egg_7",       name = "技术储备",     icon = "💡", desc = "获得 7 项专利技术",               category = C.MISC, tier = 3, seasonEggCount = 7 },
    { id = "season_egg_20",      name = "专利帝国",     icon = "💡", desc = "获得全部 20 项专利技术",          category = C.MISC, tier = 6, seasonEggCount = 20 },
    -- 合作季：合作协议全收集
    { id = "season_val_all",     name = "合作共赢",     icon = "🤝", desc = "签订全部 7 份合作协议",           category = C.MISC, tier = 4, seasonCollection = "valentine" },
    -- 市场信心等级
    { id = "season_santa_7",     name = "融资达人",     icon = "📈", desc = "市场信心达到 C轮融资 (Lv.7)",     category = C.MISC, tier = 3, santaLevel = 7 },
    { id = "season_santa_14",    name = "市场之王",     icon = "👑", desc = "市场信心达到最高等级 (Lv.14)",     category = C.MISC, tier = 6, santaLevel = 14 },
}

--- 排行榜里程碑（需排行榜总人数 >= 100 才开始计算）
local leaderboardAchievements = {
    -- ======== 排名到达类 ========
    { id = "lb_rank1",       name = "登顶之巅",       icon = "👑", iconImage = "image/排行榜.png", desc = "到达过排行榜第1名",             tier = 7, lbType = "rank1_reached" },
    { id = "lb_top3",        name = "三甲之列",       icon = "🥇", iconImage = "image/排行榜.png", desc = "到达过排行榜前3名",             tier = 5, lbType = "top3_reached" },
    { id = "lb_top10",       name = "十强精英",       icon = "🏅", iconImage = "image/排行榜.png", desc = "到达过排行榜前10名",            tier = 4, lbType = "top10_reached" },
    { id = "lb_top1p",       name = "百里挑一",       icon = "💎", iconImage = "image/排行榜.png", desc = "到达过排行榜前1%",              tier = 6, lbType = "top1p_reached" },
    { id = "lb_top10p",      name = "出类拔萃",       icon = "⭐", iconImage = "image/排行榜.png", desc = "到达过排行榜前10%",             tier = 4, lbType = "top10p_reached" },
    { id = "lb_top50p",      name = "超越半数",       icon = "📊", iconImage = "image/排行榜.png", desc = "到达过排行榜前50%",             tier = 2, lbType = "top50p_reached" },

    -- ======== 第1名时长类 ========
    { id = "lb_r1_1d",       name = "日冠王者",       icon = "🌅", iconImage = "image/排行榜.png", desc = "在第1名的累计时长超过1天",       tier = 4, lbType = "rank1_time", threshold = 86400 },
    { id = "lb_r1_7d",       name = "周冠霸主",       icon = "📅", iconImage = "image/排行榜.png", desc = "在第1名的累计时长超过1周",       tier = 5, lbType = "rank1_time", threshold = 604800 },
    { id = "lb_r1_30d",      name = "月冠传说",       icon = "🌙", iconImage = "image/排行榜.png", desc = "在第1名的累计时长超过1个月",     tier = 6, lbType = "rank1_time", threshold = 2592000 },
    { id = "lb_r1_365d",     name = "年冠神话",       icon = "🌟", iconImage = "image/排行榜.png", desc = "在第1名的累计时长超过1年",       tier = 7, lbType = "rank1_time", threshold = 31536000 },

    -- ======== 排行榜参与类 ========
    { id = "lb_join",        name = "初入榜单",       icon = "📋", iconImage = "image/排行榜.png", desc = "首次登上排行榜",                tier = 1, lbType = "on_board" },

    -- ======== 排名提升类 ========
    { id = "lb_best100",     name = "百强选手",       icon = "💯", iconImage = "image/排行榜.png", desc = "历史最佳排名进入前100",          tier = 3, lbType = "best_rank", threshold = 100 },
    { id = "lb_best50",      name = "五十强",         icon = "🎯", iconImage = "image/排行榜.png", desc = "历史最佳排名进入前50",           tier = 3, lbType = "best_rank", threshold = 50 },
    { id = "lb_best10",      name = "十强入围",       icon = "🏅", iconImage = "image/排行榜.png", desc = "历史最佳排名进入前10",           tier = 5, lbType = "best_rank", threshold = 10 },
    { id = "lb_best3",       name = "三甲荣耀",       icon = "🥇", iconImage = "image/排行榜.png", desc = "历史最佳排名进入前3",            tier = 6, lbType = "best_rank", threshold = 3 },
}

--- 小游戏里程碑
local minigameAchievements = {
    -- ======== 挖矿探险 ========
    { id = "mg_mine_clear1",    name = "初探矿脉",     icon = "⛏️", iconImage = "image/采矿场.png", desc = "清空矿区 1 次",               threshold = 1,     tier = 1, mgType = "mine_clear" },
    { id = "mg_mine_clear10",   name = "矿区扫荡",     icon = "⛏️", iconImage = "image/采矿场.png", desc = "累计清空矿区 10 次",           threshold = 10,    tier = 2, mgType = "mine_clear" },
    { id = "mg_mine_clear50",   name = "矿区征服者",   icon = "⛏️", iconImage = "image/采矿场.png", desc = "累计清空矿区 50 次",           threshold = 50,    tier = 3, mgType = "mine_clear" },
    { id = "mg_mine_clear200",  name = "矿王",         icon = "⛏️", iconImage = "image/采矿场.png", desc = "累计清空矿区 200 次",          threshold = 200,   tier = 5, mgType = "mine_clear" },
    { id = "mg_mine_streak5",   name = "连击新手",     icon = "⛏️", iconImage = "image/采矿场.png", desc = "挖矿连击达到 5",               threshold = 5,     tier = 2, mgType = "mine_streak" },
    { id = "mg_mine_streak15",  name = "连击大师",     icon = "⛏️", iconImage = "image/采矿场.png", desc = "挖矿连击达到 15",              threshold = 15,    tier = 4, mgType = "mine_streak" },

    -- ======== 孵化园 / 花园 ========
    { id = "mg_garden_seed5",   name = "园丁入门",     icon = "🌱", iconImage = "image/侧栏_孵化园.png", desc = "发现 5 种种子",            threshold = 5,     tier = 1, mgType = "garden_seed" },
    { id = "mg_garden_seed15",  name = "植物学家",     icon = "🌱", iconImage = "image/侧栏_孵化园.png", desc = "发现 15 种种子",           threshold = 15,    tier = 3, mgType = "garden_seed" },
    { id = "mg_garden_seed30",  name = "种子猎人",     icon = "🌱", iconImage = "image/侧栏_孵化园.png", desc = "发现 30 种种子",           threshold = 30,    tier = 5, mgType = "garden_seed" },
    { id = "mg_garden_all",     name = "全图鉴收集",   icon = "🌱", iconImage = "image/侧栏_孵化园.png", desc = "发现全部种子",             threshold = 999,   tier = 7, mgType = "garden_all" },

    -- ======== 制造工厂 ========
    { id = "mg_fac_deliver10",  name = "初级工头",     icon = "🏭", iconImage = "image/制造工厂.png", desc = "累计交付 10 个订单",          threshold = 10,    tier = 1, mgType = "factory_deliver" },
    { id = "mg_fac_deliver50",  name = "生产主管",     icon = "🏭", iconImage = "image/制造工厂.png", desc = "累计交付 50 个订单",          threshold = 50,    tier = 2, mgType = "factory_deliver" },
    { id = "mg_fac_deliver200", name = "工厂之王",     icon = "🏭", iconImage = "image/制造工厂.png", desc = "累计交付 200 个订单",         threshold = 200,   tier = 4, mgType = "factory_deliver" },
    { id = "mg_fac_gather100",  name = "采集达人",     icon = "🏭", iconImage = "image/制造工厂.png", desc = "累计采集 100 次原料",         threshold = 100,   tier = 2, mgType = "factory_gather" },
    { id = "mg_fac_gather500",  name = "采集狂魔",     icon = "🏭", iconImage = "image/制造工厂.png", desc = "累计采集 500 次原料",         threshold = 500,   tier = 4, mgType = "factory_gather" },
    { id = "mg_fac_level5",     name = "工厂扩建",     icon = "🏭", iconImage = "image/制造工厂.png", desc = "工厂达到 5 级",               threshold = 5,     tier = 3, mgType = "factory_level" },
    { id = "mg_fac_level10",    name = "工业帝国",     icon = "🏭", iconImage = "image/制造工厂.png", desc = "工厂达到 10 级",              threshold = 10,    tier = 5, mgType = "factory_level" },

    -- ======== 期货交易所 / 股市 ========
    { id = "mg_stock_profit1m", name = "初入股海",     icon = "📈", iconImage = "image/期货交易所.png", desc = "股市累计盈利达到 1M",       threshold = 1e6,   tier = 2, mgType = "stock_profit" },
    { id = "mg_stock_profit1b", name = "股市赢家",     icon = "📈", iconImage = "image/期货交易所.png", desc = "股市累计盈利达到 1B",       threshold = 1e9,   tier = 4, mgType = "stock_profit" },
    { id = "mg_stock_profit1t", name = "华尔街之狼",   icon = "📈", iconImage = "image/期货交易所.png", desc = "股市累计盈利达到 1T",       threshold = 1e12,  tier = 6, mgType = "stock_profit" },

    -- ======== 电商平台 ========
    { id = "mg_ecom_sold50",    name = "电商新秀",     icon = "🛒", iconImage = "image/电商平台.png", desc = "累计销售 50 件商品",          threshold = 50,    tier = 1, mgType = "ecom_sold" },
    { id = "mg_ecom_sold200",   name = "带货达人",     icon = "🛒", iconImage = "image/电商平台.png", desc = "累计销售 200 件商品",         threshold = 200,   tier = 3, mgType = "ecom_sold" },
    { id = "mg_ecom_sold1000",  name = "电商帝国",     icon = "🛒", iconImage = "image/电商平台.png", desc = "累计销售 1,000 件商品",       threshold = 1000,  tier = 5, mgType = "ecom_sold" },
    { id = "mg_ecom_streak10",  name = "好评如潮",     icon = "🛒", iconImage = "image/电商平台.png", desc = "电商连击达到 10",             threshold = 10,    tier = 3, mgType = "ecom_streak" },

    -- ======== 国际物流 ========
    { id = "mg_ship_deliver10", name = "新手船长",     icon = "🚢", iconImage = "image/国际物流.png", desc = "累计送达 10 批货物",          threshold = 10,    tier = 1, mgType = "ship_deliver" },
    { id = "mg_ship_deliver50", name = "航海老手",     icon = "🚢", iconImage = "image/国际物流.png", desc = "累计送达 50 批货物",          threshold = 50,    tier = 3, mgType = "ship_deliver" },
    { id = "mg_ship_deliver200",name = "物流大亨",     icon = "🚢", iconImage = "image/国际物流.png", desc = "累计送达 200 批货物",         threshold = 200,   tier = 5, mgType = "ship_deliver" },
    { id = "mg_ship_streak5",   name = "安全运输",     icon = "🚢", iconImage = "image/国际物流.png", desc = "连续安全送达 5 批",           threshold = 5,     tier = 2, mgType = "ship_streak" },
    { id = "mg_ship_streak20",  name = "零事故纪录",   icon = "🚢", iconImage = "image/国际物流.png", desc = "连续安全送达 20 批",          threshold = 20,    tier = 4, mgType = "ship_streak" },

    -- ======== 研发实验室 ========
    { id = "mg_grim_cast10",    name = "研发新手",     icon = "🔬", iconImage = "image/研发中心.png", desc = "累计施法 10 次",              threshold = 10,    tier = 1, mgType = "grimoire_cast" },
    { id = "mg_grim_cast50",    name = "研发专家",     icon = "🔬", iconImage = "image/研发中心.png", desc = "累计施法 50 次",              threshold = 50,    tier = 3, mgType = "grimoire_cast" },
    { id = "mg_grim_cast200",   name = "研发大师",     icon = "🔬", iconImage = "image/研发中心.png", desc = "累计施法 200 次",             threshold = 200,   tier = 5, mgType = "grimoire_cast" },
}

-- ============================================================================
-- 汇总所有里程碑
-- ============================================================================

--- 所有里程碑列表（运行时由 AchievementManager 遍历检查）
AchievementDefs.all = {}

-- 注入营收里程碑
for _, a in ipairs(productionAchievements) do
    a.category = C.PRODUCTION
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入产业规模里程碑
for _, a in ipairs(buildingAchievements) do
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入签单里程碑
for _, a in ipairs(clickAchievements) do
    a.category = C.CLICK
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入黄金商机里程碑
for _, a in ipairs(luckyAchievements) do
    a.category = C.LUCKY
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入营收速度里程碑
for _, a in ipairs(cpsAchievements) do
    a.category = C.PRODUCTION
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入升级里程碑
for _, a in ipairs(upgradeAchievements) do
    a.category = C.UPGRADE
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入每次签单收益里程碑
for _, a in ipairs(cpcAchievements) do
    a.category = C.CLICK
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入手动签单总产出里程碑
for _, a in ipairs(handmadeAchievements) do
    a.category = C.CLICK
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入持有金币里程碑
for _, a in ipairs(bankAchievements) do
    a.category = C.PRODUCTION
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入产业总数里程碑
for _, a in ipairs(totalBuildingAchievements) do
    a.category = C.BUILDING
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入转型重启里程碑
for _, a in ipairs(ascensionAchievements) do
    a.category = C.MISC
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入声望等级里程碑
for _, a in ipairs(prestigeAchievements) do
    a.category = C.MISC
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入人脉里程碑
for _, a in ipairs(sugarLumpAchievements) do
    a.category = C.MISC
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入工会危机里程碑
for _, a in ipairs(grandmapoAchievements) do
    a.category = C.MISC
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入龙里程碑
for _, a in ipairs(dragonAchievements) do
    a.category = C.MISC
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入黑洞里程碑
for _, a in ipairs(wrinklerAchievements) do
    a.category = C.MISC
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入市场周期里程碑
for _, a in ipairs(seasonAchievements) do
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入排行榜里程碑
for _, a in ipairs(leaderboardAchievements) do
    a.category = C.LEADERBOARD
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

-- 注入小游戏里程碑
for _, a in ipairs(minigameAchievements) do
    a.category = C.MINIGAME
    AchievementDefs.all[#AchievementDefs.all + 1] = a
end

--- 统计总里程碑数
AchievementDefs.totalCount = #AchievementDefs.all

print("[AchievementDefs] 总里程碑数: " .. AchievementDefs.totalCount)

return AchievementDefs
