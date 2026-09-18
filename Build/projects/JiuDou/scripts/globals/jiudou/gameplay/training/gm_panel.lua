--- 训练模式 GM 面板。外层与交互由 xlik UI 组件构建，输入框使用 Dz EDITBOX。
local module = {}

local panel = nil
local open_button = nil
local status_text = nil
local input_frame = nil
local submit = nil

local function set_input_visible(visible)
    if input_frame ~= nil then
        japi.DZ_FrameShow(input_frame, visible)
    end
end

local function input_text()
    if input_frame == nil then return "" end
    return tostring(japi.DZ_FrameGetText(input_frame) or "")
end

function module.set_status(text)
    if status_text ~= nil then
        status_text:text(tostring(text or ""))
    end
end

function module.show(visible)
    if panel == nil then return end
    panel:show(visible)
    set_input_visible(visible)
end

function module.start(on_submit)
    submit = on_submit
    if panel ~= nil then
        open_button:show(true)
        return true
    end

    panel = UIPlate("jiudou_training_gm:panel")
    panel:size(0.46, 0.28):relation(UI_ALIGN_CENTER, UIGame, UI_ALIGN_CENTER, 0, 0):esc(true):closer(true, 0.018)
    panel:show(false)

    local title = UIText("jiudou_training_gm:title", panel)
    title:size(0.40, 0.026):relation(UI_ALIGN_TOP, panel, UI_ALIGN_TOP, 0, -0.020):text("训练模式 GM 控制台"):fontSize(14)

    local hint = UIText("jiudou_training_gm:hint", panel)
    hint:size(0.40, 0.020):relation(UI_ALIGN_TOP, panel, UI_ALIGN_TOP, 0, -0.052):text("输入 1 - 9,999,999 的整数"):fontSize(10)

    input_frame = japi.DZ_CreateFrameByTagName("EDITBOX", "JiuDouTrainingGMInput", panel:handle(), "EscMenuEditBoxTemplate", 0)
    japi.DZ_FrameSetSize(input_frame, 0.38, 0.028)
    japi.DZ_FrameClearAllPoints(input_frame)
    japi.DZ_FrameSetPoint(input_frame, UI_ALIGN_TOP, panel:handle(), UI_ALIGN_TOP, 0, -0.078)
    japi.DZ_FrameSetTextSizeLimit(input_frame, 7)
    japi.DZ_FrameSetText(input_frame, "1000")
    set_input_visible(false)

    status_text = UIText("jiudou_training_gm:status", panel)
    status_text:size(0.40, 0.020):relation(UI_ALIGN_TOP, panel, UI_ALIGN_TOP, 0, -0.118):text("准备完成"):fontSize(10)

    local function command_button(key, text, x, action)
        local button = UIButton("jiudou_training_gm:" .. key, panel)
        button:size(0.105, 0.040):relation(UI_ALIGN_TOP, panel, UI_ALIGN_TOP, x, -0.155):text(text):fontSize(9)
        button:onEvent(eventKind.uiLeftClick, function()
            if type(submit) == "function" then
                submit(action, input_text())
            end
        end)
        return button
    end

    command_button("experience", "添加经验", -0.168, "experience")
    command_button("attack", "增加攻击力", -0.056, "attack")
    command_button("rogue", "获得肉鸽", 0.056, "rogue")
    command_button("full_restore", "回满生命/MP", 0.168, "restore")

    panel:onEvent(eventKind.uiHide, "gm_input_hide", function()
        set_input_visible(false)
    end)
    panel:onEvent(eventKind.uiShow, "gm_input_show", function()
        set_input_visible(true)
    end)

    open_button = UIButton("jiudou_training_gm:open", UIGame)
    open_button:size(0.050, 0.026):relation(UI_ALIGN_LEFT_BOTTOM, UIGame, UI_ALIGN_LEFT_BOTTOM, 0.112, 0.218):text("GM"):fontSize(12)
    open_button:onEvent(eventKind.uiLeftClick, function()
        module.show(not panel:isShow())
    end)
    return true
end

function module.stop()
    -- EDITBOX 是原生子 Frame，先释放它，避免父面板销毁后留下悬挂句柄。
    if input_frame ~= nil then
        japi.DZ_DestroyFrame(input_frame)
        input_frame = nil
    end
    if open_button ~= nil then
        class.destroy(open_button)
        open_button = nil
    end
    if panel ~= nil then
        class.destroy(panel)
        panel = nil
    end
    status_text = nil
    submit = nil
end

JiuDou.publish("gameplay.training.gm_panel", module)
return module