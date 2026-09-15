--- 英雄统一属性聚合服务。
--- 装备、肉鸽等系统提交来源数值；本模块统一投影到 Warcraft 原生属性，并向本地 UI 发布快照。
local jass = require "jass.common"
local equipment_config = require "config.equipment"
local attribute_config = require "config.attributes"
local unit_config = require "config.units"
local events = JiuDou.core and JiuDou.core.events
local timer_service = JiuDou.core and JiuDou.core.timer
local resource_api = JiuDou.core and JiuDou.core.resource

local module = {}

local ATTRIBUTE_IDS = {
    "strength",
    "agility",
    "intelligence",
    "attack",
    "health",
    "armor",
    "moveSpeed",
    "attack_speed_percent",
    "basic_attack_bonus_percent",
    "health_amplification_percent",
}

local sources_by_hero = {}
local applied_states = {}
local listeners = {}
local preload_timer = nil
local preload_scope = nil
local preload_dummy = nil
local preload_index = 1
local preload_completed = false
local preload_total_steps = 0
local preload_elapsed_seconds = 0
local preload_callbacks = {}

local PRELOAD_INTERVAL_SECONDS = 0.04
local PRELOAD_OPERATIONS_PER_TICK = 4
local PRELOAD_DUMMY_RAWCODE = "hpea"
-- 生命状态投影使用七位临时 AIlf 技能，最多可额外写入 9,999,999 点生命。
local MAX_DIGIT_COUNT = 7
-- 三维属性的 Warcraft 原生副作用由 war3mapMisc.txt 全局归零。
-- 本模块只投影项目规则，绝不对原生力量/敏捷/智力效果进行抵销。
local PRIMARY_ATTRIBUTE_BY_CODE = {
    STR = "strength",
    AGI = "agility",
    INT = "intelligence",
}

local function rawcode_to_integer(rawcode)
    if type(rawcode) ~= "string" or #rawcode ~= 4 then return nil end
    local a, b, c, d = string.byte(rawcode, 1, 4)
    if a == nil or b == nil or c == nil or d == nil then return nil end
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local function empty_values()
    return {
        strength = 0,
        agility = 0,
        intelligence = 0,
        attack = 0,
        health = 0,
        armor = 0,
        moveSpeed = 0,
        attack_speed_percent = 0,
        basic_attack_bonus_percent = 0,
        health_amplification_percent = 0,
    }
end

local function normalize_values(values)
    values = type(values) == "table" and values or {}
    local normalized = empty_values()
    for _, attribute_id in ipairs(ATTRIBUTE_IDS) do
        normalized[attribute_id] = math.floor(tonumber(values[attribute_id]) or 0)
    end
    return normalized
end

local function copy_values(values)
    local copied = empty_values()
    for _, attribute_id in ipairs(ATTRIBUTE_IDS) do
        copied[attribute_id] = math.floor(tonumber(values and values[attribute_id]) or 0)
    end
    return copied
end

local function ensure_ability(unit_handle, rawcode)
    local ability_id = rawcode_to_integer(rawcode)
    if ability_id == nil or type(jass.UnitAddAbility) ~= "function" then return false end
    local current = type(jass.GetUnitAbilityLevel) == "function"
        and (jass.GetUnitAbilityLevel(unit_handle, ability_id) or 0) or 0
    return current > 0 or jass.UnitAddAbility(unit_handle, ability_id)
end

local function set_ability_level(unit_handle, rawcode, level)
    local ability_id = rawcode_to_integer(rawcode)
    if ability_id == nil or type(jass.SetUnitAbilityLevel) ~= "function"
        or type(jass.UnitAddAbility) ~= "function" then return false end
    level = math.max(1, math.min(10, math.floor(tonumber(level) or 1)))
    local current = type(jass.GetUnitAbilityLevel) == "function"
        and (jass.GetUnitAbilityLevel(unit_handle, ability_id) or 0) or 0
    if current <= 0 and not jass.UnitAddAbility(unit_handle, ability_id) then return false end
    if current ~= level then jass.SetUnitAbilityLevel(unit_handle, ability_id, level) end
    return true
end

local function get_max_projected_value(rawcodes)
    local digit_count = type(rawcodes) == "table" and #rawcodes or 0
    if digit_count < 1 or digit_count > MAX_DIGIT_COUNT then return nil end
    return 10 ^ digit_count - 1
end

