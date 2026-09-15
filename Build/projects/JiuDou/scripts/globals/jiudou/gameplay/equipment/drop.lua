--- 中立敌对怪物死亡后的房主权威装备掉落。
--- 掉落结果先同步完整实例，再由所有客户端在相同坐标创建相同道具。
local jass = require "jass.common"
local units = require "config.units"
local generator = require "equipment.generator"
local instance = require "equipment.instance"

local module = {}
local death_trigger = nil
local sync_broadcast = nil
local enabled = true
local drop_sequence = 0
local processed_uids = {}
local rawcode_by_type_id = {}

local NEUTRAL_HOSTILE_PLAYER_ID = 12

local function rawcode_to_id(rawcode)
    local a, b, c, d = string.byte(rawcode or "", 1, 4)
    if a == nil or b == nil or c == nil or d == nil then
        return nil
    end
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local function integer(value, fallback)
    if type(value) == "table" then value = value[1] end
    local number = tonumber(value)
    if number == nil then return fallback or 0 end
    return math.floor(number)
end

for rawcode, unit in pairs(units) do
    if type(unit) == "table" and unit.baseUnitId ~= nil then
        local type_id = rawcode_to_id(rawcode)
        if type_id ~= nil then rawcode_by_type_id[type_id] = rawcode end
    end
end

local function get_unit_rawcode(unit_handle)
    if unit_handle == nil or type(jass.GetUnitTypeId) ~= "function" then
        return nil
    end
    local type_id = jass.GetUnitTypeId(unit_handle)
    return rawcode_by_type_id[type_id]
end

local function find_rule(unit_rawcode)
    local unit = units[unit_rawcode]
    if type(unit) ~= "table" then return nil, nil end
    local chance = integer(unit.dropChancePercent, 0)
    if chance <= 0 then return nil, nil end
    local rule = {
        poolId = unit.poolId,
        levelMin = integer(unit.dropLevelMin, 0),
        levelMax = integer(unit.dropLevelMax, 0),
        chance = chance,
        maxDrops = integer(unit.maxDrops, 1),
    }
    if type(rule.poolId) ~= "string" or rule.poolId == ""
        or rule.levelMin < 1 or rule.levelMax < rule.levelMin or rule.maxDrops < 1 then
        return nil, nil
    end
    return rule, "DROP_" .. unit_rawcode
end

local function join_passives(passives)
    if passives == nil or #passives == 0 then
        return "-"
    end
    return table.concat(passives, ",")
end

local function encode_result(drop_id, equipment, x, y)
    return table.concat({
        "DROP_RESULT", "3", drop_id, tostring(equipment.uid), equipment.rawcode,
        equipment.templateId or "-", tostring(equipment.level),
        tostring(equipment.stats.attack), tostring(equipment.stats.health), tostring(equipment.stats.armor),
        tostring(equipment.stats.basicAttackBonusPercent or 0), tostring(equipment.stats.healthAmplificationPercent or 0),
        equipment.autoSkillId or "-", join_passives(equipment.passiveSkillIds),
        equipment.comboSetId or "-", equipment.comboPieceId or "-",
        tostring(math.floor(x)), tostring(math.floor(y)),
    }, "|")
end

local function create_result(parts)
    if #parts ~= 18 or parts[2] ~= "3" then
        print("装备掉落结果字段数量错误")
        return
    end
    local uid = tonumber(parts[4])
    local level = tonumber(parts[7])
    if uid == nil or level == nil or processed_uids[uid] or instance.get_by_uid(uid) ~= nil then
        return
    end
    if level < 1 or level > 5 then
        return
    end
    local item_id = rawcode_to_id(parts[5])
    if item_id == nil or type(jass.CreateItem) ~= "function" then
        print("装备掉落创建失败：物品 Rawcode 无效")
        return
    end
    local item_handle = jass.CreateItem(item_id, tonumber(parts[17]) or 0, tonumber(parts[18]) or 0)
    if item_handle == nil then
        print("装备掉落创建失败：CreateItem 返回空")
        return
    end
    local passive_ids = {}
    if parts[14] ~= "-" and parts[14] ~= "" then
        for passive_id in string.gmatch(parts[14], "[^,]+") do
            table.insert(passive_ids, passive_id)
        end
    end
    local equipment = instance.create({
        uid = uid,
        item = item_handle,
        rawcode = parts[5],
        templateId = parts[6] == "-" and "" or parts[6],
        level = level,
        stats = {
            attack = tonumber(parts[8]) or 0,
            health = tonumber(parts[9]) or 0,
            armor = tonumber(parts[10]) or 0,
            basicAttackBonusPercent = tonumber(parts[11]) or 0,
            healthAmplificationPercent = tonumber(parts[12]) or 0,
        },
        autoSkillId = parts[13] == "-" and nil or parts[13],
        passiveSkillIds = passive_ids,
        comboSetId = parts[15] == "-" and nil or parts[15],
        comboPieceId = parts[16] == "-" and nil or parts[16],
    })
    processed_uids[uid] = true
    instance.bind_item(item_handle, equipment)
end

local function on_death()
    if not enabled or not module.is_host() then
        return
    end
    local dying_unit = type(jass.GetDyingUnit) == "function" and jass.GetDyingUnit() or nil
    local rawcode = get_unit_rawcode(dying_unit)
    local rule, drop_id = find_rule(rawcode)
    if rule == nil then
        return
    end
    drop_sequence = drop_sequence + 1
    if not generator.roll_percent(drop_sequence, rule.chance) then
        return
    end
    local drop_count = math.max(1, math.floor(tonumber(rule.maxDrops) or 1))
    for _ = 1, drop_count do
        local uid = drop_sequence * 10 + _
        local equipment = generator.create_drop(rule, uid, drop_sequence * 100 + _)
        if equipment ~= nil then
            local x = jass.GetUnitX(dying_unit)
            local y = jass.GetUnitY(dying_unit)
            if sync_broadcast ~= nil then
                sync_broadcast(encode_result(drop_id, equipment, x, y))
            end
        end
    end
end

--- 启动怪物死亡掉落监听。
---@param broadcast fun(message:string) 同步广播函数
---@param allow boolean 是否启用装备掉落
function module.start(broadcast, allow)
    sync_broadcast = broadcast
    enabled = allow ~= false
    if death_trigger ~= nil or not enabled then
        return enabled
    end
    death_trigger = jass.CreateTrigger()
    jass.TriggerRegisterPlayerUnitEvent(death_trigger, jass.Player(NEUTRAL_HOSTILE_PLAYER_ID), jass.EVENT_PLAYER_UNIT_DEATH, nil)
    jass.TriggerAddAction(death_trigger, on_death)
    return true
end

---@param host_check fun():boolean 判断本地是否为房主
function module.set_host_checker(host_check)
    module.is_host = host_check
end

module.is_host = function()
    return true
end

module.handle_result = create_result

return module
