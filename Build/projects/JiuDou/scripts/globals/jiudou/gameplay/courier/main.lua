--- 玩家专属飞行信使。
--- 信使使用原生 6 格物品栏，可携带任意物品；范围合成只处理地面的已绑定装备实例。
--- 合成结果由房主生成并分批同步，避免大量物品时同步消息过长。
local jass = require "jass.common"
local item_config = require "config.items"
local equipment_instance = require "equipment.instance"
local equipment_generator = require "equipment.generator"
local fusion_protocol = require "courier.fusion_protocol"

local module = {}

local COURIER_RAWCODE = "F0B0"
local FOLLOW_RAWCODE = "A9T4"
local FUSION_RAWCODE = "A9T5"
local CROW_FORM_RAWCODE = "Amrf"
local FUSION_RADIUS = 300
local FUSION_MAX_LEVEL = 5
local FUSION_OUTPUT_SPACING = 72
local MAX_MATERIAL_MESSAGE_LENGTH = 220

local COURIER_ID = nil
local FOLLOW_ID = nil
local FUSION_ID = nil
local CROW_FORM_ID = nil
local started = false
local fusion_enabled = false
local local_fallback = false
local sync_module = nil
local spell_trigger = nil
local next_batch_id = 0
local next_equipment_uid = 6000000
local next_fusion_serial = 0
local processed_batches = {}
local pending_batches = {}

---@type table<integer, unit>
local courier_by_player = {}
---@type table<unit, integer>
local player_by_courier = {}
---@type table<unit, unit>
local hero_by_courier = {}

local function rawcode_to_id(rawcode)
    if type(rawcode) ~= "string" or #rawcode ~= 4 then
        return nil
    end
    local a, b, c, d = string.byte(rawcode, 1, 4)
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local function get_local_player_id()
    if type(jass.GetLocalPlayer) ~= "function" or type(jass.GetPlayerId) ~= "function" then
        return 0
    end
    return jass.GetPlayerId(jass.GetLocalPlayer())
end

local function is_alive(unit_handle)
    if unit_handle == nil then
        return false
    end
    if type(jass.GetUnitState) ~= "function" or jass.UNIT_STATE_LIFE == nil then
        return true
    end
    return (jass.GetUnitState(unit_handle, jass.UNIT_STATE_LIFE) or 0) > 0.405
end

local function add_effect(path, x, y)
    if type(jass.AddSpecialEffect) ~= "function" then
        return
    end
    local effect = jass.AddSpecialEffect(path, x, y)
    if effect ~= nil and type(jass.DestroyEffect) == "function" then
        jass.DestroyEffect(effect)
    end
end

local function announce_to_player(player_id, message)
    if player_id ~= get_local_player_id() or type(jass.DisplayTimedTextToPlayer) ~= "function"
        or type(jass.GetLocalPlayer) ~= "function" then
        return
    end
    jass.DisplayTimedTextToPlayer(jass.GetLocalPlayer(), 0, 0, 3.0, message)
end

local function is_authority()
    if sync_module ~= nil and sync_module.is_available() then
        return sync_module.is_host()
    end
    return local_fallback
end

local function is_trusted_sender(sender_id)
    return sender_id == nil or sender_id == 0 or local_fallback and sender_id == get_local_player_id()
end

local function is_courier(unit_handle)
    return unit_handle ~= nil and player_by_courier[unit_handle] ~= nil
end

local function is_mergeable_equipment(equipment)
    if equipment == nil or equipment.item == nil then
        return false
    end
    if equipment.level == nil or equipment.level < 1 or equipment.level >= FUSION_MAX_LEVEL then
        return false
    end
    local config = item_config[equipment.rawcode]
    return config ~= nil and config.isEquipment == 1 and config.mergeable == 1
end

local function sort_entries(entries)
    table.sort(entries, function(left, right)
        local left_uid = tonumber(left.equipment and left.equipment.uid) or 0
        local right_uid = tonumber(right.equipment and right.equipment.uid) or 0
        if left_uid ~= right_uid then
            return left_uid < right_uid
        end
        return tostring(left.equipment and left.equipment.item) < tostring(right.equipment and right.equipment.item)
    end)
end

