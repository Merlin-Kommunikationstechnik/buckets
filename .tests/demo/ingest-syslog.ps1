#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Ingests syslog lines into Buckets as structured JSON objects (source+date partitioned).
.DESCRIPTION
    Accepts syslog lines via pipeline or file paths. Parses RFC 3164 format,
    extracts hostname, severity, facility, tag, and message, then stores each
    line as a compressed JSON object under logs/syslog/<hostname>/yyyy/MM/dd/.

    Pipeline usage:   Get-Content -Tail 0 -Wait /var/log/syslog | .tests/demo/ingest-syslog.ps1
    File usage:       .tests/demo/ingest-syslog.ps1 /var/log/syslog /var/log/auth.log
.PARAMETER Source
    Hostname or source identifier used when the line cannot be parsed or has no hostname.
#>

param([string]$Source = "generic")

$ErrorActionPreference = "Stop"

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../../Buckets" -Force

# RFC 3164 syslog: <PRI>timestamp hostname tag[PID]: message
$syslogRegex = [regex]::new('^<(\d+)>(\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+(\S+?)(?:\[(\d+)\])?:\s*(.*)$')

# PRI = facility * 8 + severity
$severityMap = @{
    0 = "emerg"; 1 = "alert"; 2 = "crit"; 3 = "err"
    4 = "warning"; 5 = "notice"; 6 = "info"; 7 = "debug"
}

$facilityMap = @{
    0  = "kern";   1  = "user";   2  = "mail";   3  = "daemon"
    4  = "auth";   5  = "syslog"; 6  = "lpr";    7  = "news"
    8  = "uucp";   9  = "cron";   10 = "authpriv"; 11 = "ftp"
    16 = "local0"; 17 = "local1"; 18 = "local2"; 19 = "local3"
    20 = "local4"; 21 = "local5"; 22 = "local6"; 23 = "local7"
}

function Ingest-Line {
    param([string]$Line, [string]$FallbackSource)
    if ([string]::IsNullOrWhiteSpace($Line)) { return }
    $day = (Get-Date).ToString("yyyy/MM/dd")
    $m = $syslogRegex.Match($Line)
    if ($m.Success) {
        $pri = [int]$m.Groups[1].Value
        $severity = $severityMap[[math]::Floor($pri % 8)]
        $facility = $facilityMap[[math]::Floor($pri / 8)]
        $hostname = $m.Groups[3].Value
        [PSCustomObject]@{
            Timestamp = $m.Groups[2].Value
            Hostname  = $hostname
            Facility  = $facility
            Severity  = $severity
            Tag       = $m.Groups[4].Value
            PID       = if ($m.Groups[5].Value) { [int]$m.Groups[5].Value } else { $null }
            Message   = $m.Groups[6].Value
            Raw       = $Line
        } | New-BucketObject -Bucket "logs/syslog/$hostname/$day" -AsTimestamp -AsBinary -Compress -Quiet
    } else {
        [PSCustomObject]@{
            Timestamp = (Get-Date -Format "MMM dd HH:mm:ss")
            Hostname  = $FallbackSource
            Facility  = "unknown"
            Severity  = "info"
            Tag       = "raw"
            PID       = $null
            Message   = $Line
            Raw       = $Line
        } | New-BucketObject -Bucket "logs/syslog/$FallbackSource/$day" -AsTimestamp -AsBinary -Compress -Quiet
    }
}

# Pipeline mode — process each line
if ($MyInvocation.ExpectingInput) {
    $input | ForEach-Object { Ingest-Line -Line $_ -FallbackSource $Source }
    return
}

# File mode — process each path argument
$paths = $args
if ($paths.Count -eq 0) {
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) [file1 file2 ...]" -ForegroundColor Yellow
    Write-Host "  or:   Get-Content -Tail 0 -Wait /var/log/syslog | $($MyInvocation.MyCommand.Name)" -ForegroundColor Yellow
    Write-Host "  or:   .\ingest-syslog.ps1 -Source <hostname> < file.log" -ForegroundColor Yellow
    return
}
foreach ($path in $paths) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $src = [System.IO.Path]::GetFileNameWithoutExtension($path)
        Get-Content -LiteralPath $path | ForEach-Object { Ingest-Line -Line $_ -FallbackSource $src }
    } else {
        Write-Warning "File not found: $path"
    }
}
