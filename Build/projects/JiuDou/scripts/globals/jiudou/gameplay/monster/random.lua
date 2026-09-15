--- PVE 确定性随机数模块。
--- 每个刷怪槽位拥有独立随机流，避免并发死亡或不同遍历顺序影响其他槽位的随机结果。
local module = {}

local MODULUS = 2147483647
local MULTIPLIER = 48271

---@class MonsterRandom
---@field state integer 当前随机状态

local function normalize_seed(seed)
    local value = math.floor(tonumber(seed) or 0) % MODULUS
    if value < 1 then
        value = 1
    end
    return value
end

--- 创建独立的确定性随机流。
---@param seed integer 初始种子
---@return MonsterRandom random 随机流实例
function module.create(seed)
    return {state = normalize_seed(seed)}
end

--- 为刷怪槽位派生独立随机种子。
---@param session_seed integer 本局同步随机种子
---@param slot_id integer 稳定刷怪槽位编号
---@return integer seed 槽位随机种子
function module.derive_seed(session_seed, slot_id)
    return normalize_seed(normalize_seed(session_seed) + slot_id * 104729)
end

--- 取得闭区间内的下一个随机整数。
---@param random MonsterRandom 随机流实例
---@param minimum integer 最小值
---@param maximum integer 最大值
---@return integer value 随机结果
function module.next_integer(random, minimum, maximum)
    if type(random) ~= "table" or type(random.state) ~= "number" then
        error("随机流无效")
    end
    if type(minimum) ~= "number" or type(maximum) ~= "number" or minimum > maximum then
        error("随机整数范围无效")
    end

    random.state = (random.state * MULTIPLIER) % MODULUS
    local range = maximum - minimum + 1
    return minimum + (random.state % range)
end

return module
