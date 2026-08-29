--- 装备拾取、丢弃和初始物品栏扫描。
--- 原生物品栏仍由 Warcraft 管理，本模块只维护实例映射和生效回调。
local jass = require "jass.common"
local config = require "config.items"
local generator = require "equipment.generator"
local instance = require "equipment.instance"

local module = {}
local pickup_trigger = nil
local drop_trigger = nil
local allow_local_fallback = false
local next_fallback_uid = 9000000
local on_changed = nil
local PICKUP_APPLY_DELAY = 0.03
local PICKUP_APPLY_MAX_RETRIES = 5
local DROP_REFRESH_DELAY = 0.03
local DROP_REFRESH_MAX_RETRIES = 5

local function rawcode_to_id(rawcode)
    local a, b, c, d = string.byte(rawcode or "", 1, 4)
    if a == nil or b == nil or c == nil or d == nil then
        return nil
    end
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local function get_item_rawcode(item_handle)
    if item_handle == nil or type(jass.GetItemTypeId) ~= "function" then
        return nil
    end
    local item_id = jass.GetItemTypeId(item_handle)
    for rawcode, item_config in pairs(config) do
        if type(item_config) == "table" and item_config.isEquipment == 1 and rawcode_to_id(rawcode) == item_id then
            return rawcode
        end
    end
    return nil
end

local function get_manipulating_unit()
    if type(jass.GetManipulatingUnit) == "function" then
        return jass.GetManipulatingUnit()
    end
    return type(jass.GetTriggerUnit) == "function" and jass.GetTriggerUnit() or nil
end

local function get_manipulated_item()
    if type(jass.GetManipulatedItem) == "function" then
        return jass.GetManipulatedItem()
    end
    return nil
end

local function ensure_instance(item_handle)
    local current = instance.get_by_item(item_handle)
    if current ~= nil then
        return current
    end
    if not allow_local_fallback then
        print("警告：拾取到未绑定的装备道具，已拒绝本地重新随机")
        return nil
    end
    local rawcode = get_item_rawcode(item_handle)
    local item_config = rawcode and config[rawcode] or nil
    if item_config == nil or item_config.isEquipment ~= 1 then
        return nil
    end
    next_fallback_uid = next_fallback_uid + 1
    local created = generator.create_instance(
        item_config.equipLevel,
        item_config.equipmentTemplateId,
        "ALL",
        next_fallback_uid,
        next_fallback_uid
    )
    if created ~= nil then
        instance.bind_item(item_handle, created)
    end
    return created
end

local function has_equipment_in_inventory(hero, equipment)
    if equipment == nil then
        return false
    end
    for _, equipped in ipairs(instance.get_equipment_instances(hero)) do
        if equipped.uid == equipment.uid then
            return true
        end
    end
    return false
end

--- 在原生拾取事件完成物品栏写入后，重新应用装备效果。
--- 使用实例 UID 判断是否已进入物品栏，不能直接比较 Lua 侧的 item 句柄对象。
---@param hero unit 拾取装备的英雄
---@param equipment EquipmentInstance 被拾取装备实例
---@return boolean applied 是否已在物品栏中生效
local function apply_pickup_after_inventory_update(hero, equipment)
    if hero == nil or equipment == nil or instance.get_hero_state(hero) == nil then
        return false
    end
    if not has_equipment_in_inventory(hero, equipment) then
        return false
    end
    if on_changed ~= nil then
        on_changed(hero, equipment, "pickup")
    end
    return true
end

local function schedule_pickup_apply(hero, equipment, retries_left)
    local function try_apply()
        if apply_pickup_after_inventory_update(hero, equipment) then
            return
        end
        if retries_left > 0 then
            schedule_pickup_apply(hero, equipment, retries_left - 1)
        else
            print("警告：装备拾取后未进入物品栏，未应用属性，uid=" .. tostring(equipment.uid))
        end
    end

    if type(jass.CreateTimer) ~= "function" or type(jass.TimerStart) ~= "function" then
        try_apply()
        return
    end

    local timer = jass.CreateTimer()
    jass.TimerStart(timer, PICKUP_APPLY_DELAY, false, function()
        if type(jass.DestroyTimer) == "function" then
            jass.DestroyTimer(timer)
        end
        try_apply()
    end)
