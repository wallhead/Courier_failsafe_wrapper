Scriptname WICourierFailsafeScript extends Quest
{Background watchdog for the vanilla WICourier quest.}

Quest Property WICourierQuest Auto
{Vanilla WICourier quest.}

WICourierScript Property CourierSystem Auto
{Vanilla WICourierScript attached to WICourier.}

ObjectReference Property CourierContainer Auto
{Vanilla WICourierContainerRef. Used as a fallback if CourierSystem is unavailable.}

ReferenceAlias Property CourierAlias Auto
{Optional: vanilla WICourier courier alias.}

Actor Property PlayerRef Auto
{Player reference.}

GlobalVariable Property WICourierItemCount Auto
{Vanilla WICourierItemCount global.}

Float Property CheckInterval = 30.0 Auto
{Seconds between watchdog checks.}

Float Property SoftResetTime = 90.0 Auto
{Seconds without progress before package/quest retry.}

Float Property StartupGraceTime = 60.0 Auto
{Seconds to let vanilla story manager start or restart WICourier after pending items appear.}


Float Property ForceDeliverTime = 300.0 Auto
{Seconds without progress before direct handoff.}

Float Property CloseDeliveryTime = 90.0 Auto
{Seconds courier can remain near the player with pending items before direct handoff is allowed.}

Float Property ApproachDistance = 700.0 Auto
{Courier is considered close enough at this distance.}


Float Property ProgressTolerance = 128.0 Auto
{Distance improvement required to count as progress.}

Bool Property AllowDirectDelivery = True Auto
{If true, final failsafe moves courier container contents to the player.}

Bool Property RequireSafeWorldForForceDelivery = True Auto
{If true, active failsafe actions wait until the player is outside, out of combat, and not in menu/dialogue.}

Bool Property DebugMode = False Auto
{If true, shows in-game notifications when the failsafe acts.}

Bool Property LogOnlyMode = False Auto
{If true, only logs courier state and never changes the courier quest, actor, packages, or inventory.}

Bool Property LogEnabled = True Auto
{If true, writes to the named Papyrus user log.}

Bool Property LogEveryCheck = False Auto
{If true, writes every watchdog check and result.}

String Property LogName = "WICourierFailsafe" Auto
{Papyrus user log name.}

String Property ForceDeliveryMessage = "Курьер устал бегать за вами и прислал письма почтой. Не забудьте прочитать их в инвентаре!" Auto
{Shown when the failsafe directly delivers courier items.}

Float LastProgressTime = 0.0
Float DeliveryStartTime = 0.0
Float LastCloseTime = 0.0
Float BadStateStartTime = 0.0
Float QueuedDelay = 0.0
Float LastDistance = -1.0
Bool DeliveryActive = False
Bool UpdateQueued = False
Bool Busy = False
Bool LogOpened = False
Bool LogOpenAttempted = False
Int LastActionLevel = 0
Int CheckCount = 0

Event OnInit()
	OpenFailsafeLog()
	WriteLog("INIT: watchdog initialized")
	QueueCheck(5.0)
EndEvent

Event OnUpdate()
	UpdateQueued = False
	QueuedDelay = 0.0

	If Busy
		WriteLog("UPDATE: skipped because previous check is still busy")
		QueueCheck(CheckInterval)
		Return
	EndIf

	Busy = True
	MonitorCourier()
	Busy = False

	QueueCheck(CheckInterval)
EndEvent

Function Kick()
	WriteLog("KICK: immediate check requested")
	QueueCheck(1.0)
EndFunction

