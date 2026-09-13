# PVE 刷怪系统参考

本文按当前 `Build/map/Lua/monster/` 的实际实现整理，作为后续调参、排错和接入新功能的入口。Excel 是单位与玩法配置的数据源；`Build/table/` 和 `Build/map/Lua/config/` 中的文件由生成脚本产出，不要把生成文件当成长期手工维护源。

## 1. 启动与规模

英雄选择完成后，PVE 初始化流程最后启动刷怪系统；PVP 不会调用刷怪启动接口。开始刷怪前会校验 PVE 模式、等级、同步随机种子及 Warcraft 1.27 所需接口。缺少怪物属性接口时，刷怪会停止并在日志中列出缺失项。

| 类别 | 固定槽位 / 上限 | 首次生成 | 死亡后的处理 |
| --- | ---: | --- | --- |
| 普通怪 | 9 区 × 50 = 450 | 开局生成；每区近战约 70%、远程约 30% | 2 秒后原槽位补生，维持每区 50 槽 |
| 精英 | 9 区 × 3 点 = 27 | 开局生成 | 20 秒后原点复活，重新随机获得一个精英技能 |
| Boss | 9 个 | 从开局第 60 秒开始，每隔 60 秒按 1→9 顺序生成 | 不复活；后续 Boss 仍按时间继续生成 |
| 特殊怪 | 全图最多 300 只 | 普通怪或精英被击杀时概率生成 | 死亡或存活 20 秒后移除，不复活、不链式召唤 |

开局普通怪和精英总数为 477。首波按每批 6 只、每批间隔 0.04 秒分帧创建，并优先处理玩家所在区域，避免同一帧集中创建全部单位。Boss 不属于首波；第一只在刷怪计时开始约 60 秒时出现。

## 2. 区域、单位与行为

- 普通怪在 `Map_Block_1` 至 `Map_Block_9` 内取可行走随机位置。每区复用该区自己的近战和远程 Rawcode（`N1M1/N1R1` 至 `N9M1/N9R1`）。
- 精英点按 `MonsterPoint_区域_序号` 读取，共 27 个点。点位区域内随机坐标生成；技能池是 `A9S1` 至 `A9S8`，每次生成/复活随机选一个。被动技能只挂载物编技能；能被 AI 识别的主动技能由刷怪 AI 自动施放。
- Boss `B1M1` 至 `B9M1` 固定对应 `BossPoint_1` 至 `BossPoint_9`，在点位区域中心生成。Boss 技能配置来自单位物编；刷怪 AI 自动施放 `monster/config.lua` 中登记了施法命令、目标类型和范围的主动技能。
- 所有怪物使用中立敌对玩家。每 0.5 秒按稳定槽位顺序检查存活英雄，只攻击其所属区域内最近的英雄；区域内没有可攻击英雄时，怪物放弃追击并返回出生点。技能被动效果由 Warcraft 物编负责。

金币怪 `G0M1` 和经验怪 `X0M1` 是全图共用的两个单位，不按区域复制 Rawcode。它们的模型和战斗基础属性可在单位表中单独调整；生成时使用出生区域对应的难度与奖励数据。

## 3. 难度与怪物属性

PVE 普通/困难模式及 1–10 级的实际倍率来自 `excelCfg/monster_scaling.xlsx`。运行时按生成配置逐档读取，不在 Lua 中临时推导另一份倍率。生命、攻击基础值向上取整：

```text
最终生命 = ceil(物编基础生命 × healthMultiplier / 10)
最终攻击基础值 = ceil(物编攻击加值 × attackMultiplier / 10)
最终护甲 = 物编基础护甲 + armorBonus
```

攻击骰子数量和骰面保持单位物编值。Warcraft 1.27 没有使用 `BlzSetUnit*`：系统通过 `UnitAddAbility`、`SetUnitAbilityLevel` 添加隐藏物品属性技能，并用 `SetUnitState` 在生命加成后回满生命。当前生成的难度技能共有 385 个：每个 38 种怪物单位对应 5 组生命和攻击技能（共 380 个），另有 5 个护甲技能。

以当前生成数据为准：普通模式 1 级倍率 1.0、10 级 1.9；困难模式 1 级 1.5、10 级 **2.9**。倍率按十分之一档配置，所以困难 10 级实际读取的是 2.9，而不是未量化公式中的 2.85。金币和经验倍率也各自从难度表读取，不要由生命倍率代替。

## 4. Boss 与“天灾”效果

