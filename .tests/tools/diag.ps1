# Array Subdirectory Diagnostic Script
# Run this and paste the output back

Import-Module "$PSScriptRoot/../../Buckets/Buckets.psm1" -Force

$createdBuckets = [System.Collections.ArrayList]::new()
function Use-Bucket {
    param([string]$Bucket)
    $null = $createdBuckets.Add($Bucket)
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$mod = Get-Module Buckets
$pwsh = "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
$os = if ($IsMacOS) { "macOS" } elseif ($IsLinux) { "Linux" } else { "Windows" }
$sep = "=" * 52

function Write-InfoBlock {
    param([string]$Mode)
    if ($Mode -eq "top") {
        Write-Host $sep -ForegroundColor DarkGray
        Write-Host " Buckets Module" -NoNewline -ForegroundColor Blue
        Write-Host " v$($mod.Version)" -NoNewline -ForegroundColor Magenta
        Write-Host " Diagnostics" -ForegroundColor DarkGray
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

$report = [System.Collections.ArrayList]::new()

function Log {
    param($Test, $Status, $Detail = "")
    $null = $report.Add([PSCustomObject]@{ Test = $Test; Status = $Status; Detail = $Detail })
}

# ============================================================
# TEST 1: Pipe array with -ArrayKey
# ============================================================
Write-Host "`n=== TEST 1: Pipe array with -ArrayKey ===" -ForegroundColor Cyan
@(
    [PSCustomObject]@{ _Id = "t1a"; Seq = 1 }
    [PSCustomObject]@{ _Id = "t1b"; Seq = 2 }
) | New-BucketObject -Bucket diag -KeyProperty _Id -ArrayKey "test1" -Quiet
Use-Bucket "diag"

$raw = Get-BucketObject -Bucket diag
if ($raw.Count -eq 2 -and $raw[0]._BucketKey -like ".arrays/*") {
    Log "1: Pipe array save" "PASS" "$($raw.Count) items, stored in .arrays/"
} else {
    Log "1: Pipe array save" "FAIL" "$($raw.Count) items, _BucketKey=$($raw[0]._BucketKey)"
}

$grouped = Get-BucketObject -Bucket diag -GroupArrays
if ($grouped -and $grouped.PSObject.Properties['_ArrayGroup'] -and $grouped._ArrayGroup -eq $true -and $grouped._ArrayItems.Count -eq 2) {
    Log "1: Pipe group read" "PASS" "ArrayItems=$($grouped._ArrayItems.Count)"
} else {
    Log "1: Pipe group read" "FAIL" "Type=$($grouped.GetType().Name), _ArrayGroup=$($grouped._ArrayGroup)"
}

# ============================================================
# TEST 2: -InputObject array with -ArrayKey
# ============================================================
Write-Host "`n=== TEST 2: -InputObject array with -ArrayKey ===" -ForegroundColor Cyan
Remove-Bucket "diag2" -Force -Confirm:$false -WarningAction SilentlyContinue
$arr = @(
    [PSCustomObject]@{ _Id = "t2a"; Seq = 1 }
    [PSCustomObject]@{ _Id = "t2b"; Seq = 2 }
)
New-BucketObject -Bucket diag2 -InputObject $arr -KeyProperty _Id -ArrayKey "test2" -Quiet
Use-Bucket "diag2"

$raw2 = Get-BucketObject -Bucket diag2
if ($raw2.Count -eq 2) {
    Log "2: InputObject save" "PASS" "$($raw2.Count) items"
} else {
    Log "2: InputObject save" "FAIL" "$($raw2.Count) items"
}

$grouped2 = Get-BucketObject -Bucket diag2 -GroupArrays
if ($grouped2 -and $grouped2.PSObject.Properties['_ArrayGroup'] -and $grouped2._ArrayGroup -eq $true -and $grouped2._ArrayItems.Count -eq 2) {
    Log "2: InputObject group read" "PASS" "ArrayItems=$($grouped2._ArrayItems.Count)"
} else {
    Log "2: InputObject group read" "FAIL" "Type=$($grouped2.GetType().Name), _ArrayGroup=$($grouped2._ArrayGroup)"
}

# ============================================================
# TEST 3: Without -ArrayKey (no grouping)
# ============================================================
Write-Host "`n=== TEST 3: Pipe array WITHOUT -ArrayKey ===" -ForegroundColor Cyan
Remove-Bucket "diag3" -Force -Confirm:$false -WarningAction SilentlyContinue
@(
    [PSCustomObject]@{ _Id = "t3a"; Seq = 1 }
    [PSCustomObject]@{ _Id = "t3b"; Seq = 2 }
) | New-BucketObject -Bucket diag3 -KeyProperty _Id -Quiet
Use-Bucket "diag3"

$raw3 = Get-BucketObject -Bucket diag3
if ($raw3.Count -eq 2 -and $raw3[0]._BucketKey -notlike ".arrays/*") {
    Log "3: No grouping (pipe)" "PASS" "$($raw3.Count) items, stored in root"
} else {
    Log "3: No grouping (pipe)" "FAIL" "$($raw3.Count) items, _BucketKey=$($raw3[0]._BucketKey)"
}

# ============================================================
# TEST 4: Array with duplicate keys (collision suffixing)
# ============================================================
Write-Host "`n=== TEST 4: Duplicate key collision ===" -ForegroundColor Cyan
Remove-Bucket "diag4" -Force -Confirm:$false -WarningAction SilentlyContinue
@(
    [PSCustomObject]@{ Name = "Alice"; Seq = 1 }
    [PSCustomObject]@{ Name = "Alice"; Seq = 2 }
    [PSCustomObject]@{ Name = "Bob"; Seq = 3 }
) | New-BucketObject -Bucket diag4 -KeyProperty Name -ArrayKey "dups" -Quiet
Use-Bucket "diag4"

$raw4 = Get-BucketObject -Bucket diag4
$keys = $raw4._BucketKey | Sort-Object
if ($keys -contains ".arrays/dups/Alice" -and $keys -contains ".arrays/dups/Alice_1" -and $keys -contains ".arrays/dups/Bob") {
    Log "4: Collision suffixing" "PASS" "Keys: $($keys -join ', ')"
} else {
    Log "4: Collision suffixing" "FAIL" "Keys: $($keys -join ', ')"
}

# ============================================================
# TEST 5: Prefix match retrieval
# ============================================================
Write-Host "`n=== TEST 5: Prefix match ===" -ForegroundColor Cyan
$matched = Get-BucketObject -Bucket diag4 -Key "Alice"
if ($matched.Count -eq 2) {
    Log "5: Prefix match" "PASS" "Found $($matched.Count) Alice items"
} else {
    Log "5: Prefix match" "FAIL" "Found $($matched.Count) items"
}

# ============================================================
# TEST 6: Mixed bucket (array group + standalone)
# ============================================================
Write-Host "`n=== TEST 6: Mixed bucket ===" -ForegroundColor Cyan
Remove-Bucket "diag6" -Force -Confirm:$false -WarningAction SilentlyContinue
@(
    [PSCustomObject]@{ _Id = "m1"; Seq = 1 }
    [PSCustomObject]@{ _Id = "m2"; Seq = 2 }
    [PSCustomObject]@{ _Id = "m3"; Seq = 3 }
) | New-BucketObject -Bucket diag6 -KeyProperty _Id -ArrayKey "myarray" -Quiet
@{ _Id = "standalone"; Seq = 99 } | New-BucketObject -Bucket diag6 -KeyProperty _Id -Quiet
Use-Bucket "diag6"

$grouped6 = [System.Collections.ArrayList]::new()
Get-BucketObject -Bucket diag6 -GroupArrays | ForEach-Object { $null = $grouped6.Add($_) }
$groups6 = $grouped6 | Where-Object { $_.PSObject.Properties['_ArrayGroup'] -and $_._ArrayGroup -eq $true }
$solos6 = $grouped6 | Where-Object { -not ($_.PSObject.Properties['_ArrayGroup'] -and $_._ArrayGroup -eq $true) }

if ($groups6.Count -eq 1 -and $groups6[0]._ArrayItems.Count -eq 3) {
    Log "6: Mixed - array group" "PASS" "1 group with 3 items"
} else {
    Log "6: Mixed - array group" "FAIL" "Groups: $($groups6.Count), Items: $($groups6[0]._ArrayItems.Count)"
}

$soloFound = $false
foreach ($s in $solos6) {
    if ($s.PSObject.Properties['_Id'] -and $s._Id -eq 'standalone') { $soloFound = $true }
}
if ($soloFound) {
    Log "6: Mixed - standalone" "PASS" "Standalone item found"
} else {
    Log "6: Mixed - standalone" "FAIL" "Standalone item not found ($($solos6.Count) non-group results)"
}

# ============================================================
# TEST 7: JSON format with -ArrayKey
# ============================================================
Write-Host "`n=== TEST 7: JSON format with -ArrayKey ===" -ForegroundColor Cyan
Remove-Bucket "diag7" -Force -Confirm:$false -WarningAction SilentlyContinue
@(
    [PSCustomObject]@{ _Id = "j1"; Seq = 1 }
    [PSCustomObject]@{ _Id = "j2"; Seq = 2 }
) | New-BucketObject -Bucket diag7 -KeyProperty _Id -ArrayKey "jsonarr" -AsJson -Quiet
Use-Bucket "diag7"

$raw7 = Get-BucketObject -Bucket diag7
if ($raw7.Count -eq 2) {
    Log "7: JSON save" "PASS" "$($raw7.Count) items"
} else {
    Log "7: JSON save" "FAIL" "$($raw7.Count) items"
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
) | New-BucketObject -Bucket diag8 -KeyProperty _Id -ArrayKey "ordered" -Quiet
Use-Bucket "diag8"

$grouped8 = Get-BucketObject -Bucket diag8 -GroupArrays
if ($grouped8._ArrayItems[0].Seq -eq 10 -and $grouped8._ArrayItems[1].Seq -eq 20 -and $grouped8._ArrayItems[2].Seq -eq 30) {
    Log "8: Order preservation" "PASS" "Order: $($grouped8._ArrayItems.Seq -join ', ')"
} else {
    Log "8: Order preservation" "FAIL" "Order: $($grouped8._ArrayItems.Seq -join ', ') (expected: 10, 20, 30)"
}

# ============================================================
# TEST 9: -ArrayKey filter
# ============================================================
Write-Host "`n=== TEST 9: -ArrayKey filter ===" -ForegroundColor Cyan
Remove-Bucket "diag9" -Force -Confirm:$false -WarningAction SilentlyContinue
@(
    [PSCustomObject]@{ _Id = "a1"; Group = "alpha" }
    [PSCustomObject]@{ _Id = "a2"; Group = "alpha" }
) | New-BucketObject -Bucket diag9 -KeyProperty _Id -ArrayKey "alpha" -Quiet
Use-Bucket "diag9"
@(
    [PSCustomObject]@{ _Id = "b1"; Group = "beta" }
    [PSCustomObject]@{ _Id = "b2"; Group = "beta" }
) | New-BucketObject -Bucket diag9 -KeyProperty _Id -ArrayKey "beta" -Quiet

$alpha = Get-BucketObject -Bucket diag9 -ArrayKey alpha
if ($alpha.Count -eq 2 -and ($alpha | Where-Object { $_.Group -eq "beta" }).Count -eq 0) {
    Log "9: ArrayKey filter" "PASS" "Only alpha items returned"
} else {
    Log "9: ArrayKey filter" "FAIL" "$($alpha.Count) items returned"
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

foreach ($bucket in $createdBuckets) {
    Remove-Bucket -Bucket $bucket -Force -Confirm:$false -WarningAction SilentlyContinue
}

Write-InfoBlock -Mode bottom
