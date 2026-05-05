-- ============================================================================
-- ui/SettingsPanel.lua
-- 设置面板：音乐/音效音量调节 + 手动保存
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local AudioManager = require("core.AudioManager")
local SlotSaveSystem = require("core.SlotSaveSystem")

local SP = {}

-- ======== 状态 ========
local uiRoot_       = nil   -- UI 根节点
local overlay_      = nil   -- 遮罩层
local btnWidget_    = nil   -- 设置按钮
local isOpen_       = false
local bgmSlider_    = nil   -- BGM 滑块引用
local sfxSlider_    = nil   -- SFX 滑块引用
local saveStatusLabel_ = nil -- 保存状态文字

-- ============================================================================
-- 弹窗
-- ============================================================================

--- 关闭设置弹窗
function SP.CloseModal()
    if not isOpen_ then return end
    isOpen_ = false
    if overlay_ and uiRoot_ then
        uiRoot_:RemoveChild(overlay_)
    end
    overlay_ = nil
    bgmSlider_ = nil
    sfxSlider_ = nil
    saveStatusLabel_ = nil
end

--- 打开设置弹窗
function SP.OpenModal()
    if isOpen_ then return end
    if not uiRoot_ then return end
    isOpen_ = true

    AudioManager.PlayBtnClick()

    local settings = GameState.settings

    -- 百分比标签（先创建，闭包捕获）
    local bgmVolLabel_ = UI.Label {
        text = math.floor(settings.bgmVolume * 100) .. "%",
        fontSize = 12,
        fontColor = { 160, 160, 180, 200 },
    }
    local sfxVolLabel_ = UI.Label {
        text = math.floor(settings.sfxVolume * 100) .. "%",
        fontSize = 12,
        fontColor = { 160, 160, 180, 200 },
    }

    -- BGM 滑块
    bgmSlider_ = UI.Slider {
        value = math.floor(settings.bgmVolume * 100),
        min = 0, max = 100,
        step = 5,
        trackHeight = 4,
        thumbSize = 18,
        onChange = function(self, value)
            local vol = value / 100
            GameState.settings.bgmVolume = vol
            AudioManager.SetBGMVolume(vol)
            bgmVolLabel_:SetText(math.floor(value) .. "%")
        end,
        onChangeEnd = function(self, value)
            SlotSaveSystem.MarkDirty()
        end,
    }

    -- SFX 滑块
    sfxSlider_ = UI.Slider {
        value = math.floor(settings.sfxVolume * 100),
        min = 0, max = 100,
        step = 5,
        trackHeight = 4,
        thumbSize = 18,
        onChange = function(self, value)
            local vol = value / 100
            GameState.settings.sfxVolume = vol
            AudioManager.SetSFXVolume(vol)
            sfxVolLabel_:SetText(math.floor(value) .. "%")
        end,
        onChangeEnd = function(self, value)
            SlotSaveSystem.MarkDirty()
        end,
    }

    -- 保存状态标签
    saveStatusLabel_ = UI.Label {
        text = "",
        fontSize = 11,
        fontColor = { 120, 220, 120, 200 },
        textAlign = "center",
        width = "100%",
        height = 16,
    }

    -- 创建弹窗遮罩
    overlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = "100%", height = "100%",
        zIndex = 200,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        pointerEvents = "auto",
        onPointerDown = function()
            SP.CloseModal()
        end,
        children = {
            -- 弹窗面板
            UI.Panel {
                width = 280,
                flexDirection = "column",
                backgroundColor = { 30, 28, 45, 250 },
                borderRadius = 10,
                borderColor = { 80, 70, 120, 100 },
                borderWidth = 1,
                paddingTop = 16, paddingBottom = 16,
                paddingLeft = 20, paddingRight = 20,
                gap = 14,
                pointerEvents = "auto",
                onPointerDown = function(self, event)
                    if event and event.stopPropagation then
                        event:stopPropagation()
                    end
                end,
                children = {
                    -- 标题栏
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "space-between",
                        children = {
                            UI.Label {
                                text = "设置",
                                fontSize = 16,
                                fontColor = { 255, 220, 80, 255 },
                                fontWeight = "bold",
                            },
                            UI.Panel {
                                paddingLeft = 8, paddingRight = 8,
                                paddingTop = 4, paddingBottom = 4,
                                borderRadius = 4,
                                backgroundColor = { 60, 50, 90, 180 },
                                pointerEvents = "auto",
                                onPointerDown = function()
                                    SP.CloseModal()
                                end,
                                children = {
                                    UI.Label {
                                        text = "✕",
                                        fontSize = 14,
                                        fontColor = { 180, 180, 200, 220 },
                                    },
                                },
                            },
                        },
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 70, 120, 80 },
                    },
                    -- BGM 音量
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 6,
                        children = {
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                justifyContent = "space-between",
                                alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = "音乐音量",
                                        fontSize = 13,
                                        fontColor = { 200, 200, 220, 255 },
                                    },
                                    bgmVolLabel_,
                                },
                            },
                            bgmSlider_,
                        },
                    },
                    -- SFX 音量
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 6,
                        children = {
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                justifyContent = "space-between",
                                alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = "音效音量",
                                        fontSize = 13,
                                        fontColor = { 200, 200, 220, 255 },
                                    },
                                    sfxVolLabel_,
                                },
                            },
                            sfxSlider_,
                        },
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 70, 120, 60 },
                    },
                    -- 保存按钮
                    UI.Panel {
                        width = "100%",
                        justifyContent = "center",
                        alignItems = "center",
                        paddingTop = 8, paddingBottom = 4,
                        flexDirection = "column",
                        gap = 6,
                        children = {
                            UI.Button {
                                text = "保存游戏",
                                variant = "primary",
                                width = "100%",
                                onClick = function()
                                    AudioManager.PlayBtnClick()
                                    SlotSaveSystem.SaveNow()
                                    if saveStatusLabel_ then
                                        saveStatusLabel_:SetText("已保存!")
                                    end
                                end,
                            },
                            saveStatusLabel_,
                        },
                    },
                },
            },
        },
    }

    -- 添加到根节点
    uiRoot_:AddChild(overlay_)
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 创建设置按钮（absolute 定位，排行榜按钮左侧）
---@return table button
function SP.Create()
    btnWidget_ = UI.Panel {
        id = "settingsBtn",
        position = "absolute",
        right = "30%",
        top = 10,
        marginRight = 120,  -- 排行榜按钮约 100px 宽 + 8px margin + 间距
        paddingLeft = 10, paddingRight = 10,
        paddingTop = 6, paddingBottom = 6,
        backgroundColor = { 50, 40, 80, 220 },
        borderRadius = 6,
        borderColor = { 80, 70, 120, 150 },
        pointerEvents = "auto",
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        onPointerDown = function()
            SP.OpenModal()
        end,
        children = {
            UI.Label {
                text = "设置",
                fontSize = 13,
                fontColor = { 255, 220, 80, 255 },
                fontWeight = "bold",
            },
        },
    }
    return btnWidget_
end

--- 初始化
---@param root table UI 根节点
function SP.Init(root)
    uiRoot_ = root
end

return SP
