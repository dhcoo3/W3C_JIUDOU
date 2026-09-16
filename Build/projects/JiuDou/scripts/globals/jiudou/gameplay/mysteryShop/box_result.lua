--- 神秘商店装备箱结果协议。
--- 只负责编解码固定字段；玩家归属、去重、配置和实例校验由主流程完成。
local module = {}

local MESSAGE_TYPE = "MYSTERY_BOX_RESULT"
local VERSION = "2"
local PART_COUNT = 19

local function join_passives(passives)
    if passives == nil or #passives == 0 then return "-" end
    return table.concat(passives, ",")
end

local function parse_passives(value)
    local result = {}
    if value == nil or value == "" or value == "-" then return result end
    for passive_id in string.gmatch(value, "[^,]+") do
        if passive_id ~= "-" and passive_id ~= "" then
            table.insert(result, passive_id)
        end
    end
    return result
end

---@param event_id integer
---@param player_id integer
---@param equipment_data table
---@param x number
---@param y number
---@return string message
function module.encode(event_id, player_id, equipment_data, x, y)
    return table.concat({
        MESSAGE_TYPE, VERSION, tostring(event_id), tostring(player_id),
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

---@param parts string[]
---@return table|nil result
function module.decode(parts)
    if #parts ~= PART_COUNT or parts[1] ~= MESSAGE_TYPE or parts[2] ~= VERSION then return nil end
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
        or attack == nil or health == nil or armor == nil or x == nil or y == nil then return nil end
    event_id = math.floor(event_id)
    player_id = math.floor(player_id)
    uid = math.floor(uid)
    level = math.floor(level)
    if event_id <= 0 or uid <= 0 or player_id < 0 or player_id > 11 or level < 1 or level > 5 then return nil end
    return {
        eventId = event_id,
        playerId = player_id,
        uid = uid,
        rawcode = parts[6],
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

function module.get_version() return tonumber(VERSION) end

return module
