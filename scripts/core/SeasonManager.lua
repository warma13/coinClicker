-- ============================================================================
-- core/SeasonManager.lua
-- 季节系统核心逻辑：季节切换、收集品、圣诞老人、驯鹿
-- ============================================================================

local GameState = require("core.GameState")
local SD = require("config.SeasonDefs")
local SaveBridge = require("core.SaveBridge")

local SM = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

--- 当前激活的季节 id（"none" / "christmas" / ...）
local activeSeason_ = SD.SEASON_NONE

--- 手动切换剩余时间（秒），<=0 表示自然季节
local manualTimer_ = 0

--- 已收集的收集品 { [collectibleId] = true }
local collected_ = {}

--- 圣诞老人等级 (0-14)
local santaLevel_ = 0

--- 已解锁的圣诞升级 { [upgradeId] = true }
local unlockedXmasUpgrades_ = {}

--- 驯鹿状态
local reindeerTimer_ = 0
local reindeerActive_ = false
local reindeerPosX_ = 0
local reindeerPosY_ = 0
local reindeerStayTimer_ = 0

--- 手动切换计数（用于价格公式中的 n）
local switchCount_ = 0

--- 世纪蛋：累计在线时间（秒）
local centuryEggTime_ = 0

--- 回调
local onSeasonChange_ = nil       -- function(newSeason)
local onCollect_ = nil            -- function(item)
local onSantaLevelUp_ = nil       -- function(newLevel, unlockedUpgrade)
local onReindeerSpawn_ = nil      -- function(x, y)
local onReindeerClick_ = nil      -- function(reward, droppedCookie)
local onReindeerExpire_ = nil     -- function()

-- ============================================================================
-- 初始化
-- ============================================================================

function SM.Init()
    activeSeason_ = SD.SEASON_NONE
    manualTimer_ = 0
    collected_ = {}
    santaLevel_ = 0
    unlockedXmasUpgrades_ = {}
    reindeerTimer_ = 200 + math.random() * 160
    reindeerActive_ = false
    reindeerStayTimer_ = 0
    switchCount_ = 0
    centuryEggTime_ = 0

    -- 检查自然季节
    SM.CheckNaturalSeason()

    SaveBridge.Register("seasons", SM.GetState, SM.SetState)
end

-- ============================================================================
-- 回调设置
-- ============================================================================

function SM.SetOnSeasonChange(fn) onSeasonChange_ = fn end
function SM.SetOnCollect(fn) onCollect_ = fn end
function SM.SetOnSantaLevelUp(fn) onSantaLevelUp_ = fn end
function SM.SetOnReindeerSpawn(fn) onReindeerSpawn_ = fn end
function SM.SetOnReindeerClick(fn) onReindeerClick_ = fn end
function SM.SetOnReindeerExpire(fn) onReindeerExpire_ = fn end

-- ============================================================================
-- 季节查询
-- ============================================================================

--- 获取当前激活季节 id
---@return string
function SM.GetActiveSeason()
    return activeSeason_
end

--- 是否在指定季节
---@param seasonId string
---@return boolean
function SM.IsSeason(seasonId)
    return activeSeason_ == seasonId
end

--- 获取手动切换剩余时间
---@return number
function SM.GetManualTimer()
    return manualTimer_
end

-- ============================================================================
-- 自然季节检测
-- ============================================================================

function SM.CheckNaturalSeason()
    if manualTimer_ > 0 then return end  -- 手动切换中，不覆盖

    local date = os.date("*t")
    local m, d = date.month, date.day

    local newSeason = SD.SEASON_NONE
    for _, s in ipairs(SD.seasons) do
        local inRange = false
        if s.startMonth == s.endMonth then
            inRange = m == s.startMonth and d >= s.startDay and d <= s.endDay
        elseif s.startMonth < s.endMonth then
            inRange = (m == s.startMonth and d >= s.startDay) or
                      (m == s.endMonth and d <= s.endDay) or
                      (m > s.startMonth and m < s.endMonth)
        end
        if inRange then
            newSeason = s.id
            break
        end
    end

    if newSeason ~= activeSeason_ then
        activeSeason_ = newSeason
        SM.OnSeasonChanged()
    end
end

--- 计算当前切换价格
---@param cps number 当前每秒金币产出
---@return number
function SM.GetSwitchCost(cps)
    return SD.SWITCH_BASE_COST + cps * 60 * (1.5 ^ switchCount_)
