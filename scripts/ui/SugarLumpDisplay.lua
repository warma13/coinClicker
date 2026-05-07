-- ============================================================================
-- ui/SugarLumpDisplay.lua
-- 人脉显示组件：顶部小图标 + 点击弹出浮窗 + 浮窗内收获/关闭按钮
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
local tooltip_ = nil           -- 浮窗
local tooltipType_ = nil       -- 浮窗：类型
local tooltipStage_ = nil      -- 浮窗：阶段
local tooltipTime_ = nil       -- 浮窗：时间
local tooltipTotal_ = nil      -- 浮窗：累计
local tooltipHint_ = nil       -- 浮窗：提示
local harvestBtn_ = nil        -- 浮窗：收获按钮
local confirmOverlay_ = nil    -- 确认弹窗遮罩
local backdropOverlay_ = nil   -- 点击外部关闭的透明遮罩
local manager_ = nil
local onHarvestClick_ = nil

local visible_ = false
local tooltipOpen_ = false     -- 浮窗是否打开
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
-- 关闭浮窗
-- ============================================================================
local function CloseTooltip()
    if tooltip_ then
        tooltip_:SetVisible(false)
    end
    if backdropOverlay_ then
        backdropOverlay_:SetVisible(false)
    end
    tooltipOpen_ = false
end

local function OpenTooltip()
    if tooltipOpen_ then return end
    SLD.RefreshTooltip()
    if tooltip_ then
        tooltip_:SetVisible(true)
    end
    if backdropOverlay_ then
        backdropOverlay_:SetVisible(true)
    end
    tooltipOpen_ = true
end

-- ============================================================================
-- 关闭确认弹窗
-- ============================================================================
local function CloseConfirm()
    if confirmOverlay_ then
        confirmOverlay_:SetVisible(false)
    end
end

-- ============================================================================
-- 执行收获
-- ============================================================================
local function DoHarvest()
    CloseConfirm()
    CloseTooltip()
    if onHarvestClick_ then
        onHarvestClick_()
    end
end

-- ============================================================================
-- 点击收获按钮
-- ============================================================================
local function OnHarvestBtnClick()
    if not manager_ then return end
    local stage = manager_.GetStage()

    if stage == SD.STAGE_COALESCING then
        -- 接触中阶段不可收获
        return
    end

    if stage == SD.STAGE_RIPE then
        -- 深交阶段直接收获
        DoHarvest()
    else
        -- 熟识阶段弹确认
        if confirmOverlay_ then
            confirmOverlay_:SetVisible(true)
        end
    end
end