end

--- 在原生丢弃事件完成物品栏移除后，撤销原英雄的装备效果。
---@param hero unit 丢弃装备的英雄
---@param equipment EquipmentInstance 被丢弃装备实例
---@return boolean refreshed 是否已确认离开物品栏并刷新
local function apply_drop_after_inventory_update(hero, equipment)
    if hero == nil or equipment == nil or instance.get_hero_state(hero) == nil then
        return false
    end
    if has_equipment_in_inventory(hero, equipment) then
        return false
    end
    if on_changed ~= nil then
        on_changed(hero, equipment, "drop")
    end
    return true
end

local function schedule_drop_refresh(hero, equipment, retries_left)
    local function try_refresh()
        if apply_drop_after_inventory_update(hero, equipment) then
            return
        end
        if retries_left > 0 then
            schedule_drop_refresh(hero, equipment, retries_left - 1)
        else
            print("警告：装备丢弃后仍在原物品栏，未撤销属性，uid=" .. tostring(equipment.uid))
        end
    end

    if type(jass.CreateTimer) ~= "function" or type(jass.TimerStart) ~= "function" then
        try_refresh()
        return
    end

    local timer = jass.CreateTimer()
    jass.TimerStart(timer, DROP_REFRESH_DELAY, false, function()
        if type(jass.DestroyTimer) == "function" then
            jass.DestroyTimer(timer)
        end
        try_refresh()
    end)
end

local function on_pickup()
    local hero = get_manipulating_unit()
    local item_handle = get_manipulated_item()
    if hero == nil or item_handle == nil or instance.get_hero_state(hero) == nil then
        return
    end

    local equipment = ensure_instance(item_handle)
    if equipment == nil then
        return
    end
    schedule_pickup_apply(hero, equipment, PICKUP_APPLY_MAX_RETRIES)
end

local function on_drop()
    local hero = get_manipulating_unit()
    local item_handle = get_manipulated_item()
    if hero == nil or item_handle == nil or instance.get_hero_state(hero) == nil then
        return
    end
    -- 地面道具仍使用同一个 Warcraft 物品句柄；保留实例才能让任意队友
    -- 再次拾取后恢复原有的随机属性、词条和自动技能。
    local equipment = instance.get_by_item(item_handle)
    if equipment == nil then
        return
    end
    schedule_drop_refresh(hero, equipment, DROP_REFRESH_MAX_RETRIES)
end

local function register_for_players(hero_results)
    pickup_trigger = jass.CreateTrigger()
    drop_trigger = jass.CreateTrigger()
    local seen = {}
    for _, result in ipairs(hero_results or {}) do
        if not seen[result.playerId] then
            seen[result.playerId] = true
            local player_handle = jass.Player(result.playerId)
            jass.TriggerRegisterPlayerUnitEvent(pickup_trigger, player_handle, jass.EVENT_PLAYER_UNIT_PICKUP_ITEM, nil)
            jass.TriggerRegisterPlayerUnitEvent(drop_trigger, player_handle, jass.EVENT_PLAYER_UNIT_DROP_ITEM, nil)
        end
    end
    jass.TriggerAddAction(pickup_trigger, on_pickup)
    jass.TriggerAddAction(drop_trigger, on_drop)
end

--- 启动装备物品栏事件。
---@param hero_results HeroSelectionResult[] 英雄结果
---@param fallback boolean 是否允许单机本地创建未绑定实例
---@param changed fun(hero:unit, equipment:EquipmentInstance, reason:string) 生效变化回调
function module.start(hero_results, fallback, changed)
    allow_local_fallback = fallback == true
    on_changed = changed
    for _, result in ipairs(hero_results or {}) do
        instance.register_hero(result.playerId, result.unit)
    end
    register_for_players(hero_results)
    for _, result in ipairs(hero_results or {}) do
        local hero = result.unit
        for slot = 0, 5 do
            local item_handle = instance.get_item_in_slot(hero, slot)
            if item_handle ~= nil then
                ensure_instance(item_handle)
            end
        end
        if on_changed ~= nil then
            on_changed(hero, nil, "initial")
        end
    end
    return true
end

module.handle_pickup = on_pickup
module.handle_drop = on_drop

return module
