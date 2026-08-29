--- Mode selection and staged PVE startup.
local jass = require "jass.common"
local config = require "runMode.config"
local dialog = require "runMode.dialog"
local bottom_hud = require "hud.bottom"
local sync = require "platform.sync"
local select_hero = require "selectHero.main"
local monster = require "monster.main"
local equipment = require "equipment.main"
local rogue = require "rogue.main"
local gold = require "gold.main"
local experience = require "experience.main"
local mystery_shop = require "mysteryShop.main"
local damage_numbers = require "combat.damage_numbers"
local damage_service = require "combat.damage"
local hero_stats = require "hero.stats"
local attribute_ui = require "hero.ui.attributes"
local attribute_tooltip = require "hero.ui.attribute_tooltip"

local M = {}
local SYNC_PREFIX = "JiuDouMode"

local started = false
local startup_scheduled = false
local sync_available = false
local sync_trigger = nil
local selection_applied = false
local pve_startup_timer = nil
local pve_startup_tasks = nil
local pve_startup_index = 1

local function show_local_status(message)
    print(message)
    if type(jass.DisplayTimedTextToPlayer) == "function"
        and type(jass.GetLocalPlayer) == "function" then
        jass.DisplayTimedTextToPlayer(jass.GetLocalPlayer(), 0, 0, 3.0, message)
    end
end

