-- ============================================================================
-- core/SaveBridge.lua
-- 存档业务桥接层：序列化/反序列化 + 数据分组 + 版本迁移
-- 自注册模式：各 Manager 在 Init() 时调用 Register() 注册存档回调
-- ============================================================================

local GameState       = require("core.GameState")
local Buildings       = require("config.Buildings")
local Upgrades        = require("config.Upgrades")
local KittenUpgrades  = require("config.KittenUpgrades")

local SB = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------

local CURRENT_VERSION = 3

--- inline 分组名（SaveBridge 自身管理序列化/反序列化的组）
local INLINE_GROUPS = {
    "core",          -- 核心数值（金币、点击等）
    "leaderboard",   -- 排行榜追踪数据
    "buildings",     -- 建筑数量与累计产出
    "upgrades",      -- 点击/管理顾问/建筑效率升级
    "misc",          -- 技能 + 体力 + buff（糖块通过注册）
    "settings",      -- 音量等用户设置
}

-- ---------------------------------------------------------------------------
-- 自注册机制
-- ---------------------------------------------------------------------------

--- 注册表：{ name = { serialize = fn, deserialize = fn } }
local registry_ = {}

--- 注册顺序（保证序列化/分组顺序稳定）
local registryOrder_ = {}

--- 注册一个存档分组
--- 各 Manager 在自己的 Init() 中调用此方法，无需 SaveBridge require Manager
---@param name string          分组名（如 "achievements", "dragon"）
---@param serializeFn function  返回该组存档数据的函数
---@param deserializeFn function 接受存档数据并恢复状态的函数
function SB.Register(name, serializeFn, deserializeFn)
    if registry_[name] then
        print("[SaveBridge] 警告: 分组 '" .. name .. "' 重复注册，覆盖旧注册")
    else
        registryOrder_[#registryOrder_ + 1] = name
    end
    registry_[name] = {
        serialize   = serializeFn,
        deserialize = deserializeFn,
    }
end

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

--- 获取分组名列表（inline + 注册的，合并后返回）
---@return string[]
function SB.GetGroupNames()
    local names = {}
    for _, n in ipairs(INLINE_GROUPS) do
        names[#names + 1] = n
    end
    for _, n in ipairs(registryOrder_) do
        names[#names + 1] = n
    end
    return names
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

    -- -------- 组装 inline 分组 --------
    local result = {
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
        misc    = {
            skills    = skills,
            stamina   = S.stamina,
            buffs     = #buffs > 0 and buffs or nil,
        },
        settings = {
            bgmVol = S.settings.bgmVolume,
            sfxVol = S.settings.sfxVolume,
        },
    }

    -- -------- 注册分组：调用各 Manager 的序列化回调 --------
    for _, name in ipairs(registryOrder_) do
        local entry = registry_[name]
        if entry and entry.serialize then
            result[name] = entry.serialize()
        end
    end

    return result
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
    -- 体力离线恢复：根据离线时间自动回复
    local savedStamina = miscData.stamina or 0
    local offlineStaminaGain = math.floor(offlineSec * (S.staminaRegenRate or 0.33))
    S.stamina = math.min(S.staminaMax, savedStamina + offlineStaminaGain)
    if offlineStaminaGain > 0 and savedStamina < S.staminaMax then
        print("[SaveBridge] 离线体力恢复: +" .. math.min(offlineStaminaGain, S.staminaMax - savedStamina) .. " (离线 " .. offlineSec .. "s)")
    end

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

    -- -------- 旧存档兼容：sugarLump 原先嵌套在 misc 内 --------
    if not data.sugarlump and miscData.sugarLump then
        data.sugarlump = miscData.sugarLump
    end

    -- -------- 注册分组：调用各 Manager 的反序列化回调 --------
    for _, name in ipairs(registryOrder_) do
        local entry = registry_[name]
        if entry and entry.deserialize then
            entry.deserialize(data[name])
        end
    end

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
    local allNames = SB.GetGroupNames()
    for _, name in ipairs(allNames) do
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
    local allNames = SB.GetGroupNames()
    for _, name in ipairs(allNames) do
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
    [1] = function(data)
        -- v1 → v2: 老玩家补偿 3 个人脉币
        data.sugarlump = data.sugarlump or {}
        data.sugarlump.lumps = (data.sugarlump.lumps or 0) + 3
        data.sugarlump.totalHarvested = (data.sugarlump.totalHarvested or 0) + 3
        print("[SaveBridge] v1→v2 迁移: 补偿 3 个人脉币")
    end,
    [2] = function(data)
        -- v2 → v3: 老玩家补偿 5 个时光沙漏
        data.inventory = data.inventory or {}
        -- 找一个空槽位放入，或叠加到已有的时光沙漏上
        local found = false
        for k, v in pairs(data.inventory) do
            if k ~= "_sg" and type(v) == "table" and v.id == "time_hourglass" then
                v.n = (v.n or 1) + 5
                found = true
                break
            end
        end
        if not found then
            -- 找第一个空槽位（1~20）
            for i = 1, 20 do
                local key = tostring(i)
                if not data.inventory[key] then
                    data.inventory[key] = { id = "time_hourglass", n = 5 }
                    break
                end
            end
        end
        print("[SaveBridge] v2→v3 迁移: 补偿 5 个时光沙漏")
    end,
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
