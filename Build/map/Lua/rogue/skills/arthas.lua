--- 阿尔萨斯技能运行时：死亡缠绕、凛风冲击、霜之哀伤与亡灵大军。
--- 伤害、控制、召唤与特效分开结算；跨玩家的游戏状态不放入本地 UI 分支。
local jass = require "jass.common"
local japi_loaded, japi = pcall(require, "jass.japi")
if not japi_loaded then japi = {} end

local config = require "rogue.config"
local state_store = require "rogue.state"
local skill_damage = require "combat.skill_damage"
local damage_service = require "combat.damage"
local recovery = require "combat.recovery"
local frame = require "platform.frame"

local module = {}
local started = false
local heroes = {}
local hero_states = {}
local ghoul_owners = {}
local control_states = {}
local spell_trigger = nil
local attack_trigger = nil
local death_trigger = nil
local update_timer = nil
local elapsed_ticks = 0
local now = 0
local counter_frame = nil
local counter_frame_attempted = false

local Q_RAWCODE, W_RAWCODE, E_RAWCODE, R_RAWCODE = "A0E1", "A0E2", "A0E3", "A0E4"
local DISPLAY_RAWCODE, SACRIFICE_RAWCODE = "R0E3", "R0E4"
local TIMED_LIFE_RAWCODE = "BTLF"
local Q_ID = nil
local W_ID = nil
local E_ID = nil
local R_ID = nil
local DISPLAY_ID = nil
local SACRIFICE_ID = nil
local TIMED_LIFE_ID = nil
local SOUL_ORB_MODEL = "Abilities\\Spells\\Undead\\DeathCoil\\UndeadDeathCoilMissile.mdl"
local SOUL_IMPACT_MODEL = "Abilities\\Spells\\Undead\\DeathCoil\\UndeadDeathCoilSpecialArt.mdl"
local HEAL_MODEL = "Abilities\\Spells\\Undead\\VampiricAura\\VampiricAuraTarget.mdl"
local FROST_BURST_MODEL = "Abilities\\Spells\\Undead\\FrostNova\\FrostNovaCaster.mdl"
local FROST_HIT_MODEL = "Abilities\\Spells\\Undead\\FrostNova\\FrostNovaTarget.mdl"
local FROST_STACK_MODEL = "Abilities\\Spells\\Undead\\FrostArmor\\FrostArmorDamage.mdl"
local FROST_FULL_MODEL = "Abilities\\Spells\\Undead\\FrostArmor\\FrostArmorTarget.mdl"
local SUMMON_MODEL = "Abilities\\Spells\\Undead\\AnimateDead\\AnimateDeadTarget.mdl"
local SACRIFICE_MODEL = "Abilities\\Spells\\Undead\\DeathCoil\\UndeadDeathCoilSpecialArt.mdl"
local TICK_SECONDS = 0.05

local function rawcode_to_integer(rawcode)
    if type(rawcode) ~= "string" or #rawcode ~= 4 then return nil end
    local a, b, c, d = string.byte(rawcode, 1, 4)
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local function integer_to_rawcode(value)
    value = math.floor(tonumber(value) or 0)
    if value <= 0 then return "" end
    local a = math.floor(value / 0x1000000) % 256
    local b = math.floor(value / 0x10000) % 256
    local c = math.floor(value / 0x100) % 256
    local d = value % 256
    return string.char(a, b, c, d)
end

local function is_alive(unit_handle)
    return unit_handle ~= nil and type(jass.GetUnitState) == "function"
        and (jass.GetUnitState(unit_handle, jass.UNIT_STATE_LIFE) or 0) > 0.405
end

local function ability_level(hero, ability_id)
    return type(jass.GetUnitAbilityLevel) == "function"
        and math.floor(jass.GetUnitAbilityLevel(hero, ability_id) or 0) or 0
end

local function skill_value(hero, skill_rawcode, key)
    local state = state_store.get_by_hero(hero)
    local values = state and state.skills[skill_rawcode] or nil
    return values and math.floor(tonumber(values[key]) or 0) or 0
end

local function common_value(hero, key)
    local state = state_store.get_by_hero(hero)
    return state and math.floor(tonumber(state.common[key]) or 0) or 0
end

local function final_skill_damage(hero, attribute, multiplier_tenth)
    return skill_damage.calculate(
        hero,
        attribute,
        multiplier_tenth,
        common_value(hero, "skill_damage_percent")
    )
end

local function final_skill_damage_hundredth(hero, attribute, multiplier_hundredth)
    return skill_damage.calculate_hundredth(
        hero,
        attribute,
        multiplier_hundredth,
        common_value(hero, "skill_damage_percent")
    )
