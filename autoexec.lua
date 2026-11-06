-- Matcha autoexec entrypoint. Download and spawn before this chunk yields.
-- Main menu, lobby and trade hub must clear the previous mission's beat.
-- "unloaded" also works when the watcher's configured lobby ID is different.
if game.PlaceId == 13379208636 or game.PlaceId == 14916516914 or game.PlaceId == 14932214603 then
  if not isfolder("aotr") then makefolder("aotr") end
  writefile("aotr/heartbeat.txt", "unloaded " .. os.date("%H:%M:%S"))
  return
end
if game.GameId ~= 0 and game.GameId ~= 4658598196 then return end
-- Users choose the stable normal farm or the feature-rich Waves/Raid farm.
-- A map ID must not choose the script for them.
if not isfolder("aotr") then makefolder("aotr") end
local source = game:HttpGet("https://raw.githubusercontent.com/malachai-build/aotr-farm/91826c17454e4c7467ba81019856c8707cf4239b/autofarm_normal.lua")
if type(source) ~= "string" or #source < 100000 then
  warn("[AoTR Normal] source download failed")
  return
end

task.spawn(loadstring(source, "autofarm_normal.lua"))
