--- 魔兽 1.27 怪物属性平台适配层。
--- 通过隐藏物品技能同步增加生命、攻击基础值和护甲，不依赖新版原生接口。
local jass = require "jass.common"
local scaling = require "config.monster_scaling"

local module = {}

---@class MonsterBaseStats
---@field health integer 基础最大生命
---@field armor integer 基础护甲
---@field damageBase integer 攻击基础值
---@field diceCount integer 攻击骰子数量
---@field diceSides integer 每颗骰子的面数

---@class MonsterDifficultyStats
---@field multiplier integer 十倍定点倍率，10 代表 1 倍
---@field healthMultiplier integer 十倍定点生命倍率
---@field attackMultiplier integer 十倍定点攻击倍率
---@field health integer 应用后的最大生命
---@field armor integer 应用后的护甲
---@field damageBase integer 应用后的攻击基础值
---@field diceCount integer 保持物编默认的攻击骰子数量
---@field diceSides integer 保持物编默认的每骰面数
---@field healthBonus integer 隐藏技能提供的生命加成
---@field damageBonus integer 隐藏技能提供的攻击基础值加成
---@field armorBonus integer 隐藏技能提供的护甲加成

local REQUIRED_INTERFACES = {
    "UnitAddAbility",
    "SetUnitAbilityLevel",
    "SetUnitState",
}

local function rawcode_to_ability_id(rawcode)
    if type(rawcode) ~= "string" or #rawcode ~= 4 then
        return nil
    end
    local first_byte, second_byte, third_byte, fourth_byte = string.byte(rawcode, 1, 4)
    if first_byte == nil or second_byte == nil or third_byte == nil or fourth_byte == nil then
        return nil
    end
    return first_byte * 0x1000000
        + second_byte * 0x10000
        + third_byte * 0x100
        + fourth_byte
end

local function has_interfaces()
    for _, name in ipairs(REQUIRED_INTERFACES) do
        if type(jass[name]) ~= "function" then
            return false
        end
    end
    return true
end

local function get_profile(difficulty)
    if type(difficulty) ~= "table" then
        return nil
    end
    return scaling.profiles[string.format("%d:%d", difficulty.modeId, difficulty.level)]
end

local function ceil_divide(value, divisor)
    if value <= 0 then
        return 0
    end
    return math.floor((value + divisor - 1) / divisor)
end

local function add_hidden_ability(unit_handle, rawcode, level)
    local ability_id = rawcode_to_ability_id(rawcode)
    if ability_id == nil then
        return false, "技能 Rawcode 无效：" .. tostring(rawcode)
    end
    if not jass.UnitAddAbility(unit_handle, ability_id) then
        return false, "技能添加失败：" .. rawcode
    end
    jass.SetUnitAbilityLevel(unit_handle, ability_id, level)
    return true, nil
end

--- 判断当前 Warcraft 1.27 运行时是否支持隐藏属性技能方案。
---@return boolean available 是否具备所需标准接口
function module.is_available()
    return has_interfaces()
end

--- 获取当前运行时缺少的标准单位技能接口。
---@return string[] names 缺失接口列表；完整可用时为空数组
function module.get_missing_interfaces()
    local names = {}
    for _, name in ipairs(REQUIRED_INTERFACES) do
        if type(jass[name]) ~= "function" then
            table.insert(names, name)
        end
    end
    return names
end

--- 返回当前固定使用的属性实现名称。
---@return string backend 后端名称
function module.get_backend_name()
    return "item-ability"
end

--- 依据 Excel 生成的难度配置计算怪物最终属性和隐藏技能加成。
---@param base MonsterBaseStats 单位物编基础属性
---@param difficulty MonsterDifficulty 难度配置
---@return MonsterDifficultyStats stats 最终属性
function module.calculate(base, difficulty)
    local health_multiplier = difficulty.healthMultiplier
    local attack_multiplier = difficulty.attackMultiplier
    local armor_bonus = difficulty.armorBonus
    local health = ceil_divide(base.health * health_multiplier, 10)
    local damage_base = ceil_divide(base.damageBase * attack_multiplier, 10)
    return {
        multiplier = difficulty.multiplier,
        healthMultiplier = health_multiplier,
        attackMultiplier = attack_multiplier,
        health = health,
        armor = base.armor + armor_bonus,
        damageBase = damage_base,
        diceCount = base.diceCount,
        diceSides = base.diceSides,
        healthBonus = health - base.health,
        damageBonus = damage_base - base.damageBase,
        armorBonus = armor_bonus,
    }
end

--- 将对应难度的隐藏属性技能添加到怪物，并在生命加成后回满生命。
---@param unit_handle unit 怪物单位句柄
---@param unit_rawcode string 怪物单位 Rawcode
---@param difficulty MonsterDifficulty 已同步的模式和等级
---@param stats MonsterDifficultyStats 已计算的目标属性
---@return boolean applied 是否成功写入
---@return string|nil message 失败原因
function module.apply(unit_handle, unit_rawcode, difficulty, stats)
    if not has_interfaces() or unit_handle == nil then
        return false, "运行时缺少单位技能接口"
    end
    local profile = get_profile(difficulty)
    local abilities = scaling.units[unit_rawcode]
    if profile == nil or abilities == nil then
        return false, "缺少难度技能映射：单位=" .. tostring(unit_rawcode)
    end
    local group_index = profile.groupIndex
    local ability_level = profile.abilityLevel
    local health_rawcode = abilities.healthAbilities[group_index]
    local attack_rawcode = abilities.attackAbilities[group_index]
    local armor_rawcode = scaling.armorAbilities[group_index]
    if health_rawcode == nil or attack_rawcode == nil or armor_rawcode == nil then
        return false, "难度技能组缺失：单位=" .. tostring(unit_rawcode)
    end

    if stats.healthBonus > 0 then
        local success, message = add_hidden_ability(unit_handle, health_rawcode, ability_level)
        if not success then
            return false, message
        end
    end
    if stats.damageBonus > 0 then
        local success, message = add_hidden_ability(unit_handle, attack_rawcode, ability_level)
        if not success then
            return false, message
        end
    end
    if stats.armorBonus > 0 then
        local success, message = add_hidden_ability(unit_handle, armor_rawcode, ability_level)
        if not success then
            return false, message
        end
    end
    jass.SetUnitState(unit_handle, jass.UNIT_STATE_LIFE, stats.health)
    return true, nil
end

return module
