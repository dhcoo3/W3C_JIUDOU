--- 第 1、2 格装备合成。
--- 本地快捷键只发送请求；房主重新读取物品栏并广播完整合成结果。
local jass = require "jass.common"
local config = require "config.items"
local instance = require "equipment.instance"
local generator = require "equipment.generator"

local module = {}
local sync_module = nil
local on_changed = nil
local on_failure = nil
local enabled = true
local next_request_id = 0
local next_merge_uid = 5000000
local processed_requests = {}
local processed_results = {}
local key_trigger = nil
local MERGE_KEY_F2 = 113
local KEY_DOWN = 1

local function rawcode_to_id(rawcode)
    local a, b, c, d = string.byte(rawcode or "", 1, 4)
    if a == nil or b == nil or c == nil or d == nil then
        return nil
    end
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local function join_passives(passives)
    if passives == nil or #passives == 0 then
        return "-"
    end
    return table.concat(passives, ",")
end

local function encode_result(request_id, player_id, first_uid, second_uid, equipment)
    return table.concat({
        "MERGE_RESULT", "3", tostring(request_id), tostring(player_id), tostring(first_uid), tostring(second_uid),
        tostring(equipment.uid), equipment.rawcode, equipment.templateId or "-", tostring(equipment.level),
        tostring(equipment.stats.attack), tostring(equipment.stats.health), tostring(equipment.stats.armor),
        tostring(equipment.stats.basicAttackBonusPercent or 0), tostring(equipment.stats.healthAmplificationPercent or 0),
        equipment.autoSkillId or "-", join_passives(equipment.passiveSkillIds), equipment.comboSetId or "-", equipment.comboPieceId or "-",
    }, "|")
end

local function report_failure(player_id, reason)
    if on_failure ~= nil then
        on_failure(player_id, reason)
    else
        print("装备合成失败：" .. tostring(reason))
    end
end

local function remove_material(hero, item_handle)
    if item_handle == nil then
        return
    end
    instance.unbind_item(item_handle)
    if type(jass.UnitRemoveItem) == "function" then
        jass.UnitRemoveItem(hero, item_handle)
    end
    if type(jass.RemoveItem) == "function" then
        jass.RemoveItem(item_handle)
    end
end

local function restore_material(hero, slot, equipment)
    local item_id = rawcode_to_id(equipment.rawcode)
    if item_id == nil then
        return false
    end
    local item_handle = nil
    if type(jass.UnitAddItemToSlotById) == "function" then
        local ok = jass.UnitAddItemToSlotById(hero, item_id, slot)
        if ok then
            item_handle = instance.get_item_in_slot(hero, slot)
        end
    elseif type(jass.CreateItem) == "function" and type(jass.UnitAddItem) == "function" then
        item_handle = jass.CreateItem(item_id, jass.GetUnitX(hero), jass.GetUnitY(hero))
        if item_handle ~= nil then
            jass.UnitAddItem(hero, item_handle)
        end
    end
    if item_handle == nil then
        return false
    end
    instance.bind_item(item_handle, equipment)
    return true
end

local function add_result_to_slot(hero, equipment)
    local item_id = rawcode_to_id(equipment.rawcode)
    if item_id == nil then
        return nil
    end
    local item_handle = nil
    if type(jass.UnitAddItemToSlotById) == "function" then
        if jass.UnitAddItemToSlotById(hero, item_id, 0) then
            item_handle = instance.get_item_in_slot(hero, 0)
        end
    elseif type(jass.CreateItem) == "function" and type(jass.UnitAddItem) == "function" then
        item_handle = jass.CreateItem(item_id, jass.GetUnitX(hero), jass.GetUnitY(hero))
        if item_handle ~= nil and not jass.UnitAddItem(hero, item_handle) then
            jass.RemoveItem(item_handle)
            item_handle = nil
        end
        item_handle = item_handle or instance.get_item_in_slot(hero, 0)
    end
    if item_handle ~= nil then
        instance.bind_item(item_handle, equipment)
    end
    return item_handle
