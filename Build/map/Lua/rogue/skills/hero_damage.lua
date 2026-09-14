--- 哪吒、牛魔王的主属性伤害结算。
--- 原生技能仅保留位移、减速、眩晕等非伤害效果；伤害统一由本模块按倍率计算。
local jass = require "jass.common"
local config = require "rogue.config"
local state_store = require "rogue.state"
local skill_damage = require "combat.skill_damage"
local damage_service = require "combat.damage"

local module = {}
local started = false
local heroes = {}
local states = {}
local spell_trigger = nil
local attack_trigger = nil
local clock_timer = nil
local event_sequence = 0
local session_seed = 1
local now = 0

local MODULUS = 2147483647
local N1_ID, N2_ID, N4_ID = nil, nil, nil
local B1_ID, B4_ID = nil, nil

local function rawcode_to_integer(rawcode)
    if type(rawcode) ~= "string" or #rawcode ~= 4 then return nil end
    local a, b, c, d = string.byte(rawcode, 1, 4)
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local function is_alive(unit_handle)
    if unit_handle == nil or type(jass.GetUnitState) ~= "function" then return false end
    return jass.GetUnitState(unit_handle, jass.UNIT_STATE_LIFE) > 0.405
end

local function ability_level(hero, ability_id)
    return type(jass.GetUnitAbilityLevel) == "function" and (jass.GetUnitAbilityLevel(hero, ability_id) or 0) or 0
end

local function common_value(hero, key)
    local state = state_store.get_by_hero(hero)
    return state and state.common[key] or 0
end

local function state_for(hero)
    local state = states[hero]
    if state == nil then
        state = { cooldowns = {} }
        states[hero] = state
    end
    return state
end

