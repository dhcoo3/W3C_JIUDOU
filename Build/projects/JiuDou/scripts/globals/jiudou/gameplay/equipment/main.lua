--- 装备系统总入口。
--- 统一接入配置、掉落、拾取、属性、自动技能、套装、合成同步和本地详情提示。
local jass = J.Common
local sync = JiuDou.module("gameplay.equipment.sync")
local generator = JiuDou.module("gameplay.equipment.generator")
local instance = JiuDou.module("gameplay.equipment.instance")
local pickup = JiuDou.module("gameplay.equipment.pickup")
local drop = JiuDou.module("gameplay.equipment.drop")
local merge = JiuDou.module("gameplay.equipment.merge")
local stats = JiuDou.module("gameplay.equipment.stats")
local auto_skill = JiuDou.module("gameplay.equipment.auto_skill")
local tooltip = JiuDou.module("gameplay.equipment.tooltip")
local courier = JiuDou.module("gameplay.courier.main")
local lifecycle = JiuDou.core and JiuDou.core.lifecycle

local module = {}
local started = false
local critical_enabled = false
local fallback_allowed = false
local next_public_uid = 8000000

local function stop_child(child)
    if type(child) == "table" and type(child.stop) == "function" then child.stop() end
end

local function rawcode_to_id(rawcode)
    local a, b, c, d = string.byte(rawcode or "", 1, 4)
    if a == nil or b == nil or c == nil or d == nil then
        return nil
    end
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local function count_active_players(hero_results)
    local count = 0
    local seen = {}
    for _, result in ipairs(hero_results or {}) do
        if not seen[result.playerId] then
            seen[result.playerId] = true
            count = count + 1
        end
    end
    if count > 0 then
        return count
    end
    if type(jass.GetPlayerSlotState) ~= "function" then
        return 1
    end
    for player_id = 0, 11 do
        local player_handle = jass.Player(player_id)
        if jass.GetPlayerSlotState(player_handle) == jass.PLAYER_SLOT_STATE_PLAYING then
            count = count + 1
        end
    end
    return math.max(1, count)
end

local function on_changed(hero, equipment, reason)
    stats.refresh(hero)
    auto_skill.refresh_hero(hero)
end

local function on_failure(player_id, reason)
    if sync.get_local_player_id() == player_id then
        print("装备合成失败：" .. tostring(reason))
    end
end

local function route_sync_message(message, sender_id)
    local parts = sync.split(message, "|")
    if parts[1] == "DROP_RESULT" and parts[2] == "3" then
        drop.handle_result(parts)
    elseif parts[1] == "MERGE_REQUEST" or parts[1] == "MERGE_RESULT" then
        merge.handle_sync(parts, sender_id)
    elseif parts[1] == "BIRD_FUSION_BEGIN" or parts[1] == "BIRD_FUSION_MATERIALS"
        or parts[1] == "BIRD_FUSION_OUTPUT" or parts[1] == "BIRD_FUSION_END" then
        courier.handle_sync(parts, sender_id)
    end
end

--- 在选将期间分帧预热装备隐藏技能，避免首次拾取时集中载入物编数据。
---@return boolean started_now 是否已启动或已经完成预热
function module.preload(on_completed)
    return stats.preload(on_completed)
end

--- 启动装备系统。
---@param hero_results HeroSelectionResult[] 英雄创建结果
---@param session_seed integer|nil 本局同步随机种子，可选
---@return boolean started_now 是否首次启动成功
function module.start(hero_results, session_seed)
    if started then
        return false
    end
    started = true
    if lifecycle ~= nil then
        lifecycle.acquire("equipment.main", function()
            stop_child(auto_skill)
            stop_child(merge)
            stop_child(drop)
            stop_child(pickup)
            stop_child(tooltip)
            stop_child(courier)
            sync.stop()
            started, critical_enabled, fallback_allowed = false, false, false
        end)
    end
    hero_results = hero_results or {}
    generator.configure(session_seed or 13579)
    local active_player_count = count_active_players(hero_results)
    local sync_available = sync.start(route_sync_message)
    fallback_allowed = not sync_available and active_player_count <= 1
    critical_enabled = sync_available or fallback_allowed
    if not sync_available and active_player_count > 1 then
        print("装备系统已禁用关键逻辑：多人模式缺少 1.27 同步接口")
    end
    drop.set_host_checker(sync.is_host)
    pickup.start(hero_results, fallback_allowed, on_changed)
    courier.start(hero_results, sync, critical_enabled, fallback_allowed)
    for _, result in ipairs(hero_results) do
        local courier_unit = courier.get_by_player(result.playerId)
        if courier_unit ~= nil and not pickup.register_inventory_proxy(result.unit, courier_unit) then
            print("飞行信使背包代理登记失败：player=" .. tostring(result.playerId))
        end
    end
    tooltip.start()
    if not critical_enabled then
        drop.start(sync.broadcast, false)
        merge.start(hero_results, sync, false, on_changed, on_failure)
        print("装备系统提示：当前多人模式不会本地随机掉落、合成或触发关键自动技能")
        return true
    end
    drop.start(sync.broadcast, true)
    merge.start(hero_results, sync, true, on_changed, on_failure)
    auto_skill.start(hero_results)
    print(string.format("装备系统已启动：玩家=%d，同步=%s，合成快捷键=F2", active_player_count, tostring(sync_available)))
    return true
