# AoTR Farm

Titan autofarm for Attack on Titan Revolution (Roblox), for the Matcha executor.

Based on Kitty's Aotr script v1.0.7 (@roguekitty). This copy adds a menu, a stop switch,
adjustable settings and two hover fixes.

## Run

Copy `autofarm.lua` to `C:\matcha\workspace\aotr\autofarm.lua`, join a mission with blades
equipped, then execute:

```lua
loadstring(readfile("aotr/autofarm.lua"))()
```

- **F6** toggles the farm, **End** unloads. `_G.AotrStop = true` also stops everything.
- The menu (laced.club UE library, same layout as the SAO Eternity script) downloads at start.
  If it fails, the hotkeys and the on-screen status line still work.
- Settings save to `aotr_farm.json` in the Matcha workspace.

## How it works

Every frame it holds you 100-200 studs above the nearest titan, moves that titan's
`Hitboxes.Hit.Nape` onto you, enlarges it and clicks to slash. Your blade hitbox touches the
nape and the game sends `POST("Hitboxes", "Register", nape, Time_Difference)` itself. Blade
hits are detected client-side, so this counts. Kills show up as `ReplicatedStorage.Objectives.Slay`
rising and the titan leaving `workspace.Titans`. Titan `Humanoid.Health` stays 100 on the client.

Memory offsets come from `https://imtheo.lol/Offsets/Offsets.json`.

## Options

| Tab | Group | Options |
|---|---|---|
| Main | Farm | Auto Farm (F6), Auto Retry, Auto Reload / Refill, Debug Logging |
| Main | Session | Print / reset kill stats, Unload |
| Tuning | Attack | Nape size, slash delay, give-up timeout |
| Tuning | Hover | Height per titan type (Normal, Stall, Attack, Colossal), bob, reload spot height |

## Known issues

- Teleports every frame. Expect kick risk.
- Refill only works on maps whose gas tank path the script knows (Shiganshina, Trost,
  Outskirts, Forest, Utgard, Docks, Stohess, Chapel, Waves). Elsewhere blades reload but gas
  never refills.
- Armored titans on Freedom difficulty need a weak spot hit first; the farm times out on them.
- One 70-second run (23 kills) ended with Matcha freezing; cause not found yet.
