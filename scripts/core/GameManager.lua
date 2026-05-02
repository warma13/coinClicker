-- ============================================================================
-- core/GameManager.lua
-- 游戏逻辑调度器：点击、购买、自动产出、Buff、幸运金币
-- ============================================================================

local GameState = require("core.GameState")
local Buildings = require("config.Buildings")
local Upgrades = require("config.Upgrades")
local BuildingUpgrades = require("config.BuildingUpgrades")
local AudioManager = require("core.AudioManager")
local AchievementManager = require("core.AchievementManager")
local GrandmapoManager = require("core.GrandmapoManager")
local WrinklerManager = require("core.WrinklerManager")
local SugarLumpManager = require("core.SugarLumpManager")
local AscensionManager = require("core.AscensionManager")
local SeasonManager = require("core.SeasonManager")
local DragonManager = require("core.DragonManager")
local GD = require("config.GrandmapocalypseDefs")
local DD = require("config.DragonDefs")
local SkillManager = require("core.SkillManager")
local SlotSaveSystem = require("core.SlotSaveSystem")
local SaveBridge = require("core.SaveBridge")

local GM = {}
local skillPanel_ = nil
local skillRefreshTimer_ = 0

-- UI 模块引用（由 main.lua 通过 SetUI 注入）
local statsBar_ = nil
local coinArea_ = nil
local shopPanel_ = nil
local luckyCoin_ = nil
local floatingText_ = nil
local coinParticle_ = nil
local achievementNotify_ = nil
local uiRoot_ = nil
local wrinklerDisplay_ = nil
local researchPanel_ = nil
local sugarLumpDisplay_ = nil
local buildingLevelPanel_ = nil
local heavenlyShop_ = nil
local ascensionPanel_ = nil
local seasonPanel_ = nil
local reindeerDisplay_ = nil
local dragonPanel_ = nil
local achievementPanel_ = nil
local luckyIsWrath_ = false
local grandmapoRefreshTimer_ = 0
local sugarLumpRefreshTimer_ = 0
local ascensionRefreshTimer_ = 0
local seasonRefreshTimer_ = 0
local dragonRefreshTimer_ = 0
local achieveCountLabel_ = nil
local lastAchCountText_ = ""

-- ============================================================================
-- 幸运金币效果定义（对齐 Cookie Clicker）
-- ============================================================================

local luckyEffects = {
    {
        id = "frenzy",
        name = "金币狂热",
        icon = "🔥",
        color = { 255, 140, 0, 255 },
        weight = 50,    -- 最常见
        apply = function()
            return {
                id = "frenzy",
                name = "金币狂热",
                icon = "🔥",
                color = { 255, 140, 0, 255 },
                remaining = 77,
                duration = 77,
                multiplierKey = "cps",
                multiplierVal = 7,
            }
        end,
    },
    {
        id = "lucky",
        name = "幸运一击",
        icon = "🍀",
        color = { 50, 205, 50, 255 },
        weight = 30,    -- 常见
        apply = function()
            local S = GameState
            -- Cookie Clicker 公式: min(CpS×900, 银行×0.15) + 13
            local amount = math.min(S.coinsPerSecond * 900, S.coins * 0.15) + 13
            amount = math.max(amount, 13)
            S.coins = S.coins + amount
            print("[Lucky Coin] 幸运一击! +" .. S.FormatNumber(amount))
            return nil
        end,
    },
    {
        id = "clickFrenzy",
        name = "点击狂潮",
        icon = "⚡",
        color = { 255, 215, 0, 255 },
        weight = 10,    -- 稀有
        apply = function()
            return {
                id = "clickFrenzy",
                name = "点击狂潮",
                icon = "⚡",
                color = { 255, 215, 0, 255 },
                remaining = 13,
                duration = 13,
                multiplierKey = "cpc",
                multiplierVal = 777,
            }
        end,
    },
    {
        id = "coinStorm",
        name = "金币风暴",
        icon = "🌧️",
        color = { 100, 149, 237, 255 },
        weight = 3,     -- 极稀有
        apply = function()
            local S = GameState
            -- 类似 Cookie Storm 简化版：大量即时金币
            local amount = math.min(S.coinsPerSecond * 3600, S.coins * 0.25) + 13
            amount = math.max(amount, 13)
            S.coins = S.coins + amount
            print("[Lucky Coin] 金币风暴! +" .. S.FormatNumber(amount))
            return nil
        end,
    },
    {
        id = "buildingSpecial",
        name = "建筑加成",
        icon = "🏗️",
        color = { 147, 112, 219, 255 },
        weight = 0,     -- 条件加入，不使用固定权重
        apply = function()
            -- 找到拥有最多的建筑类型
            local maxCount = 0
            local maxIndex = 1
            for i, b in ipairs(Buildings.buildings) do
                if b.count > maxCount then
                    maxCount = b.count
                    maxIndex = i
                end
            end
            local b = Buildings.buildings[maxIndex]
            return {
                id = "buildingSpecial",
                name = "建筑加成: " .. b.name,
                icon = b.icon,
                color = { 147, 112, 219, 255 },
                remaining = 30,
                duration = 30,
                buildingIndex = maxIndex,
                -- 不使用 multiplierKey，在 Update 循环中单独处理
            }
        end,
    },
}

-- ============================================================================
-- 初始化
-- ============================================================================

--- 建筑效率升级数据（所有模块共享）
GM.buildingUpgrades = nil

