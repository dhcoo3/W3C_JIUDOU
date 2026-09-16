--- 肉鸽系统总入口：升级队列、房主权威三选一、同步发放和公共查询。
local jass = J.Common
local config = JiuDou.module("gameplay.rogue.config")
local state_store = JiuDou.module("gameplay.rogue.state")
local pool = JiuDou.module("gameplay.rogue.pool")
local sync = JiuDou.module("gameplay.rogue.sync")
local attribute = JiuDou.module("gameplay.rogue.attribute")
local runtime_service = JiuDou.module("gameplay.rogue.runtime")
local popup = JiuDou.module("gameplay.rogue.ui.popup")
local hero_stats = JiuDou.module("gameplay.hero.stats")
local wukong = JiuDou.module("gameplay.rogue.skills.wukong")
local arthas = JiuDou.module("gameplay.rogue.skills.arthas")
local houyi = JiuDou.module("gameplay.rogue.skills.houyi")
local hero_damage = JiuDou.module("gameplay.rogue.skills.hero_damage")
local debug = JiuDou.module("gameplay.rogue.debug")
local lifecycle = JiuDou.core and JiuDou.core.lifecycle

local module = {}
local VERSION = 1
local started = false
local sync_available = false
local critical_enabled = false
local session_seed = 1
local session_id = 1
local runtime = nil
local local_selection = {}

local function stop_child(child)
    if type(child) == "table" and type(child.stop) == "function" then child.stop() end
end

local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

local function count_states()
    local count = 0
    for _ in pairs(state_store.get_all()) do count = count + 1 end
    return count
end

local function contains(choices, effect_id)
    for _, id in ipairs(choices or {}) do if id == effect_id then return true end end
    return false
end

local function effect_level_text(current_level)
    current_level = math.max(0, math.floor(tonumber(current_level) or 0))
    if current_level <= 0 then
        return "新效果  →  I"
    end
    local roman = {"I", "II", "III", "IV"}
    return (roman[current_level] or tostring(current_level))
        .. "  →  "
        .. (roman[current_level + 1] or tostring(current_level + 1))
end

local function show_local_offer(state)
    if sync.get_local_player_id() ~= state.playerId or state.currentOffer == nil then return end
    local offer = state.currentOffer
    local choices = {}
    for _, effect_id in ipairs(offer.choices) do
        local effect = config.get_effect(effect_id)
        local current_level = state.owned[effect_id] or 0
        table.insert(choices, {
            effect = effect,
            currentLevel = current_level,
            nextLevel = current_level + 1,
        })
    end
    local_selection[state.playerId] = nil
    local shown = popup.show({
        onSelected = function(slot)
            local choice = choices[slot]
            local effect_id = choice and choice.effect and choice.effect.effectId
            if state.currentOffer == offer and effect_id ~= nil and contains(offer.choices, effect_id) then
                local_selection[state.playerId] = effect_id
                popup.set_selected(slot)
                popup.set_confirm_text("确认强化")
                popup.set_confirm_enabled(true)
            end
        end,
        onRefresh = function()
            if state.currentOffer ~= offer then return end
            sync.send_request(string.format(
                "REFRESH_REQUEST|%d|%d|%d|%d|%d",
                VERSION, session_id, state.playerId, offer.serial, offer.revision
            ))
        end,
        onConfirm = function()
            local effect_id = local_selection[state.playerId]
            if state.currentOffer ~= offer or effect_id == nil then return end
            sync.send_request(string.format(
                "PICK_REQUEST|%d|%d|%d|%d|%d|%s",
                VERSION, session_id, state.playerId, offer.serial, offer.revision, effect_id
            ))
        end,
    })
    if not shown then
        print("肉鸽界面显示失败：" .. popup.get_last_error())
        return
    end

    popup.set_title("命运强化")
    popup.set_subtitle("从 3 项肉鸽强化中选择 1 项")
    local hero_name = state.heroDefinition and state.heroDefinition.name or state.heroRawcode or "英雄"
    popup.set_hero_name(hero_name)
    popup.set_hero_level(string.format("英雄等级 %d  ·  奖励 #%d", offer.heroLevel, offer.serial))
    if type(state.heroRawcode) == "string" and state.heroRawcode ~= "" then
        local portrait = japi.AssetsImage("selectHero/portraits/" .. string.lower(state.heroRawcode))
        if type(portrait) == "string" and portrait ~= "" then
            popup.set_hero_portrait(portrait)
        end
    end
    popup.set_remaining_seconds(string.format("%d 秒", math.max(0, tonumber(offer.remainingSeconds) or 0)))
    local refresh_total = math.max(0, offer.freeRefreshRemaining or 0)
        + math.max(0, state.bonusRefreshCount or 0)
    popup.set_refresh_text(string.format("刷新强化（%d）", refresh_total))
    popup.set_refresh_enabled(refresh_total > 0)
    popup.set_confirm_text("请选择强化")
    popup.set_confirm_enabled(false)

    for slot, choice in ipairs(choices) do
        local effect = choice.effect
        popup.set_card_type(slot, effect.type == "Skill" and "英雄技能" or "通用强化")
        popup.set_card_name(slot, effect.name)
        popup.set_card_level(slot, effect_level_text(choice.currentLevel))
        popup.set_card_description(slot, config.format_description(effect, choice.nextLevel))
        popup.set_card_icon(slot, effect.icon)
    end
    popup.set_selected(nil)
