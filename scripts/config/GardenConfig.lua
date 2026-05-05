-- ============================================================================
-- config/GardenConfig.lua
-- 项目孵化园配置：种子定义、杂交配方、土壤模式、常量
-- ============================================================================

local GC = {}

-- ---------------------------------------------------------------------------
-- 常量
-- ---------------------------------------------------------------------------
GC.GRID_MIN_SIZE       = 2     -- 起始网格 2x2
GC.GRID_MAX_SIZE       = 6     -- 最大 6x6
GC.GRID_EXPAND_COSTS   = { 5, 10, 20, 50 }  -- 糖块花费：3x3, 4x4, 5x5, 6x6

GC.WILT_TIME           = 600   -- 成熟后多久枯萎（秒）—— 10分钟采收窗口，匹配15-45分钟生长周期
GC.CROSSBREED_TICK     = 120   -- 杂交检查间隔（秒）—— 2分钟，匹配长生长周期
GC.BUG_CHECK_INTERVAL  = 60    -- 罢工检查间隔（秒）
GC.BUG_BASE_CHANCE     = 0.02  -- 罢工基础概率
GC.SOIL_COOLDOWN       = 300   -- 切换土壤冷却（秒）—— 5分钟

-- ---------------------------------------------------------------------------
-- 生长阶段
-- ---------------------------------------------------------------------------
GC.STAGE_EMPTY   = 0
GC.STAGE_SPROUT  = 1   -- 0~25%
GC.STAGE_GROWING = 2   -- 25~50%
GC.STAGE_BLOOM   = 3   -- 50~75%
GC.STAGE_MATURE  = 4   -- 75~100%（可收获）
GC.STAGE_WILTING = 5   -- 超时枯萎中
GC.STAGE_DEAD    = 6   -- 已死亡，需清理

-- ---------------------------------------------------------------------------
-- 土壤/团队模式（3种）
-- ---------------------------------------------------------------------------
GC.soils = {
    {
        id = "normal",
        name = "弹性工作",
        desc = "标准效率，均衡发展",
        growthMul = 1.0,
        wiltMul   = 1.0,
        crossMul  = 1.0,
        yieldMul  = 1.0,
    },
    {
        id = "overtime",
        name = "加班模式",
        desc = "生长x1.5 但枯萎也快x1.5，杂交x0.8",
        growthMul = 1.5,
        wiltMul   = 1.5,
        crossMul  = 0.8,
        yieldMul  = 1.0,
    },
    {
        id = "remote",
        name = "远程办公",
        desc = "生长x0.7 但杂交x1.5，收益x1.2",
        growthMul = 0.7,
        wiltMul   = 0.5,
        crossMul  = 1.5,
        yieldMul  = 1.2,
    },
}

-- ---------------------------------------------------------------------------
-- 基础种子（8种）
-- buffType: "cps"/"cpc"/"buildingCost"/nil
-- buffValue: 乘数值（如 1.08 表示 +8%）
-- buffDuration: buff 持续秒数
-- harvestCpsMul: 收获金币 = CPS × 此值
-- costMul: 种植成本 = CPS × 此值（秒数产出）
-- ---------------------------------------------------------------------------
GC.seeds = {
    {
        id = "app",
        name = "APP开发",
        desc = "开发移动应用，稳定收益",
        growthTime = 900,        -- 15 分钟
        costMul = 60,
        harvestCpsMul = 120,
        buffType = "cps", buffValue = 1.08, buffDuration = 300,
        tier = 1,
    },
    {
        id = "ad",
        name = "广告投放",
        desc = "精准投放，提升点击效率",
        growthTime = 600,        -- 10 分钟
        costMul = 45,
        harvestCpsMul = 90,
        buffType = "cpc", buffValue = 1.05, buffDuration = 300,
        tier = 1,
    },
    {
        id = "data",
        name = "数据分析",
        desc = "数据驱动决策，小幅提升全局",
        growthTime = 1200,       -- 20 分钟
        costMul = 100,
        harvestCpsMul = 180,
        buffType = "cps", buffValue = 1.03, buffDuration = 360,
        tier = 1,
    },
    {
        id = "support",
        name = "客服外包",
        desc = "降低运营成本",
        growthTime = 720,        -- 12 分钟
        costMul = 50,
        harvestCpsMul = 100,
        buffType = "buildingCost", buffValue = 0.95, buffDuration = 300,
        tier = 1,
    },
    {
        id = "brand",
        name = "品牌策划",
        desc = "提升品牌知名度，增加幸运事件",
        growthTime = 1080,       -- 18 分钟
        costMul = 80,
        harvestCpsMul = 150,
        buffType = "cps", buffValue = 1.05, buffDuration = 360,
        tier = 1,
    },
    {
        id = "supply",
        name = "供应链",
        desc = "优化供应效率",
        growthTime = 900,        -- 15 分钟
        costMul = 65,
        harvestCpsMul = 130,
        buffType = "cps", buffValue = 1.06, buffDuration = 300,
        tier = 1,
    },
    {
        id = "legal",
        name = "法务合规",
        desc = "防范风险，减少罢工损失",
        growthTime = 1500,       -- 25 分钟
        costMul = 120,
        harvestCpsMul = 80,
        buffType = nil, buffValue = nil, buffDuration = nil,
        bugImmunity = 180,  -- 收获后风险免疫 180 秒
        tier = 1,
    },
    {
        id = "hr",
        name = "人力招聘",
        desc = "引进人才，提升产能",
        growthTime = 1020,       -- 17 分钟
        costMul = 70,
        harvestCpsMul = 140,
        buffType = "cps", buffValue = 1.08, buffDuration = 300,
        tier = 1,
    },
}

