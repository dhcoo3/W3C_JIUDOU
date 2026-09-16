--- 九斗底部 HUD 业务适配层。
--- 静态底板由 jiudou_hud_bottom UIKit 提供。

local ui = UIKit("jiudou_hud_bottom")
local module = {}

function module.show()
    return ui:show()
end

function module.hide()
    ui:hide()
end

function module.is_visible()
    return ui:is_visible()
end

function module.get_last_error()
    return ui:get_last_error()
end

JiuDou.publish("gameplay.hud.bottom", module)
return module