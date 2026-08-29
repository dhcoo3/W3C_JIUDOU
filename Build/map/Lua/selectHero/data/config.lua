--- 随机选将配置层。
--- 负责候选数量、刷新额度、玩家范围和出生区域等只读数据。
local regions = require "config.regions"

local module = {}

---@class HeroSelectSettings
---@field candidateCount integer 每次展示的候选英雄数量
---@field durationSeconds integer 每轮选将的倒计时秒数
---@field freeRefreshCount integer 每位玩家默认拥有的免费刷新次数
---@field maxPlayerCount integer 地图允许参与选将的最大玩家数量
---@field spawnInset number 出生坐标与区域边缘的最小距离
---@type HeroSelectSettings
module.SETTINGS = {
    candidateCount = 3,
    durationSeconds = 20,
    freeRefreshCount = 1,
    maxPlayerCount = 10,
    spawnInset = 160.0,
}

---@class HeroSpawnBlock
---@field id integer 区域编号
---@field name string 区域名称
---@field minX number 区域左边界
---@field minY number 区域下边界
---@field maxX number 区域右边界
---@field maxY number 区域上边界

local SPAWN_REGION_NAMES = {
    "Map_Block_1",
    "Map_Block_2",
    "Map_Block_3",
    "Map_Block_4",
    "Map_Block_5",
    "Map_Block_6",
    "Map_Block_7",
    "Map_Block_8",
    "Map_Block_9",
}

---@type HeroSpawnBlock[]
module.SPAWN_BLOCKS = {}
for block_id, region_name in ipairs(SPAWN_REGION_NAMES) do
    local region = regions[region_name]
    if region == nil then
        error("选将出生区不存在：" .. region_name)
    end

    table.insert(module.SPAWN_BLOCKS, {
        id = block_id,
        name = region_name,
        minX = region.minX,
        minY = region.minY,
        maxX = region.maxX,
        maxY = region.maxY,
    })
end

--- 按编号获取出生区域。
---@param block_id integer 区域编号
---@return HeroSpawnBlock|nil block 对应区域；不存在时为空
function module.get_spawn_block(block_id)
    for block_index, block in ipairs(module.SPAWN_BLOCKS) do
        if block.id == block_id then
            return block
        end
    end

    return nil
end

return module
