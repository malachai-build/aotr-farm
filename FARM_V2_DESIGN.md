# AoTR farm v2 design note

`autofarm_v2.lua` is a new Matcha script. The auto-exec loader now reads `aotr/autofarm_v2.lua`. The previously deployed v1 has been copied into this repo as `autofarm.lua` and remains at `C:\matcha\workspace\aotr\autofarm.lua` as a rollback copy.

- A collector refreshes character, titan, HUD, and QTE references every 0.4 seconds. The actor works from those cached references. No work runs in `RenderStepped`; hover writes are capped at 10 Hz and extra nape pulls are paced separately.
- Every nape CFrame or Size write checks the titan's current parent address, fresh Humanoid.Health, and the weak part's current Hit parent. Freeze traces often ended near nape writes; writing dead titan napes was observed to raise the freeze rate.
- Pull All Napes remains configurable. `PullCount` and `PullRadius` bound the list, and `PullEvery` selects the slash cadence. Extras rotate one at a time. The target nape is still pulled for each human slash.
- Idle and unfocused parking zeroes velocity and only rewrites CFrame after meaningful drift. The old no-target park allowed the character to fall about 1,000 studs between teleports.
- An early-started heartbeat thread writes `farming <time>` every second and stops beating if the main actor stops making progress, hover dies, or Retry stays stuck. `lobby` and `unloaded` remain watchdog stand-down states. Boot, death, black-box, and trace writes stay outside the actor's hot path.
- The per-titan kill timeout is removed. `NoKillMinutes` and `BossNoKillMinutes` remain the stuck-run recovery. Settings preserve older JSON keys, while the prior session's temporary `MenuDisabled=true` is deliberately ignored at startup.
- Reload, gas-tank routes, Retry, shifting, skills, boss Marker `Adornee` at offset `0x710`, and QTE handling follow the deployed farm's behavior. The laced.club UE menu remains, with controls for pull pacing.

## Validation

The staged `aotr/autofarm_v2.lua` passed Matcha's wrapped `loadstring` compile check. The reload fix was started in a live mission. A later snapshot showed blade memory `0/0` with the HUD at `1 / 3` sets, consistent with successful reloads. The paced-pull revision kept a fresh heartbeat for over a minute and reached 11 recorded kills without a watchdog restart. Longer running stability remains unverified.

## Reload fix (2026-11-03)

The first v2 run attacked with broken blades because its offset loader replaced a valid cache with an empty HTTP response. The live blade snapshot showed transparency values `1/1` at the memory offset while Matcha's direct `Transparency` property returned `-0.5/-0.5`, so the memory read remains authoritative. The loader now validates JSON before replacing the cache, and the farm pauses attacks if the offset is unavailable. The actor also stays off the character during gas-tank refill so its no-target park cannot pull the character away. The cache was restored from the current offsets endpoint.

After a teleport, a second live trace showed clicks with no hover writes and a root at ground level. The collector now refreshes root and humanoid references when their parent is no longer the current character model, and the main loop waits for a valid root before attacking. It also clears the refill flag whenever the reload check does not run, allowing hover to resume.

The watchdog then recorded repeated stale-heartbeat restarts under v2. The saved settings allowed three extra napes to be moved in a single actor tick. Extra pulls were first limited to one per tick, but another stop still occurred during a sequence of nape pulls. The current revision rotates through one extra nape per configured slash cadence, and hovers at 10 Hz. Hot-path trace events use a fixed ring; string formatting happens once per second when the trace file is flushed. This reduces bursts but does not yet establish the root cause of every Matcha stop.

The v2 startup was also overwriting `trace.txt` before it archived the prior run, leaving empty freeze sections. The archive now runs before background threads start, so subsequent restarts preserve the last trace for diagnosis.

The v2 refill reached a gas station but did not activate it. V2 had shortened the `R` press from v1's 500 ms to 50 ms. Gas refill and blade reload now hold `R` for 500 ms after a brief settle, and trace the key down/up steps.

The next review found that v2 only entered refill handling after both blade models read broken. V1 also responded to empty gas or zero spare blade sets. V2 now enters station refill on either empty HUD counter, even with intact blades, and logs the counters before and after each station attempt. Repeated attempts alternate between the station position and five studs to its side. A focused live run logged `R` down/up for ordinary blade reloads and three station attempts. The third station attempt changed spare sets from `1` to `3` and gas from `0%` to `50%`; the farm resumed attacking. The watchdog restarted Matcha twice earlier in that run, so the separate freeze issue remains open.

A no-extra diagnostic run lasted through a mission transition but still had a stale-heartbeat stop after about two minutes. Its archived trace contained repeated target-nape moves and no extras. The script now enforces a configurable 250 ms minimum between human slashes and target pulls. Each reload `R` down/up is also written to `boot.txt` so the next refill can be confirmed independently of the short trace ring.

A direct-strike experiment avoided moving the nape but put the character close enough to titans to die after one kill, even with a higher position and enlarged nape. That mode was removed. Pull All Napes remains available in the menu but is off in the current live settings during stability diagnosis.

## Switch and rollback

The next Matcha auto-exec run loads `C:\matcha\workspace\aotr\autofarm_v2.lua`. The current in-memory farm keeps running until Matcha reloads or the farm is stopped. To roll back, change the loader's two `aotr/autofarm_v2.lua` references to `aotr/autofarm.lua`.
