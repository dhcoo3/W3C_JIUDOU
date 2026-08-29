--- Lua 根入口。
--- 负责初始化模块搜索路径并启动模式选择业务。
local console = require "jass.console"
console.enable = true
print = console.write

package.path = "Lua\\?.lua;Lua\\?\\init.lua;" .. package.path

local run_mode = require "runMode.main"
run_mode.start()
