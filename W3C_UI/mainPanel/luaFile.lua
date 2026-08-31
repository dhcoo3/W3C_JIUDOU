DefIcon = nil 
TriggerDefIcon = nil 
StrName = nil 
TriggerStrName = nil 
AtkIcon = nil 
TriggerAtkIcon = nil 
AttrIcon = nil 
TriggerAttrIcon = nil 
ExpBar = nil 
TriggerExpBar = nil 
IntName = nil 
TriggerIntName = nil 
AgiName = nil 
TriggerAgiName = nil 
DefName = nil 
TriggerDefName = nil 
DefVal = nil 
TriggerDefVal = nil 
StrVal = nil 
TriggerStrVal = nil 
AtkName = nil 
TriggerAtkName = nil 
AtkVal = nil 
TriggerAtkVal = nil 
IntVal = nil 
TriggerIntVal = nil 
AgiVal = nil 
TriggerAgiVal = nil 
REFORGEDUIMAKER = {}
REFORGEDUIMAKER.Initialize = function()


DefIcon = BlzCreateFrameByType("BACKDROP", "BACKDROP", BlzGetOriginFrame(ORIGIN_FRAME_GAME_UI, 0), "", 1)
BlzFrameSetAbsPoint(DefIcon, FRAMEPOINT_TOPLEFT, 0.314350, 0.0516300)
BlzFrameSetAbsPoint(DefIcon, FRAMEPOINT_BOTTOMRIGHT, 0.340620, 0.0244800)
BlzFrameSetTexture(DefIcon, "CustomFrame.png", 0, true)

StrName = BlzCreateFrameByType("TEXT", "name", BlzGetOriginFrame(ORIGIN_FRAME_GAME_UI, 0), "", 0)
BlzFrameSetAbsPoint(StrName, FRAMEPOINT_TOPLEFT, 0.440820, 0.0809900)
BlzFrameSetAbsPoint(StrName, FRAMEPOINT_BOTTOMRIGHT, 0.496040, 0.0649700)
BlzFrameSetText(StrName, "|cffFFCC00力量:|r")
BlzFrameSetEnable(StrName, false)
BlzFrameSetScale(StrName, 0.715)
BlzFrameSetTextAlignment(StrName, TEXT_JUSTIFY_TOP, TEXT_JUSTIFY_LEFT)

AtkIcon = BlzCreateFrameByType("BACKDROP", "BACKDROP", BlzGetOriginFrame(ORIGIN_FRAME_GAME_UI, 0), "", 1)
BlzFrameSetAbsPoint(AtkIcon, FRAMEPOINT_TOPLEFT, 0.314350, 0.0823100)
BlzFrameSetAbsPoint(AtkIcon, FRAMEPOINT_BOTTOMRIGHT, 0.341520, 0.0538200)
BlzFrameSetTexture(AtkIcon, "CustomFrame.png", 0, true)

AttrIcon = BlzCreateFrameByType("BACKDROP", "BACKDROP", BlzGetOriginFrame(ORIGIN_FRAME_GAME_UI, 0), "", 1)
BlzFrameSetAbsPoint(AttrIcon, FRAMEPOINT_TOPLEFT, 0.409200, 0.0658700)
BlzFrameSetAbsPoint(AttrIcon, FRAMEPOINT_BOTTOMRIGHT, 0.436810, 0.0396100)
BlzFrameSetTexture(AttrIcon, "CustomFrame.png", 0, true)

ExpBar = BlzCreateFrameByType("SIMPLESTATUSBAR", "name", BlzGetOriginFrame(ORIGIN_FRAME_GAME_UI, 0), "", 0)
BlzFrameSetTexture(ExpBar, "CustomFrame.png", 0, true)
BlzFrameSetAbsPoint(ExpBar, FRAMEPOINT_TOPLEFT, 0.312120, 0.101040)
BlzFrameSetAbsPoint(ExpBar, FRAMEPOINT_BOTTOMRIGHT, 0.495600, 0.0876900)
BlzFrameSetValue(ExpBar, 100)

IntName = BlzCreateFrameByType("TEXT", "name", BlzGetOriginFrame(ORIGIN_FRAME_GAME_UI, 0), "", 0)
BlzFrameSetAbsPoint(IntName, FRAMEPOINT_TOPLEFT, 0.440380, 0.0369300)
BlzFrameSetAbsPoint(IntName, FRAMEPOINT_BOTTOMRIGHT, 0.510300, 0.0240200)
BlzFrameSetText(IntName, "|cffFFCC00智力|r")
BlzFrameSetEnable(IntName, false)
BlzFrameSetScale(IntName, 0.715)
BlzFrameSetTextAlignment(IntName, TEXT_JUSTIFY_TOP, TEXT_JUSTIFY_LEFT)

AgiName = BlzCreateFrameByType("TEXT", "name", BlzGetOriginFrame(ORIGIN_FRAME_GAME_UI, 0), "", 0)
BlzFrameSetAbsPoint(AgiName, FRAMEPOINT_TOPLEFT, 0.440380, 0.0578600)
BlzFrameSetAbsPoint(AgiName, FRAMEPOINT_BOTTOMRIGHT, 0.484910, 0.0462900)
BlzFrameSetText(AgiName, "|cffFFCC00敏捷|r")
BlzFrameSetEnable(AgiName, false)
BlzFrameSetScale(AgiName, 0.715)
BlzFrameSetTextAlignment(AgiName, TEXT_JUSTIFY_TOP, TEXT_JUSTIFY_LEFT)

