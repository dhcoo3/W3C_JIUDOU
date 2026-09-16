--- 装备物品栏 Tooltip。
--- 优先监听 DzFrameGetItemBarButton(0..5) 返回的原生物品栏按钮，
--- 再回退到默认 Frame 名称；用本地 DzFrame 覆盖原生固定 Tooltip，显示随机装备实例的实际词条。
local jass = J.Common
local config = JiuDou.config.equipment
local combo = JiuDou.module("gameplay.equipment.combo")
local instance = JiuDou.module("gameplay.equipment.instance")
local frame = JiuDou.module("platform.frame")
local lifecycle = JiuDou.core and JiuDou.core.lifecycle
local timer_service = JiuDou.core and JiuDou.core.timer

local ui = UIKit("jiudou_equipment_tooltip")

local module = {}

local BACKDROP_TEMPLATE = "EscMenuControlBackdropTemplate"
local TEXT_TEMPLATE = "EscMenuLabelTextTemplate"
local NATIVE_TOOLTIP_NAMES = {
    "ItemTip",
    "SimpleItemTip",
    "ItemTipFrame",
}

local hide_timer = nil
local install_timer = nil
local install_attempts = 0
local installed = false
local warned = false
local native_tooltip_hidden = false
local hover_callbacks = {}
local runtime_scope = nil

local function get_local_player_id()
    if type(jass.GetLocalPlayer) ~= "function" then
        return 0
    end
    return jass.GetPlayerId(jass.GetLocalPlayer())
end

local function get_local_hero()
    return instance.get_hero_by_player(get_local_player_id())
end

local function get_local_inventory_carrier()
    return instance.get_active_inventory_carrier(get_local_player_id())
end

local function find_native_tooltip()
    local direct = frame.get_tooltip()
    if direct ~= nil then
        return direct
    end
    for _, name in ipairs(NATIVE_TOOLTIP_NAMES) do
        local found = frame.find_by_name(name, 0)
        if found ~= nil then
            return found
        end
    end
    return nil
end

local function set_native_tooltip_hidden(hidden)
    if native_tooltip_hidden == hidden then
        return
    end
    local native_tooltip = find_native_tooltip()
    if native_tooltip ~= nil then
        frame.set_visible(native_tooltip, not hidden)
    end
    native_tooltip_hidden = hidden
end

local function ensure_frames()
    return true
end

local function stop_hide_timer()
    if hide_timer == nil then
        return
    end
    if timer_service ~= nil then timer_service.cancel(hide_timer, runtime_scope) end
    hide_timer = nil
end

local function count_lines(text)
    local count = 1
    for _ in string.gmatch(text, "\n") do
        count = count + 1
    end
    return count
end

local function hide_current()
    stop_hide_timer()
    ui:hide()
    set_native_tooltip_hidden(false)
end

local function show_text(text, duration)
    if not ensure_frames() then
        return false
    end
    stop_hide_timer()
    local line_count = count_lines(text)
    local height = math.min(0.34, 0.055 + line_count * 0.023)
    ui:set_text(text, height)
    set_native_tooltip_hidden(true)
    if not ui:show() then
        set_native_tooltip_hidden(false)
        return false
    end
    if duration ~= nil and duration > 0 then
        hide_timer = timer_service and timer_service.after(duration, hide_current, runtime_scope) or nil
    end
    return true
end

