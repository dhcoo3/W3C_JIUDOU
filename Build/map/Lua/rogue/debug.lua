--- 肉鸽调试入口。肉鸽命令默认关闭；属性诊断命令在测试地图中常开且只读。
local jass = require "jass.common"

local module = {}
local ROGUE_DEBUG_ENABLED = false
local ATTACK_SPEED_DEBUG_ENABLED = true
local HEALTH_DEBUG_ENABLED = true

function module.start(rogue)
    if not ROGUE_DEBUG_ENABLED and not ATTACK_SPEED_DEBUG_ENABLED and not HEALTH_DEBUG_ENABLED then return false end
    local trigger = jass.CreateTrigger()
    for player_id = 0, 9 do
        jass.TriggerRegisterPlayerChatEvent(trigger, jass.Player(player_id), "-rogue", false)
        jass.TriggerRegisterPlayerChatEvent(trigger, jass.Player(player_id), "-asdebug", true)
        jass.TriggerRegisterPlayerChatEvent(trigger, jass.Player(player_id), "-hpdebug", true)
    end
    jass.TriggerAddAction(trigger, function()
        local player_id = jass.GetPlayerId(jass.GetTriggerPlayer())
        local text = jass.GetEventPlayerChatString() or ""
        if ATTACK_SPEED_DEBUG_ENABLED and text == "-asdebug" then
            rogue.debug_attack_speed(player_id)
        elseif HEALTH_DEBUG_ENABLED and text == "-hpdebug" then
            rogue.debug_health(player_id)
        elseif ROGUE_DEBUG_ENABLED and text == "-rogue" then
            rogue.debug_force_offer(player_id)
        elseif ROGUE_DEBUG_ENABLED and text == "-rogue-timeout" then
            rogue.debug_timeout(player_id)
        elseif ROGUE_DEBUG_ENABLED and text == "-rogue-refresh" then
            rogue.grant_refresh_count(player_id, 3)
        end
    end)
    if ATTACK_SPEED_DEBUG_ENABLED then print("攻速调试命令已启用：-asdebug") end
    if HEALTH_DEBUG_ENABLED then print("生命调试命令已启用：-hpdebug") end
    if ROGUE_DEBUG_ENABLED then print("肉鸽调试命令已启用：-rogue / -rogue-timeout / -rogue-refresh") end
    return true
end

return module
