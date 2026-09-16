--- 特殊怪计数 UIKit。
--- 套件不计算数量，只显示外部传入的文本。

local ui = UIKit("jiudou_special_count")
local text = nil

local function ensure_text()
    if text ~= nil then
        return text
    end
    text = UIText("jiudou_special_count:text", UIGame)
        :size(0.180, 0.025)
        :relation(UI_ALIGN_RIGHT_TOP, UIGame, UI_ALIGN_RIGHT_TOP, -0.018, -0.035)
        :fontSize(10)
        :textAlign(TEXT_ALIGN_RIGHT)
    return text
end

function ui:show()
    ensure_text():show(true)
    return true
end

function ui:hide()
    if text ~= nil then
        text:show(false)
    end
end

function ui:set_text(value)
    ensure_text():text(value or "")
end

function ui:is_visible()
    return text ~= nil and text:isShow()
end