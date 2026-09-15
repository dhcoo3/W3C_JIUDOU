--- JiuDou 通用有限状态机。
--- 状态对象使用 enter/leave/update，避免玩法模块自行维护大量布尔变量。
JiuDou = JiuDou or {}
JiuDou.core = JiuDou.core or {}

local log = JiuDou.core.log
local module = {}
local Machine = {}
Machine.__index = Machine

local function call_state(machine, state, method, ...)
    if state == nil or type(state[method]) ~= "function" then
        return true
    end
    local ok, result = pcall(state[method], state, machine, ...)
    if not ok then
        machine.last_error = tostring(result)
        if log ~= nil then
            log.error("FSM %s.%s 异常：%s", machine.name, method, machine.last_error)
        end
        return false
    end
    if result == false then
        machine.last_error = "state callback returned false"
        return false
    end
    return true
end

function module.new(name, states)
    local machine = setmetatable({
        name = tostring(name or "fsm"),
        states = states or {},
        current_name = nil,
        current = nil,
        data = nil,
        elapsed = 0,
        last_error = nil,
    }, Machine)
    return machine
end

function Machine:has(name)
    return self.states[name] ~= nil
end

function Machine:current_name_value()
    return self.current_name
end

function Machine:start(name, data)
    if self.current ~= nil then
        return false, "FSM 已经启动"
    end
    return self:change(name, data)
end

function Machine:change(name, data)
    local next_state = self.states[name]
    if next_state == nil then
        return false, "不存在状态：" .. tostring(name)
    end
    if self.current_name == name then
        self.data = data
        return true
    end

    if self.current ~= nil and not call_state(self, self.current, "leave", self.data) then
        return false, self.last_error
    end

    self.current_name = name
    self.current = next_state
    self.data = data
    self.elapsed = 0
    if not call_state(self, self.current, "enter", data) then
        self.current_name = nil
        self.current = nil
        return false, self.last_error
    end
    return true
end

function Machine:update(delta)
    if self.current == nil then
        return true
    end
    self.elapsed = self.elapsed + (tonumber(delta) or 0)
    return call_state(self, self.current, "update", self.data, delta)
end

function Machine:stop()
    if self.current ~= nil then
        call_state(self, self.current, "leave", self.data)
    end
    self.current_name = nil
    self.current = nil
    self.data = nil
    self.elapsed = 0
end

module.Machine = Machine
JiuDou.core.fsm = module

