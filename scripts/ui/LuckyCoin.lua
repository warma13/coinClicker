-- ============================================================================
-- ui/LuckyCoin.lua
-- 幸运金币浮动面板 + 效果提示标签
-- 动画效果：初始大尺寸 → 左右摇摆旋转 → 逐渐缩小 → 消失
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")

local LuckyCoin = {}

-- 缓存的 UI 引用
local luckyPanel_ = nil
local luckyEffectLabel_ = nil
local isWrath_ = false

-- 动画参数
local INITIAL_SCALE = 1.8      -- 初始缩放（出现时大）
local FINAL_SCALE = 0.0        -- 最终缩放（消失）
local SWING_AMPLITUDE = 15     -- 摇摆角度幅度（度）
local SWING_SPEED = 3.5        -- 摇摆速度
local BASE_COIN_SIZE = 72      -- 设计基准面板尺寸

-- 根据屏幕逻辑分辨率按比例缩放：以短边 540 逻辑像素为基准(1.0x)
-- 手机短边通常 320~414，系数 1.3~1.7；平板/PC 540+ 保持 1.0
local function CalcScreenScale()
    local dpr = graphics:GetDPR()
    local logW = graphics:GetWidth() / dpr
    local logH = graphics:GetHeight() / dpr
    local shortSide = math.min(logW, logH)
    local REF_SHORT = 540
    local scale = REF_SHORT / math.max(shortSide, 1)
    -- 限制范围：最小 1.0（不缩小），最大 2.0（极小屏幕也不过度放大）
    return math.max(1.0, math.min(scale, 2.0))
end

local screenScale_ = 1.0       -- 延迟到 Init 时计算
local COIN_SIZE = BASE_COIN_SIZE

--- 创建幸运金币 UI 定义（absolute 定位的浮动面板 + 效果提示）
---@param onTap function 点击幸运金币的回调
---@return table panel 浮动面板定义
---@return table effectLabel 效果提示定义
function LuckyCoin.Create(onTap)
    local panel = UI.Panel {
        id = "luckyPanel",
        position = "absolute",
        left = 0,
        top = 0,
        width = COIN_SIZE,
        height = COIN_SIZE,
        borderRadius = COIN_SIZE / 2,
        justifyContent = "center",
        alignItems = "center",
        zIndex = 100,
        pointerEvents = "auto",
        scale = INITIAL_SCALE,
        rotate = 0,
        transformOrigin = "center",
        onPointerDown = function(self)
            if GameState.luckyActive then
                GameState.luckyActive = false
                onTap()
            end
        end,
        children = {
            UI.Panel {
                id = "luckyCoinImage",
                width = COIN_SIZE,
                height = COIN_SIZE,
                backgroundImage = "image/幸运金币.png",
                backgroundFit = "contain",
                pointerEvents = "none",
            },
        },
    }

    local effectLabel = UI.Label {
        id = "luckyEffectLabel",
        position = "absolute",
        top = 80,
        left = 0,
        right = 0,
        text = "",
        fontSize = 20,
        fontColor = { 255, 215, 0, 255 },
        textAlign = "center",
        zIndex = 101,
        pointerEvents = "none",
    }

    return panel, effectLabel
end

--- 初始化：缓存引用，计算屏幕缩放系数
---@param root table UI 根节点
function LuckyCoin.Init(root)
    -- 计算屏幕缩放系数
    screenScale_ = CalcScreenScale()
    COIN_SIZE = math.floor(BASE_COIN_SIZE * screenScale_)
    -- 同步更新 GameState 中用于定位边距的尺寸
    GameState.luckySize = COIN_SIZE

    luckyPanel_ = root:FindById("luckyPanel")
    luckyEffectLabel_ = root:FindById("luckyEffectLabel")

    -- 应用缩放后的尺寸到面板
    if luckyPanel_ then
        luckyPanel_:SetStyle({
            width = COIN_SIZE,
            height = COIN_SIZE,
            borderRadius = math.floor(COIN_SIZE / 2),
        })
        local imgPanel = luckyPanel_:FindById("luckyCoinImage")
        if imgPanel then
            imgPanel:SetStyle({
                width = COIN_SIZE,
                height = COIN_SIZE,
            })
        end
        luckyPanel_:SetVisible(false)
    end
    if luckyEffectLabel_ then
        luckyEffectLabel_:SetStyle({
            top = COIN_SIZE + 8,
            fontSize = math.floor(20 * screenScale_),
        })
        luckyEffectLabel_:SetVisible(false)
    end
