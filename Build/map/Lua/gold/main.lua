--- PVE 原生金币系统。
--- 金币账户使用 Warcraft III 原生 PLAYER_STATE_RESOURCE_GOLD；Lua 只保存击杀结算状态。
local jass = require "jass.common"
local config = require "config.gold"
local monster_config = require "monster.config"
local formula = require "gold.formula"
local sync = require "gold.sync"
local damage_numbers = require "combat.damage_numbers"
local damage_service = require "combat.damage"

local module = {}

local HOST_PLAYER_ID = 0
local MAX_PLAYER_ID = 11
local NEUTRAL_HOSTILE_PLAYER_ID = 12
local GOLD_STATE = jass.PLAYER_STATE_RESOURCE_GOLD

local started = false
local sync_available = false
local difficulty_multiplier_percent = 100
local death_trigger = nil
local next_event_id = 0
local last_applied_event_id = 0
local active_players = {}
local hero_players = {}
local gold_bonus_by_player = {}
local gold_bonus_listeners = {}
local monster_by_unit = {}

local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

local function valid_player_id(player_id)
    return is_integer(player_id) and player_id >= 0 and player_id <= MAX_PLAYER_ID
end

local function clamp_gold(value)
    local maximum = math.max(0, math.floor(tonumber(config.settings.maxGold) or 2147483647))
    return math.max(0, math.min(maximum, math.floor(tonumber(value) or 0)))
end

local function get_player(player_id)
    if not valid_player_id(player_id) or type(jass.Player) ~= "function" then
        return nil
    end
    return jass.Player(player_id)
end

local function get_native_gold(player_id)
    local player = get_player(player_id)
    if player == nil or type(jass.GetPlayerState) ~= "function" or GOLD_STATE == nil then
        return 0
    end
    return clamp_gold(jass.GetPlayerState(player, GOLD_STATE))
end

local function set_native_gold(player_id, amount)
    local player = get_player(player_id)
    if player == nil or type(jass.SetPlayerState) ~= "function" or GOLD_STATE == nil then
        return false
    end
    jass.SetPlayerState(player, GOLD_STATE, clamp_gold(amount))
    return true
end

local function get_handle_id(handle)
    if handle == nil or type(jass.GetHandleId) ~= "function" then return nil end
    return jass.GetHandleId(handle)
end

local function get_unit_player_id(unit_handle)
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
    if active_players[player_id] then return player_id end
    return nil
end

local function get_bonus(player_id)
    local maximum = math.max(0, math.floor(tonumber(config.settings.maxGoldDropBonusPercent) or 999))
    return math.max(0, math.min(maximum, math.floor(tonumber(gold_bonus_by_player[player_id]) or 0)))
end

local function notify_gold_bonus_changed(player_id)
    local bonus = get_bonus(player_id)
    for _, listener in ipairs(gold_bonus_listeners) do
        pcall(listener, player_id, bonus)
    end
end

local function parse_integer(value)
    local number = tonumber(value)
    if number == nil or number ~= math.floor(number) then return nil end
    return number
end

local function apply_sync_balance(event_id, player_id, amount, new_balance, x, y)
    if event_id <= last_applied_event_id or not valid_player_id(player_id) or amount < 0 then
        return false
    end
    new_balance = clamp_gold(new_balance)
    if new_balance < 0 then return false end
    last_applied_event_id = event_id
    local applied = set_native_gold(player_id, new_balance)
    if applied and x ~= nil and y ~= nil then
        damage_numbers.show_gold(x, y, amount)
    end
    return applied
end

local function on_sync_message(message, sender_id)
    local parts = sync.split(message or "", "|")
    if (parts[1] ~= "GOLD_AWARD" and parts[1] ~= "GOLD_SPEND") or parts[2] ~= tostring(sync.get_version()) then
        return
    end
    if sender_id ~= nil and sender_id ~= HOST_PLAYER_ID then
        return
    end
    local event_id = parse_integer(parts[3])
    local player_id = parse_integer(parts[4])
    local amount = parse_integer(parts[5])
    local new_balance = parse_integer(parts[6])
    if event_id == nil or player_id == nil or amount == nil or new_balance == nil
        or event_id <= 0 or amount < 0 or new_balance < 0 then
        return
    end
    apply_sync_balance(event_id, player_id, amount, new_balance, tonumber(parts[7]), tonumber(parts[8]))
