--- 飞行信使范围合成同步协议。
--- 编解码批次、材料分片和装备结果；主流程负责可信发送者、去重及地图物品事务。
local module = {}

local VERSION = "1"

local function join_passives(passives)
    if passives == nil or #passives == 0 then return "-" end
    return table.concat(passives, ",")
end

local function parse_passives(value)
    local result = {}
    if value == nil or value == "" or value == "-" then return result end
    for passive_id in string.gmatch(value, "[^,]+") do
        table.insert(result, passive_id)
    end
    return result
end

function module.encode_begin(batch_id, player_id, output_count)
    return table.concat({"BIRD_FUSION_BEGIN", VERSION, tostring(batch_id), tostring(player_id), tostring(output_count)}, "|")
end

function module.encode_materials(batch_id, material_uids, max_length)
    local prefix = table.concat({"BIRD_FUSION_MATERIALS", VERSION, tostring(batch_id), ""}, "|")
    local messages, payload = {}, ""
    for _, uid in ipairs(material_uids or {}) do
        local value = tostring(uid)
        local candidate = payload == "" and value or payload .. "," .. value
        if payload ~= "" and #prefix + #candidate > max_length then
            table.insert(messages, prefix .. payload)
            payload = value
        else
            payload = candidate
        end
    end
    if payload ~= "" then table.insert(messages, prefix .. payload) end
    return messages
end

function module.encode_output(batch_id, output_index, equipment, x, y)
    return table.concat({
        "BIRD_FUSION_OUTPUT", VERSION, tostring(batch_id), tostring(output_index),
        tostring(equipment.uid), equipment.rawcode,
        equipment.templateId ~= nil and equipment.templateId ~= "" and equipment.templateId or "-",
        tostring(equipment.level), tostring(equipment.stats.attack), tostring(equipment.stats.health),
        tostring(equipment.stats.armor), tostring(equipment.stats.basicAttackBonusPercent or 0),
        tostring(equipment.stats.healthAmplificationPercent or 0), equipment.autoSkillId or "-",
        join_passives(equipment.passiveSkillIds), equipment.comboSetId or "-", equipment.comboPieceId or "-",
        tostring(x), tostring(y),
    }, "|")
end

function module.encode_end(batch_id)
    return table.concat({"BIRD_FUSION_END", VERSION, tostring(batch_id)}, "|")
end

function module.decode_begin(parts)
    if #parts ~= 5 or parts[2] ~= VERSION then return nil end
    local batch_id = tonumber(parts[3])
    local player_id = tonumber(parts[4])
    local output_count = tonumber(parts[5])
    if batch_id == nil or player_id == nil or output_count == nil or output_count <= 0 then return nil end
    return {batchId = batch_id, playerId = player_id, expectedOutputCount = output_count}
end

function module.decode_materials(parts)
    if #parts ~= 4 or parts[2] ~= VERSION then return nil end
    local batch_id = tonumber(parts[3])
    if batch_id == nil then return nil end
    local material_uids = {}
    for uid in string.gmatch(parts[4], "[^,]+") do
        local numeric_uid = tonumber(uid)
        if numeric_uid ~= nil then table.insert(material_uids, numeric_uid) end
    end
    return {batchId = batch_id, materialUids = material_uids}
end

function module.decode_output(parts)
    if #parts ~= 19 or parts[2] ~= VERSION then return nil end
    local batch_id = tonumber(parts[3])
    local index = tonumber(parts[4])
    local uid = tonumber(parts[5])
    local level = tonumber(parts[8])
    if batch_id == nil or index == nil or uid == nil or level == nil or index < 1 then return nil end
    return {
        batchId = batch_id,
        index = index,
        uid = uid,
        rawcode = parts[6],
        templateId = parts[7] == "-" and "" or parts[7],
        level = level,
        stats = {
            attack = tonumber(parts[9]) or 0,
            health = tonumber(parts[10]) or 0,
            armor = tonumber(parts[11]) or 0,
            basicAttackBonusPercent = tonumber(parts[12]) or 0,
            healthAmplificationPercent = tonumber(parts[13]) or 0,
        },
        autoSkillId = parts[14] == "-" and nil or parts[14],
        passiveSkillIds = parse_passives(parts[15]),
        comboSetId = parts[16] == "-" and nil or parts[16],
        comboPieceId = parts[17] == "-" and nil or parts[17],
        x = tonumber(parts[18]) or 0,
        y = tonumber(parts[19]) or 0,
    }
end

function module.decode_end(parts)
    if #parts ~= 3 or parts[2] ~= VERSION then return nil end
    return tonumber(parts[3])
end

function module.get_version() return VERSION end

return module
