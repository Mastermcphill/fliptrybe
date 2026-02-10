param(
  [string]$Base = "https://tri-o-fliptrybe.onrender.com",
  [string]$AdminEmail = $env:ADMIN_EMAIL,
  [string]$AdminPassword = $env:ADMIN_PASSWORD,
  [switch]$SeedLeaderboards
)

$ErrorActionPreference = "Continue"

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
    [pscustomobject]@{ Url = $url; StatusCode = [int]$resp.StatusCode; Body = $resp.Content; Json = $json }
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
    [pscustomobject]@{ Url = $url; StatusCode = $status; Body = $body; Json = $json }
  }
}

function Fail([string]$Message) {
  Write-Host "FAIL: $Message"
  exit 1
}

function Assert-Good([object]$Resp, [string]$Name) {
  Write-Host "$Name => $($Resp.StatusCode)"
  if ($Resp.StatusCode -eq 404 -or $Resp.StatusCode -ge 500 -or $Resp.StatusCode -lt 0) {
    if ($Resp.Body) { Write-Host $Resp.Body }
    Fail "$Name unhealthy"
  }
}

function Print-Summary([object]$Resp, [string]$Name) {
  if ($null -eq $Resp.Json) {
    return
  }
  if ($Resp.Json -is [System.Collections.IEnumerable] -and -not ($Resp.Json -is [string])) {
    $arr = @($Resp.Json)
    Write-Host "$Name items: $($arr.Count)"
    if ($arr.Count -gt 0) {
      Write-Host "$Name first: $($arr[0] | ConvertTo-Json -Compress -Depth 6)"
    }
    return
  }
  if ($Resp.Json -is [hashtable] -or $Resp.Json -is [pscustomobject]) {
    $obj = $Resp.Json
    if ($obj.PSObject.Properties.Name -contains "items") {
      $items = @($obj.items)
      Write-Host "$Name items: $($items.Count)"
      if ($items.Count -gt 0) {
        Write-Host "$Name first: $($items[0] | ConvertTo-Json -Compress -Depth 6)"
      }
    } else {
      Write-Host "$Name body: $($obj | ConvertTo-Json -Compress -Depth 6)"
    }
  }
}

Write-Host "base: $Base"
if (-not $AdminEmail -or -not $AdminPassword) {
  Fail "Missing ADMIN_EMAIL or ADMIN_PASSWORD."
}

$version = Invoke-Api -Path "/api/version"
Assert-Good $version "GET /api/version"
if ($version.Body) { Write-Host "version body: $($version.Body)" }

$health = Invoke-Api -Path "/api/health"
Assert-Good $health "GET /api/health"

$login = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $AdminEmail; password = $AdminPassword }
Write-Host "POST /api/auth/login => $($login.StatusCode)"
if ($login.StatusCode -lt 200 -or $login.StatusCode -ge 300 -or -not $login.Json -or -not $login.Json.token) {
  if ($login.Body) { Write-Host $login.Body }
  Fail "Admin login failed"
}
$headers = @{ Authorization = "Bearer $($login.Json.token)" }

if ($SeedLeaderboards.IsPresent) {
  $seed = Invoke-Api -Method "POST" -Path "/api/admin/demo/seed-leaderboards" -Headers $headers -BodyObj @{}
  Assert-Good $seed "POST /api/admin/demo/seed-leaderboards"
  Print-Summary $seed "seed-leaderboards"
}

$checks = @(
  @{ Name = "GET /api/admin/audit"; Path = "/api/admin/audit" },
  @{ Name = "GET /api/admin/autopilot"; Path = "/api/admin/autopilot" },
  @{ Name = "GET /api/admin/notify-queue"; Path = "/api/admin/notify-queue" },
  @{ Name = "GET /api/admin/role-requests?status=PENDING"; Path = "/api/admin/role-requests?status=PENDING" },
  @{ Name = "GET /api/admin/inspector-requests?status=pending"; Path = "/api/admin/inspector-requests?status=pending" },
  @{ Name = "GET /api/kyc/admin/pending"; Path = "/api/kyc/admin/pending" },
  @{ Name = "GET /api/admin/commission"; Path = "/api/admin/commission" },
  @{ Name = "GET /api/wallet/admin/payouts?status=pending"; Path = "/api/wallet/admin/payouts?status=pending" },
  @{ Name = "GET /api/admin/support/threads"; Path = "/api/admin/support/threads" },
  @{ Name = "GET /api/leaderboards"; Path = "/api/leaderboards?limit=20" },
  @{ Name = "GET /api/leaderboards?state=Lagos"; Path = "/api/leaderboards?state=Lagos&limit=20" }
)

foreach ($c in $checks) {
  $resp = Invoke-Api -Path $c.Path -Headers $headers
  Assert-Good $resp $c.Name
  Print-Summary $resp $c.Name
}

Write-Host "OK: adminhub smoke passed"
exit 0
