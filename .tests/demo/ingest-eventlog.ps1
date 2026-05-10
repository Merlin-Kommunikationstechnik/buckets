#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Ingests Windows Event Log entries into Buckets as structured JSON objects.
.DESCRIPTION
    Polls a Windows Event Log for recent entries and stores each event as
    a compressed JSON object under logs/eventlog/<LogName>/yyyy/MM/dd/.

    Usage:  .tests/demo/ingest-eventlog.ps1 -LogName System -Hours 24
.PARAMETER LogName
    Event log to read (e.g. System, Application, Security). Default: System.
.PARAMETER Hours
    How far back to look. Default: 1.
.PARAMETER Path
    Buckets storage path. Default: $HOME/.buckets.
#>

param(
    [string]$LogName = "System",
    [int]$Hours = 1,
    [string]$Path
)

$ErrorActionPreference = "Stop"

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../../Buckets" -Force

$filterArgs = @{LogName = $LogName; StartTime = (Get-Date).AddHours(-$Hours)}
$day = (Get-Date).ToString("yyyy/MM/dd")
$bucketArgs = @{
    Bucket      = "logs/eventlog/$LogName/$day"
    AsTimestamp = $true
    AsJson      = $true
    Compress    = $true
    Quiet       = $true
}
if ($Path) { $bucketArgs.Path = $Path }

Get-WinEvent -FilterHashtable $filterArgs -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, LevelDisplayName, Id, ProviderName, Message |
    New-BucketObject @bucketArgs
