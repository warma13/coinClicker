-- ============================================================================
-- core/SkillManager.lua
-- 技能系统核心逻辑 —— 看广告解锁/升级/释放，无CD
-- ============================================================================
---@diagnostic disable: undefined-global

local GameState = require("core.GameState")
local SkillDefs = require("config.SkillDefs")
local Buildings = require("config.Buildings")
local SM = {}

-- 内部状态
local speedClickAccum_ = 0      -- 疾速点击累计时间
local onClickCallback_ = nil    -- 点击回调 fn(x, y, skipRateLimit)
local onInstantEffect_  = nil   -- 即时技能效果回调 fn(skillId, result)

-- ============================================================================
-- 初始化
-- ============================================================================

--- 初始化技能管理器
---@param onClickCb function 触发一次点击的回调 fn(x, y, skipRateLimit)
function SM.Init(onClickCb)
    onClickCallback_ = onClickCb
    local S = GameState
    if not S.skills then
        S.skills = {}
    end
    for _, def in ipairs(SkillDefs.list) do
        if not S.skills[def.id] then
            S.skills[def.id] = { level = 1, active = false, timer = 0 }
        end
        -- 迁移旧存档
        local st = S.skills[def.id]
        st.cooldown = nil
        if st.level <= 0 then st.level = 1 end  -- 旧存档自动解锁
    end
end

--- 设置即时技能效果回调
---@param cb function fn(skillId, result)
function SM.SetOnInstantEffect(cb)
    onInstantEffect_ = cb
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

local function RandomScreenPos()
    local w = graphics:GetWidth() / graphics:GetDPR()
    local h = graphics:GetHeight() / graphics:GetDPR()
    return w * 0.25 + math.random() * w * 0.25,
           h * 0.25 + math.random() * h * 0.35
end

---@param dt number
function SM.Update(dt)
    local S = GameState
    local skills = S.skills

    -- ── 体力自动恢复（浮点累加，CoinArea 用小数部分算倒计时） ──
    if S.stamina < S.staminaMax then
        S.stamina = math.min(S.staminaMax, S.stamina + dt * S.staminaRegenRate)
    end

    -- ── 疾速签单（noClick 约束时跳过自动点击） ──
    local spdSt = skills.speedClick
    if spdSt and spdSt.active and spdSt.timer > 0 then
        spdSt.timer = spdSt.timer - dt
        local level = spdSt.level
        local params = SkillDefs.speedClick.levels[level]
        if params and onClickCallback_ then
            speedClickAccum_ = speedClickAccum_ + dt * params.rate
            local clicks = math.floor(speedClickAccum_)
            if clicks > 0 then
                speedClickAccum_ = speedClickAccum_ - clicks
                for _ = 1, clicks do
                    local rx, ry = RandomScreenPos()
                    onClickCallback_(rx, ry, true)
                end
            end
        end
        if spdSt.timer <= 0 then
            spdSt.timer = 0
            spdSt.active = false
            speedClickAccum_ = 0
        end
    end

    -- ── CPS翻倍 ──
    local cpsSt = skills.cpsDouble
    if cpsSt and cpsSt.active and cpsSt.timer > 0 then
        cpsSt.timer = cpsSt.timer - dt
        if cpsSt.timer <= 0 then
            cpsSt.timer = 0
            cpsSt.active = false
        end
    end

    -- ── 签单加成（持续型） ──
    local cbSt = skills.clickBoost
    if cbSt and cbSt.active and cbSt.timer > 0 then
        cbSt.timer = cbSt.timer - dt
        if cbSt.timer <= 0 then
            cbSt.timer = 0
            cbSt.active = false
        end
    end
end

-- ============================================================================
-- CPS 倍率查询（供 GameManager 调用）
-- ============================================================================

--- 获取当前 CPS 翻倍技能的倍率（未激活返回 1）
---@return number multiplier
function SM.GetCpsMultiplier()
    local skills = GameState.skills
    local cpsSt = skills.cpsDouble
    if not cpsSt or not cpsSt.active or (cpsSt.timer or 0) <= 0 then
        return 1
    end
    local level = cpsSt.level
    local params = SkillDefs.cpsDouble.levels[level]
    if not params then return 1 end
    return params.multiplier
end

-- ============================================================================
-- 点击收益倍率查询（供 GameManager 调用）
-- ============================================================================

--- 获取当前签单加成技能的倍率（未激活返回 1）
---@return number multiplier
function SM.GetClickMultiplier()
    local skills = GameState.skills
    local cbSt = skills.clickBoost
    if not cbSt or not cbSt.active or (cbSt.timer or 0) <= 0 then
        return 1
    end
    local level = cbSt.level
    local params = SkillDefs.clickBoost.levels[level]
    if not params then return 1 end
    return params.multiplier
end

-- ============================================================================
-- 即时技能执行
-- ============================================================================

