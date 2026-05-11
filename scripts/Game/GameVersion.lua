-- ============================================================================
-- Game/GameVersion.lua
-- 版本检测模块：通过 clientCloud 排行榜比对最新版本
-- ============================================================================

local GV = {}

-- ======== 当前版本 ========
local CURRENT_VERSION_STR = "v1.0.7"

--- 版本字符串 → 整数  "v1.0.7" → 10007
local function VersionToInt(str)
    local major, minor, patch = str:match("v?(%d+)%.(%d+)%.(%d+)")
    if not major then return 0 end
    return tonumber(major) * 10000 + tonumber(minor) * 100 + tonumber(patch)
end

--- 整数 → 版本字符串  10007 → "v1.0.7"
local function IntToVersion(n)
    local major = math.floor(n / 10000)
    local minor = math.floor((n % 10000) / 100)
    local patch = n % 100
    return string.format("v%d.%d.%d", major, minor, patch)
end

local CURRENT_VERSION_INT = VersionToInt(CURRENT_VERSION_STR)
local LB_KEY = "lb_version"

-- ======== 状态 ========
local hasNewVersion_  = false
local latestVerStr_   = nil      -- 检测到的最新版本字符串
local checkTimer_     = 0
local CHECK_INTERVAL  = 600      -- 自动检测间隔（秒）
local FIRST_DELAY     = 5        -- 首次延迟（秒）
local initialized_    = false
local onNewVersion_   = nil      -- 回调：发现新版本时通知外部刷新红点等

-- ============================================================================
-- 内部：上报 + 查询
-- ============================================================================

--- 上报当前版本到排行榜
local function ReportVersion()
    if not clientCloud then return end
    clientCloud:SetInt(LB_KEY, CURRENT_VERSION_INT)
end

--- 查询排行榜最高版本
---@param onResult fun(hasNew:boolean, latestStr:string)|nil
local function FetchLatest(onResult)
    if not clientCloud then
        if onResult then onResult(false, CURRENT_VERSION_STR) end
        return
    end
    clientCloud:GetRankList(LB_KEY, 0, 1, {
        ok = function(rankList)
            local top = (rankList and #rankList > 0) and rankList[1] or nil
            local topVer = top and top.iscore and top.iscore[LB_KEY] or 0
            if topVer > CURRENT_VERSION_INT then
                hasNewVersion_ = true
                latestVerStr_ = IntToVersion(topVer)
            else
                hasNewVersion_ = false
                latestVerStr_ = CURRENT_VERSION_STR
            end
            if onResult then onResult(hasNewVersion_, latestVerStr_) end
            if hasNewVersion_ and onNewVersion_ then
                onNewVersion_(latestVerStr_)
            end
        end,
        err = function(code, msg)
            print("[GameVersion] 查询失败: " .. tostring(msg))
            if onResult then onResult(false, CURRENT_VERSION_STR) end
        end,
    })
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 初始化（在 Start 时调用一次）
function GV.Init()
    initialized_ = true
    checkTimer_ = FIRST_DELAY
    ReportVersion()
end

--- 帧更新（自动静默检测）
---@param dt number
function GV.Update(dt)
    if not initialized_ then return end
    checkTimer_ = checkTimer_ - dt
    if checkTimer_ <= 0 then
        checkTimer_ = CHECK_INTERVAL
        FetchLatest(nil)
    end
end

--- 手动检测（设置面板按钮触发）
---@param callback fun(hasNew:boolean, latestStr:string)|nil
function GV.CheckNow(callback)
    FetchLatest(callback)
end

--- 是否有新版本
---@return boolean
function GV.HasNewVersion()
    return hasNewVersion_
end

--- 获取当前版本字符串
---@return string
function GV.GetVersionString()
    return CURRENT_VERSION_STR
end

--- 获取检测到的最新版本字符串
---@return string|nil
function GV.GetLatestVersionString()
    return latestVerStr_
end

--- 注册新版本回调（用于红点刷新等）
---@param fn fun(latestStr:string)
function GV.OnNewVersion(fn)
    onNewVersion_ = fn
end

return GV
