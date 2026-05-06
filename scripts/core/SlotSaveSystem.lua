-- ============================================================================
-- core/SlotSaveSystem.lua
-- 单槽位云端存档系统：云端优先 · 本地缓存 · 自动分片 · 自动保存
-- 对外唯一入口，业务层通过 Save/SaveNow/MarkDirty 触发存档
-- ============================================================================

---@diagnostic disable: undefined-global
-- cjson 是引擎内置全局模块（JSON 编解码）

local SaveBridge = require("core.SaveBridge")

local SSS = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------

local SLOT_ID        = 1       -- 单槽位，固定为 1
local SAVE_INTERVAL  = 10      -- 自动保存间隔（秒）
local DIRTY_DELAY    = 5       -- MarkDirty 延迟合并（秒）
local CHUNK_SIZE     = 9000    -- 单分片最大字节数（预留 key 开销）
local MAX_RETRY      = 3       -- 云端保存最大重试次数
local RETRY_BASE     = 3       -- 重试基础间隔（秒），指数退避 3^n
local LOCAL_FILE     = "save_slot1.json"

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------

local initialized_    = false
local saveConfirmed_  = false   -- 加载/新建成功后为 true，才允许自动保存
local saveSeq_        = 0       -- 保存序列号，每次成功保存递增
local playTime_       = 0       -- 累计游戏时长
local autoSaveTimer_  = 0       -- 自动保存倒计时
local dirtyTimer_     = -1      -- MarkDirty 延迟倒计时（< 0 表示无脏标记）
local retryTimer_     = -1      -- 云端重试倒计时
local retryCount_     = 0
local pendingSave_    = nil     -- 待重试的存档数据
local headCache_      = nil     -- 最近一次写入的 head（用于清理旧分片）
local saving_         = false   -- 防止并发保存
local loading_        = false
local onSavedCallback_ = nil   -- 保存成功外部回调

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
-- 本地文件缓存
-- ============================================================================

--- 同步写入本地文件
---@param saveData table
---@return boolean ok
local function SaveLocal(saveData)
    local ok, json = pcall(cjson.encode, saveData)
    if not ok then
        print("[SaveSystem] 本地编码失败: " .. tostring(json))
        return false
    end
    local file = File(LOCAL_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(json)
        file:Close()
        return true
    end
    print("[SaveSystem] 本地文件写入失败")
    return false
end

--- 同步读取本地文件
---@return table|nil
local function LoadLocal()
    if not fileSystem:FileExists(LOCAL_FILE) then return nil end
    local file = File(LOCAL_FILE, FILE_READ)
    if not file:IsOpen() then return nil end
    local str = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, str)
    if ok then return data end
    print("[SaveSystem] 本地文件解码失败")
    return nil
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

    -- 构建 head 索引
    saveSeq_ = saveSeq_ + 1
    local headData = {
        format    = 1,
        version   = version,
        timestamp = timestamp,
        slotId    = SLOT_ID,
        saveSeq   = saveSeq_,
        keys      = {},
    }

    local batch = clientCloud:BatchSet()

    for groupName, groupData in pairs(groups) do
        if groupData then
            local chunks, checksums, totalLen = EncodeGroup(groupData)

            if #chunks == 1 then
                -- 单片：直接存表（云端自动 JSON 编码）
                headData.keys[groupName] = {
                    cs  = checksums[1],
                    len = totalLen,
                }
                batch:Set(GroupKey(groupName), groupData)
            else
                -- 多片：存原始 JSON 字符串分片
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

    -- 提交
    batch:Save("自动存档", {
        ok = function()
            -- 清理旧分片残留（分片数量减少时）
            if headCache_ and headCache_.keys then
                for gn, oldInfo in pairs(headCache_.keys) do
                    if oldInfo.chunks then
                        local newInfo = headData.keys[gn]
                        local newChunks = (newInfo and newInfo.chunks) or 0
                        -- 如果之前是多片、现在单片或更少片，删除多余 key
                        if newChunks == 0 or (type(newChunks) ~= "number") then
                            -- 变成了单片，删除所有旧分片
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
            print("[SaveSystem] 云端保存成功 (seq=" .. saveSeq_ .. " " .. os.date("%H:%M:%S") .. ")")
            if onSavedCallback_ then onSavedCallback_() end
            if onComplete then onComplete(true) end
        end,
        error = function(code, reason)
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

    -- 第一步：读取 head
    clientCloud:Get(HeadKey(), {
        ok = function(values, _)
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

            -- 第二步：批量读取所有分组 key
            local batchGet  = clientCloud:BatchGet()
            local groupMeta = {} -- groupName → { single, chunks, cs }

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
                    local groups = {}

                    for groupName, meta in pairs(groupMeta) do
                        if meta.single then
                            -- 单片：云端自动 JSON 解码为 table
                            local val = values2[GroupKey(groupName)]
                            -- 校验 checksum
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
                            -- 多片：拼接 JSON 字符串后解码
                            local parts = {}
                            local valid = true
                            for ci = 0, meta.chunks - 1 do
                                local chunk = values2[ChunkKey(groupName, ci)]
                                if chunk then
                                    -- 校验每片 checksum
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

                    -- 合并为完整存档
                    local saveData = SaveBridge.MergeGroups(groups, head.version, head.timestamp)

                    -- 版本迁移
                    saveData = SaveBridge.RunMigrations(saveData)

                    onComplete(saveData, nil)
                end,
                error = function(code, reason)
                    print("[SaveSystem] 云端读取分组失败: " .. tostring(reason))
                    onComplete(nil, "fetch_error")
                end,
            })
        end,
        error = function(code, reason)
            print("[SaveSystem] 云端读取 head 失败: " .. tostring(reason))
            onComplete(nil, "head_error")
        end,
    })
