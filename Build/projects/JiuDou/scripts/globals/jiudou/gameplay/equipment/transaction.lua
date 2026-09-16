--- 装备背包事务。
--- 合成结果必须经过“校验材料 → 移除材料 → 写入结果 → 失败回滚”的单一入口。
local jass = J.Common
local config = JiuDou.config.items
local instance = JiuDou.module("gameplay.equipment.instance")

local module = {}

local function rawcode_to_id(rawcode)
    local a, b, c, d = string.byte(rawcode or "", 1, 4)
    if a == nil or b == nil or c == nil or d == nil then
        return nil
    end
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local function remove_material(carrier, item_handle)
    if item_handle == nil then
        return
    end
    instance.unbind_item(item_handle)
    if type(jass.UnitRemoveItem) == "function" then
        jass.UnitRemoveItem(carrier, item_handle)
    end
    if type(jass.RemoveItem) == "function" then
        jass.RemoveItem(item_handle)
    end
end

local function restore_material(carrier, slot, equipment)
    local item_id = rawcode_to_id(equipment.rawcode)
    if item_id == nil then
        return false
    end
    local item_handle = nil
    if type(jass.UnitAddItemToSlotById) == "function" then
        if jass.UnitAddItemToSlotById(carrier, item_id, slot) then
            item_handle = instance.get_item_in_slot(carrier, slot)
        end
    elseif type(jass.CreateItem) == "function" and type(jass.UnitAddItem) == "function" then
        item_handle = jass.CreateItem(item_id, jass.GetUnitX(carrier), jass.GetUnitY(carrier))
        if item_handle ~= nil then
            jass.UnitAddItem(carrier, item_handle)
        end
    end
    if item_handle == nil then
        return false
    end
    instance.bind_item(item_handle, equipment)
    return true
end

local function add_result_to_slot(carrier, equipment)
    local item_id = rawcode_to_id(equipment.rawcode)
    if item_id == nil then
        return nil
    end
    local item_handle = nil
    if type(jass.UnitAddItemToSlotById) == "function" then
        if jass.UnitAddItemToSlotById(carrier, item_id, 0) then
            item_handle = instance.get_item_in_slot(carrier, 0)
        end
    elseif type(jass.CreateItem) == "function" and type(jass.UnitAddItem) == "function" then
        item_handle = jass.CreateItem(item_id, jass.GetUnitX(carrier), jass.GetUnitY(carrier))
        if item_handle ~= nil and not jass.UnitAddItem(carrier, item_handle) then
            jass.RemoveItem(item_handle)
            item_handle = nil
        end
        item_handle = item_handle or instance.get_item_in_slot(carrier, 0)
    end
    if item_handle ~= nil then
        instance.bind_item(item_handle, equipment)
    end
    return item_handle
end

--- 校验第 1、2 格是否仍是请求中的可合成材料。
---@param carrier unit
---@param first_uid integer
---@param second_uid integer
---@return EquipmentInstance|nil first
---@return EquipmentInstance|nil second
---@return string|nil reason
function module.validate_merge_materials(carrier, first_uid, second_uid)
    if carrier == nil then
        return nil, nil, "找不到合成来源物品栏"
    end
    local first_item = instance.get_item_in_slot(carrier, 0)
    local second_item = instance.get_item_in_slot(carrier, 1)
    local first = first_item and instance.get_by_item(first_item) or nil
    local second = second_item and instance.get_by_item(second_item) or nil
    if first == nil or second == nil or first.uid ~= first_uid or second.uid ~= second_uid then
        return nil, nil, "第1、2格装备已变化"
    end
    if first.level ~= second.level or first.level >= 5 then
        return nil, nil, "需要两件同级且低于5级的装备"
    end
    local first_config = config[first.rawcode]
    local second_config = config[second.rawcode]
    if first_config == nil or second_config == nil or first_config.mergeable ~= 1 or second_config.mergeable ~= 1 then
        return nil, nil, "材料不是可合成装备"
    end
    return first, second, nil
end

--- 应用已由房主确定的合成结果；失败时尽力恢复两个材料。
---@param carrier unit
---@param first_uid integer
---@param second_uid integer
---@param result EquipmentInstance
---@return boolean applied
---@return string|nil reason
function module.apply_merge_result(carrier, first_uid, second_uid, result)
    if carrier == nil or result == nil then
        return false, "合成结果数据无效"
    end
    local first_item = instance.get_item_in_slot(carrier, 0)
    local second_item = instance.get_item_in_slot(carrier, 1)
    local first = first_item and instance.get_by_item(first_item) or nil
    local second = second_item and instance.get_by_item(second_item) or nil
    if first == nil or second == nil or first.uid ~= first_uid or second.uid ~= second_uid then
        return false, "本地材料状态不一致"
    end

    remove_material(carrier, first_item)
    remove_material(carrier, second_item)
    if add_result_to_slot(carrier, result) == nil then
        restore_material(carrier, 0, first)
        restore_material(carrier, 1, second)
        instance.refresh_inventory(carrier)
        return false, "结果无法放入第1格，材料已尝试恢复"
    end
    instance.refresh_inventory(carrier)
    return true, nil
end

JiuDou.publish("gameplay.equipment.transaction", module)
return module
