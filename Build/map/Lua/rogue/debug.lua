--- 肉鸽调试入口。发布版本默认关闭；需要测试时将 ENABLED 改为 true。
local jass = require "jass.common"

local module = {}
local ENABLED = false

function module.start(rogue)
    if not ENABLED then return false end
    local trigger = jass.CreateTrigger()
    for player_id = 0, 9 do
        jass.TriggerRegisterPlayerChatEvent(trigger, jass.Player(player_id), "-rogue", false)
    end
    jass.TriggerAddAction(trigger, function()
        local player_id = jass.GetPlayerId(jass.GetTriggerPlayer())
        local text = jass.GetEventPlayerChatString() or ""
        if text == "-rogue" then rogue.debug_force_offer(player_id)
        elseif text == "-rogue-timeout" then rogue.debug_timeout(player_id)
        elseif text == "-rogue-refresh" then rogue.grant_refresh_count(player_id, 3) end
    end)
    print("肉鸽调试命令已启用：-rogue / -rogue-timeout / -rogue-refresh")
    return true
end

return module
