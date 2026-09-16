--- 后羿技能运行时。
--- 原生物编只负责施法壳、目标约束、Buff 与视觉；所有伤害均经 combat.damage 结算。
local jass = J.Common
local config = JiuDou.module("gameplay.rogue.config")
local state_store = JiuDou.module("gameplay.rogue.state")
local skill_damage = JiuDou.module("gameplay.combat.skill_damage")
local damage_service = JiuDou.module("gameplay.combat.damage")
local events = JiuDou.core and JiuDou.core.events

local module = {}
local lifecycle = JiuDou.core and JiuDou.core.lifecycle
local resource_api = JiuDou.core and JiuDou.core.resource
local timer_service = JiuDou.core and JiuDou.core.timer
local runtime_scope = nil
local started = false
local heroes = {}
local hero_states = {}
local spell_trigger = nil
local death_trigger = nil
local mark_timer = nil
local clock = 0

local Q_RAWCODE, W_RAWCODE, E_RAWCODE, R_RAWCODE = "A0N1", "A0N2", "A0N3", "A0N4"
local Q_ID, W_ID, E_ID, R_ID = nil, nil, nil, nil
local SLOW_DUMMY_ID = nil
local SUN_BOW_ID = nil
local BURNING_ARROW_MODEL = "Abilities\\Weapons\\SearingArrow\\SearingArrowMissile.mdl"
local NORMAL_ARROW_MODEL = "Abilities\\Weapons\\Arrow\\ArrowMissile.mdl"
local MARK_MODEL = "Abilities\\Spells\\NightElf\\Immolation\\ImmolationTarget.mdl"
local IMPACT_MODEL = "Abilities\\Spells\\Human\\FlameStrike\\FlameStrike1.mdl"

local function rawcode_to_integer(rawcode)
    if type(rawcode) ~= "string" or #rawcode ~= 4 then return nil end
    local a, b, c, d = string.byte(rawcode, 1, 4)
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local function handle_id(handle)
    return type(jass.GetHandleId) == "function" and jass.GetHandleId(handle) or 0
end

local function is_alive(unit_handle)
    return unit_handle ~= nil and type(jass.GetUnitState) == "function"
        and (jass.GetUnitState(unit_handle, jass.UNIT_STATE_LIFE) or 0) > 0.405
end

local function is_enemy(hero, target)
    return hero ~= nil and target ~= nil and type(jass.IsUnitEnemy) == "function"
        and jass.IsUnitEnemy(target, jass.GetOwningPlayer(hero))
end

local function ability_level(hero, ability_id)
    return type(jass.GetUnitAbilityLevel) == "function"
        and math.floor(jass.GetUnitAbilityLevel(hero, ability_id) or 0) or 0
end

