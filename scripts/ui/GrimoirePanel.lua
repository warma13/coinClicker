-- ============================================================================
-- ui/GrimoirePanel.lua
-- 研发实验室面板 —— 研发能量条、研发项目列表、活跃效果
-- 右侧抽屉栏，定位在商店面板左侧（与孵化园/万神殿一致）
-- ============================================================================

local UI = require("urhox-libs/UI")
local FloatingText = require("ui.FloatingText")
local GameState = require("core.GameState")
local GC = require("config.GrimoireConfig")

local GP = {}

-- 内部引用
local uiRoot_       = nil
local overlay_      = nil   -- 抽屉容器
local panel_        = nil
local visible_      = false
local grimoireMgr_  = nil   -- GrimoireManager 引用
local manager_      = nil   -- GameManager 引用

-- UI 缓存
local manaBarFill_      = nil
local manaLabel_        = nil
local cooldownLabel_    = nil
local spellsContainer_  = nil
local buffsContainer_   = nil

-- 刷新快照
local lastFingerprint_ = ""

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
local RebuildManaBar
local RebuildSpells
local RebuildBuffs
local OnCastSpell

-- ============================================================================
-- 初始化
-- ============================================================================

function GP.Init(root, gm)
    uiRoot_ = root
    manager_ = gm
    grimoireMgr_ = gm.GetGrimoireManager()
    BuildPanel()
end

-- ============================================================================
-- 显示 / 隐藏
-- ============================================================================

function GP.Show()
    if not overlay_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    lastFingerprint_ = ""
    uiRoot_:AddChild(overlay_)
    GP.Refresh()
end

function GP.Hide()
    if not overlay_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(overlay_)
end

function GP.Toggle()
    if visible_ then GP.Hide() else GP.Show() end
end

function GP.IsVisible()
    return visible_
end

-- ============================================================================
-- 刷新（增量）
-- ============================================================================

function GP.Refresh()
    if not visible_ or not grimoireMgr_ then return end

    -- 构建指纹
    local mana = grimoireMgr_.GetCurrentMana()
    local maxMana = grimoireMgr_.GetMaxMana()
    local cd = grimoireMgr_.GetGlobalCooldown()
    local buffs = grimoireMgr_.GetActiveBuffs()

    -- 将每个 buff 的剩余时间（秒级精度）纳入指纹
    local buffFP = ""
    for _, buf in ipairs(buffs) do
        buffFP = buffFP .. buf.id .. math.floor(buf.remaining) .. ","
    end

    local fp = "m" .. math.floor(mana * 10)
             .. ":mx" .. maxMana
             .. ":cd" .. math.floor(cd)
             .. ":b" .. buffFP

    if fp == lastFingerprint_ then return end
    lastFingerprint_ = fp

    RebuildManaBar()
    RebuildSpells()
    RebuildBuffs()
end

-- ============================================================================
-- 内部：构建面板骨架
-- ============================================================================

BuildPanel = function()
    -- 能量条填充
    manaBarFill_ = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = { 80, 120, 220, 255 },
        borderRadius = 4,
    }

    -- 能量条标签
    manaLabel_ = UI.Label {
        text = "0 / 0",
        fontSize = 11,
        fontColor = { 255, 255, 255, 240 },
        textAlign = "center",
        position = "absolute",
        width = "100%",
        top = 1,
    }

    -- 冷却提示
    cooldownLabel_ = UI.Label {
        text = "",
        fontSize = 10,
        fontColor = { 200, 180, 255, 200 },
        textAlign = "center",
        width = "100%",
    }

    -- 法术列表容器
    spellsContainer_ = UI.Panel {
        width = "100%",
        gap = 5,
        paddingLeft = 4, paddingRight = 4,
    }

    -- 活跃 buff 容器
    buffsContainer_ = UI.Panel {
        width = "100%",
        gap = 3,
        paddingLeft = 6, paddingRight = 6,
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
                marginBottom = 6,
                paddingLeft = 6, paddingRight = 4,
                children = {
                    UI.Label {
                        text = "研发实验室",
                        fontSize = 17,
                        fontColor = { 180, 140, 220, 255 },
                    },
                    UI.Panel {
                        width = 28, height = 28,
                        justifyContent = "center", alignItems = "center",
                        borderRadius = 14,
                        backgroundColor = { 60, 40, 80, 180 },
                        pointerEvents = "auto",
                        onPointerDown = function()
                            GP.Hide()
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

            -- 研发能量条（图标 + 标签）
            UI.Panel {
                width = "100%",
                flexDirection = "row", alignItems = "center",
                justifyContent = "center",
                gap = 4,
                marginBottom = 2,
                children = {
                    UI.Panel {
                        width = 16, height = 16,
                        backgroundImage = "image/魔力图标.png",
                    },
                    UI.Label {
                        text = "研发能量",
                        fontSize = 11,
                        fontColor = { 160, 150, 200, 180 },
                    },
                },
            },
            UI.Panel {
                width = "90%", height = 18,
                backgroundColor = { 30, 30, 50, 200 },
                borderRadius = 4,
                borderWidth = 1,
                borderColor = { 100, 80, 160, 150 },
                overflow = "hidden",
                marginBottom = 2,
                children = {
                    manaBarFill_,
                    manaLabel_,
                },
            },
            cooldownLabel_,

            -- 可滚动内容
            UI.ScrollView {
                flex = 1,
                width = "100%",
                showScrollbar = false,
                children = {
                    UI.Panel {
                        width = "100%",
                        gap = 8,
                        paddingBottom = 20,
                        paddingTop = 6,
                        alignItems = "center",
                        children = {
                            -- 研发项目
                            UI.Label {
                                text = "研发项目",
                                fontSize = 12,
                                fontColor = { 160, 150, 200, 180 },
                                width = "100%", textAlign = "center",
                            },
                            spellsContainer_,

                            -- 活跃效果
                            UI.Label {
                                text = "活跃效果",
                                fontSize = 12,
                                fontColor = { 160, 150, 200, 180 },
                                width = "100%", textAlign = "center",
                                marginTop = 4,
                            },
                            buffsContainer_,
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
        backgroundColor = { 22, 18, 35, 245 },
        borderColor = { 100, 70, 160, 100 },
        borderWidth = { 0, 1, 0, 1 },
        pointerEvents = "auto",
        zIndex = 100,
        children = {
            panel_,
        },
    }
end

-- ============================================================================
-- 内部：刷新能量条
-- ============================================================================

RebuildManaBar = function()
    if not grimoireMgr_ then return end

    local mana = grimoireMgr_.GetCurrentMana()
    local maxMana = grimoireMgr_.GetMaxMana()
    local pct = grimoireMgr_.GetManaPercent()
    local cd = grimoireMgr_.GetGlobalCooldown()

    -- 更新进度条宽度
    if manaBarFill_ then
        manaBarFill_:SetStyle { width = string.format("%.1f%%", pct * 100) }
        -- 颜色：蓝→紫渐变
        local r = math.floor(80 + 100 * (1 - pct))
        local g = math.floor(120 * pct)
        local b = math.floor(220 - 60 * (1 - pct))
        manaBarFill_:SetStyle { backgroundColor = { r, g, b, 255 } }
    end

    -- 更新数值标签
    if manaLabel_ then
        manaLabel_:SetStyle {
            text = string.format("%.1f / %d", mana, maxMana),
        }
    end

    -- 更新冷却提示
    if cooldownLabel_ then
        if cd > 0 then
            cooldownLabel_:SetStyle {
                text = "冷却中: " .. FormatTime(cd),
                fontColor = { 255, 180, 100, 220 },
            }
        else
            cooldownLabel_:SetStyle {
                text = "",
            }
        end
    end
end

-- ============================================================================
-- 内部：重建法术列表
-- ============================================================================

RebuildSpells = function()
    if not spellsContainer_ or not grimoireMgr_ then return end
    spellsContainer_:RemoveAllChildren()

    local mana = grimoireMgr_.GetCurrentMana()
    local maxMana = grimoireMgr_.GetMaxMana()
    local cd = grimoireMgr_.GetGlobalCooldown()

    for _, spell in ipairs(GC.spells) do
        local canCast = grimoireMgr_.CanCast(spell.id)
        local failRate = GC.CalcFailRate(spell, mana, maxMana)
        local enoughMana = mana >= spell.manaCost

        -- 失败率颜色
        local failColor
        if failRate < 0.2 then
            failColor = { 100, 220, 100, 255 }  -- 绿
        elseif failRate < 0.35 then
            failColor = { 220, 200, 80, 255 }   -- 黄
        else
            failColor = { 255, 100, 100, 255 }  -- 红
        end

        local spellId = spell.id  -- 闭包捕获

        local card = UI.Panel {
            width = "100%",
            backgroundColor = canCast and { 45, 35, 65, 255 } or { 30, 25, 45, 200 },
            borderColor = canCast and { 140, 100, 200, 150 } or { 60, 50, 80, 100 },
            borderWidth = 1,
            borderRadius = 6,
            padding = 8,
            gap = 4,
            children = {
                -- 第一行：图标 + 名称 + 消耗 + 施法按钮
                UI.Panel {
                    width = "100%",
                    flexDirection = "row", alignItems = "center",
                    justifyContent = "space-between",
                    children = {
                        UI.Label {
                            text = spell.name,
                            fontSize = 13,
                            fontColor = canCast and { 220, 200, 255, 255 } or { 140, 130, 160, 200 },
                            flex = 1, flexShrink = 1,
                        },
                        -- 施法按钮（含能量消耗）
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 5,
                            paddingLeft = 8, paddingRight = 10,
                            paddingTop = 4, paddingBottom = 4,
                            borderRadius = 4,
                            backgroundColor = canCast and { 100, 60, 180, 255 } or { 50, 40, 70, 200 },
                            borderWidth = 1,
                            borderColor = canCast and { 160, 120, 240, 200 } or { 60, 50, 80, 100 },
                            pointerEvents = "auto",
                            onPointerDown = function(self, event)
                                if event and event.stopPropagation then
                                    event:stopPropagation()
                                end
                                OnCastSpell(spellId)
                            end,
                            children = {
                                UI.Panel {
                                    width = 12, height = 12,
                                    backgroundImage = "image/魔力图标.png",
                                },
                                UI.Label {
                                    text = tostring(spell.manaCost),
                                    fontSize = 11,
                                    fontColor = enoughMana and { 120, 180, 255, 255 } or { 255, 100, 100, 200 },
                                },
                                UI.Label {
                                    text = cd > 0 and "冷却" or (canCast and "研发" or "不足"),
                                    fontSize = 11,
                                    fontColor = canCast and { 255, 255, 255, 255 } or { 150, 140, 170, 180 },
                                    textAlign = "center",
                                },
                            },
                        },
                    },
                },

                -- 第二行：效果描述
                UI.Panel {
                    width = "100%", gap = 1,
                    children = {
                        UI.Label {
                            text = "成功: " .. spell.successDesc,
                            fontSize = 10,
                            fontColor = { 100, 200, 120, 200 },
                        },
                        UI.Label {
                            text = "失败: " .. spell.failDesc,
                            fontSize = 10,
                            fontColor = { 200, 100, 100, 200 },
                        },
                    },
                },

                -- 第三行：失败率
                UI.Panel {
                    width = "100%",
                    flexDirection = "row", alignItems = "center",
                    justifyContent = "flex-end",
                    children = {
                        UI.Label {
                            text = "失败率: " .. GC.FormatFailRate(failRate),
                            fontSize = 10,
                            fontColor = failColor,
                        },
                    },
                },
            },
        }

        spellsContainer_:AddChild(card)
    end
end

-- ============================================================================
-- 内部：重建活跃 buff 列表
-- ============================================================================

-- Buff 类型友好名称映射
local BUFF_TYPE_LABELS = {
    cps            = "CPS",
    building_price = "建筑价格",
    upgrade_price  = "升级价格",
}

-- Buff 类型图标映射
local BUFF_ICONS = {
    cps            = "",
    building_price = "",
    upgrade_price  = "",
}

RebuildBuffs = function()
    if not buffsContainer_ or not grimoireMgr_ then return end
    buffsContainer_:RemoveAllChildren()

    local buffs = grimoireMgr_.GetActiveBuffs()

    if #buffs == 0 then
        buffsContainer_:AddChild(UI.Label {
            text = "暂无活跃效果",
            fontSize = 10,
            fontColor = { 120, 110, 150, 150 },
            textAlign = "center",
            width = "100%",
        })
        return
    end

    for _, buf in ipairs(buffs) do
        local isPositive = buf.value < 0 and buf.type ~= "cps"  -- 价格降低是正面
        if buf.type == "cps" then isPositive = buf.value > 0 end -- CPS 增加是正面

        local icon = BUFF_ICONS[buf.type] or ""
        local label = BUFF_TYPE_LABELS[buf.type] or buf.type:upper()

        -- 价格类 buff: 负值=降价=绿色, 正值=涨价=红色
        -- CPS 类 buff: 正值=增产=绿色, 负值=减产=红色
        local valueStr
        if buf.type == "cps" then
            valueStr = string.format("%+.0f%%", buf.value * 100)
        else
            -- 价格类显示反向：value=-0.02 显示"-2%"
            valueStr = string.format("%+.0f%%", buf.value * 100)
        end

        buffsContainer_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row", alignItems = "center",
            justifyContent = "space-between",
            gap = 4,
            padding = 4,
            backgroundColor = isPositive and { 20, 40, 30, 200 } or { 50, 20, 20, 200 },
            borderRadius = 4,
            children = {
                UI.Label {
                    text = label .. " " .. valueStr,
                    fontSize = 10,
                    fontColor = isPositive and { 100, 220, 100, 255 } or { 255, 100, 100, 255 },
                    flex = 1, flexShrink = 1,
                },
                UI.Label {
                    text = FormatTime(buf.remaining),
                    fontSize = 10,
                    fontColor = { 180, 180, 200, 180 },
                },
            },
        })
    end
end

-- ============================================================================
-- 内部：施放法术
-- ============================================================================

OnCastSpell = function(spellId)
    if not grimoireMgr_ or not manager_ then return end

    local spell = GC.FindSpell(spellId)
    local result = manager_.OnCastSpell(spellId)
    if result then
        -- 浮动文本提示施法结果
        local spellName = spell and spell.name or spellId
        local dpr = graphics:GetDPR()
        local cx = graphics:GetWidth() / dpr * 0.5
        local cy = graphics:GetHeight() / dpr * 0.15
        if result.success then
            FloatingText.Show(spellName .. ": " .. (result.desc or "成功"), cx, cy, { 80, 220, 120, 255 })
        else
            FloatingText.Show(spellName .. ": " .. (result.desc or "失败"), cx, cy, { 220, 80, 80, 255 })
        end

        -- 立即刷新面板
        lastFingerprint_ = ""
        GP.Refresh()
    end
end

return GP
