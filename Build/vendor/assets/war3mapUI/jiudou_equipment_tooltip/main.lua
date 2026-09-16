--- 装备 Tooltip UIKit。
--- 只负责 Tooltip 面板和动态文本；装备数据与物品栏监听由外部业务层负责。

local ui = UIKit("jiudou_equipment_tooltip")
local view = nil

local function ensure_view()
    if view ~= nil then
        return view
    end
    view = {}
    view.root = UIBackdrop("jiudou_equipment_tooltip:root", UIGame)
        :size(0.470, 0.240)
        :relation(UI_ALIGN_CENTER, UIGame, UI_ALIGN_CENTER, 0.0, 0.0)
        :texture("panel")
    view.text = UIText("jiudou_equipment_tooltip:text", view.root)
        :size(0.430, 0.220)
        :relation(UI_ALIGN_CENTER, view.root, UI_ALIGN_CENTER, 0.0, 0.0)
        :fontSize(9)
        :textAlign(TEXT_ALIGN_LEFT)
    view.root:show(false)
    return view
end

function ui:set_text(value, height)
    local current = ensure_view()
    local text = tostring(value or "")
    local lines = 1
    for _ in string.gmatch(text, "\n") do
        lines = lines + 1
    end
    local panel_height = math.max(0.120, math.min(0.340, tonumber(height) or (0.055 + lines * 0.023)))
    current.root:size(0.470, panel_height)
    current.text:size(0.430, math.max(0.020, panel_height - 0.018))
    current.text:text(text)
end

function ui:show()
    ensure_view().root:show(true)
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