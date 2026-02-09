$ErrorActionPreference = "Continue"

param(
  [string]$Base = "https://tri-o-fliptrybe.onrender.com",
  [string]$AdminEmail = $env:ADMIN_EMAIL,
  [string]$AdminPassword = $env:ADMIN_PASSWORD,
  [string]$BuyerEmail = $env:BUYER_EMAIL,
  [string]$BuyerPassword = $env:BUYER_PASSWORD
)

function Invoke-Api {
  param([string]$Method="GET",[string]$Path,[hashtable]$Headers=@{},$BodyObj=$null)
  $url = "$Base$Path"
  try {
    if ($null -ne $BodyObj) {
      $body = ($BodyObj | ConvertTo-Json -Depth 20)
      $resp = Invoke-WebRequest -Method $Method -Uri $url -Headers $Headers -ContentType "application/json" -Body $body -UseBasicParsing
    } else {
      $resp = Invoke-WebRequest -Method $Method -Uri $url -Headers $Headers -UseBasicParsing
    }
    $json = $null
    try { $json = $resp.Content | ConvertFrom-Json } catch {}
    [pscustomobject]@{ StatusCode=[int]$resp.StatusCode; Body=$resp.Content; Json=$json }
  } catch {
    $status = -1
    $body = ""
    if ($_.Exception.Response) {
      $status = [int]$_.Exception.Response.StatusCode
      $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $body = $sr.ReadToEnd()
    } elseif ($_.ErrorDetails) { $body = $_.ErrorDetails.Message } else { $body = $_.Exception.Message }
    $json = $null
    try { $json = $body | ConvertFrom-Json } catch {}
    [pscustomobject]@{ StatusCode=$status; Body=$body; Json=$json }
  }
}

Write-Host "health:" (Invoke-Api -Path "/api/health").StatusCode
Write-Host "version:" (Invoke-Api -Path "/api/version").StatusCode

if (-not $AdminEmail -or -not $AdminPassword) {
  Write-Host "Missing ADMIN_EMAIL/ADMIN_PASSWORD; skipping admin checks"
  exit 1
}

$adminLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email=$AdminEmail; password=$AdminPassword }
Write-Host "admin login:" $adminLogin.StatusCode
$adminToken = $adminLogin.Json.token
if (-not $adminToken) {
  Write-Host "admin token missing; cannot continue"
  exit 1
}
$adminHeaders = @{ Authorization = "Bearer $adminToken" }

Write-Host "admin /me:" (Invoke-Api -Path "/api/auth/me" -Headers $adminHeaders).StatusCode
Write-Host "admin threads:" (Invoke-Api -Path "/api/admin/support/threads" -Headers $adminHeaders).StatusCode

if (-not $BuyerEmail -or -not $BuyerPassword) {
  Write-Host "Missing BUYER_EMAIL/BUYER_PASSWORD; skipping buyer checks"
  exit 0
}

$buyerLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email=$BuyerEmail; password=$BuyerPassword }
Write-Host "buyer login:" $buyerLogin.StatusCode
$buyerToken = $buyerLogin.Json.token
if (-not $buyerToken) {
  Write-Host "buyer token missing; cannot continue"
  exit 1
}
$buyerHeaders = @{ Authorization = "Bearer $buyerToken" }

Write-Host "buyer /me:" (Invoke-Api -Path "/api/auth/me" -Headers $buyerHeaders).StatusCode
Write-Host "buyer post:" (Invoke-Api -Method "POST" -Path "/api/support/messages" -Headers $buyerHeaders -BodyObj @{ body="Hello Admin. Test thread from user." }).StatusCode
Write-Host "buyer messages:" (Invoke-Api -Path "/api/support/messages" -Headers $buyerHeaders).StatusCode
