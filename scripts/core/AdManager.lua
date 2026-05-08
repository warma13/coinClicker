-- ============================================================================
-- core/AdManager.lua
-- 广告系统核心管理器
-- 统一入口、计数追踪、里程碑奖励、免广卡、连续天数
-- ============================================================================

local SaveBridge       = require("core.SaveBridge")
local SlotSaveSystem   = require("core.SlotSaveSystem")
local GameState        = require("core.GameState")
local InventoryManager = require("core.InventoryManager")
local AdConfig         = require("config.AdConfig")

---@diagnostic disable-next-line: undefined-global
local sdk = sdk  -- 引擎 C++ 注入的全局 SDK 对象

local AM = {}

-- ============================================================================
-- 内部状态
-- ============================================================================
local todayCount_      = 0           -- 今日观看数
local totalCount_      = 0           -- 累计观看数
local dateStr_         = ""          -- 上次记录的日期 "YYYY-MM-DD"
local claimed_         = {}          -- claimed_[milestoneIndex] = true
local streak_          = 0           -- 连续有效天数
local streakBonusHours_ = 1          -- 当前离线加速小时数

--- 外部回调（面板刷新等）
local onStateChanged_  = nil         -- function()

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 获取今天的日期字符串
local function GetTodayStr()
    return os.date("%Y-%m-%d")
end

--- 根据连续天数计算加速小时数
local function CalcStreakBonus(streak)
    for _, tier in ipairs(AdConfig.STREAK_TIERS) do
        if streak >= tier.days then
            return tier.hours
        end
    end
    return AdConfig.STREAK_BASE_HOURS
end

--- 发放单个奖励
---@param reward table {type, cpsSec?, id?, n?}
---@return string desc 奖励描述
local function GrantReward(reward)
    if reward.type == "coins" then
        local cps = GameState.coinsPerSecond or 0
        local mul = GameState.buffCpsMul or 1
        local gain = cps * mul * reward.cpsSec
        if gain > 0 then
            GameState.coins = GameState.coins + gain
            return "获得 " .. GameState.FormatNumber(gain) .. " 金币"
        else
            return "当前无产出"
        end
    elseif reward.type == "item" then
        local ok = InventoryManager.AddItem(reward.id, reward.n or 1)
        if ok then
            return "获得道具"
        else
            return "仓库已满"
        end
    end
    return ""
end

-- ============================================================================
-- 跨天处理
-- ============================================================================

--- 检测并执行跨天逻辑
local function DayRollover()
    local today = GetTodayStr()
    if dateStr_ == today then return end -- 同一天，无需处理

    if dateStr_ ~= "" then
        -- 有上次日期记录，结算昨日
        if todayCount_ >= AdConfig.DAILY_EFFECTIVE_MIN then
            -- 昨天是有效天
            streak_ = streak_ + 1
        else
            -- 昨天无效，衰减
            streak_ = math.max(0, streak_ - AdConfig.STREAK_DECAY_PER_DAY)
        end
    end

    -- 计算加速小时
    streakBonusHours_ = CalcStreakBonus(streak_)

    -- 重置今日数据
    todayCount_ = 0
    claimed_ = {}
    dateStr_ = today

    print("[AdManager] 跨天处理完成, streak=" .. streak_ .. ", bonus=" .. streakBonusHours_ .. "h")
end

-- ============================================================================
-- 初始化
-- ============================================================================

function AM.Init()
    SaveBridge.Register("adTracker", AM.GetSaveData, AM.LoadSaveData)
    print("[AdManager] 初始化完成")
end

-- ============================================================================
-- 核心 API
-- ============================================================================

--- 统一广告播放入口
---@param onSuccess function  广告播放成功后的回调（发放业务奖励）
---@param ctx table|nil       上下文（传入 floatingText 等 UI 引用）
function AM.ShowRewardAd(onSuccess, ctx)
    -- 先检查跨天
    DayRollover()

    -- 检查免广卡
    if AM.IsAdFreeToday() then
        -- 免广卡生效，直接发奖励
        local ok, err = pcall(function()
            AM.Record()
            if onSuccess then onSuccess() end
        end)
        if not ok then
            print("[AdManager] 免广卡回调异常: " .. tostring(err))
        end
        -- 浮字提示
        if ctx and ctx.floatingText then
            local dpr = graphics:GetDPR()
            local cx = graphics:GetWidth() / dpr * 0.5
            local cy = graphics:GetHeight() / dpr * 0.15
            ctx.floatingText.Show("免广卡生效，直接领取", cx, cy, { 100, 255, 100, 255 })
        end
        return
    end

    -- 播放真正的广告
    local ok, err = pcall(function()
        sdk:ShowRewardVideoAd(function(result)
            local ok2, err2 = pcall(function()
                if result.success then
                    AM.Record()
                    if onSuccess then onSuccess() end
                else
                    print("[AdManager] 广告未完成: " .. tostring(result.msg))
                    if ctx and ctx.floatingText then
                        local dpr = graphics:GetDPR()
                        local cx = graphics:GetWidth() / dpr * 0.5
                        local cy = graphics:GetHeight() / dpr * 0.15
                        ctx.floatingText.Show("广告未完成", cx, cy, { 255, 120, 80, 255 })
                    end
                end
            end)
            if not ok2 then
                print("[AdManager] 广告回调异常: " .. tostring(err2))
            end
        end)
    end)
    if not ok then
        print("[AdManager] SDK 调用异常: " .. tostring(err))
    end
