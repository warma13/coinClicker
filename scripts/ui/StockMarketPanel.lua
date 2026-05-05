-- ============================================================================
-- ui/StockMarketPanel.lua
-- 证券交易所面板 —— 商品行情、买卖按钮、经纪人/办公室/贷款
-- 右侧抽屉栏，定位在商店面板左侧（与其他小游戏面板一致）
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local SC = require("config.StockMarketConfig")

local SP = {}

-- 内部引用
local uiRoot_       = nil
local overlay_      = nil
local panel_        = nil
local visible_      = false
local stockMgr_     = nil   -- StockMarketManager 引用
local manager_      = nil   -- GameManager 引用

-- UI 缓存
local goodsContainer_    = nil
local infoContainer_     = nil
local tickLabel_         = nil

-- 商品行增量更新缓存: goodRowCache_[goodIndex] = { row, priceLabel, changeLabel, ownedLabel, chart, buyBtn, buyLabel, buyCostLabel, sellBtn, sellLabel, sellCostLabel }
local goodRowCache_      = {}
-- 已构建的商品行 index 集合（用于判断是否需要重建）
local goodRowBuiltSet_   = {}

-- 刷新快照
local lastFingerprint_ = ""

-- 当前展示模式："goods" 或 "info"
local viewMode_ = "goods"

-- ============================================================================
-- 工具
-- ============================================================================

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

local function FormatDollar(v)
    if v >= 1000 then
        return string.format("$%.1fK", v / 1000)
    end
    return string.format("$%.1f", v)
end

local function FormatCoins(v)
    return GameState.FormatNumber(v)
end

-- 颜色常量
local C_GREEN = { 80, 220, 120, 255 }
local C_RED   = { 220, 80, 80, 255 }
local C_GRAY  = { 140, 140, 160, 200 }
local C_GOLD  = { 255, 215, 0, 255 }
local C_TEXT  = { 220, 220, 240, 255 }
local C_DIM   = { 160, 160, 180, 180 }
local C_BG    = { 28, 32, 45, 245 }
local C_ROW   = { 38, 42, 58, 255 }
local C_ROW_ALT = { 34, 38, 52, 255 }

-- ============================================================================
-- 前向声明
-- ============================================================================
local BuildPanel
local RebuildGoods
local RebuildInfo
local CreateGoodRow
local CreateMiniChart

-- ============================================================================
-- 初始化
-- ============================================================================

function SP.Init(root, gm)
    uiRoot_ = root
    manager_ = gm
    stockMgr_ = require("core.StockMarketManager")
    BuildPanel()
end

-- ============================================================================
-- 显示 / 隐藏
-- ============================================================================

function SP.Show()
    if not overlay_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    lastFingerprint_ = ""
    uiRoot_:AddChild(overlay_)
    SP.Refresh()
end

