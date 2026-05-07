-- ============================================================================
-- config/AscensionDefs.lua
-- 转型重启/声望系统数据定义（声望公式 + 经验商店）
-- 金币帝国 · 现实商业主题
-- 纯数据，无游戏逻辑
-- ============================================================================

local AD = {}

-- ============================================================================
-- 声望公式
-- ============================================================================

--- Prestige = floor( (totalBaked / PRESTIGE_DIVISOR) ^ (1/3) )
AD.PRESTIGE_DIVISOR = 1e12

--- 计算商业声望等级
---@param totalBaked number 历史总营业额
---@return number 声望等级
function AD.CalcPrestigeLevel(totalBaked)
    if totalBaked < AD.PRESTIGE_DIVISOR then return 0 end
    return math.floor((totalBaked / AD.PRESTIGE_DIVISOR) ^ (1 / 3))
end

--- 计算达到指定声望等级所需的总营业额
---@param level number 目标声望等级
---@return number
function AD.CalcRequiredBaked(level)
    return AD.PRESTIGE_DIVISOR * level * level * level
end

-- ============================================================================
-- 经验商店（转型重启时用经验值兑换永久加成）
-- 按解锁链排列，prereq 为前置升级 id
-- ============================================================================

AD.heavenlyUpgrades = {
    -- ===== 核心链：声望加成解锁 =====
    {
        id = "legacy",
        name = "品牌传承",
        iconImage = "image/upgrade_品牌传承.png",
        desc = "启用声望系统，每声望等级 +1% CpS（5%有效）",
        cost = 1,
        prereq = nil,
        prestigeUnlock = 0.05,
    },
    {
        id = "heavenlyChipSecret",
        name = "商业机密",
        iconImage = "image/upgrade_商业机密.png",
        desc = "声望加成提升至 25%",
        cost = 11,
        prereq = "legacy",
        prestigeUnlock = 0.25,
    },
    {
        id = "heavenlyCookieStand",
        name = "老字号招牌",
        iconImage = "image/upgrade_老字号招牌.png",
        desc = "声望加成提升至 50%",
        cost = 1111,
        prereq = "heavenlyChipSecret",
        prestigeUnlock = 0.50,
    },
    {
        id = "heavenlyBakery",
        name = "行业标杆",
        iconImage = "image/upgrade_行业标杆.png",
        desc = "声望加成提升至 75%",
        cost = 111111,
        prereq = "heavenlyCookieStand",
        prestigeUnlock = 0.75,
    },
    {
        id = "heavenlyKey",
        name = "金融牌照",
        iconImage = "image/upgrade_金融牌照.png",
        desc = "声望加成提升至 100%",
        cost = 1111111111,
        prereq = "heavenlyBakery",
        prestigeUnlock = 1.00,
    },

    -- ===== 产量加成分支 =====
    {
        id = "heavenlyCookies",
        name = "管理学教程",
        iconImage = "image/upgrade_管理学教程.png",
        desc = "总产量 +10%",
        cost = 3,
        prereq = "legacy",
        productionMul = 0.10,
    },
    {
        id = "tinOfBiscuits",
        name = "MBA课程",
        iconImage = "image/upgrade_MBA课程.png",
        desc = "总产量 +12%",
        cost = 25,
        prereq = "heavenlyCookies",
        productionMul = 0.12,
    },
    {
        id = "boxOfBiscuits",
        name = "商学院人脉",
        iconImage = "image/upgrade_商学院人脉.png",
        desc = "总产量 +26%",
        cost = 25,
        prereq = "heavenlyCookies",
        productionMul = 0.26,
    },
    {
        id = "boxOfMacarons",
        name = "行业奖项",
        iconImage = "image/upgrade_行业奖项.png",
        desc = "总产量 +26%",
        cost = 25,
        prereq = "heavenlyCookies",
        productionMul = 0.26,
    },

    -- ===== 老关系分支 =====
    {
        id = "starterKit",
        name = "老关系",
        iconImage = "image/upgrade_老关系.png",
        desc = "转型后免费获得 10 个临时工",
        cost = 50,
        prereq = "legacy",
        starterBuilding = "cursor",
        starterCount = 10,
    },
    {
        id = "starterKitchen",
        name = "老合作伙伴",
        iconImage = "image/upgrade_老合作伙伴.png",
        desc = "转型后免费获得 10 个小作坊",
        cost = 5000,
        prereq = "starterKit",
        starterBuilding = "grandma",
        starterCount = 10,
    },

    -- ===== 商机升级分支 =====
    {
        id = "heavenlyLuck",
        name = "商业直觉",
        iconImage = "image/upgrade_商业直觉.png",
        desc = "黄金商机出现频率 +5%",
        cost = 77,
        prereq = "legacy",
        luckyFreqMul = 1.05,
    },
    {
        id = "lastingFortune",
        name = "持久红利",
        iconImage = "image/upgrade_持久红利.png",
        desc = "黄金商机效果持续 +10%",
        cost = 777,
        prereq = "heavenlyLuck",
        luckyDurMul = 1.10,
    },

    -- ===== 点击加成 =====
    {
        id = "santasHelpers",
        name = "私人助理",
        iconImage = "image/upgrade_私人助理.png",
        desc = "点击力量 +10%",
        cost = 1111,
        prereq = "heavenlyCookies",
        clickBonus = 0.10,
    },

    -- ===== 管理顾问加成 =====
    {
        id = "santasMilk",
        name = "顾问加成",
        iconImage = "image/upgrade_顾问加成.png",
        desc = "管理顾问效果 +5%",
        cost = 111111,
        prereq = "heavenlyCookies",
        kittenBonus = 0.05,
    },

    -- ===== AI 合伙人解锁 =====
    {
        id = "howToBakeDragon",
        name = "AI 合伙人计划",
        iconImage = "image/upgrade_AI合伙人.png",
        desc = "解锁 AI 合伙人 K1，培养你的商业 AI 助手",
        cost = 9,
        prereq = "legacy",
        unlockDragon = true,
    },

    -- ===== 周期切换器 =====
    {
        id = "seasonSwitcher",
        name = "周期切换器",
        iconImage = "image/upgrade_周期切换器.png",
        desc = "解锁手动切换市场周期的能力",
        cost = 1111,
        prereq = "legacy",
        unlockSeasonSwitch = true,
    },

    -- ===== 核心资产（永久升级槽） =====
    {
        id = "permSlot1",
        name = "核心资产 I",
        iconImage = "image/upgrade_核心资产1.png",
        desc = "保留 1 个升级跨转型",
        cost = 100,
        prereq = "legacy",
        permSlot = true,
    },
    {
        id = "permSlot2",
        name = "核心资产 II",
        iconImage = "image/upgrade_核心资产2.png",
        desc = "保留第 2 个升级跨转型",
        cost = 20000,
        prereq = "permSlot1",
        permSlot = true,
    },

    -- ===== 产量加成扩展 =====
    {
        id = "industrialKey",
        name = "产业秘钥",
        iconImage = "image/icon_industry_key.png",
        desc = "总产量 +15%",
        cost = 500000,
        prereq = "tinOfBiscuits",
        productionMul = 0.15,
    },
    {
        id = "globalOptimize",
        name = "全球化优势",
        iconImage = "image/icon_global_opt.png",
        desc = "总产量 +20%",
        cost = 5000000,
        prereq = "industrialKey",
        productionMul = 0.20,
    },

    -- ===== 自动化分支 =====
    {
        id = "autoClick",
        name = "自动签单系统",
        iconImage = "image/icon_auto_click.png",
        desc = "光标自动点击速率 ×2",
        cost = 111111,
        prereq = "santasHelpers",
        cursorSpeedMul = 2,
    },

    -- ===== 经济分支 =====
    {
        id = "costReduce",
        name = "规模经济",
        iconImage = "image/icon_cost_reduce.png",
        desc = "所有建筑价格 -3%",
        cost = 111111,
        prereq = "heavenlyCookieStand",
        buildingCostMul = 0.97,
    },
    {
        id = "purchaseOpt",
        name = "采购优化",
        iconImage = "image/icon_purchase_opt.png",
        desc = "所有建筑价格 -5%",
        cost = 11111111,
        prereq = "costReduce",
        buildingCostMul = 0.95,
    },
}

--- 通过 id 查找经验商店升级
---@param id string
---@return table|nil
function AD.FindById(id)
    for _, u in ipairs(AD.heavenlyUpgrades) do
        if u.id == id then return u end
    end
    return nil
end

return AD