local function normalize_projected_value(value, maximum)
    maximum = math.max(0, math.floor(tonumber(maximum) or 0))
    return math.max(0, math.min(maximum, math.floor(tonumber(value) or 0)))
end

local function normalize_signed_projected_value(value, maximum)
    maximum = math.max(0, math.floor(tonumber(maximum) or 0))
    return math.max(-maximum, math.min(maximum, math.floor(tonumber(value) or 0)))
end

local function apply_digit_stat(hero, rawcodes, value, previous_value)
    local maximum = get_max_projected_value(rawcodes)
    if maximum == nil then return false end
    value = normalize_projected_value(value, maximum)
    previous_value = normalize_projected_value(previous_value, maximum)
    local function set_digits(reverse)
        local start_index, end_index, step = reverse and 4 or 1, reverse and 1 or 4, reverse and -1 or 1
        for index = start_index, end_index, step do
            local divisor = 10 ^ (index - 1)
            local level = math.floor(value / divisor) % 10 + 1
            if not set_ability_level(hero, rawcodes[index], level) then return false end
        end
        return true
    end
    return set_digits(value >= previous_value)
end

local function get_digit_levels(value, rawcodes)
    local maximum = get_max_projected_value(rawcodes)
    if maximum == nil then return {} end
    value = normalize_projected_value(value, maximum)
    local levels = {}
    for index = 1, #rawcodes do
        local divisor = 10 ^ (index - 1)
        levels[index] = math.floor(value / divisor) % 10 + 1
    end
    return levels
end

local function get_ability_levels(hero, rawcodes)
    local levels = {}
    for index, rawcode in ipairs(rawcodes or {}) do
        local ability_id = rawcode_to_integer(rawcode)
        levels[index] = ability_id ~= nil and type(jass.GetUnitAbilityLevel) == "function"
            and math.floor(jass.GetUnitAbilityLevel(hero, ability_id) or 0) or 0
    end
    return levels
end

local function get_absent_ability_levels(rawcodes)
    local levels = {}
    for index = 1, #(rawcodes or {}) do levels[index] = 0 end
    return levels
end

local function get_state_ratio(hero, maximum_state, current_state)
    if type(jass.GetUnitState) ~= "function" or maximum_state == nil or current_state == nil then return nil end
    local maximum = jass.GetUnitState(hero, maximum_state)
    local current = jass.GetUnitState(hero, current_state)
    if maximum == nil or maximum <= 0 or current == nil then return nil end
    return math.max(0, math.min(1, current / maximum))
end

-- Warcraft 1.27 的 UNIT_STATE_MAX_LIFE 不能直接写入。
-- AIlf 的可靠兼容写法是：临时添加一个“反向数值”的生命技能，设置等级后立刻移除。
-- 引擎在移除技能时会反向结算该技能，从而把目标生命差额永久写进单位状态。
-- 生命技能绝不能常驻；常驻只会显示技能等级，某些 1.27 客户端并不会将其结算为英雄最大生命。
local function apply_temporary_life_digit(hero, rawcode, level)
    local ability_id = rawcode_to_integer(rawcode)
    if ability_id == nil or type(jass.UnitAddAbility) ~= "function"
        or type(jass.SetUnitAbilityLevel) ~= "function" or type(jass.UnitRemoveAbility) ~= "function" then
        return false
    end
    level = math.max(2, math.min(10, math.floor(tonumber(level) or 2)))
    if not jass.UnitAddAbility(hero, ability_id) then return false end
    local level_ok = jass.SetUnitAbilityLevel(hero, ability_id, level)
    local remove_ok = jass.UnitRemoveAbility(hero, ability_id)
    return level_ok ~= false and remove_ok ~= false
end

local function apply_temporary_life_digits(hero, rawcodes, value)
    local maximum = get_max_projected_value(rawcodes)
    if maximum == nil then return false end
    value = normalize_projected_value(value, maximum)
    for index, rawcode in ipairs(rawcodes) do
        local divisor = 10 ^ (index - 1)
        local digit = math.floor(value / divisor) % 10
        if digit > 0 and not apply_temporary_life_digit(hero, rawcode, digit + 1) then
            return false
        end
    end
    return true
end

