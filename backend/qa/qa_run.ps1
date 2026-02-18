Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BackendRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "qa_lib.ps1")
. (Join-Path $PSScriptRoot "invariants.ps1")

$state = New-QaState -BackendRoot $BackendRoot -BaseUrl "http://127.0.0.1:5000"

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

    Start-QaServer -State $state

    $health = Invoke-Api -State $state -Method "GET" -Path "/api/health"
    Add-Result -State $state -Phase "BOOT" -Test "health" -Pass ($health.StatusCode -eq 200) -Status ($health.StatusCode.ToString()) -Detail "GET /api/health"

    $pw = "Password123!"
    $buyerEmail = New-UniqueEmail -Prefix "qa_run_buyer"
    $driverEmail = New-UniqueEmail -Prefix "qa_run_driver"
    $merchantEmail = New-UniqueEmail -Prefix "qa_run_merchant"
    $inspectorEmail = New-UniqueEmail -Prefix "qa_run_inspector"

    Write-Log -State $state -Message ("Users: buyer={0}, driver={1}, merchant={2}, inspector={3}" -f $buyerEmail,$driverEmail,$merchantEmail,$inspectorEmail)

    $buyerReg = Register-Role -State $state -Role "buyer" -Payload @{ email = $buyerEmail; password = $pw; name = "QA Buyer" }
    $driverReg = Register-Role -State $state -Role "driver" -Payload @{ email = $driverEmail; password = $pw; name = "QA Driver"; phone = "+2348011000101"; state = "Lagos"; city = "Ikeja"; vehicle_type = "bike"; plate_number = "QAR-001" }
    $merchantReg = Register-Role -State $state -Role "merchant" -Payload @{ email = $merchantEmail; password = $pw; name = "QA Merchant"; business_name = "QA Store"; phone = "+2348011000102"; state = "Lagos"; city = "Ikeja"; category = "electronics"; reason = "qa run" }
    $inspectorReg = Register-Role -State $state -Role "inspector" -Payload @{ email = $inspectorEmail; password = $pw; name = "QA Inspector"; phone = "+2348011000103"; state = "Lagos"; city = "Ikeja"; region = "Lagos"; reason = "qa run" }

    $regPass = ($buyerReg.StatusCode -eq 201) -and ($driverReg.StatusCode -eq 201) -and ($merchantReg.StatusCode -eq 201) -and ($inspectorReg.StatusCode -eq 201)
    Add-Result -State $state -Phase "BOOT" -Test "register_roles" -Pass $regPass -Status ("{0}/{1}/{2}/{3}" -f $buyerReg.StatusCode,$driverReg.StatusCode,$merchantReg.StatusCode,$inspectorReg.StatusCode) -Detail "register buyer/driver/merchant/inspector"

    $buyerLogin = Login-User -State $state -Email $buyerEmail -Password $pw
    $driverLogin = Login-User -State $state -Email $driverEmail -Password $pw
    $merchantLogin = Login-User -State $state -Email $merchantEmail -Password $pw
    $adminPassword = if ([string]::IsNullOrWhiteSpace($env:ADMIN_PASSWORD)) { "Password123!" } else { $env:ADMIN_PASSWORD }
    $adminLogin = Login-User -State $state -Email "admin@fliptrybe.com" -Password $adminPassword

    $buyerToken = [string]$buyerLogin.Json.token
    $driverToken = [string]$driverLogin.Json.token
    $merchantToken = [string]$merchantLogin.Json.token
    $adminToken = [string]$adminLogin.Json.token

    $loginPass = ($buyerLogin.StatusCode -eq 200) -and ($driverLogin.StatusCode -eq 200) -and ($merchantLogin.StatusCode -eq 200) -and ($adminLogin.StatusCode -eq 200) -and $buyerToken -and $driverToken -and $merchantToken -and $adminToken
    Add-Result -State $state -Phase "BOOT" -Test "login_roles" -Pass $loginPass -Status ("{0}/{1}/{2}/{3}" -f $buyerLogin.StatusCode,$driverLogin.StatusCode,$merchantLogin.StatusCode,$adminLogin.StatusCode) -Detail "login + token capture"

    $headersBuyer = @{ Authorization = "Bearer $buyerToken" }
    $headersDriver = @{ Authorization = "Bearer $driverToken" }
    $headersMerchant = @{ Authorization = "Bearer $merchantToken" }
    $headersAdmin = @{ Authorization = "Bearer $adminToken" }

    $merchantUserId = [int]$merchantReg.Json.user.id
    $driverUserId = [int]$driverReg.Json.user.id

    $apMerchant = Approve-RoleRequest -State $state -AdminHeaders $headersAdmin -UserId $merchantUserId -RequestedRole "merchant" -AdminNote "qa approve merchant"
    $apDriver = Approve-RoleRequest -State $state -AdminHeaders $headersAdmin -UserId $driverUserId -RequestedRole "driver" -AdminNote "qa approve driver"

    Add-Result -State $state -Phase "BOOT" -Test "admin_approvals" -Pass ($apMerchant.Ok -and $apDriver.Ok) -Status ("merchant={0},driver={1}" -f $apMerchant.StatusCode,$apDriver.StatusCode) -Detail "approve role requests"

    $driverToken = [string](Login-User -State $state -Email $driverEmail -Password $pw).Json.token
    $merchantToken = [string](Login-User -State $state -Email $merchantEmail -Password $pw).Json.token
    $headersDriver = @{ Authorization = "Bearer $driverToken" }
    $headersMerchant = @{ Authorization = "Bearer $merchantToken" }

    $ctx = [ordered]@{
        Password = $pw
        Users = [ordered]@{
            Buyer = @{ id = [int]$buyerReg.Json.user.id; email = $buyerEmail }
            Driver = @{ id = [int]$driverReg.Json.user.id; email = $driverEmail }
            Merchant = @{ id = [int]$merchantReg.Json.user.id; email = $merchantEmail }
            Inspector = @{ id = [int]$inspectorReg.Json.user.id; email = $inspectorEmail }
        }
        Headers = [ordered]@{
            Buyer = $headersBuyer
            Driver = $headersDriver
            Merchant = $headersMerchant
            Admin = $headersAdmin
        }
    }
    $state.Context = $ctx

    # D/E setup
    $de = New-DeliveryOrder -State $state -MerchantId $ctx.Users.Merchant.id -DriverId $ctx.Users.Driver.id -BuyerHeaders $ctx.Headers.Buyer -MerchantHeaders $ctx.Headers.Merchant -Reference ("qaD_{0}" -f (Get-Random))
    if (-not $de.Ok) {
        Add-Result -State $state -Phase "REGRESSION" -Test "setup_D" -Pass $false -Status $de.Step -Detail $de.Resp.Body
        throw "setup D failed"
    }

    $orderD = [int]$de.OrderId
    Write-Log -State $state -Message ("orderD={0}" -f $orderD)

    $dIssue = Invoke-Api -State $state -Method "POST" -Path ("/api/orders/{0}/qr/issue" -f $orderD) -Headers $ctx.Headers.Driver -BodyObj @{ step = "pickup_seller" }
    $dScan = Invoke-Api -State $state -Method "POST" -Path ("/api/orders/{0}/qr/scan" -f $orderD) -Headers $ctx.Headers.Merchant -BodyObj @{ token = $dIssue.Json.token }
    $dCode = Get-CodeFromApiOrDb -State $state -OrderId $orderD -BuyerHeaders $ctx.Headers.Buyer -Kind pickup
    $dConfirm = Invoke-Api -State $state -Method "POST" -Path ("/api/seller/orders/{0}/confirm-pickup" -f $orderD) -Headers $ctx.Headers.Merchant -BodyObj @{ code = $dCode }
    $dReplay = Invoke-Api -State $state -Method "POST" -Path ("/api/seller/orders/{0}/confirm-pickup" -f $orderD) -Headers $ctx.Headers.Merchant -BodyObj @{ code = $dCode }

    $dPass = ($dIssue.StatusCode -eq 200) -and ($dScan.StatusCode -eq 200) -and ($dConfirm.StatusCode -in @(200,201)) -and ($dReplay.StatusCode -in @(409,400,423))
    Add-Result -State $state -Phase "REGRESSION" -Test "D_pickup_replay" -Pass $dPass -Status ("{0}/{1}/{2}/{3}" -f $dIssue.StatusCode,$dScan.StatusCode,$dConfirm.StatusCode,$dReplay.StatusCode) -Detail ("order={0}" -f $orderD)
    Db-SnapOrder -State $state -OrderId $orderD -Label "D"

    $eReplayScan = Invoke-Api -State $state -Method "POST" -Path ("/api/orders/{0}/qr/scan" -f $orderD) -Headers $ctx.Headers.Merchant -BodyObj @{ token = $dIssue.Json.token }
    $ePass = ($eReplayScan.StatusCode -in @(400,409))
    Add-Result -State $state -Phase "REGRESSION" -Test "E_qr_replay" -Pass $ePass -Status ($eReplayScan.StatusCode.ToString()) -Detail ("order={0}" -f $orderD)
    Db-SnapOrder -State $state -OrderId $orderD -Label "E"

    # F
    $fObj = New-DeliveryOrder -State $state -MerchantId $ctx.Users.Merchant.id -DriverId $ctx.Users.Driver.id -BuyerHeaders $ctx.Headers.Buyer -MerchantHeaders $ctx.Headers.Merchant -Reference ("qaF_{0}" -f (Get-Random))
    if (-not $fObj.Ok) {
        Add-Result -State $state -Phase "REGRESSION" -Test "setup_F" -Pass $false -Status $fObj.Step -Detail $fObj.Resp.Body
        throw "setup F failed"
    }
    $orderF = [int]$fObj.OrderId

    $fIssue = Invoke-Api -State $state -Method "POST" -Path ("/api/orders/{0}/qr/issue" -f $orderF) -Headers $ctx.Headers.Driver -BodyObj @{ step = "pickup_seller" }
    $fScan = Invoke-Api -State $state -Method "POST" -Path ("/api/orders/{0}/qr/scan" -f $orderF) -Headers $ctx.Headers.Merchant -BodyObj @{ token = $fIssue.Json.token }
    $fCorrect = Get-CodeFromApiOrDb -State $state -OrderId $orderF -BuyerHeaders $ctx.Headers.Buyer -Kind pickup

    $f1 = Invoke-Api -State $state -Method "POST" -Path ("/api/seller/orders/{0}/confirm-pickup" -f $orderF) -Headers $ctx.Headers.Merchant -BodyObj @{ code = "00000" }
    $f2 = Invoke-Api -State $state -Method "POST" -Path ("/api/seller/orders/{0}/confirm-pickup" -f $orderF) -Headers $ctx.Headers.Merchant -BodyObj @{ code = "00000" }
    $f3 = Invoke-Api -State $state -Method "POST" -Path ("/api/seller/orders/{0}/confirm-pickup" -f $orderF) -Headers $ctx.Headers.Merchant -BodyObj @{ code = "00000" }
    $f4 = Invoke-Api -State $state -Method "POST" -Path ("/api/seller/orders/{0}/confirm-pickup" -f $orderF) -Headers $ctx.Headers.Merchant -BodyObj @{ code = "00000" }
    $fLockedCorrect = Invoke-Api -State $state -Method "POST" -Path ("/api/seller/orders/{0}/confirm-pickup" -f $orderF) -Headers $ctx.Headers.Merchant -BodyObj @{ code = $fCorrect }

    $fProof = Invoke-Api -State $state -Method "POST" -Path ("/api/driver/orders/{0}/unlock/confirm-code" -f $orderF) -Headers $ctx.Headers.Driver -BodyObj @{ code = $fCorrect }
    $fAdmin = Invoke-Api -State $state -Method "POST" -Path ("/api/admin/orders/{0}/unlock-pickup" -f $orderF) -Headers $ctx.Headers.Admin -BodyObj @{ token = $fProof.Json.unlock_token }
    $fPost = Invoke-Api -State $state -Method "POST" -Path ("/api/seller/orders/{0}/confirm-pickup" -f $orderF) -Headers $ctx.Headers.Merchant -BodyObj @{ code = $fCorrect }

    $fPass = ($fIssue.StatusCode -eq 200) -and ($fScan.StatusCode -eq 200) -and ($f1.StatusCode -eq 400) -and ($f2.StatusCode -eq 400) -and ($f3.StatusCode -eq 400) -and ($f4.StatusCode -eq 423) -and ($fLockedCorrect.StatusCode -eq 423) -and ($fProof.StatusCode -eq 200) -and ($fAdmin.StatusCode -eq 200) -and ($fPost.StatusCode -in @(200,201))
    Add-Result -State $state -Phase "REGRESSION" -Test "F_lockout_unlock" -Pass $fPass -Status ("attempts={0},{1},{2},{3}; proof={4}; admin={5}; post={6}" -f $f1.StatusCode,$f2.StatusCode,$f3.StatusCode,$f4.StatusCode,$fProof.StatusCode,$fAdmin.StatusCode,$fPost.StatusCode) -Detail ("order={0}" -f $orderF)
    Db-SnapOrder -State $state -OrderId $orderF -Label "F"

    # G
    $gObj = New-DeliveryOrder -State $state -MerchantId $ctx.Users.Merchant.id -DriverId $ctx.Users.Driver.id -BuyerHeaders $ctx.Headers.Buyer -MerchantHeaders $ctx.Headers.Merchant -Reference ("qaG_{0}" -f (Get-Random))
    if (-not $gObj.Ok) {
        Add-Result -State $state -Phase "REGRESSION" -Test "setup_G" -Pass $false -Status $gObj.Step -Detail $gObj.Resp.Body
        throw "setup G failed"
    }
    $orderG = [int]$gObj.OrderId

    $g1 = Invoke-Api -State $state -Method "POST" -Path ("/api/seller/orders/{0}/confirm-pickup" -f $orderG) -Headers $ctx.Headers.Buyer -BodyObj @{ code = "1111" }
    $g2 = Invoke-Api -State $state -Method "POST" -Path ("/api/seller/orders/{0}/confirm-pickup" -f $orderG) -Headers $ctx.Headers.Driver -BodyObj @{ code = "1111" }
    $g3 = Invoke-Api -State $state -Method "POST" -Path ("/api/driver/orders/{0}/confirm-delivery" -f $orderG) -Headers $ctx.Headers.Merchant -BodyObj @{ code = "1111" }
    $g4 = Invoke-Api -State $state -Method "POST" -Path ("/api/driver/orders/{0}/unlock/confirm-code" -f $orderG) -Headers $ctx.Headers.Buyer -BodyObj @{ code = "1111" }

    $gPass = ($g1.StatusCode -in @(400,401,403,404,409,423)) -and ($g2.StatusCode -in @(400,401,403,404,409,423)) -and ($g3.StatusCode -in @(400,401,403,404,409,423)) -and ($g4.StatusCode -in @(400,401,403,404,409,423))
    Add-Result -State $state -Phase "REGRESSION" -Test "G_cross_role_tamper" -Pass $gPass -Status ("{0}/{1}/{2}/{3}" -f $g1.StatusCode,$g2.StatusCode,$g3.StatusCode,$g4.StatusCode) -Detail ("order={0}" -f $orderG)
    Db-SnapOrder -State $state -OrderId $orderG -Label "G"

    # Happy path
    $hObj = New-DeliveryOrder -State $state -MerchantId $ctx.Users.Merchant.id -DriverId $ctx.Users.Driver.id -BuyerHeaders $ctx.Headers.Buyer -MerchantHeaders $ctx.Headers.Merchant -Reference ("qaH_{0}" -f (Get-Random))
    if (-not $hObj.Ok) {
        Add-Result -State $state -Phase "REGRESSION" -Test "setup_H" -Pass $false -Status $hObj.Step -Detail $hObj.Resp.Body
        throw "setup H failed"
    }
    $orderH = [int]$hObj.OrderId

    $hIssueP = Invoke-Api -State $state -Method "POST" -Path ("/api/orders/{0}/qr/issue" -f $orderH) -Headers $ctx.Headers.Driver -BodyObj @{ step = "pickup_seller" }
    $hScanP = Invoke-Api -State $state -Method "POST" -Path ("/api/orders/{0}/qr/scan" -f $orderH) -Headers $ctx.Headers.Merchant -BodyObj @{ token = $hIssueP.Json.token }
    $hPickCode = Get-CodeFromApiOrDb -State $state -OrderId $orderH -BuyerHeaders $ctx.Headers.Buyer -Kind pickup
    $hPickOk = Invoke-Api -State $state -Method "POST" -Path ("/api/seller/orders/{0}/confirm-pickup" -f $orderH) -Headers $ctx.Headers.Merchant -BodyObj @{ code = $hPickCode }
    $hDriverPicked = Invoke-Api -State $state -Method "POST" -Path ("/api/orders/{0}/driver/status" -f $orderH) -Headers $ctx.Headers.Driver -BodyObj @{ status = "picked_up" }

    $hIssueD = Invoke-Api -State $state -Method "POST" -Path ("/api/orders/{0}/qr/issue" -f $orderH) -Headers $ctx.Headers.Buyer -BodyObj @{ step = "delivery_driver" }
    $hScanD = Invoke-Api -State $state -Method "POST" -Path ("/api/orders/{0}/qr/scan" -f $orderH) -Headers $ctx.Headers.Driver -BodyObj @{ token = $hIssueD.Json.token }
    $hDropCode = Get-CodeFromApiOrDb -State $state -OrderId $orderH -BuyerHeaders $ctx.Headers.Buyer -Kind dropoff
    $hDropOk = Invoke-Api -State $state -Method "POST" -Path ("/api/driver/orders/{0}/confirm-delivery" -f $orderH) -Headers $ctx.Headers.Driver -BodyObj @{ code = $hDropCode }
    $hCompleted = Invoke-Api -State $state -Method "POST" -Path ("/api/orders/{0}/driver/status" -f $orderH) -Headers $ctx.Headers.Driver -BodyObj @{ status = "completed" }
    $hTimeline = Invoke-Api -State $state -Method "GET" -Path ("/api/orders/{0}/timeline" -f $orderH) -Headers $ctx.Headers.Buyer

    $timelineEvents = @()
    if ($hTimeline.Json -and $hTimeline.Json.items) {
        $timelineEvents = @($hTimeline.Json.items | ForEach-Object { [string]$_.event })
    }
    $hasDelivered = $timelineEvents -contains "delivered"
    $hasCompleted = $timelineEvents -contains "completed"

    $hPass = ($hIssueP.StatusCode -eq 200) -and ($hScanP.StatusCode -eq 200) -and ($hPickOk.StatusCode -in @(200,201)) -and ($hDriverPicked.StatusCode -in @(200,201)) -and ($hIssueD.StatusCode -eq 200) -and ($hScanD.StatusCode -eq 200) -and ($hDropOk.StatusCode -in @(200,201)) -and ($hCompleted.StatusCode -in @(200,201)) -and ($hTimeline.StatusCode -eq 200) -and $hasDelivered -and $hasCompleted
    Add-Result -State $state -Phase "REGRESSION" -Test "happy_path_delivery" -Pass $hPass -Status ("{0}/{1}/{2}/{3}/{4}/{5}/{6}/{7}" -f $hIssueP.StatusCode,$hScanP.StatusCode,$hPickOk.StatusCode,$hDriverPicked.StatusCode,$hIssueD.StatusCode,$hScanD.StatusCode,$hDropOk.StatusCode,$hCompleted.StatusCode) -Detail ("order={0}, events={1}" -f $orderH,($timelineEvents -join ','))

    Write-Log -State $state -Message ("timeline_order_{0}={1}" -f $orderH, ($hTimeline.Body -replace "`r?`n", ""))
    Db-SnapOrder -State $state -OrderId $orderH -Label "HAPPY"

    # Ledger + reconcile
    $ledgerBuyer = Invoke-Api -State $state -Method "GET" -Path "/api/wallet/ledger" -Headers $ctx.Headers.Buyer
    $ledgerDriver = Invoke-Api -State $state -Method "GET" -Path "/api/wallet/ledger" -Headers $ctx.Headers.Driver
    $ledgerMerchant = Invoke-Api -State $state -Method "GET" -Path "/api/wallet/ledger" -Headers $ctx.Headers.Merchant
    $ledgerAdmin = Invoke-Api -State $state -Method "GET" -Path "/api/wallet/ledger" -Headers $ctx.Headers.Admin
    $recon = Invoke-Api -State $state -Method "POST" -Path "/api/admin/reconcile" -Headers $ctx.Headers.Admin -BodyObj @{ limit = 300 }

    $ref = "order:{0}" -f $orderH
    $ledgerRows = Invoke-DbQuery -State $state -Sql "SELECT user_id, direction, kind, amount FROM wallet_txns WHERE reference=? ORDER BY id ASC" -Params @($ref)
    $kinds = @()
    $ledgerRowsArray = @()
    if ($ledgerRows -and ($ledgerRows.PSObject.Properties.Name -contains "rows")) {
        $ledgerRowsArray = @($ledgerRows.rows)
    }
    foreach ($row in $ledgerRowsArray) {
        if ($row -is [System.Collections.IList] -and $row.Count -ge 3) {
            $kinds += [string]$row[2]
        }
    }
    $hasOrderSale = $kinds -contains "order_sale"
    $hasDeliveryFee = $kinds -contains "delivery_fee"
    $hasPlatform = ($kinds -contains "platform_fee") -or ($kinds -contains "user_listing_commission")

    $ledgerPass = ($ledgerBuyer.StatusCode -eq 200) -and ($ledgerDriver.StatusCode -eq 200) -and ($ledgerMerchant.StatusCode -eq 200) -and ($ledgerAdmin.StatusCode -eq 200) -and ($recon.StatusCode -eq 200) -and ($recon.Json.ok -eq $true) -and $hasOrderSale -and $hasDeliveryFee -and $hasPlatform
    Add-Result -State $state -Phase "REGRESSION" -Test "ledger_reconcile" -Pass $ledgerPass -Status ("ledger={0}/{1}/{2}/{3}, recon={4}" -f $ledgerBuyer.StatusCode,$ledgerDriver.StatusCode,$ledgerMerchant.StatusCode,$ledgerAdmin.StatusCode,$recon.StatusCode) -Detail ("order_ref={0}, kinds={1}" -f $ref,($kinds -join ','))

    Write-Log -State $state -Message ("reconcile={0}" -f ($recon.Body -replace "`r?`n", ""))

    # Invariants phase
    Invoke-Invariants -State $state -Context $ctx

    Print-ResultTable -State $state
    $fails = Get-FailCount -State $state
    Write-Log -State $state -Message ("TOTAL_FAILS={0}" -f $fails)

    if ($fails -gt 0) {
        exit 1
    }
    exit 0
}
catch {
    Write-Log -State $state -Message ("Runner exception: " + $_.Exception.Message)
    Add-Result -State $state -Phase "RUNNER" -Test "unhandled_exception" -Pass $false -Status "EXCEPTION" -Detail $_.Exception.Message
    Print-ResultTable -State $state
    exit 2
}
finally {
    try { Stop-QaServer -State $state } catch {}
    Pop-Location
}
