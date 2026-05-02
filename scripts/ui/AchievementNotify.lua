-- ============================================================================
-- ui/AchievementNotify.lua
-- 成就解锁弹窗通知
-- · 从顶部滑入，3 秒后上移滑出并移除
-- · 新弹窗出现时将已有弹窗向下推移，新弹窗重新开始计时
-- · 多个弹窗同时可见，逐个超时移除
-- ============================================================================

local UI = require("urhox-libs/UI")
local AudioManager = require("core.AudioManager")

local AchievementNotify = {}

-- ======== 常量 ========
local ITEM_HEIGHT = 56       -- 单个弹窗高度
local ITEM_GAP = 12          -- 弹窗间距
local SHOW_DURATION = 3.0    -- 停留时长（秒）
local SLIDE_SPEED = 400      -- 滑入/滑出速度（像素/秒）
local START_Y = -ITEM_HEIGHT -- 初始位置（屏幕外）
local TARGET_TOP = 12        -- 第一个弹窗的目标 top
local ITEM_WIDTH = 300       -- 弹窗宽度

-- ======== 状态 ========
-- 每个活跃弹窗: { widget, timer, state, currentY, targetY }
-- state: "sliding_in" | "visible" | "sliding_out" | "done"
local activeItems_ = {}
local container_ = nil

-- ============================================================================
-- 创建容器（absolute 定位，顶部居中）
-- ============================================================================

function AchievementNotify.Create()
    return UI.Panel {
        id = "achieveNotifyContainer",
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        height = 0,               -- 不占布局空间
        alignItems = "center",    -- 子元素水平居中
        zIndex = 200,
        pointerEvents = "none",
    }
end

function AchievementNotify.Init(root)
    container_ = root:FindById("achieveNotifyContainer")
end

-- ============================================================================
-- 创建单个弹窗控件
-- ============================================================================

local function CreateNotifyWidget(achievement)
    return UI.Panel {
        position = "absolute",
        top = START_Y,
        width = ITEM_WIDTH,
        flexDirection = "row",
        alignItems = "center",
        padding = 10,
        gap = 8,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 255, 215, 0, 160 },
        backgroundColor = { 35, 32, 22, 235 },
        pointerEvents = "none",
        children = {
            -- 图标
            UI.Panel {
                width = 32, height = 32,
                backgroundImage = achievement.iconImage or nil,
                backgroundFit = "contain",
                justifyContent = "center", alignItems = "center",
                children = (not achievement.iconImage) and {
                    UI.Label {
                        text = achievement.icon or "?",
                        fontSize = 22,
                        textAlign = "center",
                    },
                } or nil,
            },
            -- 文本
            UI.Panel {
                flex = 1, flexShrink = 1, gap = 1,
                children = {
                    UI.Label {
                        text = achievement.name or "",
                        fontSize = 13,
                        fontColor = { 255, 215, 0, 255 },
                    },
                    UI.Label {
                        text = achievement.desc or "",
                        fontSize = 10,
                        fontColor = { 190, 190, 200, 200 },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 重新计算所有弹窗的目标 Y（从顶部向下排列）
-- ============================================================================

local function RecalcTargets()
    local y = TARGET_TOP
    for i = 1, #activeItems_ do
        activeItems_[i].targetY = y
        y = y + ITEM_HEIGHT + ITEM_GAP
    end
end

-- ============================================================================
-- 入队 / 显示
-- ============================================================================

--- 将成就加入通知
---@param achievement table { icon, iconImage, name, desc }
function AchievementNotify.Enqueue(achievement)
    if not container_ then return end

    local widget = CreateNotifyWidget(achievement)
    container_:AddChild(widget)

    local item = {
        widget = widget,
        timer = SHOW_DURATION,
        state = "sliding_in",
        currentY = START_Y,
        targetY = TARGET_TOP,    -- 临时，RecalcTargets 会覆盖
    }

    -- 新弹窗插入到列表头部（最上方）
    table.insert(activeItems_, 1, item)
    RecalcTargets()

    AudioManager.PlaySFX("click")
end

-- ============================================================================
-- 帧更新
-- ============================================================================

function AchievementNotify.Update(dt)
    if #activeItems_ == 0 then return end

    local needRecalc = false

    for i = #activeItems_, 1, -1 do
        local item = activeItems_[i]

        if item.state == "sliding_in" then
            -- 向目标位置滑动
            if item.currentY < item.targetY then
                item.currentY = math.min(item.currentY + SLIDE_SPEED * dt, item.targetY)
            elseif item.currentY > item.targetY then
                item.currentY = math.max(item.currentY - SLIDE_SPEED * dt, item.targetY)
            end
            -- 到达目标
            if math.abs(item.currentY - item.targetY) < 1 then
                item.currentY = item.targetY
                item.state = "visible"
            end
            item.widget:SetStyle({ top = math.floor(item.currentY) })

        elseif item.state == "visible" then
            -- 跟随目标位置（被新弹窗推下去时）
            if math.abs(item.currentY - item.targetY) > 1 then
                if item.currentY < item.targetY then
                    item.currentY = math.min(item.currentY + SLIDE_SPEED * dt, item.targetY)
                else
                    item.currentY = math.max(item.currentY - SLIDE_SPEED * dt, item.targetY)
                end
                item.widget:SetStyle({ top = math.floor(item.currentY) })
            end

            -- 计时
            item.timer = item.timer - dt
            if item.timer <= 0 then
                item.state = "sliding_out"
                item.targetY = START_Y
            end

        elseif item.state == "sliding_out" then
            -- 向上滑出
            item.currentY = item.currentY - SLIDE_SPEED * dt
            item.widget:SetStyle({ top = math.floor(item.currentY) })
            if item.currentY <= START_Y then
                item.state = "done"
            end

        elseif item.state == "done" then
            -- 移除
            container_:RemoveChild(item.widget)
            table.remove(activeItems_, i)
            needRecalc = true
        end
    end

    if needRecalc then
        RecalcTargets()
    end
end

return AchievementNotify