Function MonitorCourier()
	CheckCount += 1

	If PlayerRef == None
		PlayerRef = Game.GetPlayer()
		WriteLog("CHECK " + CheckCount + ": PlayerRef property was empty; using Game.GetPlayer()")
	EndIf

	Int pendingItems = GetPendingItemCount()
	Bool questRunning = False
	If WICourierQuest
		questRunning = WICourierQuest.IsRunning()
	EndIf

	Actor courier = GetCourierActor()
	Float nowTime = Utility.GetCurrentRealTime()

	If LogEveryCheck
		WriteLog("CHECK " + CheckCount + ": pending=" + pendingItems + ", questRunning=" + BoolToString(questRunning) + ", deliveryActive=" + BoolToString(DeliveryActive) + ", actionLevel=" + LastActionLevel + ", logOnly=" + BoolToString(LogOnlyMode) + ", courier=" + courier)
	EndIf

	If pendingItems <= 0
		If DeliveryActive || LastActionLevel > 0
			WriteLog("RESULT " + CheckCount + ": no pending courier items; clearing delivery state")
		ElseIf LogEveryCheck
			WriteLog("RESULT " + CheckCount + ": no pending courier items")
		EndIf

		ClearDeliveryState()
		Return
	EndIf

	If DeliveryActive == False
		DeliveryActive = True
		DeliveryStartTime = nowTime
		LastProgressTime = nowTime
		LastCloseTime = 0.0
		LastDistance = -1.0
		LastActionLevel = 0
		WriteLog("STATE " + CheckCount + ": pending items detected; starting delivery timer")
	EndIf

	If courier == None
		WriteLog("RESULT " + CheckCount + ": courier reference unavailable; handling missing courier")
		HandleMissingCourier()
		Return
	EndIf

	Float deliveryAge = nowTime - DeliveryStartTime

	If courier.IsDead()
		If LogOnlyMode
			WriteLog("OBSERVE " + CheckCount + ": courier is dead; log-only mode is not changing it")
		Else
			courier.Resurrect()
			courier.ResetHealthAndLimbs()
			MarkAction(0, "Courier was dead; resurrected")
		EndIf
	EndIf

	If courier.IsDisabled()
		Float badStateAge = GetBadStateAge(nowTime)
		WriteLog("STATE " + CheckCount + ": courier is disabled while pending items exist; deliveryAge=" + deliveryAge + ", badStateAge=" + badStateAge)
		If badStateAge < SoftResetTime
			WriteLog("RESULT " + CheckCount + ": disabled courier is still inside bad-state grace window")
			Return
		EndIf

		If badStateAge >= ForceDeliverTime && AllowDirectDelivery
			WriteLog("DECISION " + CheckCount + ": courier stayed disabled past force-delivery threshold")
			If LogOnlyMode
				WriteLog("OBSERVE " + CheckCount + ": log-only mode would force-deliver disabled courier delivery")
			Else
				ForceDeliver(courier)
			EndIf
			Return
		EndIf

		If LogOnlyMode
			WriteLog("OBSERVE " + CheckCount + ": log-only mode would restart WICourier instead of directly enabling courier")
		Else
			SoftReset(courier)
		EndIf

		Return
	EndIf

	Float distance = courier.GetDistance(PlayerRef)
	Bool invalidDistance = distance > 100000000.0
	Bool closeEnough = invalidDistance == False && distance <= ApproachDistance

	If LogEveryCheck
		WriteLog("STATE " + CheckCount + ": distance=" + DistanceToString(distance, invalidDistance) + ", lastDistance=" + LastDistance + ", deliveryAge=" + deliveryAge + ", stalledFor=" + (nowTime - LastProgressTime) + ", closeFor=" + GetCloseFor(nowTime))
	EndIf

	If invalidDistance
		Float badStateAge = GetBadStateAge(nowTime)
		WriteLog("STATE " + CheckCount + ": courier distance is invalid or unloaded; badStateAge=" + badStateAge)

		If badStateAge < SoftResetTime
			WriteLog("RESULT " + CheckCount + ": invalid distance is still inside bad-state grace window")
			Return
		EndIf

		If badStateAge >= ForceDeliverTime && AllowDirectDelivery
			WriteLog("DECISION " + CheckCount + ": invalid-distance delivery reached force-delivery threshold")
			If LogOnlyMode
				WriteLog("OBSERVE " + CheckCount + ": log-only mode would force-deliver invalid-distance delivery")
			Else
				ForceDeliver(courier)
			EndIf
			Return
		EndIf

		If LogOnlyMode
			WriteLog("OBSERVE " + CheckCount + ": log-only mode would soft-reset invalid-distance delivery")
		Else
			SoftReset(courier)
		EndIf

		Return
	EndIf

	BadStateStartTime = 0.0

	If closeEnough
		LastDistance = distance
		If LastCloseTime <= 0.0
			LastCloseTime = nowTime
			WriteLog("STATE " + CheckCount + ": courier reached approach distance; starting close-delivery timer")
		EndIf

		Float closeFor = nowTime - LastCloseTime
		If LogOnlyMode
			If closeFor >= CloseDeliveryTime
				WriteLog("OBSERVE " + CheckCount + ": log-only mode would force-deliver; courier has been close for " + closeFor + " seconds")
			Else
				WriteLog("RESULT " + CheckCount + ": courier is close enough; waiting for dialogue delivery")
			EndIf
		Else
			courier.EvaluatePackage()
			If closeFor >= CloseDeliveryTime && AllowDirectDelivery
				WriteLog("DECISION " + CheckCount + ": courier is close but delivery did not complete")
				ForceDeliver(courier)
			Else
				WriteLog("RESULT " + CheckCount + ": courier is close enough; package evaluated and waiting for dialogue delivery")
			EndIf
		EndIf
		Return
	EndIf

	LastCloseTime = 0.0

	If invalidDistance == False && (LastDistance < 0.0 || distance < (LastDistance - ProgressTolerance))
		LastProgressTime = nowTime
		LastDistance = distance
		LastActionLevel = 0
		If LogOnlyMode
			WriteLog("RESULT " + CheckCount + ": courier made progress toward player; log-only mode did not evaluate package")
		Else
			courier.EvaluatePackage()
			WriteLog("RESULT " + CheckCount + ": courier made progress toward player; package evaluated")
		EndIf
		Return
	EndIf

	LastDistance = distance
	Float stalledFor = nowTime - LastProgressTime

	If deliveryAge < StartupGraceTime
		WriteLog("RESULT " + CheckCount + ": delivery is still inside startup grace window")
		Return
	EndIf

	If stalledFor >= ForceDeliverTime && AllowDirectDelivery
		WriteLog("DECISION " + CheckCount + ": force delivery threshold reached")
		If LogOnlyMode
			WriteLog("OBSERVE " + CheckCount + ": log-only mode would force-deliver here")
		Else
			ForceDeliver(courier)
		EndIf
	ElseIf stalledFor >= SoftResetTime
		WriteLog("DECISION " + CheckCount + ": soft reset threshold reached")
		If LogOnlyMode
			WriteLog("OBSERVE " + CheckCount + ": log-only mode would soft-reset here")
		Else
			SoftReset(courier)
		EndIf
	ElseIf LogEveryCheck
		WriteLog("RESULT " + CheckCount + ": courier still has time to reach player")
	EndIf
