-- ============================================================================
-- core/ECommerceManager.lua
-- 限时秒杀 —— 商品上架、秒杀倒计时、投资结算、促销连击
-- ============================================================================

local EC = require("config.ECommerceConfig")
local Buildings = require("config.Buildings")
local GameState = require("core.GameState")
local SaveBridge = require("core.SaveBridge")

--- 向全局 buff 列表添加一个 CPS 倍率 buff（同 id 叠加时间）
---@param buffDef table { id, name, mul, duration }
local function ApplyBuff(buffDef)
    for _, existing in ipairs(GameState.activeBuffs) do
        if existing.id == buffDef.id then
            existing.remaining = existing.remaining + buffDef.duration
            existing.duration = math.max(existing.duration, buffDef.duration)
            return
        end
    end
    GameState.activeBuffs[#GameState.activeBuffs + 1] = {
        id = buffDef.id,
        name = buffDef.name or buffDef.id,
        icon = "🌀",
        color = { 180, 100, 220, 255 },
        remaining = buffDef.duration,
        duration = buffDef.duration,
        multiplierKey = "cps",
        multiplierVal = buffDef.mul,
    }
end

local EM = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

---@class ECommerceProduct
---@field itemId string          商品类型 id
---@field state string           "available" | "invested" | "sold" | "expired"
---@field saleTime number        秒杀总时长（秒）
---@field elapsed number         已过时间
---@field investCost number      进货成本（投资时锁定）
---@field profit number          利润（投资时锁定）
---@field isHot boolean          是否爆款
---@field adBoosted boolean      是否已广告推广

---@type ECommerceProduct[]
local products_ = {}           -- 当前可见商品列表
local streak_ = 0              -- 连续成功计数
local totalSold_ = 0
local refreshTimer_ = 0       -- 商品自动刷新计时器

-- 回调
local onSold_ = nil            -- function(product, profit, streakBuff)
local onExpired_ = nil         -- function(product)
local onRefresh_ = nil         -- function()

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 获取电商平台数量
---@return number
local function GetPortalCount()
    for _, b in ipairs(Buildings.buildings) do
        if b.id == EC.BUILDING_ID then
            return b.count
        end
    end
    return 0
end

--- 获取当前促销等级折扣（基于连续成功）
---@return number discount (0-1)
---@return string|nil label
local function GetPromoDiscount()
    local discount = 0
    local label = nil
    for _, tier in ipairs(EC.PROMO_TIERS) do
        if streak_ >= tier.threshold then
            discount = tier.discount
            label = tier.label
        end
    end
    return discount, label
end

--- 创建一个新的随机商品
---@return ECommerceProduct
local function CreateRandomProduct()
    local def = EC.RandomItem()
    local isHot = math.random() < def.hotChance

    -- 计算成本和利润（加法叠加：profit = base × (1 + hotBonus + adBonus)）
    local discount, _ = GetPromoDiscount()
    local investCost = GameState.coinsPerSecond * def.investCpsMul * (1 - discount)
    local baseProfit = GameState.coinsPerSecond * def.profitCpsMul
    local bonusMul = 1.0
    if isHot then
        bonusMul = bonusMul + EC.HOT_BONUS
    end
    local profit = baseProfit * bonusMul

    ---@type ECommerceProduct
    local product = {
        itemId = def.id,
        state = "available",
        saleTime = def.saleTime,
        elapsed = 0,
        investCost = investCost,
        profit = profit,
        baseProfit = baseProfit,  -- 保存基础利润，广告加成时使用
        isHot = isHot,
        adBoosted = false,
    }

    return product
end

