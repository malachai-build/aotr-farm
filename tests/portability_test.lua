-- Stage autoexec.lua, raid_autoexec.lua, autofarm_normal.lua, raid_farm.lua and this test under aotr/portability/.
-- No production farm is started: loader downloads/spawns and all UI input are mocked.
local farm = readfile("aotr/portability/autofarm_normal.lua")
local function route(loader, place, expected, universe)
  local header = string.format([====[
local calls = {downloads=0,spawns=0,writes=0,folders=0}
local game = {PlaceId=%d, GameId=%d, HttpGet=function()
  calls.downloads += 1; return "--" .. string.rep("x", 200000) .. "\nreturn"
end}
local function isfolder() return false end
local function makefolder() calls.folders += 1 end
local function writefile(path, value)
  assert(path=="aotr/heartbeat.txt" and string.match(value,"^unloaded "))
  calls.writes += 1
end
local task = {spawn=function(fn) assert(type(fn)=="function"); calls.spawns += 1 end}
local function entry()
]====], place, universe or 4658598196)
  local count = expected == "mission" and 1 or 0
  local writes = expected == "social" and 1 or 0
  local folders = expected == "skip" and 0 or 1
  local checks = string.format("\nend\nentry()\nassert(calls.downloads==%d and calls.spawns==%d and calls.writes==%d and calls.folders==%d, 'routing place %d')", count, count, writes, folders, place)
  assert(loadstring(header .. loader .. checks, "route_" .. place))()
end
for _, file in ipairs({"autoexec.lua","raid_autoexec.lua"}) do
  local loader = readfile("aotr/portability/" .. file)
  -- Every current mission map and a hypothetical future map; no map whitelist.
  for _, place in ipairs({13379349730,13904207646,14012874501,14638336319,15220308770,15824912319,17688739434,15030367419,15374465998,112374853034490,126678335159530,99999999999}) do
    route(loader,place,"mission")
  end
  for _, place in ipairs({13379208636,14916516914,14932214603}) do route(loader,place,"social") end
  route(loader,123,"skip",123456)
  route(loader,14638336319,"mission",0) -- Farm checks the universe once IDs finish loading.
end
assert(loadstring(readfile("aotr/portability/raid_farm.lua"),"raid_compile"))
assert(not string.find(readfile("aotr/portability/raid_farm.lua"),"if game.PlaceId == 14638336319 then",1,true),"direct raid farm must not reject Forest")
print("PASS: both loaders support all current/future mission maps; social/unrelated game guards; raid source compiles")

local a = assert(string.find(farm,"function UI.IsOpen()",1,true))
local b = assert(string.find(farm,"local function findUE()",a,true))
local menu = string.sub(farm,a,b-1)
local header = [====[
local mode, made = "ok", 0
local UI = {window={Visible=true,Position=Vector2.new(100,400),Size=Vector2.new(540,580)},lib={Toggled=true}}
local LocalPlayer = {GetMouse=function()
  if mode=="error" then local missing = {}; return missing:GetMouse() end
  if mode=="nil" then return nil end
  if mode=="invalid" then return {X="bad",Y=456} end
  return {X=123,Y=456}
end}
local function Stopped() return false end
local function isrbxactive() return true end
local Drawing = {new=function()
  made += 1; return {Remove=function() end}
end}
]====]
local checks = [====[
assert(UI.IsInteracting()); UI.UpdateCursor()
assert(made==2 and UI.cursorFill.Visible and UI.cursorFill.PointA.X==123)
for _, failure in ipairs({"error","nil","invalid"}) do
  mode=failure
  assert(UI.IsInteracting(),"protect controls on unreadable input")
  UI.UpdateCursor()
  assert(not UI.cursorFill.Visible and not UI.cursorEdge.Visible,"hide unreadable cursor")
end
mode="ok"; UI.UpdateCursor(); assert(made==2 and UI.cursorFill.Visible,"resume using existing drawings")
UI.window.Position=Vector2.new(500,500); assert(not UI.IsInteracting())
mode="error"; UI.window.Visible=false
assert(not UI.IsInteracting()); UI.UpdateCursor()
assert(not UI.cursorFill.Visible)
]====]
assert(loadstring(header .. menu .. checks,"portable_mouse"))()
assert(loadstring(farm,"normal_compile"))
print("PASS: missing/invalid mouse input contained; cursor recovers; complete farm compiles")
