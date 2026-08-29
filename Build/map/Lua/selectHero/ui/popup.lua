--- 随机选将 DzFrame 本地界面层。
--- 使用 Warcraft III 内置模板动态创建控件，并将本地点击转交给选将同步业务层。
local frame = require "platform.frame"
local ability_catalog = require "selectHero.data.ability_catalog"
local assets = require "selectHero.ui.assets"

local module = {}

local CARD_COUNT = 3
local SKILL_COUNT = 4
local BACKDROP_TEMPLATE = "EscMenuControlBackdropTemplate"
local TEXT_TEMPLATE = "EscMenuLabelTextTemplate"

local next_frame_id = 0
local current_popup = nil
local last_error = ""

---@class HeroSelectPopupOptions
---@field sessionId integer 当前选将会话编号
---@field candidates HeroDefinition[] 当前展示的三名候选英雄
---@field remainingSeconds integer 当前倒计时秒数
---@field refreshRemaining integer 当前玩家剩余刷新次数
---@field onHeroSelected fun(rawcode: string) 点击英雄卡牌时调用
---@field onSkillSelected fun(rawcode: string) 点击技能图标时调用
---@field onRefresh fun() 点击刷新时调用
---@field onConfirm fun() 点击确认时调用

---@class HeroSelectPopup
---@field root frame 根节点
---@field timerText frame 倒计时文本
---@field refreshText frame 刷新按钮文本
---@field refreshButton frame 刷新按钮点击节点
---@field confirmText frame 确认按钮文本
---@field confirmButton frame 确认按钮点击节点
---@field detailText frame 技能详情文本
---@field cards table<string, table> 英雄 Rawcode 对应的卡牌节点
---@field callbacks function[] 保持 UI 回调引用，避免被 Lua 回收

local function create_frame(frame_type, suffix, parent, template)
    next_frame_id = next_frame_id + 1
    return frame.create(
        frame_type,
        "JiuDouHeroSelect" .. suffix .. next_frame_id,
        parent,
        template,
        next_frame_id
    )
end

local function create_backdrop(parent, suffix, template, width, height, offset_x, offset_y, texture)
    local backdrop = create_frame("BACKDROP", suffix, parent, template)
    frame.set_size(backdrop, width, height)
    frame.set_point(backdrop, frame.POINT_CENTER, parent, frame.POINT_CENTER, offset_x, offset_y)
    if texture ~= nil then
        frame.set_texture(backdrop, texture, 0)
    end
    return backdrop
end

local function create_image(parent, suffix, texture, width, height, offset_x, offset_y)
    local image = create_backdrop(
        parent,
        suffix,
        BACKDROP_TEMPLATE,
        width,
        height,
        offset_x,
        offset_y,
        texture
    )
    return image
end

local function create_text(parent, suffix, width, height, offset_x, offset_y, value)
    local text = create_frame("TEXT", suffix, parent, TEXT_TEMPLATE)
    frame.set_size(text, width, height)
    frame.set_point(text, frame.POINT_CENTER, parent, frame.POINT_CENTER, offset_x, offset_y)
    frame.set_text(text, value)
    return text
end

local function create_click_target(parent, suffix, width, height, offset_x, offset_y, callback, popup)
    local button = create_frame("BUTTON", suffix, parent, "ScriptDialogButton")
    frame.set_size(button, width, height)
    frame.set_point(button, frame.POINT_CENTER, parent, frame.POINT_CENTER, offset_x, offset_y)
    frame.set_alpha(button, 1)
    frame.on_click(button, callback)
    table.insert(popup.callbacks, callback)
    return button
end

local function format_stat(name, value, growth)
    return string.format("%s  %d  +%d/级", name, value, growth)
end

local function format_ability_detail(ability)
    return string.format(
        "%s|n%s|n伤害：%s    范围：%s    冷却：%s",
        ability.name,
        ability.description,
        ability.damage,
        ability.range,
        ability.cooldown
    )
end

local function set_card_selected(rawcode)
    if current_popup == nil then
        return
    end

    for card_rawcode, card in pairs(current_popup.cards) do
        frame.set_visible(card.selected, card_rawcode == rawcode)
    end
end

