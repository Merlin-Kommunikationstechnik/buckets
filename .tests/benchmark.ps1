#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Performance benchmarks for the Buckets module.
.DESCRIPTION
    Measures write/read throughput for simple, complex, compressed, truncated,
    and funnel-processed objects in both JSON (default) and binary formats.
    Object counts are kept modest (1k) to stay fast — focus is on comparison
    between modes, not absolute scale.
#>

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-bench-$(Get-Random)"
Set-BucketRoot $testRoot

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$createdBuckets = [System.Collections.ArrayList]::new()

function Use-Bucket {
    param([string]$Name)
    $null = $createdBuckets.Add($Name)
    Remove-Bucket $Name -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet | Out-Null
}

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
        Write-Host " Benchmarks" -ForegroundColor DarkGray
        Write-Host " $startTs" -NoNewline -ForegroundColor DarkGray
        Write-Host " - " -NoNewline -ForegroundColor DarkGray
        Write-Host $pwsh -NoNewline -ForegroundColor Cyan
        Write-Host " - " -NoNewline -ForegroundColor DarkGray
        Write-Host $os -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray
    }
    else {
        $elapsed = $sw.ElapsedMilliseconds
        Write-Host $sep -ForegroundColor DarkGray
        Write-Host " Done" -NoNewline -ForegroundColor Blue
        Write-Host " - ${elapsed}ms" -NoNewline -ForegroundColor Magenta
        Write-Host " - " -NoNewline -ForegroundColor DarkGray
        Write-Host $pwsh -NoNewline -ForegroundColor Cyan
        Write-Host " - " -NoNewline -ForegroundColor DarkGray
        Write-Host $os -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray
    }
}

function Write-BenchResult {
    param([string]$Label, [int]$WriteMs, [int]$ReadMs, [int]$Count, [string]$Extra = "")
    $extraStr = if ($Extra) { "  $Extra" } else { "" }
    Write-Host ("  {0,-50} Write {1,5}ms  Read {2,5}ms  Obj: {3}{4}" -f $Label, $WriteMs, $ReadMs, $Count, $extraStr) -ForegroundColor DarkGray
    $script:phase++
    $pct = [math]::Min(100, [int](($script:phase / $script:totalPhases) * 100))
    Write-Progress -Activity "Buckets Benchmark" -Status "Phase $($script:phase)/$($script:totalPhases): $Label" -PercentComplete $pct
}

$N = 1000

$script:phase = 0
$script:totalPhases = 22

Write-InfoBlock -Mode top

# ============================================================
# 1-2. JSON (default format) — 1k simple + 1k complex
# ============================================================

Write-Host "[1] JSON default (${N} simple objects)" -ForegroundColor Blue
Use-Bucket "b1k"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
1..$N | ForEach-Object { [PSCustomObject]@{ Id = $_; Name = "item-$_"; Value = (Get-Random); Timestamp = [DateTimeOffset]::Now } } |
    New-BucketObject -Bucket b1k -KeyProperty Id -Quiet
$w = $wt.ElapsedMilliseconds
$wt.Restart()
$r = Get-BucketObject -Bucket b1k
Write-BenchResult "Simple" $w $wt.ElapsedMilliseconds $r.Count

Write-Host "`n[2] JSON default (${N} complex objects - nested)" -ForegroundColor Blue
Use-Bucket "b1kc"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
1..$N | ForEach-Object {
    [PSCustomObject]@{
        Id = $_
        Profile = [PSCustomObject]@{ Name = "User-$_"; Email = "user-$_@example.com"; Preferences = [PSCustomObject]@{ Theme = @("dark", "light", "auto")[$_ % 3]; Language = @("en", "de", "fr")[$_ % 3]; Notifications = @{ Email = ($true, $false)[$_ % 2]; Push = ($true, $false)[($_ + 1) % 2] } } }
        Orders = @([PSCustomObject]@{ OrderId = "ORD-$($_)-1"; Total = (Get-Random -Min 10 -Max 500) }, [PSCustomObject]@{ OrderId = "ORD-$($_)-2"; Total = (Get-Random -Min 5 -Max 200) })
        Metadata = [PSCustomObject]@{ Created = [DateTimeOffset]::Now; Updated = [DateTimeOffset]::Now; Tags = @("tag-$_", "group-$($_ % 50)") }
    }
} | New-BucketObject -Bucket b1kc -KeyProperty Id -Quiet
$w = $wt.ElapsedMilliseconds
$wt.Restart()
$r = Get-BucketObject -Bucket b1kc
Write-BenchResult "Complex (nested Profile+Orders+Metadata)" $w $wt.ElapsedMilliseconds $r.Count

