--- PVE 英雄经验系统。
--- 负责自定义 25 级经验、怪物经验结算、经验加成与多人同步。
local jass = require "jass.common"
local config = require "config.experience"
local units = require "config.units"
local monster_config = require "monster.config"
local formula = require "experience.formula"
local sync = require "experience.sync"
local damage_service = require "combat.damage"
local hero_stats = require "hero.stats"
local events = JiuDou.core and JiuDou.core.events

local module = {}

local HOST_PLAYER_ID = 0
local MAX_PLAYER_ID = 11
local NEUTRAL_HOSTILE_PLAYER_ID = 12

local started = false
local sync_available = false
local death_trigger = nil
local next_event_id = 0
local last_applied_event_id = 0
local difficulty_mode_id = 1
local difficulty_level = 1
local states_by_player = {}
local states_by_hero = {}
local hero_players = {}
local active_players = {}
local monster_by_unit = {}
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

local function get_player(player_id)
    if not valid_player_id(player_id) or type(jass.Player) ~= "function" then return nil end
    return jass.Player(player_id)
end

local function get_handle_id(handle)
    if handle == nil or type(jass.GetHandleId) ~= "function" then return nil end
    return jass.GetHandleId(handle)
end

local function get_player_id_from_unit(unit_handle)
    local handle_id = get_handle_id(unit_handle)
    if handle_id ~= nil and hero_players[handle_id] ~= nil then
        return hero_players[handle_id]
    end
    if unit_handle == nil or type(jass.GetOwningPlayer) ~= "function" or type(jass.GetPlayerId) ~= "function" then
        return nil
    end
    local owner = jass.GetOwningPlayer(unit_handle)
    if owner == nil then return nil end
    local player_id = jass.GetPlayerId(owner)
    return active_players[player_id] and player_id or nil
end

local function level_config(level)
    local levels = config.levels or {}
    return levels[tostring(level)] or levels[level]
end

local function max_level()
    return math.max(1, math.floor(tonumber(config.settings and config.settings.maxLevel) or 25))
end

local function required_exp(level)
    local entry = level_config(level)
    return math.max(0, math.floor(tonumber(entry and entry.requiredExp) or 0))
end

local function calculate_progress(total_exp)
    local remaining = math.max(0, math.floor(tonumber(total_exp) or 0))
    local maximum = max_level()
    for level = 1, maximum - 1 do
        local required = required_exp(level)
        if remaining < required then
            return level, remaining, required
        end
        remaining = remaining - required
    end
    return maximum, 0, 0
end

local function copy_state(state)
    if state == nil then
        return { level = 1, maxLevel = max_level(), totalExp = 0, currentExp = 0, nextLevelExp = required_exp(1), bonusPercent = 0 }
    end
    return {
        level = state.level,
        maxLevel = max_level(),
        totalExp = state.totalExp,
        currentExp = state.currentExp,
        nextLevelExp = state.nextLevelExp,
        bonusPercent = state.bonusPercent,
    }
end

local function notify(player_id)
    local state = states_by_player[player_id]
    if state == nil then return end
    local snapshot = copy_state(state)
    for _, listener in ipairs(listeners) do
        pcall(listener, state.hero, snapshot)
    end
end

local function set_native_xp_handicap(player_id)
    local player = get_player(player_id)
    if player ~= nil and type(jass.SetPlayerHandicapXP) == "function" then
        jass.SetPlayerHandicapXP(player, 0.0)
        return true
    end
    return false
end

local function set_native_level(hero, previous_level, next_level)
    if hero == nil or type(jass.SetHeroLevel) ~= "function" then return false end
    if next_level <= previous_level then return true end
    for level = previous_level + 1, next_level do
        jass.SetHeroLevel(hero, level, false)
    end
    return true
end

local function refresh_state(state, total_exp, force_level)
    local previous_level = state.level
    local level, current_exp, next_level_exp = calculate_progress(total_exp)
    state.totalExp = math.max(0, math.floor(tonumber(total_exp) or 0))
    state.level = force_level or level
    state.currentExp = current_exp
    state.nextLevelExp = next_level_exp
    if state.level > previous_level then
        set_native_level(state.hero, previous_level, state.level)
        hero_stats.refresh(state.hero)
    end
end

local function get_bonus(state)
    local maximum = math.max(0, math.floor(tonumber(config.settings and config.settings.maxExpBonusPercent) or 100))
    return math.max(0, math.min(maximum, math.floor(tonumber(state and state.bonusPercent) or 0)))
end

