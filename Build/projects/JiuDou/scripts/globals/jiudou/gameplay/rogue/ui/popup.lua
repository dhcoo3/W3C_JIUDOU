--- 肉鸽奖励 UI 业务适配层。
--- 界面结构和控件由 jiudou_rogue_reward UIKit 提供；本文件不创建 Frame。

local ui = UIKit("jiudou_rogue_reward")
local module = {}

function module.show(options)
    return ui:show(options)
end

function module.hide()
    ui:hide()
end

function module.get_last_error()
    return ui:get_last_error()
end

function module.set_title(value)
    ui:set_title(value)
end

function module.set_subtitle(value)
    ui:set_subtitle(value)
end

function module.set_hero_portrait(path)
    ui:set_hero_portrait(path)
end

function module.set_hero_name(value)
    ui:set_hero_name(value)
end

function module.set_hero_level(value)
    ui:set_hero_level(value)
end

function module.set_card_type(slot, value)
    ui:set_card_type(slot, value)
end

function module.set_card_name(slot, value)
    ui:set_card_name(slot, value)
end

function module.set_card_level(slot, value)
    ui:set_card_level(slot, value)
end

function module.set_card_description(slot, value)
    ui:set_card_description(slot, value)
end

function module.set_card_icon(slot, path)
    ui:set_card_icon(slot, path)
end

function module.set_selected(slot)
    ui:set_selected(slot)
end

function module.set_remaining_seconds(value)
    ui:set_remaining_seconds(value)
end

function module.set_refresh_text(value)
    ui:set_refresh_text(value)
end

function module.set_confirm_text(value)
    ui:set_confirm_text(value)
end

function module.set_refresh_enabled(enabled)
    ui:set_refresh_enabled(enabled)
end

function module.set_confirm_enabled(enabled)
    ui:set_confirm_enabled(enabled)
end

JiuDou.publish("gameplay.rogue.ui.popup", module)
return module