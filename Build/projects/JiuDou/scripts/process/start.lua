--- xlik 地图启动流程。
local process = Process("start")

function process:onStart()
    JiuDou.bootstrap.start()
end
