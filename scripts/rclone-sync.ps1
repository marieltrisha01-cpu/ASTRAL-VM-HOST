# /rdpdev Real-time Persistence Script
$ErrorActionPreference = "SilentlyContinue"

Write-Host "--- Starting Remote Cloud Mirror Sync ---" -ForegroundColor Cyan

$StateDir = "C:\State"
$ConfigPath = "$HOME\.config\rclone\rclone.conf"

# 1. Decode Rclone Config from Secret
if ($env:RCLONE_CONFIG_DATA) {
    if (!(Test-Path (Split-Path $ConfigPath))) { New-Item -Path (Split-Path $ConfigPath) -ItemType Directory -Force }
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($env:RCLONE_CONFIG_DATA)) | Out-File -FilePath $ConfigPath -Encoding utf8
}

if (!(Test-Path $ConfigPath)) {
    Write-Host "Error: No Rclone config found. Define RCLONE_CONFIG_DATA secret." -ForegroundColor Red
    exit 0
}

# 2. Sync State to Cloud
Write-Host "Syncing $StateDir to remote:astral-state..." -ForegroundColor Yellow
rclone sync $StateDir "remote:astral-state" --progress --metadata --links

if ($LASTEXITCODE -eq 0) {
    Write-Host "Mirror Sync Successful." -ForegroundColor Green
} else {
    Write-Host "Mirror Sync Failed with exit code $LASTEXITCODE" -ForegroundColor Red
}
