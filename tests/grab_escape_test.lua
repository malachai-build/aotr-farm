local function extract(s, a, b)
  local first = assert(string.find(s, a, 1, true), a)
  local last = assert(string.find(s, b, first, true), b)
  return string.sub(s, first, last - 1)
end
for _, variant in ipairs({"normal", "raid"}) do
  local source = readfile("aotr/recovery_tests/" .. variant .. ".lua")
  local header = [====[
local now = 0
local os = {clock = function() return now end}
local UserConfigs = {AutoQTE = true}
local focused = true
local function isrbxactive() return focused end
local function IsObjectVisible(o) return o and o.visible end
local function Boot() end
local presses, releases = {}, {}
local function keypress(k) presses[#presses+1] = k end
local function keyrelease(k) releases[#releases+1] = k end
local function memory_read() return 1 end
local SizeOffset = 0
local function node(id, children)
  local o = {Address=id, Parent=true, visible=true, children=children or {}}
  function o:GetChildren() local out={} for _,c in pairs(self.children) do out[#out+1]=c end return out end
  function o:FindFirstChild(n) return self.children[n] end
  return o
end
local buttons = node(1)
local Interface = node(2, {Buttons=buttons})
local function prompt(id, text)
  local key=node(id+1000);key.Text=text
  return node(id, {Main=node(id+2000, {Key=key})})
end
]====]
  local checks = [====[
local function tick(t) now=t;QteTick() end
-- More than six inputs, randomized order and repeats, with each new prompt identity.
local sequence={"S","W","D","A","S","S","E","Q","D","W","A","S","E"}
for i,key in ipairs(sequence) do
  buttons.children={current=prompt(10+i,key)}
  local at=i*.15
  tick(at)
  assert(#presses==i and presses[i]==string.byte(key),"follow every displayed prompt, including after six")
  tick(at+.06)
  assert(#releases==i,"release each key before the next prompt")
end
buttons.children={};tick(2.1);assert(Qte.Active,"brief inter-prompt gap keeps combat paused")
tick(2.5);assert(not Qte.Active,"no prompts eventually returns control to combat")
local repeated=prompt(100,"F");buttons.children={current=repeated};tick(3)
local before=#presses;tick(3.07);tick(3.14)
assert(#presses==before,"lingering prompt does not spam each render")
tick(3.4);assert(#presses==before+1,"unchanged prompt can retry without a total cap")
tick(3.47)
repeated.children.Main.children.Key.Text="W";tick(3.55)
assert(presses[#presses]==0x57,"same button can change its displayed key")
tick(3.62);buttons.children={};tick(3.7)
buttons.children={current=repeated};tick(3.8)
assert(#presses==before+3,"same key and identity rearm after disappearance")
UserConfigs.AutoQTE=false;tick(3.81)
assert(not Qte.ReleaseAt and not Qte.Active and releases[#releases]==0x57,"toggle off releases held input")
UserConfigs.AutoQTE=true;focused=false;before=#presses;tick(4)
assert(#presses==before and Qte.Active,"unfocused Roblox receives no new input")
focused=true;buttons.visible=false;tick(4.5)
assert(#presses==before,"hidden parent suppresses otherwise visible children")
buttons.visible=true;repeated.children.Main.children.Key.Text="unknown";tick(5)
assert(#presses==before,"unknown prompt never guesses a key")
repeated.children.Main.children.Key.Text="A";repeated.children.Main.children.Key.visible=false;tick(5.2)
assert(#presses==before,"hidden key label never triggers")
repeated.children.Main.children.Key.visible=true
buttons.children={one=repeated,two=prompt(200,"S")};tick(5.4)
assert(#presses==before,"ambiguous simultaneous prompts never invent an order")
buttons.children={one=prompt(201,"S")};tick(5.6)
assert(#presses==before+1 and presses[#presses]==0x53,"resume with the single current prompt")
tick(5.67);buttons.children={};tick(6.1)
-- Raid timing QTE remains functional after a complete grab episode.
Qte.Frame={Parent=true,visible=true};Qte.Key={Text="E"};Qte.Timing={Parent=true,Address=1}
tick(6.3)
assert(presses[#presses]==0x45,"raid QTE still works after grab escape")
print("PASS: dynamic grab " .. "VARIANT" .. " sequence >6, random/repeated keys, gaps, retries, focus, cancellation, visibility, ambiguity, raid QTE")
]====]
  checks = string.gsub(checks, "VARIANT", variant)
  local key = extract(source, "local function KeyToVk(", "-- End prompt key mapping.")
  local qte = extract(source, "Qte = {", "--#endregion -- Quick time events --")
  loadstring(header .. "\nlocal Qte\n" .. key .. qte .. checks, "grab_" .. variant)()
end
