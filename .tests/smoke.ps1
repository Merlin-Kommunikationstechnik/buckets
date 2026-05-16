#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Smoke test for latest committed features.
.DESCRIPTION
    OVERWRITE this file when committing new features.
    Tests: -AutoIndex parameter on New-BucketObject.
#>

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-new-$(Get-Random)"
Set-BucketRoot $testRoot

$createdBuckets = [System.Collections.ArrayList]::new()
function Use-Bucket {
    param([string]$Name)
    $null = $createdBuckets.Add($Name)
}

# === 1. Create test data ===
New-BucketObject -Bucket "smoke/dup" -InputObject @(
    @{ Name = "Alice"; Role = "admin" },
    @{ Name = "Bob"; Role = "user" },
    @{ Name = "Alice"; Role = "guest" }
) -KeyProperty Name -AutoIndex -Quiet
Use-Bucket "smoke"

New-BucketObject -Bucket "smoke/pre" -InputObject @{ _Id = "test"; Val = 1 } -KeyProperty _Id -Quiet
New-BucketObject -Bucket "smoke/pre" -InputObject @{ _Id = "test"; Val = 2 } -KeyProperty _Id -AutoIndex -Quiet
Use-Bucket "smoke/pre"

# === 2. Run smoke tests ===
$pass = 0; $fail = 0
function Test-Feature {
    param([string]$Name, [scriptblock]$Check)
    try {
        $ok = & $Check
        if ($ok) {
            $script:pass++
            Write-Host "  $Name ... PASS" -ForegroundColor Green
        } else {
            $script:fail++
            Write-Host "  $Name ... FAIL" -ForegroundColor Red
        }
    } catch {
        $script:fail++
        Write-Host "  $Name ... FAIL ($($_.Exception.Message))" -ForegroundColor Red
    }
}

Write-Host "`n[Smoke Test] AutoIndex" -ForegroundColor Blue

Test-Feature "AutoIndex within-batch duplicates" {
    $keys = (Get-BucketKeys -Bucket "smoke/dup").Key
    $keys.Count -eq 3 -and "Alice" -in $keys -and "Alice_1" -in $keys -and "Bob" -in $keys
}

Test-Feature "AutoIndex pre-existing key" {
    $keys = (Get-BucketKeys -Bucket "smoke/pre").Key
    $keys.Count -eq 2 -and "test" -in $keys -and "test_1" -in $keys
}

Test-Feature "AutoIndex without -AutoIndex skips duplicates" {
    $r = New-BucketObject -Bucket "smoke/skip" -InputObject @(
        @{ Name = "x"; V = 1 },
        @{ Name = "x"; V = 2 }
    ) -KeyProperty Name -PassThru
    $r.Saved -eq 1 -and $r.Skipped -eq 1
}

Test-Feature "AutoIndex -Overwrite replaces first, indexes rest" {
    Remove-BucketObject -Bucket "smoke/ow" -Drop -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet -ErrorAction SilentlyContinue
    New-BucketObject -Bucket "smoke/ow" -InputObject @{ _Id = "k"; V = 1 } -KeyProperty _Id -Quiet
    $items = @([PSCustomObject]@{ _Id = "k"; V = 10 }, [PSCustomObject]@{ _Id = "k"; V = 20 })
    $r = $items | New-BucketObject -Bucket "smoke/ow" -KeyProperty _Id -AutoIndex -Overwrite -PassThru
    $r.Saved -eq 2 -and $r.Indexed -eq 1 -and $r.Overwritten -eq 1
}

Test-Feature "AutoIndex -Key with pipeline" {
    Remove-BucketObject -Bucket "smoke/key" -Drop -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet -ErrorAction SilentlyContinue
    1..3 | ForEach-Object { [PSCustomObject]@{ N = $_ } } | New-BucketObject -Bucket "smoke/key" -Key "item" -AutoIndex -PassThru | Out-Null
    $keys = (Get-BucketKeys -Bucket "smoke/key").Key
    $keys.Count -eq 3 -and "item" -in $keys -and "item_1" -in $keys -and "item_2" -in $keys
}

Test-Feature "AutoIndex no duplicates = no indexing" {
    $r = New-BucketObject -Bucket "smoke/nodup" -InputObject @(
        @{ Name = "A"; V = 1 },
        @{ Name = "B"; V = 2 }
    ) -KeyProperty Name -AutoIndex -PassThru
    $r.Indexed -eq 0 -and $r.Saved -eq 2
}

Test-Feature "AutoIndex PassThru includes Indexed" {
    Remove-BucketObject -Bucket "smoke/pt" -Drop -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet -ErrorAction SilentlyContinue
    $items = @([PSCustomObject]@{ Name = "z"; V = 1 }, [PSCustomObject]@{ Name = "z"; V = 2 })
    $r = $items | New-BucketObject -Bucket "smoke/pt" -KeyProperty Name -AutoIndex -PassThru
    $r.Indexed -eq 1
}

# === 3. Cleanup ===
foreach ($b in $createdBuckets) {
    Remove-BucketObject -Bucket $b -Drop -Force -Confirm:$false -Recurse -WarningAction SilentlyContinue
}

Set-BucketRoot (Join-Path $HOME ".buckets")
Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n$pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })