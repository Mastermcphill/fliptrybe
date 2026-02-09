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

$login = Invoke-Api -Method "POST" -Url "$base/api/auth/login" -BodyObj @{ email = $adminEmail; password = $adminPassword }
Write-Host "POST /api/auth/login => $($login.StatusCode)"
if (-not $login.Json -or -not $login.Json.token) {
  Write-Host $login.Body
  exit 3
}
$headers = @{ Authorization = "Bearer $($login.Json.token)" }

$res = Invoke-Api -Url "$base/api/admin/orders" -Headers $headers
Write-Host "GET /api/admin/orders => $($res.StatusCode)"
if ($res.Body) { Write-Host $res.Body }
if ($res.StatusCode -lt 200 -or $res.StatusCode -ge 300) { exit 4 }

exit 0