local function create_hero_card(popup, hero, index, options)
    local card_offset_x = -0.215 + (index - 1) * 0.215
    local card_offset_y = 0.012
    create_backdrop(
        popup.root,
        "CardNormal" .. hero.rawcode,
        BACKDROP_TEMPLATE,
        0.196,
        0.325,
        card_offset_x,
        card_offset_y,
        assets.PATHS.cardNormal
    )
    local selected = create_backdrop(
        popup.root,
        "CardSelected" .. hero.rawcode,
        BACKDROP_TEMPLATE,
        0.196,
        0.325,
        card_offset_x,
        card_offset_y,
        assets.PATHS.cardSelected
    )
    frame.set_visible(selected, false)
    create_image(popup.root, "Portrait" .. hero.rawcode, hero.portrait, 0.165, 0.145, card_offset_x, card_offset_y + 0.058)
    create_text(popup.root, "Name" .. hero.rawcode, 0.165, 0.026, card_offset_x, card_offset_y + 0.145, hero.name)
    create_text(
        popup.root,
        "Strength" .. hero.rawcode,
        0.17,
        0.020,
        card_offset_x,
        card_offset_y - 0.062,
        format_stat("力量", hero.strength, hero.strengthGrowth)
    )
    create_text(
        popup.root,
        "Agility" .. hero.rawcode,
        0.17,
        0.020,
        card_offset_x,
        card_offset_y - 0.085,
        format_stat("敏捷", hero.agility, hero.agilityGrowth)
    )
    create_text(
        popup.root,
        "Intelligence" .. hero.rawcode,
        0.17,
        0.020,
        card_offset_x,
        card_offset_y - 0.108,
        format_stat("智力", hero.intelligence, hero.intelligenceGrowth)
    )

    create_click_target(
        popup.root,
        "CardButton" .. hero.rawcode,
        0.190,
        0.315,
        card_offset_x,
        card_offset_y,
        function()
            options.onHeroSelected(hero.rawcode)
        end,
        popup
    )

    for ability_index, ability_rawcode in ipairs(hero.abilities) do
        local ability_offset_x = card_offset_x - 0.060 + (ability_index - 1) * 0.040
        local ability = ability_catalog.get(ability_rawcode)
        create_backdrop(
            popup.root,
            "SkillSlot" .. hero.rawcode .. ability_rawcode,
            BACKDROP_TEMPLATE,
            0.034,
            0.034,
            ability_offset_x,
            card_offset_y - 0.019,
            assets.PATHS.skillSlot
        )
        if ability ~= nil then
            create_image(
                popup.root,
                "SkillIcon" .. hero.rawcode .. ability_rawcode,
                ability.icon,
                0.026,
                0.026,
                ability_offset_x,
                card_offset_y - 0.019
            )
        end
        create_click_target(
            popup.root,
            "SkillButton" .. hero.rawcode .. ability_rawcode,
            0.034,
            0.034,
            ability_offset_x,
            card_offset_y - 0.019,
            function()
                options.onSkillSelected(ability_rawcode)
            end,
            popup
        )
    end

    popup.cards[hero.rawcode] = {
        selected = selected,
    }
end

--- 关闭并销毁当前本地选将弹窗。
--- 每次创建都使用唯一 Tag，避免同名控件导致退出崩溃。
---@return nil
function module.hide()
    if current_popup == nil then
        return
    end

    frame.destroy(current_popup.root)
    current_popup = nil
end

