-- ============================================================================
-- config/BuildingUpgrades.lua
-- 建筑效率升级（Tiered Upgrades）数据定义
-- 每个建筑拥有若干 "效率翻倍" 升级，按建筑持有数解锁
-- 解锁阈值参考 Cookie Clicker: 1, 5, 25, 50, 100, 150, 200
-- 价格 = 建筑基础价格 × 倍率
-- ============================================================================

local BuildingUpgrades = {}

--- 通用解锁阈值与价格倍率
--- { needCount, priceMul }
local tiers = {
    { need = 1,   priceMul = 10 },
    { need = 5,   priceMul = 50 },
    { need = 25,  priceMul = 500 },
    { need = 50,  priceMul = 5000 },
    { need = 100, priceMul = 50000 },
    { need = 150, priceMul = 500000 },
    { need = 200, priceMul = 5000000 },
}

--- 光标专用：只有 3 个基础倍率升级（x2 效率），之后转入手指升级线
--- 价格和阈值参考 Cookie Clicker 文档 §3.1
local cursorTiers = {
    { need = 1,  fixedCost = 100 },      -- 强化食指（Reinforced index finger）
    { need = 1,  fixedCost = 500 },      -- 腕管预防霜（Carpal tunnel prevention cream）
    { need = 10, fixedCost = 10000 },    -- 双手灵巧（Ambidextrous）
}

BuildingUpgrades.tiers = tiers

--- 为每个建筑动态生成升级列表
--- 光标只有 3 个效率升级（之后由手指升级线接手），其他建筑用通用 7 阶
--- 返回 upgrades[buildingIndex][tierIndex] = { bought, cost, needCount, ... }
---@param buildings table Buildings.buildings 数组
---@return table
function BuildingUpgrades.Generate(buildings)
    local all = {}
    for bi, b in ipairs(buildings) do
        local useTiers = (b.id == "cursor") and cursorTiers or tiers
        local bUpgrades = {}
        for ti, tier in ipairs(useTiers) do
            bUpgrades[ti] = {
                bought = false,
                cost = tier.fixedCost or (b.baseCost * tier.priceMul - (b.baseCost * tier.priceMul) % 1),
                needCount = tier.need,
                buildingId = b.id,
                buildingName = b.name,
                buildingIcon = b.icon,
                buildingIconImage = b.iconImage,
                tierIndex = ti,
                buildingIndex = bi,
            }
        end
        all[bi] = bUpgrades
    end
    return all
end

--- 获取建筑的当前效率倍率（2^已购买升级数）
---@param upgrades table 该建筑的升级列表
---@return number
function BuildingUpgrades.GetMultiplier(upgrades)
    local count = 0
    for _, u in ipairs(upgrades) do
        if u.bought then count = count + 1 end
    end
    return 2 ^ count  -- 每个升级翻倍
end

--- 获取所有已解锁且未购买的升级（用于 UI 显示）
---@param allUpgrades table 全量升级数据
---@param buildings table 建筑数据
---@return table[] 可见升级列表（平铺）
function BuildingUpgrades.GetVisible(allUpgrades, buildings)
    local visible = {}
    for bi, bUpgrades in ipairs(allUpgrades) do
        local b = buildings[bi]
        for _, u in ipairs(bUpgrades) do
            -- 已购买的不显示，未解锁（建筑数不够）的也不显示
            if (not u.bought) and b.count >= u.needCount then
                visible[#visible + 1] = u
            end
        end
    end
    return visible
end

return BuildingUpgrades
