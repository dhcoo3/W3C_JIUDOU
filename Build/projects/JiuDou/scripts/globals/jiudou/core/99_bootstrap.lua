--- 兼容旧业务模块的统一启动适配层。
JiuDou = JiuDou or {}
JiuDou.bootstrap = JiuDou.bootstrap or {}

function JiuDou.bootstrap.start()
    local run_mode = JiuDou.gameplay
        and JiuDou.gameplay.runMode
        and JiuDou.gameplay.runMode.main
    if type(run_mode) ~= "table" or type(run_mode.start) ~= "function" then
        print("JiuDou 启动失败：runMode.main 未完成自动加载")
        return false
    end
    return run_mode.start()
end
