--- 单人训练场：静止怪物矩阵及 GM 同步命令。
local jass = J.Common
local experience = JiuDou.module("gameplay.experience.main")
local hero_stats = JiuDou.module("gameplay.hero.stats")
local rogue = JiuDou.module("gameplay.rogue.main")
local gm_panel = JiuDou.module("gameplay.training.gm_panel")
local damage_numbers = JiuDou.module("gameplay.combat.damage_numbers")

local module = {}
local lifecycle = JiuDou.core and JiuDou.core.lifecycle
local resource_api = JiuDou.core and JiuDou.core.resource
local timer_service = JiuDou.core and JiuDou.core.timer

local NEUTRAL_HOSTILE_PLAYER_ID = 12
local TRAINING_RAWCODE = "T0D0"
local EXPERIENCE_RAWCODE = "N1M1"
local GRID_ROWS = 10
local GRID_COLUMNS = 10
local GRID_SPACING = 160
local RESPAWN_DELAY = 0.10
local SYNC_KEY = "jiudou_training_gm"

local started = false
local scope = nil
local hero = nil
local player_id = nil
local attack_bonus = 0
local death_trigger = nil
local slots = {}
local slot_by_unit = {}

local function configured_max_life()
    local unit_config = JiuDou.config and JiuDou.config.units and JiuDou.config.units[TRAINING_RAWCODE]
    local value = unit_config and tonumber(unit_config.HP) or nil
    if value == nil or value <= 0 then return nil end
    return math.max(1, math.floor(value))
end

local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

local function rawcode_to_unit_id(rawcode)
    if type(rawcode) ~= "string" or #rawcode ~= 4 then return nil end
    local a, b, c, d = string.byte(rawcode, 1, 4)
    if a == nil or b == nil or c == nil or d == nil then return nil end
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

local function max_life(unit_handle)
    if type(jass.GetUnitState) ~= "function" or jass.UNIT_STATE_MAX_LIFE == nil then return 1 end
    return math.max(1, math.floor(tonumber(jass.GetUnitState(unit_handle, jass.UNIT_STATE_MAX_LIFE)) or 1))
end

local function configure_training_unit(unit_handle)
    if type(jass.PauseUnit) == "function" then jass.PauseUnit(unit_handle, true) end
    if type(jass.SetUnitAcquireRange) == "function" then jass.SetUnitAcquireRange(unit_handle, 0) end
    if type(jass.SetUnitInvulnerable) == "function" then jass.SetUnitInvulnerable(unit_handle, false) end
    local configured_life = configured_max_life()
    if configured_life ~= nil and type(jass.SetUnitState) == "function" and jass.UNIT_STATE_MAX_LIFE ~= nil then
        pcall(jass.SetUnitState, unit_handle, jass.UNIT_STATE_MAX_LIFE, configured_life)
    end
    if type(jass.SetUnitState) == "function" and jass.UNIT_STATE_LIFE ~= nil then
        jass.SetUnitState(unit_handle, jass.UNIT_STATE_LIFE, configured_life or max_life(unit_handle))
    end
end

local function spawn_slot(slot)
    if not started then return false end
    -- 当前训练难度固定为困难 10；找不到变体时才回退基础 N1M1。
    local unit_id = rawcode_to_unit_id(TRAINING_RAWCODE)
    if unit_id == nil then return false end
    local unit_handle = jass.CreateUnit(jass.Player(NEUTRAL_HOSTILE_PLAYER_ID), unit_id, slot.x, slot.y, 270.0)
    if unit_handle == nil then return false end
    configure_training_unit(unit_handle)
    slot.generation = slot.generation + 1
    slot.unit = unit_handle
    slot_by_unit[unit_handle] = slot
    damage_numbers.register_target(unit_handle)
    damage_numbers.register_recovery_target(unit_handle)
    experience.register_monster(unit_handle, "normal", EXPERIENCE_RAWCODE, slot.generation, max_life(unit_handle))
    return true
end

local function on_unit_death()
    local unit_handle = type(jass.GetDyingUnit) == "function" and jass.GetDyingUnit() or nil
    local slot = slot_by_unit[unit_handle]
    if slot == nil then return end
    slot_by_unit[unit_handle] = nil
    slot.unit = nil
    damage_numbers.unregister_recovery_target(unit_handle)
    timer_service.after(RESPAWN_DELAY, function()
        if started and slot.unit == nil then
            spawn_slot(slot)
        end
    end, scope)
end

local function parse_amount(text)
    if type(text) ~= "string" or not string.match(text, "^%d+$") then return nil end
    local amount = tonumber(text)
    if not is_integer(amount) or amount < 1 or amount > 9999999 then return nil end
    return amount
end

local function status(message)
    gm_panel.set_status(message)
    print("训练 GM：" .. tostring(message))
end

local function state_value(unit_handle, state_id)
    if unit_handle == nil or type(jass.GetUnitState) ~= "function" or state_id == nil then return 0 end
    return math.max(0, tonumber(jass.GetUnitState(unit_handle, state_id)) or 0)
end

