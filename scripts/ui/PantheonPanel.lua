-- ============================================================================
-- ui/PantheonPanel.lua
-- 商业顾问团面板 —— 槽位管理、顾问选择、效果预览
-- 右侧抽屉栏，定位在商店面板左侧（与孵化园一致）
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local PC = require("config.PantheonConfig")

local PP = {}

-- 内部引用
local uiRoot_       = nil
local overlay_      = nil   -- 抽屉容器
local panel_        = nil
local visible_      = false
local pantheonMgr_  = nil   -- PantheonManager 引用
local manager_      = nil   -- GameManager 引用

-- UI 缓存
local slotsContainer_   = nil
local spiritsContainer_ = nil
local effectSummary_    = nil
local statusLabel_      = nil

-- 交互状态
local selectedSpirit_   = nil   -- 当前选中的顾问 id（用于装备操作）
local selectedSlot_     = nil   -- 当前选中的槽位索引（用于装备操作）

-- 刷新快照
local lastFingerprint_  = ""

-- ============================================================================
-- 工具
-- ============================================================================

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 3600 then
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        return string.format("%dh%02dm", h, m)
    end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

-- ============================================================================
-- 前向声明（local 化内部函数，防止全局污染）
-- ============================================================================
local BuildPanel
local RebuildSlots
local RebuildSpirits
local RebuildEffectSummary
local UpdateStatus
local OnSlotClick
local OnSpiritClick
local OnRemoveSpirit
local TryEquip

-- ============================================================================
-- 初始化
-- ============================================================================

function PP.Init(root, gm)
    uiRoot_ = root
    manager_ = gm
    pantheonMgr_ = gm.GetPantheonManager()
    BuildPanel()
end

-- ============================================================================
-- 显示 / 隐藏
-- ============================================================================

function PP.Show()
    if not overlay_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    lastFingerprint_ = ""
    selectedSpirit_ = nil
    selectedSlot_ = nil
    uiRoot_:AddChild(overlay_)
    PP.Refresh()
end

function PP.Hide()
    if not overlay_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(overlay_)
end

function PP.Toggle()
    if visible_ then PP.Hide() else PP.Show() end
end

function PP.IsVisible()
    return visible_
end

-- ============================================================================
-- 刷新（增量）
-- ============================================================================

function PP.Refresh()
    if not visible_ or not pantheonMgr_ then return end

    -- 构建指纹
    local fp = "tc" .. pantheonMgr_.GetTempleCount()
             .. ":lv" .. pantheonMgr_.GetTempleLevel()
             .. ":sel" .. tostring(selectedSpirit_)
             .. ":ss" .. tostring(selectedSlot_)

    for i = 1, PC.SLOT_COUNT do
        fp = fp .. ":s" .. i .. (pantheonMgr_.GetSlotSpirit(i) or "x")
        fp = fp .. "cd" .. math.floor(pantheonMgr_.GetSlotCooldown(i) / 5)
    end

    if fp == lastFingerprint_ then return end
    lastFingerprint_ = fp

    RebuildSlots()
    RebuildSpirits()
    RebuildEffectSummary()
    UpdateStatus()
end

-- ============================================================================
-- 内部：构建面板骨架
-- ============================================================================

