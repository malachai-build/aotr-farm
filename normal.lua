-- Matcha one-line loader for the normal mission farm.
if game.PlaceId ~= 14638336319 then return end
if not isfolder("aotr") then makefolder("aotr") end
local source = httpget("https://raw.githubusercontent.com/malachai-build/aotr-farm/fe802845700865bcfb60d9fb7416d7e6c30a0532/autofarm_normal.lua")
if #source < 100000 then warn("[AoTR] Normal farm download failed"); return end
task.spawn(loadstring(source, "autofarm_normal.lua"))
