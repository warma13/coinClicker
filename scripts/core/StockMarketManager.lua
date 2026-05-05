-- ============================================================================
-- core/StockMarketManager.lua
-- 证券交易所核心逻辑：价格波动、买卖交易、经纪人、贷款、存档
-- 对应 Cookie Clicker 的 Stock Market 小游戏
-- 绑定建筑：商业银行（id="bank"，index 6）
-- ============================================================================

local GameState = require("core.GameState")
local SC        = require("config.StockMarketConfig")

local SM = {}

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------

-- 每只商品的实时状态
---@class StockGoodState
---@field value number     当前价格 ($)
---@field delta number     CC delta 累积量（每 tick 衰减 + 累加）
---@field mode number      当前波动模式 SC.MODE_*
---@field modeTimer number 当前模式剩余 tick 数
---@field owned number     持有数量
---@field totalBought number 本轮累计买入金额（用于损益计算）
---@field totalSold number   本轮累计卖出金额
---@field history number[] 最近价格历史（用于趋势图）

local goodStates_ = {}   ---@type StockGoodState[]

-- 经纪人
local brokerCount_ = 0

-- 办公室等级
local officeLevel_ = 0

-- 贷款状态
---@class LoanState
---@field active boolean
---@field boostRemaining number
---@field penaltyRemaining number
local loanStates_ = {}   ---@type LoanState[]

-- 计时器
local tickTimer_ = 0

-- 本轮飞升最高无 buff CPS（$1 的价值）
local peakCPS_ = 0

-- 历史长度上限
local MAX_HISTORY = 60

-- 总利润
local totalProfit_ = 0

-- 回调
local onTradeComplete_ = nil    ---@type fun()|nil
local onTickUpdate_ = nil       ---@type fun()|nil

-- ---------------------------------------------------------------------------
-- 内部工具
-- ---------------------------------------------------------------------------

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

--- 获取建筑数量
---@param buildingId string
---@return number
local function GetBuildingCount(buildingId)
    local Buildings = require("config.Buildings")
    for _, b in ipairs(Buildings.buildings) do
        if b.id == buildingId then return b.count end
    end
    return 0
end

--- 获取建筑等级（通过 SugarLumpManager）
---@param buildingId string
---@return number
local function GetBuildingLevel(buildingId)
    local Buildings = require("config.Buildings")
    local SLM = require("core.SugarLumpManager")
    for i, b in ipairs(Buildings.buildings) do
        if b.id == buildingId then
            return SLM.GetBuildingLevel(i)
        end
    end
    return 0
end

--- 按 CC 原版权重随机选择波动模式
---@return number mode
---@return number duration (tick 数)
local function RandomMode()
    local roll = math.random(1, SC.MODE_TOTAL_WEIGHT)
    local cumulative = 0
    local mode = SC.MODE_STABLE
    for m, w in pairs(SC.MODE_WEIGHTS) do
        cumulative = cumulative + w
        if roll <= cumulative then
            mode = m
            break
        end
    end
    local dur = math.random(SC.MODE_SWITCH_MIN, SC.MODE_SWITCH_MAX)
    return mode, dur
end

--- 初始化单只商品
---@param goodIndex number 1-based
---@return StockGoodState
local function InitGoodState(goodIndex)
    local bankLevel = GetBuildingLevel("bank")
    local resting = SC.GetRestingValue(goodIndex, bankLevel)
    local startVal = resting * (0.8 + math.random() * 0.4) -- 静息值 ±20%
    local mode, dur = RandomMode()
    return {
        value = math.max(1, startVal),
        delta = 0,
        mode = mode,
        modeTimer = dur,
        owned = 0,
        totalBought = 0,
        totalSold = 0,
        history = { startVal },
    }
end

-- ---------------------------------------------------------------------------
-- 初始化
-- ---------------------------------------------------------------------------

function SM.Init()
    goodStates_ = {}
    for i = 1, #SC.goods do
        goodStates_[i] = InitGoodState(i)
    end
    brokerCount_ = 0
    officeLevel_ = 0
    tickTimer_ = 0
    totalProfit_ = 0
    peakCPS_ = math.max(peakCPS_, GameState.coinsPerSecond)

    loanStates_ = {}
    for i = 1, #SC.loans do
        loanStates_[i] = { active = false, boostRemaining = 0, penaltyRemaining = 0 }
    end
end

-- ---------------------------------------------------------------------------
-- 回调
-- ---------------------------------------------------------------------------

function SM.SetOnTradeComplete(fn) onTradeComplete_ = fn end
function SM.SetOnTickUpdate(fn) onTickUpdate_ = fn end

