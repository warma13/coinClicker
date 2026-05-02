-- ============================================================================
-- core/DragonManager.lua
-- 龙系统核心逻辑（Krumblor）
-- 龙等级、光环装备、龙掉落
-- ============================================================================

local GameState = require("core.GameState")
local Buildings = require("config.Buildings")
local DD = require("config.DragonDefs")

local DM = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

--- 龙等级 (0-24)
local dragonLevel_ = -1  -- -1 = 未购买龙蛋

--- 已解锁的光环 id 集合 { [auraId] = true }
local unlockedAuras_ = {}

--- 装备的光环 (最多2个槽位)
--- slot 1 = 主光环（右），slot 2 = 副光环（左）
local equippedAuras_ = { nil, nil }

--- 副光环槽是否解锁
local secondSlotUnlocked_ = false

--- 已收集的龙掉落物 { [dropId] = true }
local collectedDrops_ = {}

--- 龙掉落是否解锁（需天堂升级 Pet the dragon）
local dropsUnlocked_ = false

--- 掉落轮换计时器
local dropRotateTimer_ = 0

--- 当前可掉落的物品索引 (1-based)
local currentDropIndex_ = 1

--- 回调
local onLevelUp_ = nil          -- function(newLevel, auraUnlocked)
local onEquipAura_ = nil        -- function(slot, auraId)
local onDrop_ = nil             -- function(dropItem)

-- ============================================================================
-- 初始化
-- ============================================================================

function DM.Init()
    dragonLevel_ = -1
    unlockedAuras_ = {}
    equippedAuras_ = { nil, nil }
    secondSlotUnlocked_ = false
    collectedDrops_ = {}
    dropsUnlocked_ = false
    dropRotateTimer_ = 0
    currentDropIndex_ = 1
end

-- ============================================================================
-- 回调设置
-- ============================================================================

function DM.SetOnLevelUp(fn) onLevelUp_ = fn end
function DM.SetOnEquipAura(fn) onEquipAura_ = fn end
function DM.SetOnDrop(fn) onDrop_ = fn end

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 龙是否已购买（等级 >= 0）
---@return boolean
function DM.IsUnlocked()
    return dragonLevel_ >= 0
end

--- 获取龙等级
---@return number
function DM.GetLevel()
    return dragonLevel_
end

--- 获取当前等级定义
---@return table|nil
function DM.GetCurrentLevelDef()
    return DD.GetLevel(dragonLevel_)
end

--- 获取下一级定义
---@return table|nil
function DM.GetNextLevelDef()
    if dragonLevel_ >= DD.MAX_LEVEL then return nil end
    return DD.GetLevel(dragonLevel_ + 1)
end

--- 是否满级
---@return boolean
function DM.IsMaxLevel()
    return dragonLevel_ >= DD.MAX_LEVEL
end

--- 副光环槽是否解锁
---@return boolean
function DM.IsSecondSlotUnlocked()
    return secondSlotUnlocked_
end

--- 获取装备的光环
---@param slot number 1 or 2
---@return table|nil aura definition
function DM.GetEquippedAura(slot)
    local auraId = equippedAuras_[slot]
    if not auraId then return nil end
    return DD.FindAura(auraId)
end

--- 获取装备的光环 id
---@param slot number 1 or 2
---@return string|nil
function DM.GetEquippedAuraId(slot)
    return equippedAuras_[slot]
end

