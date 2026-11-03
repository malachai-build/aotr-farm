# AoTR farm v2 design note

`autofarm_v2.lua` is a new Matcha script. The auto-exec loader now reads `aotr/autofarm_v2.lua`. The previously deployed v1 has been copied into this repo as `autofarm.lua` and remains at `C:\matcha\workspace\aotr\autofarm.lua` as a rollback copy.

- A collector refreshes character, titan, HUD, and QTE references every 0.4 seconds. The actor works from those cached references. No work runs in `RenderStepped`; hover writes are capped at 20 Hz and extra nape pulls are paced separately.
- Every nape CFrame or Size write checks the titan's current parent address, fresh Humanoid.Health, and the weak part's current Hit parent. Freeze traces often ended near nape writes; writing dead titan napes was observed to raise the freeze rate.
- Pull All Napes remains configurable. `PullCount` and `PullRadius` bound the list, `PullEvery` selects the slash cadence, and `PullPerFrame` caps the extras handled at each actor tick. The target nape is still pulled for each human slash.
- Idle and unfocused parking zeroes velocity and only rewrites CFrame after meaningful drift. The old no-target park allowed the character to fall about 1,000 studs between teleports.
- An early-started heartbeat thread writes `farming <time>` every second and stops beating if the main actor stops making progress, hover dies, or Retry stays stuck. `lobby` and `unloaded` remain watchdog stand-down states. Boot, death, black-box, and trace writes stay outside the actor's hot path.
- The per-titan kill timeout is removed. `NoKillMinutes` and `BossNoKillMinutes` remain the stuck-run recovery. Settings preserve older JSON keys, while the prior session's temporary `MenuDisabled=true` is deliberately ignored at startup.
- Reload, gas-tank routes, Retry, shifting, skills, boss Marker `Adornee` at offset `0x710`, and QTE handling follow the deployed farm's behavior. The laced.club UE menu remains, with controls for pull pacing.

## Validation

The staged `aotr/autofarm_v2.lua` passed Matcha's wrapped `loadstring` compile check. This check parses the file without starting the farm. Live farming behavior has not been tested because the deployed script is still in use.

## Switch and rollback

The next Matcha auto-exec run loads `C:\matcha\workspace\aotr\autofarm_v2.lua`. The current in-memory farm keeps running until Matcha reloads or the farm is stopped. To roll back, change the loader's two `aotr/autofarm_v2.lua` references to `aotr/autofarm.lua`.
