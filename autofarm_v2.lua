-- AoTR farm v2 for Matcha. Stage as aotr/autofarm_v2.lua; autoexec still loads autofarm.lua.
-- The loader must task.spawn(loadstring(readfile(...))) before its first yield.
local S = {
  id = tostring(os.clock()) .. ":" .. tostring(math.random(1000000)),
  cfg = {
    Autofarm=true, AutoRetry=true, AutoReload=true, AutoQTE=true, MenuDisabled=false,
    NapeSize=15, PullAllNapes=false, PullRadius=5000, PullCount=6,
    PullEvery=2, PullPerFrame=1, PullExtraInterval=0.05, AttackDelay=0.06,
    HeightNormal=120, HeightStall=100, HeightAttack=160, HeightColossal=200,
    BobAmplitude=2, HoverOffsetX=0, HoverOffsetZ=0, NapeOffsetY=2, SafeHeight=9999,
    ShiftEnabled=false, ShiftKey=1, TitanSkills=true, TitanSkillDelay=0.8,
    TitanStrikeDistance=18, TitanRetreatHp=0.35, TitanReturnHp=0.8,
    NoKillMinutes=5, BossNoKillMinutes=20, DebugMode=false,
  },
  stats={kills=0, shifts=0, status="starting", target="none"},
  world={}, entries={}, list={}, target=nil, extras={}, extraAt=0, extraIndex=1,
  mode="loading", progress=os.clock(), lastKill=os.clock(), lastBeat=0,
  lastBoot="", trace={}, traceTimes={}, traceHead=0, traceAt=0,
  history={}, boxAt=0, lastBox="",
  slash=0, lastHover=0, lastPark=0, lastSlash=0, lastSkill=0,
  lastShift=0, shiftSince=0, form=false, lastBar=nil, barDrop=0,
  qte={}, ui={}, retryCount=0, retrySince=nil, refillSince=nil,
  sized={}, sizedCount=0, skipped=0, parkY=nil, wasFarm=false, wasEnd=false,
  legacySettings={},
}
_G.AotrRunId = S.id
_G.AotrStop = false
local function stopped() return _G.AotrStop == true or _G.AotrRunId ~= S.id end
local function same(a,b) return a and b and a.Address and b.Address and a.Address == b.Address end
local function path(root, ...)
  local node = root
  for _, name in ipairs({...}) do
    node = node and node:FindFirstChild(name)
    if not node then return nil end
  end
  return node
end
local function boot(msg)
  if msg == S.lastBoot then return end
  S.lastBoot = msg
  pcall(function()
    local p="aotr/boot.txt"
    local old=(isfile(p) and readfile(p)) or ""
    if #old > 12000 then old=string.sub(old,-6000) end
    writefile(p,old .. os.date("%H:%M:%S") .. " v2 " .. msg .. "\n")
  end)
end
local function trace(step)
  local i=S.traceHead%32+1
  S.traceHead=i
  S.trace[i]=step
  S.traceTimes[i]=os.clock()
