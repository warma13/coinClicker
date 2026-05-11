-- ============================================================================
-- core/MiningManager.lua
-- 挖矿探险 —— 网格生成、挖掘逻辑、镐头耐久、道具、存档
-- ============================================================================

local MC = require("config.MiningConfig")
local Buildings = require("config.Buildings")
local GameState = require("core.GameState")
local SaveBridge = require("core.SaveBridge")

--- 向全局 buff 列表添加一个 CPS 倍率 buff（同 id 叠加时间）
---@param buffDef table { id, name, mul, duration }
local function ApplyMineBuff(buffDef)
    for _, existing in ipairs(GameState.activeBuffs) do
        if existing.id == buffDef.id then
            existing.remaining = existing.remaining + buffDef.duration
            existing.duration = math.max(existing.duration, buffDef.duration)
            return
        end
    end
    GameState.activeBuffs[#GameState.activeBuffs + 1] = {
        id = buffDef.id,
        name = buffDef.name or buffDef.id,
        icon = "⛏️",
        color = { 180, 140, 60, 255 },
        remaining = buffDef.duration,
        duration = buffDef.duration,
        multiplierKey = "cps",
        multiplierVal = buffDef.mul,
    }
end

local MM = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

---@class MiningCell
---@field oreId string       矿石类型 id
---@field revealed boolean   是否已挖开
---@field hint number|nil    扫雷提示数字（挖开空岩后计算）

---@type MiningCell[][]
local grid_ = {}            -- grid_[row][col]
local cols_ = 5
local rows_ = 4
local picks_ = 10           -- 当前镐头耐久
local maxPicks_ = 10
local regenTimer_ = 0       -- 镐头回复计时器
local refreshTimer_ = 0     -- 矿区自动刷新计时器
local streak_ = 0           -- 连续挖到矿石计数
local totalRevealed_ = 0    -- 已挖开格子数
local totalCells_ = 0       -- 总格子数
local hasMinecart_ = false  -- 是否拥有矿车（被动道具）
local boardsCleared_ = 0    -- 累计矿区清空次数（成就用）

-- 回调
local onDig_ = nil          -- function(row, col, oreDef, coins, streakBonus)
local onCollapse_ = nil     -- function(row, col, lostCoins)
local onRefresh_ = nil      -- function()
local onFullClear_ = nil    -- function(bonusCoins)

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 获取采矿场数量
---@return number
local function GetMineCount()
    for _, b in ipairs(Buildings.buildings) do
        if b.id == MC.BUILDING_ID then
            return b.count
        end
    end
    return 0
end

--- 获取采矿场等级
---@return number
local function GetMineLevel()
    for _, b in ipairs(Buildings.buildings) do
        if b.id == MC.BUILDING_ID then
            return b.level or 0
        end
    end
    return 0
end

--- 加权随机选择矿石 id
---@param weights table
---@return string oreId
local function WeightedRandomOre(weights)
    local totalW = 0
    for _, w in ipairs(weights) do
        totalW = totalW + w.weight
    end
    local r = math.random() * totalW
    local acc = 0
    for _, w in ipairs(weights) do
        acc = acc + w.weight
        if r <= acc then
            return w.id
        end
    end
    return "empty"
end

--- 计算某格周围 8 格的最大价值提示
---@param row number
---@param col number
---@return number hint 0-3
local function CalcHint(row, col)
    local maxVal = 0
    local sumVal = 0
    for dr = -1, 1 do
        for dc = -1, 1 do
            if dr ~= 0 or dc ~= 0 then
                local r2, c2 = row + dr, col + dc
                if r2 >= 1 and r2 <= rows_ and c2 >= 1 and c2 <= cols_ then
                    local cell = grid_[r2][c2]
                    if not cell.revealed then
                        local v = MC.HINT_VALUES[cell.oreId] or 0
                        if v > maxVal then maxVal = v end
                        sumVal = sumVal + v
                    end
                end
            end
        end
    end
    -- 返回最高单格价值（0=无矿, 1=铜铁, 2=金/化石, 3=宝石）
    return maxVal