EndFunction

Function HandleMissingCourier()
	If DeliveryActive == False
		DeliveryActive = True
		DeliveryStartTime = Utility.GetCurrentRealTime()
		LastProgressTime = DeliveryStartTime
		WriteLog("MISSING: first missing-courier check; starting missing timer")
		Return
	EndIf

	Float stalledFor = Utility.GetCurrentRealTime() - DeliveryStartTime
	WriteLog("MISSING: courier unavailable for " + stalledFor + " seconds")

	If LogOnlyMode
		WriteLog("MISSING: log-only mode is not restarting or force-delivering")
		Return
	EndIf

	If stalledFor >= ForceDeliverTime && AllowDirectDelivery
		WriteLog("MISSING: force delivery threshold reached without courier")
		ForceDeliver(None)
	ElseIf stalledFor >= SoftResetTime
		WriteLog("MISSING: restarting courier quest")
		SoftReset(None)
	EndIf
EndFunction

Function SoftReset(Actor courier)
	If LogOnlyMode
		WriteLog("ACTION: soft reset blocked by log-only mode")
		Return
	EndIf

	If LastActionLevel >= 1
		WriteLog("ACTION: soft reset skipped; already performed action level " + LastActionLevel)
		Return
	EndIf

	String blockReason = GetFailsafeActionBlockReason(False)
	If blockReason != ""
		WriteLog("ACTION: soft reset delayed; " + blockReason)
		Return
	EndIf

	Bool restarted = RestartCourierQuest()
	If restarted == False
		WriteLog("ACTION: soft reset restart request failed")
		Return
	EndIf

	If courier
		courier.StopCombatAlarm()
		courier.EvaluatePackage()
	EndIf

	LastActionLevel = 1
	Notify("Courier delivery retry")
	WriteLog("ACTION: soft reset completed")
