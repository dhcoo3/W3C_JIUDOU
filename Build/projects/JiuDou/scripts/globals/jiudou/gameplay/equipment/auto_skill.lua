--- 自动技能和战斗事件分发器。
--- 首版只使用定时、攻击、攻击命中和击杀事件，不依赖不稳定的受伤事件。
local jass = J.Common
local config = JiuDou.config.equipment
local instance = JiuDou.module("gameplay.equipment.instance")
local passive = JiuDou.module("gameplay.equipment.passive")
local combo = JiuDou.module("gameplay.equipment.combo")
local skill_damage = JiuDou.module("gameplay.combat.skill_damage")
local recovery = JiuDou.module("gameplay.combat.recovery")
local state_store = JiuDou.module("gameplay.rogue.state")
local damage_service = JiuDou.module("gameplay.combat.damage")
local lifecycle = JiuDou.core and JiuDou.core.lifecycle
local resource_api = JiuDou.core and JiuDou.core.resource
local timer_service = JiuDou.core and JiuDou.core.timer

local module = {}
local heroes = {}
local states = {}
local interval_timer = nil
local attack_trigger = nil
local death_trigger = nil
local now = 0
local event_sequence = 0
local warned_damage = false
local runtime_scope = nil

local TICK = 0.25
local NEUTRAL_HOSTILE_PLAYER_ID = 12

local function is_alive(unit_handle)
    return unit_handle ~= nil and type(jass.GetWidgetLife) == "function" and jass.GetWidgetLife(unit_handle) > 0.405
end

local function state_for(hero)
    local state = states[hero]
    if state == nil then
        state = {cooldowns = {}}
        states[hero] = state
    end
    return state
end

local function get_level_row(level)
    return config.levels["LEVEL_" .. tostring(level)] or {skillPowerMultiplierPercent = 100}
end

local function get_auto_damage_bonus(hero)
    local equipments = instance.get_equipment_instances(hero)
    local passive_bonus = passive.get_stat_bonus(equipments)
    local combo_bonus = combo.get_stat_bonus(equipments)
    return passive_bonus.autoDamageBonus + combo_bonus.autoDamageBonus
end

local function get_common_value(hero, key)
    local state = state_store.get_by_hero(hero)
    return math.floor(tonumber(state and state.common[key]) or 0)
end

local function scaled_damage(hero, equipment, row)
    local level_row = get_level_row(equipment.level)
    local multiplier_tenth = math.floor(tonumber(row.damageMultiplierBaseTenth) or 0)
        + equipment.level * math.floor(tonumber(row.damageMultiplierPerLevelTenth) or 0)
    local percent = get_common_value(hero, "skill_damage_percent")
        + (tonumber(level_row.skillPowerMultiplierPercent) or 100) - 100
        + get_auto_damage_bonus(hero)
    return skill_damage.calculate(hero, row.damageAttribute or "primary", multiplier_tenth, percent)
end

local function heal(hero, percent)
    recovery.apply_percent(hero, percent)
end

local function heal_fixed(hero, multiplier_tenth)
    recovery.apply_fixed(hero, recovery.calculate_fixed(hero, multiplier_tenth, get_common_value(hero, "recovery_percent")))
end

local function can_damage(hero, target)
    if not is_alive(target) or type(jass.IsUnitEnemy) ~= "function" then
        return false
    end
    return jass.IsUnitEnemy(target, jass.GetOwningPlayer(hero))
end

local function damage(hero, target, amount)
    if not can_damage(hero, target) then
        return
    end
    if not damage_service.deal(hero, target, amount, jass.DAMAGE_TYPE_MAGIC) and not warned_damage then
        warned_damage = true
        print("装备自动技能伤害执行失败：当前运行时缺少兼容的 UnitDamageTarget 参数")
    end
end

