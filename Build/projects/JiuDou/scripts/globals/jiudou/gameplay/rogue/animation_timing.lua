--- 肉鸽技能动画与伤害命中时序的手动配置。
local module = {}

local entries = {
    ["H0E0:A0E3:proc"] = {
        animationIndex = 11,
        animationName = "attack slam",
        durationSeconds = 1.50,
        hitSeconds = 1.00,
    },
}

function module.get(hero_rawcode, skill_rawcode, event_key)
    local key = tostring(hero_rawcode or "") .. ":"
        .. tostring(skill_rawcode or "") .. ":" .. tostring(event_key or "")
    return entries[key]
end

JiuDou.publish("gameplay.rogue.animation_timing", module)
return module