end

function module.stop()
    return lifecycle ~= nil and lifecycle.release("equipment.main") or false
end

--- 创建一个装备实例，供掉落、合成或测试工具调用。
---@param level integer 装备等级
---@param template_id string|nil 模板 ID
---@return EquipmentInstance|nil instance 装备实例
function module.create_instance(level, template_id)
    next_public_uid = next_public_uid + 1
    return generator.create_instance(level, template_id, "ALL", next_public_uid, next_public_uid)
end

--- 将已确定的完整装备实例创建到英雄脚下，并尝试放入英雄物品栏。
--- 物品栏已满时不销毁物品，实例与地面物品保持绑定，后续拾取仍可生效。
---@param hero unit 英雄句柄
---@param equipment_data table 完整装备数据，包含 uid、rawcode、属性和词条
---@param x number 地面 X 坐标
---@param y number 地面 Y 坐标
---@return boolean created 是否创建成功
---@return boolean added 是否成功放入物品栏
---@return EquipmentInstance|nil equipment 已绑定的实例
function module.add_instance_to_hero(hero, equipment_data, x, y)
    if hero == nil or type(equipment_data) ~= "table" then
        return false, false, nil
    end
    local uid = math.floor(tonumber(equipment_data.uid) or 0)
    if uid <= 0 or instance.get_by_uid(uid) ~= nil then
        return false, false, nil
    end
    local item_id = rawcode_to_id(equipment_data.rawcode)
    if item_id == nil or type(jass.CreateItem) ~= "function" then
        return false, false, nil
    end
    local item_x = tonumber(x) or 0
    local item_y = tonumber(y) or 0
    local item_handle = jass.CreateItem(item_id, item_x, item_y)
    if item_handle == nil then
        return false, false, nil
    end
    local equipment = instance.create(equipment_data)
    if equipment == nil then
        return false, false, nil
    end
    instance.bind_item(item_handle, equipment)

    local added = false
    if type(jass.UnitAddItem) == "function" then
        added = jass.UnitAddItem(hero, item_handle) == true
    end
    if added then
        module.handle_pickup(hero, item_handle)
    end
    return true, added, equipment
end

--- 处理一次英雄拾取事件。
---@param hero unit 英雄句柄
---@param item_handle item 物品句柄
function module.handle_pickup(hero, item_handle)
    local equipment = instance.get_by_item(item_handle)
    if equipment == nil then
        return false
    end
    on_changed(hero, equipment, "pickup")
    return true
end

--- 处理一次英雄丢弃事件。
---@param hero unit 英雄句柄
---@param item_handle item 物品句柄
function module.handle_drop(hero, item_handle)
    -- 丢弃不是销毁：实例继续绑定在地面物品上，支持队友转交后复用。
    local equipment = instance.get_by_item(item_handle)
    if equipment == nil then
        return false
    end
    on_changed(hero, equipment, "drop")
    return true
end

---@return boolean sent 是否发送合成请求
function module.request_merge()
    return merge.request_merge()
end

---@param hero unit 英雄句柄
---@param equipment EquipmentInstance 装备实例
---@return boolean applied 是否成功刷新
function module.apply_instance(hero, equipment)
    return stats.apply_instance(hero, equipment)
end

---@param hero unit 英雄句柄
---@param equipment EquipmentInstance 装备实例
---@return boolean removed 是否成功刷新
function module.remove_instance(hero, equipment)
    return stats.remove_instance(hero, equipment)
end

---@param equipment EquipmentInstance 装备实例
---@param hero unit|nil 英雄句柄，可选
---@return string description 动态详情
function module.get_description(equipment, hero)
    return tooltip.build_description(equipment, hero)
end

JiuDou.publish("gameplay.equipment.main", module)
return module
