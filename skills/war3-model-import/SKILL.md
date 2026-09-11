---
name: war3-model-import
description: Import Warcraft III MDX/BLP models into an LNI/w3x2lni map through a formal source-of-truth workflow, with optional isolated rehearsal, MDX texture repair, generated object data, pack/unpack verification, runtime checks, dependency reporting, and rollback.
---

# Warcraft III 正式模型导入

这是一个“正式导入” Skill。它把模型资源、单位物编源配置、生成结果、地图打包和游戏内验证串成一条可回滚的流程；临时副本是预演模式，不是最终交付物。

## 模式选择

- 用户明确说“正式导入、落地、替换正式模型、发布”时使用 `formal` 模式。
- 用户说“测试、试装、验证能否导入”时使用 `test` 模式，只操作 `.codex_tmp/<test-id>/`。
- 只提到“导入模型”但没有说明模式时，先做正式源配置探测和影响报告；在真正改正式文件前要求用户明确选择 `formal`。
- `formal` 模式可以修改正式源文件，但必须先做备份、记录 Git 状态、展示影响范围，并保留精确回滚点。

## 正式模式的源配置规则

先判断项目的真实 source of truth，不要把生成文件当源文件：

- 模型资源通常是正式 `Build/resource/models/<slug>/` 中的文件；
- 本项目的单位物编正式来源是 `excelCfg/unit.xlsx`；
- `Build/table/unit.ini`、`Build/map/Lua/config/*.lua` 等是 `generate_lua_config.bat` 的生成结果，正式模式不得直接手工修改；
- 本项目应通过 `generate_lua_config.bat` 生成配置，再使用项目已有的 `runmap.bat` 或正式构建命令打包；
- 若项目没有可识别的源配置或生成入口，停止并报告，不要猜测后直接改生成文件。

正式修改必须遵循：源配置 → 生成器 → 生成物检查 → 打包 → 游戏内验证。若项目的 source of truth 与上面不同，以项目文档和实际生成脚本为准，并在报告中说明。

## 不可违反的边界

- `formal` 模式只在用户明确授权正式修改时执行；普通分析、检查和测试不获得正式写权限。
- 修改前记录 `git status --short`，保留用户原有未提交改动，不使用 `git reset --hard`、`git checkout --` 或覆盖无关文件。
- 正式模式在 `.codex_tmp/war3-model-import-<id>/backup/` 保存所有受影响源文件的备份和哈希；至少包括 `unit.xlsx`、已有同名模型/贴图和正式测试地图。
- 测试模式只写临时副本；正式模式才写 `excelCfg`、正式 `Build/resource` 或正式生成输出。
- 只修复确认属于该模型的自定义贴图引用；原版贴图和可替换贴图槽保持原样并列入依赖报告。
- `unit.ini` 的 `file` 值不写 `.mdx` 扩展名；Excel 源值使用实际单反斜杠，例如 `models\heretic\Heretic`，生成器会按 LNI 语法转义。
- 未经用户明确要求，不改选将界面头像、英雄逻辑、技能逻辑或无关物编字段。
- 运行时窗口不可被 Computer Use 可靠获取时，停止 UI 操作并标记 `RUNTIME UNVERIFIED`；进程存在或静态打包成功不能冒充游戏内 PASS。

## 流程 A：正式导入

### 1. 预检和回滚点

收集并报告：项目根目录、`Build`、模型源目录、目标 Rawcode、`unit.xlsx`、生成脚本、`w2l.exe`、正式地图输出路径和当前 Git 状态。

创建本次操作目录：

```text
.codex_tmp/war3-model-import-<id>/
  backup/
  report.md
```

把将被修改的源文件复制到 `backup/`，记录 SHA-256；若工作树已有改动，记录并避开无关文件。正式模式不能以“之后清理临时副本”为理由删除源配置变化。

### 2. 导入正式资源

将模型和明确需要的自定义贴图放入：

```text
Build/resource/models/<slug>/<ModelName>.mdx
Build/resource/models/<slug>/<TextureName>.blp
```

若目标路径已有文件，先比较哈希；不同内容必须记录覆盖范围并保留备份。不能把同一资源重复嵌套成 `models/<slug>/models/<slug>/...`。

### 3. 修复 MDX 自定义贴图

先扫描 MDX 的 `TEXS` 纹理表，区分自定义贴图、Warcraft III 原版贴图和可替换贴图槽。使用随附脚本修改固定宽度的 260 字节路径字段，不插入字节、不扩大文件：

```text
node <skill-dir>\scripts\patch_mdx_texture.js <mdx> <source-texture> <map-texture-path>
```

例如：

```text
node skills\war3-model-import\scripts\patch_mdx_texture.js Build\resource\models\heretic\Heretic.mdx Heretic.blp models\heretic\Heretic.blp
```

