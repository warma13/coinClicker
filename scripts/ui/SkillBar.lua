-- ============================================================================
-- ui/SkillBar.lua
-- 底部技能快捷栏 —— 解锁后显示，点击看广告释放技能（无CD）
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local SkillDefs = require("config.SkillDefs")
local FloatingText = require("ui.FloatingText")

local SkillBar = {}

-- 内部引用
local bar_         = nil
local manager_     = nil   -- GameManager
local btnWidgets_  = {}    -- skillId -> { btn, icon, activeOverlay, timerLabel, glowBorder }
local lastSnap_    = ""

local ICON_SIZE = 48
local ICON_GAP  = 6

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
end

function SkillBar.IsVisible()
    return bar_ and bar_:IsVisible()
end

-- ============================================================================
-- 内部：构建单个技能按钮
-- ============================================================================

function BuildSkillBtn(def)
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

    -- 主按钮
    w.btn = UI.Panel {
        width = ICON_SIZE, height = ICON_SIZE,
        borderRadius = 8, borderWidth = 1,
        borderColor = { 80, 180, 80, 150 },
        backgroundColor = { 30, 60, 35, 240 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onPointerDown = function(event)
            if not manager_ then return end
            local st = GameState.skills[def.id]
            if st and st.level > 0 and not st.active then
                local cost = SkillDefs.GetStaminaCost(def, st.level)
                if GameState.stamina < cost then
                    local dpr = graphics:GetDPR()
                    local x = (event and event.x) or (input.mousePosition.x / dpr)
                    local y = (event and event.y) or (input.mousePosition.y / dpr)
                    FloatingText.Show("体力不足", x, y, { 255, 100, 100, 255 })
                    return
                end
            end
            manager_.OnActivateSkill(def.id)
            lastSnap_ = ""
            SkillBar.Refresh()
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

function UpdateBtn(w, def)
    local SM = manager_.GetSkillManager()
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
        -- 激活中：金色边框 + 倒计时，不可点击
        w.btn:SetStyle {
            backgroundColor = { 45, 40, 20, 240 },
            borderColor = { 200, 170, 60, 180 },
            pointerEvents = "none",
        }
        w.icon:SetStyle { opacity = 1.0 }
        w.glowBorder:SetVisible(true)
        w.glowBorder:SetStyle { borderColor = { 255, 200, 50, 200 } }
        w.activeOverlay:SetVisible(true)
        w.timerLabel:SetText(string.format("%.0f", info.timer))
    else
        local staCost = SkillDefs.GetStaminaCost(def, level)
        local canAfford = GameState.stamina >= staCost
        if canAfford then
            -- 就绪：可激活
            w.btn:SetStyle {
                backgroundColor = { 30, 60, 35, 240 },
                borderColor = { 80, 180, 80, 150 },
                pointerEvents = "auto",
            }
            w.icon:SetStyle { opacity = 1.0 }
        else
            -- 体力不足：置灰
            w.btn:SetStyle {
                backgroundColor = { 40, 40, 45, 240 },
                borderColor = { 80, 80, 85, 120 },
                pointerEvents = "auto",
            }
            w.icon:SetStyle { opacity = 0.35 }
        end
        w.glowBorder:SetVisible(false)
        w.activeOverlay:SetVisible(false)
        w.timerLabel:SetText("")
    end
end

-- ============================================================================
-- 内部：快照
-- ============================================================================

function MakeSnapshot()
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
