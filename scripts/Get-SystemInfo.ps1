#Requires -Version 5.1
<#
.SYNOPSIS
    Collect hardware/software inventory and save as JSON.

.DESCRIPTION
    Gathers OS, CPU, RAM, disks, network adapters, installed software,
    and Defender status. Saves to ~/.claude/inventory/<COMPUTERNAME>.json
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '   Gathering system information...' -ForegroundColor Gray

# --- Collect ----------------------------------------------------------------

$os  = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$bios = Get-CimInstance Win32_BIOS

$disks = Get-Volume | Where-Object { $_.DriveLetter -and $_.Size -gt 0 } | ForEach-Object {
    @{
        Drive     = "$($_.DriveLetter):"
        Label     = $_.FileSystemLabel
        SizeGB    = [math]::Round($_.Size / 1GB, 1)
        FreeGB    = [math]::Round($_.SizeRemaining / 1GB, 1)
        UsedPct   = [math]::Round((($_.Size - $_.SizeRemaining) / $_.Size) * 100, 1)
    }
}

$netAdapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
    $ipConfig = Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    @{
        Name       = $_.Name
        Status     = $_.Status.ToString()
        MAC        = $_.MacAddress
        Speed      = "$([math]::Round($_.LinkSpeed / 1e6, 0)) Mbps"
        IPv4       = ($ipConfig | Select-Object -ExpandProperty IPAddress -ErrorAction SilentlyContinue) -join ', '
    }
}

$defender = $null
try {
    $mpStatus = Get-MpComputerStatus -ErrorAction Stop
    $defender = @{
        RealTimeProtection = $mpStatus.RealTimeProtectionEnabled
        DefinitionsUpdated = $mpStatus.AntivirusSignatureLastUpdated.ToString('o')
        LastFullScan       = if ($mpStatus.FullScanEndTime) { $mpStatus.FullScanEndTime.ToString('o') } else { $null }
        LastQuickScan      = if ($mpStatus.QuickScanEndTime) { $mpStatus.QuickScanEndTime.ToString('o') } else { $null }
    }
} catch {
    $defender = @{ Error = 'Could not query Defender' }
}

# Installed winget packages (fast, no full registry scan)
$wingetApps = @()
try {
    $raw = winget list --accept-source-agreements 2>$null
    # Skip header lines, grab package names
    $wingetApps = ($raw | Select-Object -Skip 2 | Where-Object { $_ -match '\S' }) |
        ForEach-Object { ($_ -split '\s{2,}')[0].Trim() } |
        Where-Object { $_ -and $_ -ne 'Name' }
} catch {}

$inventory = @{
    CollectedAt = (Get-Date).ToString('o')
    Computer    = $env:COMPUTERNAME
    Domain      = $env:USERDOMAIN
    User        = $env:USERNAME
    OS          = @{
        Caption = $os.Caption
        Version = $os.Version
        Build   = $os.BuildNumber
        Arch    = $env:PROCESSOR_ARCHITECTURE
    }
    BIOS        = @{
        Manufacturer = $bios.Manufacturer
        SerialNumber = $bios.SerialNumber
    }
    CPU         = @{
        Name   = $cpu.Name.Trim()
        Cores  = $cpu.NumberOfCores
        Threads = $cpu.NumberOfLogicalProcessors
    }
    RAM         = @{
        TotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        FreeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    }
    Disks       = $disks
    Network     = $netAdapters
    Defender    = $defender
    Software    = $wingetApps
}

# --- Save -------------------------------------------------------------------

$outDir = Join-Path $env:USERPROFILE '.claude\inventory'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$outFile = Join-Path $outDir "$($env:COMPUTERNAME).json"
$inventory | ConvertTo-Json -Depth 5 | Set-Content -Path $outFile -Encoding utf8

Write-Host "   OK  Inventory saved to $outFile" -ForegroundColor Green

# --- Summary to console -----------------------------------------------------

Write-Host ''
Write-Host "   Machine  : $($env:COMPUTERNAME)" -ForegroundColor White
Write-Host "   OS       : $($os.Caption) (build $($os.BuildNumber))"
Write-Host "   CPU      : $($cpu.Name.Trim())"
Write-Host "   RAM      : $([math]::Round($os.FreePhysicalMemory / 1MB, 1)) GB free / $([math]::Round($os.TotalVisibleMemorySize / 1MB, 1)) GB total"
Write-Host "   Disks    : $($disks.Count) volume(s)"
Write-Host "   Adapters : $($netAdapters.Count) physical"
Write-Host "   Software : $($wingetApps.Count) packages"
Write-Host ''
