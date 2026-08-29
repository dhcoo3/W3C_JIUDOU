--- JAPI 同步平台适配层。
--- 真实平台行为：调用 KKWE/YDWE 运行时注入的同步 native。
--- 本地兜底行为：JAPI 不可用时返回失败，由业务层执行本地模式逻辑。
local japiLoaded, japi = pcall(require, "jass.japi")
if not japiLoaded then
    japi = {}
end

local module = {}

--- 判断当前运行时是否提供完整的同步接口。
---@return boolean available 是否可以使用 JAPI 同步功能
function module.is_available()
    return type(japi) == "table"
        and type(japi.DzSyncData) == "function"
        and type(japi.DzTriggerRegisterSyncData) == "function"
        and type(japi.DzGetTriggerSyncData) == "function"
        and type(japi.DzGetTriggerSyncPlayer) == "function"
end

--- 注册指定同步标识的数据事件。
--- 真实平台会把匹配 prefix 的同步数据交给 trigger；接口不可用时不注册并返回 false。
---@param sync_trigger trigger 接收同步事件的触发器
---@param prefix string 同步事件标识
---@param server boolean 是否接收来自平台服务器的数据
---@return boolean registered 是否成功注册
function module.register_sync_data(sync_trigger, prefix, server)
    if not module.is_available() then
        return false
    end

    japi.DzTriggerRegisterSyncData(sync_trigger, prefix, server)
    return true
end

--- 向本局其他玩家广播同步数据。
--- 数据本身必须由调用方序列化；接口不可用时返回 false，由业务层自行执行本地逻辑。
---@param prefix string 同步事件标识，必须与接收端注册的标识一致
---@param data string 要广播的数据内容
---@return boolean sent 是否已调用真实同步接口
function module.send_sync_data(prefix, data)
    if not module.is_available() then
        return false
    end

    japi.DzSyncData(prefix, data)
    return true
end

--- 读取当前同步事件携带的数据。
--- 仅应在同步事件触发器的回调中调用；接口不可用时返回 nil。
---@return string|nil data 当前同步事件的数据内容
function module.get_sync_data()
    if type(japi) ~= "table" or type(japi.DzGetTriggerSyncData) ~= "function" then
        return nil
    end

    return japi.DzGetTriggerSyncData()
end

--- 获取当前同步事件的发送玩家。
--- 仅应在同步触发器回调中调用；接口缺失时返回空。
---@return player|nil sender 当前同步消息的来源玩家
function module.get_sync_player()
    if type(japi) ~= "table" or type(japi.DzGetTriggerSyncPlayer) ~= "function" then
        return nil
    end

    return japi.DzGetTriggerSyncPlayer()
end

return module