end

--- 获取手动切换次数
---@return number
function SM.GetSwitchCount()
    return switchCount_
end

--- 检查是否解锁了周期切换器天堂升级
---@return boolean
function SM.HasSeasonSwitcher()
    local AscensionManager = require("core.AscensionManager")
    return AscensionManager.HasUpgrade("seasonSwitcher")
end

--- 手动切换季节（需要 Season Switcher 天堂升级 + 支付金币）
---@param seasonId string
---@return boolean success
---@return string|nil reason 失败原因
function SM.SwitchSeason(seasonId)
    if seasonId == activeSeason_ then return false, "already_active" end

    -- 检查是否拥有周期切换器天堂升级
    if not SM.HasSeasonSwitcher() then
        print("[Season] 需要先购买「周期切换器」天堂升级才能手动切换")
        return false, "no_switcher"
    end

    -- 计算并扣除切换费用
    local cost = SM.GetSwitchCost(GameState.coinsPerSecond)
    if GameState.coins < cost then
        print("[Season] 金币不足! 需要: " .. GameState.FormatNumber(cost))
        return false, "not_enough"
    end

    GameState.coins = GameState.coins - cost
    switchCount_ = switchCount_ + 1

    activeSeason_ = seasonId
    manualTimer_ = SD.MANUAL_SWITCH_DURATION
    SM.OnSeasonChanged()
    print("[Season] 手动切换至: " .. seasonId ..
          " (花费: " .. GameState.FormatNumber(cost) ..
          ", 持续 " .. math.floor(manualTimer_) .. "s)")
    return true
end

local function OnSeasonChanged()
    -- 重置驯鹿
    reindeerActive_ = false
    reindeerTimer_ = SM.GetReindeerInterval()

    -- 情人节自动解锁
    if activeSeason_ == SD.SEASON_VALENTINE then
        SM.CheckValentineUnlocks()
    end

    if onSeasonChange_ then
        onSeasonChange_(activeSeason_)
    end
end
SM.OnSeasonChanged = OnSeasonChanged

-- ============================================================================
-- 收集品
-- ============================================================================

--- 检查是否已收集
---@param itemId string
---@return boolean
function SM.HasCollected(itemId)
    return collected_[itemId] == true
end

--- 收集一个物品
---@param item table 收集品定义
---@return boolean 是否为新收集
function SM.Collect(item)
    if collected_[item.id] then return false end
    collected_[item.id] = true
    print("[Season] 收集: " .. item.name)
    if onCollect_ then
        onCollect_(item)
    end
    return true
end

--- 获取指定列表的收集进度
---@param list table[] 收集品列表
---@return number collected, number total
function SM.GetCollectionProgress(list)
    local count = 0
    for _, item in ipairs(list) do
        if collected_[item.id] then
            count = count + 1
        end
    end
    return count, #list
end

--- 获取所有已收集物品的总 CpS 加成
---@return number
function SM.GetCollectionCpsMul()
    local bonus = 0

    -- 牛市分红
    for _, c in ipairs(SD.christmasCookies) do
        if collected_[c.id] then bonus = bonus + c.cpsMul end
    end
    -- 不良资产
    for _, c in ipairs(SD.halloweenCookies) do
        if collected_[c.id] then bonus = bonus + c.cpsMul end
    end
    -- 普通蛋
    for _, e in ipairs(SD.easterEggsNormal) do
        if collected_[e.id] then bonus = bonus + e.cpsMul end
    end
    -- 稀有蛋（有 cpsMul 的；世纪蛋用独立逻辑）
    for _, e in ipairs(SD.easterEggsRare) do
        if e.cpsMul and collected_[e.id] then bonus = bonus + e.cpsMul end
    end
    -- 世纪蛋：CpS 随在线时间递增（最大 +10%）
    if collected_["egg_century"] then
        local centuryDef = nil
        for _, e in ipairs(SD.easterEggsRare) do
            if e.centuryEgg then centuryDef = e; break end
        end
        if centuryDef then
            -- 每在线 1 小时 +1%，上限 maxBonus (10%)
            local hours = centuryEggTime_ / 3600
            local centuryBonus = math.min(hours * 0.01, centuryDef.maxBonus)
            bonus = bonus + centuryBonus
        end
    end
    -- 固定 CpS 蛋 (egg_egg) 在外部单独加
    -- 情人节
    for _, v in ipairs(SD.valentineCookies) do
        if collected_[v.id] then bonus = bonus + v.cpsMul end
    end

    return bonus
