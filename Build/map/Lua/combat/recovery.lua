--- 统一恢复公式。
--- 固定恢复按持有者主属性计算；heal_percent 是最终最大生命百分比恢复，单独结算一次。
local jass = require "jass.common"
local hero_stats = require "hero.stats"

local module = {}

local function clamp_percent(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

---@param hero unit
---@param multiplier_tenth integer
---@param recovery_bonus integer|nil 恢复百分比加成
---@return integer amount
function module.calculate_fixed(hero, multiplier_tenth, recovery_bonus)
    local primary = hero_stats.get_primary_value(hero, hero_stats.get_primary_attribute(hero))
    local base = math.floor(math.max(0, primary) * math.max(0, math.floor(tonumber(multiplier_tenth) or 0)) / 10)
    return math.floor(base * (100 + clamp_percent(recovery_bonus)) / 100)
end

---@param hero unit
---@param amount integer
---@return boolean applied
function module.apply_fixed(hero, amount)
    if hero == nil or type(jass.GetUnitState) ~= "function" or type(jass.SetUnitState) ~= "function"
        or jass.UNIT_STATE_LIFE == nil or jass.UNIT_STATE_MAX_LIFE == nil then
        return false
    end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return false end
    local current = math.max(0, tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_LIFE)) or 0)
    local maximum = math.max(0, tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE)) or 0)
    if maximum <= 0 then return false end
    jass.SetUnitState(hero, jass.UNIT_STATE_LIFE, math.min(maximum, current + amount))
    return true
end

---@param hero unit
---@param percent integer
---@return boolean applied
function module.apply_percent(hero, percent)
    if hero == nil or type(jass.GetUnitState) ~= "function" or type(jass.SetUnitState) ~= "function"
        or jass.UNIT_STATE_LIFE == nil or jass.UNIT_STATE_MAX_LIFE == nil then
        return false
    end
    local maximum = math.max(0, tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE)) or 0)
    local current = math.max(0, tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_LIFE)) or 0)
    if maximum <= 0 then return false end
    local amount = math.floor(maximum * clamp_percent(percent) / 100)
    jass.SetUnitState(hero, jass.UNIT_STATE_LIFE, math.min(maximum, current + amount))
    return true
end

return module
