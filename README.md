# Courier Failsafe Wrapper

Courier Failsafe Wrapper is a small Skyrim Special Edition / Anniversary Edition plugin that watches the vanilla `WICourier` system and completes stuck courier deliveries.

It was built after observing vanilla courier logs where pending courier items could remain undelivered when the player was in locations where the courier does not reliably spawn, such as Solstheim interiors or unsupported/no-location worldspace cells.

## What It Does

- Adds a start-game-enabled watchdog quest.
- Ships as an ESL-flagged ESP.
- Monitors the vanilla `WICourierItemCount` global.
- Lets vanilla WICourier start, stop, and restart normally.
- Avoids treating normal holding-cell or invalid-distance states as immediate failures.
- Soft-resets the courier quest when pending items make no progress.
- Teleports the courier only when the actor is far away and genuinely stalled.
- Force-delivers as a final fallback if the courier cannot reach the player.
- Shows a blocking message box before force delivery:

```text
Kurier ustal za toboy begat i prislal vse pisma pochte. Ne zabud prochitat ih v inventare!
```

Force delivery uses the vanilla `WICourierScript.GiveItemsToPlayer()` path, which clears `WICourierItemCount`, transfers the courier container contents to the player, and shows the vanilla items-added message.
If the vanilla courier script property is unavailable, the wrapper uses a direct `WICourierContainerRef` property as a fallback and only clears pending state after a confirmed transfer.
By default, soft reset, teleport, and force delivery wait until the player is in an exterior worldspace, out of combat, and not in a menu/dialogue.

## Included Files

```text
CourierFailsafe.esp
Seq/CourierFailsafe.seq
Scripts/WICourierFailsafeScript.pex
Scripts/WICourierFailsafePlayerAliasScript.pex
Scripts/WICourierFailsafeCourierAliasScript.pex
Source/Scripts/WICourierFailsafeScript.psc
Source/Scripts/WICourierFailsafePlayerAliasScript.psc
Source/Scripts/WICourierFailsafeCourierAliasScript.psc
tools/CourierFailsafeMutagen/
```

## Installation

Install the repository contents as a normal loose-file mod with MO2, Vortex, or another mod manager.

Enable:

```text
CourierFailsafe.esp
```

The `Seq/CourierFailsafe.seq` file is included so the start-game-enabled quest can initialize correctly.

## Logs

The wrapper writes to this Papyrus user log:

```text
Documents/My Games/Skyrim Special Edition/Logs/Script/User/WICourierFailsafe.0.log
```

To collect logs, Papyrus logging must be enabled in:

```text
Documents/My Games/Skyrim Special Edition/Skyrim.ini
```

Use:

```ini
[Papyrus]
bEnableLogging=1
bEnableTrace=1
bLoadDebugInformation=1
```

## Behavior Notes

The wrapper intentionally waits before acting because vanilla courier behavior often looks strange but is normal:

- The courier is often disabled in `WICourierCell` before a delivery starts.
- `GetDistance()` can be invalid while the courier is unloaded or in a different space.
- WICourier can stop at stage `200` and restart later while pending items still exist.
- The player can move through cells with no valid `Location`, causing vanilla restart delays.

If pending courier items remain active past the final timeout and the courier cannot spawn or reach the player, the wrapper force-delivers the pending letters/items directly.

## Development

The Papyrus sources are in:

```text
Source/Scripts/
```

The generated plugin can be rebuilt with the Mutagen helper in:

```text
tools/CourierFailsafeMutagen/
```

The current helper was authored for the local development layout and may need path edits before use on another machine.

## Compatibility

This plugin does not replace vanilla courier scripts. It adds its own quest/script wrapper.

It should be compatible with most mods unless they heavily rewrite the vanilla `WICourier` quest, `WICourierItemCount`, or courier delivery container behavior.