local function list_value(values, level)
    return type(values) == "table" and math.floor(tonumber(values[level] or values[#values]) or 0) or 0
end

local function runtime(skill)
    return config.get_skill_runtime("H0N0", skill) or {}
end

local function skill_value(hero, skill, key)
    local state = state_store.get_by_hero(hero)
    local values = state and state.skills[skill] or nil
    return values and math.floor(tonumber(values[key]) or 0) or 0
end

local function common_value(hero, key)
    local state = state_store.get_by_hero(hero)
    return state and math.floor(tonumber(state.common[key]) or 0) or 0
end

local function calculate_damage(hero, attribute, multiplier, bonus_percent)
    return skill_damage.calculate(hero, attribute or "primary", multiplier,
        common_value(hero, "skill_damage_percent") + math.floor(tonumber(bonus_percent) or 0))
end

local function play_effect(path, x, y)
    if type(jass.AddSpecialEffect) ~= "function" then return end
    local effect = jass.AddSpecialEffect(path, x, y)
    if effect ~= nil and type(jass.DestroyEffect) == "function" then jass.DestroyEffect(effect) end
end

local function play_arrow(path, from_x, from_y, to_x, to_y)
    -- 1.27 没有可安全移动特效的原生接口；两端瞬时特效不保留句柄，避免残留视觉对象。
    play_effect(path, from_x, from_y)
    play_effect(path, to_x, to_y)
end

local function destroy_effect(effect)
    if effect ~= nil and type(jass.DestroyEffect) == "function" then jass.DestroyEffect(effect) end
end

local function sorted_enemies(hero, x, y, radius)
    local result = {}
    if type(jass.CreateGroup) ~= "function" or type(jass.GroupEnumUnitsInRange) ~= "function"
        or type(jass.ForGroup) ~= "function" then return result end
    local group = jass.CreateGroup()
    jass.GroupEnumUnitsInRange(group, x, y, radius, nil)
    jass.ForGroup(group, function()
        local target = jass.GetEnumUnit()
        if is_alive(target) and is_enemy(hero, target) then table.insert(result, target) end
    end)
    if type(jass.DestroyGroup) == "function" then jass.DestroyGroup(group) end
    table.sort(result, function(left, right)
        local left_dx, left_dy = jass.GetUnitX(left) - x, jass.GetUnitY(left) - y
        local right_dx, right_dy = jass.GetUnitX(right) - x, jass.GetUnitY(right) - y
        local left_distance, right_distance = left_dx * left_dx + left_dy * left_dy,
            right_dx * right_dx + right_dy * right_dy
        if left_distance ~= right_distance then return left_distance < right_distance end
        return handle_id(left) < handle_id(right)
    end)
    return result
end

local function damage_target(hero, target, amount)
    if amount > 0 and is_alive(target) and is_enemy(hero, target) then
        damage_service.deal(hero, target, amount, jass.DAMAGE_TYPE_MAGIC)
    end
end

local function state_for(hero)
    local state = hero_states[hero]
    if state == nil then
        state = {marks = {}, casts = {}}
        hero_states[hero] = state
    end
    return state
end

local function has_sun_bow(hero)
    if SUN_BOW_ID == nil or type(jass.GetItemTypeId) ~= "function" then return false end
    for slot = 0, 5 do
        local item = type(jass.UnitItemInSlot) == "function" and jass.UnitItemInSlot(hero, slot)
            or (type(jass.GetUnitItemInSlot) == "function" and jass.GetUnitItemInSlot(hero, slot) or nil)
        if item ~= nil and jass.GetItemTypeId(item) == SUN_BOW_ID then return true end
    end
    return false
end

local function remove_dummy_later(dummy, seconds)
    if dummy == nil or type(jass.CreateTimer) ~= "function" or type(jass.TimerStart) ~= "function" then return end
    local timer = jass.CreateTimer()
    jass.TimerStart(timer, seconds, false, function()
        if type(jass.RemoveUnit) == "function" then jass.RemoveUnit(dummy) end
        if type(jass.DestroyTimer) == "function" then jass.DestroyTimer(timer) end
    end)
end

local function apply_native_slow(hero, target)
    if SLOW_DUMMY_ID == nil or type(jass.CreateUnit) ~= "function" or not is_alive(target) then return end
    local dummy = jass.CreateUnit(jass.GetOwningPlayer(hero), SLOW_DUMMY_ID, jass.GetUnitX(target), jass.GetUnitY(target), 0)
    if dummy == nil then return end
    if type(jass.IssueTargetOrder) == "function" then jass.IssueTargetOrder(dummy, "cripple", target) end
    remove_dummy_later(dummy, 1.20)
end

local function clear_mark(hero, target)
    local state = state_for(hero)
    local mark = state.marks[target]
    if mark ~= nil then destroy_effect(mark.effect) end
    state.marks[target] = nil
end

local function explode_mark(hero, target, level)
    local e_runtime = runtime(E_RAWCODE)
    local bonus_damage, bonus_area = 0, 0
    if has_sun_bow(hero) then
        bonus_damage = math.floor(tonumber(e_runtime.itemProcDamagePercent) or 0)
        bonus_area = math.floor(tonumber(e_runtime.itemProcAreaAdd) or 0)
    end
    local area = math.max(0, math.floor(tonumber(e_runtime.procArea) or 0)
        + skill_value(hero, E_RAWCODE, "area_add") + bonus_area)
    local amount = calculate_damage(hero, e_runtime.procDamageAttribute,
        list_value(e_runtime.procDamageMultiplierTenth, level),
        skill_value(hero, E_RAWCODE, "proc_damage_percent_add") + bonus_damage)
    local x, y = jass.GetUnitX(target), jass.GetUnitY(target)
    play_effect(IMPACT_MODEL, x, y)
    for _, victim in ipairs(sorted_enemies(hero, x, y, area)) do damage_target(hero, victim, amount) end
    apply_native_slow(hero, target)
end

local function add_day_mark(hero, target, cast_hits)
    local level = ability_level(hero, E_ID)
    if level <= 0 or not is_alive(target) or not is_enemy(hero, target) then return false end
    local id = handle_id(target)
    if cast_hits ~= nil then
        if cast_hits[id] then return false end
        cast_hits[id] = true
    end
    local e_runtime = runtime(E_RAWCODE)
    local state = state_for(hero)
    local mark = state.marks[target]
    if mark == nil then
        mark = {stacks = 0, effect = nil}
        state.marks[target] = mark
    end
    mark.stacks = math.min(math.max(1, math.floor(tonumber(e_runtime.maxStacks) or 3)), mark.stacks + 1)
    mark.expiresAt = clock + math.max(1, math.floor(tonumber(e_runtime.duration) or 5))
    if mark.effect == nil and type(jass.AddSpecialEffectTarget) == "function" then
        mark.effect = jass.AddSpecialEffectTarget(MARK_MODEL, target, "overhead")
    end
    if mark.stacks >= math.max(1, math.floor(tonumber(e_runtime.maxStacks) or 3)) then
        clear_mark(hero, target)
        explode_mark(hero, target, level)
    end
    return true
end

local function damage_area_with_mark(hero, x, y, radius, amount, cast_hits)
    for _, target in ipairs(sorted_enemies(hero, x, y, radius)) do
        damage_target(hero, target, amount)
        add_day_mark(hero, target, cast_hits)
    end
end

local function cancel_cast(hero, cast)
    if cast == nil or cast.finished then return end
    cast.finished = true
    if cast.timer ~= nil then
        if type(jass.PauseTimer) == "function" then jass.PauseTimer(cast.timer) end
        if type(jass.DestroyTimer) == "function" then jass.DestroyTimer(cast.timer) end
        cast.timer = nil
    end
    state_for(hero).casts[cast] = nil
end

local function cast_q(hero)
    local q_runtime = runtime(Q_RAWCODE)
    local level = ability_level(hero, Q_ID)
    if level <= 0 then return end
    local start_x, start_y = jass.GetUnitX(hero), jass.GetUnitY(hero)
    local end_x = type(jass.GetSpellTargetX) == "function" and jass.GetSpellTargetX() or start_x
    local end_y = type(jass.GetSpellTargetY) == "function" and jass.GetSpellTargetY() or start_y
    local dx, dy = end_x - start_x, end_y - start_y
    local distance = math.sqrt(dx * dx + dy * dy)
    local range = math.max(1, math.floor(tonumber(q_runtime.range) or 900))
    if distance <= 0.01 then dx, dy, distance = 1, 0, 1 end
    if distance > range then
        end_x, end_y = start_x + dx * range / distance, start_y + dy * range / distance
        dx, dy, distance = end_x - start_x, end_y - start_y, range
    end
    local width = math.max(1, math.floor(tonumber(q_runtime.width) or 96))
    local candidates = {}
    for _, target in ipairs(sorted_enemies(hero, start_x, start_y, distance + width)) do
        local tx, ty = jass.GetUnitX(target) - start_x, jass.GetUnitY(target) - start_y
        local projection = (tx * dx + ty * dy) / distance
        local perpendicular = math.abs(tx * dy - ty * dx) / distance
        if projection >= 0 and projection <= distance and perpendicular <= width / 2 then
            table.insert(candidates, {target = target, projection = projection, id = handle_id(target)})
        end
    end
    table.sort(candidates, function(left, right)
        if left.projection ~= right.projection then return left.projection < right.projection end
        return left.id < right.id
    end)
    play_arrow(BURNING_ARROW_MODEL, start_x, start_y, end_x, end_y)
    local amount = calculate_damage(hero, q_runtime.damageAttribute,
        list_value(q_runtime.damageMultiplierTenth, level), skill_value(hero, Q_RAWCODE, "damage_percent_add"))
    local marked = {}
    local limit = math.max(1, math.floor(tonumber(q_runtime.targetCount) or 4) + skill_value(hero, Q_RAWCODE, "target_count_add"))
    for index = 1, math.min(limit, #candidates) do
        local target = candidates[index].target
        damage_target(hero, target, amount)
        add_day_mark(hero, target, marked)
    end
end

local function next_bounce_target(hero, source, range, hit_targets)
    for _, target in ipairs(sorted_enemies(hero, jass.GetUnitX(source), jass.GetUnitY(source), range)) do
        if not hit_targets[handle_id(target)] then return target end
    end
    return nil
end

local function fire_w_arrow(cast)
    local hero = cast.hero
    local target = cast.target
    if not is_alive(target) or not is_enemy(hero, target) then
        target = sorted_enemies(hero, jass.GetUnitX(hero), jass.GetUnitY(hero), cast.range)[1]
    end
    if target == nil then return end
    local hit_targets = {}
    local from_x, from_y = jass.GetUnitX(hero), jass.GetUnitY(hero)
    local bounce = 0
    while target ~= nil and bounce <= cast.bounceCount do
        local to_x, to_y = jass.GetUnitX(target), jass.GetUnitY(target)
        play_arrow(NORMAL_ARROW_MODEL, from_x, from_y, to_x, to_y)
        damage_target(hero, target, cast.amount)
        add_day_mark(hero, target, cast.marked)
        hit_targets[handle_id(target)] = true
        from_x, from_y = to_x, to_y
        target = next_bounce_target(hero, target, cast.bounceRange, hit_targets)
        bounce = bounce + 1
    end
end

local function cast_w(hero)
    local w_runtime = runtime(W_RAWCODE)
    local level = ability_level(hero, W_ID)
    local target = type(jass.GetSpellTargetUnit) == "function" and jass.GetSpellTargetUnit() or nil
    if level <= 0 or target == nil then return end
    local cast = {
        hero = hero, target = target, marked = {},
        remaining = math.max(1, math.floor(tonumber(w_runtime.projectileCount) or 3)
            + skill_value(hero, W_RAWCODE, "projectile_count_add")),
        range = math.max(1, math.floor(tonumber(w_runtime.range) or 750)),
        bounceRange = math.max(1, math.floor(tonumber(w_runtime.bounceRange) or 350)),
        bounceCount = math.max(0, math.floor(tonumber(w_runtime.bounceCount) or 1)
            + skill_value(hero, W_RAWCODE, "bounce_count_add")),
        amount = calculate_damage(hero, w_runtime.damageAttribute, list_value(w_runtime.damageMultiplierTenth, level)),
    }
    state_for(hero).casts[cast] = true
    local interval = math.max(0.01, math.floor(tonumber(w_runtime.projectileIntervalHundredths) or 18) / 100)
    local function next_arrow()
        if cast.finished or not is_alive(hero) then return cancel_cast(hero, cast) end
        fire_w_arrow(cast)
        cast.remaining = cast.remaining - 1
        if cast.remaining <= 0 then cancel_cast(hero, cast) end
    end
    cast.timer = jass.CreateTimer()
    next_arrow()
    if not cast.finished then jass.TimerStart(cast.timer, interval, true, next_arrow) end
end

local function cast_r(hero)
    local r_runtime = runtime(R_RAWCODE)
    local level = ability_level(hero, R_ID)
    if level <= 0 then return end
    local x = type(jass.GetSpellTargetX) == "function" and jass.GetSpellTargetX() or jass.GetUnitX(hero)
    local y = type(jass.GetSpellTargetY) == "function" and jass.GetSpellTargetY() or jass.GetUnitY(hero)
    local normal_count = math.max(1, math.floor(tonumber(r_runtime.projectileCount) or 8)
        + skill_value(hero, R_RAWCODE, "projectile_count_add"))
    local duration = math.max(0.10, math.floor(tonumber(r_runtime.durationHundredths) or 200) / 100)
    local cast = {
        hero = hero, x = x, y = y, marked = {}, index = 1, normalCount = normal_count,
        outerRadius = math.max(0, math.floor(tonumber(r_runtime.outerRadius) or 240)),
        normalArea = math.max(0, math.floor(tonumber(r_runtime.normalArea) or 110)),
        finalArea = math.max(0, math.floor(tonumber(r_runtime.finalArea) or 180)),
        normalAmount = calculate_damage(hero, r_runtime.damageAttribute, list_value(r_runtime.damageMultiplierTenth, level)),
        finalAmount = calculate_damage(hero, r_runtime.damageAttribute,
            list_value(r_runtime.finalDamageMultiplierTenth, level), skill_value(hero, R_RAWCODE, "final_damage_percent_add")),
    }
    state_for(hero).casts[cast] = true
    local interval = duration / (normal_count + 1)
    cast.timer = jass.CreateTimer()
    jass.TimerStart(cast.timer, interval, true, function()
        if cast.finished or not is_alive(hero) then return cancel_cast(hero, cast) end
        if cast.index <= cast.normalCount then
            local angle = (cast.index - 1) * 2 * math.pi / cast.normalCount
            local impact_x = cast.x + math.cos(angle) * cast.outerRadius
            local impact_y = cast.y + math.sin(angle) * cast.outerRadius
            play_arrow(BURNING_ARROW_MODEL, jass.GetUnitX(hero), jass.GetUnitY(hero), impact_x, impact_y)
            play_effect(IMPACT_MODEL, impact_x, impact_y)
            damage_area_with_mark(hero, impact_x, impact_y, cast.normalArea, cast.normalAmount, cast.marked)
            cast.index = cast.index + 1
            return
        end
        play_arrow(BURNING_ARROW_MODEL, jass.GetUnitX(hero), jass.GetUnitY(hero), cast.x, cast.y)
        play_effect(IMPACT_MODEL, cast.x, cast.y)
        damage_area_with_mark(hero, cast.x, cast.y, cast.finalArea, cast.finalAmount, cast.marked)
        cancel_cast(hero, cast)
    end)
end

local function cleanup_dead_or_expired_marks()
    clock = clock + 0.05
    for hero, state in pairs(hero_states) do
        if not is_alive(hero) then
            local casts, targets = {}, {}
            for cast in pairs(state.casts) do table.insert(casts, cast) end
            for target in pairs(state.marks) do table.insert(targets, target) end
            for _, cast in ipairs(casts) do cancel_cast(hero, cast) end
            for _, target in ipairs(targets) do clear_mark(hero, target) end
        else
            for target, mark in pairs(state.marks) do
                if not is_alive(target) or clock >= (mark.expiresAt or 0) then clear_mark(hero, target) end
            end
        end
    end
end

local function register_events()
    spell_trigger = jass.CreateTrigger()
    death_trigger = jass.CreateTrigger()
    if runtime_scope ~= nil then
        resource_api.trigger(runtime_scope, spell_trigger)
        resource_api.trigger(runtime_scope, death_trigger)
    end
    for player_id = 0, 15 do
        local player = jass.Player(player_id)
        jass.TriggerRegisterPlayerUnitEvent(spell_trigger, player, jass.EVENT_PLAYER_UNIT_SPELL_EFFECT, nil)
        jass.TriggerRegisterPlayerUnitEvent(death_trigger, player, jass.EVENT_PLAYER_UNIT_DEATH, nil)
    end
    jass.TriggerAddAction(spell_trigger, function()
        local hero = jass.GetTriggerUnit()
        if not heroes[hero] then return end
        local ability = jass.GetSpellAbilityId()
        if ability == Q_ID then cast_q(hero)
        elseif ability == W_ID then cast_w(hero)
        elseif ability == R_ID then cast_r(hero) end
    end)
    jass.TriggerAddAction(death_trigger, function()
        local dying = type(jass.GetDyingUnit) == "function" and jass.GetDyingUnit() or jass.GetTriggerUnit()
        if dying ~= nil and heroes[dying] then
            local state = state_for(dying)
            local casts, targets = {}, {}
            for cast in pairs(state.casts) do table.insert(casts, cast) end
            for target in pairs(state.marks) do table.insert(targets, target) end
            for _, cast in ipairs(casts) do cancel_cast(dying, cast) end
            for _, target in ipairs(targets) do clear_mark(dying, target) end
        end
    end)
end

function module.start(hero_results)
    if started then return false end
    runtime_scope = lifecycle and lifecycle.acquire("rogue.skills.houyi", function()
        started, spell_trigger, death_trigger, mark_timer = false, nil, nil, nil
    end) or nil
    started = true
    Q_ID, W_ID, E_ID, R_ID = rawcode_to_integer(Q_RAWCODE), rawcode_to_integer(W_RAWCODE),
        rawcode_to_integer(E_RAWCODE), rawcode_to_integer(R_RAWCODE)
    SLOW_DUMMY_ID = rawcode_to_integer("u0H1")
    SUN_BOW_ID = rawcode_to_integer("I0XN")
    for _, result in ipairs(hero_results or {}) do
        if result.unit ~= nil and result.hero and result.hero.rawcode == "H0N0" then
            heroes[result.unit] = true
            state_for(result.unit)
        end
    end
    local on_damage_report = function(report)
        if report.kind == "native" and report.isBasicAttack and heroes[report.source] then
            add_day_mark(report.source, report.target, nil)
        end
    end
    if events ~= nil and type(events.on) == "function" then
        events.on("combat.damage", on_damage_report, 0)
    else
        damage_service.subscribe(on_damage_report)
    end
    register_events()
    mark_timer = timer_service and timer_service.every(0.05, cleanup_dead_or_expired_marks, runtime_scope) or nil
    return true
end

function module.stop()
    return lifecycle ~= nil and lifecycle.release("rogue.skills.houyi") or false
end

JiuDou.publish("gameplay.rogue.skills.houyi", module)
return module
