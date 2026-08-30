--- 统一战斗伤害事件服务。
---
--- 项目所有战斗单位均使用 Hero 攻击与 Hero 护甲。Lua 伤害也明确使用 Hero 攻击类型，
--- 从而不再触发普通/穿刺/攻城/魔法与轻中重甲之间的原生克制倍率。
--- Warcraft III 1.27 没有 BlzSetEventDamage。普通攻击加成因此采用受伤事件后的
--- 生命值补偿：原生攻击先完成护甲结算，本服务再直接扣除 floor(已结算伤害×普攻加成/100)
--- 点生命。补偿使用 SetUnitState，不会再次触发 EVENT_UNIT_DAMAGED。
local jass = require "jass.common"
local hero_stats = require "hero.stats"

local module = {}

local started = false
local warned_unavailable = false
local damage_trigger = nil
local attack_trigger = nil
local cleanup_timer = nil
local event_clock = 0.0
local subscribers = {}
local hero_sources = {}
local registered_targets = {}
local pending_attacks = {}
local pending_non_basic_damage = {}
local applying_compensation = {}

local ATTACK_MARK_DURATION = 0.90

local function handle_id(handle)
    if handle == nil or type(jass.GetHandleId) ~= "function" then return nil end
    return jass.GetHandleId(handle)
end

local function attack_key(source, target)
    local source_id, target_id = handle_id(source), handle_id(target)
    if source_id == nil or target_id == nil then return nil end
    return tostring(source_id) .. ":" .. tostring(target_id)
end

local function is_alive(target)
    return target ~= nil
        and type(jass.GetUnitState) == "function"
        and jass.UNIT_STATE_LIFE ~= nil
        and (tonumber(jass.GetUnitState(target, jass.UNIT_STATE_LIFE)) or 0) > 0.405
end

local function emit(report)
    for _, subscriber in ipairs(subscribers) do
        pcall(subscriber, report)
    end
end

local function mark_attack(source, target)
    if source == nil or target == nil or not hero_sources[handle_id(source)] then return end
    local key = attack_key(source, target)
    if key ~= nil then
        pending_attacks[key] = {
            source = source,
            target = target,
            expiresAt = event_clock + ATTACK_MARK_DURATION,
        }
    end
end

local function take_attack_mark(source, target)
    local key = attack_key(source, target)
    local mark = key ~= nil and pending_attacks[key] or nil
    if mark == nil then return false end
    pending_attacks[key] = nil
    return mark.expiresAt >= event_clock
end

local function cleanup_attack_marks()
    event_clock = event_clock + 0.10
    for key, mark in pairs(pending_attacks) do
        if mark.expiresAt < event_clock then pending_attacks[key] = nil end
    end
    for key, expires_at in pairs(pending_non_basic_damage) do
        if expires_at < event_clock then pending_non_basic_damage[key] = nil end
    end
end

local function take_non_basic_mark(source, target)
    local key = attack_key(source, target)
    local expires_at = key ~= nil and pending_non_basic_damage[key] or nil
    if expires_at == nil then return false end
    pending_non_basic_damage[key] = nil
    return expires_at >= event_clock
end

local function apply_basic_attack_compensation(source, target, amount, bonus_source)
    if target == nil or type(jass.SetUnitState) ~= "function" or jass.UNIT_STATE_LIFE == nil then
        return 0
    end
    local bonus = hero_stats.get_basic_attack_bonus_percent(bonus_source or source)
    if bonus <= 0 then return 0 end
    local compensation = math.floor(amount * bonus / 100)
    if compensation <= 0 then return 0 end

    local target_id = handle_id(target)
    if target_id ~= nil and applying_compensation[target_id] then return 0 end
    if target_id ~= nil then applying_compensation[target_id] = true end
    local current = math.max(0, tonumber(jass.GetUnitState(target, jass.UNIT_STATE_LIFE)) or 0)
    if current > 0.405 then
        jass.SetUnitState(target, jass.UNIT_STATE_LIFE, math.max(0, current - compensation))
    end
    if target_id ~= nil then applying_compensation[target_id] = nil end
    return compensation
end

local function on_unit_damaged()
    if type(jass.GetTriggerUnit) ~= "function"
        or type(jass.GetEventDamageSource) ~= "function"
        or type(jass.GetEventDamage) ~= "function" then
        return
    end
    local target = jass.GetTriggerUnit()
    local source = jass.GetEventDamageSource()
    local amount = math.floor((tonumber(jass.GetEventDamage()) or 0) + 0.5)
    if target == nil or source == nil or amount <= 0 then return end
    local is_internal_damage = take_non_basic_mark(source, target)
    local is_basic_attack = not is_internal_damage and take_attack_mark(source, target)
    local report = {
        source = source,
        target = target,
        amount = amount,
        kind = "native",
        synthetic = false,
        isBasicAttack = is_basic_attack,
    }
    emit(report)

    if is_basic_attack and not (handle_id(target) ~= nil and applying_compensation[handle_id(target)]) then
        local registered_owner = hero_sources[handle_id(source)]
        local bonus_source = type(registered_owner) == "table" and registered_owner.owner or registered_owner
        if bonus_source == true then bonus_source = source end
        local compensation = apply_basic_attack_compensation(source, target, amount, bonus_source)
        if compensation > 0 then
            emit({
                source = source,
                target = target,
                amount = compensation,
                kind = "basic_attack_bonus",
                synthetic = true,
                isBasicAttack = true,
            })
        end
    end
