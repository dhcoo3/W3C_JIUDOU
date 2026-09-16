--- PVE 刷怪配置层。
--- 负责从自动生成的单位、技能和区域配置中构造刷怪区域与技能行为。
local regions = JiuDou.config.regions
local units = JiuDou.config.units
local abilities = JiuDou.config.abilities
local buffs = JiuDou.config.buffs
local boss_affixes = JiuDou.config.boss_affixes
local mode_config = JiuDou.module("gameplay.runMode.config")

local module = {}

---@class MonsterRegion
---@field name string 区域名称
---@field minX number 左边界
---@field minY number 下边界
---@field maxX number 右边界
---@field maxY number 上边界

---@class MonsterBlock
---@field id integer 区域编号
---@field region MonsterRegion 普通怪归属区域

---@class EliteSpawnPoint
---@field blockId integer 所属区域编号
---@field index integer 区域内点位编号
---@field region MonsterRegion 精英点区域

---@class TierMonsterUnits
---@field normalMeleeRawcode string 近战普通怪 Rawcode
---@field normalRangedRawcode string 远程普通怪 Rawcode
---@field eliteRawcode string 精英 Rawcode

---@class BossSpawnPoint
---@field id integer Boss 编号
---@field blockId integer 所属区域编号
---@field region MonsterRegion Boss 点区域
---@field bossRawcode string Boss Rawcode

---@class BossAffixConfig
---@field affixId string 词缀编号
---@field bossRawcode string 对应 Boss Rawcode
---@field name string 词缀名称
---@field description string 词缀说明
---@field kind string 原生物编词缀类型
---@field refillLife boolean 添加后是否回满生命
---@field indicatorAbilityRawcode string 状态栏图标辅助光环 Rawcode
---@field indicatorBuffRawcode string 状态栏图标 Buff Rawcode
---@field globalAbilities string|nil 全局恒定强度词缀 Rawcode
---@field unitAbilities table<string, string>|nil 基础怪物 ID 到单位变体词缀 Rawcode 的映射

---@class MonsterActiveAbility
---@field rawcode string 技能 Rawcode
---@field order string Warcraft 施法命令
---@field targetType "point"|"unit"|"immediate" 施法目标类型
---@field range integer 允许施法的最大目标距离
---@field cooldown integer 刷怪 AI 使用的冷却秒数

---@class MonsterSettings
---@field normalCountPerBlock integer 每个地图区域维持的普通怪数量
---@field normalRespawnSeconds number 普通怪死亡后的补充等待秒数
---@field eliteRespawnSeconds number 精英死亡后的复活等待秒数
---@field bossSpawnIntervalSeconds number 相邻 Boss 的生成间隔秒数
---@field bossMinimapPingSeconds number Boss 出现时小地图提示持续秒数
---@field bossAnnouncementSeconds number Boss 出现时普通文字公告持续秒数
---@field bossAffixEffectModel string 获得 Boss 词缀的小怪持续特效模型
---@field bossAffixEffectAttachment string Boss 词缀特效挂接点
---@field aiIntervalSeconds number 索敌与施法检查间隔秒数
---@field schedulerIntervalSeconds number 确定性调度器的节拍秒数
---@field normalMeleeChance integer 普通怪生成近战单位的百分比
---@field randomPointAttempts integer 寻找可行走随机点的最大次数
---@field pointInset number 随机点与区域边缘保持的最小距离
---@field maxPlayerCount integer 参与 PVE 的最大玩家数量
---@field specialMonsterMaxAlive integer 全图特殊怪同时存活上限
---@field specialMonsterLifetimeSeconds number 特殊怪自然移除时间
---@field specialMonsterSpawnRadius number 特殊怪相对死亡点的最大偏移距离
---@type MonsterSettings
module.SETTINGS = {
    normalCountPerBlock = 50,
    normalRespawnSeconds = 2.0,
    eliteRespawnSeconds = 20.0,
    bossSpawnIntervalSeconds = 60.0,
    bossMinimapPingSeconds = 5.0,
    bossAnnouncementSeconds = 8.0,
    -- 仅为获得天灾词缀的小怪显示；原生嗜血目标特效清晰且开销较低。
    bossAffixEffectModel = "Abilities\\Spells\\Orc\\Bloodlust\\BloodlustTarget.mdl",
    bossAffixEffectAttachment = "overhead",
    aiIntervalSeconds = 0.5,
    schedulerIntervalSeconds = 0.25,
    normalMeleeChance = 70,
    randomPointAttempts = 32,
    pointInset = 32.0,
    maxPlayerCount = 10,
    specialMonsterMaxAlive = 300,
    specialMonsterLifetimeSeconds = 20.0,
    specialMonsterSpawnRadius = 300.0,
}

