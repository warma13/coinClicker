-- ============================================================================
-- core/SaveBridge.lua
-- 存档业务桥接层：序列化/反序列化 + 数据分组 + 版本迁移
-- 负责收集所有运行时状态并组织为可存储的数据结构
-- ============================================================================

local GameState       = require("core.GameState")
local Buildings       = require("config.Buildings")
local Upgrades        = require("config.Upgrades")
local KittenUpgrades  = require("config.KittenUpgrades")
local AchievementMgr  = require("core.AchievementManager")
local AscensionMgr    = require("core.AscensionManager")
local SugarLumpMgr    = require("core.SugarLumpManager")
local GrandmapoMgr    = require("core.GrandmapoManager")
local WrinklerMgr     = require("core.WrinklerManager")
local SeasonMgr       = require("core.SeasonManager")
local DragonMgr       = require("core.DragonManager")
local GardenMgr       = require("core.GardenManager")
local PantheonMgr     = require("core.PantheonManager")
local GrimoireMgr     = require("core.GrimoireManager")
local StockMarketMgr  = require("core.StockMarketManager")
local MiningMgr       = require("core.MiningManager")
local FactoryMgr      = require("core.FactoryManager")
local ShipmentMgr     = require("core.ShipmentManager")
local ECommerceMgr    = require("core.ECommerceManager")

local SB = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------

local CURRENT_VERSION = 1

--- 数据分组名（每组对应一个云端 key）
--- 新增数据时，将其加入对应分组的 Serialize/Deserialize
local GROUP_NAMES = {
    "core",          -- 核心数值（金币、点击等）
    "leaderboard",   -- 排行榜追踪数据
    "buildings",     -- 建筑数量与累计产出
    "upgrades",      -- 点击/管理顾问/建筑效率升级
    "achievements",  -- 成就系统
    "progression",   -- 飞升系统
    "grandmapo",     -- 奶奶末日 + 皱巴虫
    "seasons",       -- 季节系统
    "dragon",        -- 龙系统
    "misc",          -- 糖块 + 技能 + 其他
    "settings",      -- 音量等用户设置
    "garden",        -- 项目孵化园
    "pantheon",      -- 商业顾问团（万神殿）
    "grimoire",      -- 研发实验室（魔法书）
    "stockmarket",   -- 证券交易所（股票市场）
    "mining",        -- 挖矿探险
    "factory",       -- 制造工厂
    "shipment",      -- 国际物流
    "ecommerce",     -- 电商平台
}

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------

--- 建筑效率升级的运行时引用（由 GameManager 注入）
---@type table|nil
local buildingUpgradesRef_ = nil

-- ---------------------------------------------------------------------------
-- 公共方法
-- ---------------------------------------------------------------------------

--- 注入建筑效率升级引用（GM.Init 后调用）
---@param ref table GM.buildingUpgrades
function SB.SetBuildingUpgrades(ref)
    buildingUpgradesRef_ = ref
end

--- 获取当前存档版本号
---@return number
function SB.GetVersion()
    return CURRENT_VERSION
end

--- 获取分组名列表
---@return string[]
function SB.GetGroupNames()
    return GROUP_NAMES
end

-- ============================================================================
-- 序列化：运行时状态 → 存档数据
-- ============================================================================

