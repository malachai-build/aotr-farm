-- Matcha autoexec entrypoint. Download and spawn before this chunk yields.
if game.PlaceId ~= 14638336319 then return end
if not isfolder("aotr") then makefolder("aotr") end

local source = game:HttpGet("https://raw.githubusercontent.com/malachai-build/aotr-farm/2d7235057f6b63863b5bb54a3316c56b0c8e25af/autofarm_normal.lua")
if type(source) ~= "string" or #source < 100000 then
  warn("[AoTR Normal] source download failed")
  return
end

task.spawn(loadstring(source, "autofarm_normal.lua"))
