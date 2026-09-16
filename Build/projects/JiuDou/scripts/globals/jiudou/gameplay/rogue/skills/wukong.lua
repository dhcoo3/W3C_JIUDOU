--- 孙悟空技能 Lua 运行时。
--- 所有客户端执行相同事件和确定性随机，不在 GetLocalPlayer 分支中修改游戏状态。
local jass = J.Common
local config = JiuDou.module("gameplay.rogue.config")
local state_store = JiuDou.module("gameplay.rogue.state")
local skill_damage = JiuDou.module("gameplay.combat.skill_damage")
local damage_service = JiuDou.module("gameplay.combat.damage")

local module = {}
local lifecycle = JiuDou.core and JiuDou.core.lifecycle
local resource_api = JiuDou.core and JiuDou.core.resource
local timer_service = JiuDou.core and JiuDou.core.timer
local runtime_scope = nil
local started = false
local heroes = {}
local combat_states = {}
local monkey_owners = {}
local spell_trigger = nil
local attack_trigger = nil
local death_trigger = nil
local stack_timer = nil
local session_seed = 1
local attack_sequence = 0
local kill_sequence = 0

local Q_RAWCODE = "A0W1"
local W_RAWCODE = "A0W2"
local E_RAWCODE = "A0W3"
local R_RAWCODE = "A0W4"
local STACK_DISPLAY_RAWCODE = "R0W3"
local TIMED_LIFE_BUFF = "BTLF"
local MODULUS = 2147483647

local function rawcode_to_integer(rawcode)
    if type(rawcode) ~= "string" or #rawcode ~= 4 then return nil end
    local a, b, c, d = string.byte(rawcode, 1, 4)
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local Q_ID = rawcode_to_integer(Q_RAWCODE)
local W_ID = rawcode_to_integer(W_RAWCODE)
local E_ID = rawcode_to_integer(E_RAWCODE)
local R_ID = rawcode_to_integer(R_RAWCODE)
local STACK_DISPLAY_ID = rawcode_to_integer(STACK_DISPLAY_RAWCODE)
local TIMED_LIFE_ID = rawcode_to_integer(TIMED_LIFE_BUFF)

local function is_alive(unit_handle)
    if unit_handle == nil or type(jass.GetUnitState) ~= "function" then return false end
    return jass.GetUnitState(unit_handle, jass.UNIT_STATE_LIFE) > 0.405
end

local function ability_level(hero, ability_id)
    return type(jass.GetUnitAbilityLevel) == "function" and (jass.GetUnitAbilityLevel(hero, ability_id) or 0) or 0
end

local function skill_value(hero, skill_rawcode, key)
    local state = state_store.get_by_hero(hero)
    local values = state and state.skills[skill_rawcode] or nil
    return values and values[key] or 0
end

local function common_value(hero, key)
    local state = state_store.get_by_hero(hero)
    return state and state.common[key] or 0
end

local function final_skill_damage(hero, attribute_id, multiplier_tenth)
    return skill_damage.calculate(
        hero,
        attribute_id,
        multiplier_tenth,
        common_value(hero, "skill_damage_percent")
    )
end

local function damage(hero, target, amount, damage_type)
    if amount <= 0 or not is_alive(target) or not jass.IsUnitEnemy(target, jass.GetOwningPlayer(hero)) then return end
    if not damage_service.deal(hero, target, amount, damage_type) then
        print("悟空技能伤害执行失败：UnitDamageTarget 参数不兼容")
    end
end

local function sorted_enemies(hero, x, y, radius)
    local result = {}
    local group = jass.CreateGroup()
    jass.GroupEnumUnitsInRange(group, x, y, radius, nil)
    jass.ForGroup(group, function()
        local target = jass.GetEnumUnit()
        if is_alive(target) and jass.IsUnitEnemy(target, jass.GetOwningPlayer(hero)) then
            table.insert(result, target)
        end
    end)
    jass.DestroyGroup(group)
    table.sort(result, function(left, right)
        if type(jass.GetHandleId) == "function" then return jass.GetHandleId(left) < jass.GetHandleId(right) end
        return tostring(left) < tostring(right)
    end)
    return result
