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
    $cores = [Environment]::ProcessorCount
    $cpuModel = try { if ($IsWindows) { (Get-CimInstance Win32_Processor -ErrorAction Stop).Name -replace '\s+', ' ' } elseif ($IsLinux) { ((Get-Content /proc/cpuinfo | Select-String "model name" | Select-Object -First 1) -replace '.*: ').Trim() } elseif ($IsMacOS) { (sysctl -n machdep.cpu.brand_string 2>$null).Trim() } } catch { $null }
    $cpuStr = if ($cpuModel) { "$cores x $cpuModel" } else { "${cores} cores" }
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
        Write-Host $os -NoNewline -ForegroundColor DarkGray
        Write-Host " - " -NoNewline -ForegroundColor DarkGray
        Write-Host $cpuStr -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray
    }
    else {
        $elapsed = $sw.ElapsedMilliseconds
        Write-Host $sep -ForegroundColor DarkGray
        Write-Host " Done" -NoNewline -ForegroundColor Blue
        $secs = [math]::Round($elapsed / 1000, 2)
        Write-Host " - ${secs}s" -NoNewline -ForegroundColor Magenta
        Write-Host " - " -NoNewline -ForegroundColor DarkGray
        Write-Host $pwsh -NoNewline -ForegroundColor Cyan
        Write-Host " - " -NoNewline -ForegroundColor DarkGray
        Write-Host $os -NoNewline -ForegroundColor DarkGray
        Write-Host " - " -NoNewline -ForegroundColor DarkGray
        Write-Host $cpuStr -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray
    }
}

function Format-BenchTime([int]$Ms) {
    if ($Ms -ge 1000) { ($ms / 1000).ToString("F2", [System.Globalization.CultureInfo]::InvariantCulture) + "s" } else { "${Ms}ms" }
}

function Write-BenchResult {
    param([string]$Label, [int]$WriteMs, [int]$ReadMs, [int]$Count, [string]$Extra = "")
    $extraStr = if ($Extra) { "  $Extra" } else { "" }
    $wt = Format-BenchTime $WriteMs
    $rt = Format-BenchTime $ReadMs
    Write-Host ("  {0,-50} Write {1,8}  Read {2,8}  Obj: {3}{4}" -f $Label, $wt, $rt, $Count, $extraStr) -ForegroundColor DarkGray
    $script:phase++
    $pct = [math]::Min(100, [int](($script:phase / $script:totalPhases) * 100))
    Write-Progress -Activity "Buckets Benchmark" -Status "Phase $($script:phase)/$($script:totalPhases): $Label" -PercentComplete $pct
}

$N = 1000

$script:phase = 0
$script:totalPhases = 28

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
    Write-BenchResult $Label $writeMs $readMs $read.Count ("Size {0,7}  JSON:{1,3}  Dat:{2,3}" -f $sizeStr, $jsonFiles.Count, $datFiles.Count)
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
$r1ms = $wt.ElapsedMilliseconds
$depH1Dir = Join-Path (Get-BucketRoot) "dep-h1"
$depH1Json = @(Get-ChildItem -Path $depH1Dir -Filter *.json -ErrorAction SilentlyContinue)
$depH1Dat = @(Get-ChildItem -Path $depH1Dir -Filter *.dat -ErrorAction SilentlyContinue)
$depH1Size = ($depH1Json | Measure-Object -Property Length -Sum).Sum + ($depH1Dat | Measure-Object -Property Length -Sum).Sum
$depH1SizeStr = if ($depH1Size -gt 1MB) { "$([math]::Round($depH1Size/1MB,1))MB" } else { "$([math]::Round($depH1Size/1KB))KB" }
Write-BenchResult "Deep hashtable (25 levels) @ Depth 1 (truncated)" $w1 $r1ms 1 (" Size {0,7}  JSON:{1,3}  Dat:{2,3}" -f $depH1SizeStr, $depH1Json.Count, $depH1Dat.Count)

