$ErrorActionPreference = "Continue"

param(
  [string]$Base = "https://tri-o-fliptrybe.onrender.com",
  [string]$AdminEmail = $env:ADMIN_EMAIL,
  [string]$AdminPassword = $env:ADMIN_PASSWORD,
  [string]$BuyerEmail = $env:BUYER_EMAIL,
  [string]$BuyerPassword = $env:BUYER_PASSWORD,
  [string]$MerchantEmail = $env:MERCHANT_EMAIL,
  [string]$MerchantPassword = $env:MERCHANT_PASSWORD
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

function Login {
  param([string]$Email,[string]$Password)
  $resp = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email=$Email; password=$Password }
  return $resp
}

Write-Host "health:" (Invoke-Api -Path "/api/health").StatusCode

if (-not $AdminEmail -or -not $AdminPassword) {
  Write-Host "Missing ADMIN_EMAIL/ADMIN_PASSWORD; admin checks skipped"
} else {
  $adminLogin = Login -Email $AdminEmail -Password $AdminPassword
  Write-Host "admin login:" $adminLogin.StatusCode
}

if (-not $BuyerEmail -or -not $BuyerPassword) {
  Write-Host "Missing BUYER_EMAIL/BUYER_PASSWORD; buyer checks skipped"
  exit 0
}

$buyerLogin = Login -Email $BuyerEmail -Password $BuyerPassword
Write-Host "buyer login:" $buyerLogin.StatusCode
$buyerToken = $buyerLogin.Json.token
if (-not $buyerToken) { Write-Host "buyer token missing"; exit 1 }
$buyerHeaders = @{ Authorization = "Bearer $buyerToken" }

Write-Host "buyer /me:" (Invoke-Api -Path "/api/auth/me" -Headers $buyerHeaders).StatusCode

# Role switch should be forbidden for non-admin
$roleSwitch = Invoke-Api -Method "POST" -Path "/api/auth/set-role" -Headers $buyerHeaders -BodyObj @{ role="merchant" }
Write-Host "role switch (buyer) status:" $roleSwitch.StatusCode

if (-not $MerchantEmail -or -not $MerchantPassword) {
  Write-Host "Missing MERCHANT_EMAIL/MERCHANT_PASSWORD; merchant checks skipped"
  exit 0
}

$merchantLogin = Login -Email $MerchantEmail -Password $MerchantPassword
Write-Host "merchant login:" $merchantLogin.StatusCode
$merchantToken = $merchantLogin.Json.token
if (-not $merchantToken) { Write-Host "merchant token missing"; exit 1 }
$merchantHeaders = @{ Authorization = "Bearer $merchantToken" }

# Merchant follow should be forbidden
$merchantMe = Invoke-Api -Path "/api/auth/me" -Headers $merchantHeaders
$merchantId = $merchantMe.Json.id
if ($merchantId) {
  $followSelf = Invoke-Api -Method "POST" -Path "/api/merchants/$merchantId/follow" -Headers $merchantHeaders
  Write-Host "merchant follow status:" $followSelf.StatusCode
}

# Create a listing as merchant
$listingPayload = @{ title="Smoke Listing"; description="test"; price=1000; state="Lagos"; city="Lagos"; locality="Ikeja" }
$listingRes = Invoke-Api -Method "POST" -Path "/api/listings" -Headers $merchantHeaders -BodyObj $listingPayload
Write-Host "create listing status:" $listingRes.StatusCode
$listingId = $listingRes.Json.listing.id

# Merchant buying own listing should be blocked
if ($listingId -and $merchantId) {
  $orderPayload = @{
    listing_id = $listingId
    merchant_id = $merchantId
    amount = 1000
    delivery_fee = 0
    pickup = "Ikeja"
    dropoff = "Ikeja"
    payment_reference = ("selfbuy_" + (Get-Random))
  }
  $selfBuy = Invoke-Api -Method "POST" -Path "/api/orders" -Headers $merchantHeaders -BodyObj $orderPayload
  Write-Host "self-buy status:" $selfBuy.StatusCode
}

# Chat: non-admin sending to another user should be blocked
if ($merchantId) {
  $chatAttempt = Invoke-Api -Method "POST" -Path "/api/support/messages" -Headers $buyerHeaders -BodyObj @{ body="hi"; user_id=$merchantId }
  Write-Host "buyer chat non-admin target status:" $chatAttempt.StatusCode
}

exit 0

