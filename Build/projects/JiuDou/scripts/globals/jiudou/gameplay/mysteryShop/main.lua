--- 四区域神秘商店。
--- 商店库存和价格由 Warcraft 原生商店处理；购买装备箱后由房主确定装备结果，
--- 再把完整实例同步给所有客户端，避免各客户端重新随机出不同装备。
local jass = J.Common
local config = JiuDou.config.mystery_shop
local item_config = JiuDou.config.items
local equipment = JiuDou.module("gameplay.equipment.main")
local equipment_instance = JiuDou.module("gameplay.equipment.instance")
local courier = JiuDou.module("gameplay.courier.main")
local sync = JiuDou.module("gameplay.mysteryShop.sync")
local box_result = JiuDou.module("gameplay.mysteryShop.box_result")

local module = {}
local lifecycle = JiuDou.core and JiuDou.core.lifecycle
local resource_api = JiuDou.core and JiuDou.core.resource
local runtime_scope = nil
local started = false
local enabled = false
local sell_trigger = nil
local consumable_use_trigger = nil
local event_sequence = 0
local shop_by_unit = {}
local active_player_by_id = {}
local hero_by_player = {}
local processed_items = {}
local processed_events = {}
local processed_uids = {}

local NEUTRAL_PASSIVE_PLAYER_ID = 15
local DEFAULT_STOCK = 1

--- jass.common 在部分 KKWE 运行时未导出 UNIT_STATE_MANA 常量，
--- 但 GetUnitState/SetUnitState 仍接受 Warcraft 原生 unitstate 枚举值。
---@param exported_state unitstate|nil jass.common 已导出的状态常量
---@param enum_value integer Warcraft 原生 unitstate 枚举编号
---@return unitstate state
local function get_unit_state_enum(exported_state, enum_value)
    if exported_state ~= nil then
        return exported_state
    end
    if type(jass.ConvertUnitState) == "function" then
        return jass.ConvertUnitState(enum_value)
    end
    return enum_value
end

local UNIT_STATE_LIFE = get_unit_state_enum(jass.UNIT_STATE_LIFE, 0)
local UNIT_STATE_MAX_LIFE = get_unit_state_enum(jass.UNIT_STATE_MAX_LIFE, 1)
local UNIT_STATE_MANA = get_unit_state_enum(jass.UNIT_STATE_MANA, 2)
local UNIT_STATE_MAX_MANA = get_unit_state_enum(jass.UNIT_STATE_MAX_MANA, 3)

local function rawcode_to_id(rawcode)
    local a, b, c, d = string.byte(rawcode or "", 1, 4)
    if a == nil or b == nil or c == nil or d == nil then
        return nil
    end
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local function sorted_active_player_ids()
    local player_ids = {}
    for player_id in pairs(active_player_by_id) do
        table.insert(player_ids, player_id)
    end
    table.sort(player_ids, function(left, right)
        return left < right
    end)
    return player_ids
end

--- 让所有参与 PVE 的玩家永久拥有商店单位视野。
--- 不使用本地玩家分支，也不在英雄死亡、移动或复活时取消共享。
local function share_shop_vision(shop_unit)
    for _, player_id in ipairs(sorted_active_player_ids()) do
        jass.UnitShareVision(shop_unit, jass.Player(player_id), true)
    end
    return true
end

local function get_local_player_id()
    return sync.get_local_player_id()
end

--- 关闭 Blizzard.j 为中立商店安装的默认购买触发器。
--- 该触发器会在 EVENT_PLAYER_UNIT_SELL_ITEM 后直接 RemoveItemFromStock，
--- 会覆盖物品自身的 stockRegen 补货设置。
local function disable_default_stock_trigger()
    if type(jass.DisableTrigger) ~= "function" then
        return false
    end

    local stock_trigger = rawget(_G, "bj_stockItemPurchased")
    if stock_trigger == nil then
        print("神秘商店提示：未找到 Blizzard 默认库存移除触发器")
        return false
    end

    jass.DisableTrigger(stock_trigger)
    return true
