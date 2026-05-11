-- ============================================================================
-- core/SugarLumpManager.lua
-- 糖块系统核心逻辑：生长周期、收获、建筑等级升级
-- ============================================================================

local GameState = require("core.GameState")
local Buildings = require("config.Buildings")
local SD = require("config.SugarLumpDefs")
local SaveBridge = require("core.SaveBridge")

local SLM = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

--- 是否已解锁糖块系统
local unlocked_ = false

--- 当前持有糖块数量
local lumps_ = 0

--- 累计收获糖块总数
local totalHarvested_ = 0

--- 当前生长进度（秒）
local growthTimer_ = 0

--- 当前生长的糖块类型（在凝结开始时确定）
---@type table|nil
local currentType_ = nil

--- 各建筑等级 { [buildingIndex] = level }
local buildingLevels_ = {}

--- 回调
local onHarvest_ = nil         -- function(amount, lumpType)
local onStageChange_ = nil     -- function(newStage)
local onUnlock_ = nil          -- function()
local onTriggerLucky_ = nil    -- function() 草根人脉触发黄金商机

-- ============================================================================
-- 初始化
-- ============================================================================

function SLM.Init()
    unlocked_ = false
    lumps_ = 0
    totalHarvested_ = 0
    growthTimer_ = 0
    currentType_ = nil
    buildingLevels_ = {}

    -- 初始化所有建筑等级为 0
    for i = 1, #Buildings.buildings do
        buildingLevels_[i] = 0
    end

    -- 自注册存档分组（独立顶层 key）
    SaveBridge.Register("sugarlump", SLM.GetSaveData, SLM.LoadSaveData, function()
        unlocked_ = false
        lumps_ = 0
        totalHarvested_ = 0
        growthTimer_ = 0
        currentType_ = nil
        buildingLevels_ = {}
        for i = 1, #Buildings.buildings do
            buildingLevels_[i] = 0
        end
    end)
end

-- ============================================================================
-- 回调设置
-- ============================================================================

function SLM.SetOnHarvest(fn)
    onHarvest_ = fn
end

function SLM.SetOnStageChange(fn)
    onStageChange_ = fn
end

function SLM.SetOnUnlock(fn)
    onUnlock_ = fn
end

function SLM.SetOnTriggerLucky(fn)
    onTriggerLucky_ = fn
end

-- ============================================================================
-- 生长状态查询
-- ============================================================================

--- 获取当前生长阶段
---@return number SD.STAGE_*
function SLM.GetStage()
    if not unlocked_ then return SD.STAGE_NONE end

    if growthTimer_ < SD.COALESCING_DURATION then
        return SD.STAGE_COALESCING
    elseif growthTimer_ < SD.COALESCING_DURATION + SD.MATURE_DURATION then
        return SD.STAGE_MATURE
    else
        return SD.STAGE_RIPE
    end
end

--- 获取生长进度百分比 [0, 1]
---@return number
function SLM.GetGrowthProgress()
    if not unlocked_ then return 0 end
    return math.min(1, growthTimer_ / SD.TOTAL_CYCLE)
end

--- 获取当前阶段内的进度百分比 [0, 1]
---@return number
function SLM.GetStageProgress()
    if not unlocked_ then return 0 end

    local stage = SLM.GetStage()
    if stage == SD.STAGE_COALESCING then
        return growthTimer_ / SD.COALESCING_DURATION
    elseif stage == SD.STAGE_MATURE then
        return (growthTimer_ - SD.COALESCING_DURATION) / SD.MATURE_DURATION
    else
        return (growthTimer_ - SD.COALESCING_DURATION - SD.MATURE_DURATION) / SD.RIPE_DURATION
    end
end

--- 获取距离下一阶段的剩余时间（秒）
---@return number
function SLM.GetTimeToNextStage()
    if not unlocked_ then return 0 end

    local stage = SLM.GetStage()
    if stage == SD.STAGE_COALESCING then
        return SD.COALESCING_DURATION - growthTimer_
    elseif stage == SD.STAGE_MATURE then
        return (SD.COALESCING_DURATION + SD.MATURE_DURATION) - growthTimer_
    else
        return SD.TOTAL_CYCLE - growthTimer_
    end
end

--- 获取当前生长的糖块类型
---@return table|nil
function SLM.GetCurrentType()
    return currentType_
end

--- 格式化剩余时间为 mm:ss
---@param seconds number
---@return string
function SLM.FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

-- ============================================================================
-- 糖块数量
-- ============================================================================

function SLM.GetLumps()
    return lumps_
end

function SLM.AddLumps(amount)
    lumps_ = math.floor(lumps_ + amount)
end

function SLM.GetTotalHarvested()
    return totalHarvested_
end

function SLM.IsUnlocked()
    return unlocked_
end

--- [调试] 立即进入成熟阶段
function SLM.DebugMature()
    if not unlocked_ then
        unlocked_ = true
        currentType_ = SD.RollType()
    end
    growthTimer_ = SD.COALESCING_DURATION
    print("[SugarLump] Debug: 立即成熟")
