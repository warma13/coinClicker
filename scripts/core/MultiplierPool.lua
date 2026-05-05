-- ============================================================================
-- core/MultiplierPool.lua
-- 倍率池：统一管理加算/乘算叠加，防止连乘膨胀
--
-- 用法:
--   local pool = MultiplierPool.New()
--   pool:Add(SomeManager.GetBonus())      -- 加算：传入 1+x 格式，提取 x 加入池
--   pool:AddRaw(0.15)                     -- 加算：直接传入百分比值（不带 1+）
--   pool:Mul(DragonManager.GetProdMul())  -- 乘算：独立机制，保持乘法
--   local final = pool:Result()           -- 最终 = max(0.01, 1+加算总和) × 乘算总积
-- ============================================================================

local MultiplierPool = {}

local MT = {}
MT.__index = MT

--- 创建新的倍率池
---@return table pool
function MultiplierPool.New()
    return setmetatable({
        _add = 0,   -- 加算池（百分比加成总和）
        _mul = 1,   -- 乘算池（特殊倍率连乘）
    }, MT)
end

--- 加算：传入 1+x 格式的倍率，提取 x 部分加入池
--- 适用于大多数子系统返回的 "1 + bonus%" 格式
---@param value number 形如 1.5 表示 +50%
function MT:Add(value)
    self._add = self._add + (value - 1)
end

--- 加算：直接传入百分比数值（不带 1+）
--- 适用于已经是纯百分比的返回值
---@param value number 形如 0.15 表示 +15%
function MT:AddRaw(value)
    self._add = self._add + value
end

--- 乘算：保持乘法叠加（仅用于独立机制的大倍率）
--- 适用于固定 ×2、×3 等不应加算的特殊倍率
---@param value number 形如 2.0 表示 ×2
function MT:Mul(value)
    self._mul = self._mul * value
end

--- 获取最终合并倍率
--- 公式: max(floor, 1 + 加算总和) × 乘算总积
---@param floor number|nil 下限，默认 0.01（防止变为 0 或负数）
---@return number
function MT:Result(floor)
    floor = floor or 0.01
    return math.max(floor, 1 + self._add) * self._mul
end

--- 获取加算池当前值（调试用）
---@return number
function MT:GetAdditiveSum()
    return self._add
end

--- 获取乘算池当前值（调试用）
---@return number
function MT:GetMultiplicativeProduct()
    return self._mul
end

return MultiplierPool