--- 执行「随机扩张」技能
---@param level number
---@return table result { buildings = { {name, icon} ... } }
function SM.ExecuteRandomBuildings(level)
    local params = SkillDefs.randomBuildings.levels[level]
    if not params then return { buildings = {} } end

    -- 收集已解锁的建筑（count > 0 的）
    local unlocked = {}
    for _, b in ipairs(Buildings.buildings) do
        if b.count > 0 then
            unlocked[#unlocked + 1] = b
        end
    end

    -- 如果没有已解锁建筑，则把最便宜的作为候选
    if #unlocked == 0 then
        unlocked[1] = Buildings.buildings[1]
    end

    -- 随机选择（可重复选，同一建筑可多次抽中）
    local chosen = {}
    local count = params.count
    for _ = 1, count do
        local idx = math.random(1, #unlocked)
        local b = unlocked[idx]
        b.count = b.count + 1
        chosen[#chosen + 1] = { name = b.name, icon = b.iconImage or b.icon }
    end

    return { buildings = chosen }
end

--- 执行「立即收割」技能
---@param level number
---@return table result { coins = number, minutes = number }
function SM.ExecuteCpsHarvest(level)
    local params = SkillDefs.cpsHarvest.levels[level]
    if not params then return { coins = 0, minutes = 0 } end

    local cps = GameState.coinsPerSecond
    local seconds = params.minutes * 60
    local gain = cps * seconds
    GameState.coins = GameState.coins + gain

    return { coins = gain, minutes = params.minutes }
end

-- ============================================================================
-- 看广告叠加技能时间
-- ============================================================================

--- 每次看广告增加的时间（秒）= 10分钟
local AD_BONUS_SECONDS = 600

--- 通过看广告为技能叠加时间（可反复叠加）
---@param skillId string
---@param onDone function|nil 完成回调(success)
function SM.ActivateWithAd(skillId, onDone)
    local S = GameState
    local skills = S.skills
    local st = skills[skillId]
    local def = SkillDefs[skillId]
    if not st or not def then
        if onDone then onDone(false) end
        return
    end
    if st.level <= 0 then
        if onDone then onDone(false) end
        return
    end

    -- 直接叠加时间（不消耗体力）
    SM.AddSkillTime(skillId, AD_BONUS_SECONDS)
    if onDone then onDone(true) end
end

--- 为技能叠加指定时间（秒），可在已激活时叠加
---@param skillId string
---@param seconds number 增加的秒数
function SM.AddSkillTime(skillId, seconds)
    local st = GameState.skills[skillId]
    local def = SkillDefs[skillId]
    if not st or not def or st.level <= 0 then return end

    if st.active then
        -- 已激活：叠加时间
        st.timer = st.timer + seconds
        print("[Skill] " .. def.name .. " 叠加: +" .. seconds .. "秒, 总剩余: " .. string.format("%.0f", st.timer) .. "秒")
    else
        -- 未激活：激活并设置时间
        st.active = true
        st.timer = seconds
        if skillId == "speedClick" then speedClickAccum_ = 0 end
        print("[Skill] " .. def.name .. " 激活: " .. seconds .. "秒")
    end
end

--- 获取每次看广告增加的秒数
---@return number
function SM.GetAdBonusSeconds()
    return AD_BONUS_SECONDS
end

-- ============================================================================
-- 解锁技能（免费，0→1）
-- ============================================================================

--- 免费解锁技能（仅 level 0→1）
---@param skillId string
---@param onDone function|nil 完成回调(success)
function SM.UnlockSkill(skillId, onDone)
    local skills = GameState.skills
    local st = skills[skillId]
    local def = SkillDefs[skillId]
    if not st or not def then
        if onDone then onDone(false) end
        return
    end
    if st.level > 0 then
        if onDone then onDone(false) end
        return
    end

    st.level = 1
    print("[Skill] " .. def.name .. " 解锁! Lv.1")
    if onDone then onDone(true) end
end

-- ============================================================================
-- 免费升级技能（level 1+ → level+1，不看广告）
-- ============================================================================

--- 消耗金币升级技能（仅用于 level >= 1 的升级）
---@param skillId string
---@return boolean success
function SM.UpgradeSkill(skillId)
    local skills = GameState.skills
    local st = skills[skillId]
    local def = SkillDefs[skillId]
    if not st or not def then return false end
    if st.level <= 0 then return false end
    if st.level >= def.maxLevel then return false end
    local cost = SkillDefs.GetUpgradeCost(def, st.level)
    if GameState.coins < cost then return false end
    GameState.coins = GameState.coins - cost
    st.level = st.level + 1
    print("[Skill] " .. def.name .. " 升级! Lv." .. st.level .. " (花费 " .. GameState.FormatNumber(cost) .. ")")
    return true
end

-- ============================================================================
-- 查询接口
-- ============================================================================

function SM.GetSkillInfo(skillId)
    local skills = GameState.skills
    local st = skills[skillId]
    local def = SkillDefs[skillId]
    if not st or not def then return nil end

    local level = st.level
    local cost = SkillDefs.GetUpgradeCost(def, level)
    return {
        level       = level,
        maxLevel    = def.maxLevel,
        params      = level > 0 and def.levels[level] or nil,
        nextParams  = level < def.maxLevel and def.levels[level + 1] or nil,
        active      = st.active or false,
        timer       = st.timer or 0,
        def         = def,
        upgradeCost = cost,
        canAfford   = (cost > 0) and (GameState.coins >= cost) or false,
    }
end

function SM.IsActive(skillId)
    local st = GameState.skills[skillId]
    return st ~= nil and st.active == true and (st.timer or 0) > 0
end

function SM.IsAdBusy()
    return false
end

return SM