-- ---------------------------------------------------------------------------
-- 查询接口
-- ---------------------------------------------------------------------------

--- 是否已解锁
---@return boolean
function SM.IsUnlocked()
    return GetBuildingCount("bank") >= 1
end

--- 获取银行等级
---@return number
function SM.GetBankLevel()
    return GetBuildingLevel("bank")
end

--- 获取商品状态
---@param goodIndex number 1-based
---@return StockGoodState|nil
function SM.GetGoodState(goodIndex)
    return goodStates_[goodIndex]
end

--- 获取所有商品状态
---@return StockGoodState[]
function SM.GetAllGoodStates()
    return goodStates_
end

--- $1 的实际金币价值
---@return number
function SM.GetDollarValue()
    return math.max(1, peakCPS_)
end

--- 获取当前手续费率
---@return number 0.0 ~ 0.20
function SM.GetOverhead()
    local oh = SC.BASE_OVERHEAD
    for _ = 1, brokerCount_ do
        oh = oh * SC.BROKER_OVERHEAD_MUL
    end
    return oh
end

--- 获取经纪人数量
---@return number
function SM.GetBrokerCount()
    return brokerCount_
end

--- 获取经纪人上限（CC: grandmaCount/10 + grandmaLevel）
---@return number
function SM.GetMaxBrokers()
    local grandmaCount = GetBuildingCount("grandma")
    local grandmaLevel = GetBuildingLevel("grandma")
    return math.floor(grandmaCount / 10) + grandmaLevel
end

--- 获取经纪人雇佣成本（$）— CC: 第 n 个 = $1200 * n
---@return number
function SM.GetBrokerCostDollars()
    return SC.BROKER_BASE_COST * (brokerCount_ + 1)
end

--- 获取经纪人雇佣成本（金币）
---@return number
function SM.GetBrokerCostCoins()
    return SM.GetBrokerCostDollars() * SM.GetDollarValue()
end

--- 获取办公室等级
---@return number
function SM.GetOfficeLevel()
    return officeLevel_
end

--- 获取商品仓位上限
---@param goodIndex number 1-based
---@return number
function SM.GetMaxStock(goodIndex)
    local good = SC.goods[goodIndex]
    if not good then return 0 end

    local bCount = GetBuildingCount(good.buildingId)
    local office = SC.GetOffice(officeLevel_)
    local perBuilding = (office.storagePerBuilding or SC.BASE_STORAGE_PER_BUILDING)
    return math.floor(bCount * perBuilding) + (office.storagePlus or 0)
end

--- 获取 tick 倒计时
---@return number 剩余秒数
function SM.GetTickTimer()
    return math.max(0, SC.TICK_INTERVAL - tickTimer_)
end

--- 获取总利润
---@return number
function SM.GetTotalProfit()
    return totalProfit_
end

--- 获取贷款状态
---@param loanIndex number 1~3
---@return LoanState|nil
function SM.GetLoanState(loanIndex)
    return loanStates_[loanIndex]
end

--- 获取可用贷款槽数
---@return number
function SM.GetAvailableLoanSlots()
    local office = SC.GetOffice(officeLevel_)
    return office.loanSlots or 0
end

--- 获取 CPS 贷款乘数
---@return number
function SM.GetLoanCPSMultiplier()
    local mul = 1.0
    for i, ls in ipairs(loanStates_) do
        if ls.active then
            local loanDef = SC.loans[i]
            if loanDef then
                if ls.boostRemaining > 0 then
                    mul = mul * loanDef.boostMul
                elseif ls.penaltyRemaining > 0 then
                    mul = mul * loanDef.penaltyMul
                end
            end
        end
    end
    return mul
end

-- ---------------------------------------------------------------------------
-- 操作接口
-- ---------------------------------------------------------------------------

--- 买入商品
---@param goodIndex number 1-based
---@param qty number 买入数量
---@return boolean success
---@return string|nil reason
function SM.Buy(goodIndex, qty)
    local gs = goodStates_[goodIndex]
    if not gs then return false, "invalid" end
    if qty <= 0 then return false, "invalid_qty" end

    local maxStock = SM.GetMaxStock(goodIndex)
    local canBuy = maxStock - gs.owned
    if canBuy <= 0 then return false, "full" end
    qty = math.min(qty, canBuy)

    local overhead = SM.GetOverhead()
    local dollarVal = SM.GetDollarValue()
    local costPerUnit = gs.value * dollarVal * (1 + overhead)
    local totalCost = costPerUnit * qty

    if GameState.coins < totalCost then
        -- 尝试买更少的
        qty = math.floor(GameState.coins / costPerUnit)
        if qty <= 0 then return false, "no_money" end
        totalCost = costPerUnit * qty
    end

    GameState.coins = GameState.coins - totalCost
    gs.owned = gs.owned + qty
    gs.totalBought = gs.totalBought + totalCost

    if onTradeComplete_ then onTradeComplete_() end
    return true