local function apply_life_projection(hero, abilities, value, previous_value, base_maximum)
    local maximum = math.min(
        get_max_projected_value(abilities.healthDecrease) or 0,
        get_max_projected_value(abilities.healthIncrease) or 0
    )
    if maximum <= 0 then return false end
    value = normalize_signed_projected_value(value, maximum)
    previous_value = normalize_signed_projected_value(previous_value, maximum)
    local ratio = get_state_ratio(hero, jass.UNIT_STATE_MAX_LIFE, jass.UNIT_STATE_LIFE)
    local delta = value - previous_value
    if delta > 0 then
        -- healthIncrease 的 DataA 为负数；移除后永久增加生命。
        if not apply_temporary_life_digits(hero, abilities.healthIncrease, delta) then return false end
    elseif delta < 0 then
        -- healthDecrease 的 DataA 为正数；移除后永久减少生命。
        if not apply_temporary_life_digits(hero, abilities.healthDecrease, -delta) then return false end
    end
    if ratio ~= nil and type(jass.SetUnitState) == "function" then
        local maximum = jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE)
        jass.SetUnitState(hero, jass.UNIT_STATE_LIFE, maximum * ratio)
    end
    local actual_maximum = type(jass.GetUnitState) == "function" and jass.UNIT_STATE_MAX_LIFE ~= nil
        and math.floor(tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE)) or 0) or 0
    local expected_maximum = math.floor(tonumber(base_maximum) or 0) + value
    return actual_maximum == expected_maximum
end

local function apply_signed_projection(hero, positive_abilities, negative_abilities, value, previous_value)
    local maximum = math.min(
        get_max_projected_value(positive_abilities) or 0,
        get_max_projected_value(negative_abilities) or 0
    )
    if maximum <= 0 then return false end
    value = normalize_signed_projected_value(value, maximum)
    previous_value = normalize_signed_projected_value(previous_value, maximum)
    local positive = math.max(0, value)
    local negative = math.max(0, -value)
    local previous_positive = math.max(0, previous_value)
    local previous_negative = math.max(0, -previous_value)
    if value >= previous_value then
        if not apply_digit_stat(hero, negative_abilities, negative, previous_negative) then return false end
        if not apply_digit_stat(hero, positive_abilities, positive, previous_positive) then return false end
    else
        if not apply_digit_stat(hero, positive_abilities, positive, previous_positive) then return false end
        if not apply_digit_stat(hero, negative_abilities, negative, previous_negative) then return false end
    end
    return true
end

--- 攻速投影必须在每次属性刷新时校验，不能只相信 Lua 缓存。
--- Warcraft 原生升级或属性重算可能保留缓存值、却覆盖 AIsx 的实际等级。
local function apply_attack_speed_projection(hero, state, abilities, desired_attack_speed)
    if abilities.attackSpeedPositive == nil or abilities.attackSpeedNegative == nil then return false end
    -- previous_value 故意传入当前目标值，让八个数字技能无论缓存是否变化都逐个核对。
    if not apply_signed_projection(
        hero,
        abilities.attackSpeedPositive,
        abilities.attackSpeedNegative,
        desired_attack_speed,
        desired_attack_speed
    ) then
        return false
    end
    state.applied.attackSpeed = desired_attack_speed
    return true
end

local function ensure_stat_abilities(hero)
    local abilities = equipment_config.statAbilities
    for _, group in ipairs({
        abilities.attack,
        abilities.attackDecrease,
        abilities.armor,
        abilities.armorDecrease,
        abilities.attackSpeedPositive,
        abilities.attackSpeedNegative,
    }) do
        if get_max_projected_value(group) == nil then return false end
        for _, rawcode in ipairs(group) do
            if not ensure_ability(hero, rawcode) then return false end
        end
    end
    return true
end

