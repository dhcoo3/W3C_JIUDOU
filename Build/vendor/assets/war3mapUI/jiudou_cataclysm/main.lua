--- 天灾降临 UIKit。
--- 套件只负责静态美术字；显示时机和计时由外部业务层负责。

local ui = UIKit("jiudou_cataclysm")
local banner = nil

local function ensure_banner()
    if banner ~= nil then
        return banner
    end
    banner = UIBackdrop("jiudou_cataclysm:banner", UIGame)
        :size(0.420, 0.210)
        :relation(UI_ALIGN_CENTER, UIGame, UI_ALIGN_CENTER, 0.0, 0.170)
        :texture("cataclysm-title-v1")
    return banner
end

function ui:show()
    ensure_banner():show(true)
    return true
end

function ui:hide()
    if banner ~= nil then
        banner:show(false)
    end
end

function ui:is_visible()
    return banner ~= nil and banner:isShow()
end