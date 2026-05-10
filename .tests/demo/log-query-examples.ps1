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

function New-DemoEventLog {
    param([string]$LogName, [string]$Date, [int]$Count = 10)
    $day = $Date -replace '-', '/'
    1..$Count | ForEach-Object {
        $level = @("Information","Information","Information","Warning","Error") | Get-Random
        $src = @("ServiceControl","User32","Kernel-General","DCOM","Microsoft-Windows-WinRM","EventLog") | Get-Random
        $id = @(1000, 1001, 4625, 7036, 1074, 6005, 6008, 41, 13) | Get-Random
        $msgs = @{
            1000 = "Application hang detected"
            1001 = "Windows Error Reporting fault bucket"
            4625 = "An account failed to log on"
            7036 = "Service entered running state"
            1074 = "System restart requested"
            6005 = "Event log service started"
            6008 = "Previous system shutdown was unexpected"
            41   = "System rebooted without clean shutdown"
            13   = "Volume shadow copy failed"
        }
        [PSCustomObject]@{
            TimeCreated = (Get-Date).AddMinutes(-(Get-Random -Max 1440)).ToString("yyyy-MM-dd HH:mm:ss")
            LevelDisplayName = $level
            Id = $id
            ProviderName = $src
            Message = $msgs[$id]
        }
    } | New-BucketObject -Bucket "logs/eventlog/$LogName/$day" -AsTimestamp -AsJson -Compress -Quiet
}

# Clean previous run
Remove-Bucket "logs" -Recurse -Force -Confirm:$false -Quiet -ErrorAction SilentlyContinue

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

# Seed eventlog data across all 3 days
foreach ($d in $dates) {
    New-DemoEventLog -LogName "System" -Date ($d -replace '/', '-') -Count 15
    New-DemoEventLog -LogName "Application" -Date ($d -replace '/', '-') -Count 10
    New-DemoEventLog -LogName "Security" -Date ($d -replace '/', '-') -Count 8
}

Write-Host "`nDemo data seeded.`n" -ForegroundColor Green

$todayStr = $today.ToString("yyyy/MM/dd")
$yesterday = $today.AddDays(-1).ToString("yyyy/MM/dd")
$twoDaysAgo = $today.AddDays(-2).ToString("yyyy/MM/dd")
$ym = $today.ToString("yyyy/MM")

# ---------- 1. Tree view ----------

Write-Host "═══ 1. Tree view  ═══════════════════════════════════════" -ForegroundColor Cyan
Get-Bucket -Tree -Depth 4 logs
Write-Host ""

# ---------- 2. Recent entries from a host ----------

Write-Host "═══ 2. Last 10 entries from web01  ═════════════════════" -ForegroundColor Cyan
Get-BucketObject -Bucket "logs/syslog/web01/*" -Recurse -First 10 |
    Select-Object Severity, Tag, Message | Format-Table -AutoSize | Out-Host

# ---------- 3. Errors from all hosts (last 2 days) ----------

Write-Host "═══ 3. Errors+criticals, all hosts ($yesterday)  ═══════" -ForegroundColor Cyan
Get-BucketObject -Bucket "logs/syslog/*/$yesterday" -Recurse -Filter { $_.Severity -in @("err","crit") } |
    Select-Object Hostname, Severity, Tag, Message | Format-Table -AutoSize | Out-Host

# ---------- 4. Event count by host (today) ----------

Write-Host "═══ 4. Event count by host (today)  ════════════════════" -ForegroundColor Cyan
Get-BucketObject -Bucket "logs/syslog/*/$todayStr" -Recurse |
    Group-Object Hostname | Select-Object @{N="Host";E="Name"}, Count |
    Format-Table -AutoSize | Out-Host

# ---------- 5. Specific service (sshd) events ----------

Write-Host "═══ 5. sshd events on db01  ════════════════════════════" -ForegroundColor Cyan
Get-BucketObject -Bucket "logs/syslog/db01/*" -Recurse -Filter { $_.Tag -eq "sshd" } |
    Select-Object Severity, @{N="Msg";E={$_.Message.Substring(0,[Math]::Min(50,$_.Message.Length))}} |
    Format-Table -AutoSize | Out-Host

