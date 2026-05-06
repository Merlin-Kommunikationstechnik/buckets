# Array Tracking Diagnostic Script
# Run this and paste the output back

Import-Module ./Buckets/Buckets.psm1 -Force
Remove-Bucket "diag" -Force -Confirm:$false -WarningAction SilentlyContinue

$report = [System.Collections.ArrayList]::new()

function Log {
    param($Test, $Status, $Detail = "")
    $null = $report.Add([PSCustomObject]@{ Test = $Test; Status = $Status; Detail = $Detail })
}

# ============================================================
# TEST 1: Pipe array with -ArrayTracking
# ============================================================
Write-Host "`n=== TEST 1: Pipe array with -ArrayTracking ===" -ForegroundColor Cyan
@(
    [PSCustomObject]@{ _Id = "t1a"; Seq = 1 }
    [PSCustomObject]@{ _Id = "t1b"; Seq = 2 }
) | New-BucketObject -Bucket diag -Key _Id -ArrayTracking -Quiet

$raw = Get-BucketObject -Bucket diag
$hasIds = ($raw | Where-Object { $_.PSObject.Properties['_ArrayId'] -and -not [string]::IsNullOrWhiteSpace($_._ArrayId) }).Count
if ($hasIds -eq 2) {
    Log "1: Pipe array tracking" "PASS" "$hasIds/2 items have _ArrayId"
} else {
    Log "1: Pipe array tracking" "FAIL" "Only $hasIds/2 items have _ArrayId"
}

$grouped = Get-BucketObject -Bucket diag -GroupArrays
if ($grouped -and $grouped.PSObject.Properties['_ArrayGroup'] -and $grouped._ArrayGroup -eq $true -and $grouped._ArrayItems.Count -eq 2) {
    Log "1: Pipe group read" "PASS" "ArrayItems=$($grouped._ArrayItems.Count)"
} else {
    Log "1: Pipe group read" "FAIL" "Type=$($grouped.GetType().Name), _ArrayGroup=$($grouped._ArrayGroup)"
}

# ============================================================
# TEST 2: -InputObject array with -ArrayTracking
# ============================================================
Write-Host "`n=== TEST 2: -InputObject array with -ArrayTracking ===" -ForegroundColor Cyan
Remove-Bucket "diag2" -Force -Confirm:$false -WarningAction SilentlyContinue
$arr = @(
    [PSCustomObject]@{ _Id = "t2a"; Seq = 1 }
    [PSCustomObject]@{ _Id = "t2b"; Seq = 2 }
)
New-BucketObject -Bucket diag2 -InputObject $arr -Key _Id -ArrayTracking -Quiet

$raw2 = Get-BucketObject -Bucket diag2
$hasIds2 = ($raw2 | Where-Object { $_.PSObject.Properties['_ArrayId'] -and -not [string]::IsNullOrWhiteSpace($_._ArrayId) }).Count
if ($hasIds2 -eq 2) {
    Log "2: InputObject tracking" "PASS" "$hasIds2/2 items have _ArrayId"
} else {
    Log "2: InputObject tracking" "FAIL" "Only $hasIds2/2 items have _ArrayId"
}

$grouped2 = Get-BucketObject -Bucket diag2 -GroupArrays
if ($grouped2 -and $grouped2.PSObject.Properties['_ArrayGroup'] -and $grouped2._ArrayGroup -eq $true -and $grouped2._ArrayItems.Count -eq 2) {
    Log "2: InputObject group read" "PASS" "ArrayItems=$($grouped2._ArrayItems.Count)"
} else {
    Log "2: InputObject group read" "FAIL" "Type=$($grouped2.GetType().Name), _ArrayGroup=$($grouped2._ArrayGroup)"
}

# ============================================================
# TEST 3: Pipe array WITHOUT -ArrayTracking (no metadata expected)
# ============================================================
Write-Host "`n=== TEST 3: Pipe array WITHOUT -ArrayTracking ===" -ForegroundColor Cyan
Remove-Bucket "diag3" -Force -Confirm:$false -WarningAction SilentlyContinue
@(
    [PSCustomObject]@{ _Id = "t3a"; Seq = 1 }
    [PSCustomObject]@{ _Id = "t3b"; Seq = 2 }
) | New-BucketObject -Bucket diag3 -Key _Id -Quiet

