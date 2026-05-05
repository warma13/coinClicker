-- ============================================================================
-- ui/ECommercePanel.lua
-- 电商平台面板 —— 商品列表、秒杀倒计时、投资/推广操作
-- 右侧抽屉栏，与其他小游戏面板一致
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local EC = require("config.ECommerceConfig")

local EP = {}

-- 内部引用
local uiRoot_       = nil
local overlay_      = nil
local panel_        = nil
local visible_      = false
local ecommerceMgr_ = nil   -- ECommerceManager 引用
local manager_      = nil   -- GameManager 引用

-- UI 缓存
local productsContainer_ = nil
local slotsLabel_        = nil
local streakLabel_       = nil
local promoLabel_        = nil
local refreshLabel_      = nil

-- 刷新指纹（结构性）
local lastFingerprint_ = ""
-- 增量更新缓存 { invested = { [index] = { progressLabel, progressBar, timeLabel } } }
local dynRefs_ = {}

-- ============================================================================
-- 颜色常量
-- ============================================================================

local C_BG      = { 28, 26, 42, 245 }
local C_TEXT    = { 220, 220, 240, 255 }
local C_DIM     = { 140, 140, 160, 200 }
local C_GOLD    = { 255, 215, 0, 255 }
local C_GREEN   = { 80, 220, 120, 255 }
local C_RED     = { 220, 80, 80, 255 }
local C_PURPLE  = { 180, 100, 220, 255 }
local C_ORANGE  = { 255, 160, 60, 255 }
local C_HOT     = { 255, 80, 120, 255 }

-- ============================================================================
-- 前向声明
-- ============================================================================
local BuildPanel
local RebuildProducts

-- ============================================================================
-- 工具
-- ============================================================================

local function FormatCoins(v)
    return GameState.FormatNumber(v)
end

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    if m > 0 then
        return string.format("%d:%02d", m, s)
    end
    return string.format("%ds", s)
end

-- ============================================================================
-- 初始化
-- ============================================================================

function EP.Init(root, gm)
    uiRoot_ = root
    manager_ = gm
    ecommerceMgr_ = require("core.ECommerceManager")
    BuildPanel()
end

-- ============================================================================
-- 显示 / 隐藏
-- ============================================================================

function EP.Show()
    if not overlay_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    lastFingerprint_ = ""
    uiRoot_:AddChild(overlay_)
    EP.Refresh()
end

function EP.Hide()
    if not overlay_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(overlay_)
end

function EP.Toggle()
    if visible_ then EP.Hide() else EP.Show() end
end

function EP.IsVisible()
    return visible_
end

-- ============================================================================
-- 刷新
-- ============================================================================

-- 前向声明
local UpdateDynamic

