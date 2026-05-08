-- ============================================================================
-- ui/AdPanel.lua
-- 广告福利面板 —— 里程碑奖励 + 免广卡 + 连续天数
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local AdManager = require("core.AdManager")
local AdConfig  = require("config.AdConfig")
local AudioManager = require("core.AudioManager")
local SlotSaveSystem = require("core.SlotSaveSystem")

local AP = {}

-- ============================================================================
-- 内部状态
-- ============================================================================
local uiRoot_     = nil
local panel_      = nil
local visible_    = false
local contentBox_ = nil
local ctx_        = nil  -- { floatingText }

-- 颜色常量
local C_BG       = { 30, 30, 42, 245 }
local C_CARD     = { 40, 40, 55, 255 }
local C_ACCENT   = { 255, 180, 50, 255 }
local C_DIM      = { 140, 140, 160, 255 }
local C_GREEN    = { 80, 220, 120, 255 }
local C_GOLD     = { 255, 200, 60, 255 }
local C_CLAIMED  = { 80, 80, 100, 255 }
local C_LOCKED   = { 60, 60, 80, 255 }
local C_BTN_AD   = { 60, 140, 255, 255 }
local C_WHITE    = { 240, 240, 255, 255 }

-- 前向声明
local BuildPanel

-- ============================================================================
-- 初始化
-- ============================================================================

function AP.Init(root, context)
    uiRoot_ = root
    ctx_ = context or {}
    BuildPanel()

    -- 注册状态变更回调
    AdManager.SetOnStateChanged(function()
        if visible_ then AP.Refresh() end
    end)
end

-- ============================================================================
-- 显示 / 隐藏
-- ============================================================================

function AP.Show()
    if not panel_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    uiRoot_:AddChild(panel_)
    AP.Refresh()
end

function AP.Hide()
    if not panel_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(panel_)
end

function AP.Toggle()
    if visible_ then AP.Hide() else AP.Show() end
end

function AP.IsVisible()
    return visible_
end

-- ============================================================================
-- 刷新
-- ============================================================================

