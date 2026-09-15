--- JiuDou 游戏流程管理器。
--- 参考 War3GameFramework 的 ProcedureManager，但流程资源由作用域自动清理。
JiuDou = JiuDou or {}
JiuDou.core = JiuDou.core or {}

local fsm_api = JiuDou.core.fsm
local resource_api = JiuDou.core.resource
local events = JiuDou.core.events
local log = JiuDou.core.log
local module = {
    _definitions = {},
    _machine = nil,
    _context = nil,
}

local function current_context()
    return module._context
end

function module.register(name, definition)
    if type(name) ~= "string" or type(definition) ~= "table" then
        return false
    end
    module._definitions[name] = definition
    return true
end

function module.has(name)
    return module._definitions[name] ~= nil
end

function module.current()
    if module._machine == nil then
        return nil
    end
    return module._machine:current_name_value()
end

function module.context()
    return current_context()
end

function module.scope()
    return module._context and module._context.scope or nil
end

local function enter(name, data)
    local definition = module._definitions[name]
    local context = {
        name = name,
        data = data,
        scope = resource_api.scope("procedure:" .. name),
    }
    module._context = context
    if type(definition.enter) == "function" then
        local ok, result = pcall(definition.enter, context)
        if not ok or result == false then
            if log ~= nil then
                log.error("流程 %s 进入失败：%s", name, tostring(result))
            end
            context.scope:clear()
            module._context = nil
            return false
        end
    end
    if events ~= nil then
        events.emit("procedure.enter", context)
    end
    return true
end

local function leave(name, data)
    local definition = module._definitions[name]
    local context = module._context
    if type(definition) == "table" and type(definition.leave) == "function" then
        local ok, message = pcall(definition.leave, context)
        if not ok and log ~= nil then
            log.error("流程 %s 离开异常：%s", name, tostring(message))
        end
    end
    if events ~= nil then
        events.emit("procedure.leave", context or { name = name, data = data })
    end
    if context ~= nil and context.scope ~= nil then
        context.scope:clear()
    end
    module._context = nil
end

local function make_state(name, definition)
    -- 用工厂固定每个状态的 name/definition，兼容 Warcraft Lua 对循环变量闭包的实现差异。
    return {
        enter = function(_, machine, data)
            return enter(name, data)
        end,
        leave = function(_, machine, data)
            leave(name, data)
        end,
        update = function(_, machine, data, delta)
            if type(definition.update) == "function" and module._context ~= nil then
                return definition.update(module._context, delta)
            end
            return true
        end,
    }
end

local function ensure_machine()
    if module._machine ~= nil then
        return module._machine
    end
    local states = {}
    for name, definition in pairs(module._definitions) do
        states[name] = make_state(name, definition)
    end
    module._machine = fsm_api.new("JiuDouProcedure", states)
    return module._machine
end

function module.start(name, data)
    local machine = ensure_machine()
    if machine.current ~= nil then
        return false, "流程已经启动：" .. tostring(machine:current_name_value())
    end
    return machine:start(name, data)
end

function module.change(name, data)
    local machine = ensure_machine()
    if machine.current == nil then
        return machine:start(name, data)
    end
    return machine:change(name, data)
end

function module.update(delta)
    if module._machine == nil then
        return true
    end
    return module._machine:update(delta)
end

function module.stop()
    if module._machine ~= nil then
        module._machine:stop()
    end
    module._context = nil
end

JiuDou.core.procedure = module