BuildPanel = function()
    slotsContainer_ = UI.Panel {
        width = "100%",
        gap = 6,
        paddingLeft = 6, paddingRight = 6,
    }

    spiritsContainer_ = UI.Panel {
        width = "100%",
        gap = 4,
        paddingLeft = 4, paddingRight = 4,
    }

    effectSummary_ = UI.Panel {
        width = "100%",
        gap = 3,
        paddingLeft = 6, paddingRight = 6,
    }

    statusLabel_ = UI.Label {
        text = "",
        fontSize = 10,
        fontColor = { 150, 150, 180, 200 },
        textAlign = "center",
        width = "100%",
    }

    panel_ = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        alignItems = "center",
        paddingTop = 10, paddingLeft = 6, paddingRight = 6,
        paddingBottom = 6,
        pointerEvents = "auto",
        children = {
            -- 标题行（含关闭按钮）
            UI.Panel {
                width = "100%",
                flexDirection = "row", alignItems = "center",
                justifyContent = "space-between",
                marginBottom = 4,
                paddingLeft = 6, paddingRight = 4,
                children = {
                    UI.Label {
                        text = "商业顾问团",
                        fontSize = 17,
                        fontColor = { 220, 180, 100, 255 },
                    },
                    UI.Panel {
                        width = 28, height = 28,
                        justifyContent = "center", alignItems = "center",
                        borderRadius = 14,
                        backgroundColor = { 60, 55, 80, 180 },
                        pointerEvents = "auto",
                        onPointerDown = function()
                            PP.Hide()
                        end,
                        children = {
                            UI.Label {
                                text = "X",
                                fontSize = 14,
                                fontColor = { 200, 200, 220, 220 },
                                textAlign = "center",
                            },
                        },
                    },
                },
            },

            -- 可滚动内容
            UI.ScrollView {
                flex = 1,
                width = "100%",
                showScrollbar = false,
                children = {
                    UI.Panel {
                        width = "100%",
                        gap = 10,
                        paddingBottom = 20,
                        alignItems = "center",
                        children = {
                            -- 顾问席位
                            UI.Label {
                                text = "顾问席位",
                                fontSize = 12,
                                fontColor = { 180, 170, 200, 180 },
                                width = "100%", textAlign = "center",
                            },
                            slotsContainer_,

                            -- 操作提示
                            statusLabel_,

                            -- 可用顾问
                            UI.Label {
                                text = "可用顾问",
                                fontSize = 12,
                                fontColor = { 180, 170, 200, 180 },
                                width = "100%", textAlign = "center",
                                marginTop = 4,
                            },
                            spiritsContainer_,

                            -- 当前效果汇总
                            UI.Label {
                                text = "当前效果",
                                fontSize = 12,
                                fontColor = { 180, 170, 200, 180 },
                                width = "100%", textAlign = "center",
                                marginTop = 4,
                            },
                            effectSummary_,
                        },
                    },
                },
            },
        },
    }

    -- 右侧抽屉栏
    local dpr = graphics:GetDPR()
    local logicalW = graphics:GetWidth() / dpr
    local drawerW = math.floor(logicalW * 0.3)

    overlay_ = UI.Panel {
        position = "absolute",
        top = 0,
        right = "30%",
        width = drawerW,
        height = "100%",
        backgroundColor = { 28, 26, 38, 245 },
        borderColor = { 120, 100, 60, 100 },
        borderWidth = { 0, 1, 0, 1 },
        pointerEvents = "auto",
        zIndex = 100,
        children = {
            panel_,
        },
    }
end

-- ============================================================================
-- 内部：重建槽位区
-- ============================================================================

