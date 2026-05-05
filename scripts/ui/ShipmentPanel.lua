-- ============================================================================
-- ui/ShipmentPanel.lua
-- 货运航线 —— 国际物流(#9)小游戏面板 UI
-- 右侧抽屉面板，宽度 30%，position=absolute
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local SC = require("config.ShipmentConfig")

local ShipmentPanel = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

local root_ = nil
local gm_ = nil
local panel_ = nil
local visible_ = false
local lastStructSnap_ = ""

--- 动态 Label 引用（局部刷新用）
local refs_ = {}

-- ============================================================================
-- 结构快照（仅货物列表结构变化时重建 UI）
-- ============================================================================

local function MakeStructSnapshot()
    local mgr = gm_ and gm_.GetShipmentManager and gm_.GetShipmentManager()
    if not mgr then return "" end

    local parts = {}
    local pending = mgr.GetPendingCargos()
    local transit = mgr.GetInTransit()

    parts[#parts + 1] = "P" .. #pending
    for i, c in ipairs(pending) do
        parts[#parts + 1] = c.defId .. c.routeId
    end
    parts[#parts + 1] = "T" .. #transit
    for i, c in ipairs(transit) do
        parts[#parts + 1] = c.defId .. (c.delayed and "D" or "") .. (c.insured and "I" or "")
    end
    parts[#parts + 1] = "S" .. (mgr.GetSafeStreak())
    -- CPS 粗粒度桶：CPS 变化超 ~30% 才触发重建（更新金额/按钮）
    local cps = math.max(GameState.coinsPerSecond, 1)
    parts[#parts + 1] = "C" .. math.floor(math.log(cps) * 3)
    return table.concat(parts, ",")
end

-- ============================================================================
-- UI 构建
-- ============================================================================

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 3600 then
        return string.format("%dh%02dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    elseif seconds >= 60 then
        return string.format("%dm%02ds", math.floor(seconds / 60), seconds % 60)
    else
        return seconds .. "s"
    end
end

--- 创建待发货物卡片
---@return table card, table dynLabels 动态 Label 引用 {reward, cost, net, shipBtn, shipBtnLabel, insureBtn, insureBtnLabel}
local function CreatePendingCard(cargo, index, slotsFull)
    local F = GameState.FormatNumber
    local cps = math.max(GameState.coinsPerSecond, 1)
    local routeDef = SC.routeMap[cargo.routeId]
    local cargoDef = SC.cargoMap[cargo.defId]
    local estimateReward = math.floor(cps * cargo.cpsSeconds * cargo.rewardMul)
    local shippingCost = (cargoDef and cargoDef.investCpsMul) and math.floor(cps * cargoDef.investCpsMul) or 0
    local insuranceCost = math.floor(cps * SC.INSURANCE_CPS_MUL)
    local canAfford = (not slotsFull) and GameState.coins >= shippingCost
    local canInsure = (not slotsFull) and GameState.coins >= (shippingCost + insuranceCost)

    -- 危险品标记
    local nameLabel = cargo.name
    if cargo.hazard then
        nameLabel = cargo.name .. " [危]"
    end

    -- 先构建 children 列表，避免 nil hole 导致 ipairs 截断
    local cardChildren = {
        -- 标题行：货物 + 航线
        UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", children = {
            UI.Label { text = nameLabel, fontSize = 13, fontColor = { 220, 230, 240, 255 }, flex = 1, flexShrink = 1 },
            UI.Label { text = cargo.routeName, fontSize = 11, fontColor = { 150, 180, 220, 200 } },
        } },
        -- 信息行：时间 + 预估奖励
        UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", children = {
            UI.Label { text = "航时 " .. FormatTime(cargo.travelTime), fontSize = 11, fontColor = { 160, 170, 180, 200 } },
            UI.Panel { flex = 1 },
            UI.Label { text = "≈ " .. F(estimateReward), fontSize = 11, fontColor = { 100, 200, 100, 220 } },
        } },
        -- 运输成本
        shippingCost > 0 and UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", children = {
            UI.Label { text = "运输费: " .. F(shippingCost), fontSize = 10, fontColor = canAfford and { 200, 180, 100, 200 } or { 255, 100, 100, 220 } },
            UI.Panel { flex = 1 },
            UI.Label { text = "净利 ≈ " .. F(math.max(0, estimateReward - shippingCost)), fontSize = 10, fontColor = { 130, 200, 130, 200 } },
        } } or nil,
        -- 延误风险 + 后果说明
        UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", children = {
            UI.Label {
                text = "延误风险: " .. math.floor((routeDef and routeDef.delayChance or 0) * 100 + (cargo.hazard and SC.HAZARD_DELAY_EXTRA * 100 or 0)) .. "%",
                fontSize = 10,
                fontColor = { 200, 160, 100, 180 },
            },
            UI.Panel { flex = 1 },
            UI.Label {
                text = "延误: 时间+30%, 奖励-50%",
                fontSize = 9,
                fontColor = { 160, 140, 120, 150 },
            },
        } },
    }

    -- buff 提示（条件添加，不产生 nil hole）
    if cargo.buff then
        cardChildren[#cardChildren + 1] = UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", children = {
            UI.Label {
                text = "送达奖励: " .. cargo.buff.name .. " (CPS×" .. cargo.buff.mul .. ", " .. cargo.buff.duration .. "s)",
                fontSize = 10,
                fontColor = { 120, 180, 220, 200 },
            },
        } }
    end

    -- 操作按钮行（始终添加）
    cardChildren[#cardChildren + 1] = UI.Panel { flexDirection = "row", gap = 6, width = "100%", marginTop = 4, children = {
        -- 发货按钮
        UI.Panel {
            flex = 1, height = 28,
            justifyContent = "center", alignItems = "center",
            backgroundColor = canAfford and { 40, 80, 120, 255 } or { 40, 40, 50, 255 },
            borderRadius = 6, borderWidth = 1,
            borderColor = canAfford and { 80, 150, 220, 200 } or { 60, 60, 80, 100 },
            pointerEvents = "auto",
            onTap = function()
                local mgr = gm_ and gm_.GetShipmentManager and gm_.GetShipmentManager()
                if mgr then mgr.ShipCargo(index, false) end
                ShipmentPanel.Refresh()
            end,
            children = {
                UI.Label {
                    text = shippingCost > 0 and ("发货 " .. F(shippingCost)) or "发货",
                    fontSize = 11,
                    fontColor = canAfford and { 220, 240, 255, 255 } or { 120, 120, 140, 180 },
                },
            },
        },
        -- 投保发货按钮
        UI.Panel {
            flex = 1, height = 28,
            justifyContent = "center", alignItems = "center",
            backgroundColor = canInsure and { 50, 70, 50, 255 } or { 40, 40, 50, 255 },
            borderRadius = 6, borderWidth = 1,
            borderColor = canInsure and { 100, 180, 100, 180 } or { 60, 60, 80, 100 },
            pointerEvents = "auto",
            onTap = function()
                local mgr = gm_ and gm_.GetShipmentManager and gm_.GetShipmentManager()
                if mgr then mgr.ShipCargo(index, true) end
                ShipmentPanel.Refresh()
            end,
            children = {
                UI.Label {
                    text = "投保 " .. F(shippingCost + insuranceCost),
                    fontSize = 10,
                    fontColor = canInsure and { 150, 220, 150, 255 } or { 120, 120, 140, 180 },
                },
            },
        },
    } }

    return UI.Panel {
        width = "100%", padding = 8, borderRadius = 8, borderWidth = 1,
        backgroundColor = { 35, 45, 55, 255 },
        borderColor = cargo.hazard and { 200, 100, 50, 150 } or { 60, 100, 150, 150 },
        gap = 4,
        children = cardChildren,
    }
