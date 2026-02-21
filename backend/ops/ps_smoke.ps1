param(
    [string]$BaseUrl = "https://tri-o-fliptrybe.onrender.com",
    [string]$Email,
    [string]$Password,
    [int]$ListingId = 11,
    [int]$SleepSeconds = 5
)

if (-not $Email -or -not $Password) {
    Write-Host "❌ Email and Password required"
    exit 1
}

Write-Host "🔐 Logging in..."
$loginBody = @{
    email = $Email
    password = $Password
} | ConvertTo-Json -Compress

$login = Invoke-RestMethod `
    -Method Post `
    -Uri "$BaseUrl/api/auth/login" `
    -ContentType "application/json" `
    -Body $loginBody

$token = $login.token

if (-not $token) {
    Write-Host "❌ Login failed"
    exit 1
}

Write-Host "✅ Login successful"

$unique = "ZEBRA-$(Get-Random)-$(Get-Date -Format 'HHmmss')"
Write-Host "✏️ Updating listing $ListingId title to $unique"

$updateBody = @{
    title = $unique
} | ConvertTo-Json -Compress

Invoke-RestMethod `
    -Method Put `
    -Uri "$BaseUrl/api/listings/$ListingId" `
    -Headers @{ Authorization = "Bearer $token" } `
    -ContentType "application/json" `
    -Body $updateBody | Out-Null

Write-Host "⏳ Waiting $SleepSeconds seconds for Celery..."
Start-Sleep -Seconds $SleepSeconds

Write-Host "🔎 Searching for $unique"
$search = Invoke-RestMethod `
    -Method Get `
    -Uri "$BaseUrl/api/listings/search?q=$unique&limit=5"

if ($search.total -ge 1) {
    Write-Host "🟢 SEARCH PASS — Found $($search.total) result(s)"
} else {
    Write-Host "🔴 SEARCH FAIL — No results found"
}

Write-Host "📊 Checking Meili status"
$status = Invoke-RestMethod `
    -Method Get `
    -Uri "$BaseUrl/api/admin/search/status" `
    -Headers @{ Authorization = "Bearer $token" }

Write-Host "Document Count:" $status.document_count
Write-Host "Last Update:" $status.lastUpdate
Write-Host "Meili Version:" $status.meili_version

Write-Host "🏁 Smoke test complete."
