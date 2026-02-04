# Advanced RDP/SSH Provisioning Script - /rdpdev 100% Persistence Model
$ErrorActionPreference = 'Stop'

Write-Host '--- INITIALIZING 100% PERSISTENCE PROVISIONING ---' -ForegroundColor Cyan

# 1. State Directory Scaffolding
$StateDir = 'C:\State'
$BaseProfile = 'C:\Users\runneradmin'
$ProfileRoot = Join-Path $StateDir 'Profile'

if (-not (Test-Path $StateDir)) { New-Item -Path $StateDir -ItemType Directory -Force }
if (-not (Test-Path $ProfileRoot)) { New-Item -Path $ProfileRoot -ItemType Directory -Force }

# 2. Prevent Locked Files
Write-Host 'Ensuring clean state for redirection...' -ForegroundColor Yellow
$AppsToKill = @('chrome', 'msedge', 'onedrive', 'teams', 'skype', 'explorer')
foreach ($App in $AppsToKill) { Stop-Process -Name $App -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2

# 3. Registry-Based Shell Folder Redirection
Write-Host 'Applying Registry Shell Folder redirection...' -ForegroundColor Yellow
$ShellFoldersKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
$Redirections = @{
    'Desktop'   = "$ProfileRoot\Desktop"
    'Personal'  = "$ProfileRoot\Documents"
    'My Pictures' = "$ProfileRoot\Pictures"
    'My Video'  = "$ProfileRoot\Videos"
    '{374DE296-1261-41E8-A953-973F9238B61A}' = "$ProfileRoot\Downloads"
}

foreach ($Key in $Redirections.Keys) {
    if (-not (Test-Path $Redirections[$Key])) { New-Item -Path $Redirections[$Key] -ItemType Directory -Force }
    Set-ItemProperty -Path $ShellFoldersKey -Name $Key -Value $Redirections[$Key] -Force
}

# 4. Junction-Based AppData & System Persistence
$JunctionMaps = @(
    @{ Source = 'AppData\Roaming'; Target = "$ProfileRoot\AppData\Roaming" },
    @{ Source = 'AppData\Local'; Target = "$ProfileRoot\AppData\Local" },
    @{ Source = '.ssh'; Target = "$ProfileRoot\.ssh" },
    @{ Source = '.aws'; Target = "$ProfileRoot\.aws" },
    @{ Source = '.docker'; Target = "$ProfileRoot\.docker" }
)

Write-Host 'Re-establishing Junctions...' -ForegroundColor Yellow
foreach ($Map in $JunctionMaps) {
    $SourcePath = Join-Path $BaseProfile $Map.Source
    $TargetPath = $Map.Target
    if (-not (Test-Path $TargetPath)) { New-Item -Path $TargetPath -ItemType Directory -Force }
    if (Test-Path $SourcePath) {
        $Item = Get-Item $SourcePath
        if ($Item.Attributes -notlike '*ReparsePoint*') {
            try {
                Get-ChildItem -Path $SourcePath | Move-Item -Destination $TargetPath -Force -ErrorAction SilentlyContinue
                Remove-Item $SourcePath -Recurse -Force
                New-Item -ItemType Junction -Path $SourcePath -Target $TargetPath -Force
                Write-Host ('✓ Redirected ' + $Map.Source) -ForegroundColor Green
            } catch {
                Write-Host ('⚠ Warning: ' + $Map.Source) -ForegroundColor Red
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
$StateBin = 'C:\State\bin'
if (-not (Test-Path $StateBin)) { New-Item -Path $StateBin -ItemType Directory -Force }
$currentPath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($currentPath -notlike ('*' + $StateBin + '*')) {
    $newPath = $currentPath + ';' + $StateBin
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine')
}

# 6. Restart Explorer
start-process explorer

# 7. Networking & Firewall Hardening
Write-Host 'Restoring Overlay Access...'
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 0

# DEBUG: List all network interfaces
Get-NetIPInterface | Select-Object InterfaceAlias, InterfaceIndex, AddressFamily, ConnectionState | Out-String | Write-Host

# Universal Firewall Rules for RDP/SSH (troubleshooting mode)
Write-Host "Configuring Troubleshooting Firewall Rules..."
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False # TROUBLESHOOTING ONLY
New-NetFirewallRule -DisplayName 'Allow-RDP-Global' -Direction Inbound -LocalPort 3389 -Protocol TCP -Action Allow -Profile Any -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName 'Allow-SSH-Global' -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow -Profile Any -ErrorAction SilentlyContinue

# Explicitly trust Tailscale subnet
New-NetFirewallRule -DisplayName "Tailscale-Subnet-Trust" -Direction Inbound -RemoteAddress "100.64.0.0/10" -Action Allow -Profile Any -ErrorAction SilentlyContinue

Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue

# Verification: Is the port listening?
Write-Host "Checking if ports are listening..."
netstat -an | Select-String "3389|22" | Out-String | Write-Host

$TailscaleInterface = (Get-NetIPInterface -InterfaceAlias 'Tailscale' -ErrorAction SilentlyContinue)
if ($TailscaleInterface) {
    Write-Host "Tailscale interface found. Index: $($TailscaleInterface.InterfaceIndex)" -ForegroundColor Green
} else {
    Write-Host "Tailscale interface NOT found by alias." -ForegroundColor Red
}

# 8. Service Persistence (SSH/Password)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue
Start-Service sshd -ErrorAction SilentlyContinue
if ($env:VM_PASSWORD) {
    Write-Host "Setting password for runneradmin..."
    $Password = $env:VM_PASSWORD | ConvertTo-SecureString -AsPlainText -Force
    Set-LocalUser -Name 'runneradmin' -Password $Password
    
    # Ensure runneradmin is in Remote Desktop Users and Administrators
    Add-LocalGroupMember -Group 'Remote Desktop Users' -Member 'runneradmin' -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group 'Administrators' -Member 'runneradmin' -ErrorAction SilentlyContinue
}

# 8.1 Robust RDP Enablement
Write-Host "Performing robust RDP enablement..."
(Get-WmiObject -Class Win32_TerminalServiceSetting -Namespace root\cimv2\TerminalServices).SetAllowTSConnections(1,1) | Out-Null
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 0
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'SecurityLayer' -Value 0

# Restart RDP Services to apply changes
Restart-Service TermService -Force -ErrorAction SilentlyContinue

Write-Host "RDP Service Status:"
Get-Service TermService | Select-Object Status, DisplayName | Out-String | Write-Host

# 9. Tool Integrity Check
$Tools = @('7zip.7zip', 'Git.Git', 'Google.Chrome', 'Microsoft.VisualStudioCode', 'rclone.rclone')
foreach ($Tool in $Tools) {
    winget install --id $Tool --accept-package-agreements --accept-source-agreements --silent --force
}

Write-Host '--- PERSISTENCE MODEL ACTIVE ---' -ForegroundColor Cyan
