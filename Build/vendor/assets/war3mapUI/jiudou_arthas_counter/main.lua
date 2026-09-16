--- 阿尔萨斯技能计数 UIKit。
--- 套件只显示外部传入的堆叠文本，不查找技能或英雄数据。

local ui = UIKit("jiudou_arthas_counter")
local text = nil

local function ensure_text()
    if text ~= nil then
        return text
    end
    text = UIText("jiudou_arthas_counter:text", UIGame)
        :size(0.040, 0.022)
        :relation(UI_ALIGN_BOTTOMRIGHT, UIGame, UI_ALIGN_BOTTOMRIGHT, -0.155, 0.082)
        :fontSize(10)
        :textAlign(TEXT_ALIGN_CENTER)
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