local function make_state(hero, primary_attribute, hero_rawcode)
    if not ensure_stat_abilities(hero) then return nil end
    local initial_max_life = type(jass.GetUnitState) == "function" and jass.UNIT_STATE_MAX_LIFE ~= nil
        and (tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE)) or 0) or 0
    local unit = unit_config[hero_rawcode or ""] or {}
    local base_attack_speed_percent = math.max(1, math.floor(tonumber(unit.initialAttackSpeedPercent) or 100))
    return {
        appliedSources = empty_values(),
        applied = {
            attack = 0,
            health = 0,
            armor = 0,
            attackSpeed = 0,
        },
        snapshot = empty_values(),
        primaryAttribute = PRIMARY_ATTRIBUTE_BY_CODE[primary_attribute] or "strength",
        heroRawcode = hero_rawcode,
        baseMaxLife = initial_max_life,
        baseArmorTenth = math.floor(tonumber(unit.def) or 0) * 10,
        -- 原生主属性攻击奖励已归零；基础最小攻击仍为 dmgplus1 + dice1。
        -- TAB 显示同样采用最小攻击，避免与底部英雄栏相差 1 点。
        baseAttack = math.floor(tonumber(unit.dmgplus1) or 0)
            + math.floor(tonumber(unit.dice1) or 0),
        baseMoveSpeed = type(jass.GetUnitMoveSpeed) == "function" and jass.GetUnitMoveSpeed(hero) or nil,
        -- 100 表示标准攻击速度；字段仅配置在英雄 Lua 配置中，不写入 Warcraft 物编。
        baseAttackSpeedPercent = base_attack_speed_percent,
    }
end

local function sum_sources(hero)
    local total = empty_values()
    for _, values in pairs(sources_by_hero[hero] or {}) do
        for _, attribute_id in ipairs(ATTRIBUTE_IDS) do
            total[attribute_id] = total[attribute_id] + values[attribute_id]
        end
    end
    return total
end

local function calculate_attack_speed_projection(state, total)
    -- 100%=标准攻速；500%=标准攻速的五倍。属性来源按百分点直接相加。
    local attack_speed_percent = math.max(1, (state.baseAttackSpeedPercent or 100) + total.attack_speed_percent)
    -- AIsx 使用十分之一百分比定点。敏捷原生攻速已由游戏常数归零。
    local desired_attack_speed = (attack_speed_percent - 100) * 10
    return attack_speed_percent, desired_attack_speed
end

local function apply_primary_attribute(hero, state, attribute_id, getter, setter, source_total)
    if type(getter) ~= "function" then
        return source_total
    end
    local current = math.floor(tonumber(getter(hero, true)) or 0)
    local native_base = current - (state.appliedSources[attribute_id] or 0)
    local target = math.max(0, native_base + source_total)
    if target ~= current and type(setter) == "function" then
        setter(hero, target, true)
    end
    state.appliedSources[attribute_id] = target - native_base
    return target
end

local function notify_listeners(hero, snapshot)
    if events ~= nil and type(events.emit) == "function" then
        events.emit("hero.stats_changed", {
            hero = hero,
            snapshot = snapshot,
        })
    end
    for _, listener in ipairs(listeners) do
        pcall(listener, hero, snapshot)
    end
end

local function notify_source_changed(hero, source_id, values, removed)
    if events ~= nil and type(events.emit) == "function" then
        events.emit("hero.source_changed", {
            hero = hero,
            sourceId = source_id,
            values = copy_values(values),
            removed = removed == true,
        })
    end
end

local function finish_preload()
    if preload_timer ~= nil and type(jass.TimerGetElapsed) == "function" then
        preload_elapsed_seconds = math.max(0, jass.TimerGetElapsed(preload_timer) or 0)
    end
    if preload_timer ~= nil then
        if preload_scope ~= nil and type(preload_scope.detach) == "function" then
            preload_scope:detach(preload_timer)
        end
        if timer_service ~= nil and type(timer_service.cancel) == "function" then
            timer_service.cancel(preload_timer)
        else
            jass.PauseTimer(preload_timer)
            jass.DestroyTimer(preload_timer)
        end
        preload_timer = nil
    end
    if preload_scope ~= nil then
        preload_scope:clear()
        preload_scope = nil
    end
    if preload_dummy ~= nil and type(jass.RemoveUnit) == "function" then
        jass.RemoveUnit(preload_dummy)
        preload_dummy = nil
    end
    preload_completed = true
    print(string.format("属性预热完成：等级组合=%d，耗时=%.2f 秒", preload_total_steps, preload_elapsed_seconds))
    local callbacks = preload_callbacks
    preload_callbacks = {}
    for _, callback in ipairs(callbacks) do pcall(callback) end
end

local function get_preload_rawcodes()
    local abilities = equipment_config.statAbilities
    local result = {}
    for _, group in ipairs({
        abilities.attack,
        abilities.attackDecrease,
        abilities.armor,
        abilities.armorDecrease,
        abilities.attackSpeedPositive,
        abilities.attackSpeedNegative,
    }) do
        if get_max_projected_value(group) == nil then return nil end
        for _, rawcode in ipairs(group) do table.insert(result, rawcode) end
    end
    return result
