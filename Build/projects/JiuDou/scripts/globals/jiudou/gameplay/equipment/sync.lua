--- 装备同步适配层。
--- 业务只发送请求或完整结果，不在同步回调中重新随机。
local jass = require "jass.common"
local platform_sync = require "platform.sync"

local module = {}
local PREFIX = "JiuDouEquipment"
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

local function local_player_id()
    if type(jass.GetLocalPlayer) ~= "function" then
        return 0
    end
    return jass.GetPlayerId(jass.GetLocalPlayer())
end

--- 配置并注册装备同步事件。
---@param on_message fun(message:string, senderId:integer|nil) 同步消息回调
---@return boolean available 是否已注册或可本地运行
function module.start(on_message)
    callback = on_message
    if trigger ~= nil then
        return true
    end
    trigger = jass.CreateTrigger()
    jass.TriggerAddAction(trigger, function()
        local sender = platform_sync.get_sync_player()
        local sender_id = sender and jass.GetPlayerId(sender) or nil
        if callback ~= nil then
            callback(platform_sync.get_sync_data() or "", sender_id)
        end
    end)
    if not platform_sync.register_sync_data(trigger, PREFIX, false) then
        return false
    end
    return true
end

---@return boolean available 当前是否能进行跨客户端同步
function module.is_available()
    return platform_sync.is_available()
end

---@return boolean host 当前本地客户端是否为房主
function module.is_host()
    return local_player_id() == 0
end

---@return integer playerId 当前本地玩家编号
function module.get_local_player_id()
    return local_player_id()
end

--- 广播已确定的结果，房主本地立即执行一次以兼容不回声的平台。
---@param message string 消息内容
function module.broadcast(message)
    if platform_sync.is_available() then
        platform_sync.send_sync_data(PREFIX, message)
        if module.is_host() and callback ~= nil then
            callback(message, 0)
        end
        return
    end
    if callback ~= nil then
        callback(message, local_player_id())
    end
end

--- 发送本地请求。请求在房主回调中重新校验。
---@param message string 请求内容
function module.send_request(message)
    module.broadcast(message)
end

---@return string prefix 同步前缀
function module.get_prefix()
    return PREFIX
end

---@return integer version 协议版本
function module.get_version()
    return VERSION
end

module.split = split

return module