end

--- 卖出商品
---@param goodIndex number 1-based
---@param qty number 卖出数量
---@return boolean success
---@return string|nil reason
function SM.Sell(goodIndex, qty)
    local gs = goodStates_[goodIndex]
    if not gs then return false, "invalid" end
    if qty <= 0 then return false, "invalid_qty" end

    qty = math.min(qty, gs.owned)
    if qty <= 0 then return false, "none_owned" end

    local dollarVal = SM.GetDollarValue()
    local revenue = gs.value * dollarVal * qty

    GameState.coins = GameState.coins + revenue
    gs.owned = gs.owned - qty
    gs.totalSold = gs.totalSold + revenue
    totalProfit_ = totalProfit_ + revenue

    if onTradeComplete_ then onTradeComplete_() end
    return true
end

--- 雇佣经纪人
---@return boolean success
---@return string|nil reason
function SM.HireBroker()
    if brokerCount_ >= SM.GetMaxBrokers() then
        return false, "max_reached"
    end
    local cost = SM.GetBrokerCostCoins()
    if GameState.coins < cost then
        return false, "no_money"
    end
    GameState.coins = GameState.coins - cost
    brokerCount_ = brokerCount_ + 1
    return true
end

--- 升级办公室
---@return boolean success
---@return string|nil reason
function SM.UpgradeOffice()
    local next = SC.GetNextOffice(officeLevel_)
    if not next then return false, "max_level" end

    local cursorCount = GetBuildingCount("cursor")
    local cursorLevel = GetBuildingLevel("cursor")

    if cursorCount < next.cursorReq then
        return false, "need_cursors"
    end
    if cursorLevel < next.cursorLevel then
        return false, "need_cursor_level"
    end

    -- 办公室升级消耗对应数量的临时工（降低 count 但不退款）
    local Buildings = require("config.Buildings")
    for _, b in ipairs(Buildings.buildings) do
        if b.id == "cursor" then
            b.count = math.max(0, b.count - next.cursorReq)
            break
        end
    end

    officeLevel_ = next.level
    return true
end

--- 申请贷款
---@param loanIndex number 1~3
---@return boolean success
---@return string|nil reason
function SM.TakeLoan(loanIndex)
    local loanDef = SC.loans[loanIndex]
    if not loanDef then return false, "invalid" end

    -- 检查槽位
    if loanIndex > SM.GetAvailableLoanSlots() then
        return false, "slot_locked"
    end

    local ls = loanStates_[loanIndex]
    if not ls then return false, "invalid" end
    if ls.active then return false, "already_active" end

    -- 支付首付
    local downpayment = GameState.coins * loanDef.downpayment
    if GameState.coins < downpayment then
        return false, "no_money"
    end
    GameState.coins = GameState.coins - downpayment

    ls.active = true
    ls.boostRemaining = loanDef.boostDur
    ls.penaltyRemaining = loanDef.penaltyDur

    if onTradeComplete_ then onTradeComplete_() end
    return true
end

-- ---------------------------------------------------------------------------
-- 价格 Tick 更新
-- ---------------------------------------------------------------------------

