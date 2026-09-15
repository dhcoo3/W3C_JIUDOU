--- 肉鸽奖励的本地 DzFrame 界面。
local frame = require "platform.frame"
local assets = require "rogue.ui.assets"
local config = require "rogue.config"

local module = {}
local BACKDROP_TEMPLATE = "EscMenuControlBackdropTemplate"
local TEXT_TEMPLATE = "EscMenuLabelTextTemplate"
local CARD_COUNT = 3
local next_frame_id = 0
local current_popup = nil
local last_error = ""

local function create_frame(frame_type, suffix, parent, template)
    next_frame_id = next_frame_id + 1
    return frame.create(frame_type, "JiuDouRogue" .. suffix .. next_frame_id, parent, template, next_frame_id)
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

local function create_click_target(parent, suffix, width, height, x, y, callback, popup)
    local target = create_frame("BUTTON", suffix, parent, "ScriptDialogButton")
    frame.set_size(target, width, height)
    frame.set_point(target, frame.POINT_CENTER, parent, frame.POINT_CENTER, x, y)
    frame.set_alpha(target, 1)
    frame.on_click(target, callback)
    table.insert(popup.callbacks, callback)
    return target
end

local function level_text(current_level)
    if current_level <= 0 then return "新效果  →  I" end
    local roman = {"I", "II", "III"}
    return roman[current_level] .. "  →  " .. roman[current_level + 1]
end

local function set_selected(effect_id)
    if current_popup == nil then return end
    for id, card in pairs(current_popup.cards) do
        frame.set_visible(card.selected, id == effect_id)
    end
end

local function create_card(popup, choice, index, options)
    local effect = choice.effect
    local y = 0.086 - (index - 1) * 0.118
    create_backdrop(popup.root, "CardNormal" .. effect.effectId, 0.590, 0.108, 0.018, y, assets.cardNormal)
    local selected = create_backdrop(popup.root, "CardSelected" .. effect.effectId, 0.590, 0.108, 0.018, y, assets.cardSelected)
    frame.set_visible(selected, false)
    create_backdrop(popup.root, "IconFrame" .. effect.effectId, 0.073, 0.073, -0.225, y, assets.iconFrame)
    create_backdrop(popup.root, "Icon" .. effect.effectId, 0.055, 0.055, -0.225, y, effect.icon)
    local type_name = effect.type == "Skill" and "英雄技能" or "通用强化"
    create_text(popup.root, "Type" .. effect.effectId, 0.105, 0.019, -0.128, y + 0.031, type_name)
    create_text(popup.root, "Name" .. effect.effectId, 0.205, 0.027, -0.050, y + 0.008, effect.name)
    create_text(popup.root, "Level" .. effect.effectId, 0.120, 0.021, 0.183, y + 0.031, level_text(choice.currentLevel))
    create_text(
        popup.root,
        "Description" .. effect.effectId,
        0.420,
        0.033,
        0.045,
        y - 0.028,
        config.format_description(effect, choice.nextLevel)
    )
    create_click_target(popup.root, "CardButton" .. effect.effectId, 0.584, 0.102, 0.018, y, function()
        options.onSelected(effect.effectId)
    end, popup)
    popup.cards[effect.effectId] = {selected = selected}
end

function module.hide()
    if current_popup == nil then return end
    frame.destroy(current_popup.root)
    current_popup = nil
end

function module.show(options)
    module.hide()
    last_error = ""
    if type(options) ~= "table" or type(options.choices) ~= "table" or #options.choices ~= CARD_COUNT then
        last_error = "肉鸽界面参数不完整"
        return false
    end
    if not frame.is_available() then
        last_error = "缺少 DzFrame 接口：" .. table.concat(frame.get_missing_api_names(), ", ")
        return false
    end
    local parent = frame.get_game_ui()
    if parent == nil then last_error = "无法获取游戏主界面" return false end
    local root = create_backdrop(parent, "Root", 0.760, 0.540, 0.0, 0.0, assets.panel)
    if root == nil or root == 0 then last_error = "DzFrame 面板创建失败" return false end
    local popup = {root = root, cards = {}, callbacks = {}}
    current_popup = popup

    create_text(root, "Title", 0.300, 0.040, 0.0, 0.218, "命运强化")
    create_text(root, "Subtitle", 0.420, 0.023, 0.0, 0.187, "从 3 项肉鸽强化中选择 1 项")
    if options.hero and options.hero.portrait then
        create_backdrop(root, "HeroPortrait", 0.054, 0.054, -0.295, 0.190, options.hero.portrait)
    end
    local hero_name = options.hero and options.hero.name or options.heroRawcode or "英雄"
    create_text(root, "HeroName", 0.155, 0.024, -0.205, 0.205, hero_name)
    create_text(root, "HeroLevel", 0.155, 0.020, -0.205, 0.179, string.format("英雄等级 %d  ·  奖励 #%d", options.heroLevel, options.offerSerial))
    create_backdrop(root, "TimerBackground", 0.084, 0.070, 0.306, 0.202, assets.timer)
    popup.timerText = create_text(root, "TimerText", 0.070, 0.027, 0.306, 0.202, "20 秒")

    for index, choice in ipairs(options.choices) do create_card(popup, choice, index, options) end

    create_backdrop(root, "RefreshBackground", 0.175, 0.052, -0.120, -0.242, assets.refresh)
    popup.refreshText = create_text(root, "RefreshText", 0.150, 0.028, -0.120, -0.242, "刷新强化")
    popup.refreshButton = create_click_target(root, "RefreshButton", 0.175, 0.052, -0.120, -0.242, options.onRefresh, popup)
    create_backdrop(root, "ConfirmBackground", 0.175, 0.052, 0.120, -0.242, assets.confirm)
    popup.confirmText = create_text(root, "ConfirmText", 0.150, 0.028, 0.120, -0.242, "确认强化")
    popup.confirmButton = create_click_target(root, "ConfirmButton", 0.175, 0.052, 0.120, -0.242, options.onConfirm, popup)
    module.set_selected(nil)
    module.set_remaining_seconds(options.remainingSeconds)
    module.set_refresh_remaining(options.freeRefreshRemaining, options.bonusRefreshRemaining)
    return true
end

function module.get_last_error() return last_error end

function module.set_selected(effect_id)
    if current_popup == nil then return end
    set_selected(effect_id)
    frame.set_enabled(current_popup.confirmButton, effect_id ~= nil)
    frame.set_text(current_popup.confirmText, effect_id and "确认强化" or "请选择强化")
end

function module.set_remaining_seconds(seconds)
    if current_popup ~= nil then frame.set_text(current_popup.timerText, string.format("%d 秒", math.max(0, seconds or 0))) end
end

function module.set_refresh_remaining(free_count, bonus_count)
    if current_popup == nil then return end
    local total = math.max(0, free_count or 0) + math.max(0, bonus_count or 0)
    frame.set_text(current_popup.refreshText, string.format("刷新强化（%d）", total))
    frame.set_enabled(current_popup.refreshButton, total > 0)
end

return module
