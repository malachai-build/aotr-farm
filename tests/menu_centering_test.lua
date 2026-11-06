-- Stage both production sources at aotr/reload_tests/{normal,raid}.lua.
for _,variant in ipairs({"normal","raid"}) do
  local source=readfile("aotr/reload_tests/"..variant..".lua")
  local a=assert(string.find(source,"function UI.CenterWindow(win)",1,true))
  local b=assert(string.find(source,"-- End startup centering.",a,true))
  local header=[====[
local viewport=Vector2.new(2560,1377)
local camera={}
setmetatable(camera,{__index=function() return viewport end})
local game={GetService=function() return {CurrentCamera=camera} end}
local UI={}
local function window()
  return {Position=Vector2.new(100,100),Size=Vector2.new(497,534),_aotrCenterPending=true}
end
]====]
  local checks=[====[
local win=window()
assert(UI.CenterWindow(win))
assert(win.Position.X==1031.5 and win.Position.Y==421.5,"use actual scaled window size")
assert(not win._aotrCenterPending and win._visibilityDirty)
win.Position=Vector2.new(222,333)
assert(not UI.CenterWindow(win) and win.Position.X==222 and win.Position.Y==333,"never override later dragging")
win=window();viewport=Vector2.new(0,0)
assert(not UI.CenterWindow(win) and win.Position.X==100 and win.Position.Y==100 and win._aotrCenterPending,"safe fallback while viewport is zero")
viewport=Vector2.new(1920,1080)
assert(UI.CenterWindow(win) and win.Position.X==711.5 and win.Position.Y==273,"repair once when viewport becomes ready")
win=window();viewport=Vector2.new(320,240)
assert(UI.CenterWindow(win) and win.Position.X==8 and win.Position.Y==8,"oversized window keeps title bar reachable")
assert(win.Size.X==497 and win.Size.Y==534,"do not resize window or controls")
win=window();win.Dragging=true
assert(not UI.CenterWindow(win) and not win._aotrCenterPending and win.Position.X==100,"user drag cancels pending startup centering")
win=window();camera=nil
assert(not UI.CenterWindow(win) and win._aotrCenterPending,"missing camera retries later")
camera=setmetatable({},{__index=function() return viewport end})
for _,invalid in ipairs({{X=0,Y=1000},{X=-1,Y=1000},{X=math.huge,Y=1000},{X="bad",Y=1000},{X=0/0,Y=1000}}) do
  viewport=invalid;win=window()
  assert(not UI.CenterWindow(win) and win.Position.X==100 and win._aotrCenterPending,"invalid viewport cannot produce offscreen position")
end
]====]
  assert(loadstring(header..string.sub(source,a,b-1)..checks,"centering_"..variant))()
  assert(string.find(source,'Center = false, Position = Vector2.new(100, 100)',1,true),"disable library zero-viewport centering")
  assert(string.find(source,'if win._aotrCenterPending then UI.CenterWindow(win) end',1,true),"retry from existing menu loop")
  assert(loadstring(source,"compile_centering_"..variant))
  print("PASS: "..variant.." immediate/delayed centering, zero/missing/invalid viewport, small screen, user dragging, compilation")
end
