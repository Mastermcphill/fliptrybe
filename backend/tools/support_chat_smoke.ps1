param(
  [string]$Base = "https://tri-o-fliptrybe.onrender.com",
  [string]$AdminEmail = $(if ($env:ADMIN_EMAIL) { $env:ADMIN_EMAIL } else { "vidzimedialtd@gmail.com" }),
  [string]$AdminPassword = $(if ($env:ADMIN_PASSWORD) { $env:ADMIN_PASSWORD } else { "NewPass1234!" }),
  [string]$BuyerEmail = $env:BUYER_EMAIL,
  [string]$BuyerPassword = $env:BUYER_PASSWORD,
  [switch]$NegativeTests
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

function Ensure-Login {
  param(
    [string]$Email,
    [string]$Password,
    [string]$Role = "buyer",
    [string]$Name = "Smoke User",
    [string]$Phone = ""
  )

  $loginRes = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $Email; password = $Password }
  if (OkStatus $loginRes.StatusCode -and $loginRes.Json -and $loginRes.Json.token) {
    return [pscustomobject]@{
      Email = $Email
      Password = $Password
      Token = $loginRes.Json.token
    }
  }

  if ($loginRes.StatusCode -ne 401) {
    Write-Host "login body:" $loginRes.Body
    Fail "login failed for $Email"
  }

  $regPath = "/api/auth/register/$Role"
  $regPayload = @{
    name = $Name
    email = $Email
    password = $Password
    phone = $Phone
  }
  $regRes = Invoke-Api -Method "POST" -Path $regPath -BodyObj $regPayload
  Write-Host "register $Role ($Email):" $regRes.StatusCode
  if (-not (OkStatus $regRes.StatusCode)) {
    Write-Host $regRes.Body
    Fail "register failed for $Email"
  }

  $retry = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $Email; password = $Password }
  if (-not (OkStatus $retry.StatusCode) -or -not $retry.Json -or -not $retry.Json.token) {
    Write-Host "login retry body:" $retry.Body
    Fail "login retry failed for $Email"
  }
  return [pscustomobject]@{
    Email = $Email
    Password = $Password
    Token = $retry.Json.token
  }
}

function New-SmokeBuyer {
  param([string]$Prefix = "buyer_smoke")
  $rand = Get-Random
  return [pscustomobject]@{
    Email = "$Prefix`_$rand@t.com"
    Password = "TestPass123!"
    Name = "Smoke Buyer $rand"
    Phone = "+23480$rand"
  }
}

Write-Host "base:" $Base
Write-Host "endpoints: /api/support/messages, /api/admin/support/threads, /api/admin/support/messages/<user_id>"
$version = Invoke-Api -Path "/api/version"
Write-Host "version:" $version.StatusCode
if ($version.Body) { Write-Host "version body:" $version.Body }
Write-Host "health:" (Invoke-Api -Path "/api/health").StatusCode

if (-not $AdminEmail -or -not $AdminPassword) {
  Fail "Missing ADMIN_EMAIL/ADMIN_PASSWORD"
}

$adminLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email=$AdminEmail; password=$AdminPassword }
Write-Host "admin login:" $adminLogin.StatusCode
$safeAdmin = if ($AdminEmail) { $AdminEmail } else { "<missing>" }
Write-Host "admin email:" $safeAdmin
$adminToken = $adminLogin.Json.token
if (-not $adminToken) {
  if ($adminLogin.Body) { Write-Host $adminLogin.Body }
  Fail "admin token missing; cannot continue"
}
$adminHeaders = @{ Authorization = "Bearer $adminToken" }

$adminMe = Invoke-Api -Path "/api/auth/me" -Headers $adminHeaders
Write-Host "admin /me:" $adminMe.StatusCode
if (-not (OkStatus $adminMe.StatusCode)) { Fail "admin /me failed" }

$adminThreads0 = Invoke-Api -Path "/api/admin/support/threads" -Headers $adminHeaders
Write-Host "admin threads:" $adminThreads0.StatusCode
if (-not (OkStatus $adminThreads0.StatusCode)) { Fail "admin threads failed" }

