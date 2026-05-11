-- ============================================================================
-- ui/SkillPanel.lua
-- 技能面板 —— 展示与升级 5 个主动技能（看广告解锁/升级）
-- 样式对齐 HeavenlyShop（经验商店）
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local SkillDefs = require("config.SkillDefs")

local SP = {}

-- 内部引用
local uiRoot_   = nil
local panel_    = nil
local listContainer_ = nil
local visible_  = false
local manager_  = nil   -- GameManager

-- 技能行缓存
local rowCache_ = {}      -- rowCache_[skillId] = { row, nameLabel, lastFP, lastState }
local initialized_ = false

-- 前向声明（内部函数）
local BuildPanel
local BuildSkillRow
local FormatParams
local UpdateSkillRow

-- ============================================================================
-- 初始化
-- ============================================================================

function SP.Init(root, gm)
    uiRoot_ = root
    manager_ = gm
    BuildPanel()
end

-- ============================================================================
-- 显示 / 隐藏
-- ============================================================================

function SP.Show()
    if not panel_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    initialized_ = false
    rowCache_ = {}
    uiRoot_:AddChild(panel_)
    SP.Refresh()
end

function SP.Hide()
    if not panel_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(panel_)
end

function SP.Toggle()
    if visible_ then SP.Hide() else SP.Show() end
end

function SP.IsVisible()
    return visible_
end

-- ============================================================================
-- 刷新
-- ============================================================================

function SP.Refresh()
    if not visible_ or not manager_ then return end

    local SM = manager_.GetSkillManager()
    if not SM then return end

    if not listContainer_ then return end

    -- 收集所有技能状态
    local statusList = {}
    for _, def in ipairs(SkillDefs.list) do
        local info = SM.GetSkillInfo(def.id)
        if info then
            local isLocked = (info.level <= 0)
            local maxed = (info.level >= info.maxLevel)
            local isActive = info.active
            local adBusy = SM.IsAdBusy()
            statusList[#statusList + 1] = {
                def = def,
                info = info,
                locked = isLocked,
                maxed = maxed,
                active = isActive,
                adBusy = adBusy,
            }
        end
    end

    -- 首次构建
    if not initialized_ then
        initialized_ = true
        listContainer_:RemoveAllChildren()
        for _, s in ipairs(statusList) do
            listContainer_:AddChild(BuildSkillRow(s))
        end
        return
    end

    -- 增量更新：逐行检查指纹，状态类别变化时替换单行，否则原地更新
    for idx, s in ipairs(statusList) do
        local cache = rowCache_[s.def.id]
        if not cache then
            -- 缓存丢失，追加新行
            listContainer_:AddChild(BuildSkillRow(s))
        else
            local state = s.maxed and "M" or (s.locked and "L" or "U")
            local fp = state .. ":L" .. s.info.level
                     .. ":A" .. tostring(s.active)
                     .. ":B" .. tostring(s.adBusy)
                     .. ":C" .. tostring(s.info.canAfford)
            if fp ~= cache.lastFP then
                if state ~= cache.lastState then
                    -- 状态类别变化（锁定↔解锁↔满级）：需要替换整行（按钮结构不同）
                    -- 找到旧行索引，移除后在同位置插入新行
                    local oldIdx = nil
                    for ci, c in ipairs(listContainer_.children) do
                        if c == cache.row then oldIdx = ci; break end
                    end
                    listContainer_:RemoveChild(cache.row)
                    local newRow = BuildSkillRow(s)
                    if oldIdx then
                        listContainer_:InsertChild(newRow, oldIdx)
                    else
                        listContainer_:AddChild(newRow)
                    end
                else
                    -- 同类别内变化（等级/费用/激活/afford）：原地更新文本和样式
                    UpdateSkillRow(s)
                end
            end
        end
    end
end

-- ============================================================================
-- 内部：构建面板
-- ============================================================================

---@diagnostic disable-next-line: redefined-local
BuildPanel = function()
    listContainer_ = UI.Panel {
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
            -- 标题
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                marginBottom = 4,
                children = {
                    UI.Panel { width = 22, height = 22,
                        backgroundImage = "image/侧栏_技能.png",
                        backgroundFit = "contain" },
                    UI.Label {
                        text = "主动技能",
                        fontSize = 18,
                        fontColor = { 220, 200, 255, 255 },
                    },
                },
            },

            -- 副标题
            UI.Label {
                text = "解锁后消耗体力释放，金币升级",
                fontSize = 12,
                fontColor = { 150, 140, 170, 180 },
                marginBottom = 8,
            },

            -- 可滚动内容
            UI.ScrollView {
                flex = 1,
                width = "100%",
                showScrollbar = false,
                children = {
                    listContainer_,
                },
            },
        },
    }
