# Advanced RDP/SSH Provisioning Script (Windows Server 2025) - /rdpdev Total Persistence
$ErrorActionPreference = "Stop"

Write-Host "--- Initializing Total Persistence Provisioning ---" -ForegroundColor Cyan

# 1. State Directory Scaffolding
$StateDir = "C:\State"
$BaseProfile = "C:\Users\runneradmin"
$PersistentFolders = @("Desktop", "Documents", "Downloads", "Pictures", "Videos", "AppData\Local\Google\Chrome\User Data")

if (-not (Test-Path $StateDir)) {
    New-Item -Path $StateDir -ItemType Directory
    Write-Host "Created state root at $StateDir" -ForegroundColor Green
}

# 2. Folder Redirection & Junctions (/rdpdev requirement)
Write-Host "Redirecting User Profile folders to Persistence Layer..." -ForegroundColor Yellow
foreach ($Folder in $PersistentFolders) {
    $SourcePath = Join-Path $BaseProfile $Folder
    $TargetPath = Join-Path $StateDir $Folder
    
    # Ensure Target exists in State
    if (-not (Test-Path $TargetPath)) {
        New-Item -Path $TargetPath -ItemType Directory -Force
    }
    
    # If Source exists and is NOT a link, move contents and recreate as Link
    if (Test-Path $SourcePath) {
        $Item = Get-Item $SourcePath
        if ($Item.Attributes -notlike "*ReparsePoint*") {
            Get-ChildItem -Path $SourcePath | Move-Item -Destination $TargetPath -Force -ErrorAction SilentlyContinue
            Remove-Item $SourcePath -Recurse -Force
            New-Item -ItemType Junction -Path $SourcePath -Target $TargetPath -Force
            Write-Host "Linked $Folder -> $TargetPath" -ForegroundColor Green
        }
    } else {
        # Create parent dir if missing
        $Parent = Split-Path $SourcePath
        if (-not (Test-Path $Parent)) { New-Item -Path $Parent -ItemType Directory -Force }
        New-Item -ItemType Junction -Path $SourcePath -Target $TargetPath -Force
        Write-Host "Created Link for $Folder -> $TargetPath" -ForegroundColor Green
    }
}

# 3. Networking & Firewall Lockdown
Write-Host "Hardening Network..."
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1

$TailscaleInterface = (Get-NetIPInterface -InterfaceAlias "Tailscale" -ErrorAction SilentlyContinue)
if ($TailscaleInterface) {
    New-NetFirewallRule -DisplayName "Tailscale-RDP-In" -Direction Inbound -LocalPort 3389 -Protocol TCP -InterfaceAlias "Tailscale" -Action Allow -Force
    New-NetFirewallRule -DisplayName "Tailscale-SSH-In" -Direction Inbound -LocalPort 22 -Protocol TCP -InterfaceAlias "Tailscale" -Action Allow -Force
    Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
}

# 4. Configure OpenSSH
Write-Host "Configuring OpenSSH..."
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name "DefaultShell" -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force

# 5. Set Runner Admin Password
if ($env:VM_PASSWORD) {
    Write-Host "Setting password for runneradmin..."
    $User = "runneradmin"
    $Password = $env:VM_PASSWORD | ConvertTo-SecureString -AsPlainText -Force
    $AdminUser = Get-LocalUser -Name $User
    $AdminUser | Set-LocalPassword -Password $Password
}

# 6. Install Tools via WinGet
Write-Host "Installing project tools..."
$Tools = @("Microsoft.VisualStudioCode", "Git.Git", "7zip.7zip", "Python.Python.3.12", "Google.Chrome")
foreach ($Tool in $Tools) {
    winget install --id $Tool --accept-package-agreements --accept-source-agreements --silent --force
}

Write-Host "--- Total Persistence Setup Complete ---" -ForegroundColor Cyan
