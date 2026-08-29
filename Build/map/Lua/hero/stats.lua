--- 英雄统一属性聚合服务。
--- 装备、肉鸽等系统提交来源数值；本模块统一投影到 Warcraft 原生属性，并向本地 UI 发布快照。
local jass = require "jass.common"
local equipment_config = require "config.equipment"
local attribute_config = require "config.attributes"
local unit_config = require "config.units"

local module = {}

local ATTRIBUTE_IDS = {
    "strength",
    "agility",
    "intelligence",
    "attack",
    "health",
    "armor",
    "moveSpeed",
    "basic_attack_bonus_percent",
    "health_amplification_percent",
}

local sources_by_hero = {}
local applied_states = {}
local listeners = {}
local preload_timer = nil
local preload_dummy = nil
local preload_index = 1
local preload_completed = false
local preload_total_steps = 0
local preload_elapsed_seconds = 0
local preload_callbacks = {}

local PRELOAD_INTERVAL_SECONDS = 0.04
local PRELOAD_OPERATIONS_PER_TICK = 4
local PRELOAD_DUMMY_RAWCODE = "hpea"
local MAX_PROJECTED_VALUE = 9999
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

local function normalize_projected_value(value)
    return math.max(0, math.min(MAX_PROJECTED_VALUE, math.floor(tonumber(value) or 0)))
end

local function apply_digit_stat(hero, rawcodes, value, previous_value)
    value = normalize_projected_value(value)
    previous_value = normalize_projected_value(previous_value)
    if type(rawcodes) ~= "table" or #rawcodes ~= 4 then return false end
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

local function get_life_ratio(hero)
    if type(jass.GetUnitState) ~= "function" or jass.UNIT_STATE_MAX_LIFE == nil
        or jass.UNIT_STATE_LIFE == nil then return nil end
    local maximum = jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE)
    local current = jass.GetUnitState(hero, jass.UNIT_STATE_LIFE)
    if maximum == nil or maximum <= 0 or current == nil or current <= 0.405 then return nil end
    return math.max(0, math.min(1, current / maximum))
end

local function apply_life_projection(hero, abilities, value, previous_value)
    value = math.max(-MAX_PROJECTED_VALUE, math.min(MAX_PROJECTED_VALUE, math.floor(tonumber(value) or 0)))
    previous_value = math.max(-MAX_PROJECTED_VALUE, math.min(MAX_PROJECTED_VALUE, math.floor(tonumber(previous_value) or 0)))
    local ratio = get_life_ratio(hero)
    local previous_positive = math.max(0, previous_value)
    local previous_negative = math.max(0, -previous_value)
    local positive = math.max(0, value)
    local negative = math.max(0, -value)
    if value >= previous_value then
        if not apply_digit_stat(hero, abilities.healthDecrease, negative, previous_negative) then return false end
        if not apply_digit_stat(hero, abilities.healthIncrease, positive, previous_positive) then return false end
    else
        if not apply_digit_stat(hero, abilities.healthIncrease, positive, previous_positive) then return false end
        if not apply_digit_stat(hero, abilities.healthDecrease, negative, previous_negative) then return false end
    end
    if ratio ~= nil and type(jass.SetUnitState) == "function" then
        local maximum = jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE)
        jass.SetUnitState(hero, jass.UNIT_STATE_LIFE, maximum * ratio)
    end
    return true
end

local function apply_signed_projection(hero, positive_abilities, negative_abilities, value, previous_value)
    value = math.max(-MAX_PROJECTED_VALUE, math.min(MAX_PROJECTED_VALUE, math.floor(tonumber(value) or 0)))
    previous_value = math.max(-MAX_PROJECTED_VALUE, math.min(MAX_PROJECTED_VALUE, math.floor(tonumber(previous_value) or 0)))
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

local function ensure_stat_abilities(hero)
    local abilities = equipment_config.statAbilities
    for _, group in ipairs({
        abilities.healthDecrease,
        abilities.healthIncrease,
        abilities.attack,
        abilities.armor,
        abilities.armorDecrease,
        abilities.manaPositive,
        abilities.manaNegative,
        abilities.manaRegenPositive,
        abilities.manaRegenNegative,
        abilities.lifeRegenPositive,
        abilities.lifeRegenNegative,
        abilities.attackSpeedPositive,
        abilities.attackSpeedNegative,
    }) do
        if type(group) ~= "table" or #group ~= 4 then return false end
        for _, rawcode in ipairs(group) do
            if not ensure_ability(hero, rawcode) then return false end
        end
    end
    return true