# ============================================================
# 3. Scale test — both formats @ 10k
# ============================================================
$N10 = 10000

Write-Host "`n[3] Scale — JSON + Binary (${N10} simple objects)" -ForegroundColor Blue
Use-Bucket "s10k-json"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
1..$N10 | ForEach-Object { [PSCustomObject]@{ Id = $_; Name = "item-$_"; Value = (Get-Random); Timestamp = [DateTimeOffset]::Now } } |
    New-BucketObject -Bucket s10k-json -KeyProperty Id -Quiet
$jw = $wt.ElapsedMilliseconds
$wt.Restart()
$jr = Get-BucketObject -Bucket s10k-json
Write-BenchResult "JSON (default)" $jw $wt.ElapsedMilliseconds $jr.Count

Use-Bucket "s10k-bin"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
1..$N10 | ForEach-Object { [PSCustomObject]@{ Id = $_; Name = "item-$_"; Value = (Get-Random); Timestamp = [DateTimeOffset]::Now } } |
    New-BucketObject -Bucket s10k-bin -KeyProperty Id -AsBinary -Quiet
$bw = $wt.ElapsedMilliseconds
$wt.Restart()
$br = Get-BucketObject -Bucket s10k-bin
Write-BenchResult "Binary (-AsBinary)" $bw $wt.ElapsedMilliseconds $br.Count

# ============================================================
# 4-5. Binary (-AsBinary) — 1k simple + 1k complex
# ============================================================

Write-Host "`n[4] Binary -AsBinary (${N} simple objects)" -ForegroundColor Blue
Use-Bucket "bin1k"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
1..$N | ForEach-Object { [PSCustomObject]@{ Id = $_; Name = "item-$_"; Value = (Get-Random); Timestamp = [DateTimeOffset]::Now } } |
    New-BucketObject -Bucket bin1k -KeyProperty Id -AsBinary -Quiet
$w = $wt.ElapsedMilliseconds
$wt.Restart()
$r = Get-BucketObject -Bucket bin1k
Write-BenchResult "Simple" $w $wt.ElapsedMilliseconds $r.Count

Write-Host "`n[5] Binary -AsBinary (${N} complex objects)" -ForegroundColor Blue
Use-Bucket "bin1kc"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
1..$N | ForEach-Object {
    [PSCustomObject]@{
        Id = $_; Profile = [PSCustomObject]@{ Name = "User-$_"; Email = "user-$_@example.com"; Preferences = [PSCustomObject]@{ Theme = @("dark", "light", "auto")[$_ % 3]; Language = @("en", "de", "fr")[$_ % 3]; Notifications = @{ Email = ($true, $false)[$_ % 2]; Push = ($true, $false)[($_ + 1) % 2] } } }
        Orders = @([PSCustomObject]@{ OrderId = "ORD-$($_)-1"; Total = (Get-Random -Min 10 -Max 500) }, [PSCustomObject]@{ OrderId = "ORD-$($_)-2"; Total = (Get-Random -Min 5 -Max 200) })
        Metadata = [PSCustomObject]@{ Created = [DateTimeOffset]::Now; Updated = [DateTimeOffset]::Now; Tags = @("tag-$_", "group-$($_ % 50)") }
    }
} | New-BucketObject -Bucket bin1kc -KeyProperty Id -AsBinary -Quiet
$w = $wt.ElapsedMilliseconds
$wt.Restart()
$r = Get-BucketObject -Bucket bin1kc
Write-BenchResult "Complex (nested Profile+Orders+Metadata)" $w $wt.ElapsedMilliseconds $r.Count

# ============================================================
# 5. Compression — binary vs compressed binary
# ============================================================
Write-Host "`n[6] Compression (${N} objects — binary vs -Compress)" -ForegroundColor Blue

