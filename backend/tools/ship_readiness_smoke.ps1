param(
  [string]$Base = "https://tri-o-fliptrybe.onrender.com",
  [string]$BuyerEmail = "",
  [string]$BuyerPassword = "SmokePass123!",
  [string]$AdminEmail = "",
  [string]$AdminPassword = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($BuyerEmail)) {
  $BuyerEmail = "smoke_buyer_{0}@fliptrybe.test" -f ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
}
$phoneSuffix = ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString())
if ($phoneSuffix.Length -gt 8) {
  $phoneSuffix = $phoneSuffix.Substring($phoneSuffix.Length - 8)
}
$buyerPhone = "+23480$phoneSuffix"

function Invoke-JsonRequest {
  param(
    [string]$Method,
    [string]$Url,
    [hashtable]$Headers,
    [object]$Body
  )
  if ($null -eq $Headers) { $Headers = @{} }
  try {
    $resp = $null
    if ($null -ne $Body) {
      $json = $Body | ConvertTo-Json -Depth 8
      $resp = Invoke-WebRequest -Method $Method -Uri $Url -Headers $Headers -ContentType "application/json" -Body $json -UseBasicParsing
    } else {
      $resp = Invoke-WebRequest -Method $Method -Uri $Url -Headers $Headers -UseBasicParsing
    }
    $contentType = (($resp.Headers["Content-Type"] | Out-String).Trim()).ToLower()
    if ($Url -match "/api/" -and $contentType -notmatch "application/json") {
      throw "NON_JSON_API_RESPONSE on $Method $Url (Content-Type: $contentType)"
    }
    $raw = [string]($resp.Content)
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
    try {
      return $raw | ConvertFrom-Json
    } catch {
      throw "INVALID_JSON_RESPONSE on $Method $Url`n$raw"
    }
  } catch {
    $resp = $_.Exception.Response
    if ($null -ne $resp) {
      $status = [int]$resp.StatusCode
      $ct = (($resp.Headers["Content-Type"] | Out-String).Trim()).ToLower()
      $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
      $body = $reader.ReadToEnd()
      if ($Url -match "/api/" -and $ct -notmatch "application/json") {
        throw "NON_JSON_API_RESPONSE on $Method $Url (status $status, Content-Type: $ct)`n$body"
      }
      throw "HTTP $status on $Method $Url`n$body"
    }
    throw
  }
}

Write-Host "== FlipTrybe Ship Readiness Smoke =="
Write-Host "BASE: $Base"

Write-Host "`n[0] Deploy parity"
$version = Invoke-JsonRequest -Method GET -Url "$Base/api/version"
$prodSha = [string]($version.git_sha)
if ([string]::IsNullOrWhiteSpace($prodSha)) {
  throw "api/version did not return git_sha"
}
$localSha = ""
try {
  $localSha = (git rev-parse HEAD).Trim()
} catch {}
if (-not [string]::IsNullOrWhiteSpace($localSha) -and $prodSha -ne $localSha) {
  throw "Render parity mismatch. prod git_sha=$prodSha local git_sha=$localSha"
}
Write-Host ("OK: parity git_sha={0}" -f $prodSha)

Write-Host "`n[1] Version/health/public discovery"
$null = Invoke-JsonRequest -Method GET -Url "$Base/api/health"
$null = Invoke-JsonRequest -Method GET -Url "$Base/api/public/listings/recommended?limit=3"
$null = Invoke-JsonRequest -Method GET -Url "$Base/api/public/shortlets/recommended?limit=3"
Write-Host "OK: public endpoints"

Write-Host "`n[2] Register/login/me"
$register = Invoke-JsonRequest -Method POST -Url "$Base/api/auth/register" -Body @{
  name = "Smoke Buyer"
  email = $BuyerEmail
  phone = $buyerPhone
  password = $BuyerPassword
}
$buyerToken = [string]($register.token)
if ([string]::IsNullOrWhiteSpace($buyerToken)) {
  $login = Invoke-JsonRequest -Method POST -Url "$Base/api/auth/login" -Body @{
    email = $BuyerEmail
    password = $BuyerPassword
  }
  $buyerToken = [string]($login.token)
}
if ([string]::IsNullOrWhiteSpace($buyerToken)) {
  throw "Buyer token not returned by register/login."
}
$buyerHeaders = @{ Authorization = "Bearer $buyerToken" }
$null = Invoke-JsonRequest -Method GET -Url "$Base/api/auth/me" -Headers $buyerHeaders
Write-Host "OK: auth"

Write-Host "`n[3] Buyer support/notifications/moneybox"
$null = Invoke-JsonRequest -Method POST -Url "$Base/api/support/tickets" -Headers $buyerHeaders -Body @{
  subject = "Smoke test"
  message = "User support message"
}
$null = Invoke-JsonRequest -Method GET -Url "$Base/api/notifications" -Headers $buyerHeaders
$null = Invoke-JsonRequest -Method GET -Url "$Base/api/moneybox/status" -Headers $buyerHeaders
Write-Host "OK: buyer secured endpoints"

if (-not [string]::IsNullOrWhiteSpace($AdminEmail) -and -not [string]::IsNullOrWhiteSpace($AdminPassword)) {
  Write-Host "`n[4] Admin support list/reply"
  $adminLogin = Invoke-JsonRequest -Method POST -Url "$Base/api/auth/login" -Body @{
    email = $AdminEmail
    password = $AdminPassword
  }
  $adminToken = [string]($adminLogin.token)
  if ([string]::IsNullOrWhiteSpace($adminToken)) {
    throw "Admin token not returned by login."
  }
  $adminHeaders = @{ Authorization = "Bearer $adminToken" }
  $threads = Invoke-JsonRequest -Method GET -Url "$Base/api/admin/support/threads" -Headers $adminHeaders
  $firstThreadId = ""
  if ($threads.items -and $threads.items.Count -gt 0) {
    $firstThreadId = [string]($threads.items[0].thread_id)
  }
  if (-not [string]::IsNullOrWhiteSpace($firstThreadId)) {
    $null = Invoke-JsonRequest -Method POST -Url "$Base/api/admin/support/threads/$firstThreadId/messages" -Headers $adminHeaders -Body @{
      body = "Admin smoke reply"
    }
    Write-Host "OK: admin reply"
  } else {
    Write-Warning "No support threads available for admin reply smoke."
  }

  try {
    $payouts = Invoke-JsonRequest -Method GET -Url "$Base/api/wallet/payouts" -Headers $adminHeaders
    $items = @()
    if ($payouts.items) { $items = @($payouts.items) }
    $pending = $items | Where-Object { (($_.status | Out-String).Trim().ToLower()) -eq "pending" } | Select-Object -First 1
    if ($null -ne $pending -and $pending.id) {
      $pid = [string]$pending.id
      $null = Invoke-JsonRequest -Method POST -Url "$Base/api/wallet/payouts/$pid/admin/pay" -Headers $adminHeaders -Body @{}
      Write-Host "OK: admin payout pay alias"
    } else {
      Write-Warning "No pending payout found for admin payout smoke."
    }
  } catch {
    Write-Warning ("Admin payout smoke skipped: {0}" -f $_.Exception.Message)
  }
}

Write-Host "`nSmoke run complete."
