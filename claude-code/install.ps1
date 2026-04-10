#Requires -Version 5.1
<#
.SYNOPSIS
    Install Node.js LTS and Claude Code on Windows 10 or 11.

.DESCRIPTION
    - Detects or installs Node.js LTS (winget on Win11, direct MSI on Win10)
    - Installs @anthropic-ai/claude-code globally via npm
    - Safe to re-run (skips steps already done)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$Msg) Write-Host "`n:: $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "   OK  $Msg" -ForegroundColor Green }
function Write-Skip  { param([string]$Msg) Write-Host "   SKIP  $Msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$Msg) Write-Host "   FAIL  $Msg" -ForegroundColor Red }

function Test-CommandExists {
    param([string]$Cmd)
    $null -ne (Get-Command $Cmd -ErrorAction SilentlyContinue)
}

function Refresh-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# --- Node.js ----------------------------------------------------------------

Write-Step 'Checking for Node.js...'

$nodeInstalled = $false

if (Test-CommandExists 'node') {
    $nodeVer = (node -v 2>$null)
    $major = [int]($nodeVer -replace '^v(\d+).*', '$1')
    if ($major -ge 18) {
        Write-Ok "Node.js $nodeVer already installed (v18+ required)"
        $nodeInstalled = $true
    } else {
        Write-Fail "Node.js $nodeVer is too old (need v18+). Will install LTS."
    }
} else {
    Write-Host '   Node.js not found. Will install.' -ForegroundColor Yellow
}

if (-not $nodeInstalled) {
    Write-Step 'Installing Node.js LTS...'

    $hasWinget = Test-CommandExists 'winget'

    if ($hasWinget) {
        Write-Host '   Using winget...' -ForegroundColor Gray
        winget install --id OpenJS.NodeJS.LTS --source winget `
              --accept-source-agreements --accept-package-agreements --silent
        # -1978335189 = already installed
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
            throw "winget install failed (exit code $LASTEXITCODE)"
        }
    } else {
        Write-Host '   winget not available - downloading Node.js MSI...' -ForegroundColor Gray

        $nodeIndex = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
        $lts = $nodeIndex | Where-Object { $_.lts -ne $false } | Select-Object -First 1
        $ltsVersion = $lts.version

        $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
        $msiUrl  = "https://nodejs.org/dist/$ltsVersion/node-$ltsVersion-$arch.msi"
        $msiPath = Join-Path $env:TEMP "node-$ltsVersion-$arch.msi"

        Write-Host "   Downloading $msiUrl ..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

        Write-Host '   Running MSI installer (silent)...' -ForegroundColor Gray
        $proc = Start-Process msiexec -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "MSI install failed (exit code $($proc.ExitCode)). Try running as Administrator."
        }

        Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
    }

    Refresh-SessionPath

    if (-not (Test-CommandExists 'node')) {
        Write-Fail 'node not found after install. Close and reopen PowerShell, then re-run.'
        return
    }

    $nodeVer = (node -v 2>$null)
    Write-Ok "Node.js $nodeVer installed"
}

# --- npm check --------------------------------------------------------------

Write-Step 'Checking npm...'
Refresh-SessionPath

if (-not (Test-CommandExists 'npm')) {
    Write-Fail 'npm not found. Node.js may not have installed correctly.'
    Write-Host '   Close this terminal, open a new one, and re-run.' -ForegroundColor Yellow
    return
}

$npmVer = (npm -v 2>$null)
Write-Ok "npm $npmVer"

# --- Claude Code ------------------------------------------------------------

Write-Step 'Installing Claude Code...'

$existing = npm list -g @anthropic-ai/claude-code --depth=0 2>$null
if ($existing -match '@anthropic-ai/claude-code@') {
    $ccVer = ($existing | Select-String '@anthropic-ai/claude-code@(\S+)').Matches.Groups[1].Value
    Write-Skip "Claude Code $ccVer already installed globally"
    Write-Host '   To update: npm update -g @anthropic-ai/claude-code' -ForegroundColor Gray
} else {
    npm install -g @anthropic-ai/claude-code
    if ($LASTEXITCODE -ne 0) {
        throw 'npm install failed. If permission error, try running as Administrator.'
    }

    Refresh-SessionPath

    if (Test-CommandExists 'claude') {
        $ccVer = (claude --version 2>$null)
        Write-Ok "Claude Code $ccVer installed"
    } else {
        Write-Ok 'Package installed. Reopen terminal for claude to appear on PATH.'
    }
}