end

--- 创建运输中卡片（将动态 Label 存入 refs_.transit[index]）
local function CreateTransitCard(cargo, index)
    local F = GameState.FormatNumber
    local progress = cargo.travelTime > 0 and (cargo.elapsed / cargo.travelTime) or 0
    progress = math.min(1.0, progress)
    local remaining = math.max(0, cargo.travelTime - cargo.elapsed)
    local cps = math.max(GameState.coinsPerSecond, 1)
    local cargoDef = SC.cargoMap[cargo.defId]
    local routeDef = SC.routeMap[cargo.routeId]
    local estimateReward = cargoDef and routeDef and math.floor(cps * cargoDef.cpsSeconds * routeDef.rewardMul) or 0
    if cargo.delayed and not cargo.insured then
        estimateReward = math.floor(estimateReward * 0.5)
    end

    local expressCost = math.floor(cps * SC.EXPRESS_CPS_MUL)
    local canExpress = GameState.coins >= expressCost and progress < 0.9

    -- 状态颜色
    local statusColor = { 80, 180, 255, 255 }
    local borderCol = { 60, 120, 180, 150 }
    if cargo.delayed then
        statusColor = { 255, 150, 50, 255 }
        borderCol = { 200, 120, 40, 150 }
    end
    if cargo.insured then
        borderCol = { 80, 180, 100, 150 }
    end

    local barW = math.floor(progress * 100)

    -- 创建需要动态更新的 Label，保存引用
    local timeLabel = UI.Label { text = FormatTime(remaining), fontSize = 11, fontColor = { 180, 190, 200, 200 } }
    local progressBarInner = UI.Panel {
        width = barW .. "%", height = "100%", borderRadius = 3,
        backgroundColor = cargo.delayed and { 255, 150, 50, 255 } or { 80, 180, 255, 255 },
    }

    refs_.transit = refs_.transit or {}
    refs_.transit[index] = {
        timeLabel = timeLabel,
        progressBar = progressBarInner,
        cargo = cargo,
    }

    return UI.Panel {
        width = "100%", padding = 8, borderRadius = 8, borderWidth = 1,
        backgroundColor = { 30, 38, 50, 255 },
        borderColor = borderCol,
        gap = 4,
        children = {
            -- 标题行
            UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", children = {
                UI.Label { text = cargo.name, fontSize = 13, fontColor = { 220, 230, 240, 255 }, flex = 1, flexShrink = 1 },
                UI.Label {
                    text = "→ " .. cargo.routeName,
                    fontSize = 11,
                    fontColor = { 150, 180, 220, 200 },
                },
            } },
            -- 状态行
            UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", children = {
                UI.Label {
                    text = cargo.delayed and "延误" or (cargo.insured and "已投保" or "运输中"),
                    fontSize = 11,
                    fontColor = statusColor,
                },
                UI.Panel { flex = 1 },
                timeLabel,
            } },
            -- 进度条
            UI.Panel {
                width = "100%", height = 6, borderRadius = 3,
                backgroundColor = { 25, 30, 40, 255 },
                children = { progressBarInner },
            },
            -- 延误/保险详情
            (cargo.delayed or cargo.insured) and UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, width = "100%", children = {
                cargo.delayed and UI.Label {
                    text = cargo.insured and "延误 (已投保, 奖励不变)" or "延误 (奖励-50%)",
                    fontSize = 10,
                    fontColor = cargo.insured and { 100, 180, 120, 200 } or { 255, 130, 60, 200 },
                } or nil,
                (cargo.insured and not cargo.delayed) and UI.Label {
                    text = "已投保",
                    fontSize = 10,
                    fontColor = { 100, 180, 120, 200 },
                } or nil,
            } } or nil,
            -- 预估奖励 + 加急按钮
            UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", marginTop = 2, children = {
                UI.Label { text = "≈ " .. F(estimateReward), fontSize = 11, fontColor = { 100, 200, 100, 200 } },
                UI.Panel { flex = 1 },
                -- 加急按钮
                canExpress and UI.Panel {
                    paddingLeft = 8, paddingRight = 8, height = 24,
                    justifyContent = "center", alignItems = "center",
                    backgroundColor = { 120, 80, 30, 255 },
                    borderRadius = 4, borderWidth = 1,
                    borderColor = { 200, 160, 50, 200 },
                    pointerEvents = "auto",
                    onTap = function()
                        local mgr = gm_ and gm_.GetShipmentManager and gm_.GetShipmentManager()
                        if mgr then mgr.ExpressShipment(index) end
                        ShipmentPanel.Refresh()
                    end,
                    children = {
                        UI.Label { text = "加急 " .. F(expressCost), fontSize = 10, fontColor = { 255, 220, 100, 255 } },
                    },
                } or nil,
            } },
        },
    }
