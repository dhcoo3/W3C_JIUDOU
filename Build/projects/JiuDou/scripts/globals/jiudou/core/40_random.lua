--- JiuDou 确定性随机数服务。
--- 不依赖 math.random；多人玩法应由房主统一生成种子后使用。
JiuDou = JiuDou or {}
JiuDou.core = JiuDou.core or {}

local module = {
    state = 1,
    seeded = false,
}

local MODULUS = 2147483647
local MULTIPLIER = 48271

local function normalize(seed)
    seed = tonumber(seed) or 1
    seed = math.floor(seed)
    seed = seed % (MODULUS - 1)
    if seed <= 0 then
        seed = 1
    end
    return seed
end

function module.seed(seed)
    module.state = normalize(seed)
    module.seeded = true
    return module.state
end

function module.seed_from_native()
    local common = (J and J.Common) or {}
    if type(common.GetRandomInt) == "function" then
        return module.seed(common.GetRandomInt(1, MODULUS - 1))
    end
    return module.seed(1)
end

function module.next()
    if not module.seeded then
        module.seed_from_native()
    end
    module.state = (module.state * MULTIPLIER) % MODULUS
    return module.state
end

function module.int(minimum, maximum)
    minimum = math.floor(tonumber(minimum) or 0)
    maximum = math.floor(tonumber(maximum) or minimum)
    if minimum >= maximum then
        return minimum
    end
    return minimum + (module.next() % (maximum - minimum + 1))
end

function module.pick(values)
    if type(values) ~= "table" or #values == 0 then
        return nil
    end
    return values[module.int(1, #values)]
end

function module.create(seed)
    local rng = {
        state = normalize(seed),
    }
    return rng
end

function module.next_integer(rng, minimum, maximum)
    if type(rng) ~= "table" then
        return module.int(minimum, maximum)
    end
    minimum = math.floor(tonumber(minimum) or 0)
    maximum = math.floor(tonumber(maximum) or minimum)
    if minimum >= maximum then
        return minimum
    end
    rng.state = (rng.state * MULTIPLIER) % MODULUS
    return minimum + (rng.state % (maximum - minimum + 1))
end

JiuDou.core.random = module