local function require_region(name)
    local region = regions[name]
    if region == nil then
        error("刷怪配置缺少区域：" .. name)
    end
    return region
end

local function require_unit(rawcode)
    if units[rawcode] == nil then
        error("刷怪配置缺少单位：" .. rawcode)
    end
    return rawcode
end

local function normalize_integer(value, fallback)
    if type(value) == "number" and value == math.floor(value) then
        return value
    end
    if type(value) == "table"
        and type(value[1]) == "number"
        and value[1] == math.floor(value[1]) then
        return value[1]
    end
    return fallback
end

module.SPECIAL_GOLD_RAWCODE = require_unit("G0M1")
module.SPECIAL_EXPERIENCE_RAWCODE = require_unit("X0M1")

local variants_by_base = {}
local variant_count = 0
for rawcode, unit in pairs(units) do
    if unit.baseUnitId ~= nil then
        local mode_id = normalize_integer(unit.modeId, nil)
        local level = normalize_integer(unit.difficultyLevel, nil)
        if type(mode_id) ~= "number" or (mode_id ~= 1 and mode_id ~= 2)
            or type(level) ~= "number" or level < 1 or level > 10 then
            error("PVE 怪物变体元数据无效：" .. tostring(rawcode))
        end
        local key = string.format("%d:%d", mode_id, level)
        local base_rawcode = unit.baseUnitId
        variants_by_base[base_rawcode] = variants_by_base[base_rawcode] or {}
        if variants_by_base[base_rawcode][key] ~= nil then
            error("PVE 怪物难度组合重复：" .. tostring(base_rawcode) .. "/" .. key)
        end
        variants_by_base[base_rawcode][key] = rawcode
        variant_count = variant_count + 1
    end
end
if variant_count ~= 760 then error("PVE 怪物变体必须恰有 760 个，实际=" .. tostring(variant_count)) end
for base_rawcode, variants in pairs(variants_by_base) do
    for mode_id = 1, 2 do
        for level = 1, 10 do
            local key = string.format("%d:%d", mode_id, level)
            if variants[key] == nil then
                error("PVE 怪物变体缺失：" .. tostring(base_rawcode) .. "/" .. key)
            end
        end
    end
end

-- 军团阶位来自 unit.xlsx 名称后缀写入的 tier 字段，与地图区域编号解耦。
-- 只把每种模板的普通模式 1 级 Rawcode 作为基础模板，其余难度由 variant 映射继续选择。
local tier_units_by_tier = {}
for rawcode, unit in pairs(units) do
    local tier = normalize_integer(unit.tier, nil)
    if tier ~= nil then
        if tier < 1 or tier > 9 then
            error("PVE 怪物阶数必须为 1 到 9：" .. tostring(rawcode))
        end
        if unit.baseUnitId == rawcode
            and normalize_integer(unit.modeId, nil) == 1
            and normalize_integer(unit.difficultyLevel, nil) == 1 then
            local role
            if string.match(rawcode, "^N[1-9]M1$") then
                role = "normalMeleeRawcode"
            elseif string.match(rawcode, "^N[1-9]R1$") then
                role = "normalRangedRawcode"
            elseif string.match(rawcode, "^E[1-9]M1$") then
                role = "eliteRawcode"
            else
                error("PVE 阶数模板 Rawcode 无法识别：" .. tostring(rawcode))
            end
            tier_units_by_tier[tier] = tier_units_by_tier[tier] or {}
            if tier_units_by_tier[tier][role] ~= nil then
                error(string.format("PVE 阶数模板重复：阶数=%d，类别=%s", tier, role))
            end
            tier_units_by_tier[tier][role] = rawcode
        end
    end
end
for tier = 1, 9 do
    local templates = tier_units_by_tier[tier]
    if templates == nil
        or templates.normalMeleeRawcode == nil
        or templates.normalRangedRawcode == nil
        or templates.eliteRawcode == nil then
        error("PVE 阶数配置不完整，需包含近战普通怪、远程普通怪和精英：阶数=" .. tostring(tier))
    end
