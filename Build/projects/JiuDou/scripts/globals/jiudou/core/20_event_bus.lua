--- JiuDou 业务事件总线。
--- 将原生触发器和玩法模块解耦，支持优先级、一次性监听和消费事件。
JiuDou = JiuDou or {}
JiuDou.core = JiuDou.core or {}

local log = JiuDou.core.log
local module = {
    _events = {},
    _next_id = 0,
}

local function get_list(name, create)
    local list = module._events[name]
    if list == nil and create then
        list = {}
        module._events[name] = list
    end
    return list
end

local function sort_handlers(list)
    table.sort(list, function(left, right)
        if left.priority == right.priority then
            return left.id < right.id
        end
        return left.priority > right.priority
    end)
end

--- 注册事件监听。
---@param name string 事件名
---@param callback function 回调，参数为 payload、事件名
---@param priority integer|nil 数值越大越早执行
---@return table token 监听令牌
function module.on(name, callback, priority)
    if type(name) ~= "string" or name == "" or type(callback) ~= "function" then
        return nil
    end

    module._next_id = module._next_id + 1
    local token = {
        id = module._next_id,
        name = name,
        callback = callback,
        priority = tonumber(priority) or 0,
        active = true,
        once = false,
    }
    local list = get_list(name, true)
    table.insert(list, token)
    sort_handlers(list)
    return token
end

function module.once(name, callback, priority)
    local token = module.on(name, callback, priority)
    if token ~= nil then
        token.once = true
    end
    return token
end

function module.off(token)
    if type(token) ~= "table" then
        return false
    end
    token.active = false
    return true
end

--- 发布事件。
---@param name string 事件名
---@param payload any 事件数据
---@return boolean consumed 是否被监听器消费
---@return integer delivered 执行的监听器数量
function module.emit(name, payload)
    local list = get_list(name, false)
    if list == nil then
        return false, 0
    end

    local snapshot = {}
    for index, token in ipairs(list) do
        snapshot[index] = token
    end

    local delivered = 0
    for _, token in ipairs(snapshot) do
        if token.active then
            delivered = delivered + 1
            local ok, result = pcall(token.callback, payload, name)
            if not ok then
                if log ~= nil then
                    log.error("事件 %s 监听器异常：%s", name, tostring(result))
                end
            elseif token.once then
                token.active = false
            elseif result == true or result == "consume" then
                return true, delivered
            end
        end
    end

    return false, delivered
end

function module.clear(name)
    if name == nil then
        module._events = {}
    else
        module._events[name] = nil
    end
end

JiuDou.core.events = module

