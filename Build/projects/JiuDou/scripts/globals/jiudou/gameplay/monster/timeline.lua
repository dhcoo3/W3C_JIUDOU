--- 怪物局内时间线。
--- 管理固定调度与首波分帧生成的计时器生命周期，不包含任何刷怪或随机逻辑。
local jass = require "jass.common"
local timer_service = JiuDou.core and JiuDou.core.timer
local resource_api = JiuDou.core and JiuDou.core.resource

local module = {}
local Timeline = {}
Timeline.__index = Timeline

local function cancel_timer(self, field)
    local timer = self[field]
    if timer == nil then
        return
    end
    if self.scope ~= nil and type(self.scope.detach) == "function" then
        self.scope:detach(timer)
    end
    if timer_service ~= nil and type(timer_service.cancel) == "function" then
        timer_service.cancel(timer)
    else
        if type(jass.PauseTimer) == "function" then jass.PauseTimer(timer) end
        if type(jass.DestroyTimer) == "function" then jass.DestroyTimer(timer) end
    end
    self[field] = nil
end

local function start_every(self, field, interval, callback)
    cancel_timer(self, field)
    if timer_service ~= nil and type(timer_service.every) == "function" then
        self[field] = timer_service.every(interval, callback, self.scope)
        return self[field] ~= nil
    end
    if type(jass.CreateTimer) ~= "function" or type(jass.TimerStart) ~= "function" then
        return false
    end
    local timer = jass.CreateTimer()
    jass.TimerStart(timer, interval, true, callback)
    self[field] = timer
    return true
end

---@param name string|nil
---@return table timeline
function module.create(name)
    return setmetatable({
        scope = resource_api ~= nil and resource_api.scope(name or "monster_timeline") or nil,
        scheduler_timer = nil,
        initial_spawn_timer = nil,
        initial_spawn_index = 1,
    }, Timeline)
end

---@param interval number
---@param on_tick fun()
---@return boolean started
function Timeline:start_scheduler(interval, on_tick)
    return start_every(self, "scheduler_timer", interval, on_tick)
end

---@param queue table[]
---@param batch_size integer
---@param interval number
---@param on_item fun(item:any)
---@param on_finished fun()|nil
---@return boolean started
function Timeline:start_initial_batches(queue, batch_size, interval, on_item, on_finished)
    queue = type(queue) == "table" and queue or {}
    batch_size = math.max(1, math.floor(tonumber(batch_size) or 1))
    self.initial_spawn_index = 1
    local function on_tick()
        local last_index = math.min(#queue, self.initial_spawn_index + batch_size - 1)
        for index = self.initial_spawn_index, last_index do
            on_item(queue[index])
        end
        self.initial_spawn_index = last_index + 1
        if self.initial_spawn_index <= #queue then
            return
        end
        cancel_timer(self, "initial_spawn_timer")
        if type(on_finished) == "function" then
            on_finished()
        end
    end
    return start_every(self, "initial_spawn_timer", interval, on_tick)
end

function Timeline:stop_initial_batches()
    cancel_timer(self, "initial_spawn_timer")
    self.initial_spawn_index = 1
end

function Timeline:stop()
    self:stop_initial_batches()
    cancel_timer(self, "scheduler_timer")
    if self.scope ~= nil then
        self.scope:clear()
        self.scope = nil
    end
end

return module