RebuildSlots = function()
    if not slotsContainer_ or not pantheonMgr_ then return end
    slotsContainer_:RemoveAllChildren()

    local available = pantheonMgr_.GetAvailableSlots()

    for i = 1, PC.SLOT_COUNT do
        local slotDef = PC.slots[i]
        local isLocked = (i > available)
        local spiritId = pantheonMgr_.GetSlotSpirit(i)
        local cooldown = pantheonMgr_.GetSlotCooldown(i)
        local spirit = spiritId and PC.FindSpirit(spiritId) or nil
        local isSelected = (selectedSlot_ == i)

        -- 槽位背景色
        local bgColor
        if isLocked then
            bgColor = { 25, 24, 35, 200 }
        elseif isSelected then
            bgColor = { 50, 45, 30, 220 }
        elseif spirit then
            bgColor = { 35, 40, 55, 220 }
        else
            bgColor = { 30, 28, 45, 200 }
        end

        local borderColor
        if isSelected then
            borderColor = { 255, 200, 50, 200 }
        elseif isLocked then
            borderColor = { 40, 38, 55, 150 }
        else
            borderColor = { slotDef.color[1], slotDef.color[2], slotDef.color[3], 150 }
        end

        local slotIdx = i
        local slotRow = UI.Panel {
            width = "100%",
            flexDirection = "row", alignItems = "center",
            gap = 6,
            padding = 8,
            borderRadius = 8, borderWidth = isSelected and 2 or 1,
            backgroundColor = bgColor,
            borderColor = borderColor,
            opacity = isLocked and 0.4 or 1.0,
            pointerEvents = isLocked and "none" or "auto",
            onPointerDown = function()
                if not isLocked then
                    OnSlotClick(slotIdx)
                end
            end,
        }

        -- 槽位信息
        local infoCol = UI.Panel {
            flex = 1, flexShrink = 1,
            gap = 2,
        }

        local nameText = slotDef.name
        if isLocked then
            local neededForSlot = (i == 2) and 3 or 5
            nameText = nameText .. " (需 " .. neededForSlot .. " 商业地产)"
        end

        infoCol:AddChild(UI.Label {
            text = nameText,
            fontSize = 12,
            fontColor = isLocked
                and { 100, 95, 120, 150 }
                or { slotDef.color[1], slotDef.color[2], slotDef.color[3], 255 },
        })

        if spirit then
            infoCol:AddChild(UI.Label {
                text = spirit.name,
                fontSize = 11,
                fontColor = { 220, 210, 240, 220 },
            })

            -- 效果预览
            local effectVal = PC.GetEffectValue(spirit, i)
            local effectText = PC.FormatEffect(spirit.effectType, effectVal)
            infoCol:AddChild(UI.Label {
                text = effectText,
                fontSize = 9,
                fontColor = effectVal >= 0
                    and { 100, 220, 100, 200 }
                    or { 255, 180, 80, 200 },
            })

            -- 副作用
            if spirit.sideEffect then
                local seType, seVal = PC.GetSideEffectValue(spirit, i)
                if seType then
                    infoCol:AddChild(UI.Label {
                        text = PC.FormatEffect(seType, seVal),
                        fontSize = 9,
                        fontColor = { 255, 120, 100, 180 },
                    })
                end
            end
        elseif not isLocked then
            infoCol:AddChild(UI.Label {
                text = "空席 - 点击选择顾问",
                fontSize = 10,
                fontColor = { 120, 115, 140, 160 },
            })
        end

        slotRow:AddChild(infoCol)

        -- 冷却 / 操作按钮
        if not isLocked then
            if cooldown > 0 then
                slotRow:AddChild(UI.Label {
                    text = "⏳" .. FormatTime(cooldown),
                    fontSize = 10,
                    fontColor = { 255, 180, 80, 220 },
                })
            elseif spirit then
                -- 移除按钮
                slotRow:AddChild(UI.Panel {
                    width = 28, height = 28,
                    justifyContent = "center", alignItems = "center",
                    borderRadius = 6,
                    backgroundColor = { 80, 40, 40, 200 },
                    borderWidth = 1,
                    borderColor = { 160, 60, 60, 150 },
                    pointerEvents = "auto",
                    onPointerDown = function(self, event)
                        if event and event.stopPropagation then
                            event:stopPropagation()
                        end
                        OnRemoveSpirit(slotIdx)
                    end,
                    children = {
                        UI.Label { text = "✕", fontSize = 12, fontColor = { 255, 150, 150, 220 } },
                    },
                })
            end
        end

        slotsContainer_:AddChild(slotRow)
    end
end

-- ============================================================================
-- 内部：重建顾问列表
-- ============================================================================

