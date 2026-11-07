-- Game name: Attack on Titans Revolution
-- Game Id: 4658598196
-- Game UniverseId: 4658598196
-- Social places: 13379208636 (Main menu), 14916516914 (Lobby), 14932214603 (Trade hub)
-- Game link: https://www.roblox.com/games/13379208636/Attack-on-Titan-Revolution

-- Script version: 1.0.7

-- Shared watchdog files use Matcha's file workspace, independent of the app.exe location.
if not isfolder("aotr") then makefolder("aotr") end

-- Manual/local execution must stand down before loading the UI or mission services.
-- Main menu, lobby, trade hub: "unloaded" works with the unchanged watcher.
if game.PlaceId == 13379208636 or game.PlaceId == 14916516914 or game.PlaceId == 14932214603 then
  writefile("aotr/heartbeat.txt", "unloaded " .. os.date("%H:%M:%S"))
  return
end



local Stats = {}
local UI = { lib = nil, window = nil, controls = {}, unloading = false, ready = false }
local Qte -- Forward declaration: supplies and combat share the QTE state initialized below.

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
local Recovery = { Blocked = true, CheckedAt = -math.huge, Since = nil, StableAt = nil, Character = nil, Hp = nil, Reason = nil, Braked = false, ReleaseAt = nil }
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
  if Recovery.Blocked then return end
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
  HumanSkills = true,     -- use ready human skills between nape pulling and slashing
  AwakeningEnabled = false, -- opt in to the selected human awakening skill
  AwakeningSlot = 1,      -- human awakening/Rage Mode hotbar slot
  --[====[ Disabled titan shifting settings.
  ShiftEnabled = false,   -- press the titan shifting skill when its Shift Bar can be full
  ShiftKey = 1,           -- hotbar slot (key 1-5) the shifting skill is bound to
  TitanSkills = true,     -- use the five titan skills while shifted
  TitanSkillDelay = 0.8,  -- seconds between titan skill presses (the game enforces cooldowns)
  TitanStrikeDistance = 18, -- studs from the struck part (nape, or a boss's marked limb) that the titan form stands
  TitanRetreatHp = 0.35,  -- fraction of titan health below which the titan form backs off to the hover
  TitanReturnHp = 0.8,    -- fraction it must heal back to before striking again
  TitanKillTimeout = 25,  -- seconds before giving up on a titan while shifted
  ]====]
  NoKillMinutes = 5,      -- minutes without a kill before feeding a titan to reset the run
  BossNoKillMinutes = 20, -- the same while a raid boss is alive (bosses never time out)
  AutoQTE = true,         -- solve visible QTE and grab-escape prompts
  DebugMode = _G.KittyDebug == true -- was `or true`, which forced it on
}
local SETTINGS_FILE = "aotr_farm.json"
local SAVED_KEYS = {
  "Autofarm", "AutoRetry", "AutoReload", "NapeSize", "PullAllNapes", "PullRadius", "PullCount", "MenuDisabled", "KillTimeout", "AttackDelay", "BobAmplitude",
  "HeightNormal", "HeightStall", "HeightAttack", "HeightColossal", "HoverOffsetX", "HoverOffsetZ",
  "NapeOffsetY", "SafeHeight", "DebugMode",
  -- "ShiftEnabled", "ShiftKey", "TitanSkills", "TitanSkillDelay", "TitanStrikeDistance", "TitanRetreatHp", "TitanReturnHp", "TitanKillTimeout", -- Titan shifting disabled.
  "HumanSkills", "AwakeningEnabled", "AwakeningSlot",
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
until TitansFolder:FindFirstChildOfClass("Model") or os.clock() - TitanWaitStart > 2

if TitansFolder:FindFirstChildOfClass("Model") then
  Boot(string.format("world ready after %.1fs", os.clock() - ScriptStart))
else
  Boot("no titans after 2s, starting UI and retry monitor")
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





local TitansCache: { [number]: TitanEntry } = {}
local KnownTitans: { [number]: Instance } = {} -- Childrens of the titans folder
local CharacterCache: { [number]: CharacterCacheType } = {}
local UiCache: UiCacheType = {}


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

-- Offsets ship with the farm: startup never depends on a user's access to an offsets site.
-- Add a separately verified layout for each new Roblox client version before releasing it.
local function GetOffsets(): OffsetsData?
  local versionOk, version = pcall(getrbxversion)
  if not versionOk or type(version) ~= "string" or version == "" then
    Boot("exit: unable to identify Roblox version for bundled offsets")
    warn("[AoTR Normal] Startup stopped: cannot read Roblox client version. See aotr/boot.txt.")
    return nil
  end
  if version == "version-f0ea5da9412f4e35" then
    Boot("using bundled offsets for " .. version)
    return { Offsets = {
      Model = { PrimaryPart = 576 }, BasePart = { Primitive = 376 },
      Primitive = { Position = 212 }, GuiObject = { Visible = 1397, Size = 1272 },
      GuiBase2D = { AbsoluteSize = 0 },
      Humanoid = { HumanoidState = 2216, HumanoidStateID = 32 },
    } }
  end
  Boot("exit: unsupported Roblox version " .. version .. "; bundled offsets update required")
  warn("[AoTR Normal] Startup stopped: unsupported Roblox version " .. version .. ". Update the farm for matching bundled offsets.")
  return nil
end; local OffsetsFake = GetOffsets()

if not OffsetsFake then return end


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

local Supplies = { HudAt = -math.huge, NextReloadAt = 0, Active = nil, KeyDown = false }
-- End supply state.

local CurrentRobloxState = "Active"
local WhatShouldIBeDoing = "attack"
local TitanForm = false -- Shifting disabled; legacy diagnostics and hover guards stay in human mode.
-- local LastShiftBurstAt = -math.huge -- Titan shifting disabled.

local ReloadingBlades: boolean = false





--== Offsets ==--
local Offsets: { [string]: { [string]: number } } = OffsetsFake.Offsets
                                                     
local PrimaryPartOffset = Offsets.Model.PrimaryPart;
local BaseToPrimitiveOffset = Offsets.BasePart.Primitive;
local PrimitivePositionOffset = Offsets.Primitive.Position;
local VisibleOffset = Offsets.GuiObject.Visible;
local SizeOffset = Offsets.GuiObject.Size; -- UDim2: X.Scale float, X.Offset int, Y.Scale, Y.Offset
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


local function IsLocalAlive(): boolean
  if Recovery.Blocked then return false end
  local Humanoid = GetPlayerHumanoid(LocalPlayer); if not Humanoid then return false end
  -- Health reads nil on a humanoid that is being torn down after a death; that crashed the farm.
  local ok, health = pcall(function() return Humanoid.Health end)
  return ok and type(health) == "number" and health > 0
end
-- End local alive check.

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
  if Recovery.Blocked then return end
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
      if Stopped() or Recovery.Blocked or not IsValid(PlayerHrp) then break end
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
  if Recovery.Blocked then return false end
  if not titan or not titan.Parent then return false end

  local TitanCache = TitansCache[titan.Address]; if not TitanCache then return false end
  local LocalPlayerCache = CharacterCache[LocalPlayer.Address]; if not LocalPlayerCache then return false end
  local Hrp = GetPlayerHrp(LocalPlayer); if not Hrp then return false end
  --[====[ Titan-form positioning disabled.
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

  ]====]

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

-- HUD supply state. One float read per 100 ms replaces the blade transparency scan.
function Supplies.Counter(frame, name, kind)
  if not frame then return nil end
  local function parse(label)
    if not label or type(label.Text) ~= "string" then return nil end
    local text = string.gsub(label.Text, "<[^>]*>", "")
    if kind == "sets" then
      local count, maximum = string.match(text, "^%s*(%d+)%s*/%s*(%d+)%s*$")
      count, maximum = tonumber(count), tonumber(maximum)
      if count and maximum and maximum > 0 and count <= maximum then return count end
    else
      local count = tonumber(string.match(text, "^%s*(%d+%.?%d*)%s*%%%s*$"))
      if count and count >= 0 and count <= 100 then return count end
    end
    return nil
  end
  local named = parse(frame:FindFirstChild(name))
  if named ~= nil then return named end
  -- HUD labels can be unnamed after respawn. Read the unique matching direct text child.
  local value, matches = nil, 0
  for _, child in ipairs(frame:GetChildren()) do
    if child.ClassName == "TextLabel" then
      local parsed = parse(child)
      if parsed ~= nil then value, matches = parsed, matches + 1 end
    end
  end
  if matches == 1 then return value end
  return nil
end

function Supplies.ReadHud(force)
  local now = os.clock()
  if not force and Supplies.Hud and now - Supplies.HudAt < 0.1 then return Supplies.Hud end
  local hud = { Unknown = true, SupplyUnknown = true, DurabilityUnknown = true }
  local ok = pcall(function()
    local root = LocalPlayer:FindFirstChild("PlayerGui")
    for _, name in ipairs({"Interface", "HUD", "Main", "Top", "7"}) do
      root = root and root:FindFirstChild(name)
    end
    if not root then return end
    local blades = root:FindFirstChild("Blades")
    hud.Sets = Supplies.Counter(blades, "Sets", "sets")
    hud.Gas = Supplies.Counter(root:FindFirstChild("Gas"), "Percentage", "gas")
    local inner = blades and blades:FindFirstChild("Inner")
    local bar = inner and inner:FindFirstChild("Bar")
    local gradient = bar and bar:FindFirstChild("Gradient")
    -- Matcha does not bind UIGradient.Offset. This layout was measured against this client.
    if not Supplies.VersionChecked then
      local versionOk, version = pcall(getrbxversion)
      Supplies.GradientOffset = versionOk and version == "version-f0ea5da9412f4e35" and 296 or nil
      Supplies.VersionChecked = true
    end
    if gradient and gradient.ClassName == "UIGradient" and Supplies.GradientOffset then
      local x = memory_read("float", gradient.Address + Supplies.GradientOffset)
      if type(x) == "number" and x == x and x >= -0.1501 and x <= 1.001 then hud.Durability = x end
    end
    hud.SupplyUnknown = hud.Sets == nil or hud.Gas == nil
    hud.DurabilityUnknown = hud.Durability == nil
    hud.Unknown = hud.SupplyUnknown or hud.DurabilityUnknown
  end)
  if not ok then hud.Unknown, hud.SupplyUnknown, hud.DurabilityUnknown = true, true, true end
  Supplies.ReadyAt = Supplies.ReadyAt or (now + 2)
  if hud.SupplyUnknown then Supplies.SupplyUnknownSince = Supplies.SupplyUnknownSince or now
  else Supplies.SupplyUnknownSince = nil end
  if hud.DurabilityUnknown then Supplies.DurabilityUnknownSince = Supplies.DurabilityUnknownSince or now
  else Supplies.DurabilityUnknownSince = nil end
  -- A falling set count or rising bar is a reload transition, including a manual reload.
  if (hud.Sets ~= nil and Supplies.LastSets ~= nil and hud.Sets < Supplies.LastSets)
    or (hud.Durability ~= nil and Supplies.LastDurability ~= nil and hud.Durability > Supplies.LastDurability + 0.001) then
    Supplies.SettleUntil = now + 1
  end
  if hud.Sets ~= nil then Supplies.LastSets = hud.Sets end
  if hud.Durability ~= nil then Supplies.LastDurability = hud.Durability end
  Supplies.Hud, Supplies.HudAt = hud, now
  return hud
end

local function AreBladesFullyBroken(): boolean
  local value = Supplies.ReadHud().Durability
  -- -0.15 is represented slightly below -0.15 as a float; allow only rounding tolerance.
  return value ~= nil and value >= -0.1501 and value <= 0
end

-- Once all blades are gone, only a full spare-set refill releases combat.
function Supplies.CombatLocked()
  local hud = Supplies.ReadHud()
  if hud.Sets == 0 and AreBladesFullyBroken() then Supplies.EmptyLocked = true end
  if Supplies.EmptyLocked and hud.Sets == 3 then Supplies.EmptyLocked = false end
  return Supplies.EmptyLocked == true
end

local function DoINeedToRefill(): (boolean, string?)
  local hud = Supplies.ReadHud()
  local now = os.clock()
  if Supplies.CombatLocked() then return true, "empty blades: combat locked until 3/3" end
  if hud.Gas == 0 then return true, "gas 0%" end
  if Supplies.SupplyUnknownSince and now - Supplies.SupplyUnknownSince >= 2 then
    return true, "supply HUD unreadable"
  end
  if Supplies.DurabilityUnknownSince and now - Supplies.DurabilityUnknownSince >= 2 then
    return true, "durability HUD unreadable"
  end
  return false
end

function Supplies.Action()
  if Supplies.Active or WhatShouldIBeDoing ~= "attack" then return nil end
  if not isrbxactive() or Recovery.Blocked or Qte.Active or UI.IsInteracting() then return nil end
  Supplies.ReadHud()
  local now = os.clock()
  if now < Supplies.ReadyAt or now < (Supplies.SettleUntil or 0) then return nil end
  local refill, reason = DoINeedToRefill()
  if refill then return "refill", reason end
  if now >= Supplies.NextReloadAt and AreBladesFullyBroken() then return "reload", "empty blades" end
  return nil
end
-- End supply HUD.

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
  if Recovery.Blocked then return end
  reason = reason or "stuck refilling"
  DebugPrint("warn", 0, nil, nil, reason .. ", letting a titan kill us.")
  Boot(reason .. ", feeding a titan")
  WhatShouldIBeDoing = "dying" -- the RenderStepped hover only runs while attacking
  CurrentTitanTarget = nil
  FarmStats.Target = "none"
  FarmStats.Status = reason .. ", feeding a titan"

  local Started = os.clock()
  local LastTp = 0

  while not Stopped() and not Recovery.Blocked and os.clock() - Started < 30 do
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

  WhatShouldIBeDoing = "attack"
end


function Supplies.CanContinue()
  return not Stopped() and not Recovery.Blocked and UserConfigs.AutoReload
    and isrbxactive() and not Qte.Active and not UI.IsInteracting()
end

function Supplies.HoldReload()
  if Supplies.Active == "refill" and Supplies.RefillRoot then
    if os.clock() - Supplies.HoverAt < 0.1 then return end
    Supplies.HoverAt = os.clock()
    local velocity = Supplies.RefillRoot.AssemblyLinearVelocity
    if os.clock() < (Supplies.RefillBrakeUntil or 0) then
      -- Brief arrival brake catches residual upward/downward momentum and bounce.
      if velocity and velocity.Magnitude > 0.1 then
        Supplies.RefillRoot.AssemblyLinearVelocity = Vector3Zero
        HeavyWrites += 1
      end
      return
    end
    -- Brake sliding without cancelling gravity or moving the player off the floor.
    if velocity and (math.abs(velocity.X) > 0.1 or math.abs(velocity.Z) > 0.1) then
      Supplies.RefillRoot.AssemblyLinearVelocity = Vector3New(0, velocity.Y, 0)
      HeavyWrites += 1
    end
    return
  end
  if Supplies.Active ~= "reload" or not Supplies.ReloadRoot then return end
  if os.clock() - Supplies.HoverAt < 0.1 then return end
  Supplies.HoverAt = os.clock()
  Supplies.ReloadRoot.CFrame = SafePosNow()
  Supplies.ReloadRoot.AssemblyLinearVelocity = Vector3Zero
  HeavyWrites += 2
end

function Supplies.PressR()
  if not Supplies.CanContinue() then return false end
  keypress(0x52); Supplies.KeyDown = true
  local untilAt = os.clock() + 0.5
  repeat
    Progress()
    Supplies.HoldReload()
    task.wait(0.05)
  until os.clock() >= untilAt or not Supplies.CanContinue()
  keyrelease(0x52); Supplies.KeyDown = false
  return Supplies.CanContinue()
end

-- Discover world trigger parts once, then read their current positions per refill.
function Supplies.FindRefillStations()
  if Supplies.Stations and os.clock() - Supplies.StationsAt < 30 then return Supplies.Stations end
  local stations, seen = {}, {}
  for index, part in ipairs(Workspace:GetDescendants()) do
    if index % 1000 == 0 then task.wait() end
    if part.Name == "Refill" and (part.ClassName == "Part" or part.ClassName == "MeshPart" or part.ClassName == "UnionOperation") then
      local parent = part.Parent
      if parent and parent.Name == "GasTanks" and not seen[part.Address] then
        seen[part.Address] = true
        stations[#stations + 1] = part
      end
    end
  end
  Supplies.Stations, Supplies.StationsAt = stations, os.clock()
  return stations
end

function Supplies.SelectRefillStation()
  local stations = Supplies.FindRefillStations()
  if #stations == 0 then return nil end
  local threats = {}
  for _, titan in pairs(KnownTitans) do
    if IsTitanAlive(titan) then
      local root = GetTitanHrp(titan)
      if root then threats[#threats + 1] = root.Position end
    end
  end
  local playerRoot = GetPlayerHrp(LocalPlayer)
  local origin = playerRoot and playerRoot.Position
  local best, bestPosition, bestCount, bestClearance, bestTravel
  for _, part in ipairs(stations) do
    if part.Parent then
      local position = part.Position
      if position and position.X == position.X and position.Y == position.Y and position.Z == position.Z then
        local count, clearance = 0, math.huge
        for _, threat in ipairs(threats) do
          local distance = (threat - position).Magnitude
          if distance < 180 then count += 1 end
          clearance = math.min(clearance, distance)
        end
        local travel = origin and (origin - position).Magnitude or 0
        if not best or count < bestCount
          or (count == bestCount and clearance > bestClearance)
          or (count == bestCount and clearance == bestClearance and travel < bestTravel) then
          best, bestPosition, bestCount, bestClearance, bestTravel = part, position, count, clearance, travel
        end
      end
    end
  end
  if best then
    GasTankModel, GasTankPosition = best.Parent, bestPosition
    Boot(string.format("refill station selected: %d candidates, %d titans within 180 studs, nearest=%.0f destination=%s",
      #stations, bestCount, bestClearance, tostring(bestPosition)))
  end
  return bestPosition
end

function Supplies.TankPosition()
  local selected = Supplies.SelectRefillStation()
  if selected then return selected end
  -- Keep the previous map-specific fallback for stations without a Refill trigger.
  if GasTankModel and not GasTankModel.Parent then GasTankModel, GasTankPosition = nil, nil end
  if GasTankPosition then return GasTankPosition end
  if not GasTankModel then HandleDifferentGasTankPaths() end
  if not GasTankModel then return nil end
  local part = GasTankModel:FindFirstChild("Refill") or GasTankModel:FindFirstChild("Primary") or GasTankModel.PrimaryPart
  if part then GasTankPosition = part.Position; return GasTankPosition end
  local address = memory_read("uintptr_t", GasTankModel.Address + PrimaryPartOffset)
  if not address or address == 0 then return nil end
  local primitive = memory_read("uintptr_t", address + BaseToPrimitiveOffset)
  if not primitive or primitive == 0 then return nil end
  GasTankPosition = Vector3New(memory_read("float", primitive + PrimitivePositionOffset),
    memory_read("float", primitive + PrimitivePositionOffset + 4),
    memory_read("float", primitive + PrimitivePositionOffset + 8))
  return GasTankPosition
end

local function HandleAllReloads()
  if not Supplies.CanContinue() then return false end
  local action, reason = Supplies.Action()
  if not action then return false end
  local hrp = GetPlayerHrp(LocalPlayer)
  if not IsValid(hrp) then return false end
  local before = Supplies.ReadHud(true)
  local freshAction, freshReason = Supplies.Action()
  if freshAction ~= action then return false end
  reason = freshReason or reason
  -- Finding a station can yield. Keep the combat safety hover running until the
  -- destination exists instead of disabling it and falling during that lookup.
  local refillPosition
  if action == "refill" then
    refillPosition = Supplies.TankPosition()
    if not refillPosition or refillPosition.X ~= refillPosition.X or refillPosition.Y ~= refillPosition.Y
      or refillPosition.Z ~= refillPosition.Z then
      Boot("refill skipped: station position unavailable; refill remains pending")
      return false
    end
    if not Supplies.CanContinue() then return false end
    hrp = GetPlayerHrp(LocalPlayer)
    if not IsValid(hrp) then return false end
  end
  local combatVelocity = hrp.AssemblyLinearVelocity
  Supplies.Active = action
  ReloadingBlades = action == "reload"
  WhatShouldIBeDoing = action
  CurrentTitanTarget = nil
  FarmStats.Target = "none"
  FarmStats.Status = action == "reload" and "reloading" or "refilling"
  Boot(action .. " started: reason=" .. tostring(reason) .. " gradient=" .. tostring(before.Durability) .. " sets=" .. tostring(before.Sets) .. " gas=" .. tostring(before.Gas))
  local ok, success = pcall(function()
    local nextRefillPress
    if action == "reload" then
      -- Only an actual reload moves to the reload hover. Combat stays paused until confirmed.
      Tr.step("reload", "tp to sky (write)")
      Supplies.ReloadRoot, Supplies.HoverAt = hrp, -math.huge
      Supplies.HoldReload()
    else
      Supplies.RefillRoot, Supplies.HoverAt = hrp, -math.huge
      -- Brake before relocating, then clear any motion recreated by the teleport.
      hrp.AssemblyLinearVelocity = Vector3Zero
      HeavyWrites += 1
      Boot("refill teleport 1: from=" .. tostring(hrp.Position) .. " destination=" .. tostring(refillPosition))
      Tr.step("main", "refill: tp to gas tank (write)")
      hrp.Position = refillPosition
      hrp.AssemblyLinearVelocity = Vector3Zero
      Supplies.RefillBrakeUntil = os.clock() + 0.15
      HeavyWrites += 2
      local arriveBy = os.clock() + 0.5
      repeat
        if not Supplies.CanContinue() then return false end
        Progress()
        Supplies.HoldReload()
        task.wait(0.05)
      until os.clock() >= arriveBy
      Boot("refill teleport 1 settled: position=" .. tostring(hrp.Position) .. " velocity=" .. tostring(hrp.AssemblyLinearVelocity))
      -- Re-center after the drop, preserving the height reached naturally instead
      -- of lifting the character back into a hover above the station.
      if not Supplies.CanContinue() then return false end
      -- Titans move while we land. Re-evaluate before committing to the station.
      refillPosition = Supplies.TankPosition() or refillPosition
      hrp.AssemblyLinearVelocity = Vector3Zero
      local landed = hrp.Position
      local nearStation = (landed - refillPosition).Magnitude <= 15
        and math.abs(landed.Y - refillPosition.Y) <= 6
      local secondPosition = nearStation and Vector3New(refillPosition.X, landed.Y, refillPosition.Z) or refillPosition
      Tr.step("main", "refill: second tp after drop (write)")
      hrp.Position = secondPosition
      hrp.AssemblyLinearVelocity = Vector3Zero
      Supplies.RefillBrakeUntil = os.clock() + 0.15
      Supplies.HoverAt = -math.huge
      HeavyWrites += 3
      arriveBy = os.clock() + 0.5
      repeat
        if not Supplies.CanContinue() then return false end
        Progress()
        Supplies.HoldReload()
        task.wait(0.05)
      until os.clock() >= arriveBy
      local arrived = hrp.Position
      Boot("refill teleport 2 settled: position=" .. tostring(arrived) .. " destination=" .. tostring(secondPosition))
      if (arrived - refillPosition).Magnitude > 15 then
        Boot("refill aborted: teleport did not reach station")
        return false
      end
    end
    if not Supplies.PressR() then return false end
    nextRefillPress = os.clock() + 1
    local deadline = os.clock() + (action == "reload" and 4 or 6)
    repeat
      Progress()
      if not Supplies.CanContinue() then return false end
      Supplies.HoldReload()
      local hud = Supplies.ReadHud(true)
      if action == "reload" then
        -- The HUD tweens back to full; do not resume swings partway through that animation.
        if hud.Durability and hud.Durability >= 0.99 then return true end
      elseif hud.Sets == 3 and hud.Gas and hud.Gas > 0 then
        return true -- Partial spare sets or gas alone do not confirm a blade refill.
      end
      if action == "refill" and os.clock() >= nextRefillPress
        and os.clock() >= (Supplies.SettleUntil or 0) then
        -- ReadHud tracks rising durability gradients. Let a blade reload finish
        -- before pressing R again; continue refilling until the counter is 3/3.
        -- Entry into the station can lag behind the teleport. Retry input instead of
        -- spending the entire deadline watching a missed first press. Leave a player
        -- who stayed in place alone so movement cannot restart the refill animation.
        if not Supplies.PressR() then return false end
        nextRefillPress = os.clock() + 1
      end
      task.wait(0.1)
    until os.clock() >= deadline
    return false
  end)
  if Supplies.KeyDown then pcall(keyrelease, 0x52); Supplies.KeyDown = false end
  Supplies.Active, Supplies.ReloadRoot = nil, nil
  Supplies.RefillRoot = nil
  Supplies.RefillBrakeUntil = nil
  ReloadingBlades = false
  WhatShouldIBeDoing = "attack"
  FarmStats.Status = Supplies.CombatLocked() and "waiting for refill" or "attacking"
  -- Supply holds brake the character. Preserve combat momentum when the game's
  -- movement controller still holds it at zero afterward; damage depends on speed.
  if combatVelocity and combatVelocity.Magnitude > 10 and combatVelocity.Magnitude < 5000
    and not Supplies.CombatLocked() and UserConfigs.Autofarm and Supplies.CanContinue() and IsLocalAlive()
    and IsValid(hrp) then
    local velocity = hrp.AssemblyLinearVelocity
    if velocity and velocity.Magnitude < 1 then
      hrp.AssemblyLinearVelocity = combatVelocity
      HeavyWrites += 1
    end
  end
  if action == "reload" then
    Supplies.SettleUntil = os.clock() + 1
    Supplies.NextReloadAt = os.clock() + (ok and success and 0.25 or 3)
  end
  Boot(action .. (ok and success and " confirmed" or (Supplies.CombatLocked() and " failed; combat locked, refill pending" or " failed; resuming farming")) .. (not ok and (": " .. tostring(success)) or ""))
  return true
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

  -- This is also called from RenderStepped, where GetPath cannot yield.
  local interface = PlayerGui:FindFirstChild("Interface")
  RewardsFrame = interface and interface:FindFirstChild("Rewards"); if not RewardsFrame then return false end

  UiCache.RewardsFrame = RewardsFrame
  return IsObjectVisible(RewardsFrame)
end


local RetryCount = 0

local function PressRetry(): boolean
  if not IsRetryVisible() or not isrbxactive() or Stopped() then return false end
  local button = GetPath(PlayerGui, false, "Interface", "Rewards", "Main", "Info", "Main", "Buttons", "Retry")
  local title = button and button:FindFirstChild("Title")
  if title and string.find(string.upper(title.Text), "STARTING", 1, true) then return true end
  -- Primary retry path requested by the user: UI navigation, then D, D, Enter.
  -- Guard each step so a focus change cannot send the rest into another app.
  local function tap(vk, held, after)
    if Stopped() or not isrbxactive() or not IsRetryVisible() then return false end
    keypress(vk)
    task.wait(held)
    pcall(keyrelease, vk)
    if Stopped() or not isrbxactive() then return false end
    task.wait(after)
    return not Stopped() and isrbxactive() and IsRetryVisible()
  end
  RetryCount += 1
  Boot(string.format("retry navigation %d: backslash D D Enter", RetryCount))
  if not tap(0xDC, 0.3, 1.0) then return false end
  if not tap(0x44, 0.2, 0.4) then return false end
  if not tap(0x44, 0.2, 0.4) then return false end
  if not tap(0x0D, 0.3, 0.6) then return false end
  return title and string.find(string.upper(title.Text), "STARTING", 1, true) ~= nil or false
end

--#endregion -- Ui elements functions --



--[====[ Titan shifting disabled; retained for reference.
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
  text = string.upper((string.gsub(text, "<[^>]*>", "")))
  text = string.gsub(text, "^%s*(.-)%s*$", "%1")
  local named = { SPACE = 0x20, SPACEBAR = 0x20, ENTER = 0x0D, RETURN = 0x0D,
    LEFT = 0x25, UP = 0x26, RIGHT = 0x27, DOWN = 0x28 }
  if named[text] then return named[text] end
  if #text ~= 1 then return nil end
  local b = string.byte(text)
  return ((b >= 0x30 and b <= 0x39) or (b >= 0x41 and b <= 0x5A)) and b or nil
end
-- End prompt key mapping.

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
  -- Do not send shift keys during a bounded reload or refill action.
  local Refilling = Supplies.Active == "refill"
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
]====]

--#region -- Human skills --
local function TapKey(vk: number)
  keypress(vk)
  task.wait(0.03)
  keyrelease(vk)
end

-- "Q" -> 0x51, "3" -> 0x33; anything else (placeholder "Key", "LMB") -> nil.
local function KeyToVk(text: string?): number?
  if type(text) ~= "string" then return nil end
  text = string.upper((string.gsub(text, "<[^>]*>", "")))
  text = string.gsub(text, "^%s*(.-)%s*$", "%1")
  local named = { SPACE = 0x20, SPACEBAR = 0x20, ENTER = 0x0D, RETURN = 0x0D,
    LEFT = 0x25, UP = 0x26, RIGHT = 0x27, DOWN = 0x28 }
  if named[text] then return named[text] end
  if #text ~= 1 then return nil end
  local b = string.byte(text)
  return ((b >= 0x30 and b <= 0x39) or (b >= 0x41 and b <= 0x5A)) and b or nil
end
-- End prompt key mapping.

-- A skill succeeds when its hotbar countdown starts. Tap it between slashes until that
-- happens, then wait 2.5 seconds before trying another. The awakening slot is controlled
-- by the Bar attribute: press once at full charge and never press again while it drains.
Stats.HumanSkills = { LastSuccess = -math.huge, LastCheck = -math.huge, LastTap = -math.huge,
  NextSlot = 1, Pending = nil, PendingSince = 0, RetryAfter = {}, LastBar = nil,
  AwakeningActive = false, Slots = {}, Labels = {}, LabelSince = {} }
function Stats.UseHumanSkill(burst: boolean?): boolean
  if not UserConfigs.HumanSkills or not UserConfigs.Autofarm or Stopped() or not IsLocalAlive()
    or not isrbxactive() or Recovery.Blocked or Qte.Active or Supplies.Active
    or WhatShouldIBeDoing ~= "attack" or UI.IsInteracting() then return false end
  local character = LocalPlayer.Character
  if character and character:GetAttribute("Shifter") ~= nil then return false end
  if burst then return Stats.Colossal and Stats.Colossal.UseReadySkills() or false end
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
  if not UserConfigs.AwakeningEnabled and state.Pending == awakening then
    state.Pending = nil
    state.NextSlot = awakening % 5 + 1
  end
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
    if now - state.PendingSince > (burst and 0.3 or 8) or not vk then
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
  if now - state.LastSuccess < (burst and 0.15 or 2.5) then return false end
  for offset = 0, 4 do
    local slot = (state.NextSlot + offset - 1) % 5 + 1
    local canAwaken = slot ~= awakening or (UserConfigs.AwakeningEnabled and ((burst and (not bar or not max)) or (bar and max and max > 0 and bar >= max - 0.5 and not state.AwakeningActive)))
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
Qte = {
  HIT_BAND = 0.06,    -- press when the Timing scale is within this of 1
  STILL_PRESS = 0.35, -- seconds of an unmoving Timing before pressing anyway
  Frame = nil, Timing = nil, Key = nil,
  Active = false,
  Since = 0, PromptAt = 0, PressedAt = nil, ReleaseAt = nil, Vk = nil, PromptKey = nil,
  LastScale = nil, LastMove = 0,
  Trace = {},
  Count = 0,
  Grab = { Active = false, ScannedAt = -math.huge, SeenAt = -math.huge },
}

-- Called from a farm thread (GetPath yields).
local LastQteLookup = 0
local function FindQteUi()
  if not UserConfigs.AutoQTE then return end -- the menu's Auto Quick Time Events toggle
  if Qte.Frame and Qte.Frame.Parent and Qte.Key and Qte.Key.Parent then return end
  -- Shared QTE/grab prompt; find it from the yielding main loop, not the render callback.
  if os.clock() - LastQteLookup < 2 then return end
  LastQteLookup = os.clock()
  Qte.Frame = GetPath(Interface, false, "QTE")
  Qte.Timing = Qte.Frame and GetPath(Qte.Frame, false, "Main", "Timing")
  Qte.Key = Qte.Frame and GetPath(Qte.Frame, false, "Main", "Key")
end

-- Ordinary titan grabs use Interface.Buttons, independently of the raid QTE.
-- Scan the current children: prompts can be destroyed/recreated and keys can repeat.
function Qte.GrabTick(now)
  local grab = Qte.Grab
  if now - grab.ScannedAt < 0.05 then return grab.Active end
  grab.ScannedAt = now
  local buttons = Interface and Interface:FindFirstChild("Buttons")
  local prompt, label, count = nil, nil, 0
  if buttons and buttons.Parent and IsObjectVisible(buttons) then
    for _, button in ipairs(buttons:GetChildren()) do
      local main = button:FindFirstChild("Main")
      local key = main and main:FindFirstChild("Key")
      if key and IsObjectVisible(button) and IsObjectVisible(main) and IsObjectVisible(key) then
        prompt, label, count = button, key, count + 1
      end
    end
  end
  if count == 0 then
    grab.Id, grab.Text, grab.PressedAt = nil, nil, nil
    -- Keep combat paused across the brief gap between successive prompts.
    grab.Active = now - grab.SeenAt < 0.3
    return grab.Active
  end
  grab.Active, grab.SeenAt = true, now
  -- Multiple visible prompts have no known ordering; never invent a sequence.
  if count ~= 1 then return true end
  local text = label.Text
  if grab.Id ~= prompt.Address or grab.Text ~= text then
    grab.Id, grab.Text, grab.PressedAt = prompt.Address, text, nil
  end
  if not isrbxactive() or Qte.ReleaseAt then return true end
  local vk = KeyToVk(text)
  -- Retry an unchanged prompt slowly if the game did not accept the first press.
  -- There is no sequence length or total press limit.
  if vk and (not grab.PressedAt or now - grab.PressedAt >= 0.35) then
    grab.PressedAt = now
    Qte.Vk = vk
    pcall(keypress, vk)
    Qte.ReleaseAt = now + 0.05
    Boot("grab escape key: " .. tostring(text))
  end
  return true
end

local function QteTick()
  local now = os.clock()
  if Qte.ReleaseAt and now >= Qte.ReleaseAt then pcall(keyrelease, Qte.Vk); Qte.ReleaseAt = nil end
  -- Switched off mid-QTE, Active would stay set and hold KillTitan in "quick time event".
  if not UserConfigs.AutoQTE then
    if Qte.ReleaseAt and Qte.Vk then pcall(keyrelease, Qte.Vk) end
    Qte.ReleaseAt, Qte.Active, Qte.PressedAt = nil, false, nil
    Qte.Grab.Active, Qte.Grab.SeenAt, Qte.Grab.ScannedAt = false, -math.huge, -math.huge
    Qte.Grab.Id, Qte.Grab.Text, Qte.Grab.PressedAt = nil, nil, nil
    return
  end
  if Qte.GrabTick(now) then
    if not Qte.Active then Qte.Since, Qte.Trace = now, {} end
    Qte.Active = true
    Qte.LastScale, Qte.PromptKey, Qte.PressedAt = nil, nil, nil
    return
  end
  if not Qte.Frame or not Qte.Frame.Parent then Qte.Active = false; return end
  local visible = IsObjectVisible(Qte.Frame)
  if not visible then
    if Qte.Active then
      Qte.Active, Qte.PressedAt, Qte.LastScale = false, nil, nil
      Qte.Count += 1
      if Qte.Count <= 5 then Boot(string.format("QTE %d over after %.2fs: %s", Qte.Count, now - Qte.Since, table.concat(Qte.Trace, " "))) end
    end
    return
  end
  local text = Qte.Key and Qte.Key.Text
  if not Qte.Active then Qte.Since, Qte.Trace = now, {} end
  if not isrbxactive() then Qte.Active = true; Qte.PressedAt = nil; return end
  -- Button-only escape prompts have no animated Timing frame. Repeat only the displayed key.
  if not Qte.Timing or not Qte.Timing.Parent then
    Qte.Active = true
    if Qte.ReleaseAt then return end
    local vk = KeyToVk(text)
    if vk and (not Qte.PressedAt or now - Qte.PressedAt >= 0.4) then
      Qte.Vk, Qte.PressedAt = vk, now
      pcall(keypress, vk); Qte.ReleaseAt = now + 0.05
    end
    return
  end
  local scale = memory_read("float", Qte.Timing.Address + SizeOffset) -- Size.X.Scale
  -- One QTE is a chain of prompts (16s on the Female Titan raid): Timing shrinks 5 -> 1 in ~0.45s,
  -- then jumps back up, maybe with a new key. Each jump or key change is a new prompt to answer.
  local newPrompt = Qte.Active and ((Qte.LastScale and scale > Qte.LastScale + 0.5) or text ~= Qte.PromptKey)
  if not Qte.Active or newPrompt then
    if Qte.ReleaseAt and Qte.Vk then pcall(keyrelease, Qte.Vk); Qte.ReleaseAt = nil end
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

-- Character state is sampled at startup and continuously; damage invalidates cached parts.
-- Do not fight a grab/ragdoll by teleporting its root. Give the game time to restore control.
-- Read the actual native humanoid state using this client's loaded offsets.
-- The character's Ragdoll attribute is not sufficient evidence of an active ragdoll.
function Recovery.ReadState(humanoid)
  local fields = Offsets.Humanoid
  if not humanoid or not fields or type(fields.HumanoidState) ~= "number"
    or type(fields.HumanoidStateID) ~= "number" then return nil end
  local ok, value = pcall(function()
    local pointer = memory_read("uintptr_t", humanoid.Address + fields.HumanoidState)
    if type(pointer) ~= "number" or pointer < 65536 or pointer >= 140737488355328 then return nil end
    local state = memory_read("int", pointer + fields.HumanoidStateID)
    if type(state) == "number" and state >= 0 and state <= 18 then return state end
  end)
  return ok and value or nil
end

function Recovery.Tick()
  local now = os.clock()
  if Recovery.ReleaseAt and now >= Recovery.ReleaseAt then
    pcall(keyrelease, 0x20); Recovery.ReleaseAt = nil
  end
  if now - Recovery.CheckedAt < 0.2 then return end
  Recovery.CheckedAt = now
  if not UserConfigs.Autofarm then Recovery.Blocked = false; Recovery.Since = nil; return end
  -- Rewards intentionally has no playable character. Let Retry own this state,
  -- rather than publishing a recovery marker that restarts Matcha mid-click.
  if UserConfigs.AutoRetry and IsRetryVisible() then
    Recovery.Blocked, Recovery.Since, Recovery.Reason, Recovery.StableAt = false, nil, nil, nil
    CurrentTitanTarget = nil
    FarmStats.Target, FarmStats.Status = "none", "pressing retry"
    Progress() -- still honors the bounded retry-stuck watchdog deadline
    return
  end
  local character = LocalPlayer.Character
  local address = character and character.Address
  local humanoid = character and GetHumanoid(character)
  local root = character and GetHrp(character)
  local ok, hp = pcall(function() return humanoid and humanoid.Health end)
  if not ok then hp = nil end
  local damaged = address == Recovery.Character and type(hp) == "number" and type(Recovery.Hp) == "number" and hp < Recovery.Hp - 0.01
  if address ~= Recovery.Character or damaged then
    local cache = CharacterCache[LocalPlayer.Address]
    if cache then cache.Character, cache.Hrp, cache.Humanoid = character, nil, nil end
    if damaged then Boot(string.format("damage %.1f -> %.1f; checking character state", Recovery.Hp, hp)) end
  end
  if address ~= Recovery.Character then
    Recovery.Since, Recovery.StableAt, Recovery.Braked = nil, nil, false
  end
  Recovery.Character, Recovery.Hp = address, hp
  local nativeState = Recovery.ReadState(humanoid)
  Recovery.NativeState = nativeState
  local reason
  if not character or not character.Parent or not root or not root.Parent or type(hp) ~= "number" then
    reason = "waiting for character"
  elseif hp <= 0 then
    reason = "dead character"
  elseif not TitanForm and character:GetAttribute("Shifter") == nil and (not character:FindFirstChild("Head") or not character:FindFirstChild("UpperTorso")) then
    reason = "incomplete character body"
  elseif Qte.Active then
    reason = "escape / quick time event"
  elseif nativeState == 0 or nativeState == 1 or nativeState == 2 or nativeState == 14 then
    reason = "ragdoll"
  end
  if reason then
    if not Recovery.Blocked or not Recovery.Since then
      Recovery.Since = now
      Recovery.Braked = false
      Heartbeat("recovering") -- one marker: its age measures the whole recovery attempt
    end
    if Recovery.Reason ~= reason then Boot("character recovery: " .. reason) end
    Recovery.Blocked, Recovery.Reason, Recovery.StableAt = true, reason, nil
    CurrentTitanTarget = nil
    FarmStats.Target, FarmStats.Status = "none", "recovering: " .. reason
    -- One brake per episode, only for a real ragdoll; never teleport or force attributes.
    if reason == "ragdoll" and not Recovery.Braked and root then
      Recovery.Braked = true
      pcall(function() root.AssemblyLinearVelocity = Vector3Zero end)
    end
    return
  end
  if Recovery.Blocked then
    Recovery.StableAt = Recovery.StableAt or now
    if now - Recovery.StableAt < 0.4 then return end
    Boot("character recovery complete; resuming combat")
    if Recovery.Reason == "ragdoll" and isrbxactive() and not Qte.Active then
      pcall(keypress, 0x20); Recovery.ReleaseAt = now + 0.05
    end
    Recovery.Blocked, Recovery.Since, Recovery.Reason = false, nil, nil
    if type(FarmStats.Status) == "string" and string.match(FarmStats.Status, "^recovering:") then
      FarmStats.Status = "resuming combat"
    end
    LastProgress = now
    Heartbeat("farming")
  end
end
-- End character recovery monitor.





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
    if Recovery.Blocked then break end
    if not IsLocalAlive() then print("[Aotr] died while attacking " .. titan.Name:sub(1, 8)); LogDeath("attacking " .. titan.Name:sub(1, 8)); FarmStats.Status = "dead, waiting to respawn"; break end
    -- local Shifted = IsTitanForm() -- Titan shifting disabled.
    if Supplies.CombatLocked() or (UserConfigs.AutoReload and Supplies.Action()) then DebugPrint("debug", 3, nil, "KillTitan", "Blades broken"); break end
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
      if UI.IsInteracting() then FarmStats.Status = "editing settings"; task.wait(0.1); continue end
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
      --[====[ Titan-form attack path disabled.
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

      ]====]
      Tr.step("main", "pull napes (write)")
      PullNapesTo(titan, UserConfigs.PullAllNapes and PullList or nil)

      Tr.step("main", "human skills")
      Stats.UseHumanSkill()

      Tr.step("main", "slash wait")
      task.wait()
      Tr.step("main", "click")
      if UI.IsInteracting() then continue end
      if Recovery.Blocked then continue end
      if Supplies.CombatLocked() then continue end
      mouse1click()
      task.wait(0.03)
      --[====[ Titan skills and automatic shift attempts disabled.
      if Shifted then
        FarmStats.Status = "titan attacking"
        Tr.step("main", "titan skill")
        UseTitanSkill()
      else
        Tr.step("main", "space")
        if UI.IsInteracting() then continue end
      keypress(0x20)
        task.wait(0.03)
        keyrelease(0x20)
        Tr.step("main", "try shift")
        TryShift()
      end
      ]====]
      Tr.step("main", "space")
      if UI.IsInteracting() then continue end
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
    -- A stuck mission keeps a fresh heartbeat (5 hours on 2026-11-02), so after NoKillMinutes
    -- without a kill the character feeds itself to a titan and the run resets. A raid boss takes
    -- minutes to kill, so while one is alive the limit is BossNoKillMinutes.
    local Idle = Recovery.Blocked or Supplies.CombatLocked() or FarmStats.Status == "paused" or FarmStats.Status == "pressing retry" or FarmStats.Status == "dead, waiting to respawn"
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
      RetryScreenSince = isrbxactive() and (RetryScreenSince or os.clock()) or nil
      FarmStats.Status = "pressing retry"
      DebugPrint("debug", nil, nil, nil, "Detected that the retry button is visible.")
      PressRetry()
      task.wait(3)
      continue
    end
    RetryScreenSince = nil

    Recovery.Tick()
    if Recovery.Blocked then
      CurrentTitanTarget = nil
      FarmStats.Status = "recovering: " .. (Recovery.Reason or "checking character")
      task.wait(0.2)
      continue
    end

    if not IsLocalAlive() then
      CurrentTitanTarget = nil
      -- After Retry the teleport removes the character (health unreadable), which is not a death.
      if FarmStats.Status ~= "dead, waiting to respawn" and FarmStats.Status ~= "starting" and FarmStats.Status ~= "pressing retry" then LogDeath("main loop, was " .. FarmStats.Status) end
      FarmStats.Status = "dead, waiting to respawn"
      task.wait(1)
      continue
    end

    Tr.step("main", "blade check")
    -- Titan-form reload exemption disabled; this is the human combat path.
    if UserConfigs.AutoReload and HandleAllReloads() then
      continue
    end

    if Supplies.CombatLocked() then
      CurrentTitanTarget = nil
      FarmStats.Target, FarmStats.Status = "none", "waiting for refill"
      -- Keep WhatShouldIBeDoing="attack" so the existing no-target safety hover
      -- stays active. Recovery/QTE and the next refill attempt still run above.
      task.wait(0.2)
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
  if Recovery.Blocked then return end
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
  local stateOk, stateErr = pcall(Recovery.Tick)
  if not stateOk then
    if not Recovery.Since then Recovery.Since = os.clock(); Heartbeat("recovering") end
    Recovery.Blocked = true
    if os.clock() - LastHoverError > 5 then LastHoverError = os.clock(); Boot("character state error: " .. tostring(stateErr)) end
  end
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
local KEYS = { farm = 0x75, unload = 0x23 } -- F6, End

-- Center once after the camera supplies real dimensions; never use a zero viewport.
function UI.CenterWindow(win)
  if not win or not win._aotrCenterPending then return false end
  if win.Dragging then win._aotrCenterPending = false; return false end
  local ok, viewport = pcall(function()
    local camera = game:GetService("Workspace").CurrentCamera
    return camera and camera.ViewportSize
  end)
  if not ok or not viewport or not win.Size then return false end
  local x, y, width, height = viewport.X, viewport.Y, win.Size.X, win.Size.Y
  if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y
    or x <= 0 or y <= 0 or x == math.huge or y == math.huge
    or type(width) ~= "number" or type(height) ~= "number"
    or width ~= width or height ~= height or width <= 0 or height <= 0
    or width == math.huge or height == math.huge then return false end
  -- Keep the title bar reachable even when the window is larger than the viewport.
  win.Position = Vector2.new(math.max(math.min(8, x - 1), (x - width) / 2),
    math.max(math.min(8, y - 1), (y - height) / 2))
  win._visibilityDirty = true
  win._aotrCenterPending = false
  return true
end
-- End startup centering.

-- Roblox can hide its native cursor in combat; draw a pointer above the settings UI.
function UI.IsOpen()
  return not UI.unloading and UI.window and UI.window.Visible == true
    and UI.lib and UI.lib.Toggled ~= false and not UI.lib._unloaded
end
function UI.MousePosition()
  -- GetMouse is unavailable in some client sessions.
  -- Keep cursor failures from aborting status/heartbeat updates or the combat loop.
  local ok, x, y = pcall(function()
    local mouse = LocalPlayer:GetMouse()
    return mouse.X, mouse.Y
  end)
  if ok and type(x) == "number" and type(y) == "number" then return Vector2.new(x, y) end
  return nil
end
function UI.IsInteracting()
  if not UI.IsOpen() then return false end
  local win = UI.window
  if win.Dragging or win.SliderDrag or win.CaptureInput or win.ColorInput
    or win.ColorDrag or win.OpenDropdown or win.OpenColorPicker then return true end
  local position, size = win.Position, win.Size
  if not position or not size then return false end
  local mouse = UI.MousePosition()
  if not mouse then return true end -- Protect menu controls until input is readable again.
  return mouse.X >= position.X and mouse.X <= position.X + size.X
    and mouse.Y >= position.Y and mouse.Y <= position.Y + size.Y
end
function UI.RemoveCursor()
  if UI.cursorFill then UI.cursorFill:Remove(); UI.cursorFill = nil end
  if UI.cursorEdge then UI.cursorEdge:Remove(); UI.cursorEdge = nil end
end
function UI.UpdateCursor()
  if Stopped() or UI.unloading then UI.RemoveCursor(); return end
  local mouse = UI.IsOpen() and isrbxactive() == true and UI.MousePosition()
  local visible = mouse ~= nil and mouse ~= false
  if not visible then
    if UI.cursorFill then UI.cursorFill.Visible = false; UI.cursorEdge.Visible = false end
    return
  end
  if not UI.cursorFill then
    UI.cursorFill = Drawing.new("Triangle")
    UI.cursorFill.Filled = true
    UI.cursorFill.Color = Color3.fromRGB(255, 255, 255)
    UI.cursorFill.ZIndex = 10000
    UI.cursorEdge = Drawing.new("Triangle")
    UI.cursorEdge.Filled = false
    UI.cursorEdge.Thickness = 2
    UI.cursorEdge.Color = Color3.fromRGB(10, 10, 10)
    UI.cursorEdge.ZIndex = 10001
  end
  local a = Vector2.new(mouse.X, mouse.Y)
  local b = Vector2.new(mouse.X + 5, mouse.Y + 18)
  local c = Vector2.new(mouse.X + 14, mouse.Y + 12)
  for _, cursor in ipairs({ UI.cursorFill, UI.cursorEdge }) do
    cursor.PointA, cursor.PointB, cursor.PointC = a, b, c
    cursor.Visible = true
  end
end

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
  if _G.AotrRunId ~= RunId then return end -- an old UI must not overwrite the new run's heartbeat
  if Qte.ReleaseAt and Qte.Vk then pcall(keyrelease, Qte.Vk); Qte.ReleaseAt = nil end
  if Recovery.ReleaseAt then pcall(keyrelease, 0x20); Recovery.ReleaseAt = nil end
  if _G.AotrRunId == RunId then _G.AotrStop = true end
  CurrentTitanTarget = nil
  UI.unloading = true
  UI.RemoveCursor()
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
  local win = ue:CreateWindow({ Title = "Wings of Freedom  |  AoT: Revolution", Width = 540, Height = 580, AutoShow = true, Center = false, Position = Vector2.new(100, 100) })
  UI.window = win
  win._aotrCenterPending = true
  UI.CenterWindow(win)
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
  reg("AutoQTE", farm:AddToggle("AutoQTE", { Text = "Auto QTE / Grab Escape", Default = UserConfigs.AutoQTE,
    Tooltip = "Read each visible QTE or grab-escape key; follow the entire sequence automatically", Callback = setter("AutoQTE") }))
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

  --[====[ Titan shifting controls disabled.
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

  ]====]
  local skills = main:AddLeftGroupbox("Human Skills")
  reg("HumanSkills", skills:AddToggle("HumanSkills", { Text = "Use Human Skills", Default = UserConfigs.HumanSkills,
    Tooltip = "Use ready human skills between slashes; wait 2.5 seconds between confirmed uses", Callback = setter("HumanSkills") }))
  reg("AwakeningEnabled", skills:AddToggle("AwakeningEnabled", { Text = "Use Awakening", Default = UserConfigs.AwakeningEnabled,
    Tooltip = "Allow the selected awakening slot; when disabled, that slot is skipped while other human skills remain enabled",
    Callback = setter("AwakeningEnabled") }))
  reg("AwakeningSlot", skills:AddSlider("AwakeningSlot", { Text = "Awakening Slot", Default = UserConfigs.AwakeningSlot,
    Min = 1, Max = 5, Rounding = 0, Tooltip = "Hotbar slot for Rage Mode; press only at full bar, then wait until the bar empties and fills again",
    Callback = setter("AwakeningSlot") }))

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
    UI.CenterWindow(win)
    win:Show()
    win._visibilityDirty = true
  end)

  -- UE redraws from its own task.spawn loop, but Matcha kills a thread at its first yield when
  -- its function comes from a chunk loadstring'd after the caller had already yielded (UE is
  -- loaded mid-run), so that loop draws one frame and dies: tabs added later never appear.
  -- Drive the window from our own thread instead.
  task.spawn(function()
    while not Stopped() and not UI.unloading and not ue._unloaded and not win.Destroyed do
      if win._aotrCenterPending then UI.CenterWindow(win) end
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
  UI.UpdateCursor()
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
  if os.clock() - lastBeat >= 1 and not Recovery.Blocked and os.clock() - LastProgress < PROGRESS_STALL_LIMIT then
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
  UI.RemoveCursor()
  if StatusLabel then pcall(function() StatusLabel:Remove() end); StatusLabel = nil end
end

task.spawn(buildMenu)
Boot("loops running")
print("[Aotr] running - F6 farm on/off, End unload (or _G.AotrStop = true)")

