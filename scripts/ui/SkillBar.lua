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
local lastSnap_    = ""

-- 弹窗引用
local popup_        = nil   -- 弹窗根节点
local popupSkillId_ = nil   -- 当前弹窗显示的技能 ID
local popupTimerLabel_ = nil
local popupNameLabel_  = nil
local popupDescLabel_  = nil

local ICON_SIZE = 48
local ICON_GAP  = 6

-- 前向声明
local BuildSkillBtn
local UpdateBtn
local MakeSnapshot
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
        zIndex = 15,
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

    local snap = MakeSnapshot()
    if snap == lastSnap_ then return end
    lastSnap_ = snap

    local hasAny = false
    for _, def in ipairs(SkillDefs.list) do
        local w = btnWidgets_[def.id]
        if w then
            UpdateBtn(w, def)
            if GameState.skills[def.id] and GameState.skills[def.id].level > 0 then
                hasAny = true
            end
        end
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
    local bonusSec = SM and SM.GetAdBonusSeconds() or 1800
    local bonusMin = math.floor(bonusSec / 60)

    local st = GameState.skills[skillId]
    local timerText = (st and st.active and st.timer > 0)
        and FormatTime(st.timer) or "未激活"

    -- 名称
    popupNameLabel_ = UI.Label {
        text = def.name,
        fontSize = 18,
        fontColor = { 255, 240, 200, 255 },
        textAlign = "center",
    }

    -- 描述
    popupDescLabel_ = UI.Label {
        text = def.desc,
        fontSize = 12,
        fontColor = { 180, 170, 200, 200 },
        textAlign = "center",
    }

    -- 倒计时
    popupTimerLabel_ = UI.Label {
        text = timerText,
        fontSize = 28,
        fontColor = { 255, 220, 80, 255 },
        textAlign = "center",
    }

    -- 消耗体力按钮
    local staminaCost = SkillDefs.GetStaminaCost(def, st and st.level or 1)
    local canAfford = (GameState.stamina >= staminaCost)
    local staminaBtnBg = canAfford and { 50, 100, 140, 255 } or { 60, 60, 70, 200 }
    local staminaBtnBorder = canAfford and { 80, 160, 220, 200 } or { 80, 80, 90, 150 }
    local staminaBtnTextColor = canAfford and { 255, 255, 255, 255 } or { 120, 120, 130, 200 }

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
            -- 扣除体力
            GameState.stamina = GameState.stamina - cost
            -- 叠加 30 分钟
            sm.AddSkillTime(skillId, bonusSec)
            AudioManager.PlayBtnClick()
            lastSnap_ = ""
            SkillBar.Refresh()
            if manager_.RefreshAllUI then
                manager_.RefreshAllUI()
            end
        end,
        children = {
            UI.Label {
                text = "消耗体力 " .. staminaCost .. " +" .. bonusMin .. "分钟",
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
            -- 通过 AdManager 看广告，成功后叠加时间
            AdManager.ShowRewardAd(function()
                local sm = manager_.GetSkillManager()
                if sm then
                    sm.AddSkillTime(skillId, bonusSec)
                    AudioManager.PlayBtnClick()
                    lastSnap_ = ""
                    SkillBar.Refresh()
                    -- 刷新技能面板
                    if manager_.RefreshAllUI then
                        manager_.RefreshAllUI()
                    end
                end
            end)
        end,
        children = {
            UI.Label {
                text = "看广告 +" .. bonusMin .. "分钟",
                fontSize = 14,
                fontColor = { 255, 255, 255, 255 },
            },
        },
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

    -- 弹窗主体
    popup_ = UI.Panel {
        id = "skillPopup",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        zIndex = 500,
        pointerEvents = "auto",
        -- 半透明背景遮罩（点击关闭）
        onPointerDown = function(event)
            -- 仅当点击遮罩区域（非弹窗内容）关闭
            HidePopup()
        end,
        children = {
            -- 弹窗卡片
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
                    -- 阻止冒泡，点击弹窗内容不关闭
                end,
                children = {
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
                    -- 剩余时间标签
                    UI.Label {
                        text = "剩余时间",
                        fontSize = 11,
                        fontColor = { 140, 130, 170, 180 },
                    },
                    popupTimerLabel_,
                    -- 体力释放按钮
                    staminaBtn,
                    -- 广告按钮
                    adBtn,
                    -- 提示文字
                    UI.Label {
                        text = "时间可叠加",
                        fontSize = 10,
                        fontColor = { 120, 110, 140, 150 },
                        textAlign = "center",
                    },
                },
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
        onPointerDown = function()
            if not manager_ then return end
            local st = GameState.skills[def.id]
            if st and st.level > 0 then
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
-- 内部：更新按钮状态
-- ============================================================================

---@diagnostic disable-next-line: redefined-local
UpdateBtn = function(w, def)
    local SM = manager_ and manager_.GetSkillManager()
    if not SM then return end

    local info = SM.GetSkillInfo(def.id)
    if not info then
        w.btn:SetVisible(false)
        return
    end

    local level = info.level
    if level <= 0 then
        w.btn:SetVisible(false)
        return
    end
    w.btn:SetVisible(true)

    local isActive = info.active

    if isActive then
        -- 激活中：金色边框 + 倒计时
        w.btn:SetStyle {
            backgroundColor = { 45, 40, 20, 240 },
            borderColor = { 200, 170, 60, 180 },
            pointerEvents = "auto",
        }
        w.icon:SetStyle { opacity = 1.0 }
        w.glowBorder:SetVisible(true)
        w.glowBorder:SetStyle { borderColor = { 255, 200, 50, 200 } }
        w.activeOverlay:SetVisible(true)
        w.timerLabel:SetText(FormatTime(info.timer))
    else
        -- 就绪：可点击查看/激活
        w.btn:SetStyle {
            backgroundColor = { 30, 60, 35, 240 },
            borderColor = { 80, 180, 80, 150 },
            pointerEvents = "auto",
        }
        w.icon:SetStyle { opacity = 1.0 }
        w.glowBorder:SetVisible(false)
        w.activeOverlay:SetVisible(false)
        w.timerLabel:SetText("")
    end
end

-- ============================================================================
-- 内部：快照
-- ============================================================================

---@diagnostic disable-next-line: redefined-local
MakeSnapshot = function()
    local parts = {}
    for _, def in ipairs(SkillDefs.list) do
        local st = GameState.skills[def.id]
        if st then
            parts[#parts + 1] = string.format("%s:%d:%s:%.0f",
                def.id, st.level,
                tostring(st.active or false), st.timer or 0)
        end
    end
    parts[#parts + 1] = string.format("sta:%d", math.floor(GameState.stamina))
    return table.concat(parts, "|")
end

return SkillBar