end

--- 在选将界面出现前预热项目属性实际使用的十级隐藏技能等级组合。
---@param on_completed fun()|nil
---@return boolean started_or_completed
function module.preload(on_completed)
    if type(on_completed) == "function" then
        if preload_completed then
            on_completed()
        else
            table.insert(preload_callbacks, on_completed)
        end
    end
    if preload_completed or preload_timer ~= nil then return true end
    local abilities = equipment_config.statAbilities
    if abilities == nil or type(jass.CreateUnit) ~= "function" then return false end
    local dummy_id = rawcode_to_integer(PRELOAD_DUMMY_RAWCODE)
    if dummy_id == nil then return false end
    preload_dummy = jass.CreateUnit(jass.Player(15), dummy_id, 0.0, 0.0, 0.0)
    if preload_dummy == nil then return false end
    if type(jass.ShowUnit) == "function" then jass.ShowUnit(preload_dummy, false) end
    local rawcodes = get_preload_rawcodes()
    if rawcodes == nil then
        if type(jass.RemoveUnit) == "function" then jass.RemoveUnit(preload_dummy) end
        preload_dummy = nil
        return false
    end
    preload_index = 1
    preload_total_steps = #rawcodes * 10
    preload_elapsed_seconds = 0
    local function on_preload_tick()
        for _ = 1, PRELOAD_OPERATIONS_PER_TICK do
            if preload_index > preload_total_steps then break end
            local rawcode_index = math.floor((preload_index - 1) / 10) + 1
            local level = (preload_index - 1) % 10 + 1
            local ability_id = rawcode_to_integer(rawcodes[rawcode_index])
            if ability_id ~= nil then
                if level == 1 then jass.UnitAddAbility(preload_dummy, ability_id) end
                jass.SetUnitAbilityLevel(preload_dummy, ability_id, level)
                if level == 10 then jass.UnitRemoveAbility(preload_dummy, ability_id) end
            end
            preload_index = preload_index + 1
        end
        if preload_index > preload_total_steps then finish_preload() end
    end
    preload_scope = resource_api ~= nil and resource_api.scope("hero_stats_preload") or nil
    if timer_service ~= nil and type(timer_service.every) == "function" then
        preload_timer = timer_service.every(PRELOAD_INTERVAL_SECONDS, on_preload_tick, preload_scope)
    else
        preload_timer = jass.CreateTimer()
        jass.TimerStart(preload_timer, PRELOAD_INTERVAL_SECONDS, true, on_preload_tick)
    end
    if preload_timer == nil then
        if preload_scope ~= nil then
            preload_scope:clear()
            preload_scope = nil
        end
        if type(jass.RemoveUnit) == "function" then jass.RemoveUnit(preload_dummy) end
        preload_dummy = nil
        return false
    end
    print(string.format("属性系统准备中：预热 %d 个等级组合", preload_total_steps))
    return true
end

---@return table status
function module.get_preload_status()
    return {
        completed = preload_completed,
        completedSteps = math.min(math.max(0, preload_index - 1), preload_total_steps),
        totalSteps = preload_total_steps,
        elapsedSeconds = preload_elapsed_seconds,
    }
end

--- 注册一名已创建英雄，建立统一属性状态与原生投影基线。
---@param hero unit
---@param primary_attribute string|nil 英雄定义中的 STR / AGI / INT；未传入时兼容按力量处理
---@return boolean registered
function module.register_hero(hero, primary_attribute, hero_rawcode)
    if hero == nil or equipment_config.statAbilities == nil then return false end
    sources_by_hero[hero] = sources_by_hero[hero] or {}
    local is_new_registration = applied_states[hero] == nil
    if applied_states[hero] ~= nil then
        applied_states[hero].primaryAttribute = PRIMARY_ATTRIBUTE_BY_CODE[primary_attribute]
            or applied_states[hero].primaryAttribute
        applied_states[hero].heroRawcode = hero_rawcode or applied_states[hero].heroRawcode
    else
        applied_states[hero] = make_state(hero, primary_attribute, hero_rawcode)
        if applied_states[hero] == nil then return false end
    end
    local refreshed = module.refresh(hero)
    if refreshed and is_new_registration then
        local debug = module.get_attack_speed_debug(hero)
        if debug ~= nil then
            print(string.format(
                "英雄攻速初始化：hero=%s, cool1=%.3f, 配置=%d%%, 来源=%+d%%, 目标=%d%%, 敏捷=%d, 隐藏投影=%+.1f%%",
                tostring(debug.heroRawcode or "unknown"),
                debug.baseAttackCooldown,
                debug.configuredPercent,
                debug.sourceBonusPercent,
                debug.targetPercent,
                debug.agility,
                debug.desiredProjectionTenth / 10
            ))
        end
    end
    return refreshed
