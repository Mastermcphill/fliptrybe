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
    [pscustomobject]@{ Method = $Method; Url = $url; StatusCode = [int]$resp.StatusCode; Body = $resp.Content; Json = $json }
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
    [pscustomobject]@{ Method = $Method; Url = $url; StatusCode = $status; Body = $body; Json = $json }
  }
}

function Assert-2xx([object]$resp, [string]$label) {
  Write-Host "$label -> $($resp.StatusCode)"
  if ($resp.StatusCode -lt 200 -or $resp.StatusCode -ge 300) {
    if ($resp.Body) { Write-Host $resp.Body }
    exit 1
  }
}

function New-SmokeBuyer {
  $r = Get-Random
  [pscustomobject]@{
    email = "buyer_pay_$r@t.com"
    password = "TestPass123!"
    name = "Buyer Pay $r"
    phone = "+23480$r"
  }
}

function Get-OwnerId($listing) {
  if ($null -eq $listing) { return 0 }
  foreach ($k in @("user_id", "owner_id", "merchant_id")) {
    if ($listing.PSObject.Properties.Name -contains $k) {
      try { return [int]$listing.$k } catch {}
    }
  }
  return 0
}

Write-Host "payments smoke: base=$Base"
$version = Invoke-Api -Path "/api/version"
Write-Host "GET /api/version -> $($version.StatusCode)"
if ($version.Body) { Write-Host $version.Body }

$adminLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $AdminEmail; password = $AdminPassword }
Assert-2xx $adminLogin "POST /api/auth/login (admin)"
if (-not $adminLogin.Json -or -not $adminLogin.Json.token) { Write-Host $adminLogin.Body; exit 1 }
$adminHeaders = @{ Authorization = "Bearer $($adminLogin.Json.token)"; "X-Debug" = "1" }

$demoSeed = Invoke-Api -Method "POST" -Path "/api/demo/seed" -BodyObj @{}
Write-Host "POST /api/demo/seed -> $($demoSeed.StatusCode)"

if (-not $BuyerEmail) {
  $b = New-SmokeBuyer
  $BuyerEmail = $b.email
  $BuyerPassword = $b.password
  $reg = Invoke-Api -Method "POST" -Path "/api/auth/register/buyer" -BodyObj @{
    name = $b.name
    email = $b.email
    password = $b.password
    phone = $b.phone
  }
  Write-Host "POST /api/auth/register/buyer -> $($reg.StatusCode)"
}
if (-not $BuyerPassword) { $BuyerPassword = "TestPass123!" }

$buyerLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $BuyerEmail; password = $BuyerPassword }
Assert-2xx $buyerLogin "POST /api/auth/login (buyer)"
if (-not $buyerLogin.Json -or -not $buyerLogin.Json.token) { Write-Host $buyerLogin.Body; exit 1 }
$buyerHeaders = @{ Authorization = "Bearer $($buyerLogin.Json.token)"; "X-Debug" = "1" }
$buyerMe = Invoke-Api -Path "/api/auth/me" -Headers $buyerHeaders
Assert-2xx $buyerMe "GET /api/auth/me (buyer)"
$buyerId = [int]$buyerMe.Json.id

$settings = Invoke-Api -Method "POST" -Path "/api/admin/autopilot/settings" -Headers $adminHeaders -BodyObj @{
  payments_provider = "mock"
  integrations_mode = "sandbox"
  paystack_enabled = $true
  termii_enabled_sms = $false
  termii_enabled_wa = $false
}
Assert-2xx $settings "POST /api/admin/autopilot/settings"

$useTopup = $false
$orderId = 0
$initHeaders = $buyerHeaders
$initBody = $null

