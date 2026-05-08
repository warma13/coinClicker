-- ============================================================================
-- ui/CoinParticle.lua
-- 点击时生成金币图标，随机抛物线轨迹动画，下落时渐渐消失
-- 使用 NanoVG 直接绘制，避免 UI 组件的 Yoga 布局开销
-- ============================================================================

local UI = require("urhox-libs/UI")

local CoinParticle = {}

-- 配置
local POOL_SIZE = 8            -- 最大同时粒子数
local COIN_SIZE = 32           -- 金币图标尺寸（逻辑像素）
local GRAVITY = 600            -- 重力加速度（像素/秒²）
local LAUNCH_VY_MIN = -350     -- 初始向上速度最小值（负数=向上）
local LAUNCH_VY_MAX = -200     -- 初始向上速度最大值
local LAUNCH_VX_MIN = -120     -- 水平速度范围
local LAUNCH_VX_MAX = 120
local MAX_LIFE = 1.5           -- 最大存活时间（秒）
local FADE_START = 0.4         -- 剩余生命低于此比例开始淡出

-- NanoVG 资源（由 main.lua 通过 InitNVG 注入）
local vg_ = nil
local coinImage_ = -1

-- 活跃粒子（纯数据，无 UI 引用）
local activeCoins = {}

--- 创建占位容器（保持 AppLayout 兼容，不包含任何子元素）
---@return table UI 定义
function CoinParticle.Create()
    return UI.Panel {
        id = "coinParticleContainer",
        position = "absolute",
        left = 0, top = 0,
        width = 0, height = 0,
        pointerEvents = "none",
    }
end

--- 初始化（重置状态）
---@param root table UI 根节点（保留参数兼容）
function CoinParticle.Init(root)
    activeCoins = {}
end

--- 设置 NanoVG 资源（由 main.lua 创建 vg 上下文后调用）
---@param vg userdata NanoVG 上下文
function CoinParticle.InitNVG(vg)
    vg_ = vg
    if vg_ and coinImage_ < 0 then
        coinImage_ = nvgCreateImage(vg_, "image/金币.png", 0)
        if coinImage_ < 0 then
            print("[CoinParticle] WARNING: failed to load coin image")
        end
    end
end

--- 在指定位置生成一个金币粒子
---@param x number 点击位置逻辑 X
---@param y number 点击位置逻辑 Y
function CoinParticle.Spawn(x, y)
    if not vg_ then return end

    -- 池满，回收最旧的
    if #activeCoins >= POOL_SIZE then
        table.remove(activeCoins, 1)
    end

    -- 随机初速度
    local vx = LAUNCH_VX_MIN + math.random() * (LAUNCH_VX_MAX - LAUNCH_VX_MIN)
    local vy = LAUNCH_VY_MIN + math.random() * (LAUNCH_VY_MAX - LAUNCH_VY_MIN)

    -- 居中于点击位置
    local startX = x - COIN_SIZE * 0.5
    local startY = y - COIN_SIZE * 0.5

    activeCoins[#activeCoins + 1] = {
        x = startX,
        y = startY,
        vx = vx,
        vy = vy,
        life = MAX_LIFE,
        maxLife = MAX_LIFE,
    }
end

--- 每帧物理模拟（纯数据运算，无 UI 调用）
---@param dt number
function CoinParticle.Update(dt)
    if #activeCoins == 0 then return end

    for i = #activeCoins, 1, -1 do
        local c = activeCoins[i]
        c.life = c.life - dt

        if c.life <= 0 then
            table.remove(activeCoins, i)
        else
            c.vy = c.vy + GRAVITY * dt
            c.x = c.x + c.vx * dt
            c.y = c.y + c.vy * dt
        end
    end
end

--- NanoVG 渲染（在 nvgBeginFrame/nvgEndFrame 之间由 main.lua 调用）
---@param vg userdata NanoVG 上下文
function CoinParticle.Render(vg)
    if #activeCoins == 0 then return end
    if coinImage_ < 0 then return end

    for _, c in ipairs(activeCoins) do
        local lifeRatio = c.life / c.maxLife
        local alpha = 1.0
        if lifeRatio < FADE_START then
            alpha = lifeRatio / FADE_START
        end

        local paint = nvgImagePattern(vg, c.x, c.y, COIN_SIZE, COIN_SIZE, 0, coinImage_, alpha)
        nvgBeginPath(vg)
        nvgRect(vg, c.x, c.y, COIN_SIZE, COIN_SIZE)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end
end

return CoinParticle
