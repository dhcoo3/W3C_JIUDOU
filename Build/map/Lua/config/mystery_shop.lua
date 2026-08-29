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
---@field itemRawcode string 装备箱 Rawcode
---@field boxLevel integer 装备箱等级
---@field price integer 金币价格
---@field initialStock integer 初始库存
---@field maxStock integer 最大库存
---@field enabled integer 启用状态
---@class MysteryShopConfig
---@field version integer 配置版本
---@field refillIntervalSeconds integer 补货间隔秒数
---@field shops table<string, MysteryShopLocation>
---@field stock table<string, MysteryShopStock>
---@field boxByRawcode table<string, integer>
return {
    ["version"] = 1,
    ["refillIntervalSeconds"] = 1,
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
            ["boxLevel"] = 1,
            ["price"] = 300,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_2_L2"] = {
            ["stockId"] = "STOCK_SHOP_2_L2",
            ["shopId"] = "SHOP_2",
            ["itemRawcode"] = "I0K2",
            ["boxLevel"] = 2,
            ["price"] = 900,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_2_L3"] = {
            ["stockId"] = "STOCK_SHOP_2_L3",
            ["shopId"] = "SHOP_2",
            ["itemRawcode"] = "I0K3",
            ["boxLevel"] = 3,
            ["price"] = 1800,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_4_L1"] = {
            ["stockId"] = "STOCK_SHOP_4_L1",
            ["shopId"] = "SHOP_4",
            ["itemRawcode"] = "I0K1",
            ["boxLevel"] = 1,
            ["price"] = 300,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_4_L2"] = {
            ["stockId"] = "STOCK_SHOP_4_L2",
            ["shopId"] = "SHOP_4",
            ["itemRawcode"] = "I0K2",
            ["boxLevel"] = 2,
            ["price"] = 900,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_4_L3"] = {
            ["stockId"] = "STOCK_SHOP_4_L3",
            ["shopId"] = "SHOP_4",
            ["itemRawcode"] = "I0K3",
            ["boxLevel"] = 3,
            ["price"] = 1800,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_6_L1"] = {
            ["stockId"] = "STOCK_SHOP_6_L1",
            ["shopId"] = "SHOP_6",
            ["itemRawcode"] = "I0K1",
            ["boxLevel"] = 1,
            ["price"] = 300,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_6_L2"] = {
            ["stockId"] = "STOCK_SHOP_6_L2",
            ["shopId"] = "SHOP_6",
            ["itemRawcode"] = "I0K2",
            ["boxLevel"] = 2,
            ["price"] = 900,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_6_L3"] = {
            ["stockId"] = "STOCK_SHOP_6_L3",
            ["shopId"] = "SHOP_6",
            ["itemRawcode"] = "I0K3",
            ["boxLevel"] = 3,
            ["price"] = 1800,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_8_L1"] = {
            ["stockId"] = "STOCK_SHOP_8_L1",
            ["shopId"] = "SHOP_8",
            ["itemRawcode"] = "I0K1",
            ["boxLevel"] = 1,
            ["price"] = 300,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_8_L2"] = {
            ["stockId"] = "STOCK_SHOP_8_L2",
            ["shopId"] = "SHOP_8",
            ["itemRawcode"] = "I0K2",
            ["boxLevel"] = 2,
            ["price"] = 900,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["enabled"] = 1,
        },
        ["STOCK_SHOP_8_L3"] = {
            ["stockId"] = "STOCK_SHOP_8_L3",
            ["shopId"] = "SHOP_8",
            ["itemRawcode"] = "I0K3",
            ["boxLevel"] = 3,
            ["price"] = 1800,
            ["initialStock"] = 1,
            ["maxStock"] = 1,
            ["enabled"] = 1,
        },
    },
    ["boxByRawcode"] = {
        ["I0K1"] = 1,
        ["I0K2"] = 2,
        ["I0K3"] = 3,
    },
}
