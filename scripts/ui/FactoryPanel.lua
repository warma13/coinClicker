-- ============================================================================
-- ui/FactoryPanel.lua
-- 制造工厂面板
-- 右侧抽屉：上部=等级+合成/订单，底部=采集按钮+物品栏
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local FC = require("config.FactoryConfig")

local FP = {}

-- 内部引用
local uiRoot_       = nil
local overlay_      = nil   -- 右侧抽屉（含底部采集栏）
local panel_        = nil
local visible_      = false
local factoryMgr_   = nil
local manager_      = nil

-- 当前标签页 "craft" | "orders"
local currentTab_ = "craft"

-- 动态容器
local contentContainer_   = nil
local levelBar_           = nil
local levelLabel_         = nil

local tabBtns_            = {}

-- 底部栏容器
local gatherBtnContainer_ = nil
local inventoryContainer_ = nil
local gatherRateLabel_    = nil   -- 采集按钮上的成功率文字

-- 刷新指纹
local lastFingerprint_ = ""
local lastBottomFP_    = ""      -- 底部栏结构指纹（可见物品列表）
local bottomItemRefs_  = {}      -- { [itemId] = countLabel } 底部物品数量 Label 缓存

-- 增量更新缓存
local craftBuilt_       = false   -- 合成页是否已构建骨架
local craftRecipeCards_  = {}     -- { [recipeId] = { panel, iconLabel, nameLabel, matLabel } }
local craftRecipeGrid_   = nil
local craftQueueCards_   = {}     -- { { panel, iconLabel, nameLabel, barFill, pctLabel, waitLabel } }
local craftQueueGrid_    = nil
local craftQueueTitle_   = nil
local craftQueueTitleLabel_ = nil
local craftQueueSep_     = nil
-- craftNoRecipeLabel_ 已移除，提示文本直接在配方网格内动态创建
local craftNextUnlock_   = nil
local craftNextUnlockLabel_ = nil
local lastRecipeIds_     = ""     -- 可用配方ID拼接，变化时重建配方网格
local lastQueueCount_    = -1     -- 队列长度变化时重建队列网格

-- 订单页底部固定栏 & 刷新倒计时
local orderFooter_       = nil
local orderStreakLabel_   = nil
local orderTimerLabel_   = nil   -- 刷新倒计时（在订单列表上方，随内容滚动）

-- ============================================================================
-- 颜色
-- ============================================================================

local C_BG      = { 28, 32, 45, 245 }
local C_TEXT    = { 220, 220, 240, 255 }
local C_DIM     = { 140, 140, 160, 200 }
local C_GOLD    = { 255, 215, 0, 255 }
local C_GREEN   = { 80, 220, 120, 255 }
local C_RED     = { 220, 80, 80, 255 }
local C_BLUE    = { 100, 160, 255, 255 }
local C_ORANGE  = { 255, 160, 60, 255 }
local C_PURPLE  = { 180, 130, 255, 255 }
local C_CYAN    = { 80, 200, 200, 255 }

-- ============================================================================
-- 前向声明
-- ============================================================================
local BuildPanel, RebuildContent, RebuildCraft, RebuildOrders
local RebuildLevelBar, RebuildBottomBar, UpdateBottomCounts, UpdateCraft, BuildCraftSkeleton

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 创建图标面板（用图片替代 emoji）
local function IconPanel(iconPath, size)
    size = size or 24
    return UI.Panel {
        width = size, height = size, flexShrink = 0,
        backgroundImage = iconPath,
        backgroundFit = "contain",
        pointerEvents = "none",
    }
end

local function FormatCoins(v)
    return GameState.FormatNumber(v)
end

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 60 then
        local m = math.floor(seconds / 60)
        local s = seconds % 60
        return string.format("%d:%02d", m, s)
    end
    return string.format("%ds", seconds)
end

-- ============================================================================
-- 初始化
-- ============================================================================

function FP.Init(root, gm)
    uiRoot_ = root
    manager_ = gm
    factoryMgr_ = require("core.FactoryManager")
    BuildPanel()
end

-- ============================================================================
-- 显示 / 隐藏
-- ============================================================================

function FP.Show()
    if not overlay_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    lastFingerprint_ = ""
    lastBottomFP_ = ""
    bottomItemRefs_ = {}
    -- 重置合成页缓存
    craftBuilt_ = false
    craftRecipeCards_ = {}
    craftQueueCards_ = {}
    lastRecipeIds_ = ""
    lastQueueCount_ = -1
    uiRoot_:AddChild(overlay_)
    FP.Refresh()