Use-Bucket "comp-raw"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
1..$N | ForEach-Object {
    $h = [ordered]@{}; 1..20 | ForEach-Object { $h["f$_"] = (Get-Random -Min 100 -Max 999) }
    [PSCustomObject]@{ Id = $_; Name = "obj-$_"; Value = (Get-Random); Data = [PSCustomObject]$h; TS = [DateTimeOffset]::Now }
} | New-BucketObject -Bucket comp-raw -KeyProperty Id -AsBinary -Quiet
$rawW = $wt.ElapsedMilliseconds
$wt.Restart()
$rawR = Get-BucketObject -Bucket comp-raw
$rawSz = (Get-ChildItem -Path (Join-Path (Get-BucketRoot) "comp-raw") -Filter *.dat -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
Write-BenchResult "Binary (raw)" $rawW $wt.ElapsedMilliseconds $rawR.Count ("Size $([math]::Round($rawSz/1KB))KB")

Use-Bucket "comp-gz"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
1..$N | ForEach-Object {
    $h = [ordered]@{}; 1..20 | ForEach-Object { $h["f$_"] = (Get-Random -Min 100 -Max 999) }
    [PSCustomObject]@{ Id = $_; Name = "obj-$_"; Value = (Get-Random); Data = [PSCustomObject]$h; TS = [DateTimeOffset]::Now }
} | New-BucketObject -Bucket comp-gz -KeyProperty Id -AsBinary -Compress -Quiet
$gzW = $wt.ElapsedMilliseconds
$wt.Restart()
$gzR = Get-BucketObject -Bucket comp-gz
$gzSz = (Get-ChildItem -Path (Join-Path (Get-BucketRoot) "comp-gz") -Filter *.dat -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
$pct = if ($rawSz -gt 0) { [math]::Round((1 - $gzSz / $rawSz) * 100) } else { 0 }
Write-BenchResult "Binary + -Compress (GZip)" $gzW $wt.ElapsedMilliseconds $gzR.Count ("Size $([math]::Round($gzSz/1KB))KB  Saved ${pct}%")

# ============================================================
# 7. FileInfo — truncated JSON vs binary (strength demo)
# ============================================================
Write-Host "`n[7] FileInfo — truncated JSON vs binary strength" -ForegroundColor Blue

$fiItems = @(Get-ChildItem $HOME -File -Force -ErrorAction SilentlyContinue | Select-Object -First 10)

function Measure-FiBench {
    param([string]$Label, [string]$Bucket, [int]$Depth = 20, [switch]$AsBinary, [switch]$Compress)
    Use-Bucket $Bucket
    $wt = [System.Diagnostics.Stopwatch]::StartNew()
    $params = @{ Bucket = $Bucket; KeyProperty = 'Name'; Depth = $Depth; Quiet = $true }
    $params.AsBinary = $AsBinary.IsPresent
    if ($Compress) { $params.Compress = $true }
    $fiItems | New-BucketObject @params -WarningAction SilentlyContinue 2>&1 | Out-Null
    $writeMs = $wt.ElapsedMilliseconds
    $wt.Restart()
    $read = Get-BucketObject -Bucket $Bucket
    $readMs = $wt.ElapsedMilliseconds
    $dir = Join-Path (Get-BucketRoot) $Bucket
    $files = Get-ChildItem -Path $dir -ErrorAction SilentlyContinue
    $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
    $sizeStr = if ($totalSize -gt 1MB) { "$([math]::Round($totalSize/1MB,1))MB" } else { "$([math]::Round($totalSize/1KB))KB" }
    Write-BenchResult $Label $writeMs $readMs $read.Count ("Size ${sizeStr}")
}

Measure-FiBench "JSON @ Depth 1 (truncated)"           -Bucket "fi-d1"  -Depth 1
Measure-FiBench "JSON @ Depth 20 (full)"               -Bucket "fi-d20" -Depth 20
Measure-FiBench "Binary (full preservation)"           -Bucket "fi-bin" -AsBinary
Measure-FiBench "Binary + Compress (compressed CLIXML)" -Bucket "fi-gz"  -AsBinary -Compress

# ============================================================
# 8. Depth/truncation — system objects truncate cleanly
# ============================================================
Write-Host "`n[8] Depth/truncation — system objects (zero binary fallbacks)" -ForegroundColor Blue

$homeItems = @(Get-ChildItem $HOME -Force -ErrorAction SilentlyContinue)

function Measure-DepthBench {
    param([string]$Label, [int]$Depth, [object[]]$Items, [string]$Bucket, [string]$KeyProp)
    Use-Bucket $Bucket
    $wt = [System.Diagnostics.Stopwatch]::StartNew()
    $items = $Items | New-BucketObject -Bucket $Bucket -KeyProperty $KeyProp -Depth $Depth -Quiet -WarningAction SilentlyContinue 2>&1
    $writeMs = $wt.ElapsedMilliseconds
    $wt.Restart()
    $read = Get-BucketObject -Bucket $Bucket
    $readMs = $wt.ElapsedMilliseconds
    $dir = Join-Path (Get-BucketRoot) $Bucket
    $jsonFiles = @(Get-ChildItem -Path $dir -Filter *.json -ErrorAction SilentlyContinue)
    $datFiles = @(Get-ChildItem -Path $dir -Filter *.dat -ErrorAction SilentlyContinue)
    $totalSize = ($jsonFiles | Measure-Object -Property Length -Sum).Sum + ($datFiles | Measure-Object -Property Length -Sum).Sum
    $sizeStr = if ($totalSize -gt 1MB) { "$([math]::Round($totalSize/1MB,1))MB" } else { "$([math]::Round($totalSize/1KB))KB" }
    Write-BenchResult $Label $writeMs $readMs $read.Count ("Size ${sizeStr}  JSON:$($jsonFiles.Count)  Dat:$($datFiles.Count)")
}

Measure-DepthBench "DirectoryInfo (all items) @ Depth 1" -Depth 1 -Items $homeItems -Bucket "dep-d1" -KeyProp Name
Measure-DepthBench "DirectoryInfo (all items) @ Depth 5" -Depth 5 -Items $homeItems -Bucket "dep-d5" -KeyProp Name
Measure-DepthBench "DirectoryInfo (all items) @ Depth 20" -Depth 20 -Items $homeItems -Bucket "dep-d20" -KeyProp Name

$homeItemsNamed = $homeItems | Select-Object Name, FullName, Length, LastWriteTime, Mode
Measure-DepthBench "Selected props (Name,FullName,Length) @ Depth 1" -Depth 1 -Items $homeItemsNamed -Bucket "dep-s1" -KeyProp Name
Measure-DepthBench "Selected props (Name,FullName,Length) @ Depth 20" -Depth 20 -Items $homeItemsNamed -Bucket "dep-s20" -KeyProp Name

$inner = "leaf"
for ($i = 1; $i -le 25; $i++) { $inner = @{ "L$i" = $inner } }

Use-Bucket "dep-h1"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
$inner | New-BucketObject -Bucket dep-h1 -Key "deep" -Depth 1 -Quiet -WarningAction SilentlyContinue
$w1 = $wt.ElapsedMilliseconds
$wt.Restart()
$null = Get-BucketObject -Bucket dep-h1 -Key "deep"
Write-BenchResult "Deep hashtable (25 levels) @ Depth 1 (truncated)" $w1 $wt.ElapsedMilliseconds 1

Use-Bucket "dep-h20"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
$inner | New-BucketObject -Bucket dep-h20 -Key "deep" -Depth 20 -Quiet -WarningAction SilentlyContinue
$w20 = $wt.ElapsedMilliseconds
$wt.Restart()
$null = Get-BucketObject -Bucket dep-h20 -Key "deep"
Write-BenchResult "Deep hashtable (25 levels) @ Depth 20 (full)" $w20 $wt.ElapsedMilliseconds 1

Use-Bucket "dep-hbin"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
$inner | New-BucketObject -Bucket dep-hbin -Key "deep" -AsBinary -Quiet
$wbin = $wt.ElapsedMilliseconds
$wt.Restart()
$null = Get-BucketObject -Bucket dep-hbin -Key "deep"
Write-BenchResult "Deep hashtable (25 levels) @ binary (full preserv.)" $wbin $wt.ElapsedMilliseconds 1

# ============================================================
# 7. Funnel — throughput impact
# ============================================================
Write-Host "`n[9] Funnel throughput (${N} simple objects)" -ForegroundColor Blue

Use-Bucket "f-raw"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
1..$N | ForEach-Object { [PSCustomObject]@{ Id = $_; Name = "obj-$_"; Value = (Get-Random); A = 1; B = 2; C = 3; D = 4; E = 5 } } |
    New-BucketObject -Bucket f-raw -KeyProperty Id -Quiet
$rawW = $wt.ElapsedMilliseconds
$wt.Restart()
$rawR = Get-BucketObject -Bucket f-raw
Write-BenchResult "Raw store (6 properties)" $rawW $wt.ElapsedMilliseconds $rawR.Count

New-Funnel -Name "bench-strip" -Filter { [PSCustomObject]@{ Id = $_.Id; Name = $_.Name; Value = $_.Value } } -Force -Quiet
Use-Bucket "f-funnel"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
1..$N | ForEach-Object { [PSCustomObject]@{ Id = $_; Name = "obj-$_"; Value = (Get-Random); A = 1; B = 2; C = 3; D = 4; E = 5 } } |
    New-BucketObject -Bucket f-funnel -KeyProperty Id -Funnel "bench-strip" -Quiet
$funW = $wt.ElapsedMilliseconds
$wt.Restart()
$funR = Get-BucketObject -Bucket f-funnel
Write-BenchResult "Funnel strip (3 properties)" $funW $wt.ElapsedMilliseconds $funR.Count
Remove-Funnel -Name "bench-strip" -Quiet -Confirm:$false

# ============================================================
# Cleanup
# ============================================================
foreach ($b in $createdBuckets) { Remove-Bucket $b -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet | Out-Null }

Set-BucketRoot (Join-Path $HOME ".buckets")
Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-InfoBlock -Mode bottom
Write-Progress -Activity "Buckets Benchmark" -Completed
