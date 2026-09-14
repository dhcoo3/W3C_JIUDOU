--- 肉鸽配置访问与启动校验。
local data = require "config.roguelike"
local abilities = require "config.abilities"
local units = require "config.units"

local module = {data = data}

local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

function module.validate()
    local errors = {}
    if type(data.settings) ~= "table" or data.settings.choiceCount ~= 3 then
        table.insert(errors, "settings.choiceCount 必须为 3")
    elseif not is_integer(data.settings.firstRewardLevel) or data.settings.firstRewardLevel < 1 then
        table.insert(errors, "settings.firstRewardLevel 必须为不小于 1 的整数")
    elseif not is_integer(data.settings.rewardLevelInterval) or data.settings.rewardLevelInterval < 1 then
        table.insert(errors, "settings.rewardLevelInterval 必须为不小于 1 的整数")
    end
    local skill_counts = {}
    local common_count = 0
    for effect_id, effect in pairs(data.effects or {}) do
        if effect.effectId ~= effect_id then table.insert(errors, "效果 ID 不一致：" .. tostring(effect_id)) end
        if type(effect.values) ~= "table" or #effect.values ~= 3 then
            table.insert(errors, "效果必须有三级数值：" .. tostring(effect_id))
        else
            for _, value in ipairs(effect.values) do
                if not is_integer(value) then table.insert(errors, "效果数值必须为整数：" .. tostring(effect_id)) end
            end
        end
        if effect.maxLevel ~= 3 or not is_integer(effect.weight) or effect.weight <= 0 then
            table.insert(errors, "效果等级或权重无效：" .. tostring(effect_id))
        end
        if effect.type == "Skill" then
            if units[effect.hero] == nil then table.insert(errors, "技能肉鸽英雄不存在：" .. tostring(effect_id)) end
            if abilities[effect.skill] == nil then table.insert(errors, "技能肉鸽技能不存在：" .. tostring(effect_id)) end
            local key = tostring(effect.hero) .. ":" .. tostring(effect.skill)
            skill_counts[key] = (skill_counts[key] or 0) + 1
        elseif effect.type == "Common" then
            common_count = common_count + 1
        else
            table.insert(errors, "效果类型无效：" .. tostring(effect_id))
        end
    end
    for _, hero_skills in ipairs({
        {hero = "H0W0", name = "悟空", skills = {"A0W1", "A0W2", "A0W3", "A0W4"}},
        {hero = "H0E0", name = "阿尔萨斯", skills = {"A0E1", "A0E2", "A0E3", "A0E4"}},
    }) do
        for _, rawcode in ipairs(hero_skills.skills) do
            if skill_counts[hero_skills.hero .. ":" .. rawcode] ~= 2 then
                table.insert(errors, hero_skills.name .. "技能必须恰有两个肉鸽效果：" .. rawcode)
            end
        end
    end
    if common_count ~= 8 then table.insert(errors, "首版通用肉鸽必须恰有 8 个") end
    -- 英雄技能伤害统一从拥有者主属性读取，禁止回退到固定三维属性。
    local allowed_attributes = {primary = true}
    for hero_rawcode, by_skill in pairs(data.skillRuntime or {}) do
        for skill_rawcode, runtime in pairs(by_skill) do
            if runtime.damage ~= nil then
                table.insert(errors, "技能结算禁止固定 damage 数组：" .. hero_rawcode .. "/" .. skill_rawcode)
            end
            for _, prefix in ipairs({"", "proc"}) do
                local attribute_key = prefix == "" and "damageAttribute" or (prefix .. "DamageAttribute")
                local multiplier_key = prefix == "" and "damageMultiplierTenth" or (prefix .. "DamageMultiplierTenth")
                local attribute, multipliers = runtime[attribute_key], runtime[multiplier_key]
                if attribute ~= nil or multipliers ~= nil then
                    if not allowed_attributes[attribute] or type(multipliers) ~= "table" then
                        table.insert(errors, "技能伤害公式无效：" .. hero_rawcode .. "/" .. skill_rawcode)
                    else
                        for _, multiplier in ipairs(multipliers) do
                            if not is_integer(multiplier) or multiplier <= 0 then
                                table.insert(errors, "技能伤害倍率无效：" .. hero_rawcode .. "/" .. skill_rawcode)
                                break
                            end
                        end
                    end
                end
            end
            if runtime.summonDamageAttribute ~= nil or runtime.summonDamageMultiplierTenth ~= nil
                or runtime.summonDamageMultiplierHundredth ~= nil then
                local multiplier = runtime.summonDamageMultiplierTenth or runtime.summonDamageMultiplierHundredth
                if not allowed_attributes[runtime.summonDamageAttribute] or not is_integer(multiplier) or multiplier <= 0 then
                    table.insert(errors, "召唤伤害公式无效：" .. hero_rawcode .. "/" .. skill_rawcode)
                end
            end
        end
    end
    return #errors == 0, errors
end

function module.get_effect(effect_id)
    return data.effects[effect_id]
end

function module.get_skill_ids(hero_rawcode)
    return data.skillIdsByHero[hero_rawcode] or {}
end

function module.get_common_ids()
    return data.commonIds
end

function module.get_skill_runtime(hero_rawcode, skill_rawcode)
    local hero = data.skillRuntime[hero_rawcode]
    return hero and hero[skill_rawcode] or nil
end

function module.format_description(effect, level)
    local value = effect.values[level] or 0
    local text = effect.description or ""
    text = string.gsub(text, "{value}", tostring(value))
    local tenth = string.format("%d.%d", math.floor(value / 10), math.abs(value % 10))
    text = string.gsub(text, "{value_tenth}", tenth)
    text = string.gsub(text, "{value_hundredth}", string.format("%d.%02d", math.floor(value / 100), math.abs(value % 100)))
    return text
end

return module
