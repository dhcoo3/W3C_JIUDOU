--- 英雄选择 UIKit 套件入口。
--- 套件只负责界面结构、静态皮肤和控件更新；所有游戏数据由外部业务传入。

local ui = UIKit("jiudou_select_hero")
local view_factory = JiuDouSelectHeroView
local controls = JiuDouSelectHeroControls

local function current_view(self)
    return rawget(self, "_jiudouSelectHeroView")
end

--- 创建并显示空的英雄选择界面。
---@param options table|nil 只包含本地点击回调
---@return boolean shown
function ui:show(options)
    self:hide()
    options = type(options) == "table" and options or {}
    local view = view_factory.create(options)
    if view == nil or view.root == nil then
        self._jiudouSelectHeroError = "英雄选择 UIKit 创建失败"
        return false
    end
    self._jiudouSelectHeroError = ""
    self._jiudouSelectHeroView = view
    view.root:show(true)
    return true
end

--- 隐藏并销毁英雄选择界面。
function ui:hide()
    local view = current_view(self)
    if view == nil then
        return
    end

    -- UI 对象由同步环境创建和销毁；同步消息的本地 promise 回调可能处于异步环境。
    -- 异步环境只能隐藏，后续在同步环境 show/hide 时再由 class.destroy 回收。
    local can_destroy = type(sync) == "table" and type(sync.is) == "function" and sync.is()
    if can_destroy then
        view_factory.destroy(view)
        self._jiudouSelectHeroView = nil
    elseif view.root ~= nil then
        view.root:show(false)
    end
end

--- 获取最近一次创建错误。
---@return string
function ui:get_last_error()
    return rawget(self, "_jiudouSelectHeroError") or ""
end

local function apply(self, name, ...)
    local view = current_view(self)
    if view ~= nil then
        controls[name](view, ...)
    end
end

function ui:set_title(value)
    apply(self, "set_title", value)
end

function ui:set_subtitle(value)
    apply(self, "set_subtitle", value)
end

function ui:set_card_name(slot, value)
    apply(self, "set_card_name", slot, value)
end

function ui:set_card_attribute(slot, attribute, value_text, growth_text)
    apply(self, "set_card_attribute", slot, attribute, value_text, growth_text)
end

function ui:set_skill_name(slot, skill_index, value)
    apply(self, "set_skill_name", slot, skill_index, value)
end

function ui:set_skill_detail(value)
    apply(self, "set_skill_detail", value)
end

function ui:set_refresh_text(value)
    apply(self, "set_refresh_text", value)
end

function ui:set_confirm_text(value)
    apply(self, "set_confirm_text", value)
end

function ui:set_card_portrait(slot, path)
    apply(self, "set_card_portrait", slot, path)
end

function ui:set_skill_icon(slot, skill_index, path)
    apply(self, "set_skill_icon", slot, skill_index, path)
end

function ui:set_selected(slot)
    apply(self, "set_selected", slot)
end

function ui:set_remaining_seconds(value)
    apply(self, "set_remaining_seconds", value)
end

function ui:set_refresh_enabled(enabled)
    apply(self, "set_refresh_enabled", enabled)
end

function ui:set_confirm_enabled(enabled)
    apply(self, "set_confirm_enabled", enabled)
end