function EP.Refresh()
    if not visible_ or not ecommerceMgr_ then return end

    -- ── 结构指纹（不含 elapsed / refreshTimer） ──
    local fpParts = {}
    fpParts[#fpParts + 1] = "s" .. ecommerceMgr_.GetStreak()
    fpParts[#fpParts + 1] = "t" .. ecommerceMgr_.GetTotalSold()
    fpParts[#fpParts + 1] = "n" .. #ecommerceMgr_.GetProducts()

    for i, p in ipairs(ecommerceMgr_.GetProducts()) do
        fpParts[#fpParts + 1] = "p" .. i .. "=" .. p.state .. (p.isHot and "H" or "") .. (p.adBoosted and "A" or "") .. p.itemId
    end

    -- CPS 粗粒度桶（影响 available 卡片的成本/利润显示）
    local cps = math.max(GameState.coinsPerSecond, 1)
    fpParts[#fpParts + 1] = "C" .. math.floor(math.log(cps) * 3)

    local fp = table.concat(fpParts, "|")
    local structChanged = fp ~= lastFingerprint_

    if structChanged then
        lastFingerprint_ = fp

        -- 更新状态栏
        if slotsLabel_ then
            slotsLabel_:SetStyle({
                text = "商品 " .. #ecommerceMgr_.GetProducts() .. "/" .. ecommerceMgr_.GetMaxSlots()
            })
        end

        if streakLabel_ then
            local streak = ecommerceMgr_.GetStreak()
            if streak > 0 then
                streakLabel_:SetStyle({
                    text = "连售 ×" .. streak,
                    fontColor = streak >= 6 and C_GOLD or (streak >= 3 and C_GREEN or C_DIM),
                })
            else
                streakLabel_:SetStyle({ text = "", fontColor = C_DIM })
            end
        end

        if promoLabel_ then
            local discount, label = ecommerceMgr_.GetPromoInfo()
            if discount > 0 and label then
                promoLabel_:SetStyle({
                    text = "🏷️ " .. label .. " (-" .. math.floor(discount * 100) .. "%)",
                    fontColor = C_ORANGE,
                })
            else
                promoLabel_:SetStyle({ text = "", fontColor = C_DIM })
            end
        end

        -- 全量重建商品列表
        RebuildProducts()
    end

    -- ── 动态更新（每帧：倒计时、进度条） ──
    UpdateDynamic()
end

-- ============================================================================
-- 商品卡片列表
-- ============================================================================

--- 构建一张秒杀中的商品卡片
--- 返回 card, refs  (refs = { progressLabel, progressBar, timeLabel })
---@param product ECommerceProduct
---@param index number
---@return table widget
---@return table refs
local function BuildInvestedCard(product, index)
    local def = EC.itemMap[product.itemId]
    if not def then return nil, nil end

    local progress = math.min(1, product.elapsed / math.max(1, product.saleTime))
    local progressPct = math.floor(progress * 100)
    local remaining = product.saleTime - product.elapsed

    -- 需要动态更新的控件
    local progressLabel = UI.Label { text = progressPct .. "%", fontSize = 10, fontColor = C_PURPLE }
    local progressBar = UI.Panel {
        width = progressPct .. "%", height = "100%",
        backgroundColor = C_PURPLE, borderRadius = 3,
    }
    local timeLabel = UI.Label { text = "剩余 " .. FormatTime(remaining), fontSize = 10, fontColor = C_DIM }

    local children = {
        -- 标题行
        UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            justifyContent = "space-between",
            children = {
                UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, children = {
                    UI.Label { text = def.icon, fontSize = 14 },
                    UI.Label { text = def.name, fontSize = 12, fontColor = C_TEXT },
                    product.isHot and UI.Label { text = "🔥", fontSize = 10 } or nil,
                } },
                progressLabel,
            },
        },
        -- 进度条
        UI.Panel {
            width = "100%", height = 5, borderRadius = 3,
            backgroundColor = { 35, 35, 50, 255 }, overflow = "hidden",
            children = { progressBar },
        },
        -- 利润 + 剩余时间
        UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            justifyContent = "space-between",
            children = {
                UI.Panel { flexDirection = "row", alignItems = "center", gap = 2, children = {
                    UI.Panel { width = 10, height = 10, backgroundImage = "image/金币.png", backgroundFit = "contain" },
                    UI.Label { text = "+" .. FormatCoins(product.profit), fontSize = 10, fontColor = C_GOLD },
                } },
                timeLabel,
            },
        },
    }

    -- 推广按钮或标记
    if product.adBoosted then
        children[#children + 1] = UI.Label {
            text = "📢 已推广 利润+50%", fontSize = 9, fontColor = C_ORANGE,
        }
    else
        local adCost = GameState.coinsPerSecond * EC.AD_BOOST_CPS_MUL
        local canAfford = GameState.coins >= adCost
        children[#children + 1] = UI.Panel {
            width = "100%", alignItems = "center", marginTop = 2,
            children = {
                UI.Panel {
                    paddingLeft = 12, paddingRight = 12, paddingTop = 3, paddingBottom = 3,
                    borderRadius = 4,
                    backgroundColor = canAfford and { 55, 45, 30, 255 } or { 45, 45, 50, 255 },
                    borderWidth = 1,
                    borderColor = canAfford and { 180, 140, 60, 180 } or { 60, 60, 70, 100 },
                    pointerEvents = "auto",
                    onTap = (function(idx)
                        return function(self, event)
                            if event and event.stopPropagation then event:stopPropagation() end
                            if ecommerceMgr_.AdBoostProduct(idx) then
                                lastFingerprint_ = ""
                                EP.Refresh()
                            end
                        end
                    end)(index),
                    children = {
                        UI.Label {
                            text = "📢 推广(利润+50%) " .. FormatCoins(adCost),
                            fontSize = 9, fontColor = canAfford and C_ORANGE or C_DIM,
                        },
                    },
                },
            },
        }
    end

    local card = UI.Panel {
        width = "100%", flexDirection = "column",
        paddingLeft = 8, paddingRight = 8, paddingTop = 6, paddingBottom = 6,
        borderRadius = 6, gap = 3,
        backgroundColor = { 40, 35, 55, 255 },
        borderWidth = 1, borderColor = { 130, 90, 200, 180 },
        children = children,
    }
    local refs = { progressLabel = progressLabel, progressBar = progressBar, timeLabel = timeLabel }
    return card, refs
end

--- 构建一张已售出的商品卡片
local function BuildSoldCard(product)
    local def = EC.itemMap[product.itemId]
    if not def then return nil end
    return UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        justifyContent = "space-between",
        paddingLeft = 8, paddingRight = 8, paddingTop = 5, paddingBottom = 5,
        borderRadius = 6,
        backgroundColor = { 30, 38, 30, 200 },
        borderWidth = 1, borderColor = { 60, 100, 60, 100 },
        children = {
            UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, children = {
                UI.Label { text = def.icon, fontSize = 12 },
                UI.Label { text = def.name, fontSize = 11, fontColor = C_DIM },
            } },
            UI.Label { text = "✅ +" .. FormatCoins(product.profit), fontSize = 10, fontColor = C_GREEN },
        },
    }