$adminListings = Invoke-Api -Path "/api/admin/listings" -Headers $adminHeaders
Assert-2xx $adminListings "GET /api/admin/listings"
$listing = $null
if ($adminListings.Json -and $adminListings.Json.items) {
  $listing = @($adminListings.Json.items) | Where-Object { (Get-OwnerId $_) -ne $buyerId } | Select-Object -First 1
}
if (-not $listing) {
  $seedNation = Invoke-Api -Method "POST" -Path "/api/admin/demo/seed-nationwide" -Headers $adminHeaders -BodyObj @{}
  Write-Host "POST /api/admin/demo/seed-nationwide -> $($seedNation.StatusCode)"
  if ($seedNation.StatusCode -lt 200 -or $seedNation.StatusCode -ge 300) {
    if ($seedNation.Body) { Write-Host $seedNation.Body }
  }
  $adminListings = Invoke-Api -Path "/api/admin/listings" -Headers $adminHeaders
  Assert-2xx $adminListings "GET /api/admin/listings (after nationwide seed)"
  if ($adminListings.Json -and $adminListings.Json.items) {
    $listing = @($adminListings.Json.items) | Where-Object { (Get-OwnerId $_) -ne $buyerId } | Select-Object -First 1
  }
}
if (-not $listing) {
  $seed = Invoke-Api -Method "POST" -Path "/api/admin/demo/seed-listing" -Headers $adminHeaders -BodyObj @{}
  Write-Host "POST /api/admin/demo/seed-listing -> $($seed.StatusCode)"
  if ($seed.StatusCode -lt 200 -or $seed.StatusCode -ge 300) {
    if ($seed.Body) { Write-Host $seed.Body }
  }
  $adminListings = Invoke-Api -Path "/api/admin/listings" -Headers $adminHeaders
  Assert-2xx $adminListings "GET /api/admin/listings (after seed)"
  if ($adminListings.Json -and $adminListings.Json.items) {
    $listing = @($adminListings.Json.items) | Where-Object { (Get-OwnerId $_) -ne $buyerId } | Select-Object -First 1
  }
}

if ($listing) {
  $listingId = [int]$listing.id
  $merchantId = Get-OwnerId $listing
  $orderCreate = Invoke-Api -Method "POST" -Path "/api/orders" -Headers $buyerHeaders -BodyObj @{
    listing_id = $listingId
    merchant_id = $merchantId
    pickup = "Ikeja"
    dropoff = "Ikeja"
  }
  Write-Host "POST /api/orders -> $($orderCreate.StatusCode)"
  if ($orderCreate.StatusCode -ge 200 -and $orderCreate.StatusCode -lt 300 -and $orderCreate.Json -and $orderCreate.Json.order -and $orderCreate.Json.order.id) {
    $orderId = [int]$orderCreate.Json.order.id
    $initBody = @{
      purpose = "order"
      order_id = $orderId
    }
  } else {
    if ($orderCreate.Body) { Write-Host $orderCreate.Body }
    Write-Host "order create unavailable for buyer; falling back to topup initialize"
    $useTopup = $true
  }
} else {
  Write-Host "No listing found; falling back to topup initialize"
  $useTopup = $true
}

if ($useTopup) {
  $initBody = @{
    purpose = "topup"
    amount = 1000
  }
}

$init = Invoke-Api -Method "POST" -Path "/api/payments/initialize" -Headers $initHeaders -BodyObj $initBody
Assert-2xx $init "POST /api/payments/initialize"
if (-not $init.Json -or -not $init.Json.reference) { Write-Host $init.Body; exit 1 }
$reference = $init.Json.reference
$initAmount = 0
try { $initAmount = [double]$init.Json.amount } catch { $initAmount = 0 }
$amountKobo = [int]($initAmount * 100)
if ($amountKobo -le 0) { $amountKobo = 10000 }

$webhook = Invoke-Api -Method "POST" -Path "/api/payments/webhook/paystack" -Headers @{} -BodyObj @{
  id = "evt_payments_smoke_1"
  event = "charge.success"
  data = @{
    reference = $reference
    amount = $amountKobo
    currency = "NGN"
    customer = @{ email = $BuyerEmail }
  }
}
Assert-2xx $webhook "POST /api/payments/webhook/paystack"

if (-not $useTopup -and $orderId -gt 0) {
  $status = Invoke-Api -Method "GET" -Path "/api/payments/status?order_id=$orderId" -Headers $buyerHeaders
  Assert-2xx $status "GET /api/payments/status"
  if (-not $status.Json -or $status.Json.payment_status -ne "paid") {
    Write-Host $status.Body
    exit 1
  }
}

$replay = Invoke-Api -Method "POST" -Path "/api/payments/webhook/paystack" -Headers @{} -BodyObj @{
  id = "evt_payments_smoke_1"
  event = "charge.success"
  data = @{
    reference = $reference
    amount = $amountKobo
    currency = "NGN"
    customer = @{ email = $BuyerEmail }
  }
}
Assert-2xx $replay "POST /api/payments/webhook/paystack (replay)"
Write-Host "replay body: $($replay.Body)"
if ($useTopup) {
  Write-Host "OK: payments smoke passed in topup fallback mode (reference=$reference)"
} else {
  Write-Host "OK: payments smoke passed (order_id=$orderId, reference=$reference)"
}
exit 0