end

local function damage(hero, target, amount, damage_type)
    if amount <= 0 or not is_alive(target) or type(jass.IsUnitEnemy) ~= "function"
        or not jass.IsUnitEnemy(target, jass.GetOwningPlayer(hero)) then
        return false
    end
    return damage_service.deal(hero, target, amount, damage_type or jass.DAMAGE_TYPE_MAGIC)
end

local function add_effect_at(path, x, y)
    if type(jass.AddSpecialEffect) ~= "function" then return nil end
    local effect = jass.AddSpecialEffect(path, x, y)
    if effect ~= nil and type(jass.DestroyEffect) == "function" then jass.DestroyEffect(effect) end
    return effect
end

local function show_hero_message(hero, message)
    if type(jass.GetOwningPlayer) ~= "function" or type(jass.DisplayTimedTextToPlayer) ~= "function" then return end
    jass.DisplayTimedTextToPlayer(jass.GetOwningPlayer(hero), 0.0, 0.0, 2.5, message)
end

local function play_target_effect(path, unit_handle, attachment)
    if type(jass.AddSpecialEffectTarget) ~= "function" then return nil end
    return jass.AddSpecialEffectTarget(path, unit_handle, attachment or "origin")
end

local function destroy_effect(effect)
    if effect ~= nil and type(jass.DestroyEffect) == "function" then jass.DestroyEffect(effect) end
end

local function distance_squared(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

local function sorted_enemies(hero, x, y, radius)
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
        local left_distance = distance_squared(jass.GetUnitX(left), jass.GetUnitY(left), x, y)
        local right_distance = distance_squared(jass.GetUnitX(right), jass.GetUnitY(right), x, y)
        if left_distance ~= right_distance then return left_distance < right_distance end
        if type(jass.GetHandleId) == "function" then return jass.GetHandleId(left) < jass.GetHandleId(right) end
        return tostring(left) < tostring(right)
    end)
    return result
end

local function update_ghoul_orders(hero, state)
    if type(jass.IssueTargetOrder) ~= "function" or type(jass.GetUnitX) ~= "function"
        or type(jass.GetUnitY) ~= "function" then
        return
    end

    local retarget_radius = 900
    local retarget_radius_squared = retarget_radius * retarget_radius
    for ghoul, ghoul_state in pairs(state.ghouls) do
        if is_alive(ghoul) and now >= (ghoul_state.nextTargetScanAt or 0) then
            ghoul_state.nextTargetScanAt = now + 0.25
            local ghoul_x, ghoul_y = jass.GetUnitX(ghoul), jass.GetUnitY(ghoul)
            local target = ghoul_state.target
            if target ~= nil and (not is_alive(target)
                or not jass.IsUnitEnemy(target, jass.GetOwningPlayer(hero))
                or distance_squared(ghoul_x, ghoul_y, jass.GetUnitX(target), jass.GetUnitY(target)) > retarget_radius_squared) then
                target = nil
                ghoul_state.target = nil
            end

            if target == nil then
                target = sorted_enemies(hero, ghoul_x, ghoul_y, retarget_radius)[1]
                ghoul_state.target = target
            end

            if target ~= nil then
                if ghoul_state.orderTarget ~= target or ghoul_state.orderType ~= "attack" then
                    jass.IssueTargetOrder(ghoul, "attack", target)
                    ghoul_state.orderTarget = target
                    ghoul_state.orderType = "attack"
                end
            elseif ghoul_state.orderTarget ~= hero or ghoul_state.orderType ~= "smart" then
                -- 没有敌人时跟随阿尔萨斯；扫描发现敌人后再切换为明确的攻击目标。
                jass.IssueTargetOrder(ghoul, "smart", hero)
                ghoul_state.orderTarget = hero
                ghoul_state.orderType = "smart"
            end
        end
    end
end

local function local_player_owns(hero)
    return type(jass.GetLocalPlayer) == "function" and type(jass.GetOwningPlayer) == "function"
        and jass.GetOwningPlayer(hero) == jass.GetLocalPlayer()
end

