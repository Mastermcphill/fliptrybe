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
    email = "buyer_payments_$r@t.com"
    password = "TestPass123!"
    name = "Buyer Payments $r"
    phone = "+23480$($r.ToString().Substring(0, [Math]::Min(7, $r.ToString().Length)))"
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

$buyerMe = Invoke-Api -Path "/api/auth/me" -Headers $buyerHeaders
Assert-Ok $buyerMe "GET /api/auth/me (buyer)"
$buyerId = [int]$buyerMe.Json.id

$setMode = Invoke-Api -Method "POST" -Path "/api/admin/settings/payments" -Headers $adminHeaders -BodyObj @{ mode = "manual_company_account" }
Assert-Ok $setMode "POST /api/admin/settings/payments"

$modeRead = Invoke-Api -Method "GET" -Path "/api/admin/settings/payments" -Headers $adminHeaders
Assert-Ok $modeRead "GET /api/admin/settings/payments"
Assert-True (($modeRead.Json.settings.mode -eq "manual_company_account")) "Payments mode did not persist as manual_company_account."

$listingsResp = Invoke-Api -Method "GET" -Path "/api/admin/listings?limit=50" -Headers $adminHeaders
Assert-Ok $listingsResp "GET /api/admin/listings"
$listing = $null
if ($listingsResp.Json -and $listingsResp.Json.items) {
  $listing = @($listingsResp.Json.items) | Where-Object { (Get-OwnerId $_) -ne $buyerId } | Select-Object -First 1
}
if (-not $listing) {
  $seedNation = Invoke-Api -Method "POST" -Path "/api/admin/demo/seed-nationwide" -Headers $adminHeaders -BodyObj @{}
  Write-Host "POST /api/admin/demo/seed-nationwide -> $($seedNation.StatusCode)"
  $listingsResp = Invoke-Api -Method "GET" -Path "/api/admin/listings?limit=50" -Headers $adminHeaders
  Assert-Ok $listingsResp "GET /api/admin/listings (after seed)"
  if ($listingsResp.Json -and $listingsResp.Json.items) {
    $listing = @($listingsResp.Json.items) | Where-Object { (Get-OwnerId $_) -ne $buyerId } | Select-Object -First 1
  }
}
Assert-True ($listing -ne $null) "No listing available for payments smoke."

$listingId = [int]$listing.id
$merchantId = Get-OwnerId $listing
$createOrder = Invoke-Api -Method "POST" -Path "/api/orders" -Headers $adminHeaders -BodyObj @{
  buyer_id = $buyerId
  listing_id = $listingId
  merchant_id = $merchantId
  pickup = "Ikeja"
  dropoff = "Lekki"
}
Assert-Ok $createOrder "POST /api/orders"
Assert-True ($createOrder.Json -and $createOrder.Json.order -and $createOrder.Json.order.id) "Order create did not return order id."
$orderId = [int]$createOrder.Json.order.id

$initialize = Invoke-Api -Method "POST" -Path "/api/payments/initialize" -Headers $buyerHeaders -BodyObj @{
  purpose = "order"
  order_id = $orderId
}
Assert-Ok $initialize "POST /api/payments/initialize"
Assert-True (($initialize.Json.mode -eq "manual_company_account")) "Initialize did not return manual mode."
Assert-True (($initialize.Json.requires_admin_mark_paid -eq $true)) "Manual initialize missing requires_admin_mark_paid=true."

$manualQueue = Invoke-Api -Method "GET" -Path "/api/admin/payments/manual/pending?limit=50" -Headers $adminHeaders
Assert-Ok $manualQueue "GET /api/admin/payments/manual/pending"
$queueHit = $false
if ($manualQueue.Json -and $manualQueue.Json.items) {
  foreach ($item in @($manualQueue.Json.items)) {
    if ([int]$item.order_id -eq $orderId) {
      $queueHit = $true
      break
    }
  }
}
Assert-True $queueHit "Manual pending queue does not include created order."

$markPaid1 = Invoke-Api -Method "POST" -Path "/api/admin/payments/manual/mark-paid" -Headers $adminHeaders -BodyObj @{
  order_id = $orderId
  note = "payments smoke first mark"
}
Assert-Ok $markPaid1 "POST /api/admin/payments/manual/mark-paid (first)"

$markPaid2 = Invoke-Api -Method "POST" -Path "/api/admin/payments/manual/mark-paid" -Headers $adminHeaders -BodyObj @{
  order_id = $orderId
  note = "payments smoke replay"
}
Assert-Ok $markPaid2 "POST /api/admin/payments/manual/mark-paid (replay)"
Assert-True (($markPaid2.Json.idempotent -eq $true) -or ($markPaid2.Json.ok -eq $true)) "Replay mark-paid did not return idempotent-safe result."

$status = Invoke-Api -Method "GET" -Path "/api/payments/status?order_id=$orderId" -Headers $buyerHeaders
Assert-Ok $status "GET /api/payments/status"
Assert-True (($status.Json.payment_status -eq "paid")) "Payment status is not paid after manual mark-paid."

Write-Host "OK: payments smoke passed (order_id=$orderId)"
exit 0
