param(
  [string]$BaseUrl = $env:FLIPTRYBE_BASE_URL,
  [string]$Email   = $env:FLIPTRYBE_ADMIN_EMAIL,
  [string]$Password= $env:FLIPTRYBE_ADMIN_PASSWORD
)

if (-not $BaseUrl)   { $BaseUrl = "https://tri-o-fliptrybe.onrender.com" }

if (-not $Email -or -not $Password) {
  Write-Host "❌ Missing env vars:"
  Write-Host "   FLIPTRYBE_ADMIN_EMAIL"
  Write-Host "   FLIPTRYBE_ADMIN_PASSWORD"
  Write-Host "Optional:"
  Write-Host "   FLIPTRYBE_BASE_URL"
  exit 1
}

@{
  BaseUrl  = $BaseUrl.TrimEnd("/")
  Email    = $Email
  Password = $Password
}