local function restore_hero()
    if hero == nil or type(jass.GetUnitState) ~= "function" then return 0, 0 end
    if type(hero_stats.refresh) == "function" then hero_stats.refresh(hero) end

    local old_life = state_value(hero, jass.UNIT_STATE_LIFE)
    local old_mana = state_value(hero, jass.UNIT_STATE_MANA)
    local max_life_value = state_value(hero, jass.UNIT_STATE_MAX_LIFE)
    local max_mana_value = state_value(hero, jass.UNIT_STATE_MAX_MANA)
    if max_life_value > old_life and type(jass.SetUnitState) == "function" and jass.UNIT_STATE_LIFE ~= nil then
        jass.SetUnitState(hero, jass.UNIT_STATE_LIFE, max_life_value)
    end
    if max_mana_value > old_mana and type(jass.SetUnitState) == "function" and jass.UNIT_STATE_MANA ~= nil then
        jass.SetUnitState(hero, jass.UNIT_STATE_MANA, max_mana_value)
    end

    local life_delta = math.max(0, state_value(hero, jass.UNIT_STATE_LIFE) - old_life)
    local mana_delta = math.max(0, state_value(hero, jass.UNIT_STATE_MANA) - old_mana)
    return math.floor(life_delta + 0.5), math.floor(mana_delta + 0.5)
end

local function on_gm_command(sync_data)
    if not started or type(sync_data) ~= "table" then return end
    local data = sync_data.transferData or {}
    local action = data[1]
    if action == "restore" then
        local life_delta, mana_delta = restore_hero()
        if life_delta <= 0 and mana_delta <= 0 then
            status("生命和 MP 已经是满值")
        else
            status(string.format("已回满：生命 +%d，MP +%d", life_delta, mana_delta))
        end
        return
    end
    local amount = parse_amount(tostring(data[2] or ""))
    if amount == nil then
        status("请输入 1 - 9,999,999 的整数")
        return
    end
    if action == "rogue" then
        if rogue.grant_offer(player_id) then status("已打开一组肉鸽三选一") else status("肉鸽奖励暂不可用") end
        return
    end
    if action == "experience" then
        if experience.grant(player_id, amount) then status("已精确增加经验 " .. tostring(amount)) else status("经验发放失败（可能已满级）") end
    elseif action == "attack" then
        attack_bonus = attack_bonus + amount
        if hero_stats.set_source(hero, "training.gm.attack", { attack = attack_bonus }) then
            status("固定攻击力 +" .. tostring(amount) .. "，累计 +" .. tostring(attack_bonus))
        else
            status("攻击力修改失败")
        end
    else
        status("未知 GM 指令")
    end
end

local function clear_runtime()
    sync.receive(SYNC_KEY, nil)
    gm_panel.stop()
    for _, slot in ipairs(slots) do
        if slot.unit ~= nil then
            experience.unregister_monster(slot.unit)
            damage_numbers.unregister_recovery_target(slot.unit)
            if type(jass.RemoveUnit) == "function" then jass.RemoveUnit(slot.unit) end
        end
    end
    slots, slot_by_unit = {}, {}
    if hero ~= nil then hero_stats.clear_source(hero, "training.gm.attack") end
    started, scope, hero, player_id, attack_bonus, death_trigger = false, nil, nil, nil, 0, nil
end

function module.start(hero_results)
    if started or type(hero_results) ~= "table" or #hero_results ~= 1 then return false end
    local result = hero_results[1]
    if result == nil or result.unit == nil or not is_integer(result.playerId) then return false end
    if timer_service == nil or type(timer_service.after) ~= "function" then
        print("训练场启动失败：缺少计时器服务")
        return false
    end

    scope = lifecycle and lifecycle.acquire("training.main", clear_runtime) or nil
    started, hero, player_id = true, result.unit, result.playerId
    local origin_x = type(jass.GetUnitX) == "function" and jass.GetUnitX(hero) or result.positionX
    local origin_y = type(jass.GetUnitY) == "function" and jass.GetUnitY(hero) or result.positionY
    origin_x, origin_y = tonumber(origin_x) or 0, tonumber(origin_y) or 0

    for row = 1, GRID_ROWS do
        for column = 1, GRID_COLUMNS do
            local slot = {
                x = origin_x + (column - (GRID_COLUMNS + 1) / 2) * GRID_SPACING,
                y = origin_y + 240 + (row - 1) * GRID_SPACING,
                generation = 0,
                unit = nil,
            }
            table.insert(slots, slot)
            if not spawn_slot(slot) then
                print("训练场启动失败：无法创建训练怪")
                module.stop()
                return false
            end
        end
    end

    death_trigger = jass.CreateTrigger()
    if death_trigger == nil then
        module.stop()
        return false
    end
    if scope ~= nil and resource_api ~= nil then resource_api.trigger(scope, death_trigger) end
    jass.TriggerRegisterPlayerUnitEvent(death_trigger, jass.Player(NEUTRAL_HOSTILE_PLAYER_ID), jass.EVENT_PLAYER_UNIT_DEATH, nil)
    jass.TriggerAddAction(death_trigger, on_unit_death)

    sync.receive(SYNC_KEY, on_gm_command)
    gm_panel.start(function(action, amount_text)
        sync.send(SYNC_KEY, { action, amount_text })
    end)
    status("Training ground ready: 100 T0D0 dummies spawned")
    return true
end

function module.stop()
    return lifecycle ~= nil and lifecycle.release("training.main") or false
end

function module.is_started()
    return started
end

JiuDou.publish("gameplay.training.main", module)
return module