end

-- ============================================================================
-- 初始化 / 生成矿区
-- ============================================================================

--- 生成新矿区
local function GenerateGrid()
    local mineCount = GetMineCount()
    local mineLevel = GetMineLevel()
    cols_, rows_ = MC.GetGridSize(mineCount)
    totalCells_ = cols_ * rows_
    totalRevealed_ = 0
    streak_ = 0

    local weights = MC.GetOreWeights(mineLevel)

    grid_ = {}
    for r = 1, rows_ do
        grid_[r] = {}
        for c = 1, cols_ do
            grid_[r][c] = {
                oreId = WeightedRandomOre(weights),
                revealed = false,
                hint = nil,
            }
        end
    end

    -- 矿车被动：自动挖开 2 格（每格消耗 1 点耐久）
    if hasMinecart_ then
        local unrevealed = {}
        for r = 1, rows_ do
            for c = 1, cols_ do
                unrevealed[#unrevealed + 1] = { r = r, c = c }
            end
        end
        local autoDigCount = math.min(2, #unrevealed, picks_)
        for _ = 1, autoDigCount do
            local idx = math.random(1, #unrevealed)
            local pos = unrevealed[idx]
            table.remove(unrevealed, idx)
            local cell = grid_[pos.r][pos.c]
            cell.revealed = true
            cell.hint = nil
            totalRevealed_ = totalRevealed_ + 1
            picks_ = picks_ - MC.PICK_COST_DIG
        end
    end

    refreshTimer_ = MC.REFRESH_INTERVAL
end

function MM.Init()
    local mineCount = GetMineCount()
    maxPicks_ = MC.GetMaxPicks(mineCount)
    picks_ = maxPicks_
    regenTimer_ = 0
    hasMinecart_ = false
    GenerateGrid()

    SaveBridge.Register("mining", MM.GetSaveData, MM.LoadSaveData, function()
        local mc = GetMineCount()
        maxPicks_ = MC.GetMaxPicks(mc)
        picks_ = maxPicks_
        regenTimer_ = 0
        hasMinecart_ = false
        boardsCleared_ = 0
        streak_ = 0
        totalRevealed_ = 0
        GenerateGrid()
    end)
end

-- ============================================================================
-- 回调设置
-- ============================================================================

function MM.SetOnDig(fn) onDig_ = fn end
function MM.SetOnCollapse(fn) onCollapse_ = fn end
function MM.SetOnRefresh(fn) onRefresh_ = fn end
function MM.SetOnFullClear(fn) onFullClear_ = fn end

-- ============================================================================
-- 查询接口
-- ============================================================================

function MM.GetGrid() return grid_ end
function MM.GetCols() return cols_ end
function MM.GetRows() return rows_ end
function MM.GetPicks() return picks_ end
function MM.GetMaxPicks() return maxPicks_ end
function MM.GetRefreshTimer() return refreshTimer_ end
function MM.GetStreak() return streak_ end
function MM.GetTotalRevealed() return totalRevealed_ end
function MM.GetTotalCells() return totalCells_ end
function MM.GetBoardsCleared() return boardsCleared_ end

function MM.GetCell(row, col)
    if row >= 1 and row <= rows_ and col >= 1 and col <= cols_ then
        return grid_[row][col]
    end
    return nil
end

--- 获取已解锁的道具列表
---@return table[]
function MM.GetUnlockedTools()
    local mineCount = GetMineCount()
    local result = {}
    for _, tool in ipairs(MC.TOOLS) do
        if mineCount >= tool.unlockMineCount then
            result[#result + 1] = tool
        end
    end
    return result
end

--- 检查矿车是否激活
function MM.HasMinecart() return hasMinecart_ end

--- 切换矿车激活状态
function MM.ToggleMinecart()
    local mineCount = GetMineCount()
    local toolDef = MC.toolMap["minecart"]
    if toolDef and mineCount >= toolDef.unlockMineCount then
        hasMinecart_ = not hasMinecart_
    end
end

-- ============================================================================
-- 核心操作
-- ============================================================================

--- 挖掘一个格子
---@param row number
---@param col number
---@return boolean success
function MM.Dig(row, col)
    if row < 1 or row > rows_ or col < 1 or col > cols_ then return false end
    local cell = grid_[row][col]
    if cell.revealed then return false end
    if picks_ < MC.PICK_COST_DIG then return false end

    picks_ = picks_ - MC.PICK_COST_DIG
    cell.revealed = true
    cell.hint = nil  -- 挖开后清除探测仪提示
    totalRevealed_ = totalRevealed_ + 1

    local oreDef = MC.oreMap[cell.oreId]
    if not oreDef then return true end

    if oreDef.penalty then
        -- 塌方处理
        local lostCoins = GameState.coinsPerSecond * MC.COLLAPSE_CPS_LOSS_SECONDS
        lostCoins = math.min(lostCoins, GameState.coins * 0.05) -- 最多损失 5% 金币
        GameState.coins = GameState.coins - lostCoins
        streak_ = 0
        if onCollapse_ then onCollapse_(row, col, lostCoins) end
    elseif cell.oreId ~= "empty" then
        -- 矿石奖励
        local coins = GameState.coinsPerSecond * oreDef.cpsSeconds
        -- 连击检测
        streak_ = streak_ + 1
        local streakBonus = 1.0
        if streak_ >= MC.STREAK_THRESHOLD then
            streakBonus = MC.STREAK_MULTIPLIER
        end
        coins = coins * streakBonus
        GameState.coins = GameState.coins + coins

        -- buff 处理
        if oreDef.buff then
            ApplyMineBuff(oreDef.buff)
        end

        if onDig_ then onDig_(row, col, oreDef, coins, streakBonus > 1.0) end
    else
        -- 空岩，重置连击
        streak_ = 0
    end

    -- 全清检测
    if totalRevealed_ >= totalCells_ then
        boardsCleared_ = boardsCleared_ + 1
        local bonusCoins = GameState.coinsPerSecond * MC.FULL_CLEAR_CPS_SECONDS
        GameState.coins = GameState.coins + bonusCoins
        if onFullClear_ then onFullClear_(bonusCoins) end
    end

    return true
end

--- 使用探测仪（揭示点击格子的提示数字）
---@param centerRow number
---@param centerCol number
---@return boolean success
function MM.UseScanner(centerRow, centerCol)
    local toolDef = MC.toolMap["scanner"]
    if not toolDef then return false end
    if GetMineCount() < toolDef.unlockMineCount then return false end
    if picks_ < toolDef.pickCost then return false end
    if centerRow < 1 or centerRow > rows_ or centerCol < 1 or centerCol > cols_ then return false end

    local cell = grid_[centerRow][centerCol]
    if cell.revealed then return false end

    picks_ = picks_ - toolDef.pickCost
    cell.hint = CalcHint(centerRow, centerCol)
    return true
end

--- 使用炸药（炸开十字形 5 格）
---@param centerRow number
---@param centerCol number
---@return boolean success
function MM.UseDynamite(centerRow, centerCol)
    local toolDef = MC.toolMap["dynamite"]
    if not toolDef then return false end
    if GetMineCount() < toolDef.unlockMineCount then return false end
    if picks_ < toolDef.pickCost then return false end

    picks_ = picks_ - toolDef.pickCost

    -- 十字形: 中心 + 上下左右
    local targets = {
        { centerRow, centerCol },
        { centerRow - 1, centerCol },
        { centerRow + 1, centerCol },
        { centerRow, centerCol - 1 },
        { centerRow, centerCol + 1 },
    }

    for _, pos in ipairs(targets) do
        local r, c = pos[1], pos[2]
        if r >= 1 and r <= rows_ and c >= 1 and c <= cols_ then
            local cell = grid_[r][c]
            if not cell.revealed then
                cell.revealed = true
                cell.hint = nil
                totalRevealed_ = totalRevealed_ + 1

                local oreDef = MC.oreMap[cell.oreId]
                if oreDef and not oreDef.penalty and cell.oreId ~= "empty" then
                    local coins = GameState.coinsPerSecond * oreDef.cpsSeconds
                    GameState.coins = GameState.coins + coins
                    if oreDef.buff then
                        ApplyMineBuff(oreDef.buff)
                    end
                end
                -- 炸药不触发塌方惩罚
            end
        end
    end

    -- 全清检测
    if totalRevealed_ >= totalCells_ then
        boardsCleared_ = boardsCleared_ + 1
        local bonusCoins = GameState.coinsPerSecond * MC.FULL_CLEAR_CPS_SECONDS
        GameState.coins = GameState.coins + bonusCoins
        if onFullClear_ then onFullClear_(bonusCoins) end
    end

    return true
end

--- 手动刷新矿区
---@return boolean success
function MM.ManualRefresh()
    local cost = GameState.coinsPerSecond * MC.MANUAL_REFRESH_CPS_MUL
    if GameState.coins < cost then return false end
    GameState.coins = GameState.coins - cost
    GenerateGrid()
    if onRefresh_ then onRefresh_() end
    return true
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

function MM.Update(dt)
    local mineCount = GetMineCount()
    if mineCount < 1 then return end

    -- 更新最大耐久
    maxPicks_ = MC.GetMaxPicks(mineCount)

    -- 镐头回复
    regenTimer_ = regenTimer_ + dt
    if regenTimer_ >= MC.PICK_REGEN_INTERVAL then
        regenTimer_ = regenTimer_ - MC.PICK_REGEN_INTERVAL
        if picks_ < maxPicks_ then
            picks_ = math.min(picks_ + 1, maxPicks_)
        end
    end

    -- 矿区自动刷新
    refreshTimer_ = refreshTimer_ - dt
    if refreshTimer_ <= 0 then
        GenerateGrid()
        if onRefresh_ then onRefresh_() end
    end
end

-- ============================================================================
-- 存档 / 读档
-- ============================================================================

function MM.GetSaveData()
    -- 序列化网格
    local gridData = {}
    for r = 1, rows_ do
        gridData[r] = {}
        for c = 1, cols_ do
            local cell = grid_[r][c]
            gridData[r][c] = {
                o = cell.oreId,
                r = cell.revealed,
                h = cell.hint,
            }
        end
    end

    return {
        cols = cols_,
        rows = rows_,
        grid = gridData,
        picks = picks_,
        regenTimer = regenTimer_,
        refreshTimer = refreshTimer_,
        streak = streak_,
        totalRevealed = totalRevealed_,
        hasMinecart = hasMinecart_,
        boardsCleared = boardsCleared_,
    }
end

function MM.LoadSaveData(data)
    if not data then return end

    cols_ = data.cols or 5
    rows_ = data.rows or 4
    picks_ = data.picks or 10
    regenTimer_ = data.regenTimer or 0
    refreshTimer_ = data.refreshTimer or MC.REFRESH_INTERVAL
    streak_ = data.streak or 0
    totalRevealed_ = data.totalRevealed or 0
    hasMinecart_ = data.hasMinecart or false
    boardsCleared_ = data.boardsCleared or 0
    totalCells_ = cols_ * rows_

    local mineCount = GetMineCount()
    maxPicks_ = MC.GetMaxPicks(mineCount)

    if data.grid then
        grid_ = {}
        for r = 1, rows_ do
            grid_[r] = {}
            local rowData = data.grid[r]
            for c = 1, cols_ do
                if rowData and rowData[c] then
                    local cd = rowData[c]
                    grid_[r][c] = {
                        oreId = cd.o or "empty",
                        revealed = cd.r or false,
                        hint = cd.h,
                    }
                else
                    grid_[r][c] = { oreId = "empty", revealed = false, hint = nil }
                end
            end
        end
    else
        GenerateGrid()
    end
end

function MM.ResetForAscension()
    MM.Init()
end

--- [调试] 补满镐头
function MM.RefillPicks()
    picks_ = maxPicks_
end

return MM
