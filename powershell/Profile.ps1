# IT Admin PowerShell Profile
# Deployed by bootstrap — edit in the dotfiles repo, not here.

# --- Quick aliases -----------------------------------------------------------

Set-Alias -Name np -Value 'C:\Program Files\Notepad++\notepad++.exe' -ErrorAction SilentlyContinue
Set-Alias -Name cc -Value claude -ErrorAction SilentlyContinue

# --- IT helper functions -----------------------------------------------------

function sysinfo {
    <# Quick system summary #>
    $os   = Get-CimInstance Win32_OperatingSystem
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $ram  = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $free = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $up   = (Get-Date) - $os.LastBootUpTime

    [PSCustomObject]@{
        Computer = $env:COMPUTERNAME
        OS       = $os.Caption
        Build    = $os.BuildNumber
        CPU      = $cpu.Name
        'RAM (GB)'  = "$free free / $ram total"
        Uptime   = '{0}d {1}h {2}m' -f $up.Days, $up.Hours, $up.Minutes
    } | Format-List
}

function diskcheck {
    <# Show volumes over a usage threshold #>
    param([int]$ThresholdPercent = 85)
    Get-Volume | Where-Object {
        $_.DriveLetter -and $_.Size -gt 0
    } | ForEach-Object {
        $usedPct = [math]::Round((($_.Size - $_.SizeRemaining) / $_.Size) * 100, 1)
        $flag = if ($usedPct -ge $ThresholdPercent) { ' ** WARNING **' } else { '' }
        [PSCustomObject]@{
            Drive     = "$($_.DriveLetter):"
            Label     = $_.FileSystemLabel
            'Size GB' = [math]::Round($_.Size / 1GB, 1)
            'Free GB' = [math]::Round($_.SizeRemaining / 1GB, 1)
            'Used %'  = "$usedPct%$flag"
        }
    } | Format-Table -AutoSize
}

function netcheck {
    <# Quick network connectivity test #>
    $tests = @(
        @{ Name = 'Gateway';  Target = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop }
        @{ Name = 'DNS';      Target = '8.8.8.8' }
        @{ Name = 'Internet'; Target = 'www.google.com' }
    )
    foreach ($t in $tests) {
        if (-not $t.Target) {
            Write-Host "  $($t.Name): no target found" -ForegroundColor Yellow
            continue
        }
        $result = Test-Connection -ComputerName $t.Target -Count 1 -Quiet -ErrorAction SilentlyContinue
        $color  = if ($result) { 'Green' } else { 'Red' }
        $status = if ($result) { 'OK' } else { 'FAIL' }
        Write-Host "  $($t.Name) ($($t.Target)): $status" -ForegroundColor $color
    }
}

function services {
    <# Show stopped services that are set to auto-start #>
    Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } |
        Select-Object Name, DisplayName, Status | Format-Table -AutoSize
}

function updates {
    <# Check Windows Update status (requires PSWindowsUpdate or built-in) #>
    if (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue) {
        Get-WindowsUpdate
    } else {
        Write-Host '  Checking via Windows Update COM...' -ForegroundColor Gray
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $results = $searcher.Search('IsInstalled=0')
        if ($results.Updates.Count -eq 0) {
            Write-Host '  No pending updates.' -ForegroundColor Green
        } else {
            Write-Host "  $($results.Updates.Count) update(s) pending:" -ForegroundColor Yellow
            $results.Updates | ForEach-Object { Write-Host "    - $($_.Title)" }
        }
    }
}

function defender {
    <# Quick Windows Defender status #>
    $status = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if (-not $status) {
        Write-Host '  Could not query Defender status.' -ForegroundColor Yellow
        return
    }
    [PSCustomObject]@{
        'Real-time Protection' = $status.RealTimeProtectionEnabled
        'Definitions Age'     = "$([math]::Round(((Get-Date) - $status.AntivirusSignatureLastUpdated).TotalHours, 1)) hours"
        'Last Scan'           = $status.FullScanEndTime
        'Quick Scan'          = $status.QuickScanEndTime
    } | Format-List
}

# --- Prompt ------------------------------------------------------------------

function prompt {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $prefix = if ($isAdmin) { '[ADMIN] ' } else { '' }
    "$prefix$env:COMPUTERNAME $(Get-Location)> "
}

# --- Bootstrap marker --------------------------------------------------------

Write-Host "IT Profile loaded. Helpers: sysinfo, diskcheck, netcheck, services, updates, defender" -ForegroundColor DarkGray