# ---------- 6. Date range with wildcards ----------

Write-Host "═══ 6. First 5 entries from the day before yesterday  ══" -ForegroundColor Cyan
Get-BucketObject -Bucket "logs/syslog/web01/$twoDaysAgo" -First 5 |
    Select-Object Severity, Tag, Message | Format-Table -AutoSize | Out-Host

# ---------- 7. Pagination ----------

Write-Host "═══ 7. Paginate: skip 3, take 5 from db01  ═════════════" -ForegroundColor Cyan
Get-BucketObject -Bucket "logs/syslog/db01/$todayStr" -Skip 3 -First 5 |
    Select-Object Severity, Tag, Message | Format-Table -AutoSize | Out-Host

# ---------- 8. EventLog by level (today) ----------

Write-Host "═══ 8. EventLog System errors+ (today)  ════════════════" -ForegroundColor Cyan
Get-BucketObject -Bucket "logs/eventlog/System/$todayStr" -Filter { $_.LevelDisplayName -in @("Error","Warning") } |
    Select-Object @{N="Id";E="Id"}, ProviderName, @{N="Msg";E={$_.Message.Substring(0,[Math]::Min(50,$_.Message.Length))}} |
    Format-Table -AutoSize | Out-Host

# ---------- 9. EventLog count by source ----------

Write-Host "═══ 9. EventLog Application — count by source  ════════" -ForegroundColor Cyan
Get-BucketObject -Bucket "logs/eventlog/Application/$todayStr" |
    Group-Object ProviderName | Select-Object @{N="Source";E="Name"}, Count |
    Sort-Object Count -Descending | Format-Table -AutoSize | Out-Host

# ---------- 10. Cross-bucket — all criticals across syslog+eventlog ----------

Write-Host "═══ 10. All critical/Error events (syslog+eventlog)  ═══" -ForegroundColor Cyan
Write-Host "  syslog critical:" -ForegroundColor DarkGray
Get-BucketObject -Bucket "logs/syslog/*/*" -Recurse -Filter { $_.Severity -eq "crit" } -First 5 |
    Select-Object @{N="Source";E={"syslog"}}, Hostname, Message |
    Format-Table -AutoSize | Out-Host
Write-Host "  eventlog errors:" -ForegroundColor DarkGray
Get-BucketObject -Bucket "logs/eventlog/*/$todayStr" -Filter { $_.LevelDisplayName -eq "Error" } -First 5 |
    Select-Object @{N="Source";E={$_.ProviderName}}, @{N="Host";E={"localhost"}}, @{N="Message";E={$_.Message}} |
    Format-Table -AutoSize | Out-Host

# ---------- 11. Export both to CSV ----------

Write-Host "═══ 11. Export errors to CSV  ══════════════════════════" -ForegroundColor Cyan
$tmpExport = Join-Path ([System.IO.Path]::GetTempPath()) "all-errors.csv"
Get-BucketObject -Bucket "logs/*/*/*" -Recurse -Filter { $_.Severity -in @("err","crit") -or $_.LevelDisplayName -eq "Error" } |
    Select-Object * | Export-Csv -Path $tmpExport -NoTypeInformation
Write-Host "  Exported $((Import-Csv $tmpExport).Count) rows → $tmpExport" -ForegroundColor DarkGray
Write-Host ""

# ---------- 12. Rotation (dry run) ----------

Write-Host "═══ 12. Rotation preview (syslog+eventlog)  ════════════" -ForegroundColor Cyan
Write-Host "  syslog:" -ForegroundColor DarkGray
Remove-Bucket -Bucket "logs/syslog/*/$twoDaysAgo" -Recurse -WhatIf 2>&1 | Out-Host
Write-Host "  eventlog:" -ForegroundColor DarkGray
Remove-Bucket -Bucket "logs/eventlog/*/$twoDaysAgo" -Recurse -WhatIf 2>&1 | Out-Host
Write-Host ""

Write-Host "All query patterns completed." -ForegroundColor Green
