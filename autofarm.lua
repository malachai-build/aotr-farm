-- Game name: Attack on Titans Revolution
-- Game Id: 4658598196
-- Game UniverseId: 4658598196
-- Game PlaceIds: 13379208636 (Lobby), 13379349730 (Mission) 4658598196 ( x )
-- Game link: https://www.roblox.com/games/13379208636/Attack-on-Titan-Revolution

-- Script version: 1.0.7



local Stats = {}

local ScriptStart = os.clock()

-- Everything the menu can change. Saved to SETTINGS_FILE.
local UserConfigs = {
  Autofarm = true,
  AutoRetry = true,       -- press Retry on the rewards screen
  AutoReload = true,      -- reload blades / refill gas when they run out
  NapeSize = 15,          -- studs; the pulled nape is resized to this cube
  PullAllNapes = false,   -- pull every live titan's nape to the player, not just the target's
  KillTimeout = 10,       -- seconds before giving up on a titan
  AttackDelay = 0.06,     -- seconds between slashes
  BobAmplitude = 2,       -- studs of up/down bob while hovering
  HeightNormal = 120,     -- hover height above each titan type
  HeightStall = 100,
  HeightAttack = 160,
  HeightColossal = 200,
  SafeHeight = 9999,      -- Y of the reload spot
  DebugMode = _G.KittyDebug == true -- was `or true`, which forced it on
}
local SETTINGS_FILE = "aotr_farm.json"
local SAVED_KEYS = {
  "Autofarm", "AutoRetry", "AutoReload", "NapeSize", "PullAllNapes", "KillTimeout", "AttackDelay", "BobAmplitude",
  "HeightNormal", "HeightStall", "HeightAttack", "HeightColossal", "SafeHeight", "DebugMode",
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
_G.AotrStop = false
local function Stopped() return _G.AotrStop == true end
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

if identifyexecutor and identifyexecutor() ~= "Matcha" then DebugPrint("warn", nil, nil, nil, "Not using matcha..?"); return end
if game.GameId ~= 4658598196 then DebugPrint("debug", nil, nil, nil, "Wrong game detected..?"); return end
if game.PlaceId == 14916516914 then DebugPrint("debug", nil, nil, nil, "You seem to be in the lobby. Please execute this in a game."); return end

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
                              repeat task.wait(0.03); until TitansFolder:FindFirstChildOfClass("Model")

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
  local Docks       = GetPath(Workspace, false, "Unclimbable", "World",      "Buildings", "Hanger",   "GasTanks"); if Docks  then DebugPrint("debug", nil, nil, "GasTank", "Docks detected!");       GasTankModel = Docks;       return Docks       end
  local Stohess     = GetPath(Workspace, false, "Unclimbable", "Props",      "HQ",        "GasTanks"); if Stohess     then DebugPrint("debug", nil, nil, "GasTank", "Stohess detected!");     GasTankModel = Stohess;     return Stohess     end
  local Chapel      = GetPath(Workspace, false, "Unclimbable", "Reloads",    "GasTanks");              if Chapel      then DebugPrint("debug", nil, nil, "GasTank", "Chapel detected!");      GasTankModel = Chapel;      return Chapel      end

  local Waves       = GetPath(Workspace, false, "Unclimbable", "Objective",  "Waves",     "GasTanks"); if Waves       then DebugPrint("debug", nil, nil, "GasTank", "Waves detected!");       GasTankModel = Waves;       return Waves       end

  warn("[Aotr] No known gas tank path for this map; refilling is disabled.")
  return nil
end; HandleDifferentGasTankPaths()

DebugPrint("debug", nil, nil, "GetOffsets", "Proceeding to fetch offsets from the server...")

local function GetOffsets(): OffsetsData?
  local ok, res = pcall(function()
    return game:HttpGet("https://imtheo.lol/Offsets/Offsets.json")
  end)



  if not ok or not res then
    DebugPrint("warn", nil, nil, "GetOffsets", "Failed to fetch offsets: ", tostring(res))

    return nil
  end

  local success, decoded = pcall(function()
    return HttpService:JSONDecode(res)
  end)


  if not success then
    DebugPrint("warn", nil, nil, "GetOffsets", "JSON decode failed: ", decoded)

    return nil
  end

  return decoded :: OffsetsData
end; local OffsetsFake = GetOffsets()


if not OffsetsFake or next(OffsetsFake) == nil then
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

local CachedBladesBroken: boolean = false
local LastBladeCheck: number = 0

local CurrentRobloxState = "Active"
local WhatShouldIBeDoing = "attack"

local ReloadingBlades: boolean = false
local LastReloadingTime: number = 0


local DownMiddlePartUi: Instance? = GetPath(PlayerGui, true, "Interface", "HUD", "Main", "Top", "7"); if not DownMiddlePartUi then return end


--== Offsets ==--
local Offsets: { [string]: { [string]: number } } = OffsetsFake.Offsets
                                                     
local PrimaryPartOffset = Offsets.Model.PrimaryPart;
local BaseToPrimitiveOffset = Offsets.BasePart.Primitive;
local PrimitivePositionOffset = Offsets.Primitive.Position;
local VisibleOffset = Offsets.GuiObject.Visible;                  
local TransparencyBasePartOffset = Offsets.BasePart.Transparency;
local AbsolutPositionGuiElementOffset = Offsets.GuiBase2D.AbsoluteSize;


--#endregion -- Variables section --



--#region  -- Functions --


--#region -- Player's character and Titan's character related functions --

local function GetCharacter(player: Player): BasePart? return player.Character :: Model end
local function GetHrp(instance: Instance): BasePart? return instance:FindFirstChild("HumanoidRootPart") :: BasePart end
local function GetHumanoid(instance: Instance): Humanoid? return instance:FindFirstChildOfClass("Humanoid") :: Humanoid end


local function GetPlayerCharacter(player: Player): Model?
  DebugPrint("debug", 4, nil, "GetPlayerCharacter", "Fetching character for player:", player.Name)
  local PlayerCharacterCache = CharacterCache[player.Address]; if not PlayerCharacterCache then DebugPrint("debug", 4, nil, "GetPlayerCharacter", "No cache for player: ", player.Name); return nil end
  local CachedCharacter = PlayerCharacterCache.Character :: Model?; if IsValid(CachedCharacter) then DebugPrint("debug", 4, nil, "GetPlayerCharacter", "Returning cached character"); return CachedCharacter end

  local Character = player.Character :: Model; if not IsValid(Character) then DebugPrint("debug", 4, nil, "GetPlayerCharacter", "No character found"); return nil end

  PlayerCharacterCache.Character = Character
  DebugPrint("debug", 4, nil, "GetPlayerCharacter", "Updated cache for the player: ", player.Name)
  return Character
end


local function GetPlayerHrp(player: Player): BasePart?
  DebugPrint("debug", 4, nil, "GetPlayerHrp", "Fetching HRP for player:", player.Name)
  local PlayerCharacterCache = CharacterCache[player.Address]; if not PlayerCharacterCache then DebugPrint("debug", 4, nil, "GetPlayerHrp", "No cache found for the player: ", player.Name); return nil end
  local CachedHrp = PlayerCharacterCache.Hrp; if IsValid(CachedHrp) then DebugPrint("debug", 4, nil, "GetPlayerHrp", "Returning cached HRP"); return CachedHrp end
  local Character = GetPlayerCharacter(player); if not Character then DebugPrint("debug", 4, nil, "GetPlayerHrp", "Character not found"); return nil end
  local Hrp = GetHrp(Character); if not Hrp then DebugPrint("debug", 4, nil, "GetPlayerHrp", "HRP not found in character"); return nil end

  PlayerCharacterCache.Hrp = Hrp
  DebugPrint("debug", 4, nil, "GetPlayerHrp", "Cached new HRP for the player: ", player.Name)
  return Hrp
end


local function GetPlayerHumanoid(player: Player): Humanoid?
  DebugPrint("debug", 4, nil, "GetPlayerHumanoid", "Fetching humanoid for player:", player.Name)
  local PlayerCharacterCache = CharacterCache[player.Address]; if not PlayerCharacterCache then DebugPrint("debug", 4, nil, "GetPlayerHumanoid", "No cache for the player: ", player.Name); return nil end
  local CachedHumanoid = PlayerCharacterCache.Humanoid; if CachedHumanoid and CachedHumanoid.Parent then DebugPrint("debug", 4, nil, "GetPlayerHumanoid", "Cached humanoid valid"); return CachedHumanoid end
  local Character = GetPlayerCharacter(player); if not Character then DebugPrint("debug", 4, nil, "GetPlayerHumanoid", "Character missing"); return nil end
  local Humanoid = GetHumanoid(Character); if not Humanoid then DebugPrint("debug", 4, nil, "GetPlayerHumanoid", "Humanoid missing from character"); return nil end

  PlayerCharacterCache.Humanoid = Humanoid
  DebugPrint("debug", 4, nil, "GetPlayerHumanoid", "Cached new humanoid for the player: ", player.Name)
  return Humanoid
end


local function GetTitanHrp(titan: Instance): BasePart?
  DebugPrint("debug", 4, nil, "GetTitanHrp", "Fetching HRP for titan:", titan.Name)
  if not IsValid(titan) then DebugPrint("debug", 4, nil, "GetTitanHrp", "Titan invalid or no parent"); return nil end
  local TitanCache = TitansCache[titan.Address]; if not TitanCache then DebugPrint("debug", 4, nil, "GetTitanHrp", "No cache for titan"); return nil end
  local CachedHrp = TitanCache.Parts.HumanoidRootPart; if IsValid(CachedHrp) then DebugPrint("debug", 4, nil, "GetTitanHrp", "Using cached HRP"); return CachedHrp end
  local TitanHrp = GetHrp(titan);if not TitanHrp then DebugPrint("debug", 4, nil, "GetTitanHrp", "HRP not found"); return nil end

  TitanCache.Parts.HumanoidRootPart = TitanHrp
  DebugPrint("debug", 4, nil, "GetTitanHrp", "Cached titan HRP")
  return TitanHrp
end


local function GetTitanHumanoid(titan: Instance): Humanoid?
  DebugPrint("debug", 4, nil, "GetTitanHumanoid", "Fetching humanoid for titan:", titan.Name)
  if not IsValid(titan) then DebugPrint("debug", 4, nil, "GetTitanHumanoid", "Titan invalid"); return nil end

  local TitanCache = TitansCache[titan.Address]; if not TitanCache then DebugPrint("debug", 4, nil, "GetTitanHumanoid", "Cache missing"); return nil end
  local CachedHumanoid = TitanCache.Parts.Humanoid; if IsValid(CachedHumanoid) then DebugPrint("debug", 4, nil, "GetTitanHumanoid", "Using cached humanoid"); return CachedHumanoid end
  local TitanHumanoid = GetHumanoid(titan); if not TitanHumanoid then DebugPrint("debug", 4, nil, "GetTitanHumanoid", "Humanoid not found"); return nil end

  TitanCache.Parts.Humanoid = TitanHumanoid
  DebugPrint("debug", 4, nil, "GetTitanHumanoid", "Cached humanoid")
  return TitanHumanoid
end


local function RegisterPlayer(player: Player)
  DebugPrint("debug", 4, nil, "RegisterPlayer", "Registering player:", player.Name)
  local existing = CharacterCache[player.Address]

  if existing then
    DebugPrint("debug", 4, nil, "RegisterPlayer", "Updating existing cache for:", player.Name)
    existing.Character = player.Character
    return
  end

  DebugPrint("debug", 4, nil, "RegisterPlayer", "Creating new cache entry for:", player.Name)
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
  if not IsValid(titan) then DebugPrint("debug", 4, nil, "IsTitanIgnored", "Titan invalid"); return false end

  local TitanCache = TitansCache[titan.Address]; if not TitanCache then DebugPrint("debug", 4, nil, "IsTitanIgnored", "No cache"); return false end
  local TitanInfo = TitanCache.Info; if not TitanInfo.Ignored then DebugPrint("debug", 4, nil, "IsTitanIgnored", "Not ignored"); return false end

  local IgnoredTime = TitanInfo.IgnoredTime; if not IgnoredTime then DebugPrint("debug", 4, nil, "IsTitanIgnored", "No ignore time"); return false end
  local IgnoreDuration = TitanInfo.IgnoreDuration; if not IgnoreDuration then DebugPrint("debug", 4, nil, "IsTitanIgnored", "No ignore duration"); return false end

  if os.clock() - IgnoredTime >= IgnoreDuration then
    DebugPrint("debug", 4, nil, "IsTitanIgnored", "Ignore duration expired, un-ignoring titan")
    TitanCache.TpFails.Count = 0
    TitanInfo.Ignored = false
    TitanInfo.IgnoredTime = nil
    TitanInfo.IgnoreDuration = nil
    return false
  end

  DebugPrint("debug", 4, nil, "IsTitanIgnored", "Titan is still ignored")
  return true
end


local function RegisterTitanFail(titan: Instance)
  if not IsValid(titan) then DebugPrint("debug", 4, nil, "RegisterTitanFail", "Invalid titan"); return end

  local TitanCache = TitansCache[titan.Address]; if not TitanCache then DebugPrint("debug", 4, nil, "RegisterTitanFail", "No cache"); return end

  local TitanInfo = TitanCache.Info

  TitanCache.TpFails.Count += 1
  DebugPrint("debug", 4, nil, "RegisterTitanFail", "Fail count:", TitanCache.TpFails.Count, "for titan:", titan.Name)

  if TitanCache.TpFails.Count > 3 then
    DebugPrint("debug", 4, nil, "RegisterTitanFail", "Max fails reached, ignoring titan:", titan.Name)
    TitanInfo.Ignored = true
    TitanInfo.IgnoredTime = os.clock()
    TitanInfo.IgnoreDuration = 5
  end
end


local function GetTitanType(titan: Instance): string -- Needs more research
  local TitanCache = TitansCache[titan.Address]; if not TitanCache then DebugPrint("debug", 4, nil, "GetTitanType", "No cache, returning Normal"); return "Normal" end
  local TitanTypeCached = TitanCache.Info.Type; if TitanTypeCached then DebugPrint("debug", 4, nil, "GetTitanType", "Cached type:", TitanTypeCached); return TitanTypeCached end

  local TitanType = titan:GetAttribute("Type") :: string? or "Normal"
  DebugPrint("debug", 4, nil, "GetTitanType", "Found type:", TitanType)

  TitanCache.Info.Type = TitanType
  return TitanType
end


local function GetTitanNape(titan: Instance): BasePart?
  if not titan or not titan.Parent then DebugPrint("debug", 4, nil, "GetTitanNape", "Invalid titan"); return nil end

  local TitanCache = TitansCache[titan.Address]; if not TitanCache then DebugPrint("debug", 4, nil, "GetTitanNape", "No cache"); return nil end
  local CachedNape = TitanCache.Parts.Nape; if IsValid(CachedNape) then DebugPrint("debug", 4, nil, "GetTitanNape", "Using cached nape"); return CachedNape end
  local NapePart = GetPath(titan, true, "Hitboxes", "Hit", "Nape") :: BasePart; if not NapePart then DebugPrint("debug", 4, nil, "GetTitanNape", "Nape part not found"); return nil end

  TitanCache.Parts.Nape = NapePart
  DebugPrint("debug", 4, nil, "GetTitanNape", "Cached nape part")
  return NapePart
end


local function IsTitanAlive(titan: Instance?): boolean
  if not titan or not titan.Parent then DebugPrint("debug", 4, nil, "IsTitanAlive", "Titan invalid"); return false end

  local TitanAddress = titan.Address; if not TitanAddress then DebugPrint("debug", 4, nil, "IsTitanAlive", "No address"); return false end
  local TitanCache = TitansCache[TitanAddress]; if not TitanCache then DebugPrint("debug", 4, nil, "IsTitanAlive", "No cache"); return false end
  local TitanHumanoid = GetTitanHumanoid(titan); if not TitanHumanoid then DebugPrint("debug", 4, nil, "IsTitanAlive", "No humanoid"); return false end

  local now = os.clock()

  if TitanCache.Info.LastAliveCheck and now - TitanCache.Info.LastAliveCheck < 0.2 then
    DebugPrint("debug", 4, nil, "IsTitanAlive", "Using cached alive status:", TitanCache.Info.Alive)
    return TitanCache.Info.Alive or false
  end

  local ok, alive = pcall(function()
    return TitanHumanoid.Health > 0
  end)

  if not ok then DebugPrint("warn", 4, nil, "IsTitanAlive", "Error checking health"); return false end

  TitanCache.Info.LastAliveCheck = now
  TitanCache.Info.Alive = alive
  DebugPrint("debug", 4, nil, "IsTitanAlive", "Checked alive: ", alive, " Health: ", TitanHumanoid.Health)
  return TitanCache.Info.Alive :: boolean
end


local function BringNapeToPlayer(titan: Instance, size: Vector3?)
  DebugPrint("debug", 4, nil, "BringNapeToPlayer", "Bringing nape to player for:", titan.Name)
  if not IsValid(titan) then DebugPrint("debug", 4, nil, "BringNapeToPlayer", "Invalid titan"); return end

  local TitanCache = TitansCache[titan.Address]; if not TitanCache then DebugPrint("debug", 4, nil, "BringNapeToPlayer", "No cache"); return end
  local NapePartCached = TitanCache.Parts.Nape; if not IsValid(NapePartCached) then DebugPrint("debug", 4, nil, "BringNapeToPlayer", "Cached nape invalid"); return end
  local NapePart = GetTitanNape(titan); if not NapePart or not NapePart.Parent then DebugPrint("debug", 4, nil, "BringNapeToPlayer", "Nape part not found"); return end
  local PlayerHrp = GetPlayerHrp(LocalPlayer); if not PlayerHrp then DebugPrint("debug", 4, nil, "BringNapeToPlayer", "Player HRP not found"); return end

  TitanCache.Parts.Nape = NapePart

  NapePart.CFrame = PlayerHrp.CFrame * CFrame.new(0, 2, 0)
  DebugPrint("debug", 4, nil, "BringNapeToPlayer", "Nape CFrame updated")

  if size then
    NapePart.Size = size
    TitanCache.Nape.CurrentSize = size
    DebugPrint("debug", 4, nil, "BringNapeToPlayer", "Nape size set to:", size)
  end
end


local function GetTitanBobHeight(titan: Instance): number
  local TitanType = GetTitanType(titan); if not TitanType then DebugPrint("debug", 4, nil, "GetTitanBobHeight", "No type, using default"); return UserConfigs.HeightNormal end

  local Height = UserConfigs["Height" .. TitanType] or UserConfigs.HeightNormal
  DebugPrint("debug", 4, nil, "GetTitanBobHeight", "Type:", TitanType, "Height:", Height)
  return Height
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
  DebugPrint("debug", 4, nil, "TpAboveTitan", "Attempting teleport for: ", (titan.Name or "<nil>"))
  if not titan or not titan.Parent then DebugPrint("debug", 4, nil, "TpAboveTitan", "Invalid titan"); return false end

  local TitanCache = TitansCache[titan.Address]; if not TitanCache then DebugPrint("debug", 4, nil, "TpAboveTitan", "No cache"); return false end
  local LocalPlayerCache = CharacterCache[LocalPlayer.Address]; if not LocalPlayerCache then DebugPrint("debug", 4, nil, "TpAboveTitan", "No player cache"); return false end
  local Hrp = LocalPlayerCache.Hrp or GetPlayerHrp(LocalPlayer); if not Hrp then DebugPrint("debug", 4, nil, "TpAboveTitan", "HRP not found"); return false end
  local TitanHrp: BasePart? = GetTitanHrp(titan); if not TitanHrp or not TitanHrp:IsA("BasePart") then DebugPrint("debug", 4, nil, "TpAboveTitan", "Titan HRP invalid"); return false end

  local TitanPosition: Vector3 = TitanHrp.Position

  DebugPrint("debug", 4, nil, "TpAboveTitan", "Titan position:", TitanPosition)

  local BobHeight = GetTitanBobHeight(titan); if not BobHeight then DebugPrint("debug", 4, nil, "TpAboveTitan", "No bob height"); return false end
  local BobOffset = math.sin(os.clock() * math.pi * 2) * UserConfigs.BobAmplitude

  DebugPrint("debug", 4, nil, "TpAboveTitan", "Bob offset:", BobOffset)
  DebugPrint("debug", 3, nil, nil, "Teleporting to the titan: " .. tostring(titan.Name))

  local ok, err = pcall(function()
    Hrp.CFrame = CFrame.new(TitanPosition.X, TitanPosition.Y + BobHeight + BobOffset, TitanPosition.Z)
  end)

  if not ok then
    DebugPrint("warn", 0, nil, nil, "Error happened while setting CFrame to titan: " .. err)
    return false
  end

  DebugPrint("debug", 4, nil, "TpAboveTitan", "Teleport successful")
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
  local cached = UiCache[cacheKey]; if cached then DebugPrint("debug", 4, nil, "GetUiCached", "Returning ui cache: ", cacheKey); return cached end

  DebugPrint("debug", 4, nil, "GetUiCached", "Cache miss: ", cacheKey)
  local obj = GetPath(parent, false, ...); if not obj then DebugPrint("debug", 4, nil, "GetUiCached", "Object not found: ", cacheKey); return nil end

  UiCache[cacheKey] = obj
  DebugPrint("debug", 4, nil, "GetUiCached", "Cached object:", cacheKey)
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
  DebugPrint("debug", 4, nil, "DoINeedToRefill", "Checking refill status")

  local Blades = GetUiCached("Blades", DownMiddlePartUi, "Blades"); if not Blades then DebugPrint("debug", 4, nil, "DoINeedToRefill", "Blades UI not found"); return true end
  local TextForBlades = GetUiCached("TextForBlades", Blades, "Sets") :: TextLabel?; if not TextForBlades then DebugPrint("debug", 4, nil, "DoINeedToRefill", "Blade text not found"); return true end

  local Gas = GetUiCached("Gas", DownMiddlePartUi, "Gas"); if not Gas then DebugPrint("debug", 4, nil, "DoINeedToRefill", "Gas UI not found"); return true end
  local TextForGas = GetUiCached("TextForGas", Gas, "Percentage") :: TextLabel?; if not TextForGas then DebugPrint("debug", 4, nil, "DoINeedToRefill", "Gas text not found"); return true end

  local BladesValue = tonumber(TextForBlades.Text:match("%d+")) or 0
  local GasValue = tonumber(TextForGas.Text:match("%d+")) or 0

  DebugPrint("debug", 4, nil, "DoINeedToRefill", "Blades:", BladesValue, "Gas:", GasValue)

  local NeedRefill = BladesValue == 0 or GasValue == 0

  if NeedRefill then
    DebugPrint("debug", 4, nil, "DoINeedToRefill", "Refill needed!")
    WhatShouldIBeDoing = "refill"
  end

  return NeedRefill
end


local function IsReloadingBlades(): boolean  -- Basically, when reloading the 0 / 3 counter, the 'BV' is missing
  local LocalPlayerCache = CharacterCache[LocalPlayer.Address]; if not LocalPlayerCache then DebugPrint("debug", 4, nil, "IsReloadingBlades", "No player cache"); return false end

  local Hrp = LocalPlayerCache.Hrp or GetPlayerHrp(LocalPlayer); if not Hrp then DebugPrint("debug", 4, nil, "IsReloadingBlades", "No HRP"); return false end
  if Hrp:FindFirstChild("BV") then DebugPrint("debug", 4, nil, "IsReloadingBlades", "BV found, not reloading"); return false end

  DebugPrint("debug", 4, nil, "IsReloadingBlades", "Blades are reloading")

  return true
end


local function HandleAllReloads()
  if not AreBladesFullyBroken() then return end

  local LocalPlayerCharacterCache = CharacterCache[LocalPlayer.Address]; if not LocalPlayerCharacterCache then return end
  local Hrp = LocalPlayerCharacterCache.Hrp or GetPlayerHrp(LocalPlayer); if not Hrp then return end

  local Time = os.clock()

  if DoINeedToRefill() then
    DebugPrint("debug", 0, nil, nil, "Detected that the local player needs refilling.")

    while true do
      if not DoINeedToRefill() then WhatShouldIBeDoing = "attack"; break end
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

        Hrp.Position = GasTankPosition + Vector3New(5, 0, 0)
        Hrp.AssemblyLinearVelocity = Vector3Zero

        task.wait(0.5)

        keypress(0x52)
        task.wait(0.5)
        keyrelease(0x52)

        task.wait(1)
        continue
      end


      if not GasTankModel then WhatShouldIBeDoing = "attack"; return end
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

      Hrp.CFrame = SafePosNow()

      keypress(0x52)
      task.wait(0.5)
      keyrelease(0x52)
      task.wait(0.5)

      ReloadingBlades = false
    end)
  end
