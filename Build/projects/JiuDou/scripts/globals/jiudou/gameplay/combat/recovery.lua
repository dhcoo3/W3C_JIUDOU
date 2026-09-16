--- 统一恢复公式。
--- 固定恢复按持有者主属性计算；heal_percent 是最终最大生命百分比恢复，单独结算一次。
local jass = J.Common
local hero_stats = JiuDou.module("gameplay.hero.stats")

local module = {}

local function clamp_percent(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function current_life(unit_handle)
    if type(jass.GetWidgetLife) == "function" then
        return math.max(0, tonumber(jass.GetWidgetLife(unit_handle)) or 0)
    end
    if type(jass.GetUnitState) == "function" and jass.UNIT_STATE_LIFE ~= nil then
        return math.max(0, tonumber(jass.GetUnitState(unit_handle, jass.UNIT_STATE_LIFE)) or 0)
    end
    return nil
end

local function write_life(unit_handle, target)
    if type(jass.SetWidgetLife) == "function" then
        jass.SetWidgetLife(unit_handle, target)
        return true
    end
    if type(jass.SetUnitState) == "function" and jass.UNIT_STATE_LIFE ~= nil then
        jass.SetUnitState(unit_handle, jass.UNIT_STATE_LIFE, target)
        return true
    end
    return false
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
    if hero == nil or type(jass.GetUnitState) ~= "function" or jass.UNIT_STATE_MAX_LIFE == nil then
        return false
    end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return false end
    local current = current_life(hero)
    local maximum = math.max(0, tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE)) or 0)
    if current == nil or maximum <= current then return false end
    local target = math.min(maximum, current + amount)
    if target <= current or not write_life(hero, target) then return false end
    local actual = current_life(hero)
    return actual ~= nil and actual > current + 0.001
end

---@param hero unit
---@param percent integer
---@return boolean applied
function module.apply_percent(hero, percent)
    if hero == nil or type(jass.GetUnitState) ~= "function" or jass.UNIT_STATE_MAX_LIFE == nil then
        return false
    end
    local maximum = math.max(0, tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_MAX_LIFE)) or 0)
    local current = current_life(hero)
    if current == nil or maximum <= current then return false end
    local amount = math.floor(maximum * clamp_percent(percent) / 100)
    local target = math.min(maximum, current + amount)
    if target <= current or not write_life(hero, target) then return false end
    local actual = current_life(hero)
    return actual ~= nil and actual > current + 0.001
end

JiuDou.publish("gameplay.combat.recovery", module)
return module
