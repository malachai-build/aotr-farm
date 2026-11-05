-- Matcha one-line loader for the Waves/Raid branch.
if game.PlaceId == 14638336319 or game.PlaceId == 14916516914 then return end
if not isfolder("aotr") then makefolder("aotr") end
local source = httpget("https://raw.githubusercontent.com/malachai-build/aotr-farm/fe802845700865bcfb60d9fb7416d7e6c30a0532/autofarm.lua")
if #source < 150000 then warn("[AoTR] Waves/Raid download failed"); return end
task.spawn(loadstring(source, "autofarm.lua"))
