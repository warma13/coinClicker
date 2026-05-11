-- ============================================================================
-- ui/DebugPanel.lua
-- 测试账号调试面板：仅白名单账号可见，提供快捷调试操作
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")
local SlotSaveSystem = require("core.SlotSaveSystem")
local MiningManager = require("core.MiningManager")
local GardenManager = require("core.GardenManager")
local GrimoireManager = require("core.GrimoireManager")
local StockMarketManager = require("core.StockMarketManager")
local PantheonManager = require("core.PantheonManager")
local FactoryManager = require("core.FactoryManager")
local ShipmentManager = require("core.ShipmentManager")
local ECommerceManager = require("core.ECommerceManager")
local SugarLumpManager = require("core.SugarLumpManager")
local InventoryManager = require("core.InventoryManager")
local ItemDefs = require("config.ItemDefs")
local SD = require("config.SugarLumpDefs")
local DragonManager = require("core.DragonManager")
local AntiCheatManager = require("core.AntiCheatManager")
local AdManager = require("core.AdManager")
local SkillManager = require("core.SkillManager")
local SkillDefs = require("config.SkillDefs")

-- 面板引用（延迟设置，用于重置后刷新）
local panelRefs_ = {}

local DP = {}

--- 设置面板引用（由 main.lua 在 Init 后调用）
function DP.SetPanelRefs(refs)
    panelRefs_ = refs or {}
end

-- ======== 测试账号白名单 ========
local TEST_ACCOUNTS = {
    ["413248871"] = true,
    -- 添加更多测试账号：
    -- ["12345678"] = true,
}

-- ======== 状态 ========
local uiRoot_    = nil
local overlay_   = nil
local btnWidget_ = nil
local isOpen_    = false
local manager_   = nil   -- GameManager 引用
local isTestAccount_ = false

-- ============================================================================
-- 工具
-- ============================================================================

--- 检查当前用户是否为测试账号
---@return boolean
function DP.IsTestAccount()
    return isTestAccount_
end

--- 通知面板刷新（重置后）
local function RefreshPanel(name)
    local p = panelRefs_[name]
    if p and p.IsVisible and p:IsVisible() then
        if p.Refresh then p.Refresh() end
    end
end

--- 创建一个调试按钮
---@param text string
---@param color table
---@param onClick function
local function MakeBtn(text, color, onClick)
    return UI.Panel {
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 5, paddingBottom = 5,
        borderRadius = 4,
        backgroundColor = { color[1], color[2], color[3], 60 },
        borderWidth = 1,
        borderColor = { color[1], color[2], color[3], 150 },
        pointerEvents = "auto",
        onPointerDown = function(self, event)
            if event and event.stopPropagation then event:stopPropagation() end
            onClick()
        end,
        children = {
            UI.Label {
                text = text,
                fontSize = 10,
                fontColor = { color[1], color[2], color[3], 255 },
            },
        },
    }
end

-- ============================================================================
-- UI 辅助
-- ============================================================================

--- 创建分区标题
local function SectionTitle(text)
    return UI.Label { text = text, fontSize = 11, fontColor = { 180, 220, 180, 255 } }
end

--- 创建分隔线
local function Divider()
    return UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 80, 60, 80 } }
end

--- 创建按钮行
local function BtnRow(btns)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 6,
        children = btns,
    }
end

--- 创建状态文本
local function InfoLabel(text)
    return UI.Label { text = text, fontSize = 10, fontColor = { 160, 160, 180, 200 } }
end

-- ============================================================================
-- 弹窗
-- ============================================================================

function DP.CloseModal()
    if not isOpen_ then return end
    isOpen_ = false
    if overlay_ and uiRoot_ then
        uiRoot_:RemoveChild(overlay_)
    end
    overlay_ = nil
end

