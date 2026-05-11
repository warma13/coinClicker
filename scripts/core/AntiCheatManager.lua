-- ============================================================================
-- core/AntiCheatManager.lua
-- 反作弊模块 —— 检测系统时钟篡改行为
--   跨会话：检测时间倒退（os.time() < 上次云端时间戳）
--   会话内：检测时钟拨快（os.time() 漂移 > 引擎 elapsedTime 漂移）
--   惩罚：第一次警告弹窗，第二次清空全部资产
-- ============================================================================

local UI          = require("urhox-libs/UI")
local GameVersion = require("Game.GameVersion")

local ACM = {}

-- ======================== 配置常量 ========================
local DRIFT_TOLERANCE = 300      -- 会话内漂移容忍度（秒）

-- ======================== 内部状态 ========================
local initialized_    = false
local cheater_        = 0        -- 0=正常  1=已警告一次
local anchorLocal_    = 0        -- 会话开始时的 os.time()
local anchorElapsed_  = 0        -- 会话开始时的 time.elapsedTime

-- 外部注入回调（避免循环依赖）
local showFloatingText_ = nil    -- 浮窗提示
local switchSlotFn_     = nil    -- 切换新槽位（由 main.lua 注入）

-- ============================================================================
-- 注入浮窗回调
-- ============================================================================

--- 设置浮窗提示回调（由 main.lua 在 GameManager 初始化后调用）
---@param fn fun(text:string, color?:table, icon?:string)
function ACM.SetFloatingTextFn(fn)
    showFloatingText_ = fn
end

--- 设置槽位切换回调（由 main.lua 注入，避免 ACM → SSS 循环依赖）
---@param fn fun(onDone: fun()|nil)
function ACM.SetSlotSwitchFn(fn)
    switchSlotFn_ = fn
end

-- ============================================================================
-- 内部：执行惩罚
-- ============================================================================

--- 弹出警告浮窗
local function ShowWarning(text)
    if showFloatingText_ then
        showFloatingText_(text, { 255, 60, 60, 255 })
    end
end

--- 切换到新槽位（旧存档保留，以新玩家身份重新开始）
local function WipeAssets()
    if switchSlotFn_ then
        switchSlotFn_(function()
            print("[AntiCheat] 槽位切换完成")
        end)
    else
        print("[AntiCheat] 警告: 槽位切换回调未注入，无法执行资产清空")
    end
end

--- 首次警告弹窗（显示用户ID + 版本号）
local function ShowAlertModal()
    local uid = clientCloud and clientCloud.userId or "---"
    local ver = GameVersion.GetVersionString()
    local msg = string.format(
        "检测到异常行为，再次违规将清空全部资产。\n\nID: %s\n版本: %s",
        tostring(uid), ver)
    UI.Modal.Alert({
        title = "警告",
        message = msg,
    })
end

--- 统一处理一次作弊检测
local function OnCheatDetected()
    if cheater_ == 0 then
        -- 第一次：弹窗警告（含用户ID与版本号）
        cheater_ = 1
        ShowAlertModal()
        print("[AntiCheat] 首次违规，已弹窗警告")
    elseif cheater_ == 1 then
        -- 第二次：切换新槽位（旧存档保留），重置回 0 循环
        WipeAssets()
        ShowWarning("再次检测到作弊，已切换到新存档")
        cheater_ = 0
        -- 重置锚点（新槽位 = 新开始）
        anchorLocal_   = os.time()
        anchorElapsed_ = time.elapsedTime
    end

    -- 上报云端
    local now = os.time()
    clientCloud:BatchSet()
        :Set("ac_last_ts", now)
        :SetInt("ac_cheater", cheater_)
        :Save("anti_cheat_flag", {
            ok = function()
                print("[AntiCheat] 作弊标记已上报云端: " .. cheater_)
            end,
            error = function(code, reason)
                print("[AntiCheat] 上报失败: " .. tostring(reason))
            end,
        })
end

-- ============================================================================
-- 初始化（登录后调用，从云端读取并执行跨会话检测）
-- ============================================================================

