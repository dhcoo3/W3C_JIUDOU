--- 英雄池数据层。
--- 负责声明入池顺序，并由自动生成的单位配置构造选将展示数据。
local units = JiuDou.config.units

local module = {}

local HERO_RAWCODES = {
    "H0W0",
    "H0N0",
    "H0B0",
    "H0E0",
}

---@class HeroDefinition
---@field rawcode string 单位 Rawcode
---@field name string 英雄名称
---@field description string 英雄简介
---@field primary string 主属性英文标记
---@field strength integer 初始力量
---@field agility integer 初始敏捷
---@field intelligence integer 初始智力
---@field strengthGrowth integer 力量成长
---@field agilityGrowth integer 敏捷成长
---@field intelligenceGrowth integer 智力成长
---@field abilities string[] 四个英雄技能 Rawcode

local function split_rawcodes(rawcodes)
    local result = {}
    for rawcode in string.gmatch(rawcodes or "", "[^,]+") do
        table.insert(result, rawcode)
    end
    return result
end

local function build_hero(rawcode)
    local unit = units[rawcode]
    if unit == nil then
        error("英雄池引用了不存在的单位配置：" .. rawcode)
    end

    return {
        rawcode = rawcode,
        name = unit.Name or rawcode,
        description = unit.Ubertip or "",
        primary = unit.Primary or "STR",
        strength = unit.STR or 0,
        agility = unit.AGI or 0,
        intelligence = unit.INT or 0,
        strengthGrowth = unit.STRplus or 0,
        agilityGrowth = unit.AGIplus or 0,
        intelligenceGrowth = unit.INTplus or 0,
        abilities = split_rawcodes(unit.heroAbilList),
    }
end

---@type HeroDefinition[]
local heroes = {}
for _, rawcode in ipairs(HERO_RAWCODES) do
    table.insert(heroes, build_hero(rawcode))
end

---@type table<string, HeroDefinition>
local hero_by_rawcode = {}
for hero_index, hero in ipairs(heroes) do
    hero_by_rawcode[hero.rawcode] = hero
end

--- 获取完整英雄池。
---@return HeroDefinition[] pool 只读英雄池引用
function module.get_all()
    return heroes
end

--- 按 Rawcode 获取英雄数据。
---@param rawcode string 英雄 Rawcode
---@return HeroDefinition|nil hero 对应英雄；不存在时为空
function module.get(rawcode)
    return hero_by_rawcode[rawcode]
end

--- 判断 Rawcode 是否位于当前英雄池。
---@param rawcode string 英雄 Rawcode
---@return boolean contained 是否存在
function module.contains(rawcode)
    return hero_by_rawcode[rawcode] ~= nil
end

JiuDou.publish("gameplay.selectHero.data.hero_pool", module)
return module
