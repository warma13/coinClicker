-- ============================================================================
-- core/SlotSaveSystem.lua
-- 单槽位云端存档系统：云端优先 · 本地缓存 · 自动分片 · 自动保存
-- 防护：generation 防幽灵回调 · confirmedSeq 防回档 · 超时保护
--       连续失败熔断 · NaN/Inf 消毒 · 本地文件校验头
-- ============================================================================

---@diagnostic disable: undefined-global
-- cjson 是引擎内置全局模块（JSON 编解码）

local SaveBridge = require("core.SaveBridge")

local SSS = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------

local SLOT_ID        = 1       -- 单槽位，固定为 1
local SAVE_INTERVAL  = 30      -- 自动保存间隔（秒）
local DIRTY_DELAY    = 2       -- MarkDirty 延迟合并（秒）
local CHUNK_SIZE     = 9000    -- 单分片最大字节数（预留 key 开销）
local MAX_RETRY      = 3       -- 云端保存最大重试次数
local RETRY_BASE     = 3       -- 重试基础间隔（秒），指数退避 3^n
local LOCAL_FILE     = "save_slot1.json"
local SAVE_TIMEOUT   = 15      -- 云端保存超时（秒）
local FAIL_WARN_AT   = 3       -- 连续失败 N 次显示警告
local FAIL_PAUSE_AT  = 6       -- 连续失败 N 次暂停自动保存

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------

local initialized_    = false
local saveConfirmed_  = false   -- 加载/新建成功后为 true，才允许自动保存
local saveSeq_        = 0       -- 保存序列号，每次发出保存请求递增
local confirmedSeq_   = 0       -- 云端确认成功的序列号
local saveGeneration_ = 0       -- 保存代次，每次发出新请求递增，防幽灵回调
local loadGeneration_ = 0       -- 加载代次，防旧加载回调干扰
local playTime_       = 0       -- 累计游戏时长
local autoSaveTimer_  = 0       -- 自动保存倒计时
local dirtyTimer_     = -1      -- MarkDirty 延迟倒计时（< 0 表示无脏标记）
local retryTimer_     = -1      -- 云端重试倒计时
local retryCount_     = 0
local pendingSave_    = false   -- 是否有待发送的保存（saving_ 期间有新请求）
local headCache_      = nil     -- 最近一次写入的 head（用于清理旧分片）
local saving_         = false   -- 防止并发保存
local loading_        = false
local onSavedCallback_ = nil   -- 保存成功外部回调
local saveTimeoutTimer_ = -1   -- 超时计时器
local consecutiveFails_ = 0    -- 连续失败次数
local savePaused_     = false   -- 熔断：是否暂停自动保存
local warningShown_   = false   -- 是否已显示存档警告

-- ============================================================================
-- DJB2 校验码
-- ============================================================================

--- 计算字符串的 DJB2 哈希（32 位无符号）
---@param str string
---@return integer
local function CalcChecksum(str)
    local hash = 5381
    for i = 1, #str do
        hash = ((hash << 5) + hash + string.byte(str, i)) & 0xFFFFFFFF
    end
    return hash
end

-- ============================================================================
-- 数据消毒：NaN / Inf / 非法类型 / 循环引用
-- ============================================================================

--- 递归清洗存档数据，将 NaN/Inf 替换为 0，移除 function/userdata
---@param t table
---@param visited table|nil  循环引用检测
---@return table
local function SanitizeTable(t, visited)
    if type(t) ~= "table" then return t end
    visited = visited or {}
    if visited[t] then
        print("[SaveSystem] 警告: 检测到循环引用，已截断")
        return {}
    end
    visited[t] = true

    local cleaned = {}
    for k, v in pairs(t) do
        local kType = type(k)
        -- key 只保留 string 和 number
        if kType == "string" or kType == "number" then
            local vType = type(v)
            if vType == "number" then
                -- NaN: x ~= x；Inf: math.abs(x) == math.huge
                if v ~= v or math.abs(v) == math.huge then
                    print("[SaveSystem] 消毒: key=" .. tostring(k) .. " value=" .. tostring(v) .. " → 0")
                    cleaned[k] = 0
                else
                    cleaned[k] = v
                end
            elseif vType == "table" then
                cleaned[k] = SanitizeTable(v, visited)
            elseif vType == "string" or vType == "boolean" then
                cleaned[k] = v
            else
                -- function, userdata, thread 等：跳过
                print("[SaveSystem] 消毒: 移除非法类型 key=" .. tostring(k) .. " type=" .. vType)
            end
        end
    end

    visited[t] = nil
    return cleaned