--- 收集所有运行时状态为一个完整的存档表
---@return table saveData
function SB.Serialize()
    local S = GameState

    -- -------- core --------
    local core = {
        coins          = S.coins,
        maxCoins       = S.maxCoins,
        totalClicks    = S.totalClicks,
        handmadeCoins  = S.handmadeCoins,
        wrinklersPopped = S.wrinklersPopped,
        luckyClicks    = S.luckyClicks,
    }

    -- -------- leaderboard（排行榜追踪） --------
    local lb = S.leaderboard
    local leaderboard = {
        tp   = lb.totalPlayers,
        mr   = lb.myRank,
        br   = lb.bestRank,
        bp   = lb.bestPercent,
        r1t  = lb.rank1Time,
        r1r  = lb.rank1Reached,
        t10p = lb.top10pReached,
        t1p  = lb.top1pReached,
        t50p = lb.top50pReached,
        t3   = lb.top3Reached,
        t10  = lb.top10Reached,
    }

    -- -------- buildings（稀疏：仅存非零） --------
    local blds = {}
    for i, b in ipairs(Buildings.buildings) do
        if b.count > 0 or b.totalProduced > 0 then
            blds[tostring(i)] = { c = b.count, p = b.totalProduced }
        end
    end

    -- -------- upgrades --------
    -- 点击升级（稀疏）
    local clickUpg = {}
    for i, u in ipairs(Upgrades.clickUpgrades) do
        if u.count > 0 then
            clickUpg[tostring(i)] = u.count
        end
    end
    -- 管理顾问升级（已购买索引数组）
    local kittenUpg = {}
    for i, u in ipairs(KittenUpgrades.upgrades) do
        if u.bought then kittenUpg[#kittenUpg + 1] = i end
    end
    -- 建筑效率升级（每栋建筑已购买的阶索引数组）
    local bldUpg = {}
    if buildingUpgradesRef_ then
        for bi, tiers in ipairs(buildingUpgradesRef_) do
            local bought = {}
            for ti, tier in ipairs(tiers) do
                if tier.bought then bought[#bought + 1] = ti end
            end
            if #bought > 0 then
                bldUpg[tostring(bi)] = bought
            end
        end
    end

    -- -------- skills（仅等级 > 0 的技能，含激活状态） --------
    local skills = {}
    for id, sk in pairs(S.skills) do
        if sk.level > 0 then
            if sk.active and (sk.timer or 0) > 0 then
                skills[id] = { lv = sk.level, t = sk.timer }
            else
                skills[id] = sk.level
            end
        end
    end

    -- -------- activeBuffs（仅保存 gameplay 字段） --------
    local buffs = {}
    for _, b in ipairs(S.activeBuffs) do
        if b.remaining and b.remaining > 0 then
            buffs[#buffs + 1] = {
                id  = b.id,
                n   = b.name,
                ic  = b.icon,
                cl  = b.color,
                rem = b.remaining,
                dur = b.duration,
                mk  = b.multiplierKey,
                mv  = b.multiplierVal,
            }
        end
    end

    -- -------- 组装完整存档 --------
    return {
        version   = CURRENT_VERSION,
        timestamp = os.time(),
        core      = core,
        leaderboard = leaderboard,
        buildings = blds,
        upgrades  = {
            click    = clickUpg,
            kitten   = kittenUpg,
            building = bldUpg,
        },
        achievements = AchievementMgr.GetSaveData(),
        progression  = AscensionMgr.GetSaveData(),
        grandmapo    = {
            gm = GrandmapoMgr.GetSaveData(),
            wm = WrinklerMgr.GetSaveData(),
        },
        seasons = SeasonMgr.GetState(),
        dragon  = DragonMgr.GetSaveData(),
        misc    = {
            sugarLump = SugarLumpMgr.GetSaveData(),
            skills    = skills,
            stamina   = S.stamina,
            buffs     = #buffs > 0 and buffs or nil,
        },
        settings = {
            bgmVol = S.settings.bgmVolume,
            sfxVol = S.settings.sfxVolume,
        },
        garden = GardenMgr.GetSaveData(),
        pantheon = PantheonMgr.GetSaveData(),
        grimoire = GrimoireMgr.GetSaveData(),
        stockmarket = StockMarketMgr.GetSaveData(),
        mining = MiningMgr.GetSaveData(),
        factory = FactoryMgr.GetSaveData(),
        shipment = ShipmentMgr.GetSaveData(),
        ecommerce = ECommerceMgr.GetSaveData(),
    }
end

-- ============================================================================
-- 反序列化：存档数据 → 运行时状态
-- ============================================================================

--- 将存档数据写入运行时状态
---@param data table 完整存档数据
function SB.Deserialize(data)
    if not data then return end
    local S = GameState

    -- -------- core --------
    local core = data.core or {}
    S.coins           = core.coins or 0
    S.maxCoins        = core.maxCoins or S.coins
    S.totalClicks     = core.totalClicks or 0
    S.handmadeCoins   = core.handmadeCoins or 0
    S.wrinklersPopped = core.wrinklersPopped or 0
    S.luckyClicks     = core.luckyClicks or 0

    -- -------- leaderboard --------
    local lbData = data.leaderboard or {}
    local lb = S.leaderboard
    lb.totalPlayers  = lbData.tp   or 0
    lb.myRank        = lbData.mr   or 0
    lb.bestRank      = lbData.br   or 0
    lb.bestPercent   = lbData.bp   or 100
    lb.rank1Time     = lbData.r1t  or 0
    lb.rank1Reached  = lbData.r1r  or false
    lb.top10pReached = lbData.t10p or false
    lb.top1pReached  = lbData.t1p  or false
    lb.top50pReached = lbData.t50p or false
    lb.top3Reached   = lbData.t3   or false
    lb.top10Reached  = lbData.t10  or false

    -- -------- buildings --------
    local blds = data.buildings or {}
    for i, b in ipairs(Buildings.buildings) do
        local saved = blds[tostring(i)]
        if saved then
            b.count         = saved.c or 0
            b.totalProduced = saved.p or 0
        else
            b.count         = 0
            b.totalProduced = 0
        end
    end

    -- -------- upgrades --------
    local upg = data.upgrades or {}

    -- 点击升级
    local clickUpg = upg.click or {}
    for i, u in ipairs(Upgrades.clickUpgrades) do
        u.count = clickUpg[tostring(i)] or 0
    end

    -- 管理顾问升级
    for _, u in ipairs(KittenUpgrades.upgrades) do u.bought = false end
    local kittenUpg = upg.kitten or {}
    for _, idx in ipairs(kittenUpg) do
        if KittenUpgrades.upgrades[idx] then
            KittenUpgrades.upgrades[idx].bought = true
        end
    end

    -- 建筑效率升级
    local bldUpg = upg.building or {}
    if buildingUpgradesRef_ then
        for bi, tiers in ipairs(buildingUpgradesRef_) do
            -- 先重置
            for _, tier in ipairs(tiers) do tier.bought = false end
            -- 恢复已购买
            local bought = bldUpg[tostring(bi)]
            if bought then
                for _, ti in ipairs(bought) do
                    if tiers[ti] then tiers[ti].bought = true end
                end
            end
        end
    end

    -- -------- skills & stamina --------
    local miscData = data.misc or {}
    local skills = miscData.skills or {}
    -- 计算离线时长（用于扣减技能剩余时间）
    local offlineSec = 0
    if data.timestamp then
        offlineSec = os.time() - data.timestamp
        if offlineSec < 0 then offlineSec = 0 end
    end
    for id, sk in pairs(S.skills) do
        local saved = skills[id]
        if type(saved) == "table" then
            -- 新格式：{ lv = level, t = timer }
            sk.level = saved.lv or 0
            local remaining = (saved.t or 0) - offlineSec
            if remaining > 0 then
                sk.active = true
                sk.timer  = remaining
            else
                sk.active = false
                sk.timer  = 0
            end
        else
            -- 旧格式：skills[id] = level（数字）
            sk.level = saved or 0
            sk.active = false
            sk.timer  = 0
        end
        sk.cooldown = nil
    end
    S.stamina = miscData.stamina or 0

    -- -------- activeBuffs（恢复 + 离线扣减） --------
    S.activeBuffs = {}
    local savedBuffs = miscData.buffs
    if savedBuffs then
        for _, sb in ipairs(savedBuffs) do
            local rem = (sb.rem or 0) - offlineSec
            if rem > 0 and sb.mk and sb.mv then
                S.activeBuffs[#S.activeBuffs + 1] = {
                    id            = sb.id or "unknown",
                    name          = sb.n or sb.id or "Buff",
                    icon          = sb.ic or "⭐",
                    color         = sb.cl or { 255, 215, 0, 255 },
                    remaining     = rem,
                    duration      = sb.dur or rem,
                    multiplierKey = sb.mk,
                    multiplierVal = sb.mv,
                }
            end
        end
        if #S.activeBuffs > 0 then
            print("[SaveBridge] 恢复 " .. #S.activeBuffs .. " 个 buff（离线 " .. offlineSec .. "s，过期 " .. (#savedBuffs - #S.activeBuffs) .. " 个）")
        end
    end

    -- -------- settings --------
    local stg = data.settings or {}
    S.settings.bgmVolume = stg.bgmVol or 0.4
    S.settings.sfxVolume = stg.sfxVol or 1.0

    -- -------- 各 Manager --------
    AchievementMgr.LoadSaveData(data.achievements)
    AscensionMgr.LoadSaveData(data.progression)
    GrandmapoMgr.LoadSaveData(data.grandmapo and data.grandmapo.gm)
    WrinklerMgr.LoadSaveData(data.grandmapo and data.grandmapo.wm)
    SeasonMgr.SetState(data.seasons)
    DragonMgr.LoadSaveData(data.dragon)
    SugarLumpMgr.LoadSaveData(data.misc and data.misc.sugarLump)
    GardenMgr.LoadSaveData(data.garden)
    PantheonMgr.LoadSaveData(data.pantheon)
    GrimoireMgr.LoadSaveData(data.grimoire)
    StockMarketMgr.LoadSaveData(data.stockmarket)
    MiningMgr.LoadSaveData(data.mining)
    FactoryMgr.LoadSaveData(data.factory)
    ShipmentMgr.LoadSaveData(data.shipment)
    ECommerceMgr.LoadSaveData(data.ecommerce)

    print("[SaveBridge] 反序列化完成")
end

-- ============================================================================
-- 数据分组
-- ============================================================================

--- 将完整存档拆分为命名分组（用于分 key 存储）
---@param saveData table
---@return table groups  { groupName = groupData, ... }
---@return number version
---@return number timestamp
function SB.SplitIntoGroups(saveData)
    local groups = {}
    for _, name in ipairs(GROUP_NAMES) do
        groups[name] = saveData[name]
    end
    return groups, saveData.version or CURRENT_VERSION, saveData.timestamp or os.time()
end

--- 将分组数据合并还原为完整存档
---@param groups table
---@param version number
---@param timestamp number
---@return table saveData
function SB.MergeGroups(groups, version, timestamp)
    local data = {
        version   = version or CURRENT_VERSION,
        timestamp = timestamp or os.time(),
    }
    for _, name in ipairs(GROUP_NAMES) do
        data[name] = groups[name]
    end
    return data
end

--- 构建当前槽位的摘要信息（用于 meta 展示）
---@return table slotSummary
function SB.BuildMetaSlot()
    local S = GameState
    return {
        coins     = S.coins,
        cps       = S.coinsPerSecond,
        clicks    = S.totalClicks,
        timestamp = os.time(),
    }
end

-- ============================================================================
-- 版本迁移
-- ============================================================================

--- 迁移函数表：MIGRATIONS[oldVersion] 负责 oldVersion → oldVersion+1
local MIGRATIONS = {
    -- 示例（未来使用）：
    -- [1] = function(data)
    --     -- v1 → v2: 添加新字段的默认值
    --     data.misc = data.misc or {}
    --     data.misc.newFeature = data.misc.newFeature or {}
    -- end,
}

--- 逐级运行版本迁移
---@param data table
---@return table data
function SB.RunMigrations(data)
    if not data then return { version = CURRENT_VERSION } end
    data.version = data.version or 1
    while data.version < CURRENT_VERSION do
        local fn = MIGRATIONS[data.version]
        if fn then
            fn(data)
            data.version = data.version + 1
            print("[SaveBridge] 迁移: v" .. (data.version - 1) .. " → v" .. data.version)
        else
            print("[SaveBridge] 缺少迁移函数 v" .. data.version .. ", 中断")
            break
        end
    end
    return data
end

return SB
