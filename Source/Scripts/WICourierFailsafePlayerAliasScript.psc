Scriptname WICourierFailsafePlayerAliasScript extends ReferenceAlias
{Player alias helper for WICourierFailsafeScript.}

WICourierFailsafeScript Property FailsafeQuest Auto

Event OnInit()
	KickFailsafe()
EndEvent

Event OnPlayerLoadGame()
	KickFailsafe()
EndEvent

Event OnLocationChange(Location akOldLoc, Location akNewLoc)
	KickFailsafe()
EndEvent

Event OnPlayerFastTravelEnd(Float afTravelGameTimeHours)
	KickFailsafe()
EndEvent

Function KickFailsafe()
	If FailsafeQuest
		FailsafeQuest.Kick()
	EndIf
EndFunction