-- ============================================================================
-- 创建确认弹窗（全屏遮罩 + 居中对话框）
-- ============================================================================
local function CreateConfirmOverlay()
    confirmOverlay_ = UI.Panel {
        id = "sugarConfirmOverlay",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        zIndex = 1000,
        visible = false,
        -- 点击遮罩关闭
        onTap = function()
            CloseConfirm()
        end,
        children = {
            UI.Panel {
                width = 260,
                backgroundColor = { 35, 30, 50, 250 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 255, 180, 60, 180 },
                padding = 16,
                flexDirection = "column",
                alignItems = "center",
                gap = 10,
                -- 阻止事件冒泡到遮罩
                onTap = function() end,
                children = {
                    UI.Label {
                        text = "⚠️ 提前收获提示",
                        fontSize = 14,
                        fontWeight = "bold",
                        fontColor = { 255, 200, 80, 255 },
                    },
                    UI.Label {
                        text = "当前处于「已熟识」阶段\n收获有 50% 概率少得 1 个人脉\n\n等到「深交」阶段收获\n有 50% 概率多得 1 个人脉",
                        fontSize = 11,
                        fontColor = { 220, 200, 240, 220 },
                        textAlign = "center",
                        lineHeight = 1.5,
                    },
                    -- 按钮行
                    UI.Panel {
                        flexDirection = "row",
                        gap = 12,
                        marginTop = 4,
                        children = {
                            UI.Button {
                                text = "取消",
                                width = 90,
                                height = 32,
                                fontSize = 12,
                                variant = "ghost",
                                fontColor = { 180, 180, 200, 255 },
                                onClick = function()
                                    CloseConfirm()
                                end,
                            },
                            UI.Button {
                                text = "仍然收获",
                                width = 100,
                                height = 32,
                                fontSize = 12,
                                variant = "primary",
                                onClick = function()
                                    DoHarvest()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
    return confirmOverlay_
end

-- ============================================================================
-- 创建 UI
-- ============================================================================

function SLD.CreateWidget()
    -- 浮窗
    tooltip_ = UI.Panel {
        id = "sugarTooltip",
        position = "absolute",
        top = 52,
        left = 0,
        width = 220,
        backgroundColor = { 20, 18, 30, 245 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { 100, 80, 140, 200 },
        padding = 12,
        flexDirection = "column",
        gap = 5,
        visible = false,
        zIndex = 100,
        pointerEvents = "auto",
        -- 阻止点击冒泡到 widget_ 导致关闭
        onTap = function() end,
        children = {
            -- 关闭按钮（右上角）
            UI.Panel {
                position = "absolute",
                top = 4, right = 6,
                pointerEvents = "auto",
                children = {
                    UI.Button {
                        text = "✕",
                        width = 24, height = 24,
                        fontSize = 12,
                        variant = "ghost",
                        fontColor = { 180, 160, 200, 200 },
                        onClick = function()
                            CloseTooltip()
                        end,
                    },
                },
            },
            UI.Label {
                id = "ttType",
                text = "",
                fontSize = 13,
                fontColor = { 255, 215, 0, 255 },
                fontWeight = "bold",
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
            -- 分隔线
            UI.Panel {
                width = "100%", height = 1,
                backgroundColor = { 100, 80, 140, 80 },
                marginTop = 2, marginBottom = 2,
            },
            UI.Label {
                id = "ttDesc",
                text = "人脉每22小时积累一轮\n成熟后点击收获按钮收获\n可用于产业升级(+1%CPS/级)\n持有人脉也有加成(+1%/条)",
                fontSize = 9,
                fontColor = { 140, 140, 160, 160 },
                lineHeight = 1.4,
            },
            -- 收获按钮
            UI.Panel {
                width = "100%",
                marginTop = 4,
                alignItems = "center",
                children = {
                    UI.Button {
                        id = "ttHarvestBtn",
                        text = "收获人脉",
                        width = "100%",
                        height = 34,
                        fontSize = 12,
                        fontWeight = "bold",
                        variant = "primary",
                        onClick = function()
                            OnHarvestBtnClick()
                        end,
                    },
                },
            },
        },
    }

    -- 顶部小图标
    local dpr = graphics:GetDPR()
    local logW = graphics:GetWidth() / dpr
    local logH = graphics:GetHeight() / dpr
    local shortSide = math.min(logW, logH)
    local sidebarW = math.floor(math.max(48, math.min(80, shortSide * 0.14)))

    widget_ = UI.Panel {
        id = "sugarLumpWidget",
        position = "absolute",
        top = 8,
        left = sidebarW + 8,
        flexDirection = "column",
        alignItems = "center",
        pointerEvents = "auto",
        zIndex = 10,
        -- 点击图标 → toggle 浮窗
        onTap = function()
            if tooltipOpen_ then
                CloseTooltip()
            else
                OpenTooltip()
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
            -- 浮窗挂在这里
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
    harvestBtn_ = root:FindById("ttHarvestBtn")

    -- 创建点击外部关闭的透明遮罩
    backdropOverlay_ = UI.Panel {
        id = "sugarBackdrop",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 1 },  -- 几乎全透明，仅捕获点击
        zIndex = 9,  -- 在 widget_(zIndex=10) 之下，覆盖其他 UI
        visible = false,
        pointerEvents = "auto",
        onTap = function()
            CloseTooltip()
        end,
    }
    root:AddChild(backdropOverlay_)

    -- 创建确认弹窗并挂到 uiRoot
    CreateConfirmOverlay()
    if confirmOverlay_ then
        root:AddChild(confirmOverlay_)
    end
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
        harvestBtn_ = uiRoot_:FindById("ttHarvestBtn")
    end
end

function SLD.Hide()
    if not visible_ or not widget_ or not parentNode_ then return end
    CloseTooltip()
    CloseConfirm()
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

    -- 浮窗打开时刷新收获按钮状态和内容
    if tooltipOpen_ then
        SLD.RefreshTooltip()
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
            tooltipHint_:SetText("可以收获，但深交后收益更高")
        elseif stage == SD.STAGE_RIPE then
            tooltipHint_:SetText("✨ 最佳收获时机！")
        end
    end

    -- 收获按钮状态
    if harvestBtn_ then
        if stage == SD.STAGE_COALESCING then
            harvestBtn_:SetText("积累中…")
            harvestBtn_:SetStyle({
                opacity = 0.4,
            })
        elseif stage == SD.STAGE_MATURE then
            harvestBtn_:SetText("提前收获")
            harvestBtn_:SetStyle({
                opacity = 1.0,
            })
        else
            harvestBtn_:SetText("✨ 收获人脉")
            harvestBtn_:SetStyle({
                opacity = 1.0,
            })
        end
    end
end

return SLD