end

--- 构建一张待选商品卡片
---@param product ECommerceProduct
---@param index number
local function BuildAvailableCard(product, index)
    local def = EC.itemMap[product.itemId]
    if not def then return nil end

    local discount, _ = ecommerceMgr_.GetPromoInfo()
    local investCost = GameState.coinsPerSecond * def.investCpsMul * (1 - discount)
    local expectedProfit = GameState.coinsPerSecond * def.profitCpsMul
    if product.isHot then expectedProfit = expectedProfit * 2 end
    local canAfford = GameState.coins >= investCost

    local children = {
        -- 标题行
        UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            justifyContent = "space-between",
            children = {
                UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, children = {
                    UI.Label { text = def.icon, fontSize = 14 },
                    UI.Label { text = def.name, fontSize = 12, fontColor = C_TEXT },
                    product.isHot and UI.Label { text = "🔥爆款", fontSize = 9, fontColor = C_HOT } or nil,
                } },
                UI.Label { text = "⏱️ " .. FormatTime(def.saleTime), fontSize = 10, fontColor = C_DIM },
            },
        },
        -- 进货/利润/ROI
        UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            justifyContent = "space-between",
            children = {
                UI.Panel { flexDirection = "row", alignItems = "center", gap = 2, children = {
                    UI.Label { text = "成本", fontSize = 10, fontColor = C_DIM },
                    UI.Panel { width = 10, height = 10, backgroundImage = "image/金币.png", backgroundFit = "contain" },
                    UI.Label { text = FormatCoins(investCost), fontSize = 10, fontColor = C_TEXT },
                } },
                UI.Panel { flexDirection = "row", alignItems = "center", gap = 2, children = {
                    UI.Label { text = "利润", fontSize = 10, fontColor = C_DIM },
                    UI.Panel { width = 10, height = 10, backgroundImage = "image/金币.png", backgroundFit = "contain" },
                    UI.Label { text = "+" .. FormatCoins(expectedProfit), fontSize = 10, fontColor = C_GOLD },
                } },
            },
        },
    }

    -- buff 提示
    if def.buff then
        children[#children + 1] = UI.Label {
            text = "✨ " .. (def.buff.name or def.buff.id) .. ": CPS +" .. math.floor((def.buff.mul - 1) * 100 + 0.5) .. "%",
            fontSize = 9, fontColor = C_PURPLE,
        }
    end

    -- 进货按钮
    children[#children + 1] = UI.Panel {
        width = "100%", alignItems = "center", marginTop = 2,
        children = {
            UI.Panel {
                paddingLeft = 16, paddingRight = 16, paddingTop = 5, paddingBottom = 5,
                borderRadius = 4,
                backgroundColor = canAfford and { 50, 40, 70, 255 } or { 45, 45, 50, 255 },
                borderWidth = 1,
                borderColor = canAfford and { 150, 100, 220, 200 } or { 60, 60, 70, 100 },
                pointerEvents = "auto",
                onTap = (function(idx)
                    return function(self, event)
                        if event and event.stopPropagation then event:stopPropagation() end
                        if ecommerceMgr_.InvestProduct(idx) then
                            lastFingerprint_ = ""
                            EP.Refresh()
                        end
                    end
                end)(index),
                children = {
                    UI.Label {
                        text = canAfford and "秒杀进货" or "金币不足",
                        fontSize = 11, fontColor = canAfford and C_PURPLE or C_DIM,
                    },
                },
            },
        },
    }

    return UI.Panel {
        width = "100%", flexDirection = "column",
        paddingLeft = 8, paddingRight = 8, paddingTop = 6, paddingBottom = 6,
        borderRadius = 6, gap = 4,
        backgroundColor = { 38, 40, 55, 255 },
        borderWidth = 1, borderColor = { 70, 75, 95, 150 },
        children = children,
    }
