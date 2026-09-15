--- xlik 测试流程。
local process = Process("test")

function process:onStart()
    if JiuDou and JiuDou.bootstrap then
        JiuDou.bootstrap.start()
    end
end