EndFunction

Function ForceDeliver(Actor courier)
	If LogOnlyMode
		WriteLog("ACTION: force delivery blocked by log-only mode")
		Return
	EndIf

	If LastActionLevel >= 3
		WriteLog("ACTION: force delivery skipped; already performed action level " + LastActionLevel)
		Return
	EndIf

	String blockReason = GetFailsafeActionBlockReason()
	If blockReason != ""
		WriteLog("ACTION: force delivery delayed; " + blockReason)
		Return
	EndIf

	ShowForceDeliveryMessage()

	Bool delivered = False
	If CourierSystem
		CourierSystem.GiveItemsToPlayer()
		WriteLog("ACTION: vanilla CourierSystem.GiveItemsToPlayer() called")
		delivered = True
	Else
		ObjectReference containerRef = GetCourierContainer()
		If containerRef
			containerRef.RemoveAllItems(PlayerRef)
			WriteLog("ACTION: fallback courier container RemoveAllItems(PlayerRef) called")
			delivered = True
		Else
			WriteLog("ACTION: force delivery could not find courier container")
		EndIf

		If delivered && WICourierItemCount
			WICourierItemCount.SetValue(0.0)
			WriteLog("ACTION: WICourierItemCount set to 0")
		EndIf
	EndIf

	If delivered == False
		WriteLog("ACTION: force delivery aborted; pending items were not cleared")
		Return
	EndIf

	If courier
		courier.EvaluatePackage()
	EndIf

	If WICourierQuest && WICourierQuest.IsRunning()
		WICourierQuest.SetStage(200)
		WriteLog("ACTION: WICourier set to stage 200")
	EndIf

	ClearDeliveryState()
	LastActionLevel = 3
	Notify("Courier items delivered by failsafe")
	WriteLog("ACTION: force delivery completed")
EndFunction

String Function GetFailsafeActionBlockReason(Bool requireExterior = True)
	If RequireSafeWorldForForceDelivery == False
		Return ""
	EndIf

	If PlayerRef == None
		PlayerRef = Game.GetPlayer()
	EndIf

	If PlayerRef == None
		Return "player reference unavailable"
	EndIf

	If Utility.IsInMenuMode()
		Return "menu/dialogue is open"
	EndIf

	If PlayerRef.IsInCombat() || PlayerRef.GetCombatState() != 0
		Return "player is in combat"
	EndIf

	If requireExterior == False
		Return ""
	EndIf

	Cell playerCell = PlayerRef.GetParentCell()
	If playerCell == None
		Return "player cell unavailable"
	EndIf

	If playerCell.IsInterior()
		Return "player is not in exterior worldspace"
	EndIf

	WorldSpace playerWorld = PlayerRef.GetWorldSpace()
	If playerWorld == None
		Return "player worldspace unavailable"
	EndIf

	Return ""
EndFunction

Function ShowForceDeliveryMessage()
	If ForceDeliveryMessage != ""
		Debug.MessageBox(ForceDeliveryMessage)
		WriteLog("ACTION: force delivery message shown")
	EndIf
EndFunction