local function ensure_counter_frame(hero)
    if counter_frame ~= nil or counter_frame_attempted or not local_player_owns(hero) then return counter_frame end
    if not frame.is_available() then return nil end
    counter_frame_attempted = true
    local game_ui = frame.get_game_ui()
    local skill_button = frame.find_by_name("CommandButton_10", 0)
        or frame.find_by_name("CommandButton_2", 0)
    if game_ui == nil or skill_button == nil then return nil end
    counter_frame = frame.create("TEXT", "ArthasFrostmourneStackCounter", game_ui, "EscMenuLabelTextTemplate", 6410)
    if counter_frame == nil then return nil end
    frame.set_size(counter_frame, 0.04, 0.022)
    frame.set_point(counter_frame, frame.POINT_BOTTOMRIGHT, skill_button, frame.POINT_BOTTOMRIGHT, -0.002, 0.002)
    frame.set_text(counter_frame, "")
    frame.set_visible(counter_frame, false)
    return counter_frame
end

local function update_counter_frame(hero, stacks, max_stacks)
    if not local_player_owns(hero) then return end
    local widget = ensure_counter_frame(hero)
    if widget == nil then return end
    if stacks > 0 then
        frame.set_text(widget, string.format("|cffffd45e%d/%d|r", stacks, max_stacks))
        frame.set_visible(widget, true)
    else
        frame.set_visible(widget, false)
    end
end

local function state_for(hero)
    local state = hero_states[hero]
    if state == nil then
        state = {
            stacks = 0,
            stackExpiresAt = 0,
            summonLevel = 0,
            summonActive = false,
            nextSummonAt = 0,
            nextSacrificeAt = 0,
            healedThisSummon = 0,
            ghouls = {},
            stackEffect = nil,
            fullStackEffect = nil,
        }
        hero_states[hero] = state
    end
    return state
end

local function update_stack_display(hero, stacks)
    local runtime = config.get_skill_runtime("H0E0", E_RAWCODE)
    local state = state_for(hero)
    if stacks > 0 then
        if ability_level(hero, DISPLAY_ID) <= 0 and type(jass.UnitAddAbility) == "function" then
            jass.UnitAddAbility(hero, DISPLAY_ID)
        end
        if state.stackEffect == nil then state.stackEffect = play_target_effect(FROST_STACK_MODEL, hero, "hand,right") end
        if stacks >= runtime.maxStacks and state.fullStackEffect == nil then
            state.fullStackEffect = play_target_effect(FROST_FULL_MODEL, hero, "hand,right")
        elseif stacks < runtime.maxStacks and state.fullStackEffect ~= nil then
            destroy_effect(state.fullStackEffect)
            state.fullStackEffect = nil
        end
    else
        if ability_level(hero, DISPLAY_ID) > 0 and type(jass.UnitRemoveAbility) == "function" then
            jass.UnitRemoveAbility(hero, DISPLAY_ID)
        end
        destroy_effect(state.stackEffect)
        destroy_effect(state.fullStackEffect)
        state.stackEffect = nil
        state.fullStackEffect = nil
    end
    update_counter_frame(hero, stacks, runtime.maxStacks)
end

local function select_bounces(hero, first_target, maximum_bounces, radius)
    local selected = {first_target}
    local visited = {[first_target] = true}
    local current = first_target
    for _ = 1, maximum_bounces do
        if current == nil or not is_alive(current) then break end
        local x, y = jass.GetUnitX(current), jass.GetUnitY(current)
        local candidates = sorted_enemies(hero, x, y, radius)
        local next_target = nil
        for _, candidate in ipairs(candidates) do
            if not visited[candidate] then next_target = candidate; break end
        end
        if next_target == nil then break end
        visited[next_target] = true
        table.insert(selected, next_target)
        current = next_target
    end
    return selected
end

local function terrain_height(x, y)
    if type(jass.Location) ~= "function" or type(jass.GetLocationZ) ~= "function"
        or type(jass.RemoveLocation) ~= "function" then return 80 end
    local location = jass.Location(x, y)
    if location == nil then return 80 end
    local z = jass.GetLocationZ(location) or 0
    jass.RemoveLocation(location)
    return z + 80
end