end

--- 动态更新：刷新倒计时 + 秒杀中卡片进度（不重建 DOM）
UpdateDynamic = function()
    if not ecommerceMgr_ then return end

    -- 刷新倒计时
    if refreshLabel_ then
        refreshLabel_:SetStyle({
            text = "🔄 商品刷新  " .. FormatTime(ecommerceMgr_.GetRefreshTimer()),
        })
    end

    -- 秒杀中卡片进度
    local products = ecommerceMgr_.GetProducts()
    if dynRefs_.invested then
        for _, entry in ipairs(dynRefs_.invested) do
            local p = products[entry.idx]
            if p and p.state == "invested" then
                local progress = math.min(1, p.elapsed / math.max(1, p.saleTime))
                local pct = math.floor(progress * 100)
                local remaining = p.saleTime - p.elapsed
                local r = entry.refs
                if r.progressLabel then
                    r.progressLabel:SetStyle({ text = pct .. "%" })
                end
                if r.progressBar then
                    r.progressBar:SetStyle({ width = pct .. "%" })
                end
                if r.timeLabel then
                    r.timeLabel:SetStyle({ text = "剩余 " .. FormatTime(remaining) })
                end
            end
        end
    end
end

RebuildProducts = function()
    if not productsContainer_ or not ecommerceMgr_ then return end
    productsContainer_:RemoveAllChildren()
    dynRefs_.invested = {}

    local products = ecommerceMgr_.GetProducts()

    -- 分类
    local invested = {}
    local sold = {}
    local available = {}
    for i, p in ipairs(products) do
        if p.state == "invested" then
            invested[#invested + 1] = { prod = p, idx = i }
        elseif p.state == "sold" then
            sold[#sold + 1] = { prod = p, idx = i }
        else
            available[#available + 1] = { prod = p, idx = i }
        end
    end

    -- === 秒杀中 ===
    if #invested > 0 then
        productsContainer_:AddChild(UI.Label {
            text = "⏳ 秒杀中 (" .. #invested .. ")",
            fontSize = 12, fontColor = C_PURPLE, marginBottom = 2,
        })
        for _, item in ipairs(invested) do
            local card, refs = BuildInvestedCard(item.prod, item.idx)
            if card then
                productsContainer_:AddChild(card)
                if refs then
                    dynRefs_.invested[#dynRefs_.invested + 1] = { idx = item.idx, refs = refs }
                end
            end
        end
    end

    -- === 已售出 ===
    if #sold > 0 then
        productsContainer_:AddChild(UI.Label {
            text = "✅ 已售出 (" .. #sold .. ")",
            fontSize = 12, fontColor = C_GREEN,
            marginTop = #invested > 0 and 6 or 0, marginBottom = 2,
        })
        for _, item in ipairs(sold) do
            local card = BuildSoldCard(item.prod)
            if card then productsContainer_:AddChild(card) end
        end
    end

    -- === 待选商品 ===
    if #available > 0 then
        productsContainer_:AddChild(UI.Label {
            text = "🛒 待选商品 (" .. #available .. ")",
            fontSize = 12, fontColor = C_GOLD,
            marginTop = (#invested + #sold) > 0 and 6 or 0, marginBottom = 2,
        })
        for _, item in ipairs(available) do
            local card = BuildAvailableCard(item.prod, item.idx)
            if card then productsContainer_:AddChild(card) end
        end
    end

    -- 全部空
    if #invested == 0 and #sold == 0 and #available == 0 then
        productsContainer_:AddChild(UI.Label {
            text = "暂无商品，等待刷新",
            fontSize = 11, fontColor = C_DIM,
            width = "100%", textAlign = "center", marginTop = 8,
        })
    end
end

-- ============================================================================
-- 构建面板骨架
-- ============================================================================

BuildPanel = function()
    slotsLabel_ = UI.Label {
        text = "商品 0/3",
        fontSize = 11, fontColor = C_TEXT,
    }

    streakLabel_ = UI.Label {
        text = "",
        fontSize = 11, fontColor = C_DIM,
    }

    promoLabel_ = UI.Label {
        text = "",
        fontSize = 10, fontColor = C_DIM,
    }

    productsContainer_ = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 2,
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
                            UI.Label { text = "🌀", fontSize = 18 },
                            UI.Label {
                                text = "限时秒杀",
                                fontSize = 17,
                                fontColor = { 180, 100, 220, 255 },
                            },
                        },
                    },
                    UI.Panel {
                        paddingLeft = 8, paddingRight = 8,
                        paddingTop = 4, paddingBottom = 4,
                        borderRadius = 4,
                        backgroundColor = { 60, 40, 40, 255 },
                        pointerEvents = "auto",
                        onTap = function() EP.Hide() end,
                        children = {
                            UI.Label { text = "✕", fontSize = 14, fontColor = C_TEXT },
                        },
                    },
                },
            },
            -- 状态栏
            UI.Panel {
                width = "100%",
                flexDirection = "row", alignItems = "center",
                justifyContent = "space-between",
                paddingLeft = 6, paddingRight = 6,
                marginBottom = 2,
                children = {
                    slotsLabel_,
                    streakLabel_,
                },
            },
            -- 促销状态
            UI.Panel {
                width = "100%",
                paddingLeft = 6, paddingRight = 6,
                marginBottom = 6,
                children = { promoLabel_ },
            },
            -- 可滚动区域
            UI.Panel {
                width = "100%", flex = 1, flexShrink = 1,
                overflow = "scroll",
                paddingLeft = 2, paddingRight = 2,
                paddingBottom = 8,
                gap = 6,
                children = {
                    -- 商品区域
                    UI.Panel {
                        width = "100%", gap = 4,
                        children = {
                            UI.Label {
                                text = "🛒 商品列表",
                                fontSize = 13, fontColor = C_GOLD,
                            },
                            productsContainer_,
                        },
                    },
                    -- 刷新倒计时（动态更新）
                    (function()
                        refreshLabel_ = UI.Label {
                            text = "🔄 商品刷新  " .. FormatTime(ecommerceMgr_ and ecommerceMgr_.GetRefreshTimer() or 0),
                            fontSize = 10, fontColor = C_ORANGE,
                            width = "100%", textAlign = "center",
                            paddingTop = 6, paddingBottom = 2,
                        }
                        return refreshLabel_
                    end)(),
                    -- 分隔线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 75, 100, 80 },
                        marginTop = 4, marginBottom = 4,
                    },
                    -- 说明区域
                    UI.Panel {
                        width = "100%", gap = 2,
                        children = {
                            UI.Label { text = "📖 玩法说明", fontSize = 12, fontColor = C_GOLD, marginBottom = 2 },
                            UI.Label { text = "选择商品进货，等待秒杀倒计时结束即可获利",
                                fontSize = 9, fontColor = C_DIM },
                            UI.Label { text = "🔥爆款商品利润翻倍，但出现概率较低",
                                fontSize = 9, fontColor = C_DIM },
                            UI.Label { text = "连续成功出售可解锁促销折扣，降低进货成本",
                                fontSize = 9, fontColor = C_DIM },
                            UI.Label { text = "📢推广可花费金币提升利润50%",
                                fontSize = 9, fontColor = C_DIM },
                            UI.Label { text = "连售3次/6次可触发CPS加成Buff",
                                fontSize = 9, fontColor = C_DIM },
                        },
                    },
                },
            },
        },
    }

    -- 创建右侧抽屉容器
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
        borderColor = { 150, 90, 220, 120 },
        borderWidth = { 0, 1, 0, 1 },
        pointerEvents = "auto",
        children = { panel_ },
    }
end

return EP
