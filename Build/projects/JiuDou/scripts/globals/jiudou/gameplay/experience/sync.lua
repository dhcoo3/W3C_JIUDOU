--- 经验同步适配层。
--- 房主广播每名玩家的经验总量和经验加成，客户端只接受房主的绝对状态。
local jass = J.Common
local platform_sync = JiuDou.module("platform.sync")

local module = {}
local PREFIX = "JiuDouExperience"
local VERSION = 1
local callback = nil
local trigger = nil

local function split(value, separator)
    local result = {}
    local start_index = 1
    while true do
        local from, to = string.find(value, separator, start_index, true)
        if from == nil then
            table.insert(result, string.sub(value, start_index))
            break
        end
        table.insert(result, string.sub(value, start_index, from - 1))
        start_index = to + 1
    end
    return result
end

function module.start(on_message)
    callback = on_message
    if trigger ~= nil then return true end
    if type(jass.CreateTrigger) ~= "function" or type(jass.TriggerAddAction) ~= "function" then
        return false
    end
    trigger = jass.CreateTrigger()
    jass.TriggerAddAction(trigger, function()
        if callback == nil then return end
        local sender = platform_sync.get_sync_player()
        local sender_id = sender and jass.GetPlayerId(sender) or nil
        callback(platform_sync.get_sync_data() or "", sender_id)
    end)
    if not platform_sync.register_sync_data(trigger, PREFIX, false) then
        return false
    end
    return true
end

function module.stop()
    callback = nil
    if trigger ~= nil and type(jass.DestroyTrigger) == "function" then jass.DestroyTrigger(trigger) end
    trigger = nil
end

function module.broadcast(message)
    if platform_sync.is_available() then
        platform_sync.send_sync_data(PREFIX, message)
        if module.is_host() and callback ~= nil then callback(message, 0) end
        return true
    end
    if callback ~= nil then callback(message, module.get_local_player_id()) end
    return true
end

function module.is_host()
    return module.get_local_player_id() == 0
end

function module.get_local_player_id()
    if type(jass.GetLocalPlayer) ~= "function" or type(jass.GetPlayerId) ~= "function" then
        return 0
    end
    return jass.GetPlayerId(jass.GetLocalPlayer())
end

function module.get_version() return VERSION end
function module.get_prefix() return PREFIX end
module.split = split

JiuDou.publish("gameplay.experience.sync", module)
return module
