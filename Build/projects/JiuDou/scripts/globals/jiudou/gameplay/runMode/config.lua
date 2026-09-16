--- 模式选择配置层。
--- 负责模式枚举、显示名称和模式结果的序列化校验。
local M = {}

---@alias ModeCategory "PVE"|"PVP"

---@class ModeSelection
---@field category ModeCategory 大类：PVE 或 PVP
---@field modeId integer 具体模式编号
---@field name string 模式中文名称
---@field level integer|nil PVE 等级；PVP 固定为空

M.CATEGORY_PVE = "PVE"
M.CATEGORY_PVP = "PVP"
M.LEVEL_MIN = 1
M.LEVEL_MAX = 10

---@class ModeIdConfig
---@field PVE_NORMAL integer PVE 普通模式编号
---@field PVE_HARD integer PVE 困难模式编号
---@field PVP_MELEE integer PVP 混战模式编号
---@field PVP_2V2 integer PVP 2V2 模式编号
---@field PVP_3V3 integer PVP 3V3 模式编号
---@field PVP_5V5 integer PVP 5V5 模式编号
---@type ModeIdConfig
M.MODE_ID = {
    PVE_NORMAL = 1,
    PVE_HARD = 2,
    PVP_MELEE = 1,
    PVP_2V2 = 2,
    PVP_3V3 = 3,
    PVP_5V5 = 4,
}

local mode_names = {
    [M.CATEGORY_PVE] = {
        [M.MODE_ID.PVE_NORMAL] = "普通模式",
        [M.MODE_ID.PVE_HARD] = "困难模式",
    },
    [M.CATEGORY_PVP] = {
        [M.MODE_ID.PVP_MELEE] = "混战模式",
        [M.MODE_ID.PVP_2V2] = "2V2",
        [M.MODE_ID.PVP_3V3] = "3V3",
        [M.MODE_ID.PVP_5V5] = "5V5",
    },
}

--- 获取模式的中文显示名称。
---@param category ModeCategory 模式大类
---@param mode_id integer 具体模式编号
---@return string|nil name 中文名称，不存在时为空
function M.get_mode_name(category, mode_id)
    local category_modes = mode_names[category]
    if category_modes == nil then
        return nil
    end

    return category_modes[mode_id]
end

--- 校验模式选择是否完整且合法。
---@param selection ModeSelection 模式选择结果
---@return boolean valid 是否合法
---@return string|nil message 非法原因
function M.validate(selection)
    if type(selection) ~= "table" then
        return false, "模式结果不是表结构"
    end

    if M.get_mode_name(selection.category, selection.modeId) == nil then
        return false, "模式类别或模式编号无效"
    end

    if selection.category == M.CATEGORY_PVE then
        if type(selection.level) ~= "number"
            or selection.level < M.LEVEL_MIN
            or selection.level > M.LEVEL_MAX then
            return false, "PVE 等级必须在 1 到 10 之间"
        end
    elseif selection.category == M.CATEGORY_PVP then
        if selection.level ~= nil then
            return false, "PVP 模式不能携带等级"
        end
    else
        return false, "模式类别无效"
    end

    return true, nil
end

--- 将模式结果编码为同步字符串。
--- 编码格式为“类别|模式编号|等级”；PVP 的等级字段固定写为 0。
---@param selection ModeSelection 模式选择结果
---@return string|nil data 可同步的数据
---@return string|nil message 编码失败原因
function M.encode(selection)
    local valid, message = M.validate(selection)
    if not valid then
        return nil, message
    end

    return string.format(
        "%s|%d|%d",
        selection.category,
        selection.modeId,
        selection.level or 0
    ), nil
end

--- 将同步字符串解码为模式结果。
--- 输入格式为“类别|模式编号|等级”；PVP 的等级字段必须为 0。
---@param data string 同步字符串
---@return ModeSelection|nil selection 解码后的模式结果
---@return string|nil message 解码失败原因
function M.decode(data)
    if type(data) ~= "string" then
        return nil, "同步数据不是字符串"
    end

    local category, mode_id_text, level_text = string.match(data, "^([^|]+)|([^|]+)|([^|]+)$")
    local mode_id = tonumber(mode_id_text)
    local level = tonumber(level_text)
    if category == nil or mode_id == nil or level == nil then
        return nil, "同步数据格式错误"
    end

    local selection = {
        category = category,
        modeId = mode_id,
        name = M.get_mode_name(category, mode_id),
        level = level == 0 and nil or level,
    }
    local valid, message = M.validate(selection)
    if not valid then
        return nil, message
    end

    if category == M.CATEGORY_PVP and level ~= 0 then
        return nil, "PVP 同步数据的等级必须为 0"
    end

    return selection, nil
end

JiuDou.publish("gameplay.runMode.config", M)
return M
