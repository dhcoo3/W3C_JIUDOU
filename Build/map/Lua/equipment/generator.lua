--- 装备结果生成器。
--- 只有房主调用掉落和合成生成；所有随机使用可复现的确定性随机流。
local config = require "config.equipment"
local random = require "monster.random"
local instance = require "equipment.instance"

local module = {}
local session_seed = 13579

local function level_config(level)
    return config.levels["LEVEL_" .. tostring(level)]
end

local function seeded_random(serial, salt)
    local key = math.floor(tonumber(serial) or 0) * 104729 + math.floor(tonumber(salt) or 0) * 1009 + 17
    return random.create(random.derive_seed(session_seed, key))
end

local function weighted_pick(rows, weight_field, rng, filter)
    local total = 0
    local candidates = {}
    for key, row in pairs(rows or {}) do
        if filter == nil or filter(row, key) then
            local weight = math.floor(tonumber(row[weight_field]) or 0)
            if weight > 0 then
                total = total + weight
                table.insert(candidates, {key = key, row = row, weight = weight})
            end
        end
    end
    if total <= 0 then
        return nil, nil
    end
    local roll = random.next_integer(rng, 1, total)
    for _, candidate in ipairs(candidates) do
        roll = roll - candidate.weight
        if roll <= 0 then
            return candidate.row, candidate.key
        end
    end
    return candidates[#candidates].row, candidates[#candidates].key
end

local function scale(value, multiplier_percent)
    return math.floor((value * multiplier_percent + 99) / 100)
end

local function choose_passives(level, rng)
    local level_row = level_config(level)
    local result = {}
    if level_row == nil or level_row.passiveMax < 1 then
        return result
    end
    local count = random.next_integer(rng, level_row.passiveMin, level_row.passiveMax)
    local selected = {}
    for _ = 1, count do
        local row, key = weighted_pick(config.passives, "weight", rng, function(_, passive_id)
            return selected[passive_id] ~= true
        end)
        if row == nil then
            break
        end
        selected[key] = true
        table.insert(result, key)
    end
    return result
end

local function choose_combo(level, rng)
    local level_row = level_config(level)
    if level_row == nil or level_row.comboChance <= 0 then
        return nil, nil
    end
    if random.next_integer(rng, 1, 100) > level_row.comboChance then
        return nil, nil
    end
    local row, key = weighted_pick(config.combos, "weight", rng)
    if row == nil then
        return nil, nil
    end
    return row.setId, key
end

local function choose_auto_skill(level, rng)
    local level_row = level_config(level)
    if level_row == nil or level_row.autoSkillChance <= 0 then
        return nil
    end
    if random.next_integer(rng, 1, 100) > level_row.autoSkillChance then
        return nil
    end
    local _, key = weighted_pick(config.autoSkills, "weight", rng)
    return key
end

local function choose_template(level, pool_id, rng)
    return weighted_pick(config.templates, "weight", rng, function(row)
        return row.level == level and (pool_id == "ALL" or row.poolId == pool_id)
    end)
end

--- 设置本局装备随机种子。
---@param seed integer 同步种子
function module.configure(seed)
    if type(seed) == "number" and seed == math.floor(seed) and seed > 0 then
        session_seed = seed
    end
end

--- 根据固定模板生成完整装备实例。
---@param level integer 装备等级
---@param template_id string 模板 ID；为空时按等级和装备池随机
---@param pool_id string|nil 装备池
---@param uid integer 装备唯一 ID
---@param serial integer 随机序号
---@return EquipmentInstance|nil result 装备结果
function module.create_instance(level, template_id, pool_id, uid, serial)
    local level_row = level_config(level)
    if level_row == nil or level < 1 or level > 5 then
        return nil
    end
    local rng = seeded_random(serial or uid, level * 11 + 1)
    local selected_template_id = template_id
    local template = template_id and config.templates[template_id] or nil
    if template == nil then
        template, selected_template_id = choose_template(level, pool_id or "ALL", rng)
    end
    if template == nil then
        return nil
    end

    local base_attack = random.next_integer(rng, template.baseAttackMin, template.baseAttackMax)
    local base_health = random.next_integer(rng, template.baseHealthMin, template.baseHealthMax)
    local base_armor = random.next_integer(rng, template.baseArmorMin, template.baseArmorMax)
    local multiplier = level_row.statMultiplierPercent
    local auto_skill_id = nil
    local passive_ids = {}
    local combo_set_id = nil
    local combo_piece_id = nil
    if level >= 2 then
        auto_skill_id = choose_auto_skill(level, seeded_random(serial or uid, level * 11 + 2))
        passive_ids = choose_passives(level, seeded_random(serial or uid, level * 11 + 3))
        combo_set_id, combo_piece_id = choose_combo(level, seeded_random(serial or uid, level * 11 + 4))
    end

    return instance.create({
        uid = uid,
        rawcode = template.rawcode,
        templateId = selected_template_id or template.templateId or "",
        level = level,
        stats = {
            attack = scale(base_attack, multiplier),
            health = scale(base_health, multiplier),
            armor = scale(base_armor, multiplier),
            basicAttackBonusPercent = math.floor(tonumber(template.basicAttackBonusPercent) or 0),
            healthAmplificationPercent = math.floor(tonumber(template.healthAmplificationPercent) or 0),
        },
        autoSkillId = auto_skill_id,
        passiveSkillIds = passive_ids,
        comboSetId = combo_set_id,
        comboPieceId = combo_piece_id,
    })
end

--- 根据怪物掉落规则生成装备。
---@param drop_rule table 掉落参数，由 unit.xlsx 当前变体行构造
---@param uid integer 装备唯一 ID
---@param serial integer 随机序号
---@return EquipmentInstance|nil result 装备结果
function module.create_drop(drop_rule, uid, serial)
    local level = random.next_integer(seeded_random(serial, 71), drop_rule.levelMin, drop_rule.levelMax)
    return module.create_instance(level, nil, drop_rule.poolId, uid, serial + 1000)
end

--- 根据两个材料等级生成下一级装备。
---@param level integer 材料等级
---@param uid integer 新装备唯一 ID
---@param serial integer 随机序号
---@return EquipmentInstance|nil result 合成结果
function module.create_merge(level, uid, serial)
    if level < 1 or level >= 5 then
        return nil
    end
    return module.create_instance(level + 1, nil, "ALL", uid, serial + 2000)
end

--- 为概率自动技能生成确定性结果，不使用本地 math.random。
---@param key integer|string 事件和装备组合键
---@param chance integer 百分比
---@return boolean triggered 是否触发
function module.roll_percent(key, chance)
    chance = math.floor(tonumber(chance) or 0)
    if chance <= 0 then
        return false
    end
    if chance >= 100 then
        return true
    end
    local numeric_key = tonumber(key) or 0
    local rng = seeded_random(numeric_key, 991)
    return random.next_integer(rng, 1, 100) <= chance
end

return module
