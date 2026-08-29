--- 肉鸽系统总入口：升级队列、房主权威三选一、同步发放和公共查询。
local jass = require "jass.common"
local config = require "rogue.config"
local state_store = require "rogue.state"
local pool = require "rogue.pool"
local sync = require "rogue.sync"
local attribute = require "rogue.attribute"
local popup = require "rogue.ui.popup"
local hero_stats = require "hero.stats"
local wukong = require "rogue.skills.wukong"
local hero_damage = require "rogue.skills.hero_damage"
local debug = require "rogue.debug"

local module = {}
local VERSION = 1
local started = false
local sync_available = false
local critical_enabled = false
local session_seed = 1
local session_id = 1
local level_trigger = nil
local countdown_timer = nil
local local_selection = {}

local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

local function count_states()
    local count = 0
    for _ in pairs(state_store.get_all()) do count = count + 1 end
    return count
end

local function contains(choices, effect_id)
    for _, id in ipairs(choices or {}) do if id == effect_id then return true end end
    return false
end

local function rebuild_modifiers(state)
    state.common = {}
    state.skills = {}
    for effect_id, level in pairs(state.owned) do
        local effect = config.get_effect(effect_id)
        if effect ~= nil and level > 0 then
            local value = effect.values[level] or 0
            if effect.type == "Common" then
                state.common[effect.modifierKey] = (state.common[effect.modifierKey] or 0) + value
            elseif effect.type == "Skill" then
                state.skills[effect.skill] = state.skills[effect.skill] or {}
                local skill = state.skills[effect.skill]
                skill[effect.modifierKey] = (skill[effect.modifierKey] or 0) + value
            end
        end
    end
end

local function show_local_offer(state)
    if sync.get_local_player_id() ~= state.playerId or state.currentOffer == nil then return end
    local offer = state.currentOffer
    local choices = {}
    for _, effect_id in ipairs(offer.choices) do
        local effect = config.get_effect(effect_id)
        local current_level = state.owned[effect_id] or 0
        table.insert(choices, {
            effect = effect,
            currentLevel = current_level,
            nextLevel = current_level + 1,
        })
    end
    local_selection[state.playerId] = nil
    local shown = popup.show({
        hero = state.heroDefinition,
        heroRawcode = state.heroRawcode,
        heroLevel = offer.heroLevel,
        offerSerial = offer.serial,
        choices = choices,
        remainingSeconds = offer.remainingSeconds,
        freeRefreshRemaining = offer.freeRefreshRemaining,
        bonusRefreshRemaining = state.bonusRefreshCount,
        onSelected = function(effect_id)
            if state.currentOffer == offer and contains(offer.choices, effect_id) then
                local_selection[state.playerId] = effect_id
                popup.set_selected(effect_id)
            end
        end,
        onRefresh = function()
            if state.currentOffer ~= offer then return end
            sync.send_request(string.format(
                "REFRESH_REQUEST|%d|%d|%d|%d|%d",
                VERSION, session_id, state.playerId, offer.serial, offer.revision
            ))
        end,
        onConfirm = function()
            local effect_id = local_selection[state.playerId]
            if state.currentOffer ~= offer or effect_id == nil then return end
            sync.send_request(string.format(
                "PICK_REQUEST|%d|%d|%d|%d|%d|%s",
                VERSION, session_id, state.playerId, offer.serial, offer.revision, effect_id
            ))
        end,
    })
    if not shown then print("肉鸽界面显示失败：" .. popup.get_last_error()) end
end

local function encode_offer(state, serial, revision, choices, free_refresh, bonus_refresh)
    local hero_level = type(jass.GetHeroLevel) == "function" and jass.GetHeroLevel(state.hero) or 1
    return string.format(
        "OFFER|%d|%d|%d|%d|%d|%d|%d|%d|%s",
        VERSION, session_id, state.playerId, serial, revision, hero_level,
        free_refresh, bonus_refresh, table.concat(choices, ",")
    )
end

local open_next_offer

