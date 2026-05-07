-- ============================================================================
-- core/PurchaseHandler.lua
-- 购买相关逻辑：点击金币、购买建筑、建筑升级、点击升级、一键购买
-- 从 GameManager.lua 中提取
-- ============================================================================

local GameState = require("core.GameState")
local Buildings = require("config.Buildings")
local Upgrades = require("config.Upgrades")
local BuildingUpgrades = require("config.BuildingUpgrades")
local AudioManager = require("core.AudioManager")
local SlotSaveSystem = require("core.SlotSaveSystem")
local AchievementManager = require("core.AchievementManager")
local SeasonManager = require("core.SeasonManager")
local PantheonManager = require("core.PantheonManager")
local GrimoireManager = require("core.GrimoireManager")
local M = {}

--- 注册所有购买相关函数到 GM 表上
---@param GM table GameManager 表
---@param ctx table { ui = {floatingText, coinArea, coinParticle, shopPanel, statsBar}, buildingUpgrades = ref }
function M.Setup(GM, ctx)

    --- 点击金币
    ---@param x number 点击 x 坐标
    ---@param y number 点击 y 坐标
    function GM.OnCoinClick(x, y)
        local S = GameState

        -- 点击频率限制: 最多 15 CPS（对齐 Cookie Clicker）
        local now = time.elapsedTime
        if now - S.lastClickTime < S.clickMinInterval then
            return
        end
        S.lastClickTime = now

        S.totalClicks = S.totalClicks + 1
        local gain = S.coinsPerClick * S.buffCpcMul

        S.coins = S.coins + gain
        S.handmadeCoins = S.handmadeCoins + gain

        -- 研发实验室：消耗黄金触控次数
        if GrimoireManager.IsUnlocked() then
            GrimoireManager.OnClick()
        end

        -- 体力恢复（概率触发，随机 1~10，综合约 500 次点击恢复一次技能）
        if S.stamina < S.staminaMax then
            if math.random() < S.staminaClickChance then
                local amount = math.random(1, 10)
                S.stamina = math.min(S.staminaMax, S.stamina + amount)
                if ctx.ui.floatingText then
                    ctx.ui.floatingText.Show("+" .. amount .. "体力", x, y - 30, { 120, 220, 80, 255 })
                end
            end
        end

        -- 点击音效 + 金币放缩动画
        AudioManager.PlaySFX("click")
        if ctx.ui.coinArea then
            ctx.ui.coinArea.PlayClickAnim()
        end

        -- 在点击位置生成金币粒子
        if ctx.ui.coinParticle and x and y then
            ctx.ui.coinParticle.Spawn(x, y)
        end

        -- 在点击位置显示浮动文本
        if ctx.ui.floatingText and x and y then
            local color = S.buffCpcMul > 1
                and { 255, 215, 0, 255 }   -- buff 激活时金色
                or  { 255, 255, 255, 255 }  -- 正常白色
            ctx.ui.floatingText.Show("+" .. S.FormatNumber(gain), x, y, color)
        end
    end

    --- 购买建筑（支持批量购买）
    ---@param index number 建筑索引
    ---@param amount number|nil 购买数量（默认从 ShopPanel 获取）
    function GM.OnBuyBuilding(index, amount)
        local building = Buildings.buildings[index]
        if not building then return end

        -- 获取购买数量
        local buyAmt = amount or 1
        if not amount and ctx.ui.shopPanel and ctx.ui.shopPanel.GetBuyAmount then
            buyAmt = ctx.ui.shopPanel.GetBuyAmount()
        end

        -- 计算批量费用（含季节/buff/万神殿 费用折扣）
        local costMul = (1 - SeasonManager.GetCostReduction()) * GameState.buffBuildingCostMul
        if PantheonManager.IsUnlocked() then
            costMul = costMul * PantheonManager.GetBuildingCostMultiplier()
        end
        local totalCost = GameState.SafeFloor(GameState.GetBulkCost(building, buyAmt) * costMul)
        if GameState.coins >= totalCost then
            -- 逐个扣费购买（保持价格精度一致）
            for i = 1, buyAmt do
                local cost = GameState.SafeFloor(GameState.GetCost(building) * costMul)
                GameState.coins = GameState.coins - cost
                building.count = building.count + 1
            end
            GM.RecalcProduction()
            GM.RefreshAllUI()
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
            print("Bought " .. building.name .. " x" .. buyAmt ..
                  " (total: " .. building.count .. ")" ..
                  " | CPS: " .. string.format("%.1f", GameState.coinsPerSecond) ..
                  " | CPC: " .. GameState.coinsPerClick)
        end
    end

    --- 购买建筑效率升级
    ---@param buildingIndex number 建筑索引
    ---@param tierIndex number 升级阶索引
    function GM.OnBuyBuildingUpgrade(buildingIndex, tierIndex)
        if not GM.buildingUpgrades then return end
        local bUpgrades = GM.buildingUpgrades[buildingIndex]
        if not bUpgrades then return end
        local upgrade = bUpgrades[tierIndex]
        if not upgrade then return end

        -- 已购买
        if upgrade.bought then return end

        -- 建筑数量不够
        local building = Buildings.buildings[buildingIndex]
        if not building or building.count < upgrade.needCount then return end

        -- 金币不够（含研发实验室升级价格乘数）
        local upgradeCostMul = GrimoireManager.GetUpgradePriceMul()
        local actualCost = GameState.SafeFloor(upgrade.cost * upgradeCostMul)
        if GameState.coins < actualCost then return end

        GameState.coins = GameState.coins - actualCost
        upgrade.bought = true
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        AudioManager.PlayBtnClick()
        print("[BuildingUpgrade] Bought " .. building.name .. " Tier " .. tierIndex ..
              " | Multiplier: x" .. BuildingUpgrades.GetMultiplier(bUpgrades) ..
              " | CPS: " .. string.format("%.1f", GameState.coinsPerSecond))
    end

    --- 购买点击升级
    ---@param index number 升级索引
    function GM.OnBuyClickUpgrade(index)
        local upgrade = Upgrades.clickUpgrades[index]
        if not upgrade then return end

        -- 一次性购买限制
        if upgrade.maxCount and upgrade.count >= upgrade.maxCount then return end

        -- 鼠标升级线需要检查点击次数
        if upgrade.needClicks then
            if GameState.totalClicks < upgrade.needClicks then
                print("[Shop] 需要 " .. upgrade.needClicks .. " 次点击才能购买 " .. upgrade.name)
                return
            end
        end

        -- 幸运升级线需要检查幸运金币点击次数
        if upgrade.needLuckyClicks then
            if GameState.luckyClicks < upgrade.needLuckyClicks then
                print("[Shop] 需要点击 " .. upgrade.needLuckyClicks .. " 次幸运金币才能购买 " .. upgrade.name)
                return
            end
        end

        -- 手指升级线需要检查点金手指数量
        if upgrade.needCursor then
            local cursor = Buildings.buildings[1]
            if cursor and cursor.count < upgrade.needCursor then
                print("[Shop] 需要 " .. upgrade.needCursor .. " 个点金手指才能购买 " .. upgrade.name)
                return
            end
        end

        local baseCost = GameState.GetCost(upgrade)
        local cost = GameState.SafeFloor(baseCost * GrimoireManager.GetUpgradePriceMul())
        if GameState.coins >= cost then
            GameState.coins = GameState.coins - cost
            upgrade.count = upgrade.count + 1
            GM.RecalcProduction()
            GM.RefreshAllUI()
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
            print("Bought " .. upgrade.name .. " x" .. upgrade.count ..
                  " | CPC: " .. string.format("%.1f", GameState.coinsPerClick))
        end
    end

    -- ========================================================================
    -- 一键购买
    -- ========================================================================

    --- 一键购买所有买得起的升级（建筑效率升级 + 点击升级，不含建筑本身）
    function GM.OnBuyAll()
        local bought = 0

        local upgradeCostMul = GrimoireManager.GetUpgradePriceMul()

        -- 1) 购买所有买得起的建筑效率升级
        if GM.buildingUpgrades then
            for bi, bUpgrades in ipairs(GM.buildingUpgrades) do
                local building = Buildings.buildings[bi]
                if building then
                    for ti, upgrade in ipairs(bUpgrades) do
                        local actualCost = GameState.SafeFloor(upgrade.cost * upgradeCostMul)
                        if not upgrade.bought and building.count >= upgrade.needCount
                           and GameState.coins >= actualCost then
                            GameState.coins = GameState.coins - actualCost
                            upgrade.bought = true
                            bought = bought + 1
                        end
                    end
                end
            end
        end

        -- 2) 购买所有买得起的点击升级
        for i, upgrade in ipairs(Upgrades.clickUpgrades) do
            if not (upgrade.maxCount and upgrade.count >= upgrade.maxCount) then
                local canBuy = true
                if upgrade.needClicks and GameState.totalClicks < upgrade.needClicks then canBuy = false end
                if upgrade.needLuckyClicks and GameState.luckyClicks < upgrade.needLuckyClicks then canBuy = false end
                if upgrade.needCursor then
                    local cursor = Buildings.buildings[1]
                    if not cursor or cursor.count < upgrade.needCursor then canBuy = false end
                end
                if canBuy then
                    local baseCost = GameState.GetCost(upgrade)
                    local cost = GameState.SafeFloor(baseCost * upgradeCostMul)
                    if GameState.coins >= cost then
                        GameState.coins = GameState.coins - cost
                        upgrade.count = upgrade.count + 1
                        bought = bought + 1
                    end
                end
            end
        end

        if bought > 0 then
            GM.RecalcProduction()
            GM.RefreshAllUI()
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
            print("[BuyAll] 一键购买了 " .. bought .. " 项升级")
        end
    end

    --- 一键购买所有建筑（优先购买高级建筑，考虑折扣）
    function GM.OnBuyAllBuildings()
        local costMul = (1 - SeasonManager.GetCostReduction()) * GameState.buffBuildingCostMul
        if PantheonManager.IsUnlocked() then
            costMul = costMul * PantheonManager.GetBuildingCostMultiplier()
        end
        local totalBought = 0
        local n = #Buildings.buildings

        -- 从最高级建筑往低级遍历，优先将金币投入高产出建筑
        for i = n, 1, -1 do
            local building = Buildings.buildings[i]
            -- 计算该建筑最大可购买量
            local maxAmt = 0
            local spent = 0.0
            local tempCount = building.count
            while true do
                local price = GameState.SafeFloor(
                    GameState.SafeFloor(building.baseCost * (building.costMul ^ tempCount)) * costMul)
                if spent + price > GameState.coins then break end
                spent = spent + price
                tempCount = tempCount + 1
                maxAmt = maxAmt + 1
                if maxAmt >= 9999 then break end
            end
            if maxAmt >= 1 then
                -- 逐个购买
                for j = 1, maxAmt do
                    local price = GameState.SafeFloor(
                        GameState.SafeFloor(building.baseCost * (building.costMul ^ building.count)) * costMul)
                    if GameState.coins < price then break end
                    GameState.coins = GameState.coins - price
                    building.count = building.count + 1
                    totalBought = totalBought + 1
                end
            end
        end

        if totalBought > 0 then
            GM.RecalcProduction()
            GM.RefreshAllUI()
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
            print("[BuyAllBuildings] 一键购买了 " .. totalBought .. " 个建筑")
        end
    end

end

return M