end

-- ============================================================================
-- 收获
-- ============================================================================

--- 尝试收获当前糖块
---@return boolean 是否成功收获
---@return number 获得的糖块数量
---@return string|nil 失败原因
function SLM.TryHarvest()
    if not unlocked_ then
        return false, 0, "未解锁"
    end

    local stage = SLM.GetStage()

    if stage == SD.STAGE_COALESCING then
        return false, 0, "尚未成熟"
    end

    local lumpType = currentType_ or SD.types[1]

    -- Cookie Clicker 规则：不再有"碎裂失败"
    -- 熟识阶段收获有 50% 概率少得 1 个（在 CalcYield 中处理）
    local amount = SD.CalcYield(lumpType, stage)
    lumps_ = lumps_ + amount
    totalHarvested_ = totalHarvested_ + amount
    print("[SugarLump] 收获 " .. lumpType.name .. " x" .. amount ..
          " | 持有: " .. lumps_ .. " | 累计: " .. totalHarvested_)

    if onHarvest_ then
        onHarvest_(amount, lumpType)
    end

    -- 草根人脉特殊效果：概率触发黄金商机
    if lumpType.triggerLucky and math.random() < (lumpType.triggerLuckyChance or 0.4) then
        if onTriggerLucky_ then
            onTriggerLucky_()
        end
        print("[SugarLump] 草根人脉触发黄金商机！")
    end

    -- 贵人人脉特殊效果：立即开始新周期（跳过接触阶段）
    if lumpType.resetCooldown then
        growthTimer_ = SD.COALESCING_DURATION  -- 直接跳到成熟
        currentType_ = SD.RollType()
        print("[SugarLump] 贵人效果：立即进入成熟阶段！")
    else
        SLM.StartNewGrowth()
    end

    return true, amount, nil
end

--- 开始新的生长周期
function SLM.StartNewGrowth()
    growthTimer_ = 0
    currentType_ = SD.RollType()
    print("[SugarLump] 新糖块开始生长: " .. currentType_.name)
end

-- ============================================================================
-- 建筑等级升级
-- ============================================================================

--- 获取建筑等级
---@param buildingIndex number
---@return number
function SLM.GetBuildingLevel(buildingIndex)
    return buildingLevels_[buildingIndex] or 0
end

--- 获取升级到下一级需要的糖块数
---@param buildingIndex number
---@return number
function SLM.GetUpgradeCost(buildingIndex)
    local currentLevel = SLM.GetBuildingLevel(buildingIndex)
    return SD.GetUpgradeCost(currentLevel + 1)
end

--- 是否可以升级建筑
---@param buildingIndex number
---@return boolean
---@return string|nil 不可升级的原因
function SLM.CanUpgradeBuilding(buildingIndex)
    if not unlocked_ then
        return false, "糖块未解锁"
    end

    local building = Buildings.buildings[buildingIndex]
    if not building then
        return false, "建筑不存在"
    end

    if building.count <= 0 then
        return false, "未拥有此建筑"
    end

    local currentLevel = SLM.GetBuildingLevel(buildingIndex)
    if currentLevel >= SD.MAX_BUILDING_LEVEL then
        return false, "已达最高等级"
    end

    local cost = SD.GetUpgradeCost(currentLevel + 1)
    if lumps_ < cost then
        return false, "糖块不足"
    end

    return true, nil
end

--- 升级建筑
---@param buildingIndex number
---@return boolean 是否成功
function SLM.UpgradeBuilding(buildingIndex)
    local canUpgrade, reason = SLM.CanUpgradeBuilding(buildingIndex)
    if not canUpgrade then
        print("[SugarLump] 无法升级: " .. (reason or ""))
        return false
    end

    local currentLevel = SLM.GetBuildingLevel(buildingIndex)
    local cost = SD.GetUpgradeCost(currentLevel + 1)
    lumps_ = lumps_ - cost
    buildingLevels_[buildingIndex] = currentLevel + 1

    local building = Buildings.buildings[buildingIndex]
    print("[SugarLump] " .. building.name .. " 升级到 Lv." .. (currentLevel + 1) ..
          " | 花费 " .. cost .. " 糖块 | 剩余: " .. lumps_)

    return true
end

--- 获取建筑等级带来的 CpS 倍率
---@param buildingIndex number
---@return number 倍率（如 1.05 表示 +5%）
function SLM.GetBuildingLevelMultiplier(buildingIndex)
    local level = SLM.GetBuildingLevel(buildingIndex)
    return 1 + level * SD.LEVEL_CPS_BONUS
end

-- ============================================================================
-- Sugar Baking 加成
-- ============================================================================

--- 获取 Sugar Baking 总 CpS 倍率
---@return number
function SLM.GetSugarBakingMultiplier()
    local effectiveLumps = math.min(lumps_, SD.SUGAR_BAKING_CAP)
    return 1 + effectiveLumps * SD.SUGAR_BAKING_BONUS
end

