--- PVE 刷怪业务入口。
--- 负责基于同步种子确定性生成怪物、难度属性缩放、固定节拍复活与区域内 AI。
local jass = require "jass.common"
local config = require "monster.config"
local random = require "monster.random"
local monster_stats = require "platform.monster_stats"
local damage_numbers = require "combat.damage_numbers"
local gold = require "gold.main"
local experience = require "experience.main"
local cataclysm_ui = require "monster.ui.cataclysm"

local module = {}

local NEUTRAL_HOSTILE_PLAYER_ID = 12
local WALKABLE_PATHING = jass.PATHING_TYPE_WALKABILITY
local NORMAL_SLOT_COUNT = 450
local ELITE_SLOT_COUNT = 27
local INITIAL_SPAWN_BATCH_SIZE = 6
local INITIAL_SPAWN_INTERVAL_SECONDS = 0.04

---@class MonsterSlot
---@field id integer 稳定槽位编号
---@field kind "normal"|"elite"|"boss" 单位类别
---@field blockId integer 所属地图区域
---@field region MonsterRegion 出生区域
---@field rawcode string|nil 当前单位 Rawcode
---@field unit unit|nil 当前单位句柄
---@field random MonsterRandom 槽位独立随机流
---@field affixRandom MonsterRandom 词缀选择专用随机流
---@field generation integer 已创建次数
---@field respawnTick integer|nil 下一次复活的调度 tick
---@field bossSpawnTick integer|nil Boss 固定生成 tick
---@field homeX number|nil 最近出生点 X 坐标
---@field homeY number|nil 最近出生点 Y 坐标
---@field facing number|nil 本次创建使用的朝向，用于跨客户端校验
---@field activeAbilities MonsterActiveAbility[] 自动施放技能
---@field nextAbilityIndex integer 下一次尝试的主动技能下标
---@field nextCastAt table<string, number> 各技能下次可施放的秒数
---@field currentTarget unit|nil 最近攻击目标
---@field elitePoint EliteSpawnPoint|nil 精英点配置
---@field eliteAbilityRawcode string|nil 精英本次随机获得的技能，用于跨客户端校验
---@field bossAffix BossAffixConfig|nil Boss 自身携带的天灾词缀
---@field affixId string|nil 本次小怪继承的天灾词缀编号
---@field affixAbilityRawcode string|nil 本次小怪挂载的天灾技能，用于跨客户端校验
---@field affixIndicatorAbilityRawcode string|nil 本次小怪挂载的状态栏图标技能
---@field affixEffect effect|nil 本次小怪的天灾词缀识别特效

local running = false
local scheduler_timer = nil
local initial_spawn_timer = nil
local death_trigger = nil
local scheduler_tick = 0
local difficulty = nil
local hero_results = {}
local session_seed_value = nil
local initial_spawn_queue = {}
local initial_spawn_index = 1
local on_scheduler_tick
local shared_vision_warning_printed = false
local minimap_ping_warning_printed = false
local boss_announcement_warning_printed = false
local boss_affix_effect_warning_printed = false

---@type MonsterSlot[]
local slots = {}
---@type table<unit, MonsterSlot>
local slot_by_unit = {}

local function rawcode_to_unit_id(rawcode)
    local first_byte, second_byte, third_byte, fourth_byte = string.byte(rawcode, 1, 4)
    if first_byte == nil or second_byte == nil or third_byte == nil or fourth_byte == nil then
        return nil
    end
    return first_byte * 0x1000000
        + second_byte * 0x10000
        + third_byte * 0x100
        + fourth_byte
end

local function is_alive(unit_handle)
    return unit_handle ~= nil and jass.GetWidgetLife(unit_handle) > 0.405
end

local function is_inside_region(region, x, y)
    return x >= region.minX and x <= region.maxX and y >= region.minY and y <= region.maxY
end