Bool Function RestartCourierQuest()
	If LogOnlyMode
		WriteLog("RESTART: blocked by log-only mode")
		Return False
	EndIf

	If WICourierQuest == None
		WriteLog("RESTART: skipped; WICourierQuest property is empty")
		Return False
	EndIf

	If WICourierQuest.IsRunning()
		WriteLog("RESTART: stopping running WICourier quest")
		WICourierQuest.Stop()
		Utility.Wait(1.0)
	EndIf

	If GetPendingItemCount() > 0
		Bool started = WICourierQuest.Start()
		WriteLog("RESTART: start requested; result=" + BoolToString(started))
		Return started
	Else
		WriteLog("RESTART: skipped start; no pending items")
	EndIf

	Return False
EndFunction

Int Function GetPendingItemCount()
	If WICourierItemCount
		Return WICourierItemCount.GetValueInt()
	EndIf

	If CourierSystem && CourierSystem.pWICourierItemCount
		Return CourierSystem.pWICourierItemCount.GetValueInt()
	EndIf

	Return 0
EndFunction

Actor Function GetCourierActor()
	If CourierAlias
		Actor aliasedCourier = CourierAlias.GetActorReference()
		If aliasedCourier
			Return aliasedCourier
		EndIf
	EndIf

	If CourierSystem && CourierSystem.pCourier
		Return CourierSystem.pCourier as Actor
	EndIf

	Return None
EndFunction

ObjectReference Function GetCourierContainer()
	If CourierContainer
		Return CourierContainer
	EndIf

	If CourierSystem && CourierSystem.pCourierContainer
		Return CourierSystem.pCourierContainer
	EndIf

	Return None
EndFunction

Function QueueCheck(Float delay)
	If UpdateQueued
		If QueuedDelay > 0.0 && delay < QueuedDelay
			UnregisterForUpdate()
			If LogEveryCheck
				WriteLog("QUEUE: replacing queued update delay=" + QueuedDelay + " with delay=" + delay)
			EndIf
		Else
			If LogEveryCheck
				WriteLog("QUEUE: update already queued; requested delay=" + delay)
			EndIf
			Return
		EndIf
	EndIf

	RegisterForSingleUpdate(delay)
	UpdateQueued = True
	QueuedDelay = delay

	If LogEveryCheck
		WriteLog("QUEUE: next check in " + delay + " seconds")
	EndIf
EndFunction

Function ClearDeliveryState()
	DeliveryActive = False
	DeliveryStartTime = 0.0
	LastProgressTime = 0.0
	LastCloseTime = 0.0
	BadStateStartTime = 0.0
	QueuedDelay = 0.0
	LastDistance = -1.0
	LastActionLevel = 0
EndFunction

Float Function GetBadStateAge(Float nowTime)
	If BadStateStartTime <= 0.0
		BadStateStartTime = nowTime
		Return 0.0
	EndIf

	Return nowTime - BadStateStartTime
EndFunction

Float Function GetCloseFor(Float nowTime)
	If LastCloseTime <= 0.0
		Return 0.0
	EndIf

	Return nowTime - LastCloseTime
EndFunction

String Function DistanceToString(Float distance, Bool invalidDistance)
	If invalidDistance
		Return "INVALID_OR_DISABLED"
	EndIf

	Return "" + distance
EndFunction

Function MarkAction(Int level, String messageText)
	If LastActionLevel < level
		LastActionLevel = level
	EndIf

	Notify(messageText)
	WriteLog("ACTION: " + messageText)
EndFunction

Function Notify(String messageText)
	If DebugMode
		Debug.Notification("[Courier Failsafe] " + messageText)
	EndIf
EndFunction

Function OpenFailsafeLog()
	If LogEnabled == False || LogOpenAttempted
		Return
	EndIf

	LogOpenAttempted = True
	LogOpened = Debug.OpenUserLog(LogName)
EndFunction

Function WriteLog(String messageText, Int severity = 0)
	If LogEnabled == False
		Return
	EndIf

	If LogOpened == False
		OpenFailsafeLog()
	EndIf

	String fullMessage = "[Courier Failsafe] " + messageText
	Bool wrote = Debug.TraceUser(LogName, fullMessage, severity)
	If wrote == False
		Debug.Trace(fullMessage, severity)
	EndIf
EndFunction

String Function BoolToString(Bool value)
	If value
		Return "true"
	EndIf

	Return "false"
EndFunction
