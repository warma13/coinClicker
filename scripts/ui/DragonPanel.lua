-- ============================================================================
-- ui/DragonPanel.lua
-- AI合伙人面板（全屏覆盖式弹窗）
-- AI等级 + XP进度条 + 天赋树 + 策略模块 + AI洞察
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local DD = require("config.DragonDefs")

local DP = {}

-- ======== 引用 ========
local uiRoot_ = nil
local panel_ = nil
local visible_ = false
local contentContainer_ = nil
local dragonInfoLabel_ = nil

-- 外部注入
local dragonManager_ = nil
local onUpgrade_ = nil
local onEquipAura_ = nil
local onPetDragon_ = nil

-- ======== 增量刷新缓存 ========
local lastSnapshot_ = ""
local lastInfoText_ = ""
local upgradeBtnCache_ = nil
local eggBtnCache_ = nil
local auraRowCache_ = {}
local dropRowCache_ = {}
local slot1Label_ = nil
local slot2Label_ = nil
local initialized_ = false

-- XP 进度条缓存
local xpBarFill_ = nil
local xpBarLabel_ = nil
local xpRateLabel_ = nil
local lastXPFP_ = ""

-- 天赋缓存
local talentPointsLabel_ = nil
local talentTierCache_ = {}     -- { [talentId] = { row, statusLabel, lastFP } }
local selectedBranch_ = 1       -- 当前选中的天赋分支索引 (1-4)
local talentTabCache_ = {}      -- { [branchIdx] = { tab, progressLabel } }
local talentContentBox_ = nil   -- 天赋内容容器

-- 派遣任务缓存
local missionProgressBar_ = nil
local missionTimeLabel_ = nil
local missionSection_ = nil
local lastMissionFP_ = ""

-- ======== 颜色常量 ========
local C_GOLD   = { 240, 200, 100, 255 }
local C_GOLD_D = { 200, 170, 60, 200 }
local C_TEXT   = { 200, 180, 140, 220 }
local C_DIM    = { 140, 130, 100, 160 }
local C_DIM2   = { 100, 95, 80, 140 }
local C_GREEN  = { 100, 200, 100, 200 }
local C_BG     = { 30, 28, 22, 255 }
local C_BG_L   = { 40, 35, 22, 255 }
local C_BORDER = { 60, 55, 40, 100 }

-- ============================================================================
-- 快照生成
-- ============================================================================

