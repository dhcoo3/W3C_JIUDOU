--- 房主使用的确定性三选一生成器。
local config = require "rogue.config"

local module = {}
local MODULUS = 2147483647
local MULTIPLIER = 48271

local function next_random(seed)
    seed = (seed * MULTIPLIER) % MODULUS
    if seed < 1 then seed = 1 end
    return seed
end

local function eligible(state, effect_id)
    local effect = config.get_effect(effect_id)
    return effect ~= nil and (state.owned[effect_id] or 0) < effect.maxLevel
end

local function collect(ids, state)
    local result = {}
    for _, effect_id in ipairs(ids or {}) do
        if eligible(state, effect_id) then table.insert(result, effect_id) end
    end
    return result
end

local function weighted_take(candidates, seed)
    local total = 0
    for _, effect_id in ipairs(candidates) do total = total + config.get_effect(effect_id).weight end
    if total <= 0 then return nil, seed end
    seed = next_random(seed)
    local roll = seed % total + 1
    local cumulative = 0
    for index, effect_id in ipairs(candidates) do
        cumulative = cumulative + config.get_effect(effect_id).weight
        if roll <= cumulative then
            table.remove(candidates, index)
            return effect_id, seed
        end
    end
    return table.remove(candidates), seed
end

local function signature(choices)
    local copy = {choices[1], choices[2], choices[3]}
    table.sort(copy)
    return table.concat(copy, ",")
end

function module.draw(state, session_seed, serial, revision, previous_choices)
    local base_seed = math.abs(math.floor(tonumber(session_seed) or 1))
        + state.playerId * 100003 + serial * 1009 + revision * 97
    base_seed = base_seed % MODULUS
    if base_seed < 1 then base_seed = 1 end
    local previous_signature = previous_choices and signature(previous_choices) or nil
    for attempt = 0, 31 do
        local seed = (base_seed + attempt * 7919) % MODULUS
        if seed < 1 then seed = 1 end
        local skill = collect(config.get_skill_ids(state.heroRawcode), state)
        local common = collect(config.get_common_ids(), state)
        local choices = {}
        for _ = 1, 2 do
            local picked
            picked, seed = weighted_take(skill, seed)
            if picked ~= nil then table.insert(choices, picked) end
        end
        local picked
        picked, seed = weighted_take(common, seed)
        if picked ~= nil then table.insert(choices, picked) end
        local remaining = {}
        for _, id in ipairs(skill) do table.insert(remaining, id) end
        for _, id in ipairs(common) do table.insert(remaining, id) end
        while #choices < 3 and #remaining > 0 do
            picked, seed = weighted_take(remaining, seed)
            if picked ~= nil then table.insert(choices, picked) end
        end
        if #choices == 3 and signature(choices) ~= previous_signature then
            for index = #choices, 2, -1 do
                seed = next_random(seed)
                local other = seed % index + 1
                choices[index], choices[other] = choices[other], choices[index]
            end
            return choices
        end
    end
    return nil
end

function module.signature(choices) return signature(choices) end

return module
