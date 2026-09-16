--- 英雄属性来源存储。
--- 装备、肉鸽、Buff 等系统只通过来源 ID 写入；最终结算由 hero.stats 负责。
local schema = JiuDou.module("gameplay.hero.attribute.schema")

local module = {}
local sources_by_hero = {}

---@param hero unit
---@return table<string, table<string, integer>>|nil sources
function module.ensure(hero)
    if hero == nil then
        return nil
    end
    sources_by_hero[hero] = sources_by_hero[hero] or {}
    return sources_by_hero[hero]
end

---@param hero unit
---@param source_id string
---@param values table<string, number>|nil
---@return table<string, integer>|nil normalized
function module.set(hero, source_id, values)
    if type(source_id) ~= "string" or source_id == "" then
        return nil
    end
    local sources = module.ensure(hero)
    if sources == nil then
        return nil
    end
    local normalized = schema.normalize(values)
    sources[source_id] = normalized
    return schema.copy(normalized)
end

---@param hero unit
---@param source_id string
---@return boolean removed
function module.clear(hero, source_id)
    local sources = sources_by_hero[hero]
    if sources == nil or sources[source_id] == nil then
        return false
    end
    sources[source_id] = nil
    return true
end

---@param hero unit
---@param source_id string
---@return table<string, integer> values
function module.get(hero, source_id)
    local sources = sources_by_hero[hero]
    return schema.copy(sources and sources[source_id])
end

---@param hero unit
---@return table<string, integer> total
function module.sum(hero)
    local total = schema.empty()
    for _, values in pairs(sources_by_hero[hero] or {}) do
        for _, attribute_id in ipairs(schema.ids) do
            total[attribute_id] = total[attribute_id] + values[attribute_id]
        end
    end
    return total
end

--- 在单位移除或整局重开时释放来源引用。
---@param hero unit
function module.release(hero)
    sources_by_hero[hero] = nil
end

JiuDou.publish("gameplay.hero.attribute.source_store", module)
return module
