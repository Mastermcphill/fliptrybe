Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-OpsState {
    param([string]$BackendRoot, [string]$BaseUrl)
    $opsRoot = Join-Path $BackendRoot "ops"
    $artifactDir = Join-Path $opsRoot "artifacts"
    if (-not (Test-Path $artifactDir)) { New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null }
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $artifact = Join-Path $artifactDir ("ops_run_{0}.log" -f $stamp)
    New-Item -ItemType File -Path $artifact -Force | Out-Null

    $python = $null
    if ($env:PYTHON -and (Test-Path $env:PYTHON)) {
        $python = $env:PYTHON
    } else {
        $cmd = Get-Command python -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Path) { $python = $cmd.Path }
    }
    if (-not $python) { throw "Python not found. Ensure actions/setup-python ran or set PYTHON env var." }

    $state = [ordered]@{
        BackendRoot = $BackendRoot
        OpsRoot = $opsRoot
        ArtifactDir = $artifactDir
        ArtifactPath = $artifact
        BaseUrl = $BaseUrl
        Python = $python
        Results = New-Object System.Collections.ArrayList
        ServerProcessId = $null
        Context = @{}
    }
    Write-Log -State $state -Message "OPS run started"
    Write-Log -State $state -Message ("BackendRoot={0}" -f $BackendRoot)
    Write-Log -State $state -Message ("BaseUrl={0}" -f $BaseUrl)
    return $state
}

