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

powershell -NoProfile -ExecutionPolicy Bypass -File $toolsScript `
  -Base $Base `
  -BuyerEmail $BuyerEmail `
  -BuyerPassword $BuyerPassword `
  -AdminEmail $AdminEmail `
  -AdminPassword $AdminPassword
