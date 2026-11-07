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
local ok, source = pcall(function()
  return game:HttpGet("https://raw.githubusercontent.com/malachai-build/aotr-farm/0bd5e148551969269cf2d58b9e3986653303fd1f/autofarm_normal.lua")
end)
if not ok or type(source) ~= "string" or #source < 100000 then
  warn("[AoTR Normal] source download failed: " .. tostring(source))
  return
end

local chunk, compileError = loadstring(source, "autofarm_normal.lua")
if type(chunk) ~= "function" then
  warn("[AoTR Normal] source compile failed: " .. tostring(compileError))
  return
end
task.spawn(chunk)
