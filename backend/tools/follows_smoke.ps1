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

function Assert-True([bool]$value, [string]$message) {
  if (-not $value) {
    Write-Host $message
    exit 1
  }
}

function New-SmokeBuyer {
  $r = Get-Random
  return [pscustomobject]@{
    email = "buyer_follows_$r@t.com"
    password = "TestPass123!"
    name = "Buyer Follows $r"
    phone = "+23481$($r.ToString().Substring(0, [Math]::Min(7, $r.ToString().Length)))"
  }
}

function Get-MerchantIdFromListings([object]$json) {
  if (-not $json -or -not $json.items) { return 0 }
  foreach ($item in @($json.items)) {
    try {
      $mid = [int]($item.merchant_id)
      if ($mid -gt 0) { return $mid }
    } catch {}
  }
  return 0
}

Write-Host "follows smoke: base=$Base"

$adminLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $AdminEmail; password = $AdminPassword }
Assert-Ok $adminLogin "POST /api/auth/login (admin)"
Assert-True ($adminLogin.Json -and $adminLogin.Json.token) "Admin login did not return token."
$adminHeaders = @{ Authorization = "Bearer $($adminLogin.Json.token)"; "X-Debug" = "1" }

if (-not $BuyerEmail) {
  $buyer = New-SmokeBuyer
  $BuyerEmail = $buyer.email
  $BuyerPassword = $buyer.password
  $regBuyer = Invoke-Api -Method "POST" -Path "/api/auth/register/buyer" -BodyObj @{
    name = $buyer.name
    email = $buyer.email
    password = $buyer.password
    phone = $buyer.phone
  }
  Write-Host "POST /api/auth/register/buyer -> $($regBuyer.StatusCode)"
}
if (-not $BuyerPassword) { $BuyerPassword = "TestPass123!" }

$buyerLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $BuyerEmail; password = $BuyerPassword }
Assert-Ok $buyerLogin "POST /api/auth/login (buyer)"
Assert-True ($buyerLogin.Json -and $buyerLogin.Json.token) "Buyer login did not return token."
$buyerHeaders = @{ Authorization = "Bearer $($buyerLogin.Json.token)"; "X-Debug" = "1" }

$listings = Invoke-Api -Method "GET" -Path "/api/admin/listings?limit=20" -Headers $adminHeaders
Assert-Ok $listings "GET /api/admin/listings"
$merchantId = Get-MerchantIdFromListings $listings.Json
if ($merchantId -le 0) {
  $seed = Invoke-Api -Method "POST" -Path "/api/admin/demo/seed-listing" -Headers $adminHeaders -BodyObj @{}
  Write-Host "POST /api/admin/demo/seed-listing -> $($seed.StatusCode)"
  $listings = Invoke-Api -Method "GET" -Path "/api/admin/listings?limit=20" -Headers $adminHeaders
  Assert-Ok $listings "GET /api/admin/listings (after seed)"
  $merchantId = Get-MerchantIdFromListings $listings.Json
}
Assert-True ($merchantId -gt 0) "Could not resolve merchant_id for follow smoke."

$follow1 = Invoke-Api -Method "POST" -Path "/api/merchants/$merchantId/follow" -Headers $buyerHeaders -BodyObj @{}
Assert-Ok $follow1 "POST /api/merchants/{id}/follow (first)"
Assert-True (($follow1.Json.following -eq $true)) "Follow first call did not set following=true."

$follow2 = Invoke-Api -Method "POST" -Path "/api/merchants/$merchantId/follow" -Headers $buyerHeaders -BodyObj @{}
Assert-Ok $follow2 "POST /api/merchants/{id}/follow (idempotent)"
Assert-True (($follow2.Json.following -eq $true)) "Follow second call did not stay following=true."

$status1 = Invoke-Api -Method "GET" -Path "/api/merchants/$merchantId/follow-status" -Headers $buyerHeaders
Assert-Ok $status1 "GET /api/merchants/{id}/follow-status"
Assert-True (($status1.Json.following -eq $true)) "Follow status is not true after follow."

$myFollowing = Invoke-Api -Method "GET" -Path "/api/me/following-merchants?limit=20" -Headers $buyerHeaders
Assert-Ok $myFollowing "GET /api/me/following-merchants"
$followingPayloadOk = $false
if ($myFollowing.Json -is [array]) { $followingPayloadOk = $true }
elseif ($myFollowing.Json -and ($myFollowing.Json.PSObject.Properties.Name -contains "items")) { $followingPayloadOk = $true }
Assert-True $followingPayloadOk "Following merchants list missing items payload."

$merchantFollowersCount = Invoke-Api -Method "GET" -Path "/api/merchant/followers/count?merchant_id=$merchantId" -Headers $adminHeaders
Assert-Ok $merchantFollowersCount "GET /api/merchant/followers/count (admin)"

$merchantFollowers = Invoke-Api -Method "GET" -Path "/api/merchant/followers?merchant_id=$merchantId&limit=20" -Headers $adminHeaders
Assert-Ok $merchantFollowers "GET /api/merchant/followers (admin)"

$adminSearch = Invoke-Api -Method "GET" -Path "/api/admin/follows/search?q=$merchantId&limit=20" -Headers $adminHeaders
Assert-Ok $adminSearch "GET /api/admin/follows/search"

$unfollow1 = Invoke-Api -Method "DELETE" -Path "/api/merchants/$merchantId/follow" -Headers $buyerHeaders
Assert-Ok $unfollow1 "DELETE /api/merchants/{id}/follow (first)"
Assert-True (($unfollow1.Json.following -eq $false)) "Unfollow first call did not set following=false."

$unfollow2 = Invoke-Api -Method "DELETE" -Path "/api/merchants/$merchantId/follow" -Headers $buyerHeaders
Assert-Ok $unfollow2 "DELETE /api/merchants/{id}/follow (idempotent)"
Assert-True (($unfollow2.Json.following -eq $false)) "Unfollow second call did not stay following=false."

$status2 = Invoke-Api -Method "GET" -Path "/api/merchants/$merchantId/follow-status" -Headers $buyerHeaders
Assert-Ok $status2 "GET /api/merchants/{id}/follow-status (after unfollow)"
Assert-True (($status2.Json.following -eq $false)) "Follow status is not false after unfollow."

Write-Host "OK: follows smoke passed (merchant_id=$merchantId)"
exit 0
