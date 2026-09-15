--- 肉鸽同步适配层：只同步请求和房主已经决定的完整结果。
local jass = require "jass.common"
local platform_sync = require "platform.sync"

local module = {}
local PREFIX = "JiuDouRogue"
local VERSION = 1
local trigger = nil
local callback = nil

local function local_player_id()
    if type(jass.GetLocalPlayer) ~= "function" then return 0 end
    return jass.GetPlayerId(jass.GetLocalPlayer())
end

function module.split(value, separator)
    local result, start_index = {}, 1
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
    trigger = jass.CreateTrigger()
    jass.TriggerAddAction(trigger, function()
        local sender = platform_sync.get_sync_player()
        local sender_id = sender and jass.GetPlayerId(sender) or nil
        if callback ~= nil then callback(platform_sync.get_sync_data() or "", sender_id) end
    end)
    if not platform_sync.register_sync_data(trigger, PREFIX, false) then
        jass.DestroyTrigger(trigger)
        trigger = nil
        return false
    end
    return true
end

function module.is_available() return platform_sync.is_available() end
function module.is_host() return local_player_id() == 0 end
function module.get_local_player_id() return local_player_id() end
function module.get_version() return VERSION end

function module.broadcast(message)
    if platform_sync.is_available() then
        platform_sync.send_sync_data(PREFIX, message)
        if module.is_host() and callback ~= nil then callback(message, 0) end
        return true
    end
    if callback ~= nil then callback(message, local_player_id()) end
    return true
end

function module.send_request(message)
    return module.broadcast(message)
end

return module
