param(
  [string]$Base = $env:BASE_URL
)

$ErrorActionPreference = "Stop"

if (-not $Base) { $Base = "https://tri-o-fliptrybe.onrender.com" }

$adminEmail = $env:ADMIN_EMAIL
$adminPassword = $env:ADMIN_PASSWORD
if (-not $adminEmail -or -not $adminPassword) {
  Write-Host "Missing ADMIN_EMAIL or ADMIN_PASSWORD env vars."
  exit 2
}

function Invoke-Api {
  param(
    [string]$Method = "GET",
    [string]$Url,
    [hashtable]$Headers = @{},
    $BodyObj = $null
  )
  try {
    if ($null -ne $BodyObj) {
      $body = ($BodyObj | ConvertTo-Json -Depth 10)
      $resp = Invoke-WebRequest -Method $Method -Uri $Url -Headers $Headers -ContentType "application/json" -Body $body -UseBasicParsing
    } else {
      $resp = Invoke-WebRequest -Method $Method -Uri $Url -Headers $Headers -UseBasicParsing
    }
    $json = $null
    try { $json = $resp.Content | ConvertFrom-Json } catch {}
    return [pscustomobject]@{ StatusCode = [int]$resp.StatusCode; Body = $resp.Content; Json = $json }
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
    return [pscustomobject]@{ StatusCode = $status; Body = $body; Json = $json }
  }
}

Write-Host "BASE=$Base"
$version = Invoke-Api -Url "$Base/api/version"
Write-Host "GET /api/version => $($version.StatusCode)"
if ($version.Body) { Write-Host $version.Body }

$adminLogin = Invoke-Api -Method "POST" -Url "$Base/api/auth/login" -BodyObj @{ email = $adminEmail; password = $adminPassword }
Write-Host "POST /api/auth/login (admin) => $($adminLogin.StatusCode)"
if (-not $adminLogin.Json -or -not $adminLogin.Json.token) {
  Write-Host $adminLogin.Body
  exit 3
}
$adminHeaders = @{ Authorization = "Bearer $($adminLogin.Json.token)" }

$listings = Invoke-Api -Url "$Base/api/admin/listings" -Headers $adminHeaders
Write-Host "GET /api/admin/listings => $($listings.StatusCode)"
if ($listings.StatusCode -lt 200 -or $listings.StatusCode -ge 300) {
  if ($listings.Body) { Write-Host $listings.Body }
  Write-Host "Listings endpoint failed. Cannot create order."
  exit 4
}
if (-not $listings.Json -or -not $listings.Json.items -or $listings.Json.items.Count -lt 1) {
  Write-Host $listings.Body
  Write-Host "No listings available for order create."
  exit 5
}
$listing = $listings.Json.items | Select-Object -First 1
$listingId = [int]$listing.id
$merchantId = $listing.merchant_id
if (-not $merchantId) {
  Write-Host "Listing missing merchant_id. Use a seeded listing with owner."
  exit 6
}

$buyerEmail = $env:BUYER_EMAIL
$buyerPassword = $env:BUYER_PASSWORD
if (-not $buyerPassword) { $buyerPassword = "TestPass123!" }

$buyerLogin = $null
if ($buyerEmail) {
  $buyerLogin = Invoke-Api -Method "POST" -Url "$Base/api/auth/login" -BodyObj @{ email = $buyerEmail; password = $buyerPassword }
}

if (-not $buyerLogin -or -not $buyerLogin.Json -or -not $buyerLogin.Json.token) {
  $buyerEmail = ("buyer_smoke_{0}@t.com" -f (Get-Random))
  $phone = ("+234801{0}" -f (Get-Random -Minimum 1000000 -Maximum 9999999))
  $buyerReg = Invoke-Api -Method "POST" -Url "$Base/api/auth/register/buyer" -BodyObj @{ name = "Smoke Buyer"; email = $buyerEmail; password = $buyerPassword; phone = $phone }
  Write-Host "POST /api/auth/register/buyer => $($buyerReg.StatusCode)"
  $buyerLogin = Invoke-Api -Method "POST" -Url "$Base/api/auth/login" -BodyObj @{ email = $buyerEmail; password = $buyerPassword }
}

Write-Host "POST /api/auth/login (buyer) => $($buyerLogin.StatusCode)"
if (-not $buyerLogin.Json -or -not $buyerLogin.Json.token) {
  Write-Host $buyerLogin.Body
  exit 7
}
$buyerHeaders = @{ Authorization = "Bearer $($buyerLogin.Json.token)" }

$orderPayload = @{
  merchant_id = [int]$merchantId
  listing_id = [int]$listingId
  payment_reference = ("smoke_{0}" -f (Get-Random))
  pickup = "Ikeja"
  dropoff = "Yaba"
}
$order = Invoke-Api -Method "POST" -Url "$Base/api/orders" -Headers $buyerHeaders -BodyObj $orderPayload
Write-Host "POST /api/orders => $($order.StatusCode)"
if ($order.Body) { Write-Host $order.Body }
if ($order.StatusCode -lt 200 -or $order.StatusCode -ge 300) { exit 7 }

$orderId = $order.Json.order.id
if (-not $orderId) {
  Write-Host "Order id missing in response."
  exit 8
}

$delivery = Invoke-Api -Url "$Base/api/orders/$orderId/delivery" -Headers $buyerHeaders
Write-Host "GET /api/orders/$orderId/delivery => $($delivery.StatusCode)"
if ($delivery.Body) { Write-Host $delivery.Body }
if ($delivery.StatusCode -lt 200 -or $delivery.StatusCode -ge 300) { exit 9 }

Write-Host "OK: order create smoke passed. buyer_email=$buyerEmail order_id=$orderId"
exit 0