RebuildSpirits = function()
    if not spiritsContainer_ or not pantheonMgr_ then return end
    spiritsContainer_:RemoveAllChildren()

    local unlocked = pantheonMgr_.GetUnlockedSpirits()
    local templeCount = pantheonMgr_.GetTempleCount()

    if #unlocked == 0 then
        spiritsContainer_:AddChild(UI.Label {
            text = "需要至少 1 个商业地产",
            fontSize = 10,
            fontColor = { 120, 115, 140, 160 },
            textAlign = "center",
            width = "100%",
        })
        return
    end

    -- 所有顾问（含未解锁的，用于展示进度）
    for _, spirit in ipairs(PC.spirits) do
        local isUnlocked = (templeCount >= spirit.unlockCount)
        local isEquipped, equippedSlot = pantheonMgr_.IsSpiritEquipped(spirit.id)
        local isSelected = (selectedSpirit_ == spirit.id)

        local bgColor
        if isEquipped then
            bgColor = { 35, 45, 55, 220 }
        elseif isSelected then
            bgColor = { 55, 50, 30, 220 }
        elseif isUnlocked then
            bgColor = { 30, 28, 45, 200 }
        else
            bgColor = { 25, 24, 35, 150 }
        end

        local borderColor
        if isSelected then
            borderColor = { 255, 200, 50, 200 }
        elseif isEquipped then
            local slotDef = PC.slots[equippedSlot]
            borderColor = slotDef and { slotDef.color[1], slotDef.color[2], slotDef.color[3], 180 }
                or { 80, 120, 180, 150 }
        elseif isUnlocked then
            borderColor = { 60, 55, 80, 120 }
        else
            borderColor = { 40, 38, 55, 80 }
        end

        local sid = spirit.id
        local row = UI.Panel {
            width = "100%",
            flexDirection = "row", alignItems = "center",
            gap = 6,
            padding = 6,
            borderRadius = 6, borderWidth = isSelected and 2 or 1,
            backgroundColor = bgColor,
            borderColor = borderColor,
            opacity = isUnlocked and 1.0 or 0.4,
            pointerEvents = isUnlocked and "auto" or "none",
            onPointerDown = function()
                if isUnlocked and not isEquipped then
                    OnSpiritClick(sid)
                end
            end,
        }

        -- 信息列
        local infoCol = UI.Panel {
            flex = 1, flexShrink = 1,
            gap = 1,
        }

        -- 名称行
        local nameParts = {
            UI.Label {
                text = spirit.name,
                fontSize = 11,
                fontColor = isEquipped
                    and { 200, 220, 255, 255 }
                    or (isUnlocked and { 220, 210, 240, 220 } or { 100, 95, 120, 160 }),
            },
        }
        if isEquipped then
            local slotDef = PC.slots[equippedSlot]
            nameParts[#nameParts + 1] = UI.Label {
                text = slotDef and (" " .. slotDef.name) or "",
                fontSize = 10,
                fontColor = { slotDef.color[1], slotDef.color[2], slotDef.color[3], 180 },
            }
        end

        infoCol:AddChild(UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            children = nameParts,
        })

        -- 描述
        infoCol:AddChild(UI.Label {
            text = isUnlocked and spirit.desc or ("需要 " .. spirit.unlockCount .. " 商业地产"),
            fontSize = 9,
            fontColor = { 140, 135, 160, 160 },
        })

        -- 效果预览（金席基准）
        if isUnlocked then
            local effectText = PC.FormatEffect(spirit.effectType, spirit.baseEffect)
            local previewParts = { effectText .. " (金席)" }

            if spirit.sideEffect then
                previewParts[#previewParts + 1] = PC.FormatEffect(spirit.sideEffect.type, spirit.sideEffect.value)
            end
            if spirit.extraEffect then
                previewParts[#previewParts + 1] = PC.FormatEffect(spirit.extraEffect.type, spirit.extraEffect.value)
            end

            infoCol:AddChild(UI.Label {
                text = table.concat(previewParts, " | "),
                fontSize = 8,
                fontColor = { 150, 180, 150, 180 },
            })
        end

        row:AddChild(infoCol)

        spiritsContainer_:AddChild(row)
    end
end

-- ============================================================================
-- 内部：重建效果汇总
-- ============================================================================

RebuildEffectSummary = function()
    if not effectSummary_ or not pantheonMgr_ then return end
    effectSummary_:RemoveAllChildren()

    local effects = pantheonMgr_.GetActiveEffects()

    -- 检查是否有任何效果
    local hasEffect = false
    for _ in pairs(effects) do hasEffect = true; break end

    if not hasEffect then
        effectSummary_:AddChild(UI.Label {
            text = "尚未装备任何顾问",
            fontSize = 10,
            fontColor = { 120, 115, 140, 160 },
            textAlign = "center",
            width = "100%",
        })
        return
    end

    -- 按正面/负面分组显示
    local positives = {}
    local negatives = {}

    for effectType, value in pairs(effects) do
        local text = PC.FormatEffect(effectType, value)
        if value >= 0 then
            positives[#positives + 1] = text
        else
            negatives[#negatives + 1] = text
        end
    end

    if #positives > 0 then
        for _, text in ipairs(positives) do
            effectSummary_:AddChild(UI.Label {
                text = text,
                fontSize = 10,
                fontColor = { 100, 220, 100, 220 },
            })
        end
    end

    if #negatives > 0 then
        for _, text in ipairs(negatives) do
            effectSummary_:AddChild(UI.Label {
                text = text,
                fontSize = 10,
                fontColor = { 255, 150, 80, 200 },
            })
        end
    end
end

-- ============================================================================
-- 内部：更新状态标签
-- ============================================================================

UpdateStatus = function()
    if not statusLabel_ then return end

    if selectedSlot_ and selectedSpirit_ then
        local spirit = PC.FindSpirit(selectedSpirit_)
        local slotDef = PC.slots[selectedSlot_]
        if spirit and slotDef then
            statusLabel_:SetText("将 " .. spirit.name .. " 装备到 " .. slotDef.name .. " → 点击确认")
            statusLabel_:SetFontColor({ 255, 220, 80, 255 })
            return
        end
    end

    if selectedSlot_ then
        local slotDef = PC.slots[selectedSlot_]
        statusLabel_:SetText("已选 " .. (slotDef and slotDef.name or "席位") .. "，请选择一位顾问")
        statusLabel_:SetFontColor({ 200, 180, 120, 220 })
    elseif selectedSpirit_ then
        local spirit = PC.FindSpirit(selectedSpirit_)
        statusLabel_:SetText("已选 " .. (spirit and spirit.name or "顾问") .. "，请选择一个席位")
        statusLabel_:SetFontColor({ 200, 180, 120, 220 })
    else
        statusLabel_:SetText("点击席位或顾问进行装备")
        statusLabel_:SetFontColor({ 150, 150, 180, 200 })
    end
end

-- ============================================================================
-- 交互回调
-- ============================================================================

OnSlotClick = function(slotIndex)
    if not pantheonMgr_ then return end

    selectedSlot_ = slotIndex

    -- 如果已选顾问 → 尝试装备
    if selectedSpirit_ then
        TryEquip()
    else
        lastFingerprint_ = ""
        PP.Refresh()
    end
end

OnSpiritClick = function(spiritId)
    if not pantheonMgr_ then return end

    -- 切换选中
    if selectedSpirit_ == spiritId then
        selectedSpirit_ = nil
    else
        selectedSpirit_ = spiritId
    end

    -- 如果已选槽位 → 尝试装备
    if selectedSpirit_ and selectedSlot_ then
        TryEquip()
    else
        lastFingerprint_ = ""
        PP.Refresh()
    end
end

OnRemoveSpirit = function(slotIndex)
    if not pantheonMgr_ or not manager_ then return end

    local ok, reason = pantheonMgr_.EquipSpirit(slotIndex, nil)
    if ok then
        print("[Pantheon] 移除槽位 " .. slotIndex .. " 的顾问")
        -- 通知 GameManager 重新计算
        if manager_.RecalcProduction then
            manager_.RecalcProduction()
        end
    else
        print("[Pantheon] 移除失败: " .. tostring(reason))
    end

    selectedSlot_ = nil
    selectedSpirit_ = nil
    lastFingerprint_ = ""
    PP.Refresh()
end

TryEquip = function()
    if not pantheonMgr_ or not manager_ then return end
    if not selectedSlot_ or not selectedSpirit_ then return end

    local ok, reason = pantheonMgr_.EquipSpirit(selectedSlot_, selectedSpirit_)
    if ok then
        print("[Pantheon] 装备 " .. selectedSpirit_ .. " 到槽位 " .. selectedSlot_)
        if manager_.RecalcProduction then
            manager_.RecalcProduction()
        end
    else
        print("[Pantheon] 装备失败: " .. tostring(reason))
    end

    selectedSlot_ = nil
    selectedSpirit_ = nil
    lastFingerprint_ = ""
    PP.Refresh()
end

return PP
