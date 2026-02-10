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
    [pscustomobject]@{ StatusCode = [int]$resp.StatusCode; Body = $resp.Content; Json = $json }
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
    [pscustomobject]@{ StatusCode = $status; Body = $body; Json = $json }
  }
}

function Fail($msg) { Write-Host "FAIL:" $msg; exit 1 }
function OkStatus($code) { return ($code -ge 200 -and $code -lt 300) }
function New-RandomEmail($prefix) { return ("{0}_{1}@t.com" -f $prefix, (Get-Random)) }
function New-RandomPhone() { return ("+23480{0}" -f (Get-Random -Minimum 100000000 -Maximum 999999999)) }
function Get-ListingOwnerId($item) {
  if ($null -eq $item) { return $null }
  foreach ($k in @("user_id", "merchant_id", "owner_id")) {
    if ($item.PSObject.Properties.Name -contains $k) {
      $v = $item.$k
      if ($null -ne $v -and "$v" -ne "") {
        try { return [int]$v } catch { return $v }
      }
    }
  }
  return $null
}
function Resolve-MerchantOwnedListingId {
  param(
    [hashtable]$AdminHeaders,
    [hashtable]$MerchantHeaders,
    [int]$MerchantId
  )

  $firstFive = @()
  $adminListings = Invoke-Api -Method "GET" -Path "/api/admin/listings" -Headers $AdminHeaders
  Write-Host "admin listings:" $adminListings.StatusCode

  if (OkStatus $adminListings.StatusCode -and $adminListings.Json -and $adminListings.Json.items) {
    $items = @($adminListings.Json.items)
    $firstFive = $items | Select-Object -First 5 | ForEach-Object {
      [pscustomobject]@{ id = $_.id; owner_id = (Get-ListingOwnerId $_) }
    }
    $owned = $items | Where-Object { [int](Get-ListingOwnerId $_) -eq $MerchantId } | Select-Object -First 1
    if ($owned -and $owned.id) {
      return [pscustomobject]@{
        ok = $true
        listing_id = [int]$owned.id
        reason = "found_merchant_owned_listing"
        first_five = $firstFive
      }
    }
  }

  $createListing = Invoke-Api -Method "POST" -Path "/api/listings" -Headers $MerchantHeaders -BodyObj @{
    title = "QA Listing $(Get-Date -Format 'yyyyMMddHHmmss')"
    description = "QA"
    price = 100
    state = "Lagos"
    city = "Ikeja"
    locality = ""
  }
  Write-Host "create listing (merchant):" $createListing.StatusCode
  if ($createListing.Body) { Write-Host "create listing body:" $createListing.Body }
  if (OkStatus $createListing.StatusCode -and $createListing.Json -and $createListing.Json.listing -and $createListing.Json.listing.id) {
    return [pscustomobject]@{
      ok = $true
      listing_id = [int]$createListing.Json.listing.id
      reason = "created_listing_as_merchant"
      first_five = $firstFive
    }
  }

  $seed = Invoke-Api -Method "POST" -Path "/api/admin/demo/seed-listing" -Headers $AdminHeaders
  Write-Host "seed listing:" $seed.StatusCode
  if ($seed.Body) { Write-Host "seed listing body:" $seed.Body }

  $adminListingsAfter = Invoke-Api -Method "GET" -Path "/api/admin/listings" -Headers $AdminHeaders
  Write-Host "admin listings (after seed):" $adminListingsAfter.StatusCode
  if (OkStatus $adminListingsAfter.StatusCode -and $adminListingsAfter.Json -and $adminListingsAfter.Json.items) {
    $itemsAfter = @($adminListingsAfter.Json.items)
    $firstFive = $itemsAfter | Select-Object -First 5 | ForEach-Object {
      [pscustomobject]@{ id = $_.id; owner_id = (Get-ListingOwnerId $_) }
    }
    $ownedAfter = $itemsAfter | Where-Object { [int](Get-ListingOwnerId $_) -eq $MerchantId } | Select-Object -First 1
    if ($ownedAfter -and $ownedAfter.id) {
      return [pscustomobject]@{
        ok = $true
        listing_id = [int]$ownedAfter.id
        reason = "found_after_seed"
        first_five = $firstFive
      }
    }
  }

  return [pscustomobject]@{
    ok = $false
    listing_id = $null
    reason = "no_merchant_owned_listing_found"
    first_five = $firstFive
  }
}

