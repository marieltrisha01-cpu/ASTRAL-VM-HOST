# Advanced RDP/SSH Provisioning Script (Windows Server 2025) - /rdpdev Universal Persistence
$ErrorActionPreference = "Stop"

Write-Host "--- Initializing Universal Persistence Provisioning ---" -ForegroundColor Cyan

# 1. State Directory Scaffolding
$StateDir = "C:\State"
$BaseProfile = "C:\Users\runneradmin"
$PersistentFolders = @(
    "Desktop", 
    "Documents", 
    "Downloads", 
    "AppData\Roaming", 
    "AppData\Local"
)

# System Data Persistence (Docker/WSL)
$SystemPersistence = @(
    @{ Source = "C:\ProgramData\docker"; Target = "C:\State\SystemData\docker" },
    @{ Source = "$BaseProfile\.docker"; Target = "C:\State\Profile\.docker" }
)

if (-not (Test-Path $StateDir)) {
    New-Item -Path $StateDir -ItemType Directory
    Write-Host "Created state root at $StateDir" -ForegroundColor Green
}

# 2. Add C:\State\bin to PATH for portable apps
$StateBin = "C:\State\bin"
if (-not (Test-Path $StateBin)) { New-Item -Path $StateBin -ItemType Directory -Force }
$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($currentPath -notlike "*$StateBin*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$StateBin", "Machine")
    Write-Host "Added $StateBin to System PATH." -ForegroundColor Green
}

# 3. User Profile Folder Redirection
Write-Host "Redirecting User Profile folders (Universal Persistence)..." -ForegroundColor Yellow
foreach ($Folder in $PersistentFolders) {
    $SourcePath = Join-Path $BaseProfile $Folder
    $TargetPath = Join-Path $StateDir "Profile\$Folder"
    
    if (-not (Test-Path $TargetPath)) { New-Item -Path $TargetPath -ItemType Directory -Force }
    
    if (Test-Path $SourcePath) {
        $Item = Get-Item $SourcePath
        if ($Item.Attributes -notlike "*ReparsePoint*") {
            try {
                Get-ChildItem -Path $SourcePath | Move-Item -Destination $TargetPath -Force -ErrorAction SilentlyContinue
                Remove-Item $SourcePath -Recurse -Force
                New-Item -ItemType Junction -Path $SourcePath -Target $TargetPath -Force
                Write-Host "Junctioned $Folder" -ForegroundColor Green
            } catch {
                Write-Host "Warning: $Folder in use. Skipping migration, will link next boot." -ForegroundColor Red
            }
        }
    } else {
        $Parent = Split-Path $SourcePath
        if (-not (Test-Path $Parent)) { New-Item -Path $Parent -ItemType Directory -Force }
        New-Item -ItemType Junction -Path $SourcePath -Target $TargetPath -Force
    }
}

# 4. System Data Redirection (Docker, etc.)
foreach ($Map in $SystemPersistence) {
    $src = $Map.Source
    $tgt = $Map.Target
    if (-not (Test-Path $tgt)) { New-Item -Path $tgt -ItemType Directory -Force }
    if (Test-Path $src) {
        $Item = Get-Item $src
        if ($Item.Attributes -notlike "*ReparsePoint*") {
            try {
                Stop-Service docker -ErrorAction SilentlyContinue 
                Get-ChildItem -Path $src | Move-Item -Destination $tgt -Force -ErrorAction SilentlyContinue
                Remove-Item $src -Recurse -Force
                New-Item -ItemType Junction -Path $src -Target $tgt -Force
                Start-Service docker -ErrorAction SilentlyContinue
            } catch { Write-Host "Skipped $src" }
        }
    } else {
        $Parent = Split-Path $src
        if (-not (Test-Path $Parent)) { New-Item -Path $Parent -ItemType Directory -Force }
        New-Item -ItemType Junction -Path $src -Target $tgt -Force
    }
}

# 5. Networking & Firewall Lockdown
Write-Host "Hardening Network..."
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1

$TailscaleInterface = (Get-NetIPInterface -InterfaceAlias "Tailscale" -ErrorAction SilentlyContinue)
if ($TailscaleInterface) {
    New-NetFirewallRule -DisplayName "Tailscale-RDP-In" -Direction Inbound -LocalPort 3389 -Protocol TCP -InterfaceAlias "Tailscale" -Action Allow -Force
    New-NetFirewallRule -DisplayName "Tailscale-SSH-In" -Direction Inbound -LocalPort 22 -Protocol TCP -InterfaceAlias "Tailscale" -Action Allow -Force
    Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
}

# 6. Configure OpenSSH
Write-Host "Configuring OpenSSH..."
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name "DefaultShell" -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force

# 7. Set Runner Admin Password
if ($env:VM_PASSWORD) {
    $Password = $env:VM_PASSWORD | ConvertTo-SecureString -AsPlainText -Force
    Get-LocalUser -Name "runneradmin" | Set-LocalPassword -Password $Password
}

# 8. Install Base Tools via WinGet
$Tools = @("7zip.7zip", "Git.Git", "Google.Chrome", "Microsoft.VisualStudioCode", "rclone.rclone")
foreach ($Tool in $Tools) {
    winget install --id $Tool --accept-package-agreements --accept-source-agreements --silent --force
}

Write-Host "--- Universal Persistence Setup Complete ---" -ForegroundColor Cyan
