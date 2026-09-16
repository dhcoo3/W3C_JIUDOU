--- 肉鸽局内运行时。
--- 集中管理升级事件和强化倒计时，避免主流程持有原生 Trigger/Timer 生命周期。
local jass = J.Common
local timer_service = JiuDou.core and JiuDou.core.timer
local resource_api = JiuDou.core and JiuDou.core.resource
local lifecycle = JiuDou.core and JiuDou.core.lifecycle

local module = {}
local Runtime = {}
Runtime.__index = Runtime

local function destroy_trigger(trigger)
    if type(jass.DestroyTrigger) == "function" then
        jass.DestroyTrigger(trigger)
    end
end

local function destroy_timer(timer)
    if type(jass.PauseTimer) == "function" then jass.PauseTimer(timer) end
    if type(jass.DestroyTimer) == "function" then jass.DestroyTimer(timer) end
end

function module.create(name)
    local runtime = setmetatable({
        scope_name = tostring(name or "rogue_runtime"),
        scope = nil,
        level_trigger = nil,
        countdown_timer = nil,
    }, Runtime)
    if lifecycle ~= nil and lifecycle.is_active() then
        runtime.scope = lifecycle.acquire(runtime.scope_name, function()
            runtime.level_trigger = nil
            runtime.countdown_timer = nil
        end)
    elseif resource_api then
        runtime.scope = resource_api.scope(runtime.scope_name)
    end
    return runtime
end

---@param player_ids table<integer, table>
---@param callback fun(hero:unit)
---@return boolean registered
function Runtime:register_level_events(player_ids, callback)
    if self.level_trigger ~= nil or type(jass.CreateTrigger) ~= "function" then return false end
    local trigger = jass.CreateTrigger()
    for player_id in pairs(player_ids or {}) do
        jass.TriggerRegisterPlayerUnitEvent(trigger, jass.Player(player_id), jass.EVENT_PLAYER_HERO_LEVEL, nil)
    end
    jass.TriggerAddAction(trigger, function()
        callback(jass.GetTriggerUnit())
    end)
    self.level_trigger = trigger
    if self.scope ~= nil then
        resource_api.trigger(self.scope, trigger)
    end
    return true
end

---@param interval number
---@param callback fun()
---@return boolean started
function Runtime:start_countdown(interval, callback)
    if self.countdown_timer ~= nil then return true end
    if timer_service ~= nil and type(timer_service.every) == "function" then
        self.countdown_timer = timer_service.every(interval, callback, self.scope)
        return self.countdown_timer ~= nil
    end
    if type(jass.CreateTimer) ~= "function" or type(jass.TimerStart) ~= "function" then return false end
    local timer = jass.CreateTimer()
    jass.TimerStart(timer, interval, true, callback)
    self.countdown_timer = timer
    if self.scope ~= nil then
        self.scope:add(timer, destroy_timer)
    end
    return true
end

function Runtime:stop()
    if lifecycle ~= nil and lifecycle.release(self.scope_name) then
        self.scope = nil
        self.level_trigger = nil
        self.countdown_timer = nil
        return
    end
    if self.scope ~= nil then
        self.scope:clear()
    else
        if self.level_trigger ~= nil then destroy_trigger(self.level_trigger) end
        if self.countdown_timer ~= nil then destroy_timer(self.countdown_timer) end
    end
    self.level_trigger = nil
    self.countdown_timer = nil
    self.scope = nil
end

JiuDou.publish("gameplay.rogue.runtime", module)
return module
