# AoTR normal mission farm

The current normal mission source for Attack on Titan Revolution and the Matcha executor is [`autofarm_normal.lua`](autofarm_normal.lua).

## Autoexec

Save this single line as `C:\matcha\autoexec\aotr_normal.lua`:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/malachai-build/aotr-farm/refs/heads/main/autoexec.lua"))()
```

The entrypoint supports every AoTR mission map, checks the game ID, skips the main menu, lobby and trade hub, creates the Matcha `aotr` workspace folder, downloads the pinned source, and spawns it immediately. It has no top-level wait; Matcha needs the source spawned before the autoexec caller yields. New mission maps need no loader update.

Keep only one active AoTR autoexec entrypoint. Choose this farm for the simpler, more stable titan-killing feature set, or Waves/Raid for its additional features. Do not enable both loadstrings together. Move older autoexec copies to the local deprecated archive before installing this line.

The farm creates `aotr` through Matcha's file API before writing logs or heartbeat files, including when started directly in a mission. No workspace folders need to be created manually.

The Waves and Raid farm is maintained separately in [aotr-waves-raid](https://github.com/malachai-build/aotr-waves-raid). Historical versions remain in Git history and in the local `D:\matcha laods\deprecated` archive. The previous public `codex/aotr-crate-turnin` branch is retained so existing loadstrings continue to work.

## Watchdog setup

Download these two files into the same folder:

- [`aotr_watchdog_portable.ps1`](watchdog/aotr_watchdog_portable.ps1)
- [`Start watchdog.cmd`](watchdog/Start%20watchdog.cmd)

Open Matcha, save the loadstring above in autoexec, and execute it once for the current session if it has not already run. Then double-click **Start watchdog.cmd**. The watchdog does not install the farm or modify autoexec. Matcha's saved autoexec entrypoint starts the farm after a restart.

The watchdog detects Matcha's `app.exe` and verifies its workspace by asking Matcha MCP to write a temporary marker. This build normally uses `C:\matcha\workspace` even when the executable is on another drive. It creates the `aotr` folder and prints the selected workspace and heartbeat paths. Without MCP it uses the default workspace and reports it as unverified. Farm-stall recovery waits for the first heartbeat; closed/hung Matcha recovery and teleport handling remain available.

The farm writes `aotr/heartbeat.txt` relative to Matcha's workspace. Users do not edit Windows paths in the Lua script. To display selected paths without running recovery:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\aotr_watchdog_portable.ps1" -ValidateOnly
```

The overlay-close key is read from Matcha's saved `global.cfg` (`menukey`). With no saved key it uses Insert; custom keys such as Right Arrow work automatically. `-OverlayKey <virtual-key code>` provides an explicit override. `-ValidateOnly` displays the selected key and configuration path. Startup cleanup also runs while waiting for the first farm heartbeat.

Use `-ShowWorkspace` instead of `-ValidateOnly` to open the workspace in Explorer. Enable Matcha's MCP server (default `http://127.0.0.1:8765/mcp`) for workspace verification. Unusual workspace locations can use `-WorkspaceRoot`; a live verification rejects an override that points to a different workspace.

Workspace regression check: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\watchdog_workspace_test.ps1`.

Based on Kitty's AoTR script v1.0.7 (@roguekitty).

## Grab and ragdoll recovery

**Auto QTE / Grab Escape** uses the displayed prompt key for timed QTEs and button-only escape prompts. It releases held keys if disabled and sends no new escape input while Roblox is unfocused. The saved AutoQTE preference is preserved; enable the toggle to use automatic escape.

Ordinary grab escapes scan `Interface.Buttons` for a visible `Main.Key` label every 50 ms. Each prompt supplies its own key; sequences have no fixed order or maximum length. New button instances, label changes, and prompts that disappear and return rearm input. An unchanged prompt retries at a slower rate. Brief gaps keep combat paused; when prompts stop, control returns to the farm. Hidden, unknown, or ambiguous simultaneous prompts send no keys. Regression coverage: `tests/grab_escape_test.lua`.

Character checks run at startup, after HP loss, and during combat. Ragdoll detection reads the actual native Humanoid state using the current client offsets; a persistent character Ragdoll attribute alone never blocks combat. A ragdoll, missing human body parts, or active escape prompt pauses targeting and hover. Damage clears cached character parts. After the game restores an intact character and clears the ragdoll, combat resumes after a short stability check. The script does not force game-owned ragdoll attributes or recreate destroyed body parts.

The farm writes a single `recovering` heartbeat per interrupted episode. The updated watchdog allows 20 seconds for native recovery, then uses its existing Matcha-restart/Retry sequence. Manual Unload still disables recovery. A new server/respawn may still be required if the game's character controller cannot recover.

Regression fixtures: `tests/character_recovery_test.lua` (both sources staged at `aotr/recovery_tests/normal.lua` and `raid.lua`).

## Teleport restart timing

Teleport recovery closes all processes matching the configured Matcha executable when teleport begins. While waiting for the next server, it repeats that cleanup every 100 ms to close copies that respawn. It cleans up once more when the join marker arrives, then launches Matcha directly. The original log follower and join timeout remain in use; there is no duplicate-process launch guard or watchdog mutex. Run one watchdog at a time.

Regression check: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\watchdog_teleport_test.ps1`.
