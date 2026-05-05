-- ============================================================================
-- ui/StatsBar.lua
-- Buff 进度条栏（底部浮动，每个 buff 一行全宽进度条 + 名称）
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")

local StatsBar = {}

-- 缓存的 UI 引用
local buffBar_ = nil

-- 增量刷新缓存
local buffCache_ = {}    -- key -> { widget, nameLabel, progressFill, lastSecs }
local lastBuffKeys_ = ""

-- 常量
local BAR_HEIGHT = 18
local BAR_GAP = 3

--- 创建 Buff 栏 UI 定义（absolute 底部浮动，排在商店栏左侧）
---@return table UI 组件定义
function StatsBar.Create()
    -- paddingLeft 跟随侧边栏宽度，避免被遮挡
    local dpr = graphics:GetDPR()
    local logW = graphics:GetWidth() / dpr
    local logH = graphics:GetHeight() / dpr
    local shortSide = math.min(logW, logH)
    local sidebarW = math.floor(math.max(48, math.min(80, shortSide * 0.14)))

    return UI.Panel {
        id = "buffBar",
        width = "100%",
        flexDirection = "column",
        gap = BAR_GAP,
        paddingLeft = sidebarW + 8, paddingRight = 56,
        paddingBottom = 8,
        pointerEvents = "none",
    }
end

--- 初始化
---@param root table UI 根节点
function StatsBar.Init(root)
    buffBar_ = root:FindById("buffBar")
    if buffBar_ then buffBar_:SetVisible(false) end
end

--- 兼容旧接口
function StatsBar.Refresh() end

--- 根据 multiplierKey/multiplierVal 生成效果描述文本
local function GetEffectDesc(b)
    local mKey = b.multiplierKey
    local mVal = b.multiplierVal
    if not mKey or not mVal then return nil end
    local label = (mKey == "cpc") and "点击" or "CPS"
    if mVal >= 2 then
        return label .. " ×" .. string.format("%g", mVal)
    else
        local pct = math.floor((mVal - 1) * 100 + 0.5)
        return label .. " +" .. pct .. "%"
    end
end

--- 生成单个 buff 进度条控件
local function BuildBuffWidget(b)
    local pct = b.remaining / b.duration
    local secs = math.ceil(b.remaining)
    local col = b.color or { 255, 200, 50, 255 }
    -- 进度条背景色（效果色半透明）
    local bgCol = { col[1], col[2], col[3], 60 }
    -- 进度条前景色
    local fgCol = { col[1], col[2], col[3], 200 }

    -- 构建显示文本：名称 效果描述 倒计时
    local buffName = b.name or b.id or "buff"
    local effectDesc = GetEffectDesc(b)
    local displayText = buffName
    if effectDesc then
        displayText = displayText .. " " .. effectDesc
    end
    displayText = displayText .. "  " .. secs .. "s"

    local nameLabel = UI.Label {
        text = displayText,
        fontSize = 10,
        fontColor = fgCol,
        pointerEvents = "none",
    }

    local progressFill = UI.Panel {
        width = tostring(math.max(1, math.floor(pct * 100))) .. "%",
        height = "100%",
        borderRadius = 2,
        backgroundColor = fgCol,
    }

    local widget = UI.Panel {
        width = "100%",
        gap = 1,
        children = {
            nameLabel,
            UI.Panel {
                width = "100%",
                height = 4,
                borderRadius = 2,
                backgroundColor = bgCol,
                overflow = "hidden",
                children = { progressFill },
            },
        },
    }

    return widget, nameLabel, progressFill
end

--- 获取 buff 身份 key
local function GetBuffKey(b)
    return (b.id or b.name or "") .. ":" .. (b.icon or "")
end

--- 刷新 Buff 进度条栏
function StatsBar.RefreshBuffBar()
    if not buffBar_ then return end

    local buffs = GameState.activeBuffs
    if #buffs == 0 then
        if lastBuffKeys_ ~= "" then
            buffBar_:RemoveAllChildren()
            buffBar_:SetVisible(false)
            buffCache_ = {}
            lastBuffKeys_ = ""
        end
        return
    end

    buffBar_:SetVisible(true)

    -- 生成当前 key 串
    local keyParts = {}
    for i, b in ipairs(buffs) do
        keyParts[i] = GetBuffKey(b)
    end
    local currentKeys = table.concat(keyParts, "|")

    if currentKeys ~= lastBuffKeys_ then
        -- 集合变化，全量重建
        buffBar_:RemoveAllChildren()
        local newCache = {}
        for i, b in ipairs(buffs) do
            local key = keyParts[i]
            local widget, nameLabel, progressFill = BuildBuffWidget(b)
            buffBar_:AddChild(widget)
            newCache[key] = {
                widget = widget,
                nameLabel = nameLabel,
                progressFill = progressFill,
                lastSecs = math.ceil(b.remaining),
            }
        end
        buffCache_ = newCache
        lastBuffKeys_ = currentKeys
    else
        -- 增量更新
        for i, b in ipairs(buffs) do
            local key = keyParts[i]
            local c = buffCache_[key]
            if c then
                local secs = math.ceil(b.remaining)
                if secs ~= c.lastSecs then
                    local buffName = b.name or b.id or "buff"
                    local effectDesc = GetEffectDesc(b)
                    local displayText = buffName
                    if effectDesc then
                        displayText = displayText .. " " .. effectDesc
                    end
                    displayText = displayText .. "  " .. secs .. "s"
                    c.nameLabel:SetText(displayText)
                    c.lastSecs = secs
                end
                local pct = math.max(1, math.floor((b.remaining / b.duration) * 100))
                c.progressFill:SetStyle({ width = pct .. "%" })
            end
        end
    end
end

return StatsBar
