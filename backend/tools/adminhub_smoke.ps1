param(
  [string]$Base = "https://tri-o-fliptrybe.onrender.com",
  [string]$AdminEmail = "vidzimedialtd@gmail.com",
  [string]$AdminPassword = "NewPass1234!",
  [switch]$SeedNationwide,
  [switch]$SeedLeaderboards
)

$ErrorActionPreference = "Continue"

$script:Passed = 0
$script:Failed = 0

function Invoke-Api {
  param(
    [string]$Method = "GET",
    [string]$Path,
    [hashtable]$Headers = @{},
    $BodyObj = $null
  )
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
    return [pscustomobject]@{
      Method = $Method
      Url = $url
      StatusCode = [int]$resp.StatusCode
      Body = $resp.Content
      Json = $json
    }
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
    return [pscustomobject]@{
      Method = $Method
      Url = $url
      StatusCode = $status
      Body = $body
      Json = $json
    }
  }
}

function Get-ShortMessage([object]$resp) {
  if ($resp.Json) {
    if ($resp.Json.PSObject.Properties.Name -contains "ok") {
      return "ok=$($resp.Json.ok)"
    }
    if ($resp.Json.PSObject.Properties.Name -contains "message") {
      return ("message=" + ($resp.Json.message | Out-String).Trim())
    }
    if ($resp.Json.PSObject.Properties.Name -contains "items") {
      try {
        $count = @($resp.Json.items).Count
        return "items=$count"
      } catch {}
    }
  }
  return ""
}

function Write-Result([object]$resp) {
  $short = Get-ShortMessage $resp
  if ($short) {
    Write-Host "$($resp.Method) $($resp.Url) -> $($resp.StatusCode) ($short)"
  } else {
    Write-Host "$($resp.Method) $($resp.Url) -> $($resp.StatusCode)"
  }
}

function Check-Result([object]$resp) {
  if ($resp.StatusCode -eq 404 -or $resp.StatusCode -ge 500 -or $resp.StatusCode -lt 0) {
    $script:Failed++
    return $false
  }
  $script:Passed++
  return $true
}

function Call-And-Check {
  param(
    [string]$Method = "GET",
    [string]$Path,
    [hashtable]$Headers = @{},
    $BodyObj = $null
  )
  $resp = Invoke-Api -Method $Method -Path $Path -Headers $Headers -BodyObj $BodyObj
  Write-Result $resp
  if (-not (Check-Result $resp)) {
    if ($resp.Body) { Write-Host $resp.Body }
    exit 1
  }
  return $resp
}

Write-Host "AdminHub smoke start: base=$Base"

$version = Call-And-Check -Method "GET" -Path "/api/version"
$health = Call-And-Check -Method "GET" -Path "/api/health"

$login = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $AdminEmail; password = $AdminPassword }
Write-Result $login
if ($login.StatusCode -lt 200 -or $login.StatusCode -ge 300 -or -not $login.Json -or -not $login.Json.token) {
  if ($login.Body) { Write-Host $login.Body }
  Write-Host "Summary: passed=$script:Passed failed=$($script:Failed + 1)"
  exit 1
}
$script:Passed++

$headers = @{ Authorization = "Bearer $($login.Json.token)" }

if ($SeedNationwide.IsPresent) {
  $seedHeaders = @{
    Authorization = "Bearer $($login.Json.token)"
    "X-Debug" = "1"
  }
  Call-And-Check -Method "POST" -Path "/api/admin/demo/seed-nationwide" -Headers $seedHeaders -BodyObj @{}
}

if ($SeedLeaderboards.IsPresent) {
  $seedHeaders = @{
    Authorization = "Bearer $($login.Json.token)"
    "X-Debug" = "1"
  }
  Call-And-Check -Method "POST" -Path "/api/admin/demo/seed-leaderboards" -Headers $seedHeaders -BodyObj @{}
}

# AdminHub-backed endpoints (based on active frontend wiring)
Call-And-Check -Method "GET" -Path "/api/wallet/admin/payouts?status=pending" -Headers $headers
Call-And-Check -Method "GET" -Path "/api/admin/audit" -Headers $headers
Call-And-Check -Method "GET" -Path "/api/admin/support/threads" -Headers $headers
Call-And-Check -Method "GET" -Path "/api/admin/autopilot" -Headers $headers
Call-And-Check -Method "GET" -Path "/api/admin/notify-queue" -Headers $headers
Call-And-Check -Method "GET" -Path "/api/admin/role-requests?status=PENDING" -Headers $headers
Call-And-Check -Method "GET" -Path "/api/admin/inspector-requests?status=pending" -Headers $headers
Call-And-Check -Method "GET" -Path "/api/kyc/admin/pending" -Headers $headers
Call-And-Check -Method "GET" -Path "/api/admin/commission" -Headers $headers
Call-And-Check -Method "GET" -Path "/api/leaderboards?limit=20" -Headers $headers
Call-And-Check -Method "GET" -Path "/api/leaderboards?state=Lagos&limit=20" -Headers $headers

# Leaderboard quick meaning check
$lbNation = Invoke-Api -Method "GET" -Path "/api/leaderboards?limit=20" -Headers $headers
$lbLagos = Invoke-Api -Method "GET" -Path "/api/leaderboards?state=Lagos&limit=20" -Headers $headers
Write-Host "Leaderboard summary: nationwide_items=$(@($lbNation.Json.items).Count) lagos_items=$(@($lbLagos.Json.items).Count)"

Write-Host "Summary: passed=$script:Passed failed=$script:Failed"
if ($script:Failed -gt 0) { exit 1 }
Write-Host "OK: adminhub smoke passed"
exit 0
