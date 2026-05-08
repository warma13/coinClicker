-- ============================================================================
-- core/GameState.lua
-- 中央可变状态 + 纯工具函数
-- 所有模块通过 require 获取同一个表引用，修改即时共享
-- ============================================================================

local State = {
    -- 金币数量
    coins = 0,
    -- 历史最高金币（用于排行榜上传）
    maxCoins = 0,

    -- 累计点击次数
    totalClicks = 0,

    -- 点击公式: clickBase + cpsPercent * CpS + fingerBonus
    clickBase = 1,
    coinsPerClick = 1,

    -- 鼠标升级线: 点击时额外获得 CpS 的百分比
    cpsPercent = 0,
    -- 手指升级线: 每个非光标建筑带来的点击加成
    fingerBonus = 0,

    -- 每秒自动产出
    coinsPerSecond = 0,
    -- 全局 CPS 倍率（建筑基础产出之上的全局乘法，由 ProductionCalculator 计算）
    globalCpsMul = 1,

    -- 幸运金币升级倍率
    luckyClicks = 0,     -- 累计点击幸运金币次数
    luckyFreqMul = 1,    -- 出现频率倍率（Lucky Day / Serendipity）
    luckyStayMul = 1,    -- 停留时间倍率（Lucky Day / Serendipity）
    luckyDurMul = 1,     -- 效果持续时间倍率（Get Lucky）

    -- Buff 系统
    -- 格式: { {id, name, icon, color, remaining, duration, multiplierKey, multiplierVal} }
    activeBuffs = {},
    buffCpsMul = 1,
    buffCpcMul = 1,
    buffBuildingCostMul = 1,

    -- 幸运金币
    luckyActive = false,
    luckyTimer = 0,
    luckyLifetime = 0,
    luckyMaxLife = 13,
    luckyMinInterval = 300,
    luckyMaxInterval = 900,
    luckyPosX = 0,
    luckyPosY = 0,
    luckyFloatPhase = 0,
    luckySize = 56,

    -- 手动签单累计产出
    handmadeCoins = 0,

    -- 黑洞累计消灭数
    wrinklersPopped = 0,

    -- ======== 排行榜追踪 ========
    leaderboard = {
        totalPlayers    = 0,        -- 排行榜总人数
        myRank          = 0,        -- 我的当前排名（0=未上榜）
        bestRank        = 0,        -- 历史最佳排名（0=未上榜）
        bestPercent     = 100,      -- 历史最佳百分比（100=未上榜）
        rank1Time       = 0,        -- 在第1名的累计秒数
        rank1Reached    = false,    -- 是否到达过第1名
        top10pReached   = false,    -- 是否到达过前10%
        top1pReached    = false,    -- 是否到达过前1%
        top50pReached   = false,    -- 是否到达过前50%
        top3Reached     = false,    -- 是否到达过前3名
        top10Reached    = false,    -- 是否到达过前10名
    },

    -- 效果提示计时
    effectLabelTimer = 0,

    -- 光标自动点击计时器
    cursorTimer = 0,

    -- 技能系统（全部主动技能，带 cooldown/active/timer）
    skills = {
        speedClick    = { level = 0, active = false, timer = 0 },
        cpsDouble     = { level = 0, active = false, timer = 0 },
    },

    -- UI 刷新节流
    lastRefreshCoins = -1,
    buffRefreshCooldown = 0,

    -- 点击频率限制（对齐 Cookie Clicker: 最多 15 CPS）
    lastClickTime = 0,            -- 上次有效点击时间（秒，来自 time.elapsedTime）
    clickMinInterval = 1 / 15,    -- 最小点击间隔 ≈ 0.0667 秒

    -- 点击动画
    coinScale = 1.0,
    coinScaleTarget = 1.0,

    -- 体力系统
    stamina = 0,             -- 当前体力
    staminaMax = 300,        -- 体力上限
    staminaRegenRate = 300 / 86400, -- 每秒恢复体力（24小时回满300）

    -- 设置（音量等）
    settings = {
        bgmVolume = 0.4,
        sfxVolume = 1.0,
    },
}

