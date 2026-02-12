param(
  [string]$Base = "https://tri-o-fliptrybe.onrender.com",
  [string]$AdminEmail = $(if ($env:ADMIN_EMAIL) { $env:ADMIN_EMAIL } else { "vidzimedialtd@gmail.com" }),
  [string]$AdminPassword = $(if ($env:ADMIN_PASSWORD) { $env:ADMIN_PASSWORD } else { "NewPass1234!" }),
  [string]$BuyerEmail = $env:BUYER_EMAIL,
  [string]$BuyerPassword = $env:BUYER_PASSWORD
)

$ErrorActionPreference = "Continue"

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
    return [pscustomobject]@{ StatusCode = [int]$resp.StatusCode; Body = $resp.Content; Json = $json; Url = $url; Method = $Method }
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
    return [pscustomobject]@{ StatusCode = $status; Body = $body; Json = $json; Url = $url; Method = $Method }
  }
}

function Assert-Ok([object]$resp, [string]$label) {
  Write-Host "$label -> $($resp.StatusCode)"
  if ($resp.StatusCode -lt 200 -or $resp.StatusCode -ge 300) {
    if ($resp.Body) { Write-Host $resp.Body }
    exit 1
  }
}

function Ensure-Buyer {
  param([string]$Email, [string]$Password)
  if (-not $Email) {
    $r = Get-Random
    $Email = "buyer_heat_$r@t.com"
    $Password = "TestPass123!"
    $phone = "+23480$($r.ToString().Substring(0, [Math]::Min(7, $r.ToString().Length)))"
    $reg = Invoke-Api -Method "POST" -Path "/api/auth/register/buyer" -BodyObj @{
      name = "Buyer Heat $r"
      email = $Email
      password = $Password
      phone = $phone
    }
    Write-Host "POST /api/auth/register/buyer -> $($reg.StatusCode)"
  }
  if (-not $Password) { $Password = "TestPass123!" }
  $login = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $Email; password = $Password }
  Assert-Ok $login "POST /api/auth/login (buyer)"
  return [pscustomobject]@{ Email = $Email; Token = $login.Json.token }
}

Write-Host "watchers heat smoke: base=$Base"
$adminLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $AdminEmail; password = $AdminPassword }
Assert-Ok $adminLogin "POST /api/auth/login (admin)"
$adminHeaders = @{ Authorization = "Bearer $($adminLogin.Json.token)"; "X-Debug" = "1" }

$toggle = Invoke-Api -Method "POST" -Path "/api/admin/autopilot/settings" -Headers $adminHeaders -BodyObj @{
  views_heat_v1 = $true
  watcher_notifications_v1 = $true
}
Assert-Ok $toggle "POST /api/admin/autopilot/settings"

$seed = Invoke-Api -Method "POST" -Path "/api/admin/demo/seed-nationwide" -Headers $adminHeaders -BodyObj @{}
Write-Host "POST /api/admin/demo/seed-nationwide -> $($seed.StatusCode)"

$buyer = Ensure-Buyer -Email $BuyerEmail -Password $BuyerPassword
$buyerHeaders = @{ Authorization = "Bearer $($buyer.Token)"; "X-Debug" = "1"; "X-Session-Key" = "heat-smoke-session" }

$publicListings = Invoke-Api -Method "GET" -Path "/api/public/listings/recommended?limit=10"
Assert-Ok $publicListings "GET /api/public/listings/recommended"
$listing = $null
if ($publicListings.Json -and $publicListings.Json.items) {
  $listing = @($publicListings.Json.items) | Select-Object -First 1
}
if (-not $listing) {
  Write-Host "No listing available for watcher heat smoke."
  exit 2
}
$listingId = [int]$listing.id

$favorite = Invoke-Api -Method "POST" -Path "/api/listings/$listingId/favorite" -Headers $buyerHeaders -BodyObj @{}
Assert-Ok $favorite "POST /api/listings/{id}/favorite"

$view = Invoke-Api -Method "POST" -Path "/api/listings/$listingId/view" -Headers $buyerHeaders -BodyObj @{ session_key = "heat-smoke-session" }
Assert-Ok $view "POST /api/listings/{id}/view"

$detail = Invoke-Api -Method "GET" -Path "/api/listings/$listingId" -Headers $buyerHeaders
Assert-Ok $detail "GET /api/listings/{id}"
$viewsCount = 0
$favCount = 0
$heat = "normal"
if ($detail.Json) {
  $viewsCount = [int]($detail.Json.views_count)
  $favCount = [int]($detail.Json.favorites_count)
  $heat = if ($detail.Json.heat_level) { [string]$detail.Json.heat_level } else { "normal" }
}
Write-Host "listing metrics: views=$viewsCount favorites=$favCount heat=$heat"

$queue = Invoke-Api -Method "GET" -Path "/api/admin/notify-queue?limit=20" -Headers $adminHeaders
Assert-Ok $queue "GET /api/admin/notify-queue"

$unfavorite = Invoke-Api -Method "DELETE" -Path "/api/listings/$listingId/favorite" -Headers $buyerHeaders
Assert-Ok $unfavorite "DELETE /api/listings/{id}/favorite"

Write-Host "OK: watchers heat smoke passed (listing_id=$listingId)"
exit 0
