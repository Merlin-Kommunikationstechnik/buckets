#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Performance comparison: Buckets storage (JSON, Binary, Compressed, Funnel)
    vs plain JSON (Depth 2 + 20) vs CliXML, plus depth/truncation benchmarks.
#>

[CmdletBinding()]
param()

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-perfcomp-$(Get-Random)"
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
        Write-Host " - " -NoNewline -ForegroundColor DarkGray
        Write-Host $pwsh -NoNewline -ForegroundColor Cyan
        Write-Host " - " -NoNewline -ForegroundColor DarkGray
        Write-Host $os -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray
    }
    else {
        $elapsed = $sw.ElapsedMilliseconds
        $endTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host $sep -ForegroundColor DarkGray
        Write-Host " Done" -NoNewline -ForegroundColor Blue
        Write-Host " - ${elapsed}ms" -NoNewline -ForegroundColor Magenta
        Write-Host " - $endTs" -NoNewline -ForegroundColor DarkGray
        Write-Host " - " -NoNewline -ForegroundColor DarkGray
        Write-Host $pwsh -NoNewline -ForegroundColor Cyan
        Write-Host " - " -NoNewline -ForegroundColor DarkGray
        Write-Host $os -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray
    }
}

function Use-Bucket {
    param([string]$Name)
    $null = $createdBuckets.Add($Name)
    Remove-BucketObject -Bucket $Name -Drop -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
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
    param([switch]$AsBinary, [string]$Label, [string]$Funnel = "")
    Clear-PhaseBuckets
    $wt = [System.Diagnostics.Stopwatch]::StartNew()
    $binFlag = if ($AsBinary) { @{ AsBinary = $true } } else { @{} }
    $funnelFlag = if ($Funnel) { @{ Funnel = $Funnel } } else { @{} }
    foreach ($key in $dataKeys) {
        $bucket = $bucketMap[$key]
        $objects = $data[$key]
        if ($key -eq "incidents") {
            $objects | New-BucketObject -Bucket $bucket -AsTimestamp -Quiet @binFlag @funnelFlag
        }
        else {
            $objects | New-BucketObject -Bucket $bucket -KeyProperty _Id -Quiet @binFlag @funnelFlag
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
# 1. Buckets (JSON — default)
# ============================================================
Write-Host "`n[1] Buckets (JSON default)" -ForegroundColor Blue
$json = Write-BucketsPhase -AsBinary:$false -Label "Buckets JSON"

# ============================================================
# 2. Buckets (Binary)
# ============================================================
Write-Host "`n[2] Buckets (Binary -AsBinary)" -ForegroundColor Blue
$bin = Write-BucketsPhase -AsBinary -Label "Buckets Binary"

# ============================================================
# 3. Buckets (Binary + Compression)
# ============================================================
Write-Host "`n[3] Buckets (Compressed -AsBinary -Compress)" -ForegroundColor Blue
$comp = Write-BucketsPhase -AsBinary -Label "Buckets Compressed"

# ============================================================
# 4. Buckets (JSON + Funnel strip)
# ============================================================
Write-Host "`n[4] Buckets (JSON + funnel strip)" -ForegroundColor Blue
New-Funnel -Name "bench-perfcomp-strip" -Transform { [PSCustomObject]@{ _Id = $_.Id; Name = $_.Name; Value = $_.Value } } -Force -Quiet
$funnel = Write-BucketsPhase -AsBinary:$false -Funnel "bench-perfcomp-strip" -Label "Buckets Funnel"
Remove-Funnel -Name "bench-perfcomp-strip" -Quiet -Confirm:$false -ErrorAction SilentlyContinue

# ============================================================
# 5. Plain JSON (Depth 2 + 20)
# ============================================================
Write-Host "`n[5] Plain JSON" -ForegroundColor Blue

$pj2 = Write-FilePhase -DirName "json-d2" -Extension ".json" `
    -Serialize { param($o, $f) [System.IO.File]::WriteAllText($f, ($o | ConvertTo-Json -Depth 2 -Compress -WarningAction SilentlyContinue), [System.Text.Encoding]::UTF8) } `
    -Deserialize { param($p) [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) | ConvertFrom-Json }

$pj20 = Write-FilePhase -DirName "json-d20" -Extension ".json" `
    -Serialize { param($o, $f) [System.IO.File]::WriteAllText($f, ($o | ConvertTo-Json -Depth 20 -Compress -WarningAction SilentlyContinue), [System.Text.Encoding]::UTF8) } `
    -Deserialize { param($p) [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) | ConvertFrom-Json }

Write-Host "  Depth 2:  Write: $($pj2.WriteMs)ms  Read: $($pj2.ReadMs)ms" -ForegroundColor DarkGray
Write-Host "  Depth 20: Write: $($pj20.WriteMs)ms  Read: $($pj20.ReadMs)ms" -ForegroundColor DarkGray

# ============================================================
# 6. CliXML
# ============================================================
Write-Host "`n[6] CliXML" -ForegroundColor Blue
$clixml = Write-FilePhase -DirName "clixml" -Extension ".clixml" `
    -Serialize { param($o, $f) $o | Export-CliXml -Path $f } `
    -Deserialize { param($p) Import-CliXml -Path $p }

# ============================================================
# 7. Depth/truncation — DirectoryInfo across formats
# ============================================================
Write-Host "`n[7] Depth/truncation — DirectoryInfo @ Depth 1" -ForegroundColor Blue

$homeItems = @(Get-ChildItem $HOME -Force -ErrorAction SilentlyContinue)

# Buckets JSON
Use-Bucket "dt-json"
$dtJsonWt = [System.Diagnostics.Stopwatch]::StartNew()
$homeItems | New-BucketObject -Bucket dt-json -KeyProperty Name -Depth 1 -Quiet -WarningAction SilentlyContinue
$dtJsonWrite = $dtJsonWt.ElapsedMilliseconds
$dtJsonWt.Restart()
$dtJsonRead = Get-BucketObject -Bucket dt-json
$dtJsonReadMs = $dtJsonWt.ElapsedMilliseconds
$dtJsonFallbacks = @(Get-ChildItem -Path (Join-Path (Get-BucketRoot) "dt-json") -Filter *.dat -ErrorAction SilentlyContinue).Count
Write-Host "  Buckets JSON:  Write ${dtJsonWrite}ms  Read ${dtJsonReadMs}ms ($($dtJsonRead.Count) items, ${dtJsonFallbacks} fallbacks)" -ForegroundColor DarkGray

# Buckets Binary
Use-Bucket "dt-bin"
$dtBinWt = [System.Diagnostics.Stopwatch]::StartNew()
$homeItems | New-BucketObject -Bucket dt-bin -KeyProperty Name -AsBinary -Quiet
$dtBinWrite = $dtBinWt.ElapsedMilliseconds
$dtBinWt.Restart()
$dtBinRead = Get-BucketObject -Bucket dt-bin
$dtBinReadMs = $dtBinWt.ElapsedMilliseconds
Write-Host "  Buckets Binary: Write ${dtBinWrite}ms  Read ${dtBinReadMs}ms ($($dtBinRead.Count) items, full preservation)" -ForegroundColor DarkGray

# Plain JSON Depth 1
$pjDir = Join-Path $tempRoot "pj-dt1"
New-Item -ItemType Directory -Path $pjDir -Force | Out-Null
$dtPjWt = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($item in $homeItems) {
    $json = $item | ConvertTo-Json -Depth 1 -Compress -WarningAction SilentlyContinue
    $safeName = $item.Name -replace '[\\/:*?"<>|]', '_'
    [System.IO.File]::WriteAllText((Join-Path $pjDir "$safeName.json"), $json, [System.Text.Encoding]::UTF8)
}
$dtPjWrite = $dtPjWt.ElapsedMilliseconds
$dtPjWt.Restart()
$pjFiles = Get-ChildItem -Path $pjDir -Filter *.json
foreach ($f in $pjFiles) { $null = (Get-Content -Path $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json) }
$dtPjRead = $dtPjWt.ElapsedMilliseconds
Write-Host "  Plain JSON D1:  Write ${dtPjWrite}ms  Read ${dtPjRead}ms ($($pjFiles.Count) files)" -ForegroundColor DarkGray

# ============================================================
# Comparison
# ============================================================
Write-Host "`n[Comparison]" -ForegroundColor Blue

Write-Host ("  {0,-22}  {1,8}  {2,8}" -f "System", "Write", "Read") -ForegroundColor DarkGray
Write-Host ("  {0,-22}  {1,8}ms  {2,8}ms" -f "Buckets (JSON)", $json.WriteMs, $json.ReadMs) -ForegroundColor DarkGray
Write-Host ("  {0,-22}  {1,8}ms  {2,8}ms" -f "Buckets (Binary)", $bin.WriteMs, $bin.ReadMs) -ForegroundColor DarkGray
Write-Host ("  {0,-22}  {1,8}ms  {2,8}ms" -f "Buckets (Compressed)", $comp.WriteMs, $comp.ReadMs) -ForegroundColor DarkGray
Write-Host ("  {0,-22}  {1,8}ms  {2,8}ms" -f "Buckets (Funnel strip)", $funnel.WriteMs, $funnel.ReadMs) -ForegroundColor DarkGray
Write-Host ("  {0,-22}  {1,8}ms  {2,8}ms" -f "Plain JSON (D2)", $pj2.WriteMs, $pj2.ReadMs) -ForegroundColor DarkGray
Write-Host ("  {0,-22}  {1,8}ms  {2,8}ms" -f "Plain JSON (D20)", $pj20.WriteMs, $pj20.ReadMs) -ForegroundColor DarkGray
Write-Host ("  {0,-22}  {1,8}ms  {2,8}ms" -f "CliXML", $clixml.WriteMs, $clixml.ReadMs) -ForegroundColor DarkGray
Write-Host "  --- truncation ---" -ForegroundColor DarkGray
Write-Host ("  {0,-22}  {1,8}ms  {2,8}ms" -f "DirInfo @ Depth 1", $dtJsonWrite, $dtJsonReadMs) -ForegroundColor DarkGray

# Cleanup
foreach ($b in $createdBuckets) {
    Remove-BucketObject -Bucket $b -Drop -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
}
Get-Funnel -Name "bench-perfcomp-strip" -ErrorAction SilentlyContinue | Remove-Funnel -Name "bench-perfcomp-strip" -Quiet -Confirm:$false -ErrorAction SilentlyContinue

Set-BucketRoot (Join-Path $HOME ".buckets")
Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-InfoBlock -Mode bottom
