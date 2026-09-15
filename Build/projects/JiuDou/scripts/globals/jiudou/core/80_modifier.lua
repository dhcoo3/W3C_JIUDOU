--- Priority modifier pipeline for damage, buffs and other extensible calculations.
JiuDou = JiuDou or {}
JiuDou.core = JiuDou.core or {}

local log = JiuDou.core.log
local module = {
    _channels = {},
    _next_id = 0,
}

local function list_for(channel, create)
    local list = module._channels[channel]
    if list == nil and create then
        list = {}
        module._channels[channel] = list
    end
    return list
end

local function sort_list(list)
    table.sort(list, function(left, right)
        if left.priority == right.priority then
            return left.id < right.id
        end
        return left.priority > right.priority
    end)
end

function module.on(channel, callback, priority)
    if type(channel) ~= "string" or channel == "" or type(callback) ~= "function" then
        return nil
    end
    module._next_id = module._next_id + 1
    local token = {
        id = module._next_id,
        channel = channel,
        callback = callback,
        priority = tonumber(priority) or 0,
        active = true,
    }
    local list = list_for(channel, true)
    table.insert(list, token)
    sort_list(list)
    return token
end

function module.off(token)
    if type(token) ~= "table" then
        return false
    end
    token.active = false
    return true
end

--- Apply modifiers in descending priority order.
--- A callback may set context.cancelled=true or return false to cancel the operation.
function module.apply(channel, context)
    local list = list_for(channel, false)
    if list == nil then
        return true, 0
    end
    local snapshot = {}
    for index, token in ipairs(list) do
        snapshot[index] = token
    end
    local applied = 0
    for _, token in ipairs(snapshot) do
        if token.active then
            applied = applied + 1
            local ok, result = pcall(token.callback, context, channel)
            if not ok then
                if log ~= nil then
                    log.error("修改器 %s 异常：%s", channel, tostring(result))
                end
            elseif result == false or (type(context) == "table" and context.cancelled) then
                return false, applied
            end
        end
    end
    return true, applied
end

function module.clear(channel)
    if channel == nil then
        module._channels = {}
    else
        module._channels[channel] = nil
    end
end

JiuDou.core.modifier = module

