-- ============================================================================
-- ui/LeaderboardPanel.lua
-- 排行榜：按钮触发弹窗，分页加载，先加载自己排名
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("core.GameState")

local LP = {}

-- ======== 常量 ========
local PAGE_SIZE = 20               -- 每页条数
local MAX_ENTRIES = 100            -- 最多加载条数
local UPLOAD_INTERVAL = 10         -- 上传间隔（秒）
local RANK_QUERY_INTERVAL = 30     -- 排名查询间隔（秒）

-- ======== 状态 ========
local uploadTimer_ = 0
local lastUploadedExp_ = -1
local lastUploadedMan_ = -1
local initialized_ = false         -- clientCloud 是否可用
local rankQueryTimer_ = 0          -- 排名查询计时器

-- ======== 弹窗状态 ========
local overlay_ = nil               -- 遮罩层
local uiRoot_ = nil                -- UI 根节点引用
local btnWidget_ = nil             -- 排行榜按钮引用
local listContainer_ = nil         -- 列表容器
local loadMoreBtn_ = nil           -- "加载更多"按钮
local myRankPanel_ = nil           -- "我的排名"面板
local leaderboardData_ = {}        -- { {rank, userId, nickname, mantissa, exponent, isMe}, ... }
local myRankInfo_ = nil            -- { rank, mantissa, exponent }
local isLoading_ = false
local currentOffset_ = 0           -- 当前已加载的偏移量
local hasMore_ = true              -- 是否还有更多数据
local isModalOpen_ = false

-- ============================================================================
-- 大数拆分：将 coins 拆为 mantissa(底数) + exponent(指数)
-- ============================================================================

---@param n number
---@return number mantissa
---@return number exponent
function LP.SplitCoins(n)
    if n <= 0 then return 0, 0 end
    if n < 1000 then
        return math.floor(n), 0
    end
    local exp = math.floor(math.log(n, 10)) - 3
    if exp < 0 then exp = 0 end
    local man = math.floor(n / (10 ^ exp))
    if man >= 10000 then
        exp = exp + 1
        man = math.floor(n / (10 ^ exp))
    end
    if exp > 2000000000 then exp = 2000000000 end
    if man > 2000000000 then man = 2000000000 end
    return man, exp
end

---@param mantissa number
---@param exponent number
---@return number
function LP.RestoreCoins(mantissa, exponent)
    if mantissa <= 0 then return 0 end
    return mantissa * (10 ^ exponent)
end

-- ============================================================================
-- 排行榜追踪（更新 GameState.leaderboard）
-- ============================================================================

--- 更新排名相关追踪数据
---@param rank number 当前排名（0=未上榜）
---@param totalPlayers number 排行榜总人数
function LP.UpdateRankTracking(rank, totalPlayers)
    local lb = GameState.leaderboard
    lb.totalPlayers = math.max(lb.totalPlayers, totalPlayers)

    if rank <= 0 then return end

    lb.myRank = rank

    -- 更新历史最佳排名
    if lb.bestRank == 0 or rank < lb.bestRank then
        lb.bestRank = rank
    end

    -- 更新历史最佳百分比
    if totalPlayers > 0 then
        local percent = (rank / totalPlayers) * 100
        if percent < lb.bestPercent then
            lb.bestPercent = percent
        end
    end

    -- 更新到达标记
    if rank == 1 then
        lb.rank1Reached = true
    end
    if rank <= 3 then
        lb.top3Reached = true
    end
    if rank <= 10 then
        lb.top10Reached = true
    end

    -- 百分比类需要 >= 100 人
    if totalPlayers >= 100 then
        local percent = (rank / totalPlayers) * 100
        if percent <= 50 then
            lb.top50pReached = true
        end
        if percent <= 10 then
            lb.top10pReached = true
        end
        if percent <= 1 then
            lb.top1pReached = true
        end
    end
end

--- 后台定期查询自己的排名（不需要打开面板）
function LP.QueryMyRankBackground()
    if not clientCloud then return end

    clientCloud:GetUserRank(clientCloud.userId, "coin_exp", {
        ok = function(rank, scoreValue)
            if rank and rank > 0 then
                -- 还需要获取总人数，用 GetRankList offset=0 count=1 来间接获取
                -- 但更好的方式是用 GetRankList 拿第一条，通过排名数据估算总人数
                -- 实际做法：用一个很大的 offset 来探测总人数
                LP.QueryTotalPlayers(rank)
            end
        end,
        error = function() end,
    })
end

