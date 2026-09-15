# JiuDou xlik 工作目录

本目录是 JiuDou 的 xlik-jade 工作区。地图输入目录只有：

```text
projects/JiuDou/w3x
```

常用命令：

```text
tools\xlik.exe run JiuDou -l
tools\xlik.exe run JiuDou -l!
tools\xlik.exe run JiuDou -t!
tools\xlik.exe run JiuDou -d!
tools\xlik.exe run JiuDou -r!
```

Excel 配置由工作区外的 `generate_lua_config.bat` 生成，旧工程基线保存在根目录 `legacy/Build` 和本目录 `legacy/`。

目录约定：`projects/JiuDou/scripts` 存放 JiuDou 的业务 Lua，当前业务模块位于
`scripts/globals/jiudou`，地图流程入口位于 `scripts/process`；
`projects/JiuDou/library` 仅用于项目级 xlik 扩展库。