Write-Host "base:" $Base
$version = Invoke-Api -Method "GET" -Path "/api/version"
Write-Host "version:" $version.StatusCode
if ($version.Body) { Write-Host "version body:" $version.Body }

if (-not $AdminEmail -or -not $AdminPassword) { Fail "Missing ADMIN_EMAIL/ADMIN_PASSWORD" }
if (-not $BuyerPassword) { $BuyerPassword = "TestPass123!" }
if (-not $BuyerEmail) { $BuyerEmail = New-RandomEmail "buyer_rules" }
if (-not $MerchantPassword) { $MerchantPassword = "TestPass123!" }

$generatedBuyerEmail = $null
$generatedMerchantEmail = $null

Write-Host "admin email:" $AdminEmail
Write-Host "buyer email:" $BuyerEmail
if ($MerchantEmail) { Write-Host "merchant email (input):" $MerchantEmail }
Write-Host "merchant register path disabled in smoke (using admin role-approval flow)"

$adminLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $AdminEmail; password = $AdminPassword }
Write-Host "admin login:" $adminLogin.StatusCode
if (-not (OkStatus $adminLogin.StatusCode)) { Fail "admin login failed" }
$adminToken = $adminLogin.Json.token
if (-not $adminToken) { Fail "admin token missing" }
$adminHeaders = @{ Authorization = "Bearer $adminToken" }

$buyerLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $BuyerEmail; password = $BuyerPassword }
Write-Host "buyer login:" $buyerLogin.StatusCode
if ($buyerLogin.StatusCode -eq 401) {
  $generatedBuyerEmail = New-RandomEmail "buyer_rules"
  $buyerPhone = New-RandomPhone
  $BuyerEmail = $generatedBuyerEmail
  Write-Host "buyer auto-register email:" $BuyerEmail
  $buyerReg = Invoke-Api -Method "POST" -Path "/api/auth/register/buyer" -BodyObj @{
    name = "Rules Buyer"
    email = $BuyerEmail
    password = $BuyerPassword
    phone = $buyerPhone
  }
  Write-Host "buyer register:" $buyerReg.StatusCode
  if (-not (OkStatus $buyerReg.StatusCode)) { Fail "buyer register failed" }
  $buyerLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $BuyerEmail; password = $BuyerPassword }
  Write-Host "buyer login (new):" $buyerLogin.StatusCode
}
if (-not (OkStatus $buyerLogin.StatusCode)) { Fail "buyer login failed" }
$buyerToken = $buyerLogin.Json.token
if (-not $buyerToken) { Fail "buyer token missing" }
$buyerHeaders = @{ Authorization = "Bearer $buyerToken" }

$merchantUsers = Invoke-Api -Method "GET" -Path "/api/admin/users?role=merchant" -Headers $adminHeaders
Write-Host "admin users (role=merchant):" $merchantUsers.StatusCode

$merchantToken = $null
$merchantHeaders = $null

if ($MerchantEmail) {
  $merchantLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $MerchantEmail; password = $MerchantPassword }
  Write-Host "merchant login (provided):" $merchantLogin.StatusCode
  if (OkStatus $merchantLogin.StatusCode -and $merchantLogin.Json -and $merchantLogin.Json.token) {
    $merchantToken = $merchantLogin.Json.token
    $merchantHeaders = @{ Authorization = "Bearer $merchantToken" }
  } else {
    Fail "merchant login failed for provided MERCHANT_EMAIL/MERCHANT_PASSWORD"
  }
}

