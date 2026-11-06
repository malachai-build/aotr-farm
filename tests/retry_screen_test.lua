-- Stage sources at aotr/reload_tests/{normal,raid}.lua. All input is mocked.
for _,variant in ipairs({"normal","raid"}) do
  local s=readfile("aotr/reload_tests/"..variant..".lua")
  local a=assert(string.find(s,"local RetryCount = 0",1,true))
  local b=assert(string.find(s,"--#endregion -- Ui elements functions --",a,true))
  local header=[====[
local now,focused,visible,stopped=0,true,true,false
local down,up={},{}
local loseOnD=false
local os={clock=function() return now end}
local task={wait=function(dt) now+=dt end}
local title={Text="RETRY (0/0)"}
local button={FindFirstChild=function() return title end}
local function IsRetryVisible() return visible end
local function isrbxactive() return focused end
local function Stopped() return stopped end
local function GetPath() return button end
local function Boot() end
local function keypress(k)
  down[#down+1]=k
  if loseOnD and k==0x44 then focused=false end
  if k==0x0D then title.Text="STARTING..." end
end
local function keyrelease(k) up[#up+1]=k end
]====]
  local checks=[====[
assert(PressRetry(),"keyboard navigation reaches starting")
assert(#down==4 and down[1]==0xDC and down[2]==0x44 and down[3]==0x44 and down[4]==0x0D,"exact backslash D D Enter sequence")
assert(#up==4,"all keys released")
assert(PressRetry() and #down==4,"do not toggle navigation while starting")
title.Text="RETRY";focused=false
assert(not PressRetry() and #down==4,"no input outside Roblox")
focused=true;visible=false
assert(not PressRetry() and #down==4,"no input after Rewards closes")
visible=true;loseOnD=true;down={};up={}
assert(not PressRetry() and #down==2 and #up==2,"focus loss cancels remaining navigation and releases held key")
]====]
  assert(loadstring(header..string.sub(s,a,b-1)..checks,"retry_"..variant))()
  local visibleStart=assert(string.find(s,"local function IsRetryVisible()",1,true))
  local visibleEnd=assert(string.find(s,"\nend",visibleStart,true))+4
  local visibleFixture=[====[
local UiCache={}
local rewards={Parent=true,Visible=true}
local interface={FindFirstChild=function() return rewards end}
local PlayerGui={FindFirstChild=function() return interface end}
local function IsObjectVisible(o) return o.Visible end
local function GetPath() error("render callback must not yield") end
]====]
  assert(loadstring(visibleFixture..string.sub(s,visibleStart,visibleEnd)..[[
assert(IsRetryVisible(),"render-safe Rewards lookup")
rewards.Visible=false;assert(not IsRetryVisible(),"cached Rewards visibility remains live")
]],"retry_visibility_"..variant))()
  assert(loadstring(s,"compile_"..variant))
  print("PASS: "..variant.." primary keyboard Retry, starting state, focus and visibility guards, key cleanup")
end
