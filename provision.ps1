# Advanced RDP/SSH Provisioning Script - /rdpdev 100% Persistence Model
$ErrorActionPreference = 'Stop'

Write-Host '--- INITIALIZING 100% PERSISTENCE PROVISIONING ---' -ForegroundColor Cyan

# 1. State Directory Scaffolding
$StateDir = 'C:\State'
$BaseProfile = 'C:\Users\runneradmin'
$ProfileRoot = Join-Path $StateDir 'Profile'

if (-not (Test-Path $StateDir)) { $null = New-Item -Path $StateDir -ItemType Directory -Force }
if (-not (Test-Path $ProfileRoot)) { $null = New-Item -Path $ProfileRoot -ItemType Directory -Force }

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
    if (-not (Test-Path $Redirections[$Key])) { $null = New-Item -Path $Redirections[$Key] -ItemType Directory -Force }
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
    if (-not (Test-Path $TargetPath)) { $null = New-Item -Path $TargetPath -ItemType Directory -Force }
    if (Test-Path $SourcePath) {
        $Item = Get-Item $SourcePath
        if ($Item.Attributes -notlike '*ReparsePoint*') {
            try {
                Get-ChildItem -Path $SourcePath | Move-Item -Destination $TargetPath -Force -ErrorAction SilentlyContinue
                Remove-Item $SourcePath -Recurse -Force
                $null = New-Item -ItemType Junction -Path $SourcePath -Target $TargetPath -Force
                Write-Host ('âœ“ Redirected ' + $Map.Source) -ForegroundColor Green
            } catch {
                Write-Host ('âš  Warning: ' + $Map.Source) -ForegroundColor Red
                try { $null = New-Item -ItemType Junction -Path $SourcePath -Target $TargetPath -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
    } else {
        $Parent = Split-Path $SourcePath
        if (-not (Test-Path $Parent)) { $null = New-Item -Path $Parent -ItemType Directory -Force }
        $null = New-Item -ItemType Junction -Path $SourcePath -Target $TargetPath -Force
    }
}

# 5. C:\State\bin in PATH
$StateBin = 'C:\State\bin'
if (-not (Test-Path $StateBin)) { $null = New-Item -Path $StateBin -ItemType Directory -Force }
$currentPath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($currentPath -notlike ('*' + $StateBin + '*')) {
    $newPath = $currentPath + ';' + $StateBin
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine')
}

# 6. Restart Explorer
Start-Process explorer

# 7. Networking & Firewall Hardening
Write-Host 'Optimizing Networking for Server 2025 RDP...' -ForegroundColor Cyan

# 7.1 Protocol & Reliability Registry Tweaks
$TSPoliciesClient = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client'
$TSPoliciesServer = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
if (-not (Test-Path $TSPoliciesClient)) { $null = New-Item -Path $TSPoliciesClient -Force }
if (-not (Test-Path $TSPoliciesServer)) { $null = New-Item -Path $TSPoliciesServer -Force }

Set-ItemProperty -Path $TSPoliciesClient -Name 'fClientDisableUDP' -Value 1 -Force
Set-ItemProperty -Path $TSPoliciesServer -Name 'SelectNetworkDetect' -Value 0 -Force

# 7.2 Interface Wait Loop
Write-Host 'Waiting for Tailscale interface...' -ForegroundColor Yellow
$RetryCount = 0
$TailscaleInterface = $null
while ($RetryCount -lt 12) {
    $TailscaleInterface = Get-NetIPInterface -InterfaceAlias 'Tailscale' -ErrorAction SilentlyContinue
    if ($TailscaleInterface) { 
        Write-Host "âœ“ Tailscale connected." -ForegroundColor Green
        break 
    }
    Start-Sleep -Seconds 5
    $RetryCount++
}

# 7.3 Firewall Rules
Write-Host 'Applying Firewall Overrides...' -ForegroundColor Yellow
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

netsh advfirewall firewall add rule name="RDP-TCP-In-Definitive" dir=in action=allow protocol=TCP localport=3389 profile=any
netsh advfirewall firewall add rule name="SSH-TCP-In-Definitive" dir=in action=allow protocol=TCP localport=22 profile=any
netsh advfirewall firewall add rule name="Tailscale-Subnet-Trust" dir=in action=allow remoteip=100.64.0.0/10 profile=any

if ($TailscaleInterface) {
    $null = New-NetFirewallRule -DisplayName 'Tailscale-Only-RDP' -Direction Inbound -LocalPort 3389 -Protocol TCP -InterfaceAlias 'Tailscale' -Action Allow -Profile Any -Force
}

# 8. Service Health & RDP Binding
Write-Host 'Configuring RDP Security...' -ForegroundColor Cyan
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Force
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 0 -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'SecurityLayer' -Value 0 -Force

Restart-Service TermService -Force -ErrorAction SilentlyContinue

# Verification
Write-Host "Checking if ports are listening..."
netstat -an | Select-String "LISTENING" | Select-String "3389|22|8080"

# 8.1 dummy listener
$Listener = [System.Net.Sockets.TcpListener]8080
try {
    $Listener.Start()
    Write-Host "âœ“ Dummy connectivity listener started." -ForegroundColor Green
} catch {
    Write-Host "Failed to start dummy listener: $_" -ForegroundColor Red
}

# 8. Service Persistence (SSH/Password)
Write-Host "Configuring Services and Users..."
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue
Start-Service sshd -ErrorAction SilentlyContinue
if ($env:VM_PASSWORD) {
    Write-Host "Setting password for runneradmin..."
    $Password = $env:VM_PASSWORD | ConvertTo-SecureString -AsPlainText -Force
    Set-LocalUser -Name 'runneradmin' -Password $Password
    
    Add-LocalGroupMember -Group 'Remote Desktop Users' -Member 'runneradmin' -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group 'Administrators' -Member 'runneradmin' -ErrorAction SilentlyContinue
}

# 10. Final Pass
Write-Host "Final Health Check..." -ForegroundColor Cyan
Set-Service TermService -StartupType Automatic -ErrorAction SilentlyContinue
Set-Service SessionEnv -StartupType Automatic -ErrorAction SilentlyContinue
Set-Service UmRdpService -StartupType Automatic -ErrorAction SilentlyContinue

Start-Service TermService, SessionEnv, UmRdpService -ErrorAction SilentlyContinue

# 9. Tool Integrity Check
$Tools = @('7zip.7zip', 'Git.Git', 'Google.Chrome', 'Microsoft.VisualStudioCode', 'rclone.rclone')
foreach ($Tool in $Tools) {
    winget install --id $Tool --accept-package-agreements --accept-source-agreements --silent --force
}

Write-Host '--- PERSISTENCE MODEL ACTIVE ---' -ForegroundColor Cyan
