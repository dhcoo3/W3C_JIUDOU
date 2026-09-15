--- 九斗底部 HUD 静态底板。
--- 负责在游戏主界面底部创建整张装饰面板，不处理英雄、技能和物品数据。
local frame = require "platform.frame"

local module = {}

local BACKDROP_TEMPLATE = "EscMenuControlBackdropTemplate"
local BACKDROP_TEXTURE = "ui\\main\\forest_bottom_strip.blp"
local FRAME_NAME = "JiuDouHUDBottomBackground"
local FRAME_ID = 1

-- 保留 mainBottom.lua 导出的原始范围，并改用底部相对锚点定位。
local PANEL_WIDTH = 0.80024
local PANEL_HEIGHT = 0.16318
local PANEL_LEFT = 0.00073
local PANEL_BOTTOM = 0.00052

local root = nil
local visible = false
local last_error = ""

--- 创建底部 HUD 的静态背景。
---@param parent frame 游戏主界面父节点
---@return boolean created 是否创建成功
local function create_background(parent)
    root = frame.create(
        "BACKDROP",
        FRAME_NAME,
        parent,
        BACKDROP_TEMPLATE,
        FRAME_ID
    )
    if root == nil or root == 0 then
        root = nil
        last_error = "底部 HUD 背景 Frame 创建失败"
        return false
    end

    frame.set_size(root, PANEL_WIDTH, PANEL_HEIGHT)
    frame.set_point(
        root,
        frame.POINT_BOTTOMLEFT,
        parent,
        frame.POINT_BOTTOMLEFT,
        PANEL_LEFT,
        PANEL_BOTTOM
    )
    frame.set_texture(root, BACKDROP_TEXTURE, 0)
    frame.set_visible(root, true)
    visible = true
    return true
end

--- 显示底部 HUD 静态底板。
--- 重复调用时只恢复显示，不会创建重复 Frame。
---@return boolean shown 是否显示成功
function module.show()
    last_error = ""
    if root ~= nil then
        frame.set_visible(root, true)
        visible = true
        return true
    end

    if not frame.is_available() then
        last_error = "缺少 DzFrame 接口：" .. table.concat(frame.get_missing_api_names(), ", ")
        return false
    end

    local parent = frame.get_game_ui()
    if parent == nil then
        last_error = "无法获取游戏主界面"
        return false
    end

    return create_background(parent)
end

--- 隐藏并销毁底部 HUD 静态底板。
---@return nil
function module.hide()
    if root == nil then
        visible = false
        return
    end

    frame.destroy(root)
    root = nil
    visible = false
end

--- 判断底部 HUD 是否正在显示。
---@return boolean shown 是否正在显示
function module.is_visible()
    return visible and root ~= nil
end

--- 获取最近一次底部 HUD 创建失败的原因。
---@return string message 失败原因；成功时为空字符串
function module.get_last_error()
    return last_error
end

return module