--- 查询排行榜总人数
---@param myRank number 我的当前排名
function LP.QueryTotalPlayers(myRank)
    if not clientCloud then return end

    -- 用 GetRankList 获取从 offset=0 的数据来估算总人数
    -- 通过请求最后一页来获取总人数：请求一个很大的 offset
    -- 更简单的方式：请求 offset = max(myRank, currentKnown), count=1
    -- 如果返回0条说明已到尾部
    -- 实际上 GetRankList 返回的 rankList 中有 rank 字段，最大 rank 即为接近总人数

    -- 先用已知数据更新
    local lb = GameState.leaderboard
    local estimatedTotal = math.max(lb.totalPlayers, myRank)

    -- 请求尾部数据来探测总人数
    clientCloud:GetRankList("coin_exp", 0, 1, {
        ok = function(rankList)
            -- 从 offset 0 count 1 获取第一条（rank=1），然后再请求较大 offset
            -- 用二分法太复杂，直接用一个合理大的 offset
            local probeOffset = math.max(estimatedTotal, 100)
            clientCloud:GetRankList("coin_exp", probeOffset, 1, {
                ok = function(probeList)
                    local total
                    if #probeList > 0 then
                        -- 还有数据，说明总人数大于 probeOffset
                        total = probeOffset + #probeList
                        -- 继续尝试更大的
                    else
                        -- 没有数据了，总人数在 probeOffset 以内
                        total = probeOffset
                    end
                    -- 用 myRank 和 probe 结果更新
                    total = math.max(total, myRank)
                    LP.UpdateRankTracking(myRank, total)
                end,
                error = function()
                    LP.UpdateRankTracking(myRank, estimatedTotal)
                end,
            }, "coin_man")
        end,
        error = function()
            LP.UpdateRankTracking(myRank, estimatedTotal)
        end,
    }, "coin_man")
end

-- ============================================================================
-- 云变量交互
-- ============================================================================

--- 上传最高金币到排行榜
function LP.UploadScore()
    if not clientCloud then return end
    local man, exp = LP.SplitCoins(GameState.coins)
    if exp < lastUploadedExp_ then return end
    if exp == lastUploadedExp_ and man <= lastUploadedMan_ then return end

    clientCloud:BatchSet()
        :SetInt("coin_exp", exp)
        :SetInt("coin_man", man)
        :Save("更新最高金币", {
            ok = function()
                lastUploadedExp_ = exp
                lastUploadedMan_ = man
            end,
            error = function(code, reason)
                print("[Leaderboard] 上传失败: " .. tostring(reason))
            end,
        })
end

--- 查询自己的排名
function LP.FetchMyRank(callback)
    if not clientCloud then
        if callback then callback() end
        return
    end

    clientCloud:GetUserRank(clientCloud.userId, "coin_exp", {
        ok = function(rank, scoreValue)
            if rank then
                clientCloud:Get("coin_man", {
                    ok = function(values, iscores)
                        local man = iscores.coin_man or 0
                        local exp = scoreValue or 0
                        myRankInfo_ = { rank = rank, mantissa = man, exponent = exp }
                        -- 更新排名追踪
                        LP.QueryTotalPlayers(rank)
                        LP.RebuildMyRank()
                        if callback then callback() end
                    end,
                    error = function()
                        myRankInfo_ = nil
                        if callback then callback() end
                    end,
                })
            else
                myRankInfo_ = nil
                if callback then callback() end
            end
        end,
        error = function()
            myRankInfo_ = nil
            if callback then callback() end
        end,
    })
end

--- 查询排行榜（分页）
---@param offset number 偏移量
---@param count number 请求条数
---@param append boolean 是否追加到现有数据
function LP.FetchPage(offset, count, append)
    if not clientCloud then return end
    if isLoading_ then return end
    isLoading_ = true

    LP.UpdateLoadMoreBtn("loading")

    clientCloud:GetRankList("coin_exp", offset, count, {
        ok = function(rankList)
            local entries = {}
            local userIds = {}
            for _, item in ipairs(rankList) do
                local exp = item.iscore.coin_exp or 0
                local man = item.iscore.coin_man or 0
                table.insert(entries, {
                    userId = item.userId,
                    mantissa = man,
                    exponent = exp,
                    isMe = (item.userId == clientCloud.userId),
                })
                table.insert(userIds, item.userId)
            end

            -- 不足一页说明没有更多数据
            if #entries < count then
                hasMore_ = false
            end

            -- 查询昵称
            if #userIds > 0 then
                GetUserNickname({
                    userIds = userIds,
                    onSuccess = function(nicknames)
                        local map = {}
                        for _, info in ipairs(nicknames) do
                            map[info.userId] = info.nickname or ""
                        end
                        for _, entry in ipairs(entries) do
                            entry.nickname = map[entry.userId] or "???"
                        end
                        LP.OnPageLoaded(entries, append)
                    end,
                    onError = function()
                        for _, entry in ipairs(entries) do
                            entry.nickname = "???"
                        end
                        LP.OnPageLoaded(entries, append)
                    end,
                })
            else
                -- 空数据
                hasMore_ = false
                LP.OnPageLoaded({}, append)
            end
        end,
        error = function(code, reason)
            print("[Leaderboard] 查询失败: " .. tostring(reason))
            isLoading_ = false
            LP.UpdateLoadMoreBtn("error")
        end,
    }, "coin_man")
