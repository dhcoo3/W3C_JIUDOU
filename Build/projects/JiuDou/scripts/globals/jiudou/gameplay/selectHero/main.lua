--- PVE 随机选将业务入口。
--- 负责多人同步会话、候选刷新、最终英雄创建，并把本地界面操作转化为可校验的同步请求。
local jass = require "jass.common"
local sync = require "platform.sync"
local config = require "selectHero.data.config"
local hero_pool = require "selectHero.data.hero_pool"
local popup = require "selectHero.ui.popup"
local random = JiuDou.core and JiuDou.core.random
local resource_api = JiuDou.core and JiuDou.core.resource
local timer_service = JiuDou.core and JiuDou.core.timer

local module = {}

local SYNC_PREFIX = "JiuDouHero"
local HOST_PLAYER_ID = 0

---@class HeroSpawnResult
---@field playerId integer 玩家编号
---@field rawcode string 所选英雄 Rawcode
---@field blockId integer 出生区域编号
---@field positionX integer 出生 X 坐标
---@field positionY integer 出生 Y 坐标

---@class HeroSelectionResult
---@field playerId integer 玩家编号
---@field hero HeroDefinition 所选英雄数据
---@field unit unit 创建出的英雄单位句柄
---@field blockId integer 出生区域编号
---@field positionX integer 出生 X 坐标
---@field positionY integer 出生 Y 坐标

---@class HeroSelectPlayerState
---@field playerId integer 玩家编号
---@field candidates string[] 当前三名候选英雄 Rawcode
---@field refreshRemaining integer 剩余刷新次数
---@field submittedRawcode string|nil 已确认的英雄 Rawcode
---@field preselectedRawcode string|nil 本地预选英雄 Rawcode，仅本机 UI 使用
---@field lastRefreshMessage string|nil 最近已处理的刷新消息，用于忽略回声

---@class HeroSelectSession
---@field id integer 选将会话编号
---@field modeSelection ModeSelection 已确认的 PVE 模式
---@field playerIds integer[] 本轮参与选将的玩家编号
---@field players table<integer, HeroSelectPlayerState> 玩家选将状态
---@field remainingSeconds integer 当前剩余秒数
---@field timer timer|nil 同步倒计时计时器
---@field scope table|nil 选将阶段资源作用域
---@field finalSent boolean 房主是否已发送最终结果
---@field completed boolean 是否已完成英雄创建

local current_session = nil
local sync_trigger = nil
local completion_callback = nil
local next_session_id = 1
local sync_available = false
local pending_mode_selection = nil

local dispatch_message
local register_sync_event

local function split_text(value, separator)
    local parts = {}
    local start_index = 1

    while true do
        local separator_start, separator_end = string.find(value, separator, start_index, true)
        if separator_start == nil then
            table.insert(parts, string.sub(value, start_index))
            break
        end

        table.insert(parts, string.sub(value, start_index, separator_start - 1))
        start_index = separator_end + 1
    end

    return parts
end

local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

--- 将四字符 Rawcode 转换为 Warcraft 3 可用的单位整数 ID。
---@param rawcode string 英雄四字符 Rawcode
---@return integer|nil unitId 转换后的单位 ID，输入非法时为 nil
local function rawcode_to_unit_id(rawcode)
    if type(rawcode) ~= "string" or #rawcode ~= 4 then
        return nil
    end

    local first_byte, second_byte, third_byte, fourth_byte = string.byte(rawcode, 1, 4)
    if first_byte == nil or second_byte == nil or third_byte == nil or fourth_byte == nil then
        return nil
    end

    return first_byte * 0x1000000
        + second_byte * 0x10000
        + third_byte * 0x100
        + fourth_byte
end

local function get_local_player_id()
    return jass.GetPlayerId(jass.GetLocalPlayer())
end

local function is_local_host()
    return get_local_player_id() == HOST_PLAYER_ID
end

local function get_sender_id()
    local sender = sync.get_sync_player()
    if sender == nil then
        return nil
    end

    return jass.GetPlayerId(sender)
end

local function random_integer(minimum, maximum)
    if type(random) == "table" and type(random.int) == "function" then
        return random.int(minimum, maximum)
    end
    if minimum >= maximum then
        return minimum
    end
    if type(jass.GetRandomInt) == "function" then
        return jass.GetRandomInt(minimum, maximum)
    end
    return minimum