local function area_damage(hero, radius, amount)
    if type(jass.CreateGroup) ~= "function" or type(jass.GroupEnumUnitsInRange) ~= "function"
        or type(jass.ForGroup) ~= "function" or type(jass.GetEnumUnit) ~= "function" then
        return
    end
    local group = jass.CreateGroup()
    jass.GroupEnumUnitsInRange(group, jass.GetUnitX(hero), jass.GetUnitY(hero), radius, nil)
    jass.ForGroup(group, function()
        damage(hero, jass.GetEnumUnit(), amount)
    end)
    if type(jass.DestroyGroup) == "function" then
        jass.DestroyGroup(group)
    end
end

local function execute(hero, equipment, row, target)
    if row.handler == "heal_percent" then
        heal(hero, tonumber(row.param2) or tonumber(row.param1) or 0)
    elseif row.handler == "heal_primary" then
        heal_fixed(hero, tonumber(row.healMultiplierTenth) or tonumber(row.param1) or 0)
    elseif row.handler == "single_damage" then
        damage(hero, target, scaled_damage(hero, equipment, row))
    elseif row.handler == "area_damage" then
        area_damage(hero, tonumber(row.radius) or 0, scaled_damage(hero, equipment, row))
    end
end

local function execute_effect(hero, effect, target)
    local equipment = instance.get_by_uid(effect.uid)
    local row = {
        handler = effect.handler,
        param1 = effect.param1,
        param2 = effect.param2,
        radius = effect.radius or 0,
        damageAttribute = effect.damageAttribute,
        damageMultiplierBaseTenth = effect.damageMultiplierBaseTenth,
        damageMultiplierPerLevelTenth = effect.damageMultiplierPerLevelTenth,
        healMultiplierTenth = effect.healMultiplierTenth,
    }
    if equipment ~= nil then
        execute(hero, equipment, row, target)
    elseif effect.handler == "heal_percent" then
        heal(hero, tonumber(effect.param2) or tonumber(effect.param1) or 0)
    elseif effect.handler == "heal_primary" then
        heal_fixed(hero, tonumber(effect.healMultiplierTenth) or tonumber(effect.param1) or 0)
    end
end

local function trigger_equipment_event(hero, event_type, target)
    if not is_alive(hero) then
        return
    end
    event_sequence = event_sequence + 1
    local current_event = event_sequence
    local state = state_for(hero)
    local equipments = instance.get_equipment_instances(hero)
    for _, equipment in ipairs(equipments) do
        if equipment.autoSkillId ~= nil then
            local row = config.autoSkills[equipment.autoSkillId]
            if row ~= nil and row.eventType == event_type then
                local cooldown_key = "auto:" .. tostring(equipment.uid)
                if now >= (state.cooldowns[cooldown_key] or 0) then
                    local roll_key = current_event * 100000 + equipment.uid
                    local generator = JiuDou.module("gameplay.equipment.generator")
                    if generator.roll_percent(roll_key, row.chance) then
                        execute(hero, equipment, row, target)
                        state.cooldowns[cooldown_key] = now + math.max(0, tonumber(row.internalCooldown) or 0)
                    end
                end
            end
        end
    end
    for _, effect in ipairs(passive.get_event_effects(equipments, event_type, current_event)) do
        local cooldown_key = "passive:" .. tostring(effect.uid) .. ":" .. tostring(effect.sourceId)
        if now >= (state.cooldowns[cooldown_key] or 0) then
            execute_effect(hero, effect, target)
            state.cooldowns[cooldown_key] = now + math.max(0, tonumber(effect.internalCooldown) or 0)
        end
    end
end