---@param onDone fun()|nil
function ACM.Init(onDone)
    if initialized_ then
        if onDone then onDone() end
        return
    end

    -- 记录会话锚点
    anchorLocal_   = os.time()
    anchorElapsed_ = time.elapsedTime

    -- 从云端批量读取反作弊数据
    clientCloud:BatchGet()
        :Key("ac_last_ts")
        :Key("ac_cheater")
        :Fetch({
            ok = function(values, iscores)
                local lastTs   = values.ac_last_ts
                local oldCheat = iscores.ac_cheater or 0

                cheater_ = oldCheat
                initialized_ = true

                local now = os.time()

                -- 跨会话检测：时间倒退（当前时间 < 上次记录的时间）
                if lastTs and type(lastTs) == "number" and lastTs > 0 then
                    local diff = now - lastTs
                    if diff < 0 then
                        -- 时间倒退 → 作弊
                        print(string.format(
                            "[AntiCheat] 时钟倒退: 当前=%d 上次=%d 差值=%d秒",
                            now, lastTs, diff))
                        OnCheatDetected()
                    else
                        print(string.format(
                            "[AntiCheat] 跨会话正常: 离线 %d 秒 | cheater=%d",
                            diff, cheater_))
                        -- 正常：更新云端时间戳
                        clientCloud:Set("ac_last_ts", now, {
                            ok = function() end,
                            error = function() end,
                        })
                    end
                else
                    -- 首次登录
                    print("[AntiCheat] 首次登录，初始化反作弊数据")
                    clientCloud:BatchSet()
                        :Set("ac_last_ts", now)
                        :SetInt("ac_cheater", 0)
                        :Save("anti_cheat_init", {
                            ok = function()
                                print("[AntiCheat] 云端数据已初始化")
                            end,
                            error = function(code, reason)
                                print("[AntiCheat] 云端写入失败: " .. tostring(reason))
                            end,
                        })
                end

                if onDone then onDone() end
            end,
            error = function(code, reason)
                print("[AntiCheat] 云端读取失败: " .. tostring(reason))
                initialized_ = true
                if onDone then onDone() end
            end,
        })
end

-- ============================================================================
-- 会话内漂移检测（每次存档时调用）
-- ============================================================================

function ACM.CheckDrift()
    if not initialized_ then return end


    local now         = os.time()
    local elapsed     = time.elapsedTime
    local localDrift  = now - anchorLocal_
    local realDrift   = elapsed - anchorElapsed_
    local drift       = localDrift - realDrift

    if drift > DRIFT_TOLERANCE then
        print(string.format(
            "[AntiCheat] 会话内时钟拨快! localDrift=%.0f realDrift=%.0f 差值=%.0f秒",
            localDrift, realDrift, drift))
        OnCheatDetected()
        -- 重置锚点，避免后续每次 save 都重复触发
        anchorLocal_   = os.time()
        anchorElapsed_ = time.elapsedTime
    else
        -- 正常：更新云端时间戳
        clientCloud:Set("ac_last_ts", now, {
            ok = function() end,
            error = function() end,
        })
    end
end

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 获取作弊等级 0=正常 1=已警告 2=已清空
---@return number
function ACM.GetCheatLevel()
    return cheater_
end

--- 是否已初始化
---@return boolean
function ACM.IsInitialized()
    return initialized_
end

-- ============================================================================
-- 调试接口（仅 DebugPanel 使用）
-- ============================================================================

--- 调试：模拟触发一次作弊检测
function ACM.DebugTrigger()
    if not initialized_ then return end
    print("[AntiCheat][Debug] 手动触发作弊检测")
    OnCheatDetected()
end

--- 调试：重置反作弊状态（本地 + 云端）
function ACM.DebugReset()
    cheater_ = 0
    anchorLocal_   = os.time()
    anchorElapsed_ = time.elapsedTime
    print("[AntiCheat][Debug] 状态已重置为正常")
    clientCloud:BatchSet()
        :Set("ac_last_ts", os.time())
        :SetInt("ac_cheater", 0)
        :Save("anti_cheat_debug_reset", {
            ok = function()
                print("[AntiCheat][Debug] 云端已重置")
            end,
            error = function(code, reason)
                print("[AntiCheat][Debug] 云端重置失败: " .. tostring(reason))
            end,
        })
end

return ACM
