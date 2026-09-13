--- 随机选将界面资源索引。
--- 所有路径均指向地图内 ui/selectHero 目录，文字由 Lua 动态渲染而不写入图片。
local module = {}

local IMPORT_ROOT = "ui\\selectHero\\"

---@class HeroSelectAssetPaths
---@field panel string 居中弹窗边框
---@field cardNormal string 普通英雄卡牌
---@field cardSelected string 已选中英雄卡牌
---@field detail string 技能说明底框
---@field timer string 倒计时边框
---@field refresh string 刷新按钮贴图
---@field confirm string 确认按钮贴图
---@type HeroSelectAssetPaths
module.PATHS = {
    panel = IMPORT_ROOT .. "panel-v4.blp",
    cardNormal = IMPORT_ROOT .. "card-normal-v2.blp",
    cardSelected = IMPORT_ROOT .. "card-selected-v3.blp",
    detail = IMPORT_ROOT .. "skill-detail-v2.blp",
    timer = IMPORT_ROOT .. "timer-v2.blp",
    refresh = IMPORT_ROOT .. "button-refresh.blp",
    confirm = IMPORT_ROOT .. "button-confirm.blp",
}

return module
