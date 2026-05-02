-- ============================================================================
-- ui/WrinklerDisplay.lua
-- 资金黑洞显示：在金币周围环绕 + 点击弹出 + 阶段状态指示器
-- 使用 AddChild/RemoveChild 模式管理皱巴虫图标
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local GD = require("config.GrandmapocalypseDefs")

local WD = {}

-- ======== UI 引用 ========
local uiRoot_ = nil
local wrinklerWidgets_ = {}  -- wrinklerWidgets_[wrinklerId] = widget
local statusWidget_ = nil    -- 阶段状态指示器

-- ======== 外部注入 ========
local wrinklerManager_ = nil
local onPopCallback_ = nil   -- function(wrinklerId)

-- ======== 布局参数 ========
local WRINKLER_SIZE = 36
local ORBIT_RADIUS = 110     -- 围绕金币的轨道半径

-- ======== 动画 ========
local animPhase_ = 0

-- ============================================================================
-- 初始化
-- ============================================================================

function WD.Init(root, wm, onPop)
    uiRoot_ = root
    wrinklerManager_ = wm
    onPopCallback_ = onPop
    wrinklerWidgets_ = {}
    animPhase_ = 0
end

-- ============================================================================
-- 内部：创建单个皱巴虫控件
-- ============================================================================

local function CreateWrinklerWidget(wrinkler)
    local w = UI.Panel {
        position = "absolute",
        width = WRINKLER_SIZE,
        height = WRINKLER_SIZE,
        borderRadius = WRINKLER_SIZE / 2,
        backgroundColor = { 100, 60, 120, 220 },
        borderWidth = 2,
        borderColor = { 180, 100, 200, 200 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        onPointerDown = function()
            if onPopCallback_ then
                onPopCallback_(wrinkler.id)
            end
        end,
        children = {
            UI.Panel {
                width = 24, height = 24,
                backgroundImage = "image/icon_wrinkler_20260415013857.png",
                backgroundFit = "contain",
                pointerEvents = "none",
            },
        },
    }
    return w
end

-- ============================================================================
-- 帧更新：同步皱巴虫显示 + 位置动画
-- ============================================================================

function WD.Update(dt)
    if not uiRoot_ or not wrinklerManager_ then return end

    animPhase_ = animPhase_ + dt * 0.5

    local wrinklers = wrinklerManager_.GetAll()

    -- 获取金币区域中心坐标
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr
    local shopWidth = 310
    local coinCenterX = (screenW - shopWidth) / 2
    local coinCenterY = screenH / 2

    -- 构建当前活跃 ID 集合
    local activeIds = {}
    for _, w in ipairs(wrinklers) do
        activeIds[w.id] = true
    end

    -- 移除已消失的皱巴虫控件
    for id, widget in pairs(wrinklerWidgets_) do
        if not activeIds[id] then
            uiRoot_:RemoveChild(widget)
            wrinklerWidgets_[id] = nil
        end
    end

    -- 添加/更新皱巴虫
    for i, w in ipairs(wrinklers) do
        -- 如果控件不存在则创建
        if not wrinklerWidgets_[w.id] then
            local widget = CreateWrinklerWidget(w)
            uiRoot_:AddChild(widget)
            wrinklerWidgets_[w.id] = widget
        end

        -- 计算环绕位置（每只虫有不同的角度偏移 + 缓慢旋转）
        local angle = w.angle + animPhase_ + w.id * 0.3
        local wobble = math.sin(animPhase_ * 2 + w.id * 1.7) * 8
        local r = ORBIT_RADIUS + wobble
        local px = coinCenterX + math.cos(angle) * r - WRINKLER_SIZE / 2
        local py = coinCenterY + math.sin(angle) * r - WRINKLER_SIZE / 2

        -- 限制范围：避开左侧栏(48px)和右侧商店栏
        local minX = 52
        local maxX = screenW - shopWidth - WRINKLER_SIZE - 4
        local minY = 4
        local maxY = screenH - WRINKLER_SIZE - 4
        px = math.max(minX, math.min(maxX, px))
        py = math.max(minY, math.min(maxY, py))

        -- 吸取量越大颜色越深
        local intensity = math.min(w.absorbed / (GameState.coinsPerSecond * 60 + 1), 1)
        local red = math.floor(100 + 120 * intensity)
        local green = math.floor(60 - 30 * intensity)
        local blue = math.floor(120 - 60 * intensity)

        local widget = wrinklerWidgets_[w.id]
        if widget then
            widget:SetStyle({
                left = math.floor(px),
                top = math.floor(py),
                backgroundColor = { red, green, blue, 220 },
            })
        end
    end
end

-- ============================================================================
-- 阶段状态指示器（显示在 CpS 下方）
-- ============================================================================

function WD.CreateStatusWidget()
    statusWidget_ = UI.Panel {
        id = "grandmapoStatus",
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        marginTop = 4,
        children = {
            UI.Panel {
                id = "grandmapoIcon",
                width = 16, height = 16,
                backgroundFit = "contain",
            },
            UI.Label {
                id = "grandmapoLabel",
                text = "",
                fontSize = 10,
                fontColor = { 180, 150, 120, 200 },
            },
        },
    }
    return statusWidget_
end

--- 刷新状态指示器文字
---@param phase number 当前阶段
---@param wrinklerCount number 皱巴虫数量
---@param totalAbsorbed number 总吸取量
function WD.RefreshStatus(phase, wrinklerCount, totalAbsorbed)
    if not uiRoot_ then return end
    local iconLabel = uiRoot_:FindById("grandmapoIcon")
    local textLabel = uiRoot_:FindById("grandmapoLabel")
    if not iconLabel or not textLabel then return end

    if phase == GD.PHASE_NONE then
        iconLabel:SetStyle({ backgroundImage = "" })
        textLabel:SetText("")
        return
    end

    local iconImg = GD.phaseIconImages[phase] or ""
    local name = GD.phaseNames[phase] or ""
    local color = GD.phaseColors[phase] or { 200, 200, 200, 255 }

    iconLabel:SetStyle({ backgroundImage = iconImg })
    textLabel:SetStyle({ fontColor = color })

    local text = name
    if wrinklerCount > 0 then
        text = text .. " | 渠道x" .. wrinklerCount
        if totalAbsorbed > 0 then
            text = text .. " 侵蚀:" .. GameState.FormatNumber(totalAbsorbed)
        end
    end
    textLabel:SetText(text)
end

-- ============================================================================
-- 清理所有皱巴虫控件
-- ============================================================================

function WD.Clear()
    if uiRoot_ then
        for _, widget in pairs(wrinklerWidgets_) do
            uiRoot_:RemoveChild(widget)
        end
    end
    wrinklerWidgets_ = {}
end

return WD