end

local function encode_offer(state, serial, revision, choices, free_refresh, bonus_refresh)
    local hero_level = type(jass.GetHeroLevel) == "function" and jass.GetHeroLevel(state.hero) or 1
    return string.format(
        "OFFER|%d|%d|%d|%d|%d|%d|%d|%d|%s",
        VERSION, session_id, state.playerId, serial, revision, hero_level,
        free_refresh, bonus_refresh, table.concat(choices, ",")
    )
end

local open_next_offer

local function apply_offer(parts, sender_id)
    if sender_id ~= config.data.settings.hostPlayerId or #parts ~= 10 then return end
    local version = tonumber(parts[2])
    local incoming_session = tonumber(parts[3])
    local player_id = tonumber(parts[4])
    local serial = tonumber(parts[5])
    local revision = tonumber(parts[6])
    local hero_level = tonumber(parts[7])
    local free_refresh = tonumber(parts[8])
    local bonus_refresh = tonumber(parts[9])
    if version ~= VERSION or incoming_session ~= session_id or not is_integer(player_id)
        or not is_integer(serial) or serial < 1 or not is_integer(revision) or revision < 0
        or not is_integer(hero_level) or not is_integer(free_refresh) or free_refresh < 0
        or not is_integer(bonus_refresh) or bonus_refresh < 0 then return end
    local state = state_store.get_by_player_id(player_id)
    if state == nil then return end
    local choices = sync.split(parts[10], ",")
    if #choices ~= config.data.settings.choiceCount then return end
    local seen = {}
    for _, effect_id in ipairs(choices) do
        local effect = config.get_effect(effect_id)
        if effect == nil or seen[effect_id] or (state.owned[effect_id] or 0) >= effect.maxLevel
            or (effect.type == "Skill" and effect.hero ~= state.heroRawcode) then return end
        seen[effect_id] = true
    end
    local current = state.currentOffer
    if serial < state.offerSerial then return end
    if serial == state.offerSerial then
        if current == nil or revision <= current.revision then return end
    else
        if revision ~= 0 then return end
        state.pendingRewards = math.max(0, state.pendingRewards - 1)
    end
    state.offerSerial = serial
    state.bonusRefreshCount = bonus_refresh
    state.currentOffer = {
        serial = serial,
        revision = revision,
        heroLevel = hero_level,
        choices = choices,
        freeRefreshRemaining = free_refresh,
        remainingSeconds = config.data.settings.durationSeconds,
    }
    show_local_offer(state)
end

local function apply_reward(parts, sender_id)
    if sender_id ~= config.data.settings.hostPlayerId or #parts ~= 9 then return end
    local version = tonumber(parts[2])
    local incoming_session = tonumber(parts[3])
    local player_id = tonumber(parts[4])
    local serial = tonumber(parts[5])
    local revision = tonumber(parts[6])
    local effect_id = parts[7]
    local new_level = tonumber(parts[8])
    -- 字段 9 是协议保留校验位，首版固定为 1。
    local applied_flag = tonumber(parts[9])
    if version ~= VERSION or incoming_session ~= session_id or applied_flag ~= 1
        or not is_integer(player_id) or not is_integer(new_level) then return end
    local state = state_store.get_by_player_id(player_id)
    local offer = state and state.currentOffer or nil
    if offer == nil or offer.serial ~= serial or offer.revision ~= revision
        or not contains(offer.choices, effect_id) then return end
    local apply_key = string.format("%d:%d", serial, revision)
    if state.processedApplies[apply_key] then return end
    local effect = config.get_effect(effect_id)
    if effect == nil or new_level ~= (state.owned[effect_id] or 0) + 1 or new_level > effect.maxLevel then return end
    state.processedApplies[apply_key] = true
    state.owned[effect_id] = new_level
    state.currentOffer = nil
    attribute.rebuild(state)
    attribute.refresh(state)
    if sync.get_local_player_id() == player_id then
        local_selection[player_id] = nil
        popup.hide()
        print(string.format("获得肉鸽强化：%s Lv.%d", effect.name, new_level))
    end
    if sync.is_host() then open_next_offer(state) end