end

local function handle_request(parts, sender_id)
    if #parts ~= 6 or not module.is_host() then
        return
    end
    local request_id = tonumber(parts[3])
    local player_id = tonumber(parts[4])
    local first_uid = tonumber(parts[5])
    local second_uid = tonumber(parts[6])
    if request_id == nil or player_id == nil or first_uid == nil or second_uid == nil
        or player_id < 0 or player_id > 15 or sender_id ~= nil and sender_id ~= player_id then
        return
    end
    local request_key = tostring(player_id) .. ":" .. tostring(request_id)
    if processed_requests[request_key] then
        return
    end
    processed_requests[request_key] = true
    local hero = instance.get_hero_by_player(player_id)
    if hero == nil then
        report_failure(player_id, "找不到玩家英雄")
        return
    end
    local first_item = instance.get_item_in_slot(hero, 0)
    local second_item = instance.get_item_in_slot(hero, 1)
    local first = first_item and instance.get_by_item(first_item) or nil
    local second = second_item and instance.get_by_item(second_item) or nil
    if first == nil or second == nil or first.uid ~= first_uid or second.uid ~= second_uid then
        report_failure(player_id, "第1、2格装备已变化")
        return
    end
    if first.level ~= second.level or first.level >= 5 then
        report_failure(player_id, "需要两件同级且低于5级的装备")
        return
    end
    local first_config = config[first.rawcode]
    local second_config = config[second.rawcode]
    if first_config == nil or second_config == nil or first_config.mergeable ~= 1 or second_config.mergeable ~= 1 then
        report_failure(player_id, "材料不是可合成装备")
        return
    end
    next_merge_uid = next_merge_uid + 1
    local result = generator.create_merge(first.level, next_merge_uid, request_id + player_id * 1000)
    if result == nil then
        report_failure(player_id, "合成结果生成失败")
        return
    end
    local message = encode_result(request_id, player_id, first.uid, second.uid, result)
    sync_module.broadcast(message)
end

local function handle_result(parts)
    if #parts ~= 19 or parts[2] ~= "3" then
        return
    end
    local request_id = tonumber(parts[3])
    local player_id = tonumber(parts[4])
    local first_uid = tonumber(parts[5])
    local second_uid = tonumber(parts[6])
    local uid = tonumber(parts[7])
    local level = tonumber(parts[10])
    if request_id == nil or player_id == nil or first_uid == nil or second_uid == nil or uid == nil or level == nil then
        return
    end
    local result_key = tostring(player_id) .. ":" .. tostring(request_id)
    if processed_results[result_key] then
        return
    end
    processed_results[result_key] = true
    if instance.get_by_uid(uid) ~= nil then
        return
    end
    local hero = instance.get_hero_by_player(player_id)
    if hero == nil then
        return
    end
    local first_item = instance.get_item_in_slot(hero, 0)
    local second_item = instance.get_item_in_slot(hero, 1)
    local first = first_item and instance.get_by_item(first_item) or nil
    local second = second_item and instance.get_by_item(second_item) or nil
    if first == nil or second == nil or first.uid ~= first_uid or second.uid ~= second_uid then
        print("忽略装备合成结果：本地材料状态不一致")
        return
    end
    local passive_ids = {}
    if parts[17] ~= "-" and parts[17] ~= "" then
        for passive_id in string.gmatch(parts[17], "[^,]+") do
            table.insert(passive_ids, passive_id)
        end
    end
    local result = instance.create({
        uid = uid,
        rawcode = parts[8],
        templateId = parts[9] == "-" and "" or parts[9],
        level = level,
        stats = {
            attack = tonumber(parts[11]) or 0,
            health = tonumber(parts[12]) or 0,
            armor = tonumber(parts[13]) or 0,
            basicAttackBonusPercent = tonumber(parts[14]) or 0,
            healthAmplificationPercent = tonumber(parts[15]) or 0,
        },
        autoSkillId = parts[16] == "-" and nil or parts[16],
        passiveSkillIds = passive_ids,
        comboSetId = parts[18] == "-" and nil or parts[18],
        comboPieceId = parts[19] == "-" and nil or parts[19],
    })
    remove_material(hero, first_item)
    remove_material(hero, second_item)
    local result_item = add_result_to_slot(hero, result)
    if result_item == nil then
        restore_material(hero, 0, first)
        restore_material(hero, 1, second)
        report_failure(player_id, "结果无法放入第1格，材料已尝试恢复")
        return
    end
    instance.refresh_inventory(hero)
    if on_changed ~= nil then
        on_changed(hero, result, "merge")
    end
