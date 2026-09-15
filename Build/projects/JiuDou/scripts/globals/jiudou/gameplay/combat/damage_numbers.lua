--- PVE 伤害飘字业务模块。
--- 监听玩家英雄造成的最终伤害，并通过固定 texttag 对象池显示向上飘动的数字。
--- 普攻及普攻加成沿用原有黄橙色；技能、触发、召唤物和装备自动技能伤害使用蓝色。
local jass = require "jass.common"
local damage_service = require "combat.damage"

local module = {}

local POOL_CAPACITY = 64
local UPDATE_INTERVAL_SECONDS = 0.05
local DISPLAY_DURATION_SECONDS = 1.20
local FADE_START_SECONDS = 0.80
local TEXT_HEIGHT = 0.024
local TEXT_HEIGHT_OFFSET = 100.0
local TEXT_VELOCITY_Y = 0.0355
local COLOR_RED = 255
local COLOR_GREEN = 220
local COLOR_BLUE = 60
local SKILL_COLOR_RED = 80
local SKILL_COLOR_GREEN = 170
local SKILL_COLOR_BLUE = 255
local HEAL_COLOR_RED = 80
local HEAL_COLOR_GREEN = 255
local HEAL_COLOR_BLUE = 100
local COLOR_ALPHA = 255
local GOLD_COLOR_RED = 255
local GOLD_COLOR_GREEN = 215
local GOLD_COLOR_BLUE = 0
local HORIZONTAL_OFFSETS = {-18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 18.0}

---@class DamageNumberEntry
---@field tag texttag 原生文本标签
---@field fadeAt number 本次开始淡出的时间
---@field expiresAt number 本次显示的结束时间
---@field active boolean 当前是否正在显示
---@field red integer 当前文字红色通道
---@field green integer 当前文字绿色通道
---@field blue integer 当前文字蓝色通道

local started = false
local warned_unavailable = false
local elapsed_seconds = 0.0
local next_pool_index = 1
local display_sequence = 0
local update_timer = nil
local hero_sources = {}
local tracked_heroes = {}
local last_hero_life = {}
local pending_heal_fraction = {}
local first_damage_logged = false
---@type DamageNumberEntry[]
local pool = {}

local function has_required_api()
    return type(jass.CreateTextTag) == "function"
        and type(jass.SetTextTagText) == "function"
        and type(jass.SetTextTagPos) == "function"
        and type(jass.SetTextTagColor) == "function"
        and type(jass.SetTextTagVelocity) == "function"
        and type(jass.SetTextTagVisibility) == "function"
        and type(jass.SetTextTagSuspended) == "function"
        and type(jass.SetTextTagPermanent) == "function"
        and type(jass.SetTextTagAge) == "function"
        and type(jass.GetUnitX) == "function"
        and type(jass.GetUnitY) == "function"
        and type(jass.GetHandleId) == "function"
        and type(jass.GetOwningPlayer) == "function"
        and type(jass.IsUnitEnemy) == "function"
        and type(jass.CreateTimer) == "function"
        and type(jass.TimerStart) == "function"
end

local function hide_entry(entry)
    if not entry.active then
        return
    end

    jass.SetTextTagVisibility(entry.tag, false)
    jass.SetTextTagSuspended(entry.tag, true)
    entry.active = false
end

local function create_pool()
    for pool_index = 1, POOL_CAPACITY do
        local tag = jass.CreateTextTag()
        if tag == nil then
            return false
        end

        jass.SetTextTagPermanent(tag, true)
        jass.SetTextTagVisibility(tag, false)
        jass.SetTextTagSuspended(tag, true)
        pool[pool_index] = {
            tag = tag,
            fadeAt = 0.0,
            expiresAt = 0.0,
            active = false,
            red = COLOR_RED,
            green = COLOR_GREEN,
            blue = COLOR_BLUE,
        }
    end
    return true
end

