-- ============================================================================
-- ui/InventoryPanel.lua
-- 仓库面板 —— 左侧抽屉面板，道具网格 + 详情区
-- ============================================================================

local UI = require("urhox-libs/UI")
local ItemDefs = require("config.ItemDefs")
local GameState = require("core.GameState")
local AudioManager = require("core.AudioManager")

local IP = {}

-- ============================================================================
-- 内部状态
-- ============================================================================
local drawerContent_ = nil   -- 抽屉内容区容器
local manager_       = nil   -- GameManager 引用
local invMgr_        = nil   -- InventoryManager 引用
local visible_       = false
local contentPanel_  = nil   -- 面板根节点

-- 状态
local selectedSlot_  = nil   -- 当前选中的格子索引
local activeFilter_  = "all" -- 当前分类过滤

-- 批量使用数量
local batchCount_ = 1

-- 刷新指纹
local lastFingerprint_ = ""

-- ============================================================================
-- 颜色常量
-- ============================================================================
local C_BG       = { 28, 32, 45, 245 }
local C_CARD     = { 35, 38, 52, 255 }
local C_TEXT     = { 220, 220, 240, 255 }
local C_DIM      = { 140, 140, 160, 200 }
local C_GOLD     = { 255, 215, 0, 255 }
local C_BORDER   = { 60, 55, 80, 120 }
local C_SELECTED = { 100, 140, 255, 100 }
local C_EMPTY    = { 40, 42, 55, 255 }
local C_TAB_ON   = { 80, 100, 180, 200 }
local C_TAB_OFF  = { 50, 52, 68, 200 }

-- ============================================================================
-- 网格配置
-- ============================================================================
local GRID_COLS = 4
local CELL_SIZE = 52
local CELL_GAP  = 4

-- ============================================================================
-- 内部函数
-- ============================================================================

--- 计算刷新指纹
local function CalcFingerprint()
    local parts = { activeFilter_, tostring(selectedSlot_), tostring(batchCount_) }
    local slots = invMgr_ and invMgr_.GetSlots() or {}
    for i = 1, (invMgr_ and invMgr_.GetSlotCount() or 20) do
        local s = slots[i]
        if s then
            parts[#parts + 1] = s.itemId .. ":" .. s.count
        else
            parts[#parts + 1] = "_"
        end
    end
    return table.concat(parts, "|")
end

--- 获取稀有度颜色
local function GetRarityColor(rarity)
    local r = ItemDefs.RARITY[rarity]
    return r and r.color or { 180, 180, 190 }
end

--- 获取稀有度星星文本
local function GetRarityStars(rarity)
    local stars = ""
    for _ = 1, (rarity or 1) do
        stars = stars .. "*"
    end
    return stars
end

--- 判断某格子在当前过滤下是否可见
local function SlotMatchesFilter(slot)
    if activeFilter_ == "all" then return true end
    if not slot then return false end
    local def = ItemDefs.ITEM_MAP[slot.itemId]
    return def and def.category == activeFilter_
end

--- 选中一个格子
local function SelectSlot(index)
    selectedSlot_ = index
    batchCount_ = 1
    IP.Refresh()
end

-- ============================================================================
-- 构建 UI
-- ============================================================================

--- 构建套装收集进度条
local function BuildSetBonusBar()
    if not invMgr_ or not invMgr_.GetCollectibleBonuses then
        return UI.Panel { height = 0 }
    end

    local bonus = invMgr_.GetCollectibleBonuses()
    local owned = bonus.ownedCount
    local total = bonus.totalCount

    -- 收藏品图标行
    local iconChildren = {}
    for _, cid in ipairs(ItemDefs.COLLECTIBLE_IDS) do
        local def = ItemDefs.ITEM_MAP[cid]
        local has = bonus.ownedIds[cid]
        local rc = GetRarityColor(def.rarity)
        iconChildren[#iconChildren + 1] = UI.Panel {
            width = 22, height = 22,
            justifyContent = "center", alignItems = "center",
            backgroundColor = has and { rc[1], rc[2], rc[3], 60 } or { 40, 40, 50, 180 },
            borderRadius = 4,
            borderWidth = 1,
            borderColor = has and rc or { 50, 50, 60, 100 },
            margin = 1,
            children = {
                UI.Label {
                    text = def.abbr,
                    fontSize = 10,
                    fontColor = has and rc or { 60, 60, 70, 150 },
                    pointerEvents = "none",
                },
            },
        }
    end

    -- 套装奖励标签
    local setChildren = {}
    for _, sb in ipairs(ItemDefs.SET_BONUSES) do
        local reached = owned >= sb.need
        setChildren[#setChildren + 1] = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            marginTop = 2,
            children = {
                UI.Label {
                    text = sb.need .. "/" .. total,
                    fontSize = 9,
                    fontColor = reached and C_GOLD or C_DIM,
                    marginRight = 4,
                    pointerEvents = "none",
                },
                UI.Label {
                    text = sb.desc,
                    fontSize = 9,
                    fontColor = reached and { 140, 220, 140, 255 } or { 80, 80, 90, 180 },
                    pointerEvents = "none",
                },
                reached and UI.Label {
                    text = " [已激活]",
                    fontSize = 9,
                    fontColor = { 100, 200, 100, 200 },
                    pointerEvents = "none",
                } or nil,
            },
        }
    end

    return UI.Panel {
        width = "100%",
        marginBottom = 6,
        children = {
            -- 标题行
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                marginBottom = 4,
                children = {
                    UI.Label {
                        text = "收藏图鉴",
                        fontSize = 12,
                        fontColor = { 220, 160, 255, 255 },
                        fontWeight = "bold",
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = owned .. "/" .. total,
                        fontSize = 11,
                        fontColor = owned >= total and C_GOLD or C_DIM,
                        pointerEvents = "none",
                    },
                },
            },
            -- 图标行
            UI.Panel {
                flexDirection = "row",
                flexWrap = "wrap",
                marginBottom = 4,
                children = iconChildren,
            },
            -- 套装奖励列表
            UI.Panel {
                flexDirection = "column",
                children = setChildren,
            },
        },
    }
end

local function BuildContent()
    local slotCount = invMgr_ and invMgr_.GetSlotCount() or 20

    -- 分类 Tab 按钮
    local tabChildren = {}
    for _, cat in ipairs(ItemDefs.CATEGORIES) do
        local catId = cat.id
        tabChildren[#tabChildren + 1] = UI.Panel {
            id = "invTab_" .. catId,
            height = 28,
            flex = 1,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = (activeFilter_ == catId) and C_TAB_ON or C_TAB_OFF,
            borderRadius = 6,
            marginRight = 3,
            pointerEvents = "auto",
            onTap = function()
                activeFilter_ = catId
                selectedSlot_ = nil
                IP.Refresh()
                AudioManager.PlayBtnClick()
            end,
            children = {
                UI.Label {
                    text = cat.name,
                    fontSize = 11,
                    fontColor = (activeFilter_ == catId) and C_TEXT or C_DIM,
                    pointerEvents = "none",
                },
            },
        }
    end

    -- 网格格子
    local gridChildren = {}
    local slots = invMgr_ and invMgr_.GetSlots() or {}
    for i = 1, slotCount do
        local slot = slots[i]
        local def = slot and ItemDefs.ITEM_MAP[slot.itemId] or nil
        local isSelected = (selectedSlot_ == i)
        local matchesFilter = (not slot) or SlotMatchesFilter(slot)

        local cellBg = C_EMPTY
        if isSelected then
            cellBg = C_SELECTED
        elseif slot and def then
            local rc = GetRarityColor(def.rarity)
            cellBg = { rc[1], rc[2], rc[3], 40 }
        end

        local cellChildren = {}

        if slot and def and matchesFilter then
            local rc = GetRarityColor(def.rarity)
            if def.icon then
                -- 道具图标（图片）
                cellChildren[#cellChildren + 1] = UI.Panel {
                    width = 32, height = 32,
                    backgroundImage = def.icon,
                    pointerEvents = "none",
                }
            else
                -- 道具图标（单字缩写回退）
                cellChildren[#cellChildren + 1] = UI.Label {
                    text = def.abbr or string.sub(def.name, 1, 3),
                    fontSize = 18,
                    fontColor = rc,
                    fontWeight = "bold",
                    pointerEvents = "none",
                }
            end
            -- 数量角标
            if slot.count > 1 then
                cellChildren[#cellChildren + 1] = UI.Label {
                    position = "absolute",
                    right = 2, bottom = 1,
                    text = tostring(slot.count),
                    fontSize = 9,
                    fontColor = C_GOLD,
                    pointerEvents = "none",
                }
            end
            -- 稀有度底色条
            cellChildren[#cellChildren + 1] = UI.Panel {
                position = "absolute",
                bottom = 0, left = 0,
                width = "100%", height = 2,
                backgroundColor = rc,
                pointerEvents = "none",
            }
        elseif slot and not matchesFilter then
            -- 被过滤隐藏的格子显示暗淡
            cellChildren[#cellChildren + 1] = UI.Label {
                text = "-",
                fontSize = 14,
                fontColor = { 60, 60, 70, 100 },
                pointerEvents = "none",
            }
        end

        local idx = i
        gridChildren[#gridChildren + 1] = UI.Panel {
            id = "invCell_" .. i,
            width = CELL_SIZE, height = CELL_SIZE,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = cellBg,
            borderRadius = 6,
            borderWidth = isSelected and 2 or 1,
            borderColor = isSelected and { 120, 160, 255, 200 } or C_BORDER,
            margin = CELL_GAP / 2,
            pointerEvents = "auto",
            onTap = function()
                SelectSlot(idx)
                AudioManager.PlayBtnClick()
            end,
            children = cellChildren,
        }
    end

    -- 详情区内容
    local detailChildren = {}
    if selectedSlot_ and slots[selectedSlot_] then
        local slot = slots[selectedSlot_]
        local def = ItemDefs.ITEM_MAP[slot.itemId]
        if def then
            local rc = GetRarityColor(def.rarity)
            local rarityDef = ItemDefs.RARITY[def.rarity]

            detailChildren[#detailChildren + 1] = UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                marginBottom = 4,
                children = {
                    UI.Label {
                        text = def.name,
                        fontSize = 15,
                        fontColor = rc,
                        fontWeight = "bold",
                    },

                },
            }

            detailChildren[#detailChildren + 1] = UI.Label {
                text = (rarityDef and rarityDef.name or "") .. " | x" .. slot.count,
                fontSize = 11,
                fontColor = C_DIM,
                marginBottom = 4,
            }

            detailChildren[#detailChildren + 1] = UI.Label {
                text = def.desc or "",
                fontSize = 11,
                fontColor = { 190, 190, 210, 220 },
                marginBottom = 4,
            }

            -- 收藏品被动效果显示
            if def.passive then
                detailChildren[#detailChildren + 1] = UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    marginBottom = 8,
                    paddingLeft = 6, paddingRight = 6,
                    paddingTop = 3, paddingBottom = 3,
                    backgroundColor = { 60, 80, 60, 120 },
                    borderRadius = 4,
                    children = {
                        UI.Label {
                            text = "被动: " .. def.passive.desc,
                            fontSize = 11,
                            fontColor = { 140, 220, 140, 255 },
                            pointerEvents = "none",
                        },
                    },
                }
            else
                -- 非收藏品的间距补齐
                detailChildren[#detailChildren + 1] = UI.Panel { height = 4 }
            end

            -- 按钮行
            local btnChildren = {}
            if def.useEffect then
                -- 限制 batchCount_ 不超过持有量
                if batchCount_ > slot.count then batchCount_ = slot.count end
                if batchCount_ < 1 then batchCount_ = 1 end

                -- 数量选择器行
                detailChildren[#detailChildren + 1] = UI.Panel {
                    flexDirection = "row",
                    width = "100%",
                    alignItems = "center",
                    marginBottom = 6,
                    children = {
                        UI.Label { text = "数量", fontSize = 11, fontColor = C_DIM, marginRight = 6, pointerEvents = "none" },
                        -- 减
                        UI.Panel {
                            width = 26, height = 26,
                            justifyContent = "center", alignItems = "center",
                            backgroundColor = { 60, 60, 75, 220 },
                            borderRadius = 5,
                            pointerEvents = "auto",
                            onTap = function()
                                batchCount_ = math.max(1, batchCount_ - 1)
                                IP.Refresh()
                                AudioManager.PlayBtnClick()
                            end,
                            children = { UI.Label { text = "-", fontSize = 14, fontColor = C_TEXT, pointerEvents = "none" } },
                        },
                        -- 数字
                        UI.Panel {
                            width = 36, height = 26,
                            justifyContent = "center", alignItems = "center",
                            backgroundColor = { 45, 48, 62, 255 },
                            marginLeft = 2, marginRight = 2,
                            borderRadius = 4,
                            children = {
                                UI.Label { text = tostring(batchCount_), fontSize = 13, fontColor = C_GOLD, fontWeight = "bold", pointerEvents = "none" },
                            },
                        },
                        -- 加
                        UI.Panel {
                            width = 26, height = 26,
                            justifyContent = "center", alignItems = "center",
                            backgroundColor = { 60, 60, 75, 220 },
                            borderRadius = 5,
                            pointerEvents = "auto",
                            onTap = function()
                                local maxN = slot.count
                                batchCount_ = math.min(maxN, batchCount_ + 1)
                                IP.Refresh()
                                AudioManager.PlayBtnClick()
                            end,
                            children = { UI.Label { text = "+", fontSize = 14, fontColor = C_TEXT, pointerEvents = "none" } },
                        },
                        -- 最大
                        UI.Panel {
                            height = 26, paddingLeft = 6, paddingRight = 6,
                            justifyContent = "center", alignItems = "center",
                            backgroundColor = { 70, 85, 120, 200 },
                            borderRadius = 5,
                            marginLeft = 6,
                            pointerEvents = "auto",
                            onTap = function()
                                batchCount_ = slot.count
                                IP.Refresh()
                                AudioManager.PlayBtnClick()
                            end,
                            children = { UI.Label { text = "MAX", fontSize = 10, fontColor = { 200, 220, 255, 255 }, pointerEvents = "none" } },
                        },
                    },
                }

                -- 使用按钮
                local useText = batchCount_ > 1 and ("使用x" .. batchCount_) or "使用"
                btnChildren[#btnChildren + 1] = UI.Panel {
                    height = 30, flex = 1,
                    justifyContent = "center", alignItems = "center",
                    backgroundColor = { 60, 140, 80, 220 },
                    borderRadius = 6,
                    marginRight = 6,
                    pointerEvents = "auto",
                    onTap = function()
                        if invMgr_ then
                            if batchCount_ > 1 then
                                invMgr_.UseItemMulti(selectedSlot_, batchCount_)
                            else
                                if manager_ and manager_.OnUseItem then
                                    manager_.OnUseItem(selectedSlot_)
                                else
                                    invMgr_.UseItem(selectedSlot_)
                                end
                            end
                            -- 使用后可能格子清空
                            local s = invMgr_.GetSlots()[selectedSlot_]
                            if not s then
                                selectedSlot_ = nil
                                batchCount_ = 1
                            else
                                batchCount_ = math.min(batchCount_, s.count)
                            end
                            IP.Refresh()
                            AudioManager.PlayBtnClick()
                            local SlotSaveSystem = require("core.SlotSaveSystem")
                            SlotSaveSystem.MarkDirty()
                        end
                    end,
                    children = {
                        UI.Label { text = useText, fontSize = 13, fontColor = { 255, 255, 255, 255 }, pointerEvents = "none" },
                    },
                }
            end

            btnChildren[#btnChildren + 1] = UI.Panel {
                height = 30, flex = 1,
                justifyContent = "center", alignItems = "center",
                backgroundColor = { 140, 60, 60, 200 },
                borderRadius = 6,
                pointerEvents = "auto",
                onTap = function()
                    if invMgr_ then
                        invMgr_.RemoveItem(selectedSlot_, 1)
                        local s = invMgr_.GetSlots()[selectedSlot_]
                        if not s then
                            selectedSlot_ = nil
                            batchCount_ = 1
                        end
                        IP.Refresh()
                        AudioManager.PlayBtnClick()
                        local SlotSaveSystem = require("core.SlotSaveSystem")
                        SlotSaveSystem.MarkDirty()
                    end
                end,
                children = {
                    UI.Label { text = "丢弃", fontSize = 13, fontColor = { 255, 200, 200, 255 }, pointerEvents = "none" },
                },
            }

            detailChildren[#detailChildren + 1] = UI.Panel {
                flexDirection = "row",
                width = "100%",
                children = btnChildren,
            }
        end
    else
        detailChildren[#detailChildren + 1] = UI.Label {
            text = "选择一个道具查看详情",
            fontSize = 12,
            fontColor = C_DIM,
        }
    end

    -- 组装面板
    local usedCount = invMgr_ and invMgr_.GetUsedSlotCount() or 0

    return UI.Panel {
        id = "inventoryContent",
        width = "100%", height = "100%",
        flexDirection = "column",
        backgroundColor = C_BG,
        padding = 10,
        children = {
            -- 标题栏
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                width = "100%",
                marginBottom = 8,
                children = {
                    UI.Label {
                        text = "仓库",
                        fontSize = 16,
                        fontColor = C_GOLD,
                        fontWeight = "bold",
                    },
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = usedCount .. "/" .. slotCount,
                                fontSize = 12,
                                fontColor = C_DIM,
                                marginRight = 8,
                            },
                            -- 整理按钮
                            UI.Panel {
                                height = 24, paddingLeft = 8, paddingRight = 8,
                                justifyContent = "center", alignItems = "center",
                                backgroundColor = { 70, 90, 140, 220 },
                                borderRadius = 5,
                                pointerEvents = "auto",
                                onTap = function()
                                    if invMgr_ then
                                        invMgr_.SortItems()
                                        selectedSlot_ = nil
                                        IP.Refresh()
                                        AudioManager.PlayBtnClick()
                                        local SlotSaveSystem = require("core.SlotSaveSystem")
                                        SlotSaveSystem.MarkDirty()
                                    end
                                end,
                                children = {
                                    UI.Label { text = "整理", fontSize = 11, fontColor = { 220, 230, 255, 255 }, pointerEvents = "none" },
                                },
                            },
                        },
                    },
                },
            },

            -- 分类 Tab
            UI.Panel {
                flexDirection = "row",
                width = "100%",
                marginBottom = 8,
                children = tabChildren,
            },

            -- 网格区（可滚动）
            UI.ScrollView {
                flex = 1,
                width = "100%",
                marginBottom = 8,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        flexWrap = "wrap",
                        width = "100%",
                        children = gridChildren,
                    },
                },
            },

            -- 分隔线
            UI.Panel {
                width = "100%", height = 1,
                backgroundColor = C_BORDER,
                marginBottom = 6,
            },

            -- 详情区
            UI.Panel {
                id = "invDetail",
                width = "100%",
                minHeight = 80,
                flexDirection = "column",
                padding = 8,
                backgroundColor = C_CARD,
                borderRadius = 8,
                borderWidth = 1,
                borderColor = C_BORDER,
                children = detailChildren,
            },
        },
    }
end

-- ============================================================================
-- 公开 API（标准抽屉面板接口）
-- ============================================================================

--- 初始化仓库面板
---@param drawerContent table  抽屉内容区容器
---@param gm table  GameManager 引用
function IP.Init(drawerContent, gm)
    drawerContent_ = drawerContent
    manager_ = gm
    invMgr_ = gm and gm.GetInventoryManager and gm.GetInventoryManager() or nil
end

--- 显示面板
function IP.Show()
    visible_ = true
    lastFingerprint_ = ""
    IP.Refresh()
end

--- 隐藏面板
function IP.Hide()
    visible_ = false
    if drawerContent_ and contentPanel_ then
        drawerContent_:RemoveChild(contentPanel_)
        contentPanel_ = nil
    end
end

--- 切换显示/隐藏
function IP.Toggle()
    if visible_ then
        IP.Hide()
    else
        IP.Show()
    end
end

--- 是否可见
---@return boolean
function IP.IsVisible()
    return visible_
end

--- 刷新面板内容
function IP.Refresh()
    if not visible_ or not drawerContent_ then return end

    -- 指纹检查（避免无变化时重建）
    local fp = CalcFingerprint()
    if fp == lastFingerprint_ then return end
    lastFingerprint_ = fp

    -- 移除旧内容
    if contentPanel_ then
        drawerContent_:RemoveChild(contentPanel_)
    end

    -- 重建内容
    contentPanel_ = BuildContent()
    drawerContent_:AddChild(contentPanel_)
end

return IP
