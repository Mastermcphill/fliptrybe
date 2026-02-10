param(
  [string]$Base = "https://tri-o-fliptrybe.onrender.com",
  [string]$AdminEmail = $(if ($env:ADMIN_EMAIL) { $env:ADMIN_EMAIL } else { "vidzimedialtd@gmail.com" }),
  [string]$AdminPassword = $(if ($env:ADMIN_PASSWORD) { $env:ADMIN_PASSWORD } else { "NewPass1234!" })
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
    [pscustomobject]@{ Method = $Method; Url = $url; StatusCode = [int]$resp.StatusCode; Body = $resp.Content; Json = $json }
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
    [pscustomobject]@{ Method = $Method; Url = $url; StatusCode = $status; Body = $body; Json = $json }
  }
}

function Assert-2xx([object]$resp, [string]$label) {
  Write-Host "$label -> $($resp.StatusCode)"
  if ($resp.StatusCode -lt 200 -or $resp.StatusCode -ge 300) {
    if ($resp.Body) { Write-Host $resp.Body }
    exit 1
  }
}

function Invoke-Tick([hashtable]$Headers, [string]$Label) {
  $tick = Invoke-Api -Method "POST" -Path "/api/admin/autopilot/tick" -Headers $Headers -BodyObj @{}
  Assert-2xx $tick $Label
  if ($tick.Json -and $tick.Json.skipped -eq $true) {
    Start-Sleep -Seconds 26
    $tick = Invoke-Api -Method "POST" -Path "/api/admin/autopilot/tick" -Headers $Headers -BodyObj @{}
    Assert-2xx $tick "$Label (retry)"
  }
  return $tick
}

function Queue-TestMessage {
  param([hashtable]$Headers, [string]$Channel, [string]$Message, [string]$Ref)
  $resp = Invoke-Api -Method "POST" -Path "/api/admin/notify-queue/demo/enqueue" -Headers $Headers -BodyObj @{
    channel = $Channel
    to = "+2348011111111"
    message = $Message
    reference = $Ref
    max_attempts = 3
  }
  Assert-2xx $resp "POST /api/admin/notify-queue/demo/enqueue ($Channel)"
  return $resp.Json.row.id
}

function Find-QueueByRef {
  param([hashtable]$Headers, [string]$Ref)
  $resp = Invoke-Api -Method "GET" -Path "/api/admin/notify-queue" -Headers $Headers
  Assert-2xx $resp "GET /api/admin/notify-queue"
  foreach ($row in @($resp.Json)) {
    if (($row.reference | Out-String).Trim() -eq $Ref) {
      return $row
    }
  }
  return $null
}

Write-Host "notify queue smoke: base=$Base"
$version = Invoke-Api -Path "/api/version"
Write-Host "GET /api/version -> $($version.StatusCode)"
if ($version.Body) { Write-Host $version.Body }

$login = Invoke-Api -Method "POST" -Path "/api/auth/login" -BodyObj @{ email = $AdminEmail; password = $AdminPassword }
Assert-2xx $login "POST /api/auth/login (admin)"
if (-not $login.Json -or -not $login.Json.token) { Write-Host $login.Body; exit 1 }
$headers = @{ Authorization = "Bearer $($login.Json.token)"; "X-Debug" = "1" }
$toggle = Invoke-Api -Method "POST" -Path "/api/admin/autopilot/toggle" -Headers $headers -BodyObj @{ enabled = $true }
Assert-2xx $toggle "POST /api/admin/autopilot/toggle (enable)"

# Stage 1: channels disabled => queued with INTEGRATION_DISABLED
$cfgDisabled = Invoke-Api -Method "POST" -Path "/api/admin/autopilot/settings" -Headers $headers -BodyObj @{
  payments_provider = "mock"
  integrations_mode = "sandbox"
  paystack_enabled = $true
  termii_enabled_sms = $false
  termii_enabled_wa = $false
}
Assert-2xx $cfgDisabled "POST /api/admin/autopilot/settings (disabled)"
$ref1 = "notify-smoke-disabled-$(Get-Date -Format yyyyMMddHHmmss)"
$id1 = Queue-TestMessage -Headers $headers -Channel "sms" -Message "notify disabled smoke" -Ref $ref1
$tick1 = Invoke-Tick -Headers $headers -Label "POST /api/admin/autopilot/tick (disabled)"
$row1 = Find-QueueByRef -Headers $headers -Ref $ref1
if ($null -eq $row1) { Write-Host "queue row not found for $ref1"; exit 1 }
$err1 = (($row1.last_error | Out-String).Trim())
if ((($row1.status | Out-String).Trim().ToLower()) -ne "queued") {
  Write-Host "expected queued row when disabled, got: $($row1 | ConvertTo-Json -Depth 10)"
  exit 1
}
if ($err1 -and $err1 -notlike "INTEGRATION_DISABLED*") {
  Write-Host "unexpected last_error: $err1"
  exit 1
}
Write-Host "disabled check: status=$($row1.status) last_error=$err1"

# Stage 2: channels enabled in sandbox/mock => sent
$cfgEnabled = Invoke-Api -Method "POST" -Path "/api/admin/autopilot/settings" -Headers $headers -BodyObj @{
  payments_provider = "mock"
  integrations_mode = "sandbox"
  paystack_enabled = $true
  termii_enabled_sms = $true
  termii_enabled_wa = $true
}
Assert-2xx $cfgEnabled "POST /api/admin/autopilot/settings (enabled)"
$ref2 = "notify-smoke-enabled-$(Get-Date -Format yyyyMMddHHmmss)"
$id2 = Queue-TestMessage -Headers $headers -Channel "whatsapp" -Message "notify enabled smoke" -Ref $ref2
$tick2 = Invoke-Tick -Headers $headers -Label "POST /api/admin/autopilot/tick (enabled)"
$row2 = Find-QueueByRef -Headers $headers -Ref $ref2
if ($null -eq $row2) { Write-Host "queue row not found for $ref2"; exit 1 }
if ((($row2.status | Out-String).Trim().ToLower()) -ne "sent") {
  Write-Host "expected sent row, got: $($row2 | ConvertTo-Json -Depth 10)"
  exit 1
}
Write-Host "enabled check status: $($row2.status)"

# Stage 3: live mode without Termii keys => queued with INTEGRATION_MISCONFIGURED
$cfgMis = Invoke-Api -Method "POST" -Path "/api/admin/autopilot/settings" -Headers $headers -BodyObj @{
  payments_provider = "mock"
  integrations_mode = "live"
  paystack_enabled = $true
  termii_enabled_sms = $true
  termii_enabled_wa = $true
}
Assert-2xx $cfgMis "POST /api/admin/autopilot/settings (live)"
$ref3 = "notify-smoke-misconfig-$(Get-Date -Format yyyyMMddHHmmss)"
$id3 = Queue-TestMessage -Headers $headers -Channel "sms" -Message "notify misconfigured smoke" -Ref $ref3
$tick3 = Invoke-Tick -Headers $headers -Label "POST /api/admin/autopilot/tick (misconfigured)"
$row3 = Find-QueueByRef -Headers $headers -Ref $ref3
if ($null -eq $row3) { Write-Host "queue row not found for $ref3"; exit 1 }
$err3 = (($row3.last_error | Out-String).Trim())
if ($err3 -notlike "INTEGRATION_MISCONFIGURED*") {
  Write-Host "unexpected last_error: $err3"
  exit 1
}
Write-Host "misconfigured check last_error: $err3"

Write-Host "OK: notify queue smoke passed"
exit 0