end

local function broadcast_balance(kind, player_id, amount, new_balance, x, y)
    next_event_id = next_event_id + 1
    local message = table.concat({
        kind,
        tostring(sync.get_version()),
        tostring(next_event_id),
        tostring(player_id),
        tostring(amount),
        tostring(new_balance),
        x ~= nil and tostring(math.floor(x)) or "-",
        y ~= nil and tostring(math.floor(y)) or "-",
    }, "|")
    return sync.broadcast(message)
end

local function on_damage_report(report)
    if type(report) ~= "table" then return end
    local target = report.target
    local info = monster_by_unit[target]
    if info == nil or (info.kind ~= "elite" and info.kind ~= "boss") then return end

    local source = report.source
    local player_id = get_unit_player_id(source)
    local damage = math.floor(tonumber(report.amount) or 0)
    if player_id == nil or damage <= 0 then return end

    local remaining = math.max(0, info.maxLife - info.recordedDamage)
    local effective_damage = math.min(damage, remaining)
    if effective_damage <= 0 then return end
    info.contributions[player_id] = (info.contributions[player_id] or 0) + effective_damage
    info.recordedDamage = info.recordedDamage + effective_damage
end

local function issue_award(player_id, raw_amount, kind, x, y)
    if not valid_player_id(player_id) or raw_amount <= 0 then return false end
    local amount = formula.apply_bonus(raw_amount, get_bonus(player_id), config.settings.maxGoldDropBonusPercent)
    if amount <= 0 then return false end
    local current = get_native_gold(player_id)
    local new_balance = clamp_gold(current + amount)
    local actual_amount = new_balance - current
    if actual_amount <= 0 then return false end
    return broadcast_balance(kind or "GOLD_AWARD", player_id, actual_amount, new_balance, x, y)
end

local function settle_monster(info, dying_unit)
    if not sync.is_host() then return end
    local pool = formula.calculate_pool(
        config,
        info.kind,
        info.level,
        difficulty_multiplier_percent
    )
    if pool <= 0 then return end

    local x = type(jass.GetUnitX) == "function" and jass.GetUnitX(dying_unit) or nil
    local y = type(jass.GetUnitY) == "function" and jass.GetUnitY(dying_unit) or nil
    local awards = {}
    if info.kind == "normal" then
        local killer = type(jass.GetKillingUnit) == "function" and jass.GetKillingUnit() or nil
        local killer_id = get_unit_player_id(killer)
        if killer_id ~= nil then awards[killer_id] = pool end
    else
        awards = formula.split_by_damage(pool, info.contributions)
        if next(awards) == nil then
            local killer = type(jass.GetKillingUnit) == "function" and jass.GetKillingUnit() or nil
            local killer_id = get_unit_player_id(killer)
            if killer_id ~= nil then awards[killer_id] = pool end
        end
    end

    for player_id, amount in pairs(awards) do
        issue_award(player_id, amount, "GOLD_AWARD", x, y)
    end
end

local function on_unit_death()
    local dying_unit = type(jass.GetDyingUnit) == "function" and jass.GetDyingUnit() or nil
    local info = monster_by_unit[dying_unit]
    if info == nil or info.settled then return end
    info.settled = true
    monster_by_unit[dying_unit] = nil
    settle_monster(info, dying_unit)
end

--- 注册新生成的怪物；由 monster.main 在应用难度属性后调用。
---@param unit_handle unit 怪物句柄
---@param kind string normal、elite 或 boss
---@param level integer 怪物等级
---@param generation integer 当前槽位生成代
---@param max_life integer 难度缩放后的最大生命
function module.register_monster(unit_handle, kind, level, generation, max_life)
    if not started or unit_handle == nil then return false end
    local info = {
        kind = kind,
        level = math.max(1, math.min(9, math.floor(tonumber(level) or 1))),
        generation = math.max(1, math.floor(tonumber(generation) or 1)),
        maxLife = math.max(1, math.floor(tonumber(max_life) or 1)),
        recordedDamage = 0,
        contributions = {},
        settled = false,
    }
    monster_by_unit[unit_handle] = info
    return true
end

