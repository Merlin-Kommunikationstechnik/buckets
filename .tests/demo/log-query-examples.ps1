#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Demonstrates query and management patterns against Buckets' syslog/eventlog log buckets.
.DESCRIPTION
    Seeds demo log data across multiple hosts/dates, then runs through query patterns
    including date-range wildcards, severity filtering, tree view, and rotation.

    Usage:  .tests/demo/log-query-examples.ps1
#>

$ErrorActionPreference = "Stop"

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../../Buckets" -Force

# ---------- seed demo data ----------

function New-DemoLog {
    param([string]$Hostname, [string]$Date, [int]$Count = 20)
    $day = $Date -replace '-', '/'
    1..$Count | ForEach-Object {
        $sev = @("info","info","info","info","notice","warning","err","crit") | Get-Random
        $msg = @(
            "Connection pool resized to 32"
            "Disk usage at 67% on /dev/sda1"
            "User session expired for uid=1003"
            "DNS query timeout for ns1.example.com"
            "Certificate renewal scheduled in 14 days"
            "Heartbeat OK from replica 3"
            "Failed password attempt for root from 10.0.0.45"
            "Interface eth0 link up at 1 Gbps"
            "OOM killer invoked for PID 4512"
            "NTP offset +2.3ms to pool.ntp.org"
        ) | Get-Random
        $tag = @("sshd","nginx","kernel","systemd","dockerd","chronyd") | Get-Random
        [PSCustomObject]@{
            Timestamp = "$(Get-Date -Format 'MMM dd HH:mm:ss')"
            Hostname  = $Hostname
            Facility  = @("daemon","auth","syslog","user") | Get-Random
            Severity  = $sev
            Tag       = $tag
            Message   = $msg
        }
    } | New-BucketObject -Bucket "logs/syslog/$Hostname/$day" -AsTimestamp -AsJson -Compress -Quiet
}

$hosts = @("web01", "web02", "db01", "lb01")

# Seed 3 days of data across all hosts
$today = (Get-Date)
$dates = @(
    $today.AddDays(-2).ToString("yyyy/MM/dd")
    $today.AddDays(-1).ToString("yyyy/MM/dd")
    $today.ToString("yyyy/MM/dd")
)

foreach ($h in $hosts) {
    foreach ($d in $dates) {
        $n = if ($h -eq "web01") { 40 } elseif ($h -eq "db01") { 10 } else { 20 }
        New-DemoLog -Hostname $h -Date ($d -replace '/', '-') -Count $n
    }
}

Write-Host "`nDemo data seeded.`n" -ForegroundColor Green

# ---------- 1. Tree view ----------

Write-Host "1) Tree view of log structure" -ForegroundColor Cyan
Get-Bucket -Tree -Depth 4 logs
Write-Host ""

# ---------- 2. Recent entries from a host ----------

Write-Host "2) Last 10 entries from web01" -ForegroundColor Cyan
Get-BucketObject -Bucket "logs/syslog/web01/*" -Recurse -First 10
Write-Host ""

# ---------- 3. Errors from all hosts (last 2 days) ----------

Write-Host "3) Errors and criticals from all hosts (last 2 days)" -ForegroundColor Cyan
$yesterday = $today.AddDays(-1).ToString("yyyy/MM/dd")
Get-BucketObject -Bucket "logs/syslog/*/$yesterday" -Recurse -Filter { $_.Severity -in @("err","crit") }
Write-Host ""

# ---------- 4. Events by host with count ----------

Write-Host "4) Event count by host (today)" -ForegroundColor Cyan
$todayStr = $today.ToString("yyyy/MM/dd")
Get-BucketObject -Bucket "logs/syslog/*/$todayStr" -Recurse |
    Group-Object Hostname | Select-Object Name, Count
Write-Host ""

# ---------- 5. Specific service (sshd) events ----------

Write-Host "5) sshd events on db01" -ForegroundColor Cyan
Get-BucketObject -Bucket "logs/syslog/db01/*" -Recurse -Filter { $_.Tag -eq "sshd" }
Write-Host ""

# ---------- 6. Date range with wildcards ----------

Write-Host "6) Entries from first 2 days of this month" -ForegroundColor Cyan
$ym = $today.ToString("yyyy/MM")
Get-BucketObject -Bucket "logs/syslog/web01/$ym/0*" -Recurse -First 10
Write-Host ""

# ---------- 7. Pagination ----------

Write-Host "7) Paginate: skip 10, take 5 from db01 today" -ForegroundColor Cyan
Get-BucketObject -Bucket "logs/syslog/db01/$todayStr" -Skip 10 -First 5
Write-Host ""

# ---------- 8. Stats ----------

Write-Host "8) Bucket stats" -ForegroundColor Cyan
Get-BucketStats -Bucket logs/syslog | Select-Object Name, ObjectCount, TotalSize, OldestObject
Write-Host ""

# ---------- 9. Cross-bucket query ----------

Write-Host "9) All critical events across all log buckets" -ForegroundColor Cyan
Get-BucketObject -Bucket "logs/syslog/*/*" -Recurse -Filter { $_.Severity -eq "crit" }
Write-Host ""

# ---------- 10. Export for analysis ----------

Write-Host "10) Export all errors to CSV for offline analysis" -ForegroundColor Cyan
$tmpExport = Join-Path ([System.IO.Path]::GetTempPath()) "syslog-errors.csv"
Get-BucketObject -Bucket "logs/syslog/*/*" -Recurse -Filter { $_.Severity -in @("err","crit") } |
    Export-Csv -Path $tmpExport -NoTypeInformation
Write-Host "    Exported to $tmpExport"
Write-Host ""

# ---------- 11. Rotation (dry run) ----------

Write-Host "11) Rotation preview: remove 2-day-old data" -ForegroundColor Cyan
$twoDaysAgo = $today.AddDays(-2).ToString("yyyy/MM/dd")
Remove-Bucket -Bucket "logs/syslog/*/$twoDaysAgo" -Recurse -WhatIf
Write-Host ""

Write-Host "All query patterns completed." -ForegroundColor Green
