-- ============================================================================
-- ui/FloatingText.lua
-- 浮动文本工具：在指定位置显示文本，向上浮动渐渐消失
-- 最多同时显示 3 条，超过会把旧的快速顶掉
-- 使用 NanoVG 直接绘制，避免 UI 组件的 Yoga 布局开销
-- ============================================================================

local UI = require("urhox-libs/UI")

local FloatingText = {}

-- 配置
local MAX_VISIBLE = 3
local FLOAT_SPEED = 50         -- 向上浮动速度（像素/秒）
local NORMAL_LIFE = 2.5        -- 正常存活时间（秒）
local FAST_FADE_LIFE = 0.2     -- 被顶掉时快速淡出时间（秒）
local BASE_FONT_SIZE = 20      -- 基础字号
local ICON_SIZE = 20           -- 图标尺寸

-- NanoVG 资源（由 main.lua 通过 InitNVG 注入）
local vg_ = nil
local fontId_ = -1
local iconCache_ = {}          -- path -> nvgImageHandle

-- 活跃文本队列（纯数据）
local activeTexts = {}

--- 创建占位容器（保持 AppLayout 兼容，不包含任何子元素）
---@return table container UI 定义
function FloatingText.Create()
    return UI.Panel {
        id = "floatingTextContainer",
        position = "absolute",
        left = 0, top = 0,
        width = 0, height = 0,
        pointerEvents = "none",
    }
end

--- 初始化（重置状态）
---@param root table UI 根节点（保留参数兼容）
function FloatingText.Init(root)
    activeTexts = {}
end

--- 设置 NanoVG 资源（由 main.lua 创建 vg 上下文后调用）
---@param vg userdata NanoVG 上下文
function FloatingText.InitNVG(vg)
    vg_ = vg
    if vg_ and fontId_ < 0 then
        fontId_ = nvgCreateFont(vg_, "sans", "Fonts/MiSans-Regular.ttf")
        if fontId_ < 0 then
            print("[FloatingText] WARNING: failed to load font")
        end
    end
end

--- 获取/缓存图标的 NanoVG 图像句柄
---@param path string 图标路径
---@return number imageHandle
local function GetIconImage(path)
    if not vg_ then return -1 end
    if not iconCache_[path] then
        iconCache_[path] = nvgCreateImage(vg_, path, 0)
    end
    return iconCache_[path]
end

--- 显示一条浮动文本（可带图标）
---@param text string 要显示的文本
---@param x number 逻辑坐标 X（点击位置）
---@param y number 逻辑坐标 Y（点击位置）
---@param color table|nil 颜色 {r,g,b,a}，默认白色
---@param icon string|nil 图标图片路径（可选）
---@param duration number|nil 存活时间（秒），默认 NORMAL_LIFE
function FloatingText.Show(text, x, y, color, icon, duration)
    if not vg_ then return end

    local c = color or { 255, 255, 255, 255 }

    -- 超过上限，最旧的快速淡出
    if #activeTexts >= MAX_VISIBLE then
        local oldest = activeTexts[1]
        oldest.life = math.min(oldest.life, FAST_FADE_LIFE)
        oldest.maxLife = oldest.life
        oldest.fastFade = true
    end

    -- 溢出保护：丢弃最旧的条目
    if #activeTexts >= MAX_VISIBLE + 1 then
        table.remove(activeTexts, 1)
    end

    -- 缓存图标图像（在渲染循环外创建，安全）
    local iconImg = -1
    if icon then
        iconImg = GetIconImage(icon)
    end

    -- 计算生成位置：避开已有文本，向下堆叠
    local spawnY = y - 30
    local LINE_HEIGHT = BASE_FONT_SIZE + 8
    for _, existing in ipairs(activeTexts) do
        if not existing.fastFade then
            local existingY = existing.spawnY - existing.elapsed * FLOAT_SPEED
            if math.abs(existingY - spawnY) < LINE_HEIGHT then
                spawnY = existingY + LINE_HEIGHT
            end
        end
    end

    local lifeTime = duration or NORMAL_LIFE
    activeTexts[#activeTexts + 1] = {
        text = text,
        x = x,
        spawnY = spawnY,
        elapsed = 0,
        life = lifeTime,
        maxLife = lifeTime,
        baseColor = { c[1], c[2], c[3] },
        fastFade = false,
        iconImg = iconImg,
    }
end

--- 每帧生命周期更新（纯数据运算，无 UI 调用）
---@param dt number 帧时间
function FloatingText.Update(dt)
    if #activeTexts == 0 then return end

    for i = #activeTexts, 1, -1 do
        local entry = activeTexts[i]
        entry.elapsed = entry.elapsed + dt
        entry.life = entry.life - dt

        if entry.life <= 0 then
            table.remove(activeTexts, i)
        end
    end
end

--- NanoVG 渲染（在 nvgBeginFrame/nvgEndFrame 之间由 main.lua 调用）
---@param vg userdata NanoVG 上下文
function FloatingText.Render(vg)
    if #activeTexts == 0 then return end
    if fontId_ < 0 then return end

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, BASE_FONT_SIZE)
    nvgTextAlign(vg, NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)

    for _, entry in ipairs(activeTexts) do
        local speed = entry.fastFade and (FLOAT_SPEED * 3) or FLOAT_SPEED
        local currentY = entry.spawnY - entry.elapsed * speed

        -- 淡出计算
        local alpha = math.floor(255 * math.min(1, entry.life / (entry.maxLife * 0.5)))
        alpha = math.max(0, math.min(255, alpha))

        local bc = entry.baseColor
        local drawX = entry.x

        -- 绘制图标（如果有）
        if entry.iconImg >= 0 then
            local iconAlpha = alpha / 255
            local iconX = drawX - ICON_SIZE * 0.5 - 4
            local iconY = currentY - ICON_SIZE * 0.5
            local paint = nvgImagePattern(vg, iconX, iconY, ICON_SIZE, ICON_SIZE, 0, entry.iconImg, iconAlpha)
            nvgBeginPath(vg)
            nvgRect(vg, iconX, iconY, ICON_SIZE, ICON_SIZE)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
            drawX = drawX + ICON_SIZE * 0.5 + 4
        end

        -- 文本阴影（增强可读性）
        nvgFontBlur(vg, 2)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, alpha))
        nvgText(vg, drawX, currentY, entry.text)

        -- 正文
        nvgFontBlur(vg, 0)
        nvgFillColor(vg, nvgRGBA(bc[1], bc[2], bc[3], alpha))
        nvgText(vg, drawX, currentY, entry.text)
    end
end

return FloatingText
