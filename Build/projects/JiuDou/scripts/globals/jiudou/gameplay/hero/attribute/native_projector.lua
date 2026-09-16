--- 英雄属性到 Warcraft 原生数值的投影器。
--- 隐藏技能位、生命临时技能和攻速投影都集中在此，业务层不直接处理这些兼容细节。
local jass = require "jass.common"

local module = {}
local MAX_DIGIT_COUNT = 7

---@param rawcode string
---@return integer|nil ability_id
function module.rawcode_to_integer(rawcode)
    if type(rawcode) ~= "string" or #rawcode ~= 4 then return nil end
    local a, b, c, d = string.byte(rawcode, 1, 4)
    if a == nil or b == nil or c == nil or d == nil then return nil end
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

---@param rawcodes string[]|nil
---@return integer|nil maximum
function module.get_max_projected_value(rawcodes)
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

local function ensure_ability(unit_handle, rawcode)
    local ability_id = module.rawcode_to_integer(rawcode)
    if ability_id == nil or type(jass.UnitAddAbility) ~= "function" then return false end
    local current = type(jass.GetUnitAbilityLevel) == "function"
        and (jass.GetUnitAbilityLevel(unit_handle, ability_id) or 0) or 0
    return current > 0 or jass.UnitAddAbility(unit_handle, ability_id)
end

local function set_ability_level(unit_handle, rawcode, level)
    local ability_id = module.rawcode_to_integer(rawcode)
    if ability_id == nil or type(jass.SetUnitAbilityLevel) ~= "function"
        or type(jass.UnitAddAbility) ~= "function" then return false end
    level = math.max(1, math.min(10, math.floor(tonumber(level) or 1)))
    local current = type(jass.GetUnitAbilityLevel) == "function"
        and (jass.GetUnitAbilityLevel(unit_handle, ability_id) or 0) or 0
    if current <= 0 and not jass.UnitAddAbility(unit_handle, ability_id) then return false end
    if current ~= level then jass.SetUnitAbilityLevel(unit_handle, ability_id, level) end
    return true
end

local function apply_digit_stat(hero, rawcodes, value, previous_value)
    local maximum = module.get_max_projected_value(rawcodes)
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

---@param value number
---@param rawcodes string[]|nil
---@return integer[] levels
function module.get_digit_levels(value, rawcodes)
    local maximum = module.get_max_projected_value(rawcodes)
    if maximum == nil then return {} end
    value = normalize_projected_value(value, maximum)
    local levels = {}
    for index = 1, #rawcodes do
        local divisor = 10 ^ (index - 1)
        levels[index] = math.floor(value / divisor) % 10 + 1
    end
    return levels
end

---@param hero unit
---@param rawcodes string[]|nil
---@return integer[] levels
function module.get_ability_levels(hero, rawcodes)
    local levels = {}
    for index, rawcode in ipairs(rawcodes or {}) do
        local ability_id = module.rawcode_to_integer(rawcode)
        levels[index] = ability_id ~= nil and type(jass.GetUnitAbilityLevel) == "function"
            and math.floor(jass.GetUnitAbilityLevel(hero, ability_id) or 0) or 0
    end
    return levels
end

---@param rawcodes string[]|nil
---@return integer[] levels
function module.get_absent_ability_levels(rawcodes)
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

local function apply_temporary_life_digit(hero, rawcode, level)
    local ability_id = module.rawcode_to_integer(rawcode)
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
    local maximum = module.get_max_projected_value(rawcodes)
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

--- 通过临时 AIlf 技能投影最大生命，保持当前生命百分比。
function module.apply_life_projection(hero, abilities, value, previous_value, base_maximum)
    local maximum = math.min(
        module.get_max_projected_value(abilities.healthDecrease) or 0,
        module.get_max_projected_value(abilities.healthIncrease) or 0
    )
    if maximum <= 0 then return false end
    value = normalize_signed_projected_value(value, maximum)
    previous_value = normalize_signed_projected_value(previous_value, maximum)
    local ratio = get_state_ratio(hero, jass.UNIT_STATE_MAX_LIFE, jass.UNIT_STATE_LIFE)
    local delta = value - previous_value
    if delta > 0 then
        if not apply_temporary_life_digits(hero, abilities.healthIncrease, delta) then return false end
    elseif delta < 0 then
        if not apply_temporary_life_digits(hero, abilities.healthDecrease, -delta) then return false end
    end
    if ratio ~= nil and type(jass.SetUnitState) == "function" then
        local maximum_life = jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE)
        jass.SetUnitState(hero, jass.UNIT_STATE_LIFE, maximum_life * ratio)
    end
    local actual_maximum = type(jass.GetUnitState) == "function" and jass.UNIT_STATE_MAX_LIFE ~= nil
        and math.floor(tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE)) or 0) or 0
    local expected_maximum = math.floor(tonumber(base_maximum) or 0) + value
    return actual_maximum == expected_maximum
end

--- 通过正负隐藏技能位投影带符号属性值。
function module.apply_signed_projection(hero, positive_abilities, negative_abilities, value, previous_value)
    local maximum = math.min(
        module.get_max_projected_value(positive_abilities) or 0,
        module.get_max_projected_value(negative_abilities) or 0
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

---@param hero unit
---@param abilities table
---@return boolean ready
function module.ensure_stat_abilities(hero, abilities)
    for _, group in ipairs({
        abilities.attack,
        abilities.attackDecrease,
        abilities.armor,
        abilities.armorDecrease,
        abilities.attackSpeedPositive,
        abilities.attackSpeedNegative,
    }) do
        if module.get_max_projected_value(group) == nil then return false end
        for _, rawcode in ipairs(group) do
            if not ensure_ability(hero, rawcode) then return false end
        end
    end
    return true
end

return module
