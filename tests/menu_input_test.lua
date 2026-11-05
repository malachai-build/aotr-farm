-- Stage the two production sources as aotr/autofarm.lua and aotr/autofarm_branch.lua.
local function extract(source, first, last)
  local a = assert(string.find(source, first, 1, true))
  local b = assert(string.find(source, last, a, true))
  return string.sub(source, a, b - 1)
end
for _, path in ipairs({ "aotr/autofarm.lua", "aotr/autofarm_branch.lua" }) do
  local source = readfile(path)
  local header = [====[
local stopped, active, made, removed = false, true, 0, 0
local function Stopped() return stopped end
local function isrbxactive() return active end
local UI = { window = {Visible=true}, lib = {Toggled=true} }
local LocalPlayer = {GetMouse=function() return {X=123,Y=456} end}
local Drawing = {new=function(kind)
  assert(kind=="Triangle"); made += 1
  return {Remove=function() removed += 1 end}
end}
]====]
  local checks = [====[
UI.UpdateCursor()
assert(made==2 and UI.cursorFill.Visible and UI.cursorEdge.Visible)
assert(UI.cursorFill.PointA.X==123 and UI.cursorFill.PointA.Y==456)
UI.UpdateCursor(); assert(made==2,"reuse cursor drawings")
UI.window.Visible=false; UI.UpdateCursor(); assert(not UI.cursorFill.Visible)
UI.window.Visible=true; UI.lib.Toggled=false; UI.UpdateCursor(); assert(not UI.cursorFill.Visible)
UI.lib.Toggled=true; active=false; UI.UpdateCursor(); assert(not UI.cursorFill.Visible)
active=true; UI.UpdateCursor(); assert(UI.cursorFill.Visible)
UI.unloading=true; UI.UpdateCursor(); assert(removed==2 and not UI.cursorFill and not UI.cursorEdge)
UI.RemoveCursor(); assert(removed==2,"cleanup must be idempotent")
UI.unloading=false; UI.UpdateCursor(); stopped=true; UI.UpdateCursor()
assert(removed==4 and not UI.cursorFill,"stop removes cursor")
]====]
  assert(loadstring(header .. extract(source,"function UI.IsOpen()","local function findUE()") .. checks,"menu_cursor_fixtures"))()
end
print("PASS: cursor follows mouse, visibility, drawing reuse, unload and stop cleanup in both farms")

local source = readfile("aotr/autofarm_branch.lua")
local sweep = extract(source,"      if UserConfigs.RandomMouseMovements and not UI.IsOpen()", "      task.wait(0.03)")
for _, mode in ipairs({ "disabled", "menu", "enabled", "disable_midway", "open_midway" }) do
  local header = string.format([====[
local mode=%q
local UserConfigs={RandomMouseMovements=mode~="disabled"}
local opened=mode=="menu"
local UI={IsOpen=function() return opened end}
local FarmStats={NextMouseSweepAt=0,MouseSweepSide=0}
local Workspace={CurrentCamera={ViewportSize=Vector2.new(1920,1080)}}
local LocalPlayer={GetMouse=function() return {X=100,Y=200} end}
local WhatShouldIBeDoing="attack"
local Qte={Active=false}
local Stats={CutsceneSkip={Visible=false}}
local Tr={step=function() end}
local moves, nudges=0,0
local function Stopped() return false end
local function IsLocalAlive() return true end
local function isrbxactive() return true end
local function mousemoveabs() moves += 1 end
local function mousemoverel() nudges += 1 end
local task={wait=function()
  if mode=="disable_midway" then UserConfigs.RandomMouseMovements=false end
  if mode=="open_midway" then opened=true end
end}
]====],mode)
  local checks = [====[
if mode=="disabled" or mode=="menu" then assert(moves==0 and nudges==0)
elseif mode=="enabled" then assert(moves>=8 and nudges==1)
else assert(moves==1 and nudges==0,"cancel sweep immediately when setting or menu changes") end
]====]
  assert(loadstring(header .. sweep .. checks,"mouse_sweep_fixtures"))()
end
print("PASS: random mouse toggle, menu suppression, immediate mid-sweep cancellation")
