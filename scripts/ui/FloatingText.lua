-- ============================================================================
-- ui/FloatingText.lua
-- 浮动文本工具：在指定位置显示文本，向上浮动渐渐消失
-- 最多同时显示 3 条，超过会把旧的快速顶掉
-- ============================================================================

local UI = require("urhox-libs/UI")

local FloatingText = {}

-- 配置
local MAX_VISIBLE = 3
local FLOAT_SPEED = 50         -- 向上浮动速度（像素/秒）
local NORMAL_LIFE = 2.5        -- 正常存活时间（秒）
local FAST_FADE_LIFE = 0.2     -- 被顶掉时快速淡出时间（秒）
local LABEL_WIDTH = 320        -- Label 固定宽度（用于居中偏移）
local BASE_FONT_SIZE = 20      -- 基础字号

-- 活跃文本队列
local activeTexts = {}

-- 容器引用
local container_ = nil

-- 预分配的条目池（MAX_VISIBLE + 1 用于过渡）
-- 每个条目是一个 Panel（含可选 icon + Label）
local POOL_SIZE = MAX_VISIBLE + 1
local entryPool = {}
local poolInited = false
local ICON_SIZE = 20           -- 图标尺寸

--- 创建浮动文本容器（absolute 定位的透明容器）
---@return table container UI 定义
function FloatingText.Create()
    return UI.Panel {
        id = "floatingTextContainer",
        position = "absolute",
        left = 0,
        top = 0,
        width = "100%",
        height = "100%",
        zIndex = 200,
        pointerEvents = "none",
    }
end

--- 初始化：缓存容器引用，创建 Label 池
---@param root table UI 根节点
function FloatingText.Init(root)
    container_ = root:FindById("floatingTextContainer")
    if not container_ then
        print("[FloatingText] WARNING: container not found!")
        return
    end

    -- 创建条目池（Panel: icon + Label）
    if not poolInited then
        for i = 1, POOL_SIZE do
            local row = UI.Panel {
                id = "ft_row_" .. i,
                position = "absolute",
                left = 0, top = 0,
                width = LABEL_WIDTH,
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                gap = 4,
                pointerEvents = "none",
            }
            container_:AddChild(row)
            local rowRef = container_:FindById("ft_row_" .. i)
            if rowRef then
                -- icon 面板（默认隐藏）
                local iconPanel = UI.Panel {
                    id = "ft_icon_" .. i,
                    width = ICON_SIZE, height = ICON_SIZE,
                    backgroundFit = "contain",
                    pointerEvents = "none",
                }
                rowRef:AddChild(iconPanel)
                local iconRef = rowRef:FindById("ft_icon_" .. i)
                if iconRef then iconRef:SetVisible(false) end

                -- 文本 Label
                local label = UI.Label {
                    id = "ft_label_" .. i,
                    text = "",
                    fontSize = BASE_FONT_SIZE,
                    fontWeight = "bold",
                    fontColor = { 255, 255, 255, 255 },
                    textAlign = "center",
                    pointerEvents = "none",
                }
                rowRef:AddChild(label)
                local labelRef = rowRef:FindById("ft_label_" .. i)

                rowRef:SetVisible(false)
                entryPool[i] = { row = rowRef, label = labelRef, icon = iconRef, inUse = false }
            end
        end
        poolInited = true
    end

    activeTexts = {}
end

--- 从池中获取一个空闲条目
---@return table|nil poolEntry
local function AcquireEntry()
    for i = 1, POOL_SIZE do
        if entryPool[i] and not entryPool[i].inUse then
            entryPool[i].inUse = true
            return entryPool[i]
        end
    end
    return nil
end

--- 归还条目到池
---@param entry table poolEntry
local function ReleaseEntry(entry)
    entry.inUse = false
    entry.row:SetVisible(false)
end

--- 显示一条浮动文本（可带图标）
---@param text string 要显示的文本
---@param x number 逻辑坐标 X（点击位置）
---@param y number 逻辑坐标 Y（点击位置）
---@param color table|nil 颜色 {r,g,b,a}，默认白色
---@param icon string|nil 图标图片路径（可选）
function FloatingText.Show(text, x, y, color, icon)
    if not container_ then return end

    local c = color or { 255, 255, 255, 255 }

    -- 超过上限，最旧的快速淡出
    if #activeTexts >= MAX_VISIBLE then
        local oldest = activeTexts[1]
        oldest.life = math.min(oldest.life, FAST_FADE_LIFE)
        oldest.maxLife = oldest.life
        oldest.fastFade = true
    end

    -- 获取一个条目
    local entry = AcquireEntry()
    if not entry then
        if #activeTexts > 0 then
            local removed = table.remove(activeTexts, 1)
            ReleaseEntry(removed.poolEntry)
            entry = AcquireEntry()
        end
        if not entry then return end
    end

    -- 在点击位置上方一点出现，水平居中于点击点
    local spawnLeft = x - LABEL_WIDTH * 0.5
    local spawnTop = y - 30

    -- 设置图标
    if entry.icon then
        if icon then
            entry.icon:SetStyle({ backgroundImage = icon })
            entry.icon:SetVisible(true)
        else
            entry.icon:SetVisible(false)
        end
    end

    -- 设置文本
    entry.label:SetText(text)
    entry.label:SetFontColor({ c[1], c[2], c[3], 255 })

    -- 设置行容器位置
    entry.row:SetStyle({ left = math.floor(spawnLeft), top = math.floor(spawnTop) })
    entry.row:SetVisible(true)

    activeTexts[#activeTexts + 1] = {
        poolEntry = entry,
        life = NORMAL_LIFE,
        maxLife = NORMAL_LIFE,
        spawnLeft = spawnLeft,
        spawnTop = spawnTop,
        elapsed = 0,
        baseColor = { c[1], c[2], c[3] },
        fastFade = false,
    }
end

--- 每帧更新（由 GameManager 调用）
---@param dt number 帧时间
function FloatingText.Update(dt)
    if not container_ then return end

    for i = #activeTexts, 1, -1 do
        local entry = activeTexts[i]
        entry.elapsed = entry.elapsed + dt
        entry.life = entry.life - dt

        if entry.life <= 0 then
            ReleaseEntry(entry.poolEntry)
            table.remove(activeTexts, i)
        else
            -- 向上浮动
            local speed = entry.fastFade and (FLOAT_SPEED * 3) or FLOAT_SPEED
            local currentTop = entry.spawnTop - entry.elapsed * speed

            -- 淡出
            local alpha = math.floor(255 * math.min(1, entry.life / (entry.maxLife * 0.5)))
            alpha = math.max(0, math.min(255, alpha))

            local bc = entry.baseColor
            entry.poolEntry.label:SetFontColor({ bc[1], bc[2], bc[3], alpha })
            if entry.poolEntry.icon and entry.poolEntry.icon:IsVisible() then
                entry.poolEntry.icon:SetStyle({ opacity = alpha / 255 })
            end
            entry.poolEntry.row:SetStyle({ top = math.floor(currentTop) })
        end
    end
end

return FloatingText
