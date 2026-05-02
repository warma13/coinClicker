-- ============================================================================
-- ui/DragonPanel.lua
-- AI合伙人面板（全屏覆盖式弹窗）
-- AI等级展示 + 投入升级 + 策略模块装备 + AI洞察
-- 使用 AddChild/RemoveChild 控制显隐
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
local onUpgrade_ = nil           -- function()
local onEquipAura_ = nil         -- function(slot, auraId)
local onPetDragon_ = nil         -- function()

-- ======== 增量刷新缓存 ========
local lastSnapshot_ = ""
local lastInfoText_ = ""
-- 升级按钮缓存
local upgradeBtnCache_ = nil     -- { panel, nameLabel, costLabel, descLabel, lastFP }
-- 购买龙蛋按钮缓存
local eggBtnCache_ = nil         -- { panel, costLabel, lastFP }
-- 光环行缓存
local auraRowCache_ = {}         -- auraRowCache_[auraId] = { row, statusLabel, lastFP }
-- 掉落物行缓存
local dropRowCache_ = {}         -- dropRowCache_[dropId] = { row, statusLabel, lastCollected }
-- 光环槽显示缓存
local slot1Label_ = nil
local slot2Label_ = nil
local initialized_ = false

-- ============================================================================
-- 快照生成
-- ============================================================================