--- 填充商品槽至上限
local function FillProducts()
    local maxSlots = EC.GetItemSlots(GetPortalCount())
    while #products_ < maxSlots do
        products_[#products_ + 1] = CreateRandomProduct()
    end
end

-- ============================================================================
-- 初始化
-- ============================================================================

function EM.Init()
    products_ = {}
    streak_ = 0
    totalSold_ = 0
    refreshTimer_ = EC.ITEM_REFRESH_INTERVAL
    FillProducts()

    SaveBridge.Register("ecommerce", EM.GetSaveData, EM.LoadSaveData, function()
        products_ = {}
        streak_ = 0
        totalSold_ = 0
        refreshTimer_ = EC.ITEM_REFRESH_INTERVAL
        FillProducts()
    end)
end

-- ============================================================================
-- 回调设置
-- ============================================================================

function EM.SetOnSold(fn) onSold_ = fn end
function EM.SetOnExpired(fn) onExpired_ = fn end
function EM.SetOnRefresh(fn) onRefresh_ = fn end

-- ============================================================================
-- 查询接口
-- ============================================================================

function EM.GetProducts() return products_ end
function EM.GetStreak() return streak_ end
function EM.GetTotalSold() return totalSold_ end
function EM.GetPromoInfo() return GetPromoDiscount() end

function EM.GetMaxSlots()
    return EC.GetItemSlots(GetPortalCount())
end

function EM.IsUnlocked()
    return GetPortalCount() >= 1
end

function EM.GetRefreshTimer()
    return refreshTimer_
end

-- ============================================================================
-- 核心操作
-- ============================================================================

--- 投资（进货）一个商品，开始秒杀倒计时
---@param productIndex number  products_ 中的索引
---@return boolean success
function EM.InvestProduct(productIndex)
    if productIndex < 1 or productIndex > #products_ then return false end
    local product = products_[productIndex]
    if product.state ~= "available" then return false end

    -- 重新计算成本（基于当前 CPS 和促销折扣）
    local def = EC.itemMap[product.itemId]
    if not def then return false end

    local discount, _ = GetPromoDiscount()
    local cost = GameState.coinsPerSecond * def.investCpsMul * (1 - discount)

    if GameState.coins < cost then return false end

    GameState.coins = GameState.coins - cost
    product.investCost = cost
    product.baseProfit = GameState.coinsPerSecond * def.profitCpsMul
    local bonusMul = 1.0
    if product.isHot then
        bonusMul = bonusMul + EC.HOT_BONUS
    end
    if product.adBoosted then
        bonusMul = bonusMul + EC.AD_BONUS
    end
    product.profit = product.baseProfit * bonusMul

    product.state = "invested"
    product.elapsed = 0

    return true
end

--- 广告推广一个已投资的商品（延长秒杀时间）
---@param productIndex number
---@return boolean success
function EM.AdBoostProduct(productIndex)
    if productIndex < 1 or productIndex > #products_ then return false end
    local product = products_[productIndex]
    if product.state ~= "invested" then return false end
    if product.adBoosted then return false end

    local cost = GameState.coinsPerSecond * EC.AD_BOOST_CPS_MUL
    if GameState.coins < cost then return false end

    GameState.coins = GameState.coins - cost
    product.adBoosted = true
    -- 推广增加利润（加法叠加，基于 baseProfit 重算）
    local bonusMul = 1.0 + EC.AD_BONUS
    if product.isHot then
        bonusMul = bonusMul + EC.HOT_BONUS
    end
    product.profit = (product.baseProfit or product.profit) * bonusMul

    return true
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

function EM.Update(dt)
    local portalCount = GetPortalCount()
    if portalCount < 1 then return end

    local changed = false

    -- 更新已投资商品的秒杀倒计时
    for i = #products_, 1, -1 do
        local product = products_[i]
        if product.state == "invested" then
            product.elapsed = product.elapsed + dt
            if product.elapsed >= product.saleTime then
                -- 秒杀成功！
                product.state = "sold"
                local profit = product.profit
                GameState.coins = GameState.coins + profit

                streak_ = streak_ + 1
                totalSold_ = totalSold_ + 1

                -- 检查连续成功 buff
                local streakBuff = nil
                for _, sr in ipairs(EC.STREAK_REWARDS) do
                    if streak_ == sr.threshold then
                        ApplyBuff(sr.buff)
                        streakBuff = sr.buff
                    end
                end

                -- 商品自带 buff
                local def = EC.itemMap[product.itemId]
                if def and def.buff then
                    ApplyBuff(def.buff)
                end

                if onSold_ then onSold_(product, profit, streakBuff) end

                -- 标记为已售，保留空位等刷新
                changed = true
            end
        elseif product.state == "available" then
            -- 未投资的商品不会自己过期，等待刷新定时器处理
        end
    end

    -- 商品自动刷新（替换未投资/已售/过期的商品）
    refreshTimer_ = refreshTimer_ - dt
    if refreshTimer_ <= 0 then
        refreshTimer_ = EC.ITEM_REFRESH_INTERVAL
        local refreshed = false
        for i = #products_, 1, -1 do
            local st = products_[i].state
            if st == "available" or st == "sold" or st == "expired" then
                table.remove(products_, i)
                refreshed = true
            end
        end
        -- 补充空位
        FillProducts()
        if refreshed or #products_ < EC.GetItemSlots(GetPortalCount()) then
            if onRefresh_ then onRefresh_() end
        end
    end
end

-- ============================================================================
-- 存档 / 读档
-- ============================================================================

function EM.GetSaveData()
    local productsData = {}
    for i, p in ipairs(products_) do
        productsData[i] = {
            iid = p.itemId,
            st = p.state,
            stm = p.saleTime,
            el = p.elapsed,
            ic = p.investCost,
            pr = p.profit,
            bp = p.baseProfit,
            hot = p.isHot,
            ab = p.adBoosted,
        }
    end

    return {
        products = productsData,
        streak = streak_,
        totalSold = totalSold_,
        refreshTimer = refreshTimer_,
    }
end

function EM.LoadSaveData(data)
    if not data then return end

    streak_ = data.streak or 0
    totalSold_ = data.totalSold or 0
    refreshTimer_ = data.refreshTimer or EC.ITEM_REFRESH_INTERVAL

    products_ = {}
    if data.products then
        for _, pd in ipairs(data.products) do
            local profit = pd.pr or 0
            products_[#products_ + 1] = {
                itemId = pd.iid or "daily",
                state = pd.st or "available",
                saleTime = pd.stm or 20,
                elapsed = pd.el or 0,
                investCost = pd.ic or 0,
                profit = profit,
                baseProfit = pd.bp or profit,  -- 兼容旧存档：无 bp 时用 profit
                isHot = pd.hot or false,
                adBoosted = pd.ab or false,
            }
        end
    end

    -- 移除已过期或已售的，补充空位
    for i = #products_, 1, -1 do
        if products_[i].state == "sold" or products_[i].state == "expired" then
            table.remove(products_, i)
        end
    end
    FillProducts()
end

function EM.ResetForAscension()
    EM.Init()
end

return EM