end

--- 分页数据加载完成
function LP.OnPageLoaded(entries, append)
    if append then
        -- 追加模式：合并到现有数据
        for _, e in ipairs(entries) do
            table.insert(leaderboardData_, e)
        end
    else
        leaderboardData_ = entries
    end

    -- 利用分页数据更新总人数估算
    local lb = GameState.leaderboard
    lb.totalPlayers = math.max(lb.totalPlayers, #leaderboardData_)

    -- 按 exponent 降序 + mantissa 降序 重新排序整个列表
    table.sort(leaderboardData_, function(a, b)
        if a.exponent ~= b.exponent then
            return a.exponent > b.exponent
        end
        return a.mantissa > b.mantissa
    end)
    -- 编号
    for i, e in ipairs(leaderboardData_) do
        e.rank = i
    end

    currentOffset_ = #leaderboardData_

    -- 检查是否达到上限
    if currentOffset_ >= MAX_ENTRIES then
        hasMore_ = false
    end

    isLoading_ = false
    LP.RebuildList()
end

--- 加载更多
function LP.LoadMore()
    if isLoading_ or not hasMore_ then return end
    local remaining = MAX_ENTRIES - currentOffset_
    local count = math.min(PAGE_SIZE, remaining)
    if count <= 0 then
        hasMore_ = false
        LP.UpdateLoadMoreBtn("done")
        return
    end
    LP.FetchPage(currentOffset_, count, true)
end

-- ============================================================================
-- UI 构建
-- ============================================================================

--- 截断昵称
local function TruncName(name, maxLen)
    maxLen = maxLen or 6
    if not name then return "???" end
    local len = 0
    local byteIdx = 1
    while byteIdx <= #name and len < maxLen do
        local b = string.byte(name, byteIdx)
        if b < 0x80 then
            byteIdx = byteIdx + 1
        elseif b < 0xE0 then
            byteIdx = byteIdx + 2
        elseif b < 0xF0 then
            byteIdx = byteIdx + 3
        else
            byteIdx = byteIdx + 4
        end
        len = len + 1
    end
    if byteIdx <= #name then
        return string.sub(name, 1, byteIdx - 1) .. ".."
    end
    return name
end

--- 创建排行榜条目
local function CreateEntry(entry, highlight)
    local coins = LP.RestoreCoins(entry.mantissa, entry.exponent)
    local coinStr = GameState.FormatNumber(coins)
    local name = TruncName(entry.nickname, 8)

    local rankColors = {
        [1] = { 255, 215, 0, 255 },
        [2] = { 200, 200, 210, 255 },
        [3] = { 205, 127, 50, 255 },
    }
    local rankColor = rankColors[entry.rank] or { 160, 160, 180, 255 }
    local bgColor = highlight and { 80, 60, 140, 120 } or { 0, 0, 0, 0 }

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 6, paddingBottom = 6,
        backgroundColor = bgColor,
        gap = 8,
        children = {
            UI.Label {
                text = "#" .. entry.rank,
                fontSize = 14,
                fontColor = rankColor,
                width = 36,
                fontWeight = "bold",
            },
            UI.Label {
                text = name,
                fontSize = 13,
                fontColor = highlight and { 220, 200, 255, 255 } or { 200, 200, 210, 255 },
                flex = 1,
            },
            UI.Label {
                text = coinStr,
                fontSize = 12,
                fontColor = { 255, 220, 80, 220 },
            },
        },
    }
end

