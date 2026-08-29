-- JiuDou Bottom HUD preview/reference for Warcraft III BlzFrame.
-- This file is intentionally kept outside Build/map/Lua:
-- the current map runtime targets Warcraft III 1.27 and uses the legacy frame wrapper.
--
-- Preview resource:
--   editor: ./ui-preview/forest_bottom_strip.png
--   game:   ui\main\forest_bottom_strip.blp
--
-- All visual placeholders use CustomFrame.png or InvisButton.png.
-- Replace those paths when final HUD art is ready.

local JIUDOUHUD = rawget(_G, "JIUDOUHUD") or {}
_G.JIUDOUHUD = JIUDOUHUD

JIUDOUHUD.frames = JIUDOUHUD.frames or {}
JIUDOUHUD.callbacks = JIUDOUHUD.callbacks or {}

local PANEL_LEFT = 0.00073
local PANEL_BOTTOM = 0.00052
local PANEL_WIDTH = 0.80024
local PANEL_HEIGHT = 0.16318

local CUSTOM_TEXTURE = "CustomFrame.png"
local BUTTON_TEXTURE = "InvisButton.png"
local BOTTOM_TEXTURE = "ui\\main\\forest_bottom_strip.blp"
local COMMAND_HOTKEYS = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]" }
local UTILITY_HOTKEYS = { "B", "D", "T", "F", "G", "H" }

local function remember(name, frame)
    if frame ~= nil then
        JIUDOUHUD.frames[name] = frame
    end
    return frame
end

local function apply_level(frame, level)
    if frame ~= nil and BlzFrameSetLevel ~= nil then
        BlzFrameSetLevel(frame, level)
    end
end

local function create_frame(kind, name, parent, x, y, width, height, texture, value, level)
    local frame = BlzCreateFrameByType(kind, name, parent, "", 0)
    if frame == nil then
        return nil
    end

    BlzFrameSetSize(frame, width, height)
    BlzFrameSetAbsPoint(frame, FRAMEPOINT_BOTTOMLEFT, x, y)

    if texture ~= nil and texture ~= "" and kind ~= "BUTTON" and kind ~= "TEXT" then
        BlzFrameSetTexture(frame, texture, 0, true)
    end

    if kind == "TEXT" and value ~= nil then
        BlzFrameSetText(frame, value)
    elseif kind == "STATUSBAR" then
        BlzFrameSetMinMaxValue(frame, 0.0, 100.0)
        BlzFrameSetValue(frame, value or 100.0)
    end

    apply_level(frame, level or 0)
    return frame
end

local function add_backdrop(name, parent, x, y, width, height, texture, level)
    return remember(
        name,
        create_frame("BACKDROP", name, parent, x, y, width, height, texture or CUSTOM_TEXTURE, nil, level or 10)
    )
end

local function add_bar(name, parent, x, y, width, height, value, level)
    return remember(
        name,
        create_frame("STATUSBAR", name, parent, x, y, width, height, CUSTOM_TEXTURE, value or 100.0, level or 20)
    )
end

local function add_text(name, parent, x, y, width, height, value, level)
    return remember(
        name,
        create_frame("TEXT", name, parent, x, y, width, height, nil, value or "", level or 20)
    )
end

local function bind_button(frame, group, index)
    local callbacks = JIUDOUHUD.callbacks[group]
    local callback = callbacks and callbacks[index]
    if frame ~= nil and callback ~= nil and BlzFrameSetScriptByCode ~= nil then
        BlzFrameSetScriptByCode(frame, FRAMEEVENT_CONTROL_CLICK, callback, false)
    end
end

local function add_button(name, parent, x, y, width, height, group, index)
    local frame = remember(
        name,
        create_frame("BUTTON", name, parent, x, y, width, height, BUTTON_TEXTURE, nil, 30)
    )
    bind_button(frame, group, index)
    return frame
end

local function set_text(name, value)
    local frame = JIUDOUHUD.frames[name]
    if frame ~= nil then
        BlzFrameSetText(frame, value)
    end
end

local function set_value(name, value)
    local frame = JIUDOUHUD.frames[name]
    if frame ~= nil then
        BlzFrameSetValue(frame, value)
    end
end

function JIUDOUHUD.SetCallbacks(callbacks)
    JIUDOUHUD.callbacks = callbacks or {}
end

function JIUDOUHUD.SetVisible(visible)
    for _, frame in pairs(JIUDOUHUD.frames) do
        BlzFrameSetVisible(frame, visible)
    end
end

function JIUDOUHUD.Destroy()
    if BlzDestroyFrame ~= nil then
        for name, frame in pairs(JIUDOUHUD.frames) do
            BlzDestroyFrame(frame)
            JIUDOUHUD.frames[name] = nil
        end
    else
        JIUDOUHUD.frames = {}
    end
