-- Matcha autoexec entrypoint. Download and spawn before this chunk yields.
-- Main menu, lobby and trade hub must clear the previous mission's beat.
-- "unloaded" also works when the watcher's configured lobby ID is different.
if game.PlaceId == 13379208636 or game.PlaceId == 14916516914 or game.PlaceId == 14932214603 then
  if not isfolder("aotr") then makefolder("aotr") end
  writefile("aotr/heartbeat.txt", "unloaded " .. os.date("%H:%M:%S"))
  return
end
if game.PlaceId ~= 14638336319 then return end
if not isfolder("aotr") then makefolder("aotr") end

local source = game:HttpGet("https://raw.githubusercontent.com/malachai-build/aotr-farm/1fc8a1420f2e5382e4ef0948d26598f72410f7e0/autofarm_normal.lua")
if type(source) ~= "string" or #source < 100000 then
  warn("[AoTR Normal] source download failed")
  return
end

task.spawn(loadstring(source, "autofarm_normal.lua"))