local function process_interval()
    now = now + TICK
    for _, hero in ipairs(heroes) do
        if is_alive(hero) then
            local state = state_for(hero)
            local equipments = instance.get_equipment_instances(hero)
            event_sequence = event_sequence + 1
            local current_event = event_sequence
            for _, equipment in ipairs(equipments) do
                if equipment.autoSkillId ~= nil then
                    local row = config.autoSkills[equipment.autoSkillId]
                    if row ~= nil and row.eventType == "on_interval"
                        and now >= (state.cooldowns["auto:" .. tostring(equipment.uid)] or 0) then
                        local generator = JiuDou.module("gameplay.equipment.generator")
                        if generator.roll_percent(current_event * 100000 + equipment.uid, row.chance) then
                            execute(hero, equipment, row, nil)
                            state.cooldowns["auto:" .. tostring(equipment.uid)] = now + math.max(TICK, tonumber(row.interval) or 0)
                        end
                    end
                end
            end
            for _, effect in ipairs(passive.get_event_effects(equipments, "on_interval", current_event)) do
                local cooldown_key = "passive:" .. tostring(effect.uid) .. ":" .. tostring(effect.sourceId)
                if now >= (state.cooldowns[cooldown_key] or 0) then
                    execute_effect(hero, effect, nil)
                    state.cooldowns[cooldown_key] = now + math.max(TICK, tonumber(effect.internalCooldown) or 0)
                end
            end
        end
    end
end

local function register_events(scope)
    attack_trigger = jass.CreateTrigger()
    death_trigger = jass.CreateTrigger()
    if scope ~= nil then
        resource_api.trigger(scope, attack_trigger)
        resource_api.trigger(scope, death_trigger)
    end
    for player_id = 0, 15 do
        local player_handle = jass.Player(player_id)
        jass.TriggerRegisterPlayerUnitEvent(attack_trigger, player_handle, jass.EVENT_PLAYER_UNIT_ATTACKED, nil)
        if player_id ~= NEUTRAL_HOSTILE_PLAYER_ID then
            jass.TriggerRegisterPlayerUnitEvent(death_trigger, player_handle, jass.EVENT_PLAYER_UNIT_DEATH, nil)
        end
    end
    jass.TriggerRegisterPlayerUnitEvent(death_trigger, jass.Player(NEUTRAL_HOSTILE_PLAYER_ID), jass.EVENT_PLAYER_UNIT_DEATH, nil)
    jass.TriggerAddAction(attack_trigger, function()
        local attacker = type(jass.GetAttacker) == "function" and jass.GetAttacker() or nil
        local target = type(jass.GetAttackedUnitBJ) == "function" and jass.GetAttackedUnitBJ() or jass.GetTriggerUnit()
        if attacker ~= nil and states[attacker] ~= nil then
            trigger_equipment_event(attacker, "on_attack", target)
            trigger_equipment_event(attacker, "on_attack_hit", target)
        end
    end)
    jass.TriggerAddAction(death_trigger, function()
        local killer = type(jass.GetKillingUnit) == "function" and jass.GetKillingUnit() or nil
        local dying = type(jass.GetDyingUnit) == "function" and jass.GetDyingUnit() or jass.GetTriggerUnit()
        if killer ~= nil and states[killer] ~= nil then
            trigger_equipment_event(killer, "on_kill", dying)
        end
    end)
end

--- 重新读取英雄的装备列表；装备拾取、丢弃或合成后调用。
---@param hero unit 英雄句柄
function module.refresh_hero(hero)
    state_for(hero)
end

--- 启动自动技能调度器。
---@param hero_results HeroSelectionResult[] 英雄结果
---@return boolean started 是否启动成功
function module.start(hero_results)
    if interval_timer ~= nil then
        return true
    end
    heroes = {}
    for _, result in ipairs(hero_results or {}) do
        if result.unit ~= nil then
            table.insert(heroes, result.unit)
            state_for(result.unit)
        end
    end
    runtime_scope = lifecycle and lifecycle.acquire("equipment.auto_skill", function()
        heroes, states = {}, {}
        interval_timer, attack_trigger, death_trigger = nil, nil, nil
        now, event_sequence, warned_damage = 0, 0, false
    end) or nil
    register_events(runtime_scope)
    if timer_service ~= nil then
        interval_timer = timer_service.every(TICK, process_interval, runtime_scope)
    end
    return true
end

function module.stop()
    if lifecycle ~= nil and lifecycle.release("equipment.auto_skill") then return true end
    return false
end

JiuDou.publish("gameplay.equipment.auto_skill", module)
return module