DefName = BlzCreateFrameByType("TEXT", "name", DefIcon, "", 0)
BlzFrameSetAbsPoint(DefName, FRAMEPOINT_TOPLEFT, 0.347750, 0.0493900)
BlzFrameSetAbsPoint(DefName, FRAMEPOINT_BOTTOMRIGHT, 0.390950, 0.0378200)
BlzFrameSetText(DefName, "|cffFFCC00防御力:|r")
BlzFrameSetEnable(DefName, false)
BlzFrameSetScale(DefName, 0.715)
BlzFrameSetTextAlignment(DefName, TEXT_JUSTIFY_TOP, TEXT_JUSTIFY_LEFT)

DefVal = BlzCreateFrameByType("TEXT", "name", DefIcon, "", 0)
BlzFrameSetAbsPoint(DefVal, FRAMEPOINT_TOPLEFT, 0.348190, 0.0369400)
BlzFrameSetAbsPoint(DefVal, FRAMEPOINT_BOTTOMRIGHT, 0.391830, 0.0253700)
BlzFrameSetText(DefVal, "|cffffffff20|r")
BlzFrameSetEnable(DefVal, false)
BlzFrameSetScale(DefVal, 0.572)
BlzFrameSetTextAlignment(DefVal, TEXT_JUSTIFY_TOP, TEXT_JUSTIFY_LEFT)

StrVal = BlzCreateFrameByType("TEXT", "name", StrName, "", 0)
BlzFrameSetAbsPoint(StrVal, FRAMEPOINT_TOPLEFT, 0.445280, 0.0703100)
BlzFrameSetAbsPoint(StrVal, FRAMEPOINT_BOTTOMRIGHT, 0.515200, 0.0605200)
BlzFrameSetText(StrVal, "|cffffffff100|r")
BlzFrameSetEnable(StrVal, false)
BlzFrameSetScale(StrVal, 0.572)
BlzFrameSetTextAlignment(StrVal, TEXT_JUSTIFY_TOP, TEXT_JUSTIFY_LEFT)

AtkName = BlzCreateFrameByType("TEXT", "name", AtkIcon, "", 0)
BlzFrameSetAbsPoint(AtkName, FRAMEPOINT_TOPLEFT, 0.346860, 0.0801200)
BlzFrameSetAbsPoint(AtkName, FRAMEPOINT_BOTTOMRIGHT, 0.385160, 0.0560800)
BlzFrameSetText(AtkName, "|cffFFCC00攻击力:|r")
BlzFrameSetEnable(AtkName, false)
BlzFrameSetScale(AtkName, 0.715)
BlzFrameSetTextAlignment(AtkName, TEXT_JUSTIFY_TOP, TEXT_JUSTIFY_LEFT)

AtkVal = BlzCreateFrameByType("TEXT", "name", AtkIcon, "", 0)
BlzFrameSetAbsPoint(AtkVal, FRAMEPOINT_TOPLEFT, 0.347750, 0.0676500)
BlzFrameSetAbsPoint(AtkVal, FRAMEPOINT_BOTTOMRIGHT, 0.390060, 0.0551900)
BlzFrameSetText(AtkVal, "|cffffffff1000|r")
BlzFrameSetEnable(AtkVal, false)
BlzFrameSetScale(AtkVal, 0.572)
BlzFrameSetTextAlignment(AtkVal, TEXT_JUSTIFY_TOP, TEXT_JUSTIFY_LEFT)

IntVal = BlzCreateFrameByType("TEXT", "name", IntName, "", 0)
BlzFrameSetAbsPoint(IntVal, FRAMEPOINT_TOPLEFT, 0.445280, 0.0253700)
BlzFrameSetAbsPoint(IntVal, FRAMEPOINT_BOTTOMRIGHT, 0.504510, 0.0151300)
BlzFrameSetText(IntVal, "|cffffffff100|r")
BlzFrameSetEnable(IntVal, false)
BlzFrameSetScale(IntVal, 0.572)
BlzFrameSetTextAlignment(IntVal, TEXT_JUSTIFY_TOP, TEXT_JUSTIFY_LEFT)

AgiVal = BlzCreateFrameByType("TEXT", "name", AgiName, "", 0)
BlzFrameSetAbsPoint(AgiVal, FRAMEPOINT_TOPLEFT, 0.444390, 0.0469700)
BlzFrameSetAbsPoint(AgiVal, FRAMEPOINT_BOTTOMRIGHT, 0.514750, 0.0371800)
BlzFrameSetText(AgiVal, "|cffffffff100|r")
BlzFrameSetEnable(AgiVal, false)
BlzFrameSetScale(AgiVal, 0.572)
BlzFrameSetTextAlignment(AgiVal, TEXT_JUSTIFY_TOP, TEXT_JUSTIFY_LEFT)
end
