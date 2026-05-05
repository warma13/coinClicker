-- ============================================================================
-- core/GardenManager.lua
-- 项目孵化园核心逻辑：种植、生长、收获、杂交、罢工、存档
-- ============================================================================

local GameState = require("core.GameState")
local GC        = require("config.GardenConfig")

local GM = {}

-- ---------------------------------------------------------------------------
-- 内部状态
-- ---------------------------------------------------------------------------

---@class GardenPlot
---@field seedId string|nil   种子 id（nil = 空地）
---@field elapsed number      已生长秒数
---@field wiltElapsed number  成熟后枯萎倒计时
---@field stage number        当前阶段 GC.STAGE_*
---@field boosted boolean     是否受过管培生加速

-- 网格（1-indexed rows/cols, row major）
local grid_ = {}          ---@type GardenPlot[][]
local gridSize_ = GC.GRID_MIN_SIZE

-- 土壤
local soilId_ = "normal"

-- 计时器
local crossbreedTimer_ = 0
local bugTimer_ = 0
local soilCooldown_ = 0       -- 土壤切换冷却剩余
local bugImmunityTimer_ = 0   -- 法务合规免疫剩余

-- 图鉴
local discoveredSeeds_ = {}   ---@type table<string, boolean>

-- 管培生生长加速
local growthBoostTimer_ = 0   -- 管培生 30% 加速剩余秒数
local GROWTH_BOOST_DUR = 120  -- 加速持续 120 秒
local GROWTH_BOOST_MUL = 1.3  -- +30%

-- 回调
local onHarvest_ = nil        ---@type fun(seedDef: table, coins: number, buff: table|nil)|nil
local onDiscover_ = nil       ---@type fun(seedId: string)|nil
local onBugAttack_ = nil      ---@type fun(count: number)|nil

-- ---------------------------------------------------------------------------
-- 内部工具
-- ---------------------------------------------------------------------------

--- 初始化一个空地块
---@return GardenPlot
local function EmptyPlot()
    return {
        seedId = nil,
        elapsed = 0,
        wiltElapsed = 0,
        stage = GC.STAGE_EMPTY,
        boosted = false,
    }
end

--- 初始化空网格
local function InitGrid(size)
    gridSize_ = size
    grid_ = {}
    for r = 1, size do
        grid_[r] = {}
        for c = 1, size do
            grid_[r][c] = EmptyPlot()
        end
    end
end

--- 获取当前土壤定义
---@return table
local function GetSoil()
    return GC.FindSoil(soilId_) or GC.soils[1]
end

-- ---------------------------------------------------------------------------
-- 初始化
-- ---------------------------------------------------------------------------

function GM.Init()
    InitGrid(GC.GRID_MIN_SIZE)
    soilId_ = "normal"
    crossbreedTimer_ = 0
    bugTimer_ = 0
    soilCooldown_ = 0
    bugImmunityTimer_ = 0
    growthBoostTimer_ = 0
    discoveredSeeds_ = {}
    -- 基础种子默认已发现
    for _, s in ipairs(GC.seeds) do
        discoveredSeeds_[s.id] = true
    end
end

-- ---------------------------------------------------------------------------
-- 回调注册
-- ---------------------------------------------------------------------------

---@param fn fun(seedDef: table, coins: number, buff: table|nil)
function GM.SetOnHarvest(fn) onHarvest_ = fn end

---@param fn fun(seedId: string)
function GM.SetOnDiscover(fn) onDiscover_ = fn end

---@param fn fun(count: number)
function GM.SetOnBugAttack(fn) onBugAttack_ = fn end

-- ---------------------------------------------------------------------------
-- 查询接口
-- ---------------------------------------------------------------------------

function GM.GetGridSize() return gridSize_ end

---@param row number
---@param col number
---@return GardenPlot|nil
function GM.GetPlot(row, col)
    if row < 1 or row > gridSize_ or col < 1 or col > gridSize_ then return nil end
    return grid_[row][col]
