param([int]$Age = 25, [string]$State = 'recovering')
$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot '..\watchdog\aotr_watchdog_portable.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('aotr-watchdog-loop-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fixture\workspace\aotr" -Force | Out-Null
$exe = Join-Path $fixture 'app.exe'
Set-Content -LiteralPath $exe -Value ''
$beat = Join-Path $fixture 'workspace\aotr\heartbeat.txt'
Set-Content -LiteralPath $beat -Value "$State test"
(Get-Item -LiteralPath $beat).LastWriteTime = (Get-Date).AddSeconds(-$Age)
function Get-Process {
  param($Name,$ErrorAction)
  if ($Name -eq 'RobloxPlayerBeta') { return [pscustomobject]@{MainWindowHandle=[IntPtr]1} }
  if ($Name -eq 'app') { return [pscustomobject]@{Path=$exe;Responding=$true;MainWindowHandle=[IntPtr]0} }
}
function Invoke-RestMethod { throw 'MCP disabled in loop fixture' }
function Add-Type { param($TypeDefinition) }
$script:polls = 0
function Start-Sleep {
  param($Seconds,$Milliseconds)
  if ($Seconds) { $script:polls++; if ($script:polls -gt 1) { throw 'END LOOP FIXTURE' } }
}
try {
  & $target -MatchaExe $exe -WorkspaceRoot "$fixture\workspace" -DryRun -RestartMatcha -CharacterRecoverySeconds 20
  throw 'Loop fixture did not stop'
} catch {
  if ($_.Exception.Message -ne 'END LOOP FIXTURE') { throw }
}
$log = Get-Content -LiteralPath "$fixture\workspace\aotr\watchdog.txt" -Raw
$acted = $log -match 'would restart Matcha'
$expected = $State -eq 'recovering' -and $Age -gt 20
if ($acted -ne $expected) { throw "Unexpected recovery for state=$State age=$Age`n$log" }
Write-Output "PASS: actual watchdog loop, state=$State age=$Age recovery=$acted"