--- 扫描目标圆形范围内的地面可合成装备。
---@param x number 中心 X 坐标
---@param y number 中心 Y 坐标
---@return table<integer, table> buckets 按装备等级分组的材料
local function collect_ground_equipment(x, y)
    local buckets = {}
    for level = 1, FUSION_MAX_LEVEL do
        buckets[level] = {}
    end
    if type(jass.Rect) ~= "function" or type(jass.EnumItemsInRect) ~= "function"
        or type(jass.GetEnumItem) ~= "function" or type(jass.GetItemX) ~= "function"
        or type(jass.GetItemY) ~= "function" then
        return buckets
    end
    local rect = jass.Rect(x - FUSION_RADIUS, y - FUSION_RADIUS, x + FUSION_RADIUS, y + FUSION_RADIUS)
    if rect == nil then
        return buckets
    end
    local radius_squared = FUSION_RADIUS * FUSION_RADIUS
    jass.EnumItemsInRect(rect, nil, function()
        local item_handle = jass.GetEnumItem()
        local item_x = jass.GetItemX(item_handle)
        local item_y = jass.GetItemY(item_handle)
        local dx = item_x - x
        local dy = item_y - y
        if dx * dx + dy * dy > radius_squared then
            return
        end
        local equipment = equipment_instance.get_by_item(item_handle)
        if not is_mergeable_equipment(equipment) then
            return
        end
        table.insert(buckets[equipment.level], {
            equipment = equipment,
            sourceUids = {equipment.uid},
            generated = false,
        })
    end)
    if type(jass.RemoveRect) == "function" then
        jass.RemoveRect(rect)
    end
    for level = 1, FUSION_MAX_LEVEL do
        sort_entries(buckets[level])
    end
    return buckets
end

local function reserve_equipment_uid()
    repeat
        next_equipment_uid = next_equipment_uid + 1
    until equipment_instance.get_by_uid(next_equipment_uid) == nil
    return next_equipment_uid
end

local function merge_source_uids(left, right)
    local result = {}
    for _, uid in ipairs(left.sourceUids or {}) do
        table.insert(result, uid)
    end
    for _, uid in ipairs(right.sourceUids or {}) do
        table.insert(result, uid)
    end
    table.sort(result)
    return result
end

--- 构建本次施法的最终材料与结果；中间产物仅用于同次递归计算，不会落地。
---@param target_x number 技能目标 X 坐标
---@param target_y number 技能目标 Y 坐标
---@return integer[] material_uids 最终需要移除的初始材料 UID
---@return table[] outputs 最终掉落的装备实例
local function build_fusion_plan(target_x, target_y)
    local buckets = collect_ground_equipment(target_x, target_y)
    next_fusion_serial = next_fusion_serial + 1
    local serial_base = next_fusion_serial * 1000
    local merge_index = 0

    for level = 1, FUSION_MAX_LEVEL - 1 do
        local bucket = buckets[level]
        sort_entries(bucket)
        while #bucket >= 2 do
            local first = table.remove(bucket, 1)
            local second = table.remove(bucket, 1)
            merge_index = merge_index + 1
            local result = equipment_generator.create_merge(
                level,
                reserve_equipment_uid(),
                serial_base + merge_index
            )
            if result == nil then
                table.insert(bucket, 1, second)
                table.insert(bucket, 1, first)
                break
            end
            local entry = {
                equipment = result,
                sourceUids = merge_source_uids(first, second),
                generated = true,
            }
            table.insert(buckets[level + 1], entry)
        end
    end

    local final_entries = {}
    for level = 2, FUSION_MAX_LEVEL do
        for _, entry in ipairs(buckets[level]) do
            if entry.generated then
                table.insert(final_entries, entry)
            end
        end
    end
    table.sort(final_entries, function(left, right)
        return (left.equipment.uid or 0) < (right.equipment.uid or 0)
    end)

    local material_set = {}
    for _, entry in ipairs(final_entries) do
        for _, uid in ipairs(entry.sourceUids or {}) do
            material_set[uid] = true
        end
    end
    local material_uids = {}
    for uid in pairs(material_set) do
        table.insert(material_uids, uid)
    end
    table.sort(material_uids)

    local outputs = {}
    for _, entry in ipairs(final_entries) do
        table.insert(outputs, entry.equipment)
    end
    return material_uids, outputs
end

local function get_output_position(target_x, target_y, index, count)
    if count <= 1 then
        return math.floor(target_x), math.floor(target_y)
    end
    local columns = math.ceil(math.sqrt(count))
    local row = math.floor((index - 1) / columns)
    local column = (index - 1) % columns
    return math.floor(target_x + (column - (columns - 1) / 2) * FUSION_OUTPUT_SPACING),
        math.floor(target_y + (row - (columns - 1) / 2) * FUSION_OUTPUT_SPACING)
end

