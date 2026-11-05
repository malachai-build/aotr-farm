$ErrorActionPreference='Stop'
$target=Join-Path $PSScriptRoot '..\watchdog\aotr_watchdog_portable.ps1'
$source=Get-Content -LiteralPath $target -Raw
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
foreach($name in @('Read-RobloxLog','Wait-TeleportMatchaExit','Start-Matcha')) {
 $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 Invoke-Expression $node.Extent.Text
}
function Assert($ok,$label){if(-not $ok){throw $label};Write-Output "PASS: $label"}
$script:messages=@()
function Write-Log([string]$msg){$script:messages+=$msg}
function Get-Process {param($Name,$ErrorAction)}
$RobloxLogDir=Join-Path ([IO.Path]::GetTempPath()) ('aotr-teleport-tests-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $RobloxLogDir -Force|Out-Null
$gameLog=Join-Path $RobloxLogDir 'old_Player_game.log'
$id='12345678-1234-1234-1234-123456789abc'
[IO.File]::WriteAllText($gameLog,"2026-11-05T20:00:00.000Z,0 Joining game '$id' place 123`n2026-11-05T20:00:00.100Z,0 Replicator created for player`n")
$idleLog=Join-Path $RobloxLogDir 'new_Player_idle.log'
[IO.File]::WriteAllText($idleLog,"2026-11-05T23:59:59.000Z,0 launcher initialized`n")
(Get-Item -LiteralPath $gameLog).LastWriteTime=(Get-Date).AddDays(-1)
(Get-Item -LiteralPath $idleLog).LastWriteTime=Get-Date
$script:rbxReaders=@{};$script:rbxInitialized=$false;$script:rbxLog=$null
$lines=@(Read-RobloxLog)
Assert ($script:rbxLog -eq $gameLog -and $lines.Count -eq 0) 'active game selected over newer idle log; startup history skipped'
[IO.File]::AppendAllText($gameLog,"2026-11-05T20:01:00.000Z,0 doTeleport: url`n2026-11-05T20:01:00.100Z,0 Joining game '$id' place 123`n2026-11-05T20:01:00.200Z,0 Replicator created")
(Get-Item -LiteralPath $gameLog).LastWriteTime=(Get-Date).AddDays(-1)
$lines=@(Read-RobloxLog)
Assert ($lines.Count -eq 2 -and $lines[0] -match 'doTeleport: url' -and $script:rbxLog -eq $gameLog) 'real growth detected despite stale directory timestamp; partial line retained'
[IO.File]::AppendAllText($gameLog," for player`n")
$lines=@(Read-RobloxLog)
Assert ($lines.Count -eq 1 -and $lines[0] -match 'Replicator created for player') 'split ready marker is emitted exactly once'
Assert (@(Read-RobloxLog).Count -eq 0) 'unchanged log never replays teleport events'
$newLog=Join-Path $RobloxLogDir 'latest_Player_game.log'
[IO.File]::WriteAllText($newLog,"2026-11-05T20:02:00.000Z,0 Joining game '$id' place 456`n2026-11-05T20:02:00.100Z,0 Replicator created for player`n")
$lines=@(Read-RobloxLog)
Assert ($script:rbxLog -eq $newLog -and $lines.Count -eq 2) 'new game log preserves its first join events'
[IO.File]::WriteAllText($newLog,"2026-11-05T20:03:00.000Z,0 Joining game '$id' place 789`n")
$lines=@(Read-RobloxLog)
Assert ($lines.Count -eq 1 -and $lines[0] -match 'place 789') 'truncated log resets offset and line buffer'
# Exercise the real teleport branch and Start-Matcha with an asynchronously exiting process.
$script:fakeExited=$false;$script:exitChecks=0;$script:failFirstWait=$false;$script:replacement=$false
$script:launches=0;$script:launchAttempts=0;$script:failFirstLaunch=$false;$script:reads=0
$old=[pscustomobject]@{Id=101;Path='X:\Matcha\app.exe'}
$old|Add-Member ScriptProperty HasExited { $script:fakeExited }
$old|Add-Member ScriptMethod WaitForExit {param($ms) $script:exitChecks++;if($script:failFirstWait -and $script:exitChecks -eq 1){return $false};$script:fakeExited=$true;return $true}
$MatchaExe='X:\Matcha\app.exe';$RestartOnTeleport=$true;$DryRun=$false;$JoinTimeoutSeconds=60
function Get-Process {
 param($Name,$ErrorAction)
 if($Name -eq 'app'){
  if(-not $script:fakeExited){return $old}
  if($script:replacement){return [pscustomobject]@{Id=202;Path=$MatchaExe}}
 }
}
function Stop-Process {param([Parameter(ValueFromPipeline=$true)]$InputObject,[switch]$Force) process {$script:stops++}}
function Start-Process {
 param($FilePath,$WorkingDirectory,[switch]$PassThru,$ErrorAction)
 $script:launchAttempts++
 if($script:failFirstLaunch -and $script:launchAttempts -eq 1){throw 'simulated transient launch failure'}
 $script:launches++;$script:replacement=$true;return [pscustomobject]@{Id=202}
}
function Start-Sleep {param($Milliseconds,$Seconds)}
function Get-MatchaProc {if($script:replacement){[pscustomobject]@{Id=202}}}
function Test-OverlayOpen {param($m) $true}
function Close-Overlay {param($m) $true}
function Read-RobloxLog {
 $script:reads++
 if($script:reads -eq 1){return @('doTeleport: url',"Joining game '$id' place 123",'Replicator created for player','Replicator created for player')}
 return @()
}
$a=$source.IndexOf('  if ($RestartOnTeleport) {',$source.IndexOf('while ($true)'))
$b=$source.IndexOf('  if (((Get-Date) - $script:lastLogAt)',$a)
$branch=$source.Substring($a,$b-$a)
function Reset-Fixture {
 $script:fakeExited=$false;$script:exitChecks=0;$script:replacement=$false
 $script:launches=0;$script:launchAttempts=0;$script:reads=0;$script:messages=@();$script:stops=0
 $script:teleportSince=$null;$script:teleportStopped=@();$script:teleportReadyAt=$null;$script:teleportLaunchPending=$false
 $script:lastAction=Get-Date # a recent recovery action must not block a teleport replacement
}
Reset-Fixture
Invoke-Expression ('for($iteration=0;$iteration -lt 1;$iteration++){'+$branch+'}')
Assert ($script:stops -eq 1 -and $script:exitChecks -eq 1 -and $script:launches -eq 1 -and -not $script:teleportSince) 'same-poll teleport/join waits for dying PID and launches exactly once'
Assert (($script:messages -join '') -match 'after join readiness') 'launch timing logged at process creation'
Reset-Fixture;$script:failFirstWait=$true
Invoke-Expression ('for($iteration=0;$iteration -lt 2;$iteration++){'+$branch+'}')
Assert ($script:exitChecks -eq 2 -and $script:launches -eq 1 -and -not $script:teleportSince) 'slow process exit remains pending and retries without recovery cooldown'
Reset-Fixture;$script:failFirstWait=$false;$script:failFirstLaunch=$true
Invoke-Expression ('for($iteration=0;$iteration -lt 2;$iteration++){'+$branch+'}')
Assert ($script:launchAttempts -eq 2 -and $script:launches -eq 1 -and -not $script:teleportSince) 'failed spawn remains pending and retries without a false success'

Reset-Fixture;$script:failFirstWait=$false;$script:failFirstLaunch=$false;$script:replacement=$true
Invoke-Expression ('for($iteration=0;$iteration -lt 1;$iteration++){'+$branch+'}')
Assert ($script:exitChecks -eq 1 -and $script:launches -eq 0 -and -not $script:teleportSince) 'a live replacement is reused without launching another copy'

