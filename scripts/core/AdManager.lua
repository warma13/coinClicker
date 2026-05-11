-- ============================================================================
-- core/AdManager.lua
-- 广告系统核心管理器
-- 统一入口、计数追踪、里程碑奖励、特权卡
-- ============================================================================

local SaveBridge       = require("core.SaveBridge")
local SlotSaveSystem   = require("core.SlotSaveSystem")
local GameState        = require("core.GameState")
local InventoryManager = require("core.InventoryManager")
local AdConfig         = require("config.AdConfig")
local ItemDefs         = require("config.ItemDefs")

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
local cardPoints_      = 0           -- 特权卡累积点数
local cardPointToday_  = false       -- 今天是否已获得特权点
local cardDailyGiven_  = false       -- 今天是否已发放每日道具福利

--- 外部回调（面板刷新等）
local onStateChanged_  = nil         -- function()

--- 全局 FloatingText 引用（由 SetFloatingText 注入）
local floatingText_    = nil

--- 设置全局 FloatingText（初始化时调用一次即可）
function AM.SetFloatingText(ft)
    floatingText_ = ft
end

--- 内部 toast 工具：在屏幕上方居中显示浮字
local function Toast(text, color)
    local ft = floatingText_
    if not ft then return end
    local dpr = graphics:GetDPR()
    local cx = graphics:GetWidth() / dpr * 0.5
    local cy = graphics:GetHeight() / dpr * 0.15
    ft.Show(text, cx, cy, color or { 255, 255, 255, 255 })
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 获取今天的日期字符串
local function GetTodayStr()
    return os.date("%Y-%m-%d")
end

--- 发放单个奖励
---@param reward table {type, id, n}
---@return string desc 奖励描述
local function GrantReward(reward)
    if reward.type == "item" then
        local ok = InventoryManager.AddItem(reward.id, reward.n or 1)
        if ok then
            local def = ItemDefs.ITEM_MAP[reward.id]
            local name = def and def.name or reward.id
            return name .. " x" .. (reward.n or 1)
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

    -- 重置今日数据
    todayCount_ = 0
    claimed_ = {}
    cardPointToday_ = false
    cardDailyGiven_ = false
    dateStr_ = today

    -- 发放每日特权卡道具福利
    AM._GrantDailyCardItems()

    print("[AdManager] 跨天处理完成")
end

-- ============================================================================
-- 初始化
-- ============================================================================

function AM.Init()
    SaveBridge.Register("adTracker", AM.GetSaveData, AM.LoadSaveData, function()
        todayCount_ = 0
        totalCount_ = 0
        dateStr_ = os.date("%Y-%m-%d")
        claimed_ = {}
        cardPoints_ = 0
        cardPointToday_ = false
        cardDailyGiven_ = false
    end)
    print("[AdManager] 初始化完成")
end

-- ============================================================================
-- 核心 API
-- ============================================================================

--- 统一广告播放入口
---@param onSuccess function  广告播放成功后的回调（发放业务奖励）
---@param ctx table|nil       上下文（保留兼容，不再需要传 floatingText）
function AM.ShowRewardAd(onSuccess, ctx)
    -- 先检查跨天
    DayRollover()

    -- 检查每日上限
    if todayCount_ >= AdConfig.DAILY_LIMIT then
        print("[AdManager] 今日广告次数已达上限 " .. AdConfig.DAILY_LIMIT)
        Toast("今日广告次数已用完", { 255, 180, 80, 255 })
        return
    end

    -- 检查 SDK 是否存在
    if not sdk then
        print("[AdManager] SDK 不存在，无法播放广告")
        Toast("广告不可用", { 255, 120, 80, 255 })
        return
    end

    -- 显示加载进度条
    if floatingText_ then
        floatingText_.ShowLoading("广告加载中...")
    end

    -- 播放真正的广告
    local ok, err = pcall(function()
        sdk:ShowRewardVideoAd(function(result)
            -- 隐藏加载进度条
            if floatingText_ then
                floatingText_.HideLoading()
            end
            local ok2, err2 = pcall(function()
                if result.success then
                    AM.Record()
                    if onSuccess then onSuccess() end
                else
                    print("[AdManager] 广告未完成: " .. tostring(result.msg))
                    Toast("看完广告才能领取奖励哦", { 255, 180, 80, 255 })
                end
            end)
            if not ok2 then
                print("[AdManager] 广告回调异常: " .. tostring(err2))
            end
        end)
    end)
    if not ok then
        -- 隐藏加载进度条
        if floatingText_ then
            floatingText_.HideLoading()
        end
        print("[AdManager] SDK 调用异常: " .. tostring(err))
        Toast("广告加载失败", { 255, 120, 80, 255 })
    end