Use-Bucket "dep-h20"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
$inner | New-BucketObject -Bucket dep-h20 -Key "deep" -Depth 20 -Quiet -WarningAction SilentlyContinue
$w20 = $wt.ElapsedMilliseconds
$wt.Restart()
$null = Get-BucketObject -Bucket dep-h20 -Key "deep"
$r20ms = $wt.ElapsedMilliseconds
$depH20Dir = Join-Path (Get-BucketRoot) "dep-h20"
$depH20Json = @(Get-ChildItem -Path $depH20Dir -Filter *.json -ErrorAction SilentlyContinue)
$depH20Dat = @(Get-ChildItem -Path $depH20Dir -Filter *.dat -ErrorAction SilentlyContinue)
$depH20Size = ($depH20Json | Measure-Object -Property Length -Sum).Sum + ($depH20Dat | Measure-Object -Property Length -Sum).Sum
$depH20SizeStr = if ($depH20Size -gt 1MB) { "$([math]::Round($depH20Size/1MB,1))MB" } else { "$([math]::Round($depH20Size/1KB))KB" }
Write-BenchResult "Deep hashtable (25 levels) @ Depth 20 (full)" $w20 $r20ms 1 (" Size {0,7}  JSON:{1,3}  Dat:{2,3}" -f $depH20SizeStr, $depH20Json.Count, $depH20Dat.Count)

Use-Bucket "dep-hbin"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
$inner | New-BucketObject -Bucket dep-hbin -Key "deep" -AsBinary -Quiet
$wbin = $wt.ElapsedMilliseconds
$wt.Restart()
$null = Get-BucketObject -Bucket dep-hbin -Key "deep"
$rbinms = $wt.ElapsedMilliseconds
$depHbinDir = Join-Path (Get-BucketRoot) "dep-hbin"
$depHbinJson = @(Get-ChildItem -Path $depHbinDir -Filter *.json -ErrorAction SilentlyContinue)
$depHbinDat = @(Get-ChildItem -Path $depHbinDir -Filter *.dat -ErrorAction SilentlyContinue)
$depHbinSize = ($depHbinJson | Measure-Object -Property Length -Sum).Sum + ($depHbinDat | Measure-Object -Property Length -Sum).Sum
$depHbinSizeStr = if ($depHbinSize -gt 1MB) { "$([math]::Round($depHbinSize/1MB,1))MB" } else { "$([math]::Round($depHbinSize/1KB))KB" }
Write-BenchResult "Deep hashtable (25 levels) @ binary (full)" $wbin $rbinms 1 (" Size {0,7}  JSON:{1,3}  Dat:{2,3}" -f $depHbinSizeStr, $depHbinJson.Count, $depHbinDat.Count)

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

New-Funnel -Name "bench-strip" -Transform { [PSCustomObject]@{ Id = $_.Id; Name = $_.Name; Value = $_.Value } } -Force -Quiet
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
# 10-12. Expand / Reconstruct throughput
# ============================================================
Write-Host "`n[10] Expand - simple flat hashtable (500 items)" -ForegroundColor Blue

$Nex = 500
$expandFlats = 1..$Nex | ForEach-Object { @{ id = "item-$_"; host = "srv-$_"; port = 80 + ($_ % 100); ssl = ($true, $false)[$_ % 2]; ttl = ($_ * 10); env = @("dev","stg","prod")[$_ % 3] } }