脚本必须在 `TEXS` 中找到恰好一个源贴图名，目标路径短于 260 字节，且修改前后文件大小相同。把脚本 JSON 输出写入报告。

### 4. 修改正式物编源配置

本项目 `excelCfg/unit.xlsx` 的字段结构为：

```text
第 1 行：显示名称
第 2 行：类型（file 使用 string，modelScale 使用 real）
第 3 行：LNI 字段名（file、modelScale）
```

如果 `file` 和 `modelScale` 列不存在，正式模式应在 Excel 源表中新增这两列，再只修改目标 Rawcode 行；不要直接编辑生成的 `Build/table/unit.ini`。目标值示例：

```text
file: models\heretic\Heretic
modelScale: 1
```

使用可用的电子表格工具或项目既有 Excel 编辑方式，保留原有列、公式、格式和其他单位行。修改后做一次源表行级报告，确认 Rawcode、字段类型和数值没有错位。

### 5. 重新生成正式配置

在项目根目录运行正式生成入口：

```powershell
& '.\generate_lua_config.bat'
```

确认生成成功，并检查生成的 `Build/table/unit.ini`：目标段应包含 `file` 和 `modelScale`，路径与资源目录一致。不要直接把临时测试时手工写入的 `unit.ini` 当作正式结果。

### 6. 正式打包和静态验收

优先使用项目已有的构建入口；本项目通常使用：

```powershell
& '.\runmap.bat'
```

本项目的 `runmap.bat` 主要是测试构建/启动入口，会处理 `JiuDouTest.w3x`；它可以用于正式源配置的集成验收，但不能自动等同于正式发布。正式交付地图必须使用项目正式发布脚本或用户明确指定的输出路径。

如果只需要不启动游戏的构建，可在项目已有脚本基础上调用同版本 `w2l.exe`：

```powershell
& '<w2l.exe>' obj '<project>\Build'
```

确认：

- 生成地图命令退出码为 0；
- listfile 有 `models\<slug>\<ModelName>.mdx` 和对应 BLP；
- 没有错误的 `Heretic\Heretic.blp` 或重复目录；
- 解包后的 `war3map.w3u` 含目标 Rawcode、`umdl` 和预期模型路径；
- 生成物中的路径来自源配置，而不是残留的临时手工修改；
- 原版贴图依赖已列出，并区分“目标客户端必须提供”的依赖。

### 7. 正式运行时验收

用项目配置的 YDWE 或 Warcraft III 启动正式生成地图。每次 UI 操作前刷新并选择唯一目标窗口；截图、坐标和可访问性索引不可跨状态复用。

至少验证：

1. 目标英雄/单位可以创建并出现在正确位置；
2. Stand、Walk、Attack、Spell、Death/Decay 动画正常；
3. 主贴图正常显示，不是白模、黑模、透明模型或丢贴图；
4. 技能粒子、原版贴图依赖和单位技能仍正常；
5. 大小、朝向、出生位置和碰撞范围基本合理；
6. 没有模型消失、地图崩溃或其他回归。

运行时通过前，不得把正式导入标记为完成。窗口不可见、只打开配置程序或只能看到进程时，状态为 `FORMAL BUILD PASS / RUNTIME UNVERIFIED`。

### 8. 正式交付和回滚

正式验证通过后保留源文件、生成结果、模型依赖报告和备份索引；不自动提交 Git，除非用户明确要求。验证失败时只恢复本次备份涉及的文件，并再次检查用户原有改动没有被覆盖。

## 流程 B：隔离预演

测试模式复制到 `.codex_tmp/<test-id>/Build`，只在副本中写 `unit.ini`，按正式模式同样执行 MDX 静态检查、w2l 打包/解包和运行时验收。测试结束删除 `Build`、地图和解包目录，只保留审计报告；正式项目不得出现改动。

## 判定

- `PASS`：正式源配置、生成物、打包路径、目标单位创建、主贴图、主要动画、粒子和基础空间表现全部通过。
- `PASS WITH DEPENDENCY WARNING`：游戏内通过，但依赖目标环境可能没有的原版贴图；报告必须列出依赖和风险。
- `FAIL`：源配置生成失败、打包失败、路径错误、主贴图缺失、模型不可见、运行时崩溃或主要动画/粒子失败。
- `FORMAL BUILD PASS / RUNTIME UNVERIFIED`：正式源配置和地图构建通过，但没有可信的游戏画面或窗口控制证据；这是未完成交付，不得升级为 `PASS`。

## 二郎神 H0E0 示例

```text
mode: formal
rawcode: H0E0
unit-section: [H0E0]
model: Heretic.mdx
texture: Heretic.blp
resource-dir: Build/resource/models/heretic
file: models\heretic\Heretic
modelScale: 1
source-config: excelCfg/unit.xlsx
generator: generate_lua_config.bat
builder: runmap.bat
```

正式模式不检查头像，除非用户另行要求。
