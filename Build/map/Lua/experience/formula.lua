--- 经验奖励纯计算逻辑。
--- 所有输入和输出均为整数，便于单元测试与跨客户端复核。
local module = {}

local function integer(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback or 0 end
    return math.floor(value)
end

local function non_negative(value)
    return math.max(0, integer(value, 0))
end

function module.base_reward(units, rawcode)
    local unit = units and units[rawcode]
    if type(unit) ~= "table" then return 0 end
    return non_negative(unit.expReward)
end

function module.apply_bonus(amount, bonus_percent, max_bonus_percent)
    amount = non_negative(amount)
    bonus_percent = math.min(non_negative(bonus_percent), non_negative(max_bonus_percent))
    return math.floor(amount * (100 + bonus_percent) / 100)
end

--- 按有效伤害分配经验池；余数归有效伤害最高者，伤害相同时按玩家编号排序。
---@param pool integer 经验池
---@param contributions table<integer, integer> 玩家编号到有效伤害
---@return table<integer, integer> awards 玩家编号到未应用个人加成的经验
function module.split_by_damage(pool, contributions)
    pool = non_negative(pool)
    local total_damage = 0
    local sorted = {}
    for player_id, damage in pairs(contributions or {}) do
        player_id = integer(player_id, -1)
        damage = non_negative(damage)
        if player_id >= 0 and damage > 0 then
            total_damage = total_damage + damage
            table.insert(sorted, {playerId = player_id, damage = damage})
        end
    end

    if total_damage <= 0 or #sorted == 0 then return {} end
    table.sort(sorted, function(left, right)
        if left.damage ~= right.damage then return left.damage > right.damage end
        return left.playerId < right.playerId
    end)

    local awards = {}
    local assigned = 0
    for _, entry in ipairs(sorted) do
        local share = math.floor(pool * entry.damage / total_damage)
        awards[entry.playerId] = share
        assigned = assigned + share
    end
    awards[sorted[1].playerId] = awards[sorted[1].playerId] + pool - assigned
    return awards
end

return module