local function apply_offer(parts, sender_id)
    if sender_id ~= config.data.settings.hostPlayerId or #parts ~= 10 then return end
    local version = tonumber(parts[2])
    local incoming_session = tonumber(parts[3])
    local player_id = tonumber(parts[4])
    local serial = tonumber(parts[5])
    local revision = tonumber(parts[6])
    local hero_level = tonumber(parts[7])
    local free_refresh = tonumber(parts[8])
    local bonus_refresh = tonumber(parts[9])
    if version ~= VERSION or incoming_session ~= session_id or not is_integer(player_id)
        or not is_integer(serial) or serial < 1 or not is_integer(revision) or revision < 0
        or not is_integer(hero_level) or not is_integer(free_refresh) or free_refresh < 0
        or not is_integer(bonus_refresh) or bonus_refresh < 0 then return end
    local state = state_store.get_by_player_id(player_id)
    if state == nil then return end
    local choices = sync.split(parts[10], ",")
    if #choices ~= config.data.settings.choiceCount then return end
    local seen = {}
    for _, effect_id in ipairs(choices) do
        local effect = config.get_effect(effect_id)
        if effect == nil or seen[effect_id] or (state.owned[effect_id] or 0) >= effect.maxLevel
            or (effect.type == "Skill" and effect.hero ~= state.heroRawcode) then return end
        seen[effect_id] = true
    end
    local current = state.currentOffer
    if serial < state.offerSerial then return end
    if serial == state.offerSerial then
        if current == nil or revision <= current.revision then return end
    else
        if revision ~= 0 then return end
        state.pendingRewards = math.max(0, state.pendingRewards - 1)
    end
    state.offerSerial = serial
    state.bonusRefreshCount = bonus_refresh
    state.currentOffer = {
        serial = serial,
        revision = revision,
        heroLevel = hero_level,
        choices = choices,
        freeRefreshRemaining = free_refresh,
        remainingSeconds = config.data.settings.durationSeconds,
    }
    show_local_offer(state)
end

local function apply_reward(parts, sender_id)
    if sender_id ~= config.data.settings.hostPlayerId or #parts ~= 9 then return end
    local version = tonumber(parts[2])
    local incoming_session = tonumber(parts[3])
    local player_id = tonumber(parts[4])
    local serial = tonumber(parts[5])
    local revision = tonumber(parts[6])
    local effect_id = parts[7]
    local new_level = tonumber(parts[8])
    -- 字段 9 是协议保留校验位，首版固定为 1。
    local applied_flag = tonumber(parts[9])
    if version ~= VERSION or incoming_session ~= session_id or applied_flag ~= 1
        or not is_integer(player_id) or not is_integer(new_level) then return end
    local state = state_store.get_by_player_id(player_id)
    local offer = state and state.currentOffer or nil
    if offer == nil or offer.serial ~= serial or offer.revision ~= revision
        or not contains(offer.choices, effect_id) then return end
    local apply_key = string.format("%d:%d", serial, revision)
    if state.processedApplies[apply_key] then return end
    local effect = config.get_effect(effect_id)
    if effect == nil or new_level ~= (state.owned[effect_id] or 0) + 1 or new_level > effect.maxLevel then return end
    state.processedApplies[apply_key] = true
    state.owned[effect_id] = new_level
    state.currentOffer = nil
    rebuild_modifiers(state)
    attribute.refresh(state)
    if sync.get_local_player_id() == player_id then
        local_selection[player_id] = nil
        popup.hide()
        print(string.format("获得肉鸽强化：%s Lv.%d", effect.name, new_level))
    end
    if sync.is_host() then open_next_offer(state) end
end

-- 使用显式第九字段，便于旧客户端在协议扩展时拒绝错误 APPLY。
local function issue_apply(state, effect_id)
    local offer = state.currentOffer
    if offer == nil or not contains(offer.choices, effect_id) then return false end
    local effect = config.get_effect(effect_id)
    local new_level = (state.owned[effect_id] or 0) + 1
    if effect == nil or new_level > effect.maxLevel then return false end
    sync.broadcast(string.format(
        "APPLY|%d|%d|%d|%d|%d|%s|%d|1",
        VERSION, session_id, state.playerId, offer.serial, offer.revision, effect_id, new_level
    ))
    return true
