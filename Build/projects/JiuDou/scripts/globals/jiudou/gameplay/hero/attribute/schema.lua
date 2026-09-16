--- 英雄属性领域的统一字段与数值规范。
--- 此模块只处理 Lua 数据，不接触 Warcraft 句柄或原生投影。
local module = {}

module.ids = {
    "strength",
    "agility",
    "intelligence",
    "attack",
    "health",
    "armor",
    "moveSpeed",
    "attack_speed_percent",
    "basic_attack_bonus_percent",
    "health_amplification_percent",
}

--- 创建一份完整的零值属性表。
---@return table<string, integer> values
function module.empty()
    return {
        strength = 0,
        agility = 0,
        intelligence = 0,
        attack = 0,
        health = 0,
        armor = 0,
        moveSpeed = 0,
        attack_speed_percent = 0,
        basic_attack_bonus_percent = 0,
        health_amplification_percent = 0,
    }
end

--- 仅保留项目支持的属性字段，并将所有值规范为整数。
---@param values table<string, number>|nil
---@return table<string, integer> normalized
function module.normalize(values)
    values = type(values) == "table" and values or {}
    local normalized = module.empty()
    for _, attribute_id in ipairs(module.ids) do
        normalized[attribute_id] = math.floor(tonumber(values[attribute_id]) or 0)
    end
    return normalized
end

--- 返回属性数据的独立副本，避免调用者修改内部状态。
---@param values table<string, number>|nil
---@return table<string, integer> copied
function module.copy(values)
    return module.normalize(values)
end

JiuDou.publish("gameplay.hero.attribute.schema", module)
return module
