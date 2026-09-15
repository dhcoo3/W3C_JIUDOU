--- JiuDou 资源作用域。
--- 参考 War3GameFramework 的 ReferencePool/ResourceManager，统一管理阶段资源。
JiuDou = JiuDou or {}
JiuDou.core = JiuDou.core or {}

local log = JiuDou.core.log
local module = {}
local Scope = {}
Scope.__index = Scope

local function safe_call(callback, value)
    if type(callback) ~= "function" then
        return
    end
    local ok, message = pcall(callback, value)
    if not ok and log ~= nil then
        log.error("资源清理异常：%s", tostring(message))
    end
end

--- 创建一个资源作用域。
---@param name string 作用域名称
---@return table scope
function module.scope(name)
    return setmetatable({
        name = tostring(name or "scope"),
        resources = {},
        closed = false,
    }, Scope)
end

--- 将资源交给作用域管理。
---@param value any 资源对象
---@param cleanup function|nil 清理函数，接收资源对象
---@return any value 原资源对象
function Scope:add(value, cleanup)
    if value == nil or self.closed then
        return value
    end
    table.insert(self.resources, {
        value = value,
        cleanup = cleanup,
    })
    return value
end

function Scope:own(cleanup)
    return self:add(true, cleanup)
end

function Scope:detach(value)
    for index = #self.resources, 1, -1 do
        if self.resources[index].value == value then
            table.remove(self.resources, index)
            return true
        end
    end
    return false
end

function Scope:clear()
    if self.closed then
        return
    end
    self.closed = true
    for index = #self.resources, 1, -1 do
        local entry = self.resources[index]
        safe_call(entry.cleanup, entry.value)
        self.resources[index] = nil
    end
end

function Scope:is_closed()
    return self.closed
end

function module.timer(scope, timer)
    if scope == nil then
        return timer
    end
    return scope:add(timer, function(value)
        local common = (J and J.Common) or {}
        if type(common.PauseTimer) == "function" then
            common.PauseTimer(value)
        end
        if type(common.DestroyTimer) == "function" then
            common.DestroyTimer(value)
        end
    end)
end

function module.trigger(scope, trigger)
    if scope == nil then
        return trigger
    end
    return scope:add(trigger, function(value)
        local common = (J and J.Common) or {}
        if type(common.DestroyTrigger) == "function" then
            common.DestroyTrigger(value)
        end
    end)
end

function module.frame(scope, frame)
    if scope == nil then
        return frame
    end
    return scope:add(frame, function(value)
        local frame_api = JiuDou.platform and JiuDou.platform.frame
        if frame_api and type(frame_api.destroy) == "function" then
            frame_api.destroy(value)
        end
    end)
end

function module.effect(scope, effect)
    if scope == nil then
        return effect
    end
    return scope:add(effect, function(value)
        local common = (J and J.Common) or {}
        if type(common.DestroyEffect) == "function" then
            common.DestroyEffect(value)
        end
    end)
end

module.Scope = Scope
JiuDou.core.resource = module