--- 清理自然到期移除的怪物注册信息；不会结算金币。
---@param unit_handle unit 怪物句柄
---@return boolean removed 是否存在并已移除
function module.unregister_monster(unit_handle)
    if unit_handle == nil or monster_by_unit[unit_handle] == nil then return false end
    monster_by_unit[unit_handle] = nil
    return true
end

function module.get(player_id)
    return get_native_gold(player_id)
end

function module.get_local()
    return module.get(sync.get_local_player_id())
end

function module.get_gold_bonus(player_id)
    return get_bonus(player_id)
end

--- 订阅金币掉落加成变化；监听器只用于本地显示刷新。
---@param listener fun(playerId:integer, newBonusPercent:integer)
---@return boolean added
function module.subscribe_gold_bonus(listener)
    if type(listener) ~= "function" then return false end
    table.insert(gold_bonus_listeners, listener)
    return true
end

--- 增加玩家的金币掉落加成属性；不修改原生金币余额。
function module.add_gold_bonus(player_id, percent)
    if not valid_player_id(player_id) or not is_integer(percent) then return false end
    local next_bonus = math.max(0, get_bonus(player_id) + percent)
    gold_bonus_by_player[player_id] = next_bonus
    notify_gold_bonus_changed(player_id)
    return true
end

--- 房主向指定玩家发放金币；未来商店、任务奖励等系统可复用。
function module.add(player_id, amount, reason)
    if not started or not sync.is_host() or not valid_player_id(player_id) or not is_integer(amount) or amount <= 0 then
        return false
    end
    return issue_award(player_id, amount, "GOLD_AWARD")
end

--- 房主尝试扣除原生金币；未来神秘商店可复用。
function module.try_spend(player_id, amount, reason)
    if not started or not sync.is_host() or not valid_player_id(player_id) or not is_integer(amount) or amount <= 0 then
        return false
    end
    local current = get_native_gold(player_id)
    if current < amount then return false end
    return broadcast_balance("GOLD_SPEND", player_id, amount, current - amount)
end

function module.start(selection, hero_results)
    if started then return false end
    local difficulty, message = monster_config.create_difficulty(selection)
    if difficulty == nil then
        print("金币系统启动失败：" .. tostring(message))
        return false
    end

    hero_results = hero_results or {}
    local active_count = 0
    for _, result in ipairs(hero_results) do
        local player_id = result.playerId
        if valid_player_id(player_id) and result.unit ~= nil and not active_players[player_id] then
            active_players[player_id] = true
            active_count = active_count + 1
            local handle_id = get_handle_id(result.unit)
            if handle_id ~= nil then hero_players[handle_id] = player_id end
        end
    end
    if active_count <= 0 then
        print("金币系统启动失败：没有有效玩家英雄")
        return false
    end

    sync_available = sync.start(on_sync_message)
    if not sync_available and active_count > 1 then
        print("金币系统已禁用：多人模式缺少同步接口")
        return false
    end

    difficulty_multiplier_percent = math.max(0, math.floor(tonumber(difficulty.goldMultiplierPercent) or 100))
    for player_id in pairs(active_players) do
        set_native_gold(player_id, config.settings.initialGold)
        gold_bonus_by_player[player_id] = 0
        notify_gold_bonus_changed(player_id)
    end

    if type(jass.CreateTrigger) ~= "function" or type(jass.TriggerAddAction) ~= "function" then
        print("金币系统启动失败：缺少触发器接口")
        return false
    end
    death_trigger = jass.CreateTrigger()
    if death_trigger == nil then
        print("金币系统启动失败：触发器创建失败")
        return false
    end
    if type(jass.TriggerRegisterPlayerUnitEvent) ~= "function" then
        print("金币系统启动失败：缺少单位死亡事件接口")
        return false
    end
    jass.TriggerRegisterPlayerUnitEvent(death_trigger, jass.Player(NEUTRAL_HOSTILE_PLAYER_ID), jass.EVENT_PLAYER_UNIT_DEATH, nil)
    jass.TriggerAddAction(death_trigger, on_unit_death)
    damage_service.subscribe(on_damage_report)
    started = true
    print(string.format("金币系统已启动：难度金币倍率=%d%%，玩家=%d", difficulty_multiplier_percent, active_count))
    return true
end

function module.is_started()
    return started
end

return module
