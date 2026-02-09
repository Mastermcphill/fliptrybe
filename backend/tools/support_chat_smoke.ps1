param(
  [string]$Base = "https://tri-o-fliptrybe.onrender.com",
  [string]$AdminEmail = $env:ADMIN_EMAIL,
  [string]$AdminPassword = $env:ADMIN_PASSWORD,
  [string]$BuyerEmail = $env:BUYER_EMAIL,
  [string]$BuyerPassword = $env:BUYER_PASSWORD
)

$ErrorActionPreference = "Continue"

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

function Fail($msg) {
  Write-Host "FAIL:" $msg
  exit 1
}

function OkStatus($code) {
  return ($code -ge 200 -and $code -lt 300)
}

Write-Host "base:" $Base
$version = Invoke-Api -Path "/api/version"
Write-Host "version:" $version.StatusCode
if ($version.Body) { Write-Host "version body:" $version.Body }
Write-Host "health:" (Invoke-Api -Path "/api/health").StatusCode

if (-not $AdminEmail -or -not $AdminPassword) {
  Write-Host "Missing ADMIN_EMAIL/ADMIN_PASSWORD; skipping admin checks"
  exit 1
}

$adminLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email=$AdminEmail; password=$AdminPassword }
Write-Host "admin login:" $adminLogin.StatusCode
$safeAdmin = if ($AdminEmail) { $AdminEmail } else { "<missing>" }
Write-Host "admin email:" $safeAdmin
$adminToken = $adminLogin.Json.token
if (-not $adminToken) {
  Fail "admin token missing; cannot continue"
}
$adminHeaders = @{ Authorization = "Bearer $adminToken" }

$adminMe = Invoke-Api -Path "/api/auth/me" -Headers $adminHeaders
Write-Host "admin /me:" $adminMe.StatusCode
if (-not (OkStatus $adminMe.StatusCode)) { Fail "admin /me failed" }

$adminThreads0 = Invoke-Api -Path "/api/admin/support/threads" -Headers $adminHeaders
Write-Host "admin threads:" $adminThreads0.StatusCode
if (-not (OkStatus $adminThreads0.StatusCode)) { Fail "admin threads failed" }

if (-not $BuyerEmail -or -not $BuyerPassword) {
  Write-Host "Missing BUYER_EMAIL/BUYER_PASSWORD; skipping buyer checks"
  exit 0
}

$buyerLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email=$BuyerEmail; password=$BuyerPassword }
Write-Host "buyer login:" $buyerLogin.StatusCode
$safeBuyer = if ($BuyerEmail) { $BuyerEmail } else { "<missing>" }
Write-Host "buyer email:" $safeBuyer
$buyerToken = $buyerLogin.Json.token
if (-not $buyerToken) {
  if ($buyerLogin.StatusCode -eq 401) {
    $rand = Get-Random
    $genEmail = "buyer_smoke_$rand@t.com"
    $genPassword = "TestPass123!"
    $genPhone = "+23480$rand"
    $regRes = Invoke-Api -Method "POST" -Path "/api/auth/register/buyer" -BodyObj @{
      name = "Smoke Buyer $rand"
      email = $genEmail
      password = $genPassword
      phone = $genPhone
    }
    Write-Host "buyer register:" $regRes.StatusCode
    if (-not (OkStatus $regRes.StatusCode)) {
      Write-Host $regRes.Body
      Fail "buyer register failed"
    }
    $buyerLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email=$genEmail; password=$genPassword }
    Write-Host "buyer login (new):" $buyerLogin.StatusCode
    $buyerToken = $buyerLogin.Json.token
    $BuyerEmail = $genEmail
    $BuyerPassword = $genPassword
  }
  if (-not $buyerToken) {
    Fail "buyer token missing; cannot continue"
  }
}
$buyerHeaders = @{ Authorization = "Bearer $buyerToken" }

$buyerMe = Invoke-Api -Path "/api/auth/me" -Headers $buyerHeaders
Write-Host "buyer /me:" $buyerMe.StatusCode
if (-not (OkStatus $buyerMe.StatusCode)) { Fail "buyer /me failed" }

$buyerPost = Invoke-Api -Method "POST" -Path "/api/support/messages" -Headers $buyerHeaders -BodyObj @{ body="Hello Admin. Test thread from user." }
Write-Host "buyer post:" $buyerPost.StatusCode
if (-not (OkStatus $buyerPost.StatusCode)) { Fail "buyer post failed" }

$buyerMsgs = Invoke-Api -Path "/api/support/messages" -Headers $buyerHeaders
Write-Host "buyer messages:" $buyerMsgs.StatusCode
if (-not (OkStatus $buyerMsgs.StatusCode)) { Fail "buyer messages failed" }

$adminThreads = Invoke-Api -Path "/api/admin/support/threads" -Headers $adminHeaders
Write-Host "admin threads after buyer:" $adminThreads.StatusCode
if (-not (OkStatus $adminThreads.StatusCode)) { Fail "admin threads after buyer failed" }

$buyerId = $buyerMe.Json.id
$threadUserId = $null
if ($adminThreads.Json -and $adminThreads.Json.threads) {
  $threadUserId = ($adminThreads.Json.threads | Where-Object { $_.user_id -eq $buyerId } | Select-Object -First 1).user_id
}
if (-not $threadUserId) { $threadUserId = $buyerId }
if (-not $threadUserId) { Fail "buyer_user_id not found" }

$adminReply = Invoke-Api -Method "POST" -Path "/api/admin/support/messages/$threadUserId" -Headers $adminHeaders -BodyObj @{ body="Reply from Admin" }
Write-Host "admin reply:" $adminReply.StatusCode
if (-not (OkStatus $adminReply.StatusCode)) { Fail "admin reply failed" }

$buyerMsgs2 = Invoke-Api -Path "/api/support/messages" -Headers $buyerHeaders
Write-Host "buyer messages after reply:" $buyerMsgs2.StatusCode
if (-not (OkStatus $buyerMsgs2.StatusCode)) { Fail "buyer messages after reply failed" }

Write-Host "buyer generated email:" $BuyerEmail
Write-Host "OK: support chat smoke passed"
