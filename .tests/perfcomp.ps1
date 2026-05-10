#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Performance comparison: Buckets storage vs CliXML export/import.
.DESCRIPTION
    Uses the sysadmin dataset from data.ps1 and benchmarks write/read
    throughput for both Buckets (default binary format) and CliXML.
#>

[CmdletBinding()]
param()

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$createdBuckets = [System.Collections.ArrayList]::new()
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-perf"

function Write-InfoBlock {
    param([string]$Mode)
    $mod = Get-Module Buckets
    $pwsh = "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    $os = if ($IsMacOS) { "macOS" } elseif ($IsLinux) { "Linux" } else { "Windows" }
    $sep = "=" * 52
    if ($Mode -eq "top") {
        Write-Host $sep -ForegroundColor DarkGray
        Write-Host " Buckets Module" -NoNewline -ForegroundColor Blue
        Write-Host " v$($mod.Version)" -NoNewline -ForegroundColor Magenta
        Write-Host " Perf Comparison" -ForegroundColor DarkGray
        Write-Host " $startTs" -NoNewline -ForegroundColor DarkGray
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host $pwsh -NoNewline -ForegroundColor Cyan
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host $os -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray
    }
    else {
        $elapsed = $sw.ElapsedMilliseconds
        $endTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host $sep -ForegroundColor DarkGray
        Write-Host " Done" -NoNewline -ForegroundColor Blue
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host "${elapsed}ms" -ForegroundColor Magenta
        Write-Host " $endTs" -NoNewline -ForegroundColor DarkGray
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host $pwsh -NoNewline -ForegroundColor Cyan
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host $os -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray
    }
}

function Use-Bucket {
    param([string]$Name)
    $null = $createdBuckets.Add($Name)
    Remove-Bucket $Name -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
}

Write-InfoBlock -Mode top

# Temp dir prep
if (Test-Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

# Bucket mapping: data key → bucket name
$bucketMap = [ordered]@{
    servers        = "infra/servers"
    services       = "infra/services"
    disks          = "infra/storage"
    backups        = "infra/backups"
    containers     = "infra/containers"
    incidents      = "infra/incidents"
    monChecks      = "infra/monitoring"
    scheduledTasks = "infra/scheduled"
    networks       = "network/vlans"
    interfaces     = "network/interfaces"
    dnsRecords     = "network/dns"
    firewall       = "network/firewall"
    adUsers        = "org/users"
    groups         = "org/groups"
    roles          = "org/roles"
    workstations   = "org/clients"
    sslCerts       = "security/certificates"
    auditLogs      = "security/audit"
    packages       = "ops/packages"
    configs        = "ops/configs"
}

# Load dataset
Write-Host "Loading dataset..." -ForegroundColor DarkGray
$data = & "$PSScriptRoot/data.ps1" -Quiet -PassThru

$dataKeys = $bucketMap.Keys
$totalObjects = 0
foreach ($key in $dataKeys) { $totalObjects += $data[$key].Count }
$totalBuckets = $bucketMap.Count

Write-Host "  $totalObjects objects across $totalBuckets buckets" -ForegroundColor DarkGray

# ============================================================
# 1. Buckets Write
# ============================================================
Write-Host "`n[1] Buckets Write" -ForegroundColor Blue

foreach ($key in $dataKeys) {
    Use-Bucket $bucketMap[$key]
}

$bw = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($key in $dataKeys) {
    $bucket = $bucketMap[$key]
    $objects = $data[$key]
    if ($key -eq "incidents") {
        $objects | New-BucketObject -Bucket $bucket -AsTimestamp -Quiet
    }
    else {
        $objects | New-BucketObject -Bucket $bucket -KeyProperty _Id -Quiet
    }
}
$bucketsWriteMs = $bw.ElapsedMilliseconds

Write-Host "  Write: ${bucketsWriteMs}ms" -ForegroundColor DarkGray

# ============================================================
# 2. Buckets Read
# ============================================================
Write-Host "`n[2] Buckets Read" -ForegroundColor Blue

$br = [System.Diagnostics.Stopwatch]::StartNew()
$bucketsReadCount = 0
foreach ($key in $dataKeys) {
    $bucket = $bucketMap[$key]
    $objects = Get-BucketObject -Bucket $bucket
    $bucketsReadCount += @($objects).Count
}
$bucketsReadMs = $br.ElapsedMilliseconds

Write-Host "  Read: ${bucketsReadMs}ms, Objects: $bucketsReadCount" -ForegroundColor DarkGray

# ============================================================
# 3. CliXML Write
# ============================================================
Write-Host "`n[3] CliXML Write" -ForegroundColor Blue

$cw = [System.Diagnostics.Stopwatch]::StartNew()
$clixmlCount = 0
foreach ($key in $dataKeys) {
    $bucket = $bucketMap[$key]
    $safeDir = $bucket -replace '[\\/:*?"<>|]', '_'
    $bucketDir = Join-Path $tempRoot $safeDir
    New-Item -ItemType Directory -Path $bucketDir -Force | Out-Null
    $objects = $data[$key]
    $i = 0
    foreach ($obj in $objects) {
        $i++
        $file = Join-Path $bucketDir "$i.clixml"
        $obj | Export-CliXml -Path $file
        $clixmlCount++
    }
}
$clixmlWriteMs = $cw.ElapsedMilliseconds

Write-Host "  Write: ${clixmlWriteMs}ms, Files: $clixmlCount" -ForegroundColor DarkGray

# ============================================================
# 4. CliXML Read
# ============================================================
Write-Host "`n[4] CliXML Read" -ForegroundColor Blue

$cr = [System.Diagnostics.Stopwatch]::StartNew()
$clixmlReadCount = 0
$clixmlFiles = Get-ChildItem -Path $tempRoot -Recurse -Filter *.clixml -ErrorAction SilentlyContinue
foreach ($f in $clixmlFiles) {
    Import-CliXml -Path $f.FullName | Out-Null
    $clixmlReadCount++
}
$clixmlReadMs = $cr.ElapsedMilliseconds

Write-Host "  Read: ${clixmlReadMs}ms, Objects: $clixmlReadCount" -ForegroundColor DarkGray

# ============================================================
# Comparison
# ============================================================
Write-Host "`n[Comparison]" -ForegroundColor Blue

$bRatioW = if ($clixmlWriteMs -gt 0) { "{0:N2}" -f ($bucketsWriteMs / $clixmlWriteMs) } else { "N/A" }
$bRatioR = if ($clixmlReadMs -gt 0) { "{0:N2}" -f ($bucketsReadMs / $clixmlReadMs) } else { "N/A" }

Write-Host ("  {0,-16}  {1,8}  {2,8}" -f "System", "Write", "Read") -ForegroundColor DarkGray
Write-Host ("  {0,-16}  {1,8}ms  {2,8}ms" -f "Buckets", $bucketsWriteMs, $bucketsReadMs) -ForegroundColor DarkGray
Write-Host ("  {0,-16}  {1,8}ms  {2,8}ms" -f "CliXML", $clixmlWriteMs, $clixmlReadMs) -ForegroundColor DarkGray
Write-Host ("  {0,-16}  {1,8}x  {2,8}x" -f "Ratio (B/C)", $bRatioW, $bRatioR) -ForegroundColor DarkGray

# Cleanup
foreach ($b in $createdBuckets) {
    Remove-Bucket $b -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
}
Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-InfoBlock -Mode bottom
