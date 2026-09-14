--- 本文件由 generate_lua_config.ps1 自动生成，请勿手工修改。
--- 数据源来自 excelCfg 配置表；请修改 Excel 后重新执行生成工具。
---@class GoldSettings
---@field initialGold integer 本局初始金币
---@field maxGoldDropBonusPercent integer 金币掉落加成上限
---@field maxGold integer 原生金币上限
---@class GoldConfig
---@field settings GoldSettings 怪物金币奖励已写入 units.lua 的 goldRep 字段
return {
    ["settings"] = {
        ["initialGold"] = 0,
        ["maxGoldDropBonusPercent"] = 999,
        ["maxGold"] = 2147483647,
    },
}
