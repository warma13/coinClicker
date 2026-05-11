-- ============================================================================
-- ui/AdPanel.lua
-- 广告福利面板 —— 里程碑奖励 + 特权卡
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local AdManager = require("core.AdManager")
local AdConfig  = require("config.AdConfig")
local OnlineRewardManager = require("core.OnlineRewardManager")
local OnlineRewardConfig  = require("config.OnlineRewardConfig")
local AudioManager = require("core.AudioManager")
local SlotSaveSystem = require("core.SlotSaveSystem")
local ItemDefs = require("config.ItemDefs")
local Tooltip  = require("ui.Tooltip")

local AP = {}

-- ============================================================================
-- 内部状态
-- ============================================================================
local uiRoot_     = nil
local panel_      = nil
local visible_    = false
local contentBox_ = nil
local ctx_        = nil  -- { floatingText }
local tooltipItemId_ = nil  -- 当前浮窗显示的道具 ID

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

--- 内部 toast 工具
local function Toast(text, color)
    if not ctx_ or not ctx_.floatingText then return end
    local dpr = graphics:GetDPR()
    local cx = graphics:GetWidth() / dpr * 0.5
    local cy = graphics:GetHeight() / dpr * 0.15
    ctx_.floatingText.Show(text, cx, cy, color or { 255, 255, 255, 255 })
end

-- ============================================================================
-- 初始化
-- ============================================================================

