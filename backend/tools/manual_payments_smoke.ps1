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

function Assert-Status([object]$resp, [string]$label, [int[]]$allowed) {
  Write-Host "$label -> $($resp.StatusCode)"
  if ($allowed -notcontains [int]$resp.StatusCode) {
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
    email = "buyer_manual_$r@t.com"
    password = "TestPass123!"
    name = "Buyer Manual $r"
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

Write-Host "manual payments smoke: base=$Base"
$version = Invoke-Api -Path "/api/version"
Write-Host "GET /api/version -> $($version.StatusCode)"
if ($version.Body) { Write-Host $version.Body }

$adminLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $AdminEmail; password = $AdminPassword }
Assert-Status $adminLogin "POST /api/auth/login (admin)" @(200)
Assert-True ($adminLogin.Json -and $adminLogin.Json.token) "Admin login did not return token."
$adminHeaders = @{ Authorization = "Bearer $($adminLogin.Json.token)"; "X-Debug" = "1" }

$modeSet = Invoke-Api -Method "POST" -Path "/api/admin/payments/mode" -Headers $adminHeaders -BodyObj @{ mode = "manual_company_account" }
Assert-Status $modeSet "POST /api/admin/payments/mode" @(200)

$saveManual = Invoke-Api -Method "POST" -Path "/api/admin/settings/payments" -Headers $adminHeaders -BodyObj @{
  mode = "manual_company_account"
  manual_payment_bank_name = "FlipTrybe Demo Bank"
  manual_payment_account_number = "0123456789"
  manual_payment_account_name = "FlipTrybe Inc"
  manual_payment_note = "Use your reference when paying."
  manual_payment_sla_minutes = 360
}
Assert-Status $saveManual "POST /api/admin/settings/payments" @(200)

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
Assert-Status $buyerLogin "POST /api/auth/login (buyer)" @(200)
Assert-True ($buyerLogin.Json -and $buyerLogin.Json.token) "Buyer login did not return token."
$buyerHeaders = @{ Authorization = "Bearer $($buyerLogin.Json.token)"; "X-Debug" = "1" }

$buyerMe = Invoke-Api -Path "/api/auth/me" -Headers $buyerHeaders
Assert-Status $buyerMe "GET /api/auth/me (buyer)" @(200)
$buyerId = [int]$buyerMe.Json.id

$listingsResp = Invoke-Api -Method "GET" -Path "/api/admin/listings?limit=100" -Headers $adminHeaders
Assert-Status $listingsResp "GET /api/admin/listings" @(200)
$listing = $null
if ($listingsResp.Json -and $listingsResp.Json.items) {
  $listing = @($listingsResp.Json.items) | Where-Object { (Get-OwnerId $_) -ne $buyerId } | Select-Object -First 1
}
if (-not $listing) {
  $seedNation = Invoke-Api -Method "POST" -Path "/api/admin/demo/seed-nationwide" -Headers $adminHeaders -BodyObj @{}
  Write-Host "POST /api/admin/demo/seed-nationwide -> $($seedNation.StatusCode)"
  $listingsResp = Invoke-Api -Method "GET" -Path "/api/admin/listings?limit=100" -Headers $adminHeaders
  Assert-Status $listingsResp "GET /api/admin/listings (after seed)" @(200)
  if ($listingsResp.Json -and $listingsResp.Json.items) {
    $listing = @($listingsResp.Json.items) | Where-Object { (Get-OwnerId $_) -ne $buyerId } | Select-Object -First 1
  }
}
Assert-True ($listing -ne $null) "No listing available for manual payments smoke."

$listingId = [int]$listing.id
$createOrder = Invoke-Api -Method "POST" -Path "/api/orders" -Headers $buyerHeaders -BodyObj @{
  listing_id = $listingId
  pickup = "Ikeja"
  dropoff = "Lekki"
}
Assert-Status $createOrder "POST /api/orders" @(200,201)
Assert-True ($createOrder.Json -and $createOrder.Json.order -and $createOrder.Json.order.id) "Order create did not return order id."
$orderId = [int]$createOrder.Json.order.id

$initialize = Invoke-Api -Method "POST" -Path "/api/payments/initialize" -Headers $buyerHeaders -BodyObj @{
  purpose = "order"
  order_id = $orderId
}
Assert-Status $initialize "POST /api/payments/initialize" @(200)
Assert-True (($initialize.Json.mode -eq "manual_company_account")) "Initialize did not return manual mode."
Assert-True (($initialize.Json.payment_intent_id -as [int]) -gt 0) "Initialize missing payment_intent_id."
$paymentIntentId = [int]$initialize.Json.payment_intent_id

$proof = Invoke-Api -Method "POST" -Path "/api/payments/manual/$paymentIntentId/proof" -Headers $buyerHeaders -BodyObj @{
  bank_txn_reference = "SMOKE-TXN-$paymentIntentId"
  note = "manual payments smoke proof"
}
Assert-Status $proof "POST /api/payments/manual/{id}/proof" @(200)

$queue = Invoke-Api -Method "GET" -Path "/api/admin/payments/manual/queue?status=manual_pending&q=$paymentIntentId" -Headers $adminHeaders
Assert-Status $queue "GET /api/admin/payments/manual/queue" @(200)
$queueHit = $false
if ($queue.Json -and $queue.Json.items) {
  foreach ($item in @($queue.Json.items)) {
    if ([int]$item.payment_intent_id -eq $paymentIntentId) {
      $queueHit = $true
      break
    }
  }
}
Assert-True $queueHit "Manual queue does not include created payment intent."

$markPaid1 = Invoke-Api -Method "POST" -Path "/api/admin/payments/manual/mark-paid" -Headers $adminHeaders -BodyObj @{
  payment_intent_id = $paymentIntentId
  bank_txn_reference = "BANK-REF-$paymentIntentId"
  note = "manual smoke first mark"
}
Assert-Status $markPaid1 "POST /api/admin/payments/manual/mark-paid (first)" @(200)

$markPaid2 = Invoke-Api -Method "POST" -Path "/api/admin/payments/manual/mark-paid" -Headers $adminHeaders -BodyObj @{
  payment_intent_id = $paymentIntentId
  note = "manual smoke replay"
}
Assert-Status $markPaid2 "POST /api/admin/payments/manual/mark-paid (replay)" @(200)
Assert-True (($markPaid2.Json.idempotent -eq $true) -or ($markPaid2.Json.ok -eq $true)) "Replay mark-paid did not return idempotent-safe result."

$status = Invoke-Api -Method "GET" -Path "/api/payments/status?order_id=$orderId" -Headers $buyerHeaders
Assert-Status $status "GET /api/payments/status" @(200)
Assert-True (($status.Json.payment_status -eq "paid")) "Payment status is not paid after manual mark-paid."

$timeline = Invoke-Api -Method "GET" -Path "/api/admin/orders/$orderId/timeline" -Headers $adminHeaders
Assert-Status $timeline "GET /api/admin/orders/{id}/timeline" @(200)
$hasTransition = $false
if ($timeline.Json -and $timeline.Json.items) {
  foreach ($row in @($timeline.Json.items)) {
    if (("$($row.type)" -eq "payment_transition") -or ("$($row.kind)" -eq "payment_transition")) {
      $hasTransition = $true
      break
    }
  }
}
Assert-True $hasTransition "Order timeline does not contain payment transition entries."

Write-Host "OK: manual payments smoke passed (order_id=$orderId, intent_id=$paymentIntentId)"
exit 0

