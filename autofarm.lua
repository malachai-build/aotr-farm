-- Game name: Attack on Titans Revolution
-- Game Id: 4658598196
-- Game UniverseId: 4658598196
-- Game PlaceIds: 13379208636 (Lobby), 13379349730 (Mission) 4658598196 ( x )
-- Game link: https://www.roblox.com/games/13379208636/Attack-on-Titan-Revolution

-- Script version: 1.0.7



local Stats = {}

local ScriptStart = os.clock()

-- Startup trace in C:\matcha\workspace\aotr\boot.txt, readable from disk while Matcha's MCP is
-- down (it drops on every teleport). Shared with the auto-exec loader; kept under ~16 KB.
local BOOT_LOG = "aotr/boot.txt"
local function Boot(msg)
  pcall(function()
    local old = (type(isfile) ~= "function" or isfile(BOOT_LOG)) and readfile(BOOT_LOG) or ""
    if #old > 16000 then old = string.sub(old, -8000) end
    writefile(BOOT_LOG, old .. string.format("%s farm place=%s %s\n", os.date("%H:%M:%S"), tostring(game.PlaceId), msg))
  end)
end
Boot("start")
-- The previous run's last black-box line (see BlackBoxLine) shows what it was doing when it died
-- or froze, since Matcha restarting takes the print log with it.
pcall(function()
  if type(isfile) ~= "function" or isfile("aotr/blackbox.txt") then Boot("previous run's last state: " .. readfile("aotr/blackbox.txt")) end
end)

-- Heartbeat for watchdog/aotr_watchdog.ps1: "<state> <time>" in C:\matcha\workspace\aotr\heartbeat.txt.
-- While the state is "farming" and the file goes stale, the watchdog presses Retry from outside
-- (Matcha does not reload when the character dies before load-in, so nothing runs in here then).
-- "lobby" and "unloaded" tell it to stand down.
-- The heartbeat lets the PowerShell watcher restart Matcha if the farm stops progressing.
-- This flag also controls the once-per-second black box file write.
local HEARTBEAT_TEST_OFF = false
local function Heartbeat(state)
  if HEARTBEAT_TEST_OFF and state ~= "lobby" and state ~= "unloaded" then return end
  pcall(writefile, "aotr/heartbeat.txt", state .. " " .. os.date("%H:%M:%S"))
end
if HEARTBEAT_TEST_OFF then Heartbeat("unloaded") end
-- The heartbeat is written from the menu loop, which outlives a crashed main loop (seen 21:26 on
-- 2026-11-01: the farm died in GiveUpToTitan and the watchdog kept seeing "farming"). The farm's
-- own loops call Progress(), and the "farming" beat stops once they have been quiet too long.
local LastProgress = os.clock()
local PROGRESS_STALL_LIMIT = 30 -- seconds; longer than any single wait inside the farm loops
-- A dead hover leaves the farm "attacking" from the ground while its loops keep running, so
-- Progress() stops counting once the hover has been down HOVER_DEAD_LIMIT seconds.
local HoverDeadSince: number? = nil
local HOVER_DEAD_LIMIT = 15
-- Pressing Retry for a minute without the teleport starting is stuck too (the farm pressed it for
-- 7 minutes on 2026-11-02 with a fresh heartbeat); let the watchdog restart Matcha.
local RetryScreenSince: number? = nil
local RETRY_STUCK_LIMIT = 60
local function Progress()
  if HoverDeadSince and os.clock() - HoverDeadSince > HOVER_DEAD_LIMIT then return end
  if RetryScreenSince and os.clock() - RetryScreenSince > RETRY_STUCK_LIMIT then return end
  LastProgress = os.clock()
end

-- Step trace for freezes (2026-11-03: Matcha froze about every 85s, the black box normal up to the
-- last line). Every thread records the step it is in; the render loop writes aotr/trace.txt five
-- times a second: each thread's current step and how long ago it got there, and the 25 most recent
-- steps with counts. A freeze leaves that file as it stood, and the next run appends it to
-- aotr/trace_freezes.txt. One table, since the chunk is near Luau's 200-local limit.
local Tr = { threads = {}, events = {}, flushAt = 0 }
function Tr.step(thread, step)
  local now = os.clock()
  local t = Tr.threads[thread]; if not t then t = {}; Tr.threads[thread] = t end
  t.step, t.at = step, now
  local key = thread .. ": " .. step
  local e = Tr.events[key]; if not e then e = { n = 0 }; Tr.events[key] = e end
  e.n += 1; e.at = now