-- ============================================================================
-- 纯工具函数
-- ============================================================================

--- 数字后缀表（从高到低排列，每项 = {阈值, 后缀}）
--- K(10³) → UVg(10⁶⁶)，共 22 级
local NUMBER_SUFFIXES = {
    { 1e66, "UVg" },  -- Unvigintillion
    { 1e63, "Vg" },   -- Vigintillion
    { 1e60, "Nd" },   -- Novemdecillion
    { 1e57, "Od" },   -- Octodecillion
    { 1e54, "Spd" },  -- Septendecillion
    { 1e51, "Sxd" },  -- Sexdecillion
    { 1e48, "Qid" },  -- Quindecillion
    { 1e45, "Qad" },  -- Quattuordecillion
    { 1e42, "Td" },   -- Tredecillion
    { 1e39, "Dd" },   -- Duodecillion
    { 1e36, "Ud" },   -- Undecillion
    { 1e33, "De" },   -- Decillion
    { 1e30, "No" },   -- Nonillion
    { 1e27, "Oc" },   -- Octillion
    { 1e24, "Sp" },   -- Septillion
    { 1e21, "Sx" },   -- Sextillion
    { 1e18, "Qi" },   -- Quintillion
    { 1e15, "Qa" },   -- Quadrillion
    { 1e12, "T" },    -- Trillion
    { 1e9,  "B" },    -- Billion
    { 1e6,  "M" },    -- Million
    { 1e3,  "K" },    -- Thousand
}

--- 格式化大数字显示
---@param n number
---@return string
function State.FormatNumber(n)
    if n ~= n then return "NaN" end       -- NaN 防御
    if n == math.huge then return "Inf" end
    if n == -math.huge then return "-Inf" end
    if n < 0 then return "-" .. State.FormatNumber(-n) end

    for _, entry in ipairs(NUMBER_SUFFIXES) do
        if n >= entry[1] then
            return string.format("%.1f%s", n / entry[1], entry[2])
        end
    end

    -- 小于 1000：整数不带 .0，有小数保留一位
    if n == math.floor(n) then
        return string.format("%.0f", n)
    else
        return string.format("%.1f", n)
    end
end

--- 安全取整：小数时用 math.floor，大数时保持浮点避免 int64 溢出
--- Lua 5.4 的 math.floor 会将 float 转为 integer，超过 2^63 溢出为负数
local MAX_SAFE_INT = 2^53  -- double 精确整数上限
---@param n number
---@return number
function State.SafeFloor(n)
    if n < MAX_SAFE_INT then
        return math.floor(n)
    end
    -- 大数：用浮点截断（精度已经丢失，floor 无意义）
    return n - (n % 1)
end

--- 计算建筑/升级的当前购买价格
--- Price(N) = floor(BaseCost × costMul^N)
---@param item table 建筑或升级数据
---@return number
function State.GetCost(item)
    return State.SafeFloor(item.baseCost * (item.costMul ^ item.count))
end

--- 计算批量购买 amount 个建筑的总费用
--- 等比数列求和: sum = baseCost * costMul^count * (costMul^amount - 1) / (costMul - 1)
---@param item table 建筑数据
---@param amount number 购买数量
---@return number totalCost 总费用
function State.GetBulkCost(item, amount)
    if amount <= 1 then return State.GetCost(item) end
    local r = item.costMul
    local total = 0.0
    if r == 1 then
        total = item.baseCost * amount
    else
        for i = 0, amount - 1 do
            total = total + State.SafeFloor(item.baseCost * (r ^ (item.count + i)))
        end
    end
    return total
end

--- 计算当前金币最多能购买多少个该建筑
---@param item table 建筑数据
---@param coins number 可用金币
---@return number maxAmount 最多购买数量（至少为 0）
function State.GetMaxAffordable(item, coins)
    if coins < State.GetCost(item) then return 0 end
    local count = 0
    local spent = 0.0
    while true do
        local price = State.SafeFloor(item.baseCost * (item.costMul ^ (item.count + count)))
        if spent + price > coins then break end
        spent = spent + price
        count = count + 1
        if count >= 9999 then break end
    end
    return count
end

return State
