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
    if ($null -ne $Body) {
      $json = $Body | ConvertTo-Json -Depth 8
      return Invoke-RestMethod -Method $Method -Uri $Url -Headers $Headers -ContentType "application/json" -Body $json
    }
    return Invoke-RestMethod -Method $Method -Uri $Url -Headers $Headers
  } catch {
    $resp = $_.Exception.Response
    if ($null -ne $resp) {
      $status = [int]$resp.StatusCode
      $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
      $body = $reader.ReadToEnd()
      throw "HTTP $status on $Method $Url`n$body"
    }
    throw
  }
}

Write-Host "== FlipTrybe Ship Readiness Smoke =="
Write-Host "BASE: $Base"

Write-Host "`n[1] Version/health/public discovery"
$null = Invoke-JsonRequest -Method GET -Url "$Base/api/version"
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
}

Write-Host "`nSmoke run complete."
