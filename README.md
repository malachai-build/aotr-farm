# AoTR normal mission farm

The current normal mission source for Attack on Titan Revolution and the Matcha executor is [`autofarm_normal.lua`](autofarm_normal.lua).

## Autoexec

Save this single line as `C:\matcha\autoexec\aotr_normal.lua`:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/malachai-build/aotr-farm/refs/heads/main/autoexec.lua"))()
```

The entrypoint checks the normal mission place, creates the Matcha `aotr` workspace folder, downloads the pinned source, and spawns it immediately. It has no top-level wait; Matcha needs the source spawned before the autoexec caller yields.

Keep only one active AoTR autoexec entrypoint for this place. Move older autoexec copies to the local deprecated archive before installing this line.

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

Use `-ShowWorkspace` instead of `-ValidateOnly` to open the workspace in Explorer. Enable Matcha's MCP server (default `http://127.0.0.1:8765/mcp`) for workspace verification. Unusual workspace locations can use `-WorkspaceRoot`; a live verification rejects an override that points to a different workspace.

Workspace regression check: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\watchdog_workspace_test.ps1`.

Based on Kitty's AoTR script v1.0.7 (@roguekitty).