end

-- 使用显式第九字段，便于旧客户端在协议扩展时拒绝错误 APPLY。
local function issue_apply(state, effect_id)
    local offer = state.currentOffer
    if offer == nil or not contains(offer.choices, effect_id) then return false end
    local effect = config.get_effect(effect_id)
    local new_level = (state.owned[effect_id] or 0) + 1
    if effect == nil or new_level > effect.maxLevel then return false end
    sync.broadcast(string.format(
        "APPLY|%d|%d|%d|%d|%d|%s|%d|1",
        VERSION, session_id, state.playerId, offer.serial, offer.revision, effect_id, new_level
    ))
    return true
end

local function handle_pick_request(parts, sender_id)
    if not sync.is_host() or #parts ~= 7 then return end
    local player_id = tonumber(parts[4])
    local serial = tonumber(parts[5])
    local revision = tonumber(parts[6])
    local effect_id = parts[7]
    if tonumber(parts[2]) ~= VERSION or tonumber(parts[3]) ~= session_id
        or sender_id ~= player_id or not is_integer(player_id) then return end
    local state = state_store.get_by_player_id(player_id)
    local offer = state and state.currentOffer or nil
    if offer == nil or offer.serial ~= serial or offer.revision ~= revision then return end
    issue_apply(state, effect_id)
end

local function handle_refresh_request(parts, sender_id)
    if not sync.is_host() or #parts ~= 6 then return end
    local player_id = tonumber(parts[4])
    local serial = tonumber(parts[5])
    local revision = tonumber(parts[6])
    if tonumber(parts[2]) ~= VERSION or tonumber(parts[3]) ~= session_id
        or sender_id ~= player_id or not is_integer(player_id) then return end
    local state = state_store.get_by_player_id(player_id)
    local offer = state and state.currentOffer or nil
    if offer == nil or offer.serial ~= serial or offer.revision ~= revision then return end
    local free = offer.freeRefreshRemaining
    local bonus = state.bonusRefreshCount
    if free <= 0 and bonus <= 0 then return end
    if free > 0 then free = free - 1 else bonus = bonus - 1 end
    local choices = pool.draw(state, session_seed, serial, revision + 1, offer.choices)
    if choices == nil then return end
    sync.broadcast(encode_offer(state, serial, revision + 1, choices, free, bonus))
end

local function apply_refresh_grant(parts, sender_id)
    if sender_id ~= config.data.settings.hostPlayerId or #parts ~= 7 then return end
    local player_id = tonumber(parts[4])
    local amount = tonumber(parts[5])
    local new_bonus = tonumber(parts[6])
    local grant_serial = tonumber(parts[7])
    if tonumber(parts[2]) ~= VERSION or tonumber(parts[3]) ~= session_id
        or not is_integer(player_id) or not is_integer(amount) or amount < 1
        or not is_integer(new_bonus) or new_bonus < 0 or not is_integer(grant_serial) then return end
    local state = state_store.get_by_player_id(player_id)
    if state == nil or grant_serial < state.offerSerial then return end
    state.bonusRefreshCount = new_bonus
    if sync.get_local_player_id() == player_id and state.currentOffer ~= nil then
        local refresh_total = math.max(0, state.currentOffer.freeRefreshRemaining or 0) + math.max(0, new_bonus or 0)
        popup.set_refresh_text(string.format("刷新强化（%d）", refresh_total))
        popup.set_refresh_enabled(refresh_total > 0)
    end
end

local function dispatch_message(message, sender_id)
    local parts = sync.split(message, "|")
    if parts[1] == "OFFER" then apply_offer(parts, sender_id)
    elseif parts[1] == "PICK_REQUEST" then handle_pick_request(parts, sender_id)
    elseif parts[1] == "REFRESH_REQUEST" then handle_refresh_request(parts, sender_id)
    elseif parts[1] == "APPLY" then apply_reward(parts, sender_id)
    elseif parts[1] == "GRANT_REFRESH" then apply_refresh_grant(parts, sender_id) end
end

open_next_offer = function(state)
    if not critical_enabled or not sync.is_host() or state.currentOffer ~= nil or state.pendingRewards <= 0 then return end
    local serial = state.offerSerial + 1
    local choices = pool.draw(state, session_seed, serial, 0, nil)
    if choices == nil then
        print(string.format("肉鸽奖励池不足三项：player=%d", state.playerId))
        return
    end
    sync.broadcast(encode_offer(
        state, serial, 0, choices,
        config.data.settings.freeRefreshPerOffer, state.bonusRefreshCount
    ))
