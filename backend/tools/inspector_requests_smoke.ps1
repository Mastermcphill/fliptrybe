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

$rand = Get-Random
$email = "inspector_$rand@t.com"
$phone = "+234801$rand"

$reqPayload = @{
  name = "Inspector QA $rand"
  email = $email
  phone = $phone
  notes = "QA request"
}
$reqRes = Invoke-Api -Method "POST" -Url "$base/api/public/inspector-requests" -BodyObj $reqPayload
Write-Host "POST /api/public/inspector-requests => $($reqRes.StatusCode)"
if ($reqRes.StatusCode -lt 200 -or $reqRes.StatusCode -ge 300) { Write-Host $reqRes.Body; exit 3 }

$adminPayload = @{ email = $adminEmail; password = $adminPassword } | ConvertTo-Json
$loginRes = Invoke-Api -Method "POST" -Url "$base/api/auth/login" -BodyObj @{ email = $adminEmail; password = $adminPassword }
Write-Host "POST /api/auth/login (admin) => $($loginRes.StatusCode)"
if (-not $loginRes.Json -or -not $loginRes.Json.token) { Write-Host $loginRes.Body; exit 4 }
$adminHeaders = @{ Authorization = "Bearer $($loginRes.Json.token)" }

$listRes = Invoke-Api -Method "GET" -Url "$base/api/admin/inspector-requests?status=pending" -Headers $adminHeaders
Write-Host "GET /api/admin/inspector-requests?status=pending => $($listRes.StatusCode)"
if ($listRes.StatusCode -lt 200 -or $listRes.StatusCode -ge 300) { Write-Host $listRes.Body; exit 5 }

$reqId = $null
if ($listRes.Json -and $listRes.Json.items) {
  $match = $listRes.Json.items | Where-Object { $_.email -eq $email } | Select-Object -First 1
  if ($match) { $reqId = [int]$match.id }
}
if (-not $reqId) { Write-Host "Request not found in pending list"; exit 6 }

$approveRes = Invoke-Api -Method "POST" -Url "$base/api/admin/inspector-requests/$reqId/approve" -Headers $adminHeaders
Write-Host "POST /api/admin/inspector-requests/$reqId/approve => $($approveRes.StatusCode)"
if ($approveRes.StatusCode -lt 200 -or $approveRes.StatusCode -ge 300) { Write-Host $approveRes.Body; exit 7 }
if (-not $approveRes.Json -or -not $approveRes.Json.user -or $approveRes.Json.user.role -ne "inspector") {
  Write-Host "Approve response missing inspector role"
  Write-Host $approveRes.Body
  exit 8
}

Write-Host "OK: inspector approved user_id=$($approveRes.Json.user.id) created=$($approveRes.Json.created)"
exit 0
