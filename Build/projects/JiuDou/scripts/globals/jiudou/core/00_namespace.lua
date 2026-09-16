--- JiuDou 全局运行时命名空间。
JiuDou = JiuDou or {}

local runtime_japi = (J and J["Japi"]) or {}

JiuDou.runtime = JiuDou.runtime or {}
JiuDou.runtime.common = J.Common
JiuDou.runtime.japi = runtime_japi
JiuDou.platform = JiuDou.platform or {}
JiuDou.core = JiuDou.core or {}
JiuDou.gameplay = JiuDou.gameplay or {}
JiuDou.config = JiuDou.config or {}
--- 自动加载项目模块的命名空间访问器。
--- 项目脚本由 xlik 按文件名自动载入，因此项目代码不使用 require 互相加载。
--- gameplay/platform 模块在文件末尾通过 publish 暴露到 JiuDou 命名空间；
--- module 只延迟解析命名空间，避免跨目录自动加载顺序影响文件初始化。
local function resolve_namespace(path)
    local value = JiuDou
    for name in string.gmatch(path, "[^%.]+") do
        value = value and value[name]
    end
    return value
end

function JiuDou.publish(path, value)
    local namespace = JiuDou
    local parts = {}
    for name in string.gmatch(path, "[^%.]+") do
        parts[#parts + 1] = name
    end
    for index = 1, #parts - 1 do
        local name = parts[index]
        namespace[name] = namespace[name] or {}
        namespace = namespace[name]
    end
    namespace[parts[#parts]] = value
    return value
end

function JiuDou.module(path)
    local proxy = {}
    local metatable = {
        __index = function(_, key)
            local module = resolve_namespace(path)
            if module == nil then
                error("JiuDou 模块尚未自动加载：" .. path)
            end
            return module[key]
        end,
        __newindex = function(_, key, value)
            local module = resolve_namespace(path)
            if module == nil then
                error("JiuDou 模块尚未自动加载：" .. path)
            end
            module[key] = value
        end,
        __pairs = function()
            local module = resolve_namespace(path)
            return pairs(module or {})
        end,
        __len = function()
            local module = resolve_namespace(path)
            return module and #module or 0
        end,
        __tostring = function()
            return "JiuDou.module(" .. path .. ")"
        end,
    }
    return setmetatable(proxy, metatable)
end