local function finish_pve_startup()
    local elapsed = 0
    if pve_startup_timer ~= nil and type(jass.TimerGetElapsed) == "function" then
        elapsed = math.max(0, tonumber(jass.TimerGetElapsed(pve_startup_timer)) or 0)
    end
    if pve_startup_timer ~= nil then
        jass.PauseTimer(pve_startup_timer)
        jass.DestroyTimer(pve_startup_timer)
        pve_startup_timer = nil
    end
    print(string.format("PVE 分帧初始化完成：步骤=%d，耗时=%.2f 秒", #(pve_startup_tasks or {}), elapsed))
    pve_startup_tasks = nil
    pve_startup_index = 1
    show_local_status("游戏准备完成")
end

local function start_pve_staged(selection, hero_results, monster_seed)
    hero_results = hero_results or {}
    local tasks = {}
    for _, result in ipairs(hero_results) do
        table.insert(tasks, function()
            if not hero_stats.register_hero(
                result.unit,
                result.hero and result.hero.primary,
                result.hero and result.hero.rawcode
            ) then
                print("英雄统一属性注册失败：player=" .. tostring(result.playerId))
            end
        end)
    end
    table.insert(tasks, function()
        if not damage_service.start(hero_results) then
            print("统一伤害事件服务未启动：普通攻击加成与伤害统计将不可用")
        end
    end)
    table.insert(tasks, function()
        if not experience.start(selection, hero_results) then
            print("经验系统未能启动或已经启动")
        end
    end)
    table.insert(tasks, function()
        if not attribute_ui.start(hero_results) then
            print("属性面板未启动或当前客户端无本地英雄：" .. attribute_ui.get_last_error())
        end
    end)
    table.insert(tasks, function()
        if not attribute_tooltip.start(hero_results) then
            print("英雄属性 Tooltip 未启动或当前客户端无本地英雄")
        end
    end)
    table.insert(tasks, function()
        if not damage_numbers.start(hero_results) then
            print("伤害飘字未启动或已经启动")
        end
    end)
    table.insert(tasks, function()
        if not gold.start(selection, hero_results) then
            print("金币系统未能启动或已经启动")
        end
    end)
    table.insert(tasks, function()
        if not equipment.start(hero_results, monster_seed) then
            print("装备系统未能启动或已经启动")
        end
    end)
    table.insert(tasks, function()
        if not mystery_shop.start(hero_results) then
            print("神秘商店未能启动或已经启动")
        end
    end)
    table.insert(tasks, function()
        if not rogue.start(hero_results, monster_seed) then
            print("肉鸽系统未能启动或已经启动")
        end
    end)
    -- Spawn monsters last, after all hero-side state and event handlers are ready.
    table.insert(tasks, function()
        if not monster.start(selection, hero_results, monster_seed) then
            print("PVE 刷怪系统未能启动或已经启动")
        end
    end)

    pve_startup_tasks = tasks
    pve_startup_index = 1
    show_local_status("英雄属性初始化中")
    local function step()
        local task = pve_startup_tasks and pve_startup_tasks[pve_startup_index]
        if task == nil then
            finish_pve_startup()
            return
        end
        task()
        pve_startup_index = pve_startup_index + 1
        if pve_startup_tasks[pve_startup_index] == nil then
            finish_pve_startup()
        end
    end

    if type(jass.CreateTimer) == "function" and type(jass.TimerStart) == "function" then
        pve_startup_timer = jass.CreateTimer()
        jass.TimerStart(pve_startup_timer, 0.03, true, step)
    else
        while pve_startup_tasks ~= nil do step() end
    end
end

local function start_game_mode(selection, hero_results, monster_seed)
    if started then return end
    started = true
    print(string.format(
        "游戏模式已确定：category=%s, mode=%s, level=%s",
        selection.category,
        selection.name,
        tostring(selection.level or "无")
    ))

    if selection.category == config.CATEGORY_PVE then
        print(string.format("PVE 英雄选择完成：%d 名玩家已创建英雄", #(hero_results or {})))
        start_pve_staged(selection, hero_results, monster_seed)
        return
    end
    -- PVP initialization is intentionally unchanged until its mode is implemented.
end

local function apply_selection(selection)
    local valid, message = config.validate(selection)
    if not valid then
        print("模式选择无效：" .. tostring(message))
        return
    end
    if selection_applied then return end

    selection_applied = true
    dialog.close()
    if selection.category == config.CATEGORY_PVE then
        show_local_status("属性系统准备中")
        if not rogue.preload(function()
            show_local_status("属性系统准备完成，进入英雄选择")
            if not select_hero.start(selection, start_game_mode) then
                print("PVE 选将流程启动失败")
            end
        end) then
            print("属性系统预热启动失败")
        end
        return
    end
    start_game_mode(selection, nil)
end

local function register_sync()
    if not sync.is_available() then
        print("警告：未找到 1.27 同步扩展，当前仅支持单机模式选择测试")
        return false
    end

    sync_trigger = jass.CreateTrigger()
    jass.TriggerAddAction(sync_trigger, function()
        local selection, message = config.decode(sync.get_sync_data())
        if selection == nil then
            print("收到无效的模式同步数据：" .. tostring(message))
            return
        end
        apply_selection(selection)
    end)
    if not sync.register_sync_data(sync_trigger, SYNC_PREFIX, false) then
        jass.DestroyTrigger(sync_trigger)
        sync_trigger = nil
        print("警告：同步事件注册失败，当前仅支持单机模式选择测试")
        return false
    end
    return true
end

local function on_selection(selection)
    local data, message = config.encode(selection)
    if data == nil then
        print("模式选择编码失败：" .. tostring(message))
        return
    end
    if sync_available then sync.send_sync_data(SYNC_PREFIX, data) end
    apply_selection(selection)
end

function M.start()
    if started or startup_scheduled then return false end
    startup_scheduled = true
    local startup_timer = jass.CreateTimer()
    jass.TimerStart(startup_timer, 0.10, false, function()
        jass.DestroyTimer(startup_timer)
        local ok, message = pcall(function()
            sync_available = register_sync()
            --if not bottom_hud.show() then
            --    print("底部 HUD 启动失败：" .. bottom_hud.get_last_error())
            --end
            dialog.show_root(on_selection)
        end)
        if not ok then print("模式选择启动失败：" .. tostring(message)) end
    end)
    return true
end

return M