local function apply_state(event_id, player_id, total_exp, bonus_percent)
    if event_id <= last_applied_event_id or not valid_player_id(player_id) then return false end
    local state = states_by_player[player_id]
    if state == nil then return false end
    last_applied_event_id = event_id
    state.bonusPercent = math.max(0, math.min(
        math.floor(tonumber(config.settings and config.settings.maxExpBonusPercent) or 100),
        math.floor(tonumber(bonus_percent) or 0)
    ))
    refresh_state(state, total_exp)
    notify(player_id)
    return true
end

local function on_sync_message(message, sender_id)
    local parts = sync.split(message or "", "|")
    if parts[1] ~= "STATE" or parts[2] ~= tostring(sync.get_version()) then return end
    if sender_id ~= nil and sender_id ~= HOST_PLAYER_ID then return end
    local event_id = parse_integer(parts[3])
    local player_id = parse_integer(parts[4])
    local total_exp = parse_integer(parts[5])
    local bonus_percent = parse_integer(parts[6])
    if event_id == nil or player_id == nil or total_exp == nil or bonus_percent == nil
        or event_id <= 0 or total_exp < 0 or bonus_percent < 0 then
        return
    end
    apply_state(event_id, player_id, total_exp, bonus_percent)
end

local function broadcast_state(player_id)
    local state = states_by_player[player_id]
    if state == nil then return false end
    next_event_id = next_event_id + 1
    local message = table.concat({
        "STATE",
        tostring(sync.get_version()),
        tostring(next_event_id),
        tostring(player_id),
        tostring(state.totalExp),
        tostring(get_bonus(state)),
    }, "|")
    return sync.broadcast(message)
end

local broadcast_state_after_update

local function award_player(player_id, raw_amount)
    local state = states_by_player[player_id]
    if state == nil or state.level >= max_level() or raw_amount <= 0 then return false end
    local amount = formula.apply_bonus(
        raw_amount,
        get_bonus(state),
        config.settings and config.settings.maxExpBonusPercent or 100
    )
    if amount <= 0 then return false end
    local next_total = state.totalExp + amount
    return broadcast_state_after_update(player_id, next_total)
end

broadcast_state_after_update = function(player_id, total_exp)
    local state = states_by_player[player_id]
    if state == nil then return false end
    refresh_state(state, total_exp)
    return broadcast_state(player_id)
end

local function settle_monster(info)
    if not sync.is_host() then return end
    local pool = formula.base_reward(units, info.rawcode)
    if pool <= 0 then return end

    local awards = {}
    if info.kind == "normal" then
        local killer = type(jass.GetKillingUnit) == "function" and jass.GetKillingUnit() or nil
        local killer_id = get_player_id_from_unit(killer)
        if killer_id ~= nil then awards[killer_id] = pool end
    else
        awards = formula.split_by_damage(pool, info.contributions)
        if next(awards) == nil then
            local killer = type(jass.GetKillingUnit) == "function" and jass.GetKillingUnit() or nil
            local killer_id = get_player_id_from_unit(killer)
            if killer_id ~= nil then awards[killer_id] = pool end
        end
    end

    for player_id, amount in pairs(awards) do
        award_player(player_id, amount)
    end
end

local function on_damage_report(report)
    if type(report) ~= "table" then return end
    local target = report.target
    local info = monster_by_unit[target]
    if info == nil or (info.kind ~= "elite" and info.kind ~= "boss") then return end
    local source = report.source
    local player_id = get_player_id_from_unit(source)
    local damage = math.floor(tonumber(report.amount) or 0)
    if player_id == nil or damage <= 0 then return end
    local remaining = math.max(0, info.maxLife - info.recordedDamage)
    local effective_damage = math.min(damage, remaining)
    if effective_damage <= 0 then return end
    info.contributions[player_id] = (info.contributions[player_id] or 0) + effective_damage
    info.recordedDamage = info.recordedDamage + effective_damage
end

local function on_unit_death()
    local dying_unit = type(jass.GetDyingUnit) == "function" and jass.GetDyingUnit() or nil
    local info = monster_by_unit[dying_unit]
    if info == nil or info.settled then return end
    info.settled = true
    monster_by_unit[dying_unit] = nil
    settle_monster(info)
end

---@param unit_handle unit 怪物句柄
---@param kind string normal、elite 或 boss
---@param rawcode string 怪物 Rawcode
---@param generation integer 当前刷怪代数
---@param max_life integer 当前 unit.xlsx 变体物编的最大生命
---@return boolean registered 是否注册成功
function module.register_monster(unit_handle, kind, rawcode, generation, max_life)
    if not started or unit_handle == nil or type(rawcode) ~= "string" then return false end
    local base_exp = formula.base_reward(units, rawcode)
    if base_exp <= 0 then
        print("经验系统拒绝注册无效怪物经验：" .. rawcode)
        return false
    end
    monster_by_unit[unit_handle] = {
        kind = kind,
        rawcode = rawcode,
        generation = math.max(1, math.floor(tonumber(generation) or 1)),
        maxLife = math.max(1, math.floor(tonumber(max_life) or 1)),
        recordedDamage = 0,
        contributions = {},
        settled = false,
    }
    return true