--- 重建"我的排名"面板
function LP.RebuildMyRank()
    if not myRankPanel_ then return end
    myRankPanel_:RemoveAllChildren()

    if myRankInfo_ then
        local coins = LP.RestoreCoins(myRankInfo_.mantissa, myRankInfo_.exponent)
        local coinStr = GameState.FormatNumber(coins)
        myRankPanel_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 12, paddingRight = 12,
            paddingTop = 8, paddingBottom = 8,
            backgroundColor = { 60, 45, 120, 180 },
            borderRadius = 6,
            gap = 8,
            children = {
                UI.Label {
                    text = "我的排名",
                    fontSize = 12,
                    fontColor = { 180, 170, 220, 200 },
                },
                UI.Label {
                    text = "#" .. myRankInfo_.rank,
                    fontSize = 16,
                    fontColor = { 255, 220, 80, 255 },
                    fontWeight = "bold",
                    flex = 1,
                },
                UI.Label {
                    text = coinStr,
                    fontSize = 13,
                    fontColor = { 255, 220, 80, 220 },
                },
            },
        })
    else
        myRankPanel_:AddChild(UI.Label {
            text = "暂无排名",
            fontSize = 12,
            fontColor = { 140, 140, 160, 180 },
            width = "100%",
            textAlign = "center",
            paddingTop = 4, paddingBottom = 4,
        })
    end
end

--- 更新"加载更多"按钮状态
function LP.UpdateLoadMoreBtn(state)
    if not loadMoreBtn_ then return end
    loadMoreBtn_:RemoveAllChildren()

    if state == "loading" then
        loadMoreBtn_:AddChild(UI.Label {
            text = "加载中...",
            fontSize = 12,
            fontColor = { 140, 140, 160, 200 },
            textAlign = "center",
            width = "100%",
        })
    elseif state == "error" then
        loadMoreBtn_:AddChild(UI.Label {
            text = "加载失败，点击重试",
            fontSize = 12,
            fontColor = { 220, 100, 100, 220 },
            textAlign = "center",
            width = "100%",
        })
    elseif state == "done" or not hasMore_ then
        loadMoreBtn_:AddChild(UI.Label {
            text = "已加载全部",
            fontSize = 11,
            fontColor = { 120, 120, 140, 160 },
            textAlign = "center",
            width = "100%",
        })
    else
        loadMoreBtn_:AddChild(UI.Label {
            text = "加载更多",
            fontSize = 13,
            fontColor = { 180, 170, 240, 240 },
            textAlign = "center",
            width = "100%",
        })
    end
end

--- 重建排行榜列表
function LP.RebuildList()
    if not listContainer_ then return end
    listContainer_:RemoveAllChildren()

    if #leaderboardData_ == 0 then
        listContainer_:AddChild(UI.Label {
            text = isLoading_ and "加载中..." or "暂无数据",
            fontSize = 13,
            fontColor = { 140, 140, 160, 200 },
            textAlign = "center",
            width = "100%",
            marginTop = 20,
        })
    else
        for _, entry in ipairs(leaderboardData_) do
            listContainer_:AddChild(CreateEntry(entry, entry.isMe))
        end
    end

    -- 更新"加载更多"按钮
    if hasMore_ and #leaderboardData_ > 0 then
        LP.UpdateLoadMoreBtn("ready")
    elseif #leaderboardData_ > 0 then
        LP.UpdateLoadMoreBtn("done")
    end
end

--- 关闭排行榜弹窗
function LP.CloseModal()
    if not isModalOpen_ then return end
    isModalOpen_ = false
    if overlay_ and uiRoot_ then
        uiRoot_:RemoveChild(overlay_)
    end
    overlay_ = nil
    listContainer_ = nil
    loadMoreBtn_ = nil
    myRankPanel_ = nil
    if btnWidget_ then
        btnWidget_:Show()
    end
end

