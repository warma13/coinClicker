-- ============================================================================
-- ui/SkillBar.lua
-- 底部技能快捷栏 —— 点击弹出技能详情弹窗，看广告叠加技能时间
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local SkillDefs = require("config.SkillDefs")
local AdManager = require("core.AdManager")
local AudioManager = require("core.AudioManager")

local SkillBar = {}

-- 内部引用
local bar_         = nil
local uiRoot_      = nil
local manager_     = nil   -- GameManager
local btnWidgets_  = {}    -- skillId -> { btn, icon, activeOverlay, timerLabel, glowBorder }
-- 每个按钮的缓存状态存在 w.cachedLevel / w.cachedActive / w.cachedVisible 中
-- 无需全局快照

-- 弹窗引用
local popup_        = nil   -- 弹窗根节点
local popupSkillId_ = nil   -- 当前弹窗显示的技能 ID
local popupTimerLabel_ = nil
local popupNameLabel_  = nil
local popupDescLabel_  = nil

-- 防抖：防止弹窗遮罩 onPointerDown 关闭后，onTap 立即重开
local justClosedId_    = nil
local justClosedClock_ = 0

local ICON_SIZE = 48
local ICON_GAP  = 6

-- 前向声明
local BuildSkillBtn
local InvalidateCache
local ShowPopup
local HidePopup
local BuildPopup
local FormatTime

-- ============================================================================
-- 时间格式化
-- ============================================================================

---@diagnostic disable-next-line: redefined-local
FormatTime = function(seconds)
    if seconds <= 0 then return "未激活" end
    local s = math.floor(seconds)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sec = s % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, sec)
    else
        return string.format("%02d:%02d", m, sec)
    end
end

-- ============================================================================
-- 创建 UI 定义（absolute 浮动）
-- ============================================================================

function SkillBar.Create()
    return UI.Panel {
        id = "skillBar",
        position = "absolute",
        right = "30%",
        bottom = 12,
        marginRight = 4,
        flexDirection = "column",
        gap = ICON_GAP,
        zIndex = 50,
        pointerEvents = "auto",
    }
end

-- ============================================================================
-- 初始化
-- ============================================================================

function SkillBar.Init(root, gm)
    manager_ = gm
    uiRoot_ = root
    bar_ = root:FindById("skillBar")
    if not bar_ then return end

    -- 为每个技能预创建按钮
    for _, def in ipairs(SkillDefs.list) do
        local w = BuildSkillBtn(def)
        btnWidgets_[def.id] = w
        bar_:AddChild(w.btn)
    end
end

-- ============================================================================
-- 刷新（每帧或定期调用）
-- ============================================================================

function SkillBar.Refresh()
    if not bar_ or not manager_ then return end

    local SM = manager_.GetSkillManager()
    if not SM then return end

    local hasAny = false
    for _, def in ipairs(SkillDefs.list) do
        local w = btnWidgets_[def.id]
        if not w then goto continue end

        local st = GameState.skills[def.id]
        local level = (st and st.level) or 0
        local active = (st and st.active) or false
        local timer = (st and st.timer) or 0

        -- 可见性
        local shouldShow = (level > 0)
        if shouldShow then hasAny = true end
        if w.cachedVisible ~= shouldShow then
            w.cachedVisible = shouldShow
            w.btn:SetVisible(shouldShow)
        end
        if not shouldShow then goto continue end

        -- 状态变更（level/active）才做 SetStyle（极少发生，不影响点击）
        if w.cachedLevel ~= level or w.cachedActive ~= active then
            w.cachedLevel = level
            w.cachedActive = active
            if active then
                w.btn:SetStyle {
                    backgroundColor = { 45, 40, 20, 240 },
                    borderColor = { 200, 170, 60, 180 },
                }
                w.glowBorder:SetVisible(true)
                w.activeOverlay:SetVisible(true)
            else
                w.btn:SetStyle {
                    backgroundColor = { 30, 60, 35, 240 },
                    borderColor = { 80, 180, 80, 150 },
                }
                w.glowBorder:SetVisible(false)
                w.activeOverlay:SetVisible(false)
                w.timerLabel:SetText("")
            end
        end

        -- 倒计时文字：只调 SetText，不碰 SetStyle，绝不吞点击
        if active and timer > 0 then
            w.timerLabel:SetText(FormatTime(timer))
        end

        ::continue::
    end
    bar_:SetVisible(hasAny)

    -- 同步刷新弹窗倒计时
    if popup_ and popupSkillId_ and popupTimerLabel_ then
        local st = GameState.skills[popupSkillId_]
        if st and st.active and st.timer > 0 then
            popupTimerLabel_:SetText(FormatTime(st.timer))
        else
            popupTimerLabel_:SetText("未激活")
        end
    end
end

function SkillBar.IsVisible()
    return bar_ and bar_:IsVisible()
