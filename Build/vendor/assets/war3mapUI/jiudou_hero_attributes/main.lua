--- 英雄属性面板 UIKit。
--- 套件只负责面板结构、静态皮肤和动态文本控件。

local ui = UIKit("jiudou_hero_attributes")
local view = nil

local function invoke(name, ...)
    local callback = view and view.callbacks and view.callbacks[name]
    if type(callback) == "function" then
        callback(...)
    end
end

local function ensure_view(callbacks)
    if view ~= nil then
        if callbacks ~= nil then
            view.callbacks = callbacks
        end
        return view
    end

    view = {
        callbacks = callbacks or {},
    }
    view.root = UIBackdrop("jiudou_hero_attributes:root", UIGame)
        :size(0.278, 0.480)
        :relation(UI_ALIGN_CENTER, UIGame, UI_ALIGN_CENTER, -0.335, 0.012)
        :texture("panel")
    view.title = UIText("jiudou_hero_attributes:title", view.root)
        :size(0.230, 0.030)
        :relation(UI_ALIGN_CENTER, view.root, UI_ALIGN_CENTER, 0.0, 0.142)
        :fontSize(11)
    view.content = UIText("jiudou_hero_attributes:content", view.root)
        :size(0.235, 0.400)
        :relation(UI_ALIGN_CENTER, view.root, UI_ALIGN_CENTER, 0.0, -0.015)
        :fontSize(9)
        :textAlign(TEXT_ALIGN_LEFT)
    view.button = UIButton("jiudou_hero_attributes:toggle", UIGame, {
        _highlightFdfName = false,
        _hasBorder = false,
        _hasMark = false,
    })
        :size(0.078, 0.030)
        :relation(UI_ALIGN_CENTER, UIGame, UI_ALIGN_CENTER, -0.340, 0.278)
    view.buttonText = UIText("jiudou_hero_attributes:toggle:text", UIGame)
        :size(0.068, 0.022)
        :relation(UI_ALIGN_CENTER, UIGame, UI_ALIGN_CENTER, -0.340, 0.278)
        :fontSize(9)
    view.button:onEvent(eventKind.uiLeftClick, "jiudou_hero_attributes:toggle", function()
        invoke("onToggle")
    end)
    view.root:show(false)
    return view
end

function ui:show(options)
    options = type(options) == "table" and options or nil
    ensure_view(options)
    view.root:show(true)
    return true
end

function ui:hide()
    if view ~= nil then
        view.root:show(false)
    end
end

function ui:is_visible()
    return view ~= nil and view.root:isShow()
end

function ui:set_title(value)
    ensure_view().title:text(tostring(value or ""))
end

function ui:set_content(value)
    ensure_view().content:text(tostring(value or ""))
end

function ui:set_button_text(value)
    ensure_view().buttonText:text(tostring(value or ""))
end

function ui:get_last_error()
    return ""
end