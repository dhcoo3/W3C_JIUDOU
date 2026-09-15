--- 本文件由 generate_lua_config.ps1 自动生成，请勿手工修改。
--- 数据源来自 excelCfg 配置表；请修改 Excel 后重新执行生成工具。
---@class AttributeDefinition
---@field attributeId string 属性 ID
---@field group string 面板分组
---@field name string 显示名称
---@field displayOrder integer 显示排序
---@field displayFormat string 显示格式
---@field projection string 引擎投影类型；百分比派生属性统一使用 canonical ID
JiuDou = JiuDou or {}
JiuDou.config = JiuDou.config or {}
JiuDou.config.attributes = {
    ["version"] = 1,
    ["attributes"] = {
        ["strength"] = {
            ["attributeId"] = "strength",
            ["group"] = "主属性",
            ["name"] = "力量",
            ["displayOrder"] = 10,
            ["displayFormat"] = "integer",
            ["projection"] = "hero_strength",
        },
        ["agility"] = {
            ["attributeId"] = "agility",
            ["group"] = "主属性",
            ["name"] = "敏捷",
            ["displayOrder"] = 20,
            ["displayFormat"] = "integer",
            ["projection"] = "hero_agility",
        },
        ["intelligence"] = {
            ["attributeId"] = "intelligence",
            ["group"] = "主属性",
            ["name"] = "智力",
            ["displayOrder"] = 30,
            ["displayFormat"] = "integer",
            ["projection"] = "hero_intelligence",
        },
        ["attack"] = {
            ["attributeId"] = "attack",
            ["group"] = "战斗属性",
            ["name"] = "攻击",
            ["displayOrder"] = 100,
            ["displayFormat"] = "integer",
            ["projection"] = "hidden_attack",
        },
        ["health"] = {
            ["attributeId"] = "health",
            ["group"] = "战斗属性",
            ["name"] = "生命",
            ["displayOrder"] = 110,
            ["displayFormat"] = "integer",
            ["projection"] = "hidden_health",
        },
        ["armor"] = {
            ["attributeId"] = "armor",
            ["group"] = "战斗属性",
            ["name"] = "护甲",
            ["displayOrder"] = 120,
            ["displayFormat"] = "integer",
            ["projection"] = "hidden_armor",
        },
        ["moveSpeed"] = {
            ["attributeId"] = "moveSpeed",
            ["group"] = "战斗属性",
            ["name"] = "移速",
            ["displayOrder"] = 130,
            ["displayFormat"] = "integer",
            ["projection"] = "native_move_speed",
        },
        ["attack_speed_percent"] = {
            ["attributeId"] = "attack_speed_percent",
            ["group"] = "战斗属性",
            ["name"] = "攻击速度",
            ["displayOrder"] = 125,
            ["displayFormat"] = "percent",
            ["projection"] = "derived_attack_speed_percent",
        },
        ["basic_attack_bonus_percent"] = {
            ["attributeId"] = "basic_attack_bonus_percent",
            ["group"] = "战斗属性",
            ["name"] = "普攻加成",
            ["displayOrder"] = 135,
            ["displayFormat"] = "percent",
            ["projection"] = "derived_basic_attack_bonus_percent",
        },
        ["health_amplification_percent"] = {
            ["attributeId"] = "health_amplification_percent",
            ["group"] = "战斗属性",
            ["name"] = "生命增幅",
            ["displayOrder"] = 140,
            ["displayFormat"] = "percent",
            ["projection"] = "derived_health_amplification_percent",
        },
    },
}
return JiuDou.config.attributes