end

function JIUDOUHUD.Refresh()
    set_text("HUDHeroName", "剑七")
    set_text("HUDHeroLevel", "Lv.1")
    set_text("HUDHeroHealthText", "706/706")
    set_text("HUDHeroManaText", "100/100")
    set_text("HUDHeroStrengthValue", "STR 0")
    set_text("HUDHeroAgilityValue", "AGI 0")
    set_text("HUDHeroIntelligenceValue", "INT 0")

    set_value("HUDHeroHealthBar", 100.0)
    set_value("HUDHeroManaBar", 100.0)
    set_value("HUDHeroExperienceBar", 35.0)

    for index = 1, 6 do
        local suffix = string.format("%02d", index)
        set_text("HUDCardCount" .. suffix, "1")
        set_text("HUDInventoryCount" .. suffix, "1")
        set_text("HUDUtilityHotkey" .. suffix, UTILITY_HOTKEYS[index] or "")
        set_text("HUDUtilityCooldown" .. suffix, "0")
    end

    for index = 1, 12 do
        local suffix = string.format("%02d", index)
        set_text("HUDCommandHotkey" .. suffix, COMMAND_HOTKEYS[index] or "")
        set_text("HUDCommandCooldownText" .. suffix, "0")
    end
end

function JIUDOUHUD.Initialize()
    if next(JIUDOUHUD.frames) ~= nil then
        JIUDOUHUD.Destroy()
    end

    local game_ui = BlzGetOriginFrame(ORIGIN_FRAME_GAME_UI, 0)
    if game_ui == nil then
        return false
    end

    -- Creation order is the fallback layer order:
    -- root/background -> panels -> visual content -> buttons -> status overlays.
    local root = add_backdrop(
        "HUDRoot",
        game_ui,
        PANEL_LEFT,
        PANEL_BOTTOM,
        PANEL_WIDTH,
        PANEL_HEIGHT,
        "",
        0
    )

    if root == nil then
        return false
    end

    add_backdrop(
        "HUDBottomBackground",
        root,
        PANEL_LEFT,
        PANEL_BOTTOM,
        PANEL_WIDTH,
        PANEL_HEIGHT,
        BOTTOM_TEXTURE,
        0
    )

    add_button("HUDHelperButton", root, 0.006, 0.139, 0.040, 0.023, "helper", 1)
    add_button("HUDCardPackButton", root, 0.071, 0.139, 0.055, 0.023, "cardPack", 1)

    add_backdrop("HUDMinimapPanel", root, 0.006, 0.008, 0.105, 0.126, CUSTOM_TEXTURE, 10)
    add_backdrop("HUDMinimapFrame", root, 0.009, 0.011, 0.099, 0.120, CUSTOM_TEXTURE, 10)
    add_backdrop("HUDMinimapViewport", root, 0.017, 0.026, 0.083, 0.083, CUSTOM_TEXTURE, 20)
    add_backdrop("HUDMinimapPingLayer", root, 0.017, 0.026, 0.083, 0.083, CUSTOM_TEXTURE, 20)
    add_button("HUDMinimapButton", root, 0.017, 0.026, 0.083, 0.083, "minimap", 1)

    add_backdrop("HUDCardPackPanel", root, 0.117, 0.008, 0.105, 0.126, CUSTOM_TEXTURE, 10)
    for index = 1, 6 do
        local suffix = string.format("%02d", index)
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local x = 0.124 + column * 0.048
        local y = 0.093 - row * 0.038

        add_backdrop("HUDCardSlot" .. suffix, root, x, y, 0.043, 0.032, CUSTOM_TEXTURE, 10)
        add_backdrop("HUDCardIcon" .. suffix, root, x + 0.003, y + 0.003, 0.037, 0.026, CUSTOM_TEXTURE, 20)
        add_text("HUDCardCount" .. suffix, root, x + 0.027, y + 0.003, 0.014, 0.011, "1", 20)
        add_button("HUDCardSlotButton" .. suffix, root, x, y, 0.043, 0.032, "card", index)
    end

    add_backdrop("HUDCommandBar", root, 0.316, 0.116, 0.181, 0.047, CUSTOM_TEXTURE, 10)
    for index = 1, 12 do
        local suffix = string.format("%02d", index)
        local column = (index - 1) % 6
        local row = math.floor((index - 1) / 6)
        local x = 0.320 + column * 0.029
        local y = 0.140 - row * 0.024

        add_backdrop("HUDCommandSlot" .. suffix, root, x, y, 0.026, 0.021, CUSTOM_TEXTURE, 10)
        add_backdrop("HUDCommandIcon" .. suffix, root, x + 0.002, y + 0.002, 0.022, 0.017, CUSTOM_TEXTURE, 20)
        add_backdrop("HUDCommandCooldown" .. suffix, root, x, y, 0.026, 0.021, CUSTOM_TEXTURE, 40)
        add_text("HUDCommandCooldownText" .. suffix, root, x, y + 0.004, 0.026, 0.011, "0", 40)
        add_text("HUDCommandHotkey" .. suffix, root, x + 0.002, y + 0.001, 0.022, 0.009, "", 20)
        add_backdrop("HUDCommandDisabled" .. suffix, root, x, y, 0.026, 0.021, CUSTOM_TEXTURE, 40)
        add_button("HUDCommandButton" .. suffix, root, x, y, 0.026, 0.021, "command", index)
    end

    add_backdrop("HUDHeroPanel", root, 0.226, 0.008, 0.282, 0.126, CUSTOM_TEXTURE, 10)
    add_backdrop("HUDHeroPortraitFrame", root, 0.236, 0.019, 0.062, 0.108, CUSTOM_TEXTURE, 10)
    add_backdrop("HUDHeroPortrait", root, 0.242, 0.025, 0.050, 0.091, CUSTOM_TEXTURE, 20)
    add_text("HUDHeroName", root, 0.306, 0.112, 0.105, 0.016, "剑七", 20)
    add_text("HUDHeroLevel", root, 0.420, 0.112, 0.034, 0.016, "Lv.1", 20)
    add_bar("HUDHeroHealthBar", root, 0.306, 0.094, 0.145, 0.012, 100.0, 20)
    add_text("HUDHeroHealthText", root, 0.306, 0.080, 0.145, 0.012, "706/706", 20)
    add_bar("HUDHeroManaBar", root, 0.306, 0.065, 0.145, 0.010, 100.0, 20)
    add_text("HUDHeroManaText", root, 0.306, 0.052, 0.145, 0.012, "100/100", 20)
    add_bar("HUDHeroExperienceBar", root, 0.306, 0.038, 0.145, 0.008, 35.0, 20)
    add_text("HUDHeroStrengthValue", root, 0.460, 0.094, 0.040, 0.014, "STR 0", 20)
    add_text("HUDHeroAgilityValue", root, 0.460, 0.076, 0.040, 0.014, "AGI 0", 20)
    add_text("HUDHeroIntelligenceValue", root, 0.460, 0.058, 0.040, 0.014, "INT 0", 20)

    add_backdrop("HUDInventoryPanel", root, 0.535, 0.008, 0.115, 0.126, CUSTOM_TEXTURE, 10)
    for index = 1, 6 do
        local suffix = string.format("%02d", index)
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local x = 0.542 + column * 0.055
        local y = 0.093 - row * 0.039

        add_backdrop("HUDInventorySlot" .. suffix, root, x, y, 0.051, 0.033, CUSTOM_TEXTURE, 10)
        add_backdrop("HUDInventoryIcon" .. suffix, root, x + 0.003, y + 0.003, 0.045, 0.027, CUSTOM_TEXTURE, 20)
        add_text("HUDInventoryCount" .. suffix, root, x + 0.033, y + 0.003, 0.016, 0.011, "1", 20)
        add_backdrop("HUDInventoryCooldown" .. suffix, root, x, y, 0.051, 0.033, CUSTOM_TEXTURE, 40)
        add_button("HUDInventoryButton" .. suffix, root, x, y, 0.051, 0.033, "inventory", index)
    end

    add_backdrop("HUDUtilityPanel", root, 0.660, 0.008, 0.135, 0.126, CUSTOM_TEXTURE, 10)
    for index = 1, 6 do
        local suffix = string.format("%02d", index)
        local column = (index - 1) % 3
        local row = math.floor((index - 1) / 3)
        local x = 0.667 + column * 0.042
        local y = 0.093 - row * 0.041

        add_button("HUDUtilityButton" .. suffix, root, x, y, 0.037, 0.034, "utility", index)
        add_backdrop("HUDUtilityIcon" .. suffix, root, x + 0.002, y + 0.003, 0.033, 0.028, CUSTOM_TEXTURE, 20)
        add_text("HUDUtilityHotkey" .. suffix, root, x + 0.002, y + 0.003, 0.033, 0.010, "", 20)
        add_text("HUDUtilityCooldown" .. suffix, root, x + 0.002, y + 0.014, 0.033, 0.010, "0", 20)
    end

    JIUDOUHUD.Refresh()
    JIUDOUHUD.SetVisible(true)
    return true
end

return JIUDOUHUD