local function move_orb_through_targets(hero, targets)
    if #targets == 0 or type(jass.AddSpecialEffect) ~= "function" then return end
    local start_x, start_y = jass.GetUnitX(hero), jass.GetUnitY(hero)
    local orb = jass.AddSpecialEffect(SOUL_ORB_MODEL, start_x, start_y)
    if orb == nil or type(jass.CreateTimer) ~= "function" or type(jass.TimerStart) ~= "function"
        or type(japi.DzSetEffectPos) ~= "function" then
        for _, target in ipairs(targets) do add_effect_at(SOUL_IMPACT_MODEL, jass.GetUnitX(target), jass.GetUnitY(target)) end
        if orb ~= nil then destroy_effect(orb) end
        return
    end

    local timer = jass.CreateTimer()
    local segment = 1
    local origin_x, origin_y = start_x, start_y
    local target_x, target_y = jass.GetUnitX(targets[1]), jass.GetUnitY(targets[1])
    local progress = 0
    local duration = math.max(0.08, math.sqrt(distance_squared(origin_x, origin_y, target_x, target_y)) / 1500)
    local function set_position(x, y)
        pcall(japi.DzSetEffectPos, orb, x, y, terrain_height(x, y))
    end
    set_position(origin_x, origin_y)
    jass.TimerStart(timer, 0.025, true, function()
        progress = progress + 0.025 / duration
        if progress > 1 then progress = 1 end
        local x = origin_x + (target_x - origin_x) * progress
        local y = origin_y + (target_y - origin_y) * progress
        set_position(x, y)
        if progress < 1 then return end
        add_effect_at(SOUL_IMPACT_MODEL, target_x, target_y)
        segment = segment + 1
        if segment > #targets then
            jass.PauseTimer(timer)
            destroy_effect(orb)
            if type(jass.DestroyTimer) == "function" then jass.DestroyTimer(timer) end
            return
        end
        origin_x, origin_y = target_x, target_y
        target_x, target_y = jass.GetUnitX(targets[segment]), jass.GetUnitY(targets[segment])
        duration = math.max(0.08, math.sqrt(distance_squared(origin_x, origin_y, target_x, target_y)) / 1500)
        progress = 0
    end)
end

