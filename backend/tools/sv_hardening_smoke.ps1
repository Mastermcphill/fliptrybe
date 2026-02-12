param(
  [string]$Base = "https://tri-o-fliptrybe.onrender.com",
  [string]$AdminEmail = $(if ($env:ADMIN_EMAIL) { $env:ADMIN_EMAIL } else { "vidzimedialtd@gmail.com" }),
  [string]$AdminPassword = $(if ($env:ADMIN_PASSWORD) { $env:ADMIN_PASSWORD } else { "NewPass1234!" })
)

$ErrorActionPreference = "Continue"
$failed = 0
$passed = 0

function Invoke-Api {
  param([string]$Method = "GET", [string]$Path, [hashtable]$Headers = @{}, $BodyObj = $null)
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
    return [pscustomobject]@{ StatusCode = [int]$resp.StatusCode; Json = $json; Body = $resp.Content; Method = $Method; Path = $Path }
  } catch {
    $status = -1
    $body = ""
    if ($_.Exception.Response) {
      $status = [int]$_.Exception.Response.StatusCode
      $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
      $body = $sr.ReadToEnd()
    } elseif ($_.ErrorDetails) {
      $body = $_.ErrorDetails.Message
    } else {
      $body = $_.Exception.Message
    }
    $json = $null
    try { $json = $body | ConvertFrom-Json } catch {}
    return [pscustomobject]@{ StatusCode = $status; Json = $json; Body = $body; Method = $Method; Path = $Path }
  }
}

function Check-Resp {
  param([object]$Resp, [string]$Label)
  $global:passed += 1
  Write-Host "$Label -> $($Resp.StatusCode)"
  if ($Resp.StatusCode -eq 404 -or $Resp.StatusCode -ge 500 -or $Resp.StatusCode -lt 0) {
    $global:failed += 1
    if ($Resp.Body) { Write-Host $Resp.Body }
  }
}

Write-Host "SV hardening smoke: $Base"
$version = Invoke-Api -Path "/api/version"
Check-Resp $version "GET /api/version"

$login = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $AdminEmail; password = $AdminPassword }
Check-Resp $login "POST /api/auth/login (admin)"
if (-not ($login.Json -and $login.Json.token)) {
  Write-Host "admin login token missing"
  exit 1
}

$headers = @{ Authorization = "Bearer $($login.Json.token)"; "X-Debug" = "1" }

$setFlags = Invoke-Api -Method "POST" -Path "/api/admin/autopilot/settings" -Headers $headers -BodyObj @{
  search_v2_mode = "shadow"
  payments_allow_legacy_fallback = $false
  otel_enabled = $false
  rate_limit_enabled = $true
}
Check-Resp $setFlags "POST /api/admin/autopilot/settings"

$auto = Invoke-Api -Path "/api/admin/autopilot" -Headers $headers
Check-Resp $auto "GET /api/admin/autopilot"

$features = Invoke-Api -Path "/api/public/features"
Check-Resp $features "GET /api/public/features"

$pubSearch = Invoke-Api -Path "/api/public/listings/search?q=iphone&limit=5"
Check-Resp $pubSearch "GET /api/public/listings/search"

$adminSearchListings = Invoke-Api -Path "/api/admin/listings/search?q=iphone&limit=5" -Headers $headers
Check-Resp $adminSearchListings "GET /api/admin/listings/search"

$globalSearch = Invoke-Api -Path "/api/admin/search?q=admin" -Headers $headers
Check-Resp $globalSearch "GET /api/admin/search"

$anomalies = Invoke-Api -Path "/api/admin/anomalies" -Headers $headers
Check-Resp $anomalies "GET /api/admin/anomalies"

$risk = Invoke-Api -Path "/api/admin/risk-events?limit=5" -Headers $headers
Check-Resp $risk "GET /api/admin/risk-events"

$orders = Invoke-Api -Path "/api/admin/orders" -Headers $headers
Check-Resp $orders "GET /api/admin/orders"
if ($orders.Json -and $orders.Json.items -and @($orders.Json.items).Count -gt 0) {
  $orderId = [int](@($orders.Json.items)[0].id)
  $timeline = Invoke-Api -Path "/api/admin/orders/$orderId/timeline" -Headers $headers
  Check-Resp $timeline "GET /api/admin/orders/$orderId/timeline"
  $reconcileOrder = Invoke-Api -Method "POST" -Path "/api/admin/orders/$orderId/reconcile" -Headers $headers -BodyObj @{}
  Check-Resp $reconcileOrder "POST /api/admin/orders/$orderId/reconcile"
  $escrowTransitions = Invoke-Api -Path "/api/admin/escrows/$orderId/transitions" -Headers $headers
  Check-Resp $escrowTransitions "GET /api/admin/escrows/$orderId/transitions"
  $escrowRecon = Invoke-Api -Method "POST" -Path "/api/admin/escrows/$orderId/reconcile" -Headers $headers -BodyObj @{}
  Check-Resp $escrowRecon "POST /api/admin/escrows/$orderId/reconcile"
}

if ($failed -gt 0) {
  Write-Host "FAILED: $failed endpoint checks failed."
  exit 1
}
Write-Host "OK: $passed checks passed."
exit 0
