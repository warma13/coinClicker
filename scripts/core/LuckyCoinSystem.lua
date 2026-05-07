-- ============================================================================
-- core/LuckyCoinSystem.lua
-- 幸运金币系统：效果定义、生成/隐藏、Buff 管理、计时器
-- 从 GameManager.lua 提取
-- ============================================================================

local GameState = require("core.GameState")
local Buildings = require("config.Buildings")
local AudioManager = require("core.AudioManager")
local SlotSaveSystem = require("core.SlotSaveSystem")

local GrandmapoManager = require("core.GrandmapoManager")
local SugarLumpManager = require("core.SugarLumpManager")
local SeasonManager = require("core.SeasonManager")
local DragonManager = require("core.DragonManager")
local SkillManager = require("core.SkillManager")
local DD = require("config.DragonDefs")

local MultiplierPool = require("core.MultiplierPool")

local M = {}

-- ---------------------------------------------------------------------------
-- 私有状态
-- ---------------------------------------------------------------------------

--- UI 引用与 GM 回调上下文，由 Init 注入
--- ctx_.ui = { floatingText, luckyCoin, coinArea, coinParticle, statsBar }
--- ctx_.GM = { RecalcProduction, RefreshAllUI }
local ctx_ = nil

--- 当前金币是否为愤怒金币
local luckyIsWrath_ = false

-- ============================================================================
-- 幸运金币效果定义（对齐 Cookie Clicker）
-- ============================================================================

local luckyEffects = {
    {
        id = "frenzy",
        name = "金币狂热",
        icon = "🔥",
        color = { 255, 140, 0, 255 },
        weight = 50,    -- 最常见
        apply = function()
            return {
                id = "frenzy",
                name = "金币狂热",
                icon = "🔥",
                color = { 255, 140, 0, 255 },
                remaining = 77,
                duration = 77,
                multiplierKey = "cps",
                multiplierVal = 7,
            }
        end,
    },
    {
        id = "lucky",
        name = "幸运一击",
        icon = "🍀",
        color = { 50, 205, 50, 255 },
        weight = 30,    -- 常见
        apply = function()
            local S = GameState
            -- Cookie Clicker 公式: min(CpS×900, 银行×0.15) + 13
            local amount = math.min(S.coinsPerSecond * 900, S.coins * 0.15) + 13
            amount = math.max(amount, 13)
            S.coins = S.coins + amount
            print("[Lucky Coin] 幸运一击! +" .. S.FormatNumber(amount))
            return nil
        end,
    },
    {
        id = "clickFrenzy",
        name = "点击狂潮",
        icon = "⚡",
        color = { 255, 215, 0, 255 },
        weight = 10,    -- 稀有
        apply = function()
            return {
                id = "clickFrenzy",
                name = "点击狂潮",
                icon = "⚡",
                color = { 255, 215, 0, 255 },
                remaining = 13,
                duration = 13,
                multiplierKey = "cpc",
                multiplierVal = 777,
            }
        end,
    },
    {
        id = "coinStorm",
        name = "金币风暴",
        icon = "🌧️",
        color = { 100, 149, 237, 255 },
        weight = 3,     -- 极稀有
        apply = function()
            local S = GameState
            -- 类似 Cookie Storm 简化版：大量即时金币
            local amount = math.min(S.coinsPerSecond * 3600, S.coins * 0.25) + 13
            amount = math.max(amount, 13)
            S.coins = S.coins + amount
            print("[Lucky Coin] 金币风暴! +" .. S.FormatNumber(amount))
            return nil
        end,
    },
    {
        id = "buildingSpecial",
        name = "建筑加成",
        icon = "🏗️",
        color = { 147, 112, 219, 255 },
        weight = 0,     -- 条件加入，不使用固定权重
        apply = function()
            -- 找到拥有最多的建筑类型
            local maxCount = 0
            local maxIndex = 1
            for i, b in ipairs(Buildings.buildings) do
                if b.count > maxCount then
                    maxCount = b.count
                    maxIndex = i
                end
            end
            local b = Buildings.buildings[maxIndex]
            return {
                id = "buildingSpecial",
                name = "建筑加成: " .. b.name,
                icon = b.icon,
                color = { 147, 112, 219, 255 },
                remaining = 30,
                duration = 30,
                buildingIndex = maxIndex,
                -- 不使用 multiplierKey，在 Update 循环中单独处理
            }
        end,
    },
}

-- ============================================================================
-- 模块内部函数
-- ============================================================================

