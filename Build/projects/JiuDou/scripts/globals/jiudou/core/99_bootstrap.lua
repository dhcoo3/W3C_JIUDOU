--- 兼容旧业务模块的统一启动适配层。
JiuDou = JiuDou or {}
JiuDou.bootstrap = JiuDou.bootstrap or {}

local function register_procedures()
    local procedure = JiuDou.core and JiuDou.core.procedure
    if procedure == nil then
        return false
    end

    if procedure.has("mode_select") then
        return true
    end

    procedure.register("boot", {
        enter = function()
            if JiuDou.core.log ~= nil then
                JiuDou.core.log.info("JiuDou Core 已启动")
            end
        end,
    })
    procedure.register("mode_select", {
        enter = function()
            local run_mode = JiuDou.gameplay
                and JiuDou.gameplay.runMode
                and JiuDou.gameplay.runMode.main
            if type(run_mode) ~= "table" or type(run_mode.start) ~= "function" then
                error("runMode.main 未完成自动加载")
            end
            -- 兼容当前 runMode 实现：状态机负责流程归属，runMode 继续负责业务细节。
            run_mode.start()
        end,
    })
    procedure.register("hero_select", {
        enter = function(context)
            if JiuDou.core.log ~= nil then
                JiuDou.core.log.info("进入英雄选择阶段")
            end
            context.mode = context.data
        end,
    })
    procedure.register("prepare", {
        enter = function()
            if JiuDou.core.log ~= nil then
                JiuDou.core.log.info("进入游戏准备阶段")
            end
        end,
    })
    procedure.register("running", {
        enter = function()
            if JiuDou.core.log ~= nil then
                JiuDou.core.log.info("进入游戏运行阶段")
            end
        end,
    })
    procedure.register("result", {
        enter = function()
            if JiuDou.core.log ~= nil then
                JiuDou.core.log.info("进入结算阶段")
            end
        end,
    })
    return true
end

function JiuDou.bootstrap.start()
    if not register_procedures() then
        print("JiuDou 启动失败：核心流程服务未完成加载")
        return false
    end

    local procedure = JiuDou.core.procedure
    local started = procedure.start("boot")
    if not started then
        return false
    end
    local changed, message = procedure.change("mode_select")
    if not changed then
        print("JiuDou 启动失败：无法进入模式选择阶段：" .. tostring(message))
        return false
    end
    return true
end
