--- JiuDou 统一日志服务。
--- 参考 War3GameFramework 的 Log/Debugger，但不依赖旧框架的全局对象。
JiuDou = JiuDou or {}
JiuDou.core = JiuDou.core or {}

local module = {
    _once = {},
}

local function stringify(message, ...)
    if select("#", ...) == 0 then
        return tostring(message)
    end

    local ok, formatted = pcall(string.format, tostring(message), ...)
    if ok then
        return formatted
    end
    return tostring(message)
end

function module.write(level, message, ...)
    local text = string.format("[JiuDou][%s] %s", tostring(level), stringify(message, ...))
    if type(print) == "function" then
        print(text)
    end
    return text
end

function module.debug(message, ...)
    return module.write("DEBUG", message, ...)
end

function module.info(message, ...)
    return module.write("INFO", message, ...)
end

function module.warn(message, ...)
    return module.write("WARN", message, ...)
end

function module.error(message, ...)
    return module.write("ERROR", message, ...)
end

function module.once(key, level, message, ...)
    key = tostring(key)
    if module._once[key] then
        return false
    end
    module._once[key] = true
    module.write(level or "INFO", message, ...)
    return true
end

JiuDou.core.log = module

