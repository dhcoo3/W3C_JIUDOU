--- 特殊怪概率属性接口及确定性死亡判定。
--- 外部商城应由 Player(0) 调用 set_bonus_source，再通过同步通道向全体客户端发布结果。
local jass = require "jass.common"
local sync = require "monster.special_spawn_sync"
local random = require "monster.random"

local module = {}

local MAX_PLAYER_ID = 11
local MAX_BONUS_PERCENT = 30
local NORMAL_BASE_CHANCE = 10
local ELITE_BASE_CHANCE = 50

local started = false
local sync_available = false
local active_player_count = 0
local next_event_id = 0
local last_applied_event_id = 0
local active_players = {}
local bonus_by_player = {}
local sources_by_player = {}
local listeners = {}

local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

local function valid_player_id(player_id)
    return is_integer(player_id) and player_id >= 0 and player_id <= MAX_PLAYER_ID
end

local function parse_integer(value)
    local number = tonumber(value)
    if number == nil or number ~= math.floor(number) then return nil end
    return number
end

local function notify(player_id)
    local bonus = bonus_by_player[player_id] or 0
    for _, listener in ipairs(listeners) do
        pcall(listener, player_id, bonus)
    end
end

local function apply_bonus(event_id, player_id, bonus, sender_id)
    if sender_id ~= 0 or event_id <= last_applied_event_id
        or not active_players[player_id] or bonus < 0 or bonus > MAX_BONUS_PERCENT then
        return false
    end
    last_applied_event_id = event_id
    bonus_by_player[player_id] = bonus
    notify(player_id)
    return true
end

local function on_sync_message(message, sender_id)
    local parts = sync.split(message or "", "|")
    if parts[1] ~= "BONUS" or parts[2] ~= tostring(sync.get_version()) then return end
    local event_id = parse_integer(parts[3])
    local player_id = parse_integer(parts[4])
    local bonus = parse_integer(parts[5])
    if event_id == nil or player_id == nil or bonus == nil or event_id <= 0 or not valid_player_id(player_id) then
        return
    end
    apply_bonus(event_id, player_id, bonus, sender_id)
end

local function calculate_bonus(sources)
    local total = 0
    for _, points in pairs(sources or {}) do
        total = total + points
        if total >= MAX_BONUS_PERCENT then return MAX_BONUS_PERCENT end
    end
    return math.max(0, math.min(MAX_BONUS_PERCENT, total))
end

local function publish_bonus(player_id, bonus)
    next_event_id = next_event_id + 1
    return sync.broadcast(table.concat({
        "BONUS",
        tostring(sync.get_version()),
        tostring(next_event_id),
        tostring(player_id),
        tostring(bonus),
    }, "|"))
end

function module.get_bonus_percent(player_id)
    if not valid_player_id(player_id) then return 0 end
    return math.max(0, math.min(MAX_BONUS_PERCENT, math.floor(tonumber(bonus_by_player[player_id]) or 0)))
end

--- 返回当前概率；普通怪的金币、经验判定相互独立。
---@param player_id integer 玩家编号
---@return table chances 当前个人概率
function module.get_chances(player_id)
    local bonus = module.get_bonus_percent(player_id)
    return {
        bonusPercent = bonus,
        normalGoldPercent = math.min(30, NORMAL_BASE_CHANCE + bonus),
        normalExperiencePercent = math.min(30, NORMAL_BASE_CHANCE + bonus),
        eliteGoldPercent = math.min(80, ELITE_BASE_CHANCE + bonus),
    }
end

--- 设置某个商城/系统来源的概率百分点；同一 sourceId 重复设置会覆盖，不会叠加重复。
--- 仅 Player(0) 可调用，随后同步每位玩家的新总加成。百分比点加成为 0..30。
---@param player_id integer 玩家编号
---@param source_id string 稳定来源 ID
---@param percentage_points integer 百分比点
---@return boolean applied 是否接受并同步
function module.set_bonus_source(player_id, source_id, percentage_points)
    if not started or not sync.is_host() or not valid_player_id(player_id)
        or not active_players[player_id] or type(source_id) ~= "string" or source_id == ""
        or string.find(source_id, "|", 1, true) ~= nil or not is_integer(percentage_points) then
        return false
    end
    if not sync_available and active_player_count > 1 then return false end
    local sources = sources_by_player[player_id]
    if sources == nil then return false end
    sources[source_id] = math.max(0, math.min(MAX_BONUS_PERCENT, percentage_points))
    return publish_bonus(player_id, calculate_bonus(sources))
