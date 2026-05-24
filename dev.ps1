# Run the app in DEVELOPMENT mode with hot reload.
#
# Usage:
#   .\dev.ps1                       # Chrome (fastest, default; localhost:8000)
#   .\dev.ps1 phone                 # First connected Android phone (auto-detects laptop IP)
#   .\dev.ps1 phone -Url <url>      # Phone using a specific backend URL (e.g. tunnel)
#   .\dev.ps1 emulator              # First running Android emulator
#   .\dev.ps1 devices               # List all available devices
#   .\dev.ps1 <device-id>           # Specific device (run `.\dev.ps1 devices` first)
#
# While running:
#   r → hot reload (~500ms)   R → hot restart    q → quit

param(
    [Parameter(Position = 0)]
    [string]$Mode = "chrome",

    # Optional override: when omitted, dev.ps1 picks a sensible default:
    #   chrome / emulator → http://localhost:8000
    #   phone             → http://<your-laptop's-LAN-IP>:8000
    [string]$Url = ""
)

# Wire up Flutter + Android tooling
$env:JAVA_HOME = "${env:ProgramFiles}\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:Path = "$env:USERPROFILE\flutter\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\cmdline-tools\latest\bin;$env:ANDROID_HOME\platform-tools;$env:Path"

# CORS in the backend's .env allows 8080 for the web dev server.
$webPort = 8080

function Get-LocalIPv4 {
    # Pick the first non-loopback, non-VPN IPv4 address on the Wi-Fi/Ethernet adapter.
    $candidates = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.PrefixOrigin -ne 'WellKnown' -and
            $_.AddressState -eq 'Preferred' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.InterfaceAlias -notlike '*Loopback*'
        } |
        Sort-Object -Property InterfaceMetric
    foreach ($c in $candidates) { return $c.IPAddress }
    return $null
}

function Get-FirstAndroidDeviceId {
    # `flutter devices --machine` outputs JSON we can parse cleanly.
    $raw = flutter devices --machine 2>$null
    if (-not $raw) { return $null }
    try {
        $devices = $raw | ConvertFrom-Json
    } catch { return $null }
    foreach ($d in $devices) {
        if ($d.targetPlatform -like 'android*' -and $d.emulator -eq $false) {
            return @{ id = $d.id; name = $d.name }
        }
    }
    return $null
}

function Get-FirstEmulatorId {
    $raw = flutter devices --machine 2>$null
    if (-not $raw) { return $null }
    try { $devices = $raw | ConvertFrom-Json } catch { return $null }
    foreach ($d in $devices) {
        if ($d.targetPlatform -like 'android*' -and $d.emulator -eq $true) {
            return @{ id = $d.id; name = $d.name }
        }
    }
    return $null
}

Push-Location (Join-Path $PSScriptRoot "frontend")

try {
    switch ($Mode) {
        "devices" {
            flutter devices
            break
        }

        "chrome" {
            $apiUrl = if ($Url) { $Url } else { "http://localhost:8000" }
            $wsUrl  = $apiUrl -replace '^http://', 'ws://' -replace '^https://', 'wss://'
            Write-Host ""
            Write-Host "▶ Launching in Chrome (hot reload enabled)" -ForegroundColor Cyan
            Write-Host "  Backend: $apiUrl"
            Write-Host "  Dev URL: http://localhost:$webPort"
            Write-Host ""
            flutter run -d chrome `
                --web-port=$webPort `
                --dart-define=API_BASE_URL=$apiUrl `
                --dart-define=WS_BASE_URL=$wsUrl
            break
        }

        "phone" {
            $device = Get-FirstAndroidDeviceId
            if (-not $device) {
                Write-Host ""
                Write-Host "✗ No connected Android phone detected." -ForegroundColor Red
                Write-Host "  Checklist:"
                Write-Host "    1. Phone plugged into laptop with a USB-C/Lightning cable"
                Write-Host "    2. Developer Options on (tap Build number 7x in Settings -> About phone)"
                Write-Host "    3. USB debugging ON in Developer Options"
                Write-Host "    4. 'Allow USB debugging?' prompt approved on the phone"
                Write-Host ""
                Write-Host "Run this to see what Flutter sees:"
                Write-Host "    flutter devices"
                exit 1
            }

            if ($Url) {
                $apiUrl = $Url
            } else {
                $ip = Get-LocalIPv4
                if (-not $ip) {
                    Write-Host "✗ Could not detect your laptop's LAN IP." -ForegroundColor Red
                    Write-Host "  Pass it explicitly:  .\dev.ps1 phone -Url http://YOUR-IP:8000"
                    exit 1
                }
                $apiUrl = "http://${ip}:8000"
            }
            $wsUrl = $apiUrl -replace '^http://', 'ws://' -replace '^https://', 'wss://'

            Write-Host ""
            Write-Host "▶ Launching on $($device.name)" -ForegroundColor Cyan
            Write-Host "  Device:  $($device.id)"
            Write-Host "  Backend: $apiUrl"
            Write-Host ""
            Write-Host "  ⚠ The phone MUST be on the same Wi-Fi as this laptop"
            Write-Host "    (unless you're using -Url with a tunnel URL)."
            Write-Host ""
            flutter run -d $device.id `
                --dart-define=API_BASE_URL=$apiUrl `
                --dart-define=WS_BASE_URL=$wsUrl
            break
        }

        "emulator" {
            $device = Get-FirstEmulatorId
            if (-not $device) {
                Write-Host "✗ No running Android emulator." -ForegroundColor Red
                Write-Host "  Open Android Studio -> Device Manager -> tap ▶ on any AVD."
                exit 1
            }
            # Emulators can reach the host via the special 10.0.2.2 alias.
            $apiUrl = if ($Url) { $Url } else { "http://10.0.2.2:8000" }
            $wsUrl  = $apiUrl -replace '^http://', 'ws://' -replace '^https://', 'wss://'
            Write-Host ""
            Write-Host "▶ Launching on emulator: $($device.name)" -ForegroundColor Cyan
            Write-Host "  Backend: $apiUrl"
            Write-Host ""
            flutter run -d $device.id `
                --dart-define=API_BASE_URL=$apiUrl `
                --dart-define=WS_BASE_URL=$wsUrl
            break
        }

        default {
            # Pass-through: treat $Mode as a device ID (e.g. `.\dev.ps1 0B131FDD4004AE`)
            Write-Host ""
            Write-Host "▶ Launching on device id: $Mode" -ForegroundColor Cyan
            $apiUrl = if ($Url) { $Url } else { "http://localhost:8000" }
            $wsUrl  = $apiUrl -replace '^http://', 'ws://' -replace '^https://', 'wss://'
            flutter run -d $Mode `
                --dart-define=API_BASE_URL=$apiUrl `
                --dart-define=WS_BASE_URL=$wsUrl
        }
    }
}
finally {
    Pop-Location
}