end

local function make_state(hero, primary_attribute, hero_rawcode)
    if not ensure_stat_abilities(hero) then return nil end
    local initial_strength = type(jass.GetHeroStr) == "function" and math.floor(jass.GetHeroStr(hero, true) or 0) or 0
    local initial_intelligence = type(jass.GetHeroInt) == "function" and math.floor(jass.GetHeroInt(hero, true) or 0) or 0
    local initial_max_life = type(jass.GetUnitState) == "function" and jass.UNIT_STATE_MAX_LIFE ~= nil
        and (tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE)) or 0) or 0
    local initial_max_mana = type(jass.GetUnitState) == "function" and jass.UNIT_STATE_MAX_MANA ~= nil
        and (tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_MAX_MANA)) or 0) or 0
    local unit = unit_config[hero_rawcode or ""] or {}
    return {
        appliedSources = empty_values(),
        applied = {
            attack = 0,
            health = 0,
            armor = 0,
            mana = 0,
            manaRegen = 0,
            lifeRegen = 0,
            attackSpeed = 0,
        },
        snapshot = empty_values(),
        primaryAttribute = PRIMARY_ATTRIBUTE_BY_CODE[primary_attribute] or "strength",
        heroRawcode = hero_rawcode,
        baseMaxLifeWithoutStrength = initial_max_life - initial_strength * 19,
        baseMaxManaWithoutIntelligence = initial_max_mana - initial_intelligence * 15,
        baseArmorTenth = math.floor(tonumber(unit.def) or 0) * 10,
        baseAttack = math.floor(tonumber(unit.dmgplus1) or 0),
        baseMoveSpeed = type(jass.GetUnitMoveSpeed) == "function" and jass.GetUnitMoveSpeed(hero) or nil,
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
    for _, listener in ipairs(listeners) do
        pcall(listener, hero, snapshot)
    end
end

local function finish_preload()
    if preload_timer ~= nil and type(jass.TimerGetElapsed) == "function" then
        preload_elapsed_seconds = math.max(0, jass.TimerGetElapsed(preload_timer) or 0)
    end
    if preload_timer ~= nil then
        jass.PauseTimer(preload_timer)
        jass.DestroyTimer(preload_timer)
        preload_timer = nil
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
        abilities.healthDecrease,
        abilities.healthIncrease,
        abilities.attack,
        abilities.armor,
        abilities.armorDecrease,
        abilities.manaPositive,
        abilities.manaNegative,
        abilities.manaRegenPositive,
        abilities.manaRegenNegative,
        abilities.lifeRegenPositive,
        abilities.lifeRegenNegative,
        abilities.attackSpeedPositive,
        abilities.attackSpeedNegative,
    }) do
        if type(group) ~= "table" or #group ~= 4 then return nil end
        for _, rawcode in ipairs(group) do table.insert(result, rawcode) end
    end
    return result
end

--- 在选将界面出现前预热 16 个十级隐藏技能的全部等级组合。
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
    if rawcodes == nil then return false end
    preload_index = 1
    preload_total_steps = #rawcodes * 10
    preload_elapsed_seconds = 0
    preload_timer = jass.CreateTimer()
    jass.TimerStart(preload_timer, PRELOAD_INTERVAL_SECONDS, true, function()
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
    end)
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
    if applied_states[hero] ~= nil then
        applied_states[hero].primaryAttribute = PRIMARY_ATTRIBUTE_BY_CODE[primary_attribute]
            or applied_states[hero].primaryAttribute
        applied_states[hero].heroRawcode = hero_rawcode or applied_states[hero].heroRawcode
    else
        applied_states[hero] = make_state(hero, primary_attribute, hero_rawcode)
        if applied_states[hero] == nil then return false end
    end
    return module.refresh(hero)
end