--- 获取所有已解锁的光环列表
---@return table[]
function DM.GetUnlockedAuras()
    local result = {}
    for _, a in ipairs(DD.auras) do
        if unlockedAuras_[a.id] then
            result[#result + 1] = a
        end
    end
    return result
end

--- 光环是否已解锁
---@param auraId string
---@return boolean
function DM.IsAuraUnlocked(auraId)
    return unlockedAuras_[auraId] == true
end

--- 龙掉落是否解锁
---@return boolean
function DM.IsDropsUnlocked()
    return dropsUnlocked_
end

--- 设置掉落解锁状态（由飞升系统设置）
---@param unlocked boolean
function DM.SetDropsUnlocked(unlocked)
    dropsUnlocked_ = unlocked
end

--- 获取已收集的掉落物
---@return table { [dropId] = true }
function DM.GetCollectedDrops()
    return collectedDrops_
end

--- 是否已收集某掉落物
---@param dropId string
---@return boolean
function DM.HasDrop(dropId)
    return collectedDrops_[dropId] == true
end

-- ============================================================================
-- 升级（献祭）
-- ============================================================================

--- 检查是否能升级到下一级
---@return boolean canUpgrade
---@return string|nil reason 不能升级的原因
function DM.CanUpgrade()
    if dragonLevel_ >= DD.MAX_LEVEL then
        return false, "已满级"
    end

    local nextDef = DD.GetLevel(dragonLevel_ + 1)
    if not nextDef then return false, "无下一级定义" end

    if nextDef.costType == "none" then
        return true, nil
    elseif nextDef.costType == "cookie" then
        if GameState.coins < nextDef.cost then
            return false, "金币不足"
        end
        return true, nil
    elseif nextDef.costType == "building" then
        local b = Buildings.buildings[nextDef.buildIdx]
        if not b then return false, "建筑不存在" end
        if b.count < nextDef.need then
            return false, "需要 " .. nextDef.need .. " 个 " .. b.name .. "（当前 " .. b.count .. "）"
        end
        return true, nil
    elseif nextDef.costType == "building_all" then
        for _, b in ipairs(Buildings.buildings) do
            if b.count < nextDef.need then
                return false, "需要每种建筑 " .. nextDef.need .. " 个（" .. b.name .. " 仅 " .. b.count .. "）"
            end
        end
        return true, nil
    end

    return false, "未知成本类型"
end

--- 获取升级描述（用于 UI 显示）
---@return string
function DM.GetUpgradeCostText()
    local nextDef = DM.GetNextLevelDef()
    if not nextDef then return "已满级" end

    if nextDef.costType == "none" then
        return "免费"
    elseif nextDef.costType == "cookie" then
        return GameState.FormatNumber(nextDef.cost)
    elseif nextDef.costType == "building" then
        local b = Buildings.buildings[nextDef.buildIdx]
        if b then
            return nextDef.need .. " 个 " .. b.name
        end
        return "???"
    elseif nextDef.costType == "building_all" then
        return "每种建筑 " .. nextDef.need .. " 个"
    end

    return "???"
end

--- 获取升级费用的图标路径（用于 UI 图文混排）
---@return string|nil iconImage 图标路径，nil 表示纯文本
function DM.GetUpgradeCostIcon()
    local nextDef = DM.GetNextLevelDef()
    if not nextDef then return nil end

    if nextDef.costType == "cookie" then
        return "image/金币.png"
    elseif nextDef.costType == "building" then
        local b = Buildings.buildings[nextDef.buildIdx]
        if b then return b.iconImage end
    end
    return nil
end

--- 执行升级
---@return boolean success
function DM.Upgrade()
    local canUpgrade, reason = DM.CanUpgrade()
    if not canUpgrade then
        print("[Dragon] 升级失败: " .. (reason or ""))
        return false
    end

    local nextDef = DD.GetLevel(dragonLevel_ + 1)
    if not nextDef then return false end

    -- 扣除费用
    if nextDef.costType == "cookie" then
        GameState.coins = GameState.coins - nextDef.cost
    elseif nextDef.costType == "building" then
        local b = Buildings.buildings[nextDef.buildIdx]
        b.count = b.count - nextDef.need
    elseif nextDef.costType == "building_all" then
        for _, b in ipairs(Buildings.buildings) do
            b.count = b.count - nextDef.need
        end
    end

    dragonLevel_ = dragonLevel_ + 1

    -- 解锁光环
    local auraUnlocked = nil
    if nextDef.auraUnlock then
        unlockedAuras_[nextDef.auraUnlock] = true
        auraUnlocked = DD.FindAura(nextDef.auraUnlock)
        print("[Dragon] 光环解锁: " .. (auraUnlocked and auraUnlocked.name or nextDef.auraUnlock))
    end

    -- 解锁副光环槽
    if nextDef.secondSlot then
        secondSlotUnlocked_ = true
        print("[Dragon] 副光环槽解锁！")
    end

    print("[Dragon] 升级至 Lv." .. dragonLevel_ .. " " .. nextDef.name)

    if onLevelUp_ then
        onLevelUp_(dragonLevel_, auraUnlocked)
    end

    return true
end

--- 购买龙蛋（从 -1 升到 0）
---@return boolean
function DM.BuyEgg()
    if dragonLevel_ >= 0 then return false end

    local eggDef = DD.GetLevel(0)
    if not eggDef then return false end

    if GameState.coins < eggDef.cost then return false end

    GameState.coins = GameState.coins - eggDef.cost
    dragonLevel_ = 0
    print("[Dragon] 龙蛋已购买！")

    if onLevelUp_ then
        onLevelUp_(0, nil)
    end

    return true
end

-- ============================================================================
-- 光环装备
-- ============================================================================

--- 装备光环到指定槽位
---@param slot number 1 or 2
---@param auraId string|nil nil = 卸下
---@return boolean
function DM.EquipAura(slot, auraId)
    if slot < 1 or slot > 2 then return false end
    if slot == 2 and not secondSlotUnlocked_ then return false end

    -- 检查光环是否已解锁
    if auraId and not unlockedAuras_[auraId] then return false end

    -- 不能两个槽装同一个光环
    local otherSlot = slot == 1 and 2 or 1
    if auraId and equippedAuras_[otherSlot] == auraId then
        -- 交换：把另一个槽的设为 nil
        equippedAuras_[otherSlot] = nil
    end

    equippedAuras_[slot] = auraId

    local aura = auraId and DD.FindAura(auraId)
    print("[Dragon] 槽位 " .. slot .. " 装备: " .. (aura and aura.name or "空"))

    if onEquipAura_ then
        onEquipAura_(slot, auraId)
    end

    return true
end

-- ============================================================================
-- 龙掉落
-- ============================================================================

--- 抚摸龙（尝试掉落）
---@return table|nil droppedItem
function DM.PetDragon()
    if not dropsUnlocked_ then return nil end
    if dragonLevel_ < 23 then return nil end  -- 需要等级 23 解锁龙掉落

    -- 5% 掉落概率
    if math.random() > DD.DROP_CHANCE then
        return nil
    end

    -- 使用当前轮换索引
    local drop = DD.drops[currentDropIndex_]
    if not drop then return nil end

    -- 已收集的不再重复获取
    if collectedDrops_[drop.id] then
        -- 尝试找未收集的
        for _, d in ipairs(DD.drops) do
            if not collectedDrops_[d.id] then
                drop = d
                break
            end
        end
        -- 全部已收集
        if collectedDrops_[drop.id] then
            return nil
        end
    end

    collectedDrops_[drop.id] = true
    print("[Dragon] 掉落获得: " .. drop.name)

    if onDrop_ then
        onDrop_(drop)
    end

    return drop
end

-- ============================================================================
-- 光环效果计算（供 GameManager.RecalcProduction 使用）
-- ============================================================================

--- 获取某个效果值（遍历两个槽位的光环累加）
---@param fieldName string 光环字段名
---@param defaultVal number 默认值
---@return number
local function GetAuraEffect(fieldName, defaultVal)
    local val = defaultVal
    for slot = 1, 2 do
        local auraId = equippedAuras_[slot]
        if auraId then
            local aura = DD.FindAura(auraId)
            if aura and aura[fieldName] then
                if defaultVal == 1 then
                    -- 乘法字段
                    val = val * aura[fieldName]
                else
                    -- 加法字段
                    val = val + aura[fieldName]
                end
            end
        end
    end
    -- 加上掉落物的效果
    for _, drop in ipairs(DD.drops) do
        if collectedDrops_[drop.id] and drop[fieldName] then
            if defaultVal == 1 then
                val = val * drop[fieldName]
            else
                val = val + drop[fieldName]
            end
        end
    end
    return val
end

--- Kitten 效果加成（Breath of Milk: +5%）
---@return number
function DM.GetKittenBonus()
    return GetAuraEffect("kittenBonus", 0)
end

--- 点击效果加成（Dragon Cursor: +5%）
---@return number
function DM.GetClickBonus()
    return GetAuraEffect("clickBonus", 0)
end

--- 建筑费用折扣（Earth Shatterer + Fierce Hoarder: -2% each）
---@return number 总折扣比例 (0~1)
function DM.GetCostReduction()
    return GetAuraEffect("costReduction", 0)
end

--- 声望 CpS 加成（Dragon God: +5%）
---@return number
function DM.GetPrestigeBonus()
    return GetAuraEffect("prestigeBonus", 0)
end

--- 幸运金币频率加成（Arcane Aura / Epoch Manipulator）
---@return number 乘法倍率
function DM.GetLuckyFreqMul()
    return GetAuraEffect("luckyFreqMul", 1)
end

--- 幸运金币持续加成（Unholy Dominion / Epoch Manipulator）
---@return number 乘法倍率
function DM.GetLuckyDurMul()
    return GetAuraEffect("luckyDurMul", 1)
end

--- 幸运金币奖励加成（Ancestral Metamorphosis）
---@return number 乘法倍率
function DM.GetLuckyRewardMul()
    return GetAuraEffect("luckyRewardMul", 1)
end

--- 产量总倍率（Radiant Appetite: ×2）
---@return number
function DM.GetProductionMul()
    return GetAuraEffect("productionMul", 1)
end

--- CpS 百分比加成（Dragon's Fortune / Dragon Cookie + drops）
---@return number
function DM.GetCpsMul()
    return GetAuraEffect("cpsMul", 0)
end

--- 糖块成熟加速（Dragon's Curve: +5%）
---@return number
function DM.GetSugarBonus()
    return GetAuraEffect("sugarBonus", 0)
end

--- 是否有 Dragon Harvest 光环（Reaper of Fields）
---@return boolean
function DM.HasDragonHarvest()
    for slot = 1, 2 do
        local auraId = equippedAuras_[slot]
        if auraId then
            local aura = DD.FindAura(auraId)
            if aura and aura.dragonHarvest then return true end
        end
    end
    return false
end

--- 是否有 Dragonflight 光环
---@return boolean
function DM.HasDragonflight()
    for slot = 1, 2 do
        local auraId = equippedAuras_[slot]
        if auraId then
            local aura = DD.FindAura(auraId)
            if aura and aura.dragonflightBuff then return true end
        end
    end
    return false
end

--- 是否有奶奶协同光环（Elder Battalion）
---@return boolean
function DM.HasGrandmaSynergy()
    for slot = 1, 2 do
        local auraId = equippedAuras_[slot]
        if auraId then
            local aura = DD.FindAura(auraId)
            if aura and aura.grandmaSynergy then return true end
        end
    end
    return false
end

--- 获取 Elder Battalion 奶奶协同 CpS 加成
--- 每个非奶奶建筑给奶奶 +1% CpS
---@return number 乘法倍率 (1.0 = 无加成)
function DM.GetGrandmaSynergyMul()
    if not DM.HasGrandmaSynergy() then return 1 end
    local nonGrandmaCount = 0
    for _, b in ipairs(Buildings.buildings) do
        if b.id ~= "grandma" then
            nonGrandmaCount = nonGrandmaCount + b.count
        end
    end
    return 1 + nonGrandmaCount * 0.01
end

-- ============================================================================
-- 帧更新
-- ============================================================================

function DM.Update(dt)
    if not dropsUnlocked_ then return end

    -- 掉落轮换计时器
    dropRotateTimer_ = dropRotateTimer_ + dt
    if dropRotateTimer_ >= DD.DROP_ROTATE_INTERVAL then
        dropRotateTimer_ = dropRotateTimer_ - DD.DROP_ROTATE_INTERVAL
        currentDropIndex_ = currentDropIndex_ + 1
        if currentDropIndex_ > #DD.drops then
            currentDropIndex_ = 1
        end
    end
end

-- ============================================================================
-- 存档/读档
-- ============================================================================

--- 导出存档数据
---@return table
function DM.GetSaveData()
    local auras = {}
    for id, _ in pairs(unlockedAuras_) do
        auras[#auras + 1] = id
    end
    local drops = {}
    for id, _ in pairs(collectedDrops_) do
        drops[#drops + 1] = id
    end
    return {
        dragonLevel = dragonLevel_,
        unlockedAuras = auras,
        equippedAuras = { equippedAuras_[1], equippedAuras_[2] },
        secondSlotUnlocked = secondSlotUnlocked_,
        collectedDrops = drops,
        dropsUnlocked = dropsUnlocked_,
    }
end

--- 从存档恢复数据
---@param data table
function DM.LoadSaveData(data)
    if not data then return end
    dragonLevel_ = data.dragonLevel or -1
    secondSlotUnlocked_ = data.secondSlotUnlocked or false
    dropsUnlocked_ = data.dropsUnlocked or false
    dropRotateTimer_ = 0
    currentDropIndex_ = 1

    unlockedAuras_ = {}
    if data.unlockedAuras then
        for _, id in ipairs(data.unlockedAuras) do
            unlockedAuras_[id] = true
        end
    end

    equippedAuras_ = { nil, nil }
    if data.equippedAuras then
        equippedAuras_[1] = data.equippedAuras[1]
        equippedAuras_[2] = data.equippedAuras[2]
    end

    collectedDrops_ = {}
    if data.collectedDrops then
        for _, id in ipairs(data.collectedDrops) do
            collectedDrops_[id] = true
        end
    end
    print("[DragonManager] 存档恢复 | 等级:" .. dragonLevel_ ..
          " 光环:" .. #(data.unlockedAuras or {}) ..
          " 掉落:" .. #(data.collectedDrops or {}))
end

return DM
