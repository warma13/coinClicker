-- ============================================================================
-- ui/CoinArea.lua
-- 左侧金币点击区域（金币数量 + 每秒产出 + 金币图标）
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local StatsBar = require("ui.StatsBar")

local CoinArea = {}

-- 缓存的 UI 引用
local coinIcon_ = nil
local coinCountLabel_ = nil
local cpsLabel_ = nil
local staminaFill_ = nil
local staminaLabel_ = nil
local animTimer_ = 0
local onCoinClick_ = nil  -- 点击金币回调

-- 增量刷新缓存
local lastCoinText_ = ""
local lastCpsText_ = ""
local lastStaminaText_ = ""
local lastStaminaPct_ = -1

--- 创建点击区域 UI 定义
---@param onCoinClick function|nil 点击金币回调 function(x, y)
---@return table UI 组件定义
function CoinArea.Create(onCoinClick)
    onCoinClick_ = onCoinClick
    return UI.Panel {
        id = "coinArea",
        width = "70%",
        alignItems = "center",
        pointerEvents = "auto",
        onPointerDown = function(event)
            if onCoinClick_ then
                onCoinClick_(event.x, event.y)
            end
        end,
        children = {
            -- 体力条（固定顶部）
            UI.Panel {
                width = 200,
                paddingTop = 8,
                paddingBottom = 4,
                flexDirection = "column",
                alignItems = "center",
                gap = 3,
                pointerEvents = "none",
                children = {
                    UI.Label {
                        id = "staminaLabel",
                        text = "体力 0/300",
                        fontSize = 11,
                        fontColor = { 180, 220, 140, 200 },
                    },
                    UI.Panel {
                        width = "100%",
                        height = 6,
                        borderRadius = 3,
                        backgroundColor = { 60, 60, 80, 150 },
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                id = "staminaFill",
                                width = "0%",
                                height = "100%",
                                borderRadius = 3,
                                backgroundColor = { 120, 220, 80, 220 },
                            },
                        },
                    },
                },
            },
            -- 中间金币区域（flex=1 撑满，内容居中）
            UI.Panel {
                flex = 1,
                width = "100%",
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "none",
                children = {
                    -- 金币数量（大字）
                    UI.Label {
                        id = "coinCountLabel",
                        text = "0 金币",
                        fontSize = 28,
                        fontColor = { 255, 255, 255, 255 },
                        marginBottom = 4,
                        pointerEvents = "none",
                    },
                    -- 每秒产出
                    UI.Label {
                        id = "cpsLabel",
                        text = "每秒：0",
                        fontSize = 13,
                        fontColor = { 180, 180, 200, 200 },
                        marginBottom = 20,
                        pointerEvents = "none",
                    },
                    -- 金币图标
                    UI.Panel {
                        id = "coinIcon",
                        width = 160,
                        height = 160,
                        backgroundImage = "image/金币.png",
                        backgroundFit = "contain",
                        pointerEvents = "none",
                        scale = 1.0,
                        transition = "scale 0.1s easeOut",
                    },
                },
            },
            -- Buff 进度条栏（固定底部）
            StatsBar.Create(),
        },
    }
end

--- 初始化：缓存 FindById 引用
---@param root table UI 根节点
function CoinArea.Init(root)
    coinIcon_ = root:FindById("coinIcon")
    coinCountLabel_ = root:FindById("coinCountLabel")
    cpsLabel_ = root:FindById("cpsLabel")
    staminaFill_ = root:FindById("staminaFill")
    staminaLabel_ = root:FindById("staminaLabel")
end

--- 播放点击放缩动画（先放大再回弹）
function CoinArea.PlayClickAnim()
    if not coinIcon_ then return end
    coinIcon_:SetStyle({ scale = 1.2 })
    animTimer_ = 0.1
end

--- 每帧更新（处理动画回弹）
---@param dt number
function CoinArea.Update(dt)
    if animTimer_ > 0 then
        animTimer_ = animTimer_ - dt
        if animTimer_ <= 0 then
            animTimer_ = 0
            if coinIcon_ then
                coinIcon_:SetStyle({ scale = 1.0 })
            end
        end
    end
end

--- 刷新公式显示（已移除，保留接口兼容）
function CoinArea.RefreshFormula()
end

--- 刷新金币数量和每秒产出（增量：仅在文本变化时更新）
function CoinArea.RefreshStats()
    local S = GameState
    local F = S.FormatNumber

    if coinCountLabel_ then
        local coinText = F(math.floor(S.coins)) .. " 金币"
        if coinText ~= lastCoinText_ then
            lastCoinText_ = coinText
            coinCountLabel_:SetText(coinText)
        end
    end
    if cpsLabel_ then
        local effectiveCps = S.coinsPerSecond * S.buffCpsMul
        local t = "每秒：" .. F(effectiveCps)
        if S.buffCpsMul > 1 then
            t = t .. " (x" .. F(S.buffCpsMul) .. ")"
        end
        if t ~= lastCpsText_ then
            lastCpsText_ = t
            cpsLabel_:SetText(t)
        end
    end

    -- 体力条
    if staminaLabel_ then
        local staminaText = "体力 " .. math.floor(S.stamina) .. "/" .. S.staminaMax
        if staminaText ~= lastStaminaText_ then
            lastStaminaText_ = staminaText
            staminaLabel_:SetText(staminaText)
        end
    end
    if staminaFill_ then
        local pct = math.floor(S.stamina / S.staminaMax * 100)
        if pct ~= lastStaminaPct_ then
            lastStaminaPct_ = pct
            staminaFill_:SetStyle({ width = pct .. "%" })
        end
    end
end

return CoinArea