end

function FP.Hide()
    if not overlay_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(overlay_)
end

function FP.Toggle()
    if visible_ then FP.Hide() else FP.Show() end
end

function FP.IsVisible()
    return visible_
end

-- ============================================================================
-- 刷新
-- ============================================================================

function FP.Refresh()
    if not visible_ or not factoryMgr_ then return end

    -- ── 右侧抽屉指纹 ──
    local fp = {}
    fp[#fp + 1] = "tab" .. currentTab_
    fp[#fp + 1] = "lv" .. factoryMgr_.GetFactoryLevel()
    fp[#fp + 1] = "xp" .. factoryMgr_.GetFactoryXP()
    fp[#fp + 1] = "st" .. factoryMgr_.GetStreak()
    fp[#fp + 1] = "td" .. factoryMgr_.GetTotalDelivered()
    fp[#fp + 1] = "o" .. #factoryMgr_.GetOrders()

    local cq = factoryMgr_.GetCraftQueue()
    for i, c in ipairs(cq) do
        fp[#fp + 1] = "cq" .. i .. c.recipeId
    end
    fp[#fp + 1] = "cqn" .. #cq

    -- 合成页：仅追踪材料是否满足配方（粗粒度），精确数量由 UpdateCraft 增量更新
    local inv = factoryMgr_.GetInventory()
    local recipes = factoryMgr_.GetAvailableRecipes()
    local matBits = {}
    for _, r in ipairs(recipes) do
        local ok = true
        for iid, need in pairs(r.inputs) do
            if (inv[iid] or 0) < need then ok = false; break end
        end
        matBits[#matBits + 1] = r.id .. (ok and "1" or "0")
    end
    fp[#fp + 1] = "mat" .. table.concat(matBits, "")

    local fpStr = table.concat(fp, "|")
    local fpChanged = fpStr ~= lastFingerprint_
    if fpChanged then
        lastFingerprint_ = fpStr
        RebuildLevelBar()
        RebuildContent()
    elseif currentTab_ == "craft" and craftBuilt_ and #cq > 0 then
        -- 指纹没变但有合成队列在进行中，增量更新进度条
        UpdateCraft()
    end

    -- ── 订单页底部固定栏 + 刷新倒计时（每帧更新，不受指纹限制） ──
    local isOrders = currentTab_ == "orders"
    if orderFooter_ then
        orderFooter_:SetStyle({
            height = isOrders and "auto" or 0,
            overflow = isOrders and "visible" or "hidden",
        })
        if isOrders then
            local streak = factoryMgr_.GetStreak()
            if streak > 0 then
                local activeBuff = nil
                for _, sr in ipairs(FC.STREAK_REWARDS) do
                    if streak >= sr.threshold then activeBuff = sr end
                end
                local stxt = "连续交付 x" .. streak
                if activeBuff then
                    local pct = math.floor((activeBuff.buff.mul - 1) * 100 + 0.5)
                    stxt = stxt .. " " .. activeBuff.buff.name .. " +" .. pct .. "%"
                end
                orderStreakLabel_:SetStyle({ text = stxt, fontColor = streak >= 5 and C_GOLD or (streak >= 3 and C_GREEN or C_DIM) })
            else
                orderStreakLabel_:SetStyle({ text = "" })
            end
        end
    end
    -- 刷新倒计时（在滚动内容中，每帧更新文本）
    if isOrders and orderTimerLabel_ then
        local timer = math.ceil(factoryMgr_.GetOrderRefreshTimer())
        orderTimerLabel_:SetStyle({ text = "下次刷新 " .. FormatTime(timer) })
    end

    -- ── 底部栏：结构指纹（可见物品列表） + 增量数量更新 ──
    local lvl = factoryMgr_.GetFactoryLevel()
    local bfp = {}
    bfp[#bfp + 1] = "lv" .. lvl
    for _, item in ipairs(FC.items) do
        local c = inv[item.id] or 0
        local unlocked = lvl >= item.unlockLevel
        if unlocked or c > 0 then
            bfp[#bfp + 1] = item.id
        end
    end
    local bfpStr = table.concat(bfp, "|")
    if bfpStr ~= lastBottomFP_ then
        -- 可见物品列表变化（解锁新物品等） → 全量重建网格
        lastBottomFP_ = bfpStr
        RebuildBottomBar()
    else
        -- 结构没变 → 只更新数量文本
        UpdateBottomCounts()
    end
end

-- ============================================================================
-- 等级条
-- ============================================================================

RebuildLevelBar = function()
    if not levelBar_ or not levelLabel_ or not factoryMgr_ then return end

    local lv = factoryMgr_.GetFactoryLevel()
    local xp = factoryMgr_.GetFactoryXP()
    local needed = factoryMgr_.GetXPForNextLevel()
    local isMax = lv >= FC.MAX_FACTORY_LEVEL

    levelLabel_:SetStyle({
        text = isMax and ("Lv." .. lv .. " MAX") or ("Lv." .. lv .. "  " .. xp .. "/" .. needed),
        fontColor = isMax and C_GOLD or C_TEXT,
    })

    local pct = isMax and 100 or (needed > 0 and math.floor(xp / needed * 100) or 0)
    levelBar_:SetStyle({ width = pct .. "%" })
end



-- ============================================================================
-- 标签页切换
-- ============================================================================

local function SetTab(tabName)
    if currentTab_ == tabName then return end
    -- 切换标签时重置合成页缓存
    craftBuilt_ = false
    craftRecipeCards_ = {}
    craftQueueCards_ = {}
    lastRecipeIds_ = ""
    lastQueueCount_ = -1
    currentTab_ = tabName
    lastFingerprint_ = ""
    FP.Refresh()
end

-- ============================================================================
-- 内容区域根据标签页重建
-- ============================================================================

RebuildContent = function()
    if not contentContainer_ then return end

    for name, btn in pairs(tabBtns_) do
        local active = name == currentTab_
        btn:SetStyle({
            backgroundColor = active and { 50, 60, 80, 255 } or { 35, 38, 50, 255 },
            borderColor = active and C_BLUE or { 60, 60, 70, 120 },
        })
    end

    if currentTab_ == "craft" then
        -- 合成页：增量更新
        if not craftBuilt_ then
            contentContainer_:RemoveAllChildren()
            BuildCraftSkeleton()
            craftBuilt_ = true
        end
        UpdateCraft()
    elseif currentTab_ == "orders" then
        -- 切换到订单页时，重置合成页状态
        craftBuilt_ = false
        craftRecipeCards_ = {}
        craftQueueCards_ = {}
        lastRecipeIds_ = ""
        lastQueueCount_ = -1
        contentContainer_:RemoveAllChildren()
        RebuildOrders()
    end
end

-- ============================================================================
-- 底部栏：采集按钮 + 物品网格
-- ============================================================================

RebuildBottomBar = function()
    if not gatherBtnContainer_ or not inventoryContainer_ or not factoryMgr_ then return end

    -- ── 采集按钮区（只更新文字，不重建） ──
    local rate = factoryMgr_.GetGatherSuccessRate()
    if gatherRateLabel_ then
        gatherRateLabel_:SetStyle({ text = math.floor(rate * 100) .. "%" })
    end

    -- ── 物品网格（全量重建，缓存 Label 引用） ──
    inventoryContainer_:RemoveAllChildren()
    bottomItemRefs_ = {}
    local inv = factoryMgr_.GetInventory()
    local lvl = factoryMgr_.GetFactoryLevel()

    for tier = 1, 5 do
        local tierItems = FC.GetItemsByTier(tier)
        local showTier = false
        for _, item in ipairs(tierItems) do
            if lvl >= item.unlockLevel or (inv[item.id] or 0) > 0 then
                showTier = true
                break
            end
        end

        if showTier then
            for _, item in ipairs(tierItems) do
                local count = inv[item.id] or 0
                local unlocked = lvl >= item.unlockLevel
                if unlocked or count > 0 then
                    local countLabel = UI.Label {
                        text = count > 0 and tostring(count) or (unlocked and "0" or "🔒"),
                        fontSize = 9,
                        fontColor = count > 0 and C_TEXT or C_DIM,
                    }
                    local cellPanel = UI.Panel {
                        width = 48, height = 42,
                        flexDirection = "column", alignItems = "center", justifyContent = "center",
                        borderRadius = 4,
                        backgroundColor = count > 0 and { 45, 50, 65, 255 } or { 35, 38, 48, 255 },
                        borderWidth = 1,
                        borderColor = count > 0 and { 70, 80, 110, 150 } or { 50, 50, 60, 80 },
                        gap = 1,
                        children = {
                            IconPanel(item.icon, 22),
                            countLabel,
                        },
                    }
                    inventoryContainer_:AddChild(cellPanel)
                    bottomItemRefs_[item.id] = { label = countLabel, panel = cellPanel, unlocked = unlocked }
                end
            end
        end
    end
end

-- ============================================================================
-- 底部栏增量更新：只更新数量文本和背景色
-- ============================================================================

UpdateBottomCounts = function()
    if not factoryMgr_ then return end

    -- 采集成功率
    local rate = factoryMgr_.GetGatherSuccessRate()
    if gatherRateLabel_ then
        gatherRateLabel_:SetStyle({ text = math.floor(rate * 100) .. "%" })
    end

    -- 物品数量
    local inv = factoryMgr_.GetInventory()
    for itemId, ref in pairs(bottomItemRefs_) do
        local count = inv[itemId] or 0
        ref.label:SetStyle({
            text = count > 0 and tostring(count) or (ref.unlocked and "0" or "🔒"),
            fontColor = count > 0 and C_TEXT or C_DIM,
        })
        ref.panel:SetStyle({
            backgroundColor = count > 0 and { 45, 50, 65, 255 } or { 35, 38, 48, 255 },
            borderColor = count > 0 and { 70, 80, 110, 150 } or { 50, 50, 60, 80 },
        })
    end
end

-- ============================================================================
-- 合成页 —— 骨架构建（只调用一次）
-- ============================================================================

BuildCraftSkeleton = function()
    if not contentContainer_ or not factoryMgr_ then return end

    -- 标题
    contentContainer_:AddChild(UI.Label {
        text = "合成配方",
        fontSize = 11, fontColor = C_PURPLE,
        marginBottom = 2,
    })

    -- 配方网格（无配方提示在 UpdateCraft 中动态添加到网格内）
    craftRecipeGrid_ = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 3,
        marginBottom = 4,
    }
    contentContainer_:AddChild(craftRecipeGrid_)

    -- 下一个解锁提示（Panel 包裹确保 display 切换可靠）
    craftNextUnlockLabel_ = UI.Label {
        text = "",
        fontSize = 9, fontColor = C_DIM,
    }
    craftNextUnlock_ = UI.Panel {
        width = "100%", marginBottom = 4,
        children = { craftNextUnlockLabel_ },
    }
    contentContainer_:AddChild(craftNextUnlock_)

    -- 队列分隔线
    craftQueueSep_ = UI.Panel {
        width = "100%", height = 1,
        backgroundColor = { 80, 75, 100, 60 },
        marginBottom = 4,
    }
    contentContainer_:AddChild(craftQueueSep_)

    -- 队列标题（Panel 包裹确保 display 切换可靠）
    craftQueueTitleLabel_ = UI.Label {
        text = "合成中",
        fontSize = 11, fontColor = C_BLUE,
    }
    craftQueueTitle_ = UI.Panel {
        width = "100%", marginBottom = 2,
        children = { craftQueueTitleLabel_ },
    }
    contentContainer_:AddChild(craftQueueTitle_)

    -- 队列网格
    craftQueueGrid_ = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 3,
    }
    contentContainer_:AddChild(craftQueueGrid_)
end

-- ============================================================================
-- 合成页 —— 增量更新（每帧调用，只更新变化的属性）
-- ============================================================================

UpdateCraft = function()
    if not contentContainer_ or not factoryMgr_ then return end

    local craftQueue = factoryMgr_.GetCraftQueue()
    local inv = factoryMgr_.GetInventory()
    local lvl = factoryMgr_.GetFactoryLevel()
    local recipes = factoryMgr_.GetAvailableRecipes()

    -- ── 配方列表变化检测（解锁新配方时才重建卡片） ──
    local rids = {}
    for _, r in ipairs(recipes) do rids[#rids + 1] = r.id end
    local ridStr = table.concat(rids, ",")

    if ridStr ~= lastRecipeIds_ then
        lastRecipeIds_ = ridStr
        -- 配方列表变了，重建配方网格中的卡片
        craftRecipeGrid_:RemoveAllChildren()
        craftRecipeCards_ = {}

        -- 无配方时直接在网格内显示提示
        if #recipes == 0 then
            craftRecipeGrid_:AddChild(UI.Label {
                text = "暂无可用配方，提升等级解锁",
                fontSize = 10, fontColor = C_DIM,
                marginTop = 2, marginBottom = 4, width = "100%", textAlign = "center",
            })
        end

        for _, recipe in ipairs(recipes) do
            local outputItem = FC.itemMap[recipe.output]
            if outputItem then
                local iconLbl = IconPanel(outputItem.icon, 28)
                local nameLbl = UI.Label { text = outputItem.name, fontSize = 9, fontColor = C_TEXT }
                local matLbl  = UI.Label { text = "", fontSize = 7, fontColor = C_DIM }

                local card = UI.Panel {
                    width = "23%",
                    flexDirection = "column",
                    alignItems = "center",
                    justifyContent = "center",
                    borderRadius = 5,
                    backgroundColor = { 38, 40, 52, 255 },
                    borderWidth = 1,
                    borderColor = { 55, 58, 70, 100 },
                    paddingTop = 4, paddingBottom = 4,
                    gap = 1,
                    pointerEvents = "auto",
                    onTap = (function(rid)
                        return function(self, event)
                            if event and event.stopPropagation then event:stopPropagation() end
                            local inv2 = factoryMgr_.GetInventory()
                            local cq2 = factoryMgr_.GetCraftQueue()
                            if #cq2 >= FC.MAX_CRAFT_QUEUE then return end
                            local r = FC.recipeMap[rid]
                            if not r then return end
                            for iid, need in pairs(r.inputs) do
                                if (inv2[iid] or 0) < need then return end
                            end
                            factoryMgr_.StartCraft(rid)
                            lastFingerprint_ = ""
                            FP.Refresh()
                        end
                    end)(recipe.id),
                    children = { iconLbl, nameLbl, matLbl },
                }
                craftRecipeGrid_:AddChild(card)
                craftRecipeCards_[recipe.id] = {
                    panel = card,
                    matLabel = matLbl,
                    recipeId = recipe.id,
                }
            end
        end
    end

    -- ── 增量更新每张配方卡片的状态 ──
    for _, recipe in ipairs(recipes) do
        local cc = craftRecipeCards_[recipe.id]
        if cc then
            local matOk = true
            local matParts = { FormatTime(recipe.time) }
            for inputId, need in pairs(recipe.inputs) do
                local has = inv[inputId] or 0
                if has < need then matOk = false end
                local inputItem = FC.itemMap[inputId]
                matParts[#matParts + 1] = (inputItem and inputItem.name or inputId) .. "×" .. need
            end
            local canCraft = matOk and #craftQueue < FC.MAX_CRAFT_QUEUE

            cc.panel:SetStyle({
                backgroundColor = canCraft and { 40, 55, 65, 255 } or { 38, 40, 52, 255 },
                borderColor = canCraft and { 80, 160, 200, 180 } or { 55, 58, 70, 100 },
            })
            cc.matLabel:SetStyle({
                text = table.concat(matParts, " "),
                fontColor = matOk and C_DIM or C_RED,
            })
        end
    end

    -- ── 下一个解锁配方 ──
    local nextRecipe = nil
    for _, r in ipairs(FC.recipes) do
        if lvl < r.unlockLevel then
            nextRecipe = r
            break
        end
    end
    if craftNextUnlock_ then
        if nextRecipe then
            local outItem = FC.itemMap[nextRecipe.output]
            craftNextUnlockLabel_:SetStyle({
                text = "Lv." .. nextRecipe.unlockLevel .. " 解锁: " .. (outItem and outItem.name or nextRecipe.id),
            })
            craftNextUnlock_:SetStyle({ height = "auto", overflow = "visible" })
        else
            craftNextUnlock_:SetStyle({ height = 0, overflow = "hidden" })
        end
    end

    -- ── 合成队列 ──
    local qc = #craftQueue
    local hasQueue = qc > 0

    -- 显示/隐藏队列区域（用 height 切换代替 display 切换）
    if craftQueueSep_ then craftQueueSep_:SetStyle({ height = hasQueue and 1 or 0 }) end
    if craftQueueTitle_ then
        craftQueueTitleLabel_:SetStyle({
            text = "合成中 (" .. qc .. "/" .. FC.MAX_CRAFT_QUEUE .. ")",
        })
        craftQueueTitle_:SetStyle({ height = hasQueue and "auto" or 0, overflow = hasQueue and "visible" or "hidden" })
    end
    if craftQueueGrid_ then craftQueueGrid_:SetStyle({ height = hasQueue and "auto" or 0, overflow = hasQueue and "visible" or "hidden" }) end

    -- 队列数量变化时，重建队列卡片
    if qc ~= lastQueueCount_ then
        lastQueueCount_ = qc
        craftQueueGrid_:RemoveAllChildren()
        craftQueueCards_ = {}

        for i, craft in ipairs(craftQueue) do
            local recipe = FC.recipeMap[craft.recipeId]
            if recipe then
                local item = FC.itemMap[recipe.output]
                local isFirst = i == 1

                local iconLbl = item and IconPanel(item.icon, 28) or UI.Label { text = "?", fontSize = 18 }
                local nameLbl = UI.Label { text = item and item.name or recipe.id, fontSize = 9, fontColor = C_TEXT }

                local barFill = UI.Panel {
                    width = "0%", height = "100%",
                    backgroundColor = C_CYAN,
                    borderRadius = 2,
                }
                local barContainer = UI.Panel {
                    width = "80%", height = 4,
                    borderRadius = 2,
                    backgroundColor = { 35, 38, 50, 255 },
                    overflow = "hidden",
                    marginTop = 2,
                    children = { barFill },
                }
                local waitLbl = UI.Label { text = "等待", fontSize = 7, fontColor = C_DIM }
                local pctLbl = UI.Label { text = "", fontSize = 7, fontColor = C_CYAN }

                local card = UI.Panel {
                    width = "23%",
                    flexDirection = "column",
                    alignItems = "center",
                    justifyContent = "center",
                    borderRadius = 5,
                    backgroundColor = isFirst and { 40, 50, 55, 255 } or { 35, 38, 48, 255 },
                    borderWidth = 1,
                    borderColor = isFirst and { 80, 160, 180, 150 } or { 50, 55, 65, 80 },
                    paddingTop = 4, paddingBottom = 4,
                    gap = 1,
                    pointerEvents = "auto",
                    onTap = (function(idx)
                        return function(self, event)
                            if event and event.stopPropagation then event:stopPropagation() end
                            factoryMgr_.CancelCraft(idx)
                            lastFingerprint_ = ""
                            FP.Refresh()
                        end
                    end)(i),
                    children = {
                        iconLbl,
                        nameLbl,
                        isFirst and barContainer or waitLbl,
                        pctLbl,
                    },
                }
                craftQueueGrid_:AddChild(card)
                craftQueueCards_[i] = {
                    panel = card,
                    barFill = barFill,
                    pctLabel = pctLbl,
                    isFirst = isFirst,
                }
            end
        end
    end

    -- ── 增量更新队列卡片进度 ──
    for i, craft in ipairs(craftQueue) do
        local cc = craftQueueCards_[i]
        if cc then
            local pct = math.min(100, math.floor(craft.elapsed / math.max(0.1, craft.totalTime) * 100))
            if cc.isFirst then
                cc.barFill:SetStyle({ width = pct .. "%" })
                cc.pctLabel:SetStyle({ text = pct .. "%" })
            end
        end
    end
end

-- keep old name as alias (not used but safe)
RebuildCraft = function()
    if craftBuilt_ then
        UpdateCraft()
    else
        BuildCraftSkeleton()
        craftBuilt_ = true
        UpdateCraft()
    end
end

-- ============================================================================
-- 订单页
-- ============================================================================

RebuildOrders = function()
    if not contentContainer_ or not factoryMgr_ then return end

    local orders = factoryMgr_.GetOrders()
    local inv = factoryMgr_.GetInventory()

    -- 刷新倒计时（订单列表上方）
    local timer = math.ceil(factoryMgr_.GetOrderRefreshTimer())
    orderTimerLabel_ = UI.Label {
        text = "下次刷新 " .. FormatTime(timer),
        fontSize = 9, fontColor = C_DIM,
        width = "100%", textAlign = "right",
        marginBottom = 2,
    }
    contentContainer_:AddChild(orderTimerLabel_)

    if #orders == 0 then
        contentContainer_:AddChild(UI.Label {
            text = "暂无订单，等待刷新...",
            fontSize = 10, fontColor = C_DIM,
            width = "100%", textAlign = "center", marginTop = 8,
        })
        return
    end

    for i, order in ipairs(orders) do
        local def = FC.orderMap[order.orderId]
        if not def then goto continue end

        local matOk = true
        local matChildren = {}
        for itemId, need in pairs(def.items) do
            local has = inv[itemId] or 0
            local enough = has >= need
            if not enough then matOk = false end
            local item = FC.itemMap[itemId]
            matChildren[#matChildren + 1] = UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 2,
                children = {
                    item and IconPanel(item.icon, 14) or nil,
                    UI.Label {
                        text = (item and item.name or itemId) .. " " .. has .. "/" .. need,
                        fontSize = 9,
                        fontColor = enough and C_DIM or C_RED,
                    },
                },
            }
        end

        local reward = math.max(GameState.coinsPerSecond, 1) * def.cpsSeconds
        local tierColors = { C_DIM, C_CYAN, C_BLUE, C_PURPLE, C_GOLD }
        local tierColor = tierColors[def.tier] or C_DIM

        contentContainer_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "column",
            paddingLeft = 6, paddingRight = 6,
            paddingTop = 5, paddingBottom = 5,
            borderRadius = 5,
            backgroundColor = { 40, 42, 55, 255 },
            borderWidth = 1,
            borderColor = { 70, 75, 95, 120 },
            gap = 3,
            marginBottom = 3,
            children = {
                UI.Panel {
                    width = "100%",
                    flexDirection = "row", alignItems = "center",
                    justifyContent = "space-between",
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 4,
                            flex = 1, flexShrink = 1,
                            children = {
                                IconPanel(def.icon, 22),
                                UI.Label { text = def.name, fontSize = 10, fontColor = C_TEXT },
                                UI.Label { text = "T" .. def.tier, fontSize = 8, fontColor = tierColor },
                            },
                        },
                        UI.Panel {
                            paddingLeft = 10, paddingRight = 10,
                            paddingTop = 5, paddingBottom = 5,
                            borderRadius = 4,
                            backgroundColor = matOk and { 40, 65, 40, 255 } or { 45, 45, 50, 255 },
                            borderWidth = 1,
                            borderColor = matOk and { 80, 180, 80, 180 } or { 60, 60, 70, 100 },
                            pointerEvents = "auto",
                            onTap = (function(idx)
                                return function(self, event)
                                    if event and event.stopPropagation then event:stopPropagation() end
                                    if factoryMgr_.FulfillOrder(idx) then
                                        lastFingerprint_ = ""
                                        FP.Refresh()
                                    end
                                end
                            end)(i),
                            children = {
                                UI.Label {
                                    text = matOk and "交付" or "不足",
                                    fontSize = 10,
                                    fontColor = matOk and C_GREEN or C_DIM,
                                },
                            },
                        },
                    },
                },
                UI.Panel {
                    width = "100%",
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        UI.Label { text = "+" .. FormatCoins(reward), fontSize = 10, fontColor = C_GOLD },
                        UI.Label { text = "+" .. def.xp .. "XP", fontSize = 9, fontColor = C_CYAN },
                    },
                },
                UI.Panel {
                    width = "100%",
                    flexDirection = "row", flexWrap = "wrap", gap = 6,
                    children = matChildren,
                },
            },
        })
        ::continue::
    end
end

-- ============================================================================
-- 构建面板骨架
-- ============================================================================

BuildPanel = function()
    local dpr = graphics:GetDPR()
    local logicalW = graphics:GetWidth() / dpr
    local drawerW = math.floor(logicalW * 0.3)

    -- ── 右侧抽屉 ──

    levelLabel_ = UI.Label {
        text = "Lv.0  0/100",
        fontSize = 10, fontColor = C_TEXT,
    }

    local levelBarBg = UI.Panel {
        width = "100%", height = 4,
        borderRadius = 2,
        backgroundColor = { 35, 38, 50, 255 },
        overflow = "hidden",
    }
    levelBar_ = UI.Panel {
        width = "0%", height = "100%",
        backgroundColor = C_CYAN,
        borderRadius = 2,
    }
    levelBarBg:AddChild(levelBar_)

    local function MakeTabBtn(name, label)
        local btn = UI.Panel {
            flex = 1,
            paddingTop = 5, paddingBottom = 5,
            borderRadius = 4,
            backgroundColor = { 35, 38, 50, 255 },
            borderWidth = 1,
            borderColor = { 60, 60, 70, 120 },
            justifyContent = "center", alignItems = "center",
            pointerEvents = "auto",
            onTap = function(self, event)
                if event and event.stopPropagation then event:stopPropagation() end
                SetTab(name)
            end,
            children = {
                UI.Label { text = label, fontSize = 10, fontColor = C_TEXT },
            },
        }
        tabBtns_[name] = btn
        return btn
    end

    contentContainer_ = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 2,
    }

    -- 订单页底部固定栏（仅连续交付，居中）
    orderStreakLabel_ = UI.Label {
        text = "",
        fontSize = 9, fontColor = C_DIM,
    }
    orderFooter_ = UI.Panel {
        width = "100%", flexShrink = 0,
        justifyContent = "center", alignItems = "center",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 4,
        borderColor = { 60, 60, 80, 80 },
        borderWidth = { 1, 0, 0, 0 },
        height = 0, overflow = "hidden",
        children = { orderStreakLabel_ },
    }

    panel_ = UI.Panel {
        width = "100%", flex = 1, flexShrink = 1,
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
                marginBottom = 3,
                paddingLeft = 6, paddingRight = 4,
                children = {
                    UI.Label {
                        text = "制造工厂",
                        fontSize = 15,
                        fontColor = C_BLUE,
                    },
                    UI.Panel {
                        paddingLeft = 8, paddingRight = 8,
                        paddingTop = 4, paddingBottom = 4,
                        borderRadius = 4,
                        backgroundColor = { 60, 40, 40, 255 },
                        pointerEvents = "auto",
                        onTap = function() FP.Hide() end,
                        children = {
                            UI.Label { text = "✕", fontSize = 14, fontColor = C_TEXT },
                        },
                    },
                },
            },
            -- 等级条
            UI.Panel {
                width = "100%", gap = 2,
                marginBottom = 3,
                paddingLeft = 6, paddingRight = 6,
                children = {
                    levelLabel_,
                    levelBarBg,
                },
            },
            -- 标签栏（合成 / 订单）
            UI.Panel {
                width = "100%",
                flexDirection = "row", gap = 4,
                paddingLeft = 4, paddingRight = 4,
                marginBottom = 4,
                children = {
                    MakeTabBtn("craft", "合成"),
                    MakeTabBtn("orders", "订单"),
                },
            },
            -- 可滚动内容区域
            UI.Panel {
                width = "100%", flex = 1, flexShrink = 1,
                overflow = "scroll",
                scrollbarInteractive = false,
                paddingLeft = 4, paddingRight = 4,
                paddingBottom = 4,
                children = { contentContainer_ },
            },
            -- 订单页底部固定栏
            orderFooter_,
        },
    }

    -- ── 面板底部：材料网格 + 采集按钮行 ──

    inventoryContainer_ = UI.Panel {
        width = "100%",
        flex = 1, flexShrink = 1,
        flexDirection = "row",
        flexWrap = "wrap",
        alignItems = "center",
        alignContent = "flex-start",
        gap = 2,
        paddingLeft = 4, paddingRight = 4,
        paddingTop = 3, paddingBottom = 3,
        overflow = "scroll",
    }

    local initRate = factoryMgr_ and math.floor(factoryMgr_.GetGatherSuccessRate() * 100) or 95
    gatherRateLabel_ = UI.Label {
        text = initRate .. "%",
        fontSize = 10,
        fontColor = C_DIM,
    }

    gatherBtnContainer_ = UI.Panel {
        width = "100%",
        height = 32, flexShrink = 0,
        flexDirection = "row",
        justifyContent = "center", alignItems = "center",
        gap = 8,
        backgroundColor = { 35, 50, 40, 255 },
        borderRadius = 4,
        marginLeft = 4, marginRight = 4, marginBottom = 4,
        pointerEvents = "auto",
        onTap = function(self, event)
            if event and event.stopPropagation then event:stopPropagation() end
            if factoryMgr_ then
                factoryMgr_.Gather()
                lastBottomFP_ = ""
                lastFingerprint_ = ""
                FP.Refresh()
            end
        end,
        children = {
            UI.Label { text = "采集", fontSize = 13, fontColor = C_GREEN },
            gatherRateLabel_,
        },
    }

    local bottomSection = UI.Panel {
        width = "100%",
        height = 120, flexShrink = 0,
        flexDirection = "column",
        borderColor = { 80, 130, 200, 120 },
        borderWidth = { 1, 0, 0, 0 },
        children = {
            inventoryContainer_,
            gatherBtnContainer_,
        },
    }

    overlay_ = UI.Panel {
        position = "absolute",
        top = 0,
        right = "30%",
        width = drawerW,
        height = "100%",
        zIndex = 100,
        backgroundColor = C_BG,
        borderColor = { 80, 130, 200, 120 },
        borderWidth = { 0, 1, 0, 1 },
        pointerEvents = "auto",
        children = { panel_, bottomSection },
    }
end

return FP