local function is_enemy_target(source, target)
    if target == nil or type(jass.IsUnitEnemy) ~= "function" or type(jass.GetOwningPlayer) ~= "function" then
        return false
    end

    return jass.IsUnitEnemy(target, jass.GetOwningPlayer(source))
end

local function show_text(text, x, y, red, green, blue, height_offset)
    local entry = pool[next_pool_index]
    next_pool_index = next_pool_index % POOL_CAPACITY + 1
    display_sequence = display_sequence + 1

    local offset_index = (display_sequence - 1) % #HORIZONTAL_OFFSETS + 1
    local offset_x = HORIZONTAL_OFFSETS[offset_index]

    jass.SetTextTagText(entry.tag, text, TEXT_HEIGHT)
    jass.SetTextTagPos(entry.tag, x + offset_x, y, height_offset)
    jass.SetTextTagColor(entry.tag, red, green, blue, COLOR_ALPHA)
    jass.SetTextTagVelocity(entry.tag, 0.0, TEXT_VELOCITY_Y)
    jass.SetTextTagAge(entry.tag, 0.0)
    jass.SetTextTagSuspended(entry.tag, false)
    jass.SetTextTagVisibility(entry.tag, true)
    entry.red = red
    entry.green = green
    entry.blue = blue
    entry.fadeAt = elapsed_seconds + FADE_START_SECONDS
    entry.expiresAt = elapsed_seconds + DISPLAY_DURATION_SECONDS
    entry.active = true
end

local function show_damage(target, damage, is_basic_attack)
    local red, green, blue = COLOR_RED, COLOR_GREEN, COLOR_BLUE
    if not is_basic_attack then
        red, green, blue = SKILL_COLOR_RED, SKILL_COLOR_GREEN, SKILL_COLOR_BLUE
    end
    show_text(
        tostring(math.floor(damage + 0.5)),
        jass.GetUnitX(target),
        jass.GetUnitY(target),
        red,
        green,
        blue,
        TEXT_HEIGHT_OFFSET
    )
end

local function show_healing(hero, amount)
    amount = math.floor(tonumber(amount) or 0)
    if hero == nil or amount <= 0 then return end
    show_text(
        "+" .. tostring(amount),
        jass.GetUnitX(hero),
        jass.GetUnitY(hero),
        HEAL_COLOR_RED,
        HEAL_COLOR_GREEN,
        HEAL_COLOR_BLUE,
        TEXT_HEIGHT_OFFSET
    )
end

--- 轮询英雄当前生命值，统一捕获药水、吸血、持续恢复以及其他原生/脚本恢复。
--- 只有当前生命实际增加时才显示；初始化和掉血不会产生恢复飘字。
local function sample_hero_recovery()
    if type(jass.GetUnitState) ~= "function" or jass.UNIT_STATE_LIFE == nil then
        return
    end

    for hero_id, hero in pairs(tracked_heroes) do
        local current = math.max(0.0, tonumber(jass.GetUnitState(hero, jass.UNIT_STATE_LIFE)) or 0.0)
        local previous = last_hero_life[hero_id]
        if previous ~= nil then
            local delta = current - previous
            if delta > 0.0001 and current > 0.405 then
                local total = delta + (pending_heal_fraction[hero_id] or 0.0)
                local amount = math.floor(total + 0.0001)
                pending_heal_fraction[hero_id] = total - amount
                if amount > 0 then
                    show_healing(hero, amount)
                end
            elseif delta < -0.0001 then
                pending_heal_fraction[hero_id] = 0.0
            end
        end
        last_hero_life[hero_id] = current
    end
end