end

-- ============================================================================
-- 弹窗：技能详情 + 看广告叠加时间
-- ============================================================================

---@diagnostic disable-next-line: redefined-local
BuildPopup = function(def)
    local skillId = def.id
    local SM = manager_ and manager_.GetSkillManager()
    local adBonusSec = SM and SM.GetAdBonusSeconds() or 600
    local adBonusMin = math.floor(adBonusSec / 60)
    local isInstant = def.instant == true

    local st = GameState.skills[skillId]
    -- 体力激活给基础持续时间，广告给额外叠加时间
    local baseDuration = 1800
    if st and st.level > 0 and not isInstant then
        local params = def.levels[st.level]
        if params and params.duration then
            baseDuration = params.duration
        end
    end
    local baseMin = math.floor(baseDuration / 60)

    -- 名称
    popupNameLabel_ = UI.Label {
        text = def.name,
        fontSize = 18,
        fontColor = { 255, 240, 200, 255 },
        textAlign = "center",
    }

    -- 描述（即时技能显示当前等级参数）
    local descText = def.desc
    if st and st.level > 0 then
        local params = def.levels[st.level]
        if params then
            if skillId == "speedClick" then
                local mins = math.floor(params.duration / 60)
                descText = string.format("每秒 %.0f 次签单 · 持续 %d分钟", params.rate, mins)
            elseif skillId == "cpsDouble" then
                local mins = math.floor(params.duration / 60)
                descText = string.format("CPS ×%.1f · 持续 %d分钟", params.multiplier, mins)
            elseif skillId == "clickBoost" then
                local mins = math.floor(params.duration / 60)
                descText = string.format("签单收益 ×%.1f · 持续 %d分钟", params.multiplier, mins)
            elseif skillId == "randomBuildings" then
                descText = string.format("随机获得 %d 个已解锁产业各+1", params.count)
            elseif skillId == "cpsHarvest" then
                descText = string.format("立即获取 %d 分钟CPS收益", params.minutes)
            end
        end
    end
    popupDescLabel_ = UI.Label {
        text = descText,
        fontSize = 12,
        fontColor = { 180, 170, 200, 200 },
        textAlign = "center",
    }

    -- 关闭按钮
    local closeBtn = UI.Panel {
        position = "absolute",
        top = 8, right = 8,
        width = 28, height = 28,
        borderRadius = 14,
        backgroundColor = { 80, 70, 100, 200 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onPointerDown = function()
            HidePopup()
        end,
        children = {
            UI.Label {
                text = "✕", fontSize = 14,
                fontColor = { 200, 200, 220, 255 },
            },
        },
    }

    -- 体力消耗
    local staminaCost = SkillDefs.GetStaminaCost(def, st and st.level or 1)
    local canAfford = (GameState.stamina >= staminaCost)
    local staminaBtnBg = canAfford and { 50, 100, 140, 255 } or { 60, 60, 70, 200 }
    local staminaBtnBorder = canAfford and { 80, 160, 220, 200 } or { 80, 80, 90, 150 }
    local staminaBtnTextColor = canAfford and { 255, 255, 255, 255 } or { 120, 120, 130, 200 }

    local cardChildren = {
        closeBtn,
        -- 技能图标
        UI.Panel {
            width = 56, height = 56,
            backgroundImage = def.icon,
            backgroundFit = "contain",
            marginTop = 8,
        },
        popupNameLabel_,
        popupDescLabel_,
        -- 分隔线
        UI.Panel {
            width = "80%", height = 1,
            backgroundColor = { 100, 80, 160, 80 },
        },
    }

    if isInstant then
        -- ======== 即时型技能弹窗 ========
        popupTimerLabel_ = nil  -- 即时技能无倒计时

        -- 即时技能执行回调
        local function doInstantEffect()
            if not manager_ then return end
            local sm = manager_.GetSkillManager()
            if not sm then return end
            local level = GameState.skills[skillId].level
            if level <= 0 then return end

            local result
            if skillId == "randomBuildings" then
                result = sm.ExecuteRandomBuildings(level)
                -- 重新计算产出
                if manager_.RecalcProduction then manager_.RecalcProduction() end
            elseif skillId == "cpsHarvest" then
                result = sm.ExecuteCpsHarvest(level)
            end

            AudioManager.PlayBtnClick()
            InvalidateCache()
            HidePopup()
            SkillBar.Refresh()
            if manager_.RefreshAllUI then
                manager_.RefreshAllUI()
            end

            -- 显示浮动文字
            if result and manager_.ShowFloatingText then
                if skillId == "randomBuildings" and result.buildings then
                    local names = {}
                    for _, b in ipairs(result.buildings) do
                        names[#names + 1] = b.name
                    end
                    manager_.ShowFloatingText("扩张! +" .. table.concat(names, ", "), { 100, 220, 200, 255 })
                elseif skillId == "cpsHarvest" and result.coins then
                    manager_.ShowFloatingText("收割! +" .. GameState.FormatNumber(result.coins), { 255, 220, 80, 255 })
                end
            end
        end

        -- 消耗体力释放按钮
        local staminaBtn = UI.Panel {
            flexDirection = "row",
            alignItems = "center", justifyContent = "center",
            paddingLeft = 20, paddingRight = 20,
            paddingTop = 10, paddingBottom = 10,
            borderRadius = 8,
            backgroundColor = staminaBtnBg,
            borderWidth = 1,
            borderColor = staminaBtnBorder,
            pointerEvents = "auto",
            gap = 6,
            onPointerDown = function()
                local cost = SkillDefs.GetStaminaCost(def, GameState.skills[skillId].level)
                if GameState.stamina < cost then return end
                GameState.stamina = GameState.stamina - cost
                doInstantEffect()
            end,
            children = {
                UI.Label {
                    text = "消耗体力 " .. staminaCost .. " 释放",
                    fontSize = 13,
                    fontColor = staminaBtnTextColor,
                },
            },
        }

        -- 看广告释放按钮
        local adBtn = UI.Panel {
            flexDirection = "row",
            alignItems = "center", justifyContent = "center",
            paddingLeft = 20, paddingRight = 20,
            paddingTop = 10, paddingBottom = 10,
            borderRadius = 8,
            backgroundColor = { 60, 130, 60, 255 },
            borderWidth = 1,
            borderColor = { 100, 200, 100, 200 },
            pointerEvents = "auto",
            gap = 6,
            onPointerDown = function()
                if not manager_ then return end
                AdManager.ShowRewardAd(function()
                    doInstantEffect()
                end)
            end,
            children = {
                UI.Label {
                    text = "看广告释放",
                    fontSize = 14,
                    fontColor = { 255, 255, 255, 255 },
                },
            },
        }

        -- 即时技能提示
        cardChildren[#cardChildren + 1] = UI.Label {
            text = "即时生效",
            fontSize = 11,
            fontColor = { 255, 200, 100, 180 },
        }
        cardChildren[#cardChildren + 1] = staminaBtn
        cardChildren[#cardChildren + 1] = adBtn
    else
        -- ======== 持续型技能弹窗 ========
        local timerText = (st and st.active and st.timer > 0)
            and FormatTime(st.timer) or "未激活"
        popupTimerLabel_ = UI.Label {
            text = timerText,
            fontSize = 28,
            fontColor = { 255, 220, 80, 255 },
            textAlign = "center",
        }

        -- 消耗体力按钮
        local staminaBtn = UI.Panel {
            flexDirection = "row",
            alignItems = "center", justifyContent = "center",
            paddingLeft = 20, paddingRight = 20,
            paddingTop = 10, paddingBottom = 10,
            borderRadius = 8,
            backgroundColor = staminaBtnBg,
            borderWidth = 1,
            borderColor = staminaBtnBorder,
            pointerEvents = "auto",
            gap = 6,
            onPointerDown = function()
                if not manager_ then return end
                local sm = manager_.GetSkillManager()
                if not sm then return end
                local cost = SkillDefs.GetStaminaCost(def, GameState.skills[skillId].level)
                if GameState.stamina < cost then return end
                GameState.stamina = GameState.stamina - cost
                sm.AddSkillTime(skillId, baseDuration)
                AudioManager.PlayBtnClick()
                InvalidateCache()
                SkillBar.Refresh()
                if manager_.RefreshAllUI then
                    manager_.RefreshAllUI()
                end
            end,
            children = {
                UI.Label {
                    text = "消耗体力 " .. staminaCost .. " +" .. baseMin .. "分钟",
                    fontSize = 13,
                    fontColor = staminaBtnTextColor,
                },
            },
        }

        -- 看广告按钮
        local adBtn = UI.Panel {
            flexDirection = "row",
            alignItems = "center", justifyContent = "center",
            paddingLeft = 20, paddingRight = 20,
            paddingTop = 10, paddingBottom = 10,
            borderRadius = 8,
            backgroundColor = { 60, 130, 60, 255 },
            borderWidth = 1,
            borderColor = { 100, 200, 100, 200 },
            pointerEvents = "auto",
            gap = 6,
            onPointerDown = function()
                if not manager_ then return end
                AdManager.ShowRewardAd(function()
                    local sm = manager_.GetSkillManager()
                    if sm then
                        sm.AddSkillTime(skillId, baseDuration)
                        AudioManager.PlayBtnClick()
                        InvalidateCache()
                        SkillBar.Refresh()
                        if manager_.RefreshAllUI then
                            manager_.RefreshAllUI()
                        end
                    end
                end)
            end,
            children = {
                UI.Label {
                    text = "看广告 +" .. baseMin .. "分钟",
                    fontSize = 14,
                    fontColor = { 255, 255, 255, 255 },
                },
            },
        }

        cardChildren[#cardChildren + 1] = UI.Label {
            text = "剩余时间",
            fontSize = 11,
            fontColor = { 140, 130, 170, 180 },
        }
        cardChildren[#cardChildren + 1] = popupTimerLabel_
        cardChildren[#cardChildren + 1] = staminaBtn
        cardChildren[#cardChildren + 1] = adBtn
        cardChildren[#cardChildren + 1] = UI.Label {
            text = "时间可叠加",
            fontSize = 10,
            fontColor = { 120, 110, 140, 150 },
            textAlign = "center",
        }
    end

    -- 弹窗主体
    popup_ = UI.Panel {
        id = "skillPopup",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        zIndex = 500,
        pointerEvents = "auto",
        onPointerDown = function(event)
            HidePopup()
        end,
        children = {
            UI.Panel {
                width = 260,
                flexDirection = "column",
                alignItems = "center",
                padding = 20,
                gap = 12,
                borderRadius = 16,
                backgroundColor = { 30, 25, 45, 245 },
                borderWidth = 1,
                borderColor = { 100, 80, 160, 180 },
                pointerEvents = "auto",
                onPointerDown = function()
                    -- 阻止冒泡
                end,
                children = cardChildren,
            },
        },
    }

    popupSkillId_ = skillId
    return popup_
end

---@diagnostic disable-next-line: redefined-local
ShowPopup = function(def)
    HidePopup()
    if not uiRoot_ then return end

    local popupWidget = BuildPopup(def)
    uiRoot_:AddChild(popupWidget)
end

---@diagnostic disable-next-line: redefined-local
HidePopup = function()
    if popup_ then
        -- 记录刚关闭的技能，防止 onTap 立即重开
        justClosedId_    = popupSkillId_
        justClosedClock_ = os.clock()

        popup_:Remove()
        popup_ = nil
    end
    popupSkillId_ = nil
    popupTimerLabel_ = nil
    popupNameLabel_ = nil
    popupDescLabel_ = nil
end

function SkillBar.HidePopup()
    HidePopup()
end

-- ============================================================================
-- 内部：构建单个技能按钮
-- ============================================================================

---@diagnostic disable-next-line: redefined-local
BuildSkillBtn = function(def)
    local w = {}

    -- 激活倒计时文字
    w.timerLabel = UI.Label {
        text = "", fontSize = 12,
        fontColor = { 255, 220, 80, 255 },
        textAlign = "center",
    }

    -- 激活中遮罩（半透明金色）
    w.activeOverlay = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 80 },
        borderRadius = 8,
        justifyContent = "center", alignItems = "center",
        pointerEvents = "none",
        children = { w.timerLabel },
    }

    -- 激活发光边框
    w.glowBorder = UI.Panel {
        position = "absolute",
        top = -2, left = -2,
        width = ICON_SIZE + 4, height = ICON_SIZE + 4,
        borderRadius = 10,
        borderWidth = 2,
        borderColor = { 255, 200, 50, 200 },
        pointerEvents = "none",
    }

    -- 技能图标
    w.icon = UI.Panel {
        width = ICON_SIZE - 8, height = ICON_SIZE - 8,
        backgroundImage = def.icon,
        backgroundFit = "contain",
        pointerEvents = "none",
    }

    -- 主按钮（点击弹出弹窗）
    w.btn = UI.Panel {
        width = ICON_SIZE, height = ICON_SIZE,
        borderRadius = 8, borderWidth = 1,
        borderColor = { 80, 180, 80, 150 },
        backgroundColor = { 30, 60, 35, 240 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onTap = function()
            if not manager_ then return end
            local st = GameState.skills[def.id]
            if st and st.level > 0 then
                -- 防抖：遮罩 onPointerDown 刚关闭同一技能弹窗，跳过本次 onTap
                if justClosedId_ == def.id and (os.clock() - justClosedClock_) < 0.3 then
                    justClosedId_ = nil
                    return
                end
                -- 开关模式：已打开同一技能弹窗则关闭
                if popupSkillId_ == def.id then
                    HidePopup()
                else
                    ShowPopup(def)
                end
            end
        end,
        children = {
            w.icon,
            w.activeOverlay,
            w.glowBorder,
        },
    }

    return w
end

-- ============================================================================
-- 内部：清除缓存，强制下次 Refresh 重新应用视觉状态
-- ============================================================================

---@diagnostic disable-next-line: redefined-local
InvalidateCache = function()
    for _, w in pairs(btnWidgets_) do
        w.cachedLevel = nil
        w.cachedActive = nil
        w.cachedVisible = nil
    end
end

return SkillBar
