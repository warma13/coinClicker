-- ============================================================================
-- ui/CoinParticle.lua
-- 点击时生成金币图标，随机抛物线轨迹动画，下落时渐渐消失
-- ============================================================================

local UI = require("urhox-libs/UI")

local CoinParticle = {}

-- 配置
local POOL_SIZE = 8            -- 对象池大小（支持快速连点）
local COIN_SIZE = 32           -- 金币图标尺寸
local GRAVITY = 600            -- 重力加速度（像素/秒²）
local LAUNCH_VY_MIN = -350     -- 初始向上速度最小值（负数=向上）
local LAUNCH_VY_MAX = -200     -- 初始向上速度最大值
local LAUNCH_VX_MIN = -120     -- 水平速度范围
local LAUNCH_VX_MAX = 120
local MAX_LIFE = 1.5           -- 最大存活时间（秒）
local FADE_START = 0.4         -- 剩余生命低于此比例开始淡出

-- 容器引用
local container_ = nil

-- 对象池
local pool = {}        -- {panel, inUse}[]
local activeCoins = {} -- {poolEntry, x, y, vx, vy, life, maxLife}[]
local poolInited = false

--- 创建粒子容器
---@return table UI 定义
function CoinParticle.Create()
    return UI.Panel {
        id = "coinParticleContainer",
        position = "absolute",
        left = 0,
        top = 0,
        width = "100%",
        height = "100%",
        zIndex = 150,
        pointerEvents = "none",
    }
end

--- 初始化：缓存容器，创建对象池
---@param root table UI 根节点
function CoinParticle.Init(root)
    container_ = root:FindById("coinParticleContainer")
    if not container_ then
        print("[CoinParticle] WARNING: container not found!")
        return
    end

    if not poolInited then
        for i = 1, POOL_SIZE do
            local panel = UI.Panel {
                id = "cp_" .. i,
                position = "absolute",
                left = 0,
                top = 0,
                width = COIN_SIZE,
                height = COIN_SIZE,
                backgroundImage = "image/金币.png",
                backgroundFit = "contain",
                opacity = 1.0,
                pointerEvents = "none",
            }
            container_:AddChild(panel)
            local ref = container_:FindById("cp_" .. i)
            if ref then
                ref:SetVisible(false)
                pool[i] = { panel = ref, inUse = false }
            end
        end
        poolInited = true
    end

    activeCoins = {}
end

--- 从池中获取空闲项
---@return table|nil
local function Acquire()
    for i = 1, POOL_SIZE do
        if not pool[i].inUse then
            pool[i].inUse = true
            return pool[i]
        end
    end
    return nil
end

--- 归还到池
---@param entry table
local function Release(entry)
    entry.inUse = false
    entry.panel:SetVisible(false)
end

--- 在指定位置生成一个金币粒子
---@param x number 点击位置逻辑 X
---@param y number 点击位置逻辑 Y
function CoinParticle.Spawn(x, y)
    if not container_ then return end

    local entry = Acquire()
    if not entry then
        -- 池满，回收最旧的
        if #activeCoins > 0 then
            local removed = table.remove(activeCoins, 1)
            Release(removed.poolEntry)
            entry = Acquire()
        end
        if not entry then return end
    end

    -- 随机初速度
    local vx = LAUNCH_VX_MIN + math.random() * (LAUNCH_VX_MAX - LAUNCH_VX_MIN)
    local vy = LAUNCH_VY_MIN + math.random() * (LAUNCH_VY_MAX - LAUNCH_VY_MIN)

    -- 居中于点击位置
    local startX = x - COIN_SIZE * 0.5
    local startY = y - COIN_SIZE * 0.5

    entry.panel:SetStyle({
        left = math.floor(startX),
        top = math.floor(startY),
        opacity = 1.0,
    })
    entry.panel:SetVisible(true)

    activeCoins[#activeCoins + 1] = {
        poolEntry = entry,
        x = startX,
        y = startY,
        vx = vx,
        vy = vy,
        life = MAX_LIFE,
        maxLife = MAX_LIFE,
    }
end

--- 每帧更新
---@param dt number
function CoinParticle.Update(dt)
    if not container_ then return end

    for i = #activeCoins, 1, -1 do
        local c = activeCoins[i]
        c.life = c.life - dt

        if c.life <= 0 then
            Release(c.poolEntry)
            table.remove(activeCoins, i)
        else
            -- 物理模拟
            c.vy = c.vy + GRAVITY * dt
            c.x = c.x + c.vx * dt
            c.y = c.y + c.vy * dt

            -- 淡出：下落阶段（vy > 0）且剩余生命较低时开始淡出
            local lifeRatio = c.life / c.maxLife
            local alpha = 1.0
            if lifeRatio < FADE_START then
                alpha = lifeRatio / FADE_START
            end

            c.poolEntry.panel:SetStyle({
                left = math.floor(c.x),
                top = math.floor(c.y),
                opacity = alpha,
            })
        end
    end
end

return CoinParticle