--- 创建本地玩家的 DzFrame 选将弹窗。
---@param options HeroSelectPopupOptions 本地界面数据与回调
---@return boolean shown 是否成功创建
function module.show(options)
    module.hide()
    last_error = ""
    if type(options) ~= "table" or #options.candidates ~= CARD_COUNT then
        last_error = "选将界面参数不完整"
        return false
    end
    if not frame.is_available() then
        last_error = "缺少 DzFrame 接口：" .. table.concat(frame.get_missing_api_names(), ", ")
        return false
    end
    local parent = frame.get_game_ui()
    if parent == nil then
        last_error = "无法获取游戏主界面"
        return false
    end

    local root = create_backdrop(
        parent,
        "Root",
        BACKDROP_TEMPLATE,
        0.690,
        0.530,
        0.0,
        0.0,
        assets.PATHS.panel
    )
    if root == nil or root == 0 then
        last_error = "DzFrame 面板创建失败"
        return false
    end

    local popup = {
        root = root,
        cards = {},
        callbacks = {},
    }
    current_popup = popup

    create_text(root, "Title", 0.320, 0.040, 0.0, 0.210, "随机英雄选择")
    create_text(root, "Subtitle", 0.420, 0.026, 0.0, 0.174, "从随机的 3 位英雄中选择 1 位")
    create_backdrop(root, "TimerBackground", BACKDROP_TEMPLATE, 0.100, 0.070, 0.270, 0.208, assets.PATHS.timer)
    popup.timerText = create_text(root, "TimerText", 0.080, 0.030, 0.270, 0.208, "20 秒")

    for hero_index, hero in ipairs(options.candidates) do
        create_hero_card(popup, hero, hero_index, options)
    end

    create_backdrop(root, "DetailBackground", BACKDROP_TEMPLATE, 0.590, 0.085, 0.0, -0.170, assets.PATHS.detail)
    popup.detailText = create_text(root, "DetailText", 0.560, 0.080, 0.0, -0.170, "点击技能图标查看伤害、范围、冷却和说明。")

    create_backdrop(root, "RefreshBackground", BACKDROP_TEMPLATE, 0.170, 0.055, -0.125, -0.235, assets.PATHS.refresh)
    popup.refreshText = create_text(root, "RefreshText", 0.145, 0.030, -0.125, -0.235, "刷新（0）")
    popup.refreshButton = create_click_target(root, "RefreshButton", 0.170, 0.055, -0.125, -0.235, options.onRefresh, popup)

    create_backdrop(root, "ConfirmBackground", BACKDROP_TEMPLATE, 0.170, 0.055, 0.125, -0.235, assets.PATHS.confirm)
    popup.confirmText = create_text(root, "ConfirmText", 0.145, 0.030, 0.125, -0.235, "确认选择")
    popup.confirmButton = create_click_target(root, "ConfirmButton", 0.170, 0.055, 0.125, -0.235, options.onConfirm, popup)

    module.set_remaining_seconds(options.remainingSeconds)
    module.set_refresh_remaining(options.refreshRemaining)
    module.set_confirm_enabled(false)
    return true
end

--- 获取最近一次 DzFrame 弹窗创建失败的原因。
---@return string message 失败原因；成功创建后为空字符串
function module.get_last_error()
    return last_error
end

--- 更新倒计时文本。
---@param seconds integer 剩余秒数
---@return nil
function module.set_remaining_seconds(seconds)
    if current_popup == nil then
        return
    end

    frame.set_text(current_popup.timerText, string.format("%d 秒", math.max(seconds, 0)))
end

--- 设置当前预选英雄的卡牌高亮。
---@param rawcode string|nil 预选英雄 Rawcode；为空时取消高亮
---@return nil
function module.set_selected(rawcode)
    set_card_selected(rawcode)
    module.set_confirm_enabled(rawcode ~= nil)
end

--- 显示指定技能的详情信息。
---@param rawcode string 技能 Rawcode
---@return nil
function module.show_ability_detail(rawcode)
    if current_popup == nil then
        return
    end

    local ability = ability_catalog.get(rawcode)
    if ability == nil then
        return
    end

    frame.set_text(current_popup.detailText, format_ability_detail(ability))
end

--- 更新刷新次数及按钮可用状态。
---@param remaining integer 剩余刷新次数
---@return nil
function module.set_refresh_remaining(remaining)
    if current_popup == nil then
        return
    end

    frame.set_text(current_popup.refreshText, string.format("刷新（%d）", math.max(remaining, 0)))
    frame.set_enabled(current_popup.refreshButton, remaining > 0)
end

--- 设置确认按钮是否可点击。
---@param enabled boolean 是否允许确认
---@return nil
function module.set_confirm_enabled(enabled)
    if current_popup == nil then
        return
    end

    frame.set_enabled(current_popup.confirmButton, enabled)
    if enabled then
        frame.set_text(current_popup.confirmText, "确认选择")
    else
        frame.set_text(current_popup.confirmText, "请选择英雄")
    end
end

return module