-- ============================================================================
-- 帧更新
-- ============================================================================

--- 每帧更新
---@param dt number 帧间隔
function SLM.Update(dt)
    -- 检查是否解锁
    if not unlocked_ then
        -- 计算累计总产出
        local totalProduced = 0
        for _, b in ipairs(Buildings.buildings) do
            totalProduced = totalProduced + b.totalProduced
        end
        totalProduced = totalProduced + GameState.coins

        if totalProduced >= SD.UNLOCK_TOTAL_PRODUCED then
            unlocked_ = true
            SLM.StartNewGrowth()
            print("[SugarLump] 糖块系统已解锁！累计产出: " .. GameState.FormatNumber(totalProduced))
            if onUnlock_ then
                onUnlock_()
            end
        end
        return
    end

    -- 记录旧阶段
    local oldStage = SLM.GetStage()

    -- 推进生长
    growthTimer_ = growthTimer_ + dt

    -- 检查自动掉落（Cookie Clicker：自动掉落固定得 1 个）
    if growthTimer_ >= SD.TOTAL_CYCLE then
        local lumpType = currentType_ or SD.types[1]
        local amount = 1  -- 自动掉落固定 1 个
        lumps_ = lumps_ + amount
        totalHarvested_ = totalHarvested_ + amount
        print("[SugarLump] 糖块自动掉落: " .. lumpType.name .. " x" .. amount)
        if onHarvest_ then
            onHarvest_(amount, lumpType)
        end
        SLM.StartNewGrowth()
        return
    end

    -- 检查阶段变化
    local newStage = SLM.GetStage()
    if newStage ~= oldStage and onStageChange_ then
        print("[SugarLump] 阶段变化: " .. SD.stageNames[oldStage] .. " → " .. SD.stageNames[newStage])
        onStageChange_(newStage)
    end
end

-- ============================================================================
-- 存档/读档
-- ============================================================================

--- 导出存档数据
---@return table
function SLM.GetSaveData()
    local levels = {}
    for i, lv in pairs(buildingLevels_) do
        if lv > 0 then levels[tostring(i)] = lv end
    end
    return {
        unlocked = unlocked_,
        lumps = lumps_,
        totalHarvested = totalHarvested_,
        growthTimer = growthTimer_,
        currentType = currentType_ and currentType_.id or nil,
        buildingLevels = levels,
        savedAt = os.time(),
    }
end

--- 从存档恢复数据
---@param data table
function SLM.LoadSaveData(data)
    if not data then return end
    unlocked_ = data.unlocked or false
    lumps_ = data.lumps or 0
    totalHarvested_ = data.totalHarvested or 0
    growthTimer_ = data.growthTimer or 0

    -- 离线时间补偿：将离线期间的时间加到 growthTimer_
    local offlineAutoDrop = 0
    if unlocked_ and data.savedAt then
        local offlineSec = os.time() - data.savedAt
        if offlineSec > 0 then
            -- 离线期间可能跨越多个完整周期，每个周期自动掉落 1 个
            local remaining = growthTimer_ + offlineSec
            while remaining >= SD.TOTAL_CYCLE do
                offlineAutoDrop = offlineAutoDrop + 1
                remaining = remaining - SD.TOTAL_CYCLE
            end
            if offlineAutoDrop > 0 then
                lumps_ = lumps_ + offlineAutoDrop
                totalHarvested_ = totalHarvested_ + offlineAutoDrop
                print("[SugarLump] 离线自动掉落 " .. offlineAutoDrop .. " 个人脉")
            end
            growthTimer_ = remaining
            local stageName = growthTimer_ < SD.COALESCING_DURATION and "接触中"
                or growthTimer_ < SD.COALESCING_DURATION + SD.MATURE_DURATION and "熟识"
                or "深交"
            print("[SugarLump] 离线补偿 " .. offlineSec .. " 秒 → growthTimer=" ..
                  math.floor(growthTimer_) .. "s 阶段=" .. stageName)
        end
    end

    -- 恢复糖块类型
    currentType_ = nil
    if offlineAutoDrop > 0 then
        -- 离线期间经历了完整周期，旧类型已自动掉落，为新周期重新 roll
        currentType_ = SD.RollType()
    else
        -- 未跨周期，恢复存档中保存的类型
        if data.currentType then
            for _, t in ipairs(SD.types) do
                if t.id == data.currentType then
                    currentType_ = t
                    break
                end
            end
        end
    end
    if unlocked_ and not currentType_ then
        currentType_ = SD.RollType()
    end

    -- 恢复建筑等级
    buildingLevels_ = {}
    for i = 1, #Buildings.buildings do
        buildingLevels_[i] = 0
    end
    if data.buildingLevels then
        for k, v in pairs(data.buildingLevels) do
            local idx = tonumber(k)
            if idx then buildingLevels_[idx] = v end
        end
    end
    print("[SugarLumpManager] 存档恢复 | 糖块:" .. lumps_ .. " 累计:" .. totalHarvested_)
end

return SLM
