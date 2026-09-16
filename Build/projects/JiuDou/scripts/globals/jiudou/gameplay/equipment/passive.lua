--- 普通被动词条处理。
--- 数值型被动参与属性聚合，事件型被动交给自动技能统一执行器处理。
local config = JiuDou.config.equipment
local generator = JiuDou.module("gameplay.equipment.generator")

local module = {}

---@class EquipmentStatBonus
---@field attack integer 攻击力加成
---@field health integer 最大生命加成
---@field armor integer 护甲加成
---@field basicAttackBonusPercent integer 普攻加成百分比
---@field healthAmplificationPercent integer 生命增幅百分比
---@field autoDamageBonus integer 自动技能伤害百分比加成

local function empty_bonus()
    return {
        attack = 0,
        health = 0,
        armor = 0,
        basicAttackBonusPercent = 0,
        healthAmplificationPercent = 0,
        autoDamageBonus = 0,
    }
end

--- 汇总一组装备的数值被动。
---@param equipments EquipmentInstance[] 装备实例
---@return EquipmentStatBonus bonus 被动加成
function module.get_stat_bonus(equipments)
    local bonus = empty_bonus()
    for _, equipment in ipairs(equipments or {}) do
        for _, passive_id in ipairs(equipment.passiveSkillIds or {}) do
            local passive = config.passives[passive_id]
            if passive ~= nil then
                local value = math.floor(tonumber(passive.param1) or 0)
                if passive.handler == "stat_attack" then
                    bonus.attack = bonus.attack + value
                elseif passive.handler == "stat_health" then
                    bonus.health = bonus.health + value
                elseif passive.handler == "stat_armor" then
                    bonus.armor = bonus.armor + value
                elseif passive.handler == "stat_basic_attack_bonus_percent" then
                    bonus.basicAttackBonusPercent = bonus.basicAttackBonusPercent + value
                elseif passive.handler == "stat_health_amplification_percent" then
                    bonus.healthAmplificationPercent = bonus.healthAmplificationPercent + value
                elseif passive.handler == "auto_damage_bonus" then
                    bonus.autoDamageBonus = bonus.autoDamageBonus + value
                end
            end
        end
    end
    return bonus
end

--- 取得一次战斗事件中的被动效果。
---@param equipments EquipmentInstance[] 装备实例
---@param event_type string 事件类型
---@param event_id integer 事件序号
---@return table[] effects 需要交给自动技能执行器的效果
function module.get_event_effects(equipments, event_type, event_id)
    local effects = {}
    for _, equipment in ipairs(equipments or {}) do
        for passive_index, passive_id in ipairs(equipment.passiveSkillIds or {}) do
            local passive = config.passives[passive_id]
            if passive ~= nil and passive.eventType == event_type then
                local roll_key = event_id * 100000 + equipment.uid * 10 + passive_index
                if generator.roll_percent(roll_key, passive.chance) then
                    table.insert(effects, {
                        uid = equipment.uid,
                        level = equipment.level,
                        sourceId = passive_id,
                        handler = passive.handler,
                        param1 = passive.param1,
                        param2 = passive.param2,
                        damageAttribute = passive.damageAttribute,
                        damageMultiplierBaseTenth = passive.damageMultiplierBaseTenth,
                        damageMultiplierPerLevelTenth = passive.damageMultiplierPerLevelTenth,
                        internalCooldown = passive.internalCooldown,
                    })
                end
            end
        end
    end
    return effects
end

---@return string[] ids 已加载的被动配置 ID
function module.get_all_ids()
    local result = {}
    for passive_id in pairs(config.passives) do
        table.insert(result, passive_id)
    end
    table.sort(result)
    return result
end

JiuDou.publish("gameplay.equipment.passive", module)
return module
