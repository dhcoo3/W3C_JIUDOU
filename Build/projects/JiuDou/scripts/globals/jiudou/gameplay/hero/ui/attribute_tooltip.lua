--- 英雄三维属性合并 Tooltip。
--- 负责接管原生英雄属性信息区的旧提示，并把三项属性的项目规则显示在同一个 Tips 中。
--- 运行时只在本地玩家界面执行；属性数值仍由 hero.stats 统一计算。
local jass = J.Common
local frame = JiuDou.module("platform.frame")
local hero_stats = JiuDou.module("gameplay.hero.stats")
local events = JiuDou.core and JiuDou.core.events
local lifecycle = JiuDou.core and JiuDou.core.lifecycle
local timer_service = JiuDou.core and JiuDou.core.timer

local ui = UIKit("jiudou_hero_attribute_tooltip")

local module = {}
local runtime_scope = nil
local stats_event_token = nil

local HERO_INFO_CONTEXT = 6
local RETRY_INTERVAL = 0.5
local MAX_INSTALL_ATTEMPTS = 20
local HOVER_POLL_INTERVAL = 0.05

local ATTRIBUTE_NAMES = {
    strength = "力量",
    agility = "敏捷",
    intelligence = "智力",
}

-- 1.27 的英雄属性信息区由一个容器、一个主属性图标和三组文字组成。
-- SimpleInfoPanelIconHero 是整体容器，后续名称用于兼容不同 KKWE 客户端暴露的控件层级。
local HERO_INFO_FRAME_NAMES = {
    "SimpleInfoPanelIconHero",
    "SimpleInfoPanelIconHeroText",
    "InfoPanelIconHeroIcon",
}

local ATTRIBUTE_FRAME_NAMES = {
    "InfoPanelIconHeroStrengthLabel",
    "InfoPanelIconHeroStrengthValue",
    "InfoPanelIconHeroAgilityLabel",
    "InfoPanelIconHeroAgilityValue",
    "InfoPanelIconHeroIntellectLabel",
    "InfoPanelIconHeroIntellectValue",
}

local ATTRIBUTE_VALUE_NAMES = {
    strength = "InfoPanelIconHeroStrengthValue",
    agility = "InfoPanelIconHeroAgilityValue",
    intelligence = "InfoPanelIconHeroIntellectValue",
}

local active_hero = nil
local fallback_visible = false
local native_tooltip_hidden = false
local hooked_frames = {}
local target_frames = {}
local install_timer = nil
local hover_timer = nil
local install_attempts = 0
local started = false
local installed = false
local warned = false
local logged_target_count = 0

local function get_local_player_id()
    if type(jass.GetLocalPlayer) ~= "function" or type(jass.GetPlayerId) ~= "function" then
        return nil
    end
    return jass.GetPlayerId(jass.GetLocalPlayer())
end

local function find_native_tooltip()
    return frame.get_tooltip()
end

local function set_native_tooltip_hidden(hidden)
    if native_tooltip_hidden == hidden then
        return
    end
    local native_tooltip = find_native_tooltip()
    if native_tooltip ~= nil then
        frame.set_visible(native_tooltip, not hidden)
    end
    native_tooltip_hidden = hidden
end

local function count_lines(text)
    local count = 1
    for _ in string.gmatch(text, "\n") do
        count = count + 1
    end
    return count
end

local function is_primary(attribute_id)
    return active_hero ~= nil
        and hero_stats.get_primary_attribute(active_hero) == attribute_id
end

--- 生成单个合并属性 Tips；只在当前主属性下显示“主要属性”。
---@return string description 项目当前三维属性说明
function module.build_description()
    local lines = {"英雄属性：", ""}
    for _, attribute_id in ipairs({"strength", "agility", "intelligence"}) do
        table.insert(lines, ATTRIBUTE_NAMES[attribute_id] .. "：")
        if is_primary(attribute_id) then
            table.insert(lines, "- |cffffff00主要属性|r")
        end
        if attribute_id == "strength" then
            table.insert(lines, "- 每点增加25点最大生命")
            table.insert(lines, "- 每10点增加1%生命增幅")
        elseif attribute_id == "agility" then
            table.insert(lines, "- 每10点增加1%普攻加成")
        else
            table.insert(lines, "- 每10点增加1%技能伤害")
        end
        table.insert(lines, "- 作为主属性时，每点增加2点攻击力")
        table.insert(lines, "- 作为非主属性时，每点增加1点攻击力")
        if attribute_id ~= "intelligence" then
            table.insert(lines, "")
        end
    end
    return table.concat(lines, "\n")
end

local function ensure_frames()
    return true
end

local function update_native_attribute_values()
    if active_hero == nil then
        return
    end
    local snapshot = hero_stats.get_snapshot(active_hero)
    local value_count = 0
    for attribute_id, name in pairs(ATTRIBUTE_VALUE_NAMES) do
        local value_frame = frame.find_by_name(name, HERO_INFO_CONTEXT)
        if value_frame ~= nil then
            frame.set_visible(value_frame, true)
            frame.set_text(value_frame, tostring(math.floor(tonumber(snapshot[attribute_id]) or 0)))
            value_count = value_count + 1
        end
    end

    -- 某些 1.27 客户端会把三项文字容器误判为不可见，只留下主属性图标。
    -- 找到至少两项数值时恢复这个原生容器；不创建新的属性面板，也不改变原生布局。
    if value_count >= 2 then
        local attribute_text = frame.find_by_name("SimpleInfoPanelIconHeroText", HERO_INFO_CONTEXT)
        if attribute_text ~= nil then
            frame.set_visible(attribute_text, true)
        end
    end
