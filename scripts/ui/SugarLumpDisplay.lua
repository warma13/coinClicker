-- ============================================================================
-- ui/SugarLumpDisplay.lua
-- 人脉显示组件：顶部小图标 + 时间 + 鼠标悬浮浮窗（Cookie Clicker 风格）
-- ============================================================================

local UI = require("urhox-libs/UI")
local SD = require("config.SugarLumpDefs")

local SLD = {}

-- ============================================================================
-- 内部引用
-- ============================================================================

local uiRoot_ = nil
local widget_ = nil            -- 顶部小图标面板
local lumpImage_ = nil         -- 人脉图标
local countLabel_ = nil        -- 持有数量
local timeLabel_ = nil         -- 倒计时
local tooltip_ = nil           -- 悬浮浮窗
local tooltipType_ = nil       -- 浮窗：类型
local tooltipStage_ = nil      -- 浮窗：阶段
local tooltipTime_ = nil       -- 浮窗：时间
local tooltipTotal_ = nil      -- 浮窗：累计
local tooltipHint_ = nil       -- 浮窗：提示
local manager_ = nil
local onHarvestClick_ = nil

local visible_ = false
local parentNode_ = nil

local LUMP_IMAGE = "image/人脉.png"

-- ============================================================================
-- 格式化小时:分:秒
-- ============================================================================
local function FormatHMS(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    else
        return string.format("%d:%02d", m, s)
    end
end

-- ============================================================================
-- 创建 UI
-- ============================================================================

function SLD.CreateWidget()
    -- 悬浮浮窗（默认隐藏）
    tooltip_ = UI.Panel {
        id = "sugarTooltip",
        position = "absolute",
        top = 52,
        left = 0,
        width = 200,
        backgroundColor = { 20, 18, 30, 240 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 100, 80, 140, 180 },
        padding = 10,
        flexDirection = "column",
        gap = 5,
        visible = false,
        zIndex = 100,
        pointerEvents = "none",
        children = {
            UI.Label {
                id = "ttType",
                text = "",
                fontSize = 12,
                fontColor = { 255, 215, 0, 255 },
            },
            UI.Label {
                id = "ttStage",
                text = "",
                fontSize = 11,
                fontColor = { 220, 180, 255, 255 },
            },
            UI.Label {
                id = "ttTime",
                text = "",
                fontSize = 11,
                fontColor = { 180, 180, 200, 200 },
            },
            UI.Label {
                id = "ttTotal",
                text = "",
                fontSize = 11,
                fontColor = { 180, 180, 200, 200 },
            },
            UI.Label {
                id = "ttHint",
                text = "",
                fontSize = 11,
                fontColor = { 160, 200, 160, 220 },
            },
        },
    }

    -- 顶部小图标
    widget_ = UI.Panel {
        id = "sugarLumpWidget",
        position = "absolute",
        top = 8,
        left = 56,
        flexDirection = "column",
        alignItems = "center",
        pointerEvents = "auto",
        zIndex = 10,
        onPointerDown = function()
            if onHarvestClick_ then
                onHarvestClick_()
            end
        end,
        onPointerEnter = function()
            if tooltip_ then
                SLD.RefreshTooltip()
                tooltip_:SetVisible(true)
            end
        end,
        onPointerLeave = function()
            if tooltip_ then
                tooltip_:SetVisible(false)
            end
        end,
        children = {
            -- 图标 + 数量（横排）
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Panel {
                        id = "sugarLumpImage",
                        width = 32,
                        height = 32,
                        backgroundImage = LUMP_IMAGE,
                        backgroundFit = "contain",
                    },
                    UI.Label {
                        id = "sugarCountLabel",
                        text = "0",
                        fontSize = 14,
                        fontColor = { 255, 215, 0, 255 },
                        fontWeight = "bold",
                    },
                },
            },
            -- 倒计时
            UI.Label {
                id = "sugarTimeLabel",
                text = "",
                fontSize = 9,
                fontColor = { 180, 180, 200, 160 },
                textAlign = "center",
            },
            -- 浮窗挂在这里（相对定位）
            tooltip_,
        },
    }

    return widget_
end

-- ============================================================================
-- 初始化
-- ============================================================================

function SLD.Init(root, manager, harvestCallback)
    uiRoot_ = root
    manager_ = manager
    onHarvestClick_ = harvestCallback

    if not widget_ then return end

    lumpImage_ = root:FindById("sugarLumpImage")
    countLabel_ = root:FindById("sugarCountLabel")
    timeLabel_ = root:FindById("sugarTimeLabel")
    tooltipType_ = root:FindById("ttType")
    tooltipStage_ = root:FindById("ttStage")
    tooltipTime_ = root:FindById("ttTime")
    tooltipTotal_ = root:FindById("ttTotal")
    tooltipHint_ = root:FindById("ttHint")