end

--- 清除指定商城/系统来源的概率加成。
---@param player_id integer 玩家编号
---@param source_id string 稳定来源 ID
---@return boolean applied 是否接受并同步
function module.clear_bonus_source(player_id, source_id)
    if not started or not sync.is_host() or not valid_player_id(player_id)
        or not active_players[player_id] or type(source_id) ~= "string" or source_id == "" then
        return false
    end
    if not sync_available and active_player_count > 1 then return false end
    local sources = sources_by_player[player_id]
    if sources == nil then return false end
    sources[source_id] = nil
    return publish_bonus(player_id, calculate_bonus(sources))
end

--- 注册本地 UI 刷新监听器；监听器不参与同步状态计算。
---@param listener fun(playerId:integer, bonusPercent:integer)
---@return boolean added
function module.subscribe(listener)
    if type(listener) ~= "function" then return false end
    table.insert(listeners, listener)
    return true
end

--- 对普通怪进行独立金币/经验判定，对精英只进行金币判定。
---@param kind string normal 或 elite
---@param player_id integer|nil 击杀者玩家编号
---@param rng MonsterRandom 槽位专用随机流
---@return string[] packs 成功判定的特殊怪包，按金币、经验顺序
function module.roll_death(kind, player_id, rng)
    local packs = {}
    if not active_players[player_id] or type(rng) ~= "table" then return packs end
    local chances = module.get_chances(player_id)
    if kind == "normal" then
        if random.next_integer(rng, 1, 100) <= chances.normalGoldPercent then
            table.insert(packs, "gold")
        end
        if random.next_integer(rng, 1, 100) <= chances.normalExperiencePercent then
            table.insert(packs, "experience")
        end
    elseif kind == "elite" then
        if random.next_integer(rng, 1, 100) <= chances.eliteGoldPercent then
            table.insert(packs, "gold_elite")
        end
    end
    return packs
end

--- 只向最后一击所属的本地玩家显示特殊怪提示。
---@param player_id integer|nil 玩家编号
---@param message string 提示内容
---@param duration number 显示秒数
function module.show_to_player(player_id, message, duration)
    if not valid_player_id(player_id) or type(message) ~= "string"
        or type(jass.GetLocalPlayer) ~= "function" or type(jass.GetPlayerId) ~= "function"
        or type(jass.DisplayTimedTextToPlayer) ~= "function" then
        return false
    end
    if jass.GetPlayerId(jass.GetLocalPlayer()) ~= player_id then return false end
    jass.DisplayTimedTextToPlayer(jass.GetLocalPlayer(), 0, 0, duration or 5.0, message)
    return true
end

---@param hero_results HeroSelectionResult[] 本局 PVE 英雄列表
---@return boolean started_now
function module.start(hero_results)
    if started then return false end
    active_players = {}
    active_player_count = 0
    bonus_by_player = {}
    sources_by_player = {}
    listeners = listeners or {}
    for _, result in ipairs(hero_results or {}) do
        local player_id = result.playerId
        if valid_player_id(player_id) and result.unit ~= nil and not active_players[player_id] then
            active_players[player_id] = true
            active_player_count = active_player_count + 1
            bonus_by_player[player_id] = 0
            sources_by_player[player_id] = {}
        end
    end
    if active_player_count == 0 then
        print("特殊怪生成属性启动失败：没有有效 PVE 玩家")
        return false
    end
    sync_available = sync.start(on_sync_message)
    started = true
    print(string.format(
        "特殊怪生成属性接口已启动：玩家=%d，加成上限=%d%%，同步=%s",
        active_player_count,
        MAX_BONUS_PERCENT,
        sync_available and "可用" or "单机本地"
    ))
    return true
end

function module.is_started() return started end

return module