end

--- 计算从 previous_level 提升到 new_level 期间跨过的奖励等级数量。
--- 首次奖励等级和奖励间隔均由 roguelike.xlsx/settings 配置；间隔为 1 时保持每级奖励的旧行为。
local function get_level_reward_count(previous_level, new_level)
    local first_level = math.max(1, config.data.settings.firstRewardLevel or 1)
    local interval = math.max(1, config.data.settings.rewardLevelInterval or 1)

    if new_level < first_level then return 0 end

    local next_reward_level = first_level
    if next_reward_level <= previous_level then
        local passed_reward_count = math.floor((previous_level - next_reward_level) / interval) + 1
        next_reward_level = next_reward_level + passed_reward_count * interval
    end
    if next_reward_level > new_level then return 0 end

    return math.floor((new_level - next_reward_level) / interval) + 1
end

local function on_hero_level(hero)
    local state = state_store.get_by_hero(hero)
    if state == nil then return end
    local new_level = jass.GetHeroLevel(hero)
    if new_level <= state.lastObservedHeroLevel then return end
    local reward_count = get_level_reward_count(state.lastObservedHeroLevel, new_level)
    if reward_count > 0 then state.pendingRewards = state.pendingRewards + reward_count end
    state.lastObservedHeroLevel = new_level
    attribute.refresh(state)
    open_next_offer(state)
end

local function start_countdown()
    if runtime == nil then return false end
    return runtime:start_countdown(1.0, function()
        for _, state in pairs(state_store.get_all()) do
            local offer = state.currentOffer
            if offer ~= nil then
                offer.remainingSeconds = math.max(0, offer.remainingSeconds - 1)
                if sync.get_local_player_id() == state.playerId then
                    popup.set_remaining_seconds(string.format("%d 秒", math.max(0, tonumber(offer.remainingSeconds) or 0)))
                end
                if offer.remainingSeconds <= 0 and sync.is_host() then
                    local selected = offer.choices[1]
                    for _, effect_id in ipairs(offer.choices) do
                        if (state.owned[effect_id] or 0) > 0 then selected = effect_id break end
                    end
                    issue_apply(state, selected)
                end
            end
        end
    end)
end

function module.preload(on_completed)
    return hero_stats.preload(on_completed)
end

function module.start(hero_results, seed)
    if started then return false end
    local valid, errors = config.validate()
    if not valid then
        for _, message in ipairs(errors) do print("肉鸽配置错误：" .. message) end
        return false
    end
    started = true
    if lifecycle ~= nil then
        lifecycle.acquire("rogue.main", function()
            stop_child(hero_damage)
            stop_child(houyi)
            stop_child(arthas)
            stop_child(wukong)
            if runtime ~= nil then runtime:stop() end
            sync.stop()
            state_store.reset()
            runtime, local_selection = nil, {}
            started, sync_available, critical_enabled = false, false, false
        end)
    end
    session_seed = math.max(1, math.floor(tonumber(seed) or 1))
    session_id = session_seed % 2147483647
    if session_id < 1 then session_id = 1 end
    for _, result in ipairs(hero_results or {}) do state_store.create(result) end
    sync_available = sync.start(dispatch_message)
    critical_enabled = sync_available or count_states() <= 1
    if not sync_available and count_states() > 1 then
        print("肉鸽系统已禁用奖励发放：多人模式缺少 1.27 同步接口")
    elseif not sync_available then
        print("肉鸽系统使用单人本地权威模式")
    end
    runtime = runtime_service.create("rogue:" .. tostring(session_id))
    if not runtime:register_level_events(state_store.get_all(), on_hero_level) then
        print("肉鸽系统启动失败：无法注册英雄升级事件")
        return false
    end
    if not start_countdown() then
        print("肉鸽系统启动失败：无法创建强化倒计时")
        return false
    end
    wukong.start(hero_results or {}, session_seed)
    arthas.start(hero_results or {})
    houyi.start(hero_results or {})
    hero_damage.start(hero_results or {}, session_seed)
    debug.start(module)
    print(string.format("肉鸽系统已启动：玩家=%d，同步=%s", count_states(), tostring(sync_available)))
    return true
end

function module.stop()
    return lifecycle ~= nil and lifecycle.release("rogue.main") or false
end

function module.get_skill_value(hero, skill_rawcode, modifier_key)
    local state = state_store.get_by_hero(hero)
    local skill = state and state.skills[skill_rawcode] or nil
    return skill and skill[modifier_key] or 0
