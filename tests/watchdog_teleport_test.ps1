$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path $PSScriptRoot '..\watchdog\aotr_watchdog_portable.ps1') -Raw
function Assert($ok, $label) { if (-not $ok) { throw $label }; "PASS: $label" }
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0) 'watchdog parses'
$node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Start-Matcha'},$true)
Assert ($node.Extent.Text -notmatch 'Get-Process|already running|WaitForExit') 'launcher has no process guard or exit wait'
Assert ($source -notmatch 'watchdogMutex|Wait-TeleportMatchaExit|teleportLaunchPending|matchaLaunchSucceeded') 'duplicate protection and pending restart machinery removed'
$a=$source.IndexOf('  if ($RestartOnTeleport) {',$source.IndexOf('while ($true)'))
$b=$source.IndexOf('  if (((Get-Date) - $script:lastLogAt)',$a)
$branch=$source.Substring($a,$b-$a)
$MatchaExe='X:\Matcha\app.exe'; $RestartOnTeleport=$true; $DryRun=$false; $JoinTimeoutSeconds=60
$script:events=@(); $script:lines=@(); $teleportSince=$null; $joinSeen=$false
function Write-Log { param($msg) }
function Read-RobloxLog { $script:lines }
function Get-Process { param($Name,$ErrorAction) [pscustomobject]@{Path=$MatchaExe} }
function Stop-Process { param([Parameter(ValueFromPipeline=$true)]$InputObject,[switch]$Force) process { $script:events+='stop' } }
function Start-Matcha { $script:events+='start' }
$script:lines=@('doTeleport: url',"Joining game '12345678-1234-1234-1234-123456789abc' place 123",'Replicator created for player','Replicator created for player')
Invoke-Expression ('for($i=0;$i -lt 1;$i++){'+$branch+'}')
Assert (($script:events -join ',') -eq 'stop,start' -and -not $teleportSince) 'same-poll teleport stops then launches immediately on join, once'
$script:events=@(); $script:lines=@('doTeleport: url')
Invoke-Expression ('for($i=0;$i -lt 1;$i++){'+$branch+'}')
Assert (($script:events -join ',') -eq 'stop' -and $teleportSince) 'teleport closes Matcha while waiting for join'
$teleportSince=(Get-Date).AddSeconds(-61); $script:lines=@()
Invoke-Expression ('for($i=0;$i -lt 1;$i++){'+$branch+'}')
Assert (($script:events -join ',') -eq 'stop,start' -and -not $teleportSince) 'original join timeout launches Matcha'
$script:events=@(); $DryRun=$true
$script:lines=@('doTeleport: url',"Joining game '12345678-1234-1234-1234-123456789abc' place 123",'Replicator created for player')
Invoke-Expression ('for($i=0;$i -lt 1;$i++){'+$branch+'}')
Assert ($script:events.Count -eq 0) 'dry run never stops or starts Matcha'
