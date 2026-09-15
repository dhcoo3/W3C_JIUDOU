--- 牛魔王的统一伤害结算。
--- 后羿拥有独立的 rogue.skills.houyi 模块，本文件只处理牛魔王。
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
local now = 0
local B1_ID = nil
local B4_ID = nil

local function rawcode_to_integer(rawcode)
    if type(rawcode) ~= "string" or #rawcode ~= 4 then return nil end
    local a, b, c, d = string.byte(rawcode, 1, 4)
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local function is_alive(unit_handle)
    return unit_handle ~= nil and type(jass.GetUnitState) == "function"
        and (jass.GetUnitState(unit_handle, jass.UNIT_STATE_LIFE) or 0) > 0.405
end

local function ability_level(hero, ability_id)
    return type(jass.GetUnitAbilityLevel) == "function"
        and math.floor(jass.GetUnitAbilityLevel(hero, ability_id) or 0) or 0
end

local function common_value(hero, key)
    local state = state_store.get_by_hero(hero)
    return state and math.floor(tonumber(state.common[key]) or 0) or 0
end

local function state_for(hero)
    if states[hero] == nil then states[hero] = {cooldowns = {}} end
    return states[hero]
end

local function scaled_damage(hero, ability_rawcode, prefix, level)
    local runtime = config.get_skill_runtime("H0B0", ability_rawcode)
    if runtime == nil then return 0 end
    local attribute_key = prefix == "" and "damageAttribute" or (prefix .. "DamageAttribute")
    local multiplier_key = prefix == "" and "damageMultiplierTenth" or (prefix .. "DamageMultiplierTenth")
    local multipliers = runtime[multiplier_key]
    if type(runtime[attribute_key]) ~= "string" or type(multipliers) ~= "table" then return 0 end
    local multiplier = multipliers[level] or multipliers[#multipliers] or 0
    return skill_damage.calculate(hero, runtime[attribute_key], multiplier, common_value(hero, "skill_damage_percent"))
end

local function sorted_enemies(hero, x, y, radius)
    local result = {}
    if type(jass.CreateGroup) ~= "function" or type(jass.GroupEnumUnitsInRange) ~= "function" then return result end
    local group = jass.CreateGroup()
    jass.GroupEnumUnitsInRange(group, x, y, radius, nil)
    jass.ForGroup(group, function()
        local target = jass.GetEnumUnit()
        if is_alive(target) and jass.IsUnitEnemy(target, jass.GetOwningPlayer(hero)) then table.insert(result, target) end
    end)
    if type(jass.DestroyGroup) == "function" then jass.DestroyGroup(group) end
    table.sort(result, function(left, right) return jass.GetHandleId(left) < jass.GetHandleId(right) end)
    return result
end

local function damage_area(hero, x, y, radius, amount)
    for _, target in ipairs(sorted_enemies(hero, x, y, radius)) do
        damage_service.deal(hero, target, amount, jass.DAMAGE_TYPE_MAGIC)
    end
end

local function cast_bull_q(hero)
    local level = ability_level(hero, B1_ID)
    local runtime = config.get_skill_runtime("H0B0", "A0B1")
    if level <= 0 or runtime == nil then return end
    damage_area(hero, jass.GetUnitX(hero), jass.GetUnitY(hero), runtime.area or 250,
        scaled_damage(hero, "A0B1", "", level))
end

local function bull_counterattack(hero)
    local level = ability_level(hero, B4_ID)
    local runtime = config.get_skill_runtime("H0B0", "A0B4")
    if level <= 0 or runtime == nil then return end
    local state = state_for(hero)
    if now < (state.cooldowns.A0B4 or 0) then return end
    damage_area(hero, jass.GetUnitX(hero), jass.GetUnitY(hero), runtime.procArea or 250,
        scaled_damage(hero, "A0B4", "proc", level))
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
        if heroes[hero] and jass.GetSpellAbilityId() == B1_ID then cast_bull_q(hero) end
    end)
    jass.TriggerAddAction(attack_trigger, function()
        local target = type(jass.GetAttackedUnitBJ) == "function" and jass.GetAttackedUnitBJ() or jass.GetTriggerUnit()
        if target ~= nil and heroes[target] then bull_counterattack(target) end
    end)
end

function module.start(hero_results)
    if started then return false end
    started = true
    B1_ID, B4_ID = rawcode_to_integer("A0B1"), rawcode_to_integer("A0B4")
    for _, result in ipairs(hero_results or {}) do
        if result.unit ~= nil and result.hero and result.hero.rawcode == "H0B0" then
            heroes[result.unit] = true
            state_for(result.unit)
        end
    end
    register_events()
    clock_timer = jass.CreateTimer()
    if clock_timer ~= nil then jass.TimerStart(clock_timer, 0.25, true, function() now = now + 0.25 end) end
    return true
end

return module
