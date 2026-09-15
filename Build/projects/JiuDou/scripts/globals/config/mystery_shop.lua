--- 本文件由 generate_lua_config.ps1 自动生成，请勿手工修改。
--- 数据源来自 excelCfg 配置表；请修改 Excel 后重新执行生成工具。
---@class MysteryShopLocation
---@field shopId string 商店 ID
---@field blockId integer 地图区域编号
---@field sourcePoint string 参考刷怪点
---@field unitRawcode string 商店单位 Rawcode
---@field x integer 世界坐标 X
---@field y integer 世界坐标 Y
---@field facing integer 朝向
---@field enabled integer 启用状态
---@class MysteryShopStock
---@field stockId string 库存 ID
---@field shopId string 商店 ID
---@field itemRawcode string 商品 Rawcode
---@field productKind string 商品类型：box/health/mana
---@field boxLevel integer 装备箱等级；消耗品为 0
---@field price integer 金币价格
---@field initialStock integer 初始库存
---@field maxStock integer 最大库存
---@field stockRegen integer 补货间隔秒数
---@field enabled integer 启用状态
---@class MysteryShopConsumable
---@field rawcode string 消耗品 Rawcode
---@field kind string 恢复类型：health/mana
---@field abilityRawcode string 物品技能 Rawcode
---@field healPercent integer 最大生命恢复百分比
---@field manaPercent integer 最大法力恢复百分比
---@field price integer 金币价格
---@field stockRegen integer 补货间隔秒数
---@field enabled integer 启用状态
---@class MysteryShopConfig
---@field version integer 配置版本
---@field refillIntervalSeconds integer 装备箱补货间隔秒数
---@field consumableRefillIntervalSeconds integer 消耗品补货间隔秒数
---@field shops table<string, MysteryShopLocation>
---@field stock table<string, MysteryShopStock>
---@field boxByRawcode table<string, integer>
---@field consumableByRawcode table<string, MysteryShopConsumable>
JiuDou = JiuDou or {}
JiuDou.config = JiuDou.config or {}
JiuDou.config.mystery_shop = {
    ["version"] = 1,
    ["refillIntervalSeconds"] = 1,
    ["consumableRefillIntervalSeconds"] = 5,
    ["shops"] = {
        ["SHOP_2"] = {
            ["shopId"] = "SHOP_2",
            ["blockId"] = 2,
            ["sourcePoint"] = "MonsterPoint_2_1",
            ["unitRawcode"] = "S0M1",
            ["x"] = -240,
            ["y"] = 6320,
            ["facing"] = 270,
            ["enabled"] = 1,
        },
        ["SHOP_4"] = {
            ["shopId"] = "SHOP_4",
            ["blockId"] = 4,
            ["sourcePoint"] = "MonsterPoint_4_1",
            ["unitRawcode"] = "S0M1",
            ["x"] = -6384,
            ["y"] = 912,
            ["facing"] = 270,
            ["enabled"] = 1,
        },
        ["SHOP_6"] = {
            ["shopId"] = "SHOP_6",
            ["blockId"] = 6,
            ["sourcePoint"] = "MonsterPoint_6_1",
            ["unitRawcode"] = "S0M1",
            ["x"] = 3696,
            ["y"] = -2256,
            ["facing"] = 270,
            ["enabled"] = 1,
        },
        ["SHOP_8"] = {
            ["shopId"] = "SHOP_8",
            ["blockId"] = 8,
            ["sourcePoint"] = "MonsterPoint_8_1",
            ["unitRawcode"] = "S0M1",
            ["x"] = 1712,
            ["y"] = -6928,
            ["facing"] = 270,
            ["enabled"] = 1,
        },
    },
    ["stock"] = {
        ["STOCK_SHOP_2_L1"] = {
            ["stockId"] = "STOCK_SHOP_2_L1",
            ["shopId"] = "SHOP_2",
            ["itemRawcode"] = "I0K1",
            ["productKind"] = "box",
            ["boxLevel"] = 1,
            ["price"] = 300,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["stockRegen"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_2_L2"] = {
            ["stockId"] = "STOCK_SHOP_2_L2",
            ["shopId"] = "SHOP_2",
            ["itemRawcode"] = "I0K2",
            ["productKind"] = "box",
            ["boxLevel"] = 2,
            ["price"] = 900,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["stockRegen"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_2_L3"] = {
            ["stockId"] = "STOCK_SHOP_2_L3",
            ["shopId"] = "SHOP_2",
            ["itemRawcode"] = "I0K3",
            ["productKind"] = "box",
            ["boxLevel"] = 3,
            ["price"] = 1800,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["stockRegen"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_4_L1"] = {
            ["stockId"] = "STOCK_SHOP_4_L1",
            ["shopId"] = "SHOP_4",
            ["itemRawcode"] = "I0K1",
            ["productKind"] = "box",
            ["boxLevel"] = 1,
            ["price"] = 300,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["stockRegen"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_4_L2"] = {
            ["stockId"] = "STOCK_SHOP_4_L2",
            ["shopId"] = "SHOP_4",
            ["itemRawcode"] = "I0K2",
            ["productKind"] = "box",
            ["boxLevel"] = 2,
            ["price"] = 900,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["stockRegen"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_4_L3"] = {
            ["stockId"] = "STOCK_SHOP_4_L3",
            ["shopId"] = "SHOP_4",
            ["itemRawcode"] = "I0K3",
            ["productKind"] = "box",
            ["boxLevel"] = 3,
            ["price"] = 1800,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["stockRegen"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_6_L1"] = {
            ["stockId"] = "STOCK_SHOP_6_L1",
            ["shopId"] = "SHOP_6",
            ["itemRawcode"] = "I0K1",
            ["productKind"] = "box",
            ["boxLevel"] = 1,
            ["price"] = 300,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["stockRegen"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_6_L2"] = {
            ["stockId"] = "STOCK_SHOP_6_L2",
            ["shopId"] = "SHOP_6",
            ["itemRawcode"] = "I0K2",
            ["productKind"] = "box",
            ["boxLevel"] = 2,
            ["price"] = 900,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["stockRegen"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_6_L3"] = {
            ["stockId"] = "STOCK_SHOP_6_L3",
            ["shopId"] = "SHOP_6",
            ["itemRawcode"] = "I0K3",
            ["productKind"] = "box",
            ["boxLevel"] = 3,
            ["price"] = 1800,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["stockRegen"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_8_L1"] = {
            ["stockId"] = "STOCK_SHOP_8_L1",
            ["shopId"] = "SHOP_8",
            ["itemRawcode"] = "I0K1",
            ["productKind"] = "box",
            ["boxLevel"] = 1,
            ["price"] = 300,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["stockRegen"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_8_L2"] = {
            ["stockId"] = "STOCK_SHOP_8_L2",
            ["shopId"] = "SHOP_8",
            ["itemRawcode"] = "I0K2",
            ["productKind"] = "box",
            ["boxLevel"] = 2,
            ["price"] = 900,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["stockRegen"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_8_L3"] = {
            ["stockId"] = "STOCK_SHOP_8_L3",
            ["shopId"] = "SHOP_8",
            ["itemRawcode"] = "I0K3",
            ["productKind"] = "box",
            ["boxLevel"] = 3,
            ["price"] = 1800,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["stockRegen"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_2_HEALTH"] = {
            ["stockId"] = "STOCK_SHOP_2_HEALTH",
            ["shopId"] = "SHOP_2",
            ["itemRawcode"] = "I0P1",
            ["productKind"] = "health",
            ["boxLevel"] = 0,
            ["price"] = 50,
            ["initialStock"] = 3,
            ["maxStock"] = 3,
            ["stockRegen"] = 5,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_4_HEALTH"] = {
            ["stockId"] = "STOCK_SHOP_4_HEALTH",
            ["shopId"] = "SHOP_4",
            ["itemRawcode"] = "I0P1",
            ["productKind"] = "health",
            ["boxLevel"] = 0,
            ["price"] = 50,
            ["initialStock"] = 3,
            ["maxStock"] = 3,
            ["stockRegen"] = 5,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_6_HEALTH"] = {
            ["stockId"] = "STOCK_SHOP_6_HEALTH",
            ["shopId"] = "SHOP_6",
            ["itemRawcode"] = "I0P1",
            ["productKind"] = "health",
            ["boxLevel"] = 0,
            ["price"] = 50,
            ["initialStock"] = 3,
            ["maxStock"] = 3,
            ["stockRegen"] = 5,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_8_HEALTH"] = {
            ["stockId"] = "STOCK_SHOP_8_HEALTH",
            ["shopId"] = "SHOP_8",
            ["itemRawcode"] = "I0P1",
            ["productKind"] = "health",
            ["boxLevel"] = 0,
            ["price"] = 50,
            ["initialStock"] = 3,
            ["maxStock"] = 3,
            ["stockRegen"] = 5,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_2_MANA"] = {
            ["stockId"] = "STOCK_SHOP_2_MANA",
            ["shopId"] = "SHOP_2",
            ["itemRawcode"] = "I0P2",
            ["productKind"] = "mana",
            ["boxLevel"] = 0,
            ["price"] = 100,
            ["initialStock"] = 3,
            ["maxStock"] = 3,
            ["stockRegen"] = 5,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_4_MANA"] = {
            ["stockId"] = "STOCK_SHOP_4_MANA",
            ["shopId"] = "SHOP_4",
            ["itemRawcode"] = "I0P2",
            ["productKind"] = "mana",
            ["boxLevel"] = 0,
            ["price"] = 100,
            ["initialStock"] = 3,
            ["maxStock"] = 3,
            ["stockRegen"] = 5,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_6_MANA"] = {
            ["stockId"] = "STOCK_SHOP_6_MANA",
            ["shopId"] = "SHOP_6",
            ["itemRawcode"] = "I0P2",
            ["productKind"] = "mana",
            ["boxLevel"] = 0,
            ["price"] = 100,
            ["initialStock"] = 3,
            ["maxStock"] = 3,
            ["stockRegen"] = 5,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_8_MANA"] = {
            ["stockId"] = "STOCK_SHOP_8_MANA",
            ["shopId"] = "SHOP_8",
            ["itemRawcode"] = "I0P2",
            ["productKind"] = "mana",
            ["boxLevel"] = 0,
            ["price"] = 100,
            ["initialStock"] = 3,
            ["maxStock"] = 3,
            ["stockRegen"] = 5,
            ["enabled"] = 1,
        },
    },
    ["boxByRawcode"] = {
        ["I0K1"] = 1,
        ["I0K2"] = 2,
        ["I0K3"] = 3,
    },
    ["consumableByRawcode"] = {
        ["I0P1"] = {
            ["rawcode"] = "I0P1",
            ["kind"] = "health",
            ["abilityRawcode"] = "A0P1",
            ["healPercent"] = 20,
            ["manaPercent"] = 0,
            ["price"] = 50,
            ["stockRegen"] = 5,
            ["enabled"] = 1,
        },
        ["I0P2"] = {
            ["rawcode"] = "I0P2",
            ["kind"] = "mana",
            ["abilityRawcode"] = "A0P2",
            ["healPercent"] = 0,
            ["manaPercent"] = 50,
            ["price"] = 100,
            ["stockRegen"] = 5,
            ["enabled"] = 1,
        },
    },
}
return JiuDou.config.mystery_shop
