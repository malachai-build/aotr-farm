# AoTR normal mission farm

The current normal mission source for Attack on Titan Revolution and the Matcha executor is [`autofarm_normal.lua`](autofarm_normal.lua).

## Autoexec

Save this single line as `C:\matcha\autoexec\aotr_normal.lua`:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/malachai-build/aotr-farm/refs/heads/main/autoexec.lua"))()
```

The entrypoint checks the normal mission place, creates the Matcha `aotr` workspace folder, downloads the pinned source, and spawns it immediately. It has no top-level wait; Matcha needs the source spawned before the autoexec caller yields.

Keep only one active AoTR autoexec entrypoint for this place. Move older autoexec copies to the local deprecated archive before installing this line.

This source is the same code currently staged at `C:\matcha\workspace\aotr\autofarm.lua` (verified by SHA-256 on 2026-11-05). The active normal mission autoexec loader reads that workspace copy.

The Waves and Raid farm is maintained separately in [aotr-waves-raid](https://github.com/malachai-build/aotr-waves-raid). Historical versions remain in Git history and in the local `D:\matcha laods\deprecated` archive. The previous public `codex/aotr-crate-turnin` branch is retained so existing loadstrings continue to work.

The portable watcher is in [`watchdog/aotr_watchdog_portable.ps1`](watchdog/aotr_watchdog_portable.ps1).

Based on Kitty's AoTR script v1.0.7 (@roguekitty).
