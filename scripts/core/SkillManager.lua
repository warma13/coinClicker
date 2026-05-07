-- ============================================================================
-- core/SkillManager.lua
-- 技能系统核心逻辑 —— 看广告解锁/升级/释放，无CD
-- ============================================================================
---@diagnostic disable: undefined-global

local GameState = require("core.GameState")
local SkillDefs = require("config.SkillDefs")
local SM = {}

-- 内部状态
local speedClickAccum_ = 0      -- 疾速点击累计时间
local onClickCallback_ = nil    -- 点击回调 fn(x, y, skipRateLimit)

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
            S.skills[def.id] = { level = 0, active = false, timer = 0 }
        end
        -- 迁移旧存档：移除 cooldown 字段
        local st = S.skills[def.id]
        st.cooldown = nil
    end
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
    local skills = GameState.skills

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
-- 看广告激活技能（无CD）
-- ============================================================================

--- 消耗体力激活技能
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
    if st.active then
        if onDone then onDone(false) end
        return
    end
    -- 体力不足
    local staCost = SkillDefs.GetStaminaCost(def, st.level)
    if S.stamina < staCost then
        print("[Skill] 体力不足: " .. S.stamina .. "/" .. staCost)
        if onDone then onDone(false) end
        return
    end

    -- 消耗体力
    S.stamina = S.stamina - staCost
    SM._DoActivate(skillId)
    if onDone then onDone(true) end
end

--- 内部：实际激活逻辑
function SM._DoActivate(skillId)
    local st = GameState.skills[skillId]
    local def = SkillDefs[skillId]
    if not st or not def then return end

    local params = def.levels[st.level]
    if not params or not params.duration then return end

    st.active = true
    st.timer = params.duration

    if skillId == "speedClick" then speedClickAccum_ = 0 end

    print("[Skill] " .. def.name .. " 激活: " .. params.duration .. "秒")
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
