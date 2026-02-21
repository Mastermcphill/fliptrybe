param(
    [string]$BaseUrl = $env:FLIPTRYBE_BASE_URL,
    [string]$Email = $env:FLIPTRYBE_ADMIN_EMAIL,
    [string]$Password = $env:FLIPTRYBE_ADMIN_PASSWORD,

    [int]$ListingId = 11,
    [int]$PollSeconds = 45,        # how long to wait for index to show updated doc
    [int]$PollIntervalSeconds = 3, # polling cadence
    [switch]$WriteJsonArtifact = $true
)

$ErrorActionPreference = "Stop"

function Fail($msg) {
    Write-Host "🔴 FAIL: $msg"
    exit 1
}

function NowIso() { (Get-Date).ToUniversalTime().ToString("o") }

if (-not $BaseUrl) { $BaseUrl = "https://tri-o-fliptrybe.onrender.com" }
$BaseUrl = $BaseUrl.TrimEnd("/")

if (-not $Email -or -not $Password) {
    Fail "Missing Email/Password. Set FLIPTRYBE_ADMIN_EMAIL + FLIPTRYBE_ADMIN_PASSWORD or pass -Email/-Password."
}

$artifactDir = Join-Path $PSScriptRoot "test_artifacts"
if (-not (Test-Path $artifactDir)) { New-Item -ItemType Directory -Path $artifactDir | Out-Null }
$artifactPath = Join-Path $artifactDir ("ps_smoke_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

$report = [ordered]@{
    started_at = NowIso
    base_url = $BaseUrl
    steps = @()
    ok = $false
}

function AddStep($name, $ok, $data) {
    $report.steps += [ordered]@{
        name = $name
        ok = $ok
        at = NowIso
        data = $data
    }
}

try {
    # 1) Login
    $loginBody = @{ email=$Email; password=$Password } | ConvertTo-Json -Compress
    $login = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/auth/login" -ContentType "application/json" -Body $loginBody
    $token = $login.token
    if (-not $token) { Fail "Login response missing token." }
    AddStep "login" $true @{ user = $login.user.email; token_len = $token.Length }

    $authHeader = @{ Authorization = "Bearer $token" }

    # 2) Dependency health
    $deps = Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/admin/ops/health-deps" -Headers $authHeader
    if (-not $deps.ok) { Fail "health-deps returned ok=false" }
    AddStep "health-deps" $true $deps

    # 3) Celery status
    $cel = Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/admin/ops/celery/status" -Headers $authHeader
    if (-not $cel.ok) { Fail "celery/status returned ok=false" }
    if (-not $cel.worker_heartbeat_hint -or $cel.worker_heartbeat_hint.status -ne "available") {
        Fail "No healthy Celery workers detected."
    }
    AddStep "celery-status" $true $cel

    # 4) Meili search status (baseline)
    $status0 = Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/admin/search/status" -Headers $authHeader
    if (-not $status0.ok) { Fail "admin/search/status returned ok=false" }
    AddStep "search-status-before" $true $status0

    # 5) Update listing title
    $unique = "ZEBRA-ALPHA-999-{0}" -f (Get-Date -Format "HHmmss")
    $updateBody = @{ title = $unique } | ConvertTo-Json -Compress

    # NOTE: adjust endpoint if your API uses PATCH instead of PUT
    $updated = Invoke-RestMethod -Method Put -Uri "$BaseUrl/api/listings/$ListingId" -Headers $authHeader -ContentType "application/json" -Body $updateBody
    AddStep "listing-update" $true @{ listing_id=$ListingId; title=$unique }

    # 6) Trigger reindex (optional but helps)
    $reindex = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/admin/search/reindex" -Headers $authHeader -ContentType "application/json" -Body "{}"
    if (-not $reindex.ok) { Fail "reindex returned ok=false" }
    AddStep "search-reindex-enqueued" $true $reindex

    # 7) Poll search until found or timeout
    $found = $false
    $t0 = Get-Date
    $deadline = $t0.AddSeconds($PollSeconds)

    while ((Get-Date) -lt $deadline) {
        $res = Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/listings/search?q=$([uri]::EscapeDataString($unique))&limit=5"
        if ($res.total -ge 1) {
            $found = $true
            $latency = [int]((Get-Date) - $t0).TotalSeconds
            AddStep "search-found" $true @{ q=$unique; total=$res.total; latency_seconds=$latency }
            break
        }
        Start-Sleep -Seconds $PollIntervalSeconds
    }

    if (-not $found) {
        AddStep "search-found" $false @{ q=$unique; total=0; waited_seconds=$PollSeconds }
        Fail "Search did not return the updated listing within ${PollSeconds}s (Meili indexing lag or write hook issue)."
    }

    # 8) Final Meili status
    $status1 = Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/admin/search/status" -Headers $authHeader
    AddStep "search-status-after" $true $status1

    $report.ok = $true
    $report.finished_at = NowIso

} catch {
    $report.ok = $false
    $report.finished_at = NowIso
    $err = $_.Exception.Message
    AddStep "exception" $false @{ message = $err }
    if ($WriteJsonArtifact) {
        $report | ConvertTo-Json -Depth 30 | Out-File -FilePath $artifactPath -Encoding utf8
        Write-Host "🧾 JSON artifact written: $artifactPath"
    }
    Fail $err
}

if ($WriteJsonArtifact) {
    $report | ConvertTo-Json -Depth 30 | Out-File -FilePath $artifactPath -Encoding utf8
    Write-Host "🧾 JSON artifact written: $artifactPath"
}

Write-Host "🟢 PASS: production smoke checks OK"
exit 0