end

local function get_item_rawcode(item_handle)
    if item_handle == nil or type(jass.GetItemTypeId) ~= "function" then
        return nil
    end
    local item_id = jass.GetItemTypeId(item_handle)
    for rawcode in pairs(config.boxByRawcode or {}) do
        if rawcode_to_id(rawcode) == item_id then
            return rawcode
        end
    end
    for rawcode in pairs(config.consumableByRawcode or {}) do
        if rawcode_to_id(rawcode) == item_id then
            return rawcode
        end
    end
    return nil
end

local function get_manipulating_unit()
    if type(jass.GetManipulatingUnit) == "function" then
        return jass.GetManipulatingUnit()
    end
    return nil
end

local function get_manipulated_item()
    if type(jass.GetManipulatedItem) == "function" then
        return jass.GetManipulatedItem()
    end
    return nil
end

local function apply_percent_state(unit_handle, current_state, maximum_state, percent)
    if unit_handle == nil or type(jass.GetUnitState) ~= "function"
        or type(jass.SetUnitState) ~= "function"
        or current_state == nil or maximum_state == nil then
        return false
    end
    local maximum = math.max(0, tonumber(jass.GetUnitState(unit_handle, maximum_state)) or 0)
    local current = math.max(0, tonumber(jass.GetUnitState(unit_handle, current_state)) or 0)
    local amount = math.floor(maximum * math.max(0, math.floor(tonumber(percent) or 0)) / 100)
    if maximum <= 0 or amount <= 0 then
        return false
    end
    jass.SetUnitState(unit_handle, current_state, math.min(maximum, current + amount))
    return true
end

--- Warcraft 1.27 写当前生命优先使用 widget 接口；部分 KKWE Lua 封装下
--- SetUnitState(unit, UNIT_STATE_LIFE, value) 不会可靠刷新英雄当前生命。
---@param unit_handle unit
---@param percent integer
---@return boolean applied
local function apply_health_percent(unit_handle, percent)
    if unit_handle == nil or type(jass.GetUnitState) ~= "function" then
        return false
    end
    local maximum = math.max(0, tonumber(jass.GetUnitState(unit_handle, UNIT_STATE_MAX_LIFE)) or 0)
    local current = type(jass.GetWidgetLife) == "function"
        and math.max(0, tonumber(jass.GetWidgetLife(unit_handle)) or 0)
        or math.max(0, tonumber(jass.GetUnitState(unit_handle, UNIT_STATE_LIFE)) or 0)
    local amount = math.floor(maximum * math.max(0, math.floor(tonumber(percent) or 0)) / 100)
    if maximum <= 0 or amount <= 0 then
        print(string.format("生命药结算失败：当前=%.1f，最大=%.1f，比例=%s", current, maximum, tostring(percent)))
        return false
    end
    local target = math.min(maximum, current + amount)
    if type(jass.SetWidgetLife) == "function" then
        jass.SetWidgetLife(unit_handle, target)
    elseif type(jass.SetUnitState) == "function" then
        jass.SetUnitState(unit_handle, UNIT_STATE_LIFE, target)
    else
        print("生命药结算失败：缺少 SetWidgetLife/SetUnitState")
        return false
    end

    local actual = type(jass.GetWidgetLife) == "function"
        and math.max(0, tonumber(jass.GetWidgetLife(unit_handle)) or 0)
        or math.max(0, tonumber(jass.GetUnitState(unit_handle, UNIT_STATE_LIFE)) or 0)
    if target > current + 0.001 and actual <= current + 0.001 then
        print(string.format("生命药写入失败：当前=%.1f，目标=%.1f，写后=%.1f，最大=%.1f", current, target, actual, maximum))
        return false
    end
    return true
end

local function is_alive(unit_handle)
    if unit_handle == nil then
        return false
    end
    if type(jass.GetWidgetLife) == "function" then
        return (tonumber(jass.GetWidgetLife(unit_handle)) or 0) > 0.405
    end
    if type(jass.GetUnitState) ~= "function" then
        return false
    end
    return (tonumber(jass.GetUnitState(unit_handle, UNIT_STATE_LIFE)) or 0) > 0.405
