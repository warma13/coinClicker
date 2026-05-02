-- ============================================================================
-- ui/Tooltip.lua
-- 可复用的悬停提示框：鼠标悬停在商店条目上时显示详情
-- 支持建筑、升级、建筑强化等任意物品
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")

local Tooltip = {}

-- ======== 模块状态 ========
local panel_ = nil       -- 提示框根面板
local uiRoot_ = nil      -- UI 根节点
local visible_ = false
local TOOLTIP_W = 300     -- 提示框宽度
local TOOLTIP_GAP = 8     -- 距离商店的间距
local lastConfigFn_ = nil -- 上次显示时的数据生成函数（用于刷新）
local lastAnchorY_ = 0    -- 上次显示时的锚点 Y
local lastAnchorX_ = nil  -- 上次显示时的锚点 X（nil 表示默认商店左侧定位）
local lastFingerprint_ = "" -- 上次渲染时的内容指纹（避免无变化时重建）

-- ======== 颜色 ========
local BG_COLOR        = { 15, 15, 30, 245 }
local BORDER_COLOR     = { 80, 80, 110, 200 }
local TITLE_COLOR      = { 240, 240, 255, 255 }
local TAG_COLOR        = { 140, 140, 170, 200 }
local DESC_COLOR       = { 180, 180, 200, 230 }
local COST_GREEN       = { 100, 255, 100, 255 }
local COST_RED         = { 255, 100, 100, 255 }
local ACTION_GREEN     = { 100, 200, 100, 200 }
local ACTION_RED       = { 200, 100, 100, 200 }
local ACTION_GRAY      = { 140, 140, 160, 180 }
local SEPARATOR_COLOR  = { 60, 60, 80, 150 }

-- ============================================================================
-- 创建 UI
-- ============================================================================

--- 创建提示框面板（absolute 定位，初始隐藏在屏幕外）
---@return table UI.Panel
function Tooltip.Create()
    return UI.Panel {
        id = "tooltipPanel",
        position = "absolute",
        width = TOOLTIP_W,
        left = -999, top = -999,
        backgroundColor = BG_COLOR,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = BORDER_COLOR,
        padding = 10,
        gap = 6,
        zIndex = 9999,
    }
end

--- 初始化（缓存面板引用）
---@param root table UI 根节点
function Tooltip.Init(root)
    uiRoot_ = root
    panel_ = root:FindById("tooltipPanel")
end

-- ============================================================================
-- 指纹（快速判断内容是否变化）
-- ============================================================================

