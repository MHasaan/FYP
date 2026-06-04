# OneShotRun.ps1
#
# Brings the entire FYP stack up from cold in one command:
#   1. docker compose up -d           → backend, db, redis, ml_manager, frontend
#   2. Waits for the backend container to report "healthy"
#   3. Starts TWO Cloudflare quick tunnels in separate PowerShell windows
#         a) http://localhost      → public web URL (share with anyone)
#         b) http://localhost:8000 → public API URL (gets baked into the APK)
#   4. Builds a release APK with the backend tunnel URL baked in
#   5. Prints a summary block with the two URLs + APK path
#
# Usage:
#   .\OneShotRun.ps1                 # everything (web tunnel + backend tunnel + APK)
#   .\OneShotRun.ps1 -SkipApk        # only Docker + tunnels, no APK (~6 min faster)
#   .\OneShotRun.ps1 -LocalOnly      # Docker only, no Cloudflare; APK targets your LAN IP
#   .\OneShotRun.ps1 -LocalOnly -SkipApk   # just Docker + a heartbeat check
#
# IMPORTANT: the two cloudflared windows that pop open MUST stay open. Closing
# either kills its URL. To stop everything cleanly: close those two windows,
# then run `docker compose down` in this folder.

param(
    [switch]$SkipApk,
    [switch]$LocalOnly
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot

function Write-Step($num, $total, $msg) {
    Write-Host ""
    Write-Host "[$num/$total] $msg" -ForegroundColor Cyan
}

function Write-OK($msg)    { Write-Host "    ✓ $msg" -ForegroundColor Green }
function Write-Note($msg)  { Write-Host "    · $msg" -ForegroundColor DarkGray }
function Write-Err($msg)   { Write-Host "    ✗ $msg" -ForegroundColor Red }

# How many steps will run, depending on flags
$totalSteps = 4
if (-not $LocalOnly) { $totalSteps += 1 }    # +1 for tunnel-start step
if (-not $SkipApk)   { $totalSteps += 1 }    # +1 for APK step
$step = 0

# ── 1. Sanity checks ──────────────────────────────────────────────────────────
$step++
Write-Step $step $totalSteps "Sanity-checking prerequisites"
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Err "docker is not on PATH. Open Docker Desktop and try again."
    exit 1
}
# Docker engine alive?
try { docker info --format '{{.ServerVersion}}' | Out-Null; Write-OK "Docker engine responding" }
catch { Write-Err "Docker engine isn't responding. Make sure Docker Desktop is fully started (whale icon stable)."; exit 1 }

if (-not $LocalOnly) {
    if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
        Write-Err "cloudflared not on PATH. Install from:"
        Write-Err "  https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
        Write-Err "Or run with -LocalOnly to skip Cloudflare."
        exit 1
    }
    Write-OK "cloudflared found"
}

if (-not $SkipApk) {
    # Wire up Flutter / Java for the APK build step (same as build_apk.ps1 does)
    $env:JAVA_HOME = "${env:ProgramFiles}\Android\Android Studio\jbr"
    $env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
    $env:Path = "$env:USERPROFILE\flutter\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\cmdline-tools\latest\bin;$env:ANDROID_HOME\platform-tools;$env:Path"
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        Write-Err "flutter not on PATH (looked under $env:USERPROFILE\flutter\bin). Either install Flutter or run with -SkipApk."
        exit 1
    }
    Write-OK "flutter found"
}

# ── 2. Bring up Docker stack ─────────────────────────────────────────────────
$step++
Write-Step $step $totalSteps "Bringing up Docker stack (docker compose up -d)"
Push-Location $projectRoot
try {
    docker compose up -d | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "docker compose up failed (exit $LASTEXITCODE)" }
    Write-OK "Containers started"
} catch {
    Pop-Location
    Write-Err $_.Exception.Message
    exit 1
}

# ── 3. Wait for backend to be healthy ────────────────────────────────────────
$step++
Write-Step $step $totalSteps "Waiting for backend to report healthy (up to 180s)"
$deadline = (Get-Date).AddSeconds(180)
while ($true) {
    $health = (docker inspect --format '{{.State.Health.Status}}' fyp-backend 2>$null)
    if ($health -eq "healthy") { Write-OK "fyp-backend = healthy"; break }
    if ((Get-Date) -gt $deadline) {
        Pop-Location
        Write-Err "backend didn't become healthy in time. Inspect with: docker logs fyp-backend"
        exit 1
    }
    Write-Note "still waiting (status: $health)..."
    Start-Sleep -Seconds 3
}

# Quick API smoke test
try {
    $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 http://localhost:8000/health
    if ($r.StatusCode -eq 200) { Write-OK "/health responded 200" }
} catch {
    Write-Note "/health probe failed but container says healthy; continuing"
}

# ── 4. Cloudflare tunnels (unless -LocalOnly) ────────────────────────────────
$webUrl     = $null
$backendUrl = $null