end

--- 构建面板内容
local function BuildContent()
    if not panel_ then return end
    panel_:RemoveAllChildren()

    -- 清空动态引用
    refs_ = {}

    local mgr = gm_ and gm_.GetShipmentManager and gm_.GetShipmentManager()
    if not mgr then return end

    local pending = mgr.GetPendingCargos()
    local transit = mgr.GetInTransit()
    local streak = mgr.GetSafeStreak()
    local refreshTime = mgr.GetRefreshTimer()
    local F = GameState.FormatNumber

    -- 标题栏
    local header = UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        padding = 10, paddingBottom = 6,
        backgroundColor = { 25, 35, 50, 255 },
        borderColor = { 60, 100, 160, 80 },
        borderWidth = { 0, 0, 1, 0 },
        children = {
            UI.Label { text = "货运航线", fontSize = 16, fontColor = { 100, 180, 255, 255 }, flex = 1 },
            -- 关闭按钮
            UI.Panel {
                width = 28, height = 28,
                justifyContent = "center", alignItems = "center",
                backgroundColor = { 60, 50, 50, 200 },
                borderRadius = 14,
                pointerEvents = "auto",
                onTap = function()
                    ShipmentPanel.Hide()
                end,
                children = {
                    UI.Label { text = "✕", fontSize = 14, fontColor = { 200, 180, 180, 255 } },
                },
            },
        },
    }
    panel_:AddChild(header)

    -- 连击信息 + 下一奖励目标
    local streakChildren = {}
    streakChildren[#streakChildren + 1] = UI.Label {
        text = "安全送达连击: " .. streak,
        fontSize = 11,
        fontColor = { 100, 200, 130, 230 },
        flex = 1,
    }
    -- 找到下一个连击奖励目标
    local nextReward = nil
    for _, sr in ipairs(SC.STREAK_REWARDS) do
        if streak < sr.threshold then
            nextReward = sr
            break
        end
    end
    if nextReward then
        streakChildren[#streakChildren + 1] = UI.Label {
            text = "再" .. (nextReward.threshold - streak) .. "次 → " .. nextReward.buff.name,
            fontSize = 10,
            fontColor = { 160, 200, 160, 180 },
        }
    end

    panel_:AddChild(UI.Panel {
        width = "100%", paddingLeft = 10, paddingRight = 10, paddingTop = 4, paddingBottom = 4,
        backgroundColor = { 30, 45, 35, 255 },
        flexDirection = "row", alignItems = "center",
        children = streakChildren,
    })

    -- 滚动内容
    local scrollContent = UI.Panel {
        width = "100%", padding = 8, gap = 8,
    }

    -- === 待发货物区 ===
    local refreshLabel = UI.Label {
        text = "刷新 " .. FormatTime(refreshTime),
        fontSize = 10,
        fontColor = { 140, 150, 170, 180 },
    }
    refs_.refreshLabel = refreshLabel

    scrollContent:AddChild(UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", gap = 4,
        children = {
            UI.Label { text = "待发货物", fontSize = 13, fontColor = { 180, 200, 230, 255 }, flex = 1 },
            refreshLabel,
        },
    })

    -- 计算运输槽位是否已满
    local shipCount = 0
    if GameState.buildings then
        for _, b in ipairs(GameState.buildings) do
            if b.id == SC.BUILDING_ID then shipCount = b.count; break end
        end
    end
    local maxSlots = SC.GetRouteSlots(shipCount)
    local slotsFull = #transit >= maxSlots

    if slotsFull then
        scrollContent:AddChild(UI.Panel {
            width = "100%", padding = 6, borderRadius = 4,
            backgroundColor = { 80, 50, 30, 200 },
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = "运输槽位已满 (" .. #transit .. "/" .. maxSlots .. ")", fontSize = 11, fontColor = { 255, 180, 80, 230 } },
            },
        })
    end

    if #pending == 0 then
        scrollContent:AddChild(UI.Panel {
            width = "100%", padding = 16,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = "暂无待发货物", fontSize = 12, fontColor = { 120, 130, 150, 180 } },
            },
        })
    else
        for i, cargo in ipairs(pending) do
            scrollContent:AddChild(CreatePendingCard(cargo, i, slotsFull))
        end
    end

    -- === 运输中区 ===
    scrollContent:AddChild(UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", gap = 4, marginTop = 6,
        children = {
            UI.Label { text = "运输中", fontSize = 13, fontColor = { 100, 180, 255, 255 }, flex = 1 },
            UI.Label {
                text = #transit .. "/" .. maxSlots,
                fontSize = 11,
                fontColor = { 150, 170, 200, 200 },
            },
        },
    })

    if #transit == 0 then
        scrollContent:AddChild(UI.Panel {
            width = "100%", padding = 16,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = "暂无运输中货物", fontSize = 12, fontColor = { 120, 130, 150, 180 } },
            },
        })
    else
        for i, cargo in ipairs(transit) do
            scrollContent:AddChild(CreateTransitCard(cargo, i))
        end
    end

    -- === 规则说明 ===
    scrollContent:AddChild(UI.Panel {
        width = "100%", marginTop = 10, padding = 8, borderRadius = 6,
        backgroundColor = { 28, 34, 48, 200 },
        borderWidth = 1, borderColor = { 50, 70, 100, 100 },
        gap = 4,
        children = {
            UI.Label { text = "规则说明", fontSize = 12, fontColor = { 140, 170, 220, 220 } },
            UI.Label { text = "· 选择货物发货, 等待运输完成获得金币", fontSize = 10, fontColor = { 130, 140, 160, 180 } },
            UI.Label { text = "· 发货需支付运输费, 货物越贵费用越高", fontSize = 10, fontColor = { 130, 140, 160, 180 } },
            UI.Label { text = "· 航线越远奖励越高, 延误风险也越大", fontSize = 10, fontColor = { 130, 140, 160, 180 } },
            UI.Label { text = "· 延误: 运输时间+30%, 奖励减半", fontSize = 10, fontColor = { 130, 140, 160, 180 } },
            UI.Label { text = "· 投保: 花费CPS×10, 延误时奖励不减", fontSize = 10, fontColor = { 130, 140, 160, 180 } },
            UI.Label { text = "· 加急: 花费CPS×25, 剩余时间减半", fontSize = 10, fontColor = { 130, 140, 160, 180 } },
            UI.Label { text = "· 连续安全送达3/5次可获CPS加成", fontSize = 10, fontColor = { 130, 140, 160, 180 } },
            UI.Label { text = "· 国际物流建筑越多, 可同时运输越多", fontSize = 10, fontColor = { 130, 140, 160, 180 } },
        },
    })

    panel_:AddChild(UI.ScrollView {
        flex = 1, width = "100%",
        showScrollbar = false,
        children = { scrollContent },
    })

    lastStructSnap_ = MakeStructSnapshot()