end

local function handle_pick_request(parts, sender_id)
    if not sync.is_host() or #parts ~= 7 then return end
    local player_id = tonumber(parts[4])
    local serial = tonumber(parts[5])
    local revision = tonumber(parts[6])
    local effect_id = parts[7]
    if tonumber(parts[2]) ~= VERSION or tonumber(parts[3]) ~= session_id
        or sender_id ~= player_id or not is_integer(player_id) then return end
    local state = state_store.get_by_player_id(player_id)
    local offer = state and state.currentOffer or nil
    if offer == nil or offer.serial ~= serial or offer.revision ~= revision then return end
    issue_apply(state, effect_id)
end

local function handle_refresh_request(parts, sender_id)
    if not sync.is_host() or #parts ~= 6 then return end
    local player_id = tonumber(parts[4])
    local serial = tonumber(parts[5])
    local revision = tonumber(parts[6])
    if tonumber(parts[2]) ~= VERSION or tonumber(parts[3]) ~= session_id
        or sender_id ~= player_id or not is_integer(player_id) then return end
    local state = state_store.get_by_player_id(player_id)
    local offer = state and state.currentOffer or nil
    if offer == nil or offer.serial ~= serial or offer.revision ~= revision then return end
    local free = offer.freeRefreshRemaining
    local bonus = state.bonusRefreshCount
    if free <= 0 and bonus <= 0 then return end
    if free > 0 then free = free - 1 else bonus = bonus - 1 end
    local choices = pool.draw(state, session_seed, serial, revision + 1, offer.choices)
    if choices == nil then return end
    sync.broadcast(encode_offer(state, serial, revision + 1, choices, free, bonus))
end

local function apply_refresh_grant(parts, sender_id)
    if sender_id ~= config.data.settings.hostPlayerId or #parts ~= 7 then return end
    local player_id = tonumber(parts[4])
    local amount = tonumber(parts[5])
    local new_bonus = tonumber(parts[6])
    local grant_serial = tonumber(parts[7])
    if tonumber(parts[2]) ~= VERSION or tonumber(parts[3]) ~= session_id
        or not is_integer(player_id) or not is_integer(amount) or amount < 1
        or not is_integer(new_bonus) or new_bonus < 0 or not is_integer(grant_serial) then return end
    local state = state_store.get_by_player_id(player_id)
    if state == nil or grant_serial < state.offerSerial then return end
    state.bonusRefreshCount = new_bonus
    if sync.get_local_player_id() == player_id and state.currentOffer ~= nil then
        popup.set_refresh_remaining(state.currentOffer.freeRefreshRemaining, new_bonus)
    end
end

local function dispatch_message(message, sender_id)
    local parts = sync.split(message, "|")
    if parts[1] == "OFFER" then apply_offer(parts, sender_id)
    elseif parts[1] == "PICK_REQUEST" then handle_pick_request(parts, sender_id)
    elseif parts[1] == "REFRESH_REQUEST" then handle_refresh_request(parts, sender_id)
    elseif parts[1] == "APPLY" then apply_reward(parts, sender_id)
    elseif parts[1] == "GRANT_REFRESH" then apply_refresh_grant(parts, sender_id) end
end

open_next_offer = function(state)
    if not critical_enabled or not sync.is_host() or state.currentOffer ~= nil or state.pendingRewards <= 0 then return end
    local serial = state.offerSerial + 1
    local choices = pool.draw(state, session_seed, serial, 0, nil)
    if choices == nil then
        print(string.format("肉鸽奖励池不足三项：player=%d", state.playerId))
        return
    end
    sync.broadcast(encode_offer(
        state, serial, 0, choices,
        config.data.settings.freeRefreshPerOffer, state.bonusRefreshCount
    ))
end

local function on_hero_level(hero)
    local state = state_store.get_by_hero(hero)
    if state == nil then return end
    local new_level = jass.GetHeroLevel(hero)
    if new_level <= state.lastObservedHeroLevel then return end
    local first_level = math.max(state.lastObservedHeroLevel + 1, config.data.settings.firstRewardLevel)
    if new_level >= first_level then state.pendingRewards = state.pendingRewards + new_level - first_level + 1 end
    state.lastObservedHeroLevel = new_level
    attribute.refresh(state)
    open_next_offer(state)
