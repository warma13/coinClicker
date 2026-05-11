-- ============================================================================
-- config/ItemDefs.lua
-- 仓库道具定义表
-- ============================================================================

local ItemDefs = {}

-- ============================================================================
-- 分类定义
-- ============================================================================
ItemDefs.CATEGORIES = {
    { id = "all",         name = "全部", abbr = "[全]", color = { 200, 200, 220 } },
    { id = "boost",       name = "增益", abbr = "[增]", color = { 255, 200, 80 } },
    { id = "skip",        name = "道具", abbr = "[具]", color = { 100, 200, 255 } },
    { id = "collectible", name = "收藏", abbr = "[藏]", color = { 220, 160, 255 } },
}

-- 稀有度定义
ItemDefs.RARITY = {
    [1] = { name = "普通", color = { 180, 180, 190 }, stars = 1 },
    [2] = { name = "优良", color = { 100, 200, 100 }, stars = 2 },
    [3] = { name = "稀有", color = { 80, 160, 255 },  stars = 3 },
    [4] = { name = "史诗", color = { 200, 100, 255 }, stars = 4 },
    [5] = { name = "传说", color = { 255, 200, 50 },  stars = 5 },
}

-- ============================================================================
-- 道具列表
-- ============================================================================
ItemDefs.ITEMS = {
    -- ====== boost（增益类）======
    {
        id       = "double_potion",
        name     = "双倍药水",
        abbr     = "倍",
        icon     = "image/道具_双倍药水_20260510072634.png",
        category = "boost",
        rarity   = 2,
        desc     = "使用后 60 秒内产出翻倍",
        useEffect = {
            type     = "buff",
            buffId   = "inv_double",
            buffName = "双倍药水",
            duration = 60,
            key      = "cps",
            value    = 2,
            color    = { 100, 220, 80 },
        },
    },
    {
        id       = "click_storm",
        name     = "点击风暴",
        abbr     = "暴",
        icon     = "image/道具_点击风暴_20260510072634.png",
        category = "boost",
        rarity   = 3,
        desc     = "使用后 30 秒内点击收益 x5",
        useEffect = {
            type     = "buff",
            buffId   = "inv_click_storm",
            buffName = "点击风暴",
            duration = 30,
            key      = "cpc",
            value    = 5,
            color    = { 255, 220, 80 },
        },
    },
    {
        id       = "lucky_charm",
        name     = "幸运符",
        abbr     = "运",
        icon     = "image/道具_幸运符_20260510072655.png",
        category = "boost",
        rarity   = 2,
        desc     = "使用后 120 秒内幸运金币出现频率 x3",
        useEffect = {
            type     = "buff",
            buffId   = "inv_lucky",
            buffName = "幸运符",
            duration = 120,
            key      = "luckyFreq",
            value    = 3,
            color    = { 80, 220, 150 },
        },
    },

    -- ====== skip（跳过类）======
    {
        id       = "time_hourglass",
        name     = "时光沙漏",
        abbr     = "漏",
        icon     = "image/时光沙漏_20260507165843.png",
        category = "skip",
        rarity   = 4,
        desc     = "立即获得 1 小时的产出",
        useEffect = {
            type    = "instant_cps",
            seconds = 3600,
        },
    },
    {
        id       = "speed_gear",
        name     = "加速齿轮",
        abbr     = "速",
        icon     = "image/道具_加速齿轮_20260510072632.png",
        category = "skip",
        rarity   = 3,
        desc     = "立即获得 30 分钟的产出",
        useEffect = {
            type    = "instant_cps",
            seconds = 1800,
        },
    },
    {
        id       = "flash_capsule",
        name     = "瞬息胶囊",
        abbr     = "瞬",
        icon     = "image/道具_瞬息胶囊_20260510072635.png",
        category = "skip",
        rarity   = 2,
        desc     = "立即获得 10 分钟的产出",
        useEffect = {
            type    = "instant_cps",
            seconds = 600,
        },
    },

    -- ====== special（特殊类）======
    {
        id       = "collectible_box",
        name     = "随机藏品箱",
        abbr     = "箱",
        icon     = "image/道具_藏品箱_20260511074357.png",
        category = "skip",
        rarity   = 4,
        maxStack = 99,
        desc     = "打开后随机获得一件收藏品，低品质概率更高。",
        useEffect = {
            type = "random_collectible",
        },
    },

    -- ====== collectible（收藏类）======
    -- ── ★ 普通（1星）──────────────────────────
    {
        id       = "rusty_coin",
        name     = "锈迹铜币",
        abbr     = "铜",
        icon     = "image/collect_rusty_coin_20260511070954.png",
        category = "collectible",
        rarity   = 1,
        desc     = "一枚锈迹斑斑的古铜币，据说能带来微薄的财运。收藏品，飞升后保留。",
        passive  = { type = "cps_percent", value = 0.005, desc = "CPS +0.5%" },
    },
    {
        id       = "cracked_lens",
        name     = "碎裂透镜",
        abbr     = "镜",
        icon     = "image/collect_cracked_lens_20260511070630.png",
        category = "collectible",
        rarity   = 1,
        desc     = "一块有裂痕的透镜，仍能折射出隐约的光。收藏品，飞升后保留。",
        passive  = { type = "cpc_percent", value = 0.005, desc = "CPC +0.5%" },
    },
    {
        id       = "clover_leaf",
        name     = "三叶草",
        abbr     = "草",
        icon     = "image/collect_clover_leaf_20260511070649.png",
        category = "collectible",
        rarity   = 1,
        desc     = "随处可见的三叶草，据说偶尔能带来好运。收藏品，飞升后保留。",
        passive  = { type = "lucky_freq", value = 0.01, desc = "幸运频率 +1%" },
    },

    -- ── ★★ 优良（2星）──────────────────────────
    {
        id       = "jade_pendant",
        name     = "翠玉吊坠",
        abbr     = "玉",
        icon     = "image/collect_jade_pendant_20260511070629.png",
        category = "collectible",
        rarity   = 2,
        desc     = "温润的翠色玉石，佩戴时令人心神宁静。收藏品，飞升后保留。",
        passive  = { type = "cps_percent", value = 0.01, desc = "CPS +1%" },
    },
    {
        id       = "bronze_compass",
        name     = "青铜罗盘",
        abbr     = "盘",
        icon     = "image/collect_bronze_compass_20260511070652.png",
        category = "collectible",
        rarity   = 2,
        desc     = "古老的航海罗盘，指针永远指向财富的方向。收藏品，飞升后保留。",
        passive  = { type = "cpc_percent", value = 0.01, desc = "CPC +1%" },
    },
    {
        id       = "silver_bell",
        name     = "银铃铛",
        abbr     = "铃",
        icon     = "image/collect_silver_bell_20260511070631.png",
        category = "collectible",
        rarity   = 2,
        desc     = "轻摇发出悦耳铃声，听说能召唤好运。收藏品，飞升后保留。",
        passive  = { type = "lucky_freq", value = 0.02, desc = "幸运频率 +2%" },
    },
    {
        id       = "amber_fossil",
        name     = "琥珀化石",
        abbr     = "珀",
        icon     = "image/collect_amber_fossil_20260511070648.png",
        category = "collectible",
        rarity   = 2,
        desc     = "封存着远古昆虫的琥珀，时光的馈赠。收藏品，飞升后保留。",
        passive  = { type = "lucky_dur", value = 0.01, desc = "幸运持续 +1%" },
    },

    -- ── ★★★ 稀有（3星）──────────────────────────
    {
        id       = "moonstone",
        name     = "月光石",
        abbr     = "月",
        icon     = "image/collect_moonstone_20260511070636.png",
        category = "collectible",
        rarity   = 3,
        desc     = "在月光下微微发亮的宝石，触感冰凉。收藏品，飞升后保留。",
        passive  = { type = "cps_percent", value = 0.015, desc = "CPS +1.5%" },
    },
    {
        id       = "thunder_shard",
        name     = "雷鸣碎晶",
        abbr     = "雷",
        icon     = "image/collect_thunder_shard_20260511071140.png",
        category = "collectible",
        rarity   = 3,
        desc     = "暴风雨中凝结的电晶体，触之有微麻感。收藏品，飞升后保留。",
        passive  = { type = "cpc_percent", value = 0.015, desc = "CPC +1.5%" },
    },
    {
        id       = "four_leaf_clover",
        name     = "四叶幸运草",
        abbr     = "幸",
        icon     = "image/collect_four_leaf_clover_20260511071134.png",
        category = "collectible",
        rarity   = 3,
        desc     = "极其罕见的四叶草，据说能显著提升运势。收藏品，飞升后保留。",
        passive  = { type = "lucky_freq", value = 0.03, desc = "幸运频率 +3%" },
    },
    {
        id       = "hourglass_sand",
        name     = "永恒沙粒",
        abbr     = "沙",
        icon     = "image/collect_hourglass_sand_20260511071130.png",
        category = "collectible",
        rarity   = 3,
        desc     = "从损坏的时光沙漏中散落的金色沙粒，能延长幸运时刻。收藏品，飞升后保留。",
        passive  = { type = "lucky_dur", value = 0.03, desc = "幸运持续 +3%" },
    },

    -- ── ★★★★ 史诗（4星）──────────────────────────
    {
        id       = "crystal_ball",
        name     = "水晶球",
        abbr     = "晶",
        icon     = "image/collect_crystal_ball_20260511071131.png",
        category = "collectible",
        rarity   = 4,
        desc     = "神秘的水晶球，散发着幽蓝光芒。收藏品，飞升后保留。",
        passive  = { type = "cps_percent", value = 0.025, desc = "CPS +2.5%" },
    },
    {
        id       = "phoenix_feather",
        name     = "凤凰羽",
        abbr     = "凤",
        icon     = "image/collect_phoenix_feather_20260511071153.png",
        category = "collectible",
        rarity   = 4,
        desc     = "传说中浴火重生之鸟的羽毛，温暖而轻盈。收藏品，飞升后保留。",
        passive  = { type = "cpc_percent", value = 0.025, desc = "CPC +2.5%" },
    },
    {
        id       = "star_shard",
        name     = "星辰碎片",
        abbr     = "星",
        icon     = "image/collect_star_shard_20260511071157.png",
        category = "collectible",
        rarity   = 4,
        desc     = "坠落的流星残片，闪烁着微弱星光。收藏品，飞升后保留。",
        passive  = { type = "cps_percent", value = 0.025, desc = "CPS +2.5%" },
    },
    {
        id       = "sun_emblem",
        name     = "太阳徽记",
        abbr     = "阳",
        icon     = "image/collect_sun_emblem_20260511071150.png",
        category = "collectible",
        rarity   = 4,
        desc     = "铭刻着古老太阳纹路的金色徽章。收藏品，飞升后保留。",
        passive  = { type = "cpc_percent", value = 0.025, desc = "CPC +2.5%" },
    },
    {
        id       = "emerald_scarab",
        name     = "翡翠圣甲虫",
        abbr     = "甲",
        icon     = "image/collect_emerald_scarab_20260511071546.png",
        category = "collectible",
        rarity   = 4,
        desc     = "法老墓中出土的翡翠圣甲虫护符，蕴含神秘力量。收藏品，飞升后保留。",
        passive  = { type = "lucky_freq", value = 0.04, desc = "幸运频率 +4%" },
    },
    {
        id       = "frozen_tear",
        name     = "冰封之泪",
        abbr     = "泪",
        icon     = "image/collect_frozen_tear_20260511071235.png",
        category = "collectible",
        rarity   = 4,
        desc     = "永不融化的冰晶泪滴，散发着幽寒之气。收藏品，飞升后保留。",
        passive  = { type = "lucky_dur", value = 0.04, desc = "幸运持续 +4%" },
    },

    -- ── ★★★★★ 传说（5星）──────────────────────────
    {
        id       = "dragon_scale",
        name     = "龙鳞碎片",
        abbr     = "鳞",
        icon     = "image/collect_dragon_scale_20260511071229.png",
        category = "collectible",
        rarity   = 5,
        desc     = "从远古巨龙身上剥落的鳞片，温热而坚硬。收藏品，飞升后保留。",
        passive  = { type = "cpc_percent", value = 0.04, desc = "CPC +4%" },
    },
    {
        id       = "rainbow_medal",
        name     = "虹光勋章",
        abbr     = "虹",
        icon     = "image/collect_rainbow_medal_20260511071215.png",
        category = "collectible",
        rarity   = 5,
        desc     = "折射出七彩光芒的荣誉勋章。收藏品，飞升后保留。",
        passive  = { type = "lucky_freq", value = 0.06, desc = "幸运频率 +6%" },
    },
    {
        id       = "abyss_eye",
        name     = "深渊之眼",
        abbr     = "渊",
        icon     = "image/collect_abyss_eye_20260511071215.png",
        category = "collectible",
        rarity   = 5,
        desc     = "深渊凝视的结晶，散发着不祥的紫光。收藏品，飞升后保留。",
        passive  = { type = "lucky_dur", value = 0.06, desc = "幸运持续 +6%" },
    },
    {
        id       = "celestial_core",
        name     = "天体核心",
        abbr     = "核",
        icon     = "image/collect_celestial_core_20260511071213.png",
        category = "collectible",
        rarity   = 5,
        desc     = "据说是坍缩恒星的核心碎片，蕴含无穷能量。收藏品，飞升后保留。",
        passive  = { type = "cps_percent", value = 0.04, desc = "CPS +4%" },
    },
    {
        id       = "void_prism",
        name     = "虚空棱镜",
        abbr     = "棱",
        icon     = "image/collect_void_prism_20260511071214.png",
        category = "collectible",
        rarity   = 5,
        desc     = "能够折射维度间光芒的神秘棱镜，注视过久会头晕目眩。收藏品，飞升后保留。",
        passive  = { type = "global_percent", value = 0.03, desc = "全局产出 +3%" },
    },
}

