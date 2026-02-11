param(
  [string]$Base = "https://tri-o-fliptrybe.onrender.com",
  [string]$BuyerEmail = $env:BUYER_EMAIL,
  [string]$BuyerPassword = $env:BUYER_PASSWORD
)

$ErrorActionPreference = "Continue"

function Invoke-Api {
  param(
    [string]$Method = "GET",
    [string]$Path,
    [hashtable]$Headers = @{},
    $BodyObj = $null
  )
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
    [pscustomobject]@{ StatusCode = [int]$resp.StatusCode; Body = $resp.Content; Json = $json }
  } catch {
    $status = -1
    $body = ""
    if ($_.Exception.Response) {
      $status = [int]$_.Exception.Response.StatusCode
      $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $body = $sr.ReadToEnd()
    } elseif ($_.ErrorDetails) {
      $body = $_.ErrorDetails.Message
    } else {
      $body = $_.Exception.Message
    }
    $json = $null
    try { $json = $body | ConvertFrom-Json } catch {}
    [pscustomobject]@{ StatusCode = $status; Body = $body; Json = $json }
  }
}

function OkStatus($code) {
  return ($code -ge 200 -and $code -lt 300)
}

function Fail($message) {
  Write-Host "FAIL: $message"
  exit 1
}

function Ensure-Buyer {
  param(
    [string]$Email,
    [string]$Password
  )
  $login = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $Email; password = $Password }
  if (OkStatus $login.StatusCode -and $login.Json -and $login.Json.token) {
    return [pscustomobject]@{ Email = $Email; Password = $Password; Token = $login.Json.token }
  }

  if ($login.StatusCode -ne 401) {
    if ($login.Body) { Write-Host $login.Body }
    Fail "buyer login failed for $Email"
  }

  $register = Invoke-Api -Method "POST" -Path "/api/auth/register/buyer" -BodyObj @{
    name = "Verify Smoke Buyer"
    email = $Email
    password = $Password
    phone = "+23480$((Get-Random -Minimum 100000000 -Maximum 999999999))"
  }
  Write-Host "register buyer -> $($register.StatusCode)"
  if (-not (OkStatus $register.StatusCode)) {
    if ($register.Body) { Write-Host $register.Body }
    Fail "buyer register failed for $Email"
  }

  $retry = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $Email; password = $Password }
  if (-not (OkStatus $retry.StatusCode) -or -not $retry.Json -or -not $retry.Json.token) {
    if ($retry.Body) { Write-Host $retry.Body }
    Fail "buyer login retry failed for $Email"
  }
  return [pscustomobject]@{ Email = $Email; Password = $Password; Token = $retry.Json.token }
}

if (-not $BuyerEmail) {
  $BuyerEmail = "verify_smoke_$((Get-Random))@t.com"
}
if (-not $BuyerPassword) {
  $BuyerPassword = "TestPass123!"
}

Write-Host "base: $Base"
Write-Host "buyer email: $BuyerEmail"

$buyer = Ensure-Buyer -Email $BuyerEmail -Password $BuyerPassword
$headers = @{ Authorization = "Bearer $($buyer.Token)" }
$headersDebug = @{ Authorization = "Bearer $($buyer.Token)"; "X-Debug" = "1" }

$statusBefore = Invoke-Api -Method "GET" -Path "/api/auth/verify-email/status" -Headers $headers
Write-Host "GET /api/auth/verify-email/status -> $($statusBefore.StatusCode)"
if (-not (OkStatus $statusBefore.StatusCode)) {
  if ($statusBefore.Body) { Write-Host $statusBefore.Body }
  Fail "status before verify failed"
}

$resend = Invoke-Api -Method "POST" -Path "/api/auth/verify-email/resend" -Headers $headersDebug -BodyObj @{}
Write-Host "POST /api/auth/verify-email/resend -> $($resend.StatusCode)"
if (-not (OkStatus $resend.StatusCode)) {
  if ($resend.Body) { Write-Host $resend.Body }
  Fail "resend failed"
}
if ($resend.Json -and (($resend.Json.message | Out-String).Trim().ToLower().Contains("please wait"))) {
  Write-Host "resend rate-limited; waiting 61s and retrying..."
  Start-Sleep -Seconds 61
  $resend = Invoke-Api -Method "POST" -Path "/api/auth/verify-email/resend" -Headers $headersDebug -BodyObj @{}
  Write-Host "POST /api/auth/verify-email/resend (retry) -> $($resend.StatusCode)"
  if (-not (OkStatus $resend.StatusCode)) {
    if ($resend.Body) { Write-Host $resend.Body }
    Fail "resend retry failed"
  }
}

$mode = ""
$verificationLink = ""
if ($resend.Json) {
  $mode = (($resend.Json.mode | Out-String).Trim())
  $verificationLink = (($resend.Json.verification_link | Out-String).Trim())
}

if ([string]::IsNullOrWhiteSpace($mode)) {
  if ($resend.Body) { Write-Host $resend.Body }
  Fail "resend response missing mode"
}
Write-Host "resend mode: $mode"
if (-not [string]::IsNullOrWhiteSpace($verificationLink)) {
  Write-Host "verification_link: $verificationLink"
}

if ([string]::IsNullOrWhiteSpace($verificationLink)) {
  if ($mode -ne "live") {
    if ($resend.Body) { Write-Host $resend.Body }
    Fail "non-live resend did not return verification_link under X-Debug: 1"
  }
  Write-Host "verification_link not returned in live mode; skipping direct token confirmation."
  Write-Host "OK: email verification smoke passed (live-mode partial)."
  exit 0
}

try {
  $uri = [System.Uri]$verificationLink
  $token = [System.Web.HttpUtility]::ParseQueryString($uri.Query).Get("token")
} catch {
  $token = ""
}
if ([string]::IsNullOrWhiteSpace($token)) {
  Fail "verification_link did not include token query param"
}

$confirm = Invoke-Api -Method "GET" -Path "/api/auth/verify-email?token=$token"
Write-Host "GET /api/auth/verify-email?token=... -> $($confirm.StatusCode)"
if (-not (OkStatus $confirm.StatusCode)) {
  if ($confirm.Body) { Write-Host $confirm.Body }
  Fail "verify confirm failed"
}

$statusAfter = Invoke-Api -Method "GET" -Path "/api/auth/verify-email/status" -Headers $headers
Write-Host "GET /api/auth/verify-email/status (after) -> $($statusAfter.StatusCode)"
if (-not (OkStatus $statusAfter.StatusCode)) {
  if ($statusAfter.Body) { Write-Host $statusAfter.Body }
  Fail "status after verify failed"
}

$verified = $false
if ($statusAfter.Json) {
  try { $verified = [bool]$statusAfter.Json.verified } catch { $verified = $false }
}
if (-not $verified) {
  if ($statusAfter.Body) { Write-Host $statusAfter.Body }
  Fail "expected verified=true after confirmation"
}

Write-Host "OK: email verification smoke passed."
exit 0