end

-- ============================================================================
-- 公共 API
-- ============================================================================

--- 初始化存档系统（启动时调用一次）
--- 自动从云端加载，若无存档则视为新玩家
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
            -- 恢复运行时状态
            SaveBridge.Deserialize(saveData)

            -- 计算离线时长
            local offlineTime = 0
            if saveData.timestamp then
                offlineTime = os.time() - saveData.timestamp
                if offlineTime < 0 then offlineTime = 0 end
            end

            -- 缓存到本地
            SaveLocal(saveData)

            saveConfirmed_ = true
            initialized_   = true
            autoSaveTimer_ = SAVE_INTERVAL

            print("[SaveSystem] 云端存档加载成功 | 离线: " .. offlineTime .. "秒")
            if onComplete then onComplete(true, offlineTime) end
        else
            -- 云端失败或无存档 → 尝试本地缓存
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
                -- 新玩家
                print("[SaveSystem] 新玩家，无存档数据")
                saveConfirmed_ = true
                initialized_   = true
                autoSaveTimer_ = SAVE_INTERVAL
                if onComplete then onComplete(true, 0) end
            end
        end
    end)
end

--- 常规保存（序列化 → 本地 → 云端）
function SSS.Save()
    if not saveConfirmed_ or saving_ then return end
    saving_ = true

    local saveData = SaveBridge.Serialize()

    -- 先写本地（同步，确保不丢）
    SaveLocal(saveData)

    -- 再写云端（异步）
    SaveToCloud(saveData, function(ok)
        saving_ = false
        if not ok then
            -- 安排重试
            pendingSave_ = saveData
            retryCount_  = 0
            retryTimer_  = RETRY_BASE
        else
            pendingSave_ = nil
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
    if saving_ then return end
    SSS.Save()
end

--- 标记脏数据（延迟 DIRTY_DELAY 秒后合并为一次 Save）
function SSS.MarkDirty()
    if not saveConfirmed_ then return end
    if dirtyTimer_ < 0 then
        dirtyTimer_ = DIRTY_DELAY
    end
end

--- 每帧更新（管理自动保存 / 脏数据 / 重试计时器）
---@param dt number
function SSS.Update(dt)
    if not initialized_ or not saveConfirmed_ then return end

    -- 累计游戏时长
    playTime_ = playTime_ + dt

    -- ---- 自动保存 ----
    autoSaveTimer_ = autoSaveTimer_ - dt
    if autoSaveTimer_ <= 0 then
        autoSaveTimer_ = SAVE_INTERVAL
        if not saving_ then
            SSS.Save()
        end
    end

    -- ---- 脏标记延迟保存 ----
    if dirtyTimer_ > 0 then
        dirtyTimer_ = dirtyTimer_ - dt
        if dirtyTimer_ <= 0 then
            dirtyTimer_ = -1
            if not saving_ then
                SSS.Save()
            end
        end
    end

    -- ---- 云端重试 ----
    if retryTimer_ > 0 then
        retryTimer_ = retryTimer_ - dt
        if retryTimer_ <= 0 and pendingSave_ and not saving_ then
            retryCount_ = retryCount_ + 1
            if retryCount_ <= MAX_RETRY then
                print("[SaveSystem] 云端重试 (" .. retryCount_ .. "/" .. MAX_RETRY .. ")")
                saving_ = true
                SaveToCloud(pendingSave_, function(ok)
                    saving_ = false
                    if ok then
                        pendingSave_ = nil
                        retryTimer_  = -1
                    else
                        -- 指数退避
                        retryTimer_ = RETRY_BASE * (3 ^ retryCount_)
                    end
                end)
            else
                print("[SaveSystem] 云端重试用尽，等待下次自动保存")
                pendingSave_ = nil
                retryTimer_  = -1
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

--- 存档健康状态（已确认且无待重试数据）
---@return boolean
function SSS.IsSaveHealthy()
    return saveConfirmed_ and pendingSave_ == nil
end

--- 是否正在加载
---@return boolean
function SSS.IsLoading()
    return loading_
end

--- 注册云端保存成功回调
---@param fn fun()
function SSS.OnSaved(fn)
    onSavedCallback_ = fn
end

return SSS