--- 初始化游戏管理器
function GM.Init()
    -- 生成建筑效率升级数据
    GM.buildingUpgrades = BuildingUpgrades.Generate(Buildings.buildings)

    -- 初始化成就系统
    AchievementManager.Init()
    AchievementManager.SetOnUnlock(function(achievement)
        if achievementNotify_ then
            achievementNotify_.Enqueue(achievement)
        end
        -- 成就解锁后重新计算产出（Kitten 倍率可能变化）
        GM.RecalcProduction()
        GM.RefreshAllUI()
    end)

    -- 初始化奶奶末日系统
    GrandmapoManager.Init()
    WrinklerManager.Init()

    GrandmapoManager.SetOnPhaseChange(function(newPhase)
        GM.RecalcProduction()
    end)

    -- 初始化糖块系统
    SugarLumpManager.Init()
    SugarLumpManager.SetOnHarvest(function(amount, lumpType)
        if floatingText_ then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 80
            floatingText_.Show("经验 +" .. amount, cx, cy, lumpType.color or { 255, 200, 230, 255 })
        end
        GM.RecalcProduction()
    end)
    SugarLumpManager.SetOnUnlock(function()
        print("[GameManager] 糖块系统已解锁！")
        if sugarLumpDisplay_ and uiRoot_ then
            sugarLumpDisplay_.Show(uiRoot_)
            sugarLumpDisplay_.Refresh()
        end
    end)

    -- 初始化飞升系统
    AscensionManager.Init()
    AscensionManager.SetOnAscend(function(newPrestige, gainedChips)
        print("[GameManager] 飞升完成! 声望:" .. newPrestige .. " 芯片+" .. gainedChips)
        -- 飞升后重置附属系统
        GrandmapoManager.Init()
        WrinklerManager.Init()
        -- 重新生成建筑升级数据（建筑已重置）
        GM.buildingUpgrades = BuildingUpgrades.Generate(Buildings.buildings)
        -- 同步更新 SaveBridge 的引用（飞升后 buildingUpgrades 已重新生成）
        SaveBridge.SetBuildingUpgrades(GM.buildingUpgrades)
        GM.RecalcProduction()
        GM.RefreshAllUI()
    end)
    AscensionManager.SetOnBuyUpgrade(function(upgrade)
        GM.RecalcProduction()
        GM.RefreshAllUI()
    end)

    -- 初始化季节系统
    SeasonManager.Init()
    SeasonManager.SetOnSeasonChange(function(newSeason)
        GM.RecalcProduction()
        GM.RefreshAllUI()
        if seasonPanel_ and seasonPanel_.IsVisible() then
            seasonPanel_.Refresh()
        end
    end)
    SeasonManager.SetOnCollect(function(item)
        GM.RecalcProduction()
        if floatingText_ then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 60
            floatingText_.Show("收获 " .. item.name, cx, cy, { 255, 220, 100, 255 }, item.icon)
        end
    end)
    SeasonManager.SetOnSantaLevelUp(function(newLevel, unlockedUpgrade)
        GM.RecalcProduction()
        if floatingText_ and unlockedUpgrade then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 60
            floatingText_.Show("解锁 " .. unlockedUpgrade.name, cx, cy, { 255, 180, 100, 255 }, unlockedUpgrade.icon)
        end
    end)
    SeasonManager.SetOnReindeerSpawn(function(x, y)
        if reindeerDisplay_ then
            reindeerDisplay_.Show(x, y)
        end
    end)
    SeasonManager.SetOnReindeerClick(function(reward, droppedCookie)
        if reindeerDisplay_ then
            reindeerDisplay_.Hide()
        end
        if floatingText_ then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 40
            floatingText_.Show("+" .. GameState.FormatNumber(reward), cx, cy, { 139, 200, 80, 255 }, "image/icon_reindeer.png")
        end
    end)
    SeasonManager.SetOnReindeerExpire(function()
        if reindeerDisplay_ then
            reindeerDisplay_.Hide()
        end
    end)

    -- 初始化龙系统
    DragonManager.Init()
    DragonManager.SetOnLevelUp(function(newLevel, auraUnlocked)
        GM.RecalcProduction()
        GM.RefreshAllUI()
        if floatingText_ then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 60
            local text = "龙 Lv." .. newLevel
            if auraUnlocked then
                text = text .. " " .. auraUnlocked.name
            end
            floatingText_.Show(text, cx, cy, { 240, 200, 80, 255 })
        end
    end)
    DragonManager.SetOnEquipAura(function(slot, auraId)
        GM.RecalcProduction()
        GM.RefreshAllUI()
    end)
    DragonManager.SetOnDrop(function(dropItem)
        GM.RecalcProduction()
        if floatingText_ then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 40
            floatingText_.Show(dropItem.name .. "!", cx, cy, { 220, 180, 80, 255 })
        end
    end)

    -- 皱巴虫弹出时尝试万圣节/复活节掉落
    WrinklerManager.SetOnPop(function(wrinkler, reward)
        if floatingText_ then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 30
            floatingText_.Show("+" .. GameState.FormatNumber(reward), cx, cy, { 100, 255, 100, 255 }, "image/金币.png")
        end
        -- 季节掉落
        SeasonManager.TryHalloweenDrop()
        SeasonManager.TryEasterDrop("wrinkler")
    end)

    -- 首次幸运金币出现快一些
    GameState.luckyTimer = 10 + math.random() * 20

    -- 初始化技能系统
    SkillManager.Init(function(x, y, skipRateLimit)
        -- 技能触发的点击（跳过频率限制）
        -- 注意：不播放单次动画（粒子/浮动文字/图标缩放），
        -- 否则高频自动点击会耗尽对象池，导致玩家手动点击的动画被立即覆盖
        if skipRateLimit then
            local S = GameState
            S.totalClicks = S.totalClicks + 1
            local gain = S.coinsPerClick * S.buffCpcMul
            S.coins = S.coins + gain
            S.handmadeCoins = S.handmadeCoins + gain
        else
            GM.OnCoinClick(x, y)
        end
    end)
end

--- 注入 UI 模块引用
---@param root table UI 根节点
---@param statsBar table StatsBar 模块
---@param coinArea table CoinArea 模块
---@param shopPanel table ShopPanel 模块
---@param luckyCoin table LuckyCoin 模块
---@param floatingText table FloatingText 模块
---@param coinParticle table CoinParticle 模块
---@param achieveNotify table|nil AchievementNotify 模块
function GM.SetUI(root, statsBar, coinArea, shopPanel, luckyCoin, floatingText, coinParticle, achieveNotify, wrinklerDisp, researchPnl, sugarDisp, bldLevelPnl, hvnShop, ascPnl, ssnPnl, reindeerDisp, drgnPnl, achPnl)
    uiRoot_ = root
    statsBar_ = statsBar
    coinArea_ = coinArea
    shopPanel_ = shopPanel
    luckyCoin_ = luckyCoin
    floatingText_ = floatingText
    coinParticle_ = coinParticle
    achievementNotify_ = achieveNotify
    wrinklerDisplay_ = wrinklerDisp
    researchPanel_ = researchPnl
    sugarLumpDisplay_ = sugarDisp
    buildingLevelPanel_ = bldLevelPnl
    heavenlyShop_ = hvnShop
    ascensionPanel_ = ascPnl
    seasonPanel_ = ssnPnl
    reindeerDisplay_ = reindeerDisp
    dragonPanel_ = drgnPnl
    achievementPanel_ = achPnl

    -- 缓存高频访问的 UI 引用（避免每帧 FindById）
    achieveCountLabel_ = root and root:FindById("achieveCountLabel") or nil
