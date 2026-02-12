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
    $Email = "buyer_shortlet_$r@t.com"
    $Password = "TestPass123!"
    $phone = "+23480$($r.ToString().Substring(0, [Math]::Min(7, $r.ToString().Length)))"
    $reg = Invoke-Api -Method "POST" -Path "/api/auth/register/buyer" -BodyObj @{
      name = "Buyer Shortlet $r"
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

Write-Host "shortlet media smoke: base=$Base"

$adminLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $AdminEmail; password = $AdminPassword }
Assert-Ok $adminLogin "POST /api/auth/login (admin)"
$adminHeaders = @{ Authorization = "Bearer $($adminLogin.Json.token)"; "X-Debug" = "1" }

$toggle = Invoke-Api -Method "POST" -Path "/api/admin/autopilot/settings" -Headers $adminHeaders -BodyObj @{
  cart_checkout_v1 = $true
  shortlet_reels_v1 = $true
  payments_mode = "manual_company_account"
}
Assert-Ok $toggle "POST /api/admin/autopilot/settings"

$cfg = Invoke-Api -Method "GET" -Path "/api/media/cloudinary/config"
Assert-Ok $cfg "GET /api/media/cloudinary/config"

$sign = Invoke-Api -Method "POST" -Path "/api/media/cloudinary/sign" -Headers $adminHeaders -BodyObj @{ resource_type = "video" }
Write-Host "POST /api/media/cloudinary/sign -> $($sign.StatusCode)"
if ($sign.StatusCode -ge 500) {
  Write-Host "Cloudinary signing is not configured; continuing with URL-only media attach path."
}

$shortletCreate = Invoke-Api -Method "POST" -Path "/api/shortlets" -Headers $adminHeaders -BodyObj @{
  title = "Smoke Shortlet $(Get-Random)"
  description = "City-first shortlet smoke listing"
  state = "Lagos"
  city = "Lagos"
  locality = "Ikeja"
  nightly_price = 90000
  cleaning_fee = 5000
  beds = 2
  baths = 2
  guests = 3
  image_url = "https://images.unsplash.com/photo-1568605114967-8130f3a36994?w=1200"
}
Assert-Ok $shortletCreate "POST /api/shortlets"
$shortletId = [int]$shortletCreate.Json.shortlet.id
if ($shortletId -le 0) {
  Write-Host "Could not resolve shortlet id from create response."
  exit 2
}

$attachImage = Invoke-Api -Method "POST" -Path "/api/shortlets/$shortletId/media" -Headers $adminHeaders -BodyObj @{
  media_type = "image"
  url = "https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?w=1200"
  thumbnail_url = "https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?w=600"
  position = 0
}
Assert-Ok $attachImage "POST /api/shortlets/{id}/media (image)"

$attachVideo = Invoke-Api -Method "POST" -Path "/api/shortlets/$shortletId/media" -Headers $adminHeaders -BodyObj @{
  media_type = "video"
  url = "https://res.cloudinary.com/demo/video/upload/dog.mp4"
  thumbnail_url = "https://res.cloudinary.com/demo/video/upload/so_1,dog.jpg"
  duration_seconds = 15
  position = 1
}
Assert-Ok $attachVideo "POST /api/shortlets/{id}/media (video<=30s)"

$buyer = Ensure-Buyer -Email $BuyerEmail -Password $BuyerPassword
$buyerHeaders = @{ Authorization = "Bearer $($buyer.Token)"; "X-Debug" = "1" }

$book = Invoke-Api -Method "POST" -Path "/api/shortlets/$shortletId/book" -Headers $buyerHeaders -BodyObj @{
  check_in = "2026-03-01"
  check_out = "2026-03-03"
  guests = 2
  payment_method = "bank_transfer_manual"
}
Assert-Ok $book "POST /api/shortlets/{id}/book"
if (($book.Json.mode -ne "bank_transfer_manual")) {
  Write-Host "Expected manual mode for shortlet booking but got: $($book.Json.mode)"
  exit 3
}
$intentId = [int]$book.Json.payment_intent_id
if ($intentId -le 0) {
  Write-Host "Shortlet booking missing payment_intent_id"
  exit 4
}

$proof = Invoke-Api -Method "POST" -Path "/api/payment-intents/$intentId/manual-proof" -Headers $buyerHeaders -BodyObj @{
  bank_txn_reference = "SMOKE-SHORTLET-$intentId"
  note = "shortlet media smoke proof"
}
Assert-Ok $proof "POST /api/payment-intents/{id}/manual-proof"

$mark = Invoke-Api -Method "POST" -Path "/api/admin/payment-intents/$intentId/manual/mark-paid" -Headers $adminHeaders -BodyObj @{
  note = "shortlet media smoke mark paid"
}
Assert-Ok $mark "POST /api/admin/payment-intents/{id}/manual/mark-paid"

Write-Host "OK: shortlet media smoke passed (shortlet_id=$shortletId intent_id=$intentId)"
exit 0

