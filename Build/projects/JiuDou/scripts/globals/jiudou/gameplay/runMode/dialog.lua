--- 模式选择界面层。
--- 负责房主弹窗、按钮回调和返回导航，不处理同步或玩法初始化。
local jass = J.Common
local config = JiuDou.module("gameplay.runMode.config")

local M = {}
local HOST_PLAYER_ID = 0

local current_dialog = nil
local current_trigger = nil
local button_actions = {}
local selection_handler = nil

local show_root
local show_pve
local show_pve_level
local show_pvp
local on_dialog_clicked

local function is_host(player)
    return jass.GetPlayerId(player) == HOST_PLAYER_ID
end

local function display_dialog(dialog, visible)
    jass.DialogDisplay(jass.Player(HOST_PLAYER_ID), dialog, visible)
end

--- 关闭当前模式选择弹窗并释放关联触发器。
---@return nil
function M.close()
    if current_trigger ~= nil then
        jass.DestroyTrigger(current_trigger)
        current_trigger = nil
    end

    if current_dialog ~= nil then
        display_dialog(current_dialog, false)
        jass.DialogDestroy(current_dialog)
        current_dialog = nil
    end

    button_actions = {}
end

local function add_button(text, action)
    local button = jass.DialogAddButton(current_dialog, text, 0)
    button_actions[button] = action
end

local function bind_dialog_event()
    current_trigger = jass.CreateTrigger()
    jass.TriggerRegisterDialogEvent(current_trigger, current_dialog)
    jass.TriggerAddAction(current_trigger, on_dialog_clicked)
end

local function publish_selection(category, mode_id, level)
    local name = config.get_mode_name(category, mode_id)
    if name == nil or selection_handler == nil then
        return
    end

    M.close()
    selection_handler({
        category = category,
        modeId = mode_id,
        name = name,
        level = level,
    })
end

show_root = function()
    M.close()
    current_dialog = jass.DialogCreate()
    jass.DialogSetMessage(current_dialog, "请选择游戏模式")
    add_button("PVE", show_pve)
    add_button("PVP", show_pvp)
    bind_dialog_event()
    display_dialog(current_dialog, true)
end

show_pve = function()
    M.close()
    current_dialog = jass.DialogCreate()
    jass.DialogSetMessage(current_dialog, "请选择PVE模式")
    add_button("普通模式", function()
        show_pve_level(config.MODE_ID.PVE_NORMAL)
    end)
    add_button("困难模式", function()
        show_pve_level(config.MODE_ID.PVE_HARD)
    end)
    add_button("返回", show_root)
    bind_dialog_event()
    display_dialog(current_dialog, true)
end

show_pve_level = function(mode_id)
    local level = config.LEVEL_MIN
    local mode_name = config.get_mode_name(config.CATEGORY_PVE, mode_id)
    M.close()
    current_dialog = jass.DialogCreate()
    jass.DialogSetMessage(current_dialog, "请选择" .. mode_name .. "等级")

    while level <= config.LEVEL_MAX do
        local selected_level = level
        add_button(tostring(selected_level) .. "级", function()
            publish_selection(config.CATEGORY_PVE, mode_id, selected_level)
        end)
        level = level + 1
    end

    add_button("返回", show_pve)
    bind_dialog_event()
    display_dialog(current_dialog, true)
end

show_pvp = function()
    local pvp_modes = {
        {id = config.MODE_ID.PVP_MELEE, name = "混战模式"},
        {id = config.MODE_ID.PVP_2V2, name = "2V2"},
        {id = config.MODE_ID.PVP_3V3, name = "3V3"},
        {id = config.MODE_ID.PVP_5V5, name = "5V5"},
    }

    M.close()
    current_dialog = jass.DialogCreate()
    jass.DialogSetMessage(current_dialog, "请选择PVP模式")

    for _, pvp_mode in ipairs(pvp_modes) do
        local mode_id = pvp_mode.id
        local mode_name = pvp_mode.name
        add_button(mode_name, function()
            publish_selection(config.CATEGORY_PVP, mode_id, nil)
        end)
    end

    add_button("返回", show_root)
    bind_dialog_event()
    display_dialog(current_dialog, true)
end

on_dialog_clicked = function()
    if not is_host(jass.GetTriggerPlayer()) then
        return
    end

    local action = button_actions[jass.GetClickedButton()]
    if action ~= nil then
        action()
    end
end

--- 向房主显示模式选择根菜单。
---@param on_selection fun(selection: ModeSelection) 最终选择回调
function M.show_root(on_selection)
    selection_handler = on_selection
    show_root()
end

JiuDou.publish("gameplay.runMode.dialog", M)
return M