end

--- 按施放单位所属玩家取得本局实际英雄。
--- 不读取一次性药水的物品句柄：该句柄可能在原生效果阶段已被销毁。
---@param carrier unit 施放药水技能的单位（英雄、物品栏代理或信使）
---@return integer|nil player_id
---@return unit|nil hero
local function get_consumable_owner(carrier)
    if carrier ~= nil and type(jass.GetOwningPlayer) == "function" and type(jass.GetPlayerId) == "function" then
        local owner = jass.GetOwningPlayer(carrier)
        local player_id = owner ~= nil and jass.GetPlayerId(owner) or nil
        local hero = player_id ~= nil and hero_by_player[player_id] or nil
        if player_id ~= nil and active_player_by_id[player_id] and hero ~= nil then
            return player_id, hero
        end
    end

    -- 兼容无法读取所属玩家的旧运行时，以及特殊物品栏载体。
    local inventory_owner = equipment_instance.get_inventory_owner(carrier)
    if inventory_owner ~= nil then
        local player_id = equipment_instance.get_player_id(inventory_owner)
        if player_id ~= nil and active_player_by_id[player_id] and hero_by_player[player_id] == inventory_owner then
            return player_id, inventory_owner
        end
    end
    local courier_owner = courier.get_hero(carrier)
    if courier_owner ~= nil then
        local player_id = equipment_instance.get_player_id(courier_owner)
        if player_id ~= nil and active_player_by_id[player_id] and hero_by_player[player_id] == courier_owner then
            return player_id, courier_owner
        end
    end
    return nil, nil
end

--- Warcraft 原生“使用物品”事件入口。
--- 必须使用 GetManipulatingUnit/GetManipulatedItem 读取该事件的响应对象；
--- GetTriggerUnit 在旧版 KKWE 对该事件不保证返回使用者。
local function on_consumable_use()
    if not enabled then
        return
    end
    local carrier = get_manipulating_unit()
    local item_handle = get_manipulated_item()
    if carrier == nil or item_handle == nil then
        return
    end
    local item_rawcode = get_item_rawcode(item_handle)
    local consumable = item_rawcode and config.consumableByRawcode[item_rawcode] or nil
    if consumable == nil or consumable.enabled ~= 1 then
        return
    end
    local _, hero = get_consumable_owner(carrier)
    if hero == nil or not is_alive(hero) then
        return
    end
    if consumable.kind == "health" then
        apply_health_percent(hero, consumable.healPercent)
    elseif consumable.kind == "mana" then
        apply_percent_state(hero, UNIT_STATE_MANA, UNIT_STATE_MAX_MANA, consumable.manaPercent)
    end
end

local function parse_result(parts)
    local result = box_result.decode(parts)
    if result == nil then
        return nil
    end
    if processed_events[result.eventId] or processed_uids[result.uid] or equipment_instance.get_by_uid(result.uid) ~= nil then
        return nil
    end
    local hero = hero_by_player[result.playerId]
    local item = item_config[result.rawcode]
    if not active_player_by_id[result.playerId] or hero == nil or item == nil or item.isEquipment ~= 1 then return nil end
    result.hero = hero
    return result
end

local function on_sync_message(message, sender_id)
    if sender_id ~= nil and sender_id ~= 0 then
        return
    end
    local parts = sync.split(message or "", "|")
    local result = parse_result(parts)
    if result == nil then
        return
    end
    local created = equipment.add_instance_to_hero(result.hero, result, result.x, result.y)
    if created then
        processed_events[result.eventId] = true
        processed_uids[result.uid] = true
    end
end

local function sorted_values(values, key)
    local result = {}
    for _, value in pairs(values or {}) do
        table.insert(result, value)
    end
    table.sort(result, function(left, right)
        return tostring(left[key]) < tostring(right[key])
    end)
    return result
end