end

local function contains_rawcode(candidates, rawcode)
    for candidate_index, candidate_rawcode in ipairs(candidates) do
        if candidate_rawcode == rawcode then
            return true
        end
    end

    return false
end

local function get_candidate_signature(candidates)
    local sorted_candidates = {}
    for index, rawcode in ipairs(candidates) do
        sorted_candidates[index] = rawcode
    end
    table.sort(sorted_candidates)
    return table.concat(sorted_candidates, ",")
end

local function draw_candidates(previous_candidates)
    local heroes = hero_pool.get_all()
    local previous_signature = nil
    if previous_candidates ~= nil then
        previous_signature = get_candidate_signature(previous_candidates)
    end

    local result = {}
    local attempt = 0
    repeat
        attempt = attempt + 1
        local available_rawcodes = {}
        for hero_index, hero in ipairs(heroes) do
            table.insert(available_rawcodes, hero.rawcode)
        end

        result = {}
        while #result < config.SETTINGS.candidateCount do
            local picked_index = random_integer(1, #available_rawcodes)
            table.insert(result, available_rawcodes[picked_index])
            table.remove(available_rawcodes, picked_index)
        end
    until previous_signature == nil
        or get_candidate_signature(result) ~= previous_signature
        or attempt >= 12

    if previous_signature ~= nil and get_candidate_signature(result) == previous_signature then
        for hero_index, hero in ipairs(heroes) do
            if not contains_rawcode(result, hero.rawcode) then
                result[1] = hero.rawcode
                break
            end
        end
    end

    return result
end

local function collect_active_player_ids()
    local player_ids = {}
    for player_id = 0, config.SETTINGS.maxPlayerCount - 1 do
        local player_handle = jass.Player(player_id)
        if jass.GetPlayerSlotState(player_handle) == jass.PLAYER_SLOT_STATE_PLAYING
            and jass.GetPlayerController(player_handle) == jass.MAP_CONTROL_USER then
            table.insert(player_ids, player_id)
        end
    end

    return player_ids
end

local function parse_session_id(value)
    local session_id = tonumber(value)
    if not is_integer(session_id) or session_id < 1 then
        return nil
    end

    return session_id
end

local function is_current_session(session_id)
    return current_session ~= nil and current_session.id == session_id and not current_session.completed
end

local function stop_timer(session)
    if session.timer == nil then
        return
    end

    if timer_service ~= nil and type(timer_service.cancel) == "function" then
        if session.scope ~= nil and type(session.scope.detach) == "function" then
            session.scope:detach(session.timer)
        end
        timer_service.cancel(session.timer)
    else
        jass.PauseTimer(session.timer)
        jass.DestroyTimer(session.timer)
    end
    session.timer = nil
end

local function clear_session(session)
    if session == nil then
        return
    end
    if current_session == session and sync_trigger ~= nil then
        if session.scope ~= nil and type(session.scope.detach) == "function" then
            session.scope:detach(sync_trigger)
        end
        if type(jass.DestroyTrigger) == "function" then
            jass.DestroyTrigger(sync_trigger)
        end
        sync_trigger = nil
    end
    stop_timer(session)
    if session.scope ~= nil then
        session.scope:clear()
        session.scope = nil
    end
    popup.hide()
end

local function destroy_sync_trigger()
    if sync_trigger == nil then
        return
    end

    if current_session ~= nil
        and current_session.scope ~= nil
        and type(current_session.scope.detach) == "function" then
        current_session.scope:detach(sync_trigger)
    end
    jass.DestroyTrigger(sync_trigger)
    sync_trigger = nil
end

local function build_local_candidate_definitions(player_state)
    local candidates = {}
    for candidate_index, rawcode in ipairs(player_state.candidates) do
        local hero = hero_pool.get(rawcode)
        if hero ~= nil then
            table.insert(candidates, hero)
        end
    end

    return candidates
end

local function send_pick(player_id, rawcode)
    if current_session == nil then
        return
    end

    local message = string.format("PICK|%d|%d|%s", current_session.id, player_id, rawcode)
    if sync_available then
        sync.send_sync_data(SYNC_PREFIX, message)
        if is_local_host() then
            dispatch_message(message, HOST_PLAYER_ID)
        end
    else
        dispatch_message(message, player_id)
    end
end

local function send_refresh_request(player_id)
    if current_session == nil then
        return
    end

    local message = string.format("REFRESH_REQUEST|%d|%d", current_session.id, player_id)
    if sync_available then
        sync.send_sync_data(SYNC_PREFIX, message)
        if is_local_host() then
            dispatch_message(message, HOST_PLAYER_ID)
        end
    else
        dispatch_message(message, player_id)
    end
end

local function show_local_popup()
    if current_session == nil or current_session.completed then
        return
    end

    local local_player_id = get_local_player_id()
    local player_state = current_session.players[local_player_id]
    if player_state == nil or player_state.submittedRawcode ~= nil then
        return
    end

    local candidates = build_local_candidate_definitions(player_state)
    local shown = popup.show({
        sessionId = current_session.id,
        candidates = candidates,
        remainingSeconds = current_session.remainingSeconds,
        refreshRemaining = player_state.refreshRemaining,
        onHeroSelected = function(rawcode)
            if current_session == nil or current_session.completed then
                return
            end

            local current_state = current_session.players[local_player_id]
            if current_state == nil or current_state.submittedRawcode ~= nil then
                return
            end

            current_state.preselectedRawcode = rawcode
            popup.set_selected(rawcode)
        end,
        onSkillSelected = function(rawcode)
            popup.show_ability_detail(rawcode)
        end,
        onRefresh = function()
            if current_session == nil or current_session.completed then
                return
            end

            local current_state = current_session.players[local_player_id]
            if current_state == nil or current_state.submittedRawcode ~= nil or current_state.refreshRemaining < 1 then
                return
            end

            send_refresh_request(local_player_id)
        end,
        onConfirm = function()
            if current_session == nil or current_session.completed then
                return
            end

            local current_state = current_session.players[local_player_id]
            if current_state == nil
                or current_state.submittedRawcode ~= nil
                or current_state.preselectedRawcode == nil then
                return
            end

            send_pick(local_player_id, current_state.preselectedRawcode)
        end,
    })

    if not shown then
        print("选将界面创建失败：" .. popup.get_last_error())
    elseif player_state.preselectedRawcode ~= nil then
        popup.set_selected(player_state.preselectedRawcode)
    end
end

local function start_timer(session)
    local function on_tick()
        if current_session ~= session or session.completed then
            stop_timer(session)
            return
        end

        session.remainingSeconds = session.remainingSeconds - 1
        popup.set_remaining_seconds(session.remainingSeconds)
        if session.remainingSeconds > 0 then
            return
        end

        stop_timer(session)
        local local_player_id = get_local_player_id()
        local player_state = session.players[local_player_id]
        if player_state == nil or player_state.submittedRawcode ~= nil then
            return
        end

        local random_index = random_integer(1, #player_state.candidates)
        send_pick(local_player_id, player_state.candidates[random_index])
    end

    if timer_service ~= nil and type(timer_service.every) == "function" then
        session.timer = timer_service.every(1.0, on_tick, session.scope)
        if session.timer ~= nil then
            return
        end
    end

    session.timer = jass.CreateTimer()
    jass.TimerStart(session.timer, 1.0, true, on_tick)
end

local function encode_init(session_id, player_ids)
    local records = {}
    for player_index, player_id in ipairs(player_ids) do
        local candidates = draw_candidates(nil)
        table.insert(records, string.format("%d:%s", player_id, table.concat(candidates, ",")))
    end

    return string.format("INIT|%d|%s", session_id, table.concat(records, ";"))
end

local function parse_init(message_parts)
    if #message_parts ~= 3 then
        return nil, "INIT 字段数量错误"
    end

    local session_id = parse_session_id(message_parts[2])
    if session_id == nil then
        return nil, "INIT 会话编号错误"
    end

    local player_ids = {}
    local players = {}
    local records = split_text(message_parts[3], ";")
    for record_index, record in ipairs(records) do
        local record_parts = split_text(record, ":")
        if #record_parts ~= 2 then
            return nil, "INIT 玩家记录错误"
        end

        local player_id = tonumber(record_parts[1])
        if not is_integer(player_id)
            or player_id < 0
            or player_id >= config.SETTINGS.maxPlayerCount
            or players[player_id] ~= nil then
            return nil, "INIT 玩家编号错误"
        end

        local candidates = split_text(record_parts[2], ",")
        if #candidates ~= config.SETTINGS.candidateCount then
            return nil, "INIT 候选数量错误"
        end

        local candidate_seen = {}
        for candidate_index, rawcode in ipairs(candidates) do
            if not hero_pool.contains(rawcode) or candidate_seen[rawcode] then
                return nil, "INIT 含有无效或重复英雄"
            end
            candidate_seen[rawcode] = true
        end

        players[player_id] = {
            playerId = player_id,
            candidates = candidates,
            refreshRemaining = config.SETTINGS.freeRefreshCount,
            submittedRawcode = nil,
            preselectedRawcode = nil,
            lastRefreshMessage = nil,
        }
        table.insert(player_ids, player_id)
    end

    if #player_ids < 1 then
        return nil, "INIT 缺少参与玩家"
    end
    table.sort(player_ids)

    return {
        id = session_id,
        playerIds = player_ids,
        players = players,
    }, nil
end

local function apply_init(message, sender_id)
    if sender_id ~= HOST_PLAYER_ID then
        print("忽略非房主发送的选将 INIT")
        return
    end

    local parsed, message = parse_init(split_text(message, "|"))
    if parsed == nil then
        print("选将 INIT 无效：" .. tostring(message))
        return
    end

    if current_session ~= nil then
        if current_session.id == parsed.id then
            return
        end
        if current_session.id > parsed.id then
            return
        end
        clear_session(current_session)
    end

    if completion_callback == nil then
        print("选将 INIT 被忽略：缺少 PVE 完成回调")
        return
    end

    current_session = {
        id = parsed.id,
        modeSelection = pending_mode_selection,
        playerIds = parsed.playerIds,
        players = parsed.players,
        remainingSeconds = config.SETTINGS.durationSeconds,
        timer = nil,
        scope = resource_api ~= nil and resource_api.scope("hero_select:" .. tostring(parsed.id)) or nil,
        finalSent = false,
        completed = false,
    }
    -- 新会话可能是在旧会话被替换后创建的；旧会话清理时会销毁同步触发器，
    -- 因此这里要确保新会话重新注册，避免选将流程看似启动但再也收不到同步消息。
    if sync_available and sync_trigger == nil then
        if not register_sync_event() then
            sync_available = false
            print("选将会话启动：同步触发器重新注册失败")
        end
    end
    if current_session.scope ~= nil
        and resource_api ~= nil
        and type(resource_api.trigger) == "function" then
        resource_api.trigger(current_session.scope, sync_trigger)
    end
    print(string.format("选将会话已启动：session=%d，玩家数=%d", parsed.id, #parsed.playerIds))
    start_timer(current_session)
    show_local_popup()
end

local function apply_refresh(message, sender_id)
    if sender_id ~= HOST_PLAYER_ID then
        print("忽略非房主发送的刷新结果")
        return
    end

    local parts = split_text(message, "|")
    if #parts ~= 5 then
        print("刷新结果字段数量错误")
        return
    end

    local session_id = parse_session_id(parts[2])
    local player_id = tonumber(parts[3])
    local remaining = tonumber(parts[4])
    if not is_current_session(session_id)
        or not is_integer(player_id)
        or not is_integer(remaining)
        or remaining < 0 then
        print("刷新结果会话或数值错误")
        return
    end

    local player_state = current_session.players[player_id]
    if player_state == nil or player_state.submittedRawcode ~= nil then
        return
    end
    if player_state.lastRefreshMessage == message then
        return
    end

    local candidates = split_text(parts[5], ",")
    if #candidates ~= config.SETTINGS.candidateCount then
        print("刷新结果候选数量错误")
        return
    end

    local candidate_seen = {}
    for candidate_index, rawcode in ipairs(candidates) do
        if not hero_pool.contains(rawcode) or candidate_seen[rawcode] then
            print("刷新结果含有无效或重复英雄")
            return
        end
        candidate_seen[rawcode] = true
    end
    if get_candidate_signature(candidates) == get_candidate_signature(player_state.candidates) then
        print("刷新结果未改变候选组合")
        return
    end

    player_state.candidates = candidates
    player_state.refreshRemaining = remaining
    player_state.preselectedRawcode = nil
    player_state.lastRefreshMessage = message
    if get_local_player_id() == player_id then
        show_local_popup()
    end
end

local function handle_refresh_request(message_parts, sender_id)
    if #message_parts ~= 3 then
        return
    end

    local session_id = parse_session_id(message_parts[2])
    local player_id = tonumber(message_parts[3])
    if not is_current_session(session_id) or not is_integer(player_id) or sender_id ~= player_id then
        return
    end
    if not is_local_host() then
        return
    end

    local player_state = current_session.players[player_id]
    if player_state == nil or player_state.submittedRawcode ~= nil or player_state.refreshRemaining < 1 then
        return
    end

    local refreshed_candidates = draw_candidates(player_state.candidates)
    local refresh_remaining = player_state.refreshRemaining - 1
    local refresh_message = string.format(
        "REFRESH|%d|%d|%d|%s",
        current_session.id,
        player_state.playerId,
        refresh_remaining,
        table.concat(refreshed_candidates, ",")
    )
    apply_refresh(refresh_message, HOST_PLAYER_ID)
    if sync_available then
        sync.send_sync_data(SYNC_PREFIX, refresh_message)
    end
end

local function all_players_submitted(session)
    for player_index, player_id in ipairs(session.playerIds) do
        if session.players[player_id].submittedRawcode == nil then
            return false
        end
    end

    return true
end

local function random_spawn_result(player_id, rawcode)
    local block_index = random_integer(1, #config.SPAWN_BLOCKS)
    local block = config.SPAWN_BLOCKS[block_index]
    local minimum_x = math.ceil(block.minX + config.SETTINGS.spawnInset)
    local maximum_x = math.floor(block.maxX - config.SETTINGS.spawnInset)
    local minimum_y = math.ceil(block.minY + config.SETTINGS.spawnInset)
    local maximum_y = math.floor(block.maxY - config.SETTINGS.spawnInset)
    return {
        playerId = player_id,
        rawcode = rawcode,
        blockId = block.id,
        positionX = random_integer(minimum_x, maximum_x),
        positionY = random_integer(minimum_y, maximum_y),
    }
end

local function encode_final(session)
    local records = {}
    for player_index, player_id in ipairs(session.playerIds) do
        local player_state = session.players[player_id]
        local result = random_spawn_result(player_id, player_state.submittedRawcode)
        table.insert(records, string.format(
            "%d,%s,%d,%d,%d",
            result.playerId,
            result.rawcode,
            result.blockId,
            result.positionX,
            result.positionY
        ))
    end

    -- 随机种子随 FINAL 一次同步，后续 PVE 刷怪不再依赖房主在线。
    local monster_seed = random_integer(1, 2147483646)
    return string.format("FINAL|%d|%d|%s", session.id, monster_seed, table.concat(records, ";"))
end

local function is_valid_spawn_position(block_id, position_x, position_y)
    local block = config.get_spawn_block(block_id)
    if block == nil then
        return false
    end

    local inset = config.SETTINGS.spawnInset
    return position_x >= math.ceil(block.minX + inset)
        and position_x <= math.floor(block.maxX - inset)
        and position_y >= math.ceil(block.minY + inset)
        and position_y <= math.floor(block.maxY - inset)
end

local function apply_final(message, sender_id)
    if sender_id ~= HOST_PLAYER_ID then
        print("忽略非房主发送的选将 FINAL")
        return
    end

    local parts = split_text(message, "|")
    if #parts ~= 4 then
        print("选将 FINAL 字段数量错误")
        return
    end

    local session_id = parse_session_id(parts[2])
    local monster_seed = tonumber(parts[3])
    if not is_current_session(session_id)
        or not is_integer(monster_seed)
        or monster_seed < 1
        or monster_seed > 2147483646 then
        print("选将 FINAL 会话或刷怪随机种子错误")
        return
    end

    local parsed_results = {}
    local records = split_text(parts[4], ";")
    if #records ~= #current_session.playerIds then
        print("选将 FINAL 玩家数量错误")
        return
    end

    for record_index, record in ipairs(records) do
        local fields = split_text(record, ",")
        if #fields ~= 5 then
            print("选将 FINAL 玩家记录错误")
            return
        end

        local player_id = tonumber(fields[1])
        local rawcode = fields[2]
        local block_id = tonumber(fields[3])
        local position_x = tonumber(fields[4])
        local position_y = tonumber(fields[5])
        local player_state = current_session.players[player_id]
        if not is_integer(player_id)
            or not is_integer(block_id)
            or not is_integer(position_x)
            or not is_integer(position_y)
            or player_state == nil
            or parsed_results[player_id] ~= nil
            or not contains_rawcode(player_state.candidates, rawcode)
            or player_state.submittedRawcode ~= rawcode
            or not is_valid_spawn_position(block_id, position_x, position_y) then
            print("选将 FINAL 含有非法英雄或出生坐标")
            return
        end

        parsed_results[player_id] = {
            playerId = player_id,
            rawcode = rawcode,
            blockId = block_id,
            positionX = position_x,
            positionY = position_y,
        }
    end

    current_session.completed = true
    stop_timer(current_session)
    popup.hide()

    local selection_results = {}
    for _, player_id in ipairs(current_session.playerIds) do
        local result = parsed_results[player_id]
        local hero = hero_pool.get(result.rawcode)
        local unit_id = rawcode_to_unit_id(result.rawcode)
        if unit_id == nil then
            print("选将 FINAL 含有无法转换的英雄 Rawcode")
            return
        end

        local hero_unit = jass.CreateUnit(jass.Player(player_id), unit_id, result.positionX, result.positionY, 270.0)
        table.insert(selection_results, {
            playerId = player_id,
            hero = hero,
            unit = hero_unit,
            blockId = result.blockId,
            positionX = result.positionX,
            positionY = result.positionY,
        })
    end

    print(string.format("选将完成：session=%d，已创建 %d 名英雄", current_session.id, #selection_results))
    destroy_sync_trigger()
    local completed_scope = current_session.scope
    current_session.scope = nil
    if completed_scope ~= nil then
        completed_scope:clear()
    end
    if completion_callback ~= nil then
        completion_callback(current_session.modeSelection, selection_results, monster_seed)
    end
end

local function maybe_send_final()
    if current_session == nil
        or current_session.completed
        or current_session.finalSent
        or not is_local_host()
        or not all_players_submitted(current_session) then
        return
    end

    current_session.finalSent = true
    local final_message = encode_final(current_session)
    apply_final(final_message, HOST_PLAYER_ID)
    if sync_available then
        sync.send_sync_data(SYNC_PREFIX, final_message)
    end
end

local function apply_pick(message_parts, sender_id)
    if #message_parts ~= 4 then
        return
    end

    local session_id = parse_session_id(message_parts[2])
    local player_id = tonumber(message_parts[3])
    local rawcode = message_parts[4]
    if not is_current_session(session_id) or not is_integer(player_id) or sender_id ~= player_id then
        return
    end

    local player_state = current_session.players[player_id]
    if player_state == nil
        or player_state.submittedRawcode ~= nil
        or not contains_rawcode(player_state.candidates, rawcode) then
        return
    end

    player_state.submittedRawcode = rawcode
    player_state.preselectedRawcode = nil
    if get_local_player_id() == player_id then
        popup.hide()
    end
    maybe_send_final()
end

local function apply_grant(message, sender_id)
    if sender_id ~= HOST_PLAYER_ID then
        return
    end

    local parts = split_text(message, "|")
    if #parts ~= 5 then
        return
    end

    local session_id = parse_session_id(parts[2])
    local player_id = tonumber(parts[3])
    local amount = tonumber(parts[4])
    local remaining = tonumber(parts[5])
    if not is_current_session(session_id)
        or not is_integer(player_id)
        or not is_integer(amount)
        or not is_integer(remaining)
        or amount < 1
        or remaining < 0 then
        return
    end

    local player_state = current_session.players[player_id]
    if player_state == nil or player_state.submittedRawcode ~= nil then
        return
    end

    player_state.refreshRemaining = remaining
    if get_local_player_id() == player_id then
        popup.set_refresh_remaining(remaining)
    end
end

dispatch_message = function(message, sender_id)
    local message_parts = split_text(message, "|")
    local message_type = message_parts[1]
    if message_type == "INIT" then
        apply_init(message, sender_id)
    elseif message_type == "REFRESH_REQUEST" then
        handle_refresh_request(message_parts, sender_id)
    elseif message_type == "REFRESH" then
        apply_refresh(message, sender_id)
    elseif message_type == "PICK" then
        apply_pick(message_parts, sender_id)
    elseif message_type == "FINAL" then
        apply_final(message, sender_id)
    elseif message_type == "GRANT" then
        apply_grant(message, sender_id)
    end
end

register_sync_event = function()
    sync_trigger = jass.CreateTrigger()
    jass.TriggerAddAction(sync_trigger, function()
        local message = sync.get_sync_data()
        local sender_id = get_sender_id()
        if type(message) ~= "string" or sender_id == nil then
            return
        end

        dispatch_message(message, sender_id)
    end)

    if not sync.register_sync_data(sync_trigger, SYNC_PREFIX, false) then
        destroy_sync_trigger()
        return false
    end

    return true
end

--- 启动 PVE 的多人随机选将流程。
---@param mode_selection ModeSelection 已确认的 PVE 模式
---@param on_completed fun(modeSelection: ModeSelection, selections: HeroSelectionResult[], monsterSeed: integer) 所有英雄创建后的回调
---@return boolean started 是否成功进入选将流程
function module.start(mode_selection, on_completed)
    print("选将启动：开始初始化")
    if current_session ~= nil or completion_callback ~= nil then
        print("选将启动失败：已有未完成的选将会话")
        return false
    end
    if type(mode_selection) ~= "table" or mode_selection.category ~= "PVE" then
        print("选将启动失败：仅 PVE 模式可进入英雄选择")
        return false
    end
    if type(on_completed) ~= "function" then
        print("选将启动失败：缺少 PVE 完成回调")
        return false
    end

    local player_ids = collect_active_player_ids()
    print(string.format(
        "选将启动：参与玩家=%d，本地玩家=%d，同步接口=%s",
        #player_ids,
        get_local_player_id(),
        tostring(sync.is_available())
    ))
    if #player_ids < 1 then
        print("选将启动失败：未找到参与的玩家")
        return false
    end
    if player_ids[1] ~= HOST_PLAYER_ID then
        print("选将启动失败：房主 Player(0) 未参与游戏")
        return false
    end

    completion_callback = on_completed
    pending_mode_selection = mode_selection
    sync_available = sync.is_available()
    if sync_available and not register_sync_event() then
        sync_available = false
    end

    if not sync_available and #player_ids > 1 then
        print("选将启动失败：未找到 1.27 同步扩展，多人 PVE 不可用")
        completion_callback = nil
        pending_mode_selection = nil
        return false
    end
    if not sync_available then
        print("警告：未找到 1.27 同步扩展，当前仅支持单人选将测试")
    end

    if is_local_host() then
        local session_id = next_session_id
        next_session_id = next_session_id + 1
        local init_message = encode_init(session_id, player_ids)
        apply_init(init_message, HOST_PLAYER_ID)
        if sync_available then
            sync.send_sync_data(SYNC_PREFIX, init_message)
        end
    else
        print("选将启动等待房主 INIT：当前客户端不是 Player(0)")
    end
    return true
end

--- 为当前选将会话的指定玩家增加刷新次数。
--- 该接口只允许房主在已同步的商城或玩法事件中调用。
---@param player player 获得刷新次数的玩家
---@param amount integer 增加次数，必须大于 0
---@return boolean granted 是否已成功同步发放
function module.grant_refresh_count(player, amount)
    if current_session == nil
        or current_session.completed
        or not is_local_host()
        or not is_integer(amount)
        or amount < 1 then
        return false
    end

    local player_id = jass.GetPlayerId(player)
    local player_state = current_session.players[player_id]
    if player_state == nil or player_state.submittedRawcode ~= nil then
        return false
    end

    local remaining = player_state.refreshRemaining + amount
    local message = string.format("GRANT|%d|%d|%d|%d", current_session.id, player_id, amount, remaining)
    apply_grant(message, HOST_PLAYER_ID)
    if sync_available then
        sync.send_sync_data(SYNC_PREFIX, message)
    end
    return true
end

return module