local function MakeSnapshot()
    local parts = {}
    local level = dragonManager_.GetLevel()
    parts[#parts + 1] = "L:" .. level

    if level < 0 then
        -- 未购买
        local eggDef = DD.GetLevel(0)
        parts[#parts + 1] = "CB:" .. ((eggDef and GameState.coins >= eggDef.cost) and "Y" or "N")
    else
        -- 已购买
        local isMaxLevel = dragonManager_.IsMaxLevel()
        parts[#parts + 1] = "MX:" .. (isMaxLevel and "Y" or "N")

        if not isMaxLevel then
            parts[#parts + 1] = "CU:" .. (dragonManager_.CanUpgrade() and "Y" or "N")
        end

        -- 光环装备状态
        parts[#parts + 1] = "A1:" .. (dragonManager_.GetEquippedAuraId(1) or "nil")
        parts[#parts + 1] = "A2:" .. (dragonManager_.GetEquippedAuraId(2) or "nil")
        parts[#parts + 1] = "S2:" .. (dragonManager_.IsSecondSlotUnlocked() and "Y" or "N")

        -- 解锁光环数
        local unlockedAuras = dragonManager_.GetUnlockedAuras()
        parts[#parts + 1] = "UA:" .. #unlockedAuras

        -- 掉落物收集
        if dragonManager_.IsDropsUnlocked() and level >= 23 then
            for _, drop in ipairs(DD.drops) do
                if dragonManager_.HasDrop(drop.id) then
                    parts[#parts + 1] = "D:" .. drop.id
                end
            end
        end
    end

    return table.concat(parts, "|")
end

-- ============================================================================
-- 构建光环行（带缓存）
-- ============================================================================

local function BuildAuraRow(aura, isUnlocked, equippedSlot)
    local auraId = aura.id
    local statusText = ""
    local statusColor = { 100, 95, 115, 160 }
    if equippedSlot == 1 then
        statusText = "主策略"
        statusColor = { 255, 200, 80, 255 }
    elseif equippedSlot == 2 then
        statusText = "副策略"
        statusColor = { 180, 150, 255, 255 }
    elseif isUnlocked then
        statusText = "装备"
        statusColor = { 120, 180, 120, 200 }
    else
        statusText = "锁定"
    end

    local statusLabel = UI.Label { text = statusText, fontSize = 10,
        fontColor = statusColor,
        width = 40, textAlign = "center" }

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
        pointerEvents = isUnlocked and "auto" or "none",
        onPointerDown = isUnlocked and function()
            if equippedSlot then
                if onEquipAura_ then onEquipAura_(equippedSlot, nil) end
            else
                if onEquipAura_ then onEquipAura_(1, auraId) end
            end
            DP.Refresh()
        end or nil,
        children = {
            UI.Panel { width = 28, height = 28,
                backgroundImage = aura.iconImage or "image/icon_chart.png",
                backgroundFit = "contain" },
            UI.Panel { flex = 1, flexShrink = 1, gap = 1, children = {
                UI.Label { text = aura.name, fontSize = 12,
                    fontColor = isUnlocked and { 200, 190, 140, 255 }
                        or { 100, 95, 85, 160 } },
                UI.Label { text = aura.desc, fontSize = 9,
                    fontColor = { 140, 130, 115, 160 } },
            }},
            statusLabel,
        },
    }

    local fp = (equippedSlot or 0) .. ":" .. (isUnlocked and "Y" or "N")
    auraRowCache_[aura.id] = { row = row, statusLabel = statusLabel, lastFP = fp }

    return row
end

-- ============================================================================
-- 构建掉落物行（带缓存）
-- ============================================================================

local function BuildDropRow(drop, isCollected)
    local statusLabel = UI.Label { text = isCollected and "✓" or "?", fontSize = 12,
        fontColor = isCollected and { 100, 200, 100, 200 }
            or { 80, 75, 65, 150 },
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
                    fontColor = isCollected and { 150, 220, 120, 255 }
                        or { 100, 95, 85, 160 } },
                UI.Label { text = drop.desc, fontSize = 9,
                    fontColor = { 130, 125, 110, 160 } },
            }},
            statusLabel,
        },
    }

    dropRowCache_[drop.id] = { row = row, statusLabel = statusLabel, lastCollected = isCollected }

    return row
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

    local F = GameState.FormatNumber
    local level = dragonManager_.GetLevel()
    local levelDef = dragonManager_.GetCurrentLevelDef()
    local isMaxLevel = dragonManager_.IsMaxLevel()

    -- ===== 龙未购买：显示购买按钮 =====
    if level < 0 then
        local eggDef = DD.GetLevel(0)
        local canBuy = eggDef and GameState.coins >= eggDef.cost

        local costLabel = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            children = {
                UI.Label { text = "费用:", fontSize = 12, fontColor = { 180, 160, 120, 200 } },
                UI.Panel { width = 14, height = 14,
                    backgroundImage = "image/金币.png", backgroundFit = "contain" },
                UI.Label { text = eggDef and F(eggDef.cost) or "?",
                    fontSize = 12, fontColor = { 180, 160, 120, 200 } },
            },
        }

        local eggBtn = UI.Panel {
            width = "100%", padding = 16, borderRadius = 8, borderWidth = 1,
            justifyContent = "center", alignItems = "center", gap = 8,
            backgroundColor = canBuy and { 60, 45, 20, 255 } or { 35, 28, 20, 220 },
            borderColor = canBuy and { 220, 180, 60, 200 } or { 60, 50, 40, 100 },
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
                    backgroundImage = "image/icon_ai_prototype.png",
                    backgroundFit = "contain" },
                UI.Label { text = "购买AI原型机", fontSize = 16,
                    fontColor = canBuy and { 240, 200, 100, 255 }
                        or { 140, 120, 90, 200 } },
                costLabel,
            },
        }
        contentContainer_:AddChild(eggBtn)
        eggBtnCache_ = { panel = eggBtn, costLabel = costLabel, lastFP = canBuy and "Y" or "N" }
        initialized_ = true
        return
    end

    -- ===== 龙等级与升级 =====
    contentContainer_:AddChild(UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 4, marginBottom = 4,
        children = {
            UI.Panel { width = 14, height = 14,
                backgroundImage = "image/icon_chart.png", backgroundFit = "contain" },
            UI.Label { text = "AI等级与升级", fontSize = 12,
                fontColor = { 200, 180, 140, 200 } },
        },
    })

    -- 当前等级状态
    local phaseImg = (levelDef and levelDef.iconImage) or "image/icon_ai_robot.png"

    contentContainer_:AddChild(UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        padding = 10, gap = 10, borderRadius = 8, borderWidth = 1,
        backgroundColor = { 40, 35, 22, 255 },
        borderColor = { 160, 140, 80, 150 },
        children = {
            UI.Panel { width = 40, height = 40,
                backgroundImage = phaseImg, backgroundFit = "contain" },
            UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                UI.Label { text = (levelDef and levelDef.name or "???"),
                    fontSize = 15, fontColor = { 240, 210, 130, 255 } },
                UI.Label { text = "Lv." .. level .. " / " .. DD.MAX_LEVEL,
                    fontSize = 11, fontColor = { 180, 160, 120, 200 } },
            }},
        },
    })

    -- 升级按钮（未满级时显示）
    if not isMaxLevel then
        local nextDef = dragonManager_.GetNextLevelDef()
        local canUpgrade = dragonManager_.CanUpgrade()
        local costText = dragonManager_.GetUpgradeCostText()

        local nameLabel = UI.Label { text = nextDef and nextDef.name or "升级",
            fontSize = 13,
            fontColor = canUpgrade and { 255, 220, 100, 255 }
                or { 160, 140, 100, 180 } }

        local costIcon = dragonManager_.GetUpgradeCostIcon()
        local costChildren = {}
        costChildren[#costChildren + 1] = UI.Label { text = "投入: ", fontSize = 11,
            fontColor = { 180, 160, 120, 180 } }
        if costIcon then
            costChildren[#costChildren + 1] = UI.Panel { width = 13, height = 13,
                backgroundImage = costIcon, backgroundFit = "contain" }
        end
        costChildren[#costChildren + 1] = UI.Label { text = costText, fontSize = 11,
            fontColor = { 180, 160, 120, 180 } }
        local costLabel = UI.Panel { flexDirection = "row", alignItems = "center", gap = 3,
            children = costChildren }

        local descLabel = UI.Label { text = nextDef and nextDef.desc or "",
            fontSize = 9, fontColor = { 140, 130, 100, 160 } }

        local upgradeBtn = UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            padding = 10, gap = 8, borderRadius = 6, borderWidth = 1,
            backgroundColor = canUpgrade and { 55, 40, 15, 255 } or { 35, 28, 20, 200 },
            borderColor = canUpgrade and { 255, 180, 60, 200 } or { 70, 55, 40, 100 },
            pointerEvents = canUpgrade and "auto" or "none",
            onPointerDown = canUpgrade and function()
                if onUpgrade_ then
                    onUpgrade_()
                    initialized_ = false
                    DP.Refresh()
                end
            end or nil,
            children = {
                UI.Panel { width = 28, height = 28,
                    backgroundImage = "image/icon_upgrade_arrow.png",
                    backgroundFit = "contain" },
                UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                    nameLabel,
                    costLabel,
                    descLabel,
                }},
            },
        }
        contentContainer_:AddChild(upgradeBtn)
        upgradeBtnCache_ = {
            panel = upgradeBtn,
            nameLabel = nameLabel,
            costLabel = costLabel,
            descLabel = descLabel,
            lastFP = (canUpgrade and "Y" or "N"),
        }
    end

    -- ===== 启发灵感 =====
    if dragonManager_.IsDropsUnlocked() and level >= 23 then
        contentContainer_:AddChild(UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            marginTop = 10, marginBottom = 4,
            children = {
                UI.Panel { width = 14, height = 14,
                    backgroundImage = "image/icon_inspiration.png", backgroundFit = "contain" },
                UI.Label { text = "启发灵感", fontSize = 12,
                    fontColor = { 200, 180, 140, 200 } },
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
                    backgroundImage = "image/icon_ai_robot.png",
                    backgroundFit = "contain" },
                UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                    UI.Label { text = "启发 K1 灵感", fontSize = 13,
                        fontColor = { 220, 200, 140, 255 } },
                    UI.Label { text = "5% 概率获得AI洞察", fontSize = 10,
                        fontColor = { 160, 145, 110, 180 } },
                }},
            },
        })

        -- 掉落物列表
        for _, drop in ipairs(DD.drops) do
            local isCollected = dragonManager_.HasDrop(drop.id)
            contentContainer_:AddChild(BuildDropRow(drop, isCollected))
        end
    end

    -- ===== 光环装备 =====
    local unlockedAuras = dragonManager_.GetUnlockedAuras()
    if #unlockedAuras > 0 then
        contentContainer_:AddChild(UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            marginTop = 10, marginBottom = 4,
            children = {
                UI.Panel { width = 14, height = 14,
                    backgroundImage = "image/icon_market_predict.png", backgroundFit = "contain" },
                UI.Label { text = "AI策略模块", fontSize = 12,
                    fontColor = { 200, 180, 140, 200 } },
            },
        })

        local slot1Aura = dragonManager_.GetEquippedAura(1)
        local slot2Aura = dragonManager_.GetEquippedAura(2)

        slot1Label_ = UI.Label { text = slot1Aura and slot1Aura.name or "— 空 —",
            fontSize = 12, textAlign = "center",
            fontColor = slot1Aura and { 255, 220, 100, 255 }
                or { 100, 90, 70, 150 } }

        slot2Label_ = UI.Label {
            text = dragonManager_.IsSecondSlotUnlocked()
                and (slot2Aura and slot2Aura.name or "— 空 —")
                or "未解锁",
            fontSize = 12, textAlign = "center",
            fontColor = (slot2Aura and { 180, 160, 255, 255 })
                or { 100, 90, 110, 150 },
        }

        contentContainer_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row", gap = 8,
            marginBottom = 6,
            children = {
                UI.Panel {
                    flex = 1, padding = 8, borderRadius = 6, borderWidth = 1,
                    backgroundColor = { 40, 35, 18, 255 },
                    borderColor = { 200, 170, 60, 150 },
                    alignItems = "center", gap = 2,
                    children = {
                        UI.Label { text = "主策略", fontSize = 10,
                            fontColor = { 200, 170, 60, 200 } },
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
                (dragonManager_.IsSecondSlotUnlocked()
                    and "；长按装备到副槽位" or ""),
            fontSize = 9,
            fontColor = { 130, 120, 100, 150 },
            textAlign = "center",
            marginBottom = 4,
        })

        -- 光环列表
        for _, aura in ipairs(DD.auras) do
            local isUnlocked = dragonManager_.IsAuraUnlocked(aura.id)
            local equippedSlot = nil
            if dragonManager_.GetEquippedAuraId(1) == aura.id then
                equippedSlot = 1
            elseif dragonManager_.GetEquippedAuraId(2) == aura.id then
                equippedSlot = 2
            end
            contentContainer_:AddChild(BuildAuraRow(aura, isUnlocked, equippedSlot))
        end
    end

    -- ===== 全部龙等级列表 =====
    contentContainer_:AddChild(UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 4,
        marginTop = 10, marginBottom = 4,
        children = {
            UI.Panel { width = 14, height = 14,
                backgroundImage = "image/icon_ai_brain.png", backgroundFit = "contain" },
            UI.Label { text = "等级历程", fontSize = 12,
                fontColor = { 200, 180, 140, 200 } },
        },
    })

    for _, lvl in ipairs(DD.levels) do
        local isPassed = level >= lvl.level
        local isCurrent = level == lvl.level
        contentContainer_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            padding = 5, gap = 4, borderRadius = 3, borderWidth = isCurrent and 1 or 0,
            backgroundColor = isCurrent and { 50, 40, 20, 255 }
                or (isPassed and { 30, 35, 25, 220 } or { 22, 20, 18, 160 }),
            borderColor = isCurrent and { 220, 180, 60, 200 } or { 0, 0, 0, 0 },
            opacity = isPassed and 1.0 or 0.35,
            children = {
                UI.Label { text = string.format("%02d", lvl.level), fontSize = 9,
                    fontColor = { 140, 130, 100, 180 }, width = 18 },
                UI.Panel { flex = 1, flexShrink = 1, children = {
                    UI.Label { text = lvl.name, fontSize = 10,
                        fontColor = isPassed and { 180, 170, 120, 255 }
                            or { 100, 95, 80, 140 } },
                }},
                UI.Label {
                    text = isPassed and "✓" or (isCurrent and "◄" or ""),
                    fontSize = 9,
                    fontColor = isPassed and { 100, 180, 80, 200 }
                        or { 220, 180, 60, 255 },
                    width = 14, textAlign = "center",
                },
            },
        })
    end

    initialized_ = true
