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

An intermediate v2 change incorrectly allowed an empty HUD counter to enter station refill even with intact blades. That change came from a mistaken reading of v1: v1's outer handler deliberately requires both blades to be broken before checking the HUD. A prior live run did log a successful station attempt, but the later ten-minute run exposed a persistent stall, so that isolated success did not establish a reliable fix. The intermediate trigger and alternating station position have now been removed; see the v1 reload restoration below.

A no-extra diagnostic run lasted through a mission transition but still had a stale-heartbeat stop after about two minutes. Its archived trace contained repeated target-nape moves and no extras. The script now enforces a configurable 250 ms minimum between human slashes and target pulls. Each reload `R` down/up is also written to `boot.txt` so the next refill can be confirmed independently of the short trace ring.

A direct-strike experiment avoided moving the nape but put the character close enough to titans to die after one kill, even with a higher position and enlarged nape. That mode was removed. Pull All Napes remains available in the menu but is off in the current live settings during stability diagnosis.

## Focused ten-minute observation (2026-11-03, 05:49:38–05:59:38 Eastern)

The diagnostic build adds fixed phase slots for actor, hover, collector, and reporter operations, caught-error counts, and a one-second diagnostic file. It exposes the cached state as `_G.AotrDiagnostic` for read-only execution probes. Combat behavior and saved settings were held constant during the window; controlled R and movement interventions were recorded separately.

The recorder preserved 600 heartbeat and diagnostic samples, with a longest heartbeat update interval of 1.070 seconds. All 60 Matcha command probes responded, no watchdog restart occurred, and no caught farm error was recorded. The mission remained at six living titans and zero kills. This reproduces a gameplay stall rather than the earlier complete Matcha stops.

Refill reliability remains unresolved despite the earlier successful attempt. All 24 automatic station attempts in this window failed to raise gas. The first three consumed the remaining spare sets. The station display still reported `REFILLS: 1 / 3 [R]`, and a separate two-second R hold also failed. A movement probe showed a successful root write being overwritten with the station position within 50 ms.

Two recovery defects were confirmed by the source and live positions: recovery reuses the 4,000-stud combat selector even though all six remaining titans were 4,262–5,160 studs away, and `giveUp()` retains the expired refill timer. This produces repeated 30-second waits followed by just one refill attempt. Progress beats remain fresh because these waits call `progress()`, masking the absence of gameplay progress.

There were 48 saved blackbox versions with a NaN height. Character probes also saw nonfinite velocity/body positions. Roblox's client log independently recorded 16 `Invalid CFrame. Must contain finite values` errors, with a stack in the game's `Core.Climb`, line 59 (`Near_Floor`), called by `Core.Runtime`, line 232. The initiating source of the invalid values is not yet established. Fresh character/root references matched the cached ones, and a later finite-position sample agreed with raw primitive memory. A game-module decompile attempt failed with an SSL error.

The full report, ordered raw events, source/configuration snapshots, process metrics, and client error stacks were saved in the chat's `outputs/live-test-20261103-054938` evidence folder. These results support finite-value guards, a recovery-specific titan selector, fresh recovery timers, and separate tracking of gameplay progress. Those behavior changes were not included in the observation build.

## Restore v1 reload flow and remove target range cap (2026-11-03)

The user confirmed that the observation window was spent stuck in reload handling. Its lack of native freezes is not evidence of improved combat stability. A pre-fix live probe showed both blade transparency values at `0` (intact), empty HUD counters, and the old v2 waiting to reload. The HUD-only trigger was therefore entering the refill path contrary to v1's behavior.

The restored flow requires both existing blade models to read broken before entering either supply path. Missing models do not force a reload. It checks the current character's Shifter attribute before interpreting human supply counters; waits for the root's `BV` marker before a station attempt; waits five seconds after the final shift input; and uses v1's velocity settle, fixed `+5` station offset, 500 ms R hold, and post-input wait. Ordinary blade reloads retain v1's three-second spacing. A dedicated reload flag prevents the hover worker from taking over reload positioning. Recovery clears the expired refill timer and reload flag on exit.

The 4,000-stud cutoff has been removed from combat and recovery selection. Both consider live titans at any distance, selecting the nearest valid position. Recovery also bypasses the titan-form close-target filter. Nonfinite positions are rejected; station memory reads validate pointers before use.

Eleven isolated checks ran the actual extracted source functions against plain mock objects in Matcha. They cover intact blades with empty HUD, missing blades, ordinary reload spacing, BV gating, station R eligibility, fresh Shifter state, distant combat/recovery targets, titan-form recovery, and refill timer reset. All passed, and the full file passed Matcha's wrapped compile check.

The patched live run left the erroneous reload loop and selected a distant titan. It subsequently reported attacking, but no kill was observed and the user reported it remained ineffective. The client then returned to the lobby before a matched v1 comparison or successful refill could be verified. The reload safeguards and target selection changes are implemented; live farming and the separate combat freeze issue remain unverified.

## Switch and rollback

The next Matcha auto-exec run loads `C:\matcha\workspace\aotr\autofarm_v2.lua`. The current in-memory farm keeps running until Matcha reloads or the farm is stopped. To roll back, change the loader's two `aotr/autofarm_v2.lua` references to `aotr/autofarm.lua`.