end

local function add_effect(path, x, y)
    if type(jass.AddSpecialEffect) ~= "function" then return end
    local effect = jass.AddSpecialEffect(path, x, y)
    if effect ~= nil and type(jass.DestroyEffect) == "function" then jass.DestroyEffect(effect) end
end

local function cast_q(hero, level)
    local runtime = config.get_skill_runtime("H0W0", Q_RAWCODE)
    local radius = runtime.area + skill_value(hero, Q_RAWCODE, "area_add")
    local target_count = runtime.targetCount + skill_value(hero, Q_RAWCODE, "target_count_add")
    local multiplier = runtime.damageMultiplierTenth[level] or runtime.damageMultiplierTenth[#runtime.damageMultiplierTenth]
    local amount = final_skill_damage(hero, runtime.damageAttribute, multiplier)
    local targets = sorted_enemies(hero, jass.GetUnitX(hero), jass.GetUnitY(hero), radius)
    for index = 1, math.min(target_count, #targets) do damage(hero, targets[index], amount) end
end

local function walkable_position(from_x, from_y, target_x, target_y, maximum_range)
    local dx, dy = target_x - from_x, target_y - from_y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance > maximum_range and distance > 0 then
        target_x = from_x + dx * maximum_range / distance
        target_y = from_y + dy * maximum_range / distance
    end
    if type(jass.IsTerrainPathable) ~= "function" or jass.PATHING_TYPE_WALKABILITY == nil then
        return target_x, target_y
    end
    local final_dx, final_dy = target_x - from_x, target_y - from_y
    local final_distance = math.sqrt(final_dx * final_dx + final_dy * final_dy)
    if final_distance <= 0 then return from_x, from_y end
    local ux, uy = final_dx / final_distance, final_dy / final_distance
    local probe = final_distance
    while probe > 0 do
        local x, y = from_x + ux * probe, from_y + uy * probe
        if not jass.IsTerrainPathable(x, y, jass.PATHING_TYPE_WALKABILITY) then return x, y end
        probe = probe - 32
    end
    return from_x, from_y
end

local function cast_w(hero, level)
    local runtime = config.get_skill_runtime("H0W0", W_RAWCODE)
    local start_x, start_y = jass.GetUnitX(hero), jass.GetUnitY(hero)
    local target_x = type(jass.GetSpellTargetX) == "function" and jass.GetSpellTargetX() or start_x
    local target_y = type(jass.GetSpellTargetY) == "function" and jass.GetSpellTargetY() or start_y
    local maximum_range = runtime.range + skill_value(hero, W_RAWCODE, "range_add")
    target_x, target_y = walkable_position(start_x, start_y, target_x, target_y, maximum_range)
    add_effect("Abilities\\Spells\\NightElf\\Blink\\BlinkCaster.mdl", start_x, start_y)
    jass.SetUnitPosition(hero, target_x, target_y)
    target_x, target_y = jass.GetUnitX(hero), jass.GetUnitY(hero)
    add_effect("Abilities\\Spells\\NightElf\\Blink\\BlinkTarget.mdl", target_x, target_y)
    local radius = runtime.area + skill_value(hero, W_RAWCODE, "area_add")
    local multiplier = runtime.damageMultiplierTenth[level] or runtime.damageMultiplierTenth[#runtime.damageMultiplierTenth]
    local amount = final_skill_damage(hero, runtime.damageAttribute, multiplier)
    for _, target in ipairs(sorted_enemies(hero, target_x, target_y, radius)) do damage(hero, target, amount) end
end

local function deterministic_percent(sequence, hero, salt)
    local handle_id = type(jass.GetHandleId) == "function" and jass.GetHandleId(hero) or 1
    local value = (session_seed + sequence * 48271 + handle_id * 97 + salt * 7919) % MODULUS
    return value % 100 + 1
end

local function combat_state(hero)
    local state = combat_states[hero]
    if state == nil then
        state = {stacks = 0, remainingTicks = 0}
        combat_states[hero] = state
    end
    return state
end

local function update_stack_display(hero, stacks)
    if STACK_DISPLAY_ID == nil then return end
    if stacks > 0 then
        if ability_level(hero, STACK_DISPLAY_ID) <= 0 then jass.UnitAddAbility(hero, STACK_DISPLAY_ID) end
    elseif ability_level(hero, STACK_DISPLAY_ID) > 0 then
        jass.UnitRemoveAbility(hero, STACK_DISPLAY_ID)
    end
end

local function on_attack(hero, target)
    local level = ability_level(hero, E_ID)
    if level <= 0 or not is_alive(target) then return end
    local runtime = config.get_skill_runtime("H0W0", E_RAWCODE)
    local state = combat_state(hero)
    state.stacks = math.min(runtime.maxStacks, state.stacks + 1)
    local duration = runtime.duration + skill_value(hero, E_RAWCODE, "duration_add")
    state.remainingTicks = math.max(1, duration * 4)
    update_stack_display(hero, state.stacks)
    attack_sequence = attack_sequence + 1
    local base_chance = runtime.critChance[level] or runtime.critChance[#runtime.critChance]
    local per_stack = (runtime.critPerStack[level] or runtime.critPerStack[#runtime.critPerStack])
        + skill_value(hero, E_RAWCODE, "crit_per_stack_add")
    local chance = math.min(100, base_chance + state.stacks * per_stack)
    if deterministic_percent(attack_sequence, hero, 31) <= chance then
        local multiplier = runtime.procDamageMultiplierTenth[level]
            or runtime.procDamageMultiplierTenth[#runtime.procDamageMultiplierTenth]
        local bonus = final_skill_damage(hero, runtime.procDamageAttribute, multiplier)
        damage(hero, target, bonus, jass.DAMAGE_TYPE_NORMAL)
        add_effect("Abilities\\Spells\\Other\\Stampede\\StampedeMissileDeath.mdl", jass.GetUnitX(target), jass.GetUnitY(target))
    end
end

local function summon_monkeys(hero, x, y, count, duration, summon_rawcode)
    local unit_id = rawcode_to_integer(summon_rawcode)
    if unit_id == nil then return end
    for index = 1, count do
        local angle = (index - 1) * 6.283185307179586 / math.max(1, count)
        local spawn_x = x + math.cos(angle) * 96
        local spawn_y = y + math.sin(angle) * 96
        local summon = jass.CreateUnit(jass.GetOwningPlayer(hero), unit_id, spawn_x, spawn_y, angle * 57.29577951308232)
        if summon ~= nil then
            monkey_owners[summon] = hero
            damage_service.register_attack_source(summon, hero)
            if type(jass.SetUnitScale) == "function" then jass.SetUnitScale(summon, 0.75, 0.75, 0.75) end
            if type(jass.UnitApplyTimedLife) == "function" then jass.UnitApplyTimedLife(summon, TIMED_LIFE_ID, duration) end
            if type(jass.IssuePointOrder) == "function" then jass.IssuePointOrder(summon, "attack", x, y) end
        end
    end
end

local function on_kill(hero, dying)
    local level = ability_level(hero, R_ID)
    if level <= 0 then return end
    local runtime = config.get_skill_runtime("H0W0", R_RAWCODE)
    kill_sequence = kill_sequence + 1
    local chance = runtime.chance[level] or runtime.chance[#runtime.chance]
    if deterministic_percent(kill_sequence, hero, 73) > chance then return end
    local count = runtime.summonCount + skill_value(hero, R_RAWCODE, "summon_count_add")
    local duration = runtime.summonDuration + skill_value(hero, R_RAWCODE, "summon_duration_add")
    local x, y = jass.GetUnitX(dying), jass.GetUnitY(dying)
    add_effect("Abilities\\Spells\\Orc\\MirrorImage\\MirrorImageCaster.mdl", x, y)
    summon_monkeys(hero, x, y, count, duration, runtime.summonRawcode)
end

local function on_monkey_attack(monkey, target)
    local owner = monkey_owners[monkey]
    if owner == nil or not is_alive(owner) then return end
    local level = ability_level(owner, R_ID)
    if level <= 0 then return end
    local runtime = config.get_skill_runtime("H0W0", R_RAWCODE)
    local amount = final_skill_damage(owner, runtime.summonDamageAttribute, runtime.summonDamageMultiplierTenth)
    damage(owner, target, amount, jass.DAMAGE_TYPE_NORMAL)
end

local function register_events()
    spell_trigger = jass.CreateTrigger()
    attack_trigger = jass.CreateTrigger()
    death_trigger = jass.CreateTrigger()
    if runtime_scope ~= nil then
        resource_api.trigger(runtime_scope, spell_trigger)
        resource_api.trigger(runtime_scope, attack_trigger)
        resource_api.trigger(runtime_scope, death_trigger)
    end
    for player_id = 0, 15 do
        local player = jass.Player(player_id)
        jass.TriggerRegisterPlayerUnitEvent(spell_trigger, player, jass.EVENT_PLAYER_UNIT_SPELL_EFFECT, nil)
        jass.TriggerRegisterPlayerUnitEvent(attack_trigger, player, jass.EVENT_PLAYER_UNIT_ATTACKED, nil)
        jass.TriggerRegisterPlayerUnitEvent(death_trigger, player, jass.EVENT_PLAYER_UNIT_DEATH, nil)
    end
    jass.TriggerAddAction(spell_trigger, function()
        local hero = jass.GetTriggerUnit()
        if not heroes[hero] then return end
        local ability_id = jass.GetSpellAbilityId()
        local level = ability_level(hero, ability_id)
        if ability_id == Q_ID then cast_q(hero, level)
        elseif ability_id == W_ID then cast_w(hero, level) end
    end)
    jass.TriggerAddAction(attack_trigger, function()
        local hero = type(jass.GetAttacker) == "function" and jass.GetAttacker() or nil
        local target = type(jass.GetAttackedUnitBJ) == "function" and jass.GetAttackedUnitBJ() or jass.GetTriggerUnit()
        if hero ~= nil and monkey_owners[hero] ~= nil then
            on_monkey_attack(hero, target)
            return
        end
        if hero == nil or not heroes[hero] then return end
        on_attack(hero, target)
    end)
    jass.TriggerAddAction(death_trigger, function()
        local dying = type(jass.GetDyingUnit) == "function" and jass.GetDyingUnit() or jass.GetTriggerUnit()
        if dying ~= nil then monkey_owners[dying] = nil end
        local hero = type(jass.GetKillingUnit) == "function" and jass.GetKillingUnit() or nil
        if hero == nil or not heroes[hero] then return end
        on_kill(hero, dying)
    end)
end

local function start_stack_timer()
    stack_timer = timer_service and timer_service.every(0.25, function()
        for hero, state in pairs(combat_states) do
            if state.stacks > 0 then
                state.remainingTicks = state.remainingTicks - 1
                if state.remainingTicks <= 0 then
                    state.stacks = 0
                    state.remainingTicks = 0
                    update_stack_display(hero, 0)
                end
            end
        end
    end, runtime_scope) or nil
end

function module.start(hero_results, seed)
    if started then return false end
    runtime_scope = lifecycle and lifecycle.acquire("rogue.skills.wukong", function()
        started, spell_trigger, attack_trigger, death_trigger, stack_timer = false, nil, nil, nil, nil
    end) or nil
    started = true
    session_seed = math.max(1, math.floor(tonumber(seed) or 1))
    for _, result in ipairs(hero_results or {}) do
        if result.unit ~= nil and result.hero and result.hero.rawcode == "H0W0" then
            heroes[result.unit] = true
            combat_state(result.unit)
        end
    end
    register_events()
    start_stack_timer()
    return true
end

function module.stop()
    return lifecycle ~= nil and lifecycle.release("rogue.skills.wukong") or false
end

JiuDou.publish("gameplay.rogue.skills.wukong", module)
return module
