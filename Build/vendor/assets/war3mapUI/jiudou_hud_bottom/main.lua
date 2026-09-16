--- 九斗底部 HUD UIKit。
--- 只负责静态底板的创建和显示状态。

local ui = UIKit("jiudou_hud_bottom")
local root = nil

local PANEL_WIDTH = 0.80024
local PANEL_HEIGHT = 0.16318
local PANEL_LEFT = 0.00073
local PANEL_BOTTOM = 0.00052

local function ensure_root()
    if root ~= nil then
        return root
    end
    root = UIBackdrop("jiudou_hud_bottom:root", UIGame)
        :size(PANEL_WIDTH, PANEL_HEIGHT)
        :relation(UI_ALIGN_BOTTOMLEFT, UIGame, UI_ALIGN_BOTTOMLEFT, PANEL_LEFT, PANEL_BOTTOM)
        :texture("forest-bottom-strip")
    return root
end

function ui:show()
    ensure_root():show(true)
    return true
end

function ui:hide()
    if root ~= nil then
        root:show(false)
    end
end

function ui:is_visible()
    return root ~= nil and root:isShow()
end

function ui:get_last_error()
    return ""
end