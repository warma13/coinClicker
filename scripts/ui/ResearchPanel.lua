-- ============================================================================
-- ui/ResearchPanel.lua
-- 劳资关系面板（全屏覆盖式弹窗）
-- 使用 AddChild/RemoveChild 控制显隐
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local GD = require("config.GrandmapocalypseDefs")

local RP = {}

-- ======== 引用 ========
local uiRoot_ = nil
local panel_ = nil
local listContainer_ = nil
local pledgeBtn_ = nil
local pledgeLabel_ = nil
local visible_ = false

-- 外部注入
local grandmapoManager_ = nil
local onBuyResearch_ = nil    -- function(index)
local onBuyPledge_ = nil      -- function()

-- ======== 增量刷新缓存 ========
local rowCache_ = {}           -- rowCache_[i] = { row, nameLabel, statusLabel, def, lastFP }
local lastPledgeFP_ = ""
local lastListFP_ = ""
local initialized_ = false
local countdownRowIdx_ = nil   -- 当前正在倒计时的行索引
local lastCountdownText_ = ""  -- 上次倒计时文本（避免无变化时 SetText）

-- ============================================================================
-- 内部：构建面板
-- ============================================================================

local function BuildPanel()
    listContainer_ = UI.Panel {
        width = "100%",
        gap = 6,
        paddingBottom = 20,
    }

    pledgeLabel_ = UI.Label {
        text = "",
        fontSize = 12,
        fontColor = { 180, 180, 200, 200 },
    }

    pledgeBtn_ = UI.Panel {
        width = "100%", padding = 10, borderRadius = 8,
        backgroundColor = { 40, 60, 80, 255 },
        borderWidth = 1,
        borderColor = { 100, 150, 200, 150 },
        pointerEvents = "auto",
        flexDirection = "row", alignItems = "center", gap = 8,
        onPointerDown = function()
            if onBuyPledge_ then
                onBuyPledge_()
                RP.Refresh()
            end
        end,
        children = {
            UI.Label { text = "🤝", fontSize = 20, width = 28, textAlign = "center" },
            UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                UI.Label { text = "临时协议", fontSize = 13,
                    fontColor = { 100, 180, 255, 255 } },
                pledgeLabel_,
            }},
        },
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
                marginBottom = 8,
                children = {
                    UI.Panel { width = 28, height = 28,
                        backgroundImage = "image/劳资关系部_20260414104120.png" },
                    UI.Label {
                        text = "劳资关系部",
                        fontSize = 18,
                        fontColor = { 200, 150, 255, 255 },
                    },
                },
            },

            -- 可滚动内容区
            UI.ScrollView {
                flex = 1,
                width = "100%",
                children = {
                    UI.Panel {
                        width = "100%", gap = 8, paddingBottom = 20,
                        children = {
                            -- Elder Pledge 按钮
                            pledgeBtn_,
                            -- 分隔
                            UI.Label {
                                text = "劳资研究",
                                fontSize = 12,
                                fontColor = { 180, 160, 120, 200 },
                                marginTop = 8, marginBottom = 4,
                            },
                            -- 研究列表
                            listContainer_,
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 构建研究行（带缓存）
-- ============================================================================

local function FormatCountdown(seconds)
    local s = math.ceil(seconds)
    local m = math.floor(s / 60)
    s = s % 60
    return string.format("%d:%02d", m, s)
end

local function BuildResearchRow(i, s)
    local r = s.def
    local bgColor, borderColor, statusText, clickable

    if s.bought then
        bgColor = { 30, 55, 35, 255 }
        borderColor = { 80, 180, 80, 150 }
        clickable = false
    elseif s.unlocked then
        local canAfford = GameState.coins >= r.cost
        if canAfford then
            bgColor = { 60, 50, 30, 255 }
            borderColor = { 255, 200, 50, 200 }
        else
            bgColor = { 40, 35, 30, 255 }
            borderColor = { 120, 100, 50, 150 }
        end
        clickable = canAfford
    else
        bgColor = { 25, 25, 35, 255 }
        borderColor = { 50, 50, 65, 100 }
        clickable = false
    end

    local nameLabel = UI.Label { text = r.name, fontSize = 13,
        fontColor = s.bought and { 100, 200, 100, 255 }
            or (s.unlocked and { 230, 230, 240, 255 }
            or { 100, 100, 120, 200 }) }

    -- 状态区域：已购买/按钮样式价格/未解锁
    local statusChild
    if s.bought then
        statusChild = UI.Label { text = "✓ 已购买", fontSize = 11,
            fontColor = { 100, 200, 100, 200 } }
    elseif s.unlocked then
        local canAfford = GameState.coins >= r.cost
        statusChild = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 3,
            paddingLeft = 10, paddingRight = 10, paddingTop = 5, paddingBottom = 5,
            borderRadius = 5, borderWidth = 1,
            backgroundColor = canAfford and { 60, 140, 60, 255 } or { 40, 35, 50, 200 },
            borderColor = canAfford and { 100, 200, 100, 200 } or { 60, 50, 70, 120 },
            children = {
                UI.Panel { width = 14, height = 14,
                    backgroundImage = "image/金币.png", backgroundFit = "contain" },
                UI.Label { text = GameState.FormatNumber(r.cost), fontSize = 11,
                    fontColor = canAfford and { 255, 255, 255, 255 } or { 150, 150, 170, 180 } },
            },
        }
    else
        local timer = grandmapoManager_ and grandmapoManager_.GetResearchTimer() or 0
        local txt = (s.isNext and timer > 0) and ("解锁中 " .. FormatCountdown(timer)) or "未解锁"
        statusChild = UI.Label { id = "researchStatus_" .. i, text = txt, fontSize = 11,
            fontColor = { 150, 150, 170, 180 } }
        -- 记录倒计时行
        if s.isNext and timer > 0 then
            countdownRowIdx_ = i
        end
    end

    local idx = i  -- 闭包捕获
    local row = UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        padding = 8, gap = 8, borderRadius = 6, borderWidth = 1,
        backgroundColor = bgColor,
        borderColor = borderColor,
        opacity = (s.bought or s.unlocked) and 1.0 or 0.4,
        pointerEvents = clickable and "auto" or "none",
        onPointerDown = clickable and function()
            if onBuyResearch_ then
                onBuyResearch_(idx)
                RP.Refresh()
            end
        end or nil,
        children = {
            UI.Panel { width = 32, height = 32,
                backgroundImage = r.iconImage or nil,
            },
            UI.Panel { flex = 1, flexShrink = 1, gap = 2, children = {
                nameLabel,
                UI.Label { text = r.desc, fontSize = 10,
                    fontColor = { 140, 140, 160, 200 } },
            }},
            statusChild,
        },
    }

    -- 指纹: bought/unlocked/canAfford
    local canAfford = s.unlocked and (GameState.coins >= r.cost)
    local fp = (s.bought and "B" or "") .. (s.unlocked and "U" or "") .. (canAfford and "A" or "")

    rowCache_[i] = {
        row = row,
        nameLabel = nameLabel,
        statusLabel = statusChild,
        def = r,
        lastFP = fp,
    }

    return row
end

-- ============================================================================
-- 增量更新单行
-- ============================================================================

-- 增量更新不再逐行替换，指纹变化时触发全量重建
-- （研究条目少，全量重建性能可接受）

-- ============================================================================
-- 公共接口
-- ============================================================================

function RP.Init(root, gm, buyResearchCb, buyPledgeCb)
    uiRoot_ = root
    grandmapoManager_ = gm
    onBuyResearch_ = buyResearchCb
    onBuyPledge_ = buyPledgeCb
    BuildPanel()
end

function RP.Show()
    if not panel_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    uiRoot_:AddChild(panel_)
    -- 重置缓存
    initialized_ = false
    rowCache_ = {}
    lastPledgeFP_ = ""
    lastListFP_ = ""
    RP.Refresh()
end

function RP.Hide()
    if not panel_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(panel_)
end

function RP.Toggle()
    if visible_ then RP.Hide() else RP.Show() end
end

function RP.IsVisible() return visible_ end

-- ============================================================================
-- 刷新（增量）
-- ============================================================================

function RP.Refresh()
    if not visible_ or not grandmapoManager_ then return end

    local F = GameState.FormatNumber
    local status = grandmapoManager_.GetResearchStatus()

    -- ===== 研究列表 =====
    if listContainer_ then
        -- 计算结构指纹（不包含倒计时秒数，避免每秒全量重建）
        local fpParts = {}
        for i, s in ipairs(status) do
            local canAfford = s.unlocked and (GameState.coins >= s.def.cost)
            local hasTimer = ""
            if s.isNext and not s.bought and not s.unlocked then
                local t = grandmapoManager_ and grandmapoManager_.GetResearchTimer() or 0
                if t > 0 then hasTimer = "T" end  -- 只记录"有倒计时"，不记录秒数
            end
            fpParts[i] = (s.bought and "B" or "") .. (s.unlocked and "U" or "") .. (canAfford and "A" or "") .. hasTimer
        end
        local listFP = table.concat(fpParts, "|")

        if not initialized_ or listFP ~= lastListFP_ then
            initialized_ = true
            lastListFP_ = listFP
            countdownRowIdx_ = nil
            lastCountdownText_ = ""
            listContainer_:RemoveAllChildren()
            rowCache_ = {}
            for i, s in ipairs(status) do
                listContainer_:AddChild(BuildResearchRow(i, s))
            end
        end

        -- 单独更新倒计时文本（不触发全量重建）
        if countdownRowIdx_ and rowCache_[countdownRowIdx_] then
            local rc = rowCache_[countdownRowIdx_]
            local t = grandmapoManager_ and grandmapoManager_.GetResearchTimer() or 0
            if t > 0 then
                local txt = "解锁中 " .. FormatCountdown(t)
                if txt ~= lastCountdownText_ then
                    lastCountdownText_ = txt
                    if rc.statusLabel then
                        rc.statusLabel:SetText(txt)
                    end
                end
            else
                -- 倒计时结束，标记需要全量重建
                countdownRowIdx_ = nil
                lastListFP_ = ""  -- 强制下次重建
            end
        end
    end

    -- ===== Elder Pledge =====
    local phase = grandmapoManager_.GetRawPhase()
    local pledgeFP
    if phase == GD.PHASE_NONE then
        pledgeFP = "hidden"
    else
        local active = grandmapoManager_.IsPledgeActive()
        if active then
            local remaining = math.floor(grandmapoManager_.GetPledgeTimer())
            pledgeFP = "active:" .. remaining
        else
            local cost = grandmapoManager_.GetPledgeCost()
            local canAfford = GameState.coins >= cost
            pledgeFP = "inactive:" .. (canAfford and "Y" or "N")
        end
    end

    if pledgeFP ~= lastPledgeFP_ then
        lastPledgeFP_ = pledgeFP
        if phase == GD.PHASE_NONE then
            pledgeBtn_:SetStyle({ height = 0, padding = 0, borderWidth = 0, overflow = "hidden" })
        else
            pledgeBtn_:SetStyle({ height = "auto", padding = 10, borderWidth = 1, overflow = "visible" })
            local active = grandmapoManager_.IsPledgeActive()
            if active then
                local remaining = grandmapoManager_.GetPledgeTimer()
                pledgeLabel_:SetText("协议生效中... 剩余 " .. math.floor(remaining) .. " 秒")
                pledgeBtn_:SetStyle({ backgroundColor = { 30, 50, 40, 255 } })
            else
                local cost = grandmapoManager_.GetPledgeCost()
                pledgeLabel_:SetText("临时平息工会危机 | " .. F(cost) .. " 金币")
                local canAfford = GameState.coins >= cost
                pledgeBtn_:SetStyle({
                    backgroundColor = canAfford and { 40, 60, 80, 255 } or { 30, 30, 40, 255 },
                    opacity = canAfford and 1.0 or 0.5,
                })
            end
        end
    end
end

return RP