local function MakeSnapshot()
    local parts = {}
    local level = dragonManager_.GetLevel()
    parts[#parts + 1] = "L:" .. level

    if level < 0 then
        local eggDef = DD.GetLevel(0)
        parts[#parts + 1] = "CB:" .. ((eggDef and GameState.coins >= eggDef.cost) and "Y" or "N")
    else
        local isMaxLevel = dragonManager_.IsMaxLevel()
        parts[#parts + 1] = "MX:" .. (isMaxLevel and "Y" or "N")

        -- CU/XP 不放快照，升级按钮由 IncrementalUpdate 就地更新

        parts[#parts + 1] = "A1:" .. (dragonManager_.GetEquippedAuraId(1) or "nil")
        parts[#parts + 1] = "A2:" .. (dragonManager_.GetEquippedAuraId(2) or "nil")
        parts[#parts + 1] = "S2:" .. (dragonManager_.IsSecondSlotUnlocked() and "Y" or "N")

        local unlockedAuras = dragonManager_.GetUnlockedAuras()
        parts[#parts + 1] = "UA:" .. #unlockedAuras

        -- 天赋点（XP 由 IncrementalUpdate 内部跟踪，不放快照，避免频繁 diff）
        parts[#parts + 1] = "TP:" .. dragonManager_.GetTalentPoints()

        -- 天赋学习状态
        local tCount = 0
        for _ in pairs(dragonManager_.GetLearnedTalents()) do tCount = tCount + 1 end
        parts[#parts + 1] = "TL:" .. tCount

        if dragonManager_.IsDropsUnlocked() and level >= 23 then
            for _, drop in ipairs(DD.drops) do
                if dragonManager_.HasDrop(drop.id) then
                    parts[#parts + 1] = "D:" .. drop.id
                end
            end
        end

        -- 派遣任务结构变化（开始/完成/无）
        local am = dragonManager_.GetActiveMission()
        if am then
            parts[#parts + 1] = "MS:" .. am.missionId
            parts[#parts + 1] = "MD:" .. (dragonManager_.IsMissionDone() and "Y" or "N")
        else
            parts[#parts + 1] = "MS:nil"
        end
    end

    return table.concat(parts, "|")
end

-- ============================================================================
-- 构建 XP 进度条
-- ============================================================================

local function BuildXPBar()
    local level = dragonManager_.GetLevel()
    if level < DD.TALENT_UNLOCK_LEVEL or dragonManager_.IsMaxLevel() then
        return nil
    end

    local xpCur = dragonManager_.GetLevelXP()
    local xpMax = dragonManager_.GetNextLevelXP()
    local pct = xpMax > 0 and math.min(xpCur / xpMax, 1.0) or 1.0
    local xpRate = dragonManager_.GetXPPerSecond()

    xpBarFill_ = UI.Panel {
        width = tostring(math.floor(pct * 100)) .. "%",
        height = "100%",
        backgroundColor = { 80, 180, 120, 220 },
        borderRadius = 3,
    }

    xpBarLabel_ = UI.Label {
        text = math.floor(xpCur) .. " / " .. xpMax,
        fontSize = 9, fontColor = { 220, 220, 200, 255 },
        position = "absolute", top = 1, left = 0, right = 0,
        textAlign = "center",
    }

    xpRateLabel_ = UI.Label {
        text = string.format("%.1f XP/s", xpRate),
        fontSize = 9, fontColor = C_DIM,
    }

    lastXPFP_ = math.floor(xpCur) .. "/" .. xpMax

    return UI.Panel {
        width = "100%", gap = 2, marginTop = 4, marginBottom = 2,
        children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Label { text = "经验值", fontSize = 10, fontColor = C_TEXT },
                        },
                    },
                    xpRateLabel_,
                },
            },
            UI.Panel {
                width = "100%", height = 14, backgroundColor = { 25, 25, 20, 200 },
                borderRadius = 4, borderWidth = 1, borderColor = C_BORDER,
                overflow = "hidden",
                children = { xpBarFill_, xpBarLabel_ },
            },
        },
    }
end

-- ============================================================================
-- 构建天赋树区域
-- ============================================================================

--- 局部重建当前选中分支的天赋行
local function RebuildTalentContent()
    if not talentContentBox_ then return end
    talentContentBox_:RemoveAllChildren()
    talentTierCache_ = {}

    local branch = DD.TALENT_BRANCHES[selectedBranch_]
    if not branch then return end

    -- 分支描述
    talentContentBox_:AddChild(UI.Label {
        text = branch.desc, fontSize = 9, fontColor = C_DIM, marginBottom = 4,
    })

    for i, tier in ipairs(branch.tiers) do
        local isLearned = dragonManager_.IsTalentLearned(tier.id)
        local canLearn = dragonManager_.CanLearnTalent(tier.id)

        -- 右侧操作按钮
        local actionBtn
        if isLearned then
            actionBtn = UI.Panel {
                paddingLeft = 6, paddingRight = 6, paddingTop = 3, paddingBottom = 3,
                borderRadius = 4, backgroundColor = { 40, 60, 35, 255 },
                children = {
                    UI.Label { text = "已学习", fontSize = 9, fontColor = C_GREEN },
                },
            }
        elseif canLearn then
            actionBtn = UI.Panel {
                paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
                borderRadius = 5, borderWidth = 1,
                backgroundColor = { 70, 55, 15, 255 },
                borderColor = { 240, 200, 60, 220 },
                pointerEvents = "auto",
                onPointerDown = function()
                    dragonManager_.LearnTalent(tier.id)
                    initialized_ = false
                    DP.Refresh()
                end,
                children = {
                    UI.Label { text = "学习 " .. tier.cost .. "pt", fontSize = 10,
                        fontColor = { 255, 225, 80, 255 } },
                },
            }
        else
            actionBtn = UI.Panel {
                paddingLeft = 6, paddingRight = 6, paddingTop = 3, paddingBottom = 3,
                borderRadius = 4, backgroundColor = { 25, 22, 18, 180 },
                children = {
                    UI.Label { text = tier.cost .. "pt", fontSize = 9, fontColor = C_DIM2 },
                },
            }
        end

        local row = UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            padding = 6, gap = 6, borderRadius = 4, borderWidth = 1,
            backgroundColor = isLearned and { 30, 40, 28, 255 }
                or (canLearn and { 35, 30, 20, 255 } or { 25, 22, 20, 180 }),
            borderColor = isLearned and { 80, 160, 60, 120 }
                or (canLearn and { 100, 85, 40, 100 } or { 40, 35, 30, 60 }),
            opacity = (isLearned or canLearn) and 1.0 or 0.4,
            children = {
                UI.Label { text = "T" .. i, fontSize = 9, fontColor = C_DIM, width = 16 },
                UI.Panel { flex = 1, flexShrink = 1, gap = 1, children = {
                    UI.Label { text = tier.name, fontSize = 11,
                        fontColor = isLearned and { 150, 220, 120, 255 }
                            or (canLearn and C_GOLD or C_DIM2) },
                    UI.Label { text = tier.desc, fontSize = 9, fontColor = C_DIM },
                }},
                actionBtn,
            },
        }

        talentTierCache_[tier.id] = { row = row, actionBtn = actionBtn,
            lastFP = (isLearned and "Y" or "N") .. (canLearn and "Y" or "N") }

        talentContentBox_:AddChild(row)
    end
end

--- 更新标签的选中态样式
local function UpdateTalentTabs()
    for idx, cache in pairs(talentTabCache_) do
        local isSelected = (idx == selectedBranch_)
        cache.tab:SetStyle({
            backgroundColor = isSelected and { 50, 42, 20, 255 } or { 28, 25, 20, 200 },
            borderColor = isSelected and { 220, 180, 60, 200 } or { 50, 45, 35, 100 },
            borderWidth = isSelected and 1 or 1,
        })
        -- 更新进度
        local branch = DD.TALENT_BRANCHES[idx]
        if branch and cache.progressLabel then
            local progress = dragonManager_.GetBranchProgress(branch.id)
            cache.progressLabel:SetText(progress .. "/5")
            cache.progressLabel:SetFontColor(isSelected and C_GOLD or C_DIM)
        end
    end
end

local function BuildTalentSection()
    local level = dragonManager_.GetLevel()
    if level < DD.TALENT_UNLOCK_LEVEL then return nil end

    talentTierCache_ = {}
    talentTabCache_ = {}

    local tp = dragonManager_.GetTalentPoints()
    local totalUsed = dragonManager_.GetUsedTalentPoints()

    talentPointsLabel_ = UI.Label {
        text = "可用: " .. tp .. "  已用: " .. totalUsed,
        fontSize = 10, fontColor = C_TEXT,
    }

    -- 构建标签行
    local tabs = {}
    for idx, branch in ipairs(DD.TALENT_BRANCHES) do
        local isSelected = (idx == selectedBranch_)
        local progress = dragonManager_.GetBranchProgress(branch.id)

        local progressLabel = UI.Label {
            text = progress .. "/5", fontSize = 8,
            fontColor = isSelected and C_GOLD or C_DIM,
        }

        local tab = UI.Panel {
            flex = 1, alignItems = "center", justifyContent = "center",
            padding = 5, gap = 2, borderRadius = 5, borderWidth = 1,
            backgroundColor = isSelected and { 50, 42, 20, 255 } or { 28, 25, 20, 200 },
            borderColor = isSelected and { 220, 180, 60, 200 } or { 50, 45, 35, 100 },
            pointerEvents = "auto",
            onPointerDown = (function(bIdx)
                return function()
                    if selectedBranch_ ~= bIdx then
                        selectedBranch_ = bIdx
                        UpdateTalentTabs()
                        RebuildTalentContent()
                    end
                end
            end)(idx),
            children = {
                UI.Panel { width = 14, height = 14,
                    backgroundImage = branch.iconImage, backgroundFit = "contain" },
                UI.Label { text = branch.name, fontSize = 9,
                    fontColor = isSelected and C_GOLD or C_DIM, textAlign = "center" },
                progressLabel,
            },
        }

        talentTabCache_[idx] = { tab = tab, progressLabel = progressLabel }
        tabs[#tabs + 1] = tab
    end

    local tabRow = UI.Panel {
        width = "100%", flexDirection = "row", gap = 4,
        children = tabs,
    }

    -- 内容容器
    talentContentBox_ = UI.Panel {
        width = "100%", gap = 3, marginTop = 4,
    }

    -- 填充当前分支
    RebuildTalentContent()

    return UI.Panel {
        width = "100%", gap = 4,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                marginBottom = 2,
                children = {
                    UI.Panel { width = 14, height = 14,
                        backgroundImage = "image/icon_ai_brain.png", backgroundFit = "contain" },
                    UI.Label { text = "天赋树", fontSize = 12, fontColor = C_TEXT },
                    UI.Panel { flex = 1 },
                    talentPointsLabel_,
                },
            },
            tabRow,
            talentContentBox_,
        },
    }
end

-- ============================================================================
-- 时间格式化辅助
-- ============================================================================

local function FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 3600 then
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        return h .. "h" .. (m > 0 and string.format("%02dm", m) or "")
    elseif seconds >= 60 then
        local m = math.floor(seconds / 60)
        local s = seconds % 60
        return m .. "m" .. (s > 0 and string.format("%02ds", s) or "")
    else
        return seconds .. "s"
    end
end

-- ============================================================================
-- 构建派遣任务区域
-- ============================================================================

local function BuildMissionSection()
    local level = dragonManager_.GetLevel()
    if level < DD.MISSION_UNLOCK_LEVEL then return nil end

    missionProgressBar_ = nil
    missionTimeLabel_ = nil
    lastMissionFP_ = ""

    local F = GameState.FormatNumber
    local children = {}

    -- 标题行
    children[#children + 1] = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 4, marginBottom = 4,
        children = {
            UI.Panel { width = 14, height = 14,
                backgroundImage = "image/icon_market_research.png", backgroundFit = "contain" },
            UI.Label { text = "派遣任务", fontSize = 12, fontColor = C_TEXT },
            UI.Panel { flex = 1 },
            UI.Label { text = "已完成: " .. dragonManager_.GetCompletedMissionCount(),
                fontSize = 9, fontColor = C_DIM },
        },
    }

    local activeMission = dragonManager_.GetActiveMission()

    if activeMission then
        -- ===== 有进行中的任务 =====
        local def = DD.FindMission(activeMission.missionId)
        local isDone = dragonManager_.IsMissionDone()
        local progress = dragonManager_.GetMissionProgress()
        local elapsed = dragonManager_.GetMissionElapsed()
        local duration = dragonManager_.GetMissionDuration()
        local remaining = math.max(0, duration - elapsed)

        -- 任务信息卡
        local taskIcon = (def and def.iconImage) or "image/icon_market_research.png"

        -- 进度条填充
        missionProgressBar_ = UI.Panel {
            width = tostring(math.floor(progress * 100)) .. "%",
            height = "100%",
            backgroundColor = isDone and { 100, 200, 100, 220 } or { 80, 150, 200, 220 },
            borderRadius = 3,
        }

        -- 时间标签
        missionTimeLabel_ = UI.Label {
            text = isDone and "已完成!" or (FormatDuration(remaining) .. " 剩余"),
            fontSize = 9, fontColor = { 220, 220, 200, 255 },
            position = "absolute", top = 1, left = 0, right = 0,
            textAlign = "center",
        }

        lastMissionFP_ = (isDone and "done" or math.floor(remaining))

        -- 操作按钮
        local actionBtns = {}
        if isDone then
            actionBtns[#actionBtns + 1] = UI.Panel {
                flex = 1, alignItems = "center", justifyContent = "center",
                paddingTop = 8, paddingBottom = 8, borderRadius = 6, borderWidth = 1,
                backgroundColor = { 40, 60, 20, 255 },
                borderColor = { 120, 200, 60, 220 },
                pointerEvents = "auto",
                onPointerDown = function()
                    local rewards = dragonManager_.ClaimMission()
                    if rewards then
                        print("[UI] 任务奖励: XP+" .. rewards.xp .. " 金币+" .. F(rewards.coins))
                    end
                    initialized_ = false
                    DP.Refresh()
                end,
                children = {
                    UI.Label { text = "领取奖励", fontSize = 13,
                        fontColor = { 150, 230, 80, 255 } },
                    UI.Label { text = "XP+" .. (def and def.rewards.xp or 0),
                        fontSize = 9, fontColor = C_DIM },
                },
            }
        else
            actionBtns[#actionBtns + 1] = UI.Panel {
                alignItems = "center", justifyContent = "center",
                paddingLeft = 10, paddingRight = 10, paddingTop = 6, paddingBottom = 6,
                borderRadius = 5, borderWidth = 1,
                backgroundColor = { 50, 30, 25, 255 },
                borderColor = { 160, 80, 60, 180 },
                pointerEvents = "auto",
                onPointerDown = function()
                    dragonManager_.AbandonMission()
                    initialized_ = false
                    DP.Refresh()
                end,
                children = {
                    UI.Label { text = "放弃", fontSize = 10, fontColor = { 200, 100, 80, 220 } },
                },
            }
        end

        children[#children + 1] = UI.Panel {
            width = "100%", padding = 8, gap = 6, borderRadius = 6, borderWidth = 1,
            backgroundColor = isDone and { 30, 40, 25, 255 } or { 28, 32, 38, 255 },
            borderColor = isDone and { 100, 180, 60, 180 } or { 60, 100, 140, 150 },
            children = {
                -- 任务名和图标
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        UI.Panel { width = 24, height = 24,
                            backgroundImage = taskIcon, backgroundFit = "contain" },
                        UI.Panel { flex = 1, flexShrink = 1, gap = 1, children = {
                            UI.Label { text = def and def.name or "???",
                                fontSize = 12, fontColor = isDone and C_GREEN or C_GOLD },
                            UI.Label { text = def and def.desc or "",
                                fontSize = 9, fontColor = C_DIM },
                        }},
                    },
                },
                -- 进度条
                UI.Panel {
                    width = "100%", height = 14, backgroundColor = { 25, 25, 20, 200 },
                    borderRadius = 4, borderWidth = 1, borderColor = C_BORDER,
                    overflow = "hidden",
                    children = { missionProgressBar_, missionTimeLabel_ },
                },
                -- 总时长提示
                UI.Label {
                    text = "总时长: " .. FormatDuration(duration),
                    fontSize = 9, fontColor = C_DIM2,
                },
                -- 操作按钮行
                UI.Panel {
                    width = "100%", flexDirection = "row", gap = 6, marginTop = 2,
                    children = actionBtns,
                },
            },
        }

    elseif dragonManager_.IsMissionOnCooldown() then
        -- ===== 冷却中 =====
        local cd = dragonManager_.GetMissionCooldown()
        missionTimeLabel_ = UI.Label {
            text = "新任务将在 " .. FormatDuration(cd) .. " 后刷新",
            fontSize = 11, fontColor = C_DIM, textAlign = "center",
        }
        lastMissionFP_ = "cd:" .. math.floor(cd)

        children[#children + 1] = UI.Panel {
            width = "100%", padding = 12, borderRadius = 6, borderWidth = 1,
            backgroundColor = { 28, 26, 22, 200 },
            borderColor = C_BORDER,
            alignItems = "center", justifyContent = "center", gap = 4,
            children = {
                UI.Label { text = "任务冷却中", fontSize = 12, fontColor = C_DIM2 },
                missionTimeLabel_,
            },
        }

    else
        -- ===== 可选任务列表 =====
        local missions = dragonManager_.GetAvailableMissions()
        if #missions == 0 then
            children[#children + 1] = UI.Label {
                text = "暂无可用任务", fontSize = 11, fontColor = C_DIM,
                textAlign = "center",
            }
        else
            for _, m in ipairs(missions) do
                local missionId = m.id
                children[#children + 1] = UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center",
                    padding = 6, gap = 6, borderRadius = 5, borderWidth = 1,
                    backgroundColor = { 30, 28, 24, 255 },
                    borderColor = { 70, 60, 40, 120 },
                    children = {
                        UI.Panel { width = 22, height = 22,
                            backgroundImage = m.iconImage or "image/icon_market_research.png",
                            backgroundFit = "contain" },
                        UI.Panel { flex = 1, flexShrink = 1, gap = 1, children = {
                            UI.Label { text = m.name, fontSize = 11, fontColor = C_GOLD },
                            UI.Label { text = m.desc, fontSize = 9, fontColor = C_DIM },
                            UI.Panel {
                                flexDirection = "row", gap = 6, marginTop = 1,
                                children = {
                                    UI.Label { text = FormatDuration(m.duration),
                                        fontSize = 9, fontColor = { 100, 160, 200, 200 } },
                                    UI.Label { text = "XP+" .. m.rewards.xp,
                                        fontSize = 9, fontColor = { 120, 200, 120, 200 } },
                                },
                            },
                        }},
                        UI.Panel {
                            paddingLeft = 8, paddingRight = 8, paddingTop = 5, paddingBottom = 5,
                            borderRadius = 5, borderWidth = 1,
                            backgroundColor = { 50, 40, 15, 255 },
                            borderColor = { 200, 170, 60, 200 },
                            pointerEvents = "auto",
                            onPointerDown = (function(mid)
                                return function()
                                    dragonManager_.StartMission(mid)
                                    initialized_ = false
                                    DP.Refresh()
                                end
                            end)(missionId),
                            children = {
                                UI.Label { text = "派遣", fontSize = 11,
                                    fontColor = { 255, 220, 80, 255 } },
                            },
                        },
                    },
                }
            end
        end
    end

    missionSection_ = UI.Panel {
        width = "100%", gap = 4,
        children = children,
    }

    return missionSection_
end

-- ============================================================================
-- 构建策略模块行
-- ============================================================================

local function BuildAuraRow(aura, isUnlocked, equippedSlot)
    local auraId = aura.id

    -- 右侧操作按钮
    local actionBtn
    if equippedSlot then
        -- 已装备 → 显示槽位标识 + 卸下按钮
        local slotName = equippedSlot == 1 and "主策略" or "副策略"
        local slotColor = equippedSlot == 1 and { 255, 200, 80, 255 } or { 180, 150, 255, 255 }
        local slotBg = equippedSlot == 1 and { 80, 60, 15, 255 } or { 40, 30, 70, 255 }
        local slotBorder = equippedSlot == 1 and { 240, 200, 60, 220 } or { 160, 140, 220, 220 }
        actionBtn = UI.Panel {
            alignItems = "center", gap = 3,
            children = {
                UI.Label { text = slotName, fontSize = 9, fontColor = slotColor },
                UI.Panel {
                    paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
                    borderRadius = 4, borderWidth = 1,
                    backgroundColor = slotBg, borderColor = slotBorder,
                    pointerEvents = "auto",
                    onPointerDown = function()
                        if onEquipAura_ then onEquipAura_(equippedSlot, nil) end
                        initialized_ = false
                        DP.Refresh()
                    end,
                    children = {
                        UI.Label { text = "卸下", fontSize = 10, fontColor = slotColor },
                    },
                },
            },
        }
    elseif isUnlocked then
        -- 已解锁未装备 → 装备按钮
        actionBtn = UI.Panel {
            paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
            borderRadius = 5, borderWidth = 1,
            backgroundColor = { 25, 45, 30, 255 },
            borderColor = { 100, 180, 100, 200 },
            pointerEvents = "auto",
            onPointerDown = function()
                if onEquipAura_ then onEquipAura_(1, auraId) end
                initialized_ = false
                DP.Refresh()
            end,
            children = {
                UI.Label { text = "装备", fontSize = 10, fontColor = { 120, 200, 120, 255 } },
            },
        }
    else
        -- 未解锁 → 锁定标签
        actionBtn = UI.Panel {
            paddingLeft = 6, paddingRight = 6, paddingTop = 3, paddingBottom = 3,
            borderRadius = 4, backgroundColor = { 25, 22, 18, 180 },
            children = {
                UI.Label { text = "锁定", fontSize = 9, fontColor = C_DIM2 },
            },
        }
    end

    local row = UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        padding = 8, gap = 6, borderRadius = 6, borderWidth = 1,
        backgroundColor = equippedSlot
            and (equippedSlot == 1 and { 45, 40, 20, 255 } or { 30, 25, 45, 255 })
            or (isUnlocked and { 30, 35, 28, 255 } or { 25, 22, 20, 180 }),
        borderColor = equippedSlot
            and (equippedSlot == 1 and { 200, 170, 60, 180 } or { 140, 120, 200, 180 })
            or (isUnlocked and { 80, 120, 80, 100 } or { 40, 35, 30, 60 }),
        opacity = isUnlocked and 1.0 or 0.35,
        children = {
            UI.Panel { width = 28, height = 28,
                backgroundImage = aura.iconImage or "image/icon_chart.png",
                backgroundFit = "contain" },
            UI.Panel { flex = 1, flexShrink = 1, gap = 1, children = {
                UI.Label { text = aura.name, fontSize = 12,
                    fontColor = isUnlocked and { 200, 190, 140, 255 } or C_DIM2 },
                UI.Label { text = aura.desc, fontSize = 9, fontColor = C_DIM },
            }},
            actionBtn,
        },
    }

    local fp = (equippedSlot or 0) .. ":" .. (isUnlocked and "Y" or "N")
    auraRowCache_[aura.id] = { row = row, actionBtn = actionBtn, lastFP = fp }
    return row
end

-- ============================================================================
-- 构建洞察行
-- ============================================================================

local function BuildDropRow(drop, isCollected)
    local statusLabel = UI.Label { text = isCollected and "✓" or "?", fontSize = 12,
        fontColor = isCollected and C_GREEN or { 80, 75, 65, 150 },
        width = 20, textAlign = "center" }

    local row = UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        padding = 6, gap = 6, borderRadius = 4, borderWidth = 1,
        backgroundColor = isCollected and { 35, 45, 30, 255 } or { 25, 22, 20, 180 },
        borderColor = isCollected and { 100, 180, 80, 120 } or { 40, 35, 30, 60 },
        opacity = isCollected and 1.0 or 0.4,
        children = {
            UI.Panel { width = 24, height = 24,
                backgroundImage = drop.iconImage or "image/icon_market_report.png",
                backgroundFit = "contain" },
            UI.Panel { flex = 1, flexShrink = 1, gap = 1, children = {
                UI.Label { text = drop.name, fontSize = 11,
                    fontColor = isCollected and { 150, 220, 120, 255 } or C_DIM2 },
                UI.Label { text = drop.desc, fontSize = 9, fontColor = C_DIM },
            }},
            statusLabel,
        },
    }

    dropRowCache_[drop.id] = { row = row, statusLabel = statusLabel, lastCollected = isCollected }
    return row
end

-- ============================================================================
-- 分隔线
-- ============================================================================

local function Divider()
    return UI.Panel { width = "100%", height = 1, backgroundColor = C_BORDER, marginTop = 6, marginBottom = 6 }
end

-- ============================================================================
-- 全量构建内容
-- ============================================================================

local function RebuildContent()
    if not contentContainer_ then return end
    contentContainer_:RemoveAllChildren()
    upgradeBtnCache_ = nil
    eggBtnCache_ = nil
    auraRowCache_ = {}
    dropRowCache_ = {}
    slot1Label_ = nil
    slot2Label_ = nil
    xpBarFill_ = nil
    xpBarLabel_ = nil
    xpRateLabel_ = nil
    talentPointsLabel_ = nil
    talentTierCache_ = {}
    talentTabCache_ = {}
    talentContentBox_ = nil
    missionProgressBar_ = nil
    missionTimeLabel_ = nil
    missionSection_ = nil
    lastMissionFP_ = ""

    local F = GameState.FormatNumber
    local level = dragonManager_.GetLevel()
    local levelDef = dragonManager_.GetCurrentLevelDef()
    local isMaxLevel = dragonManager_.IsMaxLevel()

    -- ===== 未购买 =====
    if level < 0 then
        local eggDef = DD.GetLevel(0)
        local canBuy = eggDef and GameState.coins >= eggDef.cost

        local costLabel = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            children = {
                UI.Label { text = "费用:", fontSize = 12, fontColor = C_DIM },
                UI.Panel { width = 14, height = 14,
                    backgroundImage = "image/金币.png", backgroundFit = "contain" },
                UI.Label { text = eggDef and F(eggDef.cost) or "?", fontSize = 12, fontColor = C_DIM },
            },
        }

        local eggBtn = UI.Panel {
            width = "100%", padding = 16, borderRadius = 8, borderWidth = 1,
            justifyContent = "center", alignItems = "center", gap = 8,
            backgroundColor = canBuy and { 60, 45, 20, 255 } or { 35, 28, 20, 220 },
            borderColor = canBuy and { 220, 180, 60, 200 } or C_BORDER,
            pointerEvents = canBuy and "auto" or "none",
            onPointerDown = canBuy and function()
                if onUpgrade_ then
                    onUpgrade_()
                    initialized_ = false
                    DP.Refresh()
                end
            end or nil,
            children = {
                UI.Panel { width = 44, height = 44,
                    backgroundImage = "image/icon_ai_prototype.png", backgroundFit = "contain" },
                UI.Label { text = "购买AI原型机", fontSize = 16,
                    fontColor = canBuy and C_GOLD or C_DIM },
                costLabel,
            },
        }
        contentContainer_:AddChild(eggBtn)
        eggBtnCache_ = { panel = eggBtn, costLabel = costLabel, lastFP = canBuy and "Y" or "N" }
        initialized_ = true
        return
    end

    -- ===== 等级状态卡 =====
    contentContainer_:AddChild(UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 4, marginBottom = 4,
        children = {
            UI.Panel { width = 14, height = 14,
                backgroundImage = "image/icon_chart.png", backgroundFit = "contain" },
            UI.Label { text = "AI等级与升级", fontSize = 12, fontColor = C_TEXT },
        },
    })

    local phaseImg = (levelDef and levelDef.iconImage) or "image/icon_ai_robot.png"

    contentContainer_:AddChild(UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        padding = 10, gap = 10, borderRadius = 8, borderWidth = 1,
        backgroundColor = C_BG_L, borderColor = { 160, 140, 80, 150 },
        children = {
            UI.Panel { width = 40, height = 40,
                backgroundImage = phaseImg, backgroundFit = "contain" },
            UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                UI.Label { text = (levelDef and levelDef.name or "???"),
                    fontSize = 15, fontColor = C_GOLD },
                UI.Label { text = "Lv." .. level .. " / " .. DD.MAX_LEVEL,
                    fontSize = 11, fontColor = C_DIM },
            }},
        },
    })

    -- ===== XP 进度条 =====
    local xpBar = BuildXPBar()
    if xpBar then contentContainer_:AddChild(xpBar) end

    -- ===== 升级按钮（居中按钮样式） =====
    if not isMaxLevel then
        local nextDef = dragonManager_.GetNextLevelDef()
        local canUpgrade = dragonManager_.CanUpgrade()
        local costText = dragonManager_.GetUpgradeCostText()

        local nameLabel = UI.Label { text = "升级 → " .. (nextDef and nextDef.name or ""),
            fontSize = 14,
            fontColor = canUpgrade and { 255, 225, 100, 255 } or { 140, 125, 90, 160 },
            textAlign = "center" }

        local costIcon = dragonManager_.GetUpgradeCostIcon()
        local costChildren = {}
        if costIcon then
            costChildren[#costChildren + 1] = UI.Panel { width = 13, height = 13,
                backgroundImage = costIcon, backgroundFit = "contain" }
        end
        costChildren[#costChildren + 1] = UI.Label { text = costText, fontSize = 11, fontColor = C_DIM }
        local costLabel = UI.Panel { flexDirection = "row", alignItems = "center",
            justifyContent = "center", gap = 3, children = costChildren }

        local upgradeBtn = UI.Panel {
            width = "100%", alignItems = "center", justifyContent = "center",
            padding = 10, gap = 4, borderRadius = 8, borderWidth = 1,
            backgroundColor = canUpgrade and { 55, 40, 15, 255 } or { 35, 28, 20, 200 },
            borderColor = canUpgrade and { 255, 180, 60, 200 } or { 70, 55, 40, 100 },
            pointerEvents = canUpgrade and "auto" or "none",
            onPointerDown = function()
                if dragonManager_.CanUpgrade() and onUpgrade_ then
                    onUpgrade_()
                    initialized_ = false
                    DP.Refresh()
                end
            end,
            children = {
                nameLabel,
                costLabel,
            },
        }
        contentContainer_:AddChild(upgradeBtn)
        upgradeBtnCache_ = { panel = upgradeBtn, nameLabel = nameLabel,
            costLabel = costLabel, lastFP = (canUpgrade and "Y" or "N") }
    end

    -- ===== 天赋树 =====
    local talentSection = BuildTalentSection()
    if talentSection then
        contentContainer_:AddChild(Divider())
        contentContainer_:AddChild(talentSection)
    end

    -- ===== 派遣任务 =====
    local missionSec = BuildMissionSection()
    if missionSec then
        contentContainer_:AddChild(Divider())
        contentContainer_:AddChild(missionSec)
    end

    -- ===== 启发灵感 =====
    if dragonManager_.IsDropsUnlocked() and level >= 23 then
        contentContainer_:AddChild(Divider())
        contentContainer_:AddChild(UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4, marginBottom = 4,
            children = {
                UI.Panel { width = 14, height = 14,
                    backgroundImage = "image/icon_inspiration.png", backgroundFit = "contain" },
                UI.Label { text = "启发灵感", fontSize = 12, fontColor = C_TEXT },
            },
        })

        contentContainer_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            padding = 10, gap = 8, borderRadius = 6, borderWidth = 1,
            backgroundColor = { 45, 35, 25, 255 },
            borderColor = { 180, 140, 80, 150 },
            pointerEvents = "auto",
            onPointerDown = function()
                if onPetDragon_ then
                    onPetDragon_()
                    DP.Refresh()
                end
            end,
            children = {
                UI.Panel { width = 32, height = 32,
                    backgroundImage = "image/icon_ai_robot.png", backgroundFit = "contain" },
                UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                    UI.Label { text = "启发 K1 灵感", fontSize = 13, fontColor = C_GOLD },
                    UI.Label { text = "5% 概率获得AI洞察", fontSize = 10, fontColor = C_DIM },
                }},
            },
        })

        for _, drop in ipairs(DD.drops) do
            local isCollected = dragonManager_.HasDrop(drop.id)
            contentContainer_:AddChild(BuildDropRow(drop, isCollected))
        end
    end

    -- ===== 策略模块 =====
    local unlockedAuras = dragonManager_.GetUnlockedAuras()
    if #unlockedAuras > 0 then
        contentContainer_:AddChild(Divider())
        contentContainer_:AddChild(UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4, marginBottom = 4,
            children = {
                UI.Panel { width = 14, height = 14,
                    backgroundImage = "image/icon_market_predict.png", backgroundFit = "contain" },
                UI.Label { text = "AI策略模块", fontSize = 12, fontColor = C_TEXT },
            },
        })

        local slot1Aura = dragonManager_.GetEquippedAura(1)
        local slot2Aura = dragonManager_.GetEquippedAura(2)

        slot1Label_ = UI.Label { text = slot1Aura and slot1Aura.name or "— 空 —",
            fontSize = 12, textAlign = "center",
            fontColor = slot1Aura and { 255, 220, 100, 255 } or { 100, 90, 70, 150 } }

        slot2Label_ = UI.Label {
            text = dragonManager_.IsSecondSlotUnlocked()
                and (slot2Aura and slot2Aura.name or "— 空 —") or "未解锁",
            fontSize = 12, textAlign = "center",
            fontColor = (slot2Aura and { 180, 160, 255, 255 }) or { 100, 90, 110, 150 },
        }

        contentContainer_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row", gap = 8, marginBottom = 6,
            children = {
                UI.Panel {
                    flex = 1, padding = 8, borderRadius = 6, borderWidth = 1,
                    backgroundColor = C_BG_L,
                    borderColor = { 200, 170, 60, 150 },
                    alignItems = "center", gap = 2,
                    children = {
                        UI.Label { text = "主策略", fontSize = 10, fontColor = C_GOLD_D },
                        slot1Label_,
                    },
                },
                UI.Panel {
                    flex = 1, padding = 8, borderRadius = 6, borderWidth = 1,
                    backgroundColor = dragonManager_.IsSecondSlotUnlocked()
                        and { 28, 25, 40, 255 } or { 20, 18, 22, 180 },
                    borderColor = dragonManager_.IsSecondSlotUnlocked()
                        and { 140, 120, 200, 150 } or { 40, 35, 45, 80 },
                    alignItems = "center", gap = 2,
                    opacity = dragonManager_.IsSecondSlotUnlocked() and 1.0 or 0.4,
                    children = {
                        UI.Label { text = "副策略", fontSize = 10,
                            fontColor = dragonManager_.IsSecondSlotUnlocked()
                                and { 140, 120, 200, 200 } or { 80, 70, 90, 120 } },
                        slot2Label_,
                    },
                },
            },
        })

        contentContainer_:AddChild(UI.Label {
            text = "点击策略装备到主槽位" ..
                (dragonManager_.IsSecondSlotUnlocked() and "；长按装备到副槽位" or ""),
            fontSize = 9, fontColor = { 130, 120, 100, 150 },
            textAlign = "center", marginBottom = 4,
        })

        for _, aura in ipairs(DD.auras) do
            local isUnlocked = dragonManager_.IsAuraUnlocked(aura.id)
            local equippedSlot = nil
            if dragonManager_.GetEquippedAuraId(1) == aura.id then equippedSlot = 1
            elseif dragonManager_.GetEquippedAuraId(2) == aura.id then equippedSlot = 2 end
            contentContainer_:AddChild(BuildAuraRow(aura, isUnlocked, equippedSlot))
        end
    end

    initialized_ = true
