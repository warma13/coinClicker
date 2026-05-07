-- ============================================================================
-- core/ShipmentManager.lua
-- 货运航线 —— 国际物流(#9)小游戏管理器
-- ============================================================================

local GameState = require("core.GameState")
local SC = require("config.ShipmentConfig")
local Buildings = require("config.Buildings")
local SaveBridge = require("core.SaveBridge")

local SM = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

---@class ShipmentCargoInst
---@field defId string           货物类型 id
---@field routeId string         航线 id
---@field name string
---@field icon string
---@field reward number          基础奖励 CPS 秒数
---@field insured boolean        是否购买保险
---@field delayed boolean        是否已延误
---@field startTime number       发货时间戳
---@field travelTime number      实际运输时间
---@field elapsed number         已运输时间

-- 待发货物列表（可选择发送的货物）
local pendingCargos_ = {}
-- 运输中列表
local inTransit_ = {}
-- 连续安全送达计数
local safeStreak_ = 0
-- 累计送达次数（成就用）
local totalShipped_ = 0
-- 自动刷新计时
local refreshTimer_ = 0

-- 回调
local onDeliver_ = nil
local onDelay_ = nil
local onRefresh_ = nil

-- ============================================================================
-- 辅助
-- ============================================================================

--- 获取国际物流建筑数量
local function GetShipmentCount()
    for _, b in ipairs(Buildings.buildings) do
        if b.id == SC.BUILDING_ID then return b.count end
    end
    return 0
end

--- 计算运输时间
local function CalcTravelTime(cargoDef, routeDef)
    return cargoDef.travelTime * routeDef.timeMul
end

--- 计算奖励
local function CalcReward(cargoDef, routeDef)
    local cps = math.max(GameState.coinsPerSecond, 1)
    return math.floor(cps * cargoDef.cpsSeconds * routeDef.rewardMul)
end

--- 检查是否延误
local function CheckDelay(cargoDef, routeDef)
    local chance = routeDef.delayChance
    if cargoDef.hazard then
        chance = chance + SC.HAZARD_DELAY_EXTRA
    end
    return math.random() < chance
end

-- ============================================================================
-- 货物生成 & 刷新
-- ============================================================================

--- 生成一批待发货物
local function GeneratePendingCargos()
    local count = GetShipmentCount()
    local slots = SC.GetRouteSlots(count)

    -- 保留正在运输中的数量
    local transitCount = #inTransit_
    local pendingSlots = math.max(1, slots - transitCount)

    pendingCargos_ = {}
    for i = 1, pendingSlots do
        local def = SC.RandomCargo()
        -- 随机分配航线
        local routeIdx = math.random(1, #SC.routes)
        local route = SC.routes[routeIdx]
        pendingCargos_[i] = {
            defId = def.id,
            routeId = route.id,
            name = def.name,
            icon = def.icon,
            routeName = route.name,
            routeIcon = route.icon,
            travelTime = CalcTravelTime(def, route),
            cpsSeconds = def.cpsSeconds,
            rewardMul = route.rewardMul,
            hazard = def.hazard or false,
            buff = def.buff,
        }
    end
    refreshTimer_ = SC.CARGO_REFRESH_INTERVAL
end

-- ============================================================================
-- 公共 API
-- ============================================================================

function SM.Init()
    GeneratePendingCargos()

    SaveBridge.Register("shipment", SM.GetSaveData, SM.LoadSaveData)
end

function SM.Update(dt)
    -- 更新运输中货物
    local i = 1
    while i <= #inTransit_ do
        local cargo = inTransit_[i]
        cargo.elapsed = cargo.elapsed + dt

        if cargo.elapsed >= cargo.travelTime then
            -- 到达目的地
            local cargoDef = SC.cargoMap[cargo.defId]
            local routeDef = SC.routeMap[cargo.routeId]

            totalShipped_ = totalShipped_ + 1

            if cargo.delayed and not cargo.insured then
                -- 延误且未保险：奖励减半
                local reward = math.floor(CalcReward(cargoDef, routeDef) * 0.5)
                GameState.coins = GameState.coins + reward
                safeStreak_ = 0
                if onDeliver_ then onDeliver_(cargo, reward, true) end
            else
                -- 正常送达或有保险
                local reward = CalcReward(cargoDef, routeDef)
                GameState.coins = GameState.coins + reward
                safeStreak_ = safeStreak_ + 1

                -- 检查连续安全送达奖励
                for _, sr in ipairs(SC.STREAK_REWARDS) do
                    if safeStreak_ == sr.threshold then
                        local buff = {
                            id = sr.buff.id,
                            name = sr.buff.name or sr.buff.id,
                            icon = "🚚",
                            color = { 120, 180, 220, 255 },
                            duration = sr.buff.duration,
                            remaining = sr.buff.duration,
                            multiplierKey = "cps",
                            multiplierVal = sr.buff.mul,
                        }
                        GameState.activeBuffs[#GameState.activeBuffs + 1] = buff
                    end
                end

                -- 货物自带 buff
                if cargoDef and cargoDef.buff then
                    local b = cargoDef.buff
                    GameState.activeBuffs[#GameState.activeBuffs + 1] = {
                        id = b.id, name = b.name or b.id,
                        icon = "📦", color = { 160, 140, 100, 255 },
                        duration = b.duration, remaining = b.duration,
                        multiplierKey = "cps", multiplierVal = b.mul,
                    }
                end

                if onDeliver_ then onDeliver_(cargo, reward, false) end
            end

            table.remove(inTransit_, i)
        else
            -- 运输途中检查延误（仅在 50% 进度时检查一次）
            if not cargo.delayChecked and cargo.elapsed >= cargo.travelTime * 0.5 then
                cargo.delayChecked = true
                local cargoDef = SC.cargoMap[cargo.defId]
                local routeDef = SC.routeMap[cargo.routeId]
                if cargoDef and routeDef and CheckDelay(cargoDef, routeDef) then
                    cargo.delayed = true
                    cargo.travelTime = cargo.travelTime * (1 + SC.DELAY_TIME_ADD)
                    if onDelay_ then onDelay_(cargo) end
                end
            end
            i = i + 1
        end
    end

    -- 待发货物自动刷新
    refreshTimer_ = refreshTimer_ - dt
    if refreshTimer_ <= 0 then
        GeneratePendingCargos()
        if onRefresh_ then onRefresh_() end
    end
end

--- 发送货物（从待发列表中选择一个发送）
---@param pendingIndex number
---@param insured boolean
function SM.ShipCargo(pendingIndex, insured)
    if pendingIndex < 1 or pendingIndex > #pendingCargos_ then return end

    local count = GetShipmentCount()
    local maxRoutes = SC.GetRouteSlots(count)
    if #inTransit_ >= maxRoutes then return end

    local pending = pendingCargos_[pendingIndex]
    local cargoDef = SC.cargoMap[pending.defId]

    -- 运输成本（必须支付）
    local shippingCost = 0
    if cargoDef and cargoDef.investCpsMul then
        shippingCost = math.max(GameState.coinsPerSecond, 1) * cargoDef.investCpsMul
    end

    -- 保险费
    local insuranceCost = 0
    if insured then
        insuranceCost = math.max(GameState.coinsPerSecond, 1) * SC.INSURANCE_CPS_MUL
    end

    local totalCost = shippingCost + insuranceCost
    if GameState.coins < totalCost then return end
    GameState.coins = GameState.coins - totalCost

    local transit = {
        defId = pending.defId,
        routeId = pending.routeId,
        name = pending.name,
        icon = pending.icon,
        routeName = pending.routeName,
        routeIcon = pending.routeIcon,
        travelTime = pending.travelTime,
        cpsSeconds = pending.cpsSeconds,
        rewardMul = pending.rewardMul,
        hazard = pending.hazard,
        buff = pending.buff,
        insured = insured,
        delayed = false,
        delayChecked = false,
        elapsed = 0,
        startTime = os.time(),
    }

    inTransit_[#inTransit_ + 1] = transit
    table.remove(pendingCargos_, pendingIndex)
end

--- 加急运输
---@param transitIndex number
function SM.ExpressShipment(transitIndex)
    if transitIndex < 1 or transitIndex > #inTransit_ then return end

    local expressCost = math.max(GameState.coinsPerSecond, 1) * SC.EXPRESS_CPS_MUL
    if GameState.coins < expressCost then return end

    GameState.coins = GameState.coins - expressCost
    local cargo = inTransit_[transitIndex]
    cargo.travelTime = cargo.travelTime * SC.EXPRESS_TIME_MUL
end

--- 获取待发货物列表
function SM.GetPendingCargos()
    return pendingCargos_
end

--- 获取运输中列表
function SM.GetInTransit()
    return inTransit_
end

--- 获取安全送达连击数
function SM.GetSafeStreak()
    return safeStreak_
end

--- 获取累计送达次数
function SM.GetTotalShipped()
    return totalShipped_
end

--- 获取刷新剩余时间
function SM.GetRefreshTimer()
    return refreshTimer_
end

-- ============================================================================
-- 回调设置
-- ============================================================================

function SM.SetOnDeliver(fn) onDeliver_ = fn end
function SM.SetOnDelay(fn) onDelay_ = fn end
function SM.SetOnRefresh(fn) onRefresh_ = fn end

-- ============================================================================
-- 存档
-- ============================================================================

function SM.GetSaveData()
    return {
        pending = pendingCargos_,
        transit = inTransit_,
        streak = safeStreak_,
        totalShipped = totalShipped_,
        refreshTimer = refreshTimer_,
    }
end

function SM.LoadSaveData(data)
    if not data then return end
    pendingCargos_ = data.pending or {}
    inTransit_ = data.transit or {}
    safeStreak_ = data.streak or 0
    totalShipped_ = data.totalShipped or 0
    refreshTimer_ = data.refreshTimer or SC.CARGO_REFRESH_INTERVAL

    -- 恢复 delayChecked 字段
    for _, c in ipairs(inTransit_) do
        if c.delayChecked == nil then c.delayChecked = false end
    end

    -- 如果待发列表为空，自动生成
    if #pendingCargos_ == 0 then
        GeneratePendingCargos()
    end
end

function SM.ResetForAscension()
    pendingCargos_ = {}
    inTransit_ = {}
    safeStreak_ = 0
    totalShipped_ = 0
    refreshTimer_ = 0
    GeneratePendingCargos()
end

return SM