--- 根据 config 生成内容指纹字符串
local function MakeFingerprint(cfg)
    if not cfg then return "" end
    -- 拼接关键字段即可，不需要完全精确
    local parts = {
        cfg.title or "",
        cfg.cost and tostring(math.floor(cfg.cost)) or "",
        cfg.desc or "",
        cfg.extra or "",
        cfg.action or "",
        cfg.actionColor or "",
        cfg.subtitle or "",
    }
    if cfg.details then
        for _, d in ipairs(cfg.details) do
            parts[#parts + 1] = d
        end
    end
    -- afford 状态也影响显示
    if cfg.cost then
        parts[#parts + 1] = GameState.coins >= cfg.cost and "Y" or "N"
    end
    return table.concat(parts, "|")
end

-- ============================================================================
-- 显示 / 隐藏
-- ============================================================================

--- 显示提示框
--- config 字段:
---   icon       string  物品图标 emoji
---   title      string  物品名称
---   tag        string  类型标签（"建筑"/"升级"/"强化"）
---   cost       number  价格（nil 则不显示）
---   costLabel  string  价格前缀（默认 "🪙"）
---   desc       string  描述文本
---   extra      string  额外信息行（可选）
---   action     string  操作提示（"点击购买。"/"金币不足"/"已解锁" 等）
---   actionColor string "green"/"red"/"gray" 操作文本颜色
---@param configOrFn table|function 提示内容配置（table 或返回 table 的函数）
---@param anchorY number 锚点 Y 坐标（逻辑像素）
---@param anchorX number|nil 锚点 X 坐标（提供时居中显示在锚点上方）
function Tooltip.Show(configOrFn, anchorY, anchorX)
    if not panel_ then return end

    -- 支持传入函数（用于刷新时重新获取最新数据）或静态 table
    local config
    if type(configOrFn) == "function" then
        lastConfigFn_ = configOrFn
        config = configOrFn()
    else
        lastConfigFn_ = nil
        config = configOrFn
    end
    lastAnchorY_ = anchorY
    lastAnchorX_ = anchorX

    panel_:RemoveAllChildren()

    -- ====== 标题行：icon + title + [tag] ======
    local titleChildren = {}

    -- 图标（优先使用图片，回退到 emoji）
    if config.iconImage then
        titleChildren[#titleChildren + 1] = UI.Panel {
            width = 28, height = 28,
            backgroundImage = config.iconImage,
            backgroundFit = "contain",
        }
    elseif config.icon then
        titleChildren[#titleChildren + 1] = UI.Label {
            text = config.icon, fontSize = 22,
            width = 28, textAlign = "center",
        }
    end

    -- 标题 + 标签
    local titleText = config.title or ""
    titleChildren[#titleChildren + 1] = UI.Label {
        text = titleText, fontSize = 14,
        fontColor = TITLE_COLOR,
        flex = 1, flexShrink = 1,
    }

    -- 价格
    if config.cost then
        local canAfford = GameState.coins >= config.cost
        local prefix = config.costLabel or "🪙"
        titleChildren[#titleChildren + 1] = UI.Label {
            text = prefix .. GameState.FormatNumber(config.cost),
            fontSize = 13,
            fontColor = canAfford and COST_GREEN or COST_RED,
            paddingTop = 1,
        }
    end

    panel_:AddChild(UI.Panel {
        width = "100%", flexDirection = "row",
        alignItems = "center", gap = 4,
        children = titleChildren,
    })

    -- ====== 副标题（如 [拥有: N]） ======
    if config.subtitle and config.subtitle ~= "" then
        panel_:AddChild(UI.Label {
            text = config.subtitle,
            fontSize = 10,
            fontColor = TAG_COLOR,
            width = "100%",
        })
    end

    -- ====== 分隔线 ======
    panel_:AddChild(UI.Panel {
        width = "100%", height = 1,
        backgroundColor = SEPARATOR_COLOR,
    })

    -- ====== 描述 ======
    if config.desc and config.desc ~= "" then
        panel_:AddChild(UI.Label {
            text = config.desc,
            fontSize = 11,
            fontColor = DESC_COLOR,
            width = "100%",
        })
    end

    -- ====== 详情行（数组，逐行渲染） ======
    if config.details then
        for _, line in ipairs(config.details) do
            panel_:AddChild(UI.Label {
                text = line,
                fontSize = 10,
                fontColor = { 200, 200, 220, 200 },
                width = "100%",
            })
        end
    end

    -- ====== 额外信息（单行，金色高亮） ======
    if config.extra and config.extra ~= "" then
        panel_:AddChild(UI.Label {
            text = config.extra,
            fontSize = 10,
            fontColor = { 255, 215, 0, 200 },
            width = "100%",
        })
    end

    -- ====== 操作提示 ======
    if config.action then
        local color = ACTION_GRAY
        if config.actionColor == "green" then
            color = ACTION_GREEN
        elseif config.actionColor == "red" then
            color = ACTION_RED
        end

        panel_:AddChild(UI.Panel {
            width = "100%", height = 1,
            backgroundColor = SEPARATOR_COLOR,
        })
        panel_:AddChild(UI.Label {
            text = config.action,
            fontSize = 10,
            fontColor = color,
            width = "100%",
        })
    end

    -- ====== 定位 ======
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr

    local tooltipX, tooltipY

    if anchorX then
        -- 贴在左侧栏右边（图标列48 + 内容区360 + 间距）
        local drawerWidth = 48 + 360
        tooltipX = drawerWidth + TOOLTIP_GAP
        tooltipY = anchorY - 30
        if tooltipY < 8 then tooltipY = 8 end
        if tooltipY + 160 > screenH then tooltipY = screenH - 160 end
    else
        -- 默认：商店面板左侧（右侧栏 width="30%"）
        local shopWidth = math.floor(screenW * 0.30)
        tooltipX = screenW - shopWidth - TOOLTIP_W - TOOLTIP_GAP
        tooltipY = anchorY - 30
        if tooltipY < 8 then tooltipY = 8 end
        if tooltipY + 160 > screenH then tooltipY = screenH - 160 end
    end

    panel_:SetStyle({ left = tooltipX, top = tooltipY })
    visible_ = true
    lastFingerprint_ = MakeFingerprint(config)
end

--- 隐藏提示框
function Tooltip.Hide()
    if not panel_ then return end
    if not visible_ then return end
    panel_:SetStyle({ left = -999, top = -999 })
    visible_ = false
    lastConfigFn_ = nil
    lastFingerprint_ = ""
end

--- 刷新提示框（用最新数据重新渲染，仅当使用 configFn 显示时有效）
--- 内置指纹对比：数据未变化时跳过重建
function Tooltip.Refresh()
    if not visible_ then return end
    if not lastConfigFn_ then return end
    local newConfig = lastConfigFn_()
    local fp = MakeFingerprint(newConfig)
    if fp == lastFingerprint_ then return end  -- 数据未变，跳过重建
    Tooltip.Show(lastConfigFn_, lastAnchorY_, lastAnchorX_)
end

--- 当前是否可见
function Tooltip.IsVisible()
    return visible_
end

return Tooltip