if (-not $merchantToken) {
  $merchantEmailForProvision = $MerchantEmail
  if (-not $merchantEmailForProvision) {
    $merchantEmailForProvision = New-RandomEmail "merchant_rules"
    $generatedMerchantEmail = $merchantEmailForProvision
  }
  $merchantPhone = New-RandomPhone

  Write-Host "merchant auto-register as buyer:" $merchantEmailForProvision
  $merchantBaseReg = Invoke-Api -Method "POST" -Path "/api/auth/register/buyer" -BodyObj @{
    name = "Rules Merchant"
    email = $merchantEmailForProvision
    password = $MerchantPassword
    phone = $merchantPhone
  }
  Write-Host "merchant base register:" $merchantBaseReg.StatusCode
  if (-not (OkStatus $merchantBaseReg.StatusCode)) { Fail "merchant base register failed" }

  $merchantBaseLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $merchantEmailForProvision; password = $MerchantPassword }
  Write-Host "merchant base login:" $merchantBaseLogin.StatusCode
  if (-not (OkStatus $merchantBaseLogin.StatusCode)) { Fail "merchant base login failed" }
  $merchantBaseToken = $merchantBaseLogin.Json.token
  if (-not $merchantBaseToken) { Fail "merchant base token missing" }
  $merchantBaseHeaders = @{ Authorization = "Bearer $merchantBaseToken" }

  $merchantRoleReq = Invoke-Api -Method "POST" -Path "/api/role-requests" -Headers $merchantBaseHeaders -BodyObj @{ requested_role = "merchant"; reason = "rules smoke auto-provision" }
  Write-Host "merchant role request:" $merchantRoleReq.StatusCode
  if ($merchantRoleReq.StatusCode -ne 201 -and $merchantRoleReq.StatusCode -ne 409) {
    Fail "merchant role request failed"
  }

  $roleReqId = $null
  if ($merchantRoleReq.Json -and $merchantRoleReq.Json.request -and $merchantRoleReq.Json.request.id) {
    $roleReqId = [int]$merchantRoleReq.Json.request.id
  }
  if (-not $roleReqId) {
    $merchantReqMe = Invoke-Api -Method "GET" -Path "/role-requests/me" -Headers $merchantBaseHeaders
    Write-Host "merchant role request me:" $merchantReqMe.StatusCode
    if (OkStatus $merchantReqMe.StatusCode -and $merchantReqMe.Json -and $merchantReqMe.Json.request -and $merchantReqMe.Json.request.id) {
      $roleReqId = [int]$merchantReqMe.Json.request.id
    }
  }
  if (-not $roleReqId) {
    $adminPending = Invoke-Api -Method "GET" -Path "/api/admin/role-requests?status=PENDING" -Headers $adminHeaders
    Write-Host "admin pending role requests:" $adminPending.StatusCode
    if (OkStatus $adminPending.StatusCode -and $adminPending.Json -and $adminPending.Json.items) {
      $match = $adminPending.Json.items | Where-Object { $_.requested_role -eq "merchant" } | Select-Object -First 1
      if ($match -and $match.id) { $roleReqId = [int]$match.id }
    }
  }
  if (-not $roleReqId) { Fail "merchant role request id missing" }

  $approve = Invoke-Api -Method "POST" -Path "/api/admin/role-requests/$roleReqId/approve" -Headers $adminHeaders -BodyObj @{ admin_note = "rules smoke approve" }
  Write-Host "admin approve merchant role request:" $approve.StatusCode
  if (-not (OkStatus $approve.StatusCode)) { Fail "merchant role approval failed" }

  $MerchantEmail = $merchantEmailForProvision
  $merchantLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $MerchantEmail; password = $MerchantPassword }
  Write-Host "merchant login (approved):" $merchantLogin.StatusCode
  if (-not (OkStatus $merchantLogin.StatusCode)) { Fail "merchant login after approval failed" }
  $merchantToken = $merchantLogin.Json.token
  if (-not $merchantToken) { Fail "merchant token missing" }
  $merchantHeaders = @{ Authorization = "Bearer $merchantToken" }
}

