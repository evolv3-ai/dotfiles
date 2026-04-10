#Requires -Version 5.1
<#
.SYNOPSIS
    Network connectivity diagnostics for IT-managed endpoints.

.DESCRIPTION
    Tests gateway, DNS resolution, internet connectivity, and
    optionally a list of business-critical endpoints.

.PARAMETER Endpoints
    Additional hostnames/IPs to test beyond the defaults.

.PARAMETER Port
    TCP port to test for custom endpoints. Default: 443.
#>
[CmdletBinding()]
param(
    [string[]]$Endpoints = @(),
    [int]$Port = 443
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Target {
    param([string]$Name, [string]$Target, [string]$Type = 'ICMP')

    $result = @{ Name = $Name; Target = $Target; Type = $Type; Status = 'FAIL'; Detail = '' }

    try {
        switch ($Type) {
            'ICMP' {
                $ping = Test-Connection -ComputerName $Target -Count 2 -Quiet -ErrorAction Stop
                if ($ping) {
                    $latency = (Test-Connection -ComputerName $Target -Count 1 -ErrorAction Stop).ResponseTime
                    $result.Status = 'OK'
                    $result.Detail = "${latency}ms"
                }
            }
            'DNS' {
                $resolved = Resolve-DnsName -Name $Target -ErrorAction Stop | Select-Object -First 1
                $result.Status = 'OK'
                $result.Detail = $resolved.IPAddress
            }
            'TCP' {
                $tcp = Test-NetConnection -ComputerName $Target -Port $Port -WarningAction SilentlyContinue
                if ($tcp.TcpTestSucceeded) {
                    $result.Status = 'OK'
                    $result.Detail = "port $Port open"
                } else {
                    $result.Detail = "port $Port closed"
                }
            }
        }
    } catch {
        $result.Detail = $_.Exception.Message
    }

    return $result
}

# --- Run tests --------------------------------------------------------------

Write-Host "`n:: Network Connectivity Test`n" -ForegroundColor Cyan

$gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Select-Object -First 1).NextHop

$dns = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.ServerAddresses } | Select-Object -First 1).ServerAddresses[0]

$tests = @()

# Gateway
if ($gateway) {
    $tests += Test-Target -Name 'Default Gateway' -Target $gateway -Type ICMP
} else {
    $tests += @{ Name = 'Default Gateway'; Target = '-'; Status = 'FAIL'; Detail = 'No route found'; Type = 'ICMP' }
}

# DNS server
if ($dns) {
    $tests += Test-Target -Name 'DNS Server' -Target $dns -Type ICMP
}

# DNS resolution
$tests += Test-Target -Name 'DNS Resolution' -Target 'www.google.com' -Type DNS

# Internet (ICMP)
$tests += Test-Target -Name 'Internet (ICMP)' -Target '8.8.8.8' -Type ICMP

# Internet (HTTPS)
$tests += Test-Target -Name 'Internet (HTTPS)' -Target 'www.google.com' -Type TCP

# Windows Update
$tests += Test-Target -Name 'Windows Update' -Target 'windowsupdate.microsoft.com' -Type DNS

# npm registry (needed for Claude Code updates)
$tests += Test-Target -Name 'npm Registry' -Target 'registry.npmjs.org' -Type TCP

# Custom endpoints
foreach ($ep in $Endpoints) {
    $tests += Test-Target -Name "Custom: $ep" -Target $ep -Type TCP
}

# --- Display ----------------------------------------------------------------

foreach ($t in $tests) {
    $color = if ($t.Status -eq 'OK') { 'Green' } else { 'Red' }
    $line  = '   {0,-25} {1,-8} {2}' -f $t.Name, $t.Status, $t.Detail
    Write-Host $line -ForegroundColor $color
}

$failed = ($tests | Where-Object { $_.Status -ne 'OK' }).Count
Write-Host ''
if ($failed -eq 0) {
    Write-Host '   All tests passed.' -ForegroundColor Green
} else {
    Write-Host "   $failed test(s) failed." -ForegroundColor Red
}
Write-Host ''