end

local function register_damage_trigger()
    if type(jass.CreateTrigger) ~= "function"
        or type(jass.TriggerAddAction) ~= "function"
        or type(jass.TriggerRegisterUnitEvent) ~= "function"
        or jass.EVENT_UNIT_DAMAGED == nil then
        return false
    end
    damage_trigger = jass.CreateTrigger()
    if damage_trigger == nil then return false end
    jass.TriggerAddAction(damage_trigger, on_unit_damaged)
    return true
end

local function register_attack_trigger()
    if type(jass.TriggerRegisterPlayerUnitEvent) ~= "function"
        or type(jass.TriggerAddAction) ~= "function"
        or jass.EVENT_PLAYER_UNIT_ATTACKED == nil
        or type(jass.Player) ~= "function" then
        return false
    end
    attack_trigger = jass.CreateTrigger()
    if attack_trigger == nil then return false end
    for player_id = 0, 15 do
        jass.TriggerRegisterPlayerUnitEvent(
            attack_trigger,
            jass.Player(player_id),
            jass.EVENT_PLAYER_UNIT_ATTACKED,
            nil
        )
    end
    jass.TriggerAddAction(attack_trigger, function()
        local source = type(jass.GetAttacker) == "function" and jass.GetAttacker() or nil
        local target = type(jass.GetAttackedUnitBJ) == "function" and jass.GetAttackedUnitBJ()
            or (type(jass.GetTriggerUnit) == "function" and jass.GetTriggerUnit() or nil)
        mark_attack(source, target)
    end)
    return true
end

---@param hero_results HeroSelectionResult[]
---@return boolean started_now
function module.start(hero_results)
    if started then return true end
    if not register_damage_trigger() or not register_attack_trigger() then
        if not warned_unavailable then
            warned_unavailable = true
            print("统一伤害事件未启动：当前运行时缺少 1.27 单位受伤或攻击事件接口")
        end
        return false
    end
    for _, result in ipairs(hero_results or {}) do
        if result.unit ~= nil then
            local id = handle_id(result.unit)
            if id ~= nil then hero_sources[id] = true end
        end
    end
    started = true
    if type(jass.CreateTimer) == "function" and type(jass.TimerStart) == "function" then
        cleanup_timer = jass.CreateTimer()
        if cleanup_timer ~= nil then jass.TimerStart(cleanup_timer, 0.10, true, cleanup_attack_marks) end
    end
    return true
end

---@param target unit
---@return boolean registered
function module.register_target(target)
    if not started or target == nil or damage_trigger == nil then return false end
    local target_id = handle_id(target)
    if target_id == nil then return false end
    if registered_targets[target_id] then return true end
    jass.TriggerRegisterUnitEvent(damage_trigger, target, jass.EVENT_UNIT_DAMAGED)
    registered_targets[target_id] = true
    return true
end

---@param subscriber fun(report:table)
---@return boolean added
function module.subscribe(subscriber)
    if type(subscriber) ~= "function" then return false end
    table.insert(subscribers, subscriber)
    return true
end

---@param hero unit
---@param owner unit|nil 预留给需要继承英雄普攻加成的召唤物
function module.register_attack_source(hero, owner)
    local id = handle_id(hero)
    if id == nil then return false end
    hero_sources[id] = owner or true
    return true
end

--- 统一造成技能/触发/召唤物伤害的入口。
---@param source unit 伤害来源
---@param target unit 伤害目标
---@param amount integer 原始伤害
---@param damage_type number|nil Warcraft 伤害类型
---@return boolean applied
function module.deal(source, target, amount, damage_type)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if source == nil or target == nil or amount <= 0 or type(jass.UnitDamageTarget) ~= "function" then
        return false
    end
    local key = attack_key(source, target)
    local target_id = handle_id(target)
    if key ~= nil and target_id ~= nil and registered_targets[target_id] then
        pending_non_basic_damage[key] = event_clock + 0.25
    end
    local ok = pcall(function()
        jass.UnitDamageTarget(
            source,
            target,
            amount,
            true,
            false,
            jass.ATTACK_TYPE_HERO,
            damage_type or jass.DAMAGE_TYPE_MAGIC,
            jass.WEAPON_TYPE_WHOKNOWS
        )
    end)
    if not ok and key ~= nil then pending_non_basic_damage[key] = nil end
    return ok
end

function module.is_started() return started end

return module