end

local function update_text()
    if not ensure_frames() then
        return false
    end
    local text = module.build_description()
    local line_count = count_lines(text)
    local height = math.min(0.48, 0.040 + line_count * 0.020)
    ui:set_text(text, height)
    update_native_attribute_values()
    return true
end

local function hide_fallback()
    fallback_visible = false
    ui:hide()
    set_native_tooltip_hidden(false)
end

local function show_fallback()
    if not update_text() then
        return false
    end
    set_native_tooltip_hidden(true)
    if not ui:show() then
        set_native_tooltip_hidden(false)
        return false
    end
    fallback_visible = true
    return true
end

local function bind_fallback(target)
    if target == nil or hooked_frames[target] then
        return false
    end
    local enter_callback = function()
        show_fallback()
    end
    local leave_callback = function()
        hide_fallback()
    end
    local enter_bound = frame.on_mouse_enter(target, enter_callback)
    local leave_bound = frame.on_mouse_leave(target, leave_callback)
    if not enter_bound or not leave_bound then
        return false
    end
    hooked_frames[target] = {
        enter = enter_callback,
        leave = leave_callback,
    }
    return true
end

local function add_target(target)
    if target == nil or target_frames[target] then
        return false
    end
    target_frames[target] = true
    bind_fallback(target)
    return true
end

local function install_targets()
    if not update_text() then
        return 0
    end
    local found_count = 0
    for _, name in ipairs(HERO_INFO_FRAME_NAMES) do
        local target = frame.find_by_name(name, HERO_INFO_CONTEXT)
        if target ~= nil then
            add_target(target)
            found_count = found_count + 1
        end
    end
    for _, name in ipairs(ATTRIBUTE_FRAME_NAMES) do
        local target = frame.find_by_name(name, HERO_INFO_CONTEXT)
        if target ~= nil then
            add_target(target)
            found_count = found_count + 1
        end
    end
    return found_count
end

local function poll_hover()
    if not installed then
        return
    end
    local focus = frame.get_mouse_focus()
    if focus ~= nil and target_frames[focus] then
        if not fallback_visible then
            show_fallback()
        end
    elseif fallback_visible then
        hide_fallback()
    end
end

local function start_hover_timer()
    if hover_timer ~= nil
        or type(jass.CreateTimer) ~= "function"
        or type(jass.TimerStart) ~= "function" then
        return
    end
    hover_timer = timer_service and timer_service.every(HOVER_POLL_INTERVAL, poll_hover, runtime_scope) or nil
end

local function install_hooks()
    if not frame.is_available() then
        return false
    end
    local found_count = install_targets()
    if found_count > 0 then
        installed = true
        start_hover_timer()
        if logged_target_count ~= found_count then
            logged_target_count = found_count
            print(string.format("英雄属性合并 Tooltip 已绑定：目标=%d", found_count))
        end
        return true
    end
    return false
end

local function stop_install_timer()
    if install_timer == nil then
        return
    end
    if timer_service ~= nil then timer_service.cancel(install_timer, runtime_scope) end
    install_timer = nil
end

local function schedule_install()
    if install_timer ~= nil or type(jass.CreateTimer) ~= "function" or type(jass.TimerStart) ~= "function" then
        return
    end
    install_attempts = 0
    install_timer = timer_service and timer_service.every(RETRY_INTERVAL, function()
        install_attempts = install_attempts + 1
        install_hooks()
        if install_attempts >= MAX_INSTALL_ATTEMPTS then
            if not installed then print("英雄属性 Tooltip 接入失败：未找到可用的英雄属性信息区") end
            stop_install_timer()
        end
    end, runtime_scope) or nil
end

--- 启动英雄属性合并 Tooltip。
---@param hero_results HeroSelectionResult[] 已创建的英雄结果
---@return boolean started_now 是否已启动或已安排启动
function module.start(hero_results)
    if started then
        return true
    end
    local player_id = get_local_player_id()
    if player_id == nil then
        return false
    end
    for _, result in ipairs(hero_results or {}) do
        if result.playerId == player_id then
            active_hero = result.unit
            break
        end
    end
    if active_hero == nil or not frame.is_available() then
        return false
    end
    runtime_scope = lifecycle and lifecycle.acquire("hero.ui.attribute_tooltip", function()
        if stats_event_token ~= nil and events ~= nil then events.off(stats_event_token) end
        stats_event_token = nil
        active_hero, hover_timer, install_timer, started = nil, nil, nil, false
        hide_fallback()
    end) or nil

    started = true
    local on_stats_changed = function(hero)
        if hero == active_hero then
            update_text()
            if fallback_visible then
                show_fallback()
            end
        end
    end
    if events ~= nil and type(events.on) == "function" then
        stats_event_token = events.on("hero.stats_changed", function(data)
            if data ~= nil then
                on_stats_changed(data.hero)
            end
        end, 0)
    else
        hero_stats.subscribe(on_stats_changed)
    end
    install_hooks()
    -- 原生属性子控件可能在英雄面板首次刷新后才出现，成功绑定整体容器后仍保留短时重试。
    schedule_install()
    return true
end

function module.stop()
    return lifecycle ~= nil and lifecycle.release("hero.ui.attribute_tooltip") or false
end

--- 手动隐藏当前自定义属性 Tips。
---@return nil
function module.hide()
    hide_fallback()
end

JiuDou.publish("gameplay.hero.ui.attribute_tooltip", module)
return module