Use-Bucket "ex-flat-norm"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
$expandFlats | New-BucketObject -Bucket ex-flat-norm -KeyProperty id -Quiet
$exfnW = $wt.ElapsedMilliseconds
$wt.Restart()
$exfnR = Get-BucketObject -Bucket ex-flat-norm
$exfnDir = Join-Path (Get-BucketRoot) "ex-flat-norm"
$exfnFiles = @(Get-ChildItem -Path $exfnDir -ErrorAction SilentlyContinue)
$exfnSize = ($exfnFiles | Measure-Object -Property Length -Sum).Sum
$exfnSizeStr = if ($exfnSize -gt 1MB) { "$([math]::Round($exfnSize/1MB,1))MB" } else { "$([math]::Round($exfnSize/1KB))KB" }
Write-BenchResult "Normal (no expand)" $exfnW $wt.ElapsedMilliseconds $exfnR.Count ("Files: $($exfnFiles.Count), Size: ${exfnSizeStr}")

Use-Bucket "ex-flat-exp"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
$expandFlats | New-BucketObject -Bucket ex-flat-exp -KeyProperty id -Expand -Quiet
$exfexW = $wt.ElapsedMilliseconds
$wt.Restart()
$exfexR = Get-BucketObject -Bucket ex-flat-exp -Expand
$exfexDir = Join-Path (Get-BucketRoot) "ex-flat-exp"
$exfexDirs = @(Get-ChildItem -Path $exfexDir -Directory -ErrorAction SilentlyContinue)
$exfexFiles = @(Get-ChildItem -Path $exfexDir -Recurse -File -ErrorAction SilentlyContinue)
$exfexSize = ($exfexFiles | Measure-Object -Property Length -Sum).Sum
$exfexSizeStr = if ($exfexSize -gt 1MB) { "$([math]::Round($exfexSize/1MB,1))MB" } else { "$([math]::Round($exfexSize/1KB))KB" }
Write-BenchResult "Expand (-Expand)" $exfexW $wt.ElapsedMilliseconds $exfexR.Count ("Dirs: $($exfexDirs.Count), Files: $($exfexFiles.Count), Size: ${exfexSizeStr}")

Write-Host "`n[11] Expand - nested hashtable (${Nex} items, 3 groups each)" -ForegroundColor Blue

$expandNested = 1..$Nex | ForEach-Object {
    @{
        id = "item-$_"
        server = @{ host = "srv-$_"; port = 80 + ($_ % 100) }
        logging = @{ level = @("debug","info","warn")[$_ % 3]; retention = ($_ * 7); file = "/var/log/app-$_.log" }
        limits = @{ cpu = ($_ * 10); mem = ($_ * 20); disk = ($_ * 30) }
    }
}

Use-Bucket "ex-nest-norm"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
$expandNested | New-BucketObject -Bucket ex-nest-norm -KeyProperty id -Quiet
$exnnW = $wt.ElapsedMilliseconds
$wt.Restart()
$exnnR = Get-BucketObject -Bucket ex-nest-norm
$exnnDir = Join-Path (Get-BucketRoot) "ex-nest-norm"
$exnnFiles = @(Get-ChildItem -Path $exnnDir -ErrorAction SilentlyContinue)
$exnnSize = ($exnnFiles | Measure-Object -Property Length -Sum).Sum
$exnnSizeStr = if ($exnnSize -gt 1MB) { "$([math]::Round($exnnSize/1MB,1))MB" } else { "$([math]::Round($exnnSize/1KB))KB" }
Write-BenchResult "Normal (no expand)" $exnnW $wt.ElapsedMilliseconds $exnnR.Count ("Files: $($exnnFiles.Count), Size: ${exnnSizeStr}")

Use-Bucket "ex-nest-exp"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
$expandNested | New-BucketObject -Bucket ex-nest-exp -KeyProperty id -Expand -Quiet
$exnexW = $wt.ElapsedMilliseconds
$wt.Restart()
$exnexR = Get-BucketObject -Bucket ex-nest-exp -Expand
$exnexDir = Join-Path (Get-BucketRoot) "ex-nest-exp"
$exnexDirs = @(Get-ChildItem -Path $exnexDir -Directory -Recurse -ErrorAction SilentlyContinue)
$exnexFiles = @(Get-ChildItem -Path $exnexDir -Recurse -File -ErrorAction SilentlyContinue)
$exnexSize = ($exnexFiles | Measure-Object -Property Length -Sum).Sum
$exnexSizeStr = if ($exnexSize -gt 1MB) { "$([math]::Round($exnexSize/1MB,1))MB" } else { "$([math]::Round($exnexSize/1KB))KB" }
Write-BenchResult "Expand (-Expand)" $exnexW $wt.ElapsedMilliseconds $exnexR.Count ("Dirs: $($exnexDirs.Count), Files: $($exnexFiles.Count), Size: ${exnexSizeStr}")