end

-- ============================================================================
-- 产出计算
-- ============================================================================

--- 重新计算每秒/每次点击产出
function GM.RecalcProduction()
    local S = GameState
    S.coinsPerSecond = 0
    S.cpsPercent = 0
    S.fingerBonus = 0
    S.luckyFreqMul = 1
    S.luckyStayMul = 1
    S.luckyDurMul = 1

    -- 建筑产出（含效率升级倍率 + 奶奶研究倍率）
    for bi, b in ipairs(Buildings.buildings) do
        local mul = 1
        if GM.buildingUpgrades and GM.buildingUpgrades[bi] then
            mul = BuildingUpgrades.GetMultiplier(GM.buildingUpgrades[bi])
        end
        -- 奶奶额外效率倍率（Ritual Rolling Pins 等研究）
        if b.id == "grandma" then
            mul = mul * GrandmapoManager.GetGrandmaMultiplier()
        end
        -- 糖块建筑等级加成（每级 +1%）
        mul = mul * SugarLumpManager.GetBuildingLevelMultiplier(bi)
        S.coinsPerSecond = S.coinsPerSecond + b.cpsAdd * b.count * mul
    end

    -- 奶奶协同加成 CpS（One Mind / Communal Brainsweep / Elder Pact）
    S.coinsPerSecond = S.coinsPerSecond + GrandmapoManager.GetGrandmaSynergyCps()
    S.coinsPerSecond = S.coinsPerSecond + GrandmapoManager.GetPortalSynergyCps()

    -- 计算非光标建筑总数（手指升级线用）
    local nonCursorCount = 0
    for _, b in ipairs(Buildings.buildings) do
        if b.id ~= "cursor" then
            nonCursorCount = nonCursorCount + b.count
        end
    end

    -- 点击升级（三条线）
    local bestFingerMul = 0
    local fingerBase = 0.1
    for _, u in ipairs(Upgrades.clickUpgrades) do
        if u.count > 0 then
            if u.category == "mouse" then
                -- 鼠标升级线: 累加 CpS 百分比
                S.cpsPercent = S.cpsPercent + u.cpsPercentAdd
            elseif u.category == "finger" then
                -- 手指升级线: 取最高倍率（后续替换前级）
                if u.fingerMul > bestFingerMul then
                    bestFingerMul = u.fingerMul
                    fingerBase = u.fingerBase
                end
            elseif u.category == "lucky" then
                -- 幸运升级线
                if u.luckyFreqMul then
                    S.luckyFreqMul = S.luckyFreqMul * u.luckyFreqMul
                end
                if u.luckyStayMul then
                    S.luckyStayMul = S.luckyStayMul * u.luckyStayMul
                end
                if u.luckyDurMul then
                    S.luckyDurMul = S.luckyDurMul * u.luckyDurMul
                end
            end
        end
    end

    -- 手指加成 = fingerBase * bestFingerMul * 非光标建筑数
    if bestFingerMul > 0 then
        S.fingerBonus = fingerBase * bestFingerMul * nonCursorCount
    end

    -- 光标建筑效率升级同时翻倍点击力量
    local cursorMul = 1
    if GM.buildingUpgrades and GM.buildingUpgrades[1] then
        cursorMul = BuildingUpgrades.GetMultiplier(GM.buildingUpgrades[1])
    end

    -- 研究产量加成（Grandmapocalypse）
    S.coinsPerSecond = S.coinsPerSecond * GrandmapoManager.GetProductionMultiplier()

    -- Sugar Baking 加成（每个未使用糖块 +1% CpS，上限 100 块）
    S.coinsPerSecond = S.coinsPerSecond * SugarLumpManager.GetSugarBakingMultiplier()

    -- 飞升声望加成（每声望等级 +1% CpS，受解锁链限制）
    S.coinsPerSecond = S.coinsPerSecond * AscensionManager.GetPrestigeMultiplier()

    -- 天堂升级产量加成（Heavenly Cookies 等）
    S.coinsPerSecond = S.coinsPerSecond * AscensionManager.GetProductionMultiplier()

    -- 天堂升级幸运加成
    S.luckyFreqMul = S.luckyFreqMul * AscensionManager.GetLuckyFreqMul()
    S.luckyDurMul = S.luckyDurMul * AscensionManager.GetLuckyDurMul()

    -- 季节收集加成（所有收集品 CpS 百分比加成 + 圣诞升级加成）
    local seasonCpsMul = 1 + SeasonManager.GetCollectionCpsMul() + SeasonManager.GetXmasUpgradeCpsMul()
    S.coinsPerSecond = S.coinsPerSecond * seasonCpsMul

    -- 季节固定 CpS 加成（"egg" 蛋 = +9 CpS）
    S.coinsPerSecond = S.coinsPerSecond + SeasonManager.GetFixedCpsBonus()

    -- 季节幸运频率加成（Golden goose egg 等）
    S.luckyFreqMul = S.luckyFreqMul * SeasonManager.GetLuckyFreqMul()

    -- 龙光环：产量总倍率（Radiant Appetite: ×2）
    S.coinsPerSecond = S.coinsPerSecond * DragonManager.GetProductionMul()

    -- 龙光环：CpS 百分比加成（Dragon's Fortune / Dragon Cookie + 掉落物）
    local dragonCpsMul = DragonManager.GetCpsMul()
    if dragonCpsMul > 0 then
        S.coinsPerSecond = S.coinsPerSecond * (1 + dragonCpsMul)
    end

    -- 龙光环：声望加成（Dragon God: +5%）
    local dragonPrestige = DragonManager.GetPrestigeBonus()
    if dragonPrestige > 0 then
        S.coinsPerSecond = S.coinsPerSecond * (1 + dragonPrestige)
    end

    -- 龙光环：奶奶协同（Elder Battalion）
    local grandmaSynergyMul = DragonManager.GetGrandmaSynergyMul()
    if grandmaSynergyMul > 1 then
        -- 仅影响奶奶部分产出（简化：作为全局乘法，因奶奶占比难分离）
        -- 实际 Cookie Clicker 中此光环仅影响奶奶，这里简化处理
        local grandma = Buildings.buildings[2]
        if grandma and grandma.count > 0 then
            local grandmaCps = grandma.cpsAdd * grandma.count
            local extraCps = grandmaCps * (grandmaSynergyMul - 1)
            S.coinsPerSecond = S.coinsPerSecond + extraCps
        end
    end

    -- 龙光环：幸运频率/持续加成
    S.luckyFreqMul = S.luckyFreqMul * DragonManager.GetLuckyFreqMul()
    S.luckyDurMul = S.luckyDurMul * DragonManager.GetLuckyDurMul()

    -- 应用 Kitten 倍率（成就牛奶系统 + 天堂升级 Kitten 加成 + 季节 Kitten 加成 + 龙光环）
    local kittenMul = AchievementManager.GetKittenMultiplier()
    local kittenBonus = AscensionManager.GetKittenBonus() + SeasonManager.GetKittenBonus() + DragonManager.GetKittenBonus()
    kittenMul = kittenMul + kittenBonus
    S.coinsPerSecond = S.coinsPerSecond * kittenMul

    -- 最终点击产出 = (基础值 * 光标倍率) + CpS百分比加成 + 手指加成 + 天堂/季节/龙点击加成
    local clickBonus = AscensionManager.GetClickBonus() + SeasonManager.GetClickBonus() + DragonManager.GetClickBonus()
    S.coinsPerClick = S.clickBase * cursorMul + S.cpsPercent * S.coinsPerSecond + S.fingerBonus
    S.coinsPerClick = S.coinsPerClick * (1 + clickBonus)
