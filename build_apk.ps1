# Build a release APK for the Eldercare Flutter app.
#
# Usage:
#   .\build_apk.ps1                                # uses default (localhost — phone can't reach it!)
#   .\build_apk.ps1 -Url http://192.168.1.42:8000  # phone on same Wi-Fi as laptop
#   .\build_apk.ps1 -Url https://my-tunnel.trycloudflare.com   # phone anywhere
#
# What it does:
#   1. cd's into frontend/
#   2. flutter pub get  (pulls dependencies)
#   3. flutter build apk --release  (bakes in the URL)
#   4. Copies the APK to <project root>/eldercare.apk for easy transfer

param(
    [string]$Url = "http://localhost:8000"
)

$ErrorActionPreference = "Stop"

# Derive the WebSocket URL from the API URL automatically.
$wsUrl = $Url -replace '^http://', 'ws://' -replace '^https://', 'wss://'

# Wire up Flutter + Android tooling (matches what dev.ps1 sets)
$env:JAVA_HOME = "${env:ProgramFiles}\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:Path = "$env:USERPROFILE\flutter\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\cmdline-tools\latest\bin;$env:ANDROID_HOME\platform-tools;$env:Path"

$projectRoot = $PSScriptRoot
$frontend = Join-Path $projectRoot "frontend"

Write-Host ""
Write-Host "▶ Eldercare APK build" -ForegroundColor Cyan
Write-Host "  project:    $frontend"
Write-Host "  API URL:    $Url"
Write-Host "  WS URL:     $wsUrl"
Write-Host ""

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] flutter not on PATH" -ForegroundColor Red
    exit 1
}

if ($Url -match "localhost") {
    Write-Host "WARNING: APK is targeting localhost — your PHONE cannot reach this." -ForegroundColor Yellow
    Write-Host "         Use -Url with your laptop's IP or a tunnel URL." -ForegroundColor Yellow
    Write-Host ""
}

Push-Location $frontend
try {
    Write-Host "▶ flutter pub get..." -ForegroundColor Cyan
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "pub get failed" }

    Write-Host ""
    Write-Host "▶ flutter build apk --release..." -ForegroundColor Cyan
    Write-Host "  (first build ~10 min; subsequent builds ~2 min)"
    flutter build apk --release `
        --dart-define=API_BASE_URL=$Url `
        --dart-define=WS_BASE_URL=$wsUrl
    if ($LASTEXITCODE -ne 0) { throw "build failed" }

    $apk = Join-Path $frontend "build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path $apk)) { throw "APK not found at $apk" }

    $size = [math]::Round((Get-Item $apk).Length / 1MB, 1)
    # Two copies:
    #   - eldercare.apk         → stable name for adb install scripts
    #   - eldercare-<stamp>.apk → unique name so phone browsers can't serve a
    #                             stale cached download (huge time-sink otherwise)
    $stamp = Get-Date -Format "yyyyMMdd-HHmm"
    $stableDest = Join-Path $projectRoot "eldercare.apk"
    $stampedDest = Join-Path $projectRoot "eldercare-$stamp.apk"
    Copy-Item $apk $stableDest -Force
    Copy-Item $apk $stampedDest -Force

    Write-Host ""
    Write-Host "[OK] Build complete" -ForegroundColor Green
    Write-Host "     Stable name:  $stableDest"
    Write-Host "     Unique name:  $stampedDest"
    Write-Host "     Size:         ${size} MB"
    Write-Host "     Pointing at:  $Url"
    Write-Host ""
    Write-Host "Install on phone:"
    Write-Host "  Send the UNIQUE-NAMED apk to your phone (avoids browser cache):"
    Write-Host "    $stampedDest"
    Write-Host "  OR over USB:  adb install -r `"$stableDest`""
}
finally {
    Pop-Location
}
