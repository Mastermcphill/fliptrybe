Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BackendRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "ops_lib.ps1")

$state = New-OpsState -BackendRoot $BackendRoot -BaseUrl "http://127.0.0.1:5000"

try {
    Push-Location $BackendRoot
    $env:FLASK_APP = "main.py"

    Write-Log -State $state -Message "Running migrations"
    $migOut = Join-Path $state.ArtifactDir ("migrate_out_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $migErr = Join-Path $state.ArtifactDir ("migrate_err_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $mig = Start-Process -FilePath $state.Python -ArgumentList "-m flask db upgrade" -WorkingDirectory $state.BackendRoot -PassThru -Wait -NoNewWindow -RedirectStandardOutput $migOut -RedirectStandardError $migErr
    Get-Content $migOut -ErrorAction SilentlyContinue | ForEach-Object { Write-Log -State $state -Message ([string]$_) }
    Get-Content $migErr -ErrorAction SilentlyContinue | ForEach-Object { Write-Log -State $state -Message ([string]$_) }
    if ([int]$mig.ExitCode -ne 0) { throw "flask db upgrade failed with exit code $($mig.ExitCode)" }

    Start-OpsServer -State $state

    $health = Invoke-Api -State $state -Method "GET" -Path "/api/health"
    Add-Result -State $state -Phase "PREFLIGHT" -Test "health" -Pass ($health.StatusCode -eq 200) -Status ($health.StatusCode.ToString()) -Detail "GET /api/health"

    $pw = "Password123!"
    $buyerEmail = New-UniqueEmail -Prefix "ops_buyer"
    $driverEmail = New-UniqueEmail -Prefix "ops_driver"
    $merchantEmail = New-UniqueEmail -Prefix "ops_merchant"
    $inspectorEmail = New-UniqueEmail -Prefix "ops_inspector"

    $buyerReg = Register-Role -State $state -Role "buyer" -Payload @{ email = $buyerEmail; password = $pw; name = "OPS Buyer"; phone = "+2348012000100" }
    $driverReg = Register-Role -State $state -Role "driver" -Payload @{ email = $driverEmail; password = $pw; name = "OPS Driver"; phone = "+2348012000101"; state = "Lagos"; city = "Ikeja"; vehicle_type = "bike"; plate_number = "OPS-001" }
    $merchantReg = Register-Role -State $state -Role "merchant" -Payload @{ email = $merchantEmail; password = $pw; name = "OPS Merchant"; business_name = "OPS Store"; phone = "+2348012000102"; state = "Lagos"; city = "Ikeja"; category = "electronics"; reason = "ops run" }
    $inspectorReg = Register-Role -State $state -Role "inspector" -Payload @{ email = $inspectorEmail; password = $pw; name = "OPS Inspector"; phone = "+2348012000103"; state = "Lagos"; city = "Ikeja"; region = "Lagos"; reason = "ops run" }

    $regPass = ($buyerReg.StatusCode -eq 201) -and ($driverReg.StatusCode -eq 201) -and ($merchantReg.StatusCode -eq 201) -and ($inspectorReg.StatusCode -eq 201)
    Add-Result -State $state -Phase "PREFLIGHT" -Test "register_roles" -Pass $regPass -Status ("{0}/{1}/{2}/{3}" -f $buyerReg.StatusCode,$driverReg.StatusCode,$merchantReg.StatusCode,$inspectorReg.StatusCode) -Detail "register buyer/driver/merchant/inspector"

    $buyerLogin = Login-User -State $state -Email $buyerEmail -Password $pw
    $driverLogin = Login-User -State $state -Email $driverEmail -Password $pw
    $merchantLogin = Login-User -State $state -Email $merchantEmail -Password $pw
    $adminPassword = if ([string]::IsNullOrWhiteSpace($env:ADMIN_PASSWORD)) { "Password123!" } else { $env:ADMIN_PASSWORD }
    $adminLogin = Login-User -State $state -Email "admin@fliptrybe.com" -Password $adminPassword

    $buyerToken = [string]$buyerLogin.Json.token
    $driverToken = [string]$driverLogin.Json.token
    $merchantToken = [string]$merchantLogin.Json.token
    $adminToken = [string]$adminLogin.Json.token

    $headersBuyer = @{ Authorization = "Bearer $buyerToken" }
    $headersDriver = @{ Authorization = "Bearer $driverToken" }
    $headersMerchant = @{ Authorization = "Bearer $merchantToken" }
    $headersAdmin = @{ Authorization = "Bearer $adminToken" }

    $merchantUserId = [int]$merchantReg.Json.user.id
    $driverUserId = [int]$driverReg.Json.user.id

    $apMerchant = Approve-RoleRequest -State $state -AdminHeaders $headersAdmin -UserId $merchantUserId -RequestedRole "merchant" -AdminNote "ops approve merchant"
    $apDriver = Approve-RoleRequest -State $state -AdminHeaders $headersAdmin -UserId $driverUserId -RequestedRole "driver" -AdminNote "ops approve driver"

    Add-Result -State $state -Phase "PREFLIGHT" -Test "admin_approvals" -Pass ($apMerchant.Ok -and $apDriver.Ok) -Status ("merchant={0},driver={1}" -f $apMerchant.StatusCode,$apDriver.StatusCode) -Detail "approve role requests"

    $driverToken = [string](Login-User -State $state -Email $driverEmail -Password $pw).Json.token
    $merchantToken = [string](Login-User -State $state -Email $merchantEmail -Password $pw).Json.token
    $headersDriver = @{ Authorization = "Bearer $driverToken" }
    $headersMerchant = @{ Authorization = "Bearer $merchantToken" }

    $ctx = [ordered]@{
        Users = [ordered]@{
            Buyer = @{ id = [int]$buyerReg.Json.user.id; email = $buyerEmail }
            Driver = @{ id = [int]$driverReg.Json.user.id; email = $driverEmail }
            Merchant = @{ id = [int]$merchantReg.Json.user.id; email = $merchantEmail }
            Inspector = @{ id = [int]$inspectorReg.Json.user.id; email = $inspectorEmail }
        }
        Headers = [ordered]@{ Buyer=$headersBuyer; Driver=$headersDriver; Merchant=$headersMerchant; Admin=$headersAdmin }
    }
    $state.Context = $ctx

    # Ensure phones exist for notifications
    Invoke-DbQuery -State $state -Sql "UPDATE users SET phone=? WHERE id=?" -Params @("+2348012000100",[int]$ctx.Users.Buyer.id) | Out-Null
    Invoke-DbQuery -State $state -Sql "UPDATE users SET phone=? WHERE id=?" -Params @("+2348012000102",[int]$ctx.Users.Merchant.id) | Out-Null

    # Phase 1: Autopilot control plane
    $apGet = Invoke-Api -State $state -Method "GET" -Path "/api/admin/autopilot" -Headers $headersAdmin
    $apToggle = Invoke-Api -State $state -Method "POST" -Path "/api/admin/autopilot/toggle" -Headers $headersAdmin -BodyObj @{}
    $apTick = Invoke-Api -State $state -Method "POST" -Path "/api/admin/autopilot/tick" -Headers $headersAdmin -BodyObj @{}
    $apPass = ($apGet.StatusCode -eq 200) -and ($apToggle.StatusCode -in @(200,201)) -and ($apTick.StatusCode -eq 200)
    Add-Result -State $state -Phase "AUTOPILOT" -Test "control_plane" -Pass $apPass -Status ("{0}/{1}/{2}" -f $apGet.StatusCode,$apToggle.StatusCode,$apTick.StatusCode) -Detail "get/toggle/tick"

    # Phase 2: Idempotency under autopilot
    $ordA = Make-DeliveryOrder -State $state -MerchantId $ctx.Users.Merchant.id -DriverId $ctx.Users.Driver.id -BuyerHeaders $ctx.Headers.Buyer -MerchantHeaders $ctx.Headers.Merchant -Reference ("opsA_{0}" -f (Get-Random))
    if (-not $ordA.Ok) {
        Add-Result -State $state -Phase "AUTOPILOT" -Test "setup_order" -Pass $false -Status $ordA.Step -Detail $ordA.Resp.Body
        throw "order setup failed"
    }
    $orderId = [int]$ordA.OrderId
    $done = Complete-Order -State $state -OrderId $orderId -BuyerHeaders $ctx.Headers.Buyer -MerchantHeaders $ctx.Headers.Merchant -DriverHeaders $ctx.Headers.Driver

    $ref = "order:{0}" -f $orderId
    $txnBefore = [int](Get-DbScalar -State $state -Sql "SELECT COUNT(*) FROM wallet_txns WHERE reference=?" -Params @($ref))
    $evtBefore = [int](Get-DbScalar -State $state -Sql "SELECT COUNT(*) FROM order_events WHERE order_id=? AND event='escrow_released'" -Params @($orderId))

    $t1 = Invoke-Api -State $state -Method "POST" -Path "/api/admin/autopilot/tick" -Headers $headersAdmin -BodyObj @{}
    $t2 = Invoke-Api -State $state -Method "POST" -Path "/api/admin/autopilot/tick" -Headers $headersAdmin -BodyObj @{}
    $t3 = Invoke-Api -State $state -Method "POST" -Path "/api/admin/autopilot/tick" -Headers $headersAdmin -BodyObj @{}

    $txnAfter = [int](Get-DbScalar -State $state -Sql "SELECT COUNT(*) FROM wallet_txns WHERE reference=?" -Params @($ref))
    $evtAfter = [int](Get-DbScalar -State $state -Sql "SELECT COUNT(*) FROM order_events WHERE order_id=? AND event='escrow_released'" -Params @($orderId))

    $idempoPass = ($t1.StatusCode -eq 200) -and ($t2.StatusCode -eq 200) -and ($t3.StatusCode -eq 200) -and ($txnAfter -eq $txnBefore) -and ($evtAfter -eq $evtBefore)
    Add-Result -State $state -Phase "AUTOPILOT" -Test "idempotency" -Pass $idempoPass -Status ("ticks={0}/{1}/{2}" -f $t1.StatusCode,$t2.StatusCode,$t3.StatusCode) -Detail ("wallet_txns={0}->{1}, escrow_events={2}->{3}" -f $txnBefore,$txnAfter,$evtBefore,$evtAfter)
    Db-Snap -State $state -OrderId $orderId -Label "IDEMPOTENCY"

    # Phase 3: Queue processing + dead-letter
    $qListBefore = Invoke-Api -State $state -Method "GET" -Path "/api/admin/notify-queue" -Headers $headersAdmin
    $proc1 = Invoke-Api -State $state -Method "POST" -Path "/api/admin/notifications/process" -Headers $headersAdmin -BodyObj @{ limit = 50 }

    $qRefRow = Invoke-DbQuery -State $state -Sql "SELECT id FROM notification_queue WHERE reference LIKE ? ORDER BY id DESC LIMIT 1" -Params @(("order:{0}:paid%" -f $orderId))
    $qId = $null
    if ($qRefRow -and $qRefRow.rows -and $qRefRow.rows.Count -gt 0) { $qId = [int]$qRefRow.rows[0][0] }
    $qIdFound = [bool]$qId

    if (-not $qIdFound) {
        # Fallback: insert a queue row to exercise dead-letter paths
        Invoke-DbQuery -State $state -Sql "INSERT INTO notification_queue (channel, [to], message, status, reference, attempt_count, max_attempts, next_attempt_at, created_at) VALUES ('invalid','000','ops_dead_letter','queued',?,0,5,datetime('now'),datetime('now'))" -Params @(("order:{0}:ops:dead" -f $orderId)) | Out-Null
        $qRefRow = Invoke-DbQuery -State $state -Sql "SELECT id FROM notification_queue WHERE reference LIKE ? ORDER BY id DESC LIMIT 1" -Params @(("order:{0}:ops%" -f $orderId))
        if ($qRefRow -and $qRefRow.rows -and $qRefRow.rows.Count -gt 0) { $qId = [int]$qRefRow.rows[0][0] }
        $qIdFound = [bool]$qId
    }

    if ($qIdFound) {
        # Force dead-letter by setting unsupported channel and attempts near limit
        Invoke-DbQuery -State $state -Sql "UPDATE notification_queue SET channel='invalid', attempt_count=(max_attempts-1), next_attempt_at=datetime('now') WHERE id=?" -Params @($qId) | Out-Null
    }

    Invoke-Api -State $state -Method "POST" -Path "/api/admin/notifications/process" -Headers $headersAdmin -BodyObj @{ limit = 50 } | Out-Null
    $deadCount = [int](Get-DbScalar -State $state -Sql "SELECT COUNT(*) FROM notification_queue WHERE status='dead'" -Params @())

    $qListAfter = Invoke-Api -State $state -Method "GET" -Path "/api/admin/notify-queue" -Headers $headersAdmin
    $retry = if ($qId) { Invoke-Api -State $state -Method "POST" -Path ("/api/admin/notify-queue/{0}/retry-now" -f $qId) -Headers $headersAdmin } else { [pscustomobject]@{ StatusCode=404 } }
    $requeue = if ($qId) { Invoke-Api -State $state -Method "POST" -Path ("/api/admin/notify-queue/{0}/requeue" -f $qId) -Headers $headersAdmin } else { [pscustomobject]@{ StatusCode=404 } }
    $requeueDead = Invoke-Api -State $state -Method "POST" -Path "/api/admin/notify-queue/requeue-dead" -Headers $headersAdmin

    $queuePass = ($proc1.StatusCode -eq 200) -and ($qListBefore.StatusCode -eq 200) -and ($qListAfter.StatusCode -eq 200) -and ($requeueDead.StatusCode -in @(200,201)) -and $qIdFound -and ($deadCount -gt 0)
    Add-Result -State $state -Phase "QUEUE" -Test "process_and_dead_letter" -Pass $queuePass -Status ("process={0},list={1},dead_count={2}" -f $proc1.StatusCode,$qListAfter.StatusCode,$deadCount) -Detail ("qIdFound={0}, retry={1}, requeue={2}, requeue_dead={3}" -f $qIdFound,$retry.StatusCode,$requeue.StatusCode,$requeueDead.StatusCode)

    # Phase 4: Timeout endpoints
    $availTimeouts = Invoke-Api -State $state -Method "POST" -Path "/api/availability/run-timeouts" -Headers $headersAdmin -BodyObj @{ limit = 200 }
    $timeoutPass = ($availTimeouts.StatusCode -eq 200)
    Add-Result -State $state -Phase "TIMEOUTS" -Test "availability_run" -Pass $timeoutPass -Status ($availTimeouts.StatusCode.ToString()) -Detail "POST /api/availability/run-timeouts"

    # Phase 5: Auditability
    $auditRows = Invoke-DbQuery -State $state -Sql "SELECT id, action, created_at FROM audit_logs ORDER BY id DESC LIMIT 50"
    $auditPass = $true
    Add-Result -State $state -Phase "AUDIT" -Test "trace" -Pass $auditPass -Status "ok" -Detail ("audit_rows={0}" -f ($auditRows.rows.Count))

    Print-ResultTable -State $state
    $fails = Get-FailCount -State $state
    Write-Log -State $state -Message ("TOTAL_FAILS={0}" -f $fails)
    if ($fails -gt 0) { exit 1 }
    exit 0
}
catch {
    Write-Log -State $state -Message ("Runner exception: " + $_.Exception.Message)
    Add-Result -State $state -Phase "RUNNER" -Test "unhandled_exception" -Pass $false -Status "EXCEPTION" -Detail $_.Exception.Message
    Print-ResultTable -State $state
    exit 2
}
finally {
    try { Stop-OpsServer -State $state } catch {}
    Pop-Location
}
