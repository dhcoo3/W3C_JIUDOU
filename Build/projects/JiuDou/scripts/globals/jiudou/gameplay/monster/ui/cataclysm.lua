--- Boss 降临提示的本地美术字界面。
--- 只操作 DzFrame，不参与任何同步状态或游戏判定。
local jass = require "jass.common"
local frame = require "platform.frame"

local module = {}

local BANNER_TEXTURE = "ui\\monster\\cataclysm-title-v1.blp"
local BANNER_WIDTH = 0.420
local BANNER_HEIGHT = 0.210
local BANNER_OFFSET_Y = 0.170
local DISPLAY_SECONDS = 3.5

local banner = nil
local hide_timer = nil
local frame_id = 0
local warned_unavailable = false

local function hide()
    if banner ~= nil then
        frame.set_visible(banner, false)
    end
    if hide_timer ~= nil then
        jass.PauseTimer(hide_timer)
        jass.DestroyTimer(hide_timer)
        hide_timer = nil
    end
end

local function create_banner()
    if banner ~= nil then
        return true
    end
    if not frame.is_available() then
        if not warned_unavailable then
            print("天灾降临提示未启用：缺少 DzFrame 接口（" .. table.concat(frame.get_missing_api_names(), ", ") .. "）")
            warned_unavailable = true
        end
        return false
    end

    local parent = frame.get_game_ui()
    if parent == nil then
        return false
    end
    frame_id = frame_id + 1
    banner = frame.create(
        "BACKDROP",
        "JiuDouCataclysmBanner" .. frame_id,
        parent,
        "EscMenuControlBackdropTemplate",
        frame_id
    )
    if banner == nil or banner == 0 then
        banner = nil
        print("天灾降临提示未启用：DzFrame 创建失败")
        return false
    end
    frame.set_size(banner, BANNER_WIDTH, BANNER_HEIGHT)
    frame.set_point(banner, frame.POINT_CENTER, parent, frame.POINT_CENTER, 0.0, BANNER_OFFSET_Y)
    frame.set_texture(banner, BANNER_TEXTURE, 0)
    frame.set_visible(banner, false)
    return true
end

--- 显示一次 Boss 降临美术字；连续 Boss 出现时会重置显示时长。
--- 此函数只产生本地 UI 效果，不能在其中添加随机数或游戏状态。
---@return boolean shown
function module.show()
    if not create_banner() then
        return false
    end

    hide()
    frame.set_visible(banner, true)
    if type(jass.CreateTimer) == "function" and type(jass.TimerStart) == "function" then
        hide_timer = jass.CreateTimer()
        jass.TimerStart(hide_timer, DISPLAY_SECONDS, false, hide)
    end
    return true
end

return module