end

-- ============================================================================
-- 增量更新
-- ============================================================================

local function IncrementalUpdate()
    local level = dragonManager_.GetLevel()

    if level < 0 then
        if eggBtnCache_ then
            local eggDef = DD.GetLevel(0)
            local canBuy = eggDef and GameState.coins >= eggDef.cost
            local fp = canBuy and "Y" or "N"
            if fp ~= eggBtnCache_.lastFP then
                eggBtnCache_.lastFP = fp
                eggBtnCache_.panel:SetStyle({
                    backgroundColor = canBuy and { 60, 45, 20, 255 } or { 35, 28, 20, 220 },
                    borderColor = canBuy and { 220, 180, 60, 200 } or C_BORDER,
                    pointerEvents = canBuy and "auto" or "none",
                })
            end
        end
        return
    end

    -- XP 进度条
    if xpBarFill_ and xpBarLabel_ then
        local xpCur = dragonManager_.GetLevelXP()
        local xpMax = dragonManager_.GetNextLevelXP()
        local fp = math.floor(xpCur) .. "/" .. xpMax
        if fp ~= lastXPFP_ then
            lastXPFP_ = fp
            local pct = xpMax > 0 and math.min(xpCur / xpMax, 1.0) or 1.0
            xpBarFill_:SetStyle({ width = tostring(math.floor(pct * 100)) .. "%" })
            xpBarLabel_:SetText(math.floor(xpCur) .. " / " .. xpMax)
        end
        if xpRateLabel_ then
            local rateText = string.format("%.1f XP/s", dragonManager_.GetXPPerSecond())
            if xpRateLabel_._lastRate ~= rateText then
                xpRateLabel_._lastRate = rateText
                xpRateLabel_:SetText(rateText)
            end
        end
    end

    -- 升级按钮（就地更新样式，不做 rebuild，避免吞点击）
    if upgradeBtnCache_ and upgradeBtnCache_.panel then
        local canUpgrade = dragonManager_.CanUpgrade()
        local fp = canUpgrade and "Y" or "N"
        if fp ~= upgradeBtnCache_.lastFP then
            upgradeBtnCache_.lastFP = fp
            upgradeBtnCache_.panel:SetStyle({
                backgroundColor = canUpgrade and { 55, 40, 15, 255 } or { 35, 28, 20, 200 },
                borderColor = canUpgrade and { 255, 180, 60, 200 } or { 70, 55, 40, 100 },
                pointerEvents = canUpgrade and "auto" or "none",
            })
        end
    end

    -- 策略模块状态（按钮结构复杂，状态变化走 rebuild）
    for _, aura in ipairs(DD.auras) do
        local cache = auraRowCache_[aura.id]
        if cache then
            local isUnlocked = dragonManager_.IsAuraUnlocked(aura.id)
            local equippedSlot = nil
            if dragonManager_.GetEquippedAuraId(1) == aura.id then equippedSlot = 1
            elseif dragonManager_.GetEquippedAuraId(2) == aura.id then equippedSlot = 2 end

            local fp = (equippedSlot or 0) .. ":" .. (isUnlocked and "Y" or "N")
            if fp ~= cache.lastFP then
                -- 按钮结构变化较大，直接全量 rebuild
                RebuildContent()
                return
            end
        end
    end

    -- 策略模块槽标签
    if slot1Label_ then
        local slot1Aura = dragonManager_.GetEquippedAura(1)
        slot1Label_:SetText(slot1Aura and slot1Aura.name or "— 空 —")
        slot1Label_:SetFontColor(slot1Aura and { 255, 220, 100, 255 } or { 100, 90, 70, 150 })
    end
    if slot2Label_ then
        local slot2Aura = dragonManager_.GetEquippedAura(2)
        if dragonManager_.IsSecondSlotUnlocked() then
            slot2Label_:SetText(slot2Aura and slot2Aura.name or "— 空 —")
            slot2Label_:SetFontColor(slot2Aura and { 180, 160, 255, 255 } or { 100, 90, 110, 150 })
        end
    end

    -- 派遣任务进度条 / 冷却倒计时
    if missionProgressBar_ and missionTimeLabel_ then
        -- 有进行中的任务 → 更新进度条和时间
        local progress = dragonManager_.GetMissionProgress()
        local isDone = dragonManager_.IsMissionDone()
        local remaining = math.max(0, dragonManager_.GetMissionDuration() - dragonManager_.GetMissionElapsed())
        local fp = isDone and "done" or tostring(math.floor(remaining))
        if fp ~= lastMissionFP_ then
            lastMissionFP_ = fp
            if isDone then
                -- 任务完成 → 需要结构变化（显示领取按钮）
                RebuildContent()
                return
            end
            missionProgressBar_:SetStyle({ width = tostring(math.floor(progress * 100)) .. "%" })
            missionTimeLabel_:SetText(FormatDuration(remaining) .. " 剩余")
        end
    elseif missionTimeLabel_ and not missionProgressBar_ and dragonManager_.IsMissionOnCooldown() then
        -- 冷却倒计时
        local cd = dragonManager_.GetMissionCooldown()
        local fp = "cd:" .. math.floor(cd)
        if fp ~= lastMissionFP_ then
            lastMissionFP_ = fp
            if cd <= 0 then
                -- 冷却结束 → 需要结构变化（显示任务列表）
                RebuildContent()
                return
            end
            missionTimeLabel_:SetText("新任务将在 " .. FormatDuration(cd) .. " 后刷新")
        end
    end

    -- 洞察收集状态
    for _, drop in ipairs(DD.drops) do
        local cache = dropRowCache_[drop.id]
        if cache then
            local isCollected = dragonManager_.HasDrop(drop.id)
            if isCollected ~= cache.lastCollected then
                cache.lastCollected = isCollected
                cache.statusLabel:SetText(isCollected and "✓" or "?")
                cache.statusLabel:SetFontColor(isCollected and C_GREEN or { 80, 75, 65, 150 })
                cache.row:SetStyle({
                    backgroundColor = isCollected and { 35, 45, 30, 255 } or { 25, 22, 20, 180 },
                    borderColor = isCollected and { 100, 180, 80, 120 } or { 40, 35, 30, 60 },
                    opacity = isCollected and 1.0 or 0.4,
                })
            end
        end
    end
