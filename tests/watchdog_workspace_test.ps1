$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot '..\watchdog\aotr_watchdog_portable.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($target, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$node = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Find-WorkspaceRoot'}, $true)
Invoke-Expression $node.Extent.Text
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('aotr-workspace-tests-' + [Guid]::NewGuid().ToString('N'))
$script:actual = Join-Path $fixture 'matcha\workspace'
$decoy = Join-Path $fixture 'renamed\workspace'
New-Item -ItemType Directory -Path $script:actual,$decoy -Force | Out-Null
$MatchaExe = Join-Path $fixture 'renamed\usermode\app.exe'
$WorkspaceRoot = $null; $Heartbeat = $null; $env:MATCHA_WORKSPACE = $null
$McpUrl = 'http://127.0.0.1:8765/mcp'
$script:offline = $false
function Get-PSDrive { param($PSProvider) [pscustomobject]@{Root=$fixture} }
function Invoke-RestMethod {
  param($Uri,$Method,$ContentType,$Body,$TimeoutSec,$ErrorAction)
  if ($script:offline) { throw 'MCP offline' }
  $request = $Body | ConvertFrom-Json
  $code = $request.params.arguments.code
  if ($code -match 'writefile\("([^"]+)", "([^"]+)"\)') {
    $marker = Join-Path $script:actual $Matches[1]
    New-Item -ItemType Directory -Path (Split-Path -Parent $marker) -Force | Out-Null
    [IO.File]::WriteAllText($marker, $Matches[2])
    return [pscustomobject]@{result=[pscustomobject]@{isError=$false;content=@([pscustomobject]@{text='watchdog workspace probe written'})}}
  }
  if ($code -match 'delfile\("([^"]+)"\)') {
    $marker = Join-Path $script:actual $Matches[1]
    if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker }
  }
}
function Assert($condition,$label) { if (-not $condition) { throw $label }; "PASS: $label" }
$result = Find-WorkspaceRoot
Assert ($result -eq $script:actual) 'live marker selects actual workspace over executable-adjacent decoy'
Assert ($script:WorkspaceVerification -eq 'Verified through Matcha file API') 'verified status reported'
Assert (@(Get-ChildItem -LiteralPath "$script:actual\aotr" -Filter 'watchdog-probe-*').Count -eq 0) 'probe cleaned up'
Assert (-not (Test-Path -LiteralPath "$script:actual\aotr\heartbeat.txt")) 'setup never fabricates farm heartbeat'
$WorkspaceRoot = $decoy
try { Find-WorkspaceRoot; throw 'Mismatch was accepted' } catch { Assert ($_.Exception.Message -like 'The specified workspace*') 'wrong explicit workspace rejected' }
$WorkspaceRoot = $script:actual
Assert ((Find-WorkspaceRoot) -eq $script:actual) 'correct explicit workspace verified'
$script:offline = $true
Assert ((Find-WorkspaceRoot) -eq $script:actual) 'offline explicit workspace accepted'
Assert ($script:WorkspaceVerification -like 'MCP unavailable*') 'offline status does not claim verification'
$script:offline = $false; $WorkspaceRoot = $null
$script:actual = Join-Path $fixture 'unknown-workspace'
try { Find-WorkspaceRoot; throw 'Unknown workspace was guessed' } catch { Assert ($_.Exception.Message -like 'Matcha wrote a workspace probe*') 'successful probe outside known locations fails clearly'
}
$content = Get-Content -LiteralPath $target -Raw
Assert ($content.IndexOf("if (-not `$heartbeatSeen) {", $content.IndexOf('while ($true)')) -lt $content.IndexOf('  # Fast path for a hang')) 'first-heartbeat gate precedes farm-stall actions'
Assert ($errors.Count -eq 0) 'Windows PowerShell syntax validation'
