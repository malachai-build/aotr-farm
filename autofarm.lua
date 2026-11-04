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
  NapeSize = 15,          -- studs; the pulled nape is resized to this cube
  PullAllNapes = false,   -- stack every live titan's nape on the target's, not just the target's
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
  ShiftEnabled = false,   -- press the titan shifting skill when its Shift Bar can be full
  ShiftKey = 1,           -- hotbar slot (key 1-5) the shifting skill is bound to
  TitanSkills = true,     -- use the five titan skills while shifted
  TitanSkillDelay = 0.8,  -- seconds between titan skill presses (the game enforces cooldowns)
  TitanStrikeDistance = 18, -- studs from the struck part (nape, or a boss's marked limb) that the titan form stands
  TitanRetreatHp = 0.35,  -- fraction of titan health below which the titan form backs off to the hover
  TitanReturnHp = 0.8,    -- fraction it must heal back to before striking again
  TitanKillTimeout = 25,  -- seconds before giving up on a titan while shifted
  NoKillMinutes = 5,      -- minutes without a kill before feeding a titan to reset the run
  BossNoKillMinutes = 20, -- the same while a raid boss is alive (bosses never time out)
  AutoQTE = true,         -- press the key a raid quick time event asks for
  DebugMode = _G.KittyDebug == true -- was `or true`, which forced it on
}
local SETTINGS_FILE = "aotr_farm.json"
local SAVED_KEYS = {
  "Autofarm", "AutoRetry", "AutoReload", "NapeSize", "PullAllNapes", "PullRadius", "PullCount", "MenuDisabled", "KillTimeout", "AttackDelay", "BobAmplitude",
  "HeightNormal", "HeightStall", "HeightAttack", "HeightColossal", "HoverOffsetX", "HoverOffsetZ",
  "NapeOffsetY", "SafeHeight", "DebugMode",
  "ShiftEnabled", "ShiftKey", "TitanSkills", "TitanSkillDelay", "TitanStrikeDistance", "TitanRetreatHp", "TitanReturnHp", "TitanKillTimeout",
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

-- Stop switch: `_G.AotrStop = true` (or the menu's Unload) halts every loop and the hover teleport.
-- Each run takes a fresh id, so re-running (auto-exec, then by hand) stops the old copy, and the
-- old copy's Unload, fired when the new menu replaces its window, cannot stop the new one.
local RunId = tostring(os.clock()) .. "-" .. tostring(math.random(1, 1e9))
_G.AotrRunId = RunId
_G.AotrStop = false
local function Stopped() return _G.AotrStop == true or _G.AotrRunId ~= RunId end
local FarmStats = { Kills = 0, Timeouts = 0, Shifts = 0, Target = "none", Status = "starting" }


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
local CharactersFolder = nil; repeat task.wait(0.03); CharactersFolder = Workspace:FindFirstChild("Characters") until CharactersFolder
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
local TitanForm = false -- shifted into a titan; set by IsTitanForm, read by the hover and nape pull
local LastShiftBurstAt = -math.huge -- end of the last shift key burst; the refill waits for it to settle

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
  local function Place(titan: Instance)
    Tr.step("main", "pull: find nape")
    local Nape = GetTitanWeakSpot(titan); if not Nape then return end
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

    -- Our own titan, if the game files it under workspace.Titans, sits on our position.
    if TitanForm and Distance < 3 then continue end

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
  if TitanForm then
    -- Punches only count when the titan's own body reaches the part. From the hover (~200 studs up)
    -- nothing landed, and a pulled part snaps straight back: each Hitboxes.Hit part is welded to
    -- its titan. Seen 2026-11-02 in the Female Titan raid (boss bar = Interface.Raids.Health
    -- Percentage; its Humanoid always reads 100): standing TitanStrikeDistance from the marked limb
    -- at its height, the bar held at 99.8% for 10s without clicks and fell to 97.1% in 17s with them.
    -- The boss hits back hard there: 585 hp gone in ~45s, then the run was lost (2026-11-02). So
    -- below TitanRetreatHp of max health the titan backs off to the old hover (it lasted full 95s
    -- forms up there) and comes back once it has healed past TitanReturnHp.
    -- KillTitan picks the part (GetPath yields).
    local Strike = TitanCache.Info.Strike; if not Strike or not Strike.Parent then return false end
    local TitanHrp = GetTitanHrp(titan); if not TitanHrp then return false end
    local Humanoid = GetPlayerHumanoid(LocalPlayer)
    local hpOk, hp, maxHp = pcall(function() return Humanoid.Health, Humanoid.MaxHealth end)
    if hpOk and type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then
      local Was = LocalPlayerCache.TitanRetreat == true
      local Retreat = Was
      if not Was and hp < maxHp * UserConfigs.TitanRetreatHp then Retreat = true
      elseif Was and hp > maxHp * UserConfigs.TitanReturnHp then Retreat = false end
      if Retreat ~= Was then
        Boot(string.format("titan %s at %.0f/%.0f hp", Retreat and "backs off" or "returns to strike", hp, maxHp))
      end
      LocalPlayerCache.TitanRetreat = Retreat
    end
    local tp, sp, mp = TitanHrp.Position, Strike.Position, Hrp.Position
    local away = Vector3New(mp.X - tp.X, 0, mp.Z - tp.Z) -- stay on our side of the titan
    away = away.Magnitude > 1 and away.Unit or Vector3New(1, 0, 0)
    local stand = sp + away * UserConfigs.TitanStrikeDistance
    local face = Vector3New(sp.X, stand.Y, sp.Z)
    if LocalPlayerCache.TitanRetreat then
      local hx, hy, hz = GetHoverPoint(titan); if not hx then return false end
      stand = Vector3New(hx, hy, hz) + away * UserConfigs.TitanStrikeDistance
      face = Vector3New(tp.X, stand.Y, tp.Z)
    end
    HeavyWrites += 2
    local ok, err = pcall(function()
      Hrp.CFrame = CFrame.lookAt(stand, face)
      Hrp.AssemblyLinearVelocity = Vector3Zero
    end)
    if not ok then DebugPrint("warn", 0, nil, nil, "Error happened while placing the titan form: " .. tostring(err)) end
    return ok
  end

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
  if TitanForm then return end -- a titan has no blades or gas; the HUD reads empty and the refill never ends
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
      -- Shifting mid-refill left the titan hanging at the reload spot (2026-11-02): drop the refill.
      local okShift, Shifter = pcall(function() return LocalPlayer.Character:GetAttribute("Shifter") end)
      if TitanForm or (okShift and Shifter ~= nil) then RefillStuckSince = nil; WhatShouldIBeDoing = "attack"; break end
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
        -- A shift burst's key spam right before kept R from refilling; let it settle first.
        if os.clock() - LastShiftBurstAt < 5 then task.wait(0.5); continue end
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

local function PressRetry()
  if not IsRetryVisible() then return end

  DebugPrint("debug", 0, nil, "PressRetry", "Pressing the retry button.")
  Boot(string.format("retry press %d via %s", RetryCount + 1, RetryCount % 4 < 3 and "keys" or "mouse"))
  task.wait(0.5)

  -- Three key attempts, then one mouse click, repeating: the mouse click alone missed for minutes
  -- (00:18-00:25, 2026-11-02) while keys were never tried again.
  if RetryCount % 4 < 3 then -- ui navigation
    keypress(0xDC) -- Backslash key
    task.wait(0.3)
    keyrelease(0xDC)
    task.wait(1.0)

    keypress(0x44) -- D key
    task.wait(0.2)
    keyrelease(0x44)
    task.wait(0.4)

    keypress(0x44) -- D key
    task.wait(0.2)
    keyrelease(0x44)
    task.wait(0.4)

    keypress(0x0D) -- Enter key
    task.wait(0.3)
    keyrelease(0x0D)
    task.wait(0.6)

    RetryCount += 1

  else -- Press retry via mouse
    local RetryButton = GetPath(PlayerGui, true, "Interface", "Rewards", "Main", "Info", "Main", "Buttons", "Retry") :: GuiObject; if not RetryButton then return end
      
    local AbsolutePositionBtn = RetryButton.AbsolutePosition
    local AbsoluteSizeBtn = RetryButton.AbsoluteSize

    local TargetX = AbsolutePositionBtn.X + (AbsoluteSizeBtn.X / 2)
    local TargetY = AbsolutePositionBtn.Y + (AbsoluteSizeBtn.Y / 2) + 36


    mousemoveabs(TargetX, TargetY)
    task.wait(1)
    mouse1click()
    RetryCount += 1
  end
end

--#endregion -- Ui elements functions --



--#region -- Titan shifting --
-- The shifting skill sits in hotbar slot UserConfigs.ShiftKey (key 1-5). Its Shift Bar is the
-- player's "Bar" attribute out of "Max_Bar" (100): it fills while dealing damage (0 -> 23 in 20s on
-- the Female Titan raid, 2026-11-02) and can run past the max. A press with a full bar plays a short
-- cutscene; as a titan the bar drains, and at 0 the player jumps out and is human again. The titan
-- skills take over the same HUD hotbar (Top.7.Hotbar, keys 1-5; ReplicatedStorage.Modules.Waves.Hotbar).
-- The game's own check for titan form is a "Shifter" attribute on its cached character, which may be
-- the titan model rather than LocalPlayer.Character, so a draining bar counts as titan form too.
-- The first shifts are traced to boot.txt, since the transformation itself has not been watched yet.
local SHIFT_PRESS_INTERVAL = 3 -- seconds between shift key presses while the bar is full
local SHIFT_CUTSCENE = 2       -- seconds after turning into a titan before attacking (4 stood ~2s too long)
local SHIFT_TRACE_TIME = 40    -- seconds of boot.txt trace after each of the first shift presses
local TitanFormSince = 0
local LastFormCheck, LastShiftPress, ShiftPresses = 0, 0, 0
local LastBar, LastBarDropAt = nil, -math.huge
local ShiftTraceUntil, LastShiftTrace = 0, 0
local TitanSkillKeys: { number } = {}
local TitanSkillIndex, LastTitanSkill = 0, 0

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

-- The hotbar's Key labels (the titan skills use the same slots), falling back to 1-5.
local function ReadTitanSkillKeys(): string
  local texts = {}
  for i = 1, 5 do
    local label = GetPath(Interface, false, "HUD", "Main", "Top", "7", "Hotbar", "Skill_" .. i, "Key", "Key") :: TextLabel?
    local text = label and label.Text
    texts[i] = tostring(text)
    TitanSkillKeys[i] = KeyToVk(text) or (0x30 + i)
  end
  return table.concat(texts, ",")
end

local function GetShiftBar(): (number?, number)
  local ok, bar, max = pcall(function() return LocalPlayer:GetAttribute("Bar"), LocalPlayer:GetAttribute("Max_Bar") end)
  if not ok then return nil, 100 end
  return tonumber(bar), tonumber(max) or 100
end

local function CharacterShifterAttribute(): any
  local ok, value = pcall(function()
    local c = LocalPlayer.Character
    return c and c:GetAttribute("Shifter")
  end)
  return ok and value or nil
end

local function ShiftTrace(why: string)
  pcall(function()
    local c = LocalPlayer.Character
    local hrp = GetPlayerHrp(LocalPlayer)
    local bar, max = GetShiftBar()
    Boot(string.format("shift trace (%s): bar=%s/%s shiftAttr=%s charShifter=%s char=%s parts=%d hrpSize=%s y=%s titanForm=%s",
      why, bar and string.format("%.1f", bar) or "?", tostring(max), tostring(LocalPlayer:GetAttribute("Shift")),
      tostring(CharacterShifterAttribute()), c and c.Name or "nil", c and #c:GetChildren() or 0,
      hrp and tostring(hrp.Size) or "?", hrp and string.format("%.0f", hrp.Position.Y) or "?", tostring(TitanForm)))
  end)
end

-- Polled at most 4 times a second from the farm threads (GetPath yields; never the hover).
local function IsTitanForm(): boolean
  local now = os.clock()
  if now - LastFormCheck < 0.25 then return TitanForm end
  LastFormCheck = now
  local bar = GetShiftBar()
  if bar and LastBar and bar < LastBar - 0.01 then LastBarDropAt = now end
  LastBar = bar
  local Shifted = CharacterShifterAttribute() ~= nil or (now - LastBarDropAt < 1.5 and (bar or 0) > 0)
  if now < ShiftTraceUntil and now - LastShiftTrace >= 2 then LastShiftTrace = now; ShiftTrace("after press") end
  if Shifted ~= TitanForm then
    TitanForm = Shifted
    if Shifted then
      TitanFormSince = now
      if WhatShouldIBeDoing == "refill" then WhatShouldIBeDoing = "attack" end -- the hover only runs while attacking
      FarmStats.Shifts += 1
      Boot(string.format("titan form (%.1fs after shift press %d), hotbar keys %s", now - LastShiftPress, ShiftPresses, ReadTitanSkillKeys()))
    else
      Boot(string.format("human form after %.0fs as a titan", now - TitanFormSince))
    end
    ShiftTrace(Shifted and "became titan" or "became human")
  end
  return TitanForm
end

-- Blade swings block skills, so one press mid-slash does nothing (user, 2026-11-02: it took rapid
-- presses landing in the gaps between swings). With a full bar, stop slashing and spam the key
-- until the bar starts draining or the character turns, for at most SHIFT_BURST seconds.
local SHIFT_BURST = 3
local function TryShift()
  if not UserConfigs.ShiftEnabled or TitanForm then return end
  if os.clock() - LastShiftPress < SHIFT_PRESS_INTERVAL then return end
  -- The 1 spam broke a refill (user, 2026-11-02): never burst while a refill is running. Being out
  -- of supplies no longer blocks it: with 0/3 sets and 0% gas but blades still in hand, no refill
  -- starts, and a full bar sat unused (seen 2026-11-02). A refill stuck for 5s does not block it
  -- either; the refill loop drops itself once the character shifts.
  local now0 = os.clock()
  local Refilling = now0 - RefillLastSeen < 1 and RefillStuckSince ~= nil and now0 - RefillStuckSince < 5
  if WhatShouldIBeDoing ~= "attack" or ReloadingBlades or Refilling then return end
  local bar, max = GetShiftBar()
  if not bar or bar < max then return end
  ShiftPresses += 1
  local slot = math.clamp(math.floor(UserConfigs.ShiftKey), 1, 5)
  if ShiftPresses <= 3 then ShiftTraceUntil = os.clock() + SHIFT_TRACE_TIME end
  local started, taps = os.clock(), 0
  repeat
    Progress()
    TapKey(0x30 + slot)
    taps += 1
    task.wait(0.07)
    local now = GetShiftBar()
  until os.clock() - started > SHIFT_BURST or CharacterShifterAttribute() ~= nil or (now and now < bar - 0.01) or Stopped()
  LastShiftPress = os.clock()
  LastShiftBurstAt = LastShiftPress
  local after = GetShiftBar()
  if ShiftPresses <= 5 then
    Boot(string.format("shift burst %d: key %d x%d in %.1fs, bar %.0f -> %s/%d", ShiftPresses, slot, taps, os.clock() - started, bar,
      after and string.format("%.0f", after) or "?", max))
  end
end

-- One titan skill per TitanSkillDelay, in turn; the game ignores presses still on cooldown.
local function UseTitanSkill()
  if not UserConfigs.TitanSkills or os.clock() - LastTitanSkill < UserConfigs.TitanSkillDelay then return end
  if #TitanSkillKeys == 0 then ReadTitanSkillKeys() end
  LastTitanSkill = os.clock()
  TitanSkillIndex = TitanSkillIndex % #TitanSkillKeys + 1
  TapKey(TitanSkillKeys[TitanSkillIndex])
end

--#endregion -- Titan shifting --



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
    return string.format("%s status=%s kills=%d timeouts=%d form=%s titansAlive=%d nearestTitan=%s target=%s y=%s speed=%s hp=%s targetDist=%s hoverAge=%.1fs doing=%s writes=%.0f/s skipped=%d",
      os.date("%H:%M:%S"), FarmStats.Status, FarmStats.Kills, FarmStats.Timeouts, TitanForm and "titan" or "human", AliveTitans,
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
  while true do
    Progress()
    Tr.step("main", "attack delay")
    task.wait(UserConfigs.AttackDelay)
    Tr.step("main", "kill checks")
    if Stopped() or not UserConfigs.Autofarm then break end
    if not IsTitanAlive(titan) then
      FarmStats.Kills += 1
      print(string.format("[Aotr] %s down after %.1fs", titan.Name:sub(1, 8), os.clock() - StartTime))
      break
    end
    if not IsLocalAlive() then print("[Aotr] died while attacking " .. titan.Name:sub(1, 8)); LogDeath("attacking " .. titan.Name:sub(1, 8)); FarmStats.Status = "dead, waiting to respawn"; break end
    local Shifted = IsTitanForm()
    if not Shifted and AreBladesFullyBroken() then DebugPrint("debug", 3, nil, "KillTitan", "Blades broken"); break end
    -- No per-titan kill timeout (removed at the user's request, 2026-11-03): the farm stays on a
    -- target until it dies. KillTimeout/TitanKillTimeout are no longer read. A titan that never
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
      if Qte.Active then -- a click or Space mid-QTE could count as the wrong key
        FarmStats.Status = "quick time event"
        task.wait(0.05)
        continue
      end
      if Shifted and os.clock() - TitanFormSince < SHIFT_CUTSCENE then
        FarmStats.Status = "shifting"
        task.wait(0.1)
        continue
      end
      if Shifted then
        -- No pull as a titan: the part snaps back to its titan, so the hover walks to it instead.
        Tr.step("main", "titan weak spot")
        local Cache = TitansCache[TitanAddress]
        if Cache then Cache.Info.Strike = GetTitanWeakSpot(titan) end
      else
        Tr.step("main", "pull napes (write)")
        PullNapesTo(titan, UserConfigs.PullAllNapes and PullList or nil)
      end

      Tr.step("main", "slash wait")
      task.wait()
      Tr.step("main", "click")
      mouse1click()
      task.wait(0.03)
      if Shifted then
        FarmStats.Status = "titan attacking"
        Tr.step("main", "titan skill")
        UseTitanSkill()
      else
        Tr.step("main", "space")
        keypress(0x20)
        task.wait(0.03)
        keyrelease(0x20)
        Tr.step("main", "try shift")
        TryShift()
      end
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
    -- A stuck mission keeps a fresh heartbeat (5 hours on 2026-11-02), so after NoKillMinutes
    -- without a kill the character feeds itself to a titan and the run resets. A raid boss takes
    -- minutes to kill, so while one is alive the limit is BossNoKillMinutes.
    local Idle = FarmStats.Status == "paused" or FarmStats.Status == "pressing retry" or FarmStats.Status == "dead, waiting to respawn"
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

    if not UserConfigs.Autofarm then
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
      PressRetry()
      task.wait(3)
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

    Tr.step("main", "blade check")
    if not IsTitanForm() and AreBladesFullyBroken() then
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
  -- The reload spot is the skybox (SafeHeight); a titan parked there got stuck (2026-11-02) while
  -- its bar drained, so in titan form keep hovering over the target, or hold still with none.
  if CurrentRobloxState == "Inactive" and not TitanForm then
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
  if TitanForm and not CurrentTitanTarget then return end

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
  if Stopped() then if RenderConn then RenderConn:Disconnect() end; pcall(StatusCleanup); print("[Aotr] stopped"); return end
  LastHoverAt = os.clock()
  pcall(Tr.flush)
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
local UI = { lib = nil, window = nil, controls = {}, unloading = false }
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
  if UserConfigs.MenuDisabled then Boot("menu disabled (MenuDisabled in aotr_farm.json)"); return end
  local ue, err = loadUE()
  if not ue then
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

  local shifting = main:AddLeftGroupbox("Titan Shifting")
  reg("ShiftEnabled", shifting:AddToggle("ShiftEnabled", { Text = "Auto Shift", Default = UserConfigs.ShiftEnabled,
    Tooltip = "Press the shifting skill when the Shift Bar fills, then fight as the titan",
    Callback = setter("ShiftEnabled") }))
  reg("ShiftKey", shifting:AddSlider("ShiftKey", { Text = "Shift Skill Key", Default = UserConfigs.ShiftKey,
    Min = 1, Max = 5, Rounding = 0, Tooltip = "Hotbar slot (key 1-5) the shifting skill is in",
    Callback = setter("ShiftKey") }))
  reg("TitanSkills", shifting:AddToggle("TitanSkills", { Text = "Use Titan Skills", Default = UserConfigs.TitanSkills,
    Tooltip = "Cycle the five titan skills between punches", Callback = setter("TitanSkills") }))
  reg("TitanSkillDelay", shifting:AddSlider("TitanSkillDelay", { Text = "Skill Delay", Default = math.floor(UserConfigs.TitanSkillDelay * 1000 + 0.5),
    Min = 200, Max = 3000, Rounding = 0, Suffix = " ms", Callback = setter("TitanSkillDelay", 1000) }))
  reg("TitanStrikeDistance", shifting:AddSlider("TitanStrikeDistance", { Text = "Strike Distance", Default = UserConfigs.TitanStrikeDistance,
    Min = 5, Max = 60, Rounding = 0, Suffix = " studs", Tooltip = "How far from the nape (or a boss's marked limb) your titan stands to punch",
    Callback = setter("TitanStrikeDistance") }))
  reg("TitanRetreatHp", shifting:AddSlider("TitanRetreatHp", { Text = "Back Off Below", Default = math.floor(UserConfigs.TitanRetreatHp * 100 + 0.5),
    Min = 0, Max = 90, Rounding = 0, Suffix = " % hp", Tooltip = "Your titan leaves the target for the hover below this health, and returns at the Return value",
    Callback = setter("TitanRetreatHp", 100) }))
  reg("TitanKillTimeout", shifting:AddSlider("TitanKillTimeout", { Text = "Titan Give Up After", Default = UserConfigs.TitanKillTimeout,
    Min = 5, Max = 60, Rounding = 0, Suffix = "s", Callback = setter("TitanKillTimeout") }))

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
    local Text = string.format("AoTR farm:%s  kills:%d  timeouts:%d  shifts:%d  target:%s  |  %s",
      UserConfigs.Autofarm and "ON" or "off", FarmStats.Kills, FarmStats.Timeouts, FarmStats.Shifts, FarmStats.Target, FarmStats.Status)
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

