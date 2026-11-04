-- Matcha auto-exec loader for the AoTR farm. Deploy to C:\matcha\autoexec\aotr_farm.lua.
-- Matcha quirks this works around (tested 2026-11-01):
--  * a top-level wait in an auto-exec script blocks Matcha's own menu, so nothing here yields;
--  * a loadstring chunk only survives its first yield when it is spawned before the caller has
--    yielded. Called or spawned later (e.g. after a task.wait in a spawned loader) it dies
--    silently at its first wait. So compile and spawn the farm right away, synchronously;
--  * writefile refuses .log, hence boot.txt.
-- Each run appends a line to C:\matcha\workspace\aotr\boot.txt; the farm adds its own stages.
local function boot(msg)
  pcall(function()
    local p = "aotr/boot.txt"
    local old = (type(isfile) ~= "function" or isfile(p)) and readfile(p) or ""
    writefile(p, old .. string.format("%s loader place=%s job=%s %s\n",
      os.date("%H:%M:%S"), tostring(game.PlaceId), tostring(game.JobId), msg))
  end)
end

local ok, src = pcall(readfile, "aotr/autofarm.lua")
if not ok or type(src) ~= "string" then
  boot("read failed: " .. tostring(src))
else
  local chunk, err = loadstring(src, "aotr/autofarm.lua")
  if type(chunk) ~= "function" then
    boot("compile failed: " .. tostring(err))
  else
    boot("spawning farm")
    task.spawn(chunk)
  end
end
