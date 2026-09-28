# Kill Hook Probe - RuneScape: Dragonwilds

A diagnostic UE4SS Lua mod for modders. It finds out which game functions actually run when
something dies, so a mod that needs a death or kill event can hook one that works.

Many functions that look right are called straight from C++ and never reach a Lua hook. For
example `ProgressComponent:OnAIKilled` is never seen by Lua, while
`AiAttackTicketsManager:OnAiDeath(ai)` runs once for every AI death (found with this probe).

## Use

1. Install [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) for the game.
2. Copy this folder into `RSDragonwilds/Binaries/Win64/ue4ss/Mods/KillHookProbe` and add
   `KillHookProbe : 1` to `ue4ss/Mods/mods.txt`.
3. Load into a world, wait about 10 seconds (or press Ctrl+F12 near some creatures), kill
   something, then quit.
4. Read the `[KillHookProbe] FIRED` lines in `ue4ss/UE4SS.log`, for example:

   ```
   FIRED /Script/Dominion.AiAttackTicketsManager:OnAiDeath  self=AiAttackTicketsManager ...  arg1=BP_AI_Kebbit_Character_02_C ...
   ```

5. Remove the folder and its `mods.txt` line when done. It is not meant to stay installed.

## What it hooks

Every reflected function in the game's own code (`/Script/Dominion`, `/Script/Redpoint*`,
`/Script/GameplayAbilities` and `/Game/` blueprints) whose name contains death, died, dead, kill,
slain or defeat, up to 150. It rescans after each map load and on Ctrl+F12, since a creature's
blueprint class only exists once something has loaded it. Each function logs at most 20 times.

Left out on purpose:

- names where "kill" is only part of "skill"
- blueprint event graphs (`ExecuteUbergraph_*`, `__ENTRYPOINT*`): hooking those crashes UE4SS
- getters and checks (`Get*`, `Is*`, `Has*`, `Can*`, `Should*`), which run constantly
- engine noise such as dead zones, particles and pending-kill bookkeeping