local function update_pool()
    elapsed_seconds = elapsed_seconds + UPDATE_INTERVAL_SECONDS
    sample_hero_recovery()
    for _, entry in ipairs(pool) do
        if entry.active then
            if elapsed_seconds >= entry.expiresAt then
                hide_entry(entry)
            elseif elapsed_seconds >= entry.fadeAt then
                local fade_progress = (elapsed_seconds - entry.fadeAt) / (entry.expiresAt - entry.fadeAt)
                local alpha = math.max(0, math.floor(COLOR_ALPHA * (1.0 - fade_progress)))
                jass.SetTextTagColor(entry.tag, entry.red, entry.green, entry.blue, alpha)
            end
        end
    end
end

local function on_damage_report(report)
    if type(report) ~= "table" then return end
    local source = report.source
    if source == nil then
        return
    end

    local source_id = jass.GetHandleId(source)
    if not hero_sources[source_id] then
        return
    end

    local target = report.target
    local damage = tonumber(report.amount) or 0
    if target == nil or damage == nil or damage <= 0.0 or not is_enemy_target(source, target) then
        return
    end

    show_damage(target, damage, report.isBasicAttack == true)
    if not first_damage_logged then
        first_damage_logged = true
        print("伤害飘字已捕获首个英雄伤害事件")
    end
end

--- 为新生成的敌方单位注册受伤事件。
--- Warcraft III 1.27 仅支持指定单位的 EVENT_UNIT_DAMAGED，不能注册全局玩家受伤事件。
---@param target unit 敌方单位句柄
---@return boolean registered 是否成功注册或已注册
function module.register_target(target)
    return damage_service.register_target(target)
end

--- 在指定世界坐标显示金币获得飘字。
--- 坐标由金币结算房主同步，确保多人客户端显示在同一只怪物位置。
---@param x number 世界坐标 X
---@param y number 世界坐标 Y
---@param amount integer 获得金币数量
---@return boolean shown 是否成功显示
function module.show_gold(x, y, amount)
    if not started or type(x) ~= "number" or type(y) ~= "number" then
        return false
    end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 or pool[next_pool_index] == nil then
        return false
    end
    show_text(
        "+" .. tostring(amount),
        x,
        y,
        GOLD_COLOR_RED,
        GOLD_COLOR_GREEN,
        GOLD_COLOR_BLUE,
        TEXT_HEIGHT_OFFSET + 25.0
    )
    return true
end

--- 启动 PVE 伤害飘字系统。
--- 所有客户端以相同顺序创建并复用 texttag，不使用本地玩家分支。
---@param hero_results HeroSelectionResult[] 英雄创建结果
---@return boolean started_now 本次是否成功启动
function module.start(hero_results)
    if started then
        return false
    end
    if not has_required_api() then
        if not warned_unavailable then
            warned_unavailable = true
            print("伤害飘字未启动：当前运行时缺少 texttag 或单位受伤事件接口")
        end
        return false
    end

    local hero_count = 0
    for _, result in ipairs(hero_results or {}) do
        if result.unit ~= nil then
            local hero_id = jass.GetHandleId(result.unit)
            hero_sources[hero_id] = true
            tracked_heroes[hero_id] = result.unit
            if type(jass.GetUnitState) == "function" and jass.UNIT_STATE_LIFE ~= nil then
                last_hero_life[hero_id] = math.max(0.0,
                    tonumber(jass.GetUnitState(result.unit, jass.UNIT_STATE_LIFE)) or 0.0)
            end
            hero_count = hero_count + 1
        end
    end
    if hero_count == 0 then
        return false
    end
    if not create_pool() or not damage_service.start(hero_results) then
        print("伤害飘字未启动：对象池或受伤事件创建失败")
        return false
    end
    damage_service.subscribe(on_damage_report)

    update_timer = jass.CreateTimer()
    if update_timer == nil then
        print("伤害飘字未启动：对象池计时器创建失败")
        return false
    end
    jass.TimerStart(update_timer, UPDATE_INTERVAL_SECONDS, true, update_pool)
    started = true
    print(string.format("伤害飘字已启动：英雄=%d，对象池=%d", hero_count, POOL_CAPACITY))
    return true
end

return module