function Write-Log {
    param([Parameter(Mandatory = $true)]$State,[Parameter(Mandatory = $true)][string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -Path $State.ArtifactPath -Value $line
}

function Add-Result {
    param($State,[string]$Phase,[string]$Test,[bool]$Pass,[string]$Status,[string]$Detail="")
    $row = [pscustomobject]@{ Phase=$Phase; Test=$Test; Result=$(if($Pass){"PASS"}else{"FAIL"}); Status=$Status; Detail=$Detail }
    [void]$State.Results.Add($row)
    Write-Log -State $State -Message ("[{0}] {1} => {2} ({3}) {4}" -f $Phase,$Test,$row.Result,$Status,$Detail)
}

function Print-ResultTable {
    param($State)
    Write-Host ""; Write-Host "=== OPS RESULT TABLE ==="
    $State.Results | Format-Table -AutoSize | Out-String -Width 240 | ForEach-Object { Write-Host $_ }
    Add-Content -Path $State.ArtifactPath -Value "`n=== OPS RESULT TABLE ==="
    Add-Content -Path $State.ArtifactPath -Value (($State.Results | Format-Table -AutoSize | Out-String -Width 240))
}

function Get-FailCount {
    param($State)
    return @($State.Results | Where-Object { $_.Result -eq "FAIL" }).Count
}

function Invoke-Api {
    param($State,[string]$Method="GET",[string]$Path,[hashtable]$Headers=@{},$BodyObj=$null)
    $uri = "{0}{1}" -f $State.BaseUrl.TrimEnd('/'), $Path
    try {
        if ($null -ne $BodyObj) {
            $body = $BodyObj | ConvertTo-Json -Depth 30 -Compress
            $resp = Invoke-WebRequest -Method $Method -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -UseBasicParsing
        } else {
            $resp = Invoke-WebRequest -Method $Method -Uri $uri -Headers $Headers -UseBasicParsing
        }
        $json = $null; try { $json = $resp.Content | ConvertFrom-Json } catch {}
        return [pscustomobject]@{ StatusCode=[int]$resp.StatusCode; Body=[string]$resp.Content; Json=$json; Uri=$uri; Method=$Method }
    } catch {
        $status = -1; $body = ""
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
            $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $body = $sr.ReadToEnd()
        } elseif ($_.ErrorDetails) {
            $body = $_.ErrorDetails.Message
        } else {
            $body = $_.Exception.Message
        }
        $json = $null; try { $json = $body | ConvertFrom-Json } catch {}
        return [pscustomobject]@{ StatusCode=[int]$status; Body=[string]$body; Json=$json; Uri=$uri; Method=$Method }
    }
}

function Wait-Health {
    param($State,[int]$TimeoutSeconds=45)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $h = Invoke-Api -State $State -Method "GET" -Path "/api/health"
        if ($h.StatusCode -eq 200) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Stop-Port5000 {
    $conns = Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue
    if (-not $conns) { return }
    $pids = $conns | Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($procId in $pids) { try { Stop-Process -Id $procId -Force -ErrorAction Stop } catch {} }
}

function Start-OpsServer {
    param($State)
    Stop-Port5000; Start-Sleep -Milliseconds 600
    $outLog = Join-Path $State.ArtifactDir ("server_out_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $errLog = Join-Path $State.ArtifactDir ("server_err_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $args = "-m flask run --host 127.0.0.1 --port 5000 --no-reload --no-debugger"
    $proc = Start-Process -FilePath $State.Python -ArgumentList $args -WorkingDirectory $State.BackendRoot -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $State.ServerProcessId = [int]$proc.Id
    Write-Log -State $State -Message ("Server started PID={0}" -f $State.ServerProcessId)
    if (-not (Wait-Health -State $State -TimeoutSeconds 45)) { throw "Server did not become healthy in time" }
}

function Stop-OpsServer {
    param($State)
    if ($State.ServerProcessId) {
        try { Stop-Process -Id ([int]$State.ServerProcessId) -Force -ErrorAction Stop; Write-Log -State $State -Message ("Server stopped PID={0}" -f $State.ServerProcessId) } catch { Write-Log -State $State -Message ("Server stop skipped PID={0}" -f $State.ServerProcessId) }
        $State.ServerProcessId = $null
    }
}

function Invoke-DbQuery {
    param($State,[string]$Sql,[object[]]$Params=@())
    $oldSql = $env:OPS_SQL; $oldParams = $env:OPS_PARAMS
    $env:OPS_SQL = $Sql
    $env:OPS_PARAMS = ($Params | ConvertTo-Json -Compress)
    try {
        $py = @"
import json, os, sqlite3
sql = os.environ.get("OPS_SQL", "")
params = json.loads(os.environ.get("OPS_PARAMS", "[]") or "[]")
if not isinstance(params, list):
    params = [params]
con = sqlite3.connect(r"instance/fliptrybe.db")
cur = con.cursor()
cur.execute(sql, tuple(params))
rows = cur.fetchall()
con.commit()
cols = [d[0] for d in (cur.description or [])]
con.close()
print(json.dumps({"columns": cols, "rows": rows}, default=str))
"@
        $raw = $py | & $State.Python -
        $lines = @()
        if ($raw -is [System.Array]) { $lines = @($raw | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() -ne "" }) }
        elseif ($null -ne $raw) { $lines = @([string]$raw) }
        $rev = @($lines); [array]::Reverse($rev)
        foreach ($line in $rev) {
            try { $parsed = $line | ConvertFrom-Json; if ($parsed -and ($parsed.PSObject.Properties.Name -contains "rows")) { return $parsed } } catch {}
        }
        return [pscustomobject]@{ columns=@(); rows=@() }
    } finally {
        $env:OPS_SQL = $oldSql; $env:OPS_PARAMS = $oldParams
    }
}

function Get-DbScalar {
    param($State,[string]$Sql,[object[]]$Params=@())
    $res = Invoke-DbQuery -State $State -Sql $Sql -Params $Params
    if (-not $res -or -not ($res.PSObject.Properties.Name -contains "rows")) { return $null }
    $rows = @($res.rows)
    if ($rows.Count -eq 0) { return $null }
    if (-not ($rows[0] -is [System.Collections.IList])) { return $null }
    if ($rows[0].Count -eq 0) { return $null }
    return $rows[0][0]
}

function New-UniqueEmail { param([string]$Prefix) return ("{0}_{1}@t.com" -f $Prefix, (Get-Random)) }

function Register-Role {
    param($State,[string]$Role,[hashtable]$Payload)
    return Invoke-Api -State $State -Method "POST" -Path ("/api/auth/register/{0}" -f $Role) -BodyObj $Payload
}

function Login-User {
    param($State,[string]$Email,[string]$Password)
    return Invoke-Api -State $State -Method "POST" -Path "/api/auth/login" -BodyObj @{ email=$Email; password=$Password }
}

function Approve-RoleRequest {
    param($State,[hashtable]$AdminHeaders,[int]$UserId,[string]$RequestedRole,[string]$AdminNote="OPS approve")
    $pending = Invoke-Api -State $State -Method "GET" -Path "/api/admin/role-requests?status=PENDING" -Headers $AdminHeaders
    if ($pending.StatusCode -ne 200 -or -not $pending.Json -or -not $pending.Json.items) { return [pscustomobject]@{ StatusCode=$pending.StatusCode; Ok=$false; Body=$pending.Body } }
    $req = $pending.Json.items | Where-Object { [int]$_.user_id -eq [int]$UserId -and ([string]$_.requested_role).ToLower() -eq $RequestedRole.ToLower() } | Select-Object -First 1
    if (-not $req) { return [pscustomobject]@{ StatusCode=404; Ok=$false; Body="pending request not found" } }
    $resp = Invoke-Api -State $State -Method "POST" -Path ("/api/admin/role-requests/{0}/approve" -f $req.id) -Headers $AdminHeaders -BodyObj @{ admin_note=$AdminNote }
    return [pscustomobject]@{ StatusCode=$resp.StatusCode; Ok=($resp.StatusCode -in @(200,201)); Body=$resp.Body }
}

function Db-Snap {
    param($State,[int]$OrderId,[string]$Label)
    Write-Log -State $State -Message ("DB SNAP {0} order={1}" -f $Label,$OrderId)
    $o = Invoke-DbQuery -State $State -Sql "SELECT id,status,escrow_status,escrow_release_at,escrow_hold_amount,pickup_confirmed_at,dropoff_confirmed_at,payment_reference FROM orders WHERE id=?" -Params @($OrderId)
    $e = Invoke-DbQuery -State $State -Sql "SELECT id,event,created_at FROM order_events WHERE order_id=? ORDER BY id ASC" -Params @($OrderId)
    $u = Invoke-DbQuery -State $State -Sql "SELECT id,step,locked,qr_verified,unlocked_at FROM escrow_unlocks WHERE order_id=? ORDER BY id ASC" -Params @($OrderId)
    $q = Invoke-DbQuery -State $State -Sql "SELECT id,channel,status,attempt_count,dead_lettered_at,reference FROM notification_queue WHERE reference LIKE ? ORDER BY id ASC" -Params @(("order:{0}%" -f $OrderId))
    $w = Invoke-DbQuery -State $State -Sql "SELECT id,kind,amount,reference FROM wallet_txns WHERE reference=? ORDER BY id ASC" -Params @(("order:{0}" -f $OrderId))
    Write-Log -State $State -Message ("orders=" + (($o.rows | ConvertTo-Json -Compress)))
    Write-Log -State $State -Message ("order_events=" + (($e.rows | ConvertTo-Json -Compress)))
    Write-Log -State $State -Message ("escrow_unlocks=" + (($u.rows | ConvertTo-Json -Compress)))
    Write-Log -State $State -Message ("notification_queue=" + (($q.rows | ConvertTo-Json -Compress)))
    Write-Log -State $State -Message ("wallet_txns=" + (($w.rows | ConvertTo-Json -Compress)))
}

function Make-DeliveryOrder {
    param($State,[int]$MerchantId,[int]$DriverId,[hashtable]$BuyerHeaders,[hashtable]$MerchantHeaders,[string]$Reference)
    if (-not $Reference) { $Reference = "ops_ref_{0}" -f (Get-Random) }
    $create = Invoke-Api -State $State -Method "POST" -Path "/api/orders" -Headers $BuyerHeaders -BodyObj @{ merchant_id=$MerchantId; amount=25000; delivery_fee=2000; inspection_fee=0; pickup="Ikeja"; dropoff="Yaba"; payment_reference=$Reference }
    if ($create.StatusCode -notin @(200,201)) { return [pscustomobject]@{ Ok=$false; Step="create"; Resp=$create } }
    $orderId = [int]$create.Json.order.id
    $tok = [string](Get-DbScalar -State $State -Sql "SELECT response_token FROM availability_confirmations WHERE order_id=? ORDER BY id DESC LIMIT 1" -Params @($orderId))
    $av = Invoke-Api -State $State -Method "POST" -Path "/api/availability/confirm" -BodyObj @{ token=$tok }
    if ($av.StatusCode -notin @(200,201)) { return [pscustomobject]@{ Ok=$false; Step="availability"; Resp=$av; OrderId=$orderId } }
    $ful = Invoke-Api -State $State -Method "POST" -Path ("/api/orders/{0}/fulfillment" -f $orderId) -Headers $BuyerHeaders -BodyObj @{ mode="delivery" }
    if ($ful.StatusCode -notin @(200,201)) { return [pscustomobject]@{ Ok=$false; Step="fulfillment"; Resp=$ful; OrderId=$orderId } }
    $acc = Invoke-Api -State $State -Method "POST" -Path ("/api/orders/{0}/merchant/accept" -f $orderId) -Headers $MerchantHeaders -BodyObj @{}
    if ($acc.StatusCode -notin @(200,201)) { return [pscustomobject]@{ Ok=$false; Step="accept"; Resp=$acc; OrderId=$orderId } }
    $asg = Invoke-Api -State $State -Method "POST" -Path ("/api/orders/{0}/driver/assign" -f $orderId) -Headers $MerchantHeaders -BodyObj @{ driver_id=$DriverId }
    if ($asg.StatusCode -notin @(200,201)) { return [pscustomobject]@{ Ok=$false; Step="assign"; Resp=$asg; OrderId=$orderId } }
    return [pscustomobject]@{ Ok=$true; OrderId=$orderId; Reference=$Reference }
}

function Complete-Order {
    param($State,[int]$OrderId,[hashtable]$BuyerHeaders,[hashtable]$MerchantHeaders,[hashtable]$DriverHeaders)
    $issueP = Invoke-Api -State $State -Method "POST" -Path ("/api/orders/{0}/qr/issue" -f $OrderId) -Headers $DriverHeaders -BodyObj @{ step="pickup_seller" }
    $scanP = Invoke-Api -State $State -Method "POST" -Path ("/api/orders/{0}/qr/scan" -f $OrderId) -Headers $MerchantHeaders -BodyObj @{ token=$issueP.Json.token }
    $pickup = Get-DbScalar -State $State -Sql "SELECT pickup_code FROM orders WHERE id=?" -Params @($OrderId)
    $pickOk = Invoke-Api -State $State -Method "POST" -Path ("/api/seller/orders/{0}/confirm-pickup" -f $OrderId) -Headers $MerchantHeaders -BodyObj @{ code=[string]$pickup }
    $driverPicked = Invoke-Api -State $State -Method "POST" -Path ("/api/orders/{0}/driver/status" -f $OrderId) -Headers $DriverHeaders -BodyObj @{ status="picked_up" }
    $issueD = Invoke-Api -State $State -Method "POST" -Path ("/api/orders/{0}/qr/issue" -f $OrderId) -Headers $BuyerHeaders -BodyObj @{ step="delivery_driver" }
    $scanD = Invoke-Api -State $State -Method "POST" -Path ("/api/orders/{0}/qr/scan" -f $OrderId) -Headers $DriverHeaders -BodyObj @{ token=$issueD.Json.token }
    $drop = Get-DbScalar -State $State -Sql "SELECT dropoff_code FROM orders WHERE id=?" -Params @($OrderId)
    $dropOk = Invoke-Api -State $State -Method "POST" -Path ("/api/driver/orders/{0}/confirm-delivery" -f $OrderId) -Headers $DriverHeaders -BodyObj @{ code=[string]$drop }
    $completed = Invoke-Api -State $State -Method "POST" -Path ("/api/orders/{0}/driver/status" -f $OrderId) -Headers $DriverHeaders -BodyObj @{ status="completed" }
    return [pscustomobject]@{ issueP=$issueP; scanP=$scanP; pickOk=$pickOk; driverPicked=$driverPicked; issueD=$issueD; scanD=$scanD; dropOk=$dropOk; completed=$completed }
}
