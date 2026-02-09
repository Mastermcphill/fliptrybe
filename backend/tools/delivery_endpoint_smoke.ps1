$ErrorActionPreference = "Stop"

$base = $env:BASE_URL
if (-not $base) { $base = "https://tri-o-fliptrybe.onrender.com" }

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

Write-Host "BASE=$base"
$version = Invoke-Api -Url "$base/api/version"
Write-Host "GET /api/version => $($version.StatusCode)"
if ($version.Body) { Write-Host $version.Body }

$login = Invoke-Api -Method "POST" -Url "$base/api/auth/login" -BodyObj @{ email = $adminEmail; password = $adminPassword }
Write-Host "POST /api/auth/login => $($login.StatusCode)"
if (-not $login.Json -or -not $login.Json.token) {
  Write-Host $login.Body
  exit 3
}
$headers = @{ Authorization = "Bearer $($login.Json.token)" }

$notFound = Invoke-Api -Url "$base/api/orders/999999/delivery" -Headers $headers
Write-Host "GET /api/orders/999999/delivery => $($notFound.StatusCode)"
if ($notFound.Body) { Write-Host $notFound.Body }
if ($notFound.StatusCode -ne 404 -or ($notFound.Json.error -ne "order_not_found")) { exit 4 }

$orderId = $env:ORDER_ID
if ($orderId) {
  $ok = Invoke-Api -Url "$base/api/orders/$orderId/delivery" -Headers $headers
  Write-Host "GET /api/orders/$orderId/delivery => $($ok.StatusCode)"
  if ($ok.Body) { Write-Host $ok.Body }
  if ($ok.StatusCode -lt 200 -or $ok.StatusCode -ge 300) { exit 5 }
}

Write-Host "OK: delivery endpoint smoke passed"
exit 0
