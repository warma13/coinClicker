-- ============================================================================
-- ui/AscensionPanel.lua
-- 转型重启确认面板（全屏覆盖式弹窗）
-- 显示当前商业声望、转型预览、确认/取消操作
-- 使用 AddChild/RemoveChild 控制显隐
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local AD = require("config.AscensionDefs")

local AP = {}

-- ======== 引用 ========
local uiRoot_ = nil
local panel_ = nil
local visible_ = false

-- 信息标签
local currentPrestigeLabel_ = nil
local currentChipsIcon_ = nil
local currentChipsText_ = nil
local newPrestigeLabel_ = nil
local chipsGainIcon_ = nil
local chipsGainText_ = nil
local chipsGainRow_ = nil
local bakedLabel_ = nil
local warningLabel_ = nil
local ascendBtn_ = nil
local ascendBtnLabel_ = nil
local ascendBtnIcon_ = nil

-- 确认弹窗
local confirmOverlay_ = nil

-- 外部注入
local ascensionManager_ = nil
local onAscend_ = nil         -- function()
local onOpenShop_ = nil       -- function()

-- 前向声明
local ShowConfirm
local CloseConfirm

-- ============================================================================
-- 内部：构建面板
-- ============================================================================

local function BuildPanel()
    currentChipsIcon_ = UI.Panel {
        width = 14, height = 14,
        backgroundImage = "image/icon_管理经验.png",
        backgroundFit = "contain",
    }
    currentChipsText_ = UI.Label {
        text = "",
        fontSize = 14,
        fontColor = { 200, 190, 230, 230 },
    }
    currentPrestigeLabel_ = UI.Panel {
        flexDirection = "row",
        flexWrap = "wrap",
        alignItems = "center",
        justifyContent = "center",
        gap = 3,
        children = {},
    }

    newPrestigeLabel_ = UI.Label {
        text = "",
        fontSize = 18,
        fontColor = { 255, 230, 150, 255 },
        textAlign = "center",
        whiteSpace = "normal",
    }

    chipsGainIcon_ = UI.Panel {
        width = 16, height = 16,
        backgroundImage = "image/icon_管理经验.png",
        backgroundFit = "contain",
    }
    chipsGainText_ = UI.Label {
        text = "",
        fontSize = 16,
        fontColor = { 200, 170, 255, 255 },
    }
    chipsGainRow_ = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        gap = 4,
        children = { chipsGainIcon_, chipsGainText_ },
    }

    bakedLabel_ = UI.Label {
        text = "",
        fontSize = 12,
        fontColor = { 160, 150, 180, 200 },
        textAlign = "center",
    }

    warningLabel_ = UI.Label {
        text = "",
        fontSize = 12,
        fontColor = { 255, 180, 100, 220 },
        textAlign = "center",
        marginTop = 4,
    }

    ascendBtnIcon_ = UI.Panel {
        width = 16, height = 16,
        backgroundImage = "image/icon_管理经验.png",
        backgroundFit = "contain",
    }
    ascendBtnLabel_ = UI.Label {
        text = "转型重启",
        fontSize = 16,
        fontColor = { 255, 255, 255, 255 },
    }

    ascendBtn_ = UI.Panel {
        width = 200, height = 48,
        flexDirection = "row",
        justifyContent = "center", alignItems = "center",
        gap = 4,
        backgroundColor = { 120, 80, 200, 255 },
        borderRadius = 24,
        borderWidth = 2,
        borderColor = { 200, 170, 255, 200 },
        pointerEvents = "auto",
        marginTop = 8,
        onPointerDown = function()
            if onAscend_ then
                ShowConfirm()
            end
        end,
        children = { ascendBtnLabel_, ascendBtnIcon_ },
    }

    -- 确认弹窗
    confirmOverlay_ = UI.Panel {
        id = "ascendConfirmOverlay",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        zIndex = 600,
        backgroundColor = { 0, 0, 0, 160 },
        pointerEvents = "auto",
        onPointerDown = function()
            CloseConfirm()
        end,
        children = {
            UI.Panel {
                width = 280,
                flexDirection = "column",
                alignItems = "center",
                padding = 24,
                gap = 14,
                borderRadius = 16,
                backgroundColor = { 35, 28, 55, 250 },
                borderWidth = 2,
                borderColor = { 200, 170, 255, 180 },
                pointerEvents = "auto",
                onPointerDown = function() end, -- 阻止冒泡
                children = {
                    UI.Label {
                        text = "确认转型？",
                        fontSize = 20,
                        fontColor = { 255, 230, 150, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "转型将重置金币、产业、签单升级等进度，此操作不可撤销！",
                        fontSize = 12,
                        fontColor = { 220, 200, 180, 200 },
                        textAlign = "center",
                    },
                    -- 按钮行
                    UI.Panel {
                        flexDirection = "row",
                        gap = 16,
                        marginTop = 4,
                        children = {
                            -- 取消
                            UI.Panel {
                                width = 100, height = 40,
                                justifyContent = "center", alignItems = "center",
                                borderRadius = 20,
                                backgroundColor = { 60, 55, 80, 220 },
                                borderWidth = 1,
                                borderColor = { 120, 110, 150, 150 },
                                pointerEvents = "auto",
                                onPointerDown = function()
                                    CloseConfirm()
                                end,
                                children = {
                                    UI.Label {
                                        text = "取消", fontSize = 14,
                                        fontColor = { 180, 170, 200, 230 },
                                    },
                                },
                            },
                            -- 确认
                            UI.Panel {
                                width = 100, height = 40,
                                justifyContent = "center", alignItems = "center",
                                borderRadius = 20,
                                backgroundColor = { 120, 80, 200, 255 },
                                borderWidth = 1,
                                borderColor = { 200, 170, 255, 200 },
                                pointerEvents = "auto",
                                onPointerDown = function()
                                    CloseConfirm()
                                    if onAscend_ then
                                        onAscend_()
                                    end
                                end,
                                children = {
                                    UI.Label {
                                        text = "确认转型", fontSize = 14,
                                        fontColor = { 255, 255, 255, 255 },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
    confirmOverlay_:SetVisible(false)

    ---@diagnostic disable-next-line: redefined-local
    ShowConfirm = function()
        if confirmOverlay_ then confirmOverlay_:SetVisible(true) end
    end
    ---@diagnostic disable-next-line: redefined-local
    CloseConfirm = function()
        if confirmOverlay_ then confirmOverlay_:SetVisible(false) end
    end

    panel_ = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        alignItems = "center",
        paddingTop = 12, paddingLeft = 8, paddingRight = 8,
        pointerEvents = "auto",
        children = {
            -- 确认弹窗（absolute 覆盖层）
            confirmOverlay_,

            -- 标题
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                marginBottom = 8,
                children = {
                    UI.Panel { width = 22, height = 22,
                        backgroundImage = "image/侧栏_转型_20260414105515.png",
                        backgroundFit = "contain" },
                    UI.Label {
                        text = "转型重启",
                        fontSize = 18,
                        fontColor = { 230, 210, 255, 255 },
                    },
                },
            },

            -- 可滚动内容
            UI.ScrollView {
                flex = 1,
                width = "100%",
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        alignItems = "center",
                        gap = 6,
                        paddingBottom = 20,
                        children = {
                            -- 当前商业声望
                            currentPrestigeLabel_,

                            -- 分隔
                            UI.Panel {
                                width = 200, height = 1,
                                backgroundColor = { 100, 80, 150, 100 },
                                marginTop = 8, marginBottom = 8,
                            },

                            -- 转型后新声望
                            UI.Label {
                                text = "转型后",
                                fontSize = 12,
                                fontColor = { 140, 130, 170, 180 },
                                textAlign = "center",
                            },
                            newPrestigeLabel_,

                            -- 获得经验值
                            chipsGainRow_,

                            -- 营业额
                            bakedLabel_,

                            -- 警告
                            warningLabel_,

                            -- 转型按钮
                            ascendBtn_,

                            -- 查看经验商店
                            UI.Panel {
                                width = 200, height = 40,
                                flexDirection = "row",
                                justifyContent = "center", alignItems = "center",
                                gap = 4,
                                backgroundColor = { 50, 45, 70, 200 },
                                borderRadius = 20,
                                borderWidth = 1,
                                borderColor = { 150, 130, 200, 150 },
                                pointerEvents = "auto",
                                marginTop = 4,
                                onPointerDown = function()
                                    if onOpenShop_ then
                                        onOpenShop_()
                                    end
                                end,
                                children = {
                                    UI.Panel { width = 16, height = 16,
                                            backgroundImage = "image/侧栏_经验_20260414105524.png",
                                            backgroundFit = "contain" },
                                    UI.Label { text = "查看经验商店", fontSize = 13,
                                        fontColor = { 200, 190, 230, 230 } },
                                },
                            },

                            -- 重置说明
                            UI.Panel {
                                width = "100%",
                                marginTop = 12,
                                padding = 10,
                                backgroundColor = { 30, 25, 45, 150 },
                                borderRadius = 8,
                                children = {
                                    UI.Label {
                                        text = "转型将重置：金币、产业、签单升级、Buff、工会危机进度",
                                        fontSize = 10,
                                        fontColor = { 180, 160, 140, 180 },
                                        textAlign = "center",
                                    },
                                    UI.Label {
                                        text = "保留：经验值、经验升级、人脉、产业等级、里程碑",
                                        fontSize = 10,
                                        fontColor = { 140, 180, 140, 180 },
                                        textAlign = "center",
                                        marginTop = 4,
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 初始化面板
---@param root table UI 根节点
---@param manager table AscensionManager 引用
---@param ascendCb function 飞升确认回调 function()
---@param shopCb function 打开商店回调 function()
function AP.Init(root, manager, ascendCb, shopCb)
    uiRoot_ = root
    ascensionManager_ = manager
    onAscend_ = ascendCb
    onOpenShop_ = shopCb
    BuildPanel()
end

function AP.Show()
    if not panel_ or not uiRoot_ then return end
    if visible_ then return end
    visible_ = true
    uiRoot_:AddChild(panel_)
    AP.Refresh()
end

function AP.Hide()
    if not panel_ or not uiRoot_ then return end
    if not visible_ then return end
    visible_ = false
    uiRoot_:RemoveChild(panel_)
end

function AP.Toggle()
    if visible_ then AP.Hide() else AP.Show() end
end

function AP.IsVisible() return visible_ end

-- ============================================================================
-- 刷新
-- ============================================================================

function AP.Refresh()
    if not visible_ or not ascensionManager_ then return end

    local F = GameState.FormatNumber
    local currentPrestige = math.floor(ascensionManager_.GetPrestigeLevel())
    local newPrestige = math.floor(ascensionManager_.GetPotentialPrestige())
    local gainedChips = math.floor(ascensionManager_.GetPotentialChips())
    local totalBaked = ascensionManager_.GetTotalBakedAllTime() + ascensionManager_.GetBakedThisAscension()
    local chips = math.floor(ascensionManager_.GetHeavenlyChips())
    local ascCount = ascensionManager_.GetAscensionCount()

    -- 当前状态（行容器：文字 + 图标 + 文字）
    if currentPrestigeLabel_ then
        local prefix = "当前商业声望 Lv." .. currentPrestige .. " | "
        local suffix = chips .. " 经验值"
        if ascCount > 0 then
            suffix = suffix .. " | 第 " .. ascCount .. " 次转型"
        end
        currentPrestigeLabel_:RemoveAllChildren()
        currentPrestigeLabel_:AddChild(UI.Label { text = prefix, fontSize = 14, fontColor = { 200, 190, 230, 230 } })
        currentPrestigeLabel_:AddChild(currentChipsIcon_)
        currentPrestigeLabel_:AddChild(UI.Label { text = suffix, fontSize = 14, fontColor = { 200, 190, 230, 230 } })
    end

    -- 新声望
    if newPrestigeLabel_ then
        newPrestigeLabel_:SetText("商业声望 Lv." .. currentPrestige .. " → Lv." .. newPrestige)
    end

    -- 获得经验值
    if chipsGainText_ then
        if gainedChips > 0 then
            chipsGainText_:SetText("+" .. gainedChips .. " 经验值")
            chipsGainText_:SetStyle({ fontColor = { 200, 170, 255, 255 } })
            chipsGainIcon_:SetStyle({ opacity = 1.0 })
        else
            chipsGainText_:SetText("+0 经验值")
            chipsGainText_:SetStyle({ fontColor = { 120, 110, 140, 180 } })
            chipsGainIcon_:SetStyle({ opacity = 0.4 })
        end
    end

    -- 营业额
    if bakedLabel_ then
        bakedLabel_:SetText("本轮营业: " .. F(ascensionManager_.GetBakedThisAscension()) ..
                           " | 历史总计: " .. F(totalBaked))
    end

    -- 警告/提示
    if warningLabel_ then
        if gainedChips == 0 then
            warningLabel_:SetText("当前转型不会获得任何经验值！继续赚金币吧")
            warningLabel_:SetStyle({ fontColor = { 255, 150, 80, 220 } })
        elseif gainedChips < currentPrestige then
            warningLabel_:SetText("建议等到声望至少翻倍再转型")
            warningLabel_:SetStyle({ fontColor = { 200, 200, 100, 200 } })
        else
            warningLabel_:SetText("转型后商业声望将大幅提升！")
            warningLabel_:SetStyle({ fontColor = { 150, 255, 150, 220 } })
        end
    end

    -- 飞升按钮状态
    if ascendBtn_ and ascendBtnLabel_ then
        if gainedChips > 0 then
            ascendBtn_:SetStyle({
                backgroundColor = { 120, 80, 200, 255 },
                borderColor = { 200, 170, 255, 200 },
                pointerEvents = "auto",
                opacity = 1.0,
            })
            ascendBtn_:RemoveAllChildren()
            ascendBtn_:AddChild(UI.Label { text = "转型 (+", fontSize = 16, fontColor = { 255, 255, 255, 255 } })
            ascendBtn_:AddChild(ascendBtnIcon_)
            ascendBtn_:AddChild(UI.Label { text = gainedChips .. ")", fontSize = 16, fontColor = { 255, 255, 255, 255 } })
        else
            ascendBtn_:SetStyle({
                backgroundColor = { 50, 40, 60, 200 },
                borderColor = { 80, 70, 100, 100 },
                pointerEvents = "none",
                opacity = 0.5,
            })
            ascendBtn_:RemoveAllChildren()
            ascendBtn_:AddChild(UI.Label { text = "转型 (无收益)", fontSize = 16, fontColor = { 255, 255, 255, 255 } })
        end
    end
end

return AP
