-- ============================================================================
-- config/GrimoireConfig.lua
-- 研发实验室配置：研发项目（法术）定义、研发能量（法力）常量
-- 对齐 Cookie Clicker 原版 Grimoire 的 7 个法术
-- 绑定建筑：研发中心（id="wizard"，index 8）
-- ============================================================================

local GC = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
GC.UNLOCK_BUILDING_COUNT = 1      -- 需要多少个研发中心才能解锁
GC.BASE_MANA             = 4      -- 基础法力容量
GC.MANA_REGEN_RATE       = 0.002  -- 每秒恢复 maxMana 的 0.2%
GC.SPELL_COOLDOWN        = 5      -- 全局施法冷却（秒）
GC.BUFF_DURATION         = 60     -- 通用 buff 持续时间（秒）

-- ---------------------------------------------------------------------------
-- 法力容量公式
-- maxMana = BASE_MANA + floor(wizardCount ^ 0.6)
-- ---------------------------------------------------------------------------

--- 计算最大研发能量
---@param wizardCount number 研发中心数量
---@return number
function GC.CalcMaxMana(wizardCount)
    return GC.BASE_MANA + math.floor(wizardCount ^ 0.6)
end

-- ---------------------------------------------------------------------------
-- 研发项目（法术）定义 —— 对齐 Cookie Clicker 原版 7 个法术
-- ---------------------------------------------------------------------------

---@class GrimoireSpell
---@field id string
---@field name string
---@field icon string
---@field manaCost number
---@field failBase number       基础失败率
---@field successDesc string    成功效果描述
---@field failDesc string       失败效果描述
---@field effectType string     效果类型标识

GC.spells = {
    -- #1 Conjure Baked Goods → 市场爆发
    {
        id          = "market_surge",
        name        = "市场爆发",
        icon        = "📈",
        manaCost    = 10,
        failBase    = 0.15,
        successDesc = "获得 CPS×10分钟 的金币",
        failDesc    = "损失 CPS×5分钟 的金币",
        effectType  = "instant_coins",
    },
    -- #2 Force the Hand of Fate → 命运之手
    {
        id          = "force_hand",
        name        = "命运之手",
        icon        = "🪙",
        manaCost    = 10,
        failBase    = 0.15,
        successDesc = "立即生成一个幸运金币",
        failDesc    = "损失 CPS×5分钟 的金币",
        effectType  = "lucky_coin",
    },
    -- #3 Stretch Time → 时间加速
    {
        id          = "stretch_time",
        name        = "时间加速",
        icon        = "⏱️",
        manaCost    = 8,
        failBase    = 0.20,
        successDesc = "CPS +20%，持续 60 秒",
        failDesc    = "CPS -20%，持续 60 秒",
        effectType  = "cps_buff",
    },
    -- #4 Spontaneous Edifice → 猎头行动
    {
        id          = "talent_hunt",
        name        = "猎头行动",
        icon        = "🎯",
        manaCost    = 20,
        failBase    = 0.20,
        successDesc = "随机一种建筑免费 +1",
        failDesc    = "随机一种建筑 -1",
        effectType  = "building_change",
    },
    -- #5 Haggler's Charm → 谈判专家
    {
        id          = "haggler_charm",
        name        = "谈判专家",
        icon        = "🤝",
        manaCost    = 10,
        failBase    = 0.20,
        successDesc = "升级价格 -2%，持续 60 秒",
        failDesc    = "升级价格 +2%，持续 60 秒",
        effectType  = "upgrade_price",
    },
    -- #6 Summon Crafty Pixies → 精灵助手
    {
        id          = "crafty_pixie",
        name        = "精灵助手",
        icon        = "🧚",
        manaCost    = 10,
        failBase    = 0.20,
        successDesc = "建筑价格 -2%，持续 60 秒",
        failDesc    = "建筑价格 +2%，持续 60 秒",
        effectType  = "building_price",
    },
    -- #7 Gambler's Fever Dream → 赌徒直觉
    {
        id          = "gambler_dream",
        name        = "赌徒直觉",
        icon        = "🎲",
        manaCost    = 3,
        failBase    = 0.15,
        successDesc = "随机施放一个法术",
        failDesc    = "随机施放一个法术",
        effectType  = "random_spell",
    },
}

-- ---------------------------------------------------------------------------
-- 工具函数
-- ---------------------------------------------------------------------------

--- 根据 id 查找法术
---@param id string
---@return GrimoireSpell|nil
function GC.FindSpell(id)
    for _, spell in ipairs(GC.spells) do
        if spell.id == id then return spell end
    end
    return nil
end

--- 计算失败率
--- failRate = failBase + 0.15 * (1 - currentMana / maxMana)
---@param spell GrimoireSpell
---@param currentMana number
---@param maxMana number
---@return number 0~1
function GC.CalcFailRate(spell, currentMana, maxMana)
    if maxMana <= 0 then return 1.0 end
    local rate = spell.failBase + 0.15 * (1 - currentMana / maxMana)
    return math.max(0, math.min(1, rate))
end

--- 获取法术数量
---@return number
function GC.GetSpellCount()
    return #GC.spells
end

--- 格式化失败率为百分比字符串
---@param rate number 0~1
---@return string
function GC.FormatFailRate(rate)
    return string.format("%.0f%%", rate * 100)
end

return GC