$raw3 = Get-BucketObject -Bucket diag3
$hasIds3 = ($raw3 | Where-Object { $_.PSObject.Properties['_ArrayId'] -and -not [string]::IsNullOrWhiteSpace($_._ArrayId) }).Count
if ($hasIds3 -eq 0) {
    Log "3: No tracking (pipe)" "PASS" "$hasIds3/2 have _ArrayId (correct)"
} else {
    Log "3: No tracking (pipe)" "FAIL" "$hasIds3/2 have _ArrayId (should be 0)"
}

$grouped3a = [System.Collections.ArrayList]::new()
Get-BucketObject -Bucket diag3 -GroupArrays | ForEach-Object { $null = $grouped3a.Add($_) }
$arrayGroups3 = $grouped3a | Where-Object { $_.PSObject.Properties['_ArrayGroup'] -and $_._ArrayGroup -eq $true }
if ($arrayGroups3.Count -eq 0) {
    Log "3: No grouping (pipe)" "PASS" "No array groups found (correct)"
} else {
    Log "3: No grouping (pipe)" "FAIL" "Found $($arrayGroups3.Count) array groups"
}

# ============================================================
# TEST 4: -InputObject array WITHOUT -ArrayTracking
# ============================================================
Write-Host "`n=== TEST 4: -InputObject array WITHOUT -ArrayTracking ===" -ForegroundColor Cyan
Remove-Bucket "diag4" -Force -Confirm:$false -WarningAction SilentlyContinue
$arr4 = @(
    [PSCustomObject]@{ _Id = "t4a"; Seq = 1 }
    [PSCustomObject]@{ _Id = "t4b"; Seq = 2 }
)
New-BucketObject -Bucket diag4 -InputObject $arr4 -Key _Id -Quiet

$raw4 = Get-BucketObject -Bucket diag4
$hasIds4 = ($raw4 | Where-Object { $_.PSObject.Properties['_ArrayId'] -and -not [string]::IsNullOrWhiteSpace($_._ArrayId) }).Count
if ($hasIds4 -eq 0) {
    Log "4: No tracking (InputObject)" "PASS" "$hasIds4/2 have _ArrayId (correct)"
} else {
    Log "4: No tracking (InputObject)" "FAIL" "$hasIds4/2 have _ArrayId (should be 0)"
}

# ============================================================
# TEST 5: Single item with -ArrayTracking (should NOT get _ArrayId)
# ============================================================
Write-Host "`n=== TEST 5: Single item with -ArrayTracking ===" -ForegroundColor Cyan
Remove-Bucket "diag5" -Force -Confirm:$false -WarningAction SilentlyContinue
[PSCustomObject]@{ _Id = "solo"; Seq = 1 } | New-BucketObject -Bucket diag5 -Key _Id -ArrayTracking -Quiet

$raw5 = Get-BucketObject -Bucket diag5
if (-not $raw5.PSObject.Properties['_ArrayId'] -or [string]::IsNullOrWhiteSpace($raw5._ArrayId)) {
    Log "5: Single item no group" "PASS" "No _ArrayId on single item (correct)"
} else {
    Log "5: Single item no group" "FAIL" "Has _ArrayId on single item"
}

# ============================================================
# TEST 6: Mixed bucket (tracked array + standalone)
# ============================================================
Write-Host "`n=== TEST 6: Mixed bucket ===" -ForegroundColor Cyan
Remove-Bucket "diag6" -Force -Confirm:$false -WarningAction SilentlyContinue
@(
    [PSCustomObject]@{ _Id = "m1"; Seq = 1 }
    [PSCustomObject]@{ _Id = "m2"; Seq = 2 }
    [PSCustomObject]@{ _Id = "m3"; Seq = 3 }
) | New-BucketObject -Bucket diag6 -Key _Id -ArrayTracking -Quiet
@{ _Id = "standalone"; Seq = 99 } | New-BucketObject -Bucket diag6 -Key _Id -Quiet