--- 打开排行榜弹窗
function LP.OpenModal()
    if isModalOpen_ then return end
    if not uiRoot_ then return end
    isModalOpen_ = true

    -- 重置分页状态
    leaderboardData_ = {}
    myRankInfo_ = nil
    currentOffset_ = 0
    hasMore_ = true
    isLoading_ = false

    -- 我的排名区域
    myRankPanel_ = UI.Panel {
        width = "100%",
        flexDirection = "column",
        marginBottom = 4,
    }

    -- 排行列表容器
    listContainer_ = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 1,
    }

    -- 加载更多按钮
    loadMoreBtn_ = UI.Panel {
        width = "100%",
        paddingTop = 10, paddingBottom = 10,
        pointerEvents = "auto",
        onPointerDown = function()
            if hasMore_ and not isLoading_ then
                LP.LoadMore()
            end
        end,
    }

    -- 创建遮罩层（全屏绝对定位）
    overlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = "100%", height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        pointerEvents = "auto",
        onPointerDown = function(self, event)
            LP.CloseModal()
        end,
        children = {
            -- 弹窗面板（30% 宽，90% 高）
            UI.Panel {
                id = "lbModalPanel",
                width = "30%",
                height = "90%",
                flexDirection = "column",
                backgroundColor = { 30, 28, 45, 250 },
                borderRadius = 10,
                borderColor = { 80, 70, 120, 100 },
                borderWidth = 1,
                overflow = "hidden",
                pointerEvents = "auto",
                onPointerDown = function(self, event)
                    -- 阻止冒泡，点击面板内部不关闭
                    if event and event.stopPropagation then
                        event:stopPropagation()
                    end
                end,
                children = {
                    -- 标题栏
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "space-between",
                        paddingLeft = 16, paddingRight = 12,
                        paddingTop = 12, paddingBottom = 10,
                        children = {
                            UI.Label {
                                text = "排行榜",
                                fontSize = 16,
                                fontColor = { 255, 220, 80, 255 },
                                fontWeight = "bold",
                            },
                            -- 关闭按钮
                            UI.Panel {
                                paddingLeft = 8, paddingRight = 8,
                                paddingTop = 4, paddingBottom = 4,
                                borderRadius = 4,
                                backgroundColor = { 60, 50, 90, 180 },
                                pointerEvents = "auto",
                                onPointerDown = function()
                                    LP.CloseModal()
                                end,
                                children = {
                                    UI.Label {
                                        text = "✕",
                                        fontSize = 14,
                                        fontColor = { 180, 180, 200, 220 },
                                    },
                                },
                            },
                        },
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 70, 120, 80 },
                    },
                    -- 滚动列表
                    UI.ScrollView {
                        flex = 1,
                        width = "100%",
                        children = {
                            UI.Panel {
                                width = "100%",
                                flexDirection = "column",
                                children = {
                                    listContainer_,
                                    loadMoreBtn_,
                                },
                            },
                        },
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 70, 120, 60 },
                    },
                    -- 我的排名（底部）
                    myRankPanel_,
                },
            },
        },
    }

    -- 隐藏按钮
    if btnWidget_ then
        btnWidget_:Hide()
    end

    -- 添加到 UI 根节点
    uiRoot_:AddChild(overlay_)

    -- 先上传最新分数
    LP.UploadScore()

    -- 显示加载中
    LP.RebuildMyRank()
    listContainer_:AddChild(UI.Label {
        text = "加载中...",
        fontSize = 13,
        fontColor = { 140, 140, 160, 200 },
        textAlign = "center",
        width = "100%",
        marginTop = 20,
    })

    -- 先加载自己排名，再加载前20名
    LP.FetchMyRank(function()
        LP.FetchPage(0, PAGE_SIZE, false)
    end)
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 创建排行榜按钮（嵌入主布局）
---@return table button UI 按钮面板
function LP.Create()
    btnWidget_ = UI.Panel {
        id = "leaderboardBtn",
        position = "absolute",
        right = "30%",
        top = 10,
        marginRight = 8,
        paddingLeft = 10, paddingRight = 10,
        paddingTop = 6, paddingBottom = 6,
        backgroundColor = { 50, 40, 80, 220 },
        borderRadius = 6,
        borderColor = { 80, 70, 120, 150 },
        pointerEvents = "auto",
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        onPointerDown = function()
            LP.OpenModal()
        end,
        children = {
            UI.Panel {
                width = 18, height = 18,
                backgroundImage = "image/排行榜.png",
                backgroundFit = "contain",
            },
            UI.Label {
                text = "排行榜",
                fontSize = 13,
                fontColor = { 255, 220, 80, 255 },
                fontWeight = "bold",
            },
        },
    }
    return btnWidget_
end

--- 初始化
---@param root table UI 根节点
function LP.Init(root)
    uiRoot_ = root
    if clientCloud then
        initialized_ = true
    end
end

--- 帧更新（定时上传 + 排名追踪）
---@param dt number
function LP.Update(dt)
    if not initialized_ then
        if clientCloud then
            initialized_ = true
        else
            return
        end
    end

    -- 定时上传
    uploadTimer_ = uploadTimer_ + dt
    if uploadTimer_ >= UPLOAD_INTERVAL then
        uploadTimer_ = 0
        LP.UploadScore()
    end

    -- 第1名时长累加
    local lb = GameState.leaderboard
    if lb.myRank == 1 and lb.totalPlayers >= 100 then
        lb.rank1Time = lb.rank1Time + dt
    end

    -- 后台定期查询排名（用于成就追踪）
    rankQueryTimer_ = rankQueryTimer_ + dt
    if rankQueryTimer_ >= RANK_QUERY_INTERVAL then
        rankQueryTimer_ = 0
        LP.QueryMyRankBackground()
    end
end

return LP
