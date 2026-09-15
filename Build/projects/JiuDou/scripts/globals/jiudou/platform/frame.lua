--- DzFrame 平台适配层。
--- 负责封装 KKWE/YDWE 提供的动态本地界面 API，业务模块不得直接调用 JAPI。
JiuDou = JiuDou or {}
JiuDou.runtime = JiuDou.runtime or {}
local japi = {}

local function refresh_japi()
    japi = (JiuDou.runtime and JiuDou.runtime.japi) or {}
    return japi
end

local module = {}

local REQUIRED_API_NAMES = {
    "DzGetGameUI",
    "DzCreateFrameByTagName",
    "DzFrameSetPoint",
    "DzFrameSetSize",
    "DzFrameSetText",
    "DzFrameSetTexture",
    "DzFrameSetScriptByCode",
    "DzFrameShow",
    "DzDestroyFrame",
}

--- Warcraft III 的 FRAMEPOINT_TOPLEFT 枚举值。
module.POINT_TOPLEFT = 0
--- Warcraft III 的 FRAMEPOINT_TOP 枚举值。
module.POINT_TOP = 1
--- Warcraft III 的 FRAMEPOINT_TOPRIGHT 枚举值。
module.POINT_TOPRIGHT = 2
--- Warcraft III 的 FRAMEPOINT_LEFT 枚举值。
module.POINT_LEFT = 3
--- Warcraft III 的 FRAMEPOINT_CENTER 枚举值。
module.POINT_CENTER = 4
--- Warcraft III 的 FRAMEPOINT_RIGHT 枚举值。
module.POINT_RIGHT = 5
--- Warcraft III 的 FRAMEPOINT_BOTTOMLEFT 枚举值。
module.POINT_BOTTOMLEFT = 6
--- Warcraft III 的 FRAMEPOINT_BOTTOM 枚举值。
module.POINT_BOTTOM = 7
--- Warcraft III 的 FRAMEPOINT_BOTTOMRIGHT 枚举值。
module.POINT_BOTTOMRIGHT = 8

--- Warcraft III 的 FRAMEEVENT_CONTROL_CLICK 枚举值。
module.EVENT_CONTROL_CLICK = 1
--- DzFrame 鼠标移入事件。
module.EVENT_MOUSE_ENTER = 2
--- DzFrame 鼠标移出事件。
module.EVENT_MOUSE_LEAVE = 3

--- 获取当前运行时缺失的 DzFrame 接口名称。
---@return string[] names 缺失接口列表；为空时表示接口完整
function module.get_missing_api_names()
    refresh_japi()
    local names = {}
    if type(japi) ~= "table" then
        table.insert(names, "JAPI")
        return names
    end

    for _, name in ipairs(REQUIRED_API_NAMES) do
        if type(japi[name]) ~= "function" then
            table.insert(names, name)
        end
    end

    return names
end

--- 判断当前运行时是否支持创建动态 DzFrame 本地界面。
---@return boolean available 是否具备节点创建和控件操作接口
function module.is_available()
    return #module.get_missing_api_names() == 0
end

--- 获取游戏主界面，作为自定义界面的父节点。
---@return frame|nil parent 游戏主界面；接口缺失时为空
function module.get_game_ui()
    if not module.is_available() then
        return nil
    end

    return japi.DzGetGameUI()
end

--- 使用 Tag 创建界面节点，避免重复名称导致的退出崩溃。
---@param frame_type string DzFrame 节点类型
---@param name string 节点名称
---@param parent frame 父节点
---@param template string Warcraft III 内置模板名称
---@param frame_id integer 节点编号
---@return frame|nil created 创建结果
function module.create(frame_type, name, parent, template, frame_id)
    if not module.is_available() or parent == nil then
        return nil
    end

    -- 部分 KKWE 版本会把无效模板组合报告为 Lua/JASS 异常；本地 Tooltip
    -- 必须安全降级到原生界面，不能中断整张地图的运行时初始化。
    local ok, created = pcall(
        japi.DzCreateFrameByTagName,
        frame_type,
        name,
        parent,
        template or "",
        frame_id or 0
    )
    if not ok or created == nil or created == 0 then
        return nil
    end
    return created