$grouped6 = [System.Collections.ArrayList]::new()
Get-BucketObject -Bucket diag6 -GroupArrays | ForEach-Object { $null = $grouped6.Add($_) }
$groups6 = $grouped6 | Where-Object { $_.PSObject.Properties['_ArrayGroup'] -and $_._ArrayGroup -eq $true }
$solos6 = $grouped6 | Where-Object { -not ($_.PSObject.Properties['_ArrayGroup'] -and $_._ArrayGroup -eq $true) }

if ($groups6.Count -eq 1 -and $groups6[0]._ArrayItems.Count -eq 3) {
    Log "6: Mixed - array group" "PASS" "1 group with 3 items"
} else {
    Log "6: Mixed - array group" "FAIL" "Groups: $($groups6.Count), Items: $($groups6[0]._ArrayItems.Count)"
}

# Check if standalone found (handle hashtable)
$soloFound = $false
foreach ($s in $solos6) {
    if ($s.PSObject.Properties['_Id'] -and $s._Id -eq 'standalone') { $soloFound = $true }
    elseif ($s -is [hashtable] -and $s['_Id'] -eq 'standalone') { $soloFound = $true }
}
if ($soloFound) {
    Log "6: Mixed - standalone" "PASS" "Standalone item found"
} else {
    Log "6: Mixed - standalone" "FAIL" "Standalone item not found ($($solos6.Count) non-group results)"
}

# ============================================================
# TEST 7: JSON format with -ArrayTracking
# ============================================================
Write-Host "`n=== TEST 7: JSON format with -ArrayTracking ===" -ForegroundColor Cyan
Remove-Bucket "diag7" -Force -Confirm:$false -WarningAction SilentlyContinue
@(
    [PSCustomObject]@{ _Id = "j1"; Seq = 1 }
    [PSCustomObject]@{ _Id = "j2"; Seq = 2 }
) | New-BucketObject -Bucket diag7 -Key _Id -ArrayTracking -AsJson -Quiet

$raw7 = Get-BucketObject -Bucket diag7
$hasIds7 = ($raw7 | Where-Object { $_.PSObject.Properties['_ArrayId'] -and -not [string]::IsNullOrWhiteSpace($_._ArrayId) }).Count
if ($hasIds7 -eq 2) {
    Log "7: JSON tracking" "PASS" "$hasIds7/2 items have _ArrayId"
} else {
    Log "7: JSON tracking" "FAIL" "Only $hasIds7/2 items have _ArrayId"
}

$grouped7 = Get-BucketObject -Bucket diag7 -GroupArrays
if ($grouped7 -and $grouped7.PSObject.Properties['_ArrayGroup'] -and $grouped7._ArrayGroup -eq $true -and $grouped7._ArrayItems.Count -eq 2) {
    Log "7: JSON group read" "PASS" "ArrayItems=$($grouped7._ArrayItems.Count)"
} else {
    Log "7: JSON group read" "FAIL" "Type=$($grouped7.GetType().Name), _ArrayGroup=$($grouped7._ArrayGroup)"
}

# ============================================================
# TEST 8: Order preservation
# ============================================================
Write-Host "`n=== TEST 8: Order preservation ===" -ForegroundColor Cyan
Remove-Bucket "diag8" -Force -Confirm:$false -WarningAction SilentlyContinue
@(
    [PSCustomObject]@{ _Id = "z1"; Seq = 10 }
    [PSCustomObject]@{ _Id = "z2"; Seq = 20 }
    [PSCustomObject]@{ _Id = "z3"; Seq = 30 }
) | New-BucketObject -Bucket diag8 -Key _Id -ArrayTracking -Quiet

$grouped8 = Get-BucketObject -Bucket diag8 -GroupArrays
if ($grouped8._ArrayItems[0].Seq -eq 10 -and $grouped8._ArrayItems[1].Seq -eq 20 -and $grouped8._ArrayItems[2].Seq -eq 30) {
    Log "8: Order preservation" "PASS" "Order: $($grouped8._ArrayItems.Seq -join ', ')"
} else {
    Log "8: Order preservation" "FAIL" "Order: $($grouped8._ArrayItems.Seq -join ', ') (expected: 10, 20, 30)"
}

# ============================================================
# Print summary
# ============================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " RESULTS" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$passCount = ($report | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($report | Where-Object { $_.Status -eq "FAIL" }).Count

$report | Format-Table -AutoSize

Write-Host "`nSummary: $passCount passed, $failCount failed" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })
