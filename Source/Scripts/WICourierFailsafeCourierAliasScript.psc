Scriptname WICourierFailsafeCourierAliasScript extends ReferenceAlias
{Optional helper that can be attached to the vanilla WICourier Courier alias.}

WICourierFailsafeScript Property FailsafeQuest Auto

Event OnPackageStart(Package akNewPackage)
	KickFailsafe()
EndEvent

Event OnPackageChange(Package akOldPackage)
	KickFailsafe()
EndEvent

Event OnPackageEnd(Package akOldPackage)
	KickFailsafe()
EndEvent

Event OnCellAttach()
	KickFailsafe()
EndEvent

Event OnLocationChange(Location akOldLoc, Location akNewLoc)
	KickFailsafe()
EndEvent

Function KickFailsafe()
	If FailsafeQuest
		FailsafeQuest.Kick()
	EndIf
EndFunction