end

--- 按 Warcraft 原生 Frame 名称查找界面节点。
--- 同时覆盖普通 Frame、SimpleFrame、SimpleFontString 和 SimpleTexture，
--- 主要用于接入物品栏与单英雄属性信息区。
---@param name string 原生 Frame 名称
---@param frame_id integer Frame 实例编号
---@return frame|nil found 找到的界面节点
function module.find_by_name(name, frame_id)
    if type(japi) ~= "table" then
        return nil
    end

    local found = nil
    if type(japi.DzFrameFindByName) == "function" then
        found = japi.DzFrameFindByName(name, frame_id or 0)
    end
    if (found == nil or found == 0) and type(japi.DzSimpleFrameFindByName) == "function" then
        found = japi.DzSimpleFrameFindByName(name, frame_id or 0)
    end
    if (found == nil or found == 0) and type(japi.DzSimpleFontStringFindByName) == "function" then
        found = japi.DzSimpleFontStringFindByName(name, frame_id or 0)
    end
    if (found == nil or found == 0) and type(japi.DzSimpleTextureFindByName) == "function" then
        found = japi.DzSimpleTextureFindByName(name, frame_id or 0)
    end
    if found == nil or found == 0 then
        return nil
    end
    return found
end

--- 直接获取原生 6 格物品栏按钮。
--- 这是比按名称查找更可靠的方式；部分客户端不会暴露 InventoryButton_* 名称。
---@param slot integer 0 到 5 的物品栏槽位
---@return frame|nil button 原生物品栏按钮
function module.get_item_bar_button(slot)
    if type(japi) ~= "table" then
        return nil
    end

    if type(japi.DzFrameGetItemBarButton) == "function" then
        local ok, button = pcall(japi.DzFrameGetItemBarButton, slot)
        if ok and button ~= nil and button ~= 0 then
            return button
        end
    end

    local prefixes = {
        "InventoryButton_",
        "SimpleInventoryButton_",
        "InventoryButton",
    }
    for _, prefix in ipairs(prefixes) do
        local button = module.find_by_name(prefix .. tostring(slot), 0)
        if button ~= nil then
            return button
        end
    end
    return nil
end

--- 获取 Warcraft 原生物品 Tooltip 根节点。
---@return frame|nil tooltip 原生 Tooltip；接口缺失时为空
function module.get_tooltip()
    if type(japi) ~= "table" or type(japi.DzFrameGetTooltip) ~= "function" then
        return nil
    end
    local ok, tooltip = pcall(japi.DzFrameGetTooltip)
    if not ok or tooltip == nil or tooltip == 0 then
        return nil
    end
    return tooltip
end

--- 设置节点的 Tooltip。
--- KKWE/YDWE 的 DzFrameSetTooltip 可在 Warcraft III 1.27 中替换原生 Tooltip。
---@param target frame 触发 Tooltip 的节点
---@param tooltip frame Tooltip 根节点
---@return boolean success 是否设置成功
function module.set_tooltip(target, tooltip)
    if target == nil or tooltip == nil or type(japi) ~= "table"
        or type(japi.DzFrameSetTooltip) ~= "function" then
        return false
    end
    return pcall(japi.DzFrameSetTooltip, target, tooltip)
end

--- 获取当前鼠标命中的本地 Frame。
--- 1.27 的原生 UI 没有 BlzFrameGetMouseFocus，KKAPI 通过 DzGetMouseFocus 提供同等能力。
---@return frame|nil target 当前鼠标命中的 Frame；接口缺失或没有命中时为空
function module.get_mouse_focus()
    if type(japi) ~= "table" or type(japi.DzGetMouseFocus) ~= "function" then
        return nil
    end
    local ok, target = pcall(japi.DzGetMouseFocus)
    if not ok or target == nil or target == 0 then
        return nil
    end
    return target
end