local function squared_distance(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return dx * dx + dy * dy
end

local function seconds_to_ticks(seconds)
    return math.ceil(seconds / config.SETTINGS.schedulerIntervalSeconds)
end

local function get_random_point(region, rng)
    local inset = config.SETTINGS.pointInset
    local minimum_x = math.ceil(region.minX + inset)
    local maximum_x = math.floor(region.maxX - inset)
    local minimum_y = math.ceil(region.minY + inset)
    local maximum_y = math.floor(region.maxY - inset)
    if minimum_x > maximum_x or minimum_y > maximum_y then
        error("刷怪区域过小，无法取随机坐标：" .. region.name)
    end

    for _ = 1, config.SETTINGS.randomPointAttempts do
        local x = random.next_integer(rng, minimum_x, maximum_x)
        local y = random.next_integer(rng, minimum_y, maximum_y)
        if not jass.IsTerrainPathable(x, y, WALKABLE_PATHING) then
            return x, y
        end
    end

    print("警告：刷怪区域未找到可行走随机点，回退至中心：" .. region.name)
    return (region.minX + region.maxX) * 0.5, (region.minY + region.maxY) * 0.5
end

local function create_unit(rawcode, x, y, facing)
    local unit_id = rawcode_to_unit_id(rawcode)
    if unit_id == nil then
        return nil
    end
    return jass.CreateUnit(jass.Player(NEUTRAL_HOSTILE_PLAYER_ID), unit_id, x, y, facing)
end

local function apply_difficulty(unit_handle, rawcode)
    local base = config.get_unit_base_stats(rawcode)
    if base == nil then
        error("怪物单位缺少基础属性：" .. rawcode)
    end
    local scaled = monster_stats.calculate(base, difficulty)
    local applied, message = monster_stats.apply(unit_handle, rawcode, difficulty, scaled)
    if not applied then
        error("怪物难度属性应用失败：" .. rawcode .. "，" .. tostring(message))
    end
end

--- 将 Boss 当前视野共享给本局所有 PVE 玩家。
--- 该原生接口在 Boss 出生、死亡时各调用一次，不需要位置轮询或迷雾刷新。
---@param boss_unit unit
---@param enabled boolean
local function set_boss_shared_vision(boss_unit, enabled)
    if type(jass.UnitShareVision) ~= "function" then
        if not shared_vision_warning_printed then
            print("Boss 视野共享未启用：当前运行时缺少 UnitShareVision 接口")
            shared_vision_warning_printed = true
        end
        return false
    end
    for _, result in ipairs(hero_results) do
        jass.UnitShareVision(boss_unit, jass.Player(result.playerId), enabled)
    end
    return true
end

--- 在所有玩家的小地图上标出本次 Boss 的位置。
--- 仅在 Boss 出现时调用一次；位置来自确定性 Boss 点中心。
---@param x number
---@param y number
local function ping_boss_minimap(x, y)
    if type(jass.PingMinimap) ~= "function" then
        if not minimap_ping_warning_printed then
            print("Boss 小地图提示未启用：当前运行时缺少 PingMinimap 接口")
            minimap_ping_warning_printed = true
        end
        return false
    end
    jass.PingMinimap(x, y, config.SETTINGS.bossMinimapPingSeconds)
    return true
end

--- 向每个客户端的本地玩家显示 Boss 降临公告。
--- 该函数只使用本地文字界面，不读取或写入任何同步游戏状态。
---@param rawcode string
local function announce_boss_arrival(rawcode)
    if type(jass.DisplayTimedTextToPlayer) ~= "function" or type(jass.GetLocalPlayer) ~= "function" then
        if not boss_announcement_warning_printed then
            print("Boss 降临公告未启用：当前运行时缺少 DisplayTimedTextToPlayer 或 GetLocalPlayer 接口")
            boss_announcement_warning_printed = true
        end
        return false
    end
    local boss_name = config.get_unit_name(rawcode) or rawcode
    local message = string.format(
        "【%s】·天灾降临！后续产生的小怪将可能被天灾 Boss 强化，请立即前往击杀！",
        boss_name
    )
    jass.DisplayTimedTextToPlayer(
        jass.GetLocalPlayer(),
        0,
        0,
        config.SETTINGS.bossAnnouncementSeconds,
        message
    )
    return true
end

--- 按 Boss 槽位稳定顺序收集当前存活 Boss 的词缀池。
--- 已生成的小怪不会重新读取此池，因此 Boss 死亡只影响后续刷新的单位。
---@return BossAffixConfig[] affixes 当前可继承的词缀
local function collect_alive_boss_affixes()
    local affixes = {}
    for _, boss_slot in ipairs(slots) do
        if boss_slot.kind == "boss" and is_alive(boss_slot.unit) then
            local affix = boss_slot.bossAffix
            if affix == nil then
                error("存活 Boss 缺少天灾词缀：" .. tostring(boss_slot.rawcode))
            end
            table.insert(affixes, affix)
        end
    end
    return affixes
end

--- 销毁一个槽位的天灾词缀识别特效。
--- 特效仅服务显示，绝不参与随机数、调度或其他同步状态。
---@param slot MonsterSlot
local function clear_boss_affix_effect(slot)
    if slot.affixEffect == nil then
        return
    end
    if type(jass.DestroyEffect) == "function" then
        jass.DestroyEffect(slot.affixEffect)
    end
    slot.affixEffect = nil
end

--- 为已继承天灾词缀的小怪添加持续识别特效。
---@param slot MonsterSlot
---@param unit_handle unit
local function add_boss_affix_effect(slot, unit_handle)
    if type(jass.AddSpecialEffectTarget) ~= "function" then
        if not boss_affix_effect_warning_printed then
            print("Boss 词缀特效未启用：当前运行时缺少 AddSpecialEffectTarget 接口")
            boss_affix_effect_warning_printed = true
        end
        return
    end
    local effect_handle = jass.AddSpecialEffectTarget(
        config.SETTINGS.bossAffixEffectModel,
        unit_handle,
        config.SETTINGS.bossAffixEffectAttachment
    )
    if effect_handle == nil then
        if not boss_affix_effect_warning_printed then
            print("Boss 词缀特效创建失败：" .. config.SETTINGS.bossAffixEffectModel)
            boss_affix_effect_warning_printed = true
        end
        return
    end
    slot.affixEffect = effect_handle
end

--- 为新创建的普通怪或精英添加一个来自当前存活 Boss 池的词缀。
--- 词缀随机流独立于位置、精英技能随机流；只有池中至少两项时才消费随机数。
---@param slot MonsterSlot 小怪稳定槽位
---@param unit_handle unit 刚创建的单位
---@param rawcode string 小怪 Rawcode
local function apply_boss_affix(slot, unit_handle, rawcode)
    clear_boss_affix_effect(slot)
    slot.affixId = nil
    slot.affixAbilityRawcode = nil
    slot.affixIndicatorAbilityRawcode = nil
    if slot.kind == "boss" then
        return
    end

    local affixes = collect_alive_boss_affixes()
    if #affixes == 0 then
        return
    end
    local affix = affixes[1]
    if #affixes > 1 then
        local affix_index = random.next_integer(slot.affixRandom, 1, #affixes)
        affix = affixes[affix_index]
    end
    local ability_rawcode, ability_level, refill_life = config.get_boss_affix_ability(
        affix,
        rawcode,
        difficulty
    )
    if ability_rawcode == nil or ability_level == nil then
        error("Boss 词缀技能映射缺失：词缀=" .. tostring(affix.affixId) .. "，单位=" .. rawcode)
    end
    local ability_id = rawcode_to_unit_id(ability_rawcode)
    if ability_id == nil or not jass.UnitAddAbility(unit_handle, ability_id) then
        error("Boss 词缀技能添加失败：词缀=" .. tostring(affix.affixId) .. "，技能=" .. ability_rawcode)
    end
    jass.SetUnitAbilityLevel(unit_handle, ability_id, ability_level)
    if refill_life then
        if type(jass.GetUnitState) ~= "function" or jass.UNIT_STATE_MAX_LIFE == nil then
            error("Boss 生命词缀需要 GetUnitState 与 UNIT_STATE_MAX_LIFE 接口")
        end
        local maximum_life = jass.GetUnitState(unit_handle, jass.UNIT_STATE_MAX_LIFE)
        jass.SetUnitState(unit_handle, jass.UNIT_STATE_LIFE, maximum_life)
    end
    local indicator_rawcode = config.get_boss_affix_indicator(affix)
    local indicator_id = rawcode_to_unit_id(indicator_rawcode or "")
    if indicator_id == nil or not jass.UnitAddAbility(unit_handle, indicator_id) then
        error("Boss 词缀状态栏图标技能添加失败：词缀=" .. tostring(affix.affixId)
            .. "，技能=" .. tostring(indicator_rawcode))
    end
    jass.SetUnitAbilityLevel(unit_handle, indicator_id, 1)
    slot.affixId = affix.affixId
    slot.affixAbilityRawcode = ability_rawcode
    slot.affixIndicatorAbilityRawcode = indicator_rawcode
    add_boss_affix_effect(slot, unit_handle)
end

local function register_unit(slot, unit_handle, rawcode, x, y, facing, active_abilities, elite_ability_rawcode)
    apply_difficulty(unit_handle, rawcode)
    apply_boss_affix(slot, unit_handle, rawcode)
    slot.unit = unit_handle
    slot.rawcode = rawcode
    slot.homeX = x
    slot.homeY = y
    slot.facing = facing
    slot.activeAbilities = active_abilities
    slot.nextAbilityIndex = 1
    slot.nextCastAt = {}
    slot.currentTarget = nil
    slot.eliteAbilityRawcode = elite_ability_rawcode
    slot.respawnTick = nil
    slot.generation = slot.generation + 1
    slot_by_unit[unit_handle] = slot
    damage_numbers.register_target(unit_handle)
    local max_life = 1
    if type(jass.GetUnitState) == "function" and jass.UNIT_STATE_MAX_LIFE ~= nil then
        max_life = math.max(1, math.floor(tonumber(jass.GetUnitState(unit_handle, jass.UNIT_STATE_MAX_LIFE)) or 1))
    end
    gold.register_monster(unit_handle, slot.kind, slot.blockId, slot.generation, max_life)
    experience.register_monster(unit_handle, slot.kind, rawcode, slot.generation, max_life)
end

local function spawn_normal(slot)
    local block = config.get_block(slot.blockId)
    local rawcode = block.normalRangedRawcode
    if random.next_integer(slot.random, 1, 100) <= config.SETTINGS.normalMeleeChance then
        rawcode = block.normalMeleeRawcode
    end
    local x, y = get_random_point(slot.region, slot.random)
    local facing = random.next_integer(slot.random, 0, 359)
    local unit_handle = create_unit(rawcode, x, y, facing)
    if unit_handle == nil then
        error("普通怪创建失败：" .. rawcode)
    end
    register_unit(slot, unit_handle, rawcode, x, y, facing, {}, nil)
end

local function spawn_elite(slot)
    local x, y = get_random_point(slot.region, slot.random)
    local ability_index = random.next_integer(slot.random, 1, #config.ELITE_ABILITY_RAWCODES)
    local ability_rawcode = config.ELITE_ABILITY_RAWCODES[ability_index]
    local facing = random.next_integer(slot.random, 0, 359)
    local unit_handle = create_unit(slot.elitePoint.eliteRawcode, x, y, facing)
    if unit_handle == nil then
        error("精英创建失败：" .. slot.elitePoint.eliteRawcode)
    end

    local ability_id = rawcode_to_unit_id(ability_rawcode)
    if ability_id == nil or not jass.UnitAddAbility(unit_handle, ability_id) then
        error("精英技能添加失败：" .. ability_rawcode)
    end
    jass.SetUnitAbilityLevel(unit_handle, ability_id, 1)

    local active_abilities = {}
    local active_ability = config.get_active_ability(ability_rawcode)
    if active_ability ~= nil then
        table.insert(active_abilities, active_ability)
    end
    register_unit(
        slot,
        unit_handle,
        slot.elitePoint.eliteRawcode,
        x,
        y,
        facing,
        active_abilities,
        ability_rawcode
    )
end

local function spawn_boss(slot)
    local x = (slot.region.minX + slot.region.maxX) * 0.5
    local y = (slot.region.minY + slot.region.maxY) * 0.5
    local unit_handle = create_unit(slot.rawcode, x, y, 270.0)
    if unit_handle == nil then
        error("Boss 创建失败：" .. slot.rawcode)
    end
    register_unit(
        slot,
        unit_handle,
        slot.rawcode,
        x,
        y,
        270.0,
        config.get_unit_active_abilities(slot.rawcode),
        nil
    )
    set_boss_shared_vision(unit_handle, true)
    ping_boss_minimap(x, y)
    cataclysm_ui.show()
    announce_boss_arrival(slot.rawcode)
end

local function new_slot(id, kind, block_id, region, session_seed)
    return {
        id = id,
        kind = kind,
        blockId = block_id,
        region = region,
        rawcode = nil,
        unit = nil,
        random = random.create(random.derive_seed(session_seed, id)),
        affixRandom = random.create(random.derive_seed(session_seed, 10000 + id)),
        generation = 0,
        respawnTick = nil,
        bossSpawnTick = nil,
        homeX = nil,
        homeY = nil,
        facing = nil,
        activeAbilities = {},
        nextAbilityIndex = 1,
        nextCastAt = {},
        currentTarget = nil,
        elitePoint = nil,
        eliteAbilityRawcode = nil,
        bossAffix = nil,
        affixId = nil,
        affixAbilityRawcode = nil,
        affixIndicatorAbilityRawcode = nil,
    }
end

local function create_slots(session_seed)
    slots = {}
    slot_by_unit = {}
    local slot_id = 0
    for _, block in ipairs(config.BLOCKS) do
        for _ = 1, config.SETTINGS.normalCountPerBlock do
            slot_id = slot_id + 1
            table.insert(slots, new_slot(slot_id, "normal", block.id, block.region, session_seed))
        end
    end
    for _, point in ipairs(config.ELITE_POINTS) do
        slot_id = slot_id + 1
        local slot = new_slot(slot_id, "elite", point.blockId, point.region, session_seed)
        slot.elitePoint = point
        table.insert(slots, slot)
    end
    for _, point in ipairs(config.BOSS_POINTS) do
        slot_id = slot_id + 1
        local slot = new_slot(slot_id, "boss", point.blockId, point.region, session_seed)
        slot.rawcode = point.bossRawcode
        slot.bossAffix = config.get_boss_affix(slot.rawcode)
        if slot.bossAffix == nil then
            error("Boss 槽位缺少天灾词缀：" .. slot.rawcode)
        end
        slot.bossSpawnTick = seconds_to_ticks(config.SETTINGS.bossSpawnIntervalSeconds * point.id)
        table.insert(slots, slot)
    end
    if slot_id ~= NORMAL_SLOT_COUNT + ELITE_SLOT_COUNT + #config.BOSS_POINTS then
        error("刷怪槽位数量异常")
    end
end

local function on_monster_death()
    local dying_unit = jass.GetDyingUnit()
    local slot = slot_by_unit[dying_unit]
    if slot == nil then
        return
    end
    slot_by_unit[dying_unit] = nil
    clear_boss_affix_effect(slot)
    slot.unit = nil
    slot.currentTarget = nil
    if slot.kind == "boss" then
        set_boss_shared_vision(dying_unit, false)
    elseif slot.kind == "normal" then
        slot.respawnTick = scheduler_tick + seconds_to_ticks(config.SETTINGS.normalRespawnSeconds)
    elseif slot.kind == "elite" then
        slot.respawnTick = scheduler_tick + seconds_to_ticks(config.SETTINGS.eliteRespawnSeconds)
    end
end

local function collect_heroes()
    local heroes = {}
    for _, result in ipairs(hero_results) do
        if is_alive(result.unit) then
            table.insert(heroes, result.unit)
        end
    end
    return heroes
end

local function find_target(slot, heroes)
    local unit_x = jass.GetUnitX(slot.unit)
    local unit_y = jass.GetUnitY(slot.unit)
    local closest = nil
    local closest_distance = nil
    for _, hero in ipairs(heroes) do
        local hero_x = jass.GetUnitX(hero)
        local hero_y = jass.GetUnitY(hero)
        if is_inside_region(slot.region, hero_x, hero_y) then
            local distance = squared_distance(unit_x, unit_y, hero_x, hero_y)
            if closest_distance == nil or distance < closest_distance then
                closest = hero
                closest_distance = distance
            end
        end
    end
    return closest, closest_distance or 0
end

local function try_cast_ability(slot, target, target_distance, elapsed_seconds)
    local ability_count = #slot.activeAbilities
    for offset = 0, ability_count - 1 do
        local index = ((slot.nextAbilityIndex - 1 + offset) % ability_count) + 1
        local ability = slot.activeAbilities[index]
        if elapsed_seconds >= (slot.nextCastAt[ability.rawcode] or 0)
            and target_distance <= ability.range * ability.range then
            local issued = false
            if ability.targetType == "point" then
                issued = jass.IssuePointOrder(slot.unit, ability.order, jass.GetUnitX(target), jass.GetUnitY(target))
            elseif ability.targetType == "unit" then
                issued = jass.IssueTargetOrder(slot.unit, ability.order, target)
            else
                issued = jass.IssueImmediateOrder(slot.unit, ability.order)
            end
            slot.nextAbilityIndex = (index % ability_count) + 1
            if issued then
                slot.nextCastAt[ability.rawcode] = elapsed_seconds + ability.cooldown
                return true
            end
        end
    end
    return false
end

local function update_ai()
    local heroes = collect_heroes()
    local elapsed_seconds = scheduler_tick * config.SETTINGS.schedulerIntervalSeconds
    for _, slot in ipairs(slots) do
        if is_alive(slot.unit) then
            local target, target_distance = find_target(slot, heroes)
            if target == nil then
                if slot.currentTarget ~= nil then
                    jass.IssuePointOrder(slot.unit, "move", slot.homeX, slot.homeY)
                    slot.currentTarget = nil
                end
            else
                if slot.currentTarget ~= target then
                    jass.IssueTargetOrder(slot.unit, "attack", target)
                    slot.currentTarget = target
                end
                if try_cast_ability(slot, target, target_distance, elapsed_seconds) then
                    slot.currentTarget = nil
                end
            end
        end
    end
end

local function process_due_spawns()
    for _, slot in ipairs(slots) do
        if slot.kind == "boss" and slot.bossSpawnTick ~= nil and slot.bossSpawnTick <= scheduler_tick then
            slot.bossSpawnTick = nil
            spawn_boss(slot)
        end
    end
    for _, slot in ipairs(slots) do
        if slot.respawnTick ~= nil and slot.respawnTick <= scheduler_tick then
            if slot.kind == "normal" then
                spawn_normal(slot)
            elseif slot.kind == "elite" then
                spawn_elite(slot)
            end
        end
    end
end

local function start_scheduler()
    scheduler_timer = jass.CreateTimer()
    jass.TimerStart(scheduler_timer, config.SETTINGS.schedulerIntervalSeconds, true, on_scheduler_tick)
    print(string.format(
        "PVE 刷怪系统已启动：属性后端=%s，难度=%d，模式=%d，生命倍率=%d/10，攻击倍率=%d/10，护甲+%d，普通怪=%d，精英=%d",
        monster_stats.get_backend_name(),
        difficulty.level,
        difficulty.modeId,
        difficulty.healthMultiplier,
        difficulty.attackMultiplier,
        difficulty.armorBonus,
        NORMAL_SLOT_COUNT,
        ELITE_SLOT_COUNT
    ))
end

local function finish_initial_spawn()
    if initial_spawn_timer ~= nil then
        jass.PauseTimer(initial_spawn_timer)
        jass.DestroyTimer(initial_spawn_timer)
        initial_spawn_timer = nil
    end
    initial_spawn_queue = {}
    initial_spawn_index = 1
    print("PVE 首波怪物分帧生成完成")
    print("PVE 刷怪状态摘要：" .. module.get_state_summary())
end

--- 优先生成玩家所在区域，再分帧补齐其余初始怪物。
--- 每个槽位拥有独立随机流，因此调整创建先后不会改变跨客户端结果。
local function build_initial_spawn_queue()
    local priority_blocks = {}
    for _, result in ipairs(hero_results) do
        priority_blocks[result.blockId] = true
    end

    local queue = {}
    local last_initial_slot = NORMAL_SLOT_COUNT + ELITE_SLOT_COUNT
    for priority_pass = 1, 2 do
        local want_priority = priority_pass == 1
        for index = 1, last_initial_slot do
            local slot = slots[index]
            local is_priority = priority_blocks[slot.blockId] == true
            if is_priority == want_priority then
                table.insert(queue, slot)
            end
        end
    end
    return queue
end

local function spawn_initial_batch()
    local last_index = math.min(
        #initial_spawn_queue,
        initial_spawn_index + INITIAL_SPAWN_BATCH_SIZE - 1
    )
    for index = initial_spawn_index, last_index do
        local slot = initial_spawn_queue[index]
        if slot.kind == "normal" then
            spawn_normal(slot)
        else
            spawn_elite(slot)
        end
    end
    initial_spawn_index = last_index + 1
    if initial_spawn_index > #initial_spawn_queue then
        finish_initial_spawn()
    end
end

local function start_initial_spawn()
    initial_spawn_queue = build_initial_spawn_queue()
    initial_spawn_index = 1
    initial_spawn_timer = jass.CreateTimer()
    jass.TimerStart(initial_spawn_timer, INITIAL_SPAWN_INTERVAL_SECONDS, true, spawn_initial_batch)
    print(string.format(
        "PVE 首波怪物开始分帧生成：共%d只，每批%d只，优先玩家所在区域",
        #initial_spawn_queue,
        INITIAL_SPAWN_BATCH_SIZE
    ))
end

on_scheduler_tick = function()
    scheduler_tick = scheduler_tick + 1
    process_due_spawns()
    if scheduler_tick % seconds_to_ticks(config.SETTINGS.aiIntervalSeconds) == 0 then
        update_ai()
    end
end

local function hash_text(value, seed)
    local hash = seed
    for index = 1, #value do
        hash = (hash * 65599 + string.byte(value, index)) % 2147483647
    end
    return hash
end

--- 返回可在多个客户端控制台比对的确定性槽位摘要。
--- 摘要不包含单位句柄、当前位置或目标等会随战斗变化的数据，只包含槽位生成结果与调度状态。
---@return string summary 当前槽位状态摘要
function module.get_state_summary()
    local hash = 5381
    local normal_alive = 0
    local elite_alive = 0
    local boss_alive = 0
    for _, slot in ipairs(slots) do
        if is_alive(slot.unit) then
            if slot.kind == "normal" then
                normal_alive = normal_alive + 1
            elseif slot.kind == "elite" then
                elite_alive = elite_alive + 1
            else
                boss_alive = boss_alive + 1
            end
        end
        local record = string.format(
            "%d,%s,%d,%s,%.3f,%.3f,%.3f,%s,%s,%s,%s,%d,%d,%d,%d;",
            slot.id,
            slot.kind,
            slot.generation,
            slot.rawcode or "-",
            slot.homeX or 0.0,
            slot.homeY or 0.0,
            slot.facing or 0.0,
            slot.eliteAbilityRawcode or "-",
            slot.affixId or "-",
            slot.affixAbilityRawcode or "-",
            slot.affixIndicatorAbilityRawcode or "-",
            slot.respawnTick or 0,
            slot.bossSpawnTick or 0,
            slot.random.state,
            slot.affixRandom.state
        )
        hash = hash_text(record, hash)
    end
    return string.format(
        "seed=%d,tick=%d,alive=%d/%d/%d,slots=%d,hash=%d",
        session_seed_value or 0,
        scheduler_tick,
        normal_alive,
        elite_alive,
        boss_alive,
        #slots,
        hash
    )
end

--- 启动 PVE 的确定性刷怪系统。
---@param selection ModeSelection 已同步的 PVE 模式选择
---@param selections HeroSelectionResult[] 已创建且按玩家编号排序的英雄结果
---@param session_seed integer 随 FINAL 消息同步的本局随机种子
---@return boolean started 是否成功首次启动
function module.start(selection, selections, session_seed)
    if running then
        return false
    end
    if not monster_stats.is_available() then
        print(
            "PVE 刷怪系统启动失败：当前运行时缺少 Warcraft 1.27 单位技能接口（"
                .. table.concat(monster_stats.get_missing_interfaces(), ", ")
                .. "）"
        )
        return false
    end
    local created_difficulty, message = config.create_difficulty(selection)
    if created_difficulty == nil then
        print("PVE 刷怪系统启动失败：" .. tostring(message))
        return false
    end
    if type(session_seed) ~= "number"
        or session_seed ~= math.floor(session_seed)
        or session_seed < 1
        or session_seed > 2147483646 then
        print("PVE 刷怪系统启动失败：随机种子无效")
        return false
    end

    difficulty = created_difficulty
    session_seed_value = math.floor(session_seed)
    hero_results = {}
    for _, result in ipairs(selections or {}) do
        if result.unit ~= nil then
            table.insert(hero_results, result)
        end
    end
    table.sort(hero_results, function(left, right)
        return left.playerId < right.playerId
    end)

    scheduler_tick = 0
    create_slots(session_seed)
    death_trigger = jass.CreateTrigger()
    jass.TriggerRegisterPlayerUnitEvent(
        death_trigger,
        jass.Player(NEUTRAL_HOSTILE_PLAYER_ID),
        jass.EVENT_PLAYER_UNIT_DEATH,
        nil
    )
    jass.TriggerAddAction(death_trigger, on_monster_death)

    running = true
    start_scheduler()
    start_initial_spawn()
    return true
end

return module
