--- 英雄属性面板。
--- 所有 DzFrame 与按键操作仅影响本地显示，不得修改同步游戏状态。
local jass = require "jass.common"
local frame = require "platform.frame"
local input = require "platform.input"
local hero_stats = require "hero.stats"
local rogue_state = require "rogue.state"
local gold = require "gold.main"
local experience = require "experience.main"
local special_spawn = require "monster.special_spawn"
local attribute_config = require "config.attributes"
local events = JiuDou.core and JiuDou.core.events

local module = {}

local BACKDROP_TEMPLATE = "EscMenuControlBackdropTemplate"
local TEXT_TEMPLATE = "EscMenuLabelTextTemplate"
local TAB_KEY = 9
local KEY_DOWN = 1
local PROJECTION_LIMITS = {
    hidden_attack = 9999,
    hidden_health = 99999,
    hidden_armor = 9999,
}

local next_frame_id = 0
local active_hero = nil
local panel = nil
local hotkey_trigger = nil
local started = false
local last_error = ""

local function local_player_id()
    if type(jass.GetLocalPlayer) ~= "function" or type(jass.GetPlayerId) ~= "function" then return nil end
    return jass.GetPlayerId(jass.GetLocalPlayer())
end

local function create_frame(frame_type, suffix, parent, template)
    next_frame_id = next_frame_id + 1
    return frame.create(frame_type, "JiuDouHeroAttributes" .. suffix .. next_frame_id, parent, template, next_frame_id)
end

local function create_backdrop(parent, suffix, width, height, x, y, texture)
    local target = create_frame("BACKDROP", suffix, parent, BACKDROP_TEMPLATE)
    frame.set_size(target, width, height)
    frame.set_point(target, frame.POINT_CENTER, parent, frame.POINT_CENTER, x, y)
    if texture ~= nil then frame.set_texture(target, texture, 0) end
    return target
end

local function create_text(parent, suffix, width, height, x, y, value)
    local target = create_frame("TEXT", suffix, parent, TEXT_TEMPLATE)
    frame.set_size(target, width, height)
    frame.set_point(target, frame.POINT_CENTER, parent, frame.POINT_CENTER, x, y)
    frame.set_text(target, value or "")
    return target
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
    if panel == nil or active_hero == nil then return end
    -- 当前肉鸽来源中的三项主属性只来自等级成长；其他来源仍汇总在主数值中。
    local growth = hero_stats.get_source(active_hero, "rogue")
    local player_id = local_player_id()
    local gold_bonus = player_id ~= nil and gold.get_gold_bonus(player_id) or 0
    local experience_snapshot = experience.get_snapshot(active_hero)
    local skill_damage_bonus = get_skill_damage_bonus_percent(active_hero)
    local special_chances = special_spawn.get_chances(player_id)
    frame.set_text(panel.content, format_snapshot(
        snapshot or hero_stats.get_snapshot(active_hero),
        growth,
        gold_bonus,
        experience_snapshot,
        skill_damage_bonus,
        special_chances
    ))
end

function module.toggle()
    if panel == nil then return false end
    panel.visible = not panel.visible
    frame.set_visible(panel.root, panel.visible)
    if panel.visible then refresh_panel() end
    return true
end

local function create_panel()
    if not frame.is_available() then
        last_error = "缺少 DzFrame 接口：" .. table.concat(frame.get_missing_api_names(), ", ")
        return false
    end
    local parent = frame.get_game_ui()
    if parent == nil then
        last_error = "无法获取游戏主界面"
        return false
    end

    local root = create_backdrop(parent, "Root", 0.278, 0.480, -0.335, 0.012, "ui\\rogue\\panel.blp")
    if root == nil or root == 0 then
        last_error = "属性面板创建失败"
        return false
    end
    local title = create_text(root, "Title", 0.230, 0.030, 0.0, 0.142, "属性（TAB）")
    local content = create_text(root, "Content", 0.235, 0.400, 0.0, -0.015, "")
    local button = create_frame("BUTTON", "ToggleButton", parent, "ScriptDialogButton")
    frame.set_size(button, 0.078, 0.030)
    frame.set_point(button, frame.POINT_CENTER, parent, frame.POINT_CENTER, -0.340, 0.278)
    frame.set_alpha(button, 1)
    local button_text = create_text(parent, "ToggleText", 0.068, 0.022, -0.340, 0.278, "属性")

    panel = {
        root = root,
        title = title,
        content = content,
        button = button,
        buttonText = button_text,
        visible = false,
        callbacks = {},
    }
    local callback = function() module.toggle() end
    frame.on_click(button, callback)
    table.insert(panel.callbacks, callback)
    frame.set_visible(root, false)
    return true
end

local function register_tab_hotkey()
    if type(jass.CreateTrigger) ~= "function" or not input.is_available() then
        print("属性面板快捷键未注册：当前运行时没有 JAPI")
        return false
    end
    hotkey_trigger = jass.CreateTrigger()
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
    started = true
    local on_stats_changed = function(hero, snapshot)
        if hero == active_hero then refresh_panel(snapshot) end
    end
    if events ~= nil and type(events.on) == "function" then
        events.on("hero.stats_changed", function(data)
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

function module.get_last_error() return last_error end

return module