end

-- ============================================================================
-- 内部：构建单行技能
-- ============================================================================

---@diagnostic disable-next-line: redefined-local
BuildSkillRow = function(status)
    local def = status.def
    local info = status.info
    local bgColor, borderColor

    if status.maxed then
        bgColor = { 25, 45, 30, 255 }
        borderColor = { 80, 180, 80, 150 }
    elseif not status.locked then
        bgColor = { 50, 40, 65, 255 }
        borderColor = { 200, 170, 255, 200 }
    else
        bgColor = { 20, 18, 30, 200 }
        borderColor = { 40, 35, 55, 100 }
    end

    -- 名称标签
    local nameLabel = UI.Label {
        text = def.name .. (not status.locked and (" Lv." .. info.level .. "/" .. info.maxLevel) or ""),
        fontSize = 13,
        fontColor = status.maxed and { 100, 200, 100, 255 }
            or (not status.locked and { 230, 220, 255, 255 }
            or { 100, 95, 120, 200 }),
    }

    -- 描述
    local descText = def.desc
    if not status.locked and info.params then
        descText = FormatParams(def, info.params)
    end
    -- (已移除激活提示文字)

    -- 状态按钮
    local statusWidget
    local costLabel, btnLabel   -- 仅 unlocked 状态赋值，其他状态为 nil
    local skillId = def.id

    if status.maxed then
        -- 满级
        statusWidget = UI.Panel {
            flexDirection = "row", alignItems = "center", justifyContent = "center",
            paddingLeft = 6, paddingRight = 6, paddingTop = 3, paddingBottom = 3,
            borderRadius = 6,
            backgroundColor = { 40, 70, 45, 200 },
            borderWidth = 1, borderColor = { 80, 180, 80, 120 },
            children = {
                UI.Label { text = "✓ 已满级", fontSize = 11,
                    fontColor = { 100, 200, 100, 200 }, textAlign = "center" },
            },
        }
    elseif not status.locked then
        -- 已解锁 → 金币升级按钮
        local cost = status.info.upgradeCost or 0
        local canAfford = status.info.canAfford
        local clickable = not status.active and canAfford
        local costText = GameState.FormatNumber(cost)
        btnLabel = UI.Label { text = "升级", fontSize = 12,
            fontColor = { 255, 255, 255, clickable and 240 or 120 } }
        costLabel = UI.Label { text = costText, fontSize = 9,
            fontColor = canAfford and { 255, 220, 80, 200 } or { 255, 100, 100, 180 } }
        statusWidget = UI.Panel {
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            paddingLeft = 6, paddingRight = 6, paddingTop = 3, paddingBottom = 3,
            borderRadius = 6, gap = 1,
            backgroundColor = clickable and { 80, 50, 120, 255 } or { 50, 45, 60, 200 },
            borderWidth = 1,
            borderColor = clickable and { 180, 130, 255, 200 } or { 70, 60, 90, 120 },
            pointerEvents = clickable and "auto" or "none",
            onPointerDown = clickable and function()
                if manager_ then
                    manager_.OnUpgradeSkill(skillId)
                end
            end or nil,
            children = { btnLabel, costLabel },
        }
    else
        -- 未解锁 → 解锁按钮
        statusWidget = UI.Panel {
            flexDirection = "row", alignItems = "center", justifyContent = "center",
            paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
            borderRadius = 6,
            backgroundColor = { 60, 40, 90, 255 },
            borderWidth = 1,
            borderColor = { 140, 100, 200, 180 },
            pointerEvents = "auto",
            onPointerDown = function()
                if manager_ then
                    manager_.OnUpgradeSkill(skillId)
                end
            end,
            children = {
                UI.Label { text = "解锁", fontSize = 12,
                    fontColor = { 255, 255, 255, 240 } },
            },
        }
    end

    -- 描述标签（缓存引用以支持增量更新）
    local descLabel = UI.Label { text = descText, fontSize = 10,
        fontColor = { 150, 140, 170, 200 } }

    local row = UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        padding = 10, gap = 8, borderRadius = 8, borderWidth = 1,
        backgroundColor = bgColor,
        borderColor = borderColor,
        opacity = (not status.locked) and 1.0 or 0.6,
        children = {
            -- 图标
            UI.Panel { width = 32, height = 32,
                backgroundImage = def.icon,
                backgroundFit = "contain",
                opacity = (not status.locked) and 1.0 or 0.4 },
            -- 名称 + 描述 + 体力消耗
            UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                nameLabel,
                descLabel,
            }},
            -- 右侧按钮
            statusWidget,
        },
    }

    local state = status.maxed and "M" or (status.locked and "L" or "U")
    local fp = state .. ":L" .. info.level
             .. ":A" .. tostring(status.active)
             .. ":B" .. tostring(status.adBusy)
             .. ":C" .. tostring(info.canAfford)

    -- costLabel / btnLabel 仅在 unlocked 状态下存在（局部变量自然为 nil 对其他状态）
    rowCache_[def.id] = {
        row = row,
        nameLabel = nameLabel,
        descLabel = descLabel,
        costLabel = costLabel or nil,
        btnLabel = btnLabel or nil,
        statusBtn = statusWidget,
        lastFP = fp,
        lastState = state,
    }

    return row