end

-- ============================================================================
-- 玩家操作
-- ============================================================================

--- 点击金币
---@param x number 点击位置逻辑坐标 X
---@param y number 点击位置逻辑坐标 Y
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

    -- 体力恢复（概率触发，随机 1~10，综合约 500 次点击恢复一次技能）
    if S.stamina < S.staminaMax then
        if math.random() < S.staminaClickChance then
            local amount = math.random(1, 10)
            S.stamina = math.min(S.staminaMax, S.stamina + amount)
            if floatingText_ then
                floatingText_.Show("+" .. amount .. "体力", x, y - 30, { 120, 220, 80, 255 })
            end
        end
    end

    -- 点击音效 + 金币放缩动画
    AudioManager.PlaySFX("click")
    if coinArea_ then
        coinArea_.PlayClickAnim()
    end

    -- 在点击位置生成金币粒子
    if coinParticle_ and x and y then
        coinParticle_.Spawn(x, y)
    end

    -- 在点击位置显示浮动文本
    if floatingText_ and x and y then
        local color = S.buffCpcMul > 1
            and { 255, 215, 0, 255 }   -- buff 激活时金色
            or  { 255, 255, 255, 255 }  -- 正常白色
        floatingText_.Show("+" .. S.FormatNumber(gain), x, y, color)
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
    if not amount and shopPanel_ and shopPanel_.GetBuyAmount then
        buyAmt = shopPanel_.GetBuyAmount()
    end

    -- 计算批量费用（含季节/buff 费用折扣）
    local costMul = (1 - SeasonManager.GetCostReduction()) * GameState.buffBuildingCostMul
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

    -- 金币不够
    if GameState.coins < upgrade.cost then return end

    GameState.coins = GameState.coins - upgrade.cost
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

    local cost = GameState.GetCost(upgrade)
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

-- ============================================================================
-- 一键购买
-- ============================================================================

--- 一键购买所有买得起的升级（建筑效率升级 + 点击升级，不含建筑本身）
function GM.OnBuyAll()
    local bought = 0

    -- 1) 购买所有买得起的建筑效率升级
    if GM.buildingUpgrades then
        for bi, bUpgrades in ipairs(GM.buildingUpgrades) do
            local building = Buildings.buildings[bi]
            if building then
                for ti, upgrade in ipairs(bUpgrades) do
                    if not upgrade.bought and building.count >= upgrade.needCount
                       and GameState.coins >= upgrade.cost then
                        GameState.coins = GameState.coins - upgrade.cost
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
                local cost = GameState.GetCost(upgrade)
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

--- 一键购买所有建筑（每种建筑买最大可购买量，考虑折扣）
function GM.OnBuyAllBuildings()
    local costMul = (1 - SeasonManager.GetCostReduction()) * GameState.buffBuildingCostMul
    local totalBought = 0

    for i, building in ipairs(Buildings.buildings) do
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

-- ============================================================================
-- 幸运金币逻辑
-- ============================================================================