--- 执行一次价格 tick（CC 原版 delta 模型）
local function DoTick()
    local bankLevel = GetBuildingLevel("bank")

    for i, gs in ipairs(goodStates_) do
        -- 模式倒计时
        gs.modeTimer = gs.modeTimer - 1
        if gs.modeTimer <= 0 then
            gs.mode, gs.modeTimer = RandomMode()
        end

        -- 获取模式参数
        local params = SC.MODE_PARAMS[gs.mode] or SC.MODE_PARAMS[SC.MODE_STABLE]

        -- 1) delta 衰减（CC: delta *= 1 - deltaDecay - DELTA_DECAY）
        gs.delta = gs.delta * (1 - params.deltaDecay - SC.DELTA_DECAY)

        -- 2) delta 累加随机值（CC: delta += random(deltaLo, deltaHi)）
        gs.delta = gs.delta + params.deltaLo + math.random() * (params.deltaHi - params.deltaLo)

        -- 3) 价格直接随机偏移（CC: value += random(valueLo, valueHi)）
        gs.value = gs.value + params.valueLo + math.random() * (params.valueHi - params.valueLo)

        -- 4) delta 应用到价格
        gs.value = gs.value + gs.delta

        -- 5) 向静息值回归（CC: 每 tick 1% 趋向静息值）
        local resting = SC.GetRestingValue(i, bankLevel)
        gs.value = gs.value + (resting - gs.value) * 0.01

        -- 6) 天花板机制（CC: 超过静息值且 delta>0 时，delta 额外衰减 10%）
        if gs.value > resting and gs.delta > 0 then
            gs.delta = gs.delta * (1 - SC.MARKET_CAP_DECAY)
        end

        -- 7) 低价保护（CC: 价格 < $5 时，每 tick 加 (5-value)/2）
        if gs.value < SC.LOW_PRICE_THRESHOLD then
            gs.value = gs.value + (SC.LOW_PRICE_THRESHOLD - gs.value) * 0.5
        end

        -- 8) 最低价格不低于 1
        gs.value = math.max(1, gs.value)

        -- 记录历史
        gs.history[#gs.history + 1] = gs.value
        if #gs.history > MAX_HISTORY then
            table.remove(gs.history, 1)
        end
    end
end

-- ---------------------------------------------------------------------------
-- 帧更新
-- ---------------------------------------------------------------------------

function SM.Update(dt)
    if not SM.IsUnlocked() then return end

    -- 更新 peakCPS
    -- 使用无 buff 的基础 CPS（近似：用当前 CPS）
    if GameState.coinsPerSecond > peakCPS_ then
        peakCPS_ = GameState.coinsPerSecond
    end

    -- tick 计时器
    tickTimer_ = tickTimer_ + dt
    if tickTimer_ >= SC.TICK_INTERVAL then
        tickTimer_ = tickTimer_ - SC.TICK_INTERVAL
        DoTick()
        if onTickUpdate_ then onTickUpdate_() end
    end

    -- 贷款倒计时
    for i, ls in ipairs(loanStates_) do
        if ls.active then
            if ls.boostRemaining > 0 then
                ls.boostRemaining = math.max(0, ls.boostRemaining - dt)
            elseif ls.penaltyRemaining > 0 then
                ls.penaltyRemaining = math.max(0, ls.penaltyRemaining - dt)
                if ls.penaltyRemaining <= 0 then
                    ls.active = false
                end
            else
                ls.active = false
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 存档
-- ---------------------------------------------------------------------------

---@return table
function SM.GetSaveData()
    local goods = {}
    for i, gs in ipairs(goodStates_) do
        goods[i] = {
            v = gs.value,
            d = gs.delta,
            m = gs.mode,
            mt = gs.modeTimer,
            o = gs.owned,
            tb = gs.totalBought,
            ts = gs.totalSold,
            h = gs.history,
        }
    end

    local loans = {}
    for i, ls in ipairs(loanStates_) do
        if ls.active then
            loans[i] = {
                br = ls.boostRemaining,
                pr = ls.penaltyRemaining,
            }
        end
    end

    return {
        goods = goods,
        brokers = brokerCount_,
        office = officeLevel_,
        tick = tickTimer_,
        peak = peakCPS_,
        profit = totalProfit_,
        loans = loans,
    }
end

---@param data table|nil
function SM.LoadSaveData(data)
    if not data then
        SM.Init()
        return
    end

    brokerCount_ = data.brokers or 0
    officeLevel_ = data.office or 0
    tickTimer_ = data.tick or 0
    peakCPS_ = data.peak or 0
    totalProfit_ = data.profit or 0

    -- 恢复商品状态
    goodStates_ = {}
    for i = 1, #SC.goods do
        if data.goods and data.goods[i] then
            local gd = data.goods[i]
            goodStates_[i] = {
                value = gd.v or 10,
                delta = gd.d or 0,
                mode = gd.m or SC.MODE_STABLE,
                modeTimer = gd.mt or 300,
                owned = gd.o or 0,
                totalBought = gd.tb or 0,
                totalSold = gd.ts or 0,
                history = gd.h or { gd.v or 10 },
            }
        else
            goodStates_[i] = InitGoodState(i)
        end
    end

    -- 恢复贷款
    loanStates_ = {}
    for i = 1, #SC.loans do
        if data.loans and data.loans[i] then
            local ld = data.loans[i]
            loanStates_[i] = {
                active = true,
                boostRemaining = ld.br or 0,
                penaltyRemaining = ld.pr or 0,
            }
        else
            loanStates_[i] = { active = false, boostRemaining = 0, penaltyRemaining = 0 }
        end
    end

    print("[StockMarketManager] 存档加载完成 (brokers=" .. brokerCount_
        .. ", office=" .. officeLevel_ .. ")")
end

--- 飞升重置（CC: 股票市场进度不跨飞升）
function SM.ResetForAscension()
    SM.Init()
    print("[StockMarketManager] 飞升重置")
end

return SM
