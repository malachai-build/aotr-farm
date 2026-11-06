-- Stage both sources at aotr/reload_tests/{normal,raid}.lua. All input is mocked.
local previous
for _,variant in ipairs({"normal","raid"}) do
  local source=readfile("aotr/reload_tests/"..variant..".lua")
  local a=assert(string.find(source,"--#region -- Human skills --",1,true))
  local b=assert(string.find(source,"--#endregion -- Human skills --",a,true))
  local human=string.sub(source,a,b-1)
  if previous then assert(human==previous,"both scripts must share identical human-skill implementation") end
  previous=human
  local header=[====[
local now, bar, alive, focused, stopped, interacting, shifter = 100, 50, true, true, false, false, nil
local presses,releases={},{}
local os={clock=function() return now end}
local task={wait=function(dt) now += dt end}
local function keypress(k) presses[#presses+1]=k end
local function keyrelease(k) releases[#releases+1]=k end
local function Stopped() return stopped end
local function GetPlayerCharacter(p) return alive and p.Character or nil end
local function GetPlayerHumanoid() return {Parent=true,Health=alive and 100 or 0} end
local function GetPlayerHrp() return {Parent=true} end
local function isrbxactive() return focused end
local function Boot() end
local UserConfigs={HumanSkills=true,Autofarm=true,AwakeningEnabled=true,AwakeningSlot=1}
local Recovery={Blocked=false}
local Qte={Active=false}
local Supplies={Active=nil}
local WhatShouldIBeDoing="attack"
local UI={IsInteracting=function() return interacting end}
local LocalPlayer={Character={GetAttribute=function() return shifter end},GetAttribute=function(self,key)
  if key=="Bar" then return bar elseif key=="Max_Bar" then return 100 end
end}
local Interface={}
local Stats={}
local labels,slots={},{}
local function node(children)
  return {Parent=true,FindFirstChild=function(self,key) return children[key] end}
end
for i=1,5 do
  labels[i]={Text="busy"}
  slots[i]=node({Cooldown=node({Label=labels[i]}),Key=node({Key={Text=tostring(i)}})})
end
local function GetPath(root, warning, ...)
  local path={...}; local last=path[#path]; local index=tonumber(string.match(last,"Skill_(%d)"))
  return slots[index]
end
]====]
  local checks=[====[
local function reset()
  now=100;bar=50;alive=true;focused=true;stopped=false;interacting=false;shifter=nil
  UserConfigs.HumanSkills=true;UserConfigs.Autofarm=true;UserConfigs.AwakeningEnabled=true
  Recovery.Blocked=false;Qte.Active=false;Supplies.Active=nil;WhatShouldIBeDoing="attack"
  presses={};releases={}
  for i=1,5 do labels[i].Text="busy" end
  Stats.HumanSkills={LastSuccess=-math.huge,LastCheck=-math.huge,LastTap=-math.huge,NextSlot=1,
    Pending=nil,PendingSince=0,RetryAfter={},LastBar=nil,AwakeningActive=false,Slots={},Labels={},LabelSince={}}
end
reset();labels[2].Text="0s";labels[3].Text="0s"
assert(not Stats.UseHumanSkill() and presses[1]==0x32 and releases[1]==0x32,"tap ready human skill and release it")
now += 0.21;Stats.UseHumanSkill();assert(#presses==2 and presses[2]==0x32,"retry pending skill between slashes")
labels[2].Text="12s";now += 0.2
assert(Stats.UseHumanSkill() and Stats.HumanSkills.Pending==nil,"countdown confirms success")
local confirmed=Stats.HumanSkills.LastSuccess
now=confirmed+1;assert(not Stats.UseHumanSkill() and #presses==2,"respect success gap")
now=confirmed+2.51;Stats.UseHumanSkill();assert(presses[3]==0x33,"next ready skill after 2.5s")
reset();bar=99;labels[1].Text="0s";Stats.UseHumanSkill();assert(#presses==0,"do not awaken before full charge")
bar=100;now += 0.2;Stats.UseHumanSkill();assert(presses[1]==0x31,"human awakening at full bar")
bar=90;now += 0.2;assert(Stats.UseHumanSkill() and Stats.HumanSkills.AwakeningActive,"bar drain confirms awakening")
now += 3;Stats.UseHumanSkill();assert(#presses==1,"never retrigger awakening while active")
bar=0;now += 0.2;Stats.UseHumanSkill();bar=100;now += 0.2;Stats.UseHumanSkill()
assert(#presses==2,"rearm human awakening after bar empties and recharges")
for _,gate in ipairs({"disabled","farm_off","dead","unfocused","stopped","menu","recovery","qte","reload","refill","task","shifter"}) do
  reset();labels[2].Text="0s"
  if gate=="disabled" then UserConfigs.HumanSkills=false
  elseif gate=="farm_off" then UserConfigs.Autofarm=false
  elseif gate=="dead" then alive=false
  elseif gate=="unfocused" then focused=false
  elseif gate=="stopped" then stopped=true
  elseif gate=="menu" then interacting=true
  elseif gate=="recovery" then Recovery.Blocked=true
  elseif gate=="qte" then Qte.Active=true
  elseif gate=="reload" then Supplies.Active="reload"
  elseif gate=="refill" then Supplies.Active="refill"
  elseif gate=="task" then WhatShouldIBeDoing="market"
  elseif gate=="shifter" then shifter=true end
  assert(not Stats.UseHumanSkill() and #presses==0,"human input suppressed during "..gate)
end
reset();bar=100;UserConfigs.AwakeningEnabled=false;labels[1].Text="0s";labels[2].Text="0s"
Stats.UseHumanSkill()
assert(#presses==1 and presses[1]==0x32,"disabled awakening skips selected slot and still uses ordinary skills")
reset();bar=100;labels[1].Text="0s";Stats.UseHumanSkill();assert(presses[1]==0x31)
UserConfigs.AwakeningEnabled=false;labels[2].Text="0s";now += 0.21;Stats.UseHumanSkill()
assert(presses[#presses]==0x32 and Stats.HumanSkills.Pending==2,"turning awakening off cancels its pending retries")
reset();local burstCalls=0;Stats.Colossal={UseReadySkills=function() burstCalls += 1; return true end}
assert(Stats.UseHumanSkill(true) and burstCalls==1,"preserve Colossal fast-skill delegation")
Stats.Colossal=nil;assert(not Stats.UseHumanSkill(true),"normal farm has no raid-only dependency")
]====]
  local aliveAt=assert(string.find(source,"local function IsLocalAlive(): boolean",1,true))
  local aliveEnd=assert(string.find(source,"-- End local alive check.",aliveAt,true))
  assert(aliveAt<a,"live IsLocalAlive declaration must precede human skills in the real script")
  local aliveSource=string.sub(source,aliveAt,aliveEnd-1)
  assert(loadstring(header..aliveSource..human..checks,"human_skills_"..variant))()
  local active=string.gsub(source,"%-%-%[====%[.-%]====%]","")
  active=string.gsub(active,"%-%-[^\n]*","")
  assert(not string.find(active,"TryShift(",1,true) and not string.find(active,"IsTitanForm(",1,true)
    and not string.find(active,"UseTitanSkill(",1,true),"titan transformation and titan combat must be commented out")
  local first=assert(string.find(active,"local function KillTitan(",1,true))
  local last=assert(string.find(active,"local DeadTitans:",first,true))
  local combat=string.sub(active,first,last-1)
  local pull=assert(string.find(combat,"PullNapesTo(titan, UserConfigs.PullAllNapes and PullList or nil)",1,true))
  local skill=assert(string.find(combat,"Stats.UseHumanSkill(",pull,true))
  local slash=assert(string.find(combat,'Tr.step("main", "slash wait")',pull,true))
  assert(pull<skill and skill<slash,"both scripts use human skills after nape pulling and before slash")
  assert(string.find(active,'main:AddLeftGroupbox("Human Skills")',1,true),"both scripts expose Main/Human Skills controls")
  assert(loadstring(source,"compile_human_"..variant))
  print("PASS: "..variant.." human cooldown/awakening sequencing, safety gates, shared placement, shifting disabled, compilation")
end
