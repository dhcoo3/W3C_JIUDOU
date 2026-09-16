--- 通用肉鸽属性应用。
local jass = J.Common
local config = JiuDou.module("gameplay.rogue.config")
local hero_stats = JiuDou.module("gameplay.hero.stats")

local module = {}

local function common(state, key)
    return math.floor(tonumber(state.common[key]) or 0)
end

local function growth_bonus(state, key)
    local hero_level = type(jass.GetHeroLevel) == "function" and jass.GetHeroLevel(state.hero) or 1
    return math.floor(math.max(0, hero_level - 1) * common(state, key) / 10)
end

--- 根据已拥有强化重建通用与英雄技能修正表。
--- 只更新 Lua 运行态；原生属性投影由 refresh 统一处理。
function module.rebuild(state)
    if state == nil then return false end
    state.common = {}
    state.skills = {}
    for effect_id, level in pairs(state.owned or {}) do
        local effect = config.get_effect(effect_id)
        if effect ~= nil and level > 0 then
            local value = effect.values[level] or 0
            if effect.type == "Common" then
                state.common[effect.modifierKey] = (state.common[effect.modifierKey] or 0) + value
            elseif effect.type == "Skill" then
                state.skills[effect.skill] = state.skills[effect.skill] or {}
                local skill = state.skills[effect.skill]
                skill[effect.modifierKey] = (skill[effect.modifierKey] or 0) + value
            end
        end
    end
    return true
end

function module.refresh(state)
    if state == nil or state.hero == nil then return false end
    hero_stats.set_source(state.hero, "rogue", {
        attack = common(state, "attack_add"),
        health = common(state, "health_add"),
        armor = common(state, "armor_add"),
        moveSpeed = common(state, "move_speed_add"),
        basic_attack_bonus_percent = common(state, "basic_attack_bonus_percent"),
        health_amplification_percent = common(state, "health_amplification_percent"),
        strength = growth_bonus(state, "strength_growth_tenth"),
        agility = growth_bonus(state, "agility_growth_tenth"),
        intelligence = growth_bonus(state, "int_growth_tenth"),
    })
    return true
end

JiuDou.publish("gameplay.rogue.attribute", module)
return module