end

--- 设置一个来源的属性贡献；未定义键不会进入统一属性快照。
---@param hero unit
---@param source_id string
---@param values table<string, number>
---@return boolean refreshed
function module.set_source(hero, source_id, values)
    if hero == nil or type(source_id) ~= "string" or source_id == "" then return false end
    sources_by_hero[hero] = sources_by_hero[hero] or {}
    local normalized = normalize_values(values)
    sources_by_hero[hero][source_id] = normalized
    local refreshed = module.refresh(hero)
    if refreshed then
        notify_source_changed(hero, source_id, normalized, false)
    end
    return refreshed
end

---@param hero unit
---@param source_id string
---@return boolean refreshed
function module.clear_source(hero, source_id)
    local had_source = sources_by_hero[hero] ~= nil and sources_by_hero[hero][source_id] ~= nil
    if sources_by_hero[hero] ~= nil then sources_by_hero[hero][source_id] = nil end
    local refreshed = module.refresh(hero)
    if refreshed and had_source then
        notify_source_changed(hero, source_id, nil, true)
    end
    return refreshed
end

--- 刷新所有来源并投影到 Warcraft 原生属性。
---@param hero unit
---@return boolean refreshed
function module.refresh(hero)
    if hero == nil or equipment_config.statAbilities == nil then return false end
    local state = applied_states[hero]
    if state == nil then
        state = make_state(hero, nil, nil)
        if state == nil then return false end
        applied_states[hero] = state
    end
    local total = sum_sources(hero)
    local snapshot = empty_values()
    snapshot.strength = apply_primary_attribute(hero, state, "strength", jass.GetHeroStr, jass.SetHeroStr, total.strength)
    snapshot.agility = apply_primary_attribute(hero, state, "agility", jass.GetHeroAgi, jass.SetHeroAgi, total.agility)
    snapshot.intelligence = apply_primary_attribute(hero, state, "intelligence", jass.GetHeroInt, jass.SetHeroInt, total.intelligence)

    local abilities = equipment_config.statAbilities
    local primary_value = snapshot[state.primaryAttribute] or 0
    local attribute_attack = primary_value * 2
        + snapshot.strength + snapshot.agility + snapshot.intelligence - primary_value
    -- 主属性原生攻击奖励已归零，因此全部项目属性攻击力只投影一次。
    local desired_hidden_attack = attribute_attack + total.attack
    if state.applied.attack ~= desired_hidden_attack then
        if not apply_signed_projection(hero, abilities.attack, abilities.attackDecrease, desired_hidden_attack, state.applied.attack) then return false end
        state.applied.attack = desired_hidden_attack
    end
    local health_amplification = math.floor(snapshot.strength / 10) + total.health_amplification_percent
    local health_base = math.max(0, math.floor(state.baseMaxLife or 0))
    local desired_health = math.floor((health_base + snapshot.strength * 25 + total.health)
        * (100 + health_amplification) / 100)
    -- Warcraft III 1.27 不支持可靠地通过 UNIT_STATE_MAX_LIFE 直接设置最大生命。
    -- 使用临时 AIlf 七位数字状态写入，最大可增加/减少 9,999,999 点生命。
    local desired_hidden_health = desired_health - health_base
    if state.applied.health ~= desired_hidden_health then
        if not apply_life_projection(hero, abilities, desired_hidden_health, state.applied.health, health_base) then
            print(string.format(
                "生命投影失败：目标=%d，旧投影=%d，当前最大生命=%d",
                desired_health,
                state.applied.health,
                math.floor(tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE)) or 0)
            ))
            return false
        end
        state.applied.health = desired_hidden_health
    end
    -- 敏捷原生护甲和项目敏捷护甲均不存在；只投影显式固定护甲来源。
    local desired_armor_tenth = math.floor(state.baseArmorTenth or 0) + total.armor * 10
    local desired_hidden_armor = total.armor * 10
    if state.applied.armor ~= desired_hidden_armor then
        if not apply_signed_projection(hero, abilities.armor, abilities.armorDecrease, desired_hidden_armor, state.applied.armor) then return false end
        state.applied.armor = desired_hidden_armor
    end
    local attack_speed_percent, desired_attack_speed = calculate_attack_speed_projection(state, total)
    if not apply_attack_speed_projection(hero, state, abilities, desired_attack_speed) then return false end
    if state.applied.moveSpeed ~= total.moveSpeed and state.baseMoveSpeed ~= nil
        and type(jass.SetUnitMoveSpeed) == "function" then
        jass.SetUnitMoveSpeed(hero, math.max(1, state.baseMoveSpeed + total.moveSpeed))
        state.applied.moveSpeed = total.moveSpeed
    elseif state.baseMoveSpeed == nil then
        state.applied.moveSpeed = total.moveSpeed
    end

    snapshot.attack = (state.baseAttack or 0) + attribute_attack + total.attack
    snapshot.health = desired_health
    snapshot.armor = math.floor(desired_armor_tenth / 10)
    snapshot.moveSpeed = (state.baseMoveSpeed or 0) + total.moveSpeed
    snapshot.attack_speed_percent = attack_speed_percent
    snapshot.basic_attack_bonus_percent = math.floor(snapshot.agility / 10)
        + total.basic_attack_bonus_percent
    snapshot.health_amplification_percent = health_amplification
    state.snapshot = snapshot
    notify_listeners(hero, copy_values(snapshot))
    return true
