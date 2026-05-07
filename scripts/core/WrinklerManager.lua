-- ============================================================================
-- core/WrinklerManager.lua
-- 皱巴虫管理器：生成、吸取 CpS、弹出返还
-- ============================================================================

local GameState = require("core.GameState")
local GD = require("config.GrandmapocalypseDefs")
local SaveBridge = require("core.SaveBridge")

local WM = {}

-- ======== 状态 ========
-- 每只皱巴虫: { id, absorbed, spawnTime, angle }
local wrinklers_ = {}
local nextId_ = 1
local spawnTimer_ = 0

-- 回调
local onSpawn_ = nil    -- function(wrinkler)
local onPop_ = nil      -- function(wrinkler, reward)

-- ============================================================================
-- 初始化
-- ============================================================================

function WM.Init()
    wrinklers_ = {}
    nextId_ = 1
    spawnTimer_ = 0
end

function WM.SetOnSpawn(fn) onSpawn_ = fn end
function WM.SetOnPop(fn) onPop_ = fn end

-- ============================================================================
-- 查询
-- ============================================================================

function WM.GetCount() return #wrinklers_ end
function WM.GetAll() return wrinklers_ end

--- 获取皱巴虫总吸取量
function WM.GetTotalAbsorbed()
    local total = 0
    for _, w in ipairs(wrinklers_) do
        total = total + w.absorbed
    end
    return total
end

--- 获取当前吸取系数（所有虫的总吸取比例）
---@return number drainFactor (0~1 之间，实际从 CpS 中扣除的比例)
function WM.GetDrainFactor()
    return #wrinklers_ * GD.wrinkler.drainPercent
end

-- ============================================================================
-- 操作
-- ============================================================================

--- 生成一只皱巴虫
local function SpawnWrinkler()
    if #wrinklers_ >= GD.wrinkler.maxCount then return end

    local w = {
        id = nextId_,
        absorbed = 0,
        spawnTime = time.elapsedTime,
        -- 在金币周围随机位置（用角度表示）
        angle = math.random() * math.pi * 2,
    }
    nextId_ = nextId_ + 1
    wrinklers_[#wrinklers_ + 1] = w

    if onSpawn_ then onSpawn_(w) end
    print("[Wrinkler] 皱巴虫出现! 当前: " .. #wrinklers_ .. "/" .. GD.wrinkler.maxCount)
end

--- 弹出指定皱巴虫（点击移除，返还吸取量 ×1.1）
---@param index number 在 wrinklers_ 数组中的索引
---@return number reward 返还的金币
function WM.Pop(index)
    local w = wrinklers_[index]
    if not w then return 0 end

    local reward = w.absorbed * GD.wrinkler.popMultiplier
    GameState.coins = GameState.coins + reward
    GameState.wrinklersPopped = GameState.wrinklersPopped + 1
    table.remove(wrinklers_, index)

    if onPop_ then onPop_(w, reward) end
    print("[Wrinkler] 弹出皱巴虫! 返还: " .. GameState.FormatNumber(reward) ..
          " 剩余: " .. #wrinklers_)
    return reward
end

--- 弹出所有皱巴虫
---@return number totalReward
function WM.PopAll()
    local total = 0
    for i = #wrinklers_, 1, -1 do
        total = total + WM.Pop(i)
    end
    return total
end

--- 根据 ID 弹出
---@param id number
---@return number reward
function WM.PopById(id)
    for i, w in ipairs(wrinklers_) do
        if w.id == id then
            return WM.Pop(i)
        end
    end
    return 0
end

-- ============================================================================
-- 帧更新
-- ============================================================================

--- 每帧调用
---@param dt number
---@param spawnRate number 当前阶段的生成速率倍率（0=不生成）
--- 每帧调用
---@param dt number
---@param spawnRate number 当前阶段的生成速率倍率（0=不生成）
---@param effectiveCps number|nil 当前有效 CpS（含 buff），nil 则自动计算
---@return number totalDrained 本帧总吸取量（调用方需从金币中扣除）
function WM.Update(dt, spawnRate, effectiveCps)
    local totalDrained = 0

    -- ===== 吸取 CpS =====
    -- 每只虫吸取有效 CpS 的 drainPercent
    local cps = effectiveCps or (GameState.coinsPerSecond * (GameState.buffCpsMul or 1))
    if #wrinklers_ > 0 and cps > 0 then
        local drainPerWrinkler = cps * GD.wrinkler.drainPercent * dt
        for _, w in ipairs(wrinklers_) do
            w.absorbed = w.absorbed + drainPerWrinkler
            totalDrained = totalDrained + drainPerWrinkler
        end
    end

    -- ===== 生成 =====
    if spawnRate > 0 and #wrinklers_ < GD.wrinkler.maxCount then
        spawnTimer_ = spawnTimer_ + dt * spawnRate
        if spawnTimer_ >= GD.wrinkler.spawnInterval then
            spawnTimer_ = spawnTimer_ - GD.wrinkler.spawnInterval
            SpawnWrinkler()
        end
    end

    return totalDrained
end

--- 调试：立即填满黑洞
function WM.DebugFillWrinklers()
    while #wrinklers_ < GD.wrinkler.maxCount do
        SpawnWrinkler()
    end
end

-- ============================================================================
-- 存档/读档
-- ============================================================================

--- 导出存档数据
---@return table
function WM.GetSaveData()
    local list = {}
    for _, w in ipairs(wrinklers_) do
        list[#list + 1] = { absorbed = w.absorbed, angle = w.angle }
    end
    return {
        wrinklers = list,
        nextId = nextId_,
        spawnTimer = spawnTimer_,
    }
end

--- 从存档恢复数据
---@param data table
function WM.LoadSaveData(data)
    if not data then return end
    wrinklers_ = {}
    nextId_ = data.nextId or 1
    spawnTimer_ = data.spawnTimer or 0
    if data.wrinklers then
        for _, wd in ipairs(data.wrinklers) do
            wrinklers_[#wrinklers_ + 1] = {
                id = nextId_,
                absorbed = wd.absorbed or 0,
                spawnTime = time.elapsedTime,
                angle = wd.angle or (math.random() * math.pi * 2),
            }
            nextId_ = nextId_ + 1
        end
    end
    print("[WrinklerManager] 存档恢复 | 皱巴虫:" .. #wrinklers_)
end

return WM
