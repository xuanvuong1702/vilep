# Serve the Flutter web build locally and (optionally) capture screenshots.
#
#   pwsh ./scripts/serve-web.ps1                 # build (release, demo login) + serve on :8080
#   pwsh ./scripts/serve-web.ps1 -NoBuild        # serve existing build
#   pwsh ./scripts/serve-web.ps1 -Screenshots    # also capture into ./shots
param(
    [int]$Port = 8080,
    [switch]$NoBuild,
    [switch]$Screenshots,
    [string]$ApiBase = "http://127.0.0.1:5080"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$mobile = Join-Path $root "apps/mobile"
$web = Join-Path $mobile "build/web"

if (-not $NoBuild) {
    Push-Location $mobile
    flutter build web --release --dart-define=API_BASE=$ApiBase --dart-define=DEMO_PHONE=0900000001 --dart-define=SKIP_ONBOARDING=true
    Pop-Location
}

if (-not (Test-Path $web)) { throw "Chưa có build web tại $web. Chạy không kèm -NoBuild." }

Write-Host "Serving $web on http://127.0.0.1:$Port" -ForegroundColor Green
Start-Process -FilePath python -ArgumentList "-m", "http.server", "$Port", "--directory", $web -WindowStyle Hidden

if ($Screenshots) {
    Start-Sleep -Seconds 2
    $edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    $profile = Join-Path $root ".edge-profile"
    if (Test-Path $profile) { Remove-Item $profile -Recurse -Force -ErrorAction SilentlyContinue }
    Start-Process -FilePath $edge -ArgumentList @(
        "--headless=new", "--disable-gpu", "--hide-scrollbars",
        "--remote-debugging-port=9222", "--user-data-dir=$profile",
        "--window-size=500,1000", "--no-first-run", "about:blank"
    ) -WindowStyle Hidden
    Start-Sleep -Seconds 4
    Push-Location $root
    node scripts/screenshots.mjs (Join-Path $root "shots") "http://127.0.0.1:$Port" $ApiBase
    Pop-Location
}