end
local function traceText()
  local lines={}
  for n=1,32 do
    local i=(S.traceHead+n-1)%32+1
    if S.trace[i] then
      lines[#lines+1]=string.format("%.2f %s",S.traceTimes[i],S.trace[i])
    end
  end
  return table.concat(lines,"\n")
end
local function beat(state)
  pcall(writefile,"aotr/heartbeat.txt",state .. " " .. os.date("%H:%M:%S"))
end
local function progress() S.progress=os.clock() end
local function live(e)
  if not e or not e.model or not e.hum or not e.hit or not e.weak then return false end
  local folder=S.world.titans
  if not folder or not same(e.model.Parent,folder) then return false end
  if not same(e.weak.Parent,e.hit) then return false end
  local ok,hp=pcall(function() return e.hum.Health end)
  return ok and type(hp)=="number" and hp>0
end
local function weak(e)
  if not e.boss or os.clock()-(e.weakAt or 0)<0.5 then return end
  e.weakAt=os.clock()
  local marker=e.model:FindFirstChild("Marker")
  if not marker or not e.hit then return end
  local ok,addr=pcall(memory_read,"uintptr_t",marker.Address+0x710)
  if not ok or not addr or addr==0 then return end
  for _,part in ipairs(e.hit:GetChildren()) do
    if part.Address==addr then e.weak=part; return end
  end
  e.weak=e.nape
end
local function entry(model)
  local hit=path(model,"Hitboxes","Hit")
  local nape=hit and hit:FindFirstChild("Nape")
  local hum=model:FindFirstChildOfClass("Humanoid")
  local root=model:FindFirstChild("HumanoidRootPart")
  if not (hit and nape and hum and root) then return nil end
  local ok,boss=pcall(function() return model:GetAttribute("Shifter") end)
  local okType,kind=pcall(function() return model:GetAttribute("Type") end)
  return {model=model,hit=hit,nape=nape,weak=nape,hum=hum,root=root,
    boss=ok and boss~=nil and boss~=false,kind=okType and kind or "Normal",name=model.Name}
end
local function char()
  local lp=S.world.player
  local model=lp and lp.Character
  if not model then S.world.char=nil; S.world.root=nil; S.world.hum=nil; return end
  if not same(model,S.world.char) then
    S.world.char=model
    S.world.root=nil; S.world.hum=nil
  end
  if not S.world.root or not same(S.world.root.Parent,model) then
    S.world.root=model:FindFirstChild("HumanoidRootPart")
  end
  if not S.world.hum or not same(S.world.hum.Parent,model) then
    S.world.hum=model:FindFirstChildOfClass("Humanoid")
  end
end
local function collect()
  local w=S.world
  w.players=w.players or game:GetService("Players")
  w.player=w.players and w.players.LocalPlayer
  w.workspace=w.workspace or game:GetService("Workspace")
  w.titans=w.workspace and w.workspace:FindFirstChild("Titans")
  w.gui=w.player and w.player:FindFirstChild("PlayerGui")
  w.interface=w.gui and w.gui:FindFirstChild("Interface")
  char()
  if not w.titans then return end
  local nextEntries,nextList={},{}
  for _,model in ipairs(w.titans:GetChildren()) do
    local id=model.Address
    if id then
      local e=S.entries[id]
      if not e or not same(e.model,model) or not same(e.model.Parent,w.titans) then e=entry(model) end
      if e and live(e) then nextEntries[id]=e; nextList[#nextList+1]=e end
    end
  end
  S.entries=nextEntries; S.list=nextList
  if w.interface then
    S.ui.rewards=path(w.interface,"Rewards")
    S.ui.qte=path(w.interface,"QTE")
    S.ui.timing=path(S.ui.qte,"Main","Timing")
    S.ui.key=path(S.ui.qte,"Main","Key")
    S.ui.blades=path(w.interface,"HUD","Main","Top","7","Blades","Sets")
    S.ui.gas=path(w.interface,"HUD","Main","Top","7","Gas","Percentage")
    for i=1,5 do
      S.ui["skill"..i]=path(w.interface,"HUD","Main","Top","7","Hotbar","Skill_"..i,"Key","Key")
    end
  end
  -- Keep a removed target until the actor records its kill.
end
local function choose()
  local root=S.world.root
  if not root then return nil end
  local p=root.Position
  local best,d=nil,math.huge
  for _,e in ipairs(S.list) do
    if live(e) then
      local q=e.root.Position
      local dist=(q-p).Magnitude
      if dist<d and (not S.form or dist>3) and dist<4000 then best,d=e,dist end
    end
  end
  return best
end
local function extras(target)
  local list={}
  local pos=target.root.Position
  local radius=S.cfg.PullRadius>=5000 and math.huge or S.cfg.PullRadius
  for _,e in ipairs(S.list) do
    if e.model.Address~=target.model.Address and live(e) then
      local d=(e.root.Position-pos).Magnitude
      if d<=radius then list[#list+1]={e=e,d=d} end
    end
  end
  table.sort(list,function(a,b) return a.d<b.d end)
  S.extras={}
  for i=1,math.min(#list,math.max(0,S.cfg.PullCount-1)) do S.extras[i]=list[i].e end
  S.extraIndex=1; S.extraAt=os.clock()
end
local function pull(e)
  local root=S.world.root
  if not root or not live(e) then S.skipped+=1; return end
  if not S.target or not live(S.target) then return end
  if (root.Position-S.target.root.Position).Magnitude>600 then return end
  weak(e)
  if not live(e) then S.skipped+=1; return end
  local dest=root.CFrame*CFrame.new(0,S.cfg.NapeOffsetY,0)
  if (e.weak.Position-dest.Position).Magnitude>3 then
    trace("nape CFrame "..e.name)
    e.weak.CFrame=dest
  end
  local size=math.floor(S.cfg.NapeSize)
  if S.sized[e.weak.Address]~=size then
    if not live(e) then S.skipped+=1; return end
    trace("nape Size "..e.name)
    e.weak.Size=Vector3.new(size,size,size)
    S.sized[e.weak.Address]=size; S.sizedCount+=1
    if S.sizedCount>1000 then S.sized={}; S.sizedCount=0 end
  end
end
local function hover()
  local root=S.world.root
  if not root or not root.Parent then return end
  if S.refillSince then return end -- do not pull away from the gas tank during refill
  local now=os.clock()
  local t=S.target
  if t and live(t) and isrbxactive() then
    local pt=t.root.Position
    if S.form then
      weak(t)
      if not live(t) then return end
      local hp=S.world.hum
      local ratio=hp and hp.MaxHealth>0 and hp.Health/hp.MaxHealth or 1
      if S.retreat then S.retreat=ratio<S.cfg.TitanReturnHp
      else S.retreat=ratio<S.cfg.TitanRetreatHp end
      local part=t.weak
      local sp=part.Position
      local rp=root.Position
      local delta=Vector3.new(rp.X-pt.X,0,rp.Z-pt.Z)
      local away=delta.Magnitude>1 and delta.Unit or Vector3.new(1,0,0)
      local stand
      if S.retreat then stand=pt+Vector3.new(0,S.cfg.HeightNormal,0)+away*S.cfg.TitanStrikeDistance
      else stand=sp+away*S.cfg.TitanStrikeDistance end
      trace("titan hover")
      root.CFrame=CFrame.lookAt(stand,Vector3.new(sp.X,stand.Y,sp.Z))
      root.AssemblyLinearVelocity=Vector3.new(0,0,0)
    else
      local height=S.cfg["Height"..t.kind] or S.cfg.HeightNormal
      local bob=math.sin(now*math.pi*2)*S.cfg.BobAmplitude
      trace("human hover")
      root.CFrame=CFrame.new(pt.X+S.cfg.HoverOffsetX,pt.Y+height+bob,pt.Z+S.cfg.HoverOffsetZ)
    end
    S.lastHover=now
    return
  end
  if S.form or now-S.lastPark<0.5 then return end
  S.lastPark=now
  local p=root.Position
  local y=S.cfg.SafeHeight
  -- Park only if drifted: zero gravity velocity while idle or unfocused.
  if math.abs(p.X-900)>15 or math.abs(p.Y-y)>15 or math.abs(p.Z-900)>15 then
    trace("park CFrame")
    root.CFrame=CFrame.new(900,y,900)
  end
  if root.AssemblyLinearVelocity.Magnitude>1 then root.AssemblyLinearVelocity=Vector3.new(0,0,0) end
end
local function visible(obj)
  local off=S.offsets and S.offsets.GuiObject and S.offsets.GuiObject.Visible
  if not obj or not obj.Parent or not off then return false end
  local ok,v=pcall(memory_read,"byte",obj.Address+off)
  return ok and v~=0
end
local function key(text)
  if type(text)~="string" then return nil end
  local b=string.byte(string.upper(string.gsub(text,"%s","")))
  if b and ((b>=48 and b<=57) or (b>=65 and b<=90)) then return b end
end
local function qte()
  local ui=S.ui
  local q=S.qte
  if q.release and os.clock()>=q.release then pcall(keyrelease,q.vk); q.release=nil end
  if not S.cfg.AutoQTE or not visible(ui.qte) or not ui.timing or not ui.key then q.active=false; return false end
  local off=S.offsets and S.offsets.GuiObject and S.offsets.GuiObject.Size
  if not off then return false end
  local ok,scale=pcall(memory_read,"float",ui.timing.Address+off)
  if not ok or type(scale)~="number" then return false end
  local now=os.clock()
  local text=ui.key.Text
  if not q.active or text~=q.text or (q.scale and scale>q.scale+0.5) then
    q.active=true; q.text=text; q.vk=key(text); q.start=now; q.move=now; q.pressed=false
  end
  if q.scale and math.abs(scale-q.scale)>0.001 then q.move=now end
  local crossed=q.scale and (q.scale-1)*(scale-1)<0
  q.scale=scale
  if q.vk and not q.pressed and (math.abs(scale-1)<0.06 or crossed or now-q.move>0.35) then
    q.pressed=true; keypress(q.vk); q.release=now+0.05
  end
  return true
end
local function tap(vk)
  keypress(vk); task.wait(0.05); keyrelease(vk)
end
local function form()
  local w=S.world
  local player=w.player
  if not player then return end
  local ok,bar,max=pcall(function() return player:GetAttribute("Bar"),player:GetAttribute("Max_Bar") end)
  if not ok then return end
  bar=tonumber(bar); max=tonumber(max) or 100
  if bar and S.lastBar and bar<S.lastBar-0.01 then S.barDrop=os.clock() end
  S.lastBar=bar
  local okAttr,attr=pcall(function() return w.char and w.char:GetAttribute("Shifter") end)
  local yes=(okAttr and attr~=nil) or (bar and bar>0 and os.clock()-S.barDrop<1.5)
  if yes~=S.form then
    S.form=yes
    if yes then S.stats.shifts+=1; S.shiftSince=os.clock() end
    boot(yes and "titan form" or "human form")
  end
  if S.cfg.ShiftEnabled and not yes and bar and bar>=max and os.clock()-S.lastShift>3 and not S.refillSince then
    S.lastShift=os.clock()
    for _=1,12 do
      if stopped() or S.form then break end
      tap(0x30+math.clamp(math.floor(S.cfg.ShiftKey),1,5))
      task.wait(0.07)
      local b=player:GetAttribute("Bar")
      if type(b)=="number" and b<bar then break end
    end
  end
end
local function skill()
  if not S.form or not S.cfg.TitanSkills or os.clock()-S.lastSkill<S.cfg.TitanSkillDelay then return end
  S.lastSkill=os.clock(); S.skillIndex=(S.skillIndex or 0)%5+1
  local label=S.ui["skill"..S.skillIndex]
  tap(key(label and label.Text) or (0x30+S.skillIndex))
end
local function gasTank()
  local w=S.world.workspace
  if not w then return nil end
  local routes={
    {"Climbable","Walls","Gate","GasTanks"}, {"Unclimbable","Camps","Camp","GasTanks"},
    {"Climbable","_Walls","Gate","GasTanks"}, {"Climbable","Utgard","GasTanks"},
    {"Unclimbable","World","Buildings","Hanger","GasTanks"},
    {"Unclimbable","Buildings","Hanger","GasTanks"},
    {"Unclimbable","Props","HQ","GasTanks"}, {"Unclimbable","Reloads","GasTanks"},
    {"Unclimbable","Objective","Waves","GasTanks"},
  }
  for _,route in ipairs(routes) do
    local group=path(w,table.unpack(route))
    if group then
      local part=group:FindFirstChild("Refill") or group.PrimaryPart
      if part and part.Position then return part.Position end
      local off=S.offsets
      if off and off.Model and off.BasePart and off.Primitive then
        local ok,pos=pcall(function()
          local p=memory_read("uintptr_t",group.Address+off.Model.PrimaryPart)
          local prim=memory_read("uintptr_t",p+off.BasePart.Primitive)
          local a=prim+off.Primitive.Position
          return Vector3.new(memory_read("float",a),memory_read("float",a+4),memory_read("float",a+8))
        end)
        if ok then return pos end
      end
    end
  end
end
local function supplies()
  local w=S.world
  if S.form or not w.char or not w.root or not w.hum then return false end
  local rig=w.char:FindFirstChild("Rig_"..w.player.Name)
  local rightHand=rig and rig:FindFirstChild("RightHand")
  local leftHand=rig and rig:FindFirstChild("LeftHand")
  if not (rightHand and leftHand) then return false end
  local right=rightHand:FindFirstChild("Blade_1")
  local left=leftHand:FindFirstChild("Blade_1")
  local off=S.offsets and S.offsets.BasePart and S.offsets.BasePart.Transparency
  local broken=not right or not left
  if not broken then
    if not off then
      S.target=nil; S.stats.status="blade check unavailable"
      return true
    end
    local readOk,result=pcall(function()
      return memory_read("float",right.Address+off)>=0.9
        and memory_read("float",left.Address+off)>=0.9
    end)
    if not readOk then
      S.target=nil; S.stats.status="blade read failed"
      return true
    end
    broken=result
  end
  if not broken then S.refillSince=nil; return false end
  if not isrbxactive() then
    S.target=nil; S.stats.status="waiting for focus to reload"
    S.refillSince=nil
    return true
  end
  S.target=nil; S.stats.status="reloading"; S.refillSince=S.refillSince or os.clock()
  local blade=tonumber((S.ui.blades and S.ui.blades.Text or ""):match("%d+")) or 0
  local gas=tonumber((S.ui.gas and S.ui.gas.Text or ""):match("%d+")) or 0
  if blade==0 or gas==0 then
    local pos=gasTank()
    if pos then
      trace("gas tank")
      w.root.AssemblyLinearVelocity=Vector3.new(0,0,0)
      w.root.Position=pos+Vector3.new(5,0,0)
      task.wait(0.4); tap(0x52); task.wait(1)
    end
  else
    w.root.CFrame=CFrame.new(900,S.cfg.SafeHeight,900)
    w.root.AssemblyLinearVelocity=Vector3.new(0,0,0)
    tap(0x52); task.wait(0.5)
  end
  return true
end
local function retry()
  if not S.cfg.AutoRetry or not visible(S.ui.rewards) then S.retrySince=nil; S.heartbeatPaused=false; return false end
  S.target=nil; S.stats.status="pressing retry"
  S.retrySince=S.retrySince or os.clock()
  if S.retryCount%4<3 then
    tap(0xDC); task.wait(1); tap(0x44); task.wait(0.4)
    tap(0x44); task.wait(0.4); tap(0x0D)
  else
    local button=path(S.ui.rewards,"Main","Info","Main","Buttons","Retry")
    if button then
      local p=button.AbsolutePosition; local sz=button.AbsoluteSize
      mousemoveabs(p.X+sz.X/2,p.Y+sz.Y/2+36); task.wait(0.5); mouse1click()
    end
  end
  S.retryCount+=1; task.wait(3)
  return true
end
local function giveUp()
  S.target=nil; S.stats.status="no kill; feeding titan"
  boot(S.stats.status)
  local start=os.clock()
  while not stopped() and os.clock()-start<30 do
    local t=choose(); local root=S.world.root; local hum=S.world.hum
    if not hum or hum.Health<=0 then break end
    if t and root and live(t) then
      root.AssemblyLinearVelocity=Vector3.new(0,0,0)
      local p=t.root.Position; root.CFrame=CFrame.new(p.X,p.Y,p.Z)
    end
    progress(); task.wait(2)
  end
  S.lastKill=os.clock()
end
local function box()
  local w=S.world
  local p=w.root and w.root.Position
  return string.format("%s status=%s kills=%d shifts=%d target=%s alive=%d y=%s skipped=%d",
    os.date("%H:%M:%S"),S.stats.status,S.stats.kills,S.stats.shifts,S.stats.target,#S.list,
    p and string.format("%.0f",p.Y) or "?",S.skipped)
end
local function dump(reason)
  pcall(function()
    local p="aotr/deaths.txt"; local old=(isfile(p) and readfile(p)) or ""
    if #old>60000 then old=string.sub(old,-30000) end
    writefile(p,old .. "=== " .. reason .. " " .. os.date("%H:%M:%S") .. "\n" .. table.concat(S.history,"\n") .. "\n")
  end)
end
local function loadSettings()
  pcall(function()
    if not isfile("aotr_farm.json") then return end
    local data=game:GetService("HttpService"):JSONDecode(readfile("aotr_farm.json"))
    if type(data)~="table" then return end
    S.legacySettings=data
    for k,v in pairs(S.cfg) do
      if type(data[k])==type(v) and k~="MenuDisabled" then S.cfg[k]=data[k] end
    end
  end)
end
local function saveSettings()
  pcall(function()
    local data={}
    for k,v in pairs(S.legacySettings) do data[k]=v end
    for k,v in pairs(S.cfg) do data[k]=v end
    writefile("aotr_farm.json",game:GetService("HttpService"):JSONEncode(data))
  end)
end
local function unload()
  local ownsRun=_G.AotrRunId==S.id
  if ownsRun then _G.AotrStop=true; beat("unloaded") end
  S.target=nil
  if S.statusLabel then pcall(function() S.statusLabel:Remove() end); S.statusLabel=nil end
  local lib=S.menu and S.menu.lib
  if lib and not lib._unloaded and not S.menuUnloading then
    S.menuUnloading=true
    pcall(function() lib:Unload() end)
  end
end
local function menu()
  task.wait(0.2) -- the thread was spawned before the initial yield; settings load first
  if S.cfg.MenuDisabled then return end
  local url="https://raw.githubusercontent.com/hauntedscripts/Scripts2/refs/heads/main/matcha%20ue"
  local ok,src=pcall(httpget,url)
  if not ok or type(src)~="string" then boot("menu download failed"); return end
  local chunk=loadstring(src,"laced.club UE")
  local ran=type(chunk)=="function" and pcall(chunk)
  local lib=_G.UELibrary
  if not lib and type(_G.getgenv)=="function" then
    local good,env=pcall(_G.getgenv)
    if good and type(env)=="table" then lib=env.UELibrary end
  end
  if not ran or type(lib)~="table" then boot("menu load failed"); return end
  local win=lib:CreateWindow({Title="AoTR Farm v2",Width=540,Height=580,AutoShow=true,Center=true})
  S.menu={lib=lib,win=win}
  local function set(k,scale)
    return function(v)
      if type(S.cfg[k])=="boolean" then S.cfg[k]=v==true
      else S.cfg[k]=(tonumber(v) or S.cfg[k])/(scale or 1) end
      saveSettings()
    end
  end
  local function toggle(g,k,label)
    g:AddToggle(k,{Text=label,Default=S.cfg[k],Callback=set(k)})
  end
  local function slider(g,k,label,min,max,scale,suffix)
    g:AddSlider(k,{Text=label,Default=math.floor(S.cfg[k]*(scale or 1)+0.5),Min=min,Max=max,Rounding=0,
      Suffix=suffix or "",Callback=set(k,scale)})
  end
  local main=win:AddTab("Main")
  local farm=main:AddLeftGroupbox("Farm")
  toggle(farm,"Autofarm","Auto Farm (F6)"); toggle(farm,"AutoRetry","Auto Retry")
  toggle(farm,"AutoReload","Auto Reload / Refill"); toggle(farm,"AutoQTE","Auto QTE")
  slider(farm,"NoKillMinutes","Reset After No Kill",2,30,nil," min")
  slider(farm,"BossNoKillMinutes","Reset After Raid Boss Stalls",5,60,nil," min")
  local shift=main:AddRightGroupbox("Titan")
  toggle(shift,"ShiftEnabled","Auto Shift"); slider(shift,"ShiftKey","Shift Key",1,5)
  toggle(shift,"TitanSkills","Use Skills")
  slider(shift,"TitanSkillDelay","Skill Delay",200,3000,1000," ms")
  slider(shift,"TitanStrikeDistance","Strike Distance",5,60,nil," studs")
  slider(shift,"TitanRetreatHp","Retreat Below",0,90,100," %")
  slider(shift,"TitanReturnHp","Return Above",0,100,100," %")
  local session=main:AddRightGroupbox("Session")
  session:AddButton({Text="Print stats",Func=function() print("[AoTR v2] "..box()) end})
  session:AddButton({Text="Unload (End)",Func=unload})
  local tune=win:AddTab("Tuning")
  local attack=tune:AddLeftGroupbox("Attack")
  toggle(attack,"PullAllNapes","Pull All Napes")
  slider(attack,"PullCount","Pull Count",1,12,nil," napes")
  slider(attack,"PullRadius","Pull Range",100,5000,nil," studs")
  slider(attack,"PullEvery","Extra Napes Every",1,8,nil," slashes")
  slider(attack,"PullExtraInterval","Extra Pull Spacing",30,200,1000," ms")
  slider(attack,"NapeSize","Nape Size",5,40,nil," studs")
  slider(attack,"AttackDelay","Slash Delay",30,300,1000," ms")
  local heights=tune:AddRightGroupbox("Hover")
  for _,k in ipairs({"HeightNormal","HeightStall","HeightAttack","HeightColossal"}) do
    slider(heights,k,k,40,400,nil," studs")
  end
  slider(heights,"BobAmplitude","Bob",0,10,nil," studs")
  slider(heights,"SafeHeight","Safe Height",1000,20000,nil," studs")
  local pos=tune:AddLeftGroupbox("Position")
  slider(pos,"HoverOffsetX","Offset X",-80,80,nil," studs")
  slider(pos,"HoverOffsetZ","Offset Z",-80,80,nil," studs")
  slider(pos,"NapeOffsetY","Nape Above Player",-15,15,nil," studs")
  if type(lib.OnUnload)=="function" then pcall(function() lib:OnUnload(unload) end) end
  pcall(function() win:Show() end)
  -- Matcha kills late-spawned UE threads at first yield. This early-spawned thread drives Step.
  while not stopped() and not lib._unloaded and not win.Destroyed do
    pcall(win.Step,win)
    task.wait(lib.PerformanceMode and 0.05 or 0.016)
  end
end
local function offsets()
  local http=game:GetService("HttpService")
  local function decode(raw)
    if type(raw)~="string" or #raw<100 then return nil end
    local ok,data=pcall(function() return http:JSONDecode(raw) end)
    if not ok or type(data)~="table" or type(data.Offsets)~="table" then return nil end
    local o=data.Offsets
    if not (o.GuiObject and type(o.GuiObject.Visible)=="number"
      and o.BasePart and type(o.BasePart.Transparency)=="number") then return nil end
    return o
  end
  local cached
  pcall(function() cached=readfile("aotr/offsets.json") end)
  S.offsets=decode(cached)
  for _,url in ipairs({"https://offsets.imtheo.lol/Offsets.json",
    "https://imtheo.lol/Offsets/Offsets.json"}) do
    local ok,raw=pcall(httpget,url)
    local parsed=ok and decode(raw)
    if parsed then
      S.offsets=parsed
      pcall(writefile,"aotr/offsets.json",raw)
      return
    end
  end
  if S.offsets then boot("using cached offsets") else boot("offsets unavailable; blade check paused") end
end

pcall(function()
  local label=Drawing.new("Text")
  label.Size=16; label.Outline=true; label.Color=Color3.fromRGB(120,200,110)
  label.Position=Vector2.new(12,300); label.Visible=true
  S.statusLabel=label
end)

-- Preserve the previous run before the heartbeat thread can truncate trace.txt.
pcall(function()
  if isfile("aotr/trace.txt") then
    local previous=readfile("aotr/trace.txt")
    if type(previous)=="string" and #previous>0 then
      local p="aotr/trace_freezes.txt"
      local old=(isfile(p) and readfile(p)) or ""
      if #old>60000 then old=string.sub(old,-30000) end
      writefile(p,old .. "=== v2 start " .. os.date("%H:%M:%S")
        .. " previous trace:\n" .. previous .. "\n\n")
    end
  end
end)

-- Start all persistent threads before this chunk's first yield.
task.spawn(function()
  while not stopped() do
    local ok,err=pcall(collect)
    if not ok then boot("collector: "..tostring(err)) end
    task.wait(0.4)
  end
end)
task.spawn(function()
  while not stopped() do
    local now=os.clock()
    local state=S.mode
    if (state=="farming" or state=="loading") and not S.heartbeatPaused
      and (state~="farming" or (now-S.progress<30
        and (not S.target or not isrbxactive() or now-S.lastHover<3))) then beat(state) end
    if now-S.boxAt>=1 then
      S.boxAt=now; S.lastBox=box()
      if S.statusLabel then pcall(function() S.statusLabel.Text="AoTR v2 | "..S.lastBox end) end
      S.history[#S.history+1]=S.lastBox
      if #S.history>15 then table.remove(S.history,1) end
      pcall(writefile,"aotr/blackbox.txt",S.lastBox)
    end
    if now-S.traceAt>=1 then
      S.traceAt=now
      pcall(writefile,"aotr/trace.txt",traceText())
    end
    task.wait(1)
  end
  if _G.AotrRunId==S.id then beat("unloaded") end
end)
task.spawn(function()
  while not stopped() do
    local ok,err=pcall(menu)
    if not ok then boot("menu: "..tostring(err)) end
    break
  end
end)
task.spawn(function()
  local nextHover=0
  local nextExtra=0
  while not stopped() do
    local now=os.clock()
    if now>=nextHover and S.cfg.Autofarm and S.mode=="farming" then
      nextHover=now+0.05
      local ok,err=pcall(hover)
      if not ok then boot("hover: "..tostring(err)) end
    end
    if now>=nextExtra and S.extraPending and S.target and S.cfg.PullAllNapes then
      nextExtra=now+math.max(0.03,S.cfg.PullExtraInterval)
      local e=S.extras[S.extraIndex]
      if not e then S.extraPending=false
      else S.extraIndex+=1; pcall(pull,e) end
    end
    task.wait(0.016)
  end
end)

boot("start")
loadSettings()
offsets()
local idWait=os.clock()
while not stopped() and (game.GameId==0 or game.PlaceId==0) and os.clock()-idWait<20 do task.wait(0.25) end
if game.GameId~=4658598196 then boot("wrong game"); unload(); return end
if game.PlaceId==14916516914 then S.mode="lobby"; beat("lobby"); return end
S.mode="loading"
local loadingAt=os.clock()
while not stopped() and not S.world.titans and os.clock()-loadingAt<20 do task.wait(0.2) end
S.mode="farming"
boot("world ready")
while not stopped() do
  progress()
  local now=os.clock()
  local farmDown=iskeypressed(0x75)
  if farmDown and not S.wasFarm then S.cfg.Autofarm=not S.cfg.Autofarm; saveSettings() end
  S.wasFarm=farmDown
  local endDown=iskeypressed(0x23)
  if endDown and not S.wasEnd then unload(); break end
  S.wasEnd=endDown
  if not S.cfg.Autofarm then
    S.target=nil; S.stats.status="paused"; task.wait(0.25)
  elseif retry() then
    if S.retrySince and now-S.retrySince>60 then
      -- A stale farming beat lets the watchdog restart an unresponsive retry loop.
      S.heartbeatPaused=true
    end
  elseif not S.world.root or not same(S.world.root.Parent,S.world.char) then
    S.target=nil; S.stats.status="waiting for character root"; task.wait(0.25)
  elseif not S.world.hum or S.world.hum.Health<=0 then
    if S.stats.status~="dead" then dump("death") end
    S.target=nil; S.stats.status="dead"; task.wait(0.5)
  else
    if S.cfg.AutoReload and supplies() then
      if S.refillSince and now-S.refillSince>20 then giveUp() end
      task.wait(0.1)
    else
      S.refillSince=nil
      form()
      local t=S.target
      if t and not live(t) then
        S.stats.kills+=1; S.lastKill=now; S.target=nil; S.stats.target="none"
        trace("kill "..t.name)
      end
      if not S.target then S.target=choose() end
      t=S.target
      if not S.cfg.PullAllNapes or (t and S.extraFor~=t.model.Address) then
        S.extraPending=false
      end
      if t and live(t) then
        S.stats.target=string.sub(t.name,1,12)
        if now-S.lastKill>(t.boss and S.cfg.BossNoKillMinutes or S.cfg.NoKillMinutes)*60 then
          giveUp()
        elseif not isrbxactive() then
          S.stats.status="waiting for focus"; task.wait(0.2)
        elseif qte() then
          S.stats.status="quick time event"; task.wait(0.016)
        elseif S.form and now-S.shiftSince<2 then
          S.stats.status="shifting"; task.wait(0.1)
        else
          S.stats.status=S.form and "titan attacking" or "attacking"
          if not S.form then
            if S.cfg.PullAllNapes and not S.extraPending
              and (now-S.extraAt>0.5 or S.extraFor~=t.model.Address) then
              extras(t); S.extraFor=t.model.Address
            end
            pcall(pull,t)
            S.slash+=1
            if S.cfg.PullAllNapes and not S.extraPending
              and S.slash%math.max(1,S.cfg.PullEvery)==0 then
              S.extraIndex=1; S.extraPending=true
            end
          end
          task.wait()
          if live(t) and S.world.root and not stopped() then
            trace("click")
            mouse1click(); task.wait(0.03)
            if S.form then skill() else tap(0x20) end
          end
          task.wait(math.max(0.03,S.cfg.AttackDelay))
        end
      else
        S.stats.target="none"; S.stats.status="no titans found"
        task.wait(0.1)
      end
    end
  end
end
unload()