Boss 出现时会同时触发：共享该 Boss 当前视野给本局 PVE 玩家、小地图位置提示、屏幕“天灾降临”美术字，以及显示 8 秒的 Warcraft 默认文字公告。美术字是本地 UI，不参与同步计算；小地图提示持续时间配置为 5 秒。

Boss 物编和词缀数据在 `excelCfg/boss_affix.xlsx`。当前 9 个词缀编号及名称：

| 编号 | 名称 | 编号 | 名称 | 编号 | 名称 |
| --- | --- | --- | --- | --- | --- |
| B1 | 狼王疾猎 | B2 | 熔火狂攻 | B3 | 叛军战旗 |
| B4 | 五行岩甲 | B5 | 统帅军势 | B6 | 混世复苏 |
| B7 | 幽冥重击 | B8 | 极寒霜袭 | B9 | 混沌蚀魔 |

新生成的普通、精英和特殊怪会从当前存活 Boss 的词缀池中继承一个词缀；已生成的怪不会因 Boss 后续死亡而重新计算。带词缀的怪会挂载相应技能/状态图标，并在头顶显示持续特效。

> 当前实现细节：词缀池会收集**所有**存活 Boss，没有“最多 3 个最早存活 Boss”的限制。存活 Boss 为 1 只时直接使用该词缀；达到 2 只或更多时，每只新怪从完整存活池中独立随机选 1 个。若设计仍要求最多 3 个，则应修改 `monster/main.lua` 的 `collect_alive_boss_affixes()`，不能只改本说明。

## 5. 特殊怪生成、奖励与概率接口

普通怪死亡时分别独立掷两次概率：金币怪 10%、经验怪 10%。精英死亡时只判定金币怪，基础概率 50%；Boss 和特殊怪死亡不召唤。金币怪包每次 3 只，精英金币怪包 5 只；经验怪包 3 只。普通怪的金币与经验两次判定可以同时成功，因此可能同时生成两种怪物包。

| 类型 | 基础概率 | 可由接口增加 | 当前概率上限 | 奖励 |
| --- | ---: | ---: | ---: | --- |
| 普通怪 → 金币怪 | 10% | 0–20 个百分点 | 30% | 与出生区域普通怪相同的金币奖励，不给经验 |
| 普通怪 → 经验怪 | 10% | 0–20 个百分点 | 30% | 出生区域普通怪基础经验的 2 倍，不给金币 |
| 精英 → 金币怪 | 50% | 0–30 个百分点 | 80% | 与该区域普通怪相同的金币奖励，不给经验 |

加成按玩家个人属性计算，以最后一击玩家为判定对象；没有有效 PVE 玩家击杀时不生成。奖励系统仍按已有的难度倍率、玩家奖励加成和有效伤害参与者结算。生成点靠近死亡位置，限制在所属 `Map_Block` 内；超出全图 300 只上限时跳过无法完整容纳的整个包，并向击杀者提示。特殊怪计数在生成、死亡和自然移除时更新，右上角显示为“特殊怪：当前数/300”。TAB 属性详情页显示个人概率加成和当前普通/精英召唤率。

未来商城接入使用 `monster.special_spawn` 的来源接口，不必为道具另建特殊怪单位：

```lua
local special_spawn = require "monster.special_spawn"

-- 仅 Player(0)（同步房主）调用；percentagePoints 是百分点整数。
special_spawn.set_bonus_source(playerId, "store:特殊怪生成概率", 10)
special_spawn.clear_bonus_source(playerId, "store:特殊怪生成概率")
```

同一个 `sourceId` 重复设置会覆盖，不会重复叠加；不同来源相加后总加成封顶 +30 个百分点。接口会向所有客户端广播玩家加成的绝对值。多来源接入时，应使用稳定且互不重复的 `sourceId`；当前没有商城道具实现。

提示原文：金币怪为“敌人在死亡时召唤了 N 只携带大量金钱的恶魔。”；经验怪为“敌人在死亡时召唤了 3 只携带大量经验的恶魔。”仅击杀者本地显示。

## 6. 多人同步与性能要点