--- 设置一个来源的属性贡献；未定义键不会进入统一属性快照。
---@param hero unit
---@param source_id string
---@param values table<string, number>
---@return boolean refreshed
function module.set_source(hero, source_id, values)
    if hero == nil or type(source_id) ~= "string" or source_id == "" then return false end
    sources_by_hero[hero] = sources_by_hero[hero] or {}
    sources_by_hero[hero][source_id] = normalize_values(values)
    return module.refresh(hero)
end

---@param hero unit
---@param source_id string
---@return boolean refreshed
function module.clear_source(hero, source_id)
    if sources_by_hero[hero] ~= nil then sources_by_hero[hero][source_id] = nil end
    return module.refresh(hero)
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
    local desired_hidden_attack = attribute_attack + total.attack - primary_value
    if state.applied.attack ~= desired_hidden_attack then
        if not apply_signed_projection(hero, abilities.attack, abilities.attackDecrease, desired_hidden_attack, state.applied.attack) then return false end
        state.applied.attack = desired_hidden_attack
    end
    local health_amplification = math.floor(snapshot.strength / 10) + total.health_amplification_percent
    local health_base = math.max(0, math.floor(state.baseMaxLifeWithoutStrength or 0))
    local desired_health = math.floor((health_base + snapshot.strength * 25 + total.health)
        * (100 + health_amplification) / 100)
    local native_health = health_base + snapshot.strength * 19
    local desired_hidden_health = desired_health - native_health
    if state.applied.health ~= desired_hidden_health then
        if not apply_life_projection(hero, abilities, desired_hidden_health, state.applied.health) then return false end
        state.applied.health = desired_hidden_health
    end
    local desired_armor_tenth = math.floor(state.baseArmorTenth or 0)
        + total.armor * 10 + math.floor(snapshot.agility / 10) * 10
    local native_armor_tenth = math.floor(state.baseArmorTenth or 0) + snapshot.agility * 3
    local desired_hidden_armor = desired_armor_tenth - native_armor_tenth
    if state.applied.armor ~= desired_hidden_armor then
        if not apply_signed_projection(hero, abilities.armor, abilities.armorDecrease, desired_hidden_armor, state.applied.armor) then return false end
        state.applied.armor = desired_hidden_armor
    end
    local desired_mana = -snapshot.intelligence * 15
    if state.applied.mana ~= desired_mana and abilities.manaPositive ~= nil then
        if not apply_signed_projection(hero, abilities.manaPositive, abilities.manaNegative, desired_mana, state.applied.mana) then return false end
        state.applied.mana = desired_mana
    end
    local desired_mana_regen = -snapshot.intelligence * 5
    if state.applied.manaRegen ~= desired_mana_regen and abilities.manaRegenPositive ~= nil then
        if not apply_signed_projection(hero, abilities.manaRegenPositive, abilities.manaRegenNegative, desired_mana_regen, state.applied.manaRegen) then return false end
        state.applied.manaRegen = desired_mana_regen
    end
    local desired_life_regen = -snapshot.strength * 5
    if state.applied.lifeRegen ~= desired_life_regen and abilities.lifeRegenPositive ~= nil then
        if not apply_signed_projection(hero, abilities.lifeRegenPositive, abilities.lifeRegenNegative, desired_life_regen, state.applied.lifeRegen) then return false end
        state.applied.lifeRegen = desired_life_regen
    end
    local desired_attack_speed = -snapshot.agility * 25
    if state.applied.attackSpeed ~= desired_attack_speed and abilities.attackSpeedPositive ~= nil then
        if not apply_signed_projection(hero, abilities.attackSpeedPositive, abilities.attackSpeedNegative, desired_attack_speed, state.applied.attackSpeed) then return false end
        state.applied.attackSpeed = desired_attack_speed
    end
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
    snapshot.basic_attack_bonus_percent = math.floor(snapshot.agility / 10)
        + total.basic_attack_bonus_percent
    snapshot.health_amplification_percent = health_amplification
    state.snapshot = snapshot
    notify_listeners(hero, copy_values(snapshot))
    return true
end

--- 返回当前九项最终属性快照。攻击、生命、护甲已包含三维派生、固定加成及百分比结算。
---@param hero unit
---@return table<string, integer> snapshot
function module.get_snapshot(hero)
    local state = applied_states[hero]
    return state and copy_values(state.snapshot) or empty_values()
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
