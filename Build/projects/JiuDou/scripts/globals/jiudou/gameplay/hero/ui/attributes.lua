--- 英雄属性面板。
--- 所有 DzFrame 与按键操作仅影响本地显示，不得修改同步游戏状态。
local jass = J.Common
local input = JiuDou.module("platform.input")
local hero_stats = JiuDou.module("gameplay.hero.stats")
local rogue_state = JiuDou.module("gameplay.rogue.state")
local gold = JiuDou.module("gameplay.gold.main")
local experience = JiuDou.module("gameplay.experience.main")
local special_spawn = JiuDou.module("gameplay.monster.special_spawn")
local attribute_config = JiuDou.config.attributes
local events = JiuDou.core and JiuDou.core.events
local lifecycle = JiuDou.core and JiuDou.core.lifecycle
local resource_api = JiuDou.core and JiuDou.core.resource

local ui = UIKit("jiudou_hero_attributes")

local module = {}

local TAB_KEY = 9
local KEY_DOWN = 1
local PROJECTION_LIMITS = {
    hidden_attack = 9999,
    hidden_health = 99999,
    hidden_armor = 9999,
}

local active_hero = nil
local hotkey_trigger = nil
local started = false
local last_error = ""
local runtime_scope = nil
local stats_event_token = nil

local function local_player_id()
    if type(jass.GetLocalPlayer) ~= "function" or type(jass.GetPlayerId) ~= "function" then return nil end
    return jass.GetPlayerId(jass.GetLocalPlayer())
end

local function ordered_definitions()
    local definitions = {}
    for attribute_id, definition in pairs(attribute_config.attributes or {}) do
        table.insert(definitions, {
            attributeId = attribute_id,
            group = definition.group,
            name = definition.name,
            displayOrder = definition.displayOrder,
            projection = definition.projection,
        })
    end
    table.sort(definitions, function(left, right)
        return left.displayOrder < right.displayOrder
    end)
    return definitions
end

local function format_value(definition, value)
    value = math.floor(tonumber(value) or 0)
    if definition.projection == "hero_strength"
        or definition.projection == "hero_agility"
        or definition.projection == "hero_intelligence" then
        return tostring(value)
    end
    if definition.projection == "derived_attack_speed_percent" then
        return tostring(math.max(1, value)) .. "%"
    end
    if definition.displayFormat == "percent"
        or definition.projection == "derived_basic_attack_bonus_percent"
        or definition.projection == "derived_health_amplification_percent" then
        return (value >= 0 and "+" or "") .. tostring(value) .. "%"
    end
    if definition.projection == "hidden_attack"
        or definition.projection == "hidden_health"
        or definition.projection == "hidden_armor" then
        return tostring(value)
    end
    return (value >= 0 and "+" or "") .. tostring(value)
end

local function is_primary_attribute(definition)
    return definition.projection == "hero_strength"
        or definition.projection == "hero_agility"
        or definition.projection == "hero_intelligence"
end

local function format_projection_limit(definition, value)
    local projection = definition.projection
    local limit = PROJECTION_LIMITS[projection]
    if limit ~= nil and math.abs(math.floor(tonumber(value) or 0)) >= limit then
        return " |cffff8080（投影已限制）|r"
    end
    return ""
end

local function format_growth(definition, growth)
    if not is_primary_attribute(definition) then return "" end
    growth = math.floor(tonumber(growth) or 0)
    return string.format(" |cffc0c0c0（成长 %s）|r", growth >= 0 and "+" .. tostring(growth) or tostring(growth))
end

local function format_gold_bonus(value)
    value = math.floor(tonumber(value) or 0)
    return (value >= 0 and "+" or "") .. tostring(value) .. "%"
end

local function get_skill_damage_bonus_percent(hero)
    local intelligence_bonus = hero_stats.get_skill_damage_bonus_percent(hero)
    local state = rogue_state.get_by_hero(hero)
    local common_bonus = state and state.common and state.common.skill_damage_percent or 0
    return math.max(0, math.floor(intelligence_bonus + (tonumber(common_bonus) or 0)))
end

