<#
AoTR farm watchdog. Run it in its own PowerShell window while farming:

  powershell -ExecutionPolicy Bypass -File .\aotr_watchdog_portable.ps1 -RestartMatcha -RestartOnTeleport

Matcha is discovered from its process and install locations. Its workspace is verified by a
temporary marker written through Matcha MCP; when MCP is unavailable the default is C:\matcha\workspace. A fresh install needs no AoTR files: the workspace and aotr
folder are created if absent. Use -MatchaExe or -WorkspaceRoot only for unusual installs.

Why: when the character dies before a mission has loaded in, Matcha does not reload, so neither
the MCP nor auto-exec (nor the farm) runs and the run stalls. The farm writes
aotr/heartbeat.txt in Matcha's workspace ("<state> <time>") every 5 s. While the last state is
"farming" and the file goes stale, this script focuses Roblox and sends the same Retry keys the
farm uses (\ to enter UI navigation, D, D, Enter). A retry starts a fresh server, where Matcha
reloads and auto-exec restarts the farm. States "lobby" and "unloaded" make it stand down.

A death before load-in can also make Matcha's own process (app.exe) exit. Retry alone does not
help then, since nothing runs on the new server either. The watchdog logs it, and with
-RestartMatcha it starts app.exe again (auto-exec then starts the farm, whose Auto Retry takes
over); retries wait while Matcha is down. Matcha can also stall without exiting (farm and MCP go
silent mid-mission, so Retry has nothing to press), or come back after a teleport without running
auto-exec. So with -RestartMatcha a stale heartbeat first restarts app.exe (rerunning auto-exec),
then presses Retry -RestartAfterAttempts times, then restarts again, and so on. A hung Matcha window
(-HungSeconds) is restarted too. After every start it uses the saved Matcha menu key (Insert by default) to close the
overlay, which otherwise blocks the farm's clicks.

It also asks Matcha's MCP (http://127.0.0.1:8765/mcp) where it is. In the lobby it stands down.
In a mission, if the farm has been silent for -ScriptStaleSeconds (counted from the later of its
last heartbeat and the moment this server was first seen, so loading gets time), it restarts
Matcha, then presses Retry, and repeats (-TryScriptRestart first tries starting the farm through
the MCP). When the MCP is down it falls back to the heartbeat alone (-McpDownSeconds once the MCP
has been down that long, else -StaleSeconds).

-DryRun logs what it would do without pressing anything.
#>
param(
  [string]$MatchaExe,
  [string]$WorkspaceRoot,
  [string]$BootLog,
  [string]$FarmReadPath,
  [switch]$RestartMatcha,
  [int]$StaleSeconds = 45,     # MCP down and not yet McpDownSeconds: heartbeat age before acting
  [int]$CooldownSeconds = 25,  # wait between attempts (a fresh Matcha has the farm heartbeating in ~10s)
  [int]$RestartAfterAttempts = 1, # with -RestartMatcha: Retry presses between Matcha restarts while the heartbeat stays stale
  [int]$HungSeconds = 2,       # with -RestartMatcha: restart app.exe once its window stops responding this long
                               # (Windows flags it after ~5s already; 15 here took 31s to recover from a
                               # hang mid-mission on 2026-11-02, about all the time the character has)
  [int]$StatusSeconds = 30,    # log a status line at least this often, so the log shows the watchdog is alive
  [int]$ScriptStaleSeconds = 20, # in a mission with the MCP up: farm silence before acting (the farm beats every 5s)
  [int]$McpDownSeconds = 20,   # with -RestartMatcha: MCP and farm both silent this long -> act without waiting for StaleSeconds
  [int]$PollSeconds = 2,       # main loop interval
  [ValidateRange(0, 254)][int]$OverlayKey = 0, # 0 = saved Matcha menukey, falling back to Insert
  [int]$OverlaySeconds = 15,   # close Matcha's overlay once it has stayed open this long
  [int]$FastStaleSeconds = 5,  # with -RestartMatcha: restart Matcha once a "farming" heartbeat is this old (the farm beats every 1s)
  [int]$CharacterRecoverySeconds = 20, # allow the game to clear a grab/ragdoll before watchdog recovery
  [int]$RetryStuckSeconds = 45, # restart a farm that keeps heartbeating on the Retry screen
  [switch]$TryScriptRestart,   # first try starting the farm through the MCP (0 of 3 attempts worked on 2026-11-01)
  [switch]$RestartOnTeleport,  # close Matcha when Roblox starts a teleport, start it fresh once the new server is joined
  [int]$JoinTimeoutSeconds = 60, # with -RestartOnTeleport: start Matcha anyway if no join shows up in Roblox's log
  [string]$RobloxLogDir = "$env:LOCALAPPDATA\Roblox\logs",
  [string]$McpUrl = "http://127.0.0.1:8765/mcp",
  [string]$LobbyPlaceId = "14916516914",
  [string]$Heartbeat,
  [string]$Log,
  [switch]$ShowWorkspace, # open the selected workspace in Explorer, then exit
  [switch]$ValidateOnly,  # show discovered paths and exit without starting the watchdog loop
  [switch]$DryRun
)