end

-- ============================================================================
-- 增量更新（结构不变时）
-- ============================================================================

local function IncrementalUpdate()
    local level = dragonManager_.GetLevel()

    -- 未购买龙蛋：更新购买按钮
    if level < 0 then
        if eggBtnCache_ then
            local eggDef = DD.GetLevel(0)
            local canBuy = eggDef and GameState.coins >= eggDef.cost
            local fp = canBuy and "Y" or "N"
            if fp ~= eggBtnCache_.lastFP then
                eggBtnCache_.lastFP = fp
                eggBtnCache_.panel:SetStyle({
                    backgroundColor = canBuy and { 60, 45, 20, 255 } or { 35, 28, 20, 220 },
                    borderColor = canBuy and { 220, 180, 60, 200 } or { 60, 50, 40, 100 },
                    pointerEvents = canBuy and "auto" or "none",
                })
            end
        end
        return
    end

    -- 升级按钮状态
    if upgradeBtnCache_ then
        local canUpgrade = dragonManager_.CanUpgrade()
        local fp = canUpgrade and "Y" or "N"
        if fp ~= upgradeBtnCache_.lastFP then
            -- costLabel 是 Panel（图文混排），状态变化时触发全量重建
            initialized_ = false
            RebuildContent()
            return
        end
    end

    -- 光环装备状态
    for _, aura in ipairs(DD.auras) do
        local cache = auraRowCache_[aura.id]
        if cache then
            local isUnlocked = dragonManager_.IsAuraUnlocked(aura.id)
            local equippedSlot = nil
            if dragonManager_.GetEquippedAuraId(1) == aura.id then
                equippedSlot = 1
            elseif dragonManager_.GetEquippedAuraId(2) == aura.id then
                equippedSlot = 2
            end

            local fp = (equippedSlot or 0) .. ":" .. (isUnlocked and "Y" or "N")
            if fp ~= cache.lastFP then
                cache.lastFP = fp

                local statusText, statusColor
                if equippedSlot == 1 then
                    statusText = "主策略"
                    statusColor = { 255, 200, 80, 255 }
                elseif equippedSlot == 2 then
                    statusText = "副策略"
                    statusColor = { 180, 150, 255, 255 }
                elseif isUnlocked then
                    statusText = "装备"
                    statusColor = { 120, 180, 120, 200 }
                else
                    statusText = "锁定"
                    statusColor = { 100, 95, 115, 160 }
                end

                cache.statusLabel:SetText(statusText)
                cache.statusLabel:SetFontColor(statusColor)
                cache.row:SetStyle({
                    backgroundColor = equippedSlot
                        and (equippedSlot == 1 and { 45, 40, 20, 255 } or { 30, 25, 45, 255 })
                        or (isUnlocked and { 30, 35, 28, 255 } or { 25, 22, 20, 180 }),
                    borderColor = equippedSlot
                        and (equippedSlot == 1 and { 200, 170, 60, 180 } or { 140, 120, 200, 180 })
                        or (isUnlocked and { 80, 120, 80, 100 } or { 40, 35, 30, 60 }),
                })
            end
        end
    end

    -- 光环槽标签
    if slot1Label_ then
        local slot1Aura = dragonManager_.GetEquippedAura(1)
        slot1Label_:SetText(slot1Aura and slot1Aura.name or "— 空 —")
        slot1Label_:SetFontColor(slot1Aura and { 255, 220, 100, 255 }
            or { 100, 90, 70, 150 })
    end
    if slot2Label_ then
        local slot2Aura = dragonManager_.GetEquippedAura(2)
        if dragonManager_.IsSecondSlotUnlocked() then
            slot2Label_:SetText(slot2Aura and slot2Aura.name or "— 空 —")
            slot2Label_:SetFontColor(slot2Aura and { 180, 160, 255, 255 }
                or { 100, 90, 110, 150 })
        end
    end

    -- 掉落物收集状态
    for _, drop in ipairs(DD.drops) do
        local cache = dropRowCache_[drop.id]
        if cache then
            local isCollected = dragonManager_.HasDrop(drop.id)
            if isCollected ~= cache.lastCollected then
                cache.lastCollected = isCollected
                cache.statusLabel:SetText(isCollected and "✓" or "?")
                cache.statusLabel:SetFontColor(isCollected and { 100, 200, 100, 200 }
                    or { 80, 75, 65, 150 })
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
        fontColor = { 200, 180, 140, 220 },
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
                        fontColor = { 240, 200, 120, 255 },
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
    -- 重置缓存
    initialized_ = false
    lastSnapshot_ = ""
    lastInfoText_ = ""
    upgradeBtnCache_ = nil
    eggBtnCache_ = nil
    auraRowCache_ = {}
    dropRowCache_ = {}
    slot1Label_ = nil
    slot2Label_ = nil
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
-- 刷新（增量）
-- ============================================================================

function DP.Refresh()
    if not visible_ or not dragonManager_ then return end

    -- 龙信息标签
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

    -- 快照检测
    local snap = MakeSnapshot()
    if snap == lastSnapshot_ then return end

    -- 判断是否结构变化
    local needRebuild = not initialized_
    if not needRebuild then
        local level = dragonManager_.GetLevel()
        -- 龙等级变化（可能解锁新区块）→ 结构重建
        local oldLevel = lastSnapshot_:match("L:(%-?%d+)")
        local newLevel = snap:match("L:(%-?%d+)")
        if oldLevel ~= newLevel then
            needRebuild = true
        end
        -- 解锁光环数变化
        if not needRebuild then
            local oldUA = lastSnapshot_:match("UA:(%d+)")
            local newUA = snap:match("UA:(%d+)")
            if oldUA ~= newUA then
                needRebuild = true
            end
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
