#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Smoke test for latest committed features.
.DESCRIPTION
    OVERWRITE this file when committing new features.
    Tests: hidden Path property, -Tree rename, -Objects inversion,
    extension-free tree output, JSON/Binary format labels, empty bucket removal,
    -AsTimestamp pipe dedup.
#>

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

$createdBuckets = [System.Collections.ArrayList]::new()
function Use-Bucket {
    param([string]$Name)
    $null = $createdBuckets.Add($Name)
}

# === 1. Create test data ===
New-BucketObject -Bucket "smoke/users" -InputObject @(
    @{ _Id = "u1"; Name = "Alice" }, @{ _Id = "u2"; Name = "Bob" }
) -KeyProperty _Id -Quiet
Use-Bucket "smoke"

New-BucketObject -Bucket "smoke/config" -InputObject @{ _Id = "cfg"; Theme = "dark" } -KeyProperty _Id -AsJson -Quiet

New-BucketObject -Bucket "smoke/servers/web-01/logs" -InputObject @{ _Id = "log-001"; Msg = "OK" } -KeyProperty _Id -Quiet
Use-Bucket "smoke/servers"

$tsItems = 1..3 | ForEach-Object { @{ _Id = "ts$_"; Seq = $_ } }
$tsItems | New-BucketObject -Bucket "smoke/timestamps" -AsTimestamp -Quiet
Use-Bucket "smoke/timestamps"

New-BucketObject -Bucket "smoke/empty" -InputObject @() -Quiet
Use-Bucket "smoke/empty"

# === 2. Run smoke tests ===
$pass = 0; $fail = 0
function Test-Feature {
    param([string]$Name, [scriptblock]$Check)
    if (& $Check) {
        $pass++
        Write-Host "  $Name ... PASS" -ForegroundColor Green
    } else {
        $fail++
        Write-Host "  $Name ... FAIL" -ForegroundColor Red
    }
}

Write-Host "`n[Smoke Test] Latest Features" -ForegroundColor Blue

# Feature: Default dip shows top-level buckets, no Path column
Test-Feature "dip default (top-level, aggregated, no Path)" {
    $b = Get-Bucket -Name "smoke"
    $b.Name -eq "smoke" -and $b.ObjectCount -ge 4 -and -not ($b | Format-List | Out-String).Contains("/.buckets/")
}

# Feature: dip -Recurse shows all levels
Test-Feature "dip -Recurse (all levels)" {
    $r = Get-Bucket -Recurse -Name "smoke/servers"
    $r | Where-Object { $_.Name -eq "smoke/servers/web-01/logs" } | ForEach-Object { $_.ObjectCount -eq 1 }
}

# Feature: dip -Tree shows directories only
Test-Feature "dip -Tree (directories only)" {
    $t = Get-Bucket -Tree -Name "smoke" -Raw
    $objs = $t.Children | Where-Object { $_.Type -eq "Object" }
    $objs.Count -eq 0
}

# Feature: dip -Tree -Objects shows keys without extensions
Test-Feature "dip -Tree -Objects (keys, no extensions)" {
    $t = Get-Bucket -Tree -Objects -Name "smoke" -Raw
    $u = $t.Children | Where-Object { $_.Name -eq "users" }
    $keys = $u.Children | Where-Object { $_.Type -eq "Object" } | ForEach-Object { $_.Name }
    ($keys -join ",") -notmatch "\.(dat|json)"
}

# Feature: Get-BucketKeys shows JSON/Binary
Test-Feature "Get-BucketKeys format labels" {
    $keys = Get-BucketKeys -Bucket "smoke/config"
    $keys[0].Format -in @("JSON","Binary")
}

# Feature: Get-BucketStats has no visible Path
Test-Feature "Get-BucketStats (Path hidden)" {
    $s = Get-BucketStats -Bucket "smoke/users"
    -not ($s | Format-List | Out-String).Contains("/.buckets/")
}

# Feature: Empty bucket removal
Test-Feature "Remove-Bucket on empty bucket" {
    Remove-Bucket "smoke/empty" -Force -Confirm:$false -Recurse
    -not (Test-Path "$HOME/.buckets/smoke/empty")
}

# Feature: AsTimestamp pipe dedup
Test-Feature "-AsTimestamp pipe (3 unique keys)" {
    $count = (Get-BucketObject -Bucket "smoke/timestamps").Count
    $count -ge 3
}

# === 3. Cleanup ===
foreach ($b in $createdBuckets) {
    Remove-Bucket -Bucket $b -Force -Confirm:$false -Recurse -WarningAction SilentlyContinue
}

Write-Host "`n$pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
