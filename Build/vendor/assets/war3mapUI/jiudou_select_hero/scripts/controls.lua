--- 英雄选择 UIKit 的控件状态和动态内容操作。
--- 所有文本和图片都由调用方通过公开 setter 提供；本文件不保存英雄/技能数据。

JiuDouSelectHeroControls = {}

local TEXT_GOLD = "F3E4BE"
local TEXT_CYAN = "4BE5F5"
local TEXT_MUTED = "B8C2BC"
local TEXT_DISABLED = "7E8982"
local TEXT_WARNING = "F09A45"

local function color_text(color, value)
    return string.format("|cff%s%s|r", color, tostring(value or ""))
end

local function text_value(control, color, value)
    if control ~= nil then
        control:text(color_text(color, value))
    end
end

local function set_enabled(button, text_control, background, enabled, callback)
    if button == nil then
        return
    end
    enabled = enabled == true
    button:onEvent(eventKind.uiLeftClick, "jiudou_select_hero", enabled and callback or nil)
    button:alpha(enabled and 255 or 100)
    text_value(text_control, enabled and TEXT_GOLD or TEXT_DISABLED, text_control._jiudouText or "")
    if background ~= nil then
        background:alpha(enabled and 255 or 100)
    end
end

local function set_dynamic_text(control, value, color)
    if control == nil then
        return
    end
    control._jiudouText = tostring(value or "")
    text_value(control, color, control._jiudouText)
end

--- 设置标题。
function JiuDouSelectHeroControls.set_title(view, value)
    set_dynamic_text(view and view.title, value, TEXT_GOLD)
end

--- 设置副标题。
function JiuDouSelectHeroControls.set_subtitle(view, value)
    set_dynamic_text(view and view.subtitle, value, TEXT_MUTED)
end

--- 设置卡牌名称。
function JiuDouSelectHeroControls.set_card_name(view, slot, value)
    local card = view and view.cards and view.cards[slot]
    set_dynamic_text(card and card.name, value, TEXT_GOLD)
end

--- 设置卡牌属性；attribute 是调用方提供的属性显示名称。
function JiuDouSelectHeroControls.set_card_attribute(view, slot, attribute, value_text, growth_text)
    local card = view and view.cards and view.cards[slot]
    if card == nil or type(attribute) ~= "number" and type(attribute) ~= "string" then
        return
    end
    local row_index = card._attributeIndexByName and card._attributeIndexByName[attribute]
    if row_index == nil then
        row_index = card._nextAttributeIndex or 1
        card._nextAttributeIndex = row_index + 1
        card._attributeIndexByName = card._attributeIndexByName or {}
        card._attributeIndexByName[attribute] = row_index
    end
    local row = card.attributes[row_index]
    if row == nil then
        return
    end
    set_dynamic_text(row.label, attribute, TEXT_MUTED)
    set_dynamic_text(row.value, value_text, TEXT_GOLD)
    set_dynamic_text(row.growth, growth_text, TEXT_CYAN)
end

--- 设置技能名称。
function JiuDouSelectHeroControls.set_skill_name(view, slot, skill_index, value)
    local card = view and view.cards and view.cards[slot]
    local skill = card and card.skills and card.skills[skill_index]
    set_dynamic_text(skill and skill.name, value, TEXT_GOLD)
end

--- 设置技能详情。
function JiuDouSelectHeroControls.set_skill_detail(view, value)
    set_dynamic_text(view and view.detailText, value, TEXT_MUTED)
end

--- 设置倒计时显示文本。
function JiuDouSelectHeroControls.set_remaining_seconds(view, value)
    local text = tostring(value or "")
    local color = TEXT_CYAN
    local number = tonumber(string.match(text, "^%s*(%d+)"))
    if number ~= nil and number <= 5 then
        color = TEXT_WARNING
    end
    set_dynamic_text(view and view.timerText, text, color)
end

--- 设置刷新按钮文本。
function JiuDouSelectHeroControls.set_refresh_text(view, value)
    set_dynamic_text(view and view.refreshText, value, TEXT_GOLD)
end

--- 设置确认按钮文本。
function JiuDouSelectHeroControls.set_confirm_text(view, value)
    set_dynamic_text(view and view.confirmText, value, TEXT_GOLD)
end

--- 设置头像；path 必须由外部先通过 japi.AssetsImage 解析。
function JiuDouSelectHeroControls.set_card_portrait(view, slot, path)
    local card = view and view.cards and view.cards[slot]
    if card ~= nil and type(path) == "string" then
        card.portrait:texture(path)
    end
end

--- 设置技能图标；path 必须由外部先通过 japi.AssetsImage 解析。
function JiuDouSelectHeroControls.set_skill_icon(view, slot, skill_index, path)
    local card = view and view.cards and view.cards[slot]
    local skill = card and card.skills and card.skills[skill_index]
    if skill ~= nil and type(path) == "string" then
        skill.icon:texture(path)
    end
end

--- 设置选中卡牌编号，传 nil 可取消全部高亮。
function JiuDouSelectHeroControls.set_selected(view, slot)
    if view == nil or type(view.cards) ~= "table" then
        return
    end
    for index, card in ipairs(view.cards) do
        card.selected:show(index == slot)
    end
end

--- 设置刷新按钮可用状态。
function JiuDouSelectHeroControls.set_refresh_enabled(view, enabled)
    local callback = view and view.callbacks and view.callbacks.onRefresh
    set_enabled(view and view.refreshButton, view and view.refreshText, view and view.refreshBackground, enabled, callback)
end

--- 设置确认按钮可用状态。
function JiuDouSelectHeroControls.set_confirm_enabled(view, enabled)
    local callback = view and view.callbacks and view.callbacks.onConfirm
    set_enabled(view and view.confirmButton, view and view.confirmText, view and view.confirmBackground, enabled, callback)
end