end

--- 记录一次广告观看
function AM.Record()
    todayCount_ = todayCount_ + 1
    totalCount_ = totalCount_ + 1

    -- 特权卡：今日看满上限获得 1 点
    if not cardPointToday_ and todayCount_ >= AdConfig.DAILY_LIMIT then
        cardPoints_ = cardPoints_ + 1
        cardPointToday_ = true
        print("[AdManager] 特权卡 +1 点, 总计=" .. cardPoints_)
    end

    SlotSaveSystem.MarkDirty()

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

--- 获取每日上限
function AM.GetDailyLimit()
    return AdConfig.DAILY_LIMIT
end

-- ============================================================================
-- 特权卡 API
-- ============================================================================

--- 获取特权卡点数
function AM.GetCardPoints()
    return cardPoints_
end

--- 获取特权卡当前等级信息
---@return table levelDef 当前等级定义
---@return number levelIdx 当前等级索引 (1-based)
---@return table|nil nextDef 下一等级定义 (满级为nil)
---@return boolean activated 是否已激活当前等级
function AM.GetCardLevel()
    local levels = AdConfig.PRIVILEGE_CARD.levels
    -- 点数不够第一级时，返回第一级但标记未激活
    if cardPoints_ < levels[1].points then
        return levels[1], 1, levels[2], false
    end
    local curIdx = 1
    for i = #levels, 1, -1 do
        if cardPoints_ >= levels[i].points then
            curIdx = i
            break
        end
    end
    local nextDef = levels[curIdx + 1] or nil
    return levels[curIdx], curIdx, nextDef, true
end

--- 获取特权卡 CPS 加成（供 ProductionCalculator 调用）
---@return number cpsMul 加成百分比, 如 0.15 = +15%
function AM.GetCardCpsMul()
    local levelDef, _, _, activated = AM.GetCardLevel()
    if not activated then return 0 end
    return levelDef.cpsMul or 0
end

--- 获取特权卡 CPC(点击收益) 加成（供 ProductionCalculator 调用）
---@return number cpcMul 加成百分比, 如 0.08 = +8%
function AM.GetCardCpcMul()
    local levelDef, _, _, activated = AM.GetCardLevel()
    if not activated then return 0 end
    return levelDef.cpcMul or 0
end

--- 今天是否已获得特权点
function AM.IsCardPointEarnedToday()
    return cardPointToday_
end

--- 今天是否已发放每日道具福利
function AM.IsCardDailyGiven()
    return cardDailyGiven_
end

--- 获取当前等级的每日道具福利列表（读配置）
---@return table|nil dailyItems
function AM.GetCardDailyItems()
    local levelDef = AM.GetCardLevel()
    return levelDef.dailyItems
end

