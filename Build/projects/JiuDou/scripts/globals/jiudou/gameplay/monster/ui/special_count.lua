--- 特殊怪计数 HUD 业务适配层。
--- 数量计算由 monster.main 负责，UIKit 只显示传入文本。

local ui = UIKit("jiudou_special_count")

local module = {}
local started = false
local count = 0
local max_count = 300

function module.start(limit)
    if started then
        return false
    end
    max_count = math.max(1, math.floor(tonumber(limit) or max_count))
    if not ui:show() then
        return false
    end
    started = true
    module.set_count(0)
    return true
end

function module.set_count(value)
    count = math.max(0, math.min(max_count, math.floor(tonumber(value) or 0)))
    if started then
        ui:set_text(string.format("|cffffcc00特殊怪：%d/%d|r", count, max_count))
    end
end

function module.get_count()
    return count
end

JiuDou.publish("gameplay.monster.ui.special_count", module)
return module