function DP.OpenModal()
    if isOpen_ then return end
    if not uiRoot_ then return end
    isOpen_ = true

    -- ===== 构建小游戏调试区块 =====

    -- 1) 采矿场
    local miningSection = UI.Panel {
        width = "100%", flexDirection = "column", gap = 6,
        children = {
            SectionTitle("采矿场"),
            InfoLabel("镐: " .. MiningManager.GetPicks() .. "/" .. MiningManager.GetMaxPicks()
                .. "  连击: " .. MiningManager.GetStreak()),
            BtnRow({
                MakeBtn("补满镐", { 200, 180, 100 }, function()
                    MiningManager.RefillPicks()
                end),
                MakeBtn("重置矿场", { 220, 160, 80 }, function()
                    MiningManager.Init()
                    local mp = panelRefs_.mining
                    if mp then
                        mp.ForceRebuild()
                    end
                end),
            }),
        },
    }

    -- 2) 种植园
    local gardenSection = UI.Panel {
        width = "100%", flexDirection = "column", gap = 6,
        children = {
            SectionTitle("种植园"),
            BtnRow({
                MakeBtn("全部催熟", { 120, 220, 80 }, function()
                    local grid = GardenManager.GetGrid()
                    if grid then
                        for r = 1, #grid do
                            for c = 1, #grid[r] do
                                local plot = GardenManager.GetPlot(r, c)
                                if plot and plot.seedId and plot.seedId ~= "" then
                                    plot.stage = 3
                                    plot.elapsed = 99999
                                end
                            end
                        end
                    end
                end),
                MakeBtn("扩展格子", { 100, 200, 255 }, function()
                    GardenManager.ExpandGrid()
                end),
                MakeBtn("重置", { 220, 80, 80 }, function()
                    GardenManager.Init()
                end),
            }),
        },
    }

    -- 3) 研发中心 (Grimoire)
    local grimoireSection = UI.Panel {
        width = "100%", flexDirection = "column", gap = 6,
        children = {
            SectionTitle("研发中心"),
            InfoLabel("魔力: " .. math.floor(GrimoireManager.GetCurrentMana())
                .. "/" .. math.floor(GrimoireManager.GetMaxMana())
                .. "  CD: " .. string.format("%.1f", GrimoireManager.GetGlobalCooldown()) .. "s"),
            BtnRow({
                MakeBtn("补满魔力", { 150, 120, 255 }, function()
                    GrimoireManager.RefillMana()
                end),
                MakeBtn("清除CD", { 200, 180, 100 }, function()
                    GrimoireManager.ClearCooldown()
                end),
                MakeBtn("清Buff", { 220, 80, 80 }, function()
                    GrimoireManager.ClearBuffs()
                end),
            }),
        },
    }

    -- 4) 证券交易所 (Stock Market)
    local stockSection = UI.Panel {
        width = "100%", flexDirection = "column", gap = 6,
        children = {
            SectionTitle("证券交易所"),
            InfoLabel("总利润: " .. GameState.FormatNumber(StockMarketManager.GetTotalProfit())),
            BtnRow({
                MakeBtn("重置", { 220, 80, 80 }, function()
                    StockMarketManager.Init()
                end),
            }),
        },
    }

    -- 5) 商业地产 (Pantheon)
    local pantheonSection = UI.Panel {
        width = "100%", flexDirection = "column", gap = 6,
        children = {
            SectionTitle("商业地产"),
            InfoLabel("可用槽位: " .. PantheonManager.GetAvailableSlots()),
            BtnRow({
                MakeBtn("清除冷却", { 200, 180, 100 }, function()
                    PantheonManager.ClearCooldowns()
                end),
                MakeBtn("重置", { 220, 80, 80 }, function()
                    PantheonManager.Init()
                end),
            }),
        },
    }

    -- 6) 制造工厂 (Factory)
    local factorySection = UI.Panel {
        width = "100%", flexDirection = "column", gap = 6,
        children = {
            SectionTitle("制造工厂"),
            InfoLabel("连击: " .. FactoryManager.GetStreak()),
            BtnRow({
                MakeBtn("完成生产", { 100, 220, 160 }, function()
                    local prods = FactoryManager.GetProductions()
                    local count = 0
                    if prods then
                        for i = 1, #prods do
                            local p = prods[i]
                            if p and p.state == "producing" then
                                p.elapsed = p.productionTime
                                p.state = "done"
                                count = count + 1
                            end
                        end
                    end
                end),
                MakeBtn("重置", { 220, 80, 80 }, function()
                    FactoryManager.Init()
                end),
            }),
        },
    }

    -- 7) 国际物流 (Shipment)
    local shipmentSection = UI.Panel {
        width = "100%", flexDirection = "column", gap = 6,
        children = {
            SectionTitle("国际物流"),
            InfoLabel("安全连击: " .. ShipmentManager.GetSafeStreak()),
            BtnRow({
                MakeBtn("全部到达", { 100, 220, 160 }, function()
                    local transit = ShipmentManager.GetInTransit()
                    local count = 0
                    if transit then
                        for i = 1, #transit do
                            local c = transit[i]
                            if c then
                                c.elapsed = c.travelTime
                                count = count + 1
                            end
                        end
                    end
                end),
                MakeBtn("重置", { 220, 80, 80 }, function()
                    ShipmentManager.Init()
                end),
            }),
        },
    }

    -- 8) 电商平台 (ECommerce)
    local ecomSection = UI.Panel {
        width = "100%", flexDirection = "column", gap = 6,
        children = {
            SectionTitle("电商平台"),
            InfoLabel("连击: " .. ECommerceManager.GetStreak()
                .. "  已售: " .. ECommerceManager.GetTotalSold()),
            BtnRow({
                MakeBtn("秒杀完成", { 100, 220, 160 }, function()
                    local products = ECommerceManager.GetProducts()
                    local count = 0
                    if products then
                        for i = 1, #products do
                            local p = products[i]
                            if p and p.state == "invested" then
                                p.elapsed = p.saleTime
                                count = count + 1
                            end
                        end
                    end
                end),
                MakeBtn("重置", { 220, 80, 80 }, function()
                    ECommerceManager.Init()
                end),
            }),
        },
    }

    -- 9) 人脉系统 (SugarLump)
    local lumpStage = SugarLumpManager.GetStage()
    local lumpStageName = SD.stageNames[lumpStage] or "未知"
    local lumpType = SugarLumpManager.GetCurrentType()
    local lumpTypeName = lumpType and lumpType.name or "无"
    local sugarSection = UI.Panel {
        width = "100%", flexDirection = "column", gap = 6,
        children = {
            SectionTitle("人脉系统"),
            InfoLabel("持有: " .. SugarLumpManager.GetLumps()
                .. "  累计: " .. SugarLumpManager.GetTotalHarvested()
                .. "  阶段: " .. lumpStageName
                .. "  类型: " .. lumpTypeName),
            BtnRow({
                MakeBtn("+10人脉", { 255, 215, 0 }, function()
                    SugarLumpManager.AddLumps(10)
                end),
                MakeBtn("+50人脉", { 255, 215, 0 }, function()
                    SugarLumpManager.AddLumps(50)
                end),
                MakeBtn("立即成熟", { 120, 220, 80 }, function()
                    SugarLumpManager.DebugMature()
                end),
                MakeBtn("重置", { 220, 80, 80 }, function()
                    SugarLumpManager.Init()
                end),
            }),
        },
    }

    -- ===== 仓库调试 =====
    local usedSlots = InventoryManager.GetUsedSlotCount()
    local totalSlots = InventoryManager.GetSlotCount()
    -- 构建道具添加按钮（每个道具一个按钮）
    local addItemBtns = {}
    for _, item in ipairs(ItemDefs.ITEMS) do
        addItemBtns[#addItemBtns + 1] = MakeBtn("+" .. item.abbr, { 255, 220, 80 }, function()
            local ok, reason = InventoryManager.AddItem(item.id, 1)
            if ok then
                print("[Debug] 添加道具: " .. item.name)
            else
                print("[Debug] 添加失败: " .. (reason or "unknown"))
            end
        end)
    end
    local inventorySection = UI.Panel {
        width = "100%", flexDirection = "column", gap = 6,
        children = {
            SectionTitle("仓库"),
            InfoLabel("已用: " .. usedSlots .. "/" .. totalSlots),
            BtnRow(addItemBtns),
            BtnRow({
                MakeBtn("填满仓库", { 100, 200, 255 }, function()
                    for _, item in ipairs(ItemDefs.ITEMS) do
                        InventoryManager.AddItem(item.id, item.maxStack or 1)
                    end
                    print("[Debug] 仓库已填满")
                end),
                MakeBtn("清空仓库", { 220, 80, 80 }, function()
                    for i = 1, InventoryManager.GetSlotCount() do
                        InventoryManager.RemoveItem(i, 9999)
                    end
                    print("[Debug] 仓库已清空")
                end),
            }),
        },
    }

    -- ===== 构建弹窗 =====
    overlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = "100%", height = "100%",
        zIndex = 300,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        pointerEvents = "auto",
        onPointerDown = function()
            DP.CloseModal()
        end,
        children = {
            UI.Panel {
                width = 340,
                maxHeight = "85%",
                flexDirection = "column",
                backgroundColor = { 20, 25, 35, 250 },
                borderRadius = 10,
                borderColor = { 100, 200, 100, 100 },
                borderWidth = 1,
                pointerEvents = "auto",
                onPointerDown = function(self, event)
                    if event and event.stopPropagation then event:stopPropagation() end
                end,
                children = {
                    -- 标题栏（固定在顶部）
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        paddingTop = 12, paddingBottom = 8,
                        paddingLeft = 16, paddingRight = 16,
                        children = {
                            UI.Label {
                                text = "调试面板",
                                fontSize = 15,
                                fontColor = { 100, 255, 100, 255 },
                                fontWeight = "bold",
                            },
                            UI.Panel {
                                paddingLeft = 8, paddingRight = 8,
                                paddingTop = 3, paddingBottom = 3,
                                borderRadius = 4,
                                backgroundColor = { 60, 50, 50, 180 },
                                pointerEvents = "auto",
                                onPointerDown = function()
                                    DP.CloseModal()
                                end,
                                children = {
                                    UI.Label { text = "✕", fontSize = 13,
                                        fontColor = { 200, 200, 200, 220 } },
                                },
                            },
                        },
                    },
                    -- 可滚动内容区
                    UI.ScrollView {
                        width = "100%",
                        flex = 1,
                        children = {
                            UI.Panel {
                                width = "100%",
                                flexDirection = "column",
                                gap = 10,
                                paddingLeft = 16, paddingRight = 16,
                                paddingBottom = 14,
                                children = {
                                    -- 账号信息
                                    InfoLabel("ID: " .. tostring(clientCloud and clientCloud.userId or "N/A")),
                                    Divider(),

                                    -- 金币操作
                                    SectionTitle("金币操作"),
                                    BtnRow({
                                        MakeBtn("+1K", { 255, 220, 80 }, function()
                                            GameState.coins = GameState.coins + 1e3
                                        end),
                                        MakeBtn("+1M", { 255, 220, 80 }, function()
                                            GameState.coins = GameState.coins + 1e6
                                        end),
                                        MakeBtn("+1B", { 255, 220, 80 }, function()
                                            GameState.coins = GameState.coins + 1e9
                                        end),
                                        MakeBtn("+1T", { 255, 220, 80 }, function()
                                            GameState.coins = GameState.coins + 1e12
                                        end),
                                        MakeBtn("+1Qa", { 255, 220, 80 }, function()
                                            GameState.coins = GameState.coins + 1e15
                                        end),
                                        MakeBtn("清零", { 220, 80, 80 }, function()
                                            GameState.coins = 0
                                        end),
                                    }),

                                    -- CPS 调试
                                    SectionTitle("CPS 调试"),
                                    BtnRow({
                                        MakeBtn("x10", { 100, 200, 255 }, function()
                                            GameState.coinsPerSecond = GameState.coinsPerSecond * 10
                                        end),
                                        MakeBtn("x100", { 100, 200, 255 }, function()
                                            GameState.coinsPerSecond = GameState.coinsPerSecond * 100
                                        end),
                                        MakeBtn("/10", { 200, 160, 100 }, function()
                                            GameState.coinsPerSecond = math.max(1, GameState.coinsPerSecond / 10)
                                        end),
                                    }),

                                    -- 存档操作
                                    SectionTitle("存档操作"),
                                    BtnRow({
                                        MakeBtn("立即保存", { 120, 220, 120 }, function()
                                            SlotSaveSystem.SaveNow()
                                        end),
                                        MakeBtn("标记脏数据", { 200, 180, 100 }, function()
                                            SlotSaveSystem.MarkDirty()
                                        end),
                                    }),

                                    Divider(),

                                    -- ===== 小游戏调试 =====
                                    UI.Label { text = "小游戏调试", fontSize = 13,
                                        fontColor = { 100, 220, 255, 255 }, fontWeight = "bold" },

                                    miningSection,
                                    gardenSection,
                                    grimoireSection,
                                    stockSection,
                                    pantheonSection,
                                    factorySection,
                                    shipmentSection,
                                    ecomSection,
                                    sugarSection,
                                    inventorySection,

                                    -- 10) 技能系统
                                    (function()
                                        local S = GameState
                                        local staminaText = "体力: " .. math.floor(S.stamina) .. "/" .. S.staminaMax
                                            .. "  恢复: " .. string.format("%.2f", S.staminaRegenRate) .. "/s"
                                        -- 构建每个技能的状态行和按钮
                                        local skillChildren = {
                                            SectionTitle("技能系统"),
                                            InfoLabel(staminaText),
                                            BtnRow({
                                                MakeBtn("体力+100", { 100, 200, 255 }, function()
                                                    S.stamina = math.min(S.staminaMax, S.stamina + 100)
                                                    DP.CloseModal(); DP.OpenModal()
                                                end),
                                                MakeBtn("体力满", { 100, 200, 255 }, function()
                                                    S.stamina = S.staminaMax
                                                    DP.CloseModal(); DP.OpenModal()
                                                end),
                                                MakeBtn("体力清零", { 220, 80, 80 }, function()
                                                    S.stamina = 0
                                                    DP.CloseModal(); DP.OpenModal()
                                                end),
                                            }),
                                        }
                                        for _, def in ipairs(SkillDefs.list) do
                                            local info = SkillManager.GetSkillInfo(def.id)
                                            if info then
                                                local statusParts = {}
                                                statusParts[#statusParts + 1] = def.name
                                                statusParts[#statusParts + 1] = " Lv." .. info.level .. "/" .. info.maxLevel
                                                if info.active then
                                                    statusParts[#statusParts + 1] = "  [激活中 " .. string.format("%.0f", info.timer) .. "s]"
                                                end
                                                local staCost = SkillDefs.GetStaminaCost(def, info.level)
                                                statusParts[#statusParts + 1] = "  体力:" .. staCost
                                                skillChildren[#skillChildren + 1] = InfoLabel(table.concat(statusParts))
                                                -- 按钮行
                                                local btns = {}
                                                if not def.instant then
                                                    btns[#btns + 1] = MakeBtn("激活30m", { 120, 220, 80 }, function()
                                                        SkillManager.AddSkillTime(def.id, 1800)
                                                        DP.CloseModal(); DP.OpenModal()
                                                    end)
                                                    btns[#btns + 1] = MakeBtn("+5m", { 100, 200, 255 }, function()
                                                        SkillManager.AddSkillTime(def.id, 300)
                                                        DP.CloseModal(); DP.OpenModal()
                                                    end)
                                                    if info.active then
                                                        btns[#btns + 1] = MakeBtn("停止", { 220, 160, 80 }, function()
                                                            local st = S.skills[def.id]
                                                            if st then st.active = false; st.timer = 0 end
                                                            DP.CloseModal(); DP.OpenModal()
                                                        end)
                                                    end
                                                else
                                                    btns[#btns + 1] = MakeBtn("触发", { 120, 220, 80 }, function()
                                                        if def.id == "randomBuildings" then
                                                            local r = SkillManager.ExecuteRandomBuildings(info.level)
                                                            local names = {}
                                                            for _, b in ipairs(r.buildings) do names[#names + 1] = b.name end
                                                            print("[Debug] 随机扩张: " .. table.concat(names, ", "))
                                                        elseif def.id == "cpsHarvest" then
                                                            local r = SkillManager.ExecuteCpsHarvest(info.level)
                                                            print("[Debug] 立即收割: " .. GameState.FormatNumber(r.coins))
                                                        end
                                                        DP.CloseModal(); DP.OpenModal()
                                                    end)
                                                end
                                                if info.level < info.maxLevel then
                                                    btns[#btns + 1] = MakeBtn("升级", { 200, 180, 100 }, function()
                                                        SkillManager.UpgradeSkill(def.id)
                                                        DP.CloseModal(); DP.OpenModal()
                                                    end)
                                                end
                                                btns[#btns + 1] = MakeBtn("满级", { 200, 160, 255 }, function()
                                                    local st = S.skills[def.id]
                                                    if st then st.level = def.maxLevel end
                                                    DP.CloseModal(); DP.OpenModal()
                                                end)
                                                skillChildren[#skillChildren + 1] = BtnRow(btns)
                                            end
                                        end
                                        -- 全局操作
                                        skillChildren[#skillChildren + 1] = BtnRow({
                                            MakeBtn("全部激活30m", { 120, 220, 80 }, function()
                                                for _, d in ipairs(SkillDefs.list) do
                                                    if not d.instant then
                                                        SkillManager.AddSkillTime(d.id, 1800)
                                                    end
                                                end
                                                DP.CloseModal(); DP.OpenModal()
                                            end),
                                            MakeBtn("全部停止", { 220, 160, 80 }, function()
                                                for _, d in ipairs(SkillDefs.list) do
                                                    local st = S.skills[d.id]
                                                    if st then st.active = false; st.timer = 0 end
                                                end
                                                DP.CloseModal(); DP.OpenModal()
                                            end),
                                            MakeBtn("全部满级", { 200, 160, 255 }, function()
                                                for _, d in ipairs(SkillDefs.list) do
                                                    local st = S.skills[d.id]
                                                    if st then st.level = d.maxLevel end
                                                end
                                                DP.CloseModal(); DP.OpenModal()
                                            end),
                                            MakeBtn("重置等级", { 220, 80, 80 }, function()
                                                for _, d in ipairs(SkillDefs.list) do
                                                    local st = S.skills[d.id]
                                                    if st then st.level = 1; st.active = false; st.timer = 0 end
                                                end
                                                DP.CloseModal(); DP.OpenModal()
                                            end),
                                        })
                                        return UI.Panel {
                                            width = "100%", flexDirection = "column", gap = 6,
                                            children = skillChildren,
                                        }
                                    end)(),

                                    -- 11) AI合伙人
                                    (function()
                                        local lv = DragonManager.GetLevel()
                                        local xp = DragonManager.GetCurrentXP and DragonManager.GetCurrentXP() or 0
                                        local tp = DragonManager.GetTalentPoints and DragonManager.GetTalentPoints() or 0
                                        local used = DragonManager.GetUsedTalentPoints and DragonManager.GetUsedTalentPoints() or 0
                                        return UI.Panel {
                                            width = "100%", flexDirection = "column", gap = 6,
                                            children = {
                                                SectionTitle("AI合伙人"),
                                                InfoLabel("等级: " .. lv .. "  XP: " .. math.floor(xp)
                                                    .. "  天赋点: " .. tp .. " (已用" .. used .. ")"),
                                                BtnRow({
                                                    MakeBtn("+1000 XP", { 100, 200, 255 }, function()
                                                        if DragonManager.AddXP then
                                                            DragonManager.AddXP(1000)
                                                        end
                                                    end),
                                                    MakeBtn("+10000 XP", { 100, 200, 255 }, function()
                                                        if DragonManager.AddXP then
                                                            DragonManager.AddXP(10000)
                                                        end
                                                    end),
                                                    MakeBtn("重置AI", { 220, 80, 80 }, function()
                                                        DragonManager.Init()
                                                        print("[Debug] AI合伙人已重置")
                                                    end),
                                                }),
                                            },
                                        }
                                    end)(),

                                    -- 12) 反作弊
                                    (function()
                                        local inited = AntiCheatManager.IsInitialized()
                                        local level  = AntiCheatManager.GetCheatLevel()
                                        local slotId = SlotSaveSystem.GetSlotId()
                                        local statusText  = "未初始化"
                                        local statusColor = { 160, 160, 160, 200 }
                                        if inited then
                                            if level == 1 then
                                                statusText  = "已警告一次"
                                                statusColor = { 255, 200, 60, 255 }
                                            else
                                                statusText  = "正常"
                                                statusColor = { 100, 255, 100, 255 }
                                            end
                                        end
                                        return UI.Panel {
                                            width = "100%", flexDirection = "column", gap = 6,
                                            children = {
                                                SectionTitle("反作弊"),
                                                InfoLabel("槽位: " .. slotId .. "  |  等级: " .. level .. " (0=正常 1=已警告)"),
                                                UI.Label {
                                                    text = statusText,
                                                    fontSize = 10,
                                                    fontColor = statusColor,
                                                    fontWeight = "bold",
                                                },
                                                BtnRow({
                                                    MakeBtn("模拟作弊", { 255, 160, 60 }, function()
                                                        AntiCheatManager.DebugTrigger()
                                                        print("[Debug] 模拟触发作弊检测")
                                                    end),
                                                    MakeBtn("重置正常", { 100, 220, 100 }, function()
                                                        AntiCheatManager.DebugReset()
                                                        print("[Debug] 反作弊状态已重置")
                                                    end),
                                                }),
                                            },
                                        }
                                    end)(),

                                    -- 13) 广告系统
                                    (function()
                                        local todayCount = AdManager.GetTodayCount()
                                        local totalCount = AdManager.GetTotalCount()
                                        local remaining  = AdManager.GetRemainingToday()
                                        local cardLv, cardIdx, cardNext, cardActive = AdManager.GetCardLevel()
                                        local cardPts = AdManager.GetCardPoints()
                                        local dailyGiven = AdManager.IsCardDailyGiven()
                                        local earnedToday = AdManager.IsCardPointEarnedToday()
                                        local activeTxt = cardActive and "" or "[未激活] "
                                        local cpcTxt = (cardLv.cpcMul and cardLv.cpcMul > 0) and (" 点击+" .. math.floor(cardLv.cpcMul * 100) .. "%") or ""
                                        local statusText = "剩余 " .. remaining .. " 次  特权卡: " .. activeTxt .. cardLv.name .. "(Lv" .. cardIdx .. " CPS+" .. math.floor(cardLv.cpsMul * 100) .. "%" .. cpcTxt .. ")"
                                        local cardInfo = "点数: " .. cardPts
                                            .. (not cardActive and ("/" .. cardLv.points .. " → 激活" .. cardLv.name)
                                               or cardNext and ("/" .. cardNext.points .. " → " .. cardNext.name) or " (满级)")
                                            .. "  今日点: " .. (earnedToday and "已得" or "未得")
                                            .. "  福利: " .. (dailyGiven and "已发" or "未发")
                                        return UI.Panel {
                                            width = "100%", flexDirection = "column", gap = 6,
                                            children = {
                                                SectionTitle("广告系统"),
                                                InfoLabel("今日: " .. todayCount .. "  累计: " .. totalCount),
                                                InfoLabel(statusText),
                                                BtnRow({
                                                    MakeBtn("+1次", { 100, 200, 255 }, function()
                                                        AdManager.DebugAddCount(1)
                                                        DP.CloseModal()
                                                        DP.OpenModal()
                                                    end),
                                                    MakeBtn("+5次", { 100, 200, 255 }, function()
                                                        AdManager.DebugAddCount(5)
                                                        DP.CloseModal()
                                                        DP.OpenModal()
                                                    end),
                                                    MakeBtn("+20次", { 100, 200, 255 }, function()
                                                        AdManager.DebugAddCount(20)
                                                        DP.CloseModal()
                                                        DP.OpenModal()
                                                    end),
                                                }),
                                                BtnRow({
                                                    MakeBtn("领取全部", { 120, 220, 80 }, function()
                                                        local n = AdManager.DebugClaimAll()
                                                        print("[Debug] 领取了 " .. n .. " 个里程碑")
                                                        DP.CloseModal()
                                                        DP.OpenModal()
                                                    end),
                                                    MakeBtn("重置今日", { 220, 80, 80 }, function()
                                                        AdManager.DebugResetToday()
                                                        DP.CloseModal()
                                                        DP.OpenModal()
                                                    end),
                                                }),
                                                Divider(),
                                                SectionTitle("特权卡"),
                                                InfoLabel(cardInfo),
                                                BtnRow({
                                                    MakeBtn("+1点", { 200, 160, 255 }, function()
                                                        AdManager.DebugAddCardPoints(1)
                                                        DP.CloseModal()
                                                        DP.OpenModal()
                                                    end),
                                                    MakeBtn("+5点", { 200, 160, 255 }, function()
                                                        AdManager.DebugAddCardPoints(5)
                                                        DP.CloseModal()
                                                        DP.OpenModal()
                                                    end),
                                                    MakeBtn("+20点", { 200, 160, 255 }, function()
                                                        AdManager.DebugAddCardPoints(20)
                                                        DP.CloseModal()
                                                        DP.OpenModal()
                                                    end),
                                                    MakeBtn("+50点", { 200, 160, 255 }, function()
                                                        AdManager.DebugAddCardPoints(50)
                                                        DP.CloseModal()
                                                        DP.OpenModal()
                                                    end),
                                                }),
                                                BtnRow({
                                                    MakeBtn("发每日福利", { 120, 220, 80 }, function()
                                                        AdManager.DebugGrantDailyItems()
                                                        DP.CloseModal()
                                                        DP.OpenModal()
                                                    end),
                                                    MakeBtn("重置特权卡", { 220, 80, 80 }, function()
                                                        AdManager.DebugResetCard()
                                                        DP.CloseModal()
                                                        DP.OpenModal()
                                                    end),
                                                }),
                                            },
                                        }
                                    end)(),

                                    Divider(),

                                    -- 当前状态
                                    SectionTitle("当前状态"),
                                    UI.Panel {
                                        width = "100%", flexDirection = "column", gap = 2,
                                        children = {
                                            InfoLabel("金币: " .. GameState.FormatNumber(GameState.coins)),
                                            InfoLabel("CPS: " .. GameState.FormatNumber(GameState.coinsPerSecond)),
                                            InfoLabel("CPC: " .. GameState.FormatNumber(GameState.coinsPerClick)),
                                            InfoLabel("总点击: " .. GameState.FormatNumber(GameState.totalClicks)),
                                            InfoLabel("Buff: " .. #GameState.activeBuffs),
                                            InfoLabel("最高: " .. GameState.FormatNumber(GameState.maxCoins)),
                                        },
                                    },


                                },
                            },
                        },
                    },
                },
            },
        },
    }

    uiRoot_:AddChild(overlay_)
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 检查 userId 是否在白名单中（兼容 number 和 string 类型）
local function CheckTestAccount()
    local userId = clientCloud and clientCloud.userId
    if userId == nil then return false end
    local key = tostring(userId)
    print("[DebugPanel] userId=" .. key .. " type=" .. type(userId))
    return TEST_ACCOUNTS[key] == true
end

--- 创建调试按钮（仅测试账号可见）
--- 注意：如果 Create() 时 userId 尚未就绪，Init() 时会再次检测并补挂按钮
---@return table|nil
function DP.Create()
    isTestAccount_ = CheckTestAccount()

    -- 创建按钮：onPointerDown 必须在创建时绑定
    -- 初始隐藏（宽高0），确认测试账号后显示
    btnWidget_ = UI.Panel {
        id = "debugBtnContainer",
        position = "absolute",
        left = 56, bottom = 6,
        width = 0, height = 0,
        zIndex = 50,
        pointerEvents = "auto",
        onPointerDown = function()
            if isTestAccount_ then
                DP.OpenModal()
            end
        end,
    }

    if isTestAccount_ then
        DP._showButton()
    end

    return btnWidget_
end

--- 内部：让 DEBUG 按钮可见
function DP._showButton()
    if not btnWidget_ then return end
    btnWidget_:SetStyle({
        width = -1,   -- auto
        height = -1,  -- auto
        paddingLeft = 6, paddingRight = 6,
        paddingTop = 3, paddingBottom = 3,
        backgroundColor = { 30, 60, 30, 200 },
        borderRadius = 4,
        borderColor = { 80, 160, 80, 150 },
        borderWidth = 1,
    })
    btnWidget_:AddChild(UI.Label {
        text = "DEBUG",
        fontSize = 9,
        fontColor = { 100, 255, 100, 220 },
        fontWeight = "bold",
    })
    print("[DebugPanel] DEBUG button visible")
end

--- 初始化
---@param root table UI 根节点
---@param gm table|nil GameManager 引用
function DP.Init(root, gm)
    uiRoot_ = root
    manager_ = gm

    -- 延迟检测：Create() 时可能 userId 尚未就绪
    if not isTestAccount_ then
        isTestAccount_ = CheckTestAccount()
        if isTestAccount_ then
            print("[DebugPanel] Late detection: test account confirmed")
            DP._showButton()
        end
    end
end

return DP