end

-- ============================================================================
-- 分片编解码
-- ============================================================================

--- 将分组数据编码为 JSON 并按需拆分为多个分片
---@param groupData table
---@return string[] chunks      JSON 分片数组
---@return integer[] checksums  每片校验码
---@return integer totalLen     原始 JSON 总长度
local function EncodeGroup(groupData)
    local json = cjson.encode(groupData)
    local len  = #json

    if len <= CHUNK_SIZE then
        return { json }, { CalcChecksum(json) }, len
    end

    -- 超过单片上限，按字节拆分
    local chunks    = {}
    local checksums = {}
    local pos = 1
    while pos <= len do
        local chunk = json:sub(pos, pos + CHUNK_SIZE - 1)
        chunks[#chunks + 1]       = chunk
        checksums[#checksums + 1] = CalcChecksum(chunk)
        pos = pos + CHUNK_SIZE
    end
    return chunks, checksums, len
end

-- ============================================================================
-- 云端 Key 命名
-- ============================================================================

local function HeadKey()
    return "s_" .. SLOT_ID .. "_head"
end

local function GroupKey(groupName)
    return "s_" .. SLOT_ID .. "_" .. groupName
end

local function ChunkKey(groupName, chunkIdx)
    return "s_" .. SLOT_ID .. "_" .. groupName .. "_" .. chunkIdx
end

-- ============================================================================
-- 本地文件缓存（带校验头：长度:DJB2\nJSON）
-- ============================================================================

--- 同步写入本地文件（带校验头）
---@param saveData table
---@return boolean ok
local function SaveLocal(saveData)
    local ok, json = pcall(cjson.encode, saveData)
    if not ok then
        print("[SaveSystem] 本地编码失败: " .. tostring(json))
        return false
    end
    local checksum = CalcChecksum(json)
    local header = #json .. ":" .. checksum .. "\n"
    local file = File(LOCAL_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(header .. json)
        file:Close()
        return true
    end
    print("[SaveSystem] 本地文件写入失败")
    return false
end

--- 同步读取本地文件（校验长度+DJB2）
---@return table|nil
local function LoadLocal()
    if not fileSystem:FileExists(LOCAL_FILE) then return nil end
    local file = File(LOCAL_FILE, FILE_READ)
    if not file:IsOpen() then return nil end
    local raw = file:ReadString()
    file:Close()
    if not raw or #raw == 0 then return nil end

    -- 尝试解析校验头
    local newlinePos = raw:find("\n", 1, true)
    if newlinePos then
        local header = raw:sub(1, newlinePos - 1)
        local json = raw:sub(newlinePos + 1)
        local colonPos = header:find(":", 1, true)
        if colonPos then
            local expectedLen = tonumber(header:sub(1, colonPos - 1))
            local expectedCs  = tonumber(header:sub(colonPos + 1))
            if expectedLen and expectedCs then
                -- 校验长度
                if #json ~= expectedLen then
                    print("[SaveSystem] 本地文件被截断: 期望 " .. expectedLen .. " 实际 " .. #json)
                    return nil
                end
                -- 校验 DJB2
                local actualCs = CalcChecksum(json)
                if actualCs ~= expectedCs then
                    print("[SaveSystem] 本地文件校验失败: 期望 " .. expectedCs .. " 实际 " .. actualCs)
                    return nil
                end
                -- 校验通过，解码
                local decOk, data = pcall(cjson.decode, json)
                if decOk then return data end
                print("[SaveSystem] 本地文件解码失败（校验通过但 JSON 无效）")
                return nil
            end
        end
    end

    -- 兼容旧格式（无校验头，裸 JSON）
    local ok2, data = pcall(cjson.decode, raw)
    if ok2 then
        print("[SaveSystem] 本地缓存为旧格式（无校验头），已兼容读取")
        return data
    end
    print("[SaveSystem] 本地文件解码失败")
    return nil
end

-- ============================================================================
-- 连续失败熔断 + 警告
-- ============================================================================

local function OnSaveFailed()
    consecutiveFails_ = consecutiveFails_ + 1
    print("[SaveSystem] 连续失败: " .. consecutiveFails_ .. " 次")

    if consecutiveFails_ >= FAIL_PAUSE_AT and not savePaused_ then
        savePaused_ = true
        print("[SaveSystem] 熔断：连续失败 " .. consecutiveFails_ .. " 次，暂停自动保存")
    end

    if consecutiveFails_ >= FAIL_WARN_AT and not warningShown_ then
        warningShown_ = true
        print("[SaveSystem] 存档异常警告已触发")
    end
end

local function OnSaveSucceeded()
    if consecutiveFails_ > 0 then
        print("[SaveSystem] 云端保存恢复正常（此前连续失败 " .. consecutiveFails_ .. " 次）")
    end
    consecutiveFails_ = 0
    if savePaused_ then
        savePaused_ = false
        print("[SaveSystem] 熔断解除：自动保存已恢复")
    end
    if warningShown_ then
        warningShown_ = false
        print("[SaveSystem] 存档警告已消除")
    end
end

-- ============================================================================
-- 云端写入
-- ============================================================================

--- 将存档数据保存到云端
---@param saveData table  完整存档
---@param onComplete fun(ok: boolean)|nil
local function SaveToCloud(saveData, onComplete)
    if not clientCloud then
        print("[SaveSystem] clientCloud 不可用，跳过云端保存")
        if onComplete then onComplete(false) end
        return
    end

    local groups, version, timestamp = SaveBridge.SplitIntoGroups(saveData)

    -- 递增序列号和代次
    saveSeq_ = saveSeq_ + 1
    saveGeneration_ = saveGeneration_ + 1
    local myGen = saveGeneration_  -- 闭包捕获当前代次
    local mySeq = saveSeq_

    -- 构建 head 索引
    local headData = {
        format    = 1,
        version   = version,
        timestamp = timestamp,
        slotId    = SLOT_ID,
        saveSeq   = mySeq,
        keys      = {},
    }

    local batch = clientCloud:BatchSet()

    for groupName, groupData in pairs(groups) do
        if groupData then
            local chunks, checksums, totalLen = EncodeGroup(groupData)

            if #chunks == 1 then
                headData.keys[groupName] = {
                    cs  = checksums[1],
                    len = totalLen,
                }
                batch:Set(GroupKey(groupName), groupData)
            else
                headData.keys[groupName] = {
                    chunks = #chunks,
                    cs     = checksums,
                    len    = {},
                }
                for ci, chunk in ipairs(chunks) do
                    headData.keys[groupName].len[ci] = #chunk
                    batch:Set(ChunkKey(groupName, ci - 1), chunk)
                end
            end
        end
    end

    -- 写入 head
    batch:Set(HeadKey(), headData)

    -- 启动超时计时器
    saveTimeoutTimer_ = SAVE_TIMEOUT

    -- 提交
    batch:Save("自动存档", {
        ok = function()
            -- 幽灵回调检测：如果代次不匹配，丢弃
            if myGen ~= saveGeneration_ then
                print("[SaveSystem] 丢弃旧代次回调 (gen=" .. myGen .. " current=" .. saveGeneration_ .. ")")
                return
            end

            saveTimeoutTimer_ = -1  -- 取消超时
            confirmedSeq_ = mySeq   -- 更新确认序列号

            -- 清理旧分片残留
            if headCache_ and headCache_.keys then
                for gn, oldInfo in pairs(headCache_.keys) do
                    if oldInfo.chunks then
                        local newInfo = headData.keys[gn]
                        local newChunks = (newInfo and newInfo.chunks) or 0
                        if newChunks == 0 or (type(newChunks) ~= "number") then
                            for ci = 0, oldInfo.chunks - 1 do
                                clientCloud:BatchSet():Set(ChunkKey(gn, ci), ""):Save("清理")
                            end
                        elseif type(newChunks) == "number" and newChunks < oldInfo.chunks then
                            for ci = newChunks, oldInfo.chunks - 1 do
                                clientCloud:BatchSet():Set(ChunkKey(gn, ci), ""):Save("清理")
                            end
                        end
                    end
                end
            end

            headCache_ = headData
            OnSaveSucceeded()
            print("[SaveSystem] 云端保存成功 (seq=" .. mySeq .. " gen=" .. myGen .. " " .. os.date("%H:%M:%S") .. ")")
            if onSavedCallback_ then onSavedCallback_() end
            if onComplete then onComplete(true) end
        end,
        error = function(code, reason)
            -- 幽灵回调检测
            if myGen ~= saveGeneration_ then
                print("[SaveSystem] 丢弃旧代次错误回调 (gen=" .. myGen .. ")")
                return
            end
            saveTimeoutTimer_ = -1
            OnSaveFailed()
            print("[SaveSystem] 云端保存失败: " .. tostring(reason) .. " (code=" .. tostring(code) .. ")")
            if onComplete then onComplete(false) end
        end,
    })
end

-- ============================================================================
-- 云端读取
-- ============================================================================

--- 从云端加载存档
---@param onComplete fun(saveData: table|nil, err: string|nil)
local function LoadFromCloud(onComplete)
    if not clientCloud then
        print("[SaveSystem] clientCloud 不可用")
        onComplete(nil, "no_cloud")
        return
    end

    loadGeneration_ = loadGeneration_ + 1
    local myLoadGen = loadGeneration_

    -- 第一步：读取 head
    clientCloud:Get(HeadKey(), {
        ok = function(values, _)
            if myLoadGen ~= loadGeneration_ then return end

            local head = values[HeadKey()]
            if not head then
                print("[SaveSystem] 云端无存档 (head 为空)")
                onComplete(nil, "no_save")
                return
            end
            if not head.keys then
                print("[SaveSystem] head 格式无效")
                onComplete(nil, "bad_head")
                return
            end

            headCache_ = head
            saveSeq_ = head.saveSeq or 0
            confirmedSeq_ = saveSeq_  -- 加载时同步确认序列号

            -- 第二步：批量读取所有分组 key
            local batchGet  = clientCloud:BatchGet()
            local groupMeta = {}

            for groupName, info in pairs(head.keys) do
                if info.chunks then
                    groupMeta[groupName] = { single = false, chunks = info.chunks, cs = info.cs }
                    for ci = 0, info.chunks - 1 do
                        batchGet:Key(ChunkKey(groupName, ci))
                    end
                else
                    groupMeta[groupName] = { single = true, cs = info.cs }
                    batchGet:Key(GroupKey(groupName))
                end
            end

            batchGet:Fetch({
                ok = function(values2, _)
                    if myLoadGen ~= loadGeneration_ then return end

                    local groups = {}

                    for groupName, meta in pairs(groupMeta) do
                        if meta.single then
                            local val = values2[GroupKey(groupName)]
                            if val and meta.cs then
                                local json = cjson.encode(val)
                                local actual = CalcChecksum(json)
                                if actual ~= meta.cs then
                                    print("[SaveSystem] 校验失败(单片): " .. groupName
                                        .. " 期望=" .. meta.cs .. " 实际=" .. actual)
                                end
                            end
                            groups[groupName] = val
                        else
                            local parts = {}
                            local valid = true
                            for ci = 0, meta.chunks - 1 do
                                local chunk = values2[ChunkKey(groupName, ci)]
                                if chunk then
                                    if meta.cs and meta.cs[ci + 1] then
                                        local actual = CalcChecksum(chunk)
                                        if actual ~= meta.cs[ci + 1] then
                                            print("[SaveSystem] 校验失败(分片): " .. groupName
                                                .. "_" .. ci .. " 期望=" .. meta.cs[ci + 1]
                                                .. " 实际=" .. actual)
                                        end
                                    end
                                    parts[#parts + 1] = chunk
                                else
                                    print("[SaveSystem] 缺失分片: " .. groupName .. "_" .. ci)
                                    valid = false
                                end
                            end
                            if valid and #parts == meta.chunks then
                                local fullJson = table.concat(parts)
                                local decOk, decoded = pcall(cjson.decode, fullJson)
                                if decOk then
                                    groups[groupName] = decoded
                                else
                                    print("[SaveSystem] 分片解码失败: " .. groupName)
                                end
                            end
                        end
                    end

                    local saveData = SaveBridge.MergeGroups(groups, head.version, head.timestamp)
                    saveData = SaveBridge.RunMigrations(saveData)
                    onComplete(saveData, nil)
                end,
                error = function(code, reason)
                    if myLoadGen ~= loadGeneration_ then return end
                    print("[SaveSystem] 云端读取分组失败: " .. tostring(reason))
                    onComplete(nil, "fetch_error")
                end,
            })
        end,
        error = function(code, reason)
            if myLoadGen ~= loadGeneration_ then return end
            print("[SaveSystem] 云端读取 head 失败: " .. tostring(reason))
            onComplete(nil, "head_error")
        end,
    })
end

-- ============================================================================
-- 公共 API
-- ============================================================================

--- 初始化存档系统（启动时调用一次）
---@param onComplete fun(ok: boolean, offlineTime: number)|nil
function SSS.Init(onComplete)
    if initialized_ then
        if onComplete then onComplete(true, 0) end
        return
    end

    loading_ = true
    print("[SaveSystem] 初始化...")

    LoadFromCloud(function(saveData, err)
        loading_ = false

        if saveData then
            SaveBridge.Deserialize(saveData)

            local offlineTime = 0
            if saveData.timestamp then
                offlineTime = os.time() - saveData.timestamp
                if offlineTime < 0 then offlineTime = 0 end
            end

            SaveLocal(saveData)

            saveConfirmed_ = true
            initialized_   = true
            autoSaveTimer_ = SAVE_INTERVAL

            print("[SaveSystem] 云端存档加载成功 | 离线: " .. offlineTime .. "秒")
            if onComplete then onComplete(true, offlineTime) end
        else
            local localData = LoadLocal()
            if localData then
                print("[SaveSystem] 使用本地缓存存档")
                localData = SaveBridge.RunMigrations(localData)
                SaveBridge.Deserialize(localData)
                saveConfirmed_ = true
                initialized_   = true
                autoSaveTimer_ = SAVE_INTERVAL
                if onComplete then onComplete(true, 0) end
            else
                print("[SaveSystem] 新玩家，无存档数据")
                saveConfirmed_ = true
                initialized_   = true
                autoSaveTimer_ = SAVE_INTERVAL
                if onComplete then onComplete(true, 0) end
            end
        end
    end)
end

--- 常规保存（序列化 → 消毒 → 本地 → 云端）
function SSS.Save()
    if not saveConfirmed_ or saving_ then
        if saving_ then
            -- 保存进行中，标记 pendingSave，完成后用最新数据重发
            pendingSave_ = true
        end
        return
    end
    saving_ = true
    pendingSave_ = false

    local saveData = SaveBridge.Serialize()

    -- 数据消毒：NaN / Inf / 非法类型
    saveData = SanitizeTable(saveData)

    -- 先写本地（同步，确保不丢）
    SaveLocal(saveData)

    -- 再写云端（异步）
    SaveToCloud(saveData, function(ok)
        saving_ = false
        if ok then
            retryCount_ = 0
            retryTimer_ = -1
            -- 检查是否有挂起的保存请求
            if pendingSave_ then
                pendingSave_ = false
                SSS.Save()  -- 用最新数据重发
            end
        else
            -- 安排重试（用最新数据）
            retryCount_ = 0
            retryTimer_ = RETRY_BASE
        end
    end)

    -- 重置计时器
    autoSaveTimer_ = SAVE_INTERVAL
    dirtyTimer_    = -1
end

--- 立即保存（关键事件后调用：飞升、重大购买等）
function SSS.SaveNow()
    if not saveConfirmed_ then return end
    autoSaveTimer_ = SAVE_INTERVAL
    dirtyTimer_    = -1
    if saving_ then
        pendingSave_ = true  -- 进行中则挂起，完成后用最新数据重发
        return
    end
    SSS.Save()
end

--- 标记脏数据（延迟 DIRTY_DELAY 秒后合并为一次 Save）
function SSS.MarkDirty()
    if not saveConfirmed_ then return end
    if dirtyTimer_ < 0 then
        dirtyTimer_ = DIRTY_DELAY
    end
end

--- 每帧更新（管理自动保存 / 脏数据 / 重试 / 超时计时器）
---@param dt number
function SSS.Update(dt)
    if not initialized_ or not saveConfirmed_ then return end

    playTime_ = playTime_ + dt

    -- ---- 超时保护 ----
    if saveTimeoutTimer_ > 0 then
        saveTimeoutTimer_ = saveTimeoutTimer_ - dt
        if saveTimeoutTimer_ <= 0 then
            saveTimeoutTimer_ = -1
            print("[SaveSystem] 云端保存超时 (" .. SAVE_TIMEOUT .. "s)")

            -- 递增 generation 使迟到的回调失效
            saveGeneration_ = saveGeneration_ + 1
            -- 预消耗序列号：即使旧回调到达也无法用旧 seq 覆盖
            confirmedSeq_ = math.max(confirmedSeq_, saveSeq_)

            saving_ = false
            OnSaveFailed()

            -- 检查挂起的保存
            if pendingSave_ then
                pendingSave_ = false
                SSS.Save()
            end
        end
    end

    -- ---- 自动保存（熔断时跳过） ----
    if not savePaused_ then
        autoSaveTimer_ = autoSaveTimer_ - dt
        if autoSaveTimer_ <= 0 then
            autoSaveTimer_ = SAVE_INTERVAL
            if not saving_ then
                SSS.Save()
            end
        end
    end

    -- ---- 脏标记延迟保存 ----
    if dirtyTimer_ > 0 then
        dirtyTimer_ = dirtyTimer_ - dt
        if dirtyTimer_ <= 0 then
            dirtyTimer_ = -1
            if not saving_ and not savePaused_ then
                SSS.Save()
            end
        end
    end

    -- ---- 云端重试（用最新数据） ----
    if retryTimer_ > 0 then
        retryTimer_ = retryTimer_ - dt
        if retryTimer_ <= 0 and not saving_ then
            retryCount_ = retryCount_ + 1
            if retryCount_ <= MAX_RETRY then
                print("[SaveSystem] 云端重试 (" .. retryCount_ .. "/" .. MAX_RETRY .. ")，使用最新数据")
                SSS.Save()
            else
                print("[SaveSystem] 云端重试用尽，等待下次自动保存")
                retryTimer_ = -1
            end
        end
    end
end

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 累计游戏时长（秒）
---@return number
function SSS.GetPlayTime()
    return playTime_
end

--- 系统是否已初始化
---@return boolean
function SSS.IsInitialized()
    return initialized_
end

--- 存档健康状态（已确认且无连续失败）
---@return boolean
function SSS.IsSaveHealthy()
    return saveConfirmed_ and consecutiveFails_ == 0
end

--- 是否正在加载
---@return boolean
function SSS.IsLoading()
    return loading_
end

--- 是否处于熔断状态
---@return boolean
function SSS.IsSavePaused()
    return savePaused_
end

--- 是否显示存档警告
---@return boolean
function SSS.IsWarningShown()
    return warningShown_
end

--- 连续失败次数
---@return number
function SSS.GetConsecutiveFails()
    return consecutiveFails_
end

--- 注册云端保存成功回调
---@param fn fun()
function SSS.OnSaved(fn)
    onSavedCallback_ = fn
end

return SSS
