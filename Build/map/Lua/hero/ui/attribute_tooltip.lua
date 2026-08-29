--- 英雄三维属性合并 Tooltip。
--- 优先替换原生属性区的 Tooltip；不支持直接替换时回退到整体区域悬停覆盖。
--- 所有显示操作均为本地界面操作，不修改同步游戏状态。
local jass = require "jass.common"
local frame = require "platform.frame"
local hero_stats = require "hero.stats"

local module = {}

local BACKDROP_TEMPLATE = "EscMenuControlBackdropTemplate"
local TEXT_TEMPLATE = "EscMenuLabelTextTemplate"
local HERO_INFO_CONTEXT = 6
local RETRY_INTERVAL = 0.5
local MAX_INSTALL_ATTEMPTS = 20

local ATTRIBUTE_NAMES = {
    strength = "力量",
    agility = "敏捷",
    intelligence = "智力",
}

local ATTRIBUTE_FRAME_NAMES = {
    "InfoPanelIconHeroStrengthLabel",
    "InfoPanelIconHeroStrengthValue",
    "InfoPanelIconHeroAgilityLabel",
    "InfoPanelIconHeroAgilityValue",
    "InfoPanelIconHeroIntellectLabel",
    "InfoPanelIconHeroIntellectValue",
}

local HERO_INFO_FRAME_NAMES = {
    "SimpleInfoPanelIconHeroText",
    "InfoPanelIconHeroIcon",
}

local active_hero = nil
local tooltip_root = nil
local tooltip_text = nil
local fallback_anchor = nil
local fallback_visible = false
local native_tooltip_hidden = false
local frame_id = 0
local hooked_frames = {}
local direct_targets = {}
local install_timer = nil
local install_attempts = 0
local started = false
local installed = false
local warned = false

local function get_local_player_id()
    if type(jass.GetLocalPlayer) ~= "function" or type(jass.GetPlayerId) ~= "function" then
        return nil
    end
    return jass.GetPlayerId(jass.GetLocalPlayer())
end

local function create_frame(frame_type, suffix, parent, template)
    frame_id = frame_id + 1
    return frame.create(frame_type, "JiuDouHeroAttributeTooltip" .. suffix .. frame_id, parent, template, frame_id)
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

local function build_description()
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
            table.insert(lines, "- 每10点增加1点护甲")
        elseif attribute_id == "intelligence" then
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
    if tooltip_root ~= nil and tooltip_text ~= nil then
        return true
    end
    if not frame.is_available() then
        if not warned then
            warned = true
            print("属性 Tooltip 不可用：当前运行时缺少 DzFrame 接口")
        end
        return false
    end
    local game_ui = frame.get_game_ui()
    if game_ui == nil then
        return false
    end

    tooltip_root = create_frame("BACKDROP", "Root", game_ui, BACKDROP_TEMPLATE)
    if tooltip_root == nil then
        return false
    end
    -- 文字作为 Tooltip 根节点的子节点，直接设置根节点为 Tooltip 时会一起移动和显示。
    tooltip_text = create_frame("TEXT", "Text", tooltip_root, TEXT_TEMPLATE)
    if tooltip_text == nil then
        return false
    end
    frame.set_point(tooltip_text, frame.POINT_CENTER, tooltip_root, frame.POINT_CENTER, 0.0, 0.0)
    frame.set_visible(tooltip_root, false)
    frame.set_visible(tooltip_text, false)
    return true
end

local function update_text()
    if not ensure_frames() then
        return false
    end
    local text = build_description()
    local line_count = count_lines(text)
    local height = math.min(0.48, 0.040 + line_count * 0.020)
    frame.set_size(tooltip_root, 0.47, height)
    frame.set_size(tooltip_text, 0.43, math.max(0.02, height - 0.018))
    frame.set_text(tooltip_text, text)
    return true
end

local function hide_fallback()
    fallback_visible = false
    if tooltip_root ~= nil then
        frame.set_visible(tooltip_root, false)
    end
    if tooltip_text ~= nil then
        frame.set_visible(tooltip_text, false)
    end
    set_native_tooltip_hidden(false)
