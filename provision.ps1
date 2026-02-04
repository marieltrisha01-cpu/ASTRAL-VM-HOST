# Advanced RDP/SSH Provisioning Script (Windows Server 2025) - /rdpdev 100% Persistence Model
$ErrorActionPreference = "Stop"

Write-Host "--- INITIALIZING 100% PERSISTENCE PROVISIONING ---" -ForegroundColor Cyan

# 1. State Directory Scaffolding
$StateDir = "C:\State"
$BaseProfile = "C:\Users\runneradmin"
$ProfileRoot = Join-Path $StateDir "Profile"

if (-not (Test-Path $StateDir)) { New-Item -Path $StateDir -ItemType Directory -Force }
if (-not (Test-Path $ProfileRoot)) { New-Item -Path $ProfileRoot -ItemType Directory -Force }

# 2. Prevent Locked Files: Stop common background processes
Write-Host "Ensuring clean state for redirection..." -ForegroundColor Yellow
$AppsToKill = @("chrome", "msedge", "onedrive", "teams", "skype", "explorer")
foreach ($App in $AppsToKill) { Stop-Process -Name $App -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2 # Wait for locks to release

# 3. Registry-Based Shell Folder Redirection (Native Windows way)
Write-Host "Applying Registry Shell Folder redirection..." -ForegroundColor Yellow
$ShellFoldersKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
$Redirections = @{
    "Desktop"   = "$ProfileRoot\Desktop"
    "Personal"  = "$ProfileRoot\Documents"
    "My Pictures" = "$ProfileRoot\Pictures"
    "My Video"  = "$ProfileRoot\Videos"
    "{374DE296-1261-41E8-A953-973F9238B61A}" = "$ProfileRoot\Downloads" # Downloads GUID
}

foreach ($Key in $Redirections.Keys) {
    if (-not (Test-Path $Redirections[$Key])) { New-Item -Path $Redirections[$Key] -ItemType Directory -Force }
    Set-ItemProperty -Path $ShellFoldersKey -Name $Key -Value $Redirections[$Key] -Force
}

# 4. Junction-Based AppData & System Persistence
$JunctionMaps = @(
    @{ Source = "AppData\Roaming"; Target = "$ProfileRoot\AppData\Roaming" },
    @{ Source = "AppData\Local"; Target = "$ProfileRoot\AppData\Local" },
    @{ Source = ".ssh"; Target = "$ProfileRoot\.ssh" },
    @{ Source = ".aws"; Target = "$ProfileRoot\.aws" },
    @{ Source = ".docker"; Target = "$ProfileRoot\.docker" }
)

Write-Host "Re-establishing Junctions for Application State..." -ForegroundColor Yellow
foreach ($Map in $JunctionMaps) {
    $SourcePath = Join-Path $BaseProfile $Map.Source
    $TargetPath = $Map.Target
    
    if (-not (Test-Path $TargetPath)) { New-Item -Path $TargetPath -ItemType Directory -Force }
    
    if (Test-Path $SourcePath) {
        $Item = Get-Item $SourcePath
        if ($Item.Attributes -notlike "*ReparsePoint*") {
            try {
                # Move content to persistent target if junction doesn't exist yet
                Get-ChildItem -Path $SourcePath | Move-Item -Destination $TargetPath -Force -ErrorAction SilentlyContinue
                Remove-Item $SourcePath -Recurse -Force
                New-Item -ItemType Junction -Path $SourcePath -Target $TargetPath -Force
                Write-Host "✓ Redirected $($Map.Source)" -ForegroundColor Green
            } catch {
                Write-Host "⚠ Warning: Could not move $($Map.Source). Retrying link only." -ForegroundColor Red
                # Just link if possible
                try { New-Item -ItemType Junction -Path $SourcePath -Target $TargetPath -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
    } else {
        $Parent = Split-Path $SourcePath
        if (-not (Test-Path $Parent)) { New-Item -Path $Parent -ItemType Directory -Force }
        New-Item -ItemType Junction -Path $SourcePath -Target $TargetPath -Force
    }
}

# 5. C:\State\bin in PATH
$StateBin = "C:\State\bin"
if (-not (Test-Path $StateBin)) { New-Item -Path $StateBin -ItemType Directory -Force }
$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($currentPath -notlike "*$StateBin*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$StateBin", "Machine")
}

# 6. Restart Explorer to apply Shell changes
start-process explorer

# 7. Networking & Firewall Hardening
Write-Host "Restoring Overlay Access..."
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1

$TailscaleInterface = (Get-NetIPInterface -InterfaceAlias "Tailscale" -ErrorAction SilentlyContinue)
if ($TailscaleInterface) {
    New-NetFirewallRule -DisplayName "Tailscale-RDP-In" -Direction Inbound -LocalPort 3389 -Protocol TCP -InterfaceAlias "Tailscale" -Action Allow
    New-NetFirewallRule -DisplayName "Tailscale-SSH-In" -Direction Inbound -LocalPort 22 -Protocol TCP -InterfaceAlias "Tailscale" -Action Allow
    Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
}

# 8. Service Persistence (SSH/Password)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue
Start-Service sshd -ErrorAction SilentlyContinue
if ($env:VM_PASSWORD) {
    $Password = $env:VM_PASSWORD | ConvertTo-SecureString -AsPlainText -Force
    Get-LocalUser -Name "runneradmin" | Set-LocalPassword -Password $Password
}

# 9. Tool Integrity Check (Install missing only)
$Tools = @("7zip.7zip", "Git.Git", "Google.Chrome", "Microsoft.VisualStudioCode", "rclone.rclone")
foreach ($Tool in $Tools) {
    winget install --id $Tool --accept-package-agreements --accept-source-agreements --silent --force
}

Write-Host "--- 100% PERSISTENCE MODEL ACTIVE ---" -ForegroundColor Cyan