local function create_shops()
    if type(jass.CreateUnit) ~= "function" or type(jass.Player) ~= "function" then
        return false
    end
    if type(jass.UnitShareVision) ~= "function" then
        print("神秘商店启动失败：当前运行时缺少 UnitShareVision 接口，无法保证玩家拥有商店视野")
        return false
    end
    if type(jass.AddItemToStock) ~= "function" then
        print("神秘商店启动失败：缺少 AddItemToStock 原生接口")
        return false
    end
    for _, shop in ipairs(sorted_values(config.shops, "shopId")) do
        if shop.enabled == 1 then
            local unit_id = rawcode_to_id(shop.unitRawcode)
            if unit_id == nil then
                print("神秘商店启动失败：单位 Rawcode 无效：" .. tostring(shop.unitRawcode))
                return false
            end
            local shop_unit = jass.CreateUnit(
                jass.Player(NEUTRAL_PASSIVE_PLAYER_ID),
                unit_id,
                tonumber(shop.x) or 0,
                tonumber(shop.y) or 0,
                tonumber(shop.facing) or 270
            )
            if shop_unit == nil then
                print("神秘商店启动失败：无法创建商店：" .. tostring(shop.shopId))
                return false
            end
            shop_by_unit[shop_unit] = shop.shopId
            share_shop_vision(shop_unit)
            for _, stock in ipairs(sorted_values(config.stock, "stockId")) do
                if stock.shopId == shop.shopId and stock.enabled == 1 then
                    local item_id = rawcode_to_id(stock.itemRawcode)
                    if item_id == nil then
                        print("神秘商店启动失败：装备箱 Rawcode 无效：" .. tostring(stock.itemRawcode))
                        return false
                    end
                    local initial_stock = math.max(0, tonumber(stock.initialStock) or DEFAULT_STOCK)
                    local max_stock = math.max(initial_stock, tonumber(stock.maxStock) or DEFAULT_STOCK)
                    jass.AddItemToStock(
                        shop_unit,
                        item_id,
                        initial_stock,
                        max_stock
                    )
                end
            end
        end
    end
    return true
end

local function on_sell()
    if not enabled then
        return
    end
    local shop_unit = type(jass.GetSellingUnit) == "function" and jass.GetSellingUnit() or nil
    local buyer = type(jass.GetBuyingUnit) == "function" and jass.GetBuyingUnit() or nil
    local sold_item = type(jass.GetSoldItem) == "function" and jass.GetSoldItem() or nil
    if shop_unit == nil or buyer == nil or sold_item == nil or shop_by_unit[shop_unit] == nil then
        return
    end
    if processed_items[sold_item] then
        return
    end
    local player_id = equipment_instance.get_player_id(buyer)
    if player_id == nil or not active_player_by_id[player_id] or hero_by_player[player_id] ~= buyer then
        return
    end
    local box_rawcode = get_item_rawcode(sold_item)
    local box_level = box_rawcode and config.boxByRawcode[box_rawcode] or nil
    if box_level == nil or box_level < 1 or box_level > 3 then
        return
    end
    processed_items[sold_item] = true
    -- 这里只消耗购买者拿到的装备箱实例；商店库存不在这里删除，
    -- 由原生 stockRegen 在 1 秒后恢复。
    if type(jass.RemoveItem) == "function" then
        jass.RemoveItem(sold_item)
    end
    if not sync.is_host() then
        return
    end

    event_sequence = event_sequence + 1
    local equipment_data = equipment.create_instance(box_level, nil)
    if equipment_data == nil then
        print("神秘商店开箱失败：无法生成等级 " .. tostring(box_level) .. " 装备")
        return
    end
    local x = type(jass.GetUnitX) == "function" and jass.GetUnitX(buyer) or 0
    local y = type(jass.GetUnitY) == "function" and jass.GetUnitY(buyer) or 0
    sync.broadcast(box_result.encode(event_sequence, player_id, equipment_data, x, y))
end