end

local function show_fallback()
    if not update_text() then
        return false
    end
    local current_native_tooltip = find_native_tooltip()
    if current_native_tooltip ~= nil then
        fallback_anchor = current_native_tooltip
    end
    local anchor = fallback_anchor or frame.get_game_ui()
    if anchor == nil then
        return false
    end
    frame.set_point(tooltip_root, frame.POINT_CENTER, anchor, frame.POINT_CENTER, 0.0, 0.0)
    frame.set_point(tooltip_text, frame.POINT_CENTER, tooltip_root, frame.POINT_CENTER, 0.0, 0.0)
    set_native_tooltip_hidden(true)
    frame.set_visible(tooltip_root, true)
    frame.set_visible(tooltip_text, true)
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

local function install_direct_targets()
    if not update_text() then
        return 0
    end
    local count = 0
    for _, name in ipairs(HERO_INFO_FRAME_NAMES) do
        local target = frame.find_by_name(name, HERO_INFO_CONTEXT)
        if target ~= nil and not direct_targets[target] and frame.set_tooltip(target, tooltip_root) then
            direct_targets[target] = true
            count = count + 1
        elseif target ~= nil and direct_targets[target] then
            count = count + 1
        end
    end
    for _, name in ipairs(ATTRIBUTE_FRAME_NAMES) do
        local target = frame.find_by_name(name, HERO_INFO_CONTEXT)
        if target ~= nil and not direct_targets[target] and frame.set_tooltip(target, tooltip_root) then
            direct_targets[target] = true
            count = count + 1
        elseif target ~= nil and direct_targets[target] then
            count = count + 1
        end
    end
    return count
end

local function install_fallback_targets()
    local count = 0
    for _, name in ipairs(HERO_INFO_FRAME_NAMES) do
        local target = frame.find_by_name(name, HERO_INFO_CONTEXT)
        if target ~= nil and bind_fallback(target) then
            count = count + 1
        elseif target ~= nil and hooked_frames[target] then
            count = count + 1
        end
    end
    if count == 0 then
        for _, name in ipairs(ATTRIBUTE_FRAME_NAMES) do
            local target = frame.find_by_name(name, HERO_INFO_CONTEXT)
            if target ~= nil and bind_fallback(target) then
                count = count + 1
            elseif target ~= nil and hooked_frames[target] then
                count = count + 1
            end
        end
    end
    return count
end

local function install_hooks()
    if not frame.is_available() then
        return false
    end
    local direct_count = install_direct_targets()
    if direct_count > 0 then
        installed = true
        print(string.format("英雄属性合并 Tooltip 已接管：直接 Tooltip=%d", direct_count))
        return true
    end

    local fallback_count = install_fallback_targets()
    if fallback_count > 0 then
        installed = true
        print(string.format("英雄属性合并 Tooltip 已接管：悬停区域=%d", fallback_count))
        return true
    end
    return false
end

local function stop_install_timer()
    if install_timer == nil then
        return
    end
    jass.PauseTimer(install_timer)
    jass.DestroyTimer(install_timer)
    install_timer = nil
end

local function schedule_install()
    if install_timer ~= nil or type(jass.CreateTimer) ~= "function" or type(jass.TimerStart) ~= "function" then
        return
    end
    install_attempts = 0
    install_timer = jass.CreateTimer()
    jass.TimerStart(install_timer, RETRY_INTERVAL, true, function()
        install_attempts = install_attempts + 1
        if install_hooks() or install_attempts >= MAX_INSTALL_ATTEMPTS then
            if not installed then
                print("英雄属性 Tooltip 接入失败：未找到可用的英雄属性信息区")
            end
            stop_install_timer()
        end
    end)
end

--- 启动英雄属性合并 Tooltip。
---@param hero_results HeroSelectionResult[]
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

    started = true
    hero_stats.subscribe(function(hero)
        if hero == active_hero then
            update_text()
            if fallback_visible then
                show_fallback()
            end
        end
    end)
    if not install_hooks() then
        schedule_install()
    end
    return true
end

function module.hide()
    hide_fallback()
end

return module
