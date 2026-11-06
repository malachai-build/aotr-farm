-- Stage both sources at aotr/reload_tests/{normal,raid}.lua. World reads are mocked.
for _,variant in ipairs({"normal","raid"}) do
  local source=readfile("aotr/reload_tests/"..variant..".lua")
  local a=assert(string.find(source,"-- Discover world trigger parts once",1,true))
  local b=assert(string.find(source,"function Supplies.TankPosition()",a,true))
  local header=[====[
local now,scans=0,0
local os={clock=function() return now end}
local Supplies,KnownTitans={},{}
local GasTankModel,GasTankPosition
local LocalPlayer={}
local origin={Position=Vector3.new(10,0,0)}
local function GetPlayerHrp() return origin end
local function IsTitanAlive(t) return t.Alive end
local function GetTitanHrp(t) return t.Root end
local function Boot() end
local function station(id,x)
  return {Name="Refill",ClassName="Part",Address=id,Parent={Name="GasTanks"},Position=Vector3.new(x,0,0)}
end
local first,second,third=station(1,0),station(2,500),station(3,1000)
local decorative=station(4,2000);decorative.Parent.Name="Decoration"
local gui=station(5,3000);gui.ClassName="Frame"
local parts={first,second,third,first,decorative,gui}
local Workspace={GetDescendants=function() scans+=1;return parts end}
]====]
  local checks=[====[
assert(#Supplies.FindRefillStations()==3,"discover and deduplicate actual world triggers")
assert(Supplies.SelectRefillStation().X==0,"no threats chooses nearest station")
local titan={Alive=true,Root={Position=Vector3.new(0,0,0)}}
KnownTitans={titan}
assert(Supplies.SelectRefillStation().X==1000,"avoid the camped station")
titan.Root.Position=Vector3.new(600,0,0)
assert(Supplies.SelectRefillStation().X==0,"fresh titan positions change selection without a rescan")
titan.Alive=false
assert(Supplies.SelectRefillStation().X==0,"dead titans do not count")
titan.Alive=true;titan.Root.Position=Vector3.new(400,0,0);third.Position=Vector3.new(1200,0,0)
assert(Supplies.SelectRefillStation().X==1200,"read live station position rather than old cached coordinates")
third.Parent=nil
assert(Supplies.SelectRefillStation().X==0,"ignore removed stations")
assert(scans==1,"never scan the world again per scoring call")
parts[#parts+1]=station(6,1600);now=31
assert(Supplies.SelectRefillStation().X==1600 and scans==2,"bounded rediscovery includes newly loaded stations")
local counts={};KnownTitans={}
for _,x in ipairs({0,20,500,1600}) do KnownTitans[#KnownTitans+1]={Alive=true,Root={Position=Vector3.new(x,0,0)}} end
assert(Supplies.SelectRefillStation().X==500,"when all stations are camped, choose fewer nearby threats then nearer travel")
]====]
  assert(loadstring(header..string.sub(source,a,b-1)..checks,"refill_stations_"..variant))()
  assert(loadstring(source,"compile_station_selection_"..variant))
  print("PASS: "..variant.." station discovery, live positions, titan avoidance, dead/removed objects, bounded scan cache, crowded fallback")
end