end

--- 返回当前十项最终属性快照。攻击、生命、护甲和攻速已包含三维派生、固定加成及百分比结算。
---@param hero unit
---@return table<string, integer> snapshot
function module.get_snapshot(hero)
    local state = applied_states[hero]
    return state and copy_values(state.snapshot) or empty_values()
end

--- 返回攻速投影的配置、期望等级和实际隐藏技能等级，仅供调试读取。
---@param hero unit
---@return table|nil debug
function module.get_attack_speed_debug(hero)
    local state = applied_states[hero]
    if state == nil then return nil end
    local total = sum_sources(hero)
    local snapshot = state.snapshot or empty_values()
    local agility = math.floor(tonumber(snapshot.agility) or 0)
    local target_percent, desired_projection_tenth = calculate_attack_speed_projection(state, total)
    local unit = unit_config[state.heroRawcode or ""] or {}
    local positive_value = math.max(0, desired_projection_tenth)
    local negative_value = math.max(0, -desired_projection_tenth)
    local abilities = equipment_config.statAbilities or {}
    return {
        heroRawcode = state.heroRawcode,
        baseAttackCooldown = math.max(0, tonumber(unit.cool1) or 0),
        configuredPercent = math.max(1, math.floor(tonumber(state.baseAttackSpeedPercent) or 100)),
        sourceBonusPercent = math.floor(tonumber(total.attack_speed_percent) or 0),
        targetPercent = target_percent,
        expectedAttackIntervalSeconds = target_percent > 0
            and math.floor((math.max(0, tonumber(unit.cool1) or 0) * 100 / target_percent) * 1000 + 0.5) / 1000 or 0,
        agility = agility,
        nativeAgilityBonusTenth = 0,
        desiredProjectionTenth = desired_projection_tenth,
        positive = {
            rawcodes = abilities.attackSpeedPositive or {},
            expectedLevels = get_digit_levels(positive_value, abilities.attackSpeedPositive),
            actualLevels = get_ability_levels(hero, abilities.attackSpeedPositive),
        },
        negative = {
            rawcodes = abilities.attackSpeedNegative or {},
            expectedLevels = get_digit_levels(negative_value, abilities.attackSpeedNegative),
            actualLevels = get_ability_levels(hero, abilities.attackSpeedNegative),
        },
    }
end