end

function module.get_common_value(hero, modifier_key)
    local state = state_store.get_by_hero(hero)
    return state and state.common[modifier_key] or 0
end

function module.refresh_hero_stats(hero)
    return attribute.refresh(state_store.get_by_hero(hero))
end

function module.grant_refresh_count(player_id, amount)
    if not started or not critical_enabled or not sync.is_host()
        or not is_integer(player_id) or not is_integer(amount) or amount < 1 then return false end
    local state = state_store.get_by_player_id(player_id)
    if state == nil then return false end
    local new_bonus = state.bonusRefreshCount + amount
    sync.broadcast(string.format(
        "GRANT_REFRESH|%d|%d|%d|%d|%d|%d",
        VERSION, session_id, player_id, amount, new_bonus, state.offerSerial
    ))
    return true
end

function module.debug_force_offer(player_id)
    local state = state_store.get_by_player_id(player_id)
    if state == nil or not sync.is_host() then return false end
    state.pendingRewards = state.pendingRewards + 1
    open_next_offer(state)
    return true
end

function module.debug_timeout(player_id)
    local state = state_store.get_by_player_id(player_id)
    if state == nil or state.currentOffer == nil then return false end
    state.currentOffer.remainingSeconds = 1
    return true
end

local function format_levels(group)
    local entries = {}
    for index, rawcode in ipairs(group.rawcodes or {}) do
        table.insert(entries, string.format(
            "%s=%d/%d",
            tostring(rawcode),
            math.floor(tonumber(group.actualLevels and group.actualLevels[index]) or 0),
            math.floor(tonumber(group.expectedLevels and group.expectedLevels[index]) or 0)
        ))
    end
    return table.concat(entries, ",")
end

--- 输出本地玩家英雄的攻速配置和隐藏 AIsx 等级；不修改任何同步状态。
function module.debug_attack_speed(player_id)
    if not is_integer(player_id) then return false end
    local state = state_store.get_by_player_id(player_id)
    if state == nil or state.hero == nil then
        print("攻速调试失败：未找到玩家英雄，player=" .. tostring(player_id))
        return false
    end
    local debug = hero_stats.get_attack_speed_debug(state.hero)
    if debug == nil then
        print("攻速调试失败：英雄尚未注册统一属性系统")
        return false
    end
    print(string.format(
        "攻速调试：hero=%s, cool1=%.3f, 配置=%d%%, 来源=%+d%%, 目标=%d%%, 预期间隔=%.3fs, 敏捷=%d, 原生敏捷=%+.1f%%, 隐藏投影=%+.1f%%",
        tostring(debug.heroRawcode or "unknown"),
        debug.baseAttackCooldown,
        debug.configuredPercent,
        debug.sourceBonusPercent,
        debug.targetPercent,
        debug.expectedAttackIntervalSeconds,
        debug.agility,
        debug.nativeAgilityBonusTenth / 10,
        debug.desiredProjectionTenth / 10
    ))
    print("攻速调试 AIsx 正向(实际/期望)：" .. format_levels(debug.positive))
    print("攻速调试 AIsx 负向(实际/期望)：" .. format_levels(debug.negative))
    return true
end

--- 输出本地玩家英雄的生命公式、AIlf 投影和实际生命；不修改任何同步状态。
function module.debug_health(player_id)
    if not is_integer(player_id) then return false end
    local state = state_store.get_by_player_id(player_id)
    if state == nil or state.hero == nil then
        print("生命调试失败：未找到玩家英雄，player=" .. tostring(player_id))
        return false
    end
    local debug = hero_stats.get_health_debug(state.hero)
    if debug == nil then
        print("生命调试失败：英雄尚未注册统一属性系统")
        return false
    end
    print(string.format(
        "生命调试：基础=%d, 力量=%d, 固定=%+d, 增幅=%+d%%, 公式=%d, 已投影=%+d, 待写入=%+d, 上限=%d, 实际=%d/%d",
        debug.baseLife,
        debug.strength,
        debug.fixedHealth,
        debug.amplificationPercent,
        debug.desiredLife,
        debug.appliedProjection,
        debug.pendingDelta,
        debug.projectionMaximum,
        debug.currentLife,
        debug.maximumLife
    ))
    print("生命调试 AIlf 增加(临时技能，移除后应为 0)：" .. format_levels(debug.positive))
    print("生命调试 AIlf 减少(临时技能，移除后应为 0)：" .. format_levels(debug.negative))
    return true
end

JiuDou.publish("gameplay.rogue.main", module)
return module