function AP.Init(root, context)
    uiRoot_ = root
    ctx_ = context or {}
    BuildPanel()

    -- 注册状态变更回调（仅特权卡等级变化时重算产量）
    local GameManager = require("core.GameManager")
    local lastCardIdx_ = select(2, AdManager.GetCardLevel())
    local _, _, _, lastActivated_ = AdManager.GetCardLevel()
    AdManager.SetOnStateChanged(function()
        local _, idx, _, act = AdManager.GetCardLevel()
        if idx ~= lastCardIdx_ or act ~= lastActivated_ then
            lastCardIdx_ = idx
            lastActivated_ = act
            GameManager.RecalcProduction()
        end
        if visible_ then AP.Refresh() end
    end)

    -- 在线奖励：领取后重算产量
    OnlineRewardManager.SetOnStateChanged(function()
        GameManager.RecalcProduction()
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
    Tooltip.Hide()
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
    local milestones = AdManager.GetMilestones()

    -- ===== 顶部状态区 =====
    local statusChildren = {}

    -- 今日观看
    statusChildren[#statusChildren + 1] = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6,
        children = {
            UI.Label { text = "今日观看", fontSize = 12, fontColor = C_DIM },
            UI.Label {
                text = todayCount .. " / " .. AdConfig.DAILY_LIMIT,
                fontSize = 14, fontColor = C_ACCENT,
                fontWeight = "bold",
            },
        },
    }

    contentBox_:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = C_CARD,
        borderRadius = 8,
        padding = 10,
        flexDirection = "column", gap = 2,
        children = statusChildren,
    })

    -- ===== 进度条 =====
    local progressPct = math.min(100, math.floor(todayCount / AdConfig.DAILY_LIMIT * 100))
    contentBox_:AddChild(UI.Panel {
        width = "100%", height = 6, marginTop = 8, marginBottom = 4,
        backgroundColor = { 50, 50, 65, 255 }, borderRadius = 3,
        children = {
            UI.Panel {
                width = progressPct .. "%", height = "100%",
                backgroundColor = C_ACCENT,
                borderRadius = 3,
            },
        },
    })

    -- ===== 在线时长奖励 =====
    do
        local onlineSec = OnlineRewardManager.GetOnlineSeconds()
        local olMilestones = OnlineRewardManager.GetMilestones()

        -- 格式化在线时间
        local function FmtTime(sec)
            local s = math.floor(sec)
            if s < 60 then return s .. "秒" end
            if s < 3600 then return math.floor(s / 60) .. "分" .. (s % 60 > 0 and s % 60 .. "秒" or "") end
            local h = math.floor(s / 3600)
            local m = math.floor((s % 3600) / 60)
            return h .. "时" .. (m > 0 and m .. "分" or "")
        end

        -- 当前加成汇总
        local cpsBon = OnlineRewardManager.GetCpsBonusPct()
        local cpcBon = OnlineRewardManager.GetCpcBonusPct()
        local bonusParts = {}
        if cpsBon > 0 then bonusParts[#bonusParts + 1] = "CPS +" .. math.floor(cpsBon * 100) .. "%" end
        if cpcBon > 0 then bonusParts[#bonusParts + 1] = "点击 +" .. math.floor(cpcBon * 100) .. "%" end
        local bonusLine = #bonusParts > 0 and table.concat(bonusParts, "  ") or nil

        -- 标题行
        local headerChildren = {
            UI.Label {
                text = "在线奖励",
                fontSize = 13, fontColor = C_WHITE, fontWeight = "bold",
            },
            UI.Label {
                text = FmtTime(onlineSec),
                fontSize = 12, fontColor = C_ACCENT, fontWeight = "bold",
            },
        }

        contentBox_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            marginTop = 8, marginBottom = 2,
            children = headerChildren,
        })

        -- 当日加成提示
        if bonusLine then
            contentBox_:AddChild(UI.Label {
                text = "当日加成: " .. bonusLine,
                fontSize = 10, fontColor = C_GREEN, marginBottom = 4,
            })
        end

        -- 构建单个里程碑卡片
        local function BuildMilestoneCard(ms)
            local cardBg = C_CARD
            local labelColor = C_DIM
            local statusChild = nil

            local pct = math.min(100, math.floor(onlineSec / ms.seconds * 100))

            if ms.status == "claimed" then
                cardBg = C_CLAIMED
                labelColor = { 100, 100, 120, 255 }
                statusChild = UI.Label {
                    text = "✓ 已领",
                    fontSize = 10, fontColor = { 80, 180, 100, 255 }, fontWeight = "bold",
                }
            elseif ms.status == "claimable" then
                cardBg = { 50, 60, 45, 255 }
                labelColor = C_WHITE
                local msIndex = ms.index
                statusChild = UI.Button {
                    text = "领取",
                    fontSize = 10,
                    variant = "primary",
                    width = "100%", height = 22,
                    onClick = function()
                        local ok, desc = OnlineRewardManager.ClaimMilestone(msIndex)
                        if ok then
                            AudioManager.PlayBtnClick()
                            SlotSaveSystem.MarkDirty()
                            AP.Refresh()
                            if ctx_.floatingText and desc then
                                local dpr = graphics:GetDPR()
                                local cx = graphics:GetWidth() / dpr * 0.5
                                local cy = graphics:GetHeight() / dpr * 0.15
                                ctx_.floatingText.Show(desc, cx, cy, { 255, 220, 100, 255 })
                            end
                            if ms.bonus then
                                local parts = {}
                                if ms.bonus.cpsPct and ms.bonus.cpsPct > 0 then
                                    parts[#parts + 1] = "CPS +" .. math.floor(ms.bonus.cpsPct * 100) .. "%"
                                end
                                if ms.bonus.cpcPct and ms.bonus.cpcPct > 0 then
                                    parts[#parts + 1] = "点击 +" .. math.floor(ms.bonus.cpcPct * 100) .. "%"
                                end
                                if #parts > 0 then
                                    Toast("当日加成: " .. table.concat(parts, " "), { 80, 220, 120, 255 })
                                end
                            end
                        end
                    end,
                }
            else
                labelColor = { 90, 90, 110, 255 }
                statusChild = UI.Label {
                    text = pct .. "%",
                    fontSize = 10, fontColor = { 70, 70, 90, 255 },
                }
            end

            -- 奖励图标行
            local rewardIcons = {}
            local dimmed = ms.status == "claimed"
            for _, reward in ipairs(ms.rewards) do
                if reward.type == "item" then
                    local def = ItemDefs.ITEM_MAP[reward.id]
                    local iconPath = def and def.icon or nil
                    if iconPath then
                        local itemDef = def
                        local rarityInfo = ItemDefs.RARITY[itemDef.rarity]
                        rewardIcons[#rewardIcons + 1] = UI.Panel {
                            pointerEvents = "auto",
                            onPointerDown = function(event)
                                if Tooltip.IsVisible() and tooltipItemId_ == itemDef.id then
                                    Tooltip.Hide()
                                    tooltipItemId_ = nil
                                else
                                    local stars = rarityInfo and string.rep("★", rarityInfo.stars) or ""
                                    local rarityName = rarityInfo and rarityInfo.name or ""
                                    Tooltip.Show({
                                        iconImage = iconPath,
                                        title = itemDef.name,
                                        subtitle = stars .. " " .. rarityName,
                                        desc = itemDef.desc or "",
                                        extra = itemDef.passive and itemDef.passive.desc or nil,
                                    }, event.y, event.x)
                                    tooltipItemId_ = itemDef.id
                                end
                            end,
                            children = {
                                UI.Panel {
                                    width = 18, height = 18,
                                    backgroundImage = iconPath,
                                    borderRadius = 3,
                                    opacity = dimmed and 0.4 or 1.0,
                                },
                            },
                        }
                    end
                end
            end

            -- 加成标签列表
            local bonusLabels = {}
            local bonusColor = ms.status == "claimed" and { 60, 140, 80, 255 } or { 80, 80, 100, 255 }
            if ms.bonus then
                if ms.bonus.cpsPct and ms.bonus.cpsPct > 0 then
                    bonusLabels[#bonusLabels + 1] = UI.Label {
                        text = "CPS +" .. math.floor(ms.bonus.cpsPct * 100) .. "%",
                        fontSize = 8, fontColor = bonusColor,
                    }
                end
                if ms.bonus.cpcPct and ms.bonus.cpcPct > 0 then
                    bonusLabels[#bonusLabels + 1] = UI.Label {
                        text = "点击 +" .. math.floor(ms.bonus.cpcPct * 100) .. "%",
                        fontSize = 8, fontColor = bonusColor,
                    }
                end
            end

            return UI.Panel {
                flex = 1,
                flexDirection = "column",
                alignItems = "center",
                backgroundColor = cardBg,
                borderRadius = 6,
                paddingTop = 4, paddingBottom = 4,
                paddingLeft = 2, paddingRight = 2,
                gap = 2,
                children = {
                    -- 时间标签
                    UI.Label {
                        text = ms.label,
                        fontSize = 11, fontColor = labelColor, fontWeight = "bold",
                    },
                    -- 奖励图标
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "center",
                        alignItems = "center",
                        gap = 2,
                        children = rewardIcons,
                    },
                    -- 加成标签
                    UI.Panel {
                        alignItems = "center",
                        children = bonusLabels,
                    },
                    -- 领取按钮 / 状态
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        children = { statusChild },
                    },
                },
            }
        end

        -- 第一行 4 列，第二行 3 列
        local row1Children = {}
        local row2Children = {}
        for i, ms in ipairs(olMilestones) do
            local card = BuildMilestoneCard(ms)
            if i <= 4 then
                row1Children[#row1Children + 1] = card
            else
                row2Children[#row2Children + 1] = card
            end
        end

        contentBox_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 4,
            marginBottom = 4,
            children = row1Children,
        })
        contentBox_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 4,
            marginBottom = 2,
            children = row2Children,
        })

        -- 分隔线
        contentBox_:AddChild(UI.Panel {
            width = "100%", height = 1,
            backgroundColor = { 60, 60, 80, 255 },
            marginTop = 6, marginBottom = 2,
        })
    end

    -- ===== 广告里程碑列表 =====
    contentBox_:AddChild(UI.Label {
        text = "广告里程碑 (" .. todayCount .. "/" .. AdConfig.DAILY_LIMIT .. ")",
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

        -- 构建奖励图标区
        local rewardIcons = {}
        local dimmed = ms.status == "claimed"
        for _, reward in ipairs(ms.rewards) do
            if reward.type == "item" then
                local def = ItemDefs.ITEM_MAP[reward.id]
                local iconPath = def and def.icon or nil
                if iconPath then
                    local itemDef = def  -- 闭包引用
                    local rarityInfo = ItemDefs.RARITY[itemDef.rarity]
                    rewardIcons[#rewardIcons + 1] = UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 2,
                        pointerEvents = "auto",
                        onPointerDown = function(event)
                            -- 同一道具：关闭；不同道具：切换
                            if Tooltip.IsVisible() and tooltipItemId_ == itemDef.id then
                                Tooltip.Hide()
                                tooltipItemId_ = nil
                            else
                                local stars = rarityInfo and string.rep("★", rarityInfo.stars) or ""
                                local rarityName = rarityInfo and rarityInfo.name or ""
                                Tooltip.Show({
                                    iconImage = iconPath,
                                    title = itemDef.name,
                                    subtitle = stars .. " " .. rarityName,
                                    desc = itemDef.desc or "",
                                    extra = itemDef.passive and itemDef.passive.desc or nil,
                                }, event.y, event.x)
                                tooltipItemId_ = itemDef.id
                            end
                        end,
                        children = {
                            UI.Panel {
                                width = 22, height = 22,
                                backgroundImage = iconPath,
                                borderRadius = 4,
                                opacity = dimmed and 0.4 or 1.0,
                            },
                            UI.Label {
                                text = "x" .. (reward.n or 1),
                                fontSize = 10,
                                fontColor = dimmed and { 100, 100, 120, 255 } or C_WHITE,
                                fontWeight = "bold",
                            },
                        },
                    }
                end
            end
        end

        contentBox_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            backgroundColor = rowColor,
            borderRadius = 6,
            paddingLeft = 10, paddingRight = 10,
            paddingTop = 5, paddingBottom = 5,
            marginBottom = 3,
            children = {
                -- 次数标签
                UI.Label {
                    text = ms.count .. "次",
                    fontSize = 12, fontColor = countColor, fontWeight = "bold",
                    width = 32,
                },
                -- 奖励图标区
                UI.Panel {
                    flex = 1,
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 6,
                    children = rewardIcons,
                },
                -- 按钮区
                btnChild,
            },
        })
    end

    -- ===== 特权卡 =====
    local cardDef, cardIdx, nextDef, cardActivated = AdManager.GetCardLevel()
    local cardPts = AdManager.GetCardPoints()
    local cc = cardDef.color
    local gc = cardDef.glow
    local earnedToday = AdManager.IsCardPointEarnedToday()

    -- 卡面背景渐变色（未激活时变暗）
    local cardAlpha = cardActivated and 30 or 15
    local borderAlpha = cardActivated and 180 or 80
    local glowAlpha = cardActivated and 100 or 50
    local cardBgColor  = { cc[1], cc[2], cc[3], cardAlpha }
    local cardBorder   = { cc[1], cc[2], cc[3], borderAlpha }
    local glowBorder   = { gc[1], gc[2], gc[3], glowAlpha }
    local nameColor    = cardActivated and { cc[1], cc[2], cc[3], 255 } or { cc[1], cc[2], cc[3], 160 }

    -- 进度信息
    local cardProgressText, cardProgressPct
    if not cardActivated then
        -- 未激活：显示距铜卡的进度
        cardProgressText = cardPts .. " / " .. cardDef.points .. " 点"
        cardProgressPct = cardDef.points > 0 and math.floor(cardPts / cardDef.points * 100) or 0
    elseif nextDef then
        cardProgressText = cardPts .. " / " .. nextDef.points .. " 点"
        cardProgressPct = math.floor(cardPts / nextDef.points * 100)
    else
        cardProgressText = cardPts .. " 点 (已满级)"
        cardProgressPct = 100
    end

    -- 加成文字
    local bonusParts = {}
    if cardActivated and cardDef.cpsMul > 0 then
        bonusParts[#bonusParts + 1] = "CPS +" .. math.floor(cardDef.cpsMul * 100) .. "%"
    end
    if cardActivated and cardDef.cpcMul and cardDef.cpcMul > 0 then
        bonusParts[#bonusParts + 1] = "点击 +" .. math.floor(cardDef.cpcMul * 100) .. "%"
    end
    local bonusText = table.concat(bonusParts, "  ")

    -- 每日道具福利列表（只有激活后才显示已领取状态）
    local dailyItems = cardDef.dailyItems
    local dailyGiven = AdManager.IsCardDailyGiven()

    -- 下一级预览
    local nextBonusText = ""
    if not cardActivated then
        -- 未激活：预览铜卡激活后的加成
        local parts = {}
        if cardDef.cpsMul > 0 then
            parts[#parts + 1] = "CPS +" .. math.floor(cardDef.cpsMul * 100) .. "%"
        end
        if cardDef.cpcMul and cardDef.cpcMul > 0 then
            parts[#parts + 1] = "点击 +" .. math.floor(cardDef.cpcMul * 100) .. "%"
        end
        if cardDef.dailyItems and #cardDef.dailyItems > 0 then
            local names = {}
            for _, di in ipairs(cardDef.dailyItems) do
                local def = ItemDefs.ITEM_MAP[di.id]
                names[#names + 1] = (def and def.name or di.id) .. "x" .. di.n
            end
            parts[#parts + 1] = "每日" .. table.concat(names, "+")
        end
        if #parts > 0 then
            nextBonusText = "激活可获: " .. table.concat(parts, ", ")
        end
    elseif nextDef then
        local parts = {}
        if nextDef.cpsMul > 0 then
            parts[#parts + 1] = "CPS +" .. math.floor(nextDef.cpsMul * 100) .. "%"
        end
        if nextDef.cpcMul and nextDef.cpcMul > 0 then
            parts[#parts + 1] = "点击 +" .. math.floor(nextDef.cpcMul * 100) .. "%"
        end
        if nextDef.dailyItems and #nextDef.dailyItems > 0 then
            local names = {}
            for _, di in ipairs(nextDef.dailyItems) do
                local def = ItemDefs.ITEM_MAP[di.id]
                names[#names + 1] = (def and def.name or di.id) .. "x" .. di.n
            end
            parts[#parts + 1] = "每日" .. table.concat(names, "+")
        end
        nextBonusText = "下一级: " .. nextDef.name .. " (" .. table.concat(parts, ", ") .. ")"
    end

    -- 今日获取提示
    local dailyHint
    if earnedToday then
        dailyHint = UI.Label {
            text = "今日已获得 +1 特权点",
            fontSize = 10, fontColor = C_GREEN, marginTop = 2,
        }
    else
        local remaining = AdConfig.DAILY_LIMIT - todayCount
        if remaining > 0 then
            dailyHint = UI.Label {
                text = "再看 " .. remaining .. " 次获得 +1 特权点",
                fontSize = 10, fontColor = C_DIM, marginTop = 2,
            }
        else
            dailyHint = UI.Label {
                text = "今日已达上限，明日可继续",
                fontSize = 10, fontColor = C_DIM, marginTop = 2,
            }
        end
    end

    -- 卡面等级图标
    local levelBadge = UI.Panel {
        width = 32, height = 32,
        borderRadius = 16,
        backgroundColor = { cc[1], cc[2], cc[3], cardActivated and 60 or 25 },
        borderWidth = 2, borderColor = cardBorder,
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Label {
                text = cardActivated and ("Lv" .. cardIdx) or "?",
                fontSize = 11, fontColor = nameColor, fontWeight = "bold",
            },
        },
    }

    -- 构建每日道具福利展示
    local dailyRewardSection = nil
    if dailyItems and #dailyItems > 0 then
        local rewardChildren = {}
        -- 标题行（未激活时显示"激活后每日可领"）
        local statusLabel
        if not cardActivated then
            statusLabel = UI.Label {
                text = "激活后每日可领",
                fontSize = 9, fontColor = C_DIM,
            }
        elseif dailyGiven then
            statusLabel = UI.Label {
                text = "✓ 已领取",
                fontSize = 9, fontColor = C_GREEN,
            }
        else
            statusLabel = UI.Label {
                text = "登录自动发放",
                fontSize = 9, fontColor = C_DIM,
            }
        end
        rewardChildren[#rewardChildren + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            children = {
                UI.Label {
                    text = "每日福利",
                    fontSize = 10, fontColor = { cc[1], cc[2], cc[3], 180 }, fontWeight = "bold",
                },
                statusLabel,
            },
        }
        -- 道具图标行（未激活时半透明预览）
        local dimmed = (not cardActivated) or dailyGiven
        local iconRow = {}
        for _, di in ipairs(dailyItems) do
            local def = ItemDefs.ITEM_MAP[di.id]
            if def then
                iconRow[#iconRow + 1] = UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 2,
                    children = {
                        def.icon and UI.Panel {
                            width = 20, height = 20,
                            backgroundImage = def.icon,
                            borderRadius = 3,
                            opacity = dimmed and 0.5 or 1.0,
                        } or nil,
                        UI.Label {
                            text = def.name .. "x" .. di.n,
                            fontSize = 9,
                            fontColor = dimmed and C_DIM or C_WHITE,
                        },
                    },
                }
            end
        end
        rewardChildren[#rewardChildren + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6,
            flexWrap = "wrap",
            children = iconRow,
        }
        dailyRewardSection = UI.Panel {
            width = "100%",
            backgroundColor = { cc[1], cc[2], cc[3], 15 },
            borderRadius = 6,
            padding = 6,
            marginTop = 6,
            flexDirection = "column", gap = 3,
            children = rewardChildren,
        }
    end

    -- 卡片内容
    local cardChildren = {
        -- 顶部：等级徽章 + 卡名
        UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 8,
            children = {
                levelBadge,
                UI.Panel {
                    flexDirection = "column", flex = 1,
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 6,
                            children = {
                                UI.Label {
                                    text = cardDef.name,
                                    fontSize = 14, fontColor = nameColor, fontWeight = "bold",
                                },
                                not cardActivated and UI.Panel {
                                    backgroundColor = { 80, 80, 100, 200 },
                                    borderRadius = 6,
                                    paddingLeft = 5, paddingRight = 5,
                                    paddingTop = 1, paddingBottom = 1,
                                    children = {
                                        UI.Label {
                                            text = "未激活",
                                            fontSize = 9, fontColor = { 180, 180, 200, 255 },
                                        },
                                    },
                                } or nil,
                            },
                        },
                        bonusText ~= "" and UI.Label {
                            text = bonusText,
                            fontSize = 11, fontColor = { cc[1], cc[2], cc[3], 200 },
                        } or UI.Label {
                            text = not cardActivated and "累积特权点激活" or "暂无加成",
                            fontSize = 11, fontColor = C_DIM,
                        },
                    },
                },
                -- 点数显示
                UI.Panel {
                    backgroundColor = { cc[1], cc[2], cc[3], 40 },
                    borderRadius = 10,
                    paddingLeft = 8, paddingRight = 8,
                    paddingTop = 3, paddingBottom = 3,
                    children = {
                        UI.Label {
                            text = cardPts .. " pt",
                            fontSize = 11, fontColor = nameColor, fontWeight = "bold",
                        },
                    },
                },
            },
        },
        -- 每日道具福利
        dailyRewardSection,
        -- 进度条
        UI.Panel {
            width = "100%", height = 4, marginTop = 8,
            backgroundColor = { 50, 50, 65, 255 }, borderRadius = 2,
            children = {
                UI.Panel {
                    width = math.min(100, cardProgressPct) .. "%", height = "100%",
                    backgroundColor = { cc[1], cc[2], cc[3], 200 },
                    borderRadius = 2,
                },
            },
        },
        -- 进度文字
        UI.Label {
            text = cardProgressText,
            fontSize = 10, fontColor = C_DIM, marginTop = 2, alignSelf = "flex-end",
        },
    }

    -- 下一级信息
    if nextBonusText ~= "" then
        cardChildren[#cardChildren + 1] = UI.Label {
            text = nextBonusText,
            fontSize = 10, fontColor = { gc[1], gc[2], gc[3], 180 }, marginTop = 2,
        }
    end

    -- 每日提示
    cardChildren[#cardChildren + 1] = dailyHint

    contentBox_:AddChild(UI.Panel {
        width = "100%",
        marginTop = 10,
        backgroundColor = cardBgColor,
        borderRadius = 10,
        borderWidth = 1.5,
        borderColor = glowBorder,
        padding = 10,
        flexDirection = "column",
        children = cardChildren,
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