end
module.MAX_MONSTER_TIER = 9

---@class MonsterDifficulty
---@field modeId integer PVE 模式编号
---@field level integer PVE 难度等级
---@field variantIndex integer 当前难度变体索引

---@type MonsterBlock[]
module.BLOCKS = {}
---@type EliteSpawnPoint[]
module.ELITE_POINTS = {}
---@type BossSpawnPoint[]
module.BOSS_POINTS = {}
---@type BossAffixConfig[]
module.BOSS_AFFIXES = {}
local boss_affix_by_boss_rawcode = {}

for block_id = 1, 9 do
    local block = {
        id = block_id,
        region = require_region("Map_Block_" .. block_id),
    }
    table.insert(module.BLOCKS, block)

    for point_index = 1, 3 do
        table.insert(module.ELITE_POINTS, {
            blockId = block_id,
            index = point_index,
            region = require_region(string.format("MonsterPoint_%d_%d", block_id, point_index)),
        })
    end

    table.insert(module.BOSS_POINTS, {
        id = block_id,
        blockId = block_id,
        region = require_region("BossPoint_" .. block_id),
        bossRawcode = require_unit("B" .. block_id .. "M1"),
    })
end

local function validate_affix_ability(ability_rawcode, context)
    if type(ability_rawcode) ~= "string" or abilities[ability_rawcode] == nil then
        error("Boss 词缀技能对象缺失：" .. context .. "/" .. tostring(ability_rawcode))
    end
end

for boss_index = 1, #module.BOSS_POINTS do
    local boss_point = module.BOSS_POINTS[boss_index]
    local affix_id = "B" .. boss_index
    local affix = boss_affixes.affixes[affix_id]
    if type(affix) ~= "table" then
        error("Boss 词缀配置缺失：" .. affix_id)
    end
    if affix.bossRawcode ~= boss_point.bossRawcode then
        error("Boss 词缀与 Boss 点不匹配：" .. affix_id)
    end
    if boss_affix_by_boss_rawcode[affix.bossRawcode] ~= nil then
        error("Boss 词缀 Boss Rawcode 重复：" .. affix.bossRawcode)
    end
    if type(affix.indicatorAbilityRawcode) ~= "string"
        or abilities[affix.indicatorAbilityRawcode] == nil then
        error("Boss 词缀状态栏技能对象缺失：" .. affix_id)
    end
    if type(affix.indicatorBuffRawcode) ~= "string"
        or buffs[affix.indicatorBuffRawcode] == nil then
        error("Boss 词缀状态栏 Buff 对象缺失：" .. affix_id)
    end
    if affix.globalAbilities ~= nil then
        validate_affix_ability(affix.globalAbilities, affix_id)
    elseif type(affix.unitAbilities) == "table" then
        for block_id = 1, 9 do
            for _, unit_rawcode in ipairs({
                "N" .. block_id .. "M1",
                "N" .. block_id .. "R1",
                "E" .. block_id .. "M1",
                "B" .. block_id .. "M1",
            }) do
                validate_affix_ability(affix.unitAbilities[unit_rawcode], affix_id .. "/" .. unit_rawcode)
            end
        end
        for _, unit_rawcode in ipairs({ module.SPECIAL_GOLD_RAWCODE, module.SPECIAL_EXPERIENCE_RAWCODE }) do
            validate_affix_ability(affix.unitAbilities[unit_rawcode], affix_id .. "/" .. unit_rawcode)
        end
    else
        error("Boss 词缀缺少技能映射：" .. affix_id)
    end
    module.BOSS_AFFIXES[boss_index] = affix
    boss_affix_by_boss_rawcode[affix.bossRawcode] = affix
end

---@type string[]
module.ELITE_ABILITY_RAWCODES = {
    "A9S1", "A9S2", "A9S3", "A9S4", "A9S5", "A9S6", "A9S7", "A9S8",
}

