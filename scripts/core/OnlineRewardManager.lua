-- ============================================================================
-- core/OnlineRewardManager.lua
-- 每日在线时长奖励管理器
-- 追踪当日在线秒数，到达里程碑后可领取道具奖励 + 当日 CPS/CPC 加成
-- ============================================================================

local SaveBridge         = require("core.SaveBridge")
local SlotSaveSystem     = require("core.SlotSaveSystem")
local InventoryManager   = require("core.InventoryManager")
local ItemDefs           = require("config.ItemDefs")
local OnlineRewardConfig = require("config.OnlineRewardConfig")

local ORM = {}

-- ============================================================================
-- 内部状态
-- ============================================================================
local onlineSec_      = 0            -- 今日累计在线秒数
local dateStr_        = ""           -- 上次记录日期 "YYYY-MM-DD"
local claimed_        = {}           -- claimed_[milestoneIndex] = true
local onStateChanged_ = nil          -- 外部回调

--- 全局 FloatingText 引用
local floatingText_   = nil

-- ============================================================================
-- 工具函数
-- ============================================================================

local function GetTodayStr()
    return os.date("%Y-%m-%d")
end

--- 内部 toast
local function Toast(text, color)
    local ft = floatingText_
    if not ft then return end
    local dpr = graphics:GetDPR()
    local cx = graphics:GetWidth() / dpr * 0.5
    local cy = graphics:GetHeight() / dpr * 0.15
    ft.Show(text, cx, cy, color or { 255, 255, 255, 255 })
end

--- 发放单个奖励
---@param reward table {type, id, n}
---@return string desc
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

local function DayRollover()
    local today = GetTodayStr()
    if dateStr_ == today then return end

    onlineSec_ = 0
    claimed_   = {}
    dateStr_   = today

    print("[OnlineRewardManager] 跨天处理完成")
end

-- ============================================================================
-- 初始化
-- ============================================================================

function ORM.Init()
    SaveBridge.Register("onlineReward", ORM.GetSaveData, ORM.LoadSaveData, function()
        onlineSec_ = 0
        dateStr_   = GetTodayStr()
        claimed_   = {}
    end)
    print("[OnlineRewardManager] 初始化完成")
end

--- 注入 FloatingText
function ORM.SetFloatingText(ft)
    floatingText_ = ft
end

-- ============================================================================
-- 帧更新（由 GameManager 调用）
-- ============================================================================

--- 累加在线秒数
---@param dt number 帧间隔
function ORM.Update(dt)
    DayRollover()
    onlineSec_ = onlineSec_ + dt
end

-- ============================================================================
-- 领取 API
-- ============================================================================

--- 领取里程碑奖励
---@param index number 里程碑索引 (1-7)
---@return boolean success
---@return string|nil desc 奖励描述
function ORM.ClaimMilestone(index)
    local ms = OnlineRewardConfig.MILESTONES[index]
    if not ms then return false, nil end
    if claimed_[index] then return false, "已领取" end
    if onlineSec_ < ms.seconds then return false, "未达标" end

    claimed_[index] = true

    -- 发放道具奖励
    local descs = {}
    for _, reward in ipairs(ms.rewards) do
        local ok, desc = pcall(GrantReward, reward)
        if ok then
            descs[#descs + 1] = desc
        else
            print("[OnlineRewardManager] 发奖异常: " .. tostring(desc))
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

--- 获取今日在线秒数
---@return number
function ORM.GetOnlineSeconds()
    return onlineSec_
end

--- 获取里程碑列表（附状态）
---@return table[]
function ORM.GetMilestones()
    local result = {}
    for i, ms in ipairs(OnlineRewardConfig.MILESTONES) do
        local status
        if claimed_[i] then
            status = "claimed"
        elseif onlineSec_ >= ms.seconds then
            status = "claimable"
        else
            status = "locked"
        end
        result[#result + 1] = {
            index   = i,
            seconds = ms.seconds,
            label   = ms.label,
            rewards = ms.rewards,
            bonus   = ms.bonus,
            status  = status,
        }
    end
    return result
end

--- 获取当日已领取的最高档 CPS 加成（供 ProductionCalculator 调用）
---@return number cpsPct 最高档百分比（如 0.10 = +10%）
function ORM.GetCpsBonusPct()
    local best = 0
    for i, ms in ipairs(OnlineRewardConfig.MILESTONES) do
        if claimed_[i] and ms.bonus and ms.bonus.cpsPct and ms.bonus.cpsPct > best then
            best = ms.bonus.cpsPct
        end
    end
    return best
end

--- 获取当日已领取的最高档 CPC 加成（供 ProductionCalculator 调用）
---@return number cpcPct 最高档百分比（如 0.08 = +8%）
function ORM.GetCpcBonusPct()
    local best = 0
    for i, ms in ipairs(OnlineRewardConfig.MILESTONES) do
        if claimed_[i] and ms.bonus and ms.bonus.cpcPct and ms.bonus.cpcPct > best then
            best = ms.bonus.cpcPct
        end
    end
    return best
end

--- 设置状态变化回调
function ORM.SetOnStateChanged(fn)
    onStateChanged_ = fn
end

-- ============================================================================
-- 序列化 / 反序列化
-- ============================================================================

function ORM.GetSaveData()
    local claimedList = {}
    for k, _ in pairs(claimed_) do
        claimedList[#claimedList + 1] = k
    end
    return {
        os = onlineSec_,
        dt = dateStr_,
        cl = claimedList,
    }
end

function ORM.LoadSaveData(data)
    onlineSec_ = 0
    dateStr_   = ""
    claimed_   = {}

    if not data then
        dateStr_ = GetTodayStr()
        return
    end

    onlineSec_ = data.os or 0
    dateStr_   = data.dt or ""

    if data.cl then
        for _, idx in ipairs(data.cl) do
            claimed_[idx] = true
        end
    end

    -- 加载后检查跨天
    DayRollover()
end

return ORM
