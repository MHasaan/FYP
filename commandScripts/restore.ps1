[CmdletBinding()]
param(
    [string]$BackupPath = "",
    [switch]$RestoreModels,
    [switch]$RestoreEnvFile,
    [switch]$StartStack
)

$ErrorActionPreference = "Stop"

function Require-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

function Invoke-Compose {
    param([string[]]$Args)

    & docker compose @Args
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose $($Args -join ' ') failed with exit code $LASTEXITCODE."
    }
}

Require-Command "docker"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $projectRoot

if ([string]::IsNullOrWhiteSpace($BackupPath)) {
    $defaultBackupRoot = Join-Path $projectRoot "backups"
    if (-not (Test-Path $defaultBackupRoot)) {
        throw "No backups folder found at $defaultBackupRoot"
    }

    $latest = Get-ChildItem -Path $defaultBackupRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) {
        throw "No backup folders found in $defaultBackupRoot"
    }

    $BackupPath = $latest.FullName
}

$BackupPath = (Resolve-Path $BackupPath).Path
Write-Host "Using backup: $BackupPath"

$dbDumpPath = Join-Path $BackupPath "db.sql"
if (-not (Test-Path $dbDumpPath)) {
    throw "Database dump not found: $dbDumpPath"
}

if ($RestoreEnvFile) {
    $envBackupPath = Join-Path $BackupPath ".env"
    if (Test-Path $envBackupPath) {
        Copy-Item -Path $envBackupPath -Destination (Join-Path $projectRoot ".env") -Force
        Write-Host "Restored .env file from backup."
    } else {
        Write-Host "No .env found in backup; skipping env restore."
    }
}

Write-Host "Starting database service..."
Invoke-Compose @("up", "-d", "database")

$ready = $false
for ($i = 1; $i -le 30; $i++) {
    & docker compose exec -T database sh -lc "pg_isready -U \"`$POSTGRES_USER\" -d \"`$POSTGRES_DB\"" *> $null
    if ($LASTEXITCODE -eq 0) {
        $ready = $true
        break
    }
    Write-Host "Waiting for database... ($i/30)"
    Start-Sleep -Seconds 2
}

if (-not $ready) {
    throw "Database did not become ready in time."
}

$dbContainerId = (& docker compose ps -q database).Trim()
if ([string]::IsNullOrWhiteSpace($dbContainerId)) {
    throw "Could not resolve database container id."
}

Write-Host "Copying SQL dump into database container..."
& docker cp $dbDumpPath "$dbContainerId:/tmp/fyp_restore.sql"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to copy SQL dump into database container."
}

Write-Host "Restoring database..."
Invoke-Compose @(
    "exec", "-T", "database", "sh", "-lc",
    "psql -v ON_ERROR_STOP=1 -U \"`$POSTGRES_USER\" -d \"`$POSTGRES_DB\" -f /tmp/fyp_restore.sql"
)

Invoke-Compose @("exec", "-T", "database", "sh", "-lc", "rm -f /tmp/fyp_restore.sql")

$recordingsZip = Join-Path $BackupPath "recordings.zip"
if (Test-Path $recordingsZip) {
    $recordingsTarget = Join-Path $projectRoot "videos\recordings"
    New-Item -ItemType Directory -Path $recordingsTarget -Force | Out-Null
    Expand-Archive -Path $recordingsZip -DestinationPath $recordingsTarget -Force
    Write-Host "Restored recordings to $recordingsTarget"
} else {
    Write-Host "No recordings.zip found; skipping recordings restore."
}

if ($RestoreModels) {
    $modelsZip = Join-Path $BackupPath "models.zip"
    if (Test-Path $modelsZip) {
        $modelsTarget = Join-Path $projectRoot "ml_manager\models"
        New-Item -ItemType Directory -Path $modelsTarget -Force | Out-Null
        Expand-Archive -Path $modelsZip -DestinationPath $modelsTarget -Force
        Write-Host "Restored models to $modelsTarget"
    } else {
        Write-Host "No models.zip found; skipping model restore."
    }
}

if ($StartStack) {
    Write-Host "Starting full stack with rebuild..."
    Invoke-Compose @("up", "-d", "--build")
}

Write-Host ""
Write-Host "Restore complete."
Write-Host ""
Write-Host "Tips:"
Write-Host "- Restore latest backup: .\commandScripts\restore.ps1"
Write-Host "- Restore specific backup: .\commandScripts\restore.ps1 -BackupPath .\backups\20260419_123000"
Write-Host "- Also restore models: .\commandScripts\restore.ps1 -RestoreModels"
Write-Host "- Start all services after restore: .\commandScripts\restore.ps1 -StartStack"