local active_specs = {
    A1B1 = {order = "blink", targetType = "point", range = 650},
    A1B2 = {order = "roar", targetType = "immediate", range = 350},
    A2B1 = {order = "stomp", targetType = "immediate", range = 300},
    A2B2 = {order = "avatar", targetType = "immediate", range = 900},
    A3B1 = {order = "shockwave", targetType = "point", range = 700},
    A3B2 = {order = "roar", targetType = "immediate", range = 400},
    A4B1 = {order = "avatar", targetType = "immediate", range = 900},
    A4B2 = {order = "ensnare", targetType = "unit", range = 650},
    A5B1 = {order = "roar", targetType = "immediate", range = 450},
    A5B2 = {order = "stomp", targetType = "immediate", range = 320},
    A6B1 = {order = "rainoffire", targetType = "point", range = 800},
    A6B2 = {order = "shadowstrike", targetType = "unit", range = 700},
    A7B1 = {order = "stomp", targetType = "immediate", range = 360},
    A7B2 = {order = "ensnare", targetType = "unit", range = 650},
    A8B1 = {order = "stomp", targetType = "immediate", range = 380},
    A8B2 = {order = "ensnare", targetType = "unit", range = 700},
    A9B1 = {order = "rainoffire", targetType = "point", range = 800},
    A9B2 = {order = "shadowstrike", targetType = "unit", range = 750},
    A9S5 = {order = "summongrizzly", targetType = "immediate", range = 500},
}

---@type table<string, MonsterActiveAbility>
module.ACTIVE_ABILITIES = {}
for rawcode, spec in pairs(active_specs) do
    local ability = abilities[rawcode]
    if ability == nil then
        error("刷怪配置缺少技能：" .. rawcode)
    end

    local range = normalize_integer(ability.Rng, spec.range)
    if spec.targetType == "immediate" then
        -- 无目标技能的 Rng 常为 0，应以效果范围决定 AI 的施放距离。
        range = spec.range
    end

    module.ACTIVE_ABILITIES[rawcode] = {
        rawcode = rawcode,
        order = spec.order,
        targetType = spec.targetType,
        range = range,
        cooldown = normalize_integer(ability.Cool, 1),
    }
end

for _, rawcode in ipairs(module.ELITE_ABILITY_RAWCODES) do
    if abilities[rawcode] == nil then
        error("精英技能池缺少技能：" .. rawcode)
    end
end

local function split_rawcodes(rawcodes)
    local result = {}
    for rawcode in string.gmatch(rawcodes or "", "[^,]+") do
        table.insert(result, rawcode)
    end
    return result
end

--- 获取指定区域的刷怪配置。
---@param block_id integer 区域编号
---@return MonsterBlock|nil block 对应配置；不存在时为空
function module.get_block(block_id)
    return module.BLOCKS[block_id]
end

--- 按全局军团阶数读取普通怪与精英基础模板；金币怪和经验怪不经过此映射。
---@param tier integer 军团阶数 1–9
---@return TierMonsterUnits|nil templates 对应阶位的单位模板
function module.get_tier_units(tier)
    return tier_units_by_tier[tier]
end

--- 获取自动生成的单位名称；配置缺失时由调用方回退到 Rawcode。
---@param rawcode string 单位 Rawcode
---@return string|nil name 单位名称
function module.get_unit_name(rawcode)
    local unit = units[rawcode]
    if unit == nil or type(unit.Name) ~= "string" or unit.Name == "" then
        return nil
    end
    return unit.Name
end

--- 读取该难度变体物编中的最终经验奖励。
---@param rawcode string 单位 Rawcode
---@return integer experience 基础经验
function module.get_unit_experience_reward(rawcode)
    local unit = units[rawcode]
    if unit == nil then return 0 end
    return math.max(0, normalize_integer(unit.expReward, 0))
end

--- 读取该难度变体物编中的最终金币奖励。
---@param rawcode string 单位 Rawcode
---@return integer gold 最终金币奖励
function module.get_unit_gold_reward(rawcode)
    local unit = units[rawcode]
    if unit == nil then return 0 end
    return math.max(0, normalize_integer(unit.goldRep, 0))
end

--- 根据基础怪物 ID 和当前难度取得唯一的变体 Rawcode。
---@param rawcode string 基础或已变体化的单位 Rawcode
---@param current_difficulty MonsterDifficulty|nil 难度；省略时使用本局难度
---@return string|nil variant_rawcode 变体 Rawcode
function module.get_variant_rawcode(rawcode, current_difficulty)
    local unit = units[rawcode]
    if unit == nil then return nil end
    local base_rawcode = unit.baseUnitId or rawcode
    local selected = current_difficulty or module.current_difficulty
    if type(selected) ~= "table" then return nil end
    local variants = variants_by_base[base_rawcode]
    if variants == nil then return nil end
    return variants[string.format("%d:%d", selected.modeId, selected.level)]
