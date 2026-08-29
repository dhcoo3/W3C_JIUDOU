--- 装备属性来源适配层。
--- 实际属性写入由 hero.stats 聚合，避免装备与肉鸽互相覆盖。
local hero_stats = require "hero.stats"
local instance = require "equipment.instance"
local passive = require "equipment.passive"
local combo = require "equipment.combo"

local module = {}

local function get_bonus(hero)
    local equipments = instance.get_equipment_instances(hero)
    local passive_bonus = passive.get_stat_bonus(equipments)
    local combo_bonus = combo.get_stat_bonus(equipments)
    local total = {
        attack = passive_bonus.attack + combo_bonus.attack,
        health = passive_bonus.health + combo_bonus.health,
        armor = passive_bonus.armor + combo_bonus.armor,
        basic_attack_bonus_percent = passive_bonus.basicAttackBonusPercent + combo_bonus.basicAttackBonusPercent,
        health_amplification_percent = passive_bonus.healthAmplificationPercent + combo_bonus.healthAmplificationPercent,
        moveSpeed = 0,
    }
    for _, equipment in ipairs(equipments) do
        total.attack = total.attack + equipment.stats.attack
        total.health = total.health + equipment.stats.health
        total.armor = total.armor + equipment.stats.armor
        total.basic_attack_bonus_percent = total.basic_attack_bonus_percent
            + (equipment.stats.basicAttackBonusPercent or 0)
        total.health_amplification_percent = total.health_amplification_percent
            + (equipment.stats.healthAmplificationPercent or 0)
    end
    return total
end

function module.preload(on_completed)
    return hero_stats.preload(on_completed)
end

function module.refresh(hero)
    if hero == nil then return false end
    return hero_stats.set_source(hero, "equipment", get_bonus(hero))
end

function module.apply_instance(hero, instance_data)
    return module.refresh(hero)
end

function module.remove_instance(hero, instance_data)
    return module.refresh(hero)
end

return module
