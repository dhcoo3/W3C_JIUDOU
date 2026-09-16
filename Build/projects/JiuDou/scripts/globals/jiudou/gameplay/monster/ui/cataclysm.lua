--- Boss 降临提示业务适配层。
--- 美术字由 jiudou_cataclysm UIKit 提供；本文件只负责显示时长。

local jass = J.Common
local ui = UIKit("jiudou_cataclysm")

local module = {}
local hide_timer = nil

local function hide()
    ui:hide()
    if hide_timer ~= nil then
        jass.PauseTimer(hide_timer)
        jass.DestroyTimer(hide_timer)
        hide_timer = nil
    end
end

function module.show()
    if not ui:show() then
        return false
    end
    if hide_timer ~= nil then
        jass.PauseTimer(hide_timer)
        jass.DestroyTimer(hide_timer)
        hide_timer = nil
    end
    if type(jass.CreateTimer) == "function"
        and type(jass.TimerStart) == "function" then
        hide_timer = jass.CreateTimer()
        jass.TimerStart(hide_timer, 3.5, false, hide)
    end
    return true
end

function module.hide()
    hide()
end

JiuDou.publish("gameplay.monster.ui.cataclysm", module)
return module