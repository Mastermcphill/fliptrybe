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
    $Email = "buyer_cart_$r@t.com"
    $Password = "TestPass123!"
    $phone = "+23480$($r.ToString().Substring(0, [Math]::Min(7, $r.ToString().Length)))"
    $reg = Invoke-Api -Method "POST" -Path "/api/auth/register/buyer" -BodyObj @{
      name = "Buyer Cart $r"
      email = $Email
      password = $Password
      phone = $phone
    }
    Write-Host "POST /api/auth/register/buyer -> $($reg.StatusCode)"
  }
  if (-not $Password) { $Password = "TestPass123!" }
  $login = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $Email; password = $Password }
  Assert-Ok $login "POST /api/auth/login (buyer)"
  return [pscustomobject]@{ Email = $Email; Token = $login.Json.token; UserId = [int]$login.Json.user.id }
}

function Get-OwnerId($listing) {
  foreach ($key in @("user_id","owner_id","merchant_id")) {
    if ($listing.PSObject.Properties.Name -contains $key) {
      try { return [int]$listing.$key } catch {}
    }
  }
  return 0
}

Write-Host "cart checkout smoke: base=$Base"
$version = Invoke-Api -Path "/api/version"
Write-Host "GET /api/version -> $($version.StatusCode)"

$adminLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $AdminEmail; password = $AdminPassword }
Assert-Ok $adminLogin "POST /api/auth/login (admin)"
$adminHeaders = @{ Authorization = "Bearer $($adminLogin.Json.token)"; "X-Debug" = "1" }

$toggle = Invoke-Api -Method "POST" -Path "/api/admin/autopilot/settings" -Headers $adminHeaders -BodyObj @{
  cart_checkout_v1 = $true
  payments_mode = "manual_company_account"
}
Assert-Ok $toggle "POST /api/admin/autopilot/settings"

$seed = Invoke-Api -Method "POST" -Path "/api/admin/demo/seed-nationwide" -Headers $adminHeaders -BodyObj @{}
Write-Host "POST /api/admin/demo/seed-nationwide -> $($seed.StatusCode)"

$buyer = Ensure-Buyer -Email $BuyerEmail -Password $BuyerPassword
$buyerHeaders = @{ Authorization = "Bearer $($buyer.Token)"; "X-Debug" = "1" }

$listings = Invoke-Api -Method "GET" -Path "/api/admin/listings?limit=100" -Headers $adminHeaders
Assert-Ok $listings "GET /api/admin/listings"
$candidate = $null
if ($listings.Json -and $listings.Json.items) {
  $candidate = @($listings.Json.items) | Where-Object { (Get-OwnerId $_) -ne $buyer.UserId } | Select-Object -First 1
}
if (-not $candidate) {
  Write-Host "No listing available for cart smoke."
  exit 2
}
$listingId = [int]$candidate.id

$add = Invoke-Api -Method "POST" -Path "/api/cart/items" -Headers $buyerHeaders -BodyObj @{ listing_id = $listingId; quantity = 1 }
Assert-Ok $add "POST /api/cart/items"

$cart = Invoke-Api -Method "GET" -Path "/api/cart" -Headers $buyerHeaders
Assert-Ok $cart "GET /api/cart"

$idem = "smoke-cart-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
$bulk = Invoke-Api -Method "POST" -Path "/api/orders/bulk" -Headers (@{ Authorization = "Bearer $($buyer.Token)"; "X-Debug"="1"; "Idempotency-Key"=$idem }) -BodyObj @{
  listing_ids = @($listingId)
  payment_method = "bank_transfer_manual"
}
Assert-Ok $bulk "POST /api/orders/bulk"
if ($bulk.Json.mode -ne "bank_transfer_manual") {
  Write-Host "Expected manual checkout mode but got: $($bulk.Json.mode)"
  exit 3
}
$intentId = [int]$bulk.Json.payment_intent_id
if ($intentId -le 0) {
  Write-Host "Bulk checkout missing payment_intent_id"
  exit 4
}

$proof = Invoke-Api -Method "POST" -Path "/api/payment-intents/$intentId/manual-proof" -Headers $buyerHeaders -BodyObj @{
  bank_txn_reference = "SMOKE-CART-$intentId"
  note = "cart smoke proof"
}
Assert-Ok $proof "POST /api/payment-intents/{id}/manual-proof"

$mark = Invoke-Api -Method "POST" -Path "/api/admin/payment-intents/$intentId/manual/mark-paid" -Headers $adminHeaders -BodyObj @{
  bank_txn_reference = "BANK-CART-$intentId"
  note = "cart smoke mark paid"
}
Assert-Ok $mark "POST /api/admin/payment-intents/{id}/manual/mark-paid"

$orderIds = @()
if ($bulk.Json -and $bulk.Json.order_ids) { $orderIds = @($bulk.Json.order_ids) }
if ($orderIds.Count -gt 0) {
  $orderId = [int]$orderIds[0]
  $status = Invoke-Api -Method "GET" -Path "/api/payments/status?order_id=$orderId" -Headers $buyerHeaders
  Assert-Ok $status "GET /api/payments/status"
  if (($status.Json.payment_status -ne "paid")) {
    Write-Host "Expected paid status; got $($status.Json.payment_status)"
    exit 5
  }
}

Write-Host "OK: cart checkout smoke passed (intent_id=$intentId)"
exit 0