end

--- 记录一次广告观看
function AM.Record()
    todayCount_ = todayCount_ + 1
    totalCount_ = totalCount_ + 1
    SlotSaveSystem.MarkDirty()

    -- 检查是否刚好激活免广卡
    if todayCount_ == AdConfig.AD_FREE_THRESHOLD then
        print("[AdManager] 免广卡已激活！今日剩余广告自动跳过")
    end

    if onStateChanged_ then
        local ok, err = pcall(onStateChanged_)
        if not ok then
            print("[AdManager] onStateChanged 异常: " .. tostring(err))
        end
    end
end

--- 领取里程碑奖励
---@param index number 里程碑索引 (1-7)
---@return boolean success
---@return string|nil desc 奖励描述
function AM.ClaimMilestone(index)
    local ms = AdConfig.MILESTONES[index]
    if not ms then return false, nil end
    if claimed_[index] then return false, "已领取" end
    if todayCount_ < ms.count then return false, "未达标" end

    claimed_[index] = true

    -- 发放所有奖励
    local descs = {}
    for _, reward in ipairs(ms.rewards) do
        local ok, desc = pcall(GrantReward, reward)
        if ok then
            descs[#descs + 1] = desc
        else
            print("[AdManager] 发奖异常: " .. tostring(desc))
        end
    end

    SlotSaveSystem.MarkDirty()

    if onStateChanged_ then
        pcall(onStateChanged_)
    end

    return true, table.concat(descs, "，")
end

-- ============================================================================
-- 查询 API
-- ============================================================================

--- 今天是否免广告
function AM.IsAdFreeToday()
    DayRollover()
    return todayCount_ >= AdConfig.AD_FREE_THRESHOLD
end

--- 获取今日观看数
function AM.GetTodayCount()
    return todayCount_
end

--- 获取累计观看数
function AM.GetTotalCount()
    return totalCount_
end

--- 获取里程碑列表（附状态）
---@return table[] { count, label, rewards, status="locked"|"claimable"|"claimed" }
function AM.GetMilestones()
    local result = {}
    for i, ms in ipairs(AdConfig.MILESTONES) do
        local status
        if claimed_[i] then
            status = "claimed"
        elseif todayCount_ >= ms.count then
            status = "claimable"
        else
            status = "locked"
        end
        result[#result + 1] = {
            index   = i,
            count   = ms.count,
            label   = ms.label,
            rewards = ms.rewards,
            status  = status,
        }
    end
    return result
end

--- 获取连续天数信息
function AM.GetStreak()
    return streak_, streakBonusHours_
end

--- 获取免广卡阈值
function AM.GetAdFreeThreshold()
    return AdConfig.AD_FREE_THRESHOLD
end

--- 设置状态变化回调
function AM.SetOnStateChanged(fn)
    onStateChanged_ = fn
end

-- ============================================================================
-- 序列化 / 反序列化
-- ============================================================================

function AM.GetSaveData()
    local claimedList = {}
    for k, _ in pairs(claimed_) do
        claimedList[#claimedList + 1] = k
    end
    return {
        tc  = todayCount_,
        ac  = totalCount_,
        dt  = dateStr_,
        cl  = claimedList,
        sk  = streak_,
        sbh = streakBonusHours_,
    }
end

function AM.LoadSaveData(data)
    todayCount_       = 0
    totalCount_       = 0
    dateStr_          = ""
    claimed_          = {}
    streak_           = 0
    streakBonusHours_ = AdConfig.STREAK_BASE_HOURS

    if not data then
        dateStr_ = GetTodayStr()
        return
    end

    todayCount_       = data.tc or 0
    totalCount_       = data.ac or 0
    dateStr_          = data.dt or ""
    streak_           = data.sk or 0
    streakBonusHours_ = data.sbh or AdConfig.STREAK_BASE_HOURS

    if data.cl then
        for _, idx in ipairs(data.cl) do
            claimed_[idx] = true
        end
    end

    -- 加载后立即检查跨天
    DayRollover()
end

return AM
