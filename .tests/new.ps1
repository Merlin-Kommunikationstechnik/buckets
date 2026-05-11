#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Smoke test for latest committed features.
.DESCRIPTION
    OVERWRITE this file when committing new features.
    Tests: funnel transform semantics on scoop, funnel filter via $null,
    Get-Bucket no longer accepts -Funnel, Resolve-Funnel helper.
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
New-BucketObject -Bucket "smoke/users" -InputObject @(
    @{ _Id = "u1"; Name = "Alice"; Role = "admin" },
    @{ _Id = "u2"; Name = "Bob"; Role = "user" },
    @{ _Id = "u3"; Name = "Carol"; Role = "user" }
) -KeyProperty _Id -Quiet
Use-Bucket "smoke"

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

Write-Host "`n[Smoke Test] Funnel Consistency" -ForegroundColor Blue

# Feature: Scoop funnel filters with $null return (transform semantics)
Test-Feature "Scoop funnel filters via if/$null pattern" {
    $result = Get-BucketObject -Bucket "smoke/users" -Funnel { if ($_.Role -eq "admin") { $_ } }
    @($result).Count -eq 1 -and @($result)[0].Name -eq "Alice"
}

# Feature: Scoop funnel transforms (add property)
Test-Feature "Scoop funnel transforms (adds property)" {
    $result = Get-BucketObject -Bucket "smoke/users" -Funnel { $_ | Add-Member -NotePropertyName "Seen" -NotePropertyValue $true -PassThru }
    @($result).Count -eq 3 -and @($result | Where-Object { $_.Seen -eq $true }).Count -eq 3
}

# Feature: Named funnel on scoop with transform semantics
Test-Feature "Named funnel on scoop (transform filter)" {
    New-Funnel -Name "smoke-admins" -Filter { if ($_.Role -eq "admin") { $_ } } -Force -Quiet
    $result = Get-BucketObject -Bucket "smoke/users" -Funnel "smoke-admins"
    Remove-Funnel -Name "smoke-admins" -Quiet -Confirm:$false
    @($result).Count -eq 1 -and @($result)[0].Name -eq "Alice"
}

# Feature: Fill funnel still works (transform before store)
Test-Feature "Fill funnel transforms before store" {
    New-Funnel -Name "smoke-xform" -Filter { $_ | Add-Member -NotePropertyName "Source" -NotePropertyValue "test" -PassThru } -Force -Quiet
    New-BucketObject -Bucket "smoke/transformed" -InputObject ([PSCustomObject]@{ _Id = "tx1"; Val = 42 }) -KeyProperty _Id -Funnel "smoke-xform" -Quiet
    Use-Bucket "smoke/transformed"
    $obj = Get-BucketObject -Bucket "smoke/transformed" -Key "tx1"
    Remove-Funnel -Name "smoke-xform" -Quiet -Confirm:$false
    $null -ne $obj -and $obj.Source -eq "test"
}

# Feature: Get-Bucket has no -Funnel parameter
Test-Feature "Get-Bucket has no -Funnel parameter" {
    $cmd = Get-Command Get-Bucket
    -not ($cmd.Parameters.ContainsKey('Funnel'))
}

# Feature: Ad-hoc scriptblock funnel on scoop
Test-Feature "Ad-hoc scriptblock funnel on scoop" {
    $result = Get-BucketObject -Bucket "smoke/users" -Funnel { if ($_.Name -like "A*") { $_ } }
    @($result).Count -eq 1 -and @($result)[0]._Id -eq "u1"
}

# === 3. Cleanup ===
foreach ($b in $createdBuckets) {
    Remove-Bucket -Bucket $b -Force -Confirm:$false -Recurse -WarningAction SilentlyContinue
}

Set-BucketRoot (Join-Path $HOME ".buckets")
Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n$pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })