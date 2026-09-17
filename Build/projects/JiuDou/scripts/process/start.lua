--- xlik 地图启动流程。
local process = Process("start")

function process:onStart()
    -- 开局始终显示完整地形：关闭战争迷雾与未探索区域的黑色遮罩。
    fog.enable(false)
    fog.maskEnable(false)
    JiuDou.bootstrap.start()
end
