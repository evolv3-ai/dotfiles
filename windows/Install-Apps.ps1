#Requires -Version 5.1
<#
.SYNOPSIS
    Install IT admin tools via winget.

.DESCRIPTION
    Installs core and IT-specific tools on managed Windows endpoints.
    Comment out any packages you don't need.

.PARAMETER AdditionalApps
    Extra winget IDs to install beyond the defaults.

.PARAMETER CoreOnly
    Only install the core tools (Node, Git, PowerShell, etc.) — skip IT extras.
#>
[CmdletBinding()]
param(
    [string[]]$AdditionalApps = @(),
    [switch]$CoreOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Check admin + winget ---------------------------------------------------

if (![bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match 'S-1-5-32-544')) {
    Write-Error 'Please run as Administrator.'
    return
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warning 'winget not found. On Windows 10, install "App Installer" from the Microsoft Store first.'
    return
}

# --- App lists --------------------------------------------------------------

# Core: needed for Claude Code and basic IT ops
$CoreApps = @(
    'Microsoft.PowerShell'          # PowerShell 7+
    'Git.Git'                       # Version control
    '7zip.7zip'                     # Archive management
    'Microsoft.WindowsTerminal'     # Windows Terminal
)

# IT Admin: diagnostics, remote access, networking
$ITAdminApps = @(
    'Microsoft.Sysinternals.Suite'  # Process Explorer, Autoruns, PsTools, etc.
    'JAMSoftware.TreeSize.Free'     # Disk space analysis
    'WinSCP.WinSCP'                 # Secure file transfer (SCP/SFTP)
    'PuTTY.PuTTY'                   # SSH client
    'voidtools.Everything'          # Instant file search
    'Insecure.Nmap'                 # Network scanning
    'WiresharkFoundation.Wireshark' # Network packet capture
    'Notepad++.Notepad++'           # Quick text editor
)

# --- Installer function -----------------------------------------------------

function Install-WingetApp {
    param([string]$AppId)
    try {
        $check = winget list --id $AppId --accept-source-agreements 2>&1
        $notFound = ($check | Out-String) -match 'No installed package found'
        if ($notFound) {
            Write-Host "  Installing $AppId..." -ForegroundColor Yellow
            winget install --id $AppId --source winget --silent `
                  --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  OK  $AppId" -ForegroundColor Green
            } else {
                Write-Host "  WARN  $AppId exited with code $LASTEXITCODE" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  SKIP  $AppId (already installed)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  FAIL  $AppId : $_" -ForegroundColor Red
    }
}

# --- Run --------------------------------------------------------------------

$apps = $CoreApps
if (-not $CoreOnly) {
    $apps += $ITAdminApps
}
$apps += $AdditionalApps

Write-Host "`n:: Installing $($apps.Count) packages...`n" -ForegroundColor Cyan

foreach ($app in $apps) {
    Install-WingetApp -AppId $app
}

Write-Host "`n:: App installation complete.`n" -ForegroundColor Green
