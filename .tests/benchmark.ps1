#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Performance benchmarks for the Buckets module.
.DESCRIPTION
    Measures write/read throughput for 1k and 10k objects, both simple and
    complex, in binary and JSON formats.
#>

#Remove-Module Buckets -ErrorAction SilentlyContinue
#Import-Module "$PSScriptRoot/../Buckets" -Force

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-bench-$(Get-Random)"
Set-BucketRoot $testRoot

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$createdBuckets = [System.Collections.ArrayList]::new()
$existingBuckets = @(Get-Bucket -WarningAction SilentlyContinue | ForEach-Object { $_.Name })

function Use-Bucket {
    param([string]$Name)
    $null = $createdBuckets.Add($Name)
    Remove-Bucket $Name -Force -Confirm:$false -WarningAction SilentlyContinue
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

Write-InfoBlock -Mode top

# ============================================================
# 1. Performance benchmark (1,000 objects)
# ============================================================
Write-Host "[1] Performance benchmark (1,000 objects — baseline throughput)" -ForegroundColor Blue
Use-Bucket "perf-test"
$perfBench = [System.Diagnostics.Stopwatch]::StartNew()
$perfObjects = 1..1000 | ForEach-Object {
    [PSCustomObject]@{
        Id = $_
        Name = "item-$_"
        Value = (Get-Random)
        Timestamp = [DateTimeOffset]::Now
    }
}
$perfObjects | New-BucketObject -Bucket perf-test -KeyProperty Id -Quiet
$writeTime = $perfBench.ElapsedMilliseconds

$perfBench.Restart()
$retrieved = Get-BucketObject -Bucket perf-test
$readTime = $perfBench.ElapsedMilliseconds

Write-Host "  Write: ${writeTime}ms, Read: ${readTime}ms, Objects: $($retrieved.Count)" -ForegroundColor DarkGray

# ============================================================
# 2. Performance benchmark (10,000 objects)
# ============================================================
Write-Host "`n[2] Performance benchmark (10,000 objects — scale test)" -ForegroundColor Blue
Use-Bucket "perf-10k"
$perfBench10k = [System.Diagnostics.Stopwatch]::StartNew()
$perf10kObjects = 1..10000 | ForEach-Object {
    [PSCustomObject]@{
        Id = $_
        Name = "obj-$_"
        Value = (Get-Random)
        Tags = @("tag-$_", "group-$($_ % 100)")
    }
}
$perf10kObjects | New-BucketObject -Bucket perf-10k -KeyProperty Id -Quiet
$writeTime10k = $perfBench10k.ElapsedMilliseconds

$perfBench10k.Restart()
$retrieved10k = Get-BucketObject -Bucket perf-10k
$readTime10k = $perfBench10k.ElapsedMilliseconds

Write-Host "  Write: ${writeTime10k}ms, Read: ${readTime10k}ms, Objects: $($retrieved10k.Count)" -ForegroundColor DarkGray

# ============================================================
# 3. Performance benchmark (10,000 complex objects)
# ============================================================
Write-Host "`n[3] Performance benchmark (10,000 complex objects — nested depth test)" -ForegroundColor Blue
Use-Bucket "perf-10k-complex"
$perfBench10kC = [System.Diagnostics.Stopwatch]::StartNew()
$perf10kCObjects = 1..10000 | ForEach-Object {
    [PSCustomObject]@{
        Id = $_
        Profile = [PSCustomObject]@{
            Name = "User-$_"
            Email = "user-$_@example.com"
            Preferences = [PSCustomObject]@{
                Theme = @("dark", "light", "auto")[$_ % 3]
                Language = @("en", "de", "fr")[$_ % 3]
                Notifications = @{ Email = ($true, $false)[$_ % 2]; Push = ($true, $false)[($_ + 1) % 2] }
            }
        }
        Orders = @(
            [PSCustomObject]@{ OrderId = "ORD-$($_)-1"; Total = (Get-Random -Min 10 -Max 500); Status = @("pending", "shipped", "delivered")[$_ % 3] }
            [PSCustomObject]@{ OrderId = "ORD-$($_)-2"; Total = (Get-Random -Min 5 -Max 200); Status = @("pending", "cancelled")[$_ % 2] }
        )
        Metadata = [PSCustomObject]@{
            Created = [DateTimeOffset]::Now
            Updated = [DateTimeOffset]::Now
            Tags = @("tag-$_", "group-$($_ % 50)", "region-$($_ % 10)")
        }
    }
}
$perf10kCObjects | New-BucketObject -Bucket perf-10k-complex -KeyProperty Id -Quiet
$writeTime10kC = $perfBench10kC.ElapsedMilliseconds

$perfBench10kC.Restart()
$retrieved10kC = Get-BucketObject -Bucket perf-10k-complex
$readTime10kC = $perfBench10kC.ElapsedMilliseconds

Write-Host "  Write: ${writeTime10kC}ms, Read: ${readTime10kC}ms, Objects: $($retrieved10kC.Count)" -ForegroundColor DarkGray

# ============================================================
# 4. Performance benchmark JSON (1,000 objects)
# ============================================================
Write-Host "`n[4] Performance benchmark JSON (1,000 objects)" -ForegroundColor Blue
Use-Bucket "perf-json-1k"
$perfJsonBench = [System.Diagnostics.Stopwatch]::StartNew()
$perfJsonObjects = 1..1000 | ForEach-Object {
    [PSCustomObject]@{
        Id = $_
        Name = "item-$_"
        Value = (Get-Random)
        Timestamp = [DateTimeOffset]::Now
    }
}
$perfJsonObjects | New-BucketObject -Bucket perf-json-1k -KeyProperty Id -AsJson -Quiet
$jsonWriteTime = $perfJsonBench.ElapsedMilliseconds

$perfJsonBench.Restart()
$jsonRetrieved = Get-BucketObject -Bucket perf-json-1k
$jsonReadTime = $perfJsonBench.ElapsedMilliseconds

Write-Host "  Write: ${jsonWriteTime}ms, Read: ${jsonReadTime}ms, Objects: $($jsonRetrieved.Count)" -ForegroundColor DarkGray

# ============================================================
# 5. Performance benchmark JSON (10,000 objects)
# ============================================================
Write-Host "`n[5] Performance benchmark JSON (10,000 objects)" -ForegroundColor Blue
Use-Bucket "perf-json-10k"
$perfJson10kBench = [System.Diagnostics.Stopwatch]::StartNew()
$perfJson10kObjects = 1..10000 | ForEach-Object {
    [PSCustomObject]@{
        Id = $_
        Name = "obj-$_"
        Value = (Get-Random)
        Tags = @("tag-$_", "group-$($_ % 100)")
    }
}
$perfJson10kObjects | New-BucketObject -Bucket perf-json-10k -KeyProperty Id -AsJson -Quiet
$jsonWriteTime10k = $perfJson10kBench.ElapsedMilliseconds

$perfJson10kBench.Restart()
$jsonRetrieved10k = Get-BucketObject -Bucket perf-json-10k
$jsonReadTime10k = $perfJson10kBench.ElapsedMilliseconds

Write-Host "  Write: ${jsonWriteTime10k}ms, Read: ${jsonReadTime10k}ms, Objects: $($jsonRetrieved10k.Count)" -ForegroundColor DarkGray

# ============================================================
# 6. Performance benchmark JSON (10,000 complex objects)
# ============================================================
Write-Host "`n[6] Performance benchmark JSON (10,000 complex objects)" -ForegroundColor Blue
Use-Bucket "perf-json-complex"
$perfJsonCBench = [System.Diagnostics.Stopwatch]::StartNew()
$perfJsonCObjects = 1..10000 | ForEach-Object {
    [PSCustomObject]@{
        Id = $_
        Profile = [PSCustomObject]@{
            Name = "User-$_"
            Email = "user-$_@example.com"
            Preferences = [PSCustomObject]@{
                Theme = @("dark", "light", "auto")[$_ % 3]
                Language = @("en", "de", "fr")[$_ % 3]
                Notifications = @{ Email = ($true, $false)[$_ % 2]; Push = ($true, $false)[($_ + 1) % 2] }
            }
        }
        Orders = @(
            [PSCustomObject]@{ OrderId = "ORD-$($_)-1"; Total = (Get-Random -Min 10 -Max 500); Status = @("pending", "shipped", "delivered")[$_ % 3] }
            [PSCustomObject]@{ OrderId = "ORD-$($_)-2"; Total = (Get-Random -Min 5 -Max 200); Status = @("pending", "cancelled")[$_ % 2] }
        )
        Metadata = [PSCustomObject]@{
            Created = [DateTimeOffset]::Now
            Updated = [DateTimeOffset]::Now
            Tags = @("tag-$_", "group-$($_ % 50)", "region-$($_ % 10)")
        }
    }
}
$perfJsonCObjects | New-BucketObject -Bucket perf-json-complex -KeyProperty Id -AsJson -Quiet
$jsonWriteTimeC = $perfJsonCBench.ElapsedMilliseconds

$perfJsonCBench.Restart()
$jsonRetrievedC = Get-BucketObject -Bucket perf-json-complex
$jsonReadTimeC = $perfJsonCBench.ElapsedMilliseconds

Write-Host "  Write: ${jsonWriteTimeC}ms, Read: ${jsonReadTimeC}ms, Objects: $($jsonRetrievedC.Count)" -ForegroundColor DarkGray

foreach ($b in $createdBuckets) {
    Remove-Bucket $b -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse
}

Set-BucketRoot (Join-Path $HOME ".buckets")
Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-InfoBlock -Mode bottom
