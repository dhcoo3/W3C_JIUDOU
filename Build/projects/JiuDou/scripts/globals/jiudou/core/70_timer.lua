--- JiuDou 计时器服务。
--- 统一封装 Warcraft Timer，并允许绑定到流程资源作用域。
JiuDou = JiuDou or {}
JiuDou.core = JiuDou.core or {}

local resource_api = JiuDou.core.resource
local log = JiuDou.core.log
local module = {}

local function common_api()
    return (J and J.Common) or {}
end

local function destroy(timer)
    local common = common_api()
    if type(common.PauseTimer) == "function" then
        common.PauseTimer(timer)
    end
    if type(common.DestroyTimer) == "function" then
        common.DestroyTimer(timer)
    end
end

function module.after(delay, callback, scope)
    local common = common_api()
    if type(common.CreateTimer) ~= "function" or type(common.TimerStart) ~= "function" then
        if type(callback) == "function" then
            callback()
        end
        return nil
    end

    local timer = common.CreateTimer()
    if scope ~= nil then
        resource_api.timer(scope, timer)
    end
    common.TimerStart(timer, tonumber(delay) or 0, false, function()
        if scope ~= nil and type(scope.detach) == "function" then
            scope:detach(timer)
        end
        destroy(timer)
        if type(callback) == "function" then
            local ok, message = pcall(callback)
            if not ok and log ~= nil then
                log.error("延迟任务异常：%s", tostring(message))
            end
        end
    end)
    return timer
end

function module.every(interval, callback, scope)
    local common = common_api()
    if type(common.CreateTimer) ~= "function" or type(common.TimerStart) ~= "function" then
        return nil
    end

    local timer = common.CreateTimer()
    if scope ~= nil then
        resource_api.timer(scope, timer)
    end
    common.TimerStart(timer, tonumber(interval) or 0.03, true, function()
        if type(callback) ~= "function" then
            return
        end
        local ok, message = pcall(callback)
        if not ok and log ~= nil then
            log.error("周期任务异常：%s", tostring(message))
        end
    end)
    return timer
end

function module.cancel(timer, scope)
    if timer ~= nil then
        if scope ~= nil and type(scope.detach) == "function" then
            scope:detach(timer)
        end
        destroy(timer)
    end
end

JiuDou.core.timer = module
