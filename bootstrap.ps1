#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap a Windows PC as a Claude Code-managed IT endpoint.

.DESCRIPTION
    One-liner (run as Administrator):
      irm https://raw.githubusercontent.com/evolv3-ai/dotfiles/main/bootstrap.ps1 | iex

    Steps:
      1. Install Node.js LTS + Claude Code
      2. Install IT admin tools via winget
      3. Deploy Claude Code config (CLAUDE.md + settings)
      4. Deploy PowerShell profile
      5. Collect system inventory

.PARAMETER SkipApps
    Skip winget app installation (only install Node.js + Claude Code).

.PARAMETER SkipProfile
    Skip PowerShell profile deployment.

.PARAMETER SkipInventory
    Skip system inventory collection.

.PARAMETER RepoDir
    Local directory to clone/use the bootstrap repo. Defaults to C:\bootstrap.
#>
[CmdletBinding()]
param(
    [switch]$SkipApps,
    [switch]$SkipProfile,
    [switch]$SkipInventory,
    [string]$RepoDir = 'C:\bootstrap'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Unlock script execution for this process (npm, winget shims are .ps1 files)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# --- Helpers ----------------------------------------------------------------

function Write-Step  { param([string]$Msg) Write-Host "`n:: $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "   OK  $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "   WARN  $Msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$Msg) Write-Host "   FAIL  $Msg" -ForegroundColor Red }

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Refresh-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# --- Banner -----------------------------------------------------------------

Write-Host ''
Write-Host '============================================' -ForegroundColor White
Write-Host '  IT Endpoint Bootstrap - Claude Code       ' -ForegroundColor White
Write-Host '============================================' -ForegroundColor White

if (-not (Test-IsAdmin)) {
    Write-Warn 'Not running as Administrator. Some steps may fail.'
    Write-Host '   Right-click PowerShell -> Run as Administrator' -ForegroundColor Yellow
}

$osCaption = (Get-CimInstance Win32_OperatingSystem).Caption
$osBuild   = [Environment]::OSVersion.Version.Build
Write-Host "`n  Machine : $env:COMPUTERNAME"
Write-Host "  OS      : $osCaption (build $osBuild)"
Write-Host "  User    : $env:USERNAME"

# --- Ensure repo is local ---------------------------------------------------

Write-Step 'Ensuring bootstrap repo is available locally...'

if (Test-Path (Join-Path $RepoDir '.git')) {
    Write-Ok "Repo already at $RepoDir"
} elseif (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "   Cloning to $RepoDir..." -ForegroundColor Gray
    git clone https://github.com/evolv3-ai/dotfiles.git $RepoDir 2>&1 | Out-Null
    Write-Ok "Cloned to $RepoDir"
} else {
    Write-Host '   git not found - downloading repo as zip...' -ForegroundColor Gray
    $zip = Join-Path $env:TEMP 'bootstrap-repo.zip'
    Invoke-WebRequest -Uri 'https://github.com/evolv3-ai/dotfiles/archive/refs/heads/main.zip' `
                      -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force
    if (Test-Path $RepoDir) { Remove-Item $RepoDir -Recurse -Force }
    Move-Item (Join-Path $env:TEMP 'dotfiles-main') $RepoDir -Force
    Remove-Item $zip -Force
    Write-Ok "Downloaded to $RepoDir"
}

# --- Step 1: Node.js + Claude Code -----------------------------------------

Write-Step 'Installing Node.js + Claude Code...'

$installScript = Join-Path $RepoDir 'claude-code\install.ps1'
if (Test-Path $installScript) {
    Get-Content $installScript -Raw | Invoke-Expression
} else {
    Write-Fail "install.ps1 not found at $installScript"
    exit 1
}

Refresh-SessionPath

# --- Step 2: IT Admin Apps --------------------------------------------------

if (-not $SkipApps) {
    Write-Step 'Installing IT admin tools...'
    $appsScript = Join-Path $RepoDir 'windows\Install-Apps.ps1'
    if (Test-Path $appsScript) {
        Get-Content $appsScript -Raw | Invoke-Expression
    } else {
        Write-Warn 'Install-Apps.ps1 not found - skipping'
    }
} else {
    Write-Step 'Skipping app install (-SkipApps)'
}

# --- Step 3: Claude Code Config --------------------------------------------

Write-Step 'Deploying Claude Code configuration...'

$ccDir = Join-Path $env:USERPROFILE '.claude'
if (-not (Test-Path $ccDir)) { New-Item -ItemType Directory -Path $ccDir -Force | Out-Null }

# CLAUDE.md - deploy to user .claude dir (global instructions)
$ccMdSource = Join-Path $RepoDir 'claude-code\CLAUDE.md'
$ccMdTarget = Join-Path $ccDir 'CLAUDE.md'
if ((Test-Path $ccMdSource) -and -not (Test-Path $ccMdTarget)) {
    Copy-Item $ccMdSource $ccMdTarget -Force
    Write-Ok "Deployed CLAUDE.md to $ccMdTarget"
} elseif (Test-Path $ccMdTarget) {
    Write-Ok 'CLAUDE.md already exists - not overwriting'
} else {
    Write-Warn 'CLAUDE.md source not found in repo'
}

# settings.json - don't overwrite existing
$settingsSource = Join-Path $RepoDir 'claude-code\settings.json'
$settingsTarget = Join-Path $ccDir 'settings.json'
if ((Test-Path $settingsSource) -and -not (Test-Path $settingsTarget)) {
    Copy-Item $settingsSource $settingsTarget -Force
    Write-Ok "Deployed settings.json to $settingsTarget"
} elseif (Test-Path $settingsTarget) {
    Write-Ok 'settings.json already exists - not overwriting'
}

# --- Step 4: PowerShell Profile ---------------------------------------------

if (-not $SkipProfile) {
    Write-Step 'Deploying PowerShell profile...'

    $profileSource = Join-Path $RepoDir 'powershell\Profile.ps1'

    # Target CurrentUserAllHosts for pwsh 7+
    $profileTarget = $PROFILE.CurrentUserAllHosts
    $profileDir    = Split-Path $profileTarget
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    if (Test-Path $profileSource) {
        if (Test-Path $profileTarget) {
            $backup = "$profileTarget.bak"
            Copy-Item $profileTarget $backup -Force
            Write-Ok "Backed up existing profile to $backup"
        }
        Copy-Item $profileSource $profileTarget -Force
        Write-Ok "Deployed profile to $profileTarget"
    } else {
        Write-Warn 'Profile.ps1 not found in repo'
    }
} else {
    Write-Step 'Skipping profile deploy (-SkipProfile)'
}

# --- Step 5: System Inventory -----------------------------------------------

if (-not $SkipInventory) {
    Write-Step 'Collecting system inventory...'
    $inventoryScript = Join-Path $RepoDir 'scripts\Get-SystemInfo.ps1'
    if (Test-Path $inventoryScript) {
        Get-Content $inventoryScript -Raw | Invoke-Expression
    } else {
        Write-Warn 'Get-SystemInfo.ps1 not found - skipping'
    }
} else {
    Write-Step 'Skipping inventory (-SkipInventory)'
}

# --- Done -------------------------------------------------------------------

Refresh-SessionPath

Write-Host ''
Write-Host '============================================' -ForegroundColor Green
Write-Host '  Bootstrap complete!                       ' -ForegroundColor Green
Write-Host '============================================' -ForegroundColor Green
Write-Host ''
Write-Host '  Next steps:' -ForegroundColor White
Write-Host '    1. Open a NEW terminal (PowerShell 7 / Windows Terminal)' -ForegroundColor Gray
Write-Host '    2. Run:  claude' -ForegroundColor White
Write-Host '    3. Sign in via browser when prompted' -ForegroundColor Gray
Write-Host ''
