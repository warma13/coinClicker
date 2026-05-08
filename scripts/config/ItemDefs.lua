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
    { id = "skip",        name = "跳过", abbr = "[跳]", color = { 100, 200, 255 } },
    { id = "tool",        name = "工具", abbr = "[工]", color = { 180, 220, 100 } },
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
        category = "boost",
        rarity   = 2,
        desc     = "使用后 60 秒内产出翻倍",
        useEffect = {
            type     = "buff",
            buffId   = "inv_double",
            buffName = "双倍药水",
            duration = 60,
            key      = "buffCpsMul",
            value    = 2,
            color    = { 100, 220, 80 },
        },
    },
    {
        id       = "click_storm",
        name     = "点击风暴",
        abbr     = "暴",
        category = "boost",
        rarity   = 3,
        desc     = "使用后 30 秒内点击收益 x5",
        useEffect = {
            type     = "buff",
            buffId   = "inv_click_storm",
            buffName = "点击风暴",
            duration = 30,
            key      = "buffCpcMul",
            value    = 5,
            color    = { 255, 220, 80 },
        },
    },
    {
        id       = "lucky_charm",
        name     = "幸运符",
        abbr     = "运",
        category = "boost",
        rarity   = 2,
        desc     = "使用后 120 秒内幸运金币出现频率 x3",
        useEffect = {
            type     = "buff",
            buffId   = "inv_lucky",
            buffName = "幸运符",
            duration = 120,
            key      = "luckyFreqMul",
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
        category = "skip",
        rarity   = 2,
        desc     = "立即获得 10 分钟的产出",
        useEffect = {
            type    = "instant_cps",
            seconds = 600,
        },
    },

    -- ====== tool（工具类）======
    {
        id       = "master_key",
        name     = "万能钥匙",
        abbr     = "钥",
        category = "tool",
        rarity   = 4,
        desc     = "随机解锁一个未购买的升级（如果有）",
        useEffect = {
            type = "unlock_upgrade",
        },
    },
    {
        id       = "golden_compass",
        name     = "金色罗盘",
        abbr     = "盘",
        category = "tool",
        rarity   = 3,
        desc     = "显示 60 秒内的最优点击位置，点击收益 +50%",
        useEffect = {
            type     = "buff",
            buffId   = "inv_compass",
            buffName = "金色罗盘",
            duration = 60,
            key      = "buffCpcMul",
            value    = 1.5,
            color    = { 255, 200, 80 },
        },
    },
    {
        id       = "repair_hammer",
        name     = "修复锤",
        abbr     = "锤",
        category = "tool",
        rarity   = 3,
        desc     = "重置所有技能冷却时间",
        useEffect = {
            type = "reset_cooldowns",
        },
    },

    -- ====== collectible（收藏类）======
    {
        id       = "crystal_ball",
        name     = "水晶球",
        abbr     = "晶",
        category = "collectible",
        rarity   = 4,
        desc     = "神秘的水晶球，散发着幽蓝光芒。收藏品，飞升后保留。",
        passive  = { type = "cps_percent", value = 0.02, desc = "CPS +2%" },
    },
    {
        id       = "dragon_scale",
        name     = "龙鳞碎片",
        abbr     = "鳞",
        category = "collectible",
        rarity   = 5,
        desc     = "从远古巨龙身上剥落的鳞片，温热而坚硬。收藏品，飞升后保留。",
        passive  = { type = "cpc_percent", value = 0.03, desc = "CPC +3%" },
    },
    {
        id       = "rainbow_medal",
        name     = "虹光勋章",
        abbr     = "虹",
        category = "collectible",
        rarity   = 5,
        desc     = "折射出七彩光芒的荣誉勋章。收藏品，飞升后保留。",
        passive  = { type = "lucky_freq", value = 0.05, desc = "幸运频率 +5%" },
    },
    {
        id       = "moonstone",
        name     = "月光石",
        abbr     = "月",
        category = "collectible",
        rarity   = 3,
        desc     = "在月光下微微发亮的宝石，触感冰凉。收藏品，飞升后保留。",
        passive  = { type = "cps_percent", value = 0.01, desc = "CPS +1%" },
    },
    {
        id       = "phoenix_feather",
        name     = "凤凰羽",
        abbr     = "凤",
        category = "collectible",
        rarity   = 4,
        desc     = "传说中浴火重生之鸟的羽毛，温暖而轻盈。收藏品，飞升后保留。",
        passive  = { type = "cpc_percent", value = 0.02, desc = "CPC +2%" },
    },
    {
        id       = "star_shard",
        name     = "星辰碎片",
        abbr     = "星",
        category = "collectible",
        rarity   = 4,
        desc     = "坠落的流星残片，闪烁着微弱星光。收藏品，飞升后保留。",
        passive  = { type = "cps_percent", value = 0.02, desc = "CPS +2%" },
    },
    {
        id       = "abyss_eye",
        name     = "深渊之眼",
        abbr     = "渊",
        category = "collectible",
        rarity   = 5,
        desc     = "深渊凝视的结晶，散发着不祥的紫光。收藏品，飞升后保留。",
        passive  = { type = "lucky_dur", value = 0.05, desc = "幸运持续 +5%" },
    },
    {
        id       = "sun_emblem",
        name     = "太阳徽记",
        abbr     = "阳",
        category = "collectible",
        rarity   = 4,
        desc     = "铭刻着古老太阳纹路的金色徽章。收藏品，飞升后保留。",
        passive  = { type = "cpc_percent", value = 0.02, desc = "CPC +2%" },
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

--- 套装阶段奖励（按收集数量触发，各阶段独立，不叠加）
ItemDefs.SET_BONUSES = {
    { need = 3, desc = "全局产出 +5%",   bonus = { type = "global_percent", value = 0.05 } },
    { need = 5, desc = "全局产出 +8%",   bonus = { type = "global_percent", value = 0.08 } },
    { need = 8, desc = "全局产出 +12%",  bonus = { type = "global_percent", value = 0.12 } },
}

--- 获取收藏品总数
---@return number
function ItemDefs.GetCollectibleTotal()
    return #ItemDefs.COLLECTIBLE_IDS
end

return ItemDefs