# app.exe is a generic name: identify Matcha by its installation, metadata, or MCP listener.
function Test-MatchaExecutable([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $file = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $file -or $file.Extension -ne '.exe') { return $false }
  if ($file.BaseName -match '^matcha(?:[-_ ].*)?$') { return $true }
  if ($file.BaseName -ne 'app') { return $false }
  if ($Path -match '[\\/]matcha[\\/]') { return $true }
  try {
    if (($file.VersionInfo.ProductName + ' ' + $file.VersionInfo.FileDescription) -match '(?i)matcha') { return $true }
  } catch {}
  $folder = $file.DirectoryName
  foreach ($root in @($folder, (Split-Path -Parent $folder))) {
    if (-not $root) { continue }
    # A renamed portable folder still has Matcha's workspace/autoexec layout.
    if ((Test-Path -LiteralPath (Join-Path $root 'workspace') -PathType Container) -and
        (($file.Directory.Name -eq 'usermode') -or
         (Test-Path -LiteralPath (Join-Path $root 'autoexec') -PathType Container) -or
         (Test-Path -LiteralPath (Join-Path $root 'workspace\aotr') -PathType Container))) { return $true }
  }
  return $false
}

function Find-MatchaExe {
  if ($MatchaExe) {
    if (-not (Test-Path -LiteralPath $MatchaExe -PathType Leaf)) { throw "Matcha executable not found: $MatchaExe" }
    return (Resolve-Path -LiteralPath $MatchaExe).Path
  }
  # Explicit environment configuration also works for renamed installations.
  $configured = @()
  if ($env:MATCHA_EXE) { $configured += $env:MATCHA_EXE }
  if ($env:MATCHA_HOME) {
    $configured += (Join-Path $env:MATCHA_HOME 'usermode\app.exe')
    $configured += (Join-Path $env:MATCHA_HOME 'app.exe')
  }
  foreach ($candidate in $configured) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
  }

  # Get-Process.Path can be empty for elevated processes. CIM sometimes exposes the path instead.
  $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq 'app' -or $_.ProcessName -match '^matcha' })
  $cimProcesses = @()
  try { $cimProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'app.exe' OR Name LIKE 'matcha%.exe'" -ErrorAction Stop) } catch {}
  # The process listening on the configured local MCP port is useful evidence even in a renamed folder.
  $listenerIds = @()
  try {
    $uri = [Uri]$McpUrl
    if ($uri.IsLoopback) {
      $listenerIds = @(Get-NetTCPConnection -State Listen -LocalPort $uri.Port -ErrorAction Stop |
        Where-Object { $_.LocalAddress -in @('127.0.0.1', '::1', '0.0.0.0', '::') } |
        Select-Object -ExpandProperty OwningProcess -Unique)
    }
  } catch {}
  $running = @(
    foreach ($proc in $processes) {
      $path = $null
      try { $path = $proc.Path } catch {}
      if (-not $path) { $path = ($cimProcesses | Where-Object { $_.ProcessId -eq $proc.Id } | Select-Object -First 1).ExecutablePath }
      if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
        if (($listenerIds -contains $proc.Id) -or $proc.MainWindowTitle -match '(?i)matcha' -or (Test-MatchaExecutable $path)) {
          [pscustomobject]@{ Path = $path; Listener = ($listenerIds -contains $proc.Id) }
        }
      }
    }
    foreach ($proc in $cimProcesses) {
      if ($proc.ExecutablePath -and (($listenerIds -contains $proc.ProcessId) -or (Test-MatchaExecutable $proc.ExecutablePath))) {
        [pscustomobject]@{ Path = $proc.ExecutablePath; Listener = ($listenerIds -contains $proc.ProcessId) }
      }
    }
  )
  $best = $running | Sort-Object Listener -Descending | Select-Object -First 1
  if ($best) { return (Resolve-Path -LiteralPath $best.Path).Path }

  $candidates = @()
  foreach ($drive in (Get-PSDrive -PSProvider FileSystem)) {
    $candidates += (Join-Path $drive.Root 'matcha\usermode\app.exe')
    $candidates += (Join-Path $drive.Root 'matcha\app.exe')
  }
  foreach ($base in @($env:LOCALAPPDATA, $env:APPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if ($base) {
      $candidates += (Join-Path $base 'Matcha\usermode\app.exe')
      $candidates += (Join-Path $base 'Matcha\app.exe')
    }
  }
  # Explicit workspace/heartbeat paths also point back to the installation.
  foreach ($workspace in @($WorkspaceRoot, $env:MATCHA_WORKSPACE, $(if ($Heartbeat) { Split-Path -Parent (Split-Path -Parent $Heartbeat) }))) {
    if ($workspace) {
      $root = Split-Path -Parent $workspace
      if ($root) {
        $candidates += (Join-Path $root 'usermode\app.exe')
        $candidates += (Join-Path $root 'app.exe')
      }
    }
  }
  foreach ($candidate in ($candidates | Select-Object -Unique)) {
    if (Test-MatchaExecutable $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
  }

  # Search nearby portable installs, not entire drives. No junction traversal; depth/work are bounded.
  $roots = @($PSScriptRoot, (Get-Location).Path)
  if ($PSScriptRoot) { $roots += Split-Path -Parent $PSScriptRoot }
  if ($env:USERPROFILE) { $roots += Join-Path $env:USERPROFILE 'Downloads' }
  $roots += [Environment]::GetFolderPath('Desktop')
  if ($env:LOCALAPPDATA) { $roots += Join-Path $env:LOCALAPPDATA 'Programs' }
  $queue = New-Object 'System.Collections.Generic.Queue[object]'
  foreach ($root in ($roots | Where-Object { $_ } | Select-Object -Unique)) {
    if (Test-Path -LiteralPath $root -PathType Container) { $queue.Enqueue(@{ Path = $root; Depth = 0 }) }
  }
  $visited = @{}
  $checked = 0
  while ($queue.Count -gt 0 -and $checked -lt 2000) {
    $entry = $queue.Dequeue()
    if ($visited.ContainsKey($entry.Path)) { continue }
    $visited[$entry.Path] = $true
    $checked++
    foreach ($name in @('app.exe', 'matcha.exe')) {
      $candidate = Join-Path $entry.Path $name
      if (Test-MatchaExecutable $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    if ($entry.Depth -ge 3) { continue }
    foreach ($dir in (Get-ChildItem -LiteralPath $entry.Path -Directory -ErrorAction SilentlyContinue)) {
      if (($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
      if ($dir.Name -in @('node_modules', '.git', 'Cache', 'CacheStorage', 'logs')) { continue }
      $queue.Enqueue(@{ Path = $dir.FullName; Depth = $entry.Depth + 1 })
    }
  }
  $unreadable = @($processes | Where-Object { -not $_.Path }).Count
  $hint = if ($unreadable) { ' An app.exe process has no readable path; if Matcha is elevated, run this watchdog at the same privilege level.' } else { '' }
  throw "Matcha app.exe not found in running processes or nearby install folders.$hint Pass -MatchaExe <full path to app.exe> for an unusual install."
}

function Get-OverlayKeyInfo {
  if ($OverlayKey -gt 0) { return [pscustomobject]@{ VirtualKey = $OverlayKey; Source = '-OverlayKey override' } }
  $paths = @()
  if ($WorkspaceRoot) { $paths += Join-Path (Split-Path -Parent $WorkspaceRoot) 'global.cfg' }
  if ($MatchaExe) {
    $folder = Split-Path -Parent $MatchaExe
    $paths += Join-Path $folder 'global.cfg'
    $paths += Join-Path (Split-Path -Parent $folder) 'global.cfg'
  }
  $paths += 'C:\matcha\global.cfg'
  foreach ($path in ($paths | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    try {
      $config = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
      $key = 0
      if ([int]::TryParse([string]$config.menukey, [ref]$key) -and $key -gt 0 -and $key -le 254) {
        return [pscustomobject]@{ VirtualKey = $key; Source = $path }
      }
    } catch {}
  }
  return [pscustomobject]@{ VirtualKey = 0x2D; Source = 'Matcha default (Insert)' }
}

function Find-WorkspaceRoot {
  $explicit = if ($WorkspaceRoot) { $WorkspaceRoot } elseif ($env:MATCHA_WORKSPACE) { $env:MATCHA_WORKSPACE } elseif ($Heartbeat) { Split-Path -Parent (Split-Path -Parent $Heartbeat) }
  if ($explicit -and -not (Test-Path -LiteralPath $explicit -PathType Container)) {
    throw "Workspace not found: $explicit"
  }
  # Matcha's file sandbox can be independent of the executable location.
  # This build uses C:\matcha\workspace even when app.exe is installed on D:.
  $standardWorkspace = 'C:\matcha\workspace'
  $exeFolder = Split-Path -Parent $MatchaExe
  $candidates = @($explicit, $standardWorkspace, (Join-Path $exeFolder 'workspace'), (Join-Path (Split-Path -Parent $exeFolder) 'workspace'))
  foreach ($drive in (Get-PSDrive -PSProvider FileSystem)) {
    $candidates += Join-Path $drive.Root 'matcha\workspace'
  }
  foreach ($base in @($env:LOCALAPPDATA, $env:APPDATA)) {
    if ($base) { $candidates += Join-Path $base 'Matcha\workspace' }
  }
  $candidates = @($candidates | Where-Object { $_ } | Select-Object -Unique)
  # Ask the running Matcha to create a unique marker through its own sandbox.
  # Only the directory containing that exact token is verified; never write a fake heartbeat.
  $token = [Guid]::NewGuid().ToString('N')
  $relative = "aotr/watchdog-probe-$token.txt"
  $lua = 'if not isfolder("aotr") then makefolder("aotr") end; writefile("' + $relative + '", "' + $token + '"); print("watchdog workspace probe written")'
  $probeSucceeded = $false
  try {
    $body = @{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = @{ name = 'matcha_exec'; arguments = @{ code = $lua } } } | ConvertTo-Json -Depth 6 -Compress
    $response = Invoke-RestMethod -Uri $McpUrl -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 3 -ErrorAction Stop
    if ($response.result -and -not $response.result.isError) {
      $probeSucceeded = (($response.result.content | ForEach-Object { $_.text }) -join '') -match 'watchdog workspace probe written'
    }
    foreach ($candidate in $candidates) {
      $marker = Join-Path $candidate $relative
      if ((Test-Path -LiteralPath $marker -PathType Leaf) -and
          (Get-Content -LiteralPath $marker -Raw -ErrorAction SilentlyContinue) -eq $token) {
        $verified = (Resolve-Path -LiteralPath $candidate).Path
        if ($explicit -and (Resolve-Path -LiteralPath $explicit).Path -ne $verified) {
          throw "The specified workspace '$explicit' differs from Matcha's verified workspace '$verified'. Remove the override."
        }
        $script:WorkspaceVerification = 'Verified through Matcha file API'
        return $verified
      }
    }
  } catch {
    if ($_.Exception.Message -like 'The specified workspace*') { throw }
    # Matcha may be closed, loading, or have MCP disabled. Use its documented default below.
  } finally {
    # Remove only our unique probe, through the same API that wrote it.
    try {
      $cleanup = @{ jsonrpc = '2.0'; id = 2; method = 'tools/call'; params = @{ name = 'matcha_exec'; arguments = @{ code = 'if isfile("' + $relative + '") then delfile("' + $relative + '") end' } } } | ConvertTo-Json -Depth 6 -Compress
      Invoke-RestMethod -Uri $McpUrl -Method Post -ContentType 'application/json' -Body $cleanup -TimeoutSec 3 -ErrorAction Stop | Out-Null
    } catch {}
  }
  if ($probeSucceeded) {
    throw "Matcha wrote a workspace probe outside the known folders. Pass -WorkspaceRoot <Matcha's actual workspace> and run again."
  }
  $fallback = if ($explicit) { $explicit } else { $standardWorkspace }
  $script:WorkspaceVerification = 'MCP unavailable; awaiting farm heartbeat'
  try {
    New-Item -ItemType Directory -Path $fallback -Force -ErrorAction Stop | Out-Null
    return (Resolve-Path -LiteralPath $fallback).Path
  } catch {
    throw "Cannot create Matcha workspace '$fallback': $($_.Exception.Message)"
  }
}


$MatchaExe = Find-MatchaExe
$WorkspaceRoot = Find-WorkspaceRoot
$aotrDir = Join-Path $WorkspaceRoot 'aotr'
if (-not $Heartbeat) { $Heartbeat = Join-Path $aotrDir 'heartbeat.txt' }
if (-not $Log) { $Log = Join-Path $aotrDir 'watchdog.txt' }
if (-not $BootLog) { $BootLog = Join-Path $aotrDir 'boot.txt' }
New-Item -ItemType Directory -Path $aotrDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $Log) -Force | Out-Null
if ($ShowWorkspace) {
  Write-Host "Matcha workspace: $WorkspaceRoot ($script:WorkspaceVerification)"
  Start-Process -FilePath explorer.exe -ArgumentList ('"{0}"' -f $WorkspaceRoot)
  return
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class AotrWin {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int index);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint mapType);
}
"@

function Write-Log([string]$msg) {
  $line = "{0} {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
  # No console output: a click or text selection in the console window pauses any write to it,
  # and that froze the whole watchdog for 10+ minutes (22:38-22:48, 2026-11-01). Run it hidden
  # and read the log file instead.
  # Status lines every 30s add up; keep the newest half once the file passes ~200 KB.
  if ((Test-Path $Log) -and (Get-Item $Log).Length -gt 200KB) {
    $keep = Get-Content $Log -Tail 1500
    Set-Content -Path $Log -Value $keep -Encoding utf8
  }
  # Another reader holding the file (a `tail -F` did, 22:38-22:51 on 2026-11-01) made every write
  # fail silently; retry briefly instead of losing the line.
  for ($try = 0; $try -lt 5; $try++) {
    try { Add-Content -Path $Log -Value $line -Encoding utf8 -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 200 }
  }
  $script:lastLogAt = Get-Date
}

function Send-Key([byte]$vk, [int]$holdMs, [int]$afterMs) {
  [AotrWin]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds $holdMs
  [AotrWin]::keybd_event($vk, 0, 2, [UIntPtr]::Zero)   # KEYEVENTF_KEYUP
  Start-Sleep -Milliseconds $afterMs
}

function Focus-Window($proc) {
  $h = $proc.MainWindowHandle
  if ($h -eq [IntPtr]::Zero) { return $false }
  if ([AotrWin]::IsIconic($h)) { [AotrWin]::ShowWindow($h, 9) | Out-Null }   # SW_RESTORE
  # Windows blocks focus stealing unless a key event just happened; a lone ALT tap allows it.
  [AotrWin]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
  [AotrWin]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
  [AotrWin]::SetForegroundWindow($h) | Out-Null
  Start-Sleep -Milliseconds 400
  return ([AotrWin]::GetForegroundWindow() -eq $h)
}

function Get-MatchaProc {
  $exe = [IO.Path]::GetFileNameWithoutExtension($MatchaExe)
  Get-Process -Name $exe -ErrorAction SilentlyContinue | Where-Object { ($_.Path -eq $MatchaExe -or -not $_.Path) -and $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.Responding } | Select-Object -First 1
}

# Refresh the process before each style read; an invalid/replaced window is unknown, not closed.
function Test-OverlayOpen($m) {
  if (-not $m) { return $null }
  try { $m.Refresh() } catch { return $null }
  $handle = $m.MainWindowHandle
  if ($handle -eq [IntPtr]::Zero -or -not [AotrWin]::IsWindow($handle)) { return $null }
  return (([AotrWin]::GetWindowLong($handle, -20) -band 0x20) -eq 0)
}

function Send-OverlayToggle([int]$key) {
  $scan = [byte][AotrWin]::MapVirtualKey([uint32]$key, 0)
  $flags = if ($key -in @(0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x2D,0x2E)) { 1 } else { 0 }
  [AotrWin]::keybd_event([byte]$key, $scan, [uint32]$flags, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 150
  [AotrWin]::keybd_event([byte]$key, $scan, [uint32]($flags -bor 2), [UIntPtr]::Zero)
}

# Use the user's saved menu toggle; Insert is the default. Read it again if changed while running.
function Close-Overlay($m) {
  $keyInfo = Get-OverlayKeyInfo
  $presses = 0
  $closed = $false
  for ($try = 1; $try -le 6; $try++) {
    $m = Get-MatchaProc
    $open = Test-OverlayOpen $m
    if ($null -eq $open) { Write-Log 'Matcha overlay window unavailable; close could not be verified'; break }
    if (-not $open) { $closed = $true; break }
    if (Focus-Window $m) {
      Send-OverlayToggle $keyInfo.VirtualKey
      $presses++
    }
    Start-Sleep -Milliseconds 500
  }
  if (-not $closed) {
    $open = Test-OverlayOpen (Get-MatchaProc)
    $closed = ($null -ne $open -and -not $open)
  }
  if ($closed) {
    Write-Log ("Matcha overlay closed (verified; key VK 0x{0:X2}, {1} presses; {2})" -f $keyInfo.VirtualKey, $presses, $keyInfo.Source)
  } else {
    Write-Log ("Matcha overlay close unverified after {0} presses (key VK 0x{1:X2}; {2})" -f $presses, $keyInfo.VirtualKey, $keyInfo.Source)
  }
  $roblox = Get-Process RobloxPlayerBeta -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
  if ($roblox) { Focus-Window $roblox | Out-Null }
  return $closed
}

function Stop-TeleportMatcha {
  if ($DryRun) { return }
  $exe = [IO.Path]::GetFileNameWithoutExtension($MatchaExe)
  Get-Process -Name $exe -ErrorAction SilentlyContinue |
    Where-Object { -not $_.Path -or $_.Path -eq $MatchaExe } |
    ForEach-Object {
      $target = $_
      try { $target | Stop-Process -Force -ErrorAction Stop }
      catch { Write-Log "Could not stop Matcha PID $($target.Id): $($_.Exception.Message)" }
    }
}

function Start-Matcha {
  Start-Process -FilePath $MatchaExe -WorkingDirectory (Split-Path $MatchaExe)
  $script:overlayStartupUntil = (Get-Date).AddSeconds(30)
  # A fresh Matcha opens its overlay, which swallows the farm's clicks.
  $deadline = (Get-Date).AddSeconds(20)
  do {
    Start-Sleep -Milliseconds 500
    $m = Get-MatchaProc
  } until ($m -or (Get-Date) -gt $deadline)
  if (-not $m) { Write-Log "Matcha window did not appear to close its overlay"; return }
  # The overlay can open a moment after the window does; give it up to 5s.
  $deadline = (Get-Date).AddSeconds(5)
  while ((Test-OverlayOpen $m) -ne $true -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250; $m = Get-MatchaProc }
  Close-Overlay $m | Out-Null
}

# Matcha's MCP is plain JSON-RPC over HTTP with no session; returns the tool's parsed JSON result,
# or $null when Matcha isn't listening (it drops after some teleports) or the call failed.
function Invoke-Matcha([string]$tool, [hashtable]$arguments) {
  $body = @{ jsonrpc = "2.0"; id = 1; method = "tools/call"; params = @{ name = $tool; arguments = $arguments } } | ConvertTo-Json -Depth 5 -Compress
  try {
    $r = Invoke-RestMethod -Uri $McpUrl -Method Post -ContentType "application/json" -Body $body -TimeoutSec 5
    if ($r.result.isError) { return $null }
    return ($r.result.content[0].text | ConvertFrom-Json)
  } catch { return $null }
}

# Matcha readfile paths are relative to its workspace. Discover the installed farm source for the
# optional -TryScriptRestart action; auto-exec remains the normal way to launch the farm.
if ($FarmReadPath) {
  if ([IO.Path]::IsPathRooted($FarmReadPath)) { throw '-FarmReadPath must be relative to Matcha workspace.' }
  $farmSources = @($FarmReadPath.Replace('\', '/'))
} else {
  $farmSources = @('aotr/autofarm.lua', 'aotr/autofarm_branch.lua', 'autofarm.lua') |
    Where-Object { Test-Path -LiteralPath (Join-Path $WorkspaceRoot $_) -PathType Leaf }
}
if ($FarmReadPath -and -not (Test-Path -LiteralPath (Join-Path $WorkspaceRoot $FarmReadPath) -PathType Leaf)) {
  throw "Farm source not found under Matcha workspace: $FarmReadPath"
}
$StartFarmLua = $null
if ($farmSources.Count -gt 0) {
  $normal = if ($farmSources -contains 'aotr/autofarm.lua') { 'aotr/autofarm.lua' } else { $farmSources[0] }
  $raid = if ($farmSources -contains 'aotr/autofarm_branch.lua') { 'aotr/autofarm_branch.lua' } else { $normal }
  $normalLua = ConvertTo-Json -InputObject $normal -Compress
  $raidLua = ConvertTo-Json -InputObject $raid -Compress
  $StartFarmLua = '_G.AotrStop = nil; local p = game.PlaceId == 14638336319 and ' + $normalLua + ' or ' + $raidLua + '; local f,e = loadstring(readfile(p), p); if f then task.spawn(f); print("farm spawned by watchdog: " .. p) else warn(e) end'
}
if ($ValidateOnly) {
  [pscustomobject]@{
    MatchaExe = $MatchaExe
    WorkspaceRoot = $WorkspaceRoot
    WorkspaceVerification = $script:WorkspaceVerification
    Heartbeat = $Heartbeat
    BootLog = $BootLog
    Log = $Log
    FarmSources = $farmSources -join ', '
    RobloxLogDir = $RobloxLogDir
    ScriptRestartAvailable = [bool]$StartFarmLua
    OverlayKey = (Get-OverlayKeyInfo).VirtualKey
    OverlayKeySource = (Get-OverlayKeyInfo).Source
  }
  return
}

function Press-Retry {
  # Same sequence and timings as PressRetry() in autofarm.lua.
  Send-Key 0xDC 300 1000   # \  (UI navigation)
  Send-Key 0x44 200 400    # D
  Send-Key 0x44 200 400    # D
  Send-Key 0x0D 300 600    # Enter
}

Write-Log ("watchdog started (stale {0}s, cooldown {1}s{2})" -f $StaleSeconds, $CooldownSeconds, $(if ($DryRun) { ", dry run" } else { "" }))
Write-Log ("auto-discovered Matcha={0}; workspace={1}; farm sources={2}" -f $MatchaExe, $WorkspaceRoot, $(if ($farmSources.Count) { $farmSources -join ', ' } else { '(none)' }))
if ($TryScriptRestart -and -not $StartFarmLua) { Write-Log 'farm source not found; script restart disabled (Matcha restart and Retry remain available)' }
Write-Host "Matcha: $MatchaExe"
Write-Host "Workspace: $WorkspaceRoot ($script:WorkspaceVerification)"
Write-Host "Heartbeat: $Heartbeat"
Write-Host 'Leave this window running. Workspace path shown above. Stop with Ctrl+C.'
$heartbeatSeen = Test-Path -LiteralPath $Heartbeat -PathType Leaf
if (-not $heartbeatSeen) { Write-Host 'Waiting for the farm to write its first heartbeat; farm-stall recovery is paused.' }
$lastAction = [DateTime]::MinValue
$attempts = 0
$retriesSinceMatcha = $null # null until the first Matcha restart of a stall
$lastReported = ""
$hungSince = $null
$overlaySince = $null
$script:overlayStartupUntil = (Get-Date).AddSeconds(30)
$currentJob = ""
$jobSince = Get-Date
$mcpDownSince = $null
$retrySince = $null
$teleportSince = $null   # -RestartOnTeleport: set while Matcha is closed, waiting for the next join
$joinSeen = $false
$rbxLog = $null; $rbxOffset = 0L; $rbxCarry = ""

# New lines in Roblox's client log since the last call (reads only the appended bytes, shared, so
# Roblox keeps writing). Follows a newer log file when Roblox restarts.
function Read-RobloxLog {
  # The directory listing's Length and LastWriteTime lag far behind for a log Roblox still has
  # open, so the real length comes from the stream. Crash-handler logs are skipped.
  $newest = Get-ChildItem $RobloxLogDir -Filter '*_Player_*.log' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'CrashHandler' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $newest) { return @() }
  try {
    $fs = [IO.File]::Open($newest.FullName, 'Open', 'Read', 'ReadWrite, Delete')
    try {
      if ($newest.FullName -ne $script:rbxLog) { $script:rbxLog = $newest.FullName; $script:rbxOffset = $fs.Length; return @() }
      if ($fs.Length -le $script:rbxOffset) { return @() }
      [void]$fs.Seek($script:rbxOffset, 'Begin')
      $text = (New-Object IO.StreamReader($fs)).ReadToEnd()
      $script:rbxOffset = $fs.Length
    } finally { $fs.Close() }
    # Keep an unfinished last line for the next read, so a marker split across reads still matches.
    $parts = ($script:rbxCarry + $text) -split "`n"
    $script:rbxCarry = $parts[-1]
    if ($parts.Count -gt 1) { return $parts[0..($parts.Count - 2)] } else { return @() }
  } catch { return @() }
}
if ($RestartOnTeleport) { [void](Read-RobloxLog) } # start at the end of the current log

while ($true) {
  if ($teleportSince) { Start-Sleep -Milliseconds 100 } else { Start-Sleep -Seconds $PollSeconds }
  # -RestartOnTeleport: Matcha's own reload after a teleport is the unreliable step (it hangs or
  # skips auto-exec), so close it as the teleport starts and launch a fresh one, which runs
  # auto-exec reliably, once Roblox has joined the next server.
  if ($RestartOnTeleport) {
    foreach ($l in (Read-RobloxLog)) {
      if ($l -match 'doTeleport: url' -and -not $teleportSince) {
        $teleportSince = Get-Date; $joinSeen = $false
        Write-Log "teleport started - closing Matcha until the next server is joined"
        Stop-TeleportMatcha
      } elseif ($teleportSince -and $l -match "Joining game '([0-9a-f-]+)' place (\d+)") {
        $joinSeen = $true; $joinInfo = "$($Matches[1].Substring(0,8)) place $($Matches[2])"
      } elseif ($teleportSince -and $joinSeen -and $l -match 'Replicator created for player') {
        Write-Log ("joined {0} after {1:N0}s - starting Matcha" -f $joinInfo, ((Get-Date) - $teleportSince).TotalSeconds)
        $teleportSince = $null
        Stop-TeleportMatcha
        if (-not $DryRun) { Start-Matcha }
        $lastAction = Get-Date; $attempts = 0; $retriesSinceMatcha = $null; $lastReported = ""
      }
    }
    if ($teleportSince) {
      # Matcha may respawn itself during the loading screen. Keep it closed until our launch.
      Stop-TeleportMatcha
      if (((Get-Date) - $teleportSince).TotalSeconds -lt $JoinTimeoutSeconds) { continue }
      Write-Log ("no join in Roblox's log after {0}s - starting Matcha anyway" -f $JoinTimeoutSeconds)
      $teleportSince = $null
      if (-not $DryRun) { Start-Matcha }
      $lastAction = Get-Date
      continue
    }
  }
  if (((Get-Date) - $script:lastLogAt).TotalSeconds -ge $StatusSeconds) {
    $hbAge = if (Test-Path $Heartbeat) { "{0:N0}s old" -f ((Get-Date) - (Get-Item $Heartbeat).LastWriteTime).TotalSeconds } else { "missing" }
    Write-Log ("status: {0}, farm heartbeat {1}" -f $(if ($lastReported) { $lastReported } else { "starting" }), $hbAge)
  }
  $proc = Get-Process RobloxPlayerBeta -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
  if (-not $proc) { if ($lastReported -ne "noroblox") { Write-Log "Roblox not running, idle"; $lastReported = "noroblox" }; continue }
  # Path is empty when the process runs elevated; never start a second copy over that.
  $exeName = [IO.Path]::GetFileNameWithoutExtension($MatchaExe)
  $matcha = Get-Process -Name $exeName -ErrorAction SilentlyContinue | Where-Object { -not $_.Path -or $_.Path -eq $MatchaExe } | Select-Object -First 1
  if (-not $matcha) {
    if ($lastReported -ne "nomatcha") { Write-Log "Matcha (app.exe) is not running"; $lastReported = "nomatcha" }
    if ($RestartMatcha -and ((Get-Date) - $lastAction).TotalSeconds -ge $CooldownSeconds) {
      $lastAction = Get-Date
      if ($DryRun) { Write-Log "would start $MatchaExe" }
      else { Write-Log "starting $MatchaExe"; Start-Matcha }
    }
    continue
  }
  # A hung Matcha (seen reloading after a teleport) leaves its frozen overlay over Roblox and never
  # runs auto-exec. Windows flags its window as not responding; restart it if that lasts.
  if (-not $matcha.Responding) {
    if (-not $hungSince) { $hungSince = Get-Date }
    $hungFor = ((Get-Date) - $hungSince).TotalSeconds
    if ($RestartMatcha -and $hungFor -ge $HungSeconds) {
      $hungSince = $null
      $lastAction = Get-Date
      if ($DryRun) { Write-Log ("Matcha not responding for {0:N0}s - would restart it" -f $hungFor); continue }
      Write-Log ("Matcha not responding for {0:N0}s - restarting it" -f $hungFor)
      $matcha | Stop-Process -Force
      Start-Sleep -Seconds 2
      Start-Matcha
      $attempts = 0
    }
    continue
  }
  $hungSince = $null

  # An overlay left open (or reopened) blocks the farm's input; close it once it has stayed open
  # OverlaySeconds, which leaves time to use the menu by hand.
  if ($matcha.MainWindowHandle -ne [IntPtr]::Zero -and (Test-OverlayOpen $matcha)) {
    if (-not $overlaySince) { $overlaySince = Get-Date }
    if (-not $DryRun -and ((Get-Date) -lt $script:overlayStartupUntil -or ((Get-Date) - $overlaySince).TotalSeconds -ge $OverlaySeconds)) {
      Write-Log ("Matcha overlay open {0:N0}s - closing it" -f ((Get-Date) - $overlaySince).TotalSeconds)
      Close-Overlay $matcha | Out-Null
      $overlaySince = $null
    }
  } else { $overlaySince = $null }

  if (-not $heartbeatSeen) {
    if (Test-Path -LiteralPath $Heartbeat -PathType Leaf) {
      $heartbeatSeen = $true
      $jobSince = Get-Date
      $lastAction = Get-Date
      Write-Log 'first farm heartbeat found; farm-stall recovery enabled'
    } else {
      if ($lastReported -ne 'waitingforfarm') { Write-Log "waiting for the farm to write $Heartbeat; farm-stall recovery paused"; $lastReported = 'waitingforfarm' }
      continue
    }
  }

  $age = [double]::MaxValue
  $state = ""
  if (Test-Path $Heartbeat) {
    $age = ((Get-Date) - (Get-Item $Heartbeat).LastWriteTime).TotalSeconds
    $state = ((Get-Content $Heartbeat -Raw -ErrorAction SilentlyContinue) -split " ")[0]
  }
  if ($state -eq "unloaded") {
    if ($lastReported -ne "unloaded") { Write-Log "farm unloaded by hand, standing down"; $lastReported = "unloaded" }
    $attempts = 0
    continue
  }

  # Fast path for a hang mid-mission: the farm beats every second while it is making progress, and
  # a hung Matcha stops the hover, so the character falls and dies ~30s later. Restart Matcha as
  # soon as a "farming" beat is FastStaleSeconds old, before the MCP query below (which blocks for
  # its 5s timeout on a hung Matcha). The cooldown still gives a fresh Matcha time to load. After
  # two fast restarts that did not bring the beat back (e.g. back in the lobby, where the farm does
  # not run), fall through to the MCP-aware handling below.
  if ($RestartMatcha -and $state -eq "farming" -and $age -ge $FastStaleSeconds -and $attempts -lt 2 -and ((Get-Date) - $lastAction).TotalSeconds -ge $CooldownSeconds) {
    $lastAction = Get-Date; $attempts++; $retriesSinceMatcha = 0; $lastReported = "stale"
    if ($DryRun) { Write-Log ("farm heartbeat {0:N0}s old - would restart Matcha (attempt {1})" -f $age, $attempts); continue }
    Write-Log ("farm heartbeat {0:N0}s old - restarting Matcha (attempt {1})" -f $age, $attempts)
    Get-Process -Name $exeName -ErrorAction SilentlyContinue | Where-Object { -not $_.Path -or $_.Path -eq $MatchaExe } | Stop-Process -Force
    Start-Sleep -Milliseconds 500
    Start-Matcha
    continue
  }

  # Ask Matcha where it is. Its MCP answers even when auto-exec never started the farm, so this
  # catches "Matcha is up but the script isn't" without trusting an old heartbeat.
  $status = Invoke-Matcha "matcha_status" @{}
  if ($status) { $mcpDownSince = $null } elseif (-not $mcpDownSince) { $mcpDownSince = Get-Date }
  if ($status) {
    if ([string][int64]$status.place_id -eq $LobbyPlaceId) {
      if ($lastReported -ne "lobby") { Write-Log "in the lobby, standing down"; $lastReported = "lobby" }
      $attempts = 0
      continue
    }
    # Give each new server time to load and start the farm before calling it stalled.
    $job = [string]$status.job_id
    if ($job -ne $currentJob) { $currentJob = $job; $jobSince = Get-Date }
    $stale = [math]::Min($age, ((Get-Date) - $jobSince).TotalSeconds)
    $limit = $ScriptStaleSeconds
  } else {
    # MCP down: fall back to the heartbeat alone, as before.
    if ($state -ne "farming" -and $state -ne "recovering") {
      if ($lastReported -ne "mcpdown-$state") { Write-Log "Matcha MCP not answering, farm state '$state', standing down"; $lastReported = "mcpdown-$state" }
      $attempts = 0
      continue
    }
    $stale = $age
    $limit = $StaleSeconds
    # A reload that never brings the MCP or the farm back (seen 21:09, 2026-11-01) left the
    # character undefended for the full StaleSeconds.
    if ($RestartMatcha -and ((Get-Date) - $mcpDownSince).TotalSeconds -ge $McpDownSeconds) { $limit = $McpDownSeconds }
  }

  # The farm writes this marker once per recovery episode. Fresh loop activity must not
  # conceal a ragdoll/incomplete body; allow a short grace period, then use normal recovery.
  if ($state -eq 'recovering') {
    $stale = $age
    $limit = $CharacterRecoverySeconds
  }

  # A live retry loop continues writing the heartbeat, so heartbeat age alone never catches it.
  # The latest start/status marker distinguishes an active Retry screen from an old completed run.
  $retryMarker = Get-Content -LiteralPath $BootLog -Tail 200 -ErrorAction SilentlyContinue |
    Where-Object { $_ -match ' (start|exit: lobby|status: )' } | Select-Object -Last 1
  if ($retryMarker -match 'status: pressing retry') {
    if (-not $retrySince) { $retrySince = Get-Date }
    $retryAge = ((Get-Date) - $retrySince).TotalSeconds
    if ($RetryStuckSeconds -gt 0 -and $retryAge -ge $RetryStuckSeconds) {
      $stale = $retryAge
      $limit = $RetryStuckSeconds
    }
  } else { $retrySince = $null }

  if ($stale -lt $limit) {
    # Only a fresh heartbeat counts as recovered. The MCP flapping down switches to the longer
    # StaleSeconds limit, and an old heartbeat under it used to log "back" and reset the attempts
    # (seen 21:49:47, 2026-11-01), delaying the Matcha restart by another ~40s.
    if ($age -ge $ScriptStaleSeconds -and $lastReported -eq "stale") { continue }
    if ($lastReported -ne "ok") { if ($attempts -gt 0) { Write-Log "heartbeat back after $attempts attempt(s)" } else { Write-Log "heartbeat ok" }; $lastReported = "ok" }
    $attempts = 0
    $retriesSinceMatcha = $null
    continue
  }
  if (((Get-Date) - $lastAction).TotalSeconds -lt $CooldownSeconds) { continue }

  # The farm isn't running: auto-exec didn't fire, or the script or Matcha stalled. A fresh Matcha
  # reruns auto-exec reliably (5 of 5 on 2026-11-01), so it goes first, then -RestartAfterAttempts
  # Retry presses (for a rewards screen nobody is pressing), and repeat. The step used to be picked
  # as attempts % plan, where the plan changed shape with the MCP up or down, so flapping skipped
  # the restart (22:18-22:20 on 2026-11-01: script, Retry, Retry).
  $lastAction = Get-Date
  if ($attempts -eq 0 -and $TryScriptRestart -and $StartFarmLua -and $status) { $step = "script" }
  elseif ($RestartMatcha -and ($null -eq $retriesSinceMatcha -or $retriesSinceMatcha -ge $RestartAfterAttempts)) { $step = "matcha"; $retriesSinceMatcha = 0 }
  else { $step = "retry"; if ($null -ne $retriesSinceMatcha) { $retriesSinceMatcha++ } }
  $attempts++
  $lastReported = "stale"
  $what = @{ script = "restart the farm script"; matcha = "restart Matcha"; retry = "press Retry" }[$step]
  if ($DryRun) { Write-Log ("farm silent {0:N0}s - would {1} (attempt {2})" -f $stale, $what, $attempts); continue }
  switch ($step) {
    "script" {
      $r = Invoke-Matcha "matcha_exec" @{ code = $StartFarmLua }
      if ($r -and $r.ok) { Write-Log ("farm silent {0:N0}s - restarted the farm script (attempt {1})" -f $stale, $attempts) }
      else { Write-Log ("farm silent {0:N0}s - could not start the farm script through the MCP (attempt {1})" -f $stale, $attempts) }
    }
    "matcha" {
      Write-Log ("farm stalled/recovering {0:N0}s - restarting Matcha to rerun auto-exec (attempt {1})" -f $stale, $attempts)
      Get-Process -Name $exeName -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $MatchaExe } | Stop-Process -Force
      Start-Sleep -Seconds 2
      Start-Matcha
    }
    "retry" {
      if (-not (Focus-Window $proc)) { Write-Log ("farm silent {0:N0}s - could not focus Roblox, retrying later" -f $stale); continue }
      Write-Log ("farm silent {0:N0}s - pressing Retry (attempt {1})" -f $stale, $attempts)
      Press-Retry
    }
  }
}