local function register_sell_event()
    if type(jass.CreateTrigger) ~= "function" or type(jass.TriggerRegisterPlayerUnitEvent) ~= "function" then
        return false
    end
    sell_trigger = jass.CreateTrigger()
    if runtime_scope ~= nil then resource_api.trigger(runtime_scope, sell_trigger) end
    -- EVENT_PLAYER_UNIT_SELL_ITEM 按出售单位所有者归属触发。
    -- 神秘商店由中立被动玩家(15)拥有，不能按购买英雄所属玩家注册。
    jass.TriggerRegisterPlayerUnitEvent(
        sell_trigger,
        jass.Player(NEUTRAL_PASSIVE_PLAYER_ID),
        jass.EVENT_PLAYER_UNIT_SELL_ITEM,
        nil
    )
    jass.TriggerAddAction(sell_trigger, on_sell)
    return true
end

local function register_consumable_use_event()
    if type(jass.CreateTrigger) ~= "function"
        or type(jass.TriggerRegisterPlayerUnitEvent) ~= "function"
        or type(jass.TriggerAddAction) ~= "function"
        or jass.EVENT_PLAYER_UNIT_USE_ITEM == nil
        or type(jass.GetManipulatingUnit) ~= "function"
        or type(jass.GetManipulatedItem) ~= "function"
        or type(jass.GetItemTypeId) ~= "function"
        or type(jass.GetOwningPlayer) ~= "function"
        or type(jass.GetPlayerId) ~= "function"
        or type(jass.GetUnitState) ~= "function"
        or type(jass.SetUnitState) ~= "function" then
        print("神秘商店启动失败：缺少药水使用事件所需的原生接口")
        return false
    end
    consumable_use_trigger = jass.CreateTrigger()
    if runtime_scope ~= nil then resource_api.trigger(runtime_scope, consumable_use_trigger) end
    for _, player_id in ipairs(sorted_active_player_ids()) do
        jass.TriggerRegisterPlayerUnitEvent(
            consumable_use_trigger,
            jass.Player(player_id),
            jass.EVENT_PLAYER_UNIT_USE_ITEM,
            nil
        )
    end
    jass.TriggerAddAction(consumable_use_trigger, on_consumable_use)
    return true
end

--- 启动四个区域神秘商店。
---@param hero_results HeroSelectionResult[] 参与玩家的英雄结果
---@return boolean started_now 是否完成启动
function module.start(hero_results)
    if started then
        return false
    end
    runtime_scope = lifecycle and lifecycle.acquire("mysteryShop.main", function()
        started, enabled, sell_trigger, consumable_use_trigger = false, false, nil, nil
        event_sequence, shop_by_unit, active_player_by_id, hero_by_player = 0, {}, {}, {}
        processed_items, processed_events, processed_uids = {}, {}, {}
        sync.stop()
    end) or nil
    hero_results = hero_results or {}
    local active_count = 0
    for _, result in ipairs(hero_results) do
        if not active_player_by_id[result.playerId] then
            active_player_by_id[result.playerId] = true
            hero_by_player[result.playerId] = result.unit
            active_count = active_count + 1
        end
    end
    active_count = math.max(1, active_count)
    local sync_available = sync.start(on_sync_message)
    if not sync_available and active_count > 1 then
        print("神秘商店已禁用关键逻辑：多人模式缺少同步接口")
        return false
    end
    disable_default_stock_trigger()
    if not create_shops() or not register_sell_event() or not register_consumable_use_event() then
        return false
    end
    enabled = true
    started = true
    print(string.format("神秘商店已启动：商店=%d，同步=%s", #sorted_values(config.shops, "shopId"), tostring(sync_available)))
    return true
end

function module.stop()
    return lifecycle ~= nil and lifecycle.release("mysteryShop.main") or false
end

---@return boolean started 是否已启动
function module.is_started()
    return started
end

---@return integer playerId 当前本地玩家编号
function module.get_local_player_id()
    return get_local_player_id()
end

module.handle_sell = on_sell
module.handle_consumable_use = on_consumable_use

JiuDou.publish("gameplay.mysteryShop.main", module)
return module