-- ============================================================================
-- 快查表
-- ============================================================================
ItemDefs.ITEM_MAP = {}
for _, item in ipairs(ItemDefs.ITEMS) do
    ItemDefs.ITEM_MAP[item.id] = item
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 获取某个分类的所有道具
---@param categoryId string
---@return table
function ItemDefs.GetItemsByCategory(categoryId)
    if categoryId == "all" then return ItemDefs.ITEMS end
    local result = {}
    for _, item in ipairs(ItemDefs.ITEMS) do
        if item.category == categoryId then
            result[#result + 1] = item
        end
    end
    return result
end

--- 获取随机道具 ID（按稀有度加权，低稀有度更常见）
---@return string itemId
function ItemDefs.GetRandomItemId()
    -- 权重：rarity 1→50, 2→30, 3→15, 4→4, 5→1
    local weights = { [1] = 50, [2] = 30, [3] = 15, [4] = 4, [5] = 1 }
    local pool = {}
    for _, item in ipairs(ItemDefs.ITEMS) do
        local w = weights[item.rarity] or 10
        for _ = 1, w do
            pool[#pool + 1] = item.id
        end
    end
    return pool[math.random(1, #pool)]
end

-- ============================================================================
-- 收藏品套装系统
-- ============================================================================

--- 所有收藏品 ID 列表
ItemDefs.COLLECTIBLE_IDS = {}
for _, item in ipairs(ItemDefs.ITEMS) do
    if item.category == "collectible" then
        ItemDefs.COLLECTIBLE_IDS[#ItemDefs.COLLECTIBLE_IDS + 1] = item.id
    end
end

--- 套装阶段奖励（按收集数量触发，取最高已达成阶段，不叠加）
ItemDefs.SET_BONUSES = {
    { need = 5,  desc = "全局产出 +3%",   bonus = { type = "global_percent", value = 0.03 } },
    { need = 10, desc = "全局产出 +6%",   bonus = { type = "global_percent", value = 0.06 } },
    { need = 15, desc = "全局产出 +10%",  bonus = { type = "global_percent", value = 0.10 } },
    { need = 20, desc = "全局产出 +15%",  bonus = { type = "global_percent", value = 0.15 } },
}

--- 获取收藏品总数
---@return number
function ItemDefs.GetCollectibleTotal()
    return #ItemDefs.COLLECTIBLE_IDS
end

return ItemDefs
