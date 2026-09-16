--- 整局游戏会话资源管理。
--- Procedure 作用域仅管理短流程；战斗、怪物等长期服务统一挂在此处。
JiuDou = JiuDou or {}
JiuDou.core = JiuDou.core or {}

local resource_api = JiuDou.core.resource
local log = JiuDou.core.log
local module = {
    _session = nil,
}

local function safe_stop(record)
    if record == nil or record.stopped then return end
    record.stopped = true
    if type(record.onStop) == "function" then
        local ok, message = pcall(record.onStop)
        if not ok and log ~= nil then
            log.error("会话模块停止异常 %s：%s", record.name, tostring(message))
        end
    end
end

--- 开始新游戏会话；旧会话会先完整停止。
---@param session_id any
---@return table root_scope
function module.begin(session_id)
    module.finish()
    module._session = {
        id = tostring(session_id or "default"),
        root = resource_api.scope("game:" .. tostring(session_id or "default")),
        modules = {},
        order = {},
    }
    return module._session.root
end

function module.is_active()
    return module._session ~= nil
end

function module.get_id()
    return module._session and module._session.id or nil
end

--- 取得模块独占作用域；同名模块会先停止旧实例。
---@param name string
---@param on_stop function|nil
---@return table|nil scope
function module.acquire(name, on_stop)
    local session = module._session
    if session == nil or type(name) ~= "string" or name == "" then return nil end
    module.release(name)
    local scope = session.root:child("game:" .. session.id .. ":" .. name)
    local record = { name = name, scope = scope, onStop = on_stop, stopped = false }
    session.modules[name] = record
    table.insert(session.order, name)
    scope:own(function()
        safe_stop(record)
    end)
    return scope
end

--- 停止单模块并释放其全部已托管资源。
function module.release(name)
    local session = module._session
    local record = session and session.modules[name] or nil
    if record == nil then return false end
    session.modules[name] = nil
    session.root:detach(record.scope)
    record.scope:clear()
    return true
end

--- 按逆启动顺序停止并释放整局资源。
function module.finish()
    local session = module._session
    if session == nil then return false end
    for index = #session.order, 1, -1 do
        module.release(session.order[index])
    end
    session.root:clear()
    module._session = nil
    return true
end

JiuDou.core.lifecycle = module
