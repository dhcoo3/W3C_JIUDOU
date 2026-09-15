--- 右上角本地 HUD：显示全图金币怪与经验怪的合计存活数量。
local frame = require "platform.frame"

local module = {}
local started = false
local text_frame = nil
local count = 0
local max_count = 300
local TEMPLATE = "EscMenuLabelTextTemplate"

function module.start(limit)
    if started then return false end
    if not frame.is_available() then
        print("特殊怪计数 HUD 未启用：缺少 DzFrame 接口")
        return false
    end
    local parent = frame.get_game_ui()
    if parent == nil then return false end
    text_frame = frame.create("TEXT", "JiuDouSpecialMonsterCount", parent, TEMPLATE, 0)
    if text_frame == nil then return false end
    frame.set_size(text_frame, 0.18, 0.025)
    frame.set_point(text_frame, frame.POINT_TOPRIGHT, parent, frame.POINT_TOPRIGHT, -0.018, -0.035)
    max_count = math.max(1, math.floor(tonumber(limit) or max_count))
    started = true
    module.set_count(0)
    return true
end

function module.set_count(value)
    count = math.max(0, math.min(max_count, math.floor(tonumber(value) or 0)))
    if text_frame ~= nil then
        frame.set_text(text_frame, string.format("|cffffcc00特殊怪：%d/%d|r", count, max_count))
    end
end

function module.get_count() return count end

return module
