-- Stage both sources at aotr/reload_tests/{normal,raid}.lua. All gameplay is mocked.
local function extract(s, a, b)
  local first = assert(string.find(s, a, 1, true), a)
  local last = assert(string.find(s, b, first, true), b)
  return string.sub(s, first, last - 1)
end
for _, variant in ipairs({"normal", "raid"}) do
  local source = readfile("aotr/reload_tests/" .. variant .. ".lua")
  local header = [====[
local now, reads, skyWrites, tankWrites, presses, releases = 100, 0, 0, 0, 0, 0
local value, setsText, gasText, available, nativeVersion = 1, "3 / 3", "100%", true, "version-f0ea5da9412f4e35"
local focused, stopped, interacting = true, false, false
local behavior, actionStart = "none", 100
local secondReadValue=nil
local Supplies
local logs = {}
local os = {clock=function() return now end}
local function node(children)
  return {Parent=true, FindFirstChild=function(self,key) return children[key] end, GetChildren=function() local out={};for _,c in pairs(children) do out[#out+1]=c end;return out end}
end
local gradient = {ClassName="UIGradient",Address=1000}
local sets = setmetatable({ClassName="TextLabel"}, {__index=function() return setsText end})
local percentage = setmetatable({ClassName="TextLabel"}, {__index=function() return gasText end})
local blades = node({Sets=sets,Inner=node({Bar=node({Gradient=gradient})})})
local gasChildren={Percentage=percentage}
local gui = node({Interface=node({HUD=node({Main=node({Top=node({["7"]=node({Blades=blades,Gas=node(gasChildren)})})})})})})
local LocalPlayer = {FindFirstChild=function() return available and gui or nil end}
local function memory_read(kind,address)
  assert(kind=="float" and address==1296,"only the HUD gradient is read")
  reads += 1; if secondReadValue and reads==2 then value=secondReadValue end; return value
end
local function getrbxversion() return nativeVersion end
local function isrbxactive() return focused end
local function Stopped() return stopped end
local Recovery = {Blocked=false}
local Qte = {Active=false}
local UI = {IsInteracting=function() return interacting end}
local UserConfigs = {AutoReload=true,Autofarm=true}
local function IsLocalAlive() return true end
local WhatShouldIBeDoing, CurrentTitanTarget, TitanForm = "attack", {}, false
local ReloadingBlades, HeavyWrites = false, 0
local FarmStats = {Target="target",Status="attacking"}
local Workspace = {GetDescendants=function() return {} end}
local KnownTitans = {}
local GasTankModel, GasTankPosition = nil, Vector3.new(1,2,3)
local Vector3New, Vector3Zero = Vector3.new, Vector3.new(0,0,0)
local PrimaryPartOffset, BaseToPrimitiveOffset, PrimitivePositionOffset = 0, 0, 0
local function HandleDifferentGasTankPaths() end
local rootPosition = Vector3.new(1,2,3)
local rootVelocity = Vector3.new(0,-300,0)
local velocityWrites, lastBrake = 0, 0
local hrp = setmetatable({Parent=true}, {__index=function(self,key) if key=="Position" then return rootPosition elseif key=="AssemblyLinearVelocity" then return rootVelocity end end, __newindex=function(self,key,v)
  if key=="CFrame" then skyWrites += 1; assert(WhatShouldIBeDoing=="reload","reload teleport only during reload")
  elseif key=="Position" then tankWrites += 1; if behavior~="refill_tp_ignored" and not (behavior=="refill_first_tp_ignored" and tankWrites==1) then rootPosition=v end; assert(WhatShouldIBeDoing=="refill")
  elseif key=="AssemblyLinearVelocity" then rootVelocity=v;velocityWrites+=1;if v.Magnitude==0 then lastBrake=now end end
end})
local function GetPlayerHrp() return hrp end
local function IsValid(o) return o and o.Parent end
local function SafePosNow() return "sky" end
local function Progress() end
local Tr = {step=function() end}
local function Boot(s) logs[#logs+1]=s end
local function keypress(k) assert(k==0x52); presses += 1 end
local function keyrelease(k) assert(k==0x52); releases += 1 end
local task = {wait=function(dt)
  now += dt
  if Supplies.Active=="reload" and velocityWrites>0 then assert(now-lastBrake<=0.201,"blade reload hold cannot leave a half-second gap") end
  if Supplies.Active then assert(Supplies.Action()==nil,"active reload/refill cannot start a second action") end
  if behavior=="reload_success" and now-actionStart>=0.8 then value=1 end
  if behavior=="reload_missing_hud" then
    if now-actionStart>=0.2 and now-actionStart<0.8 then value=nil;gasText="loading"
    elseif now-actionStart>=0.8 then value=1;gasText="100%" end
  end
  if (behavior=="refill_success" or behavior=="refill_first_tp_ignored") and now-actionStart>=1.2 then setsText="3 / 3";gasText="100%" end
  if behavior=="refill_missed_first" and presses>=2 then setsText="3 / 3";gasText="100%" end
  if behavior=="refill_partial" and presses>=1 then setsText=presses>=2 and "3 / 3" or "1 / 3";gasText="100%" end
  if behavior=="refill_partial_stuck" and presses>=1 then setsText="2 / 3";gasText="100%" end
  if behavior=="refill_ground" or behavior=="refill_momentum" then
    if behavior=="refill_momentum" and now-actionStart<0.2 then rootVelocity=Vector3.new(8,rootVelocity.Y,6) end
    rootVelocity=Vector3.new(0,rootVelocity.Y-20*dt,0)
    rootPosition=rootPosition+rootVelocity*dt
    if rootPosition.Y<=0 then
      rootPosition=Vector3.new(rootPosition.X,0,rootPosition.Z)
      rootVelocity=Vector3.new(0,0,0)
      if presses>=1 then setsText="3 / 3";gasText="100%" end
    end
  end
  if behavior=="lose_focus" then focused=false end
end}
]====]
  local checks = [====[
local function reset(x, count, gas)
  now=100; actionStart=now;value=x;setsText=count or "3 / 3";gasText=gas or "100%"
  available=true;focused=true;stopped=false;interacting=false;behavior="none"
  nativeVersion="version-f0ea5da9412f4e35"
  secondReadValue=nil;gasChildren.Percentage=percentage;gasChildren.unnamed=nil;gasChildren.extra=nil
  reads=0;skyWrites=0;tankWrites=0;presses=0;releases=0;logs={}
  Supplies.Hud=nil;Supplies.HudAt=-math.huge;Supplies.NextReloadAt=0
  Supplies.Active=nil;Supplies.KeyDown=false;Supplies.VersionChecked=false
  Supplies.RefillRoot=nil;Supplies.RefillPosition=nil;rootPosition=Vector3.new(1,2,3)
  Supplies.RefillBrakeUntil=nil;Supplies.EmptyLocked=false
  rootVelocity=Vector3.new(0,-300,0);velocityWrites=0;lastBrake=now
  Supplies.ReadyAt=now;Supplies.SettleUntil=0;Supplies.LastSets=nil;Supplies.LastDurability=nil
  Supplies.SupplyUnknownSince=nil;Supplies.DurabilityUnknownSince=nil
  WhatShouldIBeDoing="attack";ReloadingBlades=false;Recovery.Blocked=false;Qte.Active=false
  GasTankPosition=Vector3.new(1,2,3)
end
local function maturedAction()
  Supplies.Action(); now += 2.01
  return Supplies.Action()
end
for _,x in ipairs({1,0.5,0.02}) do
  reset(x)
  assert(not AreBladesFullyBroken() and Supplies.Action()==nil)
  for i=1,10 do assert(not HandleAllReloads()) end
  assert(skyWrites==0 and tankWrites==0 and presses==0,"healthy blades never start reload or move to sky")
  assert(reads==1,"reuse one HUD sample for 100ms")
end
for _,x in ipairs({-0.15000000596046448,-0.1,0}) do
  reset(x);assert(AreBladesFullyBroken() and Supplies.Action()=="reload","empty range includes float boundary")
end
reset(-0.1502);assert(maturedAction()=="refill","invalid gradient follows unknown refill fallback")
reset(nil);assert(maturedAction()=="refill","unreadable gradient attempts refill")
reset(1,"broken");assert(maturedAction()=="refill","unreadable counter attempts refill")
for _,x in ipairs({1,0.5,0.001}) do
  reset(x," 0 / 3 ");assert(Supplies.Action()==nil,"0/3 keeps farming while equipped blades have durability")
end
for _,x in ipairs({-0.15000000596046448,-0.1,0}) do
  reset(x," 0 / 3 ");assert(Supplies.Action()=="refill","0/3 with empty gradient refills")
  reset(x,"1 / 3");assert(Supplies.Action()=="reload","empty gradient with spare sets reloads instead")
end
reset(1,"3 / 3","0%");assert(Supplies.Action()=="refill","empty gas still refills")
reset(1);nativeVersion="unverified-client";assert(maturedAction()=="refill" and reads==0,"unknown layouts never read a guessed offset")
reset(1);available=false;assert(maturedAction()=="refill","missing HUD attempts refill")
reset(-0.15);behavior="reload_success"
assert(HandleAllReloads());assert(skyWrites>=1 and tankWrites==0 and presses==1 and releases==1)
assert(not ReloadingBlades and not Supplies.Active and WhatShouldIBeDoing=="attack")
assert(value==1 and string.find(logs[#logs],"confirmed",1,true),"reload waits for full HUD confirmation")
assert(rootVelocity.Y==-300,"combat momentum restored after reload")
local writesAfterReload=skyWrites
assert(not HandleAllReloads() and skyWrites==writesAfterReload,"no immediate repeated reload")
reset(-0.15);behavior="none";assert(HandleAllReloads())
assert(string.find(logs[#logs],"failed",1,true) and not Supplies.Active and not ReloadingBlades)
assert(Supplies.Action()==nil,"failed reload resumes combat during bounded retry delay")
reset(-0.15);behavior="lose_focus";assert(HandleAllReloads())
assert(presses==1 and releases==1 and not Supplies.KeyDown,"focus loss releases R and cleans up action")
assert(rootVelocity.Magnitude==0,"interrupted action must not restore combat velocity")
reset(-0.15,"0 / 3");behavior="refill_success";assert(HandleAllReloads())
assert(tankWrites==2 and skyWrites==0 and presses==1 and releases==1)
assert(string.find(logs[#logs],"confirmed",1,true) and WhatShouldIBeDoing=="attack")
assert(rootVelocity.Y==-300,"combat momentum restored after refill")
assert(not Supplies.RefillRoot and not Supplies.RefillPosition,"refill positioning is cleared after completion")
reset(-0.15,"0 / 3");behavior="refill_first_tp_ignored";rootPosition=Vector3.new(1,1127,3);assert(HandleAllReloads())
assert(rootPosition.Y==2 and string.find(logs[#logs],"confirmed",1,true),"secondary teleport must not reuse sky height when first teleport fails")
reset(-0.15,"0 / 3");behavior="refill_tp_ignored";rootPosition=Vector3.new(1,1127,3);assert(HandleAllReloads())
assert(presses==0 and string.find(logs[#logs],"failed",1,true),"do not press R when neither teleport reached the station")
reset(-0.15,"0 / 3");behavior="refill_missed_first";assert(HandleAllReloads())
assert(presses==2 and releases==2 and tankWrites==2 and string.find(logs[#logs],"confirmed",1,true),"missed first input retries without moving a stationary character")
reset(-0.15,"0 / 3");behavior="refill_partial";assert(HandleAllReloads())
assert(presses==2 and setsText=="3 / 3" and string.find(logs[#logs],"confirmed",1,true),"partial sets and gas increase must retry until 3/3")
reset(-0.15,"0 / 3");behavior="refill_partial_stuck";assert(HandleAllReloads())
assert(presses>1 and string.find(logs[#logs],"failed",1,true),"2/3 never confirms a successful refill")
reset(-0.15,"0 / 3");behavior="refill_ground";assert(HandleAllReloads())
assert(tankWrites==2 and skyWrites==0 and rootPosition.Y==0 and string.find(logs[#logs],"confirmed",1,true),"secondary teleport preserves the ground reached during the initial drop")
assert(velocityWrites>=5 and velocityWrites<=10,"arrival braking is brief and ends before landing")
reset(-0.15,"0 / 3");behavior="refill_momentum"
Supplies.Active="refill";Supplies.RefillRoot=hrp;Supplies.HoverAt=-math.huge
Supplies.RefillBrakeUntil=now+0.15
rootVelocity=Vector3.new(100,70,80)
Supplies.HoldReload()
assert(rootVelocity.Magnitude==0,"arrival brake cancels all axes including upward bounce")
now+=0.2
rootVelocity=Vector3.new(100,-25,80)
Supplies.HoldReload()
assert(rootVelocity.X==0 and rootVelocity.Z==0 and rootVelocity.Y==-25,"refill brake cancels horizontal motion while preserving the fall")
assert(tankWrites==0 and skyWrites==0,"horizontal brake never pins position")
Supplies.Active=nil;Supplies.RefillRoot=nil
Supplies.RefillBrakeUntil=nil
reset(-0.15,"0 / 3");assert(HandleAllReloads())
assert(string.find(logs[#logs],"failed",1,true) and WhatShouldIBeDoing=="attack" and Supplies.CombatLocked())
assert(presses>1 and presses<=5 and releases==presses,"retries stay bounded and release every key")
assert(Supplies.Action()=="refill" and Supplies.CombatLocked(),"failed refill immediately retries and never releases combat")
assert(rootVelocity.Magnitude==0,"failed empty refill must not restore combat momentum")
Recovery.Blocked=true;assert(Supplies.Action()==nil and Supplies.CombatLocked(),"grab/ragdoll pauses refill without clearing empty lock")
Recovery.Blocked=false;assert(Supplies.Action()=="refill","recovery immediately returns to refilling")
available=false;now+=0.2;Supplies.ReadHud(true);assert(Supplies.CombatLocked(),"unknown HUD cannot clear confirmed-empty lock")
available=true;setsText="2 / 3";Supplies.ReadHud(true);assert(Supplies.CombatLocked(),"partial refill cannot release combat")
setsText="3 / 3";Supplies.ReadHud(true);assert(not Supplies.CombatLocked(),"3/3 releases combat lock")
reset(0.5);available=false;GasTankPosition=nil;assert(maturedAction()=="refill");assert(not HandleAllReloads())
assert(presses==0 and skyWrites==0 and tankWrites==0)
assert(Supplies.Action()=="refill" and WhatShouldIBeDoing=="attack","missing destination never disables safety hover or imposes a refill cooldown")

-- The live failure: gas percentage text exists but the label has no name.
reset(1);gasText="91%";gasChildren.Percentage=nil;gasChildren.unnamed=percentage
local live=Supplies.ReadHud(true)
assert(live.Gas==91 and not live.Unknown and Supplies.Action()==nil,"unnamed gas label must not cause refill")
reset(1);gasText="<font color='#ffffff'> 91% </font>";setsText="<b>3 / 3</b>"
assert(Supplies.ReadHud(true).Gas==91 and Supplies.ReadHud().Sets==3 and Supplies.Action()==nil,"strip rich text before reading counters")
reset(1);gasChildren.Percentage=nil;gasChildren.unnamed=percentage;gasChildren.extra={ClassName="TextLabel",Text="50%"}
assert(Supplies.ReadHud(true).Gas==nil,"ambiguous unnamed labels stay unknown")
-- Startup gets a short observation period, including genuine empty supplies.
reset(-0.15,"0 / 3");Supplies.ReadyAt=nil
assert(Supplies.Action()==nil);now=101.99;assert(Supplies.Action()==nil)
now=102.01;assert(Supplies.Action()=="refill","0/3 and empty gradient refills after startup observation")
reset(1);Supplies.ReadyAt=nil;available=false
assert(Supplies.Action()==nil);now=101;available=true
assert(Supplies.Action()==nil);now=102.01;assert(Supplies.Action()==nil,"HUD appearing during startup never causes a false refill")
-- Unknown data must persist, rather than one animation frame starting a refill.
reset(0.5);gasText="loading";assert(Supplies.Action()==nil)
now=101;gasText="100%";assert(Supplies.Action()==nil)
now=104;assert(Supplies.Action()==nil,"transient unreadable counter clears fallback timer")
reset(0.5);gasText="loading";assert(Supplies.Action()==nil)
now=102.01;local action,reason=Supplies.Action()
assert(action=="refill" and reason=="supply HUD unreadable","persistent unknown HUD still attempts refill")
-- An externally initiated reload can cross the empty range while the bar rises.
reset(-0.15);Supplies.ReadHud(true)
now=100.11;setsText="2 / 3";value=-0.05
assert(Supplies.Action()==nil,"spare consumption and rising bar indicate an ongoing reload")
now=100.3;value=0;assert(Supplies.Action()==nil,"rising bar crossing zero cannot start another action")
now=100.5;value=1;assert(Supplies.Action()==nil)
now=101.51;assert(Supplies.Action()==nil,"healthy post-reload HUD resumes without refill")
reset(-0.15);behavior="reload_missing_hud"
assert(HandleAllReloads() and presses==1 and tankWrites==0 and value==1)
assert(Supplies.Action()==nil and string.find(logs[#logs],"confirmed",1,true),"missing HUD during reload never chains into refill")
reset(-0.15);secondReadValue=1
assert(not HandleAllReloads() and presses==0 and skyWrites==0,"revalidate fresh HUD before committing to an action")

reset(-0.15);focused=false;assert(not HandleAllReloads() and presses==0)
reset(-0.15);interacting=true;assert(not HandleAllReloads() and presses==0)
reset(-0.15);Qte.Active=true;assert(not HandleAllReloads() and presses==0)
reset(-0.15);Recovery.Blocked=true;assert(not HandleAllReloads() and presses==0)
]====]
  local state = extract(source, "local Supplies = {", "-- End supply state.")
  state = string.gsub(state,"local Supplies =", "Supplies =",1)
  local hud = extract(source, "-- HUD supply state.", "-- End supply HUD.")
  local handlers = extract(source, "function Supplies.CanContinue()", "--#endregion Gas tank functions --")
  assert(loadstring(header .. state .. hud .. handlers .. checks, "hud_reload_" .. variant))()
  assert(loadstring(source, "compile_" .. variant))
  local forward = assert(string.find(source,"local Qte -- Forward declaration:",1,true))
  local consumer = assert(string.find(source,"function Supplies.CanContinue()",1,true))
  assert(forward < consumer and not string.find(source,"local Qte = {",1,true),"QTE must be in lexical scope before supply handlers")
  assert(not string.find(source,"TransparencyBasePartOffset",1,true),"transparency detector removed")
  assert(string.find(source,'Tr.step("render", "park, no target (write)")',1,true),"no-target safety hover preserved")
  print("PASS: " .. variant .. " HUD thresholds, unnamed/rich-text counters, startup/reload settling, persistent-unknown retry, empty combat lock, immediate refill retry, fresh revalidation, cleanup, safety hover, compilation")
end