end

--- 获取指定存活 Boss 对应的天灾词缀。
---@param boss_rawcode string Boss Rawcode
---@return BossAffixConfig|nil affix 词缀配置
function module.get_boss_affix(boss_rawcode)
    return boss_affix_by_boss_rawcode[boss_rawcode]
end

--- 获取指定 Boss 词缀的状态栏图标辅助光环。
---@param affix BossAffixConfig Boss 词缀配置
---@return string|nil rawcode 辅助光环 Rawcode
function module.get_boss_affix_indicator(affix)
    if type(affix) ~= "table" then
        return nil
    end
    local rawcode = affix.indicatorAbilityRawcode
    if type(rawcode) ~= "string" or abilities[rawcode] == nil then
        return nil
    end
    return rawcode
end

--- 获取指定小怪在当前难度下应挂载的 Boss 词缀技能。
---@param affix BossAffixConfig Boss 词缀配置
---@param unit_rawcode string 小怪 Rawcode
---@param current_difficulty MonsterDifficulty 当前难度
---@return string|nil rawcode 物编技能 Rawcode
---@return integer|nil level 物编技能等级
---@return boolean refill_life 是否需要在添加后回满生命
function module.get_boss_affix_ability(affix, unit_rawcode, current_difficulty)
    if type(affix) ~= "table" or type(current_difficulty) ~= "table" then
        return nil, nil, false
    end
    local ability_rawcode
    if type(affix.unitAbilities) == "table" then
        local unit = units[unit_rawcode]
        local base_rawcode = unit and (unit.baseUnitId or unit_rawcode) or unit_rawcode
        ability_rawcode = affix.unitAbilities[base_rawcode]
        if type(ability_rawcode) == "string" then
            local ability_level = (current_difficulty.modeId - 1) * 10 + current_difficulty.level
            if abilities[ability_rawcode] == nil then return nil, nil, false end
            return ability_rawcode, ability_level, affix.refillLife == true
        end
    end
    ability_rawcode = affix.globalAbilities
    if type(ability_rawcode) ~= "string" or abilities[ability_rawcode] == nil then
        return nil, nil, false
    end
    return ability_rawcode, 1, affix.refillLife == true
end

--- 获取单位静态技能中需要 AI 主动施放的技能。
---@param rawcode string 单位 Rawcode
---@return MonsterActiveAbility[] abilities 主动技能列表
function module.get_unit_active_abilities(rawcode)
    local unit = units[rawcode]
    if unit == nil then
        return {}
    end

    local result = {}
    for _, ability_rawcode in ipairs(split_rawcodes(unit.abilList)) do
        local ability = module.ACTIVE_ABILITIES[ability_rawcode]
        if ability ~= nil then
            table.insert(result, ability)
        end
    end
    return result
end

--- 获取精英随机技能中的主动施法配置。
---@param rawcode string 技能 Rawcode
---@return MonsterActiveAbility|nil ability 主动技能配置；被动技能为空
function module.get_active_ability(rawcode)
    return module.ACTIVE_ABILITIES[rawcode]
end

--- 根据已同步的 PVE 选择读取 Excel 生成的难度配置。
---@param selection ModeSelection PVE 模式与等级
---@return MonsterDifficulty|nil difficulty 难度数据；非法时为空
---@return string|nil message 非法原因
function module.create_difficulty(selection)
    if type(selection) ~= "table" or selection.category ~= mode_config.CATEGORY_PVE then
        return nil, "刷怪系统仅支持 PVE 模式"
    end
    if type(selection.level) ~= "number"
        or selection.level ~= math.floor(selection.level)
        or selection.level < mode_config.LEVEL_MIN
        or selection.level > mode_config.LEVEL_MAX then
        return nil, "PVE 难度等级无效"
    end

    if selection.modeId ~= mode_config.MODE_ID.PVE_NORMAL
        and selection.modeId ~= mode_config.MODE_ID.PVE_HARD then
        return nil, "PVE 模式编号无效"
    end
    local difficulty = {
        modeId = selection.modeId,
        level = selection.level,
        variantIndex = (selection.modeId - 1) * 10 + selection.level,
    }
    module.current_difficulty = difficulty
    return difficulty, nil
end

JiuDou.publish("gameplay.monster.config", module)
return module
