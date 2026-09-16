--- 组合套装统计和被动效果。
--- 重复相同部件只计一次，3 件效果建立在 2 件效果之上。
local config = JiuDou.config.equipment

local module = {}

local function collect_sets(equipments)
    local sets = {}
    for _, equipment in ipairs(equipments or {}) do
        if equipment.comboSetId ~= nil and equipment.comboPieceId ~= nil then
            local set = sets[equipment.comboSetId]
            if set == nil then
                set = {pieces = {}, rows = {}}
                sets[equipment.comboSetId] = set
            end
            if not set.pieces[equipment.comboPieceId] then
                set.pieces[equipment.comboPieceId] = true
                set.rows[equipment.comboPieceId] = config.combos[equipment.comboPieceId]
            end
        end
    end
    return sets
end

local function apply_handler(bonus, handler, value)
    if handler == "stat_attack" then
        bonus.attack = bonus.attack + value
    elseif handler == "stat_health" then
        bonus.health = bonus.health + value
    elseif handler == "stat_armor" then
        bonus.armor = bonus.armor + value
    elseif handler == "stat_basic_attack_bonus_percent" then
        bonus.basicAttackBonusPercent = bonus.basicAttackBonusPercent + value
    elseif handler == "stat_health_amplification_percent" then
        bonus.healthAmplificationPercent = bonus.healthAmplificationPercent + value
    elseif handler == "auto_damage_bonus" then
        bonus.autoDamageBonus = bonus.autoDamageBonus + value
    end
end

--- 获取当前激活的套装效果。
---@param equipments EquipmentInstance[] 当前物品栏装备
---@return table[] active 当前套装状态
function module.get_active_sets(equipments)
    local active = {}
    for set_id, set in pairs(collect_sets(equipments)) do
        local count = 0
        for _ in pairs(set.pieces) do
            count = count + 1
        end
        if count >= 2 then
            local representative = nil
            for _, row in pairs(set.rows) do
                representative = row
                break
            end
            table.insert(active, {
                setId = set_id,
                count = count,
                row = representative,
                need2Handler = representative and representative.need2Handler or nil,
                need2Param1 = representative and representative.need2Param1 or 0,
                need2Param2 = representative and representative.need2Param2 or 0,
                need2Description = representative and representative.need2Description or "",
                need3Handler = representative and representative.need3Handler or nil,
                need3Param1 = representative and representative.need3Param1 or 0,
                need3Param2 = representative and representative.need3Param2 or 0,
                need3Description = representative and representative.need3Description or "",
            })
        end
    end
    table.sort(active, function(left, right)
        return left.setId < right.setId
    end)
    return active
end

--- 汇总当前套装的数值效果。
---@param equipments EquipmentInstance[] 当前物品栏装备
---@return EquipmentStatBonus bonus 套装加成
function module.get_stat_bonus(equipments)
    local bonus = {
        attack = 0,
        health = 0,
        armor = 0,
        basicAttackBonusPercent = 0,
        healthAmplificationPercent = 0,
        autoDamageBonus = 0,
    }
    for _, active in ipairs(module.get_active_sets(equipments)) do
        apply_handler(bonus, active.need2Handler, math.floor(tonumber(active.need2Param1) or 0))
        if active.count >= 3 then
            apply_handler(bonus, active.need3Handler, math.floor(tonumber(active.need3Param1) or 0))
        end
    end
    return bonus
end

JiuDou.publish("gameplay.equipment.combo", module)
return module