end

-- ============================================================================
-- 内部：构建面板
-- ============================================================================

local function BuildPanel()
    dragonInfoLabel_ = UI.Label {
        text = "",
        fontSize = 13,
        fontColor = C_TEXT,
        textAlign = "center",
        marginBottom = 8,
    }

    contentContainer_ = UI.Panel {
        width = "100%",
        gap = 6,
        paddingBottom = 20,
    }

    panel_ = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        alignItems = "center",
        paddingTop = 12, paddingLeft = 8, paddingRight = 8,
        pointerEvents = "auto",
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                marginBottom = 4,
                children = {
                    UI.Panel { width = 22, height = 22,
                        backgroundImage = "image/侧栏_AI_20260414105511.png",
                        backgroundFit = "contain" },
                    UI.Label {
                        text = "AI合伙人 K1",
                        fontSize = 18,
                        fontColor = C_GOLD,
                    },
                },
            },
            dragonInfoLabel_,
            UI.ScrollView {
                flex = 1,
                width = "100%",
                showScrollbar = false,
                children = {
                    contentContainer_,
                },
            },
        },
    }
end

-- ============================================================================
-- 公共接口
-- ============================================================================

function DP.Init(root, manager, upgradeCb, equipAuraCb, petCb)
    uiRoot_ = root
    dragonManager_ = manager
    onUpgrade_ = upgradeCb
    onEquipAura_ = equipAuraCb
    onPetDragon_ = petCb
    BuildPanel()