end

--- 清理自然到期移除的怪物注册信息；不会结算经验。
---@param unit_handle unit 怪物句柄
---@return boolean removed 是否存在并已移除
function module.unregister_monster(unit_handle)
    if unit_handle == nil or monster_by_unit[unit_handle] == nil then return false end
    monster_by_unit[unit_handle] = nil
    return true
end

function module.get_snapshot(hero)
    return copy_state(states_by_hero[hero])
end

function module.get_exp_bonus(player_id)
    return get_bonus(states_by_player[player_id])
end

function module.set_bonus_source(player_id, source_id, percent)
    if not started or not sync.is_host() or not valid_player_id(player_id)
        or type(source_id) ~= "string" or source_id == "" then return false end
    local state = states_by_player[player_id]
    if state == nil then return false end
    state.sources[source_id] = math.max(0, math.floor(tonumber(percent) or 0))
    local total = math.max(0, math.floor(tonumber(config.settings and config.settings.initialExpBonusPercent) or 0))
    for _, value in pairs(state.sources) do total = total + value end
    state.bonusPercent = math.min(
        math.max(0, math.floor(tonumber(config.settings and config.settings.maxExpBonusPercent) or 100)),
        total
    )
    return broadcast_state(player_id)
end

function module.clear_bonus_source(player_id, source_id)
    return module.set_bonus_source(player_id, source_id, 0)
end

---@param listener fun(hero:unit, snapshot:table)
---@return boolean added 是否添加成功
function module.subscribe(listener)
    if type(listener) ~= "function" then return false end
    table.insert(listeners, listener)
    return true
end

---@param selection ModeSelection PVE 模式选择
---@param hero_results HeroSelectionResult[] 已创建英雄
---@return boolean started_now 是否启动成功
function module.start(selection, hero_results)
    if started then return false end
    local difficulty, message = monster_config.create_difficulty(selection)
    if difficulty == nil then
        print("经验系统启动失败：" .. tostring(message))
        return false
    end
    states_by_player = {}
    states_by_hero = {}
    hero_players = {}
    active_players = {}
    for _, result in ipairs(hero_results or {}) do
        local player_id = result.playerId
        if valid_player_id(player_id) and result.unit ~= nil and states_by_player[player_id] == nil then
            active_players[player_id] = true
            local handle_id = get_handle_id(result.unit)
            if handle_id ~= nil then hero_players[handle_id] = player_id end
            local initial_bonus = math.max(0, math.floor(tonumber(config.settings and config.settings.initialExpBonusPercent) or 0))
            local state = {
                playerId = player_id,
                hero = result.unit,
                totalExp = 0,
                level = 1,
                currentExp = 0,
                nextLevelExp = required_exp(1),
                bonusPercent = initial_bonus,
                sources = {},
            }
            states_by_player[player_id] = state
            states_by_hero[result.unit] = state
            set_native_xp_handicap(player_id)
            if type(jass.SetHeroXP) == "function" then jass.SetHeroXP(result.unit, 0) end
        end
    end
    if next(states_by_player) == nil then
        print("经验系统启动失败：没有有效玩家英雄")
        return false
    end
    difficulty_mode_id = difficulty.modeId
    difficulty_level = difficulty.level
    sync_available = sync.start(on_sync_message)
    if not sync_available and #(hero_results or {}) > 1 then
        print("经验系统已禁用：多人模式缺少同步接口")
        return false
    end
    if type(jass.CreateTrigger) ~= "function" or type(jass.TriggerAddAction) ~= "function"
        or type(jass.TriggerRegisterPlayerUnitEvent) ~= "function" then
        print("经验系统启动失败：缺少触发器接口")
        return false
    end
    death_trigger = jass.CreateTrigger()
    if death_trigger == nil then
        print("经验系统启动失败：触发器创建失败")
        return false
    end
    jass.TriggerRegisterPlayerUnitEvent(
        death_trigger,
        jass.Player(NEUTRAL_HOSTILE_PLAYER_ID),
        jass.EVENT_PLAYER_UNIT_DEATH,
        nil
    )
    jass.TriggerAddAction(death_trigger, on_unit_death)
    if events ~= nil and type(events.on) == "function" then
        events.on("combat.damage", on_damage_report, 0)
    else
        damage_service.subscribe(on_damage_report)
    end
    started = true
    print(string.format("经验系统已启动：英雄等级=%d，经验读取 unit.xlsx 最终变体，模式=%d，难度=%d，玩家=%d", max_level(), difficulty_mode_id, difficulty_level, #hero_results))
    return true
end

function module.is_started() return started end

return module