end

--- 获取固定 CpS 加成（"egg" 蛋）
---@return number
function SM.GetFixedCpsBonus()
    if collected_["egg_egg"] then return 9 end
    return 0
end

--- 获取点击加成（圣诞 helpers + cookie egg）
---@return number
function SM.GetClickBonus()
    local bonus = 0
    for _, u in ipairs(SD.christmasUpgrades) do
        if u.clickBonus and unlockedXmasUpgrades_[u.id] then
            bonus = bonus + u.clickBonus
        end
    end
    for _, e in ipairs(SD.easterEggsRare) do
        if e.clickBonus and collected_[e.id] then
            bonus = bonus + e.clickBonus
        end
    end
    return bonus
end

--- 获取 Kitten 加成
---@return number
function SM.GetKittenBonus()
    local bonus = 0
    for _, u in ipairs(SD.christmasUpgrades) do
        if u.kittenBonus and unlockedXmasUpgrades_[u.id] then
            bonus = bonus + u.kittenBonus
        end
    end
    return bonus
end

--- 获取幸运频率加成
---@return number
function SM.GetLuckyFreqMul()
    local mul = 1
    for _, e in ipairs(SD.easterEggsRare) do
        if e.luckyFreqMul and collected_[e.id] then
            mul = mul * e.luckyFreqMul
        end
    end
    return mul
end

--- 获取圣诞升级 CpS 加成倍率
---@return number
function SM.GetXmasUpgradeCpsMul()
    local bonus = 0
    for _, u in ipairs(SD.christmasUpgrades) do
        if u.cpsMul and unlockedXmasUpgrades_[u.id] then
            -- Final Claus 专属
            if u.needFinalClaus then
                if santaLevel_ >= SD.SANTA_MAX_LEVEL then
                    bonus = bonus + u.cpsMul
                end
            else
                bonus = bonus + u.cpsMul
            end
        end
    end
    -- Santa's legacy: 每等级 +3%
    for _, u in ipairs(SD.christmasUpgrades) do
        if u.santaLevelBonus and unlockedXmasUpgrades_[u.id] then
            bonus = bonus + u.santaLevelBonus * santaLevel_
        end
    end
    return bonus
end

--- 获取奶奶倍率（Naughty list）
---@return number
function SM.GetGrandmaMul()
    if unlockedXmasUpgrades_["xmas_naughty"] then return 2 end
    return 1
end

--- 获取费用折扣（Toy workshop + Faberge egg）
---@return number 折扣比例 (0~1)
function SM.GetCostReduction()
    local reduction = 0
    for _, u in ipairs(SD.christmasUpgrades) do
        if u.costReduction and unlockedXmasUpgrades_[u.id] then
            reduction = reduction + u.costReduction
        end
    end
    for _, e in ipairs(SD.easterEggsRare) do
        if e.costReduction and collected_[e.id] then
            reduction = reduction + e.costReduction
        end
    end
    return reduction
end

-- ============================================================================
-- 圣诞老人
-- ============================================================================

--- 获取圣诞老人等级
---@return number
function SM.GetSantaLevel()
    return santaLevel_
end

--- 获取圣诞老人等级名
---@return string
function SM.GetSantaName()
    return SD.santaNames[santaLevel_] or "Unknown"
end

--- 获取已解锁的圣诞升级状态
---@return table[]
function SM.GetXmasUpgradeStatus()
    local result = {}
    for _, u in ipairs(SD.christmasUpgrades) do
        result[#result + 1] = {
            def = u,
            unlocked = unlockedXmasUpgrades_[u.id] == true,
        }
    end
    return result
end

