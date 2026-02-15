param(
  [string]$Base = "https://tri-o-fliptrybe.onrender.com",
  [string]$BuyerEmail = "",
  [string]$BuyerPassword = "SmokePass123!",
  [string]$AdminEmail = "",
  [string]$AdminPassword = ""
)

$ErrorActionPreference = "Stop"
$toolsScript = Join-Path $PSScriptRoot "..\tools\ship_readiness_smoke.ps1"
if (-not (Test-Path $toolsScript)) {
  throw "Missing smoke script: $toolsScript"
}

$invokeArgs = @(
  "-NoProfile",
  "-ExecutionPolicy", "Bypass",
  "-File", $toolsScript,
  "-Base", $Base,
  "-BuyerPassword", $BuyerPassword
)

if (-not [string]::IsNullOrWhiteSpace($BuyerEmail)) {
  $invokeArgs += @("-BuyerEmail", $BuyerEmail)
}
if (-not [string]::IsNullOrWhiteSpace($AdminEmail)) {
  $invokeArgs += @("-AdminEmail", $AdminEmail)
}
if (-not [string]::IsNullOrWhiteSpace($AdminPassword)) {
  $invokeArgs += @("-AdminPassword", $AdminPassword)
}

& powershell @invokeArgs