function AP.Refresh()
    if not visible_ or not contentBox_ then return end

    contentBox_:RemoveAllChildren()

    local todayCount = AdManager.GetTodayCount()
    local threshold  = AdManager.GetAdFreeThreshold()
    local isAdFree   = AdManager.IsAdFreeToday()
    local streak, bonusHours = AdManager.GetStreak()
    local milestones = AdManager.GetMilestones()

    -- ===== 顶部状态区 =====
    local statusChildren = {}

    -- 今日观看
    statusChildren[#statusChildren + 1] = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6,
        children = {
            UI.Label { text = "今日观看", fontSize = 12, fontColor = C_DIM },
            UI.Label {
                text = todayCount .. " / " .. threshold,
                fontSize = 14, fontColor = isAdFree and C_GREEN or C_ACCENT,
                fontWeight = "bold",
            },
        },
    }

    -- 免广卡状态
    if isAdFree then
        statusChildren[#statusChildren + 1] = UI.Panel {
            backgroundColor = { 40, 100, 60, 255 },
            borderRadius = 6,
            paddingLeft = 10, paddingRight = 10,
            paddingTop = 4, paddingBottom = 4,
            marginTop = 4,
            children = {
                UI.Label {
                    text = "免广卡已激活 - 今日广告自动跳过",
                    fontSize = 12, fontColor = C_GREEN, fontWeight = "bold",
                },
            },
        }
    else
        local remaining = threshold - todayCount
        statusChildren[#statusChildren + 1] = UI.Label {
            text = "再看 " .. remaining .. " 次激活免广卡",
            fontSize = 11, fontColor = C_DIM, marginTop = 2,
        }
    end

    -- 连续天数
    if streak > 0 then
        statusChildren[#statusChildren + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6, marginTop = 4,
            children = {
                UI.Label { text = "连续", fontSize = 11, fontColor = C_DIM },
                UI.Label {
                    text = streak .. " 天",
                    fontSize = 13, fontColor = C_GOLD, fontWeight = "bold",
                },
                UI.Label {
                    text = "离线加速 " .. bonusHours .. " 小时",
                    fontSize = 11, fontColor = C_DIM,
                },
            },
        }
    end

    contentBox_:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = C_CARD,
        borderRadius = 8,
        padding = 10,
        flexDirection = "column", gap = 2,
        children = statusChildren,
    })

    -- ===== 进度条 =====
    local progressPct = math.min(100, math.floor(todayCount / threshold * 100))
    contentBox_:AddChild(UI.Panel {
        width = "100%", height = 6, marginTop = 8, marginBottom = 4,
        backgroundColor = { 50, 50, 65, 255 }, borderRadius = 3,
        children = {
            UI.Panel {
                width = progressPct .. "%", height = "100%",
                backgroundColor = isAdFree and C_GREEN or C_ACCENT,
                borderRadius = 3,
            },
        },
    })

    -- ===== 里程碑列表 =====
    contentBox_:AddChild(UI.Label {
        text = "里程碑奖励",
        fontSize = 13, fontColor = C_WHITE, fontWeight = "bold",
        marginTop = 6, marginBottom = 4,
    })

    for _, ms in ipairs(milestones) do
        local rowColor = C_CARD
        local countColor = C_DIM
        local labelColor = C_DIM
        local btnChild = nil

        if ms.status == "claimed" then
            rowColor = C_CLAIMED
            countColor = { 100, 100, 120, 255 }
            labelColor = { 100, 100, 120, 255 }
            btnChild = UI.Label {
                text = "已领",
                fontSize = 11, fontColor = { 80, 80, 100, 255 },
            }
        elseif ms.status == "claimable" then
            rowColor = { 50, 60, 45, 255 }
            countColor = C_GREEN
            labelColor = C_WHITE
            local msIndex = ms.index
            btnChild = UI.Button {
                text = "领取",
                fontSize = 11,
                variant = "primary",
                width = 52, height = 26,
                onClick = function()
                    local ok, desc = AdManager.ClaimMilestone(msIndex)
                    if ok then
                        AudioManager.PlayBtnClick()
                        SlotSaveSystem.MarkDirty()
                        AP.Refresh()
                        -- 浮字显示奖励
                        if ctx_.floatingText and desc then
                            local dpr = graphics:GetDPR()
                            local cx = graphics:GetWidth() / dpr * 0.5
                            local cy = graphics:GetHeight() / dpr * 0.15
                            ctx_.floatingText.Show(desc, cx, cy, { 255, 220, 100, 255 })
                        end
                    end
                end,
            }
        else
            -- locked
            countColor = C_DIM
            labelColor = { 90, 90, 110, 255 }
            btnChild = UI.Label {
                text = "未达",
                fontSize = 11, fontColor = { 70, 70, 90, 255 },
            }
        end

        contentBox_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            backgroundColor = rowColor,
            borderRadius = 6,
            paddingLeft = 10, paddingRight = 10,
            paddingTop = 6, paddingBottom = 6,
            marginBottom = 3,
            children = {
                -- 次数标签
                UI.Label {
                    text = ms.count .. " 次",
                    fontSize = 12, fontColor = countColor, fontWeight = "bold",
                    width = 40,
                },
                -- 奖励描述
                UI.Label {
                    text = ms.label,
                    fontSize = 12, fontColor = labelColor,
                    flex = 1, flexShrink = 1,
                },
                -- 按钮区
                btnChild,
            },
        })
    end

    -- ===== 看广告按钮 =====
    local btnText = isAdFree and "免广告领取" or "看广告领奖励"
    local btnColor = isAdFree and C_GREEN or C_BTN_AD

    contentBox_:AddChild(UI.Button {
        text = btnText,
        fontSize = 15,
        fontWeight = "bold",
        width = "100%",
        height = 44,
        marginTop = 10,
        backgroundColor = btnColor,
        borderRadius = 8,
        variant = "primary",
        onClick = function()
            AdManager.ShowRewardAd(function()
                -- 广告成功回调：刷新面板
                AudioManager.PlayBtnClick()
                AP.Refresh()
                -- 浮字
                if ctx_.floatingText then
                    local dpr = graphics:GetDPR()
                    local cx = graphics:GetWidth() / dpr * 0.5
                    local cy = graphics:GetHeight() / dpr * 0.15
                    ctx_.floatingText.Show("观看成功 +1", cx, cy, { 100, 255, 200, 255 })
                end
            end, { floatingText = ctx_.floatingText })
        end,
    })

    -- ===== 底部累计信息 =====
    contentBox_:AddChild(UI.Label {
        text = "累计观看: " .. AdManager.GetTotalCount() .. " 次",
        fontSize = 10, fontColor = { 80, 80, 100, 255 },
        marginTop = 8, alignSelf = "center",
    })
end

-- ============================================================================
-- 构建面板骨架
-- ============================================================================

---@diagnostic disable-next-line: redefined-local
BuildPanel = function()
    local dpr = graphics:GetDPR()
    local logicalW = graphics:GetWidth() / dpr
    local drawerW = math.floor(logicalW * 0.3)

    contentBox_ = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 2,
    }

    panel_ = UI.Panel {
        position = "absolute",
        right = 0, top = 0,
        width = drawerW,
        height = "100%",
        backgroundColor = C_BG,
        flexDirection = "column",
        zIndex = 800,
        children = {
            -- 标题栏
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 8, paddingBottom = 6,
                backgroundColor = { 35, 35, 48, 255 },
                children = {
                    UI.Label {
                        text = "每日福利",
                        fontSize = 15, fontColor = C_ACCENT, fontWeight = "bold",
                    },
                    UI.Button {
                        text = "X",
                        fontSize = 13,
                        width = 28, height = 28,
                        backgroundColor = { 80, 40, 40, 200 },
                        borderRadius = 14,
                        onClick = function() AP.Hide() end,
                    },
                },
            },
            -- 可滚动内容区
            UI.ScrollView {
                flex = 1,
                width = "100%",
                padding = 10,
                children = { contentBox_ },
            },
        },
    }
end

return AP