Write-Host "`n[12] Expand - array with -Key (${Nex} items, 3 elements each)" -ForegroundColor Blue

$expandArrays = 1..$Nex | ForEach-Object {
    @(
        [PSCustomObject]@{ name = "svc-$_-a"; port = 80 + ($_ % 100); status = "active" }
        [PSCustomObject]@{ name = "svc-$_-b"; port = 81 + ($_ % 100); status = @("active","idle")[$_ % 2] }
        [PSCustomObject]@{ name = "svc-$_-c"; port = 82 + ($_ % 100); status = @("active","maintenance")[$_ % 3 -eq 0 -and $_ -ne 0] }
    )
}
# Flatten for non-expand comparison
$flatItems = $expandArrays | ForEach-Object { $_ }

Use-Bucket "ex-arr-norm"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
$flatItems | New-BucketObject -Bucket ex-arr-norm -Key "services" -AutoIndex -Quiet
$exanW = $wt.ElapsedMilliseconds
$wt.Restart()
$exanR = @(Get-BucketObject -Bucket ex-arr-norm)
$exanDir = Join-Path (Get-BucketRoot) "ex-arr-norm"
$exanFiles = @(Get-ChildItem -Path $exanDir -File -ErrorAction SilentlyContinue)
$exanSize = ($exanFiles | Measure-Object -Property Length -Sum).Sum
$exanSizeStr = if ($exanSize -gt 1MB) { "$([math]::Round($exanSize/1MB,1))MB" } else { "$([math]::Round($exanSize/1KB))KB" }
Write-BenchResult "Normal (-AutoIndex, flat)" $exanW $wt.ElapsedMilliseconds $exanR.Count ("Files: $($exanFiles.Count), Size: ${exanSizeStr}")

Use-Bucket "ex-arr-exp"
$wt = [System.Diagnostics.Stopwatch]::StartNew()
$expandArrays | New-BucketObject -Bucket ex-arr-exp -Key "services" -Expand -Quiet
$exaexW = $wt.ElapsedMilliseconds
$wt.Restart()
$exaexR = @(Get-BucketObject -Bucket ex-arr-exp -Key "services" -Expand)
$exaexDir = Join-Path (Get-BucketRoot) "ex-arr-exp/services"
$exaexDirs = @(Get-ChildItem -Path $exaexDir -Directory -ErrorAction SilentlyContinue)
$exaexFiles = @(Get-ChildItem -Path $exaexDir -Recurse -File -ErrorAction SilentlyContinue)
$exaexSize = ($exaexFiles | Measure-Object -Property Length -Sum).Sum
$exaexSizeStr = if ($exaexSize -gt 1MB) { "$([math]::Round($exaexSize/1MB,1))MB" } else { "$([math]::Round($exaexSize/1KB))KB" }
Write-BenchResult "Expand (-Key -Expand)" $exaexW $wt.ElapsedMilliseconds $exaexR.Count ("Dirs: $($exaexDirs.Count), Files: $($exaexFiles.Count), Size: ${exaexSizeStr}")

# ============================================================
# Cleanup
# ============================================================
foreach ($b in $createdBuckets) { Remove-Bucket $b -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet | Out-Null }

Set-BucketRoot (Join-Path $HOME ".buckets")
Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-InfoBlock -Mode bottom
Write-Progress -Activity "Buckets Benchmark" -Completed
