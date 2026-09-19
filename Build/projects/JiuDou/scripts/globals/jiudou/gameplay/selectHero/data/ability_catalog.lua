--- 英雄技能展示数据层。
--- 负责把自动生成的技能配置转换为选将界面可直接展示的资料。
local abilities = JiuDou.config.abilities
local roguelike = JiuDou.config.roguelike

local module = {}


---@class HeroAbilityView
---@field rawcode string 技能 Rawcode
---@field name string 技能名称
---@field description string 技能文字说明
---@field damage string 伤害或效果说明
---@field range string 技能范围说明
---@field cooldown string 冷却时间说明

--- 仅保存无法从通用对象字段可靠推断的界面语义。
---@class HeroAbilityPresentation
---@field damage string 伤害或玩法效果文案
---@field range string 范围或目标方式文案
---@field cooldown string 冷却或被动文案
---@type table<string, HeroAbilityPresentation>
local presentation_by_rawcode = {
    A0W1 = {range = "325", cooldown = "9 / 8 / 7 秒"},
    A0W2 = {damage = "由 Lua 结算", range = "突进 700；落点 250", cooldown = "16 / 14 / 12 秒"},
    A0W3 = {damage = "无直接伤害", range = "自身", cooldown = "被动"},
    A0W4 = {damage = "召唤伤害由 Lua 结算", range = "自身", cooldown = "被动"},
    A0N1 = {range = "900；飞行扫掠半径 100", cooldown = "12 / 11 / 10 秒"},
    A0N2 = {range = "750；每箭弹射 350", cooldown = "9 / 8 / 7 秒"},
    A0N3 = {damage = "日痕爆发由 Lua 结算", range = "日痕爆发范围 180", cooldown = "被动"},
    A0N4 = {damage = "普通箭与第九箭伤害由 Lua 结算", range = "落点半径 360", cooldown = "70 / 60 / 50 秒"},
    A0B1 = {range = "250", cooldown = "10 / 9 / 8 秒"},
    A0B2 = {damage = "无直接伤害", range = "350", cooldown = "18 / 16 / 14 秒"},
    A0B3 = {damage = "无直接伤害", range = "自身", cooldown = "被动"},
    A0B4 = {damage = "反击伤害由 Lua 结算", range = "自身", cooldown = "被动"},
    A0E1 = {damage = "按主属性结算；自身施放时恢复生命", range = "单体；肉鸽可弹射", cooldown = "8 / 7 / 6 秒"},
    A0E2 = {damage = "冰龙卷每 0.5 秒结算；冰箭由 Lua 结算", range = "区域 300；施法距离 700", cooldown = "14 / 12 / 10 秒"},
    A0E3 = {damage = "满 5 层后强化下一次普攻", range = "自身普攻", cooldown = "被动"},
    A0E4 = {damage = "食尸鬼伤害与献祭治疗由 Lua 结算", range = "区域召唤；再次按 R 献祭", cooldown = "45 / 40 秒；耗魔 120 / 150"},
}

local ATTRIBUTE_LABELS = {strength = "力量", agility = "敏捷", intelligence = "智力"}

local function format_multiplier(value)
    value = math.max(0, math.floor(tonumber(value) or 0))
    local whole, fraction = math.floor(value / 10), value % 10
    return fraction == 0 and tostring(whole) or (tostring(whole) .. "." .. tostring(fraction))
end

local function format_formula(attribute, multipliers, prefix)
    local label = ATTRIBUTE_LABELS[attribute] or "主属性"
    local values = {}
    for level, multiplier in ipairs(multipliers or {}) do
        table.insert(values, tostring(level) .. "级 " .. format_multiplier(multiplier) .. "×" .. label)
    end
    return (prefix or "伤害") .. "：" .. table.concat(values, " / ")
end

local function formula_damage(rawcode)
    for _, by_skill in pairs(roguelike.skillRuntime or {}) do
        local runtime = by_skill[rawcode]
        if runtime ~= nil then
            if runtime.damageAttribute and runtime.damageMultiplierTenth then
                return format_formula(runtime.damageAttribute, runtime.damageMultiplierTenth)
            end
            if runtime.procDamageAttribute and runtime.procDamageMultiplierTenth then
                return format_formula(runtime.procDamageAttribute, runtime.procDamageMultiplierTenth, "额外伤害")
            end
            if runtime.summonDamageAttribute and runtime.summonDamageMultiplierTenth then
                return "猴兵每次攻击：" .. format_multiplier(runtime.summonDamageMultiplierTenth)
                    .. "×" .. (ATTRIBUTE_LABELS[runtime.summonDamageAttribute] or "主属性")
            end
        end
    end
    return nil
end

---@type table<string, HeroAbilityView>
local ability_by_rawcode = {}

local function format_values(value)
    if type(value) == "table" then
        local values = {}
        for _, entry in ipairs(value) do
            table.insert(values, tostring(entry))
        end
        return table.concat(values, " / ")
    end
    if value == nil then
        return "无"
    end
    return tostring(value)
end

local function format_default_range(ability)
    if ability.Rng == nil and ability.Area == nil then
        return "无"
    end
    if ability.Rng == nil then
        return "范围 " .. format_values(ability.Area)
    end
    if ability.Area == nil then
        return "距离 " .. format_values(ability.Rng)
    end
    return "距离 " .. format_values(ability.Rng) .. "；范围 " .. format_values(ability.Area)
end

local function format_default_cooldown(ability)
    if ability.Cool == nil then
        return "无"
    end
    if type(ability.Cool) == "number" and ability.Cool == 0 then
        return "被动"
    end
    if type(ability.Cool) == "table" then
        local has_cooldown = false
        for _, cooldown in ipairs(ability.Cool) do
            if cooldown ~= 0 then
                has_cooldown = true
                break
            end
        end
        if not has_cooldown then
            return "被动"
        end
    end
    return format_values(ability.Cool) .. " 秒"
end

local function build_ability(rawcode)
    local ability = abilities[rawcode]
    if ability == nil then
        return nil
    end

    local presentation = presentation_by_rawcode[rawcode] or {}
    return {
        rawcode = rawcode,
        name = ability.Name or rawcode,
        description = ability.Ubertip or "",
        damage = formula_damage(rawcode) or presentation.damage or format_values(ability.DataA),
        range = presentation.range or format_default_range(ability),
        cooldown = presentation.cooldown or format_default_cooldown(ability),
    }
end

--- 获取技能展示数据。
---@param rawcode string 技能 Rawcode
---@return HeroAbilityView|nil ability 技能展示数据；不存在时为空
function module.get(rawcode)
    if ability_by_rawcode[rawcode] == nil then
        ability_by_rawcode[rawcode] = build_ability(rawcode)
    end
    return ability_by_rawcode[rawcode]
end

JiuDou.publish("gameplay.selectHero.data.ability_catalog", module)
return module