end

--#endregion Gas tank functions --


--#region -- Ui elements functions --

local function IsObjectVisible(object: GuiObject): boolean
  if not object or not object.Address then
    DebugPrint("debug", 4, nil, "IsObjectVisible", "Object invalid")
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
  DebugPrint("debug", 4, nil, "IsObjectVisible", "Object:", object.Name, "Visible:", visible)
  return visible
end


local function IsRetryVisible(): boolean
  DebugPrint("debug", 4, nil, "IsRetryVisible", "Checking retry visibility")

  local RewardsFrame;

  if UiCache.RewardsFrame and UiCache.RewardsFrame.Parent then
    DebugPrint("debug", 4, nil, "IsRetryVisible", "Using cached rewards frame")
    return IsObjectVisible(UiCache.RewardsFrame)
  end

  RewardsFrame = GetPath(PlayerGui, true, "Interface", "Rewards") :: GuiObject; if not RewardsFrame then DebugPrint("debug", 4, nil, "IsRetryVisible", "Rewards frame not found"); return false end

  UiCache.RewardsFrame = RewardsFrame
  DebugPrint("debug", 4, nil, "IsRetryVisible", "Cached new rewards frame")
  return IsObjectVisible(RewardsFrame)
end


local RetryCount = 0

local function PressRetry()
  if not IsRetryVisible() then return end

  DebugPrint("debug", 0, nil, "PressRetry", "Pressing the retry button.")
  task.wait(0.5)

  if RetryCount < 3 then -- ui navigation
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
  end