function SP.Hide()
    if not overlay_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(overlay_)
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
    if not visible_ or not stockMgr_ then return end

    -- 构建指纹
    local states = stockMgr_.GetAllGoodStates()
    local fpParts = { "v" .. viewMode_ }
    for i, gs in ipairs(states) do
        fpParts[#fpParts + 1] = string.format("%d:%.0f:%d", i, gs.value, gs.owned)
    end
    fpParts[#fpParts + 1] = "b" .. stockMgr_.GetBrokerCount()
    fpParts[#fpParts + 1] = "o" .. stockMgr_.GetOfficeLevel()
    fpParts[#fpParts + 1] = "t" .. math.floor(stockMgr_.GetTickTimer())
    fpParts[#fpParts + 1] = "c" .. math.floor(GameState.coins)

    -- 贷款状态
    for i = 1, #SC.loans do
        local ls = stockMgr_.GetLoanState(i)
        if ls and ls.active then
            fpParts[#fpParts + 1] = "l" .. i .. ":" .. math.floor(ls.boostRemaining) .. ":" .. math.floor(ls.penaltyRemaining)
        end
    end

    local fp = table.concat(fpParts, "|")
    if fp == lastFingerprint_ then return end
    lastFingerprint_ = fp

    -- 更新 tick 计时器
    if tickLabel_ then
        tickLabel_.text = "⏱️ " .. FormatTime(stockMgr_.GetTickTimer())
    end

    if viewMode_ == "goods" then
        RebuildGoods()
    else
        RebuildInfo()
    end
end

-- ============================================================================
-- 迷你趋势图（NanoVG 太重，用文字 sparkline 代替）
-- ============================================================================

CreateMiniChart = function(history)
    if not history or #history < 2 then
        return UI.Label { text = "─", fontSize = 9, fontColor = C_DIM }
    end

    -- 取最后 15 个数据点
    local pts = {}
    local start = math.max(1, #history - 14)
    for i = start, #history do
        pts[#pts + 1] = history[i]
    end

    -- 找 min/max
    local lo, hi = pts[1], pts[1]
    for _, v in ipairs(pts) do
        if v < lo then lo = v end
        if v > hi then hi = v end
    end

    -- 映射到 sparkline 字符
    local blocks = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
    local range = hi - lo
    if range < 0.01 then range = 1 end
    local chars = {}
    for _, v in ipairs(pts) do
        local idx = math.floor((v - lo) / range * 7) + 1
        idx = math.max(1, math.min(8, idx))
        chars[#chars + 1] = blocks[idx]
    end

    -- 颜色：最后 > 第一个 = 绿色，否则红色
    local trending = pts[#pts] >= pts[1]

    return UI.Label {
        text = table.concat(chars),
        fontSize = 10,
        fontColor = trending and C_GREEN or C_RED,
    }
end

-- ============================================================================
-- 商品行
-- ============================================================================

--- 计算涨跌字符串和颜色
local function CalcChange(gs)
    local history = gs.history
    local prevVal = #history >= 2 and history[#history - 1] or gs.value
    local change = gs.value - prevVal
    if change > 0.01 then
        return string.format("+%.1f", change), C_GREEN
    elseif change < -0.01 then
        return string.format("%.1f", change), C_RED
    end
    return "", C_GRAY
end

--- 创建商品行并缓存动态 UI 引用
CreateGoodRow = function(goodIndex, goodDef, gs, bgColor)
    local dollarVal = stockMgr_.GetDollarValue()
    local overhead = stockMgr_.GetOverhead()
    local maxStock = stockMgr_.GetMaxStock(goodIndex)
    local buyCost = gs.value * dollarVal * (1 + overhead)
    local sellVal = gs.value * dollarVal
    local canBuy = GameState.coins >= buyCost and gs.owned < maxStock
    local canSell = gs.owned > 0

    local changeStr, changeColor = CalcChange(gs)

    -- 创建需要动态更新的 Label 引用
    local priceLabel = UI.Label { text = FormatDollar(gs.value), fontSize = 13,
        fontColor = C_TEXT, fontStyle = "bold" }
    local changeLabel = UI.Label { text = changeStr, fontSize = 10, fontColor = changeColor }
    local ownedLabel = UI.Label {
        text = "持有 " .. gs.owned .. "/" .. maxStock,
        fontSize = 10,
        fontColor = gs.owned > 0 and C_GREEN or C_DIM,
    }
    local chartLabel = CreateMiniChart(gs.history)
    local buyLabel = UI.Label { text = "买入", fontSize = 10,
        fontColor = canBuy and C_GREEN or C_GRAY }
    local buyCostLabel = UI.Label { text = FormatCoins(buyCost), fontSize = 9,
        fontColor = canBuy and C_DIM or { 80, 80, 90, 150 } }
    local sellLabel = UI.Label { text = "卖出", fontSize = 10,
        fontColor = canSell and C_RED or C_GRAY }
    local sellCostLabel = UI.Label { text = FormatCoins(sellVal), fontSize = 9,
        fontColor = canSell and C_DIM or { 80, 80, 90, 150 } }

    local buyBtn = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 3,
        paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
        borderRadius = 4,
        backgroundColor = canBuy and { 30, 60, 40, 255 } or { 40, 40, 50, 200 },
        borderWidth = 1,
        borderColor = canBuy and { 60, 160, 80, 180 } or { 50, 50, 60, 100 },
        pointerEvents = "auto",
        onTap = function(self, event)
            if event and event.stopPropagation then event:stopPropagation() end
            stockMgr_.Buy(goodIndex, 1)
            lastFingerprint_ = ""
            SP.Refresh()
        end,
        children = { buyLabel, buyCostLabel },
    }

    local buyMaxLabel = UI.Label { text = "满仓", fontSize = 10,
        fontColor = canBuy and C_GREEN or C_GRAY }
    local buyMaxBtn = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 3,
        paddingLeft = 6, paddingRight = 6, paddingTop = 3, paddingBottom = 3,
        borderRadius = 4,
        backgroundColor = canBuy and { 30, 60, 40, 255 } or { 40, 40, 50, 200 },
        borderWidth = 1,
        borderColor = canBuy and { 60, 160, 80, 180 } or { 50, 50, 60, 100 },
        pointerEvents = "auto",
        onTap = function(self, event)
            if event and event.stopPropagation then event:stopPropagation() end
            stockMgr_.Buy(goodIndex, 99999)
            lastFingerprint_ = ""
            SP.Refresh()
        end,
        children = { buyMaxLabel },
    }

    local sellBtn = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 3,
        paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
        borderRadius = 4,
        backgroundColor = canSell and { 60, 30, 30, 255 } or { 40, 40, 50, 200 },
        borderWidth = 1,
        borderColor = canSell and { 160, 60, 60, 180 } or { 50, 50, 60, 100 },
        pointerEvents = "auto",
        onTap = function(self, event)
            if event and event.stopPropagation then event:stopPropagation() end
            stockMgr_.Sell(goodIndex, 1)
            lastFingerprint_ = ""
            SP.Refresh()
        end,
        children = { sellLabel, sellCostLabel },
    }

    local sellAllLabel = UI.Label { text = "清仓", fontSize = 10,
        fontColor = canSell and C_RED or C_GRAY }
    local sellAllBtn = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 3,
        paddingLeft = 6, paddingRight = 6, paddingTop = 3, paddingBottom = 3,
        borderRadius = 4,
        backgroundColor = canSell and { 60, 30, 30, 255 } or { 40, 40, 50, 200 },
        borderWidth = 1,
        borderColor = canSell and { 160, 60, 60, 180 } or { 50, 50, 60, 100 },
        pointerEvents = "auto",
        onTap = function(self, event)
            if event and event.stopPropagation then event:stopPropagation() end
            stockMgr_.Sell(goodIndex, 99999)
            lastFingerprint_ = ""
            SP.Refresh()
        end,
        children = { sellAllLabel },
    }

    local row = UI.Panel {
        width = "100%", flexDirection = "column",
        backgroundColor = bgColor,
        borderRadius = 6, padding = 6, gap = 4,
        children = {
            -- 第一行：图标 + 代码 + 名称 + 趋势图
            UI.Panel {
                width = "100%", flexDirection = "row",
                alignItems = "center", gap = 4,
                children = {
                    UI.Label { text = goodDef.ticker, fontSize = 12,
                        fontColor = C_GOLD, fontStyle = "bold", flexShrink = 0 },
                    UI.Label { text = goodDef.name, fontSize = 10,
                        fontColor = C_DIM, flex = 1, flexShrink = 1 },
                    chartLabel,
                },
            },
            -- 第二行：价格 + 涨跌 + 持仓
            UI.Panel {
                width = "100%", flexDirection = "row",
                alignItems = "center", justifyContent = "space-between",
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = { priceLabel, changeLabel },
                    },
                    ownedLabel,
                },
            },
            -- 第三行：买入/卖出按钮
            UI.Panel {
                width = "100%", flexDirection = "row",
                gap = 4, justifyContent = "flex-end",
                children = { buyMaxBtn, buyBtn, sellBtn, sellAllBtn },
            },
        },
    }

    -- 缓存引用
    goodRowCache_[goodIndex] = {
        row = row,
        priceLabel = priceLabel,
        changeLabel = changeLabel,
        ownedLabel = ownedLabel,
        chartLabel = chartLabel,
        buyBtn = buyBtn,
        buyLabel = buyLabel,
        buyCostLabel = buyCostLabel,
        buyMaxBtn = buyMaxBtn,
        buyMaxLabel = buyMaxLabel,
        sellBtn = sellBtn,
        sellLabel = sellLabel,
        sellCostLabel = sellCostLabel,
        sellAllBtn = sellAllBtn,
        sellAllLabel = sellAllLabel,
    }

    return row
end

--- 增量更新已缓存的商品行
local function UpdateGoodRow(goodIndex, gs)
    local cache = goodRowCache_[goodIndex]
    if not cache then return end

    local dollarVal = stockMgr_.GetDollarValue()
    local overhead = stockMgr_.GetOverhead()
    local maxStock = stockMgr_.GetMaxStock(goodIndex)
    local buyCost = gs.value * dollarVal * (1 + overhead)
    local sellVal = gs.value * dollarVal
    local canBuy = GameState.coins >= buyCost and gs.owned < maxStock
    local canSell = gs.owned > 0

    local changeStr, changeColor = CalcChange(gs)

    -- 更新价格
    cache.priceLabel:SetStyle({ text = FormatDollar(gs.value) })

    -- 更新涨跌
    cache.changeLabel:SetStyle({ text = changeStr, fontColor = changeColor })

    -- 更新持仓
    cache.ownedLabel:SetStyle({
        text = "持有 " .. gs.owned .. "/" .. maxStock,
        fontColor = gs.owned > 0 and C_GREEN or C_DIM,
    })

    -- 更新趋势图
    local history = gs.history
    if history and #history >= 2 then
        local pts = {}
        local start = math.max(1, #history - 14)
        for i = start, #history do pts[#pts + 1] = history[i] end
        local lo, hi = pts[1], pts[1]
        for _, v in ipairs(pts) do
            if v < lo then lo = v end
            if v > hi then hi = v end
        end
        local blocks = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
        local range = hi - lo
        if range < 0.01 then range = 1 end
        local chars = {}
        for _, v in ipairs(pts) do
            local idx = math.floor((v - lo) / range * 7) + 1
            idx = math.max(1, math.min(8, idx))
            chars[#chars + 1] = blocks[idx]
        end
        local trending = pts[#pts] >= pts[1]
        cache.chartLabel:SetStyle({
            text = table.concat(chars),
            fontColor = trending and C_GREEN or C_RED,
        })
    end

    -- 更新买入按钮状态
    cache.buyBtn:SetStyle({
        backgroundColor = canBuy and { 30, 60, 40, 255 } or { 40, 40, 50, 200 },
        borderColor = canBuy and { 60, 160, 80, 180 } or { 50, 50, 60, 100 },
    })
    cache.buyLabel:SetStyle({ fontColor = canBuy and C_GREEN or C_GRAY })
    cache.buyCostLabel:SetStyle({
        text = FormatCoins(buyCost),
        fontColor = canBuy and C_DIM or { 80, 80, 90, 150 },
    })

    -- 更新买满按钮状态
    cache.buyMaxBtn:SetStyle({
        backgroundColor = canBuy and { 30, 60, 40, 255 } or { 40, 40, 50, 200 },
        borderColor = canBuy and { 60, 160, 80, 180 } or { 50, 50, 60, 100 },
    })
    cache.buyMaxLabel:SetStyle({ fontColor = canBuy and C_GREEN or C_GRAY })

    -- 更新卖出按钮状态
    cache.sellBtn:SetStyle({
        backgroundColor = canSell and { 60, 30, 30, 255 } or { 40, 40, 50, 200 },
        borderColor = canSell and { 160, 60, 60, 180 } or { 50, 50, 60, 100 },
    })
    cache.sellLabel:SetStyle({ fontColor = canSell and C_RED or C_GRAY })
    cache.sellCostLabel:SetStyle({
        text = FormatCoins(sellVal),
        fontColor = canSell and C_DIM or { 80, 80, 90, 150 },
    })

    -- 更新全卖按钮状态
    cache.sellAllBtn:SetStyle({
        backgroundColor = canSell and { 60, 30, 30, 255 } or { 40, 40, 50, 200 },
        borderColor = canSell and { 160, 60, 60, 180 } or { 50, 50, 60, 100 },
    })
    cache.sellAllLabel:SetStyle({ fontColor = canSell and C_RED or C_GRAY })
end

-- ============================================================================
-- 重建商品列表
-- ============================================================================

RebuildGoods = function()
    if not goodsContainer_ then return end

    local states = stockMgr_.GetAllGoodStates()
    local Buildings = require("config.Buildings")

    -- 1) 计算当前可见商品索引列表
    local visibleIndices = {}
    for i, goodDef in ipairs(SC.goods) do
        local gs = states[i]
        if gs then
            for _, b in ipairs(Buildings.buildings) do
                if b.id == goodDef.buildingId and b.count > 0 then
                    visibleIndices[#visibleIndices + 1] = i
                    break
                end
            end
        end
    end

    -- 2) 判断可见集合是否发生变化（需要重建容器结构）
    local needsRebuild = (#visibleIndices ~= #goodRowBuiltSet_)
    if not needsRebuild then
        for idx, gi in ipairs(visibleIndices) do
            if goodRowBuiltSet_[idx] ~= gi then
                needsRebuild = true
                break
            end
        end
    end

    -- 3) 如果可见集合变化了，重建容器
    if needsRebuild then
        goodsContainer_:RemoveAllChildren()
        goodRowCache_ = {}
        goodRowBuiltSet_ = {}

        if #visibleIndices == 0 then
            goodsContainer_:AddChild(UI.Panel {
                width = "100%", padding = 20, alignItems = "center",
                children = {
                    UI.Label { text = "购买更多产业以解锁商品", fontSize = 12, fontColor = C_DIM },
                },
            })
            return
        end

        for order, gi in ipairs(visibleIndices) do
            local gs = states[gi]
            local bgColor = (order % 2 == 0) and C_ROW_ALT or C_ROW
            goodsContainer_:AddChild(CreateGoodRow(gi, SC.goods[gi], gs, bgColor))
            goodRowBuiltSet_[order] = gi
        end
    else
        -- 4) 可见集合没变，增量更新所有行
        for _, gi in ipairs(visibleIndices) do
            UpdateGoodRow(gi, states[gi])
        end
    end
end

-- ============================================================================
-- 重建信息面板（经纪人/办公室/贷款）
-- ============================================================================

RebuildInfo = function()
    if not infoContainer_ then return end
    infoContainer_:RemoveAllChildren()

    local children = {}

    -- ── 手续费 & 经纪人 ──
    local overhead = stockMgr_.GetOverhead()
    local brokers = stockMgr_.GetBrokerCount()
    local maxBrokers = stockMgr_.GetMaxBrokers()
    local brokerCost = stockMgr_.GetBrokerCostCoins()
    local canHire = brokers < maxBrokers and GameState.coins >= brokerCost

    children[#children + 1] = UI.Panel {
        width = "100%", backgroundColor = C_ROW, borderRadius = 6,
        padding = 8, gap = 4,
        children = {
            UI.Label { text = "经纪人", fontSize = 13, fontColor = C_GOLD },
            UI.Label {
                text = string.format("当前手续费: %.2f%%", overhead * 100),
                fontSize = 11, fontColor = C_TEXT,
            },
            UI.Label {
                text = string.format("经纪人: %d / %d", brokers, maxBrokers),
                fontSize = 11, fontColor = C_DIM,
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
                borderRadius = 4, marginTop = 4,
                backgroundColor = canHire and { 30, 50, 60, 255 } or { 40, 40, 50, 200 },
                borderWidth = 1,
                borderColor = canHire and { 60, 140, 180, 180 } or { 50, 50, 60, 100 },
                pointerEvents = "auto",
                onTap = function(self, event)
                    if event and event.stopPropagation then event:stopPropagation() end
                    if canHire then
                        stockMgr_.HireBroker()
                        lastFingerprint_ = ""
                        SP.Refresh()
                    end
                end,
                children = {
                    UI.Label { text = "雇佣 $" .. stockMgr_.GetBrokerCostDollars(), fontSize = 11,
                        fontColor = canHire and { 100, 200, 240, 255 } or C_GRAY },
                    UI.Label { text = "(" .. FormatCoins(brokerCost) .. ")", fontSize = 9,
                        fontColor = C_DIM },
                },
            },
            maxBrokers == 0 and UI.Label {
                text = "提示: 购买小作坊以解锁经纪人",
                fontSize = 9, fontColor = { 200, 180, 100, 180 },
            } or UI.Panel { width = 0, height = 0 },
        },
    }

    -- ── 办公室 ──
    local officeLevel = stockMgr_.GetOfficeLevel()
    local curOffice = SC.GetOffice(officeLevel)
    local nextOffice = SC.GetNextOffice(officeLevel)

    children[#children + 1] = UI.Panel {
        width = "100%", backgroundColor = C_ROW_ALT, borderRadius = 6,
        padding = 8, gap = 4,
        children = {
            UI.Label { text = curOffice.name, fontSize = 13, fontColor = C_GOLD },
            UI.Label {
                text = "仓位加成: +" .. curOffice.storagePlus,
                fontSize = 11, fontColor = C_DIM,
            },
            nextOffice and UI.Panel {
                gap = 2,
                children = {
                    UI.Label { text = "下一级: " .. nextOffice.name, fontSize = 10, fontColor = C_TEXT },
                    UI.Label {
                        text = "需要 " .. nextOffice.cursorReq .. " 个临时工 (等级" .. nextOffice.cursorLevel .. ")",
                        fontSize = 9, fontColor = C_DIM,
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center",
                        paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
                        borderRadius = 4, marginTop = 2,
                        backgroundColor = { 40, 40, 60, 255 },
                        borderWidth = 1,
                        borderColor = { 80, 80, 120, 150 },
                        pointerEvents = "auto",
                        onTap = function(self, event)
                            if event and event.stopPropagation then event:stopPropagation() end
                            local ok, reason = stockMgr_.UpgradeOffice()
                            if ok then
                                lastFingerprint_ = ""
                                SP.Refresh()
                            end
                        end,
                        children = {
                            UI.Label { text = "升级", fontSize = 11, fontColor = { 150, 150, 200, 255 } },
                        },
                    },
                },
            } or UI.Label { text = "已满级", fontSize = 10, fontColor = C_DIM },
        },
    }

    -- ── 贷款 ──
    local loanSlots = stockMgr_.GetAvailableLoanSlots()
    if loanSlots > 0 then
        local loanChildren = {
            UI.Label { text = "贷款", fontSize = 13, fontColor = C_GOLD },
        }
        for i, loanDef in ipairs(SC.loans) do
            if i <= loanSlots then
                local ls = stockMgr_.GetLoanState(i)
                local isActive = ls and ls.active

                -- 构建详情描述行
                local descLines = {}
                descLines[#descLines + 1] = string.format(
                    "增益: CPS ×%.1f (%s)", loanDef.boostMul, FormatTime(loanDef.boostDur))
                descLines[#descLines + 1] = string.format(
                    "偿还: CPS ×%.1f (%s)", loanDef.penaltyMul, FormatTime(loanDef.penaltyDur))
                descLines[#descLines + 1] = string.format(
                    "首付: 当前金币的 %d%%", loanDef.downpayment * 100)

                -- 状态行
                local statusChildren = {}
                if isActive then
                    if ls.boostRemaining > 0 then
                        statusChildren[#statusChildren + 1] = UI.Label {
                            text = "增益中 " .. FormatTime(ls.boostRemaining),
                            fontSize = 10, fontColor = C_GREEN,
                        }
                    elseif ls.penaltyRemaining > 0 then
                        statusChildren[#statusChildren + 1] = UI.Label {
                            text = "偿还中 " .. FormatTime(ls.penaltyRemaining),
                            fontSize = 10, fontColor = C_RED,
                        }
                    end
                end

                loanChildren[#loanChildren + 1] = UI.Panel {
                    width = "100%", flexDirection = "row",
                    alignItems = "center", justifyContent = "space-between",
                    paddingTop = 4, paddingBottom = 4,
                    borderBottomWidth = 1, borderColor = { 50, 50, 65, 100 },
                    children = {
                        UI.Panel { gap = 2, flex = 1, flexShrink = 1, children = {
                            UI.Label { text = loanDef.name, fontSize = 12, fontColor = C_TEXT },
                            UI.Label { text = descLines[1], fontSize = 9, fontColor = C_GREEN },
                            UI.Label { text = descLines[2], fontSize = 9, fontColor = C_RED },
                            UI.Label { text = descLines[3], fontSize = 9, fontColor = C_DIM },
                            table.unpack(statusChildren),
                        } },
                        not isActive and UI.Panel {
                            paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
                            borderRadius = 4,
                            backgroundColor = { 50, 40, 30, 255 },
                            borderWidth = 1,
                            borderColor = { 180, 140, 60, 180 },
                            pointerEvents = "auto",
                            onTap = function(self, event)
                                if event and event.stopPropagation then event:stopPropagation() end
                                stockMgr_.TakeLoan(i)
                                lastFingerprint_ = ""
                                SP.Refresh()
                            end,
                            children = {
                                UI.Label { text = "申请", fontSize = 10, fontColor = C_GOLD },
                            },
                        } or UI.Panel { width = 0, height = 0 },
                    },
                }
            end
        end

        children[#children + 1] = UI.Panel {
            width = "100%", backgroundColor = C_ROW, borderRadius = 6,
            padding = 8, gap = 4,
            children = loanChildren,
        }
    end

    -- ── 统计 ──
    children[#children + 1] = UI.Panel {
        width = "100%", backgroundColor = C_ROW_ALT, borderRadius = 6,
        padding = 8, gap = 2,
        children = {
            UI.Label { text = "交易统计", fontSize = 13, fontColor = C_GOLD },
            UI.Label {
                text = "$1 = " .. FormatCoins(stockMgr_.GetDollarValue()),
                fontSize = 10, fontColor = C_DIM,
            },
        },
    }

    for _, child in ipairs(children) do
        infoContainer_:AddChild(child)
    end
end

-- ============================================================================
-- 构建面板骨架
-- ============================================================================

BuildPanel = function()
    tickLabel_ = UI.Label {
        text = "⏱️ 0:00",
        fontSize = 11,
        fontColor = C_DIM,
    }

    goodsContainer_ = UI.Panel {
        width = "100%", gap = 4,
    }

    infoContainer_ = UI.Panel {
        width = "100%", gap = 6,
    }

    -- 商品视图 + 信息视图（同一时间只挂载一个）
    local goodsView = UI.Panel {
        width = "100%", flex = 1, flexShrink = 1,
        overflow = "scroll",
        paddingLeft = 4, paddingRight = 4, paddingBottom = 8,
        children = { goodsContainer_ },
    }

    local infoView = UI.Panel {
        width = "100%", flex = 1, flexShrink = 1,
        overflow = "scroll",
        paddingLeft = 4, paddingRight = 4, paddingBottom = 8,
        children = { infoContainer_ },
    }

    -- 内容容器（通过 AddChild/RemoveChild 切换视图）
    local contentHost = UI.Panel {
        width = "100%", flex = 1, flexShrink = 1,
        children = { goodsView },  -- 默认显示行情
    }

    -- Tab 按钮
    local tabGoods, tabInfo

    local function SwitchView(mode)
        viewMode_ = mode
        lastFingerprint_ = ""
        contentHost:RemoveAllChildren()
        if mode == "goods" then
            contentHost:AddChild(goodsView)
            tabGoods:SetStyle({ backgroundColor = { 60, 80, 100, 255 } })
            tabInfo:SetStyle({ backgroundColor = { 35, 38, 50, 255 } })
        else
            contentHost:AddChild(infoView)
            tabGoods:SetStyle({ backgroundColor = { 35, 38, 50, 255 } })
            tabInfo:SetStyle({ backgroundColor = { 60, 80, 100, 255 } })
        end
        SP.Refresh()
    end

    tabGoods = UI.Panel {
        flex = 1, alignItems = "center", justifyContent = "center",
        paddingTop = 6, paddingBottom = 6, borderRadius = 4,
        backgroundColor = { 60, 80, 100, 255 },
        pointerEvents = "auto",
        onTap = function() SwitchView("goods") end,
        children = {
            UI.Label { text = "行情", fontSize = 12, fontColor = C_TEXT },
        },
    }

    tabInfo = UI.Panel {
        flex = 1, alignItems = "center", justifyContent = "center",
        paddingTop = 6, paddingBottom = 6, borderRadius = 4,
        backgroundColor = { 35, 38, 50, 255 },
        pointerEvents = "auto",
        onTap = function() SwitchView("info") end,
        children = {
            UI.Label { text = "管理", fontSize = 12, fontColor = C_TEXT },
        },
    }

    panel_ = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        paddingTop = 10, paddingLeft = 6, paddingRight = 6,
        paddingBottom = 6,
        pointerEvents = "auto",
        children = {
            -- 标题行
            UI.Panel {
                width = "100%",
                flexDirection = "row", alignItems = "center",
                justifyContent = "space-between",
                marginBottom = 6,
                paddingLeft = 6, paddingRight = 4,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label { text = "📈", fontSize = 14 },
                            UI.Label {
                                text = "证券交易所",
                                fontSize = 17,
                                fontColor = { 100, 200, 160, 255 },
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 8,
                        children = {
                            tickLabel_,
                            UI.Panel {
                                paddingLeft = 8, paddingRight = 8,
                                paddingTop = 4, paddingBottom = 4,
                                borderRadius = 4,
                                backgroundColor = { 60, 40, 40, 255 },
                                pointerEvents = "auto",
                                onTap = function() SP.Hide() end,
                                children = {
                                    UI.Label { text = "✕", fontSize = 14, fontColor = C_TEXT },
                                },
                            },
                        },
                    },
                },
            },
            -- Tab 栏
            UI.Panel {
                width = "100%", flexDirection = "row", gap = 4,
                marginBottom = 6, paddingLeft = 4, paddingRight = 4,
                children = { tabGoods, tabInfo },
            },
            -- 内容区（通过 contentHost 切换行情/管理）
            contentHost,
        },
    }

    -- 创建右侧抽屉容器（与其他面板一致：30% 宽度）
    local dpr = graphics:GetDPR()
    local logicalW = graphics:GetWidth() / dpr
    local drawerW = math.floor(logicalW * 0.3)

    overlay_ = UI.Panel {
        position = "absolute",
        top = 0,
        right = "30%",
        width = drawerW,
        height = "100%",
        zIndex = 100,
        backgroundColor = C_BG,
        borderColor = { 80, 100, 120, 120 },
        borderWidth = { 0, 1, 0, 1 },
        pointerEvents = "auto",
        children = { panel_ },
    }
end

return SP
