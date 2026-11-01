# Handoff

State on 2026-11-01, for the next session.

## Status

- `autofarm.lua` worked live before the menu was added: 23 kills in about 70 s, 2-4 s per titan.
- The menu, settings, hotkeys, status line and the two hover fixes have **not been run yet**.
  Matcha went offline before they could be compile-checked.
- First step next session: Matcha back up, in a mission with blades, run
  `loadstring(readfile("aotr/autofarm.lua"))()` and confirm it compiles, the menu shows and kills count.

## What was learned

- Places: lobby 14916516914; missions seen 13379349730, 14638336319, 15824912319. GameId 4658598196.
- Remotes: `ReplicatedStorage.Assets.Remotes` `GET` (RemoteFunction), `POST` (RemoteEvent),
  `GET_2` on mission places. Calls are `(module, action, ...)`.
- Blades: `POST("Hitboxes", "Register", <titan Hit part>, Time_Difference)`. Fired remotely from
  321 and 174 studs it did not kill, so the server checks range. The farm works because it hovers close.
- Thunder spears: `GET("Spears","S_Fire","1".."8")` then `POST("Spears","S_Explode", Vector3, Time_Difference)`.
  The server accepts it but never killed in 4 tests; the server does its own overlap check.
- `PlayerScripts.Baka` is a 136-byte stub; nothing to deobfuscate client-side.
- Matcha cannot hook outgoing remotes (no hookmetamethod). Decompiles of large modules can time out.

## Open items

- Find why the first run froze Matcha at ~70 s.
- Gas tank path for unknown maps (e.g. place 15824912319) so refills work.
- Armored (Freedom) titans: weak spot mechanic, server sets `Vulnerable` on a Hit part at runtime.