end

--#endregion -- Ui elements functions --



-- // Some functions that couldn't fit before \\ --
local function KillTitan(titan: Instance)
  DebugPrint("debug", 3, nil, "KillTitan", "Starting kill sequence for:", titan.Name)
  if not titan or not titan.Parent then DebugPrint("debug", 3, nil, "KillTitan", "Invalid titan"); return end

  local StartTime = os.clock()

  local LocalPlayerCharacterCache = CharacterCache[LocalPlayer.Address]; if not LocalPlayerCharacterCache then DebugPrint("debug", 3, nil, "KillTitan", "No player cache"); return end
  local Hrp = LocalPlayerCharacterCache.Hrp or GetPlayerHrp(LocalPlayer); if not Hrp then DebugPrint("debug", 3, nil, "KillTitan", "No HRP"); return end

  print("[Aotr] targeting " .. titan.Name:sub(1, 8))
  FarmStats.Target = titan.Name:sub(1, 8)
  FarmStats.Status = "attacking"
  while true do
    task.wait(UserConfigs.AttackDelay)
    if Stopped() or not UserConfigs.Autofarm then break end
    if not IsTitanAlive(titan) then
      FarmStats.Kills += 1
      print(string.format("[Aotr] %s down after %.1fs", titan.Name:sub(1, 8), os.clock() - StartTime))
      break
    end
    if AreBladesFullyBroken() then DebugPrint("debug", 3, nil, "KillTitan", "Blades broken"); break end
    if os.clock() - StartTime > UserConfigs.KillTimeout then
      FarmStats.Timeouts += 1
      print("[Aotr] timeout on " .. titan.Name:sub(1, 8))
      break
    end

    if CurrentRobloxState == "Inactive" then
      DebugPrint("debug", 4, nil, "KillTitan", "Window not active, waiting...")
      task.wait(0.5)
    else
      if WhatShouldIBeDoing ~= "attack" then task.wait(0.1); continue end
      CurrentTitanTarget = titan

      local s = UserConfigs.NapeSize
      BringNapeToPlayer(titan, Vector3New(s, s, s))
      if UserConfigs.PullAllNapes then
        for _, other in pairs(KnownTitans) do
          if other ~= titan and IsTitanAlive(other) and not IsTitanIgnored(other) then
            BringNapeToPlayer(other, Vector3New(s, s, s))
          end
        end
      end
      DebugPrint("debug", 4, nil, "KillTitan", "Attacking nape")

      task.wait()
      mouse1click()
      task.wait(0.03)
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

