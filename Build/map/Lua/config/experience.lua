--- 本文件由 generate_lua_config.ps1 自动生成，请勿手工修改。
--- 数据源来自 excelCfg 配置表；请修改 Excel 后重新执行生成工具。
---@class ExperienceSettings
---@field maxLevel integer 英雄最大等级
---@field initialExpBonusPercent integer 初始经验加成百分比
---@field maxExpBonusPercent integer 经验加成上限百分比
---@class ExperienceLevelConfig
---@field levelId string 等级配置 ID
---@field level integer 英雄等级
---@field requiredExp integer 升到下一级所需经验
---@class ExperienceConfig
---@field version integer 配置版本
---@field settings ExperienceSettings
---@field levels table<string, ExperienceLevelConfig> 等级配置
return {
    ["version"] = 1,
    ["settings"] = {
        ["maxLevel"] = 25,
        ["initialExpBonusPercent"] = 0,
        ["maxExpBonusPercent"] = 100,
    },
    ["levels"] = {
        ["1"] = {
            ["levelId"] = "LEVEL_1",
            ["level"] = 1,
            ["requiredExp"] = 100,
        },
        ["2"] = {
            ["levelId"] = "LEVEL_2",
            ["level"] = 2,
            ["requiredExp"] = 120,
        },
        ["3"] = {
            ["levelId"] = "LEVEL_3",
            ["level"] = 3,
            ["requiredExp"] = 140,
        },
        ["4"] = {
            ["levelId"] = "LEVEL_4",
            ["level"] = 4,
            ["requiredExp"] = 160,
        },
        ["5"] = {
            ["levelId"] = "LEVEL_5",
            ["level"] = 5,
            ["requiredExp"] = 190,
        },
        ["6"] = {
            ["levelId"] = "LEVEL_6",
            ["level"] = 6,
            ["requiredExp"] = 220,
        },
        ["7"] = {
            ["levelId"] = "LEVEL_7",
            ["level"] = 7,
            ["requiredExp"] = 250,
        },
        ["8"] = {
            ["levelId"] = "LEVEL_8",
            ["level"] = 8,
            ["requiredExp"] = 280,
        },
        ["9"] = {
            ["levelId"] = "LEVEL_9",
            ["level"] = 9,
            ["requiredExp"] = 320,
        },
        ["10"] = {
            ["levelId"] = "LEVEL_10",
            ["level"] = 10,
            ["requiredExp"] = 360,
        },
        ["11"] = {
            ["levelId"] = "LEVEL_11",
            ["level"] = 11,
            ["requiredExp"] = 400,
        },
        ["12"] = {
            ["levelId"] = "LEVEL_12",
            ["level"] = 12,
            ["requiredExp"] = 450,
        },
        ["13"] = {
            ["levelId"] = "LEVEL_13",
            ["level"] = 13,
            ["requiredExp"] = 500,
        },
        ["14"] = {
            ["levelId"] = "LEVEL_14",
            ["level"] = 14,
            ["requiredExp"] = 550,
        },
        ["15"] = {
            ["levelId"] = "LEVEL_15",
            ["level"] = 15,
            ["requiredExp"] = 600,
        },
        ["16"] = {
            ["levelId"] = "LEVEL_16",
            ["level"] = 16,
            ["requiredExp"] = 660,
        },
        ["17"] = {
            ["levelId"] = "LEVEL_17",
            ["level"] = 17,
            ["requiredExp"] = 720,
        },
        ["18"] = {
            ["levelId"] = "LEVEL_18",
            ["level"] = 18,
            ["requiredExp"] = 780,
        },
        ["19"] = {
            ["levelId"] = "LEVEL_19",
            ["level"] = 19,
            ["requiredExp"] = 840,
        },
        ["20"] = {
            ["levelId"] = "LEVEL_20",
            ["level"] = 20,
            ["requiredExp"] = 900,
        },
        ["21"] = {
            ["levelId"] = "LEVEL_21",
            ["level"] = 21,
            ["requiredExp"] = 970,
        },
        ["22"] = {
            ["levelId"] = "LEVEL_22",
            ["level"] = 22,
            ["requiredExp"] = 1040,
        },
        ["23"] = {
            ["levelId"] = "LEVEL_23",
            ["level"] = 23,
            ["requiredExp"] = 1110,
        },
        ["24"] = {
            ["levelId"] = "LEVEL_24",
            ["level"] = 24,
            ["requiredExp"] = 1180,
        },
        ["25"] = {
            ["levelId"] = "LEVEL_25",
            ["level"] = 25,
            ["requiredExp"] = 0,
        },
    },
}