--- 设置节点相对锚点位置。
---@param target frame 目标节点
---@param point integer 目标锚点
---@param relative frame 参照节点
---@param relative_point integer 参照锚点
---@param offset_x number 横向偏移
---@param offset_y number 纵向偏移
---@return nil
function module.set_point(target, point, relative, relative_point, offset_x, offset_y)
    if target == nil or relative == nil or type(japi.DzFrameSetPoint) ~= "function" then
        return
    end

    japi.DzFrameSetPoint(target, point, relative, relative_point, offset_x, offset_y)
end

--- 设置节点尺寸。
---@param target frame 目标节点
---@param width number 宽度
---@param height number 高度
---@return nil
function module.set_size(target, width, height)
    if target == nil or type(japi.DzFrameSetSize) ~= "function" then
        return
    end

    japi.DzFrameSetSize(target, width, height)
end

--- 设置背景贴图。
---@param target frame 目标节点
---@param texture string 地图内贴图路径
---@param tiled integer 是否平铺，0 表示不平铺
---@return nil
function module.set_texture(target, texture, tiled)
    if target == nil or type(japi.DzFrameSetTexture) ~= "function" then
        return
    end

    japi.DzFrameSetTexture(target, texture, tiled or 0)
end

--- 设置节点文字。
---@param target frame 目标节点
---@param value string 显示文本
---@return nil
function module.set_text(target, value)
    if target == nil or type(japi.DzFrameSetText) ~= "function" then
        return
    end

    japi.DzFrameSetText(target, value)
end

--- 设置节点显示状态。
---@param target frame 目标节点
---@param visible boolean 是否显示
---@return nil
function module.set_visible(target, visible)
    if target == nil or type(japi.DzFrameShow) ~= "function" then
        return
    end

    japi.DzFrameShow(target, visible)
end

--- 设置节点透明度。
---@param target frame 目标节点
---@param alpha integer 透明度，范围 0 到 255
---@return nil
function module.set_alpha(target, alpha)
    if target == nil or type(japi.DzFrameSetAlpha) ~= "function" then
        return
    end

    japi.DzFrameSetAlpha(target, alpha)
end

--- 设置按钮可用状态。
---@param target frame 目标节点
---@param enabled boolean 是否可用
---@return nil
function module.set_enabled(target, enabled)
    if target == nil or type(japi.DzFrameSetEnable) ~= "function" then
        return
    end

    japi.DzFrameSetEnable(target, enabled)
end

--- 绑定本地点击回调。
---@param target frame 目标节点
---@param callback fun() 点击后的本地回调
---@return nil
function module.on_click(target, callback)
    if target == nil or type(japi.DzFrameSetScriptByCode) ~= "function" then
        return
    end

    japi.DzFrameSetScriptByCode(target, module.EVENT_CONTROL_CLICK, callback, false)
end

--- 绑定鼠标移入事件。
---@param target frame 目标节点
---@param callback fun() 鼠标移入后的本地回调
---@return boolean bound 是否成功绑定
function module.on_mouse_enter(target, callback)
    if target == nil or type(japi.DzFrameSetScriptByCode) ~= "function" then
        return false
    end
    local ok = pcall(japi.DzFrameSetScriptByCode, target, module.EVENT_MOUSE_ENTER, callback, false)
    return ok
end

--- 绑定鼠标移出事件。
---@param target frame 目标节点
---@param callback fun() 鼠标移出后的本地回调
---@return boolean bound 是否成功绑定
function module.on_mouse_leave(target, callback)
    if target == nil or type(japi.DzFrameSetScriptByCode) ~= "function" then
        return false
    end
    local ok = pcall(japi.DzFrameSetScriptByCode, target, module.EVENT_MOUSE_LEAVE, callback, false)
    return ok
end

--- 销毁根节点及其子节点。
---@param target frame|nil 根节点
---@return nil
function module.destroy(target)
    if target == nil or type(japi.DzDestroyFrame) ~= "function" then
        return
    end

    japi.DzDestroyFrame(target)
end

JiuDou.platform = JiuDou.platform or {}
JiuDou.platform.frame = module
return module
