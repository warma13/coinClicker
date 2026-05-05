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
local SD = require("config.SugarLumpDefs")

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
