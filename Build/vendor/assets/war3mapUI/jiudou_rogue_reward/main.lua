--- 肉鸽奖励 UIKit。
--- 只负责界面结构、静态皮肤和公开控件方法，不保存奖励业务数据。

local ui = UIKit("jiudou_rogue_reward")

local VIEW_KIT = "jiudou_rogue_reward"
local CARD_COUNT = 3
local view = nil

local TEXT_GOLD = "F3E4BE"
local TEXT_CYAN = "4BE5F5"
local TEXT_MUTED = "B8C2BC"
local TEXT_DISABLED = "7E8982"
local TEXT_WARNING = "F09A45"

local function key(name)
    return VIEW_KIT .. ":" .. name
end

local function place(control, parent, width, height, offset_x, offset_y)
    control:size(width, height)
        :relation(UI_ALIGN_CENTER, parent, UI_ALIGN_CENTER, offset_x, offset_y)
    return control
end

local function set_text(control, value, color)
    if control == nil then
        return
    end
    control._kitText = tostring(value or "")
    local text = control._kitText
    if color ~= nil then
        text = string.format("|cff%s%s|r", color, text)
    end
    control:text(text)
end

local function backdrop(name, parent, width, height, offset_x, offset_y, texture)
    local control = UIBackdrop(key(name), parent)
    place(control, parent, width, height, offset_x, offset_y)
    if texture ~= nil then
        control:texture(texture)
    end
    return control
end

local function text(name, parent, width, height, offset_x, offset_y)
    return place(
        UIText(key(name), parent),
        parent,
        width,
        height,
        offset_x,
        offset_y
    )
end

local function invoke(name, ...)
    local callbacks = view and view.callbacks
    local callback = callbacks and callbacks[name]
    if type(callback) == "function" then
        callback(...)
    end
end

local function button(name, parent, width, height, offset_x, offset_y, callback, event_key)
    local control = place(
        UIButton(key(name), parent, {
            _highlightFdfName = false,
            _hasBorder = false,
            _hasMark = false,
        }),
        parent,
        width,
        height,
        offset_x,
        offset_y
    )
    control:onEvent(eventKind.uiLeftClick, event_key or VIEW_KIT, callback)
    return control
end

local function create_card(index)
    local card_offset_y = 0.086 - (index - 1) * 0.118
    local card = {
        normal = backdrop(
            "card" .. index .. ":normal",
            view.root,
            0.590,
            0.108,
            0.018,
            card_offset_y,
            "card-normal"
        ),
        selected = backdrop(
            "card" .. index .. ":selected",
            view.root,
            0.590,
            0.108,
            0.018,
            card_offset_y,
            "card-selected"
        ),
        iconFrame = backdrop(
            "card" .. index .. ":iconFrame",
            view.root,
            0.073,
            0.073,
            -0.225,
            card_offset_y,
            "icon-frame"
        ),
        icon = backdrop(
            "card" .. index .. ":icon",
            view.root,
            0.055,
            0.055,
            -0.225,
            card_offset_y
        ),
        type = text(
            "card" .. index .. ":type",
            view.root,
            0.105,
            0.019,
            -0.128,
            card_offset_y + 0.031
        ),
        name = text(
            "card" .. index .. ":name",
            view.root,
            0.205,
            0.027,
            -0.050,
            card_offset_y + 0.008
        ),
        level = text(
            "card" .. index .. ":level",
            view.root,
            0.120,
            0.021,
            0.183,
            card_offset_y + 0.031
        ),
        description = text(
            "card" .. index .. ":description",
            view.root,
            0.420,
            0.033,
            0.045,
            card_offset_y - 0.028
        ),
    }

    card.button = button(
        "card" .. index .. ":button",
        view.root,
        0.584,
        0.102,
        0.018,
        card_offset_y,
        function()
            invoke("onSelected", index)
        end,
        VIEW_KIT .. ":card" .. index
    )
    card.selected:show(false)
    return card
end

local function create_view(callbacks)
    view = {
        callbacks = callbacks or {},
        cards = {},
    }
    view.root = backdrop("root", UIGame, 0.760, 0.540, 0.0, 0.0, "panel")
    view.title = text("title", view.root, 0.300, 0.040, 0.0, 0.218)
    view.subtitle = text("subtitle", view.root, 0.420, 0.023, 0.0, 0.187)
    view.heroPortrait = backdrop("hero:portrait", view.root, 0.054, 0.054, -0.295, 0.190)
    view.heroName = text("hero:name", view.root, 0.155, 0.024, -0.205, 0.205)
    view.heroLevel = text("hero:level", view.root, 0.270, 0.020, -0.205, 0.179)
    view.timerBackground = backdrop("timer:background", view.root, 0.084, 0.070, 0.306, 0.202, "timer")
    view.timerText = text("timer:text", view.root, 0.070, 0.027, 0.306, 0.202)
    for index = 1, CARD_COUNT do
        view.cards[index] = create_card(index)
    end
    view.refreshBackground = backdrop("refresh:background", view.root, 0.175, 0.052, -0.120, -0.242, "button-refresh")
    view.refreshText = text("refresh:text", view.root, 0.150, 0.028, -0.120, -0.242)
    view.refreshButton = button(
        "refresh:button",
        view.root,
        0.175,
        0.052,
        -0.120,
        -0.242,
        function()
            invoke("onRefresh")
        end,
        VIEW_KIT .. ":refresh"
    )
    view.confirmBackground = backdrop("confirm:background", view.root, 0.175, 0.052, 0.120, -0.242, "button-confirm")
    view.confirmText = text("confirm:text", view.root, 0.150, 0.028, 0.120, -0.242)
    view.confirmButton = button(
        "confirm:button",
        view.root,
        0.175,
        0.052,
        0.120,
        -0.242,
        function()
            invoke("onConfirm")
        end,
        VIEW_KIT .. ":confirm"
    )
    return view
