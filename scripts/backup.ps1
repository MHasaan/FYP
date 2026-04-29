[CmdletBinding()]
param(
    [string]$BackupRoot = "",
    [switch]$IncludeModels,
    [switch]$IncludeEnvFile
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

if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
    $BackupRoot = Join-Path $projectRoot "backups"
}

New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $BackupRoot $timestamp
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

Write-Host "Preparing backup in: $backupDir"

$dbContainerId = (& docker compose ps -q database).Trim()
if ([string]::IsNullOrWhiteSpace($dbContainerId)) {
    Write-Host "Database service is not running. Starting database..."
    Invoke-Compose @("up", "-d", "database")
    $dbContainerId = (& docker compose ps -q database).Trim()
    if ([string]::IsNullOrWhiteSpace($dbContainerId)) {
        throw "Could not resolve database container id."
    }
}

Write-Host "Creating database dump..."
$dbDumpPath = Join-Path $backupDir "db.sql"
& docker compose exec -T database sh -lc 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' | Set-Content -Path $dbDumpPath -Encoding utf8
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $dbDumpPath) -or ((Get-Item $dbDumpPath).Length -eq 0)) {
    throw "Failed to create database dump."
}

$recordingsDir = Join-Path $projectRoot "videos\recordings"
$recordingsZip = Join-Path $backupDir "recordings.zip"

if (Test-Path $recordingsDir) {
    $recordingFiles = Get-ChildItem -Path $recordingsDir -File -Recurse
    if ($recordingFiles.Count -gt 0) {
        Write-Host "Packing recordings..."
        Compress-Archive -Path (Join-Path $recordingsDir "*") -DestinationPath $recordingsZip -Force
    } else {
        Write-Host "No recording files found."
    }
} else {
    Write-Host "Recordings directory not found: $recordingsDir"
}

if ($IncludeModels) {
    $modelsDir = Join-Path $projectRoot "ml_manager\models"
    $modelsZip = Join-Path $backupDir "models.zip"

    if (Test-Path $modelsDir) {
        $modelFiles = Get-ChildItem -Path $modelsDir -File -Recurse
        if ($modelFiles.Count -gt 0) {
            Write-Host "Packing ML models..."
            Compress-Archive -Path (Join-Path $modelsDir "*") -DestinationPath $modelsZip -Force
        } else {
            Write-Host "No model files found."
        }
    } else {
        Write-Host "Models directory not found: $modelsDir"
    }
}

if ($IncludeEnvFile) {
    $envPath = Join-Path $projectRoot ".env"
    if (Test-Path $envPath) {
        Copy-Item -Path $envPath -Destination (Join-Path $backupDir ".env") -Force
        Write-Host "Included .env in backup."
    } else {
        Write-Host "No .env file found."
    }
}

$manifest = [ordered]@{
    created_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root   = $projectRoot
    database_dump  = (Test-Path $dbDumpPath)
    recordings_zip = (Test-Path $recordingsZip)
    models_zip     = (Test-Path (Join-Path $backupDir "models.zip"))
    env_file       = (Test-Path (Join-Path $backupDir ".env"))
}

$manifest | ConvertTo-Json | Set-Content -Path (Join-Path $backupDir "manifest.json") -Encoding UTF8

Write-Host ""
Write-Host "Backup complete."
Write-Host "Backup folder: $backupDir"
Write-Host ""
Write-Host "Tips:"
Write-Host "- Include models: .\scripts\backup.ps1 -IncludeModels"
Write-Host "- Include env file: .\scripts\backup.ps1 -IncludeEnvFile"