end

--- 处理同步消息。
---@param parts string[] 已按 | 分割的消息
---@param sender_id integer|nil 发送玩家
function module.handle_sync(parts, sender_id)
    if parts[1] == "MERGE_REQUEST" and parts[2] == "2" then
        handle_request(parts, sender_id)
    elseif parts[1] == "MERGE_RESULT" and parts[2] == "3" then
        if sender_id == nil or sender_id == 0 then
            handle_result(parts)
        end
    end
end

--- 本地请求第 1、2 格合成。
---@return boolean sent 是否发送了请求
function module.request_merge()
    if not enabled or sync_module == nil then
        return false
    end
    local player_id = sync_module.get_local_player_id()
    local hero = instance.get_hero_by_player(player_id)
    if hero == nil then
        return false
    end
    local first = instance.get_by_item(instance.get_item_in_slot(hero, 0))
    local second = instance.get_by_item(instance.get_item_in_slot(hero, 1))
    if first == nil or second == nil then
        report_failure(player_id, "请把两件装备放入第1、2格")
        return false
    end
    next_request_id = next_request_id + 1
    local message = string.format("MERGE_REQUEST|2|%d|%d|%d|%d", next_request_id, player_id, first.uid, second.uid)
    sync_module.send_request(message)
    return true
end

local function register_hotkey()
    local loaded, japi = pcall(require, "jass.japi")
    if not loaded or type(japi) ~= "table" then
        print("装备合成快捷键未注册：当前运行时没有 jass.japi")
        return false
    end
    key_trigger = jass.CreateTrigger()

    -- F2 的 JAPI 按键码为 113。按键只在本地捕获，再发送合成同步请求。
    local callback = function()
        module.request_merge()
    end
    local registered = false

    if type(japi.DzTriggerRegisterKeyEventByCode) == "function" then
        registered = pcall(function()
            japi.DzTriggerRegisterKeyEventByCode(key_trigger, MERGE_KEY_F2, KEY_DOWN, false, callback)
        end)
    elseif type(japi.DzTriggerRegisterKeyEvent) == "function" then
        -- 兼容只有字符串回调版本的旧 JAPI；全局引用用于保证回调在游戏期间不被回收。
        _G.JiuDouEquipmentMergeHotkey = callback
        registered = pcall(function()
            japi.DzTriggerRegisterKeyEvent(key_trigger, MERGE_KEY_F2, KEY_DOWN, false, "JiuDouEquipmentMergeHotkey")
        end)
    end

    if not registered then
        print("装备合成快捷键注册失败：F2 的 DzTriggerRegisterKeyEvent 接口不可用")
        return false
    end
    print("装备合成快捷键已注册：F2")
    return true
end

--- 启动合成请求和结果处理。
---@param heroes HeroSelectionResult[] 英雄结果
---@param sync_adapter table 装备同步模块
---@param allow boolean 是否允许合成
---@param changed fun(hero:unit, equipment:EquipmentInstance, reason:string) 生效回调
---@param failure fun(playerId:integer, reason:string) 失败回调
function module.start(heroes, sync_adapter, allow, changed, failure)
    sync_module = sync_adapter
    enabled = allow ~= false
    on_changed = changed
    on_failure = failure
    if enabled then
        register_hotkey()
    end
    return enabled
end

module.is_host = function()
    return sync_module ~= nil and sync_module.is_host()
end

return module
