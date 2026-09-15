--- 本地键盘输入适配层。
--- 业务模块不直接读取 JiuDou.runtime.japi，所有 JAPI 输入能力集中在 platform。
JiuDou = JiuDou or {}
JiuDou.platform = JiuDou.platform or {}
JiuDou.runtime = JiuDou.runtime or {}

local japi = {}
local module = {}
local callback_index = 0

local function refresh_japi()
    japi = (JiuDou.runtime and JiuDou.runtime.japi) or {}
    return japi
end

local function keyboard_api()
    local api = rawget(_G, "keyboard")
    if type(api) == "table" and type(api.onPress) == "function" then
        return api
    end
    return nil
end

function module.is_available()
    refresh_japi()
    return keyboard_api() ~= nil
        or (type(japi) == "table"
        and (type(japi.DzTriggerRegisterKeyEventByCode) == "function"
            or type(japi.DzTriggerRegisterKeyEvent) == "function"))
end

--- 注册本地键盘事件。
---@param trigger trigger Warcraft 触发器
---@param key_code integer JAPI 键码
---@param callback function 本地回调
---@param callback_name string|nil 旧版字符串回调名
---@return boolean registered
function module.register_key(trigger, key_code, callback, callback_name)
    refresh_japi()
    if type(callback) ~= "function" or not module.is_available() then
        return false
    end

    -- xlik 的标准键盘层负责对接当前 JAPI/KKWE 运行时；它也会用 key
    -- 作为注册标识覆盖同名回调，避免流程重进时重复触发。
    local keyboard = keyboard_api()
    if keyboard ~= nil then
        callback_index = callback_index + 1
        local name = callback_name or ("JiuDouLocalKeyCallback" .. tostring(callback_index))
        keyboard.onPress(key_code, name, function(event_data)
            local ok, message = pcall(callback, event_data)
            if not ok then
                print("本地快捷键回调异常：" .. tostring(message))
            end
        end)
        return true
    end

    if trigger == nil then
        return false
    end

    if type(japi.DzTriggerRegisterKeyEventByCode) == "function" then
        if type(J and J.Common and J.Common.TriggerAddAction) == "function" then
            J.Common.TriggerAddAction(trigger, callback)
        end
        local ok, result = pcall(japi.DzTriggerRegisterKeyEventByCode, trigger, key_code, 0, true, false)
        return ok and result ~= false
    end

    if type(japi.DzTriggerRegisterKeyEvent) == "function" then
        if type(J and J.Common and J.Common.TriggerAddAction) == "function" then
            J.Common.TriggerAddAction(trigger, callback)
        end
        local ok, result = pcall(japi.DzTriggerRegisterKeyEvent, trigger, key_code, 0, true, false)
        return ok and result ~= false
    end
    return false
end

JiuDou.platform.input = module
return module
