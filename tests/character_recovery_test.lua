-- Stage both variants at aotr/recovery_tests/{normal,raid}.lua. All inputs/body objects are mocked.
local function extract(s, a, b)
  local first=assert(string.find(s,a,1,true),a)
  local last=assert(string.find(s,b,first,true),b)
  return string.sub(s,first,last-1)
end
for _, variant in ipairs({"normal","raid"}) do
  local source=readfile("aotr/recovery_tests/"..variant..".lua")
  local header=[====[
local now=0
local os={clock=function() return now end}
local beats, logs, presses, releases={},{},{},{}
local function Heartbeat(s) beats[#beats+1]=s end
local function Boot(s) logs[#logs+1]=s end
local function keypress(k) presses[#presses+1]=k end
local function keyrelease(k) releases[#releases+1]=k end
local function isrbxactive() return true end
local UserConfigs={Autofarm=true}
local LocalPlayer={Address=1}
local CharacterCache={[1]={}}
local Qte={Active=false}
local FarmStats={Target="target",Status="attacking"}
local CurrentTitanTarget={}
local LastProgress=0
local function Progress() LastProgress=now end
local rewardsVisible=false
local function IsRetryVisible() return rewardsVisible end
local TitanForm=false
local Vector3Zero=Vector3.new(0,0,0)
local Recovery={Blocked=true,CheckedAt=-math.huge,Braked=false,ReadState=function(h) return h and h.State end}
local function GetHumanoid(c) return c.hum end
local function GetHrp(c) return c.root end
local function body(id)
  local c={Address=id,Parent=true,Ragdoll=false,parts={Head={},UpperTorso={}}}
  c.hum={Health=100,Parent=c,State=8}; c.root={Parent=c,AssemblyLinearVelocity=Vector3.new(0,-400,0)}
  function c:FindFirstChild(n) return self.parts[n] end
  function c:GetAttribute(n) return self[n] end
  return c
end
local c=body(2); LocalPlayer.Character=c
local function tick(t) now=t; Recovery.Tick() end
]====]
  local checks=[====[
UserConfigs.AutoRetry=true;rewardsVisible=true;LocalPlayer.Character=nil
tick(-1);assert(not Recovery.Blocked and FarmStats.Status=="pressing retry" and #beats==0,"rewards without a character belongs to Retry, not recovery")
rewardsVisible=false;LocalPlayer.Character=c;Recovery.Blocked=true
tick(0); assert(Recovery.Blocked,"startup must validate before combat")
tick(0.5); assert(not Recovery.Blocked,"healthy startup resumes")
beats={}; CharacterCache[1].Hrp={old=true}; CharacterCache[1].Humanoid={old=true}
c.hum.Health=90; c.Ragdoll=true; c.hum.State=1; tick(0.8)
assert(Recovery.Blocked and Recovery.Reason=="ragdoll","HP drop/ragdoll interrupts combat")
assert(CharacterCache[1].Hrp==nil and CharacterCache[1].Humanoid==nil,"damage clears stale part cache")
assert(CurrentTitanTarget==nil and FarmStats.Target=="none","recovery drops target")
assert(#beats==1 and beats[1]=="recovering","one recovery marker, never healthy heartbeat")
assert(c.root.AssemblyLinearVelocity.Magnitude==0,"ragdoll braking")
c.root.AssemblyLinearVelocity=Vector3.new(0,-123,0); tick(1.1)
assert(c.root.AssemblyLinearVelocity.Y==-123,"do not brake every tick")
assert(#beats==1,"do not refresh recovery timer")
c.Ragdoll=false; c.hum.State=8; tick(1.4); assert(Recovery.Blocked,"debounce recovery")
tick(1.9); assert(not Recovery.Blocked and beats[2]=="farming","resume after game clears ragdoll")
assert(#presses==1 and presses[1]==0x20,"one normal jump after recovery")
assert(FarmStats.Status=="resuming combat","successful recovery clears its stale status label")
tick(2.0); assert(#releases==1 and releases[1]==0x20,"release jump without waiting for next sample")
-- Positive health must not hide a destroyed character, even after healing.
c.parts.Head=nil; tick(2.3); assert(Recovery.Blocked and Recovery.Reason=="incomplete character body")
local count=#beats; c.hum.Health=100; tick(3)
assert(Recovery.Blocked and #beats==count,"healing does not mark missing body healthy")
-- Prompt ownership prevents braking against grab constraints.
c.parts.Head={}; c.Ragdoll=true; Qte.Active=true; Recovery.Braked=false
c.root.AssemblyLinearVelocity=Vector3.new(0,-88,0); tick(3.3)
assert(Recovery.Reason=="escape / quick time event" and c.root.AssemblyLinearVelocity.Y==-88,"escape prompt owns control")
-- Respawn with fresh body must clear the old HP sample/cache and recover.
Qte.Active=false; c=body(3); LocalPlayer.Character=c; tick(4); tick(4.5)
assert(not Recovery.Blocked and Recovery.Character==3,"fresh character resumes")
LocalPlayer.Character=nil; tick(4.8); assert(Recovery.Blocked,"respawn gap blocks combat")
c=body(4); c.parts.Head=nil; c.parts.UpperTorso=nil; c.Shifter=true; LocalPlayer.Character=c
tick(5.1); tick(5.6); assert(not Recovery.Blocked,"shifted form does not require human body parts")
UserConfigs.Autofarm=false; c.Ragdoll=true; tick(6); assert(not Recovery.Blocked,"manual pause does not request watchdog recovery")
UserConfigs.Autofarm=true; c=body(5); c.Ragdoll=true; LocalPlayer.Character=c; tick(6.3)
assert(not Recovery.Blocked,"sticky Ragdoll attribute does not block a healthy native state")
c.hum.State=nil; tick(6.6); assert(not Recovery.Blocked,"unreadable state does not trust sticky attribute")
Qte.Active=true;tick(7);assert(Recovery.Blocked and Recovery.Reason=="escape / quick time event")
Qte.Active=false;tick(7.3);tick(7.8)
assert(not Recovery.Blocked and FarmStats.Status=="resuming combat","completed escape returns to combat on the same character")
]====]
  assert(loadstring(header..extract(source,"function Recovery.Tick()","-- End character recovery monitor.")..checks,"recovery_"..variant))()
  print("PASS: "..variant.." damage, ragdoll, missing body, escape ownership, respawn, pause, recovery timer")
  local qheader=[====[
local now=0
local os={clock=function() return now end}
local UserConfigs={AutoQTE=true}
local focused=true
local function isrbxactive() return focused end
local function IsObjectVisible(f) return f.visible end
local function Boot() end
local presses,releases={},{}
local function keypress(k) presses[#presses+1]=k end
local function keyrelease(k) releases[#releases+1]=k end
local scale=2
local function memory_read() return scale end
local SizeOffset=0
]====]
  local qchecks=[====[
assert(KeyToVk("F")==0x46 and KeyToVk(" Space ")==0x20 and KeyToVk("<b>E</b>")==0x45)
assert(KeyToVk("unknown")==nil,"never guess an unknown prompt")
Qte.Frame={Parent=true,visible=true}; Qte.Key={Parent=true,Text="F"}; Qte.Timing={Parent=true,Address=1}
QteTick(); assert(#presses==0)
now=.1; scale=1; QteTick(); assert(#presses==1 and presses[1]==0x46,"timed escape prompt")
now=.2; QteTick(); assert(#releases==1,"release prompted key")
now=.3; scale=2; QteTick(); now=.4; scale=1; QteTick(); assert(#presses==2,"same key/new timing cycle rearmed")
UserConfigs.AutoQTE=false; now=.41; QteTick()
assert(not Qte.Active and not Qte.ReleaseAt and #releases==2,"toggle off releases held key")
UserConfigs.AutoQTE=true; Qte.Frame.visible=false; now=.6; QteTick()
Qte.Frame.visible=true; Qte.Timing=nil; Qte.Key.Text="SPACE"; now=.8; QteTick()
assert(presses[#presses]==0x20,"button-only grab prompt uses displayed key")
local before=#presses; now=.9; QteTick(); assert(#presses==before,"do not spam prompt every frame")
now=1.3; QteTick(); assert(#presses==before+1,"repeat button-only escape while visible")
focused=false; now=1.5; QteTick(); before=#presses; now=2; QteTick(); assert(#presses==before,"no escape keys in other apps")
focused=true; Qte.Key.Text="unknown"; now=2.5; QteTick(); assert(#presses==before,"unknown key is ignored")
]====]
  local key=extract(source,"local function KeyToVk(","-- End prompt key mapping.")
  local qte=extract(source,"Qte = {","--#endregion -- Quick time events --")
  assert(loadstring(qheader.."\nlocal Qte\n"..key..qte..qchecks,"qte_"..variant))()
  print("PASS: "..variant.." timed/button escape, repeated prompt, toggle cancellation, key release, focus")
end
