--- 装备实例和物品栏映射。
--- 装备的随机结果只在掉落或合成同步结果中确定，拾取阶段不重新随机。
local jass = require "jass.common"

local module = {}

---@class EquipmentInstance
---@field uid integer 装备唯一 ID
---@field item item Warcraft 物品句柄
---@field rawcode string 基础物品 Rawcode
---@field templateId string 装备模板 ID
---@field level integer 装备等级
---@field stats table<string, number> 最终属性，包含固定值和百分比属性
---@field autoSkillId string|nil 自动技能 ID
---@field passiveSkillIds string[] 普通被动 ID
---@field comboSetId string|nil 套装 ID
---@field comboPieceId string|nil 套装部件 ID

---@class EquipmentHeroState
---@field playerId integer 玩家编号
---@field hero unit 英雄句柄
---@field slots table<integer, item|nil> 当前 6 格物品

---@type table<item, EquipmentInstance>
local by_item = {}
---@type table<integer, EquipmentInstance>
local by_uid = {}
---@type table<unit, EquipmentHeroState>
local by_hero = {}
---@type table<integer, unit>
local hero_by_player = {}

local function get_item_in_slot(hero, slot)
    if type(jass.UnitItemInSlot) == "function" then
        return jass.UnitItemInSlot(hero, slot)
    end
    if type(jass.GetUnitItemInSlot) == "function" then
        return jass.GetUnitItemInSlot(hero, slot)
    end
    return nil
end

local function copy_array(values)
    local result = {}
    for index, value in ipairs(values or {}) do
        result[index] = value
    end
    return result
end

--- 初始化一个装备实例，不绑定到物品句柄。
---@param data table 同步或生成后的装备数据
---@return EquipmentInstance instance 装备实例
function module.create(data)
    local instance = {
        uid = math.floor(tonumber(data.uid) or 0),
        item = data.item,
        rawcode = tostring(data.rawcode),
        templateId = tostring(data.templateId or ""),
        level = math.floor(tonumber(data.level) or 1),
        stats = {
            attack = math.floor(tonumber(data.stats and data.stats.attack or data.attack) or 0),
            health = math.floor(tonumber(data.stats and data.stats.health or data.health) or 0),
            armor = math.floor(tonumber(data.stats and data.stats.armor or data.armor) or 0),
            basicAttackBonusPercent = math.floor(tonumber(
                data.stats and data.stats.basicAttackBonusPercent or data.basicAttackBonusPercent
            ) or 0),
            healthAmplificationPercent = math.floor(tonumber(
                data.stats and data.stats.healthAmplificationPercent or data.healthAmplificationPercent
            ) or 0),
        },
        autoSkillId = data.autoSkillId ~= nil and tostring(data.autoSkillId) or nil,
        passiveSkillIds = copy_array(data.passiveSkillIds),
        comboSetId = data.comboSetId ~= nil and tostring(data.comboSetId) or nil,
        comboPieceId = data.comboPieceId ~= nil and tostring(data.comboPieceId) or nil,
    }
    return instance
end

--- 注册玩家英雄。
---@param playerId integer 玩家编号
---@param hero unit 英雄句柄
function module.register_hero(playerId, hero)
    local state = {
        playerId = playerId,
        hero = hero,
        slots = {},
    }
    by_hero[hero] = state
    hero_by_player[playerId] = hero
    module.refresh_inventory(hero)
end

---@param hero unit 英雄句柄
---@return EquipmentHeroState|nil state 英雄装备状态
function module.get_hero_state(hero)
    return by_hero[hero]
end

---@param playerId integer 玩家编号
---@return unit|nil hero 玩家英雄
function module.get_hero_by_player(playerId)
    return hero_by_player[playerId]
end

---@param hero unit 英雄句柄
---@return integer|nil playerId 英雄所属玩家编号
function module.get_player_id(hero)
    local state = by_hero[hero]
    return state and state.playerId or nil
end

---@param item_handle item 物品句柄
---@return EquipmentInstance|nil instance 装备实例
function module.get_by_item(item_handle)
    return by_item[item_handle]
end

---@param uid integer 装备唯一 ID
---@return EquipmentInstance|nil instance 装备实例
function module.get_by_uid(uid)
    return by_uid[uid]
end

--- 绑定物品句柄和装备实例。
---@param item_handle item 物品句柄
---@param instance EquipmentInstance 装备实例
function module.bind_item(item_handle, instance)
    if item_handle == nil or instance == nil then
        return
    end
    instance.item = item_handle
    by_item[item_handle] = instance
    if instance.uid > 0 then
        by_uid[instance.uid] = instance
    end
end

--- 删除物品映射，但保留实例对象给调用方做回滚或日志。
---@param item_handle item 物品句柄
---@return EquipmentInstance|nil instance 被删除的实例
function module.unbind_item(item_handle)
    local instance = by_item[item_handle]
    if instance == nil then
        return nil
    end
    by_item[item_handle] = nil
    if instance.uid > 0 and by_uid[instance.uid] == instance then
        by_uid[instance.uid] = nil
    end
    instance.item = nil
    return instance
end

--- 按原生物品栏重新建立英雄的 6 格状态。
---@param hero unit 英雄句柄
---@return item[] items 当前物品栏中的物品
function module.refresh_inventory(hero)
    local state = by_hero[hero]
    if state == nil then
        return {}
    end
    local items = {}
    state.slots = {}
    for slot = 0, 5 do
        local item_handle = get_item_in_slot(hero, slot)
        state.slots[slot] = item_handle
        if item_handle ~= nil then
            table.insert(items, item_handle)
        end
    end
    return items
end

---@param hero unit 英雄句柄
---@param slot integer 0 到 5 的原生物品栏下标
---@return item|nil itemHandle 物品句柄
function module.get_item_in_slot(hero, slot)
    return get_item_in_slot(hero, slot)
end

---@param hero unit 英雄句柄
---@return EquipmentInstance[] instances 当前 6 格中的装备实例
function module.get_equipment_instances(hero)
    module.refresh_inventory(hero)
    local state = by_hero[hero]
    local result = {}
    if state == nil then
        return result
    end
    for slot = 0, 5 do
        local item_handle = state.slots[slot]
        local instance = item_handle and by_item[item_handle] or nil
        if instance ~= nil then
            table.insert(result, instance)
        end
    end
    return result
end

---@param hero unit 英雄句柄
---@return table<integer, EquipmentInstance|nil> slots 0 到 5 的装备实例
function module.get_equipment_slots(hero)
    module.refresh_inventory(hero)
    local state = by_hero[hero]
    local result = {}
    if state == nil then
        return result
    end
    for slot = 0, 5 do
        local item_handle = state.slots[slot]
        result[slot] = item_handle and by_item[item_handle] or nil
    end
    return result
end

---@return table<integer, EquipmentInstance> all 当前所有实例
function module.get_all()
    return by_uid
end

return module