end
function Tr.flush()
  local now = os.clock()
  if now - Tr.flushAt < 0.2 then return end
  Tr.flushAt = now
  local lines = { string.format("%s clock=%.2f", os.date("%H:%M:%S"), now) }
  for name, t in pairs(Tr.threads) do
    lines[#lines + 1] = string.format("thread %-8s %s (%.2fs ago)", name, t.step, now - t.at)
  end
  local list = {}
  for k, e in pairs(Tr.events) do list[#list + 1] = { k = k, e = e } end
  table.sort(list, function(a, b) return a.e.at > b.e.at end)
  for i = 1, math.min(#list, 25) do
    lines[#lines + 1] = string.format("%6.2fs ago  x%-6d %s", now - list[i].e.at, list[i].e.n, list[i].k)
  end
  pcall(writefile, "aotr/trace.txt", table.concat(lines, "\n"))
end
pcall(function()
  if type(isfile) == "function" and not isfile("aotr/trace.txt") then return end
  local path = "aotr/trace_freezes.txt"
  local old = (type(isfile) ~= "function" or isfile(path)) and readfile(path) or ""
  if #old > 60000 then old = string.sub(old, -30000) end
  writefile(path, old .. string.format("=== run starting %s (place=%s); previous run's last trace:\n%s\n\n",
    os.date("%H:%M:%S"), tostring(game.PlaceId), readfile("aotr/trace.txt")))
end)

-- Everything the menu can change. Saved to SETTINGS_FILE.
local UserConfigs = {
  Autofarm = true,
  AutoRetry = true,       -- press Retry on the rewards screen
  AutoReload = true,      -- reload blades / refill gas when they run out
  AutoSkipCutscenes = true, -- press E when the cutscene Skip prompt appears
  AutoRaidChest = true,   -- open the free raid chest, then finish its screen
  OpenKeyChest = false,   -- optionally spend one key on the right raid chest
  AutoCrates = true,       -- collect and deliver the player-specific Waves crate
  AutoEquipmentUpgrades = true, -- after delivery, buy five rounds of equipment upgrades
  AutoStationUpgrades = true, -- buy Regen first, then HQ Max HP twice; Refills on even waves
  AutoPerks = true,       -- choose the strongest owned perks after Waves tasks
  AutoMarket = true,      -- buy missing priority perks from Orange before upgrades
  PriorityPerks = { "", "", "", "", "", "" },
  NapeSize = 15,          -- studs; the pulled nape is resized to this cube
  PullAllNapes = false,   -- stack every live titan's nape on the target's, not just the target's
  PullBossLimbs = false,  -- pull every raid boss hitbox limb onto the player
  PullRadius = 5000,      -- studs from the target that Pull All Napes reaches; 5000 (the max) = whole map
  PullCount = 6,          -- napes stacked per slash, target included; blade hits cap at ~6 titans
  MenuDisabled = false,   -- skip the menu (edit aotr_farm.json); F6/End and the status line still work
  KillTimeout = 10,       -- seconds before giving up on a titan
  AttackDelay = 0.06,     -- seconds between slashes
  BobAmplitude = 2,       -- studs of up/down bob while hovering
  HeightNormal = 120,     -- hover height above each titan type
  HeightStall = 100,
  HeightAttack = 160,
  HeightColossal = 200,
  HoverOffsetX = 0,       -- studs; shifts the hover spot (and the pulled nape) off the titan's centre
  HoverOffsetZ = 0,
  NapeOffsetY = 2,        -- studs; pulled napes sit this far above the player
  SafeHeight = 9999,      -- Y of the reload spot
  HumanSkills = true,     -- use ready human hotbar skills with a short gap between successes
  AwakeningSlot = 1,     -- Rage Mode / other awakening hotbar slot
  NoKillMinutes = 5,      -- minutes without a kill before feeding a titan to reset the run
  BossNoKillMinutes = 20, -- the same while a raid boss is alive (bosses never time out)
  AutoQTE = true,         -- press the key a raid quick time event asks for
  DebugMode = _G.KittyDebug == true -- was `or true`, which forced it on
}
local SETTINGS_FILE = "aotr_farm.json"
local SAVED_KEYS = {
  "Autofarm", "AutoRetry", "AutoReload", "AutoSkipCutscenes", "AutoRaidChest", "OpenKeyChest", "AutoCrates", "AutoEquipmentUpgrades", "AutoStationUpgrades", "AutoPerks", "AutoMarket", "PriorityPerks", "NapeSize", "PullAllNapes", "PullBossLimbs", "PullRadius", "PullCount", "MenuDisabled", "KillTimeout", "AttackDelay", "BobAmplitude",
  "HeightNormal", "HeightStall", "HeightAttack", "HeightColossal", "HoverOffsetX", "HoverOffsetZ",
  "NapeOffsetY", "SafeHeight", "DebugMode",
  "HumanSkills", "AwakeningSlot",
  "NoKillMinutes", "BossNoKillMinutes", "AutoQTE",
}

local function SaveSettings()
  pcall(function()
    local data = {}
    for _, k in ipairs(SAVED_KEYS) do data[k] = UserConfigs[k] end
    writefile(SETTINGS_FILE, game:GetService("HttpService"):JSONEncode(data))
  end)
end

pcall(function()
  if type(isfile) == "function" and not isfile(SETTINGS_FILE) then return end
  local d = game:GetService("HttpService"):JSONDecode(readfile(SETTINGS_FILE))
  if type(d) ~= "table" then return end
  for _, k in ipairs(SAVED_KEYS) do
    if d[k] ~= nil and type(d[k]) == type(UserConfigs[k]) then UserConfigs[k] = d[k] end
  end
end)

-- Saved lists may come from an older or manually edited settings file.
do
  local cleaned, seen = {}, {}
  for i = 1, 6 do
    local name = type(UserConfigs.PriorityPerks) == "table" and UserConfigs.PriorityPerks[i] or nil
    name = type(name) == "string" and name or ""
    if seen[name] then name = "" end
    cleaned[i] = name
    if name ~= "" then seen[name] = true end
  end
  UserConfigs.PriorityPerks = cleaned
end
SaveSettings() -- discard retired controls from older saved settings

-- Stop switch: `_G.AotrStop = true` (or the menu's Unload) halts every loop and the hover teleport.
-- Each run takes a fresh id, so re-running (auto-exec, then by hand) stops the old copy, and the
-- old copy's Unload, fired when the new menu replaces its window, cannot stop the new one.
local RunId = tostring(os.clock()) .. "-" .. tostring(math.random(1, 1e9))
_G.AotrRunId = RunId
_G.AotrStop = false
local function Stopped() return _G.AotrStop == true or _G.AotrRunId ~= RunId end
local FarmStats = { Kills = 0, Timeouts = 0, Target = "none", Status = "starting" }


local CurrentLogFile = nil
local DebugRateLimit = {}

if UserConfigs.DebugMode then
  local DateString = os.date("%Y-%m-%d")
  local TimeString = os.date("%H-%M-%S")
  local Path = "KittyScripts/Aotr/logs/"
  local FileName = Path .. "log_" .. DateString .. "_" .. TimeString .. ".txt"

  local Header = { 
    string.rep("-", 50),
    "Debug file for the script",
    "Date: " .. os.date("%A, %B %d, %Y"),
    "Time: " .. os.date("%X"),
    "File Path: C:/matcha/workspace/" .. FileName,
    string.rep("-", 50),
    "\n"
  }

  writefile(FileName, table.concat(Header, "\n"))

  warn("Debug mode is on. Logging to: " .. FileName)
    
  CurrentLogFile = FileName
end

local function DebugPrint(mode: "warn" | "debug", maxAmount: number?, stackOffset: number?, functionName: string?, ...)
  if not UserConfigs.DebugMode then return end

  local Prefix = "[Kitty's Aotr]"
  local ModeLower = string.lower(mode)

  local Handlers = {
    print = print,
    warn = warn,
    debug = print
  }

  local Handler = Handlers[ModeLower]

  local args = table.pack(...)
  local MessageParts = {}

  for i = 1, args.n do
    MessageParts[i] = tostring(args[i])
  end

  local FinalMessage = table.concat(MessageParts, " ")
  local RateKey = ModeLower .. ":" .. FinalMessage

  -- Basically, maxAmount = 0 or nil means infinite prints
  if maxAmount and maxAmount ~= 0  then
    local CurrentTime = os.clock()
    local RateData = DebugRateLimit[RateKey]

    if not RateData then
      RateData = {
        WindowStart = CurrentTime,
        Count = 0
      }

      DebugRateLimit[RateKey] = RateData
    end

    if CurrentTime - RateData.WindowStart >= 1 then
      RateData.WindowStart = CurrentTime
      RateData.Count = 0
    end

    if RateData.Count >= maxAmount then
      return
    end

    RateData.Count += 1
  end

  local DebugLine = debug.info((stackOffset or 1) + 1, "l") -- function name doesn't work, returns " ", thank you matcha.

  local Timestamp = os.clock() - ScriptStart
  local TimestampFormatted = string.format("%.4f", Timestamp)


  local RealFinalMessage = string.format("[%s] [line: %s || func: %s] %s [%s]: %s",
    TimestampFormatted,
    tostring(DebugLine),
    functionName or "<anonymouse>",
    Prefix,
    ModeLower,
    FinalMessage
  )

  
  Handler(RealFinalMessage)

  if CurrentLogFile then
    appendfile(CurrentLogFile, RealFinalMessage .. "\n")
  end
end


DebugPrint("debug", nil, nil, nil, "Proceeding to check the game and wait for services...")

task.wait(0.5)

if identifyexecutor and identifyexecutor() ~= "Matcha" then Boot("exit: executor " .. tostring(identifyexecutor())); DebugPrint("warn", nil, nil, nil, "Not using matcha..?"); return end
-- Auto-exec can fire before the DataModel has its ids; wait so the game check below is real.
repeat task.wait(0.25) until game.GameId ~= 0 and game.PlaceId ~= 0
if game.GameId ~= 4658598196 then Boot("exit: wrong game " .. tostring(game.GameId)); DebugPrint("debug", nil, nil, nil, "Wrong game detected..?"); return end
if game.PlaceId == 14916516914 then Boot("exit: lobby"); Heartbeat("lobby"); DebugPrint("debug", nil, nil, nil, "You seem to be in the lobby. Please execute this in a game."); return end
Boot("game ok")

local function WaitForService(serviceName: string)
  local Service = nil; repeat Service = game:GetService(serviceName); task.wait(0.05); DebugPrint("debug", nil, 1, "WaitForService", "Waiting for service: " .. serviceName) until Service; return Service
end

local Workspace = WaitForService("Workspace")
local Players = WaitForService("Players")
local HttpService = WaitForService("HttpService")

local LocalPlayer = nil; repeat task.wait(0.03); LocalPlayer = Players.LocalPlayer until LocalPlayer
local PlayerGui = nil; repeat task.wait(0.03);  PlayerGui = LocalPlayer:FindFirstChild("PlayerGui") until PlayerGui


local TitansFolder = nil; repeat task.wait(0.03); TitansFolder = Workspace:FindFirstChild("Titans") until TitansFolder
local Interface = nil; repeat task.wait(0.03); Interface = PlayerGui:FindFirstChild("Interface") until Interface
Boot("waiting for titans")
-- Bounded: on a mission-end screen no titans ever spawn, and the main loop (Auto Retry, heartbeat)
-- has to run to get out of it. An unbounded wait here stalled a run for ~5 hours.
-- Beats "loading" meanwhile: the watchdog restarts Matcha on a stale "farming" beat, and after a
-- hang at a mission's end the old beat kept it killing each fresh Matcha in this wait (01:56-01:57,
-- 2026-11-02).
local TitanWaitStart, LastLoadBeat = os.clock(), 0
repeat
  task.wait(0.03)
  if os.clock() - LastLoadBeat >= 1 then LastLoadBeat = os.clock(); Heartbeat("loading") end
until TitansFolder:FindFirstChildOfClass("Model") or os.clock() - TitanWaitStart > 20

if TitansFolder:FindFirstChildOfClass("Model") then
  Boot(string.format("world ready after %.1fs", os.clock() - ScriptStart))
else
  Boot("no titans after 20s, starting anyway")
end
DebugPrint("debug", nil, nil, nil, "Sucesfully loaded all services and titans folder / interface.")







--#region -- Types, Tables && Caches, Variables --


-- // Types && Caches \\ --
type OffsetsData = {
  Offsets: {
    [string]: {
      [string]: number
    }
  }
}

type TitanEntry = {
  Instance: Instance?,

  Info: {
    Name: string?,
    Type: string?,

    Alive: boolean?,
    LastAliveCheck: number?,

    Ignored: boolean?,
    IgnoredTime: number?,
    IgnoreDuration: number?
  },

  Parts: {
    Nape: BasePart?,
    HumanoidRootPart: BasePart?,
    Humanoid: Humanoid?
  },

  Nape: {
    CurrentSize: Vector3?
  },

  TpFails: {
    Count: number
  }
}

type CharacterCacheType = {
  Character: Instance?,
  Hrp: BasePart?,
  Humanoid: Humanoid?,

  Username: string?,
  DisplayName: string?,
  UserId: number?
}

type UiCacheType = {
  RewardsFrame: GuiObject?
}

type BladeCacheType = {
  RightBlade: Instance?,
  LeftBlade: Instance?,
  RightHand: Instance?,
  LeftHand: Instance?
}



local TitansCache: { [number]: TitanEntry } = {}
local KnownTitans: { [number]: Instance } = {} -- Childrens of the titans folder
local CharacterCache: { [number]: CharacterCacheType } = {}
local UiCache: UiCacheType = {}
local BladeCache: BladeCacheType = {}


local GasTankModel: Instance? = nil
local GasTankPosition: Vector3? = nil

--#endregion -- Types, Tables && Caches, Variables --


--#region Small functions


local function GetPath(root: Instance, Warning: boolean, ...): Instance?
  local CurrentInstance = root
  local args = {...}

  for _, name in ipairs(args) do
    if not CurrentInstance then
      if Warning then
        DebugPrint("warn", nil, nil, "GetPath", "Couldn't find a children: ", name)
      end

      return nil
    end

    local NextInstance = CurrentInstance:FindFirstChild(name)

    if not NextInstance then
      if Warning then
        DebugPrint( "warn", nil, nil, "GetPath", "Missing: ", name , " in ", (CurrentInstance:GetFullName() or "<unknown>") )
      end
      return nil
    end

    CurrentInstance = NextInstance
    task.wait()
  end

  return CurrentInstance
end


local function HandleDifferentGasTankPaths(): Instance?
  local Shiganshina = GetPath(Workspace, false, "Climbable",   "Walls",      "Gate",      "GasTanks"); if Shiganshina then DebugPrint("debug", nil, nil, "GasTank", "Shiganshina detected!"); GasTankModel = Shiganshina; return Shiganshina end
  local Trost       = GetPath(Workspace, false, "Unclimbable", "Camps",      "Camp",      "GasTanks"); if Trost       then DebugPrint("debug", nil, nil, "GasTank", "Trost detected!");       GasTankModel = Trost;       return Trost       end
  local OutSkirts   = GetPath(Workspace, false, "Climbable",   "_Walls",     "Gate",      "GasTanks"); if OutSkirts   then DebugPrint("debug", nil, nil, "GasTank", "Outskirts detected!");   GasTankModel = OutSkirts;   return OutSkirts   end
  local Forest      = GetPath(Workspace, false, "Unclimbable", "Camps",      "Camp",      "GasTanks"); if Forest      then DebugPrint("debug", nil, nil, "GasTank", "Forest detected!");      GasTankModel = Forest;      return Forest      end
  local UtGard      = GetPath(Workspace, false, "Climbable",   "Utgard",     "GasTanks");              if UtGard      then DebugPrint("debug", nil, nil, "GasTank", "UtGard detected!");      GasTankModel = UtGard;      return UtGard      end
  -- Docks on Stall has no "World" folder
  local Docks       = GetPath(Workspace, false, "Unclimbable", "World",      "Buildings", "Hanger",   "GasTanks")
                   or GetPath(Workspace, false, "Unclimbable", "Buildings",  "Hanger",    "GasTanks"); if Docks  then DebugPrint("debug", nil, nil, "GasTank", "Docks detected!");       GasTankModel = Docks;       return Docks       end
  local Stohess     = GetPath(Workspace, false, "Unclimbable", "Props",      "HQ",        "GasTanks"); if Stohess     then DebugPrint("debug", nil, nil, "GasTank", "Stohess detected!");     GasTankModel = Stohess;     return Stohess     end
  local Chapel      = GetPath(Workspace, false, "Unclimbable", "Reloads",    "GasTanks");              if Chapel      then DebugPrint("debug", nil, nil, "GasTank", "Chapel detected!");      GasTankModel = Chapel;      return Chapel      end

  local Waves       = GetPath(Workspace, false, "Unclimbable", "Objective",  "Waves",     "GasTanks"); if Waves       then DebugPrint("debug", nil, nil, "GasTank", "Waves detected!");       GasTankModel = Waves;       return Waves       end

  warn("[Aotr] No known gas tank path for this map; refilling is disabled.")
  return nil
end; HandleDifferentGasTankPaths()

DebugPrint("debug", nil, nil, "GetOffsets", "Proceeding to fetch offsets from the server...")

-- Last good download, used when the offsets site is down. Offsets change with Roblox updates,
-- so a cached copy can go stale; a fresh download always overwrites it.
local OFFSETS_CACHE = "aotr/offsets.json"

local function DecodeOffsets(raw: string?): OffsetsData?
  if type(raw) ~= "string" or raw == "" then return nil end
  local success, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
  if not success or type(decoded) ~= "table" or type(decoded.Offsets) ~= "table" then
    DebugPrint("warn", nil, nil, "GetOffsets", "JSON decode failed: ", decoded)
    return nil
  end
  return decoded :: OffsetsData
end

local function GetOffsets(): OffsetsData?
  local ok, res = pcall(function()
    return game:HttpGet("https://imtheo.lol/Offsets/Offsets.json")
  end)

  local decoded = ok and DecodeOffsets(res) or nil
  if decoded then
    pcall(writefile, OFFSETS_CACHE, res)
    return decoded
  end

  DebugPrint("warn", nil, nil, "GetOffsets", "Failed to fetch offsets: ", tostring(res))

  local cacheOk, cached = pcall(function()
    if type(isfile) == "function" and not isfile(OFFSETS_CACHE) then return nil end
    return readfile(OFFSETS_CACHE)
  end)
  decoded = cacheOk and DecodeOffsets(cached) or nil
  if decoded then Boot("offsets download failed, using cached " .. OFFSETS_CACHE) end
  return decoded
end; local OffsetsFake = GetOffsets()


if not OffsetsFake or next(OffsetsFake) == nil then
  Boot("exit: offsets download failed and no cached " .. OFFSETS_CACHE)
  DebugPrint("warn", nil, nil, "Offset check", "Offsets or next offset is missing..?")
  return
end


local function IsValid(object: Instance?): boolean
    return object and object.Parent
end
--#endregion Small functions



--#region -- variables section --


local Vector3New = Vector3.new
local Vector3Zero: Vector3 = Vector3New(0, 0, 0)

local function SafePosNow(): CFrame return CFrame.new(900, UserConfigs.SafeHeight, 900) end
local CurrentMission: string? = nil



local CachedNearestTitan: Instance? = nil
local LastNearestUpdate: number = 0

local CurrentTitanTarget: Instance? = nil
local LastHoverAt = os.clock() -- last RenderStepped hover callback; KillTitan takes over when it goes quiet
local LastHoverRewire = 0
local RewireHover = function() end -- assigned with the RenderStepped hover below
local StatusTick = function() end -- assigned with the status line below; ticked from RenderStepped
local StatusCleanup = function() end

-- CFrame/Size/velocity writes cost thousands of memory writes each (Matcha's docs), the likeliest
-- load behind Matcha hanging. Counted here and shown per second in the black box (writes=).
local HeavyWrites = 0

local CachedBladesBroken: boolean = false
local LastBladeCheck: number = 0

local CurrentRobloxState = "Active"
local WhatShouldIBeDoing = "attack"

local ReloadingBlades: boolean = false
local LastReloadingTime: number = 0

local REFILL_STUCK_LIMIT = 20 -- seconds stuck refilling before letting a titan kill us
local RefillStuckSince: number? = nil
local RefillLastSeen: number = 0


local DownMiddlePartUi: Instance? = GetPath(PlayerGui, true, "Interface", "HUD", "Main", "Top", "7"); if not DownMiddlePartUi then return end


--== Offsets ==--
local Offsets: { [string]: { [string]: number } } = OffsetsFake.Offsets
                                                     
local PrimaryPartOffset = Offsets.Model.PrimaryPart;
local BaseToPrimitiveOffset = Offsets.BasePart.Primitive;
local PrimitivePositionOffset = Offsets.Primitive.Position;
local VisibleOffset = Offsets.GuiObject.Visible;
local SizeOffset = Offsets.GuiObject.Size; -- UDim2: X.Scale float, X.Offset int, Y.Scale, Y.Offset
local TransparencyBasePartOffset = Offsets.BasePart.Transparency;
local AbsolutPositionGuiElementOffset = Offsets.GuiBase2D.AbsoluteSize;


--#endregion -- Variables section --



--#region  -- Functions --


--#region -- Player's character and Titan's character related functions --

local function GetCharacter(player: Player): BasePart? return player.Character :: Model end
local function GetHrp(instance: Instance): BasePart? return instance:FindFirstChild("HumanoidRootPart") :: BasePart end
local function GetHumanoid(instance: Instance): Humanoid? return instance:FindFirstChildOfClass("Humanoid") :: Humanoid end


-- After a death the old body can stay parented, so a cached part still looks valid.
-- Drop the cached parts whenever player.Character is a different model.
local function SyncCharacterCache(player: Player, cache)
  local Current = player.Character
  if Current and (not cache.Character or cache.Character.Address ~= Current.Address) then
    cache.Character, cache.Hrp, cache.Humanoid = Current, nil, nil
  end
end


local function GetPlayerCharacter(player: Player): Model?
  local PlayerCharacterCache = CharacterCache[player.Address]; if not PlayerCharacterCache then return nil end
  SyncCharacterCache(player, PlayerCharacterCache)
  local CachedCharacter = PlayerCharacterCache.Character :: Model?; if IsValid(CachedCharacter) then return CachedCharacter end

  local Character = player.Character :: Model; if not IsValid(Character) then return nil end

  PlayerCharacterCache.Character = Character
  return Character
end


local function GetPlayerHrp(player: Player): BasePart?
  local PlayerCharacterCache = CharacterCache[player.Address]; if not PlayerCharacterCache then return nil end
  SyncCharacterCache(player, PlayerCharacterCache)
  local CachedHrp = PlayerCharacterCache.Hrp; if IsValid(CachedHrp) then return CachedHrp end
  local Character = GetPlayerCharacter(player); if not Character then return nil end
  local Hrp = GetHrp(Character); if not Hrp then return nil end

  PlayerCharacterCache.Hrp = Hrp
  return Hrp
end


local function GetPlayerHumanoid(player: Player): Humanoid?
  local PlayerCharacterCache = CharacterCache[player.Address]; if not PlayerCharacterCache then return nil end
  SyncCharacterCache(player, PlayerCharacterCache)
  local CachedHumanoid = PlayerCharacterCache.Humanoid; if CachedHumanoid and CachedHumanoid.Parent then return CachedHumanoid end
  local Character = GetPlayerCharacter(player); if not Character then return nil end
  local Humanoid = GetHumanoid(Character); if not Humanoid then return nil end

  PlayerCharacterCache.Humanoid = Humanoid
  return Humanoid
end


local function GetTitanHrp(titan: Instance): BasePart?
  if not IsValid(titan) then return nil end
  local TitanCache = TitansCache[titan.Address]; if not TitanCache then return nil end
  local CachedHrp = TitanCache.Parts.HumanoidRootPart; if IsValid(CachedHrp) then return CachedHrp end
  local TitanHrp = GetHrp(titan);if not TitanHrp then return nil end

  TitanCache.Parts.HumanoidRootPart = TitanHrp
  return TitanHrp
end


local function GetTitanHumanoid(titan: Instance): Humanoid?
  if not IsValid(titan) then return nil end

  local TitanCache = TitansCache[titan.Address]; if not TitanCache then return nil end
  local CachedHumanoid = TitanCache.Parts.Humanoid; if IsValid(CachedHumanoid) then return CachedHumanoid end
  local TitanHumanoid = GetHumanoid(titan); if not TitanHumanoid then return nil end

  TitanCache.Parts.Humanoid = TitanHumanoid
  return TitanHumanoid
end


local function RegisterPlayer(player: Player)
  local existing = CharacterCache[player.Address]

  if existing then
    SyncCharacterCache(player, existing)
    return
  end

  CharacterCache[player.Address] = {
    Character = player.Character,
    Hrp = nil,
    Humanoid = nil,

    Username = player.Name,
    DisplayName = player.DisplayName,
    UserId = player.UserId
  }
end

--#endregion -- Player's character and Titan's character related functions --


--#region -- Titan functions --

local function IsTitanIgnored(titan: Instance): boolean
  if not IsValid(titan) then return false end

  local TitanCache = TitansCache[titan.Address]; if not TitanCache then return false end
  local TitanInfo = TitanCache.Info; if not TitanInfo.Ignored then return false end

  local IgnoredTime = TitanInfo.IgnoredTime; if not IgnoredTime then return false end
  local IgnoreDuration = TitanInfo.IgnoreDuration; if not IgnoreDuration then return false end

  if os.clock() - IgnoredTime >= IgnoreDuration then
    TitanCache.TpFails.Count = 0
    TitanInfo.Ignored = false
    TitanInfo.IgnoredTime = nil
    TitanInfo.IgnoreDuration = nil
    return false
  end

  return true
end


local function RegisterTitanFail(titan: Instance)
  if not IsValid(titan) then return end

  local TitanCache = TitansCache[titan.Address]; if not TitanCache then return end

  local TitanInfo = TitanCache.Info

  TitanCache.TpFails.Count += 1

  if TitanCache.TpFails.Count > 3 then
    TitanInfo.Ignored = true
    TitanInfo.IgnoredTime = os.clock()
    TitanInfo.IgnoreDuration = 5
  end
end


-- Raid bosses (the Female Titan raid, 2026-11-02) carry a Shifter attribute and have far more HP
-- than the client shows (Humanoid.Health reads 100), so they never time out.
local function IsBossTitan(titan: Instance): boolean
  local TitanCache = TitansCache[titan.Address]
  if TitanCache and TitanCache.Info.Boss ~= nil then return TitanCache.Info.Boss end
  local ok, value = pcall(function() return titan:GetAttribute("Shifter") end)
  local Boss = ok and value ~= nil and value ~= false
  if TitanCache then TitanCache.Info.Boss = Boss end
  return Boss
end


-- After a kill timeout the player is still hovering over that titan, so it was the nearest again
-- and got picked straight back: one titan the farm could not kill held a mission for 5 hours
-- (09:08-14:21, 2026-11-02, fresh heartbeat, 0 kills). Skip it for a while, longer each time.
local function IgnoreTimedOutTitan(titan: Instance): number
  local TitanCache = TitansCache[titan.Address]; if not TitanCache then return 0 end
  local TitanInfo = TitanCache.Info
  TitanInfo.Timeouts = (TitanInfo.Timeouts or 0) + 1
  TitanInfo.Ignored = true
  TitanInfo.IgnoredTime = os.clock()
  TitanInfo.IgnoreDuration = math.min(15 * 2 ^ (TitanInfo.Timeouts - 1), 120)
  return TitanInfo.Timeouts
end


local function GetTitanType(titan: Instance): string -- Needs more research
  local TitanCache = TitansCache[titan.Address]; if not TitanCache then return "Normal" end
  local TitanTypeCached = TitanCache.Info.Type; if TitanTypeCached then return TitanTypeCached end

  local TitanType = titan:GetAttribute("Type") :: string? or "Normal"

  TitanCache.Info.Type = TitanType
  return TitanType
end


local function GetTitanNape(titan: Instance): BasePart?
  if not titan or not titan.Parent then return nil end

  local TitanCache = TitansCache[titan.Address]; if not TitanCache then return nil end
  local CachedNape = TitanCache.Parts.Nape; if IsValid(CachedNape) then return CachedNape end
  Tr.step("main", "nape lookup (yields)")
  local NapePart = GetPath(titan, true, "Hitboxes", "Hit", "Nape") :: BasePart; if not NapePart then return nil end

  TitanCache.Parts.Nape = NapePart
  return NapePart
end


-- Cache lookups come first (Address needs no read of the titan). A titan seen dead stays dead:
-- its model is removed soon after, and a removed instance returns garbage instead of erroring,
-- so nothing reads it again.
local function IsTitanAlive(titan: Instance?): boolean
  if not titan then return false end
  local TitanCache = TitansCache[titan.Address]; if not TitanCache then return false end
  local Info = TitanCache.Info
  if Info.Dead then return false end

  local now = os.clock()
  if Info.LastAliveCheck and now - Info.LastAliveCheck < 0.2 then return Info.Alive or false end

  if not titan.Parent then Info.Dead = true; return false end
  local TitanHumanoid = GetTitanHumanoid(titan); if not TitanHumanoid then return false end

  Info.LastAliveCheck = now
  Info.Alive = true
  return true
end


local function IsBossAlive(): boolean
  for _, titan in pairs(KnownTitans) do
    if IsTitanAlive(titan) and IsBossTitan(titan) then return true end
  end
  return false
end


local function GetTitanBobHeight(titan: Instance): number
  local TitanType = GetTitanType(titan); if not TitanType then return UserConfigs.HeightNormal end

  local Height = UserConfigs["Height" .. TitanType] or UserConfigs.HeightNormal
  return Height
end


-- Where the character hovers over a titan, before bob: titan root + height + the menu's X/Z offsets.
-- Pulled napes follow the player (PullNapesTo), so moving the hover moves the hitboxes with it.
local function GetHoverPoint(titan: Instance): (number?, number?, number?)
  local TitanHrp = GetTitanHrp(titan); if not TitanHrp then return nil end
  local p = TitanHrp.Position
  return p.X + UserConfigs.HoverOffsetX, p.Y + GetTitanBobHeight(titan), p.Z + UserConfigs.HoverOffsetZ
end


-- Blade hits only land on ~6 titans per slash (the game's cap), so Pull All Napes pulls the target
-- plus the PullCount-1 live titans nearest to it, within Pull Range, instead of every nape on the
-- map: 40 CFrame + Size writes per slash were the heaviest thing the farm did.
local PullList, PullListAt, PullListFor = {}, 0, nil
local function GetPullTargets(target: Instance): { Instance }
  local TargetHrp = GetTitanHrp(target); if not TargetHrp then return {} end
  local TargetPos = TargetHrp.Position
  local Range = UserConfigs.PullRadius >= 5000 and math.huge or UserConfigs.PullRadius
  local Candidates = {}
  local TargetAddress = target.Address -- Matcha wrappers do not compare equal; compare addresses
  for address, other in pairs(KnownTitans) do
    if address ~= TargetAddress and IsTitanAlive(other) and not IsTitanIgnored(other) then
      local OtherHrp = GetTitanHrp(other)
      if OtherHrp then
        local Distance = (OtherHrp.Position - TargetPos).Magnitude
        if Distance <= Range then table.insert(Candidates, { titan = other, d = Distance }) end
      end
    end
  end
  table.sort(Candidates, function(a, b) return a.d < b.d end)
  local Picked = {}
  for i = 1, math.min(#Candidates, math.max(UserConfigs.PullCount - 1, 0)) do Picked[i] = Candidates[i].titan end
  return Picked
end


-- Moves the target's nape, plus the pulled ones, onto the player for the next slash. One
-- destination per call, 2 studs above the player's actual position (as Kitty's original did, so
-- the napes stay on the player even when the throttled hover lets it drift), and each nape is
-- resized only once: the game keeps the size, and Size writes are as heavy as CFrame writes.
-- That halves the heavy writes of the old per-nape BringNapeToPlayer and skips its lookups.
-- Raid bosses open other limbs (Hitboxes.Hit: Eyes, LeftArm, LeftLeg, RightArm, Nape, RightLeg on the
-- Female Titan); enough damage there stuns the boss and the open limb changes. The game marks the
-- open limb with a skull: the boss's "Marker" BillboardGui, whose Adornee is that Hit part. Matcha
-- cannot read Adornee, so it is read from memory (0x710, found 2026-11-02 by scanning the Marker for
-- pointers to the boss's parts: 0x60 Parent, 0x710 Hit.RightArm while the right arm was open).
-- Checked at most twice a second; the nape is the fallback.
local MARKER_ADORNEE_OFFSET = 0x710
local function GetTitanWeakSpot(titan: Instance): BasePart?
  local TitanCache = TitansCache[titan.Address]
  if not TitanCache or not IsBossTitan(titan) then return GetTitanNape(titan) end
  local Info = TitanCache.Info
  local now = os.clock()
  if Info.WeakAt and now - Info.WeakAt < 0.5 then
    if Info.WeakPart and Info.WeakPart.Parent then return Info.WeakPart end
    return GetTitanNape(titan)
  end
  Info.WeakAt = now
  Info.WeakPart = nil
  local Marker = titan:FindFirstChild("Marker")
  local Hitboxes = titan:FindFirstChild("Hitboxes")
  local Hit = Hitboxes and Hitboxes:FindFirstChild("Hit")
  if Marker and Hit then
    local ok, adornee = pcall(memory_read, "uintptr_t", Marker.Address + MARKER_ADORNEE_OFFSET)
    if ok and adornee and adornee ~= 0 then
      for _, part in ipairs(Hit:GetChildren()) do
        if part.Address == adornee then Info.WeakPart = part; break end
      end
    end
  end
  local Name = Info.WeakPart and Info.WeakPart.Name or "none"
  if Name ~= Info.WeakName then
    Info.WeakName = Name
    Boot(string.format("boss %s vulnerable limb: %s", titan.Name, Name))
  end
  return Info.WeakPart or GetTitanNape(titan)
end

local NAPE_REPULL_DISTANCE = 3 -- studs; a nape closer than this to the pull spot is left alone
local SizedNapes: { [number]: number } = {}
local SizedNapesCount = 0
local PULL_MAX_DISTANCE = 600 -- studs from the target beyond which nothing is pulled
local PullSlash = 0 -- slashes pulled so far; the extra napes go on every other one
local SkippedNapes = 0 -- nape writes refused by the live-titan check (black box: skipped=)
local function PullNapesTo(target: Instance, extra: { Instance }?)
  local PlayerHrp = GetPlayerHrp(LocalPlayer); if not PlayerHrp then return end
  -- Right after a reload the player is still at the sky spot, 3,000+ studs off, and the first slash
  -- dragged up to PullCount welded napes (and their titans) up there; Matcha froze within seconds
  -- of that twice on 2026-11-03. Wait a frame for the hover to bring us over the target instead.
  local TargetHrp = GetTitanHrp(target)
  if TargetHrp and (TargetHrp.Position - PlayerHrp.Position).Magnitude > PULL_MAX_DISTANCE then return end
  local Size = UserConfigs.NapeSize
  -- Pulled napes kill titans the farm is not targeting, and the alive cache (0.2s) and pull list
  -- (0.5s) lag behind. Before each write:
  -- the titan is still in the Titans folder and the nape still hangs off Hitboxes.Hit.
  -- Matcha's native Health lookup can spin indefinitely when the underlying instance is stale.
  local FolderAddress = TitansFolder.Address
  local function Writable(titan: Instance, Nape: BasePart): boolean
    local Parent = titan.Parent; if not Parent or Parent.Address ~= FolderAddress then return false end
    local Cache = TitansCache[titan.Address]
    if not Cache or Cache.Info.Dead or not GetTitanHumanoid(titan) then return false end
    local NapeParent = Nape.Parent
    return NapeParent ~= nil and NapeParent.Name == "Hit"
  end
  local function PlacePart(titan: Instance, Nape: BasePart)
    Tr.step("main", "pull: live check")
    if not Writable(titan, Nape) then SkippedNapes += 1; return end
    -- Read per nape: with a frame between napes the player has moved since the last one.
    local Dest = PlayerHrp.CFrame * CFrame.new(0, UserConfigs.NapeOffsetY, 0)
    -- A Position read is cheap and a CFrame write is not: skip napes still sitting on the player.
    -- (Napes snap back to their titans, so in practice this rarely skips; seen 2026-11-03.)
    Tr.step("main", "pull: read nape position")
    if (Nape.Position - Dest.Position).Magnitude > NAPE_REPULL_DISTANCE then
      Tr.step("main", "pull: nape CFrame write")
      Nape.CFrame = Dest
      HeavyWrites += 1
    end
    local Key = Nape.Address
    if SizedNapes[Key] ~= Size then
      Tr.step("main", "pull: nape Size write")
      Nape.Size = Vector3New(Size, Size, Size)
      HeavyWrites += 1
      if not SizedNapes[Key] then SizedNapesCount += 1 end
      SizedNapes[Key] = Size
    end
  end
  local function Place(titan: Instance)
    Tr.step("main", "pull: find weak spot")
    local WeakSpot = GetTitanWeakSpot(titan); if not WeakSpot then return end
    PlacePart(titan, WeakSpot)
    if not UserConfigs.PullBossLimbs or not IsBossTitan(titan) then return end
    local Hitboxes = titan:FindFirstChild("Hitboxes")
    local Hit = Hitboxes and Hitboxes:FindFirstChild("Hit")
    if not Hit then return end
    for _, part in ipairs(Hit:GetChildren()) do
      if Stopped() or not IsValid(PlayerHrp) then break end
      if part.Address ~= WeakSpot.Address and part:IsA("BasePart") then
        task.wait() -- avoid a burst of native writes that can stall Matcha
        PlacePart(titan, part)
      end
    end
  end
  Place(target)
  -- Pull All Napes wrote ~6 napes back to back every slash: ~110 ms without a yield, so the hover
  -- and heartbeat stalled each slash, and both traced Matcha hangs (03:34, 03:39 on 2026-11-03)
  -- came right after one. Now the extras go every other slash, one frame apart.
  PullSlash += 1
  if extra and PullSlash % 2 == 0 then
    for _, other in ipairs(extra) do
      task.wait()
      if Stopped() or not IsValid(PlayerHrp) then break end
      if IsTitanAlive(other) then Place(other) end
    end
  end
  if SizedNapesCount > 1000 then SizedNapes = {}; SizedNapesCount = 0 end -- titans come and go
end

local function GetNearestTitan(): Instance?
  if os.clock() - LastNearestUpdate < 1 and CachedNearestTitan and CachedNearestTitan.Parent and IsTitanAlive(CachedNearestTitan) and not IsTitanIgnored(CachedNearestTitan) then return CachedNearestTitan end

  local NearestTitan: Instance? = nil
  local NearestDistance = math.huge

  local PlayerHrp = GetPlayerHrp(LocalPlayer)
  if not PlayerHrp then return nil end

  for _, titan in pairs(KnownTitans) do
    if not titan or not titan.Parent then continue end
    -- if not titan:IsA("Model") then continue end
    if IsTitanIgnored(titan) then continue end
    if not IsTitanAlive(titan) then continue end

    local TitanHrp = GetTitanHrp(titan); if not TitanHrp then continue end

    local ok, Distance = pcall(function()
      return (TitanHrp.Position - PlayerHrp.Position).Magnitude
    end)

    if not ok or not Distance then
      DebugPrint( "warn", 0, nil, nil, "Failed to calculate distance to titan: ", tostring(titan.Name), " Error: ", tostring(Distance) )

      continue
    end

    if Distance < NearestDistance then
      NearestDistance = Distance
      NearestTitan = titan
    end
  end

  CachedNearestTitan = NearestTitan
  LastNearestUpdate = os.clock()

  return NearestTitan
end


local function TpAboveTitan(titan): boolean -- This might require changes!
  if not titan or not titan.Parent then return false end

  local TitanCache = TitansCache[titan.Address]; if not TitanCache then return false end
  local LocalPlayerCache = CharacterCache[LocalPlayer.Address]; if not LocalPlayerCache then return false end
  local Hrp = GetPlayerHrp(LocalPlayer); if not Hrp then return false end
  local x, y, z = GetHoverPoint(titan); if not x then return false end

  local BobOffset = math.sin(os.clock() * math.pi * 2) * UserConfigs.BobAmplitude

  DebugPrint("debug", 3, nil, nil, "Teleporting to the titan:", titan.Name)

  HeavyWrites += 1
  local ok, err = pcall(function()
    -- Velocity is left alone on purpose: gravity builds it to ~-700 studs/s while hovering, and slash
    -- damage scales with speed. Resetting it (tried 2026-11-01) stopped one-slash kills and the farm
    -- ran out of blades. The cost: a stall in this loop drops the character fast.
    Hrp.CFrame = CFrame.new(x, y + BobOffset, z)
  end)

  if not ok then
    DebugPrint("warn", 0, nil, nil, "Error happened while setting CFrame to titan: " .. err)
    return false
  end

  return true
end


local function RegisterTitan(titan: Instance?)
  if not titan or not titan.Parent then
    DebugPrint( "warn", 0, nil, nil, "RegisterTitan: invalid titan or missing Address: ", titan and tostring(titan.Name) or "nil", titan and tostring(titan.Address) or "0" )
    return
  end

  if TitansCache[titan.Address] then return end

  TitansCache[titan.Address] = {
    Instance = titan,

    Info = {
      Name = titan.Name,
      Type = nil,

      Alive = true,

      Ignored = false,
      IgnoredTime = nil,
      IgnoreDuration = nil
    },

    Parts = {
      Nape = nil,
      HumanoidRootPart = nil,
      Humanoid = nil
    },

    Nape = {
      CurrentSize = nil
    },

    TpFails = {
      Count = 0
    }
  }

  local Parts = TitansCache[titan.Address].Parts
  Parts.Nape = GetTitanNape(titan)
  Parts.HumanoidRootPart = GetTitanHrp(titan)
  Parts.Humanoid = GetTitanHumanoid(titan)

  DebugPrint("debug", 0, nil, nil, string.format("Register information: Titan Info: %s", titan.Name))
end

--#endregion -- Titan functions --



--#region Gas tank functions --

local function GetUiCached(cacheKey: string, parent: Instance, ...)
  local cached = UiCache[cacheKey]; if cached then return cached end

  local obj = GetPath(parent, false, ...); if not obj then return nil end

  UiCache[cacheKey] = obj
  return obj
end


local function AreBladesFullyBroken(): boolean
  if os.clock() - LastBladeCheck < 0.5 then return CachedBladesBroken end

  LastBladeCheck = os.clock()

  local RightBlade = BladeCache.RightBlade :: Instance
  local LeftBlade = BladeCache.LeftBlade :: Instance

  if not RightBlade or not RightBlade.Parent or not LeftBlade or not LeftBlade.Parent then
    local LocalPlayerCharacterCache = CharacterCache[LocalPlayer.Address]; if not LocalPlayerCharacterCache then return false end

    local Character = LocalPlayerCharacterCache.Character or GetPlayerCharacter(LocalPlayer); if not Character then return false end
    local Rig_ = Character:FindFirstChild("Rig_" .. LocalPlayer.Name); if not Rig_ then return false end

    local RightHand = BladeCache.RightHand :: Instance
    local LeftHand = BladeCache.LeftHand :: Instance

    if not RightHand or not LeftHand then
      RightHand = Rig_:FindFirstChild("RightHand")
      LeftHand = Rig_:FindFirstChild("LeftHand")

      if not RightHand or not LeftHand then return false end

      BladeCache.RightHand = RightHand
      BladeCache.LeftHand = LeftHand
    end

    RightBlade = RightHand:FindFirstChild("Blade_1")
    LeftBlade = LeftHand:FindFirstChild("Blade_1")

    if not RightBlade or not LeftBlade then return false end

    BladeCache.RightBlade = RightBlade
    BladeCache.LeftBlade = LeftBlade
  end

  local ok, AreBroken = pcall(function()
    local RightTransparency = memory_read("float", RightBlade.Address :: number + TransparencyBasePartOffset)
    local LeftTransparency = memory_read("float", LeftBlade.Address :: number + TransparencyBasePartOffset)

    return RightTransparency >= 0.9 and LeftTransparency >= 0.9
  end)

  if not ok then
    DebugPrint("warn", 0, nil, nil, "Memory read failed:", AreBroken)
    return false
  end

  CachedBladesBroken = AreBroken
  return AreBroken
end


local function DoINeedToRefill(): boolean -- The 0 / 3 counter

  local Blades = GetUiCached("Blades", DownMiddlePartUi, "Blades"); if not Blades then return true end
  local TextForBlades = GetUiCached("TextForBlades", Blades, "Sets") :: TextLabel?; if not TextForBlades then return true end

  local Gas = GetUiCached("Gas", DownMiddlePartUi, "Gas"); if not Gas then return true end
  local TextForGas = GetUiCached("TextForGas", Gas, "Percentage") :: TextLabel?; if not TextForGas then return true end

  local BladesValue = tonumber(TextForBlades.Text:match("%d+")) or 0
  local GasValue = tonumber(TextForGas.Text:match("%d+")) or 0


  local NeedRefill = BladesValue == 0 or GasValue == 0

  if NeedRefill then
    WhatShouldIBeDoing = "refill"
  end

  return NeedRefill
end


local function IsReloadingBlades(): boolean  -- Basically, when reloading the 0 / 3 counter, the 'BV' is missing
  local LocalPlayerCache = CharacterCache[LocalPlayer.Address]; if not LocalPlayerCache then return false end

  local Hrp = LocalPlayerCache.Hrp or GetPlayerHrp(LocalPlayer); if not Hrp then return false end
  if Hrp:FindFirstChild("BV") then return false end


  return true
end


-- Nearest live titan, skipped ones included (a titan the farm gave up on can still eat us).
local function GetNearestTitanAny(): Instance?
  local Hrp = GetPlayerHrp(LocalPlayer); if not Hrp then return nil end
  local Best, BestDistance = nil, math.huge
  for _, titan in pairs(KnownTitans) do
    local TitanHrp = IsTitanAlive(titan) and GetTitanHrp(titan)
    if TitanHrp then
      local Distance = (TitanHrp.Position - Hrp.Position).Magnitude
      if Distance < BestDistance then Best, BestDistance = titan, Distance end
    end
  end
  return Best
end

-- Stuck (out of blades with no refill, or no kill for minutes): stop hovering, sit on the nearest
-- titan and let it kill us so the run resets. The game has no reset button.
local function GiveUpToTitan(reason: string?)
  reason = reason or "stuck refilling"
  DebugPrint("warn", 0, nil, nil, reason .. ", letting a titan kill us.")
  Boot(reason .. ", feeding a titan")
  WhatShouldIBeDoing = "dying" -- the RenderStepped hover only runs while attacking
  CurrentTitanTarget = nil
  FarmStats.Target = "none"
  FarmStats.Status = reason .. ", feeding a titan"

  local Started = os.clock()
  local LastTp = 0

  while not Stopped() and os.clock() - Started < 30 do
    Progress()
    local Humanoid = GetPlayerHumanoid(LocalPlayer)
    local ok, health = pcall(function() return Humanoid.Health end)
    if not ok or type(health) ~= "number" or health <= 0 then break end

    -- Re-teleport every 2s (titans walk); CFrame writes are expensive, so not per frame.
    if os.clock() - LastTp > 2 then
      local Hrp = GetPlayerHrp(LocalPlayer)
      local Titan = GetNearestTitanAny()
      local TitanHrp = Titan and GetTitanHrp(Titan)
      if Hrp and TitanHrp then
        Hrp.AssemblyLinearVelocity = Vector3Zero
        local p = TitanHrp.Position
        Tr.step("main", "give up: tp onto titan (write)")
        Hrp.CFrame = CFrame.new(p.X, p.Y, p.Z) -- matcha's CFrame.new rejects a single Vector3
        LastTp = os.clock()
      end
    end

    task.wait(0.25)
  end

  RefillStuckSince = nil
  WhatShouldIBeDoing = "attack"
end


local function HandleAllReloads()
  if not AreBladesFullyBroken() then return end

  local LocalPlayerCharacterCache = CharacterCache[LocalPlayer.Address]; if not LocalPlayerCharacterCache then return end
  local Hrp = LocalPlayerCharacterCache.Hrp or GetPlayerHrp(LocalPlayer); if not Hrp then return end

  local Time = os.clock()

  if DoINeedToRefill() then
    DebugPrint("debug", 0, nil, nil, "Detected that the local player needs refilling.")

    -- The inner loop times out after 10s and gets re-entered, so track the stuck time across calls.
    if not RefillStuckSince or os.clock() - RefillLastSeen > 5 then RefillStuckSince = os.clock() end

    while true do
      Progress()
      RefillLastSeen = os.clock()
      if not DoINeedToRefill() then RefillStuckSince = nil; WhatShouldIBeDoing = "attack"; break end
      if os.clock() - RefillStuckSince > REFILL_STUCK_LIMIT then GiveUpToTitan(); return end
      if IsReloadingBlades() then
        task.wait(0.5)
        continue
      end

      if os.clock() - Time > 10 then
        DebugPrint("warn", 0, nil, nil, "Timeout happened while trying to refill?")
        WhatShouldIBeDoing = "attack"
        break
      end

      if GasTankPosition then
        Hrp.AssemblyLinearVelocity = Vector3Zero
        task.wait(0.24)

        Tr.step("main", "refill: tp to gas tank (write)")
        Hrp.Position = GasTankPosition + Vector3New(5, 0, 0)
        Hrp.AssemblyLinearVelocity = Vector3Zero

        task.wait(0.5)

        keypress(0x52)
        task.wait(0.5)
        keyrelease(0x52)

        task.wait(1)
        continue
      end


      if not GasTankModel then HandleDifferentGasTankPaths() end -- the map may have loaded after startup
      if not GasTankModel then WhatShouldIBeDoing = "attack"; return end
      -- Docks' tank groups have a "Refill" trigger part whose Position Matcha reads natively
      -- (13 studs wide, so the +5 X above still lands inside it).
      local RefillPart = GasTankModel:FindFirstChild("Refill"); if RefillPart and RefillPart:IsA("BasePart") then GasTankPosition = RefillPart.Position; continue end
      local PrimaryPart = GasTankModel.Primary; if PrimaryPart and PrimaryPart:IsA("BasePart") then GasTankPosition = PrimaryPart.Position; continue end

      local PartAddress = memory_read("uintptr_t", GasTankModel.Address + PrimaryPartOffset )

      if PartAddress == 0 then
        DebugPrint("warn", 0, nil, nil, "No PrimaryPart for gas tank found!")
        return
      end

      local Primitive = memory_read( "uintptr_t", PartAddress + BaseToPrimitiveOffset )

      if Primitive == 0 then
        DebugPrint("warn", 0, nil, nil, "No Primitive part found for 'PartAdress'!")
        return
      end

      local x = memory_read("float", Primitive + PrimitivePositionOffset)
      local y = memory_read("float", Primitive + PrimitivePositionOffset + 4)
      local z = memory_read("float", Primitive + PrimitivePositionOffset + 8)

      GasTankPosition = Vector3New(x, y, z)
      DebugPrint("debug", 0, nil, nil, "Fetched gas tank position from memory: ", GasTankPosition)
    end

  else   -- Case 2: Only needs to reload blades
    if ReloadingBlades then return end
    if os.clock() - LastReloadingTime < 3 then return end

    DebugPrint("debug", 0, nil, nil, "Detected that the local player needs reloading.")

    ReloadingBlades = true
    LastReloadingTime = os.clock()

    task.spawn(function()
      if not isrbxactive() then
        DebugPrint("debug", 0, nil, nil, "Roblox is not active /:")
        ReloadingBlades = false
        return
      end

      DebugPrint("debug", 0, nil, nil, "Proceeding to reload blades.")

      Tr.step("reload", "tp to sky (write)")
      Hrp.CFrame = SafePosNow()

      Tr.step("reload", "press R")
      keypress(0x52)
      task.wait(0.5)
      keyrelease(0x52)
      task.wait(0.5)
      Tr.step("reload", "done")

      ReloadingBlades = false
    end)
  end
end

--#endregion Gas tank functions --


--#region -- Ui elements functions --

local function IsObjectVisible(object: GuiObject): boolean
  if not object or not object.Address then
    return false
  end

  local ok, value = pcall(function()
    return memory_read("byte", object.Address + VisibleOffset)
  end)

  if not ok then
    DebugPrint( "warn", 0, nil, nil, "Something went wrong in memory reading for the object: ", tostring(object:GetFullName()) )
    return false
  end

  local visible = value ~= 0
  return visible
end

Stats.CutsceneSkip = { Frame = nil, Down = false, ReleaseAt = 0, NextPress = 0, Visible = false }
function Stats.SkipCutsceneTick()
  local skip = Stats.CutsceneSkip
  local now = os.clock()
  if skip.Down and now >= skip.ReleaseAt then
    keyrelease(0x45)
    skip.Down = false
  end
  if not UserConfigs.AutoSkipCutscenes then skip.Visible = false; return end
  if not skip.Frame or not skip.Frame.Parent then skip.Frame = Interface:FindFirstChild("Skip") end
  skip.Visible = skip.Frame ~= nil and IsObjectVisible(skip.Frame)
  if skip.Visible and isrbxactive() and not skip.Down and now >= skip.NextPress then
    keypress(0x45) -- SKIP [E]
    skip.Down = true
    skip.ReleaseAt = now + 0.12
    skip.NextPress = now + 1
    Boot("cutscene skip E pressed")
  end
end


local function IsRetryVisible(): boolean

  local RewardsFrame;

  if UiCache.RewardsFrame and UiCache.RewardsFrame.Parent then
    return IsObjectVisible(UiCache.RewardsFrame)
  end

  RewardsFrame = GetPath(PlayerGui, true, "Interface", "Rewards") :: GuiObject; if not RewardsFrame then return false end

  UiCache.RewardsFrame = RewardsFrame
  return IsObjectVisible(RewardsFrame)
end


local RetryCount = 0

local function PressRetry(): boolean
  if not IsRetryVisible() or not isrbxactive() then return false end
  local button = GetPath(PlayerGui, false, "Interface", "Rewards", "Main", "Info", "Main", "Buttons", "Retry") :: GuiObject?
  local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
  if not button or not viewport then return false end
  local title = button:FindFirstChild("Title") :: TextLabel?
  if title and string.find(string.upper(title.Text), "STARTING", 1, true) then return true end
  local pos, size = button.AbsolutePosition, button.AbsoluteSize
  -- Verified live click: (1475,1136) at 2560x1440. Retry.AbsolutePosition is
  -- (1428,1103), while Matcha reports zero AbsoluteSize for this button.
  local x = pos.X + (size.X > 1 and size.X / 2 or viewport.X * 0.018)
  local y = pos.Y + (size.Y > 1 and size.Y / 2 or viewport.Y * 0.0231)
  local targetX, targetY = math.floor(x), math.floor(y)
  mousemoveabs(targetX, targetY)
  mousemoverel(1, 0)
  local mouse = LocalPlayer:GetMouse()
  local moveDeadline = os.clock() + 1.5
  while os.clock() < moveDeadline and (math.abs(mouse.X - targetX) > 6 or math.abs(mouse.Y - targetY) > 6) do
    task.wait(0.05)
  end
  if math.abs(mouse.X - targetX) > 6 or math.abs(mouse.Y - targetY) > 6 then
    Boot(string.format("retry pointer missed target (%d,%d -> %d,%d)", targetX, targetY, mouse.X, mouse.Y))
    return false
  end
  task.wait(0.12)
  mouse1click()
  RetryCount += 1
  task.wait(0.3)
  local started = title and string.find(string.upper(title.Text), "STARTING", 1, true) ~= nil
  Boot(string.format("retry click %d (%s)", RetryCount, started and "starting" or "awaiting response"))
  return started or false
end

--#endregion -- Ui elements functions --



--#region -- Human skills --
local function TapKey(vk: number)
  keypress(vk)
  task.wait(0.03)
  keyrelease(vk)
end

-- "Q" -> 0x51, "3" -> 0x33; anything else (placeholder "Key", "LMB") -> nil.
local function KeyToVk(text: string?): number?
  if type(text) ~= "string" then return nil end
  text = string.upper((string.gsub(text, "%s", "")))
  if #text ~= 1 then return nil end
  local b = string.byte(text)
  if (b >= 0x30 and b <= 0x39) or (b >= 0x41 and b <= 0x5A) then return b end
  return nil
end

-- A skill succeeds when its hotbar countdown starts. Tap it between slashes until that
-- happens, then wait 2.5 seconds before trying another. The awakening slot is controlled
-- by the Bar attribute: press once at full charge and never press again while it drains.
Stats.HumanSkills = { LastSuccess = -math.huge, LastCheck = -math.huge, LastTap = -math.huge,
  NextSlot = 1, Pending = nil, PendingSince = 0, RetryAfter = {}, LastBar = nil,
  AwakeningActive = false, Slots = {}, Labels = {}, LabelSince = {} }
function Stats.UseHumanSkill(): boolean
  if not UserConfigs.HumanSkills then return false end
  local state = Stats.HumanSkills
  local now = os.clock()
  if now - state.LastCheck < 0.15 then return false end
  state.LastCheck = now
  local bar, max = tonumber(LocalPlayer:GetAttribute("Bar")), tonumber(LocalPlayer:GetAttribute("Max_Bar"))
  if bar and max and max > 0 then
    local wasActive = state.AwakeningActive
    if state.LastBar and bar < state.LastBar - 0.1 and bar > 0 then state.AwakeningActive = true end
    if bar <= 0.1 then state.AwakeningActive = false end
    state.LastBar = bar
    if state.AwakeningActive ~= wasActive then
      Boot(string.format("awakening %s at %.1f/%.1f bar", state.AwakeningActive and "active" or "empty", bar, max))
    end
  end
  local awakening = math.clamp(math.floor(UserConfigs.AwakeningSlot), 1, 5)
  local function slotUi(slot)
    local skill = state.Slots[slot]
    if not skill or not skill.Parent then
      skill = GetPath(Interface, false, "HUD", "Main", "Top", "7", "Hotbar", "Skill_" .. slot)
      state.Slots[slot] = skill
    end
    local cooldown = skill and skill:FindFirstChild("Cooldown")
    local label = cooldown and cooldown:FindFirstChild("Label")
    local keyFrame = skill and skill:FindFirstChild("Key")
    local key = keyFrame and keyFrame:FindFirstChild("Key")
    local text = label and label.Text
    if text ~= state.Labels[slot] then
      state.Labels[slot] = text
      state.LabelSince[slot] = now
    end
    return type(text) == "string" and tonumber(string.match(text, "[%d%.]+")) or nil,
      KeyToVk(key and key.Text), text, now - (state.LabelSince[slot] or now) >= 2
  end
  if state.Pending then
    local slot = state.Pending
    local seconds, vk, text = slotUi(slot)
    local activated = slot == awakening and bar and state.BarAtPress and bar < state.BarAtPress - 0.1 and state.AwakeningActive
    local cooldownStarted = seconds and seconds > 1 and text ~= state.PendingText
    if (slot ~= awakening and cooldownStarted) or activated then
      state.LastSuccess = now
      state.NextSlot = slot % 5 + 1
      state.Pending = nil
      Boot(string.format("human skill slot %d confirmed", slot))
      return true
    end
    if now - state.PendingSince > 8 or not vk then
      state.RetryAfter[slot] = now + 5
      state.NextSlot = slot % 5 + 1
      state.Pending = nil
      return false
    end
    if slot == awakening and cooldownStarted then return false end
    if now - state.LastTap >= 0.2 then
      state.LastTap = now
      TapKey(vk)
    end
    return false
  end
  if now - state.LastSuccess < 2.5 then return false end
  for offset = 0, 4 do
    local slot = (state.NextSlot + offset - 1) % 5 + 1
    local canAwaken = slot ~= awakening or (bar and max and max > 0 and bar >= max - 0.5 and not state.AwakeningActive)
    if canAwaken and now >= (state.RetryAfter[slot] or 0) then
      local seconds, vk, text, stable = slotUi(slot)
      if seconds and (seconds <= 1 or stable) and vk then
        state.Pending = slot
        state.PendingText = text
        state.BarAtPress = slot == awakening and bar or nil
        state.PendingSince = now
        state.LastTap = now
        TapKey(vk)
        return false
      end
    end
  end
  return false
end

--#endregion -- Human skills --



--#region -- Quick time events --
-- Raids show Interface.QTE (a CanvasGroup, hidden otherwise) with Main.Key (the key to press, e.g.
-- "D"), Main.Timing (a frame whose size animates) and Main.Button. Seen idle only (2026-11-02):
-- Timing at scale 1, so the guess is that it shrinks or grows toward 1 and the key is pressed
-- when it gets there. If it never moves, the key is pressed after Qte.STILL_PRESS seconds.
-- Ticked from RenderStepped (no yields): memory reads only, and the key is released a tick later.
-- The first QTEs are traced to boot.txt to tune this.
local Qte = {
  HIT_BAND = 0.06,    -- press when the Timing scale is within this of 1
  STILL_PRESS = 0.35, -- seconds of an unmoving Timing before pressing anyway
  Frame = nil, Timing = nil, Key = nil,
  Active = false,
  Since = 0, PromptAt = 0, PressedAt = nil, ReleaseAt = nil, Vk = nil, PromptKey = nil,
  LastScale = nil, LastMove = 0,
  Trace = {},
  Count = 0,
}

-- Called from a farm thread (GetPath yields).
local LastQteLookup = 0
local function FindQteUi()
  if not UserConfigs.AutoQTE then return end -- the menu's Auto Quick Time Events toggle
  if Qte.Frame and Qte.Frame.Parent then return end
  -- Only raids have it; elsewhere this was a lookup and a yield on every main loop pass.
  if os.clock() - LastQteLookup < 2 then return end
  LastQteLookup = os.clock()
  Qte.Frame = GetPath(Interface, false, "QTE")
  Qte.Timing = Qte.Frame and GetPath(Qte.Frame, false, "Main", "Timing")
  Qte.Key = Qte.Frame and GetPath(Qte.Frame, false, "Main", "Key")
end

local function QteTick()
  local now = os.clock()
  if Qte.ReleaseAt and now >= Qte.ReleaseAt then pcall(keyrelease, Qte.Vk); Qte.ReleaseAt = nil end
  -- Switched off mid-QTE, Active would stay set and hold KillTitan in "quick time event".
  if not UserConfigs.AutoQTE then Qte.Active = false; return end
  if not Qte.Frame or not Qte.Timing then return end
  local visible = IsObjectVisible(Qte.Frame)
  if not visible then
    if Qte.Active then
      Qte.Active = false
      Qte.Count += 1
      if Qte.Count <= 5 then Boot(string.format("QTE %d over after %.2fs: %s", Qte.Count, now - Qte.Since, table.concat(Qte.Trace, " "))) end
    end
    return
  end
  local scale = memory_read("float", Qte.Timing.Address + SizeOffset) -- Size.X.Scale
  local text = Qte.Key and Qte.Key.Text
  -- One QTE is a chain of prompts (16s on the Female Titan raid): Timing shrinks 5 -> 1 in ~0.45s,
  -- then jumps back up, maybe with a new key. Each jump or key change is a new prompt to answer.
  local newPrompt = Qte.Active and ((Qte.LastScale and scale > Qte.LastScale + 0.5) or text ~= Qte.PromptKey)
  if not Qte.Active or newPrompt then
    if not Qte.Active then Qte.Since = now; Qte.Trace = {} end
    Qte.Active, Qte.PromptAt, Qte.PressedAt, Qte.LastMove, Qte.LastScale = true, now, nil, now, scale
    Qte.PromptKey = text
    Qte.Vk = KeyToVk(text)
    if #Qte.Trace < 40 then table.insert(Qte.Trace, string.format("[%.2f %s from %.2f", now - Qte.Since, tostring(text), scale)) end
  end
  if Qte.LastScale and math.abs(scale - Qte.LastScale) > 0.001 then Qte.LastMove = now end
  local crossed = Qte.LastScale and (Qte.LastScale - 1) * (scale - 1) < 0
  Qte.LastScale = scale
  if Qte.PressedAt or not Qte.Vk then return end
  local moving = now - Qte.LastMove < Qte.STILL_PRESS
  if (moving and (math.abs(scale - 1) <= Qte.HIT_BAND or crossed)) or (not moving and now - Qte.PromptAt >= Qte.STILL_PRESS) then
    Qte.PressedAt = now
    pcall(keypress, Qte.Vk)
    Qte.ReleaseAt = now + 0.05
    if #Qte.Trace < 40 then Qte.Trace[#Qte.Trace] = Qte.Trace[#Qte.Trace] .. string.format(" press +%.2f at %.2f]", now - Qte.PromptAt, scale) end
  end
end

--#endregion -- Quick time events --



-- // Some functions that couldn't fit before \\ --
-- Black box for death analysis: one line of state, rewritten to aotr/blackbox.txt every second and
-- copied into boot.txt on a death. Both files survive Matcha restarting itself, which takes the
-- print log with it.
local LastBlackBox = ""
local LastWritesCount, LastWritesAt, WritesPerSecond = 0, os.clock(), 0
local function BlackBoxLine(): string
  local now = os.clock()
  if now - LastWritesAt >= 0.5 then
    WritesPerSecond = (HeavyWrites - LastWritesCount) / (now - LastWritesAt)
    LastWritesCount, LastWritesAt = HeavyWrites, now
  end
  local ok, line = pcall(function()
    local Hrp = GetPlayerHrp(LocalPlayer)
    local Humanoid = GetPlayerHumanoid(LocalPlayer)
    local p = Hrp and Hrp.Position
    local v = Hrp and Hrp.AssemblyLinearVelocity
    local Target = CurrentTitanTarget
    local TargetHrp = Target and GetTitanHrp(Target)
    local hp = Humanoid and Humanoid.Health
    local AliveTitans, NearestTitanDist = 0, math.huge
    for _, t in pairs(KnownTitans) do
      if IsTitanAlive(t) then
        AliveTitans += 1
        local th = p and GetTitanHrp(t)
        if th then NearestTitanDist = math.min(NearestTitanDist, (th.Position - p).Magnitude) end
      end
    end
    return string.format("%s status=%s kills=%d timeouts=%d titansAlive=%d nearestTitan=%s target=%s y=%s speed=%s hp=%s targetDist=%s hoverAge=%.1fs doing=%s writes=%.0f/s skipped=%d",
      os.date("%H:%M:%S"), FarmStats.Status, FarmStats.Kills, FarmStats.Timeouts, AliveTitans,
      NearestTitanDist < math.huge and string.format("%.0f", NearestTitanDist) or "-", FarmStats.Target,
      p and string.format("%.0f", p.Y) or "?", v and string.format("%.0f", v.Magnitude) or "?",
      type(hp) == "number" and string.format("%.0f", hp) or "?",
      (p and TargetHrp) and string.format("%.0f", (TargetHrp.Position - p).Magnitude) or "-",
      os.clock() - LastHoverAt, tostring(WhatShouldIBeDoing), WritesPerSecond, SkippedNapes)
  end)
  return ok and line or ("blackbox error: " .. tostring(line))
end

-- The last ~15s of black-box lines (2 a second), written to aotr/deaths.txt on a death or when the
-- Retry screen shows up: a run can end with the farm never seeing hp <= 0.
local BoxHistory: { string } = {}
local function PushHistory(line: string)
  table.insert(BoxHistory, line)
  if #BoxHistory > 30 then table.remove(BoxHistory, 1) end
end
local function DumpHistory(reason: string)
  pcall(function()
    local path = "aotr/deaths.txt"
    local old = (type(isfile) ~= "function" or isfile(path)) and readfile(path) or ""
    if #old > 60000 then old = string.sub(old, -30000) end
    writefile(path, old .. string.format("=== %s %s (place=%s)\n%s\nnow: %s\n\n",
      os.date("%H:%M:%S"), reason, tostring(game.PlaceId), table.concat(BoxHistory, "\n"), BlackBoxLine()))
  end)
  Boot(reason .. "; last 15s in deaths.txt")
end

local function LogDeath(where: string)
  DumpHistory("death (" .. where .. ")")
end


local function IsLocalAlive(): boolean
  local Humanoid = GetPlayerHumanoid(LocalPlayer); if not Humanoid then return false end
  -- Health reads nil on a humanoid that is being torn down after a death; that crashed the farm.
  local ok, health = pcall(function() return Humanoid.Health end)
  return ok and type(health) == "number" and health > 0
end


-- Clicks only land while Roblox has focus; the hover retreats to the safe spot while it does not.
local function UpdateRobloxState()
  CurrentRobloxState = isrbxactive() and "Active" or "Inactive"
end

-- Waves places a separate Crate_<player> model each round. The static map also has dozens of
-- decorative Crates; only the player-specific model has a touch-enabled Hitbox.
local PerkManager
local CrateRoute = { Cached = nil, NextCheck = 0, LastAttemptAt = -math.huge, LastAttemptAddress = nil,
  EquipmentPending = false, EquipmentClicks = 0, NextEquipmentAttempt = 0,
  UpgradePending = false, MaxClicks = 0, RegenClicks = 0, RefillsClicks = 0, NextUpgradeAttempt = 0,
  MarketPending = false, RoundNumber = nil, RegenPlanned = 0, RefillsPlanned = 0 }
CrateRoute.WaveState = { JobId = game.JobId, Wave = "", RegenTotal = 0,
  EquipmentClicks = 0, MaxClicks = 0, RegenClicks = 0, RefillsClicks = 0,
  RegenPlanned = 0, RefillsPlanned = 0, MarketAttempts = {}, Maxed = {} }
pcall(function()
  if type(isfile) == "function" and not isfile("aotr/waves_purchases.json") then return end
  local saved = HttpService:JSONDecode(readfile("aotr/waves_purchases.json"))
  if type(saved) == "table" and saved.JobId == game.JobId then
    CrateRoute.WaveState = saved
    CrateRoute.WaveState.Wave = type(saved.Wave) == "string" and saved.Wave or ""
    CrateRoute.WaveState.RegenTotal = math.clamp(tonumber(saved.RegenTotal) or 0, 0, 5)
    CrateRoute.WaveState.EquipmentClicks = math.clamp(tonumber(saved.EquipmentClicks) or 0, 0, 5)
    CrateRoute.WaveState.MaxClicks = math.clamp(tonumber(saved.MaxClicks) or 0, 0, 2)
    CrateRoute.WaveState.RegenClicks = math.clamp(tonumber(saved.RegenClicks) or 0, 0, 2)
    CrateRoute.WaveState.RefillsClicks = math.clamp(tonumber(saved.RefillsClicks) or 0, 0, 1)
    CrateRoute.WaveState.RegenPlanned = math.clamp(tonumber(saved.RegenPlanned) or 0, 0, 2)
    CrateRoute.WaveState.RefillsPlanned = math.clamp(tonumber(saved.RefillsPlanned) or 0, 0, 1)
    CrateRoute.WaveState.Maxed = type(saved.Maxed) == "table" and saved.Maxed or {}
    CrateRoute.WaveState.MarketAttempts = type(saved.MarketAttempts) == "table" and saved.MarketAttempts or {}
  end
end)
function CrateRoute.SaveWaveState()
  pcall(writefile, "aotr/waves_purchases.json", HttpService:JSONEncode(CrateRoute.WaveState))
end
function CrateRoute.RefreshUpgradePending()
  local maxed = CrateRoute.WaveState.Maxed or {}
  CrateRoute.UpgradePending = (CrateRoute.RegenClicks < CrateRoute.RegenPlanned and not maxed.Regen)
    or (CrateRoute.MaxClicks < 2 and not maxed.Max)
    or (CrateRoute.RefillsClicks < CrateRoute.RefillsPlanned and not maxed.Refills)
end
function CrateRoute.ApplyWaveState()
  CrateRoute.EquipmentClicks = CrateRoute.WaveState.EquipmentClicks
  CrateRoute.MaxClicks = CrateRoute.WaveState.MaxClicks
  CrateRoute.RegenClicks = CrateRoute.WaveState.RegenClicks
  CrateRoute.RefillsClicks = CrateRoute.WaveState.RefillsClicks
  CrateRoute.RegenPlanned = CrateRoute.WaveState.RegenPlanned
  CrateRoute.RefillsPlanned = CrateRoute.WaveState.RefillsPlanned
  CrateRoute.EquipmentPending = CrateRoute.EquipmentClicks < 5
  CrateRoute.RefreshUpgradePending()
end
function CrateRoute.BeginWave(round: number?, crate: Instance)
  local wave = round and tostring(round) or "crate:" .. tostring(crate.Address)
  CrateRoute.RoundNumber = round
  if CrateRoute.WaveState.Wave ~= wave then
    CrateRoute.WaveState.Wave = wave
    CrateRoute.WaveState.EquipmentClicks = 0
    CrateRoute.WaveState.MaxClicks = 0
    CrateRoute.WaveState.RegenClicks = 0
    CrateRoute.WaveState.RefillsClicks = 0
    CrateRoute.WaveState.Maxed = {}
    CrateRoute.WaveState.RegenPlanned = math.min(2, 5 - CrateRoute.WaveState.RegenTotal)
    CrateRoute.WaveState.RefillsPlanned = round and round % 2 == 0 and 1 or 0
    CrateRoute.WaveState.MarketAttempts = {}
    CrateRoute.MarketPending = true
    PerkManager.Pending = true
    PerkManager.SurveyPending = true
    CrateRoute.SaveWaveState()
  end
  CrateRoute.ResumedWave = true
  CrateRoute.ApplyWaveState()
end
function CrateRoute.ReadRound(): number?
  local Hud = Interface:FindFirstChild("HUD")
  local Objectives = Hud and Hud:FindFirstChild("Objectives")
  local Main = Objectives and Objectives:FindFirstChild("Main")
  local Clearance = Main and Main:FindFirstChild("Clearance")
  local Cleared = Clearance and string.match(Clearance.Text or "", "Waves Cleared%s*%[(%d+)%s*/")
  return Cleared and tonumber(Cleared) + 1 or nil
end
function CrateRoute.ResumeSavedWave()
  if CrateRoute.ResumedWave then return end
  local current = CrateRoute.ReadRound()
  if not current then return end
  CrateRoute.ResumedWave = true
  if tostring(current) == CrateRoute.WaveState.Wave then
    CrateRoute.RoundNumber = current
    CrateRoute.ApplyWaveState()
    Boot("resumed wave " .. current .. " upgrade receipt")
  end
end
function CrateRoute.GetOwned(): Instance?
  if not UserConfigs.AutoCrates then return nil end
  local now = os.clock()
  if now < CrateRoute.NextCheck and CrateRoute.Cached and CrateRoute.Cached.Parent then return CrateRoute.Cached end
  if now < CrateRoute.NextCheck then return nil end
  CrateRoute.NextCheck = now + 0.5
  local Waves = Workspace:FindFirstChild("Waves")
  local Crates = Waves and Waves:FindFirstChild("Crates")
  CrateRoute.Cached = Crates and Crates:FindFirstChild("Crate_" .. LocalPlayer.Name) or nil
  return CrateRoute.Cached
end

function CrateRoute.Pending(): boolean
  if Qte.Active then return false end
  local Crate = CrateRoute.GetOwned()
  return Crate ~= nil and (Crate.Address ~= CrateRoute.LastAttemptAddress or os.clock() - CrateRoute.LastAttemptAt > 5)
end

function CrateRoute.Handle(): boolean
  if not CrateRoute.Pending() then return false end
  local Crate = CrateRoute.GetOwned(); if not Crate then return false end
  local Hitbox = Crate:FindFirstChild("Hitbox"); if not Hitbox or not Hitbox:IsA("BasePart") then return false end
  local Waves = Workspace:FindFirstChild("Waves")
  local Props = Waves and Waves:FindFirstChild("Props")
  local Dropoff = Props and Props:FindFirstChild("Dropoff")
  local Cart = Dropoff and Dropoff:FindFirstChild("Cart")
  if not Cart or not Cart:IsA("BasePart") then return false end
  local Hrp = GetPlayerHrp(LocalPlayer); if not Hrp then return false end

  CrateRoute.LastAttemptAddress = Crate.Address
  CrateRoute.LastAttemptAt = os.clock()
  CurrentTitanTarget = nil
  FarmStats.Target = "crate"
  WhatShouldIBeDoing = "crate"
  FarmStats.Status = "collecting crate"
  local ok, err = pcall(function()
    local at = Hitbox.Position
    Hrp.AssemblyLinearVelocity = Vector3Zero
    -- Fall through the touch volume so the TouchInterest sees physical contact.
    Hrp.CFrame = CFrame.new(at.X, at.Y + Hitbox.Size.Y / 2 + 4, at.Z)
    Hrp.AssemblyLinearVelocity = Vector3Zero
  end)
  if not ok then Boot("crate pickup move failed: " .. tostring(err)) end
  if ok then
    Boot("crate pickup touch attempted")
    task.wait(0.65)
    if not Stopped() and UserConfigs.AutoCrates and IsLocalAlive() then
      FarmStats.Status = "delivering crate"
      local delivered, dropErr = pcall(function()
        local at = Cart.Position
        Hrp.AssemblyLinearVelocity = Vector3Zero
        Hrp.CFrame = CFrame.new(at.X, at.Y + Cart.Size.Y / 2 + 4, at.Z)
        Hrp.AssemblyLinearVelocity = Vector3Zero
      end)
      if not delivered then Boot("crate dropoff move failed: " .. tostring(dropErr))
      else Boot("crate dropoff touch attempted") end
      task.wait(0.65)
      Boot("crate after dropoff: " .. (Crate.Parent and "still present" or "removed"))
      if not Crate.Parent then
        CrateRoute.BeginWave(CrateRoute.ReadRound(), Crate)
        Boot("crate delivered on wave " .. tostring(CrateRoute.RoundNumber or "unknown"))
      end
    end
  end
  if not Stopped() then WhatShouldIBeDoing = "attack" end
  return true
end

function CrateRoute.EquipmentRootOpen(): boolean
  local Equipment = Interface:FindFirstChild("Equipment")
  local Categories = Equipment and Equipment:FindFirstChild("Categories")
  local Upgrades = Categories and Categories:FindFirstChild("Equipment_Upgrades")
  local Inner = Upgrades and Upgrades:FindFirstChild("Inner")
  local Button = Inner and Inner:FindFirstChild("Interact")
  local Viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
  local Position = Button and Button.AbsolutePosition
  return Position ~= nil and Viewport ~= nil and Position.Y > Viewport.Y * 0.03 and Position.Y < Viewport.Y * 0.3
end

function CrateRoute.EquipmentMenuOpen(): boolean
  local Equipment = Interface:FindFirstChild("Equipment")
  local Stats = Equipment and Equipment:FindFirstChild("Stats")
  local All = Stats and Stats:FindFirstChild("All")
  local Position = All and All.AbsolutePosition
  local Camera = Workspace.CurrentCamera
  local Viewport = Camera and Camera.ViewportSize
  return Position ~= nil and Viewport ~= nil and Position.X > Viewport.X * 0.02
end

function CrateRoute.ClickButton(Button: Instance, fallbackX: number, fallbackY: number)
  local Position = Button.AbsolutePosition
  local Size = Button.AbsoluteSize
  local Viewport = Workspace.CurrentCamera.ViewportSize
  local x = Position.X + (Size and Size.X > 1 and Size.X / 2 or Viewport.X * fallbackX)
  local y = Position.Y + (Size and Size.Y > 1 and Size.Y / 2 or Viewport.Y * fallbackY)
  mousemoveabs(math.floor(x), math.floor(y))
  mousemoverel(1, 0) -- Matcha's absolute move alone does not trigger this game's GUI hover.
  task.wait(0.18)
  mouse1click()
end

-- The raid ends at Interface.Chests before the usual Rewards screen. Matcha reads these
-- buttons' AbsolutePosition but reports zero AbsoluteSize, so the hover samples supply
-- viewport-scaled click offsets. The free button disappears once its chest opens.
CrateRoute.RaidChestOpenedAt = nil
CrateRoute.RaidKeyChestDone = false
function CrateRoute.HandleRaidChest(): boolean
  local chests = Interface:FindFirstChild("Chests")
  if not chests or not IsObjectVisible(chests) then
    if WhatShouldIBeDoing == "chest" then WhatShouldIBeDoing = "attack" end
    CrateRoute.RaidChestOpenedAt = nil
    CrateRoute.RaidKeyChestDone = false
    return false
  end
  if not UserConfigs.AutoRaidChest then return false end
  CurrentTitanTarget = nil
  WhatShouldIBeDoing = "chest"
  FarmStats.Status = "opening raid chest"
  if not isrbxactive() then task.wait(0.3); return true end
  local free = chests:FindFirstChild("Free")
  if free and IsObjectVisible(free) then
    CrateRoute.ClickButton(free, 0.044, 0.018)
    task.wait(0.6)
    if not IsObjectVisible(free) then
      CrateRoute.RaidChestOpenedAt = os.clock()
      Boot("free raid chest opened")
    end
    return true
  end
  CrateRoute.RaidChestOpenedAt = CrateRoute.RaidChestOpenedAt or os.clock()
  if os.clock() - CrateRoute.RaidChestOpenedAt < 1.5 then task.wait(0.2); return true end
  if UserConfigs.OpenKeyChest and not CrateRoute.RaidKeyChestDone then
    CrateRoute.RaidKeyChestDone = true -- one click at most, so this route cannot spend two keys
    local premium = chests:FindFirstChild("Premium")
    local title = premium and premium:FindFirstChild("Title")
    local label = title and title.Text or ""
    local countText = string.match(label, "%(([%d,]+)%)")
    local keys = countText and tonumber((string.gsub(countText, ",", ""))) or nil
    if keys == 0 then
      Boot("key chest skipped: no keys shown")
    elseif premium and IsObjectVisible(premium) then
      FarmStats.Status = "opening key chest"
      CrateRoute.ClickButton(premium, 0.044, 0.018)
      task.wait(0.6)
      CrateRoute.RaidChestOpenedAt = os.clock() -- let the key chest reveal finish before clicking Finish
      local after = premium:FindFirstChild("Title")
      local afterText = after and after.Text or ""
      local afterCount = string.match(afterText, "%(([%d,]+)%)")
      local remaining = afterCount and tonumber((string.gsub(afterCount, ",", ""))) or nil
      Boot((not IsObjectVisible(premium) or (keys and remaining and remaining < keys))
        and "key chest opened" or "key chest click unconfirmed")
    end
    return true
  end
  local finish = chests:FindFirstChild("Finish")
  if finish and IsObjectVisible(finish) then
    FarmStats.Status = "finishing raid chest"
    CrateRoute.ClickButton(finish, 0.067, 0.017)
    task.wait(0.6)
    if not IsObjectVisible(chests) then Boot("raid chest finished; rewards screen opened") end
  end
  return true
end

function CrateRoute.ReadGold(menu: Instance): number?
  local gold = menu:FindFirstChild("Gold")
  local title = gold and gold:FindFirstChild("Title")
  if not title then return nil end
  return tonumber(((title.Text or ""):gsub("[^%d]", "")))
end

function CrateRoute.BuyPrice(button: Instance): number?
  local title = button:FindFirstChild("Title")
  local text = title and title.Text or ""
  if not string.match(text, "^BUY") then return nil end
  local price = string.match(text, "%(([%d,]+)%)")
  return price and tonumber(((price:gsub(",", "")))) or nil
end

function CrateRoute.SpentGold(menu: Instance, before: number, description: Instance?, oldDescription: string?): boolean
  for _ = 1, 10 do
    task.wait(0.15)
    local now = CrateRoute.ReadGold(menu)
    if now and now < before then return true end
    if description and oldDescription and description.Text ~= oldDescription then return true end
  end
  return false
end

function CrateRoute.HandleEquipment(): boolean
  if not UserConfigs.AutoEquipmentUpgrades or not CrateRoute.EquipmentPending then return false end
  if UserConfigs.AutoStationUpgrades and CrateRoute.RegenClicks < CrateRoute.RegenPlanned
    and not (CrateRoute.WaveState.Maxed or {}).Regen then return false end
  if Qte.Active or not isrbxactive() or os.clock() < CrateRoute.NextEquipmentAttempt then return false end
  local Waves = Workspace:FindFirstChild("Waves")
  local NPCs = Waves and Waves:FindFirstChild("NPCs")
  local Lulu = NPCs and NPCs:FindFirstChild("Lulu")
  local NpcHrp = Lulu and Lulu:FindFirstChild("HumanoidRootPart")
  local Hrp = GetPlayerHrp(LocalPlayer)
  local Equipment = Interface:FindFirstChild("Equipment")
  local Stats = Equipment and Equipment:FindFirstChild("Stats")
  local All = Stats and Stats:FindFirstChild("All")
  local Categories = Equipment and Equipment:FindFirstChild("Categories")
  local Upgrades = Categories and Categories:FindFirstChild("Equipment_Upgrades")
  local Inner = Upgrades and Upgrades:FindFirstChild("Inner")
  local UpgradesTab = Inner and Inner:FindFirstChild("Interact")
  local CloseFrame = Equipment and Equipment:FindFirstChild("Equipment_Close")
  local Close = CloseFrame and CloseFrame:FindFirstChild("Interact")
  if not NpcHrp or not Hrp or not All or not UpgradesTab or not Close then return false end

  CurrentTitanTarget = nil
  FarmStats.Target = "equipment"
  FarmStats.Status = "opening equipment"
  WhatShouldIBeDoing = "equipment"
  CrateRoute.NextEquipmentAttempt = os.clock() + 5
  if not CrateRoute.EquipmentRootOpen() then
    local at = NpcHrp.Position
    Hrp.AssemblyLinearVelocity = Vector3Zero
    Hrp.CFrame = CFrame.new(at.X + 4, at.Y, at.Z - 2)
    Hrp.AssemblyLinearVelocity = Vector3Zero
    task.wait(0.45)
    for _ = 1, 12 do
      if Stopped() or not UserConfigs.AutoCrates or not isrbxactive() or not IsLocalAlive() then break end
      if CrateRoute.EquipmentRootOpen() then break end
      keypress(0x45)
      task.wait(0.15)
      keyrelease(0x45)
      task.wait(0.4)
    end
  end

  if CrateRoute.EquipmentRootOpen() and not CrateRoute.EquipmentMenuOpen() and isrbxactive() then
    task.wait(0.55)
    for _ = 1, 3 do
      if Stopped() or not CrateRoute.EquipmentRootOpen() or CrateRoute.EquipmentMenuOpen() then break end
      CrateRoute.ClickButton(UpgradesTab, 0.025, 0.04)
      task.wait(0.45)
    end
  end

  if CrateRoute.EquipmentMenuOpen() and not Stopped() then
    FarmStats.Status = "buying equipment upgrades"
    while CrateRoute.EquipmentClicks < 5 and not Stopped() and UserConfigs.AutoCrates and isrbxactive() and CrateRoute.EquipmentMenuOpen() do
      local beforeGold = CrateRoute.ReadGold(Equipment)
      if not beforeGold or beforeGold <= 0 then
        Boot("equipment Upgrade All deferred: no gold available")
        CrateRoute.NextEquipmentAttempt = os.clock() + 15
        break
      end
      CrateRoute.ClickButton(All, 0.063, 0.019)
      if not CrateRoute.SpentGold(Equipment, beforeGold) then
        Boot("equipment Upgrade All did not spend gold; count stays " .. CrateRoute.EquipmentClicks .. "/5")
        CrateRoute.NextEquipmentAttempt = os.clock() + 15
        break
      end
      CrateRoute.EquipmentClicks += 1
      CrateRoute.WaveState.EquipmentClicks = CrateRoute.EquipmentClicks
      CrateRoute.SaveWaveState()
      Boot("equipment Upgrade All purchased " .. CrateRoute.EquipmentClicks .. "/5")
      task.wait(0.55)
    end
    if isrbxactive() then
      FarmStats.Status = "closing equipment"
      for attempt = 1, 3 do
        if Stopped() or not CrateRoute.EquipmentMenuOpen() then break end
        CrateRoute.ClickButton(Close, 0.012, 0.021)
        task.wait(0.45)
      end
      if not CrateRoute.EquipmentMenuOpen() then
        if CrateRoute.EquipmentClicks == 5 then
          CrateRoute.EquipmentPending = false
          Boot("equipment upgrades finished; menu closed")
        end
      else
        Boot("equipment X click did not close menu")
      end
    end
  else
    Boot("equipment menu did not open")
  end
  if not Stopped() then WhatShouldIBeDoing = "attack" end
  return true
end

function CrateRoute.UpgradeMenuOpen(): boolean
  local Upgrade = Interface:FindFirstChild("Upgrade")
  local Main = Upgrade and Upgrade:FindFirstChild("Main")
  local Upgrades = Main and Main:FindFirstChild("Upgrades")
  local Max = Upgrades and Upgrades:FindFirstChild("Max")
  local Buy = Max and Max:FindFirstChild("Max_Use")
  local Position = Buy and Buy.AbsolutePosition
  local Camera = Workspace.CurrentCamera
  local Viewport = Camera and Camera.ViewportSize
  return Position ~= nil and Viewport ~= nil and Position.Y < Viewport.Y * 0.78
end

function CrateRoute.HandleUpgrade(): boolean
  if not UserConfigs.AutoStationUpgrades or not CrateRoute.UpgradePending then return false end
  if Qte.Active or not isrbxactive() or os.clock() < CrateRoute.NextUpgradeAttempt then return false end
  local Waves = Workspace:FindFirstChild("Waves")
  local NPCs = Waves and Waves:FindFirstChild("NPCs")
  local Cole = NPCs and NPCs:FindFirstChild("Cole")
  local NpcHrp = Cole and Cole:FindFirstChild("HumanoidRootPart")
  local Hrp = GetPlayerHrp(LocalPlayer)
  local Upgrade = Interface:FindFirstChild("Upgrade")
  local Main = Upgrade and Upgrade:FindFirstChild("Main")
  local Upgrades = Main and Main:FindFirstChild("Upgrades")
  local Max = Upgrades and Upgrades:FindFirstChild("Max")
  local Regen = Upgrades and Upgrades:FindFirstChild("Regen")
  local Refills = Upgrades and Upgrades:FindFirstChild("Refills")
  local MaxBuy = Max and Max:FindFirstChild("Max_Use")
  local RegenBuy = Regen and Regen:FindFirstChild("Regen_Use")
  local RefillsBuy = Refills and Refills:FindFirstChild("Refills_Use")
  local CloseFrame = Upgrade and Upgrade:FindFirstChild("Upgrade_Close")
  local Close = CloseFrame and CloseFrame:FindFirstChild("Interact")
  if not NpcHrp or not Hrp or not MaxBuy or not RegenBuy or not RefillsBuy or not Close then return false end

  CurrentTitanTarget = nil
  FarmStats.Target = "HQ upgrades"
  FarmStats.Status = "opening HQ upgrades"
  WhatShouldIBeDoing = "upgrade"
  CrateRoute.NextUpgradeAttempt = os.clock() + 5
  if not CrateRoute.UpgradeMenuOpen() then
    local at = NpcHrp.Position
    Hrp.AssemblyLinearVelocity = Vector3Zero
    Hrp.CFrame = CFrame.new(at.X + 4, at.Y, at.Z - 2)
    Hrp.AssemblyLinearVelocity = Vector3Zero
    task.wait(0.45)
    for _ = 1, 12 do
      if Stopped() or not UserConfigs.AutoCrates or not isrbxactive() or not IsLocalAlive() then break end
      if CrateRoute.UpgradeMenuOpen() then break end
      keypress(0x45)
      task.wait(0.15)
      keyrelease(0x45)
      task.wait(0.4)
    end
  end

  if CrateRoute.UpgradeMenuOpen() and not Stopped() then
    FarmStats.Status = "buying HQ upgrades"
    while CrateRoute.UpgradePending do
      if Stopped() or not UserConfigs.AutoCrates or not isrbxactive() or not CrateRoute.UpgradeMenuOpen() then break end
      local maxed = CrateRoute.WaveState.Maxed or {}
      local kind, group, button
      if CrateRoute.RegenClicks < CrateRoute.RegenPlanned and not maxed.Regen then
        kind, group, button = "Regen", Regen, RegenBuy
      elseif CrateRoute.MaxClicks < 2 and not maxed.Max then
        kind, group, button = "Max", Max, MaxBuy
      elseif CrateRoute.RefillsClicks < CrateRoute.RefillsPlanned and not maxed.Refills then
        kind, group, button = "Refills", Refills, RefillsBuy
      else
        CrateRoute.RefreshUpgradePending()
        break
      end
      local description = group:FindFirstChild("Description")
      local beforeDescription = description and description.Text
      local beforeGold = CrateRoute.ReadGold(Upgrade)
      local price = CrateRoute.BuyPrice(button)
      if not price then
        local label = button:FindFirstChild("Title")
        if label and string.match(label.Text or "", "^MAX") then
          CrateRoute.WaveState.Maxed[kind] = true
          CrateRoute.SaveWaveState()
          CrateRoute.RefreshUpgradePending()
          Boot("HQ " .. kind .. " already maxed")
        else
          Boot("HQ " .. kind .. " price unavailable; retry later")
          CrateRoute.NextUpgradeAttempt = os.clock() + 15
          break
        end
      elseif not beforeGold or beforeGold < price then
        Boot("HQ " .. kind .. " deferred: " .. tostring(beforeGold) .. " gold < " .. price)
        CrateRoute.NextUpgradeAttempt = os.clock() + 15
        break
      else
        CrateRoute.ClickButton(button, 0.043, 0.016)
        if not CrateRoute.SpentGold(Upgrade, beforeGold, description, beforeDescription) then
          Boot("HQ " .. kind .. " did not spend gold; count unchanged")
          CrateRoute.NextUpgradeAttempt = os.clock() + 15
          break
        end
        if kind == "Regen" then
          CrateRoute.RegenClicks += 1
          CrateRoute.WaveState.RegenClicks = CrateRoute.RegenClicks
          CrateRoute.WaveState.RegenTotal = math.min(5, CrateRoute.WaveState.RegenTotal + 1)
        elseif kind == "Max" then
          CrateRoute.MaxClicks += 1
          CrateRoute.WaveState.MaxClicks = CrateRoute.MaxClicks
        else
          CrateRoute.RefillsClicks += 1
          CrateRoute.WaveState.RefillsClicks = CrateRoute.RefillsClicks
        end
        CrateRoute.SaveWaveState()
        CrateRoute.RefreshUpgradePending()
        Boot("HQ " .. kind .. " purchased; gold " .. beforeGold .. " -> " .. tostring(CrateRoute.ReadGold(Upgrade)))
      end
      task.wait(0.55)
    end
    if isrbxactive() then
      FarmStats.Status = "closing HQ upgrades"
      for _ = 1, 3 do
        if Stopped() or not CrateRoute.UpgradeMenuOpen() then break end
        CrateRoute.ClickButton(Close, 0.012, 0.021)
        task.wait(0.45)
      end
      if not CrateRoute.UpgradeMenuOpen() then
        if not CrateRoute.UpgradePending then Boot("HQ upgrades finished; menu closed") end
      else
        Boot("HQ upgrade X click did not close menu")
      end
    end
  else
    Boot("HQ upgrade menu did not open")
  end
  if not Stopped() then WhatShouldIBeDoing = "attack" end
  return true
end


-- Perk names and rarities from the AoTR Perks wiki, read 2026-11-04. The GUI cards
-- carry the perk name but not a useful rarity label, so keep this catalog local.
local UI
PerkManager = { Pending = true, SurveyPending = true, Owned = nil, NextCheck = 0 }
PerkManager.Tiers = {
  [1] = "ENHANCED METABOLISM|ENDURING|FORTITUDE|CRIPPLE|HOLLOW|LUCKY|MIGHTY|FIRST AID|GEAR BEGINNER",
  [2] = "CRITICAL HUNTER|HEIGHTENED VITALITY|PROTECTION|TOUGH|UNYIELDING|BLESSED|FORCEFUL|LIGHTWEIGHT|MANGLE|EXPERIMENTAL SHELLS|FULLY STOCKED|GEAR INTERMEDIATE",
  [3] = "RESILIENT|SOLO|HARDY|SAFEGUARD|STALWART DURABILITY|UNBREAKABLE|BUTCHER|FLAWED RELEASE|FOCUS|LUMINOUS|MUTILATE|PEERLESS STRENGTH|RECKLESS ABANDON|SPEEDY|WARRIOR|ADRENALINE|GEAR EXPERT|MUNITIONS EXPERT|SIPHONING|TRAUMA BATTERY",
  [4] = "FLAME RHAPSODY|INDEFATIGABLE|PERFECT FORM|PERFECT SOUL|TYRANT'S STARE|WIND RHAPSODY|AEGIS|FONT OF VITALITY|INVINCIBLE|PEERLESS CONSTITUTION|ROBUST|BOMBARDIER|CARNIFEX|EVISCERATE|PEERLESS FOCUS|SANCTIFIED|UNPARALLELED STRENGTH|WARCHIEF|COURAGE CATALYST|EXHUMATION|GEAR MASTER|MUNITIONS MASTER|PEERLESS COMMANDER|SIXTH SENSE",
  [5] = "FOUNDER'S BLESSING|HEAVENLY RESTRICTION|MAXIMUM FIREPOWER|ADAPTATION|IMMORTAL|ART OF WAR|BLACK FLASH|BLITZKREIG|EVERLASTING FLAME|KENGO|EXPLOSIVE FORTUNE|FONT OF INSPIRATION|SOULFEED|TATSUJIN|UNWAVERING BELIEF",
  [6] = "AVATAR OF YMIR|MANKIND’S STRONGEST|SANGUINE DESTROYER|ETERNAL|FORESIGHT|GODFORGED|STORMWRATH|15TH COMMANDER|BRANCHING PATHS|WINGS OF FREEDOM",
}
PerkManager.Rarity, PerkManager.Names = {}, {}
for tier, names in ipairs(PerkManager.Tiers) do
  for name in string.gmatch(names, "[^|]+") do
    PerkManager.Rarity[name:gsub("’", "'")] = tier
    table.insert(PerkManager.Names, name)
  end
end
table.sort(PerkManager.Names)

function PerkManager.Key(name: string): string
  return string.upper((name or ""):gsub("’", "'"):gsub("^%s+", ""):gsub("%s+$", ""))
end

function PerkManager.SearchOptions(query: string, selected: string)
  local options, seen = { "None" }, { None = true }
  if selected ~= "" then table.insert(options, selected); seen[selected] = true end
  local needle = PerkManager.Key(query)
  for _, name in ipairs(PerkManager.Names) do
    if #options >= 8 then break end
    if not seen[name] and (needle == "" or string.find(PerkManager.Key(name), needle, 1, true)) then
      table.insert(options, name)
      seen[name] = true
    end
  end
  return options
end

function PerkManager.MenuOpen(): boolean
  local Equipment = Interface:FindFirstChild("Equipment")
  local Categories = Equipment and Equipment:FindFirstChild("Categories")
  local Perks = Categories and Categories:FindFirstChild("Equipment_Perks")
  local Inner = Perks and Perks:FindFirstChild("Inner")
  local Button = Inner and Inner:FindFirstChild("Interact")
  local Viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
  local p = Button and Button.AbsolutePosition
  return p ~= nil and Viewport ~= nil and p.Y > Viewport.Y * 0.03 and p.Y < Viewport.Y * 0.3
end

function PerkManager.Scan()
  local Equipment = Interface:FindFirstChild("Equipment")
  local Items = Equipment and Equipment:FindFirstChild("Items")
  local Main = Items and Items:FindFirstChild("Main")
  local Using = Main and Main:FindFirstChild("Using")
  local Storage = Main and Main:FindFirstChild("Storage")
  local Capacity = Items and Items:FindFirstChild("Capacity")
  if not Using or not Storage or not Capacity then return nil end
  local used, limit = string.match(Capacity.Text or "", "(%d+)%s*/%s*(%d+)")
  if not used or not limit then return nil end
  local cards = {}
  for _, group in ipairs({ Using, Storage }) do
    for _, card in ipairs(group:GetChildren()) do
      local name = string.match(card.Name, "^%d+%s*%-%s*(.+)$")
      local main = name and card:FindFirstChild("Main")
      local button = main and main:FindFirstChild("Interact")
      if button then
        table.insert(cards, { Name = name, Key = PerkManager.Key(name),
          Card = card, Button = button, Equipped = group == Using })
      end
    end
  end
  return cards, tonumber(used), tonumber(limit)
end

function PerkManager.Rank(card)
  for index, name in ipairs(UserConfigs.PriorityPerks) do
    if PerkManager.Key(name) == card.Key then return 100 + (7 - index) end
  end
  -- Unknown new perks are retained if equipped, but are not equipped over a known rarity.
  return PerkManager.Rarity[card.Key] or (card.Equipped and 7 or -1)
end

function PerkManager.CloseInfo()
  local viewport = Workspace.CurrentCamera.ViewportSize
  mousemoveabs(math.floor(viewport.X * 0.78), math.floor(viewport.Y * 0.55))
  mousemoverel(1, 0)
  task.wait(0.2)
  mouse1click()
  task.wait(0.3)
end

function PerkManager.Change(card, equip: boolean): boolean
  local desired = equip and "EQUIP" or "UNEQUIP"
  local Equipment = Interface:FindFirstChild("Equipment")
  local Info = Interface:FindFirstChild("Info")
  local Prompt = Info and Info:FindFirstChild("Prompt")
  local Main = Prompt and Prompt:FindFirstChild("Main")
  local Buttons = Main and Main:FindFirstChild("Buttons")
  local Change = Buttons and Buttons:FindFirstChild("Change")
  local Label = Change and Change:FindFirstChild("Title")
  local Title = Main and Main:FindFirstChild("Title")
  if not Equipment or not Change or not Label or not Title then return false end

  for attempt = 1, 2 do
    if Stopped() or not isrbxactive() or not PerkManager.MenuOpen() then return false end
    local before = PerkManager.Scan()
    if before then
      for _, current in ipairs(before) do
        if current.Key == card.Key and current.Equipped == equip then return true end
      end
    end
    PerkManager.CloseInfo()
    CrateRoute.ClickButton(card.Button, 0.016, 0.026)
    task.wait(0.45)
    if PerkManager.Key(Title.Text) ~= card.Key or Label.Text ~= desired then
      Boot("perk prompt mismatch for " .. card.Name .. ": " .. tostring(Title.Text) .. " / " .. tostring(Label.Text))
      continue
    end
    CrateRoute.ClickButton(Change, 0.035, 0.018)
    for _ = 1, 6 do
      task.wait(0.25)
      local cards = PerkManager.Scan()
      if cards then
        for _, current in ipairs(cards) do
          if current.Key == card.Key and current.Equipped == equip then
            PerkManager.CloseInfo()
            Boot("perk " .. desired:lower() .. " confirmed: " .. card.Name)
            return true
          end
        end
      end
    end
  end
  Boot("perk " .. desired:lower() .. " failed: " .. card.Name)
  return false
end

function PerkManager.Handle(): boolean
  if not UserConfigs.AutoPerks then return false end
  if not UserConfigs.MenuDisabled and (not UI or not UI.ready) then return false end
  if UserConfigs.AutoMarket and CrateRoute.MarketPending and not PerkManager.SurveyPending then return false end
  if not PerkManager.Pending and os.clock() < PerkManager.NextCheck then return false end
  if Qte.Active or not isrbxactive() or not IsLocalAlive() then return false end
  local Equipment = Interface:FindFirstChild("Equipment")
  local Categories = Equipment and Equipment:FindFirstChild("Categories")
  local Category = Categories and Categories:FindFirstChild("Equipment_Perks")
  local Inner = Category and Category:FindFirstChild("Inner")
  local TabButton = Inner and Inner:FindFirstChild("Interact")
  local UpgradesCategory = Categories and Categories:FindFirstChild("Equipment_Upgrades")
  local UpgradesInner = UpgradesCategory and UpgradesCategory:FindFirstChild("Inner")
  local UpgradesTab = UpgradesInner and UpgradesInner:FindFirstChild("Interact")
  local CloseFrame = Equipment and Equipment:FindFirstChild("Equipment_Close")
  local Close = CloseFrame and CloseFrame:FindFirstChild("Interact")
  local Waves = Workspace:FindFirstChild("Waves")
  local NPCs = Waves and Waves:FindFirstChild("NPCs")
  local Lulu = NPCs and NPCs:FindFirstChild("Lulu")
  local NpcHrp = Lulu and Lulu:FindFirstChild("HumanoidRootPart")
  local Hrp = GetPlayerHrp(LocalPlayer)
  if not TabButton or not UpgradesTab or not Close or not NpcHrp or not Hrp then return false end

  PerkManager.Pending, PerkManager.NextCheck = false, os.clock() + 120
  CurrentTitanTarget = nil
  FarmStats.Target, FarmStats.Status = "perks", "opening perks"
  WhatShouldIBeDoing = "perks"
  local wasVisible = UI and UI.window and UI.window.Visible
  if wasVisible then
    pcall(function() UI.window:Hide() end)
    task.wait(0.12) -- let the Drawing window disappear before pressing central game buttons
  end
  if not PerkManager.MenuOpen() then
    local at = NpcHrp.Position
    Hrp.AssemblyLinearVelocity = Vector3Zero
    Hrp.CFrame = CFrame.new(at.X + 4, at.Y, at.Z - 2)
    Hrp.AssemblyLinearVelocity = Vector3Zero
    task.wait(0.45)
    for _ = 1, 12 do
      if Stopped() or not UserConfigs.AutoPerks or not isrbxactive() or not IsLocalAlive() then break end
      if PerkManager.MenuOpen() then break end
      keypress(0x45)
      task.wait(0.15)
      keyrelease(0x45)
      task.wait(0.4)
    end
  end
  if PerkManager.MenuOpen() and not Stopped() and isrbxactive() then
    task.wait(0.55) -- finish the Equipment slide-in before switching pages
    if CrateRoute.EquipmentMenuOpen() then
      CrateRoute.ClickButton(TabButton, 0.025, 0.04)
      task.wait(0.45)
    end
    for _ = 1, 8 do
      if Stopped() or not UserConfigs.AutoPerks or not isrbxactive() or not PerkManager.MenuOpen() then break end
      local cards, used, limit = PerkManager.Scan()
      if not cards or not limit or limit < 1 then break end
      table.sort(cards, function(a, b)
        local ar, br = PerkManager.Rank(a), PerkManager.Rank(b)
        if ar ~= br then return ar > br end
        if a.Equipped ~= b.Equipped then return a.Equipped end
        return a.Key < b.Key
      end)
      local wanted = {}
      for index = 1, math.min(limit, #cards) do wanted[cards[index].Key] = true end
      local candidate, victim = nil, nil
      for _, card in ipairs(cards) do
        if not card.Equipped and wanted[card.Key] then candidate = card; break end
      end
      if not candidate then break end
      if used >= limit then
        for index = #cards, 1, -1 do
          local card = cards[index]
          if card.Equipped and not wanted[card.Key] then victim = card; break end
        end
        if not victim or not PerkManager.Change(victim, false) then break end
      end
      if not PerkManager.Change(candidate, true) then break end
    end
    local ownedCards = PerkManager.Scan()
    if ownedCards then
      PerkManager.Owned = {}
      for _, card in ipairs(ownedCards) do PerkManager.Owned[card.Key] = true end
      PerkManager.SurveyPending = false
    else
      PerkManager.Pending, PerkManager.NextCheck = true, os.clock() + 5
      Boot("perk inventory scan failed")
    end
    PerkManager.CloseInfo()
    if PerkManager.MenuOpen() and isrbxactive() then
      CrateRoute.ClickButton(UpgradesTab, 0.025, 0.04)
      task.wait(0.45)
      if not CrateRoute.EquipmentMenuOpen() then Boot("perk manager could not restore Upgrades tab") end
    end
    for _ = 1, 3 do
      if not PerkManager.MenuOpen() or not isrbxactive() then break end
      CrateRoute.ClickButton(Close, 0.012, 0.021)
      task.wait(0.45)
    end
    Boot("perk manager finished; menu " .. (PerkManager.MenuOpen() and "still open" or "closed"))
  else
    PerkManager.Pending, PerkManager.NextCheck = true, os.clock() + 5
    Boot("perk menu did not open")
  end
  if wasVisible and UI.window and not Stopped() then pcall(function() UI.window:Show() end) end
  if not Stopped() then WhatShouldIBeDoing = "attack" end
  return true
end

-- Orange's Market rotates every wave. Buying a perk is immediate: the Buy button is
-- the purchase itself, so only click a listing after name, stock, gold and ownership checks.
CrateRoute.MarketManager = { NextAttempt = 0 }
function CrateRoute.MarketManager.MenuOpen(): boolean
  local Market = Interface:FindFirstChild("Market")
  local Categories = Market and Market:FindFirstChild("Categories")
  local Perks = Categories and Categories:FindFirstChild("Market_Perks")
  local Inner = Perks and Perks:FindFirstChild("Inner")
  local Button = Inner and Inner:FindFirstChild("Interact")
  local Viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
  local p = Button and Button.AbsolutePosition
  return p ~= nil and Viewport ~= nil and p.Y > Viewport.Y * 0.03 and p.Y < Viewport.Y * 0.3
end

function CrateRoute.MarketManager.Scan()
  local Market = Interface:FindFirstChild("Market")
  local Main = Market and Market:FindFirstChild("Main")
  local Items = Main and Main:FindFirstChild("Items")
  local Gold = Market and Market:FindFirstChild("Gold")
  local GoldTitle = Gold and Gold:FindFirstChild("Title")
  if not Items or not GoldTitle then return nil end
  local amount = tonumber(((GoldTitle.Text or ""):gsub("[^%d]", ""))) or 0
  local listings, onPerksPage = {}, false
  for _, card in ipairs(Items:GetChildren()) do
    local Inner = card:FindFirstChild("Inner")
    local Item = Inner and Inner:FindFirstChild("Item")
    local Stock = Inner and Inner:FindFirstChild("Stock")
    local Amount = Stock and Stock:FindFirstChild("Amount")
    local Buy = Inner and Inner:FindFirstChild("Buy")
    local Price = Buy and Buy:FindFirstChild("Title")
    local name = Item and Item.Text
    if type(name) == "string" then
      local key = PerkManager.Key(name)
      if key == "PERK CRATE" or PerkManager.Rarity[key] then onPerksPage = true end
      if PerkManager.Rarity[key] and Amount and Buy and Price then
        table.insert(listings, { Name = name, Key = key, Card = card, Buy = Buy,
          Stock = Amount, Price = tonumber(((Price.Text or ""):gsub("[^%d]", ""))) or math.huge,
          Count = tonumber(string.match(Amount.Text or "", "^(%d+)")) or 0 })
      end
    end
  end
  return listings, amount, onPerksPage
end

function CrateRoute.MarketManager.Handle(): boolean
  if not UserConfigs.AutoMarket or not UserConfigs.AutoPerks or not CrateRoute.MarketPending then return false end
  if PerkManager.SurveyPending or not PerkManager.Owned then return false end
  if not UserConfigs.MenuDisabled and (not UI or not UI.ready) then return false end
  if Qte.Active or not isrbxactive() or not IsLocalAlive() or os.clock() < CrateRoute.MarketManager.NextAttempt then return false end

  local Waves = Workspace:FindFirstChild("Waves")
  local NPCs = Waves and Waves:FindFirstChild("NPCs")
  local Orange = NPCs and NPCs:FindFirstChild("Orange")
  local NpcHrp = Orange and Orange:FindFirstChild("HumanoidRootPart")
  local Hrp = GetPlayerHrp(LocalPlayer)
  local Market = Interface:FindFirstChild("Market")
  local Categories = Market and Market:FindFirstChild("Categories")
  local Perks = Categories and Categories:FindFirstChild("Market_Perks")
  local Inner = Perks and Perks:FindFirstChild("Inner")
  local TabButton = Inner and Inner:FindFirstChild("Interact")
  local CloseFrame = Market and Market:FindFirstChild("Market_Close")
  local Close = CloseFrame and CloseFrame:FindFirstChild("Interact")
  if not NpcHrp then
    CrateRoute.MarketPending = false -- this station is a Waves feature
    return false
  end
  if not Hrp or not TabButton or not Close then return false end

  CrateRoute.MarketManager.NextAttempt = os.clock() + 5
  CurrentTitanTarget = nil
  FarmStats.Target, FarmStats.Status = "market", "checking market"
  WhatShouldIBeDoing = "market"
  local wasVisible = UI and UI.window and UI.window.Visible
  if wasVisible then
    pcall(function() UI.window:Hide() end)
    task.wait(0.12)
  end
  if not CrateRoute.MarketManager.MenuOpen() then
    local at = NpcHrp.Position
    Hrp.AssemblyLinearVelocity = Vector3Zero
    Hrp.CFrame = CFrame.new(at.X + 4, at.Y, at.Z - 2)
    Hrp.AssemblyLinearVelocity = Vector3Zero
    task.wait(0.45)
    for _ = 1, 12 do
      if Stopped() or not UserConfigs.AutoMarket or not isrbxactive() or not IsLocalAlive() then break end
      if CrateRoute.MarketManager.MenuOpen() then break end
      keypress(0x45)
      task.wait(0.15)
      keyrelease(0x45)
      task.wait(0.4)
    end
  end

  if CrateRoute.MarketManager.MenuOpen() and not Stopped() and isrbxactive() then
    task.wait(0.55)
    local listings, gold, onPerksPage = CrateRoute.MarketManager.Scan()
    if listings and not onPerksPage then
      CrateRoute.ClickButton(TabButton, 0.025, 0.04)
      task.wait(0.45)
      listings, gold, onPerksPage = CrateRoute.MarketManager.Scan()
      -- An empty Perks page has no named cards from which to identify the tab.
      if listings and #listings == 0 and CrateRoute.MarketManager.MenuOpen() then onPerksPage = true end
    end
    if listings and onPerksPage and CrateRoute.MarketManager.MenuOpen() then
      local priority = {}
      for _, name in ipairs(UserConfigs.PriorityPerks) do
        if name ~= "" then priority[PerkManager.Key(name)] = true end
      end
      Boot("market checked on wave " .. tostring(CrateRoute.RoundNumber or CrateRoute.ReadRound() or "?")
        .. ": " .. tostring(#listings) .. " perk listings, " .. tostring(gold) .. " gold")
      for _, listing in ipairs(listings) do
        if Stopped() or not UserConfigs.AutoMarket or not isrbxactive() or not CrateRoute.MarketManager.MenuOpen() then break end
        if priority[listing.Key] and not PerkManager.Owned[listing.Key]
          and not CrateRoute.WaveState.MarketAttempts[listing.Key] and listing.Count > 0 then
          -- Read Gold again because an earlier buy in this same visit may have spent it.
          local GoldTitle = Market.Gold and Market.Gold:FindFirstChild("Title")
          local currentGold = GoldTitle and tonumber(((GoldTitle.Text or ""):gsub("[^%d]", ""))) or 0
          if currentGold >= listing.Price then
            CrateRoute.WaveState.MarketAttempts[listing.Key] = true -- never repeat an unconfirmed immediate purchase
            CrateRoute.SaveWaveState()
            CrateRoute.ClickButton(listing.Buy, 0.031, 0.022)
            local purchased = false
            for _ = 1, 6 do
              task.wait(0.25)
              local remaining = tonumber(string.match(listing.Stock.Text or "", "^(%d+)")) or 0
              if remaining < listing.Count then purchased = true; break end
            end
            if purchased then
              PerkManager.Owned[listing.Key] = true
              PerkManager.Pending = true -- equip the new priority before buying other upgrades
              Boot("market bought priority perk " .. listing.Name .. " for " .. listing.Price)
            else
              Boot("market buy unconfirmed for " .. listing.Name .. "; no second click this round")
            end
          else
            Boot("market skipped unaffordable priority " .. listing.Name .. " (" .. listing.Price .. " > " .. currentGold .. ")")
          end
        end
      end
      for _ = 1, 3 do
        if not CrateRoute.MarketManager.MenuOpen() or not isrbxactive() then break end
        CrateRoute.ClickButton(Close, 0.012, 0.021)
        task.wait(0.45)
      end
      if not CrateRoute.MarketManager.MenuOpen() then
        CrateRoute.MarketPending = false
        Boot("market check complete; menu closed")
      else
        Boot("market X click did not close menu")
      end
    else
      Boot("market perk listings unavailable")
    end
  else
    Boot("market menu did not open")
  end
  if wasVisible and UI and UI.window and not Stopped() then pcall(function() UI.window:Show() end) end
  if not Stopped() then WhatShouldIBeDoing = "attack" end
  return true
end

local function KillTitan(titan: Instance)
  DebugPrint("debug", 3, nil, "KillTitan", "Starting kill sequence for:", titan.Name)
  if not titan or not titan.Parent then DebugPrint("debug", 3, nil, "KillTitan", "Invalid titan"); return end

  local StartTime = os.clock()
  local TitanAddress = titan.Address

  local LocalPlayerCharacterCache = CharacterCache[LocalPlayer.Address]; if not LocalPlayerCharacterCache then DebugPrint("debug", 3, nil, "KillTitan", "No player cache"); return end
  local Hrp = LocalPlayerCharacterCache.Hrp or GetPlayerHrp(LocalPlayer); if not Hrp then DebugPrint("debug", 3, nil, "KillTitan", "No HRP"); return end

  local IsBoss = IsBossTitan(titan)
  if IsBoss then Boot("attacking raid boss " .. titan.Name .. " (no timeout)") end
  print("[Aotr] targeting " .. titan.Name:sub(1, 8))
  FarmStats.Target = titan.Name:sub(1, 8)
  FarmStats.Status = "attacking"
  local LastChestCheck = 0
  while true do
    Progress()
    Tr.step("main", "attack delay")
    task.wait(UserConfigs.AttackDelay)
    Tr.step("main", "kill checks")
    if Stopped() or not UserConfigs.Autofarm then break end
    if CrateRoute.Pending() then break end
    if IsBoss and os.clock() - LastChestCheck > 0.5 then
      LastChestCheck = os.clock()
      local chests = Interface:FindFirstChild("Chests")
      if chests and IsObjectVisible(chests) then break end
    end
    if not IsTitanAlive(titan) then
      FarmStats.Kills += 1
      print(string.format("[Aotr] %s down after %.1fs", titan.Name:sub(1, 8), os.clock() - StartTime))
      break
    end
    if not IsLocalAlive() then print("[Aotr] died while attacking " .. titan.Name:sub(1, 8)); LogDeath("attacking " .. titan.Name:sub(1, 8)); FarmStats.Status = "dead, waiting to respawn"; break end
    if AreBladesFullyBroken() then DebugPrint("debug", 3, nil, "KillTitan", "Blades broken"); break end
    -- No per-titan kill timeout (removed at the user's request, 2026-11-03): the farm stays on a
    -- target until it dies. KillTimeout is no longer read. A titan that never
    -- dies is still caught by NoKillMinutes in the main loop, which resets the run.

    Tr.step("main", "kill checks done")
    UpdateRobloxState()
    if CurrentRobloxState == "Inactive" then
      FarmStats.Status = "waiting for Roblox focus"
      StartTime = os.clock() -- an unfocused stretch should not count toward the timeout
      task.wait(0.5)
    else
      if WhatShouldIBeDoing ~= "attack" then task.wait(0.1); continue end
      FarmStats.Status = "attacking"
      CurrentTitanTarget = titan

      -- The hover lives in a RenderStepped callback; if that stops, hold position from here
      -- (about 7 writes a second) and reconnect it.
      local HoverQuiet = os.clock() - LastHoverAt
      if HoverQuiet > 1 then
        if not HoverDeadSince then HoverDeadSince = LastHoverAt; Boot(string.format("hover quiet %.1fs while attacking", HoverQuiet)) end
        TpAboveTitan(titan)
        if os.clock() - LastHoverRewire > 3 then LastHoverRewire = os.clock(); RewireHover() end
      elseif HoverDeadSince then
        Boot(string.format("hover back after %.1fs", os.clock() - HoverDeadSince)); HoverDeadSince = nil
      end

      if UserConfigs.PullAllNapes and (os.clock() - PullListAt > 0.5 or PullListFor ~= TitanAddress) then
        PullList = GetPullTargets(titan); PullListAt = os.clock(); PullListFor = TitanAddress
      end
      if Stats.CutsceneSkip.Visible then
        FarmStats.Status = "skipping cutscene"
        task.wait(0.1)
        continue
      end
      if Qte.Active then -- a click or Space mid-QTE could count as the wrong key
        FarmStats.Status = "quick time event"
        task.wait(0.05)
        continue
      end
      Tr.step("main", "pull napes (write)")
      PullNapesTo(titan, UserConfigs.PullAllNapes and PullList or nil)

      Stats.UseHumanSkill()

      Tr.step("main", "slash wait")
      task.wait()
      Tr.step("main", "click")
      mouse1click()
      task.wait(0.03)
      Tr.step("main", "space")
      keypress(0x20)
      task.wait(0.03)
      keyrelease(0x20)
    end
  end
  -- Drop the target so the hover stops following a dead or abandoned titan.
  CurrentTitanTarget = nil
  FarmStats.Target = "none"
  DebugPrint("debug", 3, nil, "KillTitan", "Kill sequence ended for: ", titan.Name)
end


--#endregion -- Functions --



--#region -- Main loops and events --

-- Titans seen dead, by address, so a corpse still in the folder is not registered again (and
-- read again) on the next pass. Matcha's IsA always returns true, so it filtered nothing; one
-- GetChildren a pass instead of two.
local DeadTitans: { [number]: boolean } = {}
local DeadTitansCount = 0
task.spawn(function() -- KnownTitans updater and TitansCache cleanup
  while not Stopped() do
    local InFolder = {}
    Tr.step("titans", "folder scan")
    for _, titan in ipairs(TitansFolder:GetChildren()) do
      local address = titan.Address
      InFolder[address] = true
      if not KnownTitans[address] and not DeadTitans[address] then
        KnownTitans[address] = titan
      end
    end

    Tr.step("titans", "sweep dead")
    for address, titan in pairs(KnownTitans) do
      local Cache = TitansCache[address]
      local Dead = Cache and Cache.Info.Dead
      if Dead or not InFolder[address] or not GetHumanoid(titan) then
        if Dead and InFolder[address] then DeadTitans[address] = true; DeadTitansCount += 1 end
        KnownTitans[address] = nil
        TitansCache[address] = nil
      end
    end
    -- Forget corpses that have left the folder (addresses get reused by new titans).
    if DeadTitansCount > 0 then
      for address in pairs(DeadTitans) do
        if not InFolder[address] then DeadTitans[address] = nil; DeadTitansCount -= 1 end
      end
    end

    Tr.step("titans", "wait")
    task.wait(1)
  end
end)


task.spawn(function() -- Titans cache
  while not Stopped() do
    local CachedCount = 0
    for _, titan in pairs(KnownTitans) do
      if titan and titan.Parent and GetHumanoid(titan) then
        Tr.step("cache", "register titan")
        RegisterTitan(titan)
        CachedCount += 1
      end
      task.wait()
    end

    Tr.step("cache", "wait")
    task.wait(3)
  end
end)


task.spawn(function() -- The main loop, where the magic happens
  local LastKills, LastKillAt = 0, os.clock()
  while not Stopped() do
    Tr.step("main", "loop top")
    FindQteUi()
    if CrateRoute.HandleRaidChest() then
      LastKillAt = os.clock()
      Progress()
      task.wait(0.1)
      continue
    end
    -- A stuck mission keeps a fresh heartbeat (5 hours on 2026-11-02), so after NoKillMinutes
    -- without a kill the character feeds itself to a titan and the run resets. A raid boss takes
    -- minutes to kill, so while one is alive the limit is BossNoKillMinutes.
    local Idle = not UserConfigs.Autofarm or FarmStats.Status == "paused" or FarmStats.Status == "pressing retry" or FarmStats.Status == "dead, waiting to respawn"
    if FarmStats.Kills ~= LastKills or Idle then
      LastKills, LastKillAt = FarmStats.Kills, os.clock()
    else
      local Limit = (IsBossAlive() and UserConfigs.BossNoKillMinutes or UserConfigs.NoKillMinutes) * 60
      if os.clock() - LastKillAt > Limit then
        GiveUpToTitan(string.format("no kill for %.0f min (kills %d, timeouts %d)", Limit / 60, FarmStats.Kills, FarmStats.Timeouts))
        LastKillAt = os.clock()
        continue
      end
    end
    Progress()

    if not UserConfigs.Autofarm and not UserConfigs.AutoCrates and not UserConfigs.AutoPerks then
      CurrentTitanTarget = nil
      FarmStats.Status = "paused"
      task.wait(0.5)
      continue
    end

    Tr.step("main", "retry check")
    if UserConfigs.AutoRetry and IsRetryVisible() then
      Tr.step("main", "pressing retry")
      if FarmStats.Status ~= "pressing retry" then DumpHistory(string.format("retry screen at %d kills", FarmStats.Kills)) end
      RetryScreenSince = RetryScreenSince or os.clock()
      FarmStats.Status = "pressing retry"
      DebugPrint("debug", nil, nil, nil, "Detected that the retry button is visible.")
      local retryStarting = PressRetry()
      task.wait(retryStarting and 0.5 or 5)
      continue
    end
    RetryScreenSince = nil

    if not IsLocalAlive() then
      CurrentTitanTarget = nil
      -- After Retry the teleport removes the character (health unreadable), which is not a death.
      if FarmStats.Status ~= "dead, waiting to respawn" and FarmStats.Status ~= "starting" and FarmStats.Status ~= "pressing retry" then LogDeath("main loop, was " .. FarmStats.Status) end
      FarmStats.Status = "dead, waiting to respawn"
      task.wait(1)
      continue
    end

    if CrateRoute.Handle() then
      task.wait(0.1)
      continue
    end
    if UserConfigs.AutoPerks and UserConfigs.AutoMarket and CrateRoute.MarketPending then
      if PerkManager.SurveyPending then
        if PerkManager.Handle() then task.wait(0.1); continue end
      else
        if CrateRoute.MarketManager.Handle() then task.wait(0.1); continue end
      end
      FarmStats.Status = "waiting for market check"
      task.wait(0.5)
      continue
    end
    if PerkManager.Handle() then
      task.wait(0.1)
      continue
    end
    CrateRoute.ResumeSavedWave()
    if CrateRoute.HandleUpgrade() then
      task.wait(0.1)
      continue
    end
    if CrateRoute.HandleEquipment() then
      task.wait(0.1)
      continue
    end
    if not UserConfigs.Autofarm then
      CurrentTitanTarget = nil
      FarmStats.Status = "Waves tasks idle (titan farm off)"
      task.wait(0.5)
      continue
    end

    Tr.step("main", "blade check")
    if AreBladesFullyBroken() then
      CurrentTitanTarget = nil
      if UserConfigs.AutoReload then
        FarmStats.Status = "reloading"
        Tr.step("main", "reload")
        HandleAllReloads()
      else
        FarmStats.Status = "blades broken (auto reload off)"
      end
      task.wait(1)
      continue
    end

    Tr.step("main", "nearest titan")
    local NearestTitan = GetNearestTitan()

    if not NearestTitan then
      FarmStats.Status = "no titans found"
      task.wait(0.05)
      continue
    end

    DebugPrint("debug", 2, nil, nil, "Attempting to kill the titan: ", NearestTitan.Name)
    KillTitan(NearestTitan)
    task.wait(0.1)
  end
end)


task.spawn(function() -- Players cache
  while not Stopped() do
    local PlayerCount = #Players:GetPlayers()
    
    for _, player in ipairs(Players:GetPlayers()) do
      RegisterPlayer(player)
      task.wait()
    end

    local CachedCount = 0
    for playerAddress, cache in pairs(CharacterCache) do
      local character = cache.Character

      if not character or not character.Parent then
        CharacterCache[playerAddress] = nil
      else
        CachedCount += 1
      end
      task.wait()
    end
    
    task.wait(10)
  end
end)

--#endregion -- Main loops and events --



task.spawn(function() -- loop to fix matcha's weird task's bug
  while true do
    task.wait(math.huge)
  end

  task.spawn(function()
    while true do
      task.wait(math.huge)
    end

    task.spawn(function()
      while true do
        task.wait(math.huge)
      end
    end)
  end)
end)


local LastParkTime = 0
local LastHoverError = 0
local LastHoverWrite = 0
local HOVER_INTERVAL = 0.05 -- seconds between hover CFrame writes (20 a second)
local RenderConn

local function HoverStep()
  if not UserConfigs.Autofarm or WhatShouldIBeDoing ~= "attack" then return end
  if CurrentRobloxState == "Inactive" then
    -- This used to write the CFrame every frame (~60 heavy writes a second) with velocity left to
    -- build (2,800 studs/s seen 2026-11-03). Unfocusing Roblox happens on every watchdog restart,
    -- so it fed the hangs it was restarting for. No clicks land while unfocused, so the slash
    -- speed does not matter here: zero the velocity and re-park twice a second.
    if os.clock() - LastParkTime < 0.5 then return end
    LastParkTime = os.clock()
    local Hrp = GetPlayerHrp(LocalPlayer); if not IsValid(Hrp) then return end
    Tr.step("render", "park unfocused (write)")
    Hrp.CFrame = SafePosNow()
    Hrp.AssemblyLinearVelocity = Vector3Zero
    HeavyWrites += 2
    return
  end
  if CurrentTitanTarget then
    -- Throttled to HOVER_INTERVAL: a CFrame write every frame was ~60 heavy writes a second, the
    -- likeliest load behind Matcha hanging mid-mission. Velocity still builds between writes.
    if os.clock() - LastHoverWrite >= HOVER_INTERVAL then
      LastHoverWrite = os.clock()
      Tr.step("render", "hover over target (write)")
      TpAboveTitan(CurrentTitanTarget)
    end
  elseif os.clock() - LastParkTime > 0.5 then
    -- No target (between kills, or waiting): park out of reach instead of standing among titans.
    -- Throttled, since each CFrame write is expensive.
    LastParkTime = os.clock()
    local Hrp = GetPlayerHrp(LocalPlayer); if not IsValid(Hrp) then return end
    Tr.step("render", "park, no target (write)")
    Hrp.CFrame = SafePosNow()
    HeavyWrites += 1
  end
end

local function OnRenderStepped()
  if Stopped() then
    if Stats.CutsceneSkip and Stats.CutsceneSkip.Down then keyrelease(0x45); Stats.CutsceneSkip.Down = false end
    if RenderConn then RenderConn:Disconnect() end
    pcall(StatusCleanup)
    print("[Aotr] stopped")
    return
  end
  LastHoverAt = os.clock()
  pcall(Tr.flush)
  Tr.step("render", "cutscene skip")
  local okSkip, skipErr = pcall(Stats.SkipCutsceneTick)
  if not okSkip and os.clock() - LastHoverError > 5 then LastHoverError = os.clock(); Boot("cutscene skip error: " .. tostring(skipErr)) end
  Tr.step("render", "qte")
  local okQte, qteErr = pcall(QteTick)
  if not okQte and os.clock() - LastHoverError > 5 then LastHoverError = os.clock(); Boot("qte tick error: " .. tostring(qteErr)) end
  Tr.step("render", "status")
  local okTick, tickErr = pcall(StatusTick)
  if not okTick and os.clock() - LastHoverError > 5 then LastHoverError = os.clock(); Boot("status tick error: " .. tostring(tickErr)) end
  -- An error must not take the hover down with it; log it (throttled) for debugging instead.
  Tr.step("render", "hover")
  local ok, err = pcall(HoverStep)
  if not ok and os.clock() - LastHoverError > 5 then LastHoverError = os.clock(); Boot("hover error: " .. tostring(err)) end
  Tr.step("render", "frame done")
end

RewireHover = function()
  pcall(function() if RenderConn then RenderConn:Disconnect() end end)
  RenderConn = game:GetService("RunService").RenderStepped:Connect(OnRenderStepped)
  Boot("hover reconnected")
end
RenderConn = game:GetService("RunService").RenderStepped:Connect(OnRenderStepped)

-- ---------------------------------------------------------------------------
-- Menu (same laced.club UE library and layout as the SAO Eternity script)
-- ---------------------------------------------------------------------------
-- Main tab: Farm (on/off, retry, reload, logging) and Session (kill counts, unload).
-- Tuning tab: Attack (nape size, slash delay, timeout) and Hover (heights per titan type,
-- bob, reload spot). UE's own Settings tab has the menu key and configs. Our settings are
-- saved to aotr_farm.json on every change and loaded at start.
local UE_URL = "https://raw.githubusercontent.com/hauntedscripts/Scripts2/refs/heads/main/matcha%20ue"
UI = { lib = nil, window = nil, controls = {}, unloading = false, ready = false }
local KEYS = { farm = 0x75, unload = 0x23 } -- F6, End

local function findUE()
  local envs = {}
  if type(_G.getgenv) == "function" then
    local ok, genv = pcall(_G.getgenv)
    if ok and type(genv) == "table" then envs[#envs + 1] = genv end
  end
  envs[#envs + 1] = _G
  for _, env in ipairs(envs) do
    local c = env.UELibrary
    if type(c) == "table" and type(c.CreateWindow) == "function" then return c end
  end
  return nil
end

local function loadUE()
  local src = nil
  for attempt = 1, 3 do
    local ok, body = pcall(httpget, UE_URL)
    if ok and type(body) == "string" and #body > 2000 and string.find(body, "UELibrary", 1, true) then
      src = body
      break
    end
    task.wait(attempt)
  end
  if not src then return nil, "UE download failed" end
  local previous = findUE()
  local chunk = loadstring(src, "laced.club UE")
  if type(chunk) ~= "function" then return nil, "UE compile failed" end
  local okRun, err = pcall(chunk)
  if not okRun then return nil, "UE run failed: " .. tostring(err) end
  local ue = findUE()
  if not ue or ue == previous or ue._unloaded then return nil, "UE did not expose a fresh UELibrary" end
  return ue
end

local function syncControl(id, value)
  local c = UI.controls[id]
  if c and c.Value ~= value and c.SetValue then pcall(function() c:SetValue(value) end) end
end

local function Unload()
  if _G.AotrRunId == RunId then _G.AotrStop = true end
  CurrentTitanTarget = nil
  UI.unloading = true
  Heartbeat("unloaded")
  if UI.lib and not UI.lib._unloaded and type(UI.lib.Unload) == "function" then pcall(function() UI.lib:Unload() end) end
end

-- Toggle and slider callbacks share one shape: set the config value, save.
local function setter(key, scale)
  return function(v)
    if type(UserConfigs[key]) == "boolean" then
      UserConfigs[key] = v == true
    else
      local n = tonumber(v)
      if n then UserConfigs[key] = scale and n / scale or n end
    end
    SaveSettings()
  end
end

local function buildMenu()
  -- The menu redraws itself from Lua every 16ms; MenuDisabled skips it to test whether that load
  -- is what hangs Matcha mid-mission. Hotkeys and the status line keep working without it.
  if UserConfigs.MenuDisabled then UI.ready = true; Boot("menu disabled (MenuDisabled in aotr_farm.json)"); return end
  local ue, err = loadUE()
  if not ue then
    UI.ready = true
    Boot("menu failed: " .. tostring(err))
    warn("[Aotr] menu failed to load: " .. tostring(err) .. " (F6 / End hotkeys still work)")
    return
  end
  Boot("menu loaded")
  UI.lib = ue
  -- Survey Corps look: wings-of-freedom green on dark olive and leather brown.
  local accent = Color3.fromRGB(120, 200, 110)
  ue.AccentColor, ue.StaticAccentColor = accent, accent
  ue.BackgroundColor = Color3.fromRGB(16, 15, 11)
  ue.MainColor = Color3.fromRGB(30, 28, 20)
  ue.OutlineColor = Color3.fromRGB(86, 74, 50)
  ue.FontColor = Color3.fromRGB(238, 232, 214)
  ue.GradientEnabled = true
  ue.GradientTopColor = Color3.fromRGB(48, 58, 34)
  ue.GradientBottomColor = Color3.fromRGB(14, 12, 8)
  ue.SettingsFile = "aotr_farm.ui.json"
  ue.ConfigFolder = "aotr_farm_configs"
  local win = ue:CreateWindow({ Title = "Wings of Freedom  |  AoT: Revolution", Width = 540, Height = 580, AutoShow = true, Center = true })
  UI.window = win
  -- UE draws each control the moment it is added; build hidden, show once.
  pcall(function() win:Hide() end)
  local function reg(id, c) UI.controls[id] = c; return c end

  local main = win:AddTab("Main")
  local farm = main:AddLeftGroupbox("Farm")
  reg("Autofarm", farm:AddToggle("Autofarm", { Text = "Auto Farm Titans (F6)", Default = UserConfigs.Autofarm,
    Tooltip = "Hover above the nearest titan, pull its nape to you and slash",
    Callback = setter("Autofarm") }))
  reg("AutoRetry", farm:AddToggle("AutoRetry", { Text = "Auto Retry", Default = UserConfigs.AutoRetry,
    Tooltip = "Press Retry on the rewards screen to start the next mission",
    Callback = setter("AutoRetry") }))
  reg("AutoReload", farm:AddToggle("AutoReload", { Text = "Auto Reload / Refill", Default = UserConfigs.AutoReload,
    Tooltip = "Reload blades at the safe spot; refill at the gas tank on maps the script knows",
    Callback = setter("AutoReload") }))
  reg("AutoSkipCutscenes", farm:AddToggle("AutoSkipCutscenes", { Text = "Auto Skip Cutscenes", Default = UserConfigs.AutoSkipCutscenes,
    Tooltip = "Press E when the cutscene Skip prompt appears", Callback = setter("AutoSkipCutscenes") }))
  reg("AutoRaidChest", farm:AddToggle("AutoRaidChest", { Text = "Auto Raid Chest", Default = UserConfigs.AutoRaidChest,
    Tooltip = "Open the free left chest, then click Finish before Retry", Callback = setter("AutoRaidChest") }))
  reg("OpenKeyChest", farm:AddToggle("OpenKeyChest", { Text = "Open Key Chest", Default = UserConfigs.OpenKeyChest,
    Tooltip = "Spend one key on the right raid chest after opening the free chest", Callback = setter("OpenKeyChest") }))
  reg("AutoCrates", farm:AddToggle("AutoCrates", { Text = "Auto Crate Delivery", Default = UserConfigs.AutoCrates,
    Tooltip = "Touch your spawned Waves crate, then the drop-off cart",
    Callback = setter("AutoCrates") }))
  reg("AutoEquipmentUpgrades", farm:AddToggle("AutoEquipmentUpgrades", { Text = "Auto Equipment Upgrades", Default = UserConfigs.AutoEquipmentUpgrades,
    Tooltip = "After crate delivery, visit Lulu and click Upgrade All five times",
    Callback = setter("AutoEquipmentUpgrades") }))
  reg("AutoStationUpgrades", farm:AddToggle("AutoStationUpgrades", { Text = "Auto HQ Upgrades", Default = UserConfigs.AutoStationUpgrades,
    Tooltip = "Regen first, up to five successful buys total; then Max HP twice and Refills on even waves",
    Callback = setter("AutoStationUpgrades") }))
  reg("AutoQTE", farm:AddToggle("AutoQTE", { Text = "Auto Quick Time Events", Default = UserConfigs.AutoQTE,
    Tooltip = "Press the key a raid quick time event shows", Callback = setter("AutoQTE") }))
  reg("NoKillMinutes", farm:AddSlider("NoKillMinutes", { Text = "Reset After No Kill", Default = UserConfigs.NoKillMinutes,
    Min = 2, Max = 30, Rounding = 0, Suffix = " min", Tooltip = "Feed a titan to restart a stuck run",
    Callback = setter("NoKillMinutes") }))
  reg("BossNoKillMinutes", farm:AddSlider("BossNoKillMinutes", { Text = "Reset After (Raid Boss)", Default = UserConfigs.BossNoKillMinutes,
    Min = 5, Max = 60, Rounding = 0, Suffix = " min", Callback = setter("BossNoKillMinutes") }))
  reg("DebugMode", farm:AddToggle("DebugMode", { Text = "Debug Logging", Default = UserConfigs.DebugMode,
    Tooltip = "Verbose log lines (file logging only starts if this was on at launch)",
    Callback = setter("DebugMode") }))

  local session = main:AddRightGroupbox("Session")
  session:AddButton({ Text = "Print kill stats", Func = function()
    print(string.format("[Aotr] kills %d  timeouts %d  target %s  status %s",
      FarmStats.Kills, FarmStats.Timeouts, FarmStats.Target, FarmStats.Status))
  end })
  session:AddButton({ Text = "Reset kill stats", Func = function() FarmStats.Kills, FarmStats.Timeouts = 0, 0 end })
  session:AddButton({ Text = "Unload (End)", Func = Unload })

  local boss = main:AddRightGroupbox("Raid Boss")
  reg("PullBossLimbs", boss:AddToggle("PullBossLimbs", { Text = "Pull All Limbs", Default = UserConfigs.PullBossLimbs,
    Tooltip = "Stack a raid boss's hitbox limbs for each slash; extra damage is unverified",
    Callback = setter("PullBossLimbs") }))

  local skills = main:AddLeftGroupbox("Human Skills")
  reg("HumanSkills", skills:AddToggle("HumanSkills", { Text = "Use Human Skills", Default = UserConfigs.HumanSkills,
    Tooltip = "Use ready hotbar skills; wait 2.5 seconds after each confirmed use", Callback = setter("HumanSkills") }))
  reg("AwakeningSlot", skills:AddSlider("AwakeningSlot", { Text = "Awakening Slot", Default = UserConfigs.AwakeningSlot,
    Min = 1, Max = 5, Rounding = 0, Tooltip = "Hotbar slot for Rage Mode; press only at full bar, then wait until the bar empties and fills again",
    Callback = setter("AwakeningSlot") }))

  local perksTab = win:AddTab("Perk Manager")
  local priorityLeft = perksTab:AddLeftGroupbox("Priority Perks 1-3")
  local priorityRight = perksTab:AddRightGroupbox("Priority Perks 4-6")
  reg("AutoPerks", priorityLeft:AddToggle("AutoPerks", { Text = "Auto Manage Perks", Default = UserConfigs.AutoPerks,
    Tooltip = "Equip priority perks first, then the highest-rarity perks in remaining slots",
    Callback = function(value) UserConfigs.AutoPerks = value == true; PerkManager.Pending = true; PerkManager.SurveyPending = true; SaveSettings() end }))
  reg("AutoMarket", priorityLeft:AddToggle("AutoMarket", { Text = "Auto Buy Missing Priority Perks", Default = UserConfigs.AutoMarket,
    Tooltip = "After each Waves crate, check Orange's Market before upgrades. Requires Auto Manage Perks.",
    Callback = function(value)
      UserConfigs.AutoMarket = value == true
      if UserConfigs.AutoMarket then CrateRoute.MarketPending = true; PerkManager.SurveyPending = true; PerkManager.Pending = true end
      SaveSettings()
    end }))
  local selectors = {}
  priorityLeft:AddInput("PerkSearch", { Text = "Search perk names", Default = "", Placeholder = "Type part of a perk name",
    Callback = function(query)
      for i, selector in ipairs(selectors) do
        selector:SetValues(PerkManager.SearchOptions(tostring(query or ""), UserConfigs.PriorityPerks[i]))
      end
    end })
  for i = 1, 6 do
    local box = i <= 3 and priorityLeft or priorityRight
    local selected = UserConfigs.PriorityPerks[i]
    selectors[i] = reg("PriorityPerk" .. i, box:AddDropdown("PriorityPerk" .. i, {
      Text = "Priority " .. i, Values = PerkManager.SearchOptions("", selected),
      Default = selected ~= "" and selected or "None",
      Tooltip = "Search above, then choose this slot. Earlier slots win when capacity is limited.",
      Callback = function(value)
        local name = value == "None" and "" or tostring(value or "")
        if name ~= "" and not PerkManager.Rarity[PerkManager.Key(name)] then return end
        UserConfigs.PriorityPerks[i] = name
        for other = 1, 6 do
          if other ~= i and name ~= "" and UserConfigs.PriorityPerks[other] == name then
            UserConfigs.PriorityPerks[other] = ""
            if selectors[other] then selectors[other]:SetValue("None") end
          end
        end
        PerkManager.Pending = true
        if UserConfigs.AutoMarket then
          PerkManager.SurveyPending = true
          CrateRoute.MarketPending = true
        end
        SaveSettings()
      end }))
  end
  priorityRight:AddButton({ Text = "Manage perks now", Func = function() PerkManager.Pending = true; PerkManager.NextCheck = 0 end })

  local tuning = win:AddTab("Tuning")
  local attack = tuning:AddLeftGroupbox("Attack")
  reg("NapeSize", attack:AddSlider("NapeSize", { Text = "Nape Size", Default = UserConfigs.NapeSize,
    Min = 5, Max = 40, Rounding = 0, Suffix = " studs", Callback = setter("NapeSize") }))
  reg("PullAllNapes", attack:AddToggle("PullAllNapes", { Text = "Pull All Napes", Default = UserConfigs.PullAllNapes,
    Tooltip = "Stack every live titan's nape on your target's so each slash can hit them all",
    Callback = setter("PullAllNapes") }))
  reg("PullRadius", attack:AddSlider("PullRadius", { Text = "Pull Range", Default = UserConfigs.PullRadius,
    Min = 100, Max = 5000, Rounding = 0, Suffix = " studs",
    Tooltip = "How far from your target Pull All Napes reaches; max = whole map", Callback = setter("PullRadius") }))
  reg("PullCount", attack:AddSlider("PullCount", { Text = "Pull Count", Default = UserConfigs.PullCount,
    Min = 1, Max = 12, Rounding = 0, Suffix = " napes",
    Tooltip = "Napes stacked per slash, your target included; blade hits cap at about 6", Callback = setter("PullCount") }))
  reg("AttackDelay", attack:AddSlider("AttackDelay", { Text = "Slash Delay", Default = math.floor(UserConfigs.AttackDelay * 1000 + 0.5),
    Min = 30, Max = 300, Rounding = 0, Suffix = " ms", Callback = setter("AttackDelay", 1000) }))
  reg("KillTimeout", attack:AddSlider("KillTimeout", { Text = "Give Up After", Default = UserConfigs.KillTimeout,
    Min = 3, Max = 30, Rounding = 0, Suffix = "s", Callback = setter("KillTimeout") }))

  local hover = tuning:AddRightGroupbox("Hover")
  reg("HeightNormal", hover:AddSlider("HeightNormal", { Text = "Height: Normal", Default = UserConfigs.HeightNormal,
    Min = 40, Max = 300, Rounding = 0, Suffix = " studs", Callback = setter("HeightNormal") }))
  reg("HeightStall", hover:AddSlider("HeightStall", { Text = "Height: Stall", Default = UserConfigs.HeightStall,
    Min = 40, Max = 300, Rounding = 0, Suffix = " studs", Callback = setter("HeightStall") }))
  reg("HeightAttack", hover:AddSlider("HeightAttack", { Text = "Height: Attack", Default = UserConfigs.HeightAttack,
    Min = 40, Max = 300, Rounding = 0, Suffix = " studs", Callback = setter("HeightAttack") }))
  reg("HeightColossal", hover:AddSlider("HeightColossal", { Text = "Height: Colossal", Default = UserConfigs.HeightColossal,
    Min = 40, Max = 400, Rounding = 0, Suffix = " studs", Callback = setter("HeightColossal") }))
  reg("BobAmplitude", hover:AddSlider("BobAmplitude", { Text = "Bob Amount", Default = UserConfigs.BobAmplitude,
    Min = 0, Max = 10, Rounding = 1, Suffix = " studs", Callback = setter("BobAmplitude") }))
  reg("SafeHeight", hover:AddSlider("SafeHeight", { Text = "Reload Spot Height", Default = UserConfigs.SafeHeight,
    Min = 1000, Max = 20000, Rounding = 0, Suffix = " studs", Callback = setter("SafeHeight") }))

  -- Separate box on the left: nine sliders in Hover ran past the bottom of the window.
  local position = tuning:AddLeftGroupbox("Position")
  reg("HoverOffsetX", position:AddSlider("HoverOffsetX", { Text = "Offset X", Default = UserConfigs.HoverOffsetX,
    Min = -80, Max = 80, Rounding = 0, Suffix = " studs", Tooltip = "Sideways shift of the hover spot; the nape moves with it",
    Callback = setter("HoverOffsetX") }))
  reg("HoverOffsetZ", position:AddSlider("HoverOffsetZ", { Text = "Offset Z", Default = UserConfigs.HoverOffsetZ,
    Min = -80, Max = 80, Rounding = 0, Suffix = " studs", Tooltip = "Forward/back shift of the hover spot; the nape moves with it",
    Callback = setter("HoverOffsetZ") }))
  reg("NapeOffsetY", position:AddSlider("NapeOffsetY", { Text = "Nape Above You", Default = UserConfigs.NapeOffsetY,
    Min = -15, Max = 15, Rounding = 0, Suffix = " studs", Tooltip = "Height of the pulled napes above you",
    Callback = setter("NapeOffsetY") }))

  if type(ue.OnUnload) == "function" then
    pcall(function() ue:OnUnload(function() if not UI.unloading then Unload() end end) end)
  end
  pcall(function()
    win:Show()
    win._visibilityDirty = true
  end)
  UI.ready = true

  -- UE redraws from its own task.spawn loop, but Matcha kills a thread at its first yield when
  -- its function comes from a chunk loadstring'd after the caller had already yielded (UE is
  -- loaded mid-run), so that loop draws one frame and dies: tabs added later never appear.
  -- Drive the window from our own thread instead.
  task.spawn(function()
    while not Stopped() and not UI.unloading and not ue._unloaded and not win.Destroyed do
      local ok, err = pcall(win.Step, win)
      if not ok then warn("[Aotr] menu step error: " .. tostring(err)); task.wait(0.25)
      else task.wait(ue.PerformanceMode and 0.05 or 0.016) end
    end
  end)
end

-- Status line and hotkeys (work without the menu).
local StatusLabel = nil
pcall(function()
  StatusLabel = Drawing.new("Text")
  StatusLabel.Size = 16
  StatusLabel.Outline = true
  StatusLabel.Color = Color3.fromRGB(120, 200, 110)
  StatusLabel.Position = Vector2.new(12, 300)
  StatusLabel.Visible = true
end)

local function keyDown(vk)
  if type(iskeypressed) ~= "function" then return false end
  local ok, s = pcall(iskeypressed, vk)
  return ok and s == true
end

-- Status changes go to boot.txt too (Matcha's log is wiped on every reload), except the
-- attacking / no titans churn of normal farming.
local QuietStatus = { ["attacking"] = true, ["titan attacking"] = true, ["no titans found"] = true, ["starting"] = true }
local LastTracedStatus = "starting"
local function TraceStatus()
  local s = FarmStats.Status
  if s == LastTracedStatus then return end
  if not (QuietStatus[s] and QuietStatus[LastTracedStatus]) then
    Boot(string.format("status: %s (kills %d)", s, FarmStats.Kills))
  end
  LastTracedStatus = s
end

-- Status, black box, heartbeat and hotkeys. Ticked from the RenderStepped hover connection rather
-- than a task.spawn loop: with the menu disabled that loop ran one pass and died at its first wait
-- (Matcha kills threads started this late at their first yield; the menu's thread was keeping it
-- alive), so the heartbeat stopped and the watchdog restarted Matcha every ~30s.
local was = {}
local lastBeat, lastStatusTick = 0, 0
local lastBox, boxWrites = 0, 0
local LastStatusText = nil
StatusTick = function()
  if os.clock() - lastStatusTick < 0.1 then return end
  lastStatusTick = os.clock()
  TraceStatus()
  if os.clock() - lastBox >= 0.5 then
    Tr.step("render", "black box line")
    lastBox = os.clock(); LastBlackBox = BlackBoxLine(); PushHistory(LastBlackBox)
    -- Freeze test (2026-11-03): black box writes off, like the heartbeat. The line is still built
    -- and kept in memory, so death and Retry dumps in deaths.txt still have it.
    boxWrites += 1
    if not HEARTBEAT_TEST_OFF and boxWrites % 2 == 0 then Tr.step("render", "black box write"); pcall(writefile, "aotr/blackbox.txt", LastBlackBox) end
  end
  -- Every second: the watchdog restarts a hung Matcha once this is 5s old, and the character
  -- outlives a hang by ~30s (2026-11-01 deaths), so a 5s beat wasted most of that margin.
  if os.clock() - lastBeat >= 1 and os.clock() - LastProgress < PROGRESS_STALL_LIMIT then
    Tr.step("render", "heartbeat write")
    lastBeat = os.clock(); Heartbeat("farming")
  end
  Tr.step("render", "keys and status text")
  for name, vk in pairs(KEYS) do
    local down = keyDown(vk)
    if down and not was[name] then
      if name == "farm" then
        UserConfigs.Autofarm = not UserConfigs.Autofarm
        SaveSettings()
      elseif name == "unload" then
        Unload()
      end
    end
    was[name] = down
  end
  syncControl("Autofarm", UserConfigs.Autofarm)
  if StatusLabel then
    local Text = string.format("AoTR farm:%s  kills:%d  timeouts:%d  target:%s  |  %s",
      UserConfigs.Autofarm and "ON" or "off", FarmStats.Kills, FarmStats.Timeouts, FarmStats.Target, FarmStats.Status)
    if Text ~= LastStatusText then -- a Drawing write per tick otherwise
      LastStatusText = Text
      pcall(function() StatusLabel.Text = Text end)
    end
  end
end
StatusCleanup = function()
  if StatusLabel then pcall(function() StatusLabel:Remove() end); StatusLabel = nil end
end

task.spawn(buildMenu)
Boot("loops running")
print("[Aotr] running - F6 farm on/off, End unload (or _G.AotrStop = true)")

