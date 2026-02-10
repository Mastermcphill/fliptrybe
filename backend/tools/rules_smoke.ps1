param(
  [string]$Base = "https://tri-o-fliptrybe.onrender.com",
  [string]$AdminEmail = $env:ADMIN_EMAIL,
  [string]$AdminPassword = $env:ADMIN_PASSWORD,
  [string]$BuyerEmail = $env:BUYER_EMAIL,
  [string]$BuyerPassword = $env:BUYER_PASSWORD,
  [string]$MerchantEmail = $env:MERCHANT_EMAIL,
  [string]$MerchantPassword = $env:MERCHANT_PASSWORD
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

function Fail($msg) { Write-Host "FAIL:" $msg; exit 1 }
function OkStatus($code) { return ($code -ge 200 -and $code -lt 300) }

Write-Host "base:" $Base
$version = Invoke-Api -Method "GET" -Path "/api/version"
Write-Host "version:" $version.StatusCode
if ($version.Body) { Write-Host "version body:" $version.Body }

if (-not $AdminEmail -or -not $AdminPassword) { Fail "Missing ADMIN_EMAIL/ADMIN_PASSWORD" }
if (-not $BuyerEmail -or -not $BuyerPassword) { Fail "Missing BUYER_EMAIL/BUYER_PASSWORD" }
if (-not $MerchantEmail -or -not $MerchantPassword) { Fail "Missing MERCHANT_EMAIL/ MERCHANT_PASSWORD" }

Write-Host "admin email:" $AdminEmail
Write-Host "buyer email:" $BuyerEmail
Write-Host "merchant email:" $MerchantEmail

$adminLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email=$AdminEmail; password=$AdminPassword }
Write-Host "admin login:" $adminLogin.StatusCode
if (-not (OkStatus $adminLogin.StatusCode)) { Fail "admin login failed" }
$adminToken = $adminLogin.Json.token
if (-not $adminToken) { Fail "admin token missing" }
$adminHeaders = @{ Authorization = "Bearer $adminToken" }

$buyerLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email=$BuyerEmail; password=$BuyerPassword }
Write-Host "buyer login:" $buyerLogin.StatusCode
if (-not (OkStatus $buyerLogin.StatusCode)) { Fail "buyer login failed" }
$buyerToken = $buyerLogin.Json.token
if (-not $buyerToken) { Fail "buyer token missing" }
$buyerHeaders = @{ Authorization = "Bearer $buyerToken" }

$merchantLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email=$MerchantEmail; password=$MerchantPassword }
Write-Host "merchant login:" $merchantLogin.StatusCode
if (-not (OkStatus $merchantLogin.StatusCode)) { Fail "merchant login failed" }
$merchantToken = $merchantLogin.Json.token
if (-not $merchantToken) { Fail "merchant token missing" }
$merchantHeaders = @{ Authorization = "Bearer $merchantToken" }

# Role switch should be forbidden for non-admin
$roleSwitch = Invoke-Api -Method "POST" -Path "/api/auth/set-role" -Headers $buyerHeaders -BodyObj @{ role="admin" }
Write-Host "buyer set-role admin:" $roleSwitch.StatusCode
if ($roleSwitch.StatusCode -ne 403) { Fail "role switch not blocked" }

# Merchant list for follow test
$merchants = Invoke-Api -Method "GET" -Path "/api/merchants" -Headers $buyerHeaders
Write-Host "merchants list:" $merchants.StatusCode
if (-not (OkStatus $merchants.StatusCode)) { Fail "merchants list failed" }
$merchantId = $null
if ($merchants.Json -is [System.Collections.IEnumerable]) {
  $merchantId = ($merchants.Json | Select-Object -First 1).user_id
  if (-not $merchantId) { $merchantId = ($merchants.Json | Select-Object -First 1).id }
}
$merchantMe = Invoke-Api -Method "GET" -Path "/api/auth/me" -Headers $merchantHeaders
if (-not $merchantId -and $merchantMe.Json -and $merchantMe.Json.id) { $merchantId = $merchantMe.Json.id }
if (-not $merchantId) { Fail "no merchant id found" }

# Buyer can follow merchant
$follow = Invoke-Api -Method "POST" -Path "/api/merchants/$merchantId/follow" -Headers $buyerHeaders
Write-Host "buyer follow merchant:" $follow.StatusCode
if (-not (OkStatus $follow.StatusCode)) { Fail "buyer follow failed" }

# Merchant cannot follow
$merchantFollow = Invoke-Api -Method "POST" -Path "/api/merchants/$merchantId/follow" -Headers $merchantHeaders
Write-Host "merchant follow merchant:" $merchantFollow.StatusCode
if ($merchantFollow.StatusCode -ne 403) { Fail "merchant follow not blocked" }

# Chat rule: user-to-user chat blocked (buyer tries to target merchant user_id)
$buyerMe = Invoke-Api -Method "GET" -Path "/api/auth/me" -Headers $buyerHeaders
$targetId = $merchantMe.Json.id
$chat = Invoke-Api -Method "POST" -Path "/api/support/messages" -Headers $buyerHeaders -BodyObj @{ body="Hi"; user_id=$targetId }
Write-Host "buyer chat non-admin target:" $chat.StatusCode
if ($chat.StatusCode -ne 403) { Fail "chat not blocked" }

# Self-buy: create listing as merchant then attempt to buy with same merchant
$listingPayload = @{ title="QA Listing $(Get-Date -Format 'yyyyMMddHHmmss')"; description="QA"; price=100; state="Lagos"; city="Ikeja"; locality="" }
$createListing = Invoke-Api -Method "POST" -Path "/api/listings" -Headers $merchantHeaders -BodyObj $listingPayload
Write-Host "create listing:" $createListing.StatusCode
$listingId = $null
if (OkStatus $createListing.StatusCode) {
  $listingId = $createListing.Json.listing.id
} elseif ($createListing.StatusCode -eq 403) {
  Write-Host "listing create blocked (likely verification gate); reusing existing admin-visible listing."
  $adminListings = Invoke-Api -Method "GET" -Path "/api/admin/listings" -Headers $adminHeaders
  Write-Host "admin listings:" $adminListings.StatusCode
  if (OkStatus $adminListings.StatusCode -and $adminListings.Json -and $adminListings.Json.items -and $adminListings.Json.items.Count -gt 0) {
    $mine = $adminListings.Json.items | Where-Object { $_.merchant_id -eq $merchantId } | Select-Object -First 1
    if ($mine) { $listingId = $mine.id }
  }
} else {
  Fail "listing create failed unexpectedly"
}
if (-not $listingId) { Fail "listing id missing" }
$merchantId = $merchantMe.Json.id
$buy = Invoke-Api -Method "POST" -Path "/api/orders" -Headers $merchantHeaders -BodyObj @{ merchant_id=$merchantId; amount=100; delivery_fee=0; inspection_fee=0; pickup="Ikeja"; dropoff="Ikeja"; listing_id=$listingId; payment_reference="qa_selfbuy_$(Get-Date -Format 'yyyyMMddHHmmss')" }
Write-Host "self-buy order:" $buy.StatusCode
if ($buy.StatusCode -ne 409 -and $buy.StatusCode -ne 400) { Fail "self-buy not blocked with expected status" }
if (-not $buy.Json) { Fail "self-buy response missing JSON body" }
if ($buy.Json.error -ne "SELLER_CANNOT_BUY_OWN_LISTING") { Fail "self-buy response missing expected error code" }
if (-not ($buy.Json.message -like "*own listing*")) { Fail "self-buy response missing expected message" }

Write-Host "OK: rules smoke passed"