end

--- 显示幸运金币
---@param x number X 坐标
---@param y number Y 坐标
function LuckyCoin.Show(x, y)
    if luckyPanel_ then
        luckyPanel_:SetStyle({
            left = math.floor(x),
            top = math.floor(y),
            scale = INITIAL_SCALE,
            rotate = 0,
            opacity = 1.0,
        })
        luckyPanel_:SetVisible(true)
    end
end

--- 隐藏幸运金币
function LuckyCoin.Hide()
    if luckyPanel_ then
        luckyPanel_:SetVisible(false)
    end
end

--- 更新浮动动画：摇摆旋转 + 逐渐缩小
---@param dt number 帧时间
function LuckyCoin.UpdateAnimation(dt)
    local S = GameState
    if not S.luckyActive or not luckyPanel_ then return end

    local totalLife = S.luckyMaxLife * S.luckyStayMul
    local elapsed = totalLife - S.luckyLifetime
    local progress = math.min(1.0, elapsed / totalLife)  -- 0→1 生命进度

    -- 摇摆旋转：sin 波左右摆动
    S.luckyFloatPhase = S.luckyFloatPhase + dt * SWING_SPEED
    local swingAngle = math.sin(S.luckyFloatPhase) * SWING_AMPLITUDE

    -- 缩小：从大到小，使用缓出曲线让前期缩得慢、后期缩得快
    local scaleProg = progress * progress  -- ease-in 曲线
    local baseScale = INITIAL_SCALE + (FINAL_SCALE - INITIAL_SCALE) * scaleProg

    -- 脉冲缩放：在整体缩小的同时叠加呼吸式放缩
    local pulseAmount = 0.15 * (1.0 - progress)  -- 脉冲幅度随缩小逐渐减弱
    local pulse = math.sin(S.luckyFloatPhase * 2.0) * pulseAmount
    local currentScale = baseScale + pulse

    -- 上下浮动
    local floatOffset = math.sin(S.luckyFloatPhase * 0.7) * 4

    -- 最后 3 秒透明度闪烁
    local alpha = 1.0
    if S.luckyLifetime < 3 then
        local blink = math.sin(S.luckyLifetime * 8) * 0.5 + 0.5
        alpha = 0.3 + 0.7 * blink
    end

    luckyPanel_:SetStyle({
        top = math.floor(S.luckyPosY + floatOffset),
        scale = math.max(0.1, currentScale),
        rotate = swingAngle,
        opacity = alpha,
    })
end

--- 显示效果提示文字
---@param text string 提示内容
function LuckyCoin.ShowEffect(text)
    if luckyEffectLabel_ then
        luckyEffectLabel_:SetText(text)
        luckyEffectLabel_:SetVisible(true)
    end
end

--- 隐藏效果提示
function LuckyCoin.HideEffect()
    if luckyEffectLabel_ then
        luckyEffectLabel_:SetVisible(false)
    end
end

--- 设置愤怒金币外观
---@param wrath boolean
function LuckyCoin.SetWrath(wrath)
    isWrath_ = wrath
    if not luckyPanel_ then return end
    local imgPanel = luckyPanel_:FindById("luckyCoinImage")
    if wrath then
        -- 愤怒金币：加红色叠色
        if imgPanel then
            imgPanel:SetStyle({ imageTint = { 255, 80, 60, 255 } })
        end
    else
        -- 正常金币：无叠色
        if imgPanel then
            imgPanel:SetStyle({ imageTint = nil })
        end
    end
end

return LuckyCoin