- 英雄选择 `FINAL` 消息同步本局 `sessionSeed`；各客户端据此独立模拟相同刷怪结果。英雄按玩家编号排序。
- 刷怪随机数由 `monster/random.lua` 提供，使用同步种子派生出的确定性随机流；单位类型、位置、朝向、精英技能、词缀和特殊怪判定都不调用 Warcraft `GetRandomInt`。
- 普通怪、精英、Boss 槽位和特殊怪子槽位按稳定键顺序处理。固定节拍器每 0.25 秒检查复活、Boss 到期生成及特殊怪超时；AI 每 0.5 秒更新。死亡事件和这些定时操作由所有客户端同步执行。
- Player(0) 离开不应中断种子同步后的常规刷怪、复活或 Boss 时序；但未来概率加成的更新接口是 Player(0) 权威广播，房主离开后不能再通过该接口发布新的商城加成。
- 不为每只怪单独创建轮询计时器，也不每 0.03 秒扫描全图。主要工作量是 0.25 秒调度扫描固定槽位，以及每 0.5 秒为存活怪物寻找区域内最近英雄；特殊怪另受 300 只上限和 20 秒寿命限制。
- 右上角计数、屏幕美术字、公告文本属于显示层，不应添加随机数或修改同步游戏状态。

调试日志会在首波完成后输出“PVE 刷怪状态摘要”，包含种子、tick、各类存活数、槽位数和摘要哈希。多人对测时比较各端相同时间点的摘要；如果不同，先检查是否有客户端单独调用随机接口、客户端本地条件影响创建、配置文件未重新生成，或同步死亡/计时逻辑发生分歧。

## 7. 后续修改入口

| 想调整的内容 | 数据/代码入口 | 修改后操作 |
| --- | --- | --- |
| 普通怪、精英、Boss、金币怪、经验怪单位名称/模型/属性/经验 | [`excelCfg/unit.xlsx`](../excelCfg/unit.xlsx) | 重新生成配置并构建地图 |
| 1–10 级生命/攻击/护甲/金币/经验倍率 | [`excelCfg/monster_scaling.xlsx`](../excelCfg/monster_scaling.xlsx) | 重新生成配置并构建地图 |
| Boss 词缀定义 | [`excelCfg/boss_affix.xlsx`](../excelCfg/boss_affix.xlsx) | 重新生成配置并构建地图 |
| 普通怪数、复活时间、精英点数、Boss 间隔、AI/调度节拍、特殊怪上限和寿命 | [`monster/config.lua`](../Build/map/Lua/monster/config.lua) | 改 Lua 后构建地图 |
| 普通/精英/Boss/特殊怪生成、索敌、奖励注册、Boss 词缀继承 | [`monster/main.lua`](../Build/map/Lua/monster/main.lua) | 改 Lua 后构建并实测多人同步 |
| 特殊怪概率上限、基础概率、来源加成和同步 | [`monster/special_spawn.lua`](../Build/map/Lua/monster/special_spawn.lua)、[`monster/special_spawn_sync.lua`](../Build/map/Lua/monster/special_spawn_sync.lua) | 改后测试双客户端及房主离开行为 |
| 特殊怪难度属性实现 | [`platform/monster_stats.lua`](../Build/map/Lua/platform/monster_stats.lua) 与难度表生成器 | 不要手改生成的属性技能；重新生成配置 |
| TAB 概率详情、右上角数量 UI、Boss 美术字 | [`hero/ui/attributes.lua`](../Build/map/Lua/hero/ui/attributes.lua)、[`monster/ui/special_count.lua`](../Build/map/Lua/monster/ui/special_count.lua)、[`monster/ui/cataclysm.lua`](../Build/map/Lua/monster/ui/cataclysm.lua) | 改 UI 后构建地图并在游戏内验收 |

生成器会将物编 `.ini` 写入 `Build/table/`，生成的 Lua 配置写入 `Build/map/Lua/config/`。修改 Excel 后先运行项目根目录的 `generate_lua_config.bat`；`runmap.bat` 会重新生成配置、构建 `Build/JiuDouTest.w3x` 并尝试启动测试地图。不要直接编辑生成的 `Build/table/*.ini` 或 `Build/map/Lua/config/*.lua`，否则下一次生成会覆盖修改。

## 8. 相关源文件

- [刷怪入口与主循环](../Build/map/Lua/monster/main.lua)
- [刷怪配置和区域映射](../Build/map/Lua/monster/config.lua)
- [确定性随机数](../Build/map/Lua/monster/random.lua)
- [特殊怪个人概率属性](../Build/map/Lua/monster/special_spawn.lua)
- [1.27 隐藏技能属性适配](../Build/map/Lua/platform/monster_stats.lua)
- [PVE 启动流程](../Build/map/Lua/runMode/main.lua)
- [Boss 词缀生成配置](../Build/map/Lua/config/boss_affixes.lua)（生成文件，仅供查看）
- [怪物单位物编](../Build/table/unit.ini)（生成文件，仅供查看）
- [技能物编](../Build/table/ability.ini)（生成文件，仅供查看）