task.spawn(function() -- KnownTitans updater and TitansCache cleanup
  while not Stopped() do
    DebugPrint("debug", 4, nil, nil, "The known titans updater is running!")
    local TitansCount = #TitansFolder:GetChildren()
    DebugPrint("debug", 4, nil, nil, "Titans in folder: ", TitansCount)

    for _, titan in ipairs(TitansFolder:GetChildren()) do
      if not titan:IsA("Model") then continue end

      if not KnownTitans[titan.Address] then
        DebugPrint("debug", 4, nil, nil, "Registered new titan: ", titan.Name)
        KnownTitans[titan.Address] = titan
      end
    end

    for address, titan in pairs(KnownTitans) do
      if not titan or not titan.Parent or not GetHumanoid(titan) then
        DebugPrint("debug", 4, nil, nil, "Cleaning up dead/invalid titan")
        KnownTitans[address] = nil
        TitansCache[address] = nil
      end
    end

    DebugPrint("debug", 4, nil, nil, "Known titans count: ", #KnownTitans)
    task.wait(1)
  end
end)


task.spawn(function() -- Titans cache
  while not Stopped() do
    DebugPrint("debug", 4, nil, nil, "The titan cache loop is running!")
    local CachedCount = 0
    for _, titan in pairs(KnownTitans) do
      if titan and titan.Parent and GetHumanoid(titan) then
        RegisterTitan(titan)
        CachedCount += 1
      end
      task.wait()
    end
    DebugPrint("debug", 4, nil, nil, "Titans cached:", CachedCount)

    task.wait(3)
  end
end)


task.spawn(function() -- The main loop, where the magic happens
  while not Stopped() do
    DebugPrint("debug", 4, nil, nil, "The main loop is running!")

    if not UserConfigs.Autofarm then
      CurrentTitanTarget = nil
      FarmStats.Status = "paused"
      task.wait(0.5)
      continue
    end

    if UserConfigs.AutoRetry and IsRetryVisible() then
      FarmStats.Status = "pressing retry"
      DebugPrint("debug", nil, nil, nil, "Detected that the retry button is visible.")
      PressRetry()
      task.wait(3)
      continue
    end

    if AreBladesFullyBroken() then
      CurrentTitanTarget = nil
      if UserConfigs.AutoReload then
        FarmStats.Status = "reloading"
        HandleAllReloads()
      else
        FarmStats.Status = "blades broken (auto reload off)"
      end
      task.wait(1)
      continue
    end

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
    DebugPrint("debug", 4, nil, nil, "The player cache loop is running!")
    local PlayerCount = #Players:GetPlayers()
    DebugPrint("debug", 4, nil, nil, "Players found: ", PlayerCount)
    
    for _, player in ipairs(Players:GetPlayers()) do
      RegisterPlayer(player)
      task.wait()
    end

    local CachedCount = 0
    for playerAddress, cache in pairs(CharacterCache) do
      local character = cache.Character

      if not character or not character.Parent then
        DebugPrint("debug", 4, nil, nil, "Removing player from cache: ", cache.Username)
        CharacterCache[playerAddress] = nil
      else
        CachedCount += 1
      end
      task.wait()
    end
    
    DebugPrint("debug", 4, nil, nil, "Active character caches: ", CachedCount)
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


local RenderConn
RenderConn = game:GetService("RunService").RenderStepped:Connect(function(delta)
  if Stopped() then RenderConn:Disconnect(); print("[Aotr] stopped"); return end
  if not UserConfigs.Autofarm or WhatShouldIBeDoing ~= "attack" then return end
  if CurrentRobloxState == "inactive" then
    local Hrp = GetPlayerHrp(LocalPlayer); if not IsValid(Hrp) then return end
    Hrp.CFrame = SafePosNow()
    return
  end

  if CurrentTitanTarget then
    TpAboveTitan(CurrentTitanTarget)
  end
end)

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
  _G.AotrStop = true
  CurrentTitanTarget = nil
  UI.unloading = true
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
  local ue, err = loadUE()
  if not ue then
    warn("[Aotr] menu failed to load: " .. tostring(err) .. " (F6 / End hotkeys still work)")
    return
  end
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
  local win = ue:CreateWindow({ Title = "Wings of Freedom  |  AoT: Revolution", Width = 540, Height = 470, AutoShow = true, Center = true })
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

  local tuning = win:AddTab("Tuning")
  local attack = tuning:AddLeftGroupbox("Attack")
  reg("NapeSize", attack:AddSlider("NapeSize", { Text = "Nape Size", Default = UserConfigs.NapeSize,
    Min = 5, Max = 40, Rounding = 0, Suffix = " studs", Callback = setter("NapeSize") }))
  reg("PullAllNapes", attack:AddToggle("PullAllNapes", { Text = "Pull All Napes", Default = UserConfigs.PullAllNapes,
    Tooltip = "Pull every live titan's nape to you so each slash can hit them all",
    Callback = setter("PullAllNapes") }))
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

  if type(ue.OnUnload) == "function" then
    pcall(function() ue:OnUnload(function() if not UI.unloading then Unload() end end) end)
  end
  pcall(function()
    win:Show()
    win._visibilityDirty = true
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

task.spawn(function()
  local was = {}
  while not Stopped() do
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
      pcall(function()
        StatusLabel.Text = string.format("AoTR farm:%s  kills:%d  timeouts:%d  target:%s  |  %s",
          UserConfigs.Autofarm and "ON" or "off", FarmStats.Kills, FarmStats.Timeouts, FarmStats.Target, FarmStats.Status)
      end)
    end
    task.wait(0.1)
  end
  if StatusLabel then pcall(function() StatusLabel:Remove() end); StatusLabel = nil end
end)

task.spawn(buildMenu)
print("[Aotr] running - F6 farm on/off, End unload (or _G.AotrStop = true)")

