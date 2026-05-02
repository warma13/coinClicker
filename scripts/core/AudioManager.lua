-- ============================================================================
-- core/AudioManager.lua
-- 音效管理模块：统一管理 BGM 和音效播放
-- ============================================================================

local AM = {}

---@type Scene
local scene_ = nil

-- 音效资源缓存
local sounds = {}

-- BGM 相关
---@type Node
local bgmNode_ = nil
---@type SoundSource
local bgmSource_ = nil

-- 音效节点（复用）
---@type Node
local sfxNode_ = nil

-- 配置
local config = {
    bgmVolume = 0.4,
    sfxVolume = 1.0,
}

--- 预加载音效资源
---@param key string 标识名
---@param path string 资源路径
---@param looped boolean|nil 是否循环
local function LoadSound(key, path, looped)
    local sound = cache:GetResource("Sound", path)
    if sound then
        sound.looped = looped or false
        sounds[key] = sound
    else
        print("[AudioManager] WARNING: Failed to load sound: " .. path)
    end
end

--- 初始化音效系统
---@param gameScene Scene 游戏场景
function AM.Init(gameScene)
    scene_ = gameScene

    -- 创建 BGM 节点
    bgmNode_ = scene_:CreateChild("BGM")
    bgmSource_ = bgmNode_:CreateComponent("SoundSource")
    bgmSource_.soundType = "Music"
    bgmSource_.gain = config.bgmVolume

    -- 创建音效节点
    sfxNode_ = scene_:CreateChild("SFX")

    -- 预加载音效
    LoadSound("click", "audio/sfx/coin_click.ogg", false)
    LoadSound("btn_click", "audio/sfx/btn_click.ogg", false)
    LoadSound("bgm", "audio/music/bgm.ogg", true)

    print("[AudioManager] Initialized")
end

-- BGM 是否应该在播放
local bgmShouldPlay_ = false

--- 播放 BGM
function AM.PlayBGM()
    if bgmSource_ and sounds["bgm"] then
        sounds["bgm"].looped = true
        bgmSource_:Play(sounds["bgm"])
        bgmShouldPlay_ = true
    end
end

--- 停止 BGM
function AM.StopBGM()
    bgmShouldPlay_ = false
    if bgmSource_ then
        bgmSource_:Stop()
    end
end

--- 帧更新：检测 BGM 意外停止后自动重播
---@param dt number
function AM.Update(dt)
    if bgmShouldPlay_ and bgmSource_ and not bgmSource_.playing then
        if sounds["bgm"] then
            sounds["bgm"].looped = true
            bgmSource_:Play(sounds["bgm"])
        end
    end
end

--- 设置 BGM 音量
---@param volume number 0.0 ~ 1.0
function AM.SetBGMVolume(volume)
    config.bgmVolume = volume
    if bgmSource_ then
        bgmSource_.gain = volume
    end
end

--- 播放音效
---@param key string 音效标识名
function AM.PlaySFX(key)
    local sound = sounds[key]
    if not sound or not sfxNode_ then return end

    -- 每次创建新的 SoundSource 播放，自动移除
    local source = sfxNode_:CreateComponent("SoundSource")
    source.soundType = "Effect"
    source.gain = config.sfxVolume
    source.autoRemoveMode = REMOVE_COMPONENT
    source:Play(sound)
end

--- 播放按钮点击音效
function AM.PlayBtnClick()
    AM.PlaySFX("btn_click")
end

--- 设置音效音量
---@param volume number 0.0 ~ 1.0
function AM.SetSFXVolume(volume)
    config.sfxVolume = volume
end

return AM
