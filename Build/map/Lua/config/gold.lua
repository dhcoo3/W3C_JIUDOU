--- 本文件由 generate_lua_config.ps1 自动生成，请勿手工修改。
--- 数据源来自 excelCfg 配置表；请修改 Excel 后重新执行生成工具。
---@class GoldSettings
---@field initialGold integer 本局初始金币
---@field maxGoldDropBonusPercent integer 金币掉落加成上限
---@field maxGold integer 原生金币上限
---@class GoldConfig
---@field settings GoldSettings
---@field rewards table<string, table<string, integer>> 怪物金币奖励
return {
    ["settings"] = {
        ["initialGold"] = 0,
        ["maxGoldDropBonusPercent"] = 999,
        ["maxGold"] = 2147483647,
    },
    ["rewards"] = {
        ["normal"] = {
            ["1"] = 5,
            ["2"] = 7,
            ["3"] = 9,
            ["4"] = 12,
            ["5"] = 15,
            ["6"] = 18,
            ["7"] = 22,
            ["8"] = 26,
            ["9"] = 30,
        },
        ["elite"] = {
            ["1"] = 30,
            ["2"] = 42,
            ["3"] = 54,
            ["4"] = 72,
            ["5"] = 90,
            ["6"] = 108,
            ["7"] = 132,
            ["8"] = 156,
            ["9"] = 180,
        },
        ["boss"] = {
            ["1"] = 150,
            ["2"] = 210,
            ["3"] = 270,
            ["4"] = 360,
            ["5"] = 450,
            ["6"] = 540,
            ["7"] = 660,
            ["8"] = 780,
            ["9"] = 900,
        },
    },
}