--- 生成包含实际随机属性和词条的装备详情。
---@param equipment EquipmentInstance 装备实例
---@param hero unit|nil 当前英雄，用于计算套装件数
---@return string description 详情文本
function module.build_description(equipment, hero)
    local lines = {}
    local template = config.templates[equipment.templateId]
    table.insert(lines, "【" .. tostring(template and template.name or equipment.rawcode) .. "】")
    table.insert(lines, string.format("%d级装备", equipment.level))
    table.insert(lines, string.format("攻击力 +%d", equipment.stats.attack))
    table.insert(lines, string.format("最大生命 +%d", equipment.stats.health))
    table.insert(lines, string.format("护甲 +%d", equipment.stats.armor))
    if (equipment.stats.basicAttackBonusPercent or 0) ~= 0 then
        table.insert(lines, string.format("普攻加成 %+d%%", equipment.stats.basicAttackBonusPercent))
    end
    if (equipment.stats.healthAmplificationPercent or 0) ~= 0 then
        table.insert(lines, string.format("生命增幅 %+d%%", equipment.stats.healthAmplificationPercent))
    end

    if equipment.autoSkillId ~= nil then
        local auto = config.autoSkills[equipment.autoSkillId]
        table.insert(lines, "自动·" .. tostring(auto and auto.name or equipment.autoSkillId))
        table.insert(lines, auto and ("  " .. tostring(auto.description)) or "  自动触发")
    end
    for _, passive_id in ipairs(equipment.passiveSkillIds or {}) do
        local passive = config.passives[passive_id]
        table.insert(lines, "被动·" .. tostring(passive and passive.name or passive_id))
        if passive ~= nil then
            table.insert(lines, "  " .. tostring(passive.description))
        end
    end
    if equipment.comboSetId ~= nil then
        local active_count = 0
        if hero ~= nil then
            for _, active in ipairs(combo.get_active_sets(instance.get_equipment_instances(hero))) do
                if active.setId == equipment.comboSetId then
                    active_count = active.count
                    break
                end
            end
        end
        table.insert(lines, string.format("组合·%s（当前：%d/3）", equipment.comboSetId, active_count))
        local piece = config.combos[equipment.comboPieceId]
        if piece ~= nil then
            table.insert(lines, "  2件：" .. tostring(piece.need2Description))
            table.insert(lines, "  3件：" .. tostring(piece.need3Description))
        end
    end
    return table.concat(lines, "\n")
end

local function show_slot(slot)
    local carrier = get_local_inventory_carrier()
    local hero = get_local_hero()
    if carrier == nil or hero == nil then
        hide_current()
        return
    end
    local item_handle = instance.get_item_in_slot(carrier, slot)
    local equipment = item_handle and instance.get_by_item(item_handle) or nil
    if equipment == nil then
        hide_current()
        return
    end
    show_text(module.build_description(equipment, hero), nil)
end

local function install_inventory_hooks()
    if installed then
        return true
    end
    if not frame.is_available() then
        return false
    end
    local found_count = 0
    for slot = 0, 5 do
        local button = frame.get_item_bar_button(slot)
        if button ~= nil then
            local slot_index = slot
            local enter_callback = function()
                show_slot(slot_index)
            end
            local leave_callback = function()
                hide_current()
            end
            local enter_bound = frame.on_mouse_enter(button, enter_callback)
            local leave_bound = frame.on_mouse_leave(button, leave_callback)
            if enter_bound and leave_bound then
                hover_callbacks[slot] = {enter = enter_callback, leave = leave_callback}
                found_count = found_count + 1
            end
        end
    end
    if found_count == 6 then
        installed = true
        print("装备 Tooltip 已接入物品栏悬停事件")
        return true
    end
    if found_count > 0 and not warned then
        warned = true
        print(string.format("装备 Tooltip 只找到 %d/6 个物品栏按钮，等待下一次重试", found_count))
    end
    return false
end

--- 启动物品栏 Tooltip 悬停接入。
---@return boolean started 是否已成功接入
function module.start()
    runtime_scope = lifecycle and lifecycle.acquire("equipment.tooltip", function()
        hide_timer, install_timer, installed = nil, nil, false
        hover_callbacks = {}
        hide_current()
    end) or runtime_scope
    if installed then
        return true
    end
    if install_inventory_hooks() then
        return true
    end
    if install_timer == nil and type(jass.CreateTimer) == "function" then
        install_attempts = 0
        install_timer = timer_service and timer_service.every(1.0, function()
            install_attempts = install_attempts + 1
            if install_inventory_hooks() or install_attempts >= 10 then
                if not installed and install_attempts >= 10 then
                    print("装备 Tooltip 接入失败：未找到原生物品栏按钮，请检查 DzFrameGetItemBarButton 或 InventoryButton_0 至 InventoryButton_5")
                end
                timer_service.cancel(install_timer, runtime_scope)
                install_timer = nil
            end
        end, runtime_scope) or nil
    end
    return false
end

function module.stop()
    return lifecycle ~= nil and lifecycle.release("equipment.tooltip") or false
end

--- 手动隐藏装备 Tooltip。
function module.hide()
    hide_current()
end

JiuDou.publish("gameplay.equipment.tooltip", module)
return module