local function scaled_damage(hero, hero_rawcode, ability_rawcode, prefix, level)
    local runtime = config.get_skill_runtime(hero_rawcode, ability_rawcode)
    if runtime == nil then return 0 end
    local attribute_key = prefix == "" and "damageAttribute" or (prefix .. "DamageAttribute")
    local multiplier_key = prefix == "" and "damageMultiplierTenth" or (prefix .. "DamageMultiplierTenth")
    local attribute = runtime[attribute_key]
    local multipliers = runtime[multiplier_key]
    if type(attribute) ~= "string" or type(multipliers) ~= "table" then return 0 end
    local multiplier = multipliers[level] or multipliers[#multipliers] or 0
    return skill_damage.calculate(hero, attribute, multiplier, common_value(hero, "skill_damage_percent"))
end

local function damage(hero, target, amount, damage_type)
    if amount <= 0 or not is_alive(target) or type(jass.IsUnitEnemy) ~= "function"
        or not jass.IsUnitEnemy(target, jass.GetOwningPlayer(hero)) then
        return
    end
    damage_service.deal(hero, target, amount, damage_type)
end

local function enemies_in_range(hero, x, y, radius)
    local result = {}
    if type(jass.CreateGroup) ~= "function" or type(jass.GroupEnumUnitsInRange) ~= "function"
        or type(jass.ForGroup) ~= "function" then
        return result
    end
    local group = jass.CreateGroup()
    jass.GroupEnumUnitsInRange(group, x, y, radius, nil)
    jass.ForGroup(group, function()
        local target = jass.GetEnumUnit()
        if is_alive(target) and jass.IsUnitEnemy(target, jass.GetOwningPlayer(hero)) then
            table.insert(result, target)
        end
    end)
    if type(jass.DestroyGroup) == "function" then jass.DestroyGroup(group) end
    table.sort(result, function(left, right)
        if type(jass.GetHandleId) == "function" then return jass.GetHandleId(left) < jass.GetHandleId(right) end
        return tostring(left) < tostring(right)
    end)
    return result
end

local function damage_area(hero, x, y, radius, amount)
    for _, target in ipairs(enemies_in_range(hero, x, y, radius)) do
        damage(hero, target, amount)
    end
end

local function distance_to_segment_squared(x, y, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local length_squared = dx * dx + dy * dy
    if length_squared <= 0 then
        local ex, ey = x - ax, y - ay
        return ex * ex + ey * ey
    end
    local t = ((x - ax) * dx + (y - ay) * dy) / length_squared
    t = math.max(0, math.min(1, t))
    local px, py = ax + t * dx, ay + t * dy
    local ex, ey = x - px, y - py
    return ex * ex + ey * ey
end

local function damage_charge_line(hero, start_x, start_y, end_x, end_y, radius, amount)
    local length = math.sqrt((end_x - start_x) ^ 2 + (end_y - start_y) ^ 2)
    local search_radius = math.max(radius, length + radius)
    for _, target in ipairs(enemies_in_range(hero, start_x, start_y, search_radius)) do
        local x, y = jass.GetUnitX(target), jass.GetUnitY(target)
        if distance_to_segment_squared(x, y, start_x, start_y, end_x, end_y) <= radius * radius then
            damage(hero, target, amount)
        end
    end
end

local function deterministic_percent(hero, salt)
    event_sequence = event_sequence + 1
    local handle_id = type(jass.GetHandleId) == "function" and jass.GetHandleId(hero) or 1
    local value = (session_seed + event_sequence * 48271 + handle_id * 97 + salt * 7919) % MODULUS
    return value % 100 + 1
end

local function list_value(values, level)
    return type(values) == "table" and (values[level] or values[#values] or 0) or 0
end

local function cast_spell(hero, hero_rawcode, ability_id)
    if hero_rawcode == "H0N0" and ability_id == N1_ID then
        local level = ability_level(hero, N1_ID)
        local amount = scaled_damage(hero, hero_rawcode, "A0N1", "", level)
        damage_area(hero, jass.GetUnitX(hero), jass.GetUnitY(hero), 250, amount)
    elseif hero_rawcode == "H0N0" and ability_id == N2_ID then
        local level = ability_level(hero, N2_ID)
        local start_x, start_y = jass.GetUnitX(hero), jass.GetUnitY(hero)
        local target_x = type(jass.GetSpellTargetX) == "function" and jass.GetSpellTargetX() or start_x
        local target_y = type(jass.GetSpellTargetY) == "function" and jass.GetSpellTargetY() or start_y
        local amount = scaled_damage(hero, hero_rawcode, "A0N2", "", level)
        damage_charge_line(hero, start_x, start_y, target_x, target_y, 180, amount)
    elseif hero_rawcode == "H0B0" and ability_id == B1_ID then
        local level = ability_level(hero, B1_ID)
        local amount = scaled_damage(hero, hero_rawcode, "A0B1", "", level)
        damage_area(hero, jass.GetUnitX(hero), jass.GetUnitY(hero), 250, amount)
    end
end

local function proc_attack(hero, hero_rawcode, target)
    if hero_rawcode == "H0N0" then
        local level = ability_level(hero, N4_ID)
        if level <= 0 then return end
        local runtime = config.get_skill_runtime(hero_rawcode, "A0N4")
        if deterministic_percent(hero, 41) <= list_value(runtime.procChance, level) then
            damage(hero, target, scaled_damage(hero, hero_rawcode, "A0N4", "proc", level), jass.DAMAGE_TYPE_NORMAL)
        end
    end
end

local function bull_counterattack(hero, attacker)
    local level = ability_level(hero, B4_ID)
    if level <= 0 then return end
    local runtime = config.get_skill_runtime("H0B0", "A0B4")
    local state = state_for(hero)
    if now < (state.cooldowns.A0B4 or 0) then return end
    local amount = scaled_damage(hero, "H0B0", "A0B4", "proc", level)
    damage_area(hero, jass.GetUnitX(hero), jass.GetUnitY(hero), runtime.procArea or 250, amount)
    state.cooldowns.A0B4 = now + math.max(0, tonumber(runtime.procCooldown) or 0)
end

local function register_events()
    spell_trigger = jass.CreateTrigger()
    attack_trigger = jass.CreateTrigger()
    for player_id = 0, 15 do
        local player = jass.Player(player_id)
        jass.TriggerRegisterPlayerUnitEvent(spell_trigger, player, jass.EVENT_PLAYER_UNIT_SPELL_EFFECT, nil)
        jass.TriggerRegisterPlayerUnitEvent(attack_trigger, player, jass.EVENT_PLAYER_UNIT_ATTACKED, nil)
    end
    jass.TriggerAddAction(spell_trigger, function()
        local hero = jass.GetTriggerUnit()
        local hero_rawcode = heroes[hero]
        if hero_rawcode ~= nil then cast_spell(hero, hero_rawcode, jass.GetSpellAbilityId()) end
    end)
    jass.TriggerAddAction(attack_trigger, function()
        local attacker = type(jass.GetAttacker) == "function" and jass.GetAttacker() or nil
        local target = type(jass.GetAttackedUnitBJ) == "function" and jass.GetAttackedUnitBJ() or jass.GetTriggerUnit()
        if attacker ~= nil and heroes[attacker] ~= nil then proc_attack(attacker, heroes[attacker], target) end
        if target ~= nil and heroes[target] == "H0B0" then bull_counterattack(target, attacker) end
    end)
end

---@param hero_results HeroSelectionResult[]
---@param seed integer|nil
---@return boolean started_now
function module.start(hero_results, seed)
    if started then return false end
    started = true
    session_seed = math.max(1, math.floor(tonumber(seed) or 1))
    N1_ID, N2_ID, N4_ID = rawcode_to_integer("A0N1"), rawcode_to_integer("A0N2"), rawcode_to_integer("A0N4")
    B1_ID, B4_ID = rawcode_to_integer("A0B1"), rawcode_to_integer("A0B4")
    for _, result in ipairs(hero_results or {}) do
        if result.unit ~= nil and result.hero
            and result.hero.rawcode ~= "H0W0" and result.hero.rawcode ~= "H0E0" then
            heroes[result.unit] = result.hero.rawcode
            state_for(result.unit)
        end
    end
    register_events()
    clock_timer = jass.CreateTimer()
    if clock_timer ~= nil then
        jass.TimerStart(clock_timer, 0.25, true, function() now = now + 0.25 end)
    end
    return true
end

return module
