--- 四区域神秘商店。
--- 商店库存和价格由 Warcraft 原生商店处理；购买装备箱后由房主确定装备结果，
--- 再把完整实例同步给所有客户端，避免各客户端重新随机出不同装备。
local jass = require "jass.common"
local config = require "config.mystery_shop"
local item_config = require "config.items"
local equipment = require "equipment.main"
local equipment_instance = require "equipment.instance"
local sync = require "mysteryShop.sync"

local module = {}
local started = false
local enabled = false
local sell_trigger = nil
local event_sequence = 0
local shop_by_unit = {}
local active_player_by_id = {}
local hero_by_player = {}
local processed_items = {}
local processed_events = {}
local processed_uids = {}

local NEUTRAL_PASSIVE_PLAYER_ID = 15
local DEFAULT_STOCK = 1
local RESULT_PART_COUNT = 19

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

    local stock_trigger = nil
    local loaded, globals = pcall(require, "jass.globals")
    if loaded and type(globals) == "table" then
        stock_trigger = globals.bj_stockItemPurchased
    end
    if stock_trigger == nil then
        stock_trigger = rawget(_G, "bj_stockItemPurchased")
    end
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
    return nil
end

local function join_passives(passives)
    if passives == nil or #passives == 0 then
        return "-"
    end
    return table.concat(passives, ",")
end

local function encode_result(event_id, player_id, equipment_data, x, y)
    return table.concat({
        "MYSTERY_BOX_RESULT", "2", tostring(event_id), tostring(player_id),
        tostring(equipment_data.uid), equipment_data.rawcode,
        equipment_data.templateId ~= nil and equipment_data.templateId ~= "" and equipment_data.templateId or "-",
        tostring(equipment_data.level), tostring(equipment_data.stats.attack),
        tostring(equipment_data.stats.health), tostring(equipment_data.stats.armor),
        tostring(equipment_data.stats.basicAttackBonusPercent or 0), tostring(equipment_data.stats.healthAmplificationPercent or 0),
        equipment_data.autoSkillId or "-", join_passives(equipment_data.passiveSkillIds),
        equipment_data.comboSetId or "-", equipment_data.comboPieceId or "-",
        tostring(math.floor(tonumber(x) or 0)), tostring(math.floor(tonumber(y) or 0)),
    }, "|")
end

local function parse_passives(value)
    local result = {}
    if value == nil or value == "" or value == "-" then
        return result
    end
    for passive_id in string.gmatch(value, "[^,]+") do
        if passive_id ~= "-" and passive_id ~= "" then
            table.insert(result, passive_id)
        end
    end
    return result
end

local function parse_result(parts)
    if #parts ~= RESULT_PART_COUNT or parts[1] ~= "MYSTERY_BOX_RESULT" or parts[2] ~= "2" then
        return nil
    end
    local event_id = tonumber(parts[3])
    local player_id = tonumber(parts[4])
    local uid = tonumber(parts[5])
    local level = tonumber(parts[8])
    local attack = tonumber(parts[9])
    local health = tonumber(parts[10])
    local armor = tonumber(parts[11])
    local x = tonumber(parts[18])
    local y = tonumber(parts[19])
    if event_id == nil or player_id == nil or uid == nil or level == nil
        or attack == nil or health == nil or armor == nil or x == nil or y == nil then
        return nil
    end
    event_id = math.floor(event_id)
    player_id = math.floor(player_id)
    uid = math.floor(uid)
    level = math.floor(level)
    if event_id <= 0 or uid <= 0 or player_id < 0 or player_id > 11 or level < 1 or level > 5 then
        return nil
    end
    if processed_events[event_id] or processed_uids[uid] or equipment_instance.get_by_uid(uid) ~= nil then
        return nil
    end
    local hero = hero_by_player[player_id]
    local rawcode = parts[6]
    local item = item_config[rawcode]
    if not active_player_by_id[player_id] or hero == nil or item == nil or item.isEquipment ~= 1 then
        return nil
    end
    return {
        eventId = event_id,
        playerId = player_id,
        hero = hero,
        uid = uid,
        rawcode = rawcode,
        templateId = parts[7] == "-" and "" or parts[7],
        level = level,
        stats = {
            attack = math.floor(attack),
            health = math.floor(health),
            armor = math.floor(armor),
            basicAttackBonusPercent = tonumber(parts[12]) or 0,
            healthAmplificationPercent = tonumber(parts[13]) or 0,
        },
        autoSkillId = parts[14] == "-" and nil or parts[14],
        passiveSkillIds = parse_passives(parts[15]),
        comboSetId = parts[16] == "-" and nil or parts[16],
        comboPieceId = parts[17] == "-" and nil or parts[17],
        x = x,
        y = y,
    }
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
    sync.broadcast(encode_result(event_sequence, player_id, equipment_data, x, y))
end

local function register_sell_event()
    if type(jass.CreateTrigger) ~= "function" or type(jass.TriggerRegisterPlayerUnitEvent) ~= "function" then
        return false
    end
    sell_trigger = jass.CreateTrigger()
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

--- 启动四个区域神秘商店。
---@param hero_results HeroSelectionResult[] 参与玩家的英雄结果
---@return boolean started_now 是否完成启动
function module.start(hero_results)
    if started then
        return false
    end
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
    if not create_shops() or not register_sell_event() then
        return false
    end
    enabled = true
    started = true
    print(string.format("神秘商店已启动：商店=%d，同步=%s", #sorted_values(config.shops, "shopId"), tostring(sync_available)))
    return true
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

return module