local function cast_q(hero, level)
    local target = type(jass.GetSpellTargetUnit) == "function" and jass.GetSpellTargetUnit() or nil
    -- Channel 版死亡缠绕自施法时，部分客户端不会返回目标句柄；Q 只能指定单位，空目标按自身处理。
    if target == nil then target = hero end
    local runtime = config.get_skill_runtime("H0E0", Q_RAWCODE)
    local base_heal = runtime.healMultiplierTenth[level] or runtime.healMultiplierTenth[#runtime.healMultiplierTenth]
    local heal_bonus = skill_value(hero, Q_RAWCODE, "self_heal_multiplier_tenth_add")
    if target == hero then
        local amount = recovery.calculate_fixed(hero, base_heal + heal_bonus, common_value(hero, "recovery_percent"))
        recovery.apply_fixed(hero, amount)
        add_effect_at(HEAL_MODEL, jass.GetUnitX(hero), jass.GetUnitY(hero))
        return
    end
    if not is_alive(target) or not jass.IsUnitEnemy(target, jass.GetOwningPlayer(hero)) then return end
    local maximum_bounces = skill_value(hero, Q_RAWCODE, "extra_bounces_add")
    local targets = select_bounces(hero, target, maximum_bounces, runtime.bounceRange)
    local base_multiplier = runtime.damageMultiplierTenth[level]
        or runtime.damageMultiplierTenth[#runtime.damageMultiplierTenth]
    local previous_damage = final_skill_damage(hero, runtime.damageAttribute, base_multiplier)
    for index, victim in ipairs(targets) do
        local amount = previous_damage
        if index > 1 then
            amount = math.floor(previous_damage * runtime.bounceDamagePercent / 100)
            previous_damage = amount
        end
        damage(hero, victim, amount, jass.DAMAGE_TYPE_MAGIC)
    end
    move_orb_through_targets(hero, targets)
end

local function rawcode_is_boss(target)
    if jass.UNIT_TYPE_HERO ~= nil and type(jass.IsUnitType) == "function"
        and jass.IsUnitType(target, jass.UNIT_TYPE_HERO) then return true end
    if type(jass.GetUnitTypeId) ~= "function" then return false end
    return string.sub(integer_to_rawcode(jass.GetUnitTypeId(target)), 1, 1) == "B"
end

local function refresh_control_speed(target, control)
    if not is_alive(target) then
        control_states[target] = nil
        return
    end
    if now >= control.rootExpiresAt and now >= control.slowExpiresAt then
        if type(jass.SetUnitMoveSpeed) == "function" then jass.SetUnitMoveSpeed(target, control.originalSpeed) end
        control_states[target] = nil
        return
    end
    local speed = control.originalSpeed
    if now < control.rootExpiresAt then
        speed = 1
    elseif now < control.slowExpiresAt then
        speed = math.max(1, math.floor(control.originalSpeed * 0.70))
    end
    if type(jass.SetUnitMoveSpeed) == "function" then jass.SetUnitMoveSpeed(target, speed) end
end

local function apply_control(target, duration_hundredths)
    local control = control_states[target]
    if control == nil then
        control = {
            originalSpeed = type(jass.GetUnitMoveSpeed) == "function" and jass.GetUnitMoveSpeed(target) or 270,
            rootExpiresAt = 0,
            slowExpiresAt = 0,
        }
        control_states[target] = control
    end
    local expires = now + duration_hundredths / 100
    if rawcode_is_boss(target) or (jass.UNIT_TYPE_MAGIC_IMMUNE ~= nil
        and type(jass.IsUnitType) == "function" and jass.IsUnitType(target, jass.UNIT_TYPE_MAGIC_IMMUNE)) then
        control.slowExpiresAt = math.max(control.slowExpiresAt, expires)
    else
        control.rootExpiresAt = math.max(control.rootExpiresAt, expires)
    end
    refresh_control_speed(target, control)
end

local function cast_w(hero, level)
    local runtime = config.get_skill_runtime("H0E0", W_RAWCODE)
    local x = type(jass.GetSpellTargetX) == "function" and jass.GetSpellTargetX() or jass.GetUnitX(hero)
    local y = type(jass.GetSpellTargetY) == "function" and jass.GetSpellTargetY() or jass.GetUnitY(hero)
    local radius = runtime.area + skill_value(hero, W_RAWCODE, "area_add")
    local duration = 100 + skill_value(hero, W_RAWCODE, "control_duration_hundredths_add")
    local multiplier = runtime.damageMultiplierTenth[level] or runtime.damageMultiplierTenth[#runtime.damageMultiplierTenth]
    local amount = final_skill_damage(hero, runtime.damageAttribute, multiplier)
    add_effect_at(FROST_BURST_MODEL, x, y)
    for _, target in ipairs(sorted_enemies(hero, x, y, radius)) do
        damage(hero, target, amount, jass.DAMAGE_TYPE_MAGIC)
        apply_control(target, duration)
        add_effect_at(FROST_HIT_MODEL, jass.GetUnitX(target), jass.GetUnitY(target))
    end
end

local function clear_stacks(hero, state)
    state.stacks = 0
    state.stackExpiresAt = 0
    update_stack_display(hero, 0)
end

local function apply_frostmourne_attack(hero, target)
    local level = ability_level(hero, E_ID)
    if level <= 0 or not is_alive(target) or not jass.IsUnitEnemy(target, jass.GetOwningPlayer(hero)) then return end
    local runtime = config.get_skill_runtime("H0E0", E_RAWCODE)
    local state = state_for(hero)
    if state.stacks < runtime.maxStacks then
        state.stacks = math.min(runtime.maxStacks, state.stacks + 1)
        state.stackExpiresAt = now + runtime.duration
        update_stack_display(hero, state.stacks)
        if state.stacks == runtime.maxStacks then
            add_effect_at(FROST_FULL_MODEL, jass.GetUnitX(hero), jass.GetUnitY(hero))
        end
        return
    end

    local multiplier = runtime.procDamageMultiplierTenth[level]
        or runtime.procDamageMultiplierTenth[#runtime.procDamageMultiplierTenth]
    local amount = final_skill_damage(hero, runtime.procDamageAttribute, multiplier)
    damage(hero, target, amount, jass.DAMAGE_TYPE_MAGIC)
    add_effect_at(FROST_HIT_MODEL, jass.GetUnitX(target), jass.GetUnitY(target))

    local radius = runtime.procRadius + skill_value(hero, E_RAWCODE, "proc_radius_add")
    if radius > 0 then
        for _, victim in ipairs(sorted_enemies(hero, jass.GetUnitX(target), jass.GetUnitY(target), radius)) do
            if victim ~= target then
                damage(hero, victim, amount, jass.DAMAGE_TYPE_MAGIC)
                add_effect_at(SOUL_IMPACT_MODEL, jass.GetUnitX(victim), jass.GetUnitY(victim))
            end
        end
    end

    local heal_multiplier = skill_value(hero, E_RAWCODE, "proc_heal_multiplier_tenth_add")
    if heal_multiplier > 0 then
        recovery.apply_fixed(hero, recovery.calculate_fixed(hero, heal_multiplier, 0))
        add_effect_at(HEAL_MODEL, jass.GetUnitX(hero), jass.GetUnitY(hero))
    end
    clear_stacks(hero, state)
end

local function count_living_ghouls(state)
    local count = 0
    for ghoul in pairs(state.ghouls) do
        if is_alive(ghoul) then count = count + 1 end
    end
    return count
end

local function add_ability(unit_handle, ability_id, level)
    if type(jass.UnitAddAbility) ~= "function" then return false end
    if ability_level(unit_handle, ability_id) <= 0 and not jass.UnitAddAbility(unit_handle, ability_id) then return false end
    if level ~= nil and type(jass.SetUnitAbilityLevel) == "function" then
        jass.SetUnitAbilityLevel(unit_handle, ability_id, math.max(1, math.min(10, math.floor(level))))
    end
    return true
end

local function remove_ability(unit_handle, ability_id)
    if ability_level(unit_handle, ability_id) > 0 and type(jass.UnitRemoveAbility) == "function" then
        jass.UnitRemoveAbility(unit_handle, ability_id)
    end
end

local function switch_to_sacrifice(hero, state)
    remove_ability(hero, R_ID)
    if not add_ability(hero, SACRIFICE_ID, state.summonLevel) then
        add_ability(hero, R_ID, state.summonLevel)
        show_hero_message(hero, "亡灵大军已召唤，但献祭按钮切换失败。")
        return false
    end
    return true
end

local function restore_summon_cooldown(hero, state)
    -- R is replaced by the sacrifice ability while ghouls live; reapply the
    -- remaining native cooldown when the summon ability returns to the slot.
    local remaining = math.max(0, state.nextSummonAt - now)
    if remaining > 0 then
        if type(jass.BlzStartUnitAbilityCooldown) == "function" then
            jass.BlzStartUnitAbilityCooldown(hero, R_ID, remaining)
        end
    elseif type(jass.BlzEndUnitAbilityCooldown) == "function" then
        jass.BlzEndUnitAbilityCooldown(hero, R_ID)
    end
end

local function rollback_summon_attempt(hero, state, level, runtime)
    local mana_cost = runtime.summonManaCost[level] or runtime.summonManaCost[#runtime.summonManaCost] or 0
    if mana_cost > 0 and type(jass.GetUnitState) == "function" and type(jass.SetUnitState) == "function"
        and jass.UNIT_STATE_MANA ~= nil and jass.UNIT_STATE_MAX_MANA ~= nil then
        local mana = jass.GetUnitState(hero, jass.UNIT_STATE_MANA) or 0
        local max_mana = jass.GetUnitState(hero, jass.UNIT_STATE_MAX_MANA) or (mana + mana_cost)
        jass.SetUnitState(hero, jass.UNIT_STATE_MANA, math.min(max_mana, mana + mana_cost))
    end
    restore_summon_cooldown(hero, state)
end

local function switch_to_summon(hero)
    remove_ability(hero, SACRIFICE_ID)
    local state = state_for(hero)
    if not add_ability(hero, R_ID, state.summonLevel > 0 and state.summonLevel or 1) then
        show_hero_message(hero, "亡灵大军技能恢复失败，请重新选择阿尔萨斯。")
        return false
    end
    restore_summon_cooldown(hero, state)
    return true
end

local function remove_ghoul(hero, ghoul, remove_unit)
    local state = hero_states[hero]
    if state == nil or state.ghouls[ghoul] == nil then return end
    state.ghouls[ghoul] = nil
    ghoul_owners[ghoul] = nil
    if remove_unit and type(jass.RemoveUnit) == "function" then jass.RemoveUnit(ghoul) end
    if state.summonActive and count_living_ghouls(state) <= 0 then
        state.summonActive = false
        switch_to_summon(hero)
    end
end

local function summon_ghouls(hero, level, x, y)
    local runtime = config.get_skill_runtime("H0E0", R_RAWCODE)
    local state = state_for(hero)
    if now < state.nextSummonAt then
        rollback_summon_attempt(hero, state, level, runtime)
        show_hero_message(hero, string.format("亡灵大军冷却中：还需 %d 秒。", math.ceil(state.nextSummonAt - now)))
        return
    end
    local count = (runtime.summonCount[level] or runtime.summonCount[#runtime.summonCount])
        + skill_value(hero, R_RAWCODE, "summon_count_add")
    local duration = runtime.summonDuration[level] or runtime.summonDuration[#runtime.summonDuration]
    local unit_id = rawcode_to_integer(runtime.summonRawcode)
    if unit_id == nil or type(jass.CreateUnit) ~= "function" then
        rollback_summon_attempt(hero, state, level, runtime)
        show_hero_message(hero, "亡灵大军召唤失败：食尸鬼单位配置缺失。")
        return
    end
    state.summonLevel = level
    state.summonActive = true
    state.healedThisSummon = 0
    local player = jass.GetOwningPlayer(hero)
    local created_count = 0
    for index = 1, count do
        local angle = (index - 1) * 6.283185307179586 / math.max(1, count)
        local spawn_x = x + math.cos(angle) * 96
        local spawn_y = y + math.sin(angle) * 96
        local ghoul = jass.CreateUnit(player, unit_id, spawn_x, spawn_y, angle * 57.29577951308232)
        if ghoul ~= nil then
            created_count = created_count + 1
            if type(jass.SetUnitPosition) == "function" then jass.SetUnitPosition(ghoul, spawn_x, spawn_y) end
            state.ghouls[ghoul] = {
                lastAttackAt = now - runtime.summonAttackIntervalHundredth / 100,
                nextTargetScanAt = 0,
            }
            ghoul_owners[ghoul] = hero
            damage_service.register_attack_source(ghoul, hero)
            if type(jass.UnitApplyTimedLife) == "function" then jass.UnitApplyTimedLife(ghoul, TIMED_LIFE_ID, duration) end
            if type(jass.IssueTargetOrder) == "function" then jass.IssueTargetOrder(ghoul, "smart", hero) end
        end
    end
    if created_count <= 0 then
        state.summonActive = false
        state.healedThisSummon = 0
        switch_to_summon(hero)
        rollback_summon_attempt(hero, state, level, runtime)
        show_hero_message(hero, "食尸鬼没有找到可用位置，请换一个地点再召唤。")
        return
    end
    state.nextSummonAt = now + (runtime.summonCooldown[level] or runtime.summonCooldown[#runtime.summonCooldown])
    add_effect_at(SUMMON_MODEL, x, y)
    switch_to_sacrifice(hero, state)
    if created_count < count then
        show_hero_message(hero, string.format("亡灵大军已召唤：%d/%d 只食尸鬼找到位置。", created_count, count))
    end
    if count_living_ghouls(state) <= 0 then
        state.summonActive = false
        switch_to_summon(hero)
    end
end

local function sacrifice_nearest_ghoul(hero)
    local state = state_for(hero)
    if not state.summonActive then
        switch_to_summon(hero)
        return
    end
    if now < state.nextSacrificeAt then
        show_hero_message(hero, string.format("献祭冷却中：还需 %d 秒。", math.ceil(state.nextSacrificeAt - now)))
        return
    end
    local hero_x, hero_y = jass.GetUnitX(hero), jass.GetUnitY(hero)
    local nearest = nil
    local nearest_distance = nil
    for ghoul in pairs(state.ghouls) do
        if is_alive(ghoul) then
            local distance = distance_squared(hero_x, hero_y, jass.GetUnitX(ghoul), jass.GetUnitY(ghoul))
            if nearest == nil or distance < nearest_distance
                or (distance == nearest_distance and type(jass.GetHandleId) == "function"
                    and jass.GetHandleId(ghoul) < jass.GetHandleId(nearest)) then
                nearest = ghoul
                nearest_distance = distance
            end
        end
    end
    if nearest == nil then
        state.summonActive = false
        switch_to_summon(hero)
        return
    end

    state.nextSacrificeAt = now + config.get_skill_runtime("H0E0", R_RAWCODE).sacrificeCooldown
    local runtime = config.get_skill_runtime("H0E0", R_RAWCODE)
    local bonus = skill_value(hero, R_RAWCODE, "sacrifice_heal_multiplier_tenth_add")
    local heal = recovery.calculate_fixed(hero, runtime.sacrificeHealMultiplierTenth + bonus, 0)
    local maximum = type(jass.GetUnitState) == "function" and jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE) or 0
    local cap = math.floor(maximum * runtime.healCapPercent / 100)
    heal = math.min(heal, math.max(0, cap - state.healedThisSummon))
    local before = type(jass.GetUnitState) == "function" and jass.GetUnitState(hero, jass.UNIT_STATE_LIFE) or 0

    local ghoul_x, ghoul_y = jass.GetUnitX(nearest), jass.GetUnitY(nearest)
    add_effect_at(SACRIFICE_MODEL, ghoul_x, ghoul_y)
    remove_ghoul(hero, nearest, true)
    recovery.apply_fixed(hero, heal)
    local after = type(jass.GetUnitState) == "function" and jass.GetUnitState(hero, jass.UNIT_STATE_LIFE) or before
    state.healedThisSummon = state.healedThisSummon + math.max(0, math.floor(after - before))
    add_effect_at(HEAL_MODEL, hero_x, hero_y)
end

local function on_ghoul_attack(ghoul, target)
    local hero = ghoul_owners[ghoul]
    if hero == nil or not is_alive(hero) or not is_alive(target)
        or not jass.IsUnitEnemy(target, jass.GetOwningPlayer(hero)) then return end
    local state = state_for(hero)
    local ghoul_state = state.ghouls[ghoul]
    if ghoul_state == nil then return end
    local runtime = config.get_skill_runtime("H0E0", R_RAWCODE)
    local interval = runtime.summonAttackIntervalHundredth / 100
    if now < ghoul_state.lastAttackAt + interval then return end
    ghoul_state.lastAttackAt = now
    local amount = final_skill_damage_hundredth(
        hero,
        runtime.summonDamageAttribute,
        runtime.summonDamageMultiplierHundredth
    )
    damage(hero, target, amount, jass.DAMAGE_TYPE_NORMAL)
end

local function on_attack(attacker, target)
    local ghoul_owner = ghoul_owners[attacker]
    if ghoul_owner ~= nil then
        on_ghoul_attack(attacker, target)
        return
    end
    local hero_rawcode = heroes[attacker]
    if hero_rawcode == "H0E0" then apply_frostmourne_attack(attacker, target) end
end

local function on_death(dying)
    local hero = ghoul_owners[dying]
    if hero ~= nil then remove_ghoul(hero, dying, false) end
end

local function update_states()
    elapsed_ticks = elapsed_ticks + 1
    now = elapsed_ticks * TICK_SECONDS
    for hero, state in pairs(hero_states) do
        if state.stacks > 0 and now >= state.stackExpiresAt then clear_stacks(hero, state) end
        update_ghoul_orders(hero, state)
        if state.summonActive and count_living_ghouls(state) <= 0 then
            state.summonActive = false
            switch_to_summon(hero)
        end
    end
    for target, control in pairs(control_states) do refresh_control_speed(target, control) end
end

local function register_events()
    spell_trigger = jass.CreateTrigger()
    attack_trigger = jass.CreateTrigger()
    death_trigger = jass.CreateTrigger()
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
        if ability_id == Q_ID then
            cast_q(hero, ability_level(hero, Q_ID))
        elseif ability_id == W_ID then
            cast_w(hero, ability_level(hero, W_ID))
        elseif ability_id == R_ID then
            local state = state_for(hero)
            if state.summonActive then
                sacrifice_nearest_ghoul(hero)
            else
                local level = ability_level(hero, R_ID)
                local x = type(jass.GetSpellTargetX) == "function" and jass.GetSpellTargetX() or jass.GetUnitX(hero)
                local y = type(jass.GetSpellTargetY) == "function" and jass.GetSpellTargetY() or jass.GetUnitY(hero)
                summon_ghouls(hero, level, x, y)
            end
        elseif ability_id == SACRIFICE_ID then
            sacrifice_nearest_ghoul(hero)
        end
    end)
    jass.TriggerAddAction(attack_trigger, function()
        local attacker = type(jass.GetAttacker) == "function" and jass.GetAttacker() or nil
        local target = type(jass.GetAttackedUnitBJ) == "function" and jass.GetAttackedUnitBJ()
            or (type(jass.GetTriggerUnit) == "function" and jass.GetTriggerUnit() or nil)
        if attacker ~= nil and target ~= nil then on_attack(attacker, target) end
    end)
    jass.TriggerAddAction(death_trigger, function()
        local dying = type(jass.GetDyingUnit) == "function" and jass.GetDyingUnit() or jass.GetTriggerUnit()
        if dying ~= nil then on_death(dying) end
    end)
end

function module.start(hero_results)
    if started then return false end
    started = true
    Q_ID, W_ID, E_ID, R_ID = rawcode_to_integer(Q_RAWCODE), rawcode_to_integer(W_RAWCODE),
        rawcode_to_integer(E_RAWCODE), rawcode_to_integer(R_RAWCODE)
    DISPLAY_ID, SACRIFICE_ID = rawcode_to_integer(DISPLAY_RAWCODE), rawcode_to_integer(SACRIFICE_RAWCODE)
    TIMED_LIFE_ID = rawcode_to_integer(TIMED_LIFE_RAWCODE)
    for _, result in ipairs(hero_results or {}) do
        if result.unit ~= nil and result.hero and result.hero.rawcode == "H0E0" then
            heroes[result.unit] = "H0E0"
            state_for(result.unit)
            ensure_counter_frame(result.unit)
        end
    end
    register_events()
    update_timer = jass.CreateTimer()
    if update_timer ~= nil then jass.TimerStart(update_timer, TICK_SECONDS, true, update_states) end
    return true
end

function module.get_state(hero)
    return hero_states[hero]
end

return module
