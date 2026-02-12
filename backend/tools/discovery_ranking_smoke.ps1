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
    $Email = "buyer_discovery_$r@t.com"
    $Password = "TestPass123!"
    $phone = "+23480$($r.ToString().Substring(0, [Math]::Min(7, $r.ToString().Length)))"
    $reg = Invoke-Api -Method "POST" -Path "/api/auth/register/buyer" -BodyObj @{
      name = "Buyer Discovery $r"
      email = $Email
      password = $Password
      phone = $phone
    }
    Write-Host "POST /api/auth/register/buyer -> $($reg.StatusCode)"
  }
  if (-not $Password) { $Password = "TestPass123!" }
  $login = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $Email; password = $Password }
  Assert-Ok $login "POST /api/auth/login (buyer)"
  if (-not $login.Json -or -not $login.Json.token) {
    Write-Host "buyer login missing token"
    exit 1
  }
  return [pscustomobject]@{ Email = $Email; Token = $login.Json.token }
}

Write-Host "discovery ranking smoke: base=$Base"
$version = Invoke-Api -Path "/api/version"
Write-Host "GET /api/version -> $($version.StatusCode)"
if ($version.Body) { Write-Host $version.Body }

$adminLogin = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $AdminEmail; password = $AdminPassword }
Assert-Ok $adminLogin "POST /api/auth/login (admin)"
$adminHeaders = @{ Authorization = "Bearer $($adminLogin.Json.token)"; "X-Debug" = "1" }

$seed = Invoke-Api -Method "POST" -Path "/api/admin/demo/seed-nationwide" -Headers $adminHeaders -BodyObj @{}
Write-Host "POST /api/admin/demo/seed-nationwide -> $($seed.StatusCode)"

$buyer = Ensure-Buyer -Email $BuyerEmail -Password $BuyerPassword
$buyerHeaders = @{ Authorization = "Bearer $($buyer.Token)"; "X-Debug" = "1" }

$setPrefs = Invoke-Api -Method "POST" -Path "/api/me/preferences" -Headers $buyerHeaders -BodyObj @{
  preferred_city = "Lagos"
  preferred_state = "Lagos"
}
Assert-Ok $setPrefs "POST /api/me/preferences"

$recommended = Invoke-Api -Method "GET" -Path "/api/public/listings/recommended?city=Lagos&state=Lagos&limit=10" -Headers $buyerHeaders
Assert-Ok $recommended "GET /api/public/listings/recommended"
if ($recommended.Json -and $recommended.Json.items) {
  $items = @($recommended.Json.items)
  Write-Host "recommended count=$($items.Count)"
  if ($items.Count -gt 0) {
    $top = $items[0]
    Write-Host "top listing id=$($top.id) reasons=$([string]::Join(',', @($top.ranking_reason)))"
  }
}

$search = Invoke-Api -Method "GET" -Path "/api/public/listings/search?q=ps5&state=Lagos&limit=10" -Headers $buyerHeaders
Assert-Ok $search "GET /api/public/listings/search"
if ($search.Json -and $search.Json.items) {
  $items = @($search.Json.items)
  if ($items.Count -gt 0) {
    Write-Host "search top id=$($items[0].id) reasons=$([string]::Join(',', @($items[0].ranking_reason)))"
  }
}

$global = Invoke-Api -Method "GET" -Path "/api/public/search?q=tv&city=Lagos&limit=5"
Assert-Ok $global "GET /api/public/search"

$suggest = Invoke-Api -Method "GET" -Path "/api/public/search/suggest?q=iph&city=Lagos&limit=5"
Assert-Ok $suggest "GET /api/public/search/suggest"

$titles = Invoke-Api -Method "GET" -Path "/api/public/listings/title-suggestions?q=lap&limit=5"
Assert-Ok $titles "GET /api/public/listings/title-suggestions"

Write-Host "OK: discovery ranking smoke passed"
exit 0