$merchantMe = Invoke-Api -Method "GET" -Path "/api/auth/me" -Headers $merchantHeaders
Write-Host "merchant me:" $merchantMe.StatusCode
if (-not (OkStatus $merchantMe.StatusCode)) { Fail "merchant /api/auth/me failed" }
$merchantId = $merchantMe.Json.id
if (-not $merchantId) { Fail "merchant id missing" }
if (($merchantMe.Json.role | Out-String).Trim().ToLower() -ne "merchant") { Fail "merchant role not active" }

# Role switch should be forbidden for non-admin
$roleSwitch = Invoke-Api -Method "POST" -Path "/api/auth/set-role" -Headers $buyerHeaders -BodyObj @{ role = "admin" }
Write-Host "buyer set-role admin:" $roleSwitch.StatusCode
if ($roleSwitch.StatusCode -ne 403) { Fail "role switch not blocked" }

# Buyer can follow merchant
$follow = Invoke-Api -Method "POST" -Path "/api/merchants/$merchantId/follow" -Headers $buyerHeaders
Write-Host "buyer follow merchant:" $follow.StatusCode
if (-not (OkStatus $follow.StatusCode)) { Fail "buyer follow failed" }

# Merchant cannot follow
$merchantFollow = Invoke-Api -Method "POST" -Path "/api/merchants/$merchantId/follow" -Headers $merchantHeaders
Write-Host "merchant follow merchant:" $merchantFollow.StatusCode
if ($merchantFollow.StatusCode -ne 403) { Fail "merchant follow not blocked" }

# Chat rule: user-to-user chat blocked (buyer tries to target merchant user_id)
$chat = Invoke-Api -Method "POST" -Path "/api/support/messages" -Headers $buyerHeaders -BodyObj @{ body = "Hi"; user_id = [int]$merchantId }
Write-Host "buyer chat non-admin target:" $chat.StatusCode
if ($chat.StatusCode -ne 403) { Fail "chat not blocked" }

# Self-buy guard test: must use a merchant-owned listing.
$resolvedListing = Resolve-MerchantOwnedListingId -AdminHeaders $adminHeaders -MerchantHeaders $merchantHeaders -MerchantId ([int]$merchantId
)
if (-not $resolvedListing.ok -or -not $resolvedListing.listing_id) {
  Write-Host "merchant id:" $merchantId
  Write-Host "listing resolve reason:" $resolvedListing.reason
  if ($resolvedListing.first_five -and $resolvedListing.first_five.Count -gt 0) {
    Write-Host "first 5 admin listings (id/owner_id):"
    foreach ($row in $resolvedListing.first_five) {
      Write-Host " - id=$($row.id), owner_id=$($row.owner_id)"
    }
  } else {
    Write-Host "first 5 admin listings (id/owner_id): none"
  }
  Fail "merchant-owned listing id missing"
}

$listingId = [int]$resolvedListing.listing_id
$buy = Invoke-Api -Method "POST" -Path "/api/orders" -Headers $merchantHeaders -BodyObj @{
  listing_id = $listingId
  merchant_id = [int]$merchantId
  amount = 100
  delivery_fee = 0
  inspection_fee = 0
  pickup = "Ikeja"
  dropoff = "Ikeja"
  payment_reference = "qa_selfbuy_$(Get-Date -Format 'yyyyMMddHHmmss')"
}
Write-Host "self-buy order:" $buy.StatusCode
if ($buy.Body) { Write-Host "self-buy body:" $buy.Body }
if ($buy.StatusCode -ne 409 -and $buy.StatusCode -ne 400) { Fail "self-buy not blocked with expected status" }
if (-not $buy.Json) { Fail "self-buy response missing JSON body" }
if ($buy.Json.error -ne "SELLER_CANNOT_BUY_OWN_LISTING") { Fail "self-buy response missing expected error code" }
if (-not ($buy.Json.message -like "*own listing*")) { Fail "self-buy response missing expected message" }

if ($generatedBuyerEmail) { Write-Host "buyer generated email:" $generatedBuyerEmail }
if ($generatedMerchantEmail) { Write-Host "merchant generated email:" $generatedMerchantEmail }
Write-Host "OK: rules smoke passed"