end

local function clear_dynamic()
    set_text(view.title, "", TEXT_GOLD)
    set_text(view.subtitle, "", TEXT_MUTED)
    view.heroPortrait:texture(X_UI_NIL)
    set_text(view.heroName, "", TEXT_GOLD)
    set_text(view.heroLevel, "", TEXT_MUTED)
    set_text(view.timerText, "", TEXT_CYAN)
    for _, card in ipairs(view.cards) do
        card.selected:show(false)
        card.icon:texture(X_UI_NIL)
        set_text(card.type, "", TEXT_MUTED)
        set_text(card.name, "", TEXT_GOLD)
        set_text(card.level, "", TEXT_MUTED)
        set_text(card.description, "", TEXT_MUTED)
    end
    set_text(view.refreshText, "", TEXT_GOLD)
    set_text(view.confirmText, "", TEXT_GOLD)
    view.refreshButton:alpha(100)
    view.confirmButton:alpha(100)
    view.refreshButton:onEvent(eventKind.uiLeftClick, VIEW_KIT .. ":refresh", nil)
    view.confirmButton:onEvent(eventKind.uiLeftClick, VIEW_KIT .. ":confirm", nil)
end

function ui:show(options)
    options = type(options) == "table" and options or {}
    if view == nil then
        create_view(options)
    else
        view.callbacks = options
        view.root:show(false)
    end
    clear_dynamic()
    view.root:show(true)
    return true
end

function ui:hide()
    if view ~= nil and view.root ~= nil then
        view.root:show(false)
    end
end

function ui:set_title(value)
    set_text(view and view.title, value, TEXT_GOLD)
end

function ui:set_subtitle(value)
    set_text(view and view.subtitle, value, TEXT_MUTED)
end

function ui:set_hero_portrait(path)
    if view ~= nil and type(path) == "string" then
        view.heroPortrait:texture(path)
    end
end

function ui:set_hero_name(value)
    set_text(view and view.heroName, value, TEXT_GOLD)
end

function ui:set_hero_level(value)
    set_text(view and view.heroLevel, value, TEXT_MUTED)
end

function ui:set_card_type(slot, value)
    set_text(view and view.cards[slot] and view.cards[slot].type, value, TEXT_MUTED)
end

function ui:set_card_name(slot, value)
    set_text(view and view.cards[slot] and view.cards[slot].name, value, TEXT_GOLD)
end

function ui:set_card_level(slot, value)
    set_text(view and view.cards[slot] and view.cards[slot].level, value, TEXT_MUTED)
end

function ui:set_card_description(slot, value)
    set_text(view and view.cards[slot] and view.cards[slot].description, value, TEXT_MUTED)
end

function ui:set_card_icon(slot, path)
    local card = view and view.cards[slot]
    if card ~= nil and type(path) == "string" then
        card.icon:texture(path)
    end
end

function ui:set_selected(slot)
    if view == nil then
        return
    end
    for index, card in ipairs(view.cards) do
        card.selected:show(index == slot)
    end
end

function ui:set_remaining_seconds(value)
    local display = tostring(value or "")
    local number = tonumber(string.match(display, "^%s*(%d+)"))
    set_text(view and view.timerText, display, number ~= nil and number <= 5 and TEXT_WARNING or TEXT_CYAN)
end

local function set_enabled(button_control, text_control, background, enabled, callback, event_key)
    if button_control == nil then
        return
    end
    enabled = enabled == true
    button_control:onEvent(eventKind.uiLeftClick, event_key, enabled and callback or nil)
    button_control:alpha(enabled and 255 or 100)
    set_text(text_control, text_control._kitText or "", enabled and TEXT_GOLD or TEXT_DISABLED)
    if background ~= nil then
        background:alpha(enabled and 255 or 100)
    end
end

function ui:set_refresh_text(value)
    set_text(view and view.refreshText, value, TEXT_GOLD)
end

function ui:set_confirm_text(value)
    set_text(view and view.confirmText, value, TEXT_GOLD)
end

function ui:set_refresh_enabled(enabled)
    set_enabled(
        view and view.refreshButton,
        view and view.refreshText,
        view and view.refreshBackground,
        enabled,
        function() invoke("onRefresh") end,
        VIEW_KIT .. ":refresh"
    )
end

function ui:set_confirm_enabled(enabled)
    set_enabled(
        view and view.confirmButton,
        view and view.confirmText,
        view and view.confirmBackground,
        enabled,
        function() invoke("onConfirm") end,
        VIEW_KIT .. ":confirm"
    )
end

function ui:get_last_error()
    return ""
end