--- 按权重随机选择一个效果（动态池：Building Special / Business Day 条件加入）
local function PickLuckyEffect()
    local pool = {}
    local totalWeight = 0
    for _, e in ipairs(luckyEffects) do
        local w = e.weight
        -- Building Special: 总建筑数 >= 10 时，25% 概率加入池，权重 15
        if e.id == "buildingSpecial" then
            w = 0
            local totalCount = 0
            for _, b in ipairs(Buildings.buildings) do
                totalCount = totalCount + b.count
            end
            if totalCount >= 10 and math.random() < 0.25 then
                w = 15
            end
        end
        if w > 0 then
            pool[#pool + 1] = { effect = e, weight = w }
            totalWeight = totalWeight + w
        end
    end

    -- 商业日（清仓促销）季节时，加入清仓大促效果
    local bizEffect = SeasonManager.GetBusinessDayEffect()
    if bizEffect then
        local bizEntry = {
            effect = {
                id = bizEffect.id,
                name = bizEffect.name,
                icon = "📋",
                color = { 100, 200, 150, 255 },
                weight = bizEffect.weight,
                apply = function()
                    return {
                        id = bizEffect.id,
                        name = bizEffect.name,
                        icon = "📋",
                        color = { 100, 200, 150, 255 },
                        remaining = bizEffect.duration,
                        duration = bizEffect.duration,
                        multiplierKey = "buildingCost",
                        multiplierVal = bizEffect.buildingCostMul,
                    }
                end,
            },
            weight = bizEffect.weight,
        }
        pool[#pool + 1] = bizEntry
        totalWeight = totalWeight + bizEffect.weight
    end

    -- 从池中按权重抽取
    local roll = math.random() * totalWeight
    local cumulative = 0
    for _, entry in ipairs(pool) do
        cumulative = cumulative + entry.weight
        if roll <= cumulative then
            return entry.effect
        end
    end
    return pool[1].effect
end

--- 生成幸运金币
local function SpawnLuckyCoin()
    local S = GameState
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr

    local margin = S.luckySize
    local shopWidth = 260
    local topBar = 50
    S.luckyPosX = margin + math.random() * math.max(1, screenW - shopWidth - margin * 2 - S.luckySize)
    S.luckyPosY = topBar + margin + math.random() * math.max(1, screenH - topBar - margin * 2 - S.luckySize)

    S.luckyActive = true
    S.luckyLifetime = S.luckyMaxLife * S.luckyStayMul
    S.luckyFloatPhase = 0

    -- 奶奶末日：判断是否为愤怒金币
    local isWrath, _ = GrandmapoManager.RollWrathCoin()
    luckyIsWrath_ = isWrath

    if luckyCoin_ then
        luckyCoin_.Show(S.luckyPosX, S.luckyPosY)
        luckyCoin_.SetWrath(isWrath)
    end

    local coinType = isWrath and "愤怒金币" or "幸运金币"
    print("[Lucky Coin] " .. coinType .. "出现! pos=(" .. math.floor(S.luckyPosX) .. "," .. math.floor(S.luckyPosY) .. ")")
end

--- 隐藏幸运金币
local function HideLuckyCoin()
    GameState.luckyActive = false
    if luckyCoin_ then
        luckyCoin_.Hide()
    end
end

-- 草根人脉收获时触发黄金商机（需在 SpawnLuckyCoin 定义之后注册）
SugarLumpManager.SetOnTriggerLucky(function()
    print("[GameManager] 草根人脉触发黄金商机！")
    SpawnLuckyCoin()
end)

--- 获取建筑专属 buff 倍率（buildingSpecial）
--- @param bi number 建筑索引
--- @return number 该建筑的额外 buff 倍率
local function GetBuildingBuffMul(bi)
    local mul = 1
    for _, b in ipairs(GameState.activeBuffs) do
        if b.id == "buildingSpecial" and b.buildingIndex == bi then
            mul = mul * 10 -- x10 该建筑产出
        end
    end
    return mul
end

--- 重新计算 buff 倍率
local function RecalcBuffMultipliers()
    local S = GameState
    S.buffCpsMul = 1
    S.buffCpcMul = 1
    S.buffBuildingCostMul = 1
    for _, b in ipairs(S.activeBuffs) do
        if b.multiplierKey == "cps" then
            S.buffCpsMul = S.buffCpsMul * b.multiplierVal
        elseif b.multiplierKey == "cpc" then
            S.buffCpcMul = S.buffCpcMul * b.multiplierVal
        elseif b.multiplierKey == "buildingCost" then
            S.buffBuildingCostMul = S.buffBuildingCostMul * b.multiplierVal
        end
    end
    -- CPS翻倍技能叠加
    S.buffCpsMul = S.buffCpsMul * SkillManager.GetCpsMultiplier()
end

--- 应用愤怒金币效果
---@param effect table 从 GrandmapocalypseDefs.wrathEffects 中抽取的效果
---@return table|nil buff 如果是持续 buff 则返回
local function ApplyWrathEffect(effect)
    local S = GameState
    if effect.id == "lucky" then
        -- 同正常幸运一击
        local amount = math.min(S.coinsPerSecond * 900, S.coins * 0.15) + 13
        amount = math.max(amount, 13)
        S.coins = S.coins + amount
        print("[Wrath] 幸运一击! +" .. S.FormatNumber(amount))
        return nil
    elseif effect.id == "ruin" then
        -- 失去金币
        local loss = math.min(S.coinsPerSecond * 900, S.coins * 0.05) + 13
        loss = math.min(loss, S.coins)
        S.coins = S.coins - loss
        print("[Wrath] 毁灭! -" .. S.FormatNumber(loss))
        return nil
    elseif effect.type == "buff" then
        -- 持续 buff（clot / elderFrenzy / clickFrenzyWrath）
        print("[Wrath] Buff: " .. effect.name .. " (x" .. effect.multiplierVal .. " " .. effect.duration .. "s)")
        return {
            id = effect.id,
            name = effect.name,
            icon = effect.icon,
            color = effect.color,
            remaining = effect.duration,
            duration = effect.duration,
            multiplierKey = effect.multiplierKey,
            multiplierVal = effect.multiplierVal,
        }
    end
    return nil
end

--- 触发幸运金币效果（由 LuckyCoin UI 的点击回调调用）
function GM.TriggerLuckyEffect()
    local S = GameState
    S.luckyClicks = S.luckyClicks + 1

    local effect, buff
    if luckyIsWrath_ then
        -- 愤怒金币：从愤怒效果池抽取
        local wrathEffect = GrandmapoManager.PickWrathEffect()
        effect = wrathEffect
        buff = ApplyWrathEffect(wrathEffect)
        print("[Wrath Coin] 触发: " .. effect.name .. " (累计点击: " .. S.luckyClicks .. ")")
    else
        effect = PickLuckyEffect()
        buff = effect.apply()
        print("[Lucky Coin] 触发: " .. effect.name .. " (累计点击: " .. S.luckyClicks .. ")")
    end
    if buff then
        -- 应用效果持续时间倍率（Get Lucky）
        if S.luckyDurMul > 1 then
            buff.remaining = buff.remaining * S.luckyDurMul
            buff.duration = buff.duration * S.luckyDurMul
        end

        -- 同 id buff 叠加：累加剩余时间（CC v2.002+ 行为）
        local stacked = false
        for _, existing in ipairs(S.activeBuffs) do
            if existing.id == buff.id then
                existing.remaining = existing.remaining + buff.remaining
                existing.duration = math.max(existing.duration, buff.duration)
                stacked = true
                print("[Lucky Coin] Buff 叠加: " .. buff.name .. " (剩余 " .. string.format("%.1f", existing.remaining) .. "s)")
                break
            end
        end
        if not stacked then
            S.activeBuffs[#S.activeBuffs + 1] = buff
        end
    end

    -- buff 效果：立即刷新底部进度条
    if buff and statsBar_ then
        statsBar_.RefreshBuffBar()
    end

    -- 即时/一次性效果 或 buff 触发：都在点击位置显示浮动提示
    if floatingText_ then
        floatingText_.Show(effect.name .. "!",
            S.luckyPosX + S.luckySize * 0.5,
            S.luckyPosY, effect.color or { 255, 215, 0, 255 }, effect.iconImage)
    end

    -- 龙光环特殊效果：Dragon Harvest / Dragonflight
    if not luckyIsWrath_ then
        if DragonManager.HasDragonHarvest() and math.random() < 0.05 then
            -- Dragon Harvest: CpS × 15 持续 60s
            local dhBuff = {
                id = "dragonHarvest",
                name = "Dragon Harvest",
                icon = "丰",
                color = { 180, 220, 80, 255 },
                remaining = DD.DRAGON_HARVEST_DUR,
                duration = DD.DRAGON_HARVEST_DUR,
                multiplierKey = "cps",
                multiplierVal = DD.DRAGON_HARVEST_MUL,
            }
            -- 叠加
            local stacked = false
            for _, existing in ipairs(S.activeBuffs) do
                if existing.id == "dragonHarvest" then
                    existing.remaining = existing.remaining + dhBuff.remaining
                    stacked = true
                    break
                end
            end
            if not stacked then
                S.activeBuffs[#S.activeBuffs + 1] = dhBuff
            end
            if floatingText_ then
                floatingText_.Show("丰收 Dragon Harvest!", S.luckyPosX, S.luckyPosY - 30, { 180, 220, 80, 255 })
            end
        end
        if DragonManager.HasDragonflight() and math.random() < 0.05 then
            -- Dragonflight: 点击 × 1111 持续 10s
            local dfBuff = {
                id = "dragonflight",
                name = "Dragonflight",
                icon = "龙",
                color = { 255, 180, 60, 255 },
                remaining = DD.DRAGONFLIGHT_DUR,
                duration = DD.DRAGONFLIGHT_DUR,
                multiplierKey = "cpc",
                multiplierVal = DD.DRAGONFLIGHT_MUL,
            }
            local stacked = false
            for _, existing in ipairs(S.activeBuffs) do
                if existing.id == "dragonflight" then
                    existing.remaining = existing.remaining + dfBuff.remaining
                    stacked = true
                    break
                end
            end
            if not stacked then
                S.activeBuffs[#S.activeBuffs + 1] = dfBuff
            end
            if floatingText_ then
                floatingText_.Show("龙 Dragonflight!", S.luckyPosX, S.luckyPosY - 30, { 255, 180, 60, 255 })
            end
        end
    end

    -- 复活节蛋掉落尝试（点击幸运/愤怒金币时）
    SeasonManager.TryEasterDrop("lucky")

    HideLuckyCoin()
    local baseInterval = S.luckyMinInterval + math.random() * (S.luckyMaxInterval - S.luckyMinInterval)
    S.luckyTimer = baseInterval / S.luckyFreqMul

    SlotSaveSystem.MarkDirty()
end

-- ============================================================================
-- UI 刷新
-- ============================================================================

--- 刷新所有 UI
function GM.RefreshAllUI()
    if coinArea_ then
        coinArea_.RefreshStats()
        coinArea_.RefreshFormula()
    end
    if shopPanel_ then
        shopPanel_.Refresh()
    end
    if achievementPanel_ and achievementPanel_.IsVisible() then
        achievementPanel_.Refresh()
    end
    -- 状态变化后刷新 Tooltip，显示最新数据
    local Tooltip = require("ui.Tooltip")
    Tooltip.Refresh()
end

-- ============================================================================
-- 帧更新
-- ============================================================================

--- 每帧更新（由 main.lua 的 HandleUpdate 调用）
---@param dt number 帧间隔时间
function GM.Update(dt)
    local S = GameState

    -- ========== Buff 倒计时 ==========
    local buffsChanged = false
    for i = #S.activeBuffs, 1, -1 do
        S.activeBuffs[i].remaining = S.activeBuffs[i].remaining - dt
        if S.activeBuffs[i].remaining <= 0 then
            print("[Lucky Coin] Buff 结束: " .. S.activeBuffs[i].name)
            table.remove(S.activeBuffs, i)
            buffsChanged = true
        end
    end
    RecalcBuffMultipliers()

    -- 刷新 buff 栏
    S.buffRefreshCooldown = S.buffRefreshCooldown - dt
    if statsBar_ and (buffsChanged or (S.buffRefreshCooldown <= 0 and #S.activeBuffs > 0)) then
        S.buffRefreshCooldown = 0.5
        statsBar_.RefreshBuffBar()
    end

    -- ========== 幸运金币计时 ==========
    if not S.luckyActive then
        S.luckyTimer = S.luckyTimer - dt
        if S.luckyTimer <= 0 then
            SpawnLuckyCoin()
        end
    else
        S.luckyLifetime = S.luckyLifetime - dt
        if S.luckyLifetime <= 0 then
            print("[Lucky Coin] 幸运金币消失（未被点击）")
            HideLuckyCoin()
            local baseInterval = S.luckyMinInterval + math.random() * (S.luckyMaxInterval - S.luckyMinInterval)
            S.luckyTimer = baseInterval / S.luckyFreqMul
        elseif luckyCoin_ then
            luckyCoin_.UpdateAnimation(dt)
        end
    end

    -- ========== 自动产出（逐建筑累加，追踪 totalProduced） ==========
    -- 光标（建筑索引 1）：每 10 秒批量结算一次，其余建筑逐帧累加
    for bi, b in ipairs(Buildings.buildings) do
        if b.count > 0 and bi ~= 1 then
            local mul = 1
            if GM.buildingUpgrades and GM.buildingUpgrades[bi] then
                mul = BuildingUpgrades.GetMultiplier(GM.buildingUpgrades[bi])
            end
            local bMul = GetBuildingBuffMul(bi)
            local produced = b.cpsAdd * b.count * mul * S.buffCpsMul * bMul * dt
            S.coins = S.coins + produced
            b.totalProduced = b.totalProduced + produced
        end
    end

    -- 光标每 10 秒自动点击一次（结算 10 秒累计产出）
    local cursor = Buildings.buildings[1]
    if cursor and cursor.count > 0 then
        S.cursorTimer = (S.cursorTimer or 0) + dt
        if S.cursorTimer >= 10 then
            S.cursorTimer = S.cursorTimer - 10
            local mul = 1
            if GM.buildingUpgrades and GM.buildingUpgrades[1] then
                mul = BuildingUpgrades.GetMultiplier(GM.buildingUpgrades[1])
            end
            local bMul = GetBuildingBuffMul(1)
            local produced = cursor.cpsAdd * cursor.count * mul * S.buffCpsMul * bMul * 10
            S.coins = S.coins + produced
            cursor.totalProduced = cursor.totalProduced + produced
        end
    end

    -- ========== 奶奶末日 + 皱巴虫更新 ==========
    GrandmapoManager.Update(dt)

    local spawnRate = GrandmapoManager.GetWrinklerSpawnRate()
    local effectiveCps = S.coinsPerSecond * S.buffCpsMul
    local drained = WrinklerManager.Update(dt, spawnRate, effectiveCps)
    if drained > 0 then
        S.coins = math.max(0, S.coins - drained)
    end

    -- 皱巴虫显示更新
    if wrinklerDisplay_ then
        wrinklerDisplay_.Update(dt)
    end

    -- ========== 糖块系统更新 ==========
    SugarLumpManager.Update(dt)

    sugarLumpRefreshTimer_ = sugarLumpRefreshTimer_ - dt
    if sugarLumpRefreshTimer_ <= 0 then
        sugarLumpRefreshTimer_ = 1.0
        if sugarLumpDisplay_ and sugarLumpDisplay_.IsVisible() then
            sugarLumpDisplay_.Refresh()
        end
        if buildingLevelPanel_ and buildingLevelPanel_.IsVisible() then
            buildingLevelPanel_.Refresh()
        end
    end

    -- 奶奶末日状态 + 研究面板定期刷新（每 0.5 秒）
    grandmapoRefreshTimer_ = grandmapoRefreshTimer_ - dt
    if grandmapoRefreshTimer_ <= 0 then
        grandmapoRefreshTimer_ = 0.5
        if wrinklerDisplay_ then
            wrinklerDisplay_.RefreshStatus(
                GrandmapoManager.GetPhase(),
                WrinklerManager.GetCount(),
                WrinklerManager.GetTotalAbsorbed()
            )
        end
        if researchPanel_ and researchPanel_.IsVisible() then
            researchPanel_.Refresh()
        end
    end

    -- ========== 飞升烘焙追踪 ==========
    -- 追踪本帧所有建筑产出（用于声望计算）
    local frameCps = S.coinsPerSecond * S.buffCpsMul
    if frameCps > 0 then
        AscensionManager.TrackProduction(frameCps * dt)
    end

    -- 飞升面板定期刷新
    ascensionRefreshTimer_ = ascensionRefreshTimer_ - dt
    if ascensionRefreshTimer_ <= 0 then
        ascensionRefreshTimer_ = 1.0
        if ascensionPanel_ and ascensionPanel_.IsVisible() then
            ascensionPanel_.Refresh()
        end
        if heavenlyShop_ and heavenlyShop_.IsVisible() then
            heavenlyShop_.Refresh()
        end
    end

    -- ========== 季节系统更新 ==========
    SeasonManager.Update(dt)

    -- 驯鹿动画更新
    if reindeerDisplay_ and SeasonManager.IsReindeerActive() then
        local rx, ry = SeasonManager.GetReindeerPos()
        local stay = SeasonManager.GetReindeerStayTimer()
        reindeerDisplay_.UpdateAnimation(dt, rx, ry, stay)
    end

    -- 季节面板定期刷新
    seasonRefreshTimer_ = seasonRefreshTimer_ - dt
    if seasonRefreshTimer_ <= 0 then
        seasonRefreshTimer_ = 1.0
        if seasonPanel_ and seasonPanel_.IsVisible() then
            seasonPanel_.Refresh()
        end
    end

    -- ========== 龙系统更新 ==========
    DragonManager.Update(dt)

    -- 龙面板定期刷新
    dragonRefreshTimer_ = dragonRefreshTimer_ - dt
    if dragonRefreshTimer_ <= 0 then
        dragonRefreshTimer_ = 1.0
        if dragonPanel_ and dragonPanel_.IsVisible() then
            dragonPanel_.Refresh()
        end
    end

    -- ========== 点击缩放动画 ==========
    if coinArea_ then
        coinArea_.Update(dt)
    end

    -- ========== 金币粒子更新 ==========
    if coinParticle_ then
        coinParticle_.Update(dt)
    end

    -- ========== 浮动文本更新 ==========
    if floatingText_ then
        floatingText_.Update(dt)
    end

    -- ========== 更新金币区域显示 ==========
    if coinArea_ then
        coinArea_.RefreshStats()
        coinArea_.RefreshFormula()
    end

    -- ========== 更新成就计数标签（增量） ==========
    if achieveCountLabel_ then
        local achText = AchievementManager.GetUnlockedCount() .. "/" .. AchievementManager.GetTotalCount()
        if achText ~= lastAchCountText_ then
            lastAchCountText_ = achText
            achieveCountLabel_:SetText(achText)
        end
    end

    -- ========== 技能系统更新 ==========
    SkillManager.Update(dt)

    -- 技能面板定期刷新
    skillRefreshTimer_ = skillRefreshTimer_ - dt
    if skillRefreshTimer_ <= 0 then
        skillRefreshTimer_ = 0.3
        if skillPanel_ and skillPanel_.IsVisible() then
            skillPanel_.Refresh()
        end
    end

    -- ========== 成就检查 ==========
    AchievementManager.Update(dt, GM.buildingUpgrades)

    -- ========== 成就通知更新 ==========
    if achievementNotify_ then
        achievementNotify_.Update(dt)
    end

    -- ========== 定期刷新商店（降频：0.3 秒一次） ==========
    shopRefreshTimer_ = (shopRefreshTimer_ or 0) - dt
    if shopRefreshTimer_ <= 0 then
        shopRefreshTimer_ = 0.3
        local currentFloor = math.floor(S.coins)
        if currentFloor ~= S.lastRefreshCoins then
            S.lastRefreshCoins = currentFloor
            if shopPanel_ then
                shopPanel_.Refresh()
            end
        end
    end
end

--- 购买 Kitten 升级（由 AchievementPanel 调用）
---@param index number
function GM.OnBuyKitten(index)
    if AchievementManager.BuyKitten(index) then
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        AudioManager.PlayBtnClick()
    end
end

--- 获取成就管理器引用（供 UI 模块使用）
---@return table AchievementManager
function GM.GetAchievementManager()
    return AchievementManager
end

--- 购买研究升级
---@param index number
function GM.OnBuyResearch(index)
    if GrandmapoManager.BuyResearch(index) then
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        AudioManager.PlayBtnClick()
    end
end

--- 购买 Elder Pledge
function GM.OnBuyPledge()
    if GrandmapoManager.BuyPledge() then
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        AudioManager.PlayBtnClick()
    end
end

--- 获取奶奶末日管理器引用
---@return table GrandmapoManager
function GM.GetGrandmapoManager()
    return GrandmapoManager
end

--- 获取皱巴虫管理器引用
---@return table WrinklerManager
function GM.GetWrinklerManager()
    return WrinklerManager
end

--- 获取糖块管理器引用
---@return table SugarLumpManager
function GM.GetSugarLumpManager()
    return SugarLumpManager
end

--- 收获糖块（由 UI 点击触发）
function GM.OnHarvestSugarLump()
    local success, amount, reason = SugarLumpManager.TryHarvest()
    if success then
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        AudioManager.PlayBtnClick()
    elseif reason == "碎裂" then
        -- 失败也要显示提示
        if floatingText_ then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 80
            floatingText_.Show("碎裂了!", cx, cy, { 255, 100, 100, 255 })
        end
    elseif reason == "尚未成熟" then
        if floatingText_ then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 80
            floatingText_.Show("还没成熟", cx, cy, { 180, 180, 200, 200 })
        end
    end
end

--- 升级建筑等级（由 BuildingLevelPanel 调用）
---@param buildingIndex number
function GM.OnUpgradeBuildingLevel(buildingIndex)
    if SugarLumpManager.UpgradeBuilding(buildingIndex) then
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        AudioManager.PlayBtnClick()
    end
end

-- ============================================================================
-- 飞升系统
-- ============================================================================

--- 获取飞升管理器引用
---@return table AscensionManager
function GM.GetAscensionManager()
    return AscensionManager
end

--- 购买天堂升级（由 HeavenlyShop 调用）
---@param upgradeId string
function GM.OnBuyHeavenlyUpgrade(upgradeId)
    if AscensionManager.BuyUpgrade(upgradeId) then
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        AudioManager.PlayBtnClick()
        if heavenlyShop_ and heavenlyShop_.IsVisible() then
            heavenlyShop_.Refresh()
        end
    end
end

--- 执行飞升（由 AscensionPanel 调用）
function GM.OnAscend()
    local gainedChips, newPrestige = AscensionManager.DoAscend()

    -- 关闭飞升面板
    if ascensionPanel_ and ascensionPanel_.IsVisible() then
        ascensionPanel_.Hide()
    end

    -- 显示浮动提示
    if floatingText_ then
        local dpr = graphics:GetDPR()
        local cx = (graphics:GetWidth() / dpr - 310) / 2
        local cy = graphics:GetHeight() / dpr / 2 - 50
        if gainedChips > 0 then
            floatingText_.Show("飞升! +" .. gainedChips .. " 经验值", cx, cy, { 200, 170, 255, 255 })
        end
    end

    -- 飞升是关键事件，立即保存
    SlotSaveSystem.SaveNow()
end

-- ============================================================================
-- 季节系统
-- ============================================================================

--- 获取季节管理器引用
---@return table SeasonManager
function GM.GetSeasonManager()
    return SeasonManager
end

--- 切换季节（由 SeasonPanel 调用）
---@param seasonId string
function GM.OnSwitchSeason(seasonId)
    local success, reason = SeasonManager.SwitchSeason(seasonId)
    if success then
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        AudioManager.PlayBtnClick()
    else
        -- 切换失败提示
        if floatingText_ and reason then
            local dpr = graphics:GetDPR()
            local cx = (graphics:GetWidth() / dpr - 310) / 2
            local cy = graphics:GetHeight() / dpr / 2 - 40
            local msg = "切换失败"
            if reason == "no_switcher" then
                msg = "需先购买「周期切换器」"
            elseif reason == "not_enough" then
                msg = "金币不足"
            end
            floatingText_.Show(msg, cx, cy, { 255, 100, 100, 255 })
        end
    end
end

--- 升级圣诞老人（由 SeasonPanel 调用）
function GM.OnUpgradeSanta()
    local success, unlocked = SeasonManager.UpgradeSanta()
    if success then
        GM.RecalcProduction()
        GM.RefreshAllUI()
        SlotSaveSystem.MarkDirty()
        AudioManager.PlayBtnClick()
    end
end

--- 点击驯鹿（由 ReindeerDisplay 调用）
function GM.OnClickReindeer()
    SeasonManager.ClickReindeer()
    AudioManager.PlayBtnClick()
end

-- ============================================================================
-- 龙系统
-- ============================================================================

--- 获取龙管理器引用
---@return table DragonManager
function GM.GetDragonManager()
    return DragonManager
end

--- 升级龙 / 购买龙蛋（由 DragonPanel 调用）
function GM.OnUpgradeDragon()
    local dm = DragonManager
    if dm.GetLevel() < 0 then
        dm.BuyEgg()
    else
        dm.Upgrade()
    end
    GM.RecalcProduction()
    GM.RefreshAllUI()
    SlotSaveSystem.MarkDirty()
    AudioManager.PlayBtnClick()
end

--- 装备龙光环（由 DragonPanel 调用）
---@param slot number 1 or 2
---@param auraId string|nil
function GM.OnEquipDragonAura(slot, auraId)
    DragonManager.EquipAura(slot, auraId)
    SlotSaveSystem.MarkDirty()
    AudioManager.PlayBtnClick()
end

--- 抚摸龙（由 DragonPanel 调用）
function GM.OnPetDragon()
    DragonManager.PetDragon()
    AudioManager.PlayBtnClick()
end

-- ============================================================================
-- 技能系统
-- ============================================================================

--- 获取技能管理器引用
---@return table SkillManager
function GM.GetSkillManager()
    return SkillManager
end

--- 注入技能面板引用
---@param panel table SkillPanel 模块
function GM.SetSkillPanel(panel)
    skillPanel_ = panel
end

--- 激活技能（看广告后释放）
---@param skillId string
function GM.OnActivateSkill(skillId)
    SkillManager.ActivateWithAd(skillId, function(ok)
        if ok then
            AudioManager.PlayBtnClick()
            if skillPanel_ and skillPanel_.Refresh then
                skillPanel_.Refresh()
            end
        end
    end)
end

--- 解锁或升级技能
--- level == 0 → 看广告解锁（0→1）
--- level >= 1 → 免费升级（+1）
---@param skillId string
function GM.OnUpgradeSkill(skillId)
    local info = SkillManager.GetSkillInfo(skillId)
    if not info then return end

    if info.level <= 0 then
        -- 解锁（免费）
        SkillManager.UnlockSkill(skillId, function(ok)
            if ok then
                GM.RecalcProduction()
                SlotSaveSystem.MarkDirty()
                AudioManager.PlayBtnClick()
                if skillPanel_ and skillPanel_.Refresh then
                    skillPanel_.Refresh()
                end
            end
        end)
    else
        -- 升级：免费
        if SkillManager.UpgradeSkill(skillId) then
            GM.RecalcProduction()
            SlotSaveSystem.MarkDirty()
            AudioManager.PlayBtnClick()
            if skillPanel_ and skillPanel_.Refresh then
                skillPanel_.Refresh()
            end
        end
    end
end

return GM