end

local function register_level_events()
    level_trigger = jass.CreateTrigger()
    for player_id in pairs(state_store.get_all()) do
        jass.TriggerRegisterPlayerUnitEvent(level_trigger, jass.Player(player_id), jass.EVENT_PLAYER_HERO_LEVEL, nil)
    end
    jass.TriggerAddAction(level_trigger, function() on_hero_level(jass.GetTriggerUnit()) end)
end

local function start_countdown()
    countdown_timer = jass.CreateTimer()
    jass.TimerStart(countdown_timer, 1.0, true, function()
        for _, state in pairs(state_store.get_all()) do
            local offer = state.currentOffer
            if offer ~= nil then
                offer.remainingSeconds = math.max(0, offer.remainingSeconds - 1)
                if sync.get_local_player_id() == state.playerId then
                    popup.set_remaining_seconds(offer.remainingSeconds)
                end
                if offer.remainingSeconds <= 0 and sync.is_host() then
                    local selected = offer.choices[1]
                    for _, effect_id in ipairs(offer.choices) do
                        if (state.owned[effect_id] or 0) > 0 then selected = effect_id break end
                    end
                    issue_apply(state, selected)
                end
            end
        end
    end)
end

function module.preload(on_completed)
    return hero_stats.preload(on_completed)
end

function module.start(hero_results, seed)
    if started then return false end
    local valid, errors = config.validate()
    if not valid then
        for _, message in ipairs(errors) do print("肉鸽配置错误：" .. message) end
        return false
    end
    started = true
    session_seed = math.max(1, math.floor(tonumber(seed) or 1))
    session_id = session_seed % 2147483647
    if session_id < 1 then session_id = 1 end
    for _, result in ipairs(hero_results or {}) do state_store.create(result) end
    sync_available = sync.start(dispatch_message)
    critical_enabled = sync_available or count_states() <= 1
    if not sync_available and count_states() > 1 then
        print("肉鸽系统已禁用奖励发放：多人模式缺少 1.27 同步接口")
    elseif not sync_available then
        print("肉鸽系统使用单人本地权威模式")
    end
    register_level_events()
    start_countdown()
    wukong.start(hero_results or {}, session_seed)
    hero_damage.start(hero_results or {}, session_seed)
    debug.start(module)
    print(string.format("肉鸽系统已启动：玩家=%d，同步=%s", count_states(), tostring(sync_available)))
    return true
end

function module.get_skill_value(hero, skill_rawcode, modifier_key)
    local state = state_store.get_by_hero(hero)
    local skill = state and state.skills[skill_rawcode] or nil
    return skill and skill[modifier_key] or 0
end

function module.get_common_value(hero, modifier_key)
    local state = state_store.get_by_hero(hero)
    return state and state.common[modifier_key] or 0
end

function module.refresh_hero_stats(hero)
    return attribute.refresh(state_store.get_by_hero(hero))
end

function module.grant_refresh_count(player_id, amount)
    if not started or not critical_enabled or not sync.is_host()
        or not is_integer(player_id) or not is_integer(amount) or amount < 1 then return false end
    local state = state_store.get_by_player_id(player_id)
    if state == nil then return false end
    local new_bonus = state.bonusRefreshCount + amount
    sync.broadcast(string.format(
        "GRANT_REFRESH|%d|%d|%d|%d|%d|%d",
        VERSION, session_id, player_id, amount, new_bonus, state.offerSerial
    ))
    return true
end

function module.debug_force_offer(player_id)
    local state = state_store.get_by_player_id(player_id)
    if state == nil or not sync.is_host() then return false end
    state.pendingRewards = state.pendingRewards + 1
    open_next_offer(state)
    return true
end

function module.debug_timeout(player_id)
    local state = state_store.get_by_player_id(player_id)
    if state == nil or state.currentOffer == nil then return false end
    state.currentOffer.remainingSeconds = 1
    return true
end

return module
