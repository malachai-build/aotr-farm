-- Stage both repos' autoexec/farm files at aotr/lobby_test/{normal,raid}_{loader,farm}.lua.
-- Matcha loadstring chunks discard return values, so assertions run inside each fixture.
local function run(path, place, exists, lobby, starts, preludeOnly)
  local header = string.format([====[
local calls = { writes = 0, folders = 0, downloads = 0, spawns = 0 }
local game = { PlaceId = %d, GameId = 4658598196, HttpGet = function()
  calls.downloads += 1
  return "--" .. string.rep("x", 200000) .. "\nreturn"
end }
local function isfolder() return %s end
local function makefolder(path)
  assert(path == "aotr"); calls.folders += 1
end
local function writefile(path, value)
  assert(path == "aotr/heartbeat.txt")
  calls.writes += 1; calls.beat = value
end
local task = { spawn = function(fn)
  assert(type(fn) == "function"); calls.spawns += 1
end }
local function entry()
]====], place, tostring(exists))
  local checks
  if lobby then
    checks = string.format([====[
assert(calls.writes == 1 and string.match(calls.beat, "^unloaded %%d%%d:%%d%%d:%%d%%d$"), "lobby must replace farming beat")
assert(calls.folders == %d, "create workspace only if missing")
assert(calls.downloads == 0 and calls.spawns == 0, "lobby must not start farm")
]====], exists and 0 or 1)
  else
    checks = string.format([====[
assert(calls.downloads == %d and calls.spawns == %d and calls.writes == 0, "mission routing must be preserved")
]====], starts and 1 or 0, starts and 1 or 0)
  end
  local source = readfile(path)
  if preludeOnly then
    source = assert(string.match(source, "^(.-)local Stats = {}"), "farm initialization boundary missing")
    checks = checks .. string.format("assert(calls.folders == %d, 'direct mission startup must create missing aotr folder')\n", exists and 0 or 1)
  end
  assert(loadstring(header .. source .. "\nend\nentry()\n" .. checks, path))()
end

for _, name in ipairs({ "normal", "raid" }) do
  for _, kind in ipairs({ "loader", "farm" }) do
    local path = "aotr/lobby_test/" .. name .. "_" .. kind .. ".lua"
    for _, place in ipairs({ 13379208636, 14916516914, 14932214603 }) do
      for _, exists in ipairs({ false, true }) do
        run(path, place, exists, true, false)
      end
    end
  end
end

run("aotr/lobby_test/normal_loader.lua", 14638336319, true, false, true)
run("aotr/lobby_test/raid_loader.lua", 17688739434, true, false, true)
run("aotr/lobby_test/raid_loader.lua", 14638336319, true, false, false)
run("aotr/lobby_test/normal_loader.lua", 17688739434, true, false, false)
for _, exists in ipairs({ false, true }) do
  run("aotr/lobby_test/normal_farm.lua", 14638336319, exists, false, false, true)
  run("aotr/lobby_test/raid_farm.lua", 17688739434, exists, false, false, true)
end
print("PASS: main menu, lobby and trade hub, both loaders and direct farms, missing workspace, mission routing, direct mission folder creation")