end

-- ============================================================================
-- 显示/隐藏
-- ============================================================================

function SLD.Show(parent)
    if visible_ or not widget_ then return end
    parentNode_ = parent
    parent:AddChild(widget_)
    visible_ = true

    if uiRoot_ then
        lumpImage_ = uiRoot_:FindById("sugarLumpImage")
        countLabel_ = uiRoot_:FindById("sugarCountLabel")
        timeLabel_ = uiRoot_:FindById("sugarTimeLabel")
        tooltipType_ = uiRoot_:FindById("ttType")
        tooltipStage_ = uiRoot_:FindById("ttStage")
        tooltipTime_ = uiRoot_:FindById("ttTime")
        tooltipTotal_ = uiRoot_:FindById("ttTotal")
        tooltipHint_ = uiRoot_:FindById("ttHint")
    end
end

function SLD.Hide()
    if not visible_ or not widget_ or not parentNode_ then return end
    parentNode_:RemoveChild(widget_)
    visible_ = false
end

function SLD.IsVisible()
    return visible_
end

-- ============================================================================
-- 刷新主显示（每帧或定时调用）
-- ============================================================================

function SLD.Refresh()
    if not visible_ or not manager_ then return end

    local stage = manager_.GetStage()
    local timeLeft = manager_.GetTimeToNextStage()
    local lumps = manager_.GetLumps()

    -- 数量
    if countLabel_ then
        countLabel_:SetText(tostring(lumps))
    end

    -- 倒计时
    if timeLabel_ then
        if stage == SD.STAGE_RIPE then
            timeLabel_:SetText("可收获")
            timeLabel_:SetStyle({ fontColor = { 255, 215, 0, 255 } })
        elseif stage == SD.STAGE_MATURE then
            timeLabel_:SetText("可收获")
            timeLabel_:SetStyle({ fontColor = { 255, 180, 220, 255 } })
        else
            timeLabel_:SetText(FormatHMS(timeLeft))
            timeLabel_:SetStyle({ fontColor = { 180, 180, 200, 160 } })
        end
    end

    -- 图标透明度
    if lumpImage_ then
        if stage == SD.STAGE_COALESCING then
            lumpImage_:SetStyle({ opacity = 0.5 })
        else
            lumpImage_:SetStyle({ opacity = 1.0 })
        end
    end
end

-- ============================================================================
-- 刷新浮窗内容
-- ============================================================================

function SLD.RefreshTooltip()
    if not manager_ then return end

    local stage = manager_.GetStage()
    local timeLeft = manager_.GetTimeToNextStage()
    local lumps = manager_.GetLumps()
    local totalHarvested = manager_.GetTotalHarvested()
    local lumpType = manager_.GetCurrentType()

    -- 类型
    if tooltipType_ then
        if lumpType then
            tooltipType_:SetText(lumpType.icon .. " " .. lumpType.name)
            tooltipType_:SetStyle({ fontColor = lumpType.color or { 255, 215, 0, 255 } })
        else
            tooltipType_:SetText("未生成")
        end
    end

    -- 阶段
    if tooltipStage_ then
        local name = SD.stageNames[stage] or "未知"
        local hint = ""
        if stage == SD.STAGE_MATURE then
            hint = "（收获可能少得1个）"
        elseif stage == SD.STAGE_RIPE then
            hint = "（收获可能多得1个）"
        end
        tooltipStage_:SetText("阶段: " .. name .. hint)
        tooltipStage_:SetStyle({ fontColor = SD.stageColors[stage] or { 200, 200, 200, 255 } })
    end

    -- 时间
    if tooltipTime_ then
        if stage == SD.STAGE_RIPE then
            tooltipTime_:SetText("自动掉落: " .. FormatHMS(timeLeft))
        elseif stage == SD.STAGE_MATURE then
            tooltipTime_:SetText("距深交: " .. FormatHMS(timeLeft))
        else
            tooltipTime_:SetText("距成熟: " .. FormatHMS(timeLeft))
        end
    end

    -- 累计
    if tooltipTotal_ then
        tooltipTotal_:SetText("持有: " .. lumps .. " | 累计: " .. totalHarvested)
    end

    -- 提示
    if tooltipHint_ then
        if stage == SD.STAGE_COALESCING then
            tooltipHint_:SetText("人脉尚在积累中…")
        elseif stage == SD.STAGE_MATURE then
            tooltipHint_:SetText("点击图标收获人脉")
        elseif stage == SD.STAGE_RIPE then
            tooltipHint_:SetText("点击图标收获人脉")
        end
    end
end

return SLD