if ($LocalOnly) {
    # Use the laptop's LAN IPv4 as the target URLs
    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.PrefixOrigin -ne 'WellKnown' -and
            $_.AddressState -eq 'Preferred' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.InterfaceAlias -notlike '*Loopback*'
        } |
        Sort-Object InterfaceMetric | Select-Object -First 1).IPAddress

    if (-not $ip) {
        Pop-Location
        Write-Err "Could not determine your LAN IPv4. Pass one explicitly via build_apk.ps1 -Url instead."
        exit 1
    }
    $webUrl     = "http://${ip}"
    $backendUrl = "http://${ip}:8000"
    Write-OK "LAN web URL: $webUrl"
    Write-OK "LAN backend URL: $backendUrl  (phone must be on the same Wi-Fi)"
} else {
    $step++
    Write-Step $step $totalSteps "Starting Cloudflare tunnels (two new windows will pop up - keep them open)"

    # Each tunnel writes to its own log file so this script can read the URL.
    $webLog = Join-Path $env:TEMP "fyp-tunnel-web.log"
    $apiLog = Join-Path $env:TEMP "fyp-tunnel-api.log"
    Remove-Item $webLog, $apiLog -ErrorAction SilentlyContinue | Out-Null

    # Spawn each tunnel in a visible PowerShell window so the user can see/close it.
    # `-NoExit` keeps the window open if cloudflared exits. `Tee-Object` mirrors
    # stdout to the log file we'll grep below.
    $webCmd = "Write-Host '== Web tunnel (http://localhost) =='; cloudflared tunnel --url http://localhost 2>&1 | Tee-Object -FilePath '$webLog'"
    $apiCmd = "Write-Host '== Backend tunnel (http://localhost:8000) =='; cloudflared tunnel --url http://localhost:8000 2>&1 | Tee-Object -FilePath '$apiLog'"
    Start-Process powershell -ArgumentList "-NoExit","-Command",$webCmd -WindowStyle Normal | Out-Null
    Start-Process powershell -ArgumentList "-NoExit","-Command",$apiCmd -WindowStyle Normal | Out-Null

    # Read each log until a trycloudflare URL appears.
    function Wait-TunnelUrl($logFile, $label, $timeoutSec = 90) {
        $deadline = (Get-Date).AddSeconds($timeoutSec)
        while ($true) {
            if (Test-Path $logFile) {
                $content = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
                if ($content -and ($content -match 'https://[a-z0-9-]+\.trycloudflare\.com')) {
                    return $Matches[0]
                }
            }
            if ((Get-Date) -gt $deadline) {
                throw "$label tunnel didn't print a URL within ${timeoutSec}s. Look at the new PowerShell window for errors."
            }
            Start-Sleep -Seconds 2
        }
    }

    try {
        $webUrl = Wait-TunnelUrl $webLog "Web"
        Write-OK "Web tunnel : $webUrl"
        $backendUrl = Wait-TunnelUrl $apiLog "Backend"
        Write-OK "Backend tunnel : $backendUrl"
    } catch {
        Pop-Location
        Write-Err $_.Exception.Message
        exit 1
    }
}

# ── 5. Build APK with backend URL baked in (unless -SkipApk) ────────────────
$apkPath = $null
if (-not $SkipApk) {
    $step++
    Write-Step $step $totalSteps "Building Android APK targeting $backendUrl  (~3-5 min)"

    # Re-use the existing build script so URL logic stays in one place.
    & (Join-Path $projectRoot "build_apk.ps1") -Url $backendUrl
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Write-Err "APK build failed (see above)"
        exit 1
    }

    $apkPath = Join-Path $projectRoot "eldercare.apk"
    if (Test-Path $apkPath) {
        Write-OK "APK ready: $apkPath"
    } else {
        Write-Note "APK build script reported success but eldercare.apk wasn't found at $apkPath"
    }
}

# ── 6. Summary ───────────────────────────────────────────────────────────────
$step++
Write-Step $step $totalSteps "All set"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Yellow
Write-Host "  ELDERCARE STACK IS LIVE" -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  🌐  Web app for browsers : $webUrl" -ForegroundColor Green
Write-Host "  📡  Backend API URL      : $backendUrl" -ForegroundColor Green
if ($apkPath -and (Test-Path $apkPath)) {
    $size = [math]::Round((Get-Item $apkPath).Length / 1MB, 1)
    Write-Host "  📱  APK ready to install : $apkPath  (${size} MB)" -ForegroundColor Green
}
Write-Host ""
if (-not $LocalOnly) {
    Write-Host "  ⚠  Keep the two cloudflared PowerShell windows OPEN." -ForegroundColor Yellow
    Write-Host "     Closing either kills its URL." -ForegroundColor Yellow
}
Write-Host "  Stop everything cleanly:" -ForegroundColor DarkGray
Write-Host "     1. Close the cloudflared windows (Ctrl+C in each)"   -ForegroundColor DarkGray
Write-Host "     2. docker compose down"                              -ForegroundColor DarkGray
Write-Host ""

Pop-Location