--- 升级圣诞老人（购买一级，随机解锁一个未解锁的圣诞升级）
---@return boolean success
---@return table|nil unlockedUpgrade 解锁的升级
function SM.UpgradeSanta()
    if activeSeason_ ~= SD.SEASON_CHRISTMAS then return false, nil end
    if santaLevel_ >= SD.SANTA_MAX_LEVEL then return false, nil end

    local cost = SD.GetSantaUpgradeCost(santaLevel_)
    if GameState.coins < cost then return false, nil end

    GameState.coins = GameState.coins - cost
    santaLevel_ = santaLevel_ + 1

    -- 随机解锁一个未解锁的圣诞升级
    local available = {}
    for _, u in ipairs(SD.christmasUpgrades) do
        if not unlockedXmasUpgrades_[u.id] then
            -- Final Claus 专属升级只在满级时解锁
            if u.needFinalClaus then
                if santaLevel_ >= SD.SANTA_MAX_LEVEL then
                    available[#available + 1] = u
                end
            else
                available[#available + 1] = u
            end
        end
    end

    local unlocked = nil
    if #available > 0 then
        unlocked = available[math.random(1, #available)]
        unlockedXmasUpgrades_[unlocked.id] = true
        print("[Season] 圣诞升级解锁: " .. unlocked.name)
    end

    print("[Season] 圣诞老人升级! Lv." .. santaLevel_ .. " " .. SM.GetSantaName())

    if onSantaLevelUp_ then
        onSantaLevelUp_(santaLevel_, unlocked)
    end

    return true, unlocked
end

-- ============================================================================
-- 驯鹿
-- ============================================================================

--- 获取驯鹿出现间隔
---@return number
function SM.GetReindeerInterval()
    local min = SD.REINDEER_MIN_INTERVAL
    local max = SD.REINDEER_MAX_INTERVAL
    -- Reindeer baking grounds: 频率 ×2（间隔 ÷2）
    if unlockedXmasUpgrades_["xmas_reindeer"] then
        min = min / 2
        max = max / 2
    end
    return min + math.random() * (max - min)
end

--- 获取驯鹿停留时间
---@return number
function SM.GetReindeerStayTime()
    local stay = SD.REINDEER_STAY_DURATION
    if unlockedXmasUpgrades_["xmas_sleighs"] then
        stay = stay * 2
    end
    return stay
end

--- 驯鹿是否在场
---@return boolean
function SM.IsReindeerActive()
    return reindeerActive_
end

--- 获取驯鹿位置
---@return number x, number y
function SM.GetReindeerPos()
    return reindeerPosX_, reindeerPosY_
end

--- 获取驯鹿停留剩余
---@return number
function SM.GetReindeerStayTimer()
    return reindeerStayTimer_
end

--- 调试：立即触发当前赛季特殊事件（风投快车等）
function SM.DebugForceSpawn()
    if activeSeason_ == SD.SEASON_CHRISTMAS then
        reindeerTimer_ = 0  -- 下一帧立即生成风投快车
        print("[Season][Debug] 强制触发风投快车")
    end
end

--- 点击驯鹿
function SM.ClickReindeer()
    if not reindeerActive_ then return end
    reindeerActive_ = false

    -- 计算奖励
    local S = GameState
    local reward = math.max(S.coinsPerSecond * SD.REINDEER_MIN_REWARD_CPS, SD.REINDEER_MIN_REWARD_FLAT)

    -- Ho ho ho: 奖励 ×2
    if unlockedXmasUpgrades_["xmas_hohoho"] then
        reward = reward * 2
    end

    -- 受当前 Buff 影响
    reward = reward * S.buffCpsMul

    S.coins = S.coins + reward

    -- 尝试掉落牛市分红
    local droppedCookie = nil
    local dropChance = SD.REINDEER_COOKIE_DROP_CHANCE
    -- xmas_bag (渠道拓展基金) 提升掉落率 +10%
    if unlockedXmasUpgrades_["xmas_bag"] then
        dropChance = dropChance + 0.10
    end
    if math.random() < dropChance then
        -- 随机选一个未收集的
        local uncollected = {}
        for _, c in ipairs(SD.christmasCookies) do
            if not collected_[c.id] then
                uncollected[#uncollected + 1] = c
            end
        end
        if #uncollected > 0 then
            droppedCookie = uncollected[math.random(1, #uncollected)]
            SM.Collect(droppedCookie)
        end
    end

    print("[Season] 驯鹿点击! 奖励: " .. GameState.FormatNumber(reward) ..
          (droppedCookie and (" + 掉落: " .. droppedCookie.name) or ""))

    if onReindeerClick_ then
        onReindeerClick_(reward, droppedCookie)
    end

    -- 重置驯鹿计时器
    reindeerTimer_ = SM.GetReindeerInterval()
end

-- ============================================================================
-- 情人节自动解锁
-- ============================================================================

function SM.CheckValentineUnlocks()
    if activeSeason_ ~= SD.SEASON_VALENTINE then return end
    local totalBaked = GameState.totalProduced or 0
    -- 也尝试从 coins 估算
    totalBaked = math.max(totalBaked, GameState.coins)

    for _, v in ipairs(SD.valentineCookies) do
        if not collected_[v.id] and totalBaked >= v.threshold then
            SM.Collect(v)
        end
    end
end

-- ============================================================================
-- 万圣节/复活节掉落尝试（外部调用）
-- ============================================================================

--- 尝试万圣节掉落（弹出褶皱虫时调用）
---@return table|nil droppedItem
function SM.TryHalloweenDrop()
    if activeSeason_ ~= SD.SEASON_HALLOWEEN then return nil end

    -- 检查是否全部收集
    local collected, total = SM.GetCollectionProgress(SD.halloweenCookies)
    if collected >= total then return nil end

    -- 有「逆市淘金」(season_hw_all) 成就时掉落率提升
    local AchievementManager = require("core.AchievementManager")
    local hasBoosted = AchievementManager.IsUnlocked("season_hw_all")
    local chance = hasBoosted and SD.HALLOWEEN_DROP_BOOSTED or SD.HALLOWEEN_DROP_BASE

    -- xmas_bag (渠道拓展基金) 提升掉落率 +10%
    if unlockedXmasUpgrades_["xmas_bag"] then
        chance = chance + 0.10
    end

    if math.random() < chance then
        local uncollected = {}
        for _, c in ipairs(SD.halloweenCookies) do
            if not collected_[c.id] then
                uncollected[#uncollected + 1] = c
            end
        end
        if #uncollected > 0 then
            local item = uncollected[math.random(1, #uncollected)]
            SM.Collect(item)
            return item
        end
    end
    return nil
end

--- 尝试专利技术掉落（商机点击/皱巴虫弹出时调用）
---@param source string "lucky" | "wrinkler"
---@return table|nil droppedItem
function SM.TryEasterDrop(source)
    if activeSeason_ ~= SD.SEASON_EASTER then return nil end

    local chance = source == "lucky" and SD.EGG_DROP_LUCKY or SD.EGG_DROP_WRINKLER

    -- Omelette 加成
    if collected_["egg_omelette"] then
        chance = chance + 0.10
    end

    -- xmas_bag (渠道拓展基金) 提升掉落率 +10%
    if unlockedXmasUpgrades_["xmas_bag"] then
        chance = chance + 0.10
    end

    if math.random() > chance then return nil end

    -- 决定普通还是稀有
    local isRare = math.random() < SD.RARE_EGG_CHANCE

    local pool = isRare and SD.easterEggsRare or SD.easterEggsNormal
    local uncollected = {}
    for _, e in ipairs(pool) do
        if not collected_[e.id] then
            uncollected[#uncollected + 1] = e
        end
    end

    -- 如果该池已收集满，尝试另一个池
    if #uncollected == 0 then
        pool = isRare and SD.easterEggsNormal or SD.easterEggsRare
        for _, e in ipairs(pool) do
            if not collected_[e.id] then
                uncollected[#uncollected + 1] = e
            end
        end
    end

    if #uncollected == 0 then return nil end

    local item = uncollected[math.random(1, #uncollected)]

    -- Chocolate egg 特殊处理：获得银行余额 5%
    if item.chocolateEgg then
        local bonus = GameState.coins * 0.05
        GameState.coins = GameState.coins + bonus
        print("[Season] Chocolate egg! 获得银行余额 5%: +" .. GameState.FormatNumber(bonus))
    end

    SM.Collect(item)
    return item
end

-- ============================================================================
-- 商业日效果
-- ============================================================================

--- 获取商业日效果定义（供 GameManager 加入 golden cookie 效果池）
---@return table|nil 效果定义（仅当前为商业日季节时返回）
function SM.GetBusinessDayEffect()
    if activeSeason_ == SD.SEASON_BUSINESS then
        return SD.BUSINESS_DAY_EFFECT
    end
    return nil
end

--- 获取世纪蛋当前加成
---@return number 百分比加成 (0~0.10)
function SM.GetCenturyEggBonus()
    if not collected_["egg_century"] then return 0 end
    local centuryDef = nil
    for _, e in ipairs(SD.easterEggsRare) do
        if e.centuryEgg then centuryDef = e; break end
    end
    if not centuryDef then return 0 end
    local hours = centuryEggTime_ / 3600
    return math.min(hours * 0.01, centuryDef.maxBonus)
end

--- 获取建筑费用折扣（含商业日清仓大促 buff）
---@return number 费用乘数 (1.0 = 无折扣, 0.95 = -5%)
function SM.GetBusinessDayCostMul()
    -- 清仓大促 buff 由 GameManager 通过 activeBuffs 管理
    -- 此处仅作为查询接口
    return 1.0
end

-- ============================================================================
-- 帧更新
-- ============================================================================

function SM.Update(dt)
    -- 世纪蛋在线时间累计
    if collected_["egg_century"] then
        centuryEggTime_ = centuryEggTime_ + dt
    end

    -- 手动切换倒计时
    if manualTimer_ > 0 then
        manualTimer_ = manualTimer_ - dt
        if manualTimer_ <= 0 then
            manualTimer_ = 0
            print("[Season] 手动季节切换结束，恢复自然季节")
            SM.CheckNaturalSeason()
        end
    end

    -- 情人节定期检查解锁
    if activeSeason_ == SD.SEASON_VALENTINE then
        SM.CheckValentineUnlocks()
    end

    -- 圣诞节驯鹿
    if activeSeason_ == SD.SEASON_CHRISTMAS then
        if not reindeerActive_ then
            reindeerTimer_ = reindeerTimer_ - dt
            if reindeerTimer_ <= 0 then
                -- 生成驯鹿
                local dpr = graphics:GetDPR()
                local screenW = graphics:GetWidth() / dpr
                local screenH = graphics:GetHeight() / dpr
                local shopWidth = 260
                local topBar = 50
                reindeerPosX_ = 40 + math.random() * math.max(1, screenW - shopWidth - 80)
                reindeerPosY_ = topBar + 20 + math.random() * math.max(1, screenH - topBar - 80)
                reindeerActive_ = true
                reindeerStayTimer_ = SM.GetReindeerStayTime()

                print("[Season] 🦌 驯鹿出现! pos=(" .. math.floor(reindeerPosX_) .. "," .. math.floor(reindeerPosY_) .. ")")
                if onReindeerSpawn_ then
                    onReindeerSpawn_(reindeerPosX_, reindeerPosY_)
                end
            end
        else
            reindeerStayTimer_ = reindeerStayTimer_ - dt
            if reindeerStayTimer_ <= 0 then
                reindeerActive_ = false
                reindeerTimer_ = SM.GetReindeerInterval()
                print("[Season] 🦌 驯鹿离开（未被点击）")
                if onReindeerExpire_ then
                    onReindeerExpire_()
                end
            end
        end
    end
end

-- ============================================================================
-- 存档/读档
-- ============================================================================

--- 导出当前状态（用于存档）
---@return table
function SM.GetState()
    return {
        activeSeason = activeSeason_,
        manualTimer = manualTimer_,
        switchCount = switchCount_,
        santaLevel = santaLevel_,
        centuryEggTime = centuryEggTime_,
        collected = collected_,
        unlockedXmasUpgrades = unlockedXmasUpgrades_,
        reindeerTimer = reindeerTimer_,
    }
end

--- 从存档恢复状态
---@param state table
function SM.SetState(state)
    if not state then return end
    activeSeason_ = state.activeSeason or SD.SEASON_NONE
    manualTimer_ = state.manualTimer or 0
    switchCount_ = state.switchCount or 0
    santaLevel_ = state.santaLevel or 0
    centuryEggTime_ = state.centuryEggTime or 0

    collected_ = {}
    if state.collected then
        for k, v in pairs(state.collected) do
            collected_[k] = v
        end
    end

    unlockedXmasUpgrades_ = {}
    if state.unlockedXmasUpgrades then
        for k, v in pairs(state.unlockedXmasUpgrades) do
            unlockedXmasUpgrades_[k] = v
        end
    end

    reindeerTimer_ = state.reindeerTimer or SM.GetReindeerInterval()
    reindeerActive_ = false
    reindeerStayTimer_ = 0

    -- 恢复后检查情人节自动解锁
    if activeSeason_ == SD.SEASON_VALENTINE then
        SM.CheckValentineUnlocks()
    end

    print("[Season] 状态已恢复 | 季节: " .. activeSeason_ ..
          " | 圣诞等级: " .. santaLevel_ ..
          " | 切换次数: " .. switchCount_)
end

return SM