--- (内部) 发放每日特权卡道具福利
function AM._GrantDailyCardItems()
    if cardDailyGiven_ then return end
    local levelDef, _, _, activated = AM.GetCardLevel()
    if not activated then return end  -- 未激活不发放
    local items = levelDef.dailyItems
    if not items or #items == 0 then return end

    cardDailyGiven_ = true
    local descs = {}
    for _, reward in ipairs(items) do
        local ok = InventoryManager.AddItem(reward.id, reward.n or 1)
        if ok then
            local def = ItemDefs.ITEM_MAP[reward.id]
            local name = def and def.name or reward.id
            descs[#descs + 1] = name .. " x" .. (reward.n or 1)
        end
    end
    SlotSaveSystem.MarkDirty()

    if #descs > 0 then
        Toast("每日福利: " .. table.concat(descs, ", "), { 80, 220, 120, 255 })
        print("[AdManager] 每日特权卡福利已发放: " .. table.concat(descs, ", "))
    end
end

--- 获取今日剩余次数
function AM.GetRemainingToday()
    return math.max(0, AdConfig.DAILY_LIMIT - todayCount_)
end

--- 设置状态变化回调
function AM.SetOnStateChanged(fn)
    onStateChanged_ = fn
end

-- ============================================================================
-- 调试 API（仅限 DebugPanel 使用）
-- ============================================================================

--- 调试：直接增加今日观看次数（不触发真实广告）
---@param n number
function AM.DebugAddCount(n)
    for _ = 1, (n or 1) do
        AM.Record()
    end
    print("[AdManager][Debug] +", n, " → todayCount=", todayCount_)
end

--- 调试：重置今日数据（次数归零、领取清空）
function AM.DebugResetToday()
    todayCount_ = 0
    claimed_ = {}
    SlotSaveSystem.MarkDirty()
    if onStateChanged_ then pcall(onStateChanged_) end
    print("[AdManager][Debug] 今日数据已重置")
end

--- 调试：领取所有可领取的里程碑
---@return number claimedCount
function AM.DebugClaimAll()
    local count = 0
    for i, ms in ipairs(AdConfig.MILESTONES) do
        if not claimed_[i] and todayCount_ >= ms.count then
            claimed_[i] = true
            for _, reward in ipairs(ms.rewards) do
                pcall(GrantReward, reward)
            end
            count = count + 1
        end
    end
    SlotSaveSystem.MarkDirty()
    if onStateChanged_ then pcall(onStateChanged_) end
    print("[AdManager][Debug] 批量领取 " .. count .. " 个里程碑")
    return count
end

--- 调试：增加特权卡点数
---@param n number
function AM.DebugAddCardPoints(n)
    cardPoints_ = cardPoints_ + (n or 1)
    SlotSaveSystem.MarkDirty()
    if onStateChanged_ then pcall(onStateChanged_) end
    print("[AdManager][Debug] 特权卡 +" .. (n or 1) .. " → 总计=" .. cardPoints_)
end

--- 调试：手动发放每日道具福利
function AM.DebugGrantDailyItems()
    cardDailyGiven_ = false  -- 重置标记，允许重新发放
    AM._GrantDailyCardItems()
    if onStateChanged_ then pcall(onStateChanged_) end
    print("[AdManager][Debug] 每日福利已手动发放")
end

--- 调试：重置特权卡（点数清零、福利重置）
function AM.DebugResetCard()
    cardPoints_ = 0
    cardPointToday_ = false
    cardDailyGiven_ = false
    SlotSaveSystem.MarkDirty()
    if onStateChanged_ then pcall(onStateChanged_) end
    print("[AdManager][Debug] 特权卡已重置")
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
        cp  = cardPoints_,
        cpt = cardPointToday_,
        cdg = cardDailyGiven_,
    }
end

function AM.LoadSaveData(data)
    todayCount_       = 0
    totalCount_       = 0
    dateStr_          = ""
    claimed_          = {}
    cardPoints_       = 0
    cardPointToday_   = false
    cardDailyGiven_   = false

    if not data then
        dateStr_ = GetTodayStr()
        return
    end

    todayCount_       = data.tc or 0
    totalCount_       = data.ac or 0
    dateStr_          = data.dt or ""
    cardPoints_       = data.cp or 0
    cardPointToday_   = data.cpt or false
    cardDailyGiven_   = data.cdg or false

    if data.cl then
        for _, idx in ipairs(data.cl) do
            claimed_[idx] = true
        end
    end

    -- 加载后立即检查跨天
    DayRollover()

    -- 如果今天还没发过每日道具，补发（首次登录 / 升级后首次加载）
    AM._GrantDailyCardItems()
end

return AM
