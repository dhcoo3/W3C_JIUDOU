--- 英雄选择 UIKit 的静态视图结构。
--- 这里只创建布局、静态皮肤和空的动态控件，不引用任何英雄/技能业务数据。

JiuDouSelectHeroView = {}

local VIEW_KIT = "jiudou_select_hero"
local CARD_COUNT = 3
local SKILL_COUNT = 4
local CARD_WIDTH = 0.190
local CARD_HEIGHT = 0.315
local CARD_STEP_X = 0.210
local CARD_OFFSET_Y = 0.017

local function key(name)
    return VIEW_KIT .. ":" .. name
end

local function place(control, parent, width, height, offset_x, offset_y)
    control:size(width, height)
        :relation(UI_ALIGN_CENTER, parent, UI_ALIGN_CENTER, offset_x, offset_y)
    return control
end

local function backdrop(name, parent, width, height, offset_x, offset_y, texture)
    local control = UIBackdrop(key(name), parent)
    place(control, parent, width, height, offset_x, offset_y)
    if texture ~= nil then
        control:texture(texture)
    end
    return control
end

local function text(name, parent, width, height, offset_x, offset_y)
    return place(
        UIText(key(name), parent),
        parent,
        width,
        height,
        offset_x,
        offset_y
    )
end

local function button(name, parent, width, height, offset_x, offset_y, callback)
    local control = place(
        UIButton(key(name), parent, {
            _highlightFdfName = false,
            _hasBorder = false,
            _hasMark = false,
        }),
        parent,
        width,
        height,
        offset_x,
        offset_y
    )
    control:onEvent(eventKind.uiLeftClick, "jiudou_select_hero", callback)
    return control
end

local function create_attribute_row(parent, card_offset_x, card_offset_y, index)
    local row_offset_y = card_offset_y - 0.072 - (index - 1) * 0.024
    return {
        label = text("card" .. index .. ":attribute" .. index .. ":label", parent, 0.046, 0.018, card_offset_x - 0.051, row_offset_y),
        value = text("card" .. index .. ":attribute" .. index .. ":value", parent, 0.036, 0.018, card_offset_x, row_offset_y),
        growth = text("card" .. index .. ":attribute" .. index .. ":growth", parent, 0.063, 0.018, card_offset_x + 0.054, row_offset_y),
    }
end

local function create_card(root, index, callbacks)
    local card_offset_x = -CARD_STEP_X + (index - 1) * CARD_STEP_X
    local card_offset_y = CARD_OFFSET_Y
    local card_name = "card" .. index
    local card = {
        attributes = {},
        skills = {},
    }

    card.normal = backdrop(
        card_name .. ":normal",
        root,
        CARD_WIDTH,
        CARD_HEIGHT,
        card_offset_x,
        card_offset_y,
        "card-normal-v2"
    )
    card.selected = backdrop(
        card_name .. ":selected",
        root,
        CARD_WIDTH,
        CARD_HEIGHT,
        card_offset_x,
        card_offset_y,
        "card-selected-v3"
    ):show(false)
    card.portrait = backdrop(
        card_name .. ":portrait",
        root,
        0.154,
        0.128,
        card_offset_x,
        card_offset_y + 0.055
    )
    card.name = text(
        card_name .. ":name",
        root,
        0.164,
        0.024,
        card_offset_x,
        card_offset_y + 0.140
    )

    for attribute_index = 1, 3 do
        card.attributes[attribute_index] = create_attribute_row(root, card_offset_x, card_offset_y, attribute_index)
    end

    card.cardButton = button(
        card_name .. ":button",
        root,
        CARD_WIDTH - 0.006,
        CARD_HEIGHT - 0.006,
        card_offset_x,
        card_offset_y,
        function()
            if type(callbacks.onHeroSelected) == "function" then
                callbacks.onHeroSelected(index)
            end
        end
    )

    for skill_index = 1, SKILL_COUNT do
        local skill_offset_x = card_offset_x - 0.056 + (skill_index - 1) * 0.037
        local skill_name = card_name .. ":skill" .. skill_index
        local skill = {
            icon = backdrop(
                skill_name .. ":icon",
                root,
                0.028,
                0.028,
                skill_offset_x,
                card_offset_y - 0.022
            ),
            name = text(
                skill_name .. ":name",
                root,
                0.034,
                0.014,
                skill_offset_x,
                card_offset_y - 0.050
            ),
        }
        skill.button = button(
            skill_name .. ":button",
            root,
            0.034,
            0.034,
            skill_offset_x,
            card_offset_y - 0.022,
            function()
                if type(callbacks.onSkillSelected) == "function" then
                    callbacks.onSkillSelected(index, skill_index)
                end
            end
        )
        card.skills[skill_index] = skill
    end

    return card
end

--- 创建完整的英雄选择视图。
---@param callbacks table 本地点击回调
---@return table view
function JiuDouSelectHeroView.create(callbacks)
    callbacks = type(callbacks) == "table" and callbacks or {}
    local root = backdrop("root", UIGame, 0.47740, 0.25015, 0, 0, "panel-v4")
    local view = {
        root = root,
        cards = {},
        callbacks = callbacks,
        title = text("title", root, 0.340, 0.042, 0, 0.215),
        subtitle = text("subtitle", root, 0.440, 0.024, 0, 0.180),
        timerBackground = backdrop("timer:background", root, 0.092, 0.067, 0.300, 0.212, "timer-v2"),
        timerText = text("timer:text", root, 0.076, 0.028, 0.300, 0.212),
        detailBackground = backdrop("detail:background", root, 0.620, 0.060, 0, -0.175, "skill-detail-v2"),
        detailText = text("detail:text", root, 0.570, 0.054, 0, -0.175),
        refreshBackground = backdrop("refresh:background", root, 0.170, 0.052, -0.125, -0.240, "button-refresh"),
        refreshText = text("refresh:text", root, 0.145, 0.028, -0.125, -0.240),
        confirmBackground = backdrop("confirm:background", root, 0.170, 0.052, 0.125, -0.240, "button-confirm"),
        confirmText = text("confirm:text", root, 0.145, 0.028, 0.125, -0.240),
    }

    for index = 1, CARD_COUNT do
        view.cards[index] = create_card(root, index, callbacks)
    end

    view.refreshButton = button(
        "refresh:button",
        root,
        0.170,
        0.052,
        -0.125,
        -0.240,
        function()
            if type(callbacks.onRefresh) == "function" then
                callbacks.onRefresh()
            end
        end
    )
    view.confirmButton = button(
        "confirm:button",
        root,
        0.170,
        0.052,
        0.125,
        -0.240,
        function()
            if type(callbacks.onConfirm) == "function" then
                callbacks.onConfirm()
            end
        end
    )

    return view
end

--- 销毁完整的英雄选择视图。
---@param view table
function JiuDouSelectHeroView.destroy(view)
    if type(view) == "table" and view.root ~= nil then
        class.destroy(view.root)
    end
end