local function format_snapshot(snapshot, growth, gold_bonus, experience_snapshot, skill_damage_bonus, special_chances)
    local lines = {}
    local previous_group = nil
    for _, definition in ipairs(ordered_definitions()) do
        if definition.group ~= previous_group then
            if previous_group ~= nil then table.insert(lines, "") end
            table.insert(lines, "|cffffcc00" .. tostring(definition.group) .. "|r")
            previous_group = definition.group
        end
        table.insert(lines, string.format(
            "%s：|cff80ff80%s|r%s",
            tostring(definition.name),
            format_value(definition, snapshot[definition.attributeId]),
            format_growth(definition, growth[definition.attributeId])
            .. format_projection_limit(definition, snapshot[definition.attributeId])
        ))
    end
    table.insert(lines, string.format(
        "技能增幅：|cff80ff80+%d%%|r",
        math.max(0, math.floor(tonumber(skill_damage_bonus) or 0))
    ))
    table.insert(lines, "")
    table.insert(lines, "|cffffcc00成长属性|r")
    local experience_level = math.floor(tonumber(experience_snapshot and experience_snapshot.level) or 1)
    local experience_max_level = math.max(1, math.floor(tonumber(experience_snapshot and experience_snapshot.maxLevel) or 25))
    local current_exp = math.max(0, math.floor(tonumber(experience_snapshot and experience_snapshot.currentExp) or 0))
    local next_level_exp = math.max(0, math.floor(tonumber(experience_snapshot and experience_snapshot.nextLevelExp) or 0))
    local exp_text = next_level_exp > 0
        and string.format("%d / %d", current_exp, next_level_exp)
        or "已满级"
    table.insert(lines, string.format(
        "等级：|cff80ff80Lv.%d / %d|r",
        experience_level,
        experience_max_level
    ))
    table.insert(lines, string.format("经验：|cff80ff80%s|r", exp_text))
    table.insert(lines, string.format(
        "经验加成：|cff80ff80+%d%%|r",
        math.max(0, math.floor(tonumber(experience_snapshot and experience_snapshot.bonusPercent) or 0))
    ))
    table.insert(lines, "")
    table.insert(lines, "|cffffcc00经济属性|r")
    table.insert(lines, string.format(
        "金币掉落加成：|cff80ff80%s|r",
        format_gold_bonus(gold_bonus)
    ))
    table.insert(lines, string.format(
        "特殊怪生成概率加成：|cff80ff80+%d%%|r",
        math.max(0, math.floor(tonumber(special_chances and special_chances.bonusPercent) or 0))
    ))
    table.insert(lines, string.format(
        "普通怪召唤：金币怪 |cff80ff80%d%%|r / 经验怪 |cff80ff80%d%%|r",
        math.max(0, math.floor(tonumber(special_chances and special_chances.normalGoldPercent) or 10)),
        math.max(0, math.floor(tonumber(special_chances and special_chances.normalExperiencePercent) or 10))
    ))
    table.insert(lines, string.format(
        "精英怪召唤：金币怪 |cff80ff80%d%%|r",
        math.max(0, math.floor(tonumber(special_chances and special_chances.eliteGoldPercent) or 50))
    ))
    return table.concat(lines, "|n")
end

local function refresh_panel(snapshot)
    if active_hero == nil then return end
    -- 当前肉鸽来源中的三项主属性只来自等级成长；其他来源仍汇总在主数值中。
    local growth = hero_stats.get_source(active_hero, "rogue")
    local player_id = local_player_id()
    local gold_bonus = player_id ~= nil and gold.get_gold_bonus(player_id) or 0
    local experience_snapshot = experience.get_snapshot(active_hero)
    local skill_damage_bonus = get_skill_damage_bonus_percent(active_hero)
    local special_chances = special_spawn.get_chances(player_id)
    ui:set_content(format_snapshot(
        snapshot or hero_stats.get_snapshot(active_hero),
        growth,
        gold_bonus,
        experience_snapshot,
        skill_damage_bonus,
        special_chances
    ))
end

function module.toggle()
    if active_hero == nil then return false end
    if ui:is_visible() then
        ui:hide()
    else
        ui:show()
        refresh_panel()
    end
    return true
end

local function create_panel()
    if not ui:show({
        onToggle = function()
            module.toggle()
        end,
    }) then
        last_error = "属性面板创建失败"
        return false
    end
    ui:set_title("属性（TAB）")
    ui:set_button_text("属性")
    ui:set_content("")
    ui:hide()
    return true
end

local function register_tab_hotkey()
    if type(jass.CreateTrigger) ~= "function" or not input.is_available() then
        print("属性面板快捷键未注册：当前运行时没有 JAPI")
        return false
    end
    hotkey_trigger = jass.CreateTrigger()
    if runtime_scope ~= nil then resource_api.trigger(runtime_scope, hotkey_trigger) end
    local callback = function() module.toggle() end
    local registered = input.register_key(hotkey_trigger, TAB_KEY, callback, "JiuDouHeroAttributesHotkey")
    if not registered then
        print("属性面板快捷键注册失败：TAB 的 DzTriggerRegisterKeyEvent 接口不可用，可点击左上角属性按钮")
        return false
    end
    print("属性面板快捷键已注册：TAB")
    return true
end

--- 初始化本地玩家的属性面板。
---@param hero_results HeroSelectionResult[]
---@return boolean started_now
function module.start(hero_results)
    if started then return false end
    local player_id = local_player_id()
    if player_id == nil then return false end
    for _, result in ipairs(hero_results or {}) do
        if result.playerId == player_id then
            active_hero = result.unit
            break
        end
    end
    if active_hero == nil then return false end
    runtime_scope = lifecycle and lifecycle.acquire("hero.ui.attributes", function()
        if stats_event_token ~= nil and events ~= nil then events.off(stats_event_token) end
        stats_event_token = nil
        active_hero, hotkey_trigger, started = nil, nil, false
        ui:hide()
    end) or nil
    started = true
    local on_stats_changed = function(hero, snapshot)
        if hero == active_hero then refresh_panel(snapshot) end
    end
    if events ~= nil and type(events.on) == "function" then
        stats_event_token = events.on("hero.stats_changed", function(data)
            if data ~= nil then
                on_stats_changed(data.hero, data.snapshot)
            end
        end, 0)
    else
        hero_stats.subscribe(on_stats_changed)
    end
    gold.subscribe_gold_bonus(function(player_id)
        if player_id == local_player_id() then refresh_panel() end
    end)
    special_spawn.subscribe(function(player_id)
        if player_id == local_player_id() then refresh_panel() end
    end)
    experience.subscribe(function(hero)
        if hero == active_hero then refresh_panel() end
    end)
    if not create_panel() then
        print("属性面板未启动：" .. last_error)
        return false
    end
    refresh_panel()
    register_tab_hotkey()
    return true
end

function module.stop()
    return lifecycle ~= nil and lifecycle.release("hero.ui.attributes") or false
end

function module.get_last_error() return last_error end

JiuDou.publish("gameplay.hero.ui.attributes", module)
return module