end

-- ============================================================================
-- 局部刷新（仅更新时间/进度文本，不重建 UI 树）
-- ============================================================================

local function UpdateDynamic()
    local mgr = gm_ and gm_.GetShipmentManager and gm_.GetShipmentManager()
    if not mgr then return end

    -- 刷新计时器
    if refs_.refreshLabel then
        refs_.refreshLabel:SetText("刷新 " .. FormatTime(mgr.GetRefreshTimer()))
    end

    -- 运输中卡片：剩余时间 + 进度条
    if refs_.transit then
        local transit = mgr.GetInTransit()
        for i, ref in pairs(refs_.transit) do
            local c = transit[i]
            if c and ref.timeLabel then
                local remaining = math.max(0, c.travelTime - c.elapsed)
                ref.timeLabel:SetText(FormatTime(remaining))
            end
            if c and ref.progressBar then
                local progress = c.travelTime > 0 and math.min(1.0, c.elapsed / c.travelTime) or 0
                local barW = math.floor(progress * 100)
                ref.progressBar:SetWidth(barW .. "%")
            end
        end
    end
end

-- ============================================================================
-- 公共 API
-- ============================================================================

function ShipmentPanel.Init(uiRoot, gameMgr)
    root_ = uiRoot
    gm_ = gameMgr

    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local drawerW = math.floor(screenW * 0.3)

    panel_ = UI.Panel {
        id = "shipmentPanel",
        position = "absolute",
        right = "30%",
        top = 0,
        width = drawerW,
        height = "100%",
        flexDirection = "column",
        backgroundColor = { 22, 28, 42, 245 },
        borderColor = { 60, 100, 160, 100 },
        borderWidth = { 0, 1, 0, 1 },
        zIndex = 100,
        overflow = "hidden",
        pointerEvents = "auto",
        visible = false,
    }

    root_:AddChild(panel_)
end

function ShipmentPanel.Show()
    if not panel_ then return end
    visible_ = true
    panel_:SetVisible(true)
    BuildContent()
end

function ShipmentPanel.Hide()
    if not panel_ then return end
    visible_ = false
    panel_:SetVisible(false)
end

function ShipmentPanel.Toggle()
    if visible_ then
        ShipmentPanel.Hide()
    else
        ShipmentPanel.Show()
    end
end

function ShipmentPanel.IsVisible()
    return visible_
end

function ShipmentPanel.Refresh()
    if not visible_ then return end
    local snap = MakeStructSnapshot()
    if snap ~= lastStructSnap_ then
        BuildContent()      -- 结构变化 → 全量重建
    else
        UpdateDynamic()     -- 仅数据变化 → 局部更新文本
    end
end

return ShipmentPanel
