--- 每名玩家独立的肉鸽状态。
local jass = J.Common

local module = {}
local by_player_id = {}
local by_hero = {}

local function resolve_hero_rawcode(result)
    if result.hero and result.hero.rawcode then return result.hero.rawcode end
    return result.rawcode
end

function module.create(result)
    local hero = result.unit
    local player_id = result.playerId
    local current_level = type(jass.GetHeroLevel) == "function" and jass.GetHeroLevel(hero) or 1
    local state = {
        playerId = player_id,
        hero = hero,
        heroDefinition = result.hero,
        heroRawcode = resolve_hero_rawcode(result),
        lastObservedHeroLevel = current_level,
        pendingRewards = 0,
        offerSerial = 0,
        currentOffer = nil,
        bonusRefreshCount = 0,
        owned = {},
        common = {},
        skills = {},
        processedApplies = {},
    }
    by_player_id[player_id] = state
    by_hero[hero] = state
    return state
end

function module.get_by_player_id(player_id) return by_player_id[player_id] end
function module.get_by_hero(hero) return by_hero[hero] end
function module.get_all() return by_player_id end

function module.reset()
    by_player_id = {}
    by_hero = {}
end

JiuDou.publish("gameplay.rogue.state", module)
return module