end

function DP.Show()
    if not panel_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    uiRoot_:AddChild(panel_)
    initialized_ = false
    lastSnapshot_ = ""
    lastInfoText_ = ""
    upgradeBtnCache_ = nil
    eggBtnCache_ = nil
    auraRowCache_ = {}
    dropRowCache_ = {}
    slot1Label_ = nil
    slot2Label_ = nil
    xpBarFill_ = nil
    xpBarLabel_ = nil
    xpRateLabel_ = nil
    talentPointsLabel_ = nil
    talentTierCache_ = {}
    selectedBranch_ = 1
    talentTabCache_ = {}
    talentContentBox_ = nil
    missionProgressBar_ = nil
    missionTimeLabel_ = nil
    missionSection_ = nil
    lastMissionFP_ = ""
    DP.Refresh()
end

function DP.Hide()
    if not panel_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(panel_)
end

function DP.Toggle()
    if visible_ then DP.Hide() else DP.Show() end
end

function DP.IsVisible() return visible_ end

-- ============================================================================
-- 刷新
-- ============================================================================

function DP.Refresh()
    if not visible_ or not dragonManager_ then return end

    if dragonInfoLabel_ then
        local level = dragonManager_.GetLevel()
        local levelDef = dragonManager_.GetCurrentLevelDef()
        local text = ""
        if level < 0 then
            text = "尚未购买AI原型机"
        elseif levelDef then
            text = levelDef.name .. "  (Lv." .. level .. "/" .. DD.MAX_LEVEL .. ")"
        end
        if text ~= lastInfoText_ then
            dragonInfoLabel_:SetText(text)
            lastInfoText_ = text
        end
    end

    local snap = MakeSnapshot()
    if snap == lastSnapshot_ then
        if initialized_ then IncrementalUpdate() end
        return
    end

    local needRebuild = not initialized_
    if not needRebuild then
        local oldLevel = lastSnapshot_:match("L:(%-?%d+)")
        local newLevel = snap:match("L:(%-?%d+)")
        if oldLevel ~= newLevel then needRebuild = true end
        if not needRebuild then
            local oldUA = lastSnapshot_:match("UA:(%d+)")
            local newUA = snap:match("UA:(%d+)")
            if oldUA ~= newUA then needRebuild = true end
        end
        if not needRebuild then
            local oldTL = lastSnapshot_:match("TL:(%d+)")
            local newTL = snap:match("TL:(%d+)")
            if oldTL ~= newTL then needRebuild = true end
        end
    end

    lastSnapshot_ = snap

    if needRebuild then
        RebuildContent()
    else
        IncrementalUpdate()
    end
end

return DP
