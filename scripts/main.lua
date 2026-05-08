-- ============================================================================
-- Coin Clicker - 放置类点击游戏
-- 纯入口文件：初始化 → 转发事件
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameManager    = require("core.GameManager")
local AudioManager   = require("core.AudioManager")
local SaveBridge     = require("core.SaveBridge")
local SlotSaveSystem = require("core.SlotSaveSystem")
local AppLayout      = require("ui.AppLayout")
local Tooltip        = require("ui.Tooltip")
local SkillBar       = require("ui.SkillBar")
local LeaderboardPanel = require("ui.LeaderboardPanel")
local CoinParticle   = require("ui.CoinParticle")
local FloatingText   = require("ui.FloatingText")

local root_           = nil   -- UI root 引用
local skillBarTimer_   = 0
local vg_             = nil   -- NanoVG 上下文（粒子 + 浮动文本共享）

function Start()
    graphics.windowTitle = "Coin Clicker"

    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 移动端：触屏会同时发 Mouse + Touch，禁掉模拟鼠标事件
    local platform = GetPlatform()
    if platform == "Android" or platform == "iOS" or platform == "Web" then
        input.touchEmulation = false
        local origMouseDown = UI.HandleMouseDown
        local origMouseUp   = UI.HandleMouseUp
        local lastTouchTime = -1
        local DEBOUNCE_S    = 0.1
        UI.HandleMouseDown = function(x, y, button)
            if time.elapsedTime - lastTouchTime < DEBOUNCE_S then return end
            origMouseDown(x, y, button)
        end
        UI.HandleMouseUp = function(x, y, button)
            if time.elapsedTime - lastTouchTime < DEBOUNCE_S then return end
            origMouseUp(x, y, button)
        end
        local origTouchBegin = UI.HandleTouchBegin
        UI.HandleTouchBegin = function(touchId, x, y, pressure)
            lastTouchTime = time.elapsedTime
            origTouchBegin(touchId, x, y, pressure)
        end
    end

    -- 初始化音频
    ---@type Scene
    local audioScene = Scene()
    AudioManager.Init(audioScene)
    AudioManager.PlayBGM()

    -- 初始化游戏管理器
    GameManager.Init()
    SaveBridge.SetBuildingUpgrades(GameManager.buildingUpgrades)

    -- 构建 UI 树并初始化所有模块
    root_ = AppLayout.Build()

    -- 初始化 NanoVG（金币粒子 + 浮动文本使用 NanoVG 直接绘制，避免 Yoga 布局开销）
    vg_ = nvgCreate(0)
    CoinParticle.InitNVG(vg_)
    FloatingText.InitNVG(vg_)

    -- 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("NanoVGRender", "HandleNanoVGRender")

    -- 初始化存档系统（云端加载 → 本地回退 → 新玩家）
    SlotSaveSystem.Init(function(ok, offlineTime)
        if ok then
            AppLayout.OnSaveLoaded(root_)
            if offlineTime > 0 then
                print("[SaveSystem] 离线 " .. offlineTime .. " 秒")
            end
        end
        GameManager.GetAchievementManager().MarkReady()
        print("[SaveSystem] 初始化完成, ok=" .. tostring(ok))
    end)

    print("=== Coin Clicker Started ===")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- 事件处理（转发到 GameManager）
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    GameManager.Update(dt)
    SlotSaveSystem.Update(dt)

    -- 刷新底部技能栏（降频：0.2 秒一次）
    skillBarTimer_ = skillBarTimer_ - dt
    if skillBarTimer_ <= 0 then
        skillBarTimer_ = 0.2
        SkillBar.Refresh()
    end

    LeaderboardPanel.Update(dt)
    AudioManager.Update(dt)
end

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseButtonDown(eventType, eventData)
    -- 金币点击已由 CoinArea 的 pointerEvents 处理
end

---@param eventType string
---@param eventData TouchBeginEventData
function HandleTouchBegin(eventType, eventData)
    -- 移动端触摸后 pointerLeave 不会触发，全局触摸时关闭 Tooltip
    Tooltip.Hide()
end

--- NanoVG 渲染（金币粒子 + 浮动文本）
---@param eventType string
---@param eventData table
function HandleNanoVGRender(eventType, eventData)
    if not vg_ then return end
    local dpr = graphics:GetDPR()
    local logW = graphics:GetWidth() / dpr
    local logH = graphics:GetHeight() / dpr
    nvgBeginFrame(vg_, logW, logH, dpr)
    CoinParticle.Render(vg_)
    FloatingText.Render(vg_)
    nvgEndFrame(vg_)
end