-- ---------------------------------------------------------------------------
-- 杂交种子（12种）
-- parents: 两个父本种子 id
-- mutationChance: 每次杂交检查的成功概率
-- ---------------------------------------------------------------------------
GC.advancedSeeds = {
    {
        id = "adPlatform",
        name = "广告变现平台",
        desc = "APP+广告的完美结合",
        parents = { "app", "ad" },
        mutationChance = 0.08,
        growthTime = 1500,       -- 25 分钟
        costMul = 150,
        harvestCpsMul = 300,
        buffType = "cps", buffValue = 1.20, buffDuration = 420,
        tier = 2,
    },
    {
        id = "aiRecommend",
        name = "AI推荐系统",
        desc = "数据+APP的智能推荐",
        parents = { "app", "data" },
        mutationChance = 0.07,
        growthTime = 1800,       -- 30 分钟
        costMul = 200,
        harvestCpsMul = 400,
        buffType = "cpc", buffValue = 1.15, buffDuration = 420,
        tier = 2,
    },
    {
        id = "fullMarketing",
        name = "全域营销",
        desc = "广告+品牌的全面覆盖",
        parents = { "ad", "brand" },
        mutationChance = 0.06,
        growthTime = 1680,       -- 28 分钟
        costMul = 180,
        harvestCpsMul = 360,
        buffType = "cps", buffValue = 1.15, buffDuration = 480,
        tier = 2,
    },
    {
        id = "smartLogistics",
        name = "智慧物流",
        desc = "数据+供应链的深度优化",
        parents = { "data", "supply" },
        mutationChance = 0.06,
        growthTime = 1800,       -- 30 分钟
        costMul = 220,
        harvestCpsMul = 450,
        buffType = "cps", buffValue = 1.15, buffDuration = 420,
        tier = 2,
    },
    {
        id = "autoSupport",
        name = "智能客服",
        desc = "APP+客服的自动化方案",
        parents = { "support", "app" },
        mutationChance = 0.07,
        growthTime = 1380,       -- 23 分钟
        costMul = 140,
        harvestCpsMul = 280,
        buffType = "buildingCost", buffValue = 0.88, buffDuration = 420,
        tier = 2,
    },
    {
        id = "employerBrand",
        name = "雇主品牌",
        desc = "品牌+人力的雇主吸引力",
        parents = { "brand", "hr" },
        mutationChance = 0.06,
        growthTime = 1680,       -- 28 分钟
        costMul = 200,
        harvestCpsMul = 380,
        buffType = "cps", buffValue = 1.18, buffDuration = 480,
        tier = 2,
    },
    {
        id = "riskControl",
        name = "风控系统",
        desc = "法务+数据的风险管控",
        parents = { "legal", "data" },
        mutationChance = 0.05,
        growthTime = 2100,       -- 35 分钟
        costMul = 250,
        harvestCpsMul = 300,
        buffType = "cps", buffValue = 1.10, buffDuration = 420,
        bugImmunity = 300,
        tier = 2,
    },
    {
        id = "afterSales",
        name = "售后体系",
        desc = "供应链+客服的完整售后",
        parents = { "supply", "support" },
        mutationChance = 0.06,
        growthTime = 1380,       -- 23 分钟
        costMul = 160,
        harvestCpsMul = 320,
        buffType = "cps", buffValue = 1.12, buffDuration = 420,
        tier = 2,
    },
    {
        id = "recruitPlatform",
        name = "招聘平台",
        desc = "人力+APP的平台效应",
        parents = { "hr", "app" },
        mutationChance = 0.05,
        growthTime = 2400,       -- 40 分钟
        costMul = 300,
        harvestCpsMul = 500,
        buffType = "cps", buffValue = 1.10, buffDuration = 420,
        permanent = "grid",  -- 永久：解锁 1 个额外格子
        tier = 2,
    },
    {
        id = "precisionAd",
        name = "精准营销",
        desc = "广告+数据的精准触达",
        parents = { "ad", "data" },
        mutationChance = 0.05,
        growthTime = 1800,       -- 30 分钟
        costMul = 200,
        harvestCpsMul = 380,
        buffType = "cps", buffValue = 1.25, buffDuration = 360,
        tier = 2,
    },
    {
        id = "ipRights",
        name = "知识产权",
        desc = "品牌+法务的知产保护",
        parents = { "brand", "legal" },
        mutationChance = 0.04,
        growthTime = 2700,       -- 45 分钟
        costMul = 350,
        harvestCpsMul = 600,
        buffType = "cps", buffValue = 1.30, buffDuration = 300,
        tier = 2,
    },
    {
        id = "traineeProgram",
        name = "管培生计划",
        desc = "供应链+人力的人才培养",
        parents = { "supply", "hr" },
        mutationChance = 0.06,
        growthTime = 1380,       -- 23 分钟
        costMul = 130,
        harvestCpsMul = 250,
        buffType = "cps", buffValue = 1.08, buffDuration = 420,
        soilBonus = "growthSpeed",  -- 收获后临时加速生长 30%
        tier = 2,
    },
}