local function broadcast_materials(batch_id, material_uids)
    for _, message in ipairs(fusion_protocol.encode_materials(batch_id, material_uids, MAX_MATERIAL_MESSAGE_LENGTH)) do
        sync_module.broadcast(message)
    end
end

local function create_fusion_batch(player_id, target_x, target_y)
    local material_uids, outputs = build_fusion_plan(target_x, target_y)
    if #material_uids == 0 or #outputs == 0 then
        return false
    end
    next_batch_id = next_batch_id + 1
    local batch_id = next_batch_id
    sync_module.broadcast(fusion_protocol.encode_begin(batch_id, player_id, #outputs))
    broadcast_materials(batch_id, material_uids)
    for index, equipment in ipairs(outputs) do
        local output_x, output_y = get_output_position(target_x, target_y, index, #outputs)
        sync_module.broadcast(fusion_protocol.encode_output(batch_id, index, equipment, output_x, output_y))
    end
    sync_module.broadcast(fusion_protocol.encode_end(batch_id))
    return true
end

--- 确认物品未在英雄或信使背包中。同步消息抵达前，玩家可能已将地面材料拾起；
--- 此时应取消本批合成，绝不能删除背包内物品。
---@param item_handle item
---@return boolean held
local function is_held_by_registered_unit(item_handle)
    for player_id = 0, 15 do
        local hero = equipment_instance.get_hero_by_player(player_id)
        local courier = courier_by_player[player_id]
        if hero ~= nil then
            for slot = 0, 5 do
                if equipment_instance.get_item_in_slot(hero, slot) == item_handle then
                    return true
                end
            end
        end
        if courier ~= nil then
            for slot = 0, 5 do
                if equipment_instance.get_item_in_slot(courier, slot) == item_handle then
                    return true
                end
            end
        end
    end
    return false
end

local function remove_materials(material_uids)
    for _, uid in ipairs(material_uids) do
        local equipment = equipment_instance.get_by_uid(uid)
        if equipment == nil or equipment.item == nil or is_held_by_registered_unit(equipment.item) then
            return false
        end
    end
    for _, uid in ipairs(material_uids) do
        local equipment = equipment_instance.get_by_uid(uid)
        local item_handle = equipment and equipment.item or nil
        if item_handle ~= nil then
            equipment_instance.unbind_item(item_handle)
            if type(jass.RemoveItem) == "function" then
                jass.RemoveItem(item_handle)
            end
        end
    end
    return true
end

local function create_output(output)
    if output == nil or equipment_instance.get_by_uid(output.uid) ~= nil then
        return false
    end
    local item_id = rawcode_to_id(output.rawcode)
    if item_id == nil or type(jass.CreateItem) ~= "function" then
        return false
    end
    local item_handle = jass.CreateItem(item_id, output.x, output.y)
    if item_handle == nil then
        return false
    end
    local equipment = equipment_instance.create({
        uid = output.uid,
        rawcode = output.rawcode,
        templateId = output.templateId,
        level = output.level,
        stats = output.stats,
        autoSkillId = output.autoSkillId,
        passiveSkillIds = output.passiveSkillIds,
        comboSetId = output.comboSetId,
        comboPieceId = output.comboPieceId,
    })
    equipment_instance.bind_item(item_handle, equipment)
    return true
end

local function apply_fusion_batch(batch_id)
    if processed_batches[batch_id] then
        return
    end
    local batch = pending_batches[batch_id]
    if batch == nil or batch.expectedOutputCount <= 0 or #batch.materialUids <= 0
        or #batch.outputs ~= batch.expectedOutputCount then
        print("飞行信使合成结果不完整：batch=" .. tostring(batch_id))
        pending_batches[batch_id] = nil
        return
    end
    table.sort(batch.outputs, function(left, right)
        return left.index < right.index
    end)
    if not remove_materials(batch.materialUids) then
        print("飞行信使合成取消：地面材料状态不一致，batch=" .. tostring(batch_id))
        pending_batches[batch_id] = nil
        return
    end
    for _, output in ipairs(batch.outputs) do
        if not create_output(output) then
            print("飞行信使合成结果创建失败：uid=" .. tostring(output.uid))
        end
    end
    processed_batches[batch_id] = true
    pending_batches[batch_id] = nil
end

local function handle_sync_begin(parts, sender_id)
    if not is_trusted_sender(sender_id) then return end
    local message = fusion_protocol.decode_begin(parts)
    if message == nil or processed_batches[message.batchId] or pending_batches[message.batchId] ~= nil then
        return
    end
    pending_batches[message.batchId] = {
        playerId = message.playerId,
        expectedOutputCount = message.expectedOutputCount,
        materialUids = {},
        outputs = {},
    }
end

local function handle_sync_materials(parts, sender_id)
    if not is_trusted_sender(sender_id) then return end
    local message = fusion_protocol.decode_materials(parts)
    local batch = message and pending_batches[message.batchId] or nil
    if batch == nil then return end
    for _, uid in ipairs(message.materialUids) do table.insert(batch.materialUids, uid) end
end

local function handle_sync_output(parts, sender_id)
    if not is_trusted_sender(sender_id) then return end
    local incoming_output = fusion_protocol.decode_output(parts)
    local batch = incoming_output and pending_batches[incoming_output.batchId] or nil
    if batch == nil then return end
    for _, existing_output in ipairs(batch.outputs) do
        if existing_output.index == incoming_output.index or existing_output.uid == incoming_output.uid then
            return
        end
    end
    table.insert(batch.outputs, incoming_output)
end

local function handle_sync_end(parts, sender_id)
    if not is_trusted_sender(sender_id) then return end
    local batch_id = fusion_protocol.decode_end(parts)
    if batch_id ~= nil then
        apply_fusion_batch(batch_id)
    end
end

local function follow_hero(courier)
    local hero = hero_by_courier[courier]
    local player_id = player_by_courier[courier]
    if not is_alive(hero) then
        announce_to_player(player_id, "飞行信使：绑定英雄当前不可跟随")
        return false
    end
    local hero_x = jass.GetUnitX(hero)
    local hero_y = jass.GetUnitY(hero)
    local target_x = hero_x + 96
    local target_y = hero_y - 64
    add_effect("Abilities\\Spells\\NightElf\\Blink\\BlinkCaster.mdl", jass.GetUnitX(courier), jass.GetUnitY(courier))
    if type(jass.SetUnitPosition) == "function" then
        jass.SetUnitPosition(courier, target_x, target_y)
    elseif type(jass.SetUnitX) == "function" and type(jass.SetUnitY) == "function" then
        jass.SetUnitX(courier, target_x)
        jass.SetUnitY(courier, target_y)
    end
    add_effect("Abilities\\Spells\\NightElf\\Blink\\BlinkTarget.mdl", jass.GetUnitX(courier), jass.GetUnitY(courier))
    return true
end

local function on_spell_effect()
    local courier = type(jass.GetTriggerUnit) == "function" and jass.GetTriggerUnit() or nil
    if not is_courier(courier) or type(jass.GetSpellAbilityId) ~= "function" then
        return
    end
    local ability_id = jass.GetSpellAbilityId()
    if ability_id == FOLLOW_ID then
        follow_hero(courier)
        return
    end
    if ability_id ~= FUSION_ID then
        return
    end
    local player_id = player_by_courier[courier]
    if not fusion_enabled then
        announce_to_player(player_id, "飞行信使：多人同步不可用，范围合成已禁用")
        return
    end
    if not is_authority() then
        return
    end
    local target_x = type(jass.GetSpellTargetX) == "function" and jass.GetSpellTargetX() or jass.GetUnitX(courier)
    local target_y = type(jass.GetSpellTargetY) == "function" and jass.GetSpellTargetY() or jass.GetUnitY(courier)
    create_fusion_batch(player_id, target_x, target_y)
end

local function create_courier(player_id, hero)
    if courier_by_player[player_id] ~= nil or COURIER_ID == nil or hero == nil then
        return courier_by_player[player_id]
    end
    local x = jass.GetUnitX(hero) + 96
    local y = jass.GetUnitY(hero) - 64
    local courier = jass.CreateUnit(jass.Player(player_id), COURIER_ID, x, y, 270.0)
    if courier == nil then
        print("飞行信使创建失败：player=" .. tostring(player_id))
        return nil
    end
    if type(jass.SetUnitInvulnerable) == "function" then
        jass.SetUnitInvulnerable(courier, true)
    else
        print("飞行信使警告：当前运行时没有 SetUnitInvulnerable")
    end
    -- 以农民为物编父级，并在物编中清空可建造列表；临时添加再移除乌鸦形态只用于切换飞行移动类型。
    -- 该能力不会留在单位身上，因此不会占用命令卡或显示为技能。
    if CROW_FORM_ID ~= nil and type(jass.UnitAddAbility) == "function"
        and type(jass.UnitRemoveAbility) == "function" then
        jass.UnitAddAbility(courier, CROW_FORM_ID)
        jass.UnitRemoveAbility(courier, CROW_FORM_ID)
    end
    -- 物编已配置两项系统技能；这里再次添加以兼容旧存档/对象表未刷新的测试地图。
    if type(jass.UnitAddAbility) == "function" then
        jass.UnitAddAbility(courier, FOLLOW_ID)
        jass.UnitAddAbility(courier, FUSION_ID)
    end
    if type(jass.SetUnitPathing) == "function" then
        jass.SetUnitPathing(courier, false)
    end
    if type(jass.SetUnitAcquireRange) == "function" then
        jass.SetUnitAcquireRange(courier, 0)
    end
    if type(jass.SetUnitFlyHeight) == "function" then
        jass.SetUnitFlyHeight(courier, 180, 0)
    end
    courier_by_player[player_id] = courier
    player_by_courier[courier] = player_id
    hero_by_courier[courier] = hero
    return courier
end

local function register_spell_events()
    if type(jass.CreateTrigger) ~= "function" or type(jass.TriggerRegisterPlayerUnitEvent) ~= "function"
        or type(jass.TriggerAddAction) ~= "function" then
        return false
    end
    spell_trigger = jass.CreateTrigger()
    for player_id = 0, 15 do
        jass.TriggerRegisterPlayerUnitEvent(spell_trigger, jass.Player(player_id), jass.EVENT_PLAYER_UNIT_SPELL_EFFECT, nil)
    end
    jass.TriggerAddAction(spell_trigger, on_spell_effect)
    return true
end

--- 获取玩家绑定的飞行信使。
---@param player_id integer 玩家编号
---@return unit|nil courier 飞行信使
function module.get_by_player(player_id)
    return courier_by_player[player_id]
end

--- 获取飞行信使绑定的英雄。
---@param courier unit 飞行信使
---@return unit|nil hero 绑定英雄
function module.get_hero(courier)
    return hero_by_courier[courier]
end

---@param unit_handle unit 单位句柄
---@return boolean isCourier 是否为飞行信使
function module.is_courier(unit_handle)
    return is_courier(unit_handle)
end

--- 处理装备同步通道中的飞行信使消息。
---@param parts string[] 已按 | 分隔的消息
---@param sender_id integer|nil 发送玩家
function module.handle_sync(parts, sender_id)
    if parts[1] == "BIRD_FUSION_BEGIN" then
        handle_sync_begin(parts, sender_id)
    elseif parts[1] == "BIRD_FUSION_MATERIALS" then
        handle_sync_materials(parts, sender_id)
    elseif parts[1] == "BIRD_FUSION_OUTPUT" then
        handle_sync_output(parts, sender_id)
    elseif parts[1] == "BIRD_FUSION_END" then
        handle_sync_end(parts, sender_id)
    end
end

--- 启动飞行信使系统。
---@param hero_results HeroSelectionResult[] 英雄创建结果
---@param sync_adapter table 装备同步模块
---@param allow_fusion boolean 是否允许执行范围合成
---@param allow_local_fallback boolean 单人无同步时是否允许本地执行合成
---@return boolean started_now 是否首次启动
function module.start(hero_results, sync_adapter, allow_fusion, allow_local_fallback)
    if started then
        return false
    end
    COURIER_ID = rawcode_to_id(COURIER_RAWCODE)
    FOLLOW_ID = rawcode_to_id(FOLLOW_RAWCODE)
    FUSION_ID = rawcode_to_id(FUSION_RAWCODE)
    CROW_FORM_ID = rawcode_to_id(CROW_FORM_RAWCODE)
    if COURIER_ID == nil or FOLLOW_ID == nil or FUSION_ID == nil or CROW_FORM_ID == nil then
        print("飞行信使启动失败：Rawcode 无效")
        return false
    end
    if type(jass.CreateUnit) ~= "function" or type(jass.Player) ~= "function" then
        print("飞行信使启动失败：CreateUnit 接口不可用")
        return false
    end
    started = true
    sync_module = sync_adapter
    fusion_enabled = allow_fusion == true
    local_fallback = allow_local_fallback == true
    for _, result in ipairs(hero_results or {}) do
        if result.playerId ~= nil and result.unit ~= nil then
            create_courier(result.playerId, result.unit)
        end
    end
    if not register_spell_events() then
        print("飞行信使警告：技能事件注册失败")
    end
    print(string.format("飞行信使已启动：玩家=%d，范围合成=%s", #(hero_results or {}), tostring(fusion_enabled)))
    return true
end

return module
