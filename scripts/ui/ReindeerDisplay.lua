-- ============================================================================
-- ui/ReindeerDisplay.lua
-- 驯鹿浮动显示（absolute 定位，点击收集奖励）
-- 类似 LuckyCoin，使用 SetVisible 控制显隐
-- ============================================================================

local UI = require("urhox-libs/UI")

local RD = {}

-- 缓存 UI 引用
local panel_ = nil
local emoji_ = nil
local floatPhase_ = 0

--- 创建驯鹿 UI 定义（absolute 定位浮动面板）
---@param onTap function 点击驯鹿的回调
---@return table panel
function RD.Create(onTap)
    local size = 56

    local panel = UI.Panel {
        id = "reindeerPanel",
        position = "absolute",
        left = 0, top = 0,
        width = size, height = size,
        borderRadius = size / 2,
        backgroundColor = { 139, 90, 43, 230 },
        borderWidth = 3,
        borderColor = { 200, 150, 80, 255 },
        justifyContent = "center",
        alignItems = "center",
        zIndex = 99,
        pointerEvents = "auto",
        onPointerDown = function(self)
            if onTap then onTap() end
        end,
        children = {
            UI.Panel {
                id = "reindeerEmoji",
                width = 36, height = 36,
                backgroundImage = "image/icon_reindeer.png",
                backgroundFit = "contain",
                pointerEvents = "none",
            },
        },
    }

    return panel
end

--- 初始化：缓存引用
---@param root table UI 根节点
function RD.Init(root)
    panel_ = root:FindById("reindeerPanel")
    emoji_ = root:FindById("reindeerEmoji")
    if panel_ then panel_:SetVisible(false) end
    floatPhase_ = 0
end

--- 显示驯鹿
---@param x number X 逻辑坐标
---@param y number Y 逻辑坐标
function RD.Show(x, y)
    if panel_ then
        panel_:SetStyle({ left = math.floor(x), top = math.floor(y) })
        panel_:SetVisible(true)
        floatPhase_ = 0
    end
end

--- 隐藏驯鹿
function RD.Hide()
    if panel_ then
        panel_:SetVisible(false)
    end
end

--- 驯鹿是否可见
---@return boolean
function RD.IsVisible()
    if panel_ then return panel_:IsVisible() end
    return false
end

--- 更新浮动动画（逐帧调用）
---@param dt number
---@param posX number 基础 X 坐标
---@param posY number 基础 Y 坐标
---@param stayTimer number 剩余停留时间
function RD.UpdateAnimation(dt, posX, posY, stayTimer)
    if not panel_ then return end

    floatPhase_ = floatPhase_ + dt * 4.0
    local floatOffset = math.sin(floatPhase_) * 8

    -- 最后 2 秒闪烁
    local alpha = 230
    if stayTimer < 2 then
        local blink = math.sin(stayTimer * 10) * 0.5 + 0.5
        alpha = math.floor(80 + 150 * blink)
    end

    panel_:SetStyle({
        left = math.floor(posX),
        top = math.floor(posY + floatOffset),
        backgroundColor = { 139, 90, 43, alpha },
    })
end

return RD