--- 按权重随机选择一个效果（动态池：Building Special / Business Day 条件加入）
local function PickLuckyEffect()
    local pool = {}
    local totalWeight = 0
    for _, e in ipairs(luckyEffects) do
        local w = e.weight
        -- Building Special: 总建筑数 >= 10 时，25% 概率加入池，权重 15
        if e.id == "buildingSpecial" then
            w = 0
            local totalCount = 0
            for _, b in ipairs(Buildings.buildings) do
                totalCount = totalCount + b.count
            end
            if totalCount >= 10 and math.random() < 0.25 then
                w = 15
            end
        end
        if w > 0 then
            pool[#pool + 1] = { effect = e, weight = w }
            totalWeight = totalWeight + w
        end
    end

    -- 商业日（清仓促销）季节时，加入清仓大促效果
    local bizEffect = SeasonManager.GetBusinessDayEffect()
    if bizEffect then
        local bizEntry = {
            effect = {
                id = bizEffect.id,
                name = bizEffect.name,
                icon = "📋",
                color = { 100, 200, 150, 255 },
                weight = bizEffect.weight,
                apply = function()
                    return {
                        id = bizEffect.id,
                        name = bizEffect.name,
                        icon = "📋",
                        color = { 100, 200, 150, 255 },
                        remaining = bizEffect.duration,
                        duration = bizEffect.duration,
                        multiplierKey = "buildingCost",
                        multiplierVal = bizEffect.buildingCostMul,
                    }
                end,
            },
            weight = bizEffect.weight,
        }
        pool[#pool + 1] = bizEntry
        totalWeight = totalWeight + bizEffect.weight
    end

    -- 从池中按权重抽取
    local roll = math.random() * totalWeight
    local cumulative = 0
    for _, entry in ipairs(pool) do
        cumulative = cumulative + entry.weight
        if roll <= cumulative then
            return entry.effect
        end
    end
    return pool[1].effect
end

--- 生成幸运金币
local function SpawnLuckyCoin()
    local S = GameState
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr

    local margin = S.luckySize
    local shopWidth = 260
    local topBar = 50
    S.luckyPosX = margin + math.random() * math.max(1, screenW - shopWidth - margin * 2 - S.luckySize)
    S.luckyPosY = topBar + margin + math.random() * math.max(1, screenH - topBar - margin * 2 - S.luckySize)

    S.luckyActive = true
    S.luckyLifetime = S.luckyMaxLife * S.luckyStayMul
    S.luckyFloatPhase = 0

    -- 奶奶末日：判断是否为愤怒金币
    local isWrath, _ = GrandmapoManager.RollWrathCoin()
    luckyIsWrath_ = isWrath

    if ctx_.ui.luckyCoin then
        ctx_.ui.luckyCoin.Show(S.luckyPosX, S.luckyPosY)
        ctx_.ui.luckyCoin.SetWrath(isWrath)
    end

    local coinType = isWrath and "愤怒金币" or "幸运金币"
    print("[Lucky Coin] " .. coinType .. "出现! pos=(" .. math.floor(S.luckyPosX) .. "," .. math.floor(S.luckyPosY) .. ")")
end

--- 隐藏幸运金币
local function HideLuckyCoin()
    GameState.luckyActive = false
    if ctx_.ui.luckyCoin then
        ctx_.ui.luckyCoin.Hide()
    end
end

--- 获取建筑专属 buff 倍率（buildingSpecial）
--- @param bi number 建筑索引
--- @return number 该建筑的额外 buff 倍率
local function GetBuildingBuffMul(bi)
    local mul = 1
    for _, b in ipairs(GameState.activeBuffs) do
        if b.id == "buildingSpecial" and b.buildingIndex == bi then
            mul = mul * 10 -- x10 该建筑产出
        end
    end
    return mul
end

--- 重新计算 buff 倍率（使用 MultiplierPool 统一接口，加算合并防止膨胀）
local function RecalcBuffMultipliers()
    local S = GameState
    S.buffBuildingCostMul = 1

    local cpsPool = MultiplierPool.New()
    local cpcPool = MultiplierPool.New()

    for _, b in ipairs(S.activeBuffs) do
        if b.multiplierKey == "cps" then
            cpsPool:Add(b.multiplierVal)        -- 1+x 格式，加算合并
        elseif b.multiplierKey == "cpc" then
            cpcPool:Add(b.multiplierVal)        -- 1+x 格式，加算合并
        elseif b.multiplierKey == "buildingCost" then
            S.buffBuildingCostMul = S.buffBuildingCostMul * b.multiplierVal
        end
    end

    -- CPS翻倍技能也加算
    cpsPool:Add(SkillManager.GetCpsMultiplier())

    S.buffCpsMul = cpsPool:Result()
    S.buffCpcMul = cpcPool:Result()
end

--- 应用愤怒金币效果
---@param effect table 从 GrandmapocalypseDefs.wrathEffects 中抽取的效果
---@return table|nil buff 如果是持续 buff 则返回
local function ApplyWrathEffect(effect)
    local S = GameState
    if effect.id == "lucky" then
        -- 同正常幸运一击
        local amount = math.min(S.coinsPerSecond * 900, S.coins * 0.15) + 13
        amount = math.max(amount, 13)
        S.coins = S.coins + amount
        print("[Wrath] 幸运一击! +" .. S.FormatNumber(amount))
        return nil
    elseif effect.id == "ruin" then
        -- 失去金币
        local loss = math.min(S.coinsPerSecond * 900, S.coins * 0.05) + 13
        loss = math.min(loss, S.coins)
        S.coins = S.coins - loss
        print("[Wrath] 毁灭! -" .. S.FormatNumber(loss))
        return nil
    elseif effect.type == "buff" then
        -- 持续 buff（clot / elderFrenzy / clickFrenzyWrath）
        print("[Wrath] Buff: " .. effect.name .. " (x" .. effect.multiplierVal .. " " .. effect.duration .. "s)")
        return {
            id = effect.id,
            name = effect.name,
            icon = effect.icon,
            color = effect.color,
            remaining = effect.duration,
            duration = effect.duration,
            multiplierKey = effect.multiplierKey,
            multiplierVal = effect.multiplierVal,
        }
    end
    return nil
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 初始化：存储 UI 引用和 GM 回调上下文
--- @param ctx table { ui = { floatingText, luckyCoin, coinArea, coinParticle, statsBar }, GM = { RecalcProduction, RefreshAllUI } }
function M.Init(ctx)
    ctx_ = ctx

    -- 草根人脉收获时触发黄金商机（需在 SpawnLuckyCoin 定义之后注册）
    SugarLumpManager.SetOnTriggerLucky(function()
        print("[LuckyCoinSystem] 草根人脉触发黄金商机！")
        SpawnLuckyCoin()
    end)
end

--- 获取建筑专属 buff 倍率（供外部产出计算使用）
--- @param bi number 建筑索引
--- @return number
function M.GetBuildingBuffMul(bi)
    return GetBuildingBuffMul(bi)
end

--- 触发幸运金币效果（由 LuckyCoin UI 的点击回调调用）
function M.TriggerEffect()
    local S = GameState
    S.luckyClicks = S.luckyClicks + 1

    local effect, buff
    if luckyIsWrath_ then
        -- 愤怒金币：从愤怒效果池抽取
        local wrathEffect = GrandmapoManager.PickWrathEffect()
        effect = wrathEffect
        buff = ApplyWrathEffect(wrathEffect)
        print("[Wrath Coin] 触发: " .. effect.name .. " (累计点击: " .. S.luckyClicks .. ")")
    else
        effect = PickLuckyEffect()
        buff = effect.apply()
        print("[Lucky Coin] 触发: " .. effect.name .. " (累计点击: " .. S.luckyClicks .. ")")
    end
    if buff then
        -- 应用效果持续时间倍率（Get Lucky）
        if S.luckyDurMul > 1 then
            buff.remaining = buff.remaining * S.luckyDurMul
            buff.duration = buff.duration * S.luckyDurMul
        end

        -- 同 id buff 叠加：累加剩余时间（CC v2.002+ 行为）
        local stacked = false
        for _, existing in ipairs(S.activeBuffs) do
            if existing.id == buff.id then
                existing.remaining = existing.remaining + buff.remaining
                existing.duration = math.max(existing.duration, buff.duration)
                stacked = true
                print("[Lucky Coin] Buff 叠加: " .. buff.name .. " (剩余 " .. string.format("%.1f", existing.remaining) .. "s)")
                break
            end
        end
        if not stacked then
            S.activeBuffs[#S.activeBuffs + 1] = buff
        end
    end

    -- buff 效果：立即刷新底部进度条
    if buff and ctx_.ui.statsBar then
        ctx_.ui.statsBar.RefreshBuffBar()
    end

    -- 即时/一次性效果 或 buff 触发：都在点击位置显示浮动提示
    if ctx_.ui.floatingText then
        ctx_.ui.floatingText.Show(effect.name .. "!",
            S.luckyPosX + S.luckySize * 0.5,
            S.luckyPosY, effect.color or { 255, 215, 0, 255 }, effect.iconImage)
    end

    -- 龙光环特殊效果：Dragon Harvest / Dragonflight（受 noBuffs 约束）
    if not luckyIsWrath_ then
        if DragonManager.HasDragonHarvest() and math.random() < 0.05 then
            -- Dragon Harvest: CpS × 15 持续 60s
            local dhBuff = {
                id = "dragonHarvest",
                name = "Dragon Harvest",
                icon = "丰",
                color = { 180, 220, 80, 255 },
                remaining = DD.DRAGON_HARVEST_DUR,
                duration = DD.DRAGON_HARVEST_DUR,
                multiplierKey = "cps",
                multiplierVal = DD.DRAGON_HARVEST_MUL,
            }
            -- 叠加
            local stacked = false
            for _, existing in ipairs(S.activeBuffs) do
                if existing.id == "dragonHarvest" then
                    existing.remaining = existing.remaining + dhBuff.remaining
                    stacked = true
                    break
                end
            end
            if not stacked then
                S.activeBuffs[#S.activeBuffs + 1] = dhBuff
            end
            if ctx_.ui.floatingText then
                ctx_.ui.floatingText.Show("丰收 Dragon Harvest!", S.luckyPosX, S.luckyPosY - 30, { 180, 220, 80, 255 })
            end
        end
        if DragonManager.HasDragonflight() and math.random() < 0.05 then
            -- Dragonflight: 点击 × 1111 持续 10s
            local dfBuff = {
                id = "dragonflight",
                name = "Dragonflight",
                icon = "龙",
                color = { 255, 180, 60, 255 },
                remaining = DD.DRAGONFLIGHT_DUR,
                duration = DD.DRAGONFLIGHT_DUR,
                multiplierKey = "cpc",
                multiplierVal = DD.DRAGONFLIGHT_MUL,
            }
            local stacked = false
            for _, existing in ipairs(S.activeBuffs) do
                if existing.id == "dragonflight" then
                    existing.remaining = existing.remaining + dfBuff.remaining
                    stacked = true
                    break
                end
            end
            if not stacked then
                S.activeBuffs[#S.activeBuffs + 1] = dfBuff
            end
            if ctx_.ui.floatingText then
                ctx_.ui.floatingText.Show("龙 Dragonflight!", S.luckyPosX, S.luckyPosY - 30, { 255, 180, 60, 255 })
            end
        end
    end

    -- 复活节蛋掉落尝试（点击幸运/愤怒金币时）
    SeasonManager.TryEasterDrop("lucky")

    HideLuckyCoin()
    local baseInterval = S.luckyMinInterval + math.random() * (S.luckyMaxInterval - S.luckyMinInterval)
    S.luckyTimer = baseInterval / S.luckyFreqMul

    SlotSaveSystem.MarkDirty()
end

--- Buff 倒计时 + 刷新 buff 栏（从 GM.Update 提取）
--- @param dt number 帧间隔
function M.UpdateBuffs(dt)
    local S = GameState

    local buffsChanged = false
    for i = #S.activeBuffs, 1, -1 do
        S.activeBuffs[i].remaining = S.activeBuffs[i].remaining - dt
        if S.activeBuffs[i].remaining <= 0 then
            print("[Lucky Coin] Buff 结束: " .. S.activeBuffs[i].name)
            table.remove(S.activeBuffs, i)
            buffsChanged = true
        end
    end
    RecalcBuffMultipliers()

    -- 刷新 buff 栏
    S.buffRefreshCooldown = S.buffRefreshCooldown - dt
    if ctx_.ui.statsBar and (buffsChanged or (S.buffRefreshCooldown <= 0 and #S.activeBuffs > 0)) then
        S.buffRefreshCooldown = 0.5
        ctx_.ui.statsBar.RefreshBuffBar()
    end
end

--- 幸运金币计时器（从 GM.Update 提取）
--- @param dt number 帧间隔
function M.UpdateLuckyCoin(dt)
    local S = GameState

    if not S.luckyActive then
        S.luckyTimer = S.luckyTimer - dt
        if S.luckyTimer <= 0 then
            SpawnLuckyCoin()
        end
    else
        S.luckyLifetime = S.luckyLifetime - dt
        if S.luckyLifetime <= 0 then
            print("[Lucky Coin] 幸运金币消失（未被点击）")
            HideLuckyCoin()
            local baseInterval = S.luckyMinInterval + math.random() * (S.luckyMaxInterval - S.luckyMinInterval)
            S.luckyTimer = baseInterval / S.luckyFreqMul
        elseif ctx_.ui.luckyCoin then
            ctx_.ui.luckyCoin.UpdateAnimation(dt)
        end
    end
end

return M
