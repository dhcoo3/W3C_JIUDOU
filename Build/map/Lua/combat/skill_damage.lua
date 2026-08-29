--- 技能伤害公式服务。
--- 所有倍率使用十倍定点整数：6 表示 0.6×，10 表示 1×；不使用浮点倍率。
--- 技能最终伤害统一叠加 floor(最终智力 / 10) 的智力技能伤害加成。
local hero_stats = require "hero.stats"

local module = {}

local ATTRIBUTE_LABELS = {
    strength = "力量",
    agility = "敏捷",
    intelligence = "智力",
    primary = "主属性",
}

local function normalize_multiplier(multiplier_tenth)
    return math.max(0, math.floor(tonumber(multiplier_tenth) or 0))
end

--- 取得公式使用的属性最终值。primary 会解析为英雄当前主属性。
---@param hero unit
---@param attribute_id string
---@return integer value
function module.get_attribute_value(hero, attribute_id)
    attribute_id = attribute_id or "primary"
    local resolved = attribute_id == "primary" and hero_stats.get_primary_attribute(hero) or attribute_id
    return math.max(0, hero_stats.get_primary_value(hero, resolved))
end

--- 取得技能最终百分比加成。传入的值通常来自 skill_damage_percent，单位为百分比；
--- 装备自动技能的装备等级倍率也应先换算为同一百分比后传入。
---@param hero unit
---@param explicit_bonus integer|nil 配置或其他系统提供的技能伤害百分比
---@return integer percent
function module.get_percent_bonus(hero, explicit_bonus)
    return math.floor(tonumber(explicit_bonus) or 0)
        + hero_stats.get_skill_damage_bonus_percent(hero)
end

---计算未附加百分比增幅的基础伤害：floor(主属性 × 十倍定点倍率 / 10)。
---@param hero unit
---@param attribute_id string
---@param multiplier_tenth integer
---@return integer damage
function module.calculate_base(hero, attribute_id, multiplier_tenth)
    return math.floor(module.get_attribute_value(hero, attribute_id) * normalize_multiplier(multiplier_tenth) / 10)
end

---在基础伤害之后结算百分比增幅。
---@param base_damage integer
---@param percent_bonus integer|nil
---@return integer damage
function module.apply_percent_bonus(base_damage, percent_bonus)
    local base = math.max(0, math.floor(tonumber(base_damage) or 0))
    local bonus = math.floor(tonumber(percent_bonus) or 0)
    return math.max(0, math.floor(base * math.max(0, 100 + bonus) / 100))
end

---@param hero unit
---@param attribute_id string
---@param multiplier_tenth integer
---@param percent_bonus integer|nil
---@return integer damage
function module.calculate(hero, attribute_id, multiplier_tenth, percent_bonus)
    return module.apply_percent_bonus(
        module.calculate_base(hero, attribute_id or "primary", multiplier_tenth),
        module.get_percent_bonus(hero, percent_bonus)
    )
end

---@param multiplier_tenth integer
---@return string text
function module.format_multiplier(multiplier_tenth)
    local value = normalize_multiplier(multiplier_tenth)
    local whole = math.floor(value / 10)
    local fraction = value % 10
    if fraction == 0 then return tostring(whole) end
    return tostring(whole) .. "." .. tostring(fraction)
end

---@param attribute_id string
---@return string label
function module.attribute_label(attribute_id)
    return ATTRIBUTE_LABELS[attribute_id] or tostring(attribute_id or "主属性")
end

return module