--- 返回最大生命公式、临时 AIlf 状态写入和原生实际生命，仅供调试读取。
---@param hero unit
---@return table|nil debug
function module.get_health_debug(hero)
    local state = applied_states[hero]
    if state == nil then return nil end
    local total = sum_sources(hero)
    local snapshot = state.snapshot or empty_values()
    local strength = math.floor(tonumber(snapshot.strength) or 0)
    local health_base = math.max(0, math.floor(tonumber(state.baseMaxLife) or 0))
    local health_amplification = math.floor(strength / 10) + total.health_amplification_percent
    local desired_health = math.floor((health_base + strength * 25 + total.health)
        * (100 + health_amplification) / 100)
    local desired_projection = desired_health - health_base
    local abilities = equipment_config.statAbilities or {}
    local current_life = type(jass.GetUnitState) == "function" and jass.UNIT_STATE_LIFE ~= nil
        and math.floor(tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_LIFE)) or 0) or 0
    local maximum_life = type(jass.GetUnitState) == "function" and jass.UNIT_STATE_MAX_LIFE ~= nil
        and math.floor(tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE)) or 0) or 0
    return {
        baseLife = health_base,
        strength = strength,
        fixedHealth = total.health,
        amplificationPercent = health_amplification,
        desiredLife = desired_health,
        desiredProjection = desired_projection,
        appliedProjection = math.floor(tonumber(state.applied.health) or 0),
        pendingDelta = desired_projection - math.floor(tonumber(state.applied.health) or 0),
        projectionMaximum = math.min(
            get_max_projected_value(abilities.healthIncrease) or 0,
            get_max_projected_value(abilities.healthDecrease) or 0
        ),
        currentLife = current_life,
        maximumLife = maximum_life,
        positive = {
            rawcodes = abilities.healthIncrease or {},
            expectedLevels = get_absent_ability_levels(abilities.healthIncrease),
            actualLevels = get_ability_levels(hero, abilities.healthIncrease),
        },
        negative = {
            rawcodes = abilities.healthDecrease or {},
            expectedLevels = get_absent_ability_levels(abilities.healthDecrease),
            actualLevels = get_ability_levels(hero, abilities.healthDecrease),
        },
    }
end

---返回英雄当前主属性 ID；装备自动技可用 primary 取得对应三维属性。
---@param hero unit
---@return string attribute_id
function module.get_primary_attribute(hero)
    local state = applied_states[hero]
    return state and state.primaryAttribute or "strength"
end

---返回当前主属性（或指定三维属性）的最终值。
---@param hero unit
---@param attribute_id string|nil
---@return integer value
function module.get_primary_value(hero, attribute_id)
    local snapshot = module.get_snapshot(hero)
    local resolved = attribute_id or module.get_primary_attribute(hero)
    return math.floor(tonumber(snapshot[resolved]) or 0)
end

---@param hero unit
---@return integer percent 普攻最终伤害百分比加成
function module.get_basic_attack_bonus_percent(hero)
    local snapshot = module.get_snapshot(hero)
    return math.max(0, math.floor(tonumber(snapshot.basic_attack_bonus_percent) or 0))
end

---@param hero unit
---@return integer percent 技能伤害百分比加成
function module.get_skill_damage_bonus_percent(hero)
    local snapshot = module.get_snapshot(hero)
    local intelligence = math.max(0, math.floor(tonumber(snapshot.intelligence) or 0))
    return math.max(0, math.floor(intelligence / 10))
end

---@param hero unit
---@return integer percent 生命增幅百分比
function module.get_health_amplification_percent(hero)
    local snapshot = module.get_snapshot(hero)
    return math.max(0, math.floor(tonumber(snapshot.health_amplification_percent) or 0))
end

--- 返回指定来源当前贡献的统一属性，仅供本地展示和调试读取。
---@param hero unit
---@param source_id string
---@return table<string, integer> values
function module.get_source(hero, source_id)
    local values = sources_by_hero[hero] and sources_by_hero[hero][source_id]
    return copy_values(values)
end

--- 保持与旧装备接口的兼容，同时返回当前最终战斗属性。
---@param hero unit
---@return table<string, integer> total
function module.get_total(hero)
    local snapshot = module.get_snapshot(hero)
    return {
        attack = snapshot.attack,
        health = snapshot.health,
        armor = snapshot.armor,
        moveSpeed = snapshot.moveSpeed,
        attackSpeedPercent = snapshot.attack_speed_percent,
    }
end

--- 订阅属性刷新。监听器只应用于本地显示，不得修改同步游戏状态。
---@param listener fun(hero:unit, snapshot:table<string, integer>)
---@return boolean added
function module.subscribe(listener)
    if type(listener) ~= "function" then return false end
    table.insert(listeners, listener)
    return true
end

--- 返回 Excel 定义的首版属性元数据。
function module.get_definitions()
    return attribute_config.attributes
end

return module
