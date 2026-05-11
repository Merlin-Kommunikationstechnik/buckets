#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Performance comparison: Buckets storage vs CliXML export/import.
.DESCRIPTION
    Uses the sysadmin dataset from data.ps1 and benchmarks write/read
    throughput for Buckets (binary + JSON), plain JSON (Depth 2 + 20),
    and CliXML formats.
#>

[CmdletBinding()]
param()

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

$testRoot = Join-Path $env:TEMP "buckets-perfcomp-$(Get-Random)"
Set-BucketRoot $testRoot

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

function Clear-PhaseBuckets {
    $createdBuckets.Clear()
    foreach ($key in $dataKeys) {
        Use-Bucket $bucketMap[$key]
    }
}

Write-InfoBlock -Mode top

# Temp dir prep
if (Test-Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

# Bucket mapping: data key -> bucket name
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

$dataKeys = $bucketMap.Keys

# Load dataset
Write-Host "Loading dataset..." -ForegroundColor DarkGray
$data = & "$PSScriptRoot/data.ps1" -Quiet -PassThru

$totalObjects = 0
foreach ($key in $dataKeys) { $totalObjects += $data[$key].Count }
Write-Host "  $totalObjects objects across $($bucketMap.Count) buckets" -ForegroundColor DarkGray

function Write-BucketsPhase {
    param([bool]$AsJson, [string]$Label)
    Clear-PhaseBuckets
    $wt = [System.Diagnostics.Stopwatch]::StartNew()
    $jsonFlag = if ($AsJson) { @{ AsJson = $true } } else { @{} }
    foreach ($key in $dataKeys) {
        $bucket = $bucketMap[$key]
        $objects = $data[$key]
        if ($key -eq "incidents") {
            $objects | New-BucketObject -Bucket $bucket -AsTimestamp -Quiet @jsonFlag
        }
        else {
            $objects | New-BucketObject -Bucket $bucket -KeyProperty _Id -Quiet @jsonFlag
        }
    }
    $writeMs = $wt.ElapsedMilliseconds

    $rt = [System.Diagnostics.Stopwatch]::StartNew()
    $readCount = 0
    foreach ($key in $dataKeys) {
        $bucket = $bucketMap[$key]
        $objects = Get-BucketObject -Bucket $bucket
        $readCount += @($objects).Count
    }
    $readMs = $rt.ElapsedMilliseconds

    Write-Host "  Write: ${writeMs}ms  Read: ${readMs}ms ($readCount objects)" -ForegroundColor DarkGray
    return @{ WriteMs = $writeMs; ReadMs = $readMs }
}

function Write-FilePhase {
    param([string]$DirName, [string]$Extension, [scriptblock]$Serialize, [scriptblock]$Deserialize, [string]$Label)
    $dir = Join-Path $tempRoot $DirName
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $wt = [System.Diagnostics.Stopwatch]::StartNew()
    $fileCount = 0
    foreach ($key in $dataKeys) {
        $bucket = $bucketMap[$key]
        $safeDir = $bucket -replace '[\\/:*?"<>|]', '_'
        $bucketDir = Join-Path $dir $safeDir
        New-Item -ItemType Directory -Path $bucketDir -Force | Out-Null
        $objects = $data[$key]
        $i = 0
        foreach ($obj in $objects) {
            $i++
            $file = Join-Path $bucketDir "$i$Extension"
            & $Serialize $obj $file
            $fileCount++
        }
    }
    $writeMs = $wt.ElapsedMilliseconds

    $rt = [System.Diagnostics.Stopwatch]::StartNew()
    $readCount = 0
    $files = Get-ChildItem -Path $dir -Recurse -Filter "*$Extension" -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        & $Deserialize $f.FullName | Out-Null
        $readCount++
    }
    $readMs = $rt.ElapsedMilliseconds

    Write-Host "  Write: ${writeMs}ms  Read: ${readMs}ms ($readCount files)" -ForegroundColor DarkGray
    return @{ WriteMs = $writeMs; ReadMs = $readMs }
}

# ============================================================
# 1. Buckets (Binary)
# ============================================================
Write-Host "`n[1] Buckets (Binary)" -ForegroundColor Blue
$bin = Write-BucketsPhase -AsJson:$false -Label "Buckets Binary"

# ============================================================
# 2. Buckets (JSON)
# ============================================================
Write-Host "`n[2] Buckets (JSON)" -ForegroundColor Blue
$json = Write-BucketsPhase -AsJson:$true -Label "Buckets JSON"

# ============================================================
# 3. Plain JSON
# ============================================================
Write-Host "`n[3] Plain JSON" -ForegroundColor Blue

$pj2 = Write-FilePhase -DirName "json-d2" -Extension ".json" `
    -Serialize { param($o, $f) [System.IO.File]::WriteAllText($f, ($o | ConvertTo-Json -Depth 2 -Compress), [System.Text.Encoding]::UTF8) } `
    -Deserialize { param($p) [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) | ConvertFrom-Json }

$pj20 = Write-FilePhase -DirName "json-d20" -Extension ".json" `
    -Serialize { param($o, $f) [System.IO.File]::WriteAllText($f, ($o | ConvertTo-Json -Depth 20 -Compress), [System.Text.Encoding]::UTF8) } `
    -Deserialize { param($p) [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) | ConvertFrom-Json }

Write-Host "  Depth 2:  Write: $($pj2.WriteMs)ms  Read: $($pj2.ReadMs)ms" -ForegroundColor DarkGray
Write-Host "  Depth 20: Write: $($pj20.WriteMs)ms  Read: $($pj20.ReadMs)ms" -ForegroundColor DarkGray

# ============================================================
# 4. CliXML
# ============================================================
Write-Host "`n[4] CliXML" -ForegroundColor Blue
$clixml = Write-FilePhase -DirName "clixml" -Extension ".clixml" `
    -Serialize { param($o, $f) $o | Export-CliXml -Path $f } `
    -Deserialize { param($p) Import-CliXml -Path $p }

# ============================================================
# Comparison
# ============================================================
Write-Host "`n[Comparison]" -ForegroundColor Blue

Write-Host ("  {0,-18}  {1,8}  {2,8}" -f "System", "Write", "Read") -ForegroundColor DarkGray
Write-Host ("  {0,-18}  {1,8}ms  {2,8}ms" -f "Buckets (Bin)", $bin.WriteMs, $bin.ReadMs) -ForegroundColor DarkGray
Write-Host ("  {0,-18}  {1,8}ms  {2,8}ms" -f "Buckets (JSON)", $json.WriteMs, $json.ReadMs) -ForegroundColor DarkGray
Write-Host ("  {0,-18}  {1,8}ms  {2,8}ms" -f "Plain JSON (D2)", $pj2.WriteMs, $pj2.ReadMs) -ForegroundColor DarkGray
Write-Host ("  {0,-18}  {1,8}ms  {2,8}ms" -f "Plain JSON (D20)", $pj20.WriteMs, $pj20.ReadMs) -ForegroundColor DarkGray
Write-Host ("  {0,-18}  {1,8}ms  {2,8}ms" -f "CliXML", $clixml.WriteMs, $clixml.ReadMs) -ForegroundColor DarkGray

# Cleanup
foreach ($b in $createdBuckets) {
    Remove-Bucket $b -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
}
Set-BucketRoot (Join-Path $HOME ".buckets")
Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-InfoBlock -Mode bottom