end

function GM.GetSoilId() return soilId_ end
function GM.GetSoilCooldown() return soilCooldown_ end
function GM.GetBugImmunityTimer() return bugImmunityTimer_ end
function GM.GetGrowthBoostTimer() return growthBoostTimer_ end

--- 获取已发现的种子 id 集合
---@return table<string, boolean>
function GM.GetDiscoveredSeeds() return discoveredSeeds_ end

--- 获取已发现种子数量
---@return number
function GM.GetDiscoveredCount()
    local n = 0
    for _ in pairs(discoveredSeeds_) do n = n + 1 end
    return n
end

--- 是否已发现某种子
---@param seedId string
---@return boolean
function GM.IsDiscovered(seedId) return discoveredSeeds_[seedId] == true end

--- 获取已解锁的种子列表（用于种植选择）
---@return table[]
function GM.GetPlantableSeeds()
    local list = {}
    for _, s in ipairs(GC.seeds) do
        if discoveredSeeds_[s.id] then
            list[#list + 1] = s
        end
    end
    for _, s in ipairs(GC.advancedSeeds) do
        if discoveredSeeds_[s.id] then
            list[#list + 1] = s
        end
    end
    return list
end

-- ---------------------------------------------------------------------------
-- 操作接口
-- ---------------------------------------------------------------------------

--- 种植种子
---@param row number
---@param col number
---@param seedId string
---@return boolean success
function GM.Plant(row, col, seedId)
    local plot = GM.GetPlot(row, col)
    if not plot then return false end
    if plot.seedId ~= nil then return false end -- 已有植物

    local seedDef = GC.FindSeed(seedId)
    if not seedDef then return false end
    if not discoveredSeeds_[seedId] then return false end

    -- 扣除种植成本（CPS × costMul）
    local costMul = seedDef.costMul or 0
    if costMul > 0 then
        local cost = GameState.coinsPerSecond * costMul
        if GameState.coins < cost then return false end
        GameState.coins = GameState.coins - cost
    end

    plot.seedId = seedId
    plot.elapsed = 0
    plot.wiltElapsed = 0
    plot.stage = GC.STAGE_SPROUT
    plot.boosted = false
    return true
end

--- 收获成熟植物
---@param row number
---@param col number
---@return boolean success
function GM.Harvest(row, col)
    local plot = GM.GetPlot(row, col)
    if not plot or not plot.seedId then return false end
    if plot.stage ~= GC.STAGE_MATURE and plot.stage ~= GC.STAGE_WILTING then
        return false
    end

    local seedDef = GC.FindSeed(plot.seedId)
    if not seedDef then
        -- 未知种子，清理
        grid_[row][col] = EmptyPlot()
        return false
    end

    local soil = GetSoil()

    -- 计算金币奖励 = CPS × harvestCpsMul × 土壤收益倍率
    local coins = GameState.coinsPerSecond * seedDef.harvestCpsMul * soil.yieldMul
    coins = math.max(coins, 1)
    GameState.coins = GameState.coins + coins

    -- 枯萎中收获减半 buff 持续时间
    local wiltPenalty = (plot.stage == GC.STAGE_WILTING) and 0.5 or 1.0

    -- 生成 buff
    local buff = nil
    if seedDef.buffType then
        buff = {
            id = "garden_" .. seedDef.id,
            name = seedDef.name,
            icon = "🌱",
            color = { 100, 200, 120, 255 },
            remaining = seedDef.buffDuration * wiltPenalty,
            duration = seedDef.buffDuration * wiltPenalty,
            multiplierKey = seedDef.buffType,
            multiplierVal = seedDef.buffValue,
        }
        -- 注入 buff 到 activeBuffs（叠加同 id）
        local stacked = false
        for _, existing in ipairs(GameState.activeBuffs) do
            if existing.id == buff.id then
                existing.remaining = existing.remaining + buff.remaining
                existing.duration = math.max(existing.duration, buff.duration)
                stacked = true
                break
            end
        end
        if not stacked then
            GameState.activeBuffs[#GameState.activeBuffs + 1] = buff
        end
    end

    -- 特殊效果
    if seedDef.bugImmunity then
        bugImmunityTimer_ = math.max(bugImmunityTimer_, seedDef.bugImmunity)
    end
    if seedDef.soilBonus == "growthSpeed" then
        growthBoostTimer_ = math.max(growthBoostTimer_, GROWTH_BOOST_DUR)
    end
    if seedDef.permanent == "grid" then
        -- 永久解锁 1 个额外格子（扩展网格，上限 6）
        if gridSize_ < GC.GRID_MAX_SIZE then
            GM.ExpandGrid()
        end
    end

    -- 清空地块
    grid_[row][col] = EmptyPlot()

    -- 回调
    if onHarvest_ then
        onHarvest_(seedDef, coins, buff)
    end

    return true
end

--- 清除地块（枯死植物或手动移除）
---@param row number
---@param col number
---@return boolean
function GM.ClearPlot(row, col)
    local plot = GM.GetPlot(row, col)
    if not plot or not plot.seedId then return false end
    grid_[row][col] = EmptyPlot()
    return true
end

--- 切换土壤模式
---@param newSoilId string
---@return boolean success
---@return string|nil reason
function GM.SwitchSoil(newSoilId)
    if soilCooldown_ > 0 then
        return false, "cooling"
    end
    if newSoilId == soilId_ then
        return false, "same"
    end
    local def = GC.FindSoil(newSoilId)
    if not def then return false, "invalid" end

    soilId_ = newSoilId
    soilCooldown_ = GC.SOIL_COOLDOWN
    return true
end

--- 扩展网格（消耗糖块，由外部检查支付）
---@return boolean success
function GM.ExpandGrid()
    if gridSize_ >= GC.GRID_MAX_SIZE then return false end
    local newSize = gridSize_ + 1
    -- 扩展：保留已有地块，新增空地块
    for r = 1, newSize do
        if not grid_[r] then grid_[r] = {} end
        for c = 1, newSize do
            if not grid_[r][c] then
                grid_[r][c] = EmptyPlot()
            end
        end
    end
    gridSize_ = newSize
    return true
end

-- ---------------------------------------------------------------------------
-- 杂交检查
-- ---------------------------------------------------------------------------

--- 检查一块地的 4 邻居，寻找杂交机会
---@param row number
---@param col number
local function TryCrossBreedsAt(row, col)
    local plot = GM.GetPlot(row, col)
    if not plot or plot.seedId ~= nil then return end -- 需要空地

    local soil = GetSoil()
    local neighbors = {}
    local dirs = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
    for _, d in ipairs(dirs) do
        local np = GM.GetPlot(row + d[1], col + d[2])
        if np and np.seedId and (np.stage == GC.STAGE_MATURE or np.stage == GC.STAGE_BLOOM) then
            neighbors[#neighbors + 1] = np.seedId
        end
    end
    if #neighbors < 2 then return end

    -- 尝试所有邻居配对
    for i = 1, #neighbors - 1 do
        for j = i + 1, #neighbors do
            local offspring = GC.GetPossibleOffspring(neighbors[i], neighbors[j])
            for _, child in ipairs(offspring) do
                local chance = child.mutationChance * soil.crossMul
                if math.random() < chance then
                    -- 杂交成功！
                    plot.seedId = child.id
                    plot.elapsed = 0
                    plot.wiltElapsed = 0
                    plot.stage = GC.STAGE_SPROUT
                    -- 新品种发现
                    if not discoveredSeeds_[child.id] then
                        discoveredSeeds_[child.id] = true
                        if onDiscover_ then
                            onDiscover_(child.id)
                        end
                    end
                    print("[Garden] 杂交成功! " .. neighbors[i] .. " + " .. neighbors[j] .. " → " .. child.id)
                    return -- 一块地只能出一个
                end
            end
        end
    end
end

--- 全网格杂交检查
local function CheckAllCrossbreeds()
    for r = 1, gridSize_ do
        for c = 1, gridSize_ do
            TryCrossBreedsAt(r, c)
        end
    end
end

-- ---------------------------------------------------------------------------
-- 罢工检查
-- ---------------------------------------------------------------------------

local function TryBugDisaster()
    if bugImmunityTimer_ > 0 then return end

    local chance = GC.BUG_BASE_CHANCE
    -- 加班模式增加罢工概率
    if soilId_ == "overtime" then
        chance = chance * 1.5
    end
    -- 远程办公降低罢工概率
    if soilId_ == "remote" then
        chance = chance * 0.5
    end

    if math.random() > chance then return end

    -- 随机选择 1~2 块有项目的地块
    local occupied = {}
    for r = 1, gridSize_ do
        for c = 1, gridSize_ do
            if grid_[r][c].seedId then
                occupied[#occupied + 1] = { r = r, c = c }
            end
        end
    end
    if #occupied == 0 then return end

    local killCount = math.min(math.random(1, 2), #occupied)
    -- 打乱顺序
    for i = #occupied, 2, -1 do
        local j = math.random(1, i)
        occupied[i], occupied[j] = occupied[j], occupied[i]
    end
    for i = 1, killCount do
        local pos = occupied[i]
        print("[Garden] 罢工! 地块 (" .. pos.r .. "," .. pos.c .. ") 项目受损")
        grid_[pos.r][pos.c] = EmptyPlot()
    end

    if onBugAttack_ then
        onBugAttack_(killCount)
    end
end

-- ---------------------------------------------------------------------------
-- 帧更新
-- ---------------------------------------------------------------------------

function GM.Update(dt)
    local soil = GetSoil()

    -- 冷却倒计时
    if soilCooldown_ > 0 then
        soilCooldown_ = math.max(0, soilCooldown_ - dt)
    end
    if bugImmunityTimer_ > 0 then
        bugImmunityTimer_ = math.max(0, bugImmunityTimer_ - dt)
    end
    if growthBoostTimer_ > 0 then
        growthBoostTimer_ = math.max(0, growthBoostTimer_ - dt)
    end

    -- 生长倍率
    local growMul = soil.growthMul
    if growthBoostTimer_ > 0 then
        growMul = growMul * GROWTH_BOOST_MUL
    end

    -- 更新每块地的生长
    for r = 1, gridSize_ do
        for c = 1, gridSize_ do
            local plot = grid_[r][c]
            if plot.seedId then
                local seedDef = GC.FindSeed(plot.seedId)
                if not seedDef then
                    -- 未知种子，视为死亡
                    grid_[r][c] = EmptyPlot()
                else
                    if plot.stage < GC.STAGE_MATURE then
                        -- 生长中
                        plot.elapsed = plot.elapsed + dt * growMul
                        local frac = plot.elapsed / seedDef.growthTime
                        plot.stage = GC.GetStageFromFraction(frac)
                    elseif plot.stage == GC.STAGE_MATURE then
                        -- 成熟→枯萎倒计时
                        plot.wiltElapsed = plot.wiltElapsed + dt * soil.wiltMul
                        if plot.wiltElapsed >= GC.WILT_TIME then
                            plot.stage = GC.STAGE_WILTING
                        end
                    elseif plot.stage == GC.STAGE_WILTING then
                        -- 枯萎→死亡（再给一半时间）
                        plot.wiltElapsed = plot.wiltElapsed + dt * soil.wiltMul
                        if plot.wiltElapsed >= GC.WILT_TIME * 1.5 then
                            plot.stage = GC.STAGE_DEAD
                            print("[Garden] 地块 (" .. r .. "," .. c .. ") " .. seedDef.name .. " 枯死")
                        end
                    end
                    -- DEAD 不做处理，等玩家手动清理
                end
            end
        end
    end

    -- 杂交定时检查
    crossbreedTimer_ = crossbreedTimer_ + dt
    if crossbreedTimer_ >= GC.CROSSBREED_TICK then
        crossbreedTimer_ = crossbreedTimer_ - GC.CROSSBREED_TICK
        CheckAllCrossbreeds()
    end

    -- 虫灾定时检查
    bugTimer_ = bugTimer_ + dt
    if bugTimer_ >= GC.BUG_CHECK_INTERVAL then
        bugTimer_ = bugTimer_ - GC.BUG_CHECK_INTERVAL
        TryBugDisaster()
    end
end

-- ---------------------------------------------------------------------------
-- 存档
-- ---------------------------------------------------------------------------

---@return table
function GM.GetSaveData()
    -- 网格（稀疏存储，只存有植物的格子）
    local plots = {}
    for r = 1, gridSize_ do
        for c = 1, gridSize_ do
            local p = grid_[r][c]
            if p.seedId then
                plots[#plots + 1] = {
                    r = r, c = c,
                    s = p.seedId,
                    e = p.elapsed,
                    w = p.wiltElapsed,
                    st = p.stage,
                }
            end
        end
    end

    -- 发现列表
    local disc = {}
    for id in pairs(discoveredSeeds_) do
        disc[#disc + 1] = id
    end

    return {
        sz   = gridSize_,
        soil = soilId_,
        sc   = soilCooldown_,
        bi   = bugImmunityTimer_,
        gb   = growthBoostTimer_,
        ct   = crossbreedTimer_,
        bt   = bugTimer_,
        plots = plots,
        disc  = disc,
    }
end

---@param data table|nil
function GM.LoadSaveData(data)
    if not data then
        GM.Init()
        return
    end

    gridSize_ = data.sz or GC.GRID_MIN_SIZE
    InitGrid(gridSize_)

    soilId_ = data.soil or "normal"
    soilCooldown_ = data.sc or 0
    bugImmunityTimer_ = data.bi or 0
    growthBoostTimer_ = data.gb or 0
    crossbreedTimer_ = data.ct or 0
    bugTimer_ = data.bt or 0

    -- 恢复发现列表
    discoveredSeeds_ = {}
    for _, s in ipairs(GC.seeds) do
        discoveredSeeds_[s.id] = true
    end
    if data.disc then
        for _, id in ipairs(data.disc) do
            discoveredSeeds_[id] = true
        end
    end

    -- 恢复地块
    if data.plots then
        for _, pd in ipairs(data.plots) do
            if pd.r >= 1 and pd.r <= gridSize_ and pd.c >= 1 and pd.c <= gridSize_ then
                grid_[pd.r][pd.c] = {
                    seedId = pd.s,
                    elapsed = pd.e or 0,
                    wiltElapsed = pd.w or 0,
                    stage = pd.st or GC.STAGE_SPROUT,
                    boosted = false,
                }
            end
        end
    end

    print("[GardenManager] 存档加载完成 (grid=" .. gridSize_ .. ", discovered=" .. GM.GetDiscoveredCount() .. ")")
end

--- 飞升重置（保留图鉴，重置网格和状态）
function GM.ResetForAscension()
    InitGrid(GC.GRID_MIN_SIZE)
    soilId_ = "normal"
    soilCooldown_ = 0
    bugImmunityTimer_ = 0
    growthBoostTimer_ = 0
    crossbreedTimer_ = 0
    bugTimer_ = 0
    -- discoveredSeeds_ 保留！这是永久进度
    print("[GardenManager] 飞升重置 (图鉴保留:" .. GM.GetDiscoveredCount() .. ")")
end

return GM
