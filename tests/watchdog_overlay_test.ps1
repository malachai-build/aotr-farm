$ErrorActionPreference='Stop'
$target=Join-Path $PSScriptRoot '..\watchdog\aotr_watchdog_portable.ps1'
$source=Get-Content -LiteralPath $target -Raw
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
foreach($name in @('Get-OverlayKeyInfo','Close-Overlay','Start-Matcha')){
 $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 Invoke-Expression $node.Extent.Text
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('aotr-overlay-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fixture\workspace" -Force|Out-Null
$WorkspaceRoot="$fixture\workspace";$MatchaExe="$fixture\usermode\app.exe";$OverlayKey=0
# Isolate the real PC's saved setting while exercising actual config resolution.
function Test-Path {param($LiteralPath,$PathType) if($LiteralPath -eq 'C:\matcha\global.cfg'){return $false}; Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath -PathType $PathType}
function Assert($ok,$label){if(-not $ok){throw $label};"PASS: $label"}
Assert ((Get-OverlayKeyInfo).VirtualKey -eq 45) 'Insert default with no saved configuration'
Set-Content -LiteralPath "$fixture\global.cfg" -Value '{"menukey":39}'
Assert ((Get-OverlayKeyInfo).VirtualKey -eq 39) 'Right Arrow from saved Matcha config'
Set-Content -LiteralPath "$fixture\global.cfg" -Value '{"menukey":121}'
Assert ((Get-OverlayKeyInfo).VirtualKey -eq 121) 'custom F10 key from config'
$OverlayKey=36
Assert ((Get-OverlayKeyInfo).VirtualKey -eq 36) 'explicit key override'
$OverlayKey=0
Set-Content -LiteralPath "$fixture\global.cfg" -Value '{"menukey":999}'
Assert ((Get-OverlayKeyInfo).VirtualKey -eq 45) 'invalid saved key falls back to Insert'
Set-Content -LiteralPath "$fixture\global.cfg" -Value 'not json'
Assert ((Get-OverlayKeyInfo).VirtualKey -eq 45) 'malformed saved configuration falls back safely'
Set-Content -LiteralPath "$fixture\global.cfg" -Value '{"menukey":39}'
$script:open=$true;$script:focus=$true;$script:sent=@();$script:log=@();$script:starts=0;$script:exists=$true
function Get-MatchaProc { [pscustomobject]@{Id=123;MainWindowHandle=[IntPtr]1} }
function Test-OverlayOpen {param($m) $script:open}
function Focus-Window {param($m) $script:focus}
function Send-OverlayToggle {param($key) $script:sent+= $key;$script:open=$false}
function Write-Log {param($msg) $script:log+= $msg}
function Start-Sleep {param($Milliseconds,$Seconds)}
function Get-Process {param($Name,$ErrorAction) if($Name -eq 'app' -and $script:exists){[pscustomobject]@{Id=123;Path=$MatchaExe}}}
function Start-Process {param($FilePath,$WorkingDirectory) $script:starts++;$script:exists=$true}
Assert ((Close-Overlay $null) -and $script:sent.Count -eq 1 -and $script:sent[0] -eq 39) 'saved key closes an open overlay once'
$script:sent=@();Assert ((Close-Overlay $null) -and $script:sent.Count -eq 0) 'closed overlay never receives a reopening toggle'
$script:open=$true;$script:focus=$false;$script:log=@()
Assert (-not (Close-Overlay $null) -and $script:sent.Count -eq 0 -and ($script:log -join '') -match 'unverified') 'focus failure never reports a successful close'
$script:open=$null;$script:focus=$true;$script:log=@()
Assert (-not (Close-Overlay $null) -and ($script:log -join '') -match 'unavailable') 'missing window is unknown rather than closed'
$script:open=$true;$script:sent=@();Start-Matcha
Assert ($script:starts -eq 0 -and $script:sent.Count -eq 1 -and -not $script:open) 'existing Matcha still receives overlay cleanup without a second launch'
$script:exists=$false;$script:open=$true;$script:sent=@()
Set-Content -LiteralPath "$fixture\global.cfg" -Value '{}'
Start-Matcha
Assert ($script:starts -eq 1 -and $script:sent.Count -eq 1 -and $script:sent[0] -eq 45 -and -not $script:open) 'new Matcha launch closes default Insert overlay'
$loop=$source.IndexOf('while ($true)')
Assert ($source.IndexOf('  # An overlay left open',$loop) -lt $source.IndexOf('  if (-not $heartbeatSeen) {',$loop)) 'overlay cleanup runs before first-heartbeat wait'
