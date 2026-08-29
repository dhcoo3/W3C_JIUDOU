--- 通用肉鸽属性应用。
local jass = require "jass.common"
local hero_stats = require "hero.stats"

local module = {}

local function common(state, key)
    return math.floor(tonumber(state.common[key]) or 0)
end

local function growth_bonus(state, key)
    local hero_level = type(jass.GetHeroLevel) == "function" and jass.GetHeroLevel(state.hero) or 1
    return math.floor(math.max(0, hero_level - 1) * common(state, key) / 10)
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

return module
