--- 特效位置平台适配层。
JiuDou = JiuDou or {}
JiuDou.platform = JiuDou.platform or {}
JiuDou.runtime = JiuDou.runtime or {}

local japi = {}
local module = {}

local function refresh_japi()
    japi = (JiuDou.runtime and JiuDou.runtime.japi) or {}
    return japi
end

function module.is_available()
    refresh_japi()
    return type(japi) == "table" and type(japi.DzSetEffectPos) == "function"
end

function module.set_position(effect, x, y, z)
    if effect == nil or not module.is_available() then
        return false
    end
    local ok = pcall(japi.DzSetEffectPos, effect, x, y, z)
    return ok
end

function module.set_size(effect, scale)
    if effect == nil or type(scale) ~= "number" or scale <= 0 then
        return false
    end
    if type(effector) ~= "table" or type(effector.size) ~= "function" then
        return false
    end
    local ok = pcall(effector.size, effect, scale)
    return ok
end

JiuDou.platform.effect = module
return module