end

-- ============================================================================
-- 内部：增量更新行
-- ============================================================================

---@diagnostic disable-next-line: redefined-local
UpdateSkillRow = function(status)
    local def = status.def
    local info = status.info
    local cache = rowCache_[def.id]
    if not cache or not cache.row then return end

    local bgColor, borderColor

    if status.maxed then
        bgColor = { 25, 45, 30, 255 }
        borderColor = { 80, 180, 80, 150 }
    elseif not status.locked then
        bgColor = { 50, 40, 65, 255 }
        borderColor = { 200, 170, 255, 200 }
    else
        bgColor = { 20, 18, 30, 200 }
        borderColor = { 40, 35, 55, 100 }
    end

    cache.row:SetStyle({
        backgroundColor = bgColor,
        borderColor = borderColor,
        opacity = (not status.locked) and 1.0 or 0.6,
    })

    -- 更新名称
    cache.nameLabel:SetText(
        def.name .. (not status.locked and (" Lv." .. info.level .. "/" .. info.maxLevel) or "")
    )
    cache.nameLabel:SetFontColor(
        status.maxed and { 100, 200, 100, 255 }
        or (not status.locked and { 230, 220, 255, 255 }
        or { 100, 95, 120, 200 })
    )

    -- 更新描述
    if cache.descLabel then
        local descText = def.desc
        if not status.locked and info.params then
            descText = FormatParams(def, info.params)
        end
        cache.descLabel:SetText(descText)
    end

    -- 更新费用和按钮（仅 unlocked 状态）
    if not status.locked and not status.maxed then
        local canAfford = info.canAfford
        local clickable = not status.active and canAfford

        if cache.costLabel then
            local costText = GameState.FormatNumber(info.upgradeCost or 0)
            cache.costLabel:SetText(costText)
            cache.costLabel:SetFontColor(
                canAfford and { 255, 220, 80, 200 } or { 255, 100, 100, 180 }
            )
        end
        if cache.btnLabel then
            cache.btnLabel:SetFontColor(
                { 255, 255, 255, clickable and 240 or 120 }
            )
        end
        if cache.statusBtn then
            local skillId = def.id
            cache.statusBtn:SetStyle({
                backgroundColor = clickable and { 80, 50, 120, 255 } or { 50, 45, 60, 200 },
                borderColor = clickable and { 180, 130, 255, 200 } or { 70, 60, 90, 120 },
                pointerEvents = clickable and "auto" or "none",
                onPointerDown = clickable and function()
                    if manager_ then
                        manager_.OnUpgradeSkill(skillId)
                    end
                end or nil,
            })
        end
    end

    local state = status.maxed and "M" or (status.locked and "L" or "U")
    cache.lastFP = state .. ":L" .. info.level
                 .. ":A" .. tostring(status.active)
                 .. ":B" .. tostring(status.adBusy)
                 .. ":C" .. tostring(info.canAfford)
    cache.lastState = state
end

-- ============================================================================
-- 内部：格式化参数
-- ============================================================================

---@diagnostic disable-next-line: redefined-local
FormatParams = function(def, params)
    local id = def.id
    if id == "speedClick" then
        local mins = math.floor(params.duration / 60)
        return string.format("持续 %d分钟 · 每秒 %.0f 次签单", mins, params.rate)
    elseif id == "cpsDouble" then
        local mins = math.floor(params.duration / 60)
        return string.format("持续 %d分钟 · CPS ×%.1f", mins, params.multiplier)
    elseif id == "clickBoost" then
        local mins = math.floor(params.duration / 60)
        return string.format("持续 %d分钟 · 签单收益 ×%.1f", mins, params.multiplier)
    elseif id == "randomBuildings" then
        return string.format("随机获得 %d 个已解锁产业各+1", params.count)
    elseif id == "cpsHarvest" then
        return string.format("立即获取 %d 分钟CPS收益", params.minutes)
    end
    return def.desc
end

return SP