if (-not $BuyerEmail) {
  $seedBuyer = New-SmokeBuyer -Prefix "buyer_smoke"
  $BuyerEmail = $seedBuyer.Email
  $BuyerPassword = $seedBuyer.Password
  $buyerName = $seedBuyer.Name
  $buyerPhone = $seedBuyer.Phone
} else {
  if (-not $BuyerPassword) { $BuyerPassword = "TestPass123!" }
  $buyerName = "Smoke Buyer Existing"
  $buyerPhone = "+2348099988877"
}

$buyerLogin = Ensure-Login -Email $BuyerEmail -Password $BuyerPassword -Role "buyer" -Name $buyerName -Phone $buyerPhone
$buyerToken = $buyerLogin.Token
$buyerHeaders = @{ Authorization = "Bearer $buyerToken" }
Write-Host "buyer login:" 200
Write-Host "buyer email:" $buyerLogin.Email

$buyerMe = Invoke-Api -Path "/api/auth/me" -Headers $buyerHeaders
Write-Host "buyer /me:" $buyerMe.StatusCode
if (-not (OkStatus $buyerMe.StatusCode)) { Fail "buyer /me failed" }

$userMsgBody = "Hello Admin smoke $(Get-Date -Format o)"
$buyerPost = Invoke-Api -Method "POST" -Path "/api/support/messages" -Headers $buyerHeaders -BodyObj @{ body=$userMsgBody }
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

$adminReplyBody = "Reply from Admin smoke $(Get-Date -Format o)"
$adminReply = Invoke-Api -Method "POST" -Path "/api/admin/support/messages/$threadUserId" -Headers $adminHeaders -BodyObj @{ body=$adminReplyBody }
Write-Host "admin reply:" $adminReply.StatusCode
if (-not (OkStatus $adminReply.StatusCode)) { Fail "admin reply failed" }

$buyerMsgs2 = Invoke-Api -Path "/api/support/messages" -Headers $buyerHeaders
Write-Host "buyer messages after reply:" $buyerMsgs2.StatusCode
if (-not (OkStatus $buyerMsgs2.StatusCode)) { Fail "buyer messages after reply failed" }
if (-not $buyerMsgs2.Json -or -not $buyerMsgs2.Json.items) { Fail "buyer messages shape invalid" }
$sawReply = $false
foreach ($it in @($buyerMsgs2.Json.items)) {
  if ($it.body -eq $adminReplyBody) { $sawReply = $true; break }
}
if (-not $sawReply) { Fail "admin reply not visible in user thread" }

if ($NegativeTests.IsPresent) {
  Write-Host "negative tests: user-to-user DM must fail with CHAT_NOT_ALLOWED"
  $u1 = New-SmokeBuyer -Prefix "buyer_a"
  $u2 = New-SmokeBuyer -Prefix "buyer_b"

  $userA = Ensure-Login -Email $u1.Email -Password $u1.Password -Role "buyer" -Name $u1.Name -Phone $u1.Phone
  $userB = Ensure-Login -Email $u2.Email -Password $u2.Password -Role "buyer" -Name $u2.Name -Phone $u2.Phone
  $hA = @{ Authorization = "Bearer $($userA.Token)" }
  $meB = Invoke-Api -Path "/api/auth/me" -Headers @{ Authorization = "Bearer $($userB.Token)" }
  if (-not (OkStatus $meB.StatusCode) -or -not $meB.Json -or -not $meB.Json.id) {
    Fail "negative test setup failed to resolve user B id"
  }
  $targetId = [int]$meB.Json.id

  $dm = Invoke-Api -Method "POST" -Path "/api/support/messages" -Headers $hA -BodyObj @{
    body = "DM attempt should fail $(Get-Date -Format o)"
    user_id = $targetId
  }
  Write-Host "negative user->user post:" $dm.StatusCode
  if ($dm.StatusCode -ne 403) {
    if ($dm.Body) { Write-Host $dm.Body }
    Fail "expected 403 for user-to-user chat attempt"
  }
  $dmErr = ""
  try { $dmErr = (($dm.Json.error | Out-String).Trim()) } catch { $dmErr = "" }
  if ($dmErr -and (@("CHAT_NOT_ALLOWED", "chat_not_allowed") -notcontains $dmErr)) {
    if ($dm.Body) { Write-Host $dm.Body }
    Fail "expected CHAT_NOT_ALLOWED error code for user-to-user chat attempt"
  }
}

Write-Host "buyer generated email:" $buyerLogin.Email
Write-Host "OK: support chat smoke passed"
