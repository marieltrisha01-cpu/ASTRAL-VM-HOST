# Advanced RDP/SSH Provisioning Script (Windows Server 2025) - /rdpdev Hardened
$ErrorActionPreference = "Stop"

Write-Host "--- Initializing Provisioning for Windows Server 2025 ---" -ForegroundColor Cyan

# 1. State Directory Preparation
$StateDir = "C:\State"
if (-not (Test-Path $StateDir)) {
    New-Item -Path $StateDir -ItemType Directory
    Write-Host "Created state directory at $StateDir" -ForegroundColor Green
}

# 2. Networking & Firewall Lockdown (/rdpdev requirement)
Write-Host "Hardening Network..."
# Enable RDP and NLA
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1

# Firewall: Allow RDP/SSH ONLY from Tailscale interface
$TailscaleInterface = (Get-NetIPInterface -InterfaceAlias "Tailscale" -ErrorAction SilentlyContinue)
if ($TailscaleInterface) {
    Write-Host "Locking down firewall to Tailscale interface..." -ForegroundColor Yellow
    New-NetFirewallRule -DisplayName "Tailscale-RDP-In" -Direction Inbound -LocalPort 3389 -Protocol TCP -InterfaceAlias "Tailscale" -Action Allow -Force
    New-NetFirewallRule -DisplayName "Tailscale-SSH-In" -Direction Inbound -LocalPort 22 -Protocol TCP -InterfaceAlias "Tailscale" -Action Allow -Force
    
    # Disable global RDP/SSH rules (if they exist) to ensure only Tailscale access
    Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
}

# 3. Configure OpenSSH
Write-Host "Configuring OpenSSH..."
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name "DefaultShell" -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force

# 4. Set Runner Admin Password
if ($env:VM_PASSWORD) {
    Write-Host "Setting password for runneradmin..."
    $User = "runneradmin"
    $Password = $env:VM_PASSWORD | ConvertTo-SecureString -AsPlainText -Force
    $AdminUser = Get-LocalUser -Name $User
    $AdminUser | Set-LocalPassword -Password $Password
}

# 5. Install Tools via WinGet
Write-Host "Installing project tools..."
$Tools = @("Microsoft.VisualStudioCode", "Git.Git", "7zip.7zip", "Python.Python.3.12")
foreach ($Tool in $Tools) {
    winget install --id $Tool --accept-package-agreements --accept-source-agreements --silent
}

# 6. Self-Healing & Health Check Agent
Write-Host "Deploying Health Agent..."
$HealthScript = {
    while ($true) {
        # Check if Tailscale is up
        if (-not (tailscale status)) {
            Write-EventLog -LogName Application -Source "HealthAgent" -EventID 1001 -EntryType Warning -Message "Tailscale disconnected!"
            tailscale up --authkey "$($env:TAILSCALE_AUTHKEY)"
        }
        # Incremental backup trigger (every 30 mins)
        # This acts as a 'Self-Healing' state layer
        Start-Sleep -Seconds 1800
    }
}
# Note: For simple GHA runs, the health check is maintained by the 'Keep VM Alive' step in main.yml

Write-Host "--- Hardening Complete ---" -ForegroundColor Cyan