-- ---------------------------------------------------------------------------
-- 工具函数
-- ---------------------------------------------------------------------------

--- 按 id 查找种子定义（基础+杂交）
---@param seedId string
---@return table|nil
function GC.FindSeed(seedId)
    for _, s in ipairs(GC.seeds) do
        if s.id == seedId then return s end
    end
    for _, s in ipairs(GC.advancedSeeds) do
        if s.id == seedId then return s end
    end
    return nil
end

--- 按 id 查找土壤定义
---@param soilId string
---@return table|nil
function GC.FindSoil(soilId)
    for _, s in ipairs(GC.soils) do
        if s.id == soilId then return s end
    end
    return nil
end

--- 给定两个父本 id，返回所有可能的杂交后代
---@param idA string
---@param idB string
---@return table[] 匹配的高级种子列表
function GC.GetPossibleOffspring(idA, idB)
    local results = {}
    for _, adv in ipairs(GC.advancedSeeds) do
        local p = adv.parents
        if (p[1] == idA and p[2] == idB) or (p[1] == idB and p[2] == idA) then
            results[#results + 1] = adv
        end
    end
    return results
end

--- 获取扩展到指定尺寸的糖块花费
---@param targetSize number 3~6
---@return number|nil
function GC.GetExpandCost(targetSize)
    local idx = targetSize - GC.GRID_MIN_SIZE
    if idx >= 1 and idx <= #GC.GRID_EXPAND_COSTS then
        return GC.GRID_EXPAND_COSTS[idx]
    end
    return nil
end

--- 根据生长比例返回阶段
---@param fraction number 0.0~1.0+
---@return number GC.STAGE_*
function GC.GetStageFromFraction(fraction)
    if fraction >= 1.0 then return GC.STAGE_MATURE end
    if fraction >= 0.75 then return GC.STAGE_BLOOM end
    if fraction >= 0.25 then return GC.STAGE_GROWING end
    return GC.STAGE_SPROUT
end

--- 获取所有种子总数（图鉴用）
---@return number
function GC.GetTotalSeedCount()
    return #GC.seeds + #GC.advancedSeeds
end

return GC
