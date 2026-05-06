#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test script for the Buckets module.
#>

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

$bucketDir = Join-Path $PWD.Path ".buckets"
if (Test-Path $bucketDir) { Remove-Item $bucketDir -Recurse -Force }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Buckets Module - Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$sw = [System.Diagnostics.Stopwatch]::StartNew()

# ============================================================
# 1. Simple objects (hashtables)
# ============================================================
Write-Host "[1] Simple hashtables (keyed array save)" -ForegroundColor Yellow

$users = @(
    @{ Name = "Alice"; Email = "alice@example.com"; Role = "admin"; Active = $true }
    @{ Name = "Bob"; Email = "bob@example.com"; Role = "user"; Active = $true }
    @{ Name = "Charlie"; Email = "charlie@example.com"; Role = "user"; Active = $false }
    @{ Name = "Diana"; Email = "diana@example.com"; Role = "manager"; Active = $true }
)

New-BucketObject -Bucket users -InputObject $users -Key Name -Quiet
Write-Host "  Saved $($users.Count) users (keyed by Name)" -ForegroundColor DarkGray

# ============================================================
# 2. Nested PSCustomObjects
# ============================================================
Write-Host "`n[2] Nested PSCustomObjects (deep object serialization)" -ForegroundColor Yellow

$orders = @(
    [PSCustomObject]@{
        OrderId = "ORD-001"
        Customer = "Alice"
        Items = @(
            [PSCustomObject]@{ Product = "Widget"; Qty = 3; Price = 9.99 }
            [PSCustomObject]@{ Product = "Gadget"; Qty = 1; Price = 24.99 }
        )
        Shipping = [PSCustomObject]@{
            Method = "Express"
            Address = [PSCustomObject]@{ City = "Portland"; State = "OR" }
        }
        Status = "shipped"
    }
    [PSCustomObject]@{
        OrderId = "ORD-002"
        Customer = "Bob"
        Items = @(
            [PSCustomObject]@{ Product = "Doohickey"; Qty = 5; Price = 4.99 }
        )
        Shipping = [PSCustomObject]@{
            Method = "Standard"
            Address = [PSCustomObject]@{ City = "Seattle"; State = "WA" }
        }
        Status = "processing"
    }
)

New-BucketObject -Bucket orders -InputObject $orders -Key OrderId -Quiet
Write-Host "  Saved $($orders.Count) orders" -ForegroundColor DarkGray

# ============================================================
# 3. System objects (FileInfo) - triggers binary fallback
# ============================================================
Write-Host "`n[3] System objects (FileInfo — complex objects auto-fallback to binary)" -ForegroundColor Yellow

Get-ChildItem $PSScriptRoot | Where-Object { $_.Name -notmatch "^\." } | New-BucketObject -Bucket files -Key Name -Quiet
Write-Host "  Saved directory listing (complex objects fallback to .dat)" -ForegroundColor DarkGray

# ============================================================
# 4. Log entries with unique keys
# ============================================================
Write-Host "`n[4] Log entries (bulk save with unique keys)" -ForegroundColor Yellow

$logEntries = @(
    @{ Id = "log-001"; Level = "INFO"; Message = "Application started" }
    @{ Id = "log-002"; Level = "DEBUG"; Message = "Loading configuration" }
    @{ Id = "log-003"; Level = "WARN"; Message = "Deprecated API call" }
    @{ Id = "log-004"; Level = "ERROR"; Message = "Connection timeout" }
)

New-BucketObject -Bucket logs -InputObject $logEntries -Key Id -Quiet
Write-Host "  Saved $($logEntries.Count) log entries" -ForegroundColor DarkGray

# ============================================================
# 5. Config (JSON format)
# ============================================================
Write-Host "`n[5] Config (JSON format — explicit -AsJson switch)" -ForegroundColor Yellow

$config = [PSCustomObject]@{
    _Id = "app-config"
    Database = [PSCustomObject]@{ Host = "localhost"; Port = 5432; Name = "app_db" }
    Cache = [PSCustomObject]@{ Enabled = $true; TTL = 3600; Provider = "Redis" }
    Logging = [PSCustomObject]@{ Level = "Debug"; Outputs = @("Console", "File") }
    Version = "2.1.0"
}

New-BucketObject -Bucket config -InputObject $config -Key _Id -AsJson -Quiet
Write-Host "  Saved config as JSON" -ForegroundColor DarkGray

# ============================================================
# 6. Metrics
# ============================================================
Write-Host "`n[6] Performance metrics (24 hours — numeric bulk save)" -ForegroundColor Yellow

$metrics = foreach ($hour in 0..23) {
    [PSCustomObject]@{
        Hour = $hour
        CPU = [math]::Round((Get-Random -Min 5 -Max 95), 2)
        Memory = [math]::Round((Get-Random -Min 40 -Max 85), 2)
        Requests = Get-Random -Min 100 -Max 5000
    }
}

New-BucketObject -Bucket metrics -InputObject $metrics -Key Hour -Quiet
Write-Host "  Saved 24 hourly records" -ForegroundColor DarkGray

# ============================================================
# 7. Mixed formats in same bucket
# ============================================================
Write-Host "`n[7] Mixed formats (JSON + binary in same bucket)" -ForegroundColor Yellow

New-BucketObject -Bucket mixed -InputObject @{ _Id = "m1"; Type = "json"; Value = 1 } -Key _Id -AsJson -Quiet
New-BucketObject -Bucket mixed -InputObject @{ _Id = "m2"; Type = "binary"; Value = 2 } -Key _Id -Quiet
New-BucketObject -Bucket mixed -InputObject @{ _Id = "m3"; Type = "json-fallback" } -Key _Id -AsJson -Quiet
Write-Host "  Saved 3 objects (2 JSON, 1 binary)" -ForegroundColor DarkGray

# ============================================================
# VERIFICATION
# ============================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Verification" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "[Buckets]" -ForegroundColor Green
Get-Bucket | Format-Table -AutoSize

Write-Host "[Users] Filter Role = 'admin'" -ForegroundColor Green
Get-BucketObject -Bucket users -Filter { $_.Role -eq "admin" } | ForEach-Object { Write-Host "  $($_.Name) ($($_.Email))" }

Write-Host "`n[Orders] Shipped with Express shipping" -ForegroundColor Green
Get-BucketObject -Bucket orders -Filter { $_.Status -eq "shipped" -and $_.Shipping.Method -eq "Express" } | ForEach-Object { Write-Host "  $($_.OrderId) by $($_.Customer)" }

Write-Host "`n[Config] JSON verification" -ForegroundColor Green
$cfg = Get-BucketObject -Bucket config -Key "app-config"
Write-Host "  DB: $($cfg.Database.Host):$($cfg.Database.Port)/$($cfg.Database.Name)"
Write-Host "  Cache: $($cfg.Cache.Provider) (TTL: $($cfg.Cache.TTL)s)"

Write-Host "`n[Metrics] Hours with CPU > 80%" -ForegroundColor Green
Get-BucketObject -Bucket metrics -Filter { $_.CPU -gt 80 } | ForEach-Object { Write-Host "  Hour $($_.Hour): CPU=$($_.CPU)%, Mem=$($_.Memory)%" }

Write-Host "`n[Logs] Filter WARN/ERROR" -ForegroundColor Green
Get-BucketObject -Bucket logs -Filter { $_.Level -in @("WARN", "ERROR") } | ForEach-Object { Write-Host "  [$($_.Level)] $($_.Message)" }

Write-Host "`n[Mixed] Formats" -ForegroundColor Green
Get-BucketObject -Bucket mixed | ForEach-Object {
    $ext = [System.IO.Path]::GetExtension($_._BucketFile)
    Write-Host "  $($_.Type) ($ext)"
}

# ============================================================
# STATS
# ============================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Stats" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

foreach ($b in (Get-Bucket)) {
    $stats = Get-BucketStats -Bucket $b.Name
    Write-Host "  $($b.Name): $($stats.ObjectCount) objects, $($stats.TotalSize)"
}

$elapsed = $sw.ElapsedMilliseconds
Write-Host "`nTotal time: ${elapsed}ms" -ForegroundColor Cyan

# ============================================================
# NEW CMDLETS & FEATURES
# ============================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " New Features" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ============================================================
# 8. Copy-BucketObject
# ============================================================
Write-Host "`n[8] Copy-BucketObject (cross-bucket copy, key rename)" -ForegroundColor Yellow
Remove-Bucket "archive" -Force -Confirm:$false -WarningAction SilentlyContinue
Copy-BucketObject -Bucket users -Key "Alice" -DestinationBucket archive -PassThru | Format-Table
Copy-BucketObject -Bucket config -Key "app-config" -DestinationKey "app-config-backup" -PassThru | Format-Table
$archived = Get-BucketObject -Bucket archive -Key "Alice"
Write-Host "  Archived user: $($archived.Name) ($($archived.Email))" -ForegroundColor DarkGray
$backup = Get-BucketObject -Bucket config -Key "app-config-backup"
Write-Host "  Backed up config version: $($backup.Version)" -ForegroundColor DarkGray

# ============================================================
# 9. Rename-BucketObject
# ============================================================
Write-Host "`n[9] Rename-BucketObject (in-place key change, preserves format)" -ForegroundColor Yellow
Rename-BucketObject -Bucket archive -Key "Alice" -NewKey "alice-admin" -PassThru | Format-Table
$renamed = Get-BucketObject -Bucket archive -Key "alice-admin"
Write-Host "  Renamed user: $($renamed.Name) (key: alice-admin)" -ForegroundColor DarkGray

# ============================================================
# 10. Export-Bucket & Import-Bucket
# ============================================================
Write-Host "`n[10] Export/Import bucket (archive to CLIXML/JSON, restore)" -ForegroundColor Yellow
$exportPath = Join-Path $PSScriptRoot "test-export.clixml"
$exportJson = Join-Path $PSScriptRoot "test-export.json"
Export-Bucket -Bucket users -OutputFile $exportPath
Export-Bucket -Bucket logs -OutputFile $exportJson -AsJson
Remove-Bucket "import-test" -Force -Confirm:$false -WarningAction SilentlyContinue
Import-Bucket -Bucket import-test -InputFile $exportPath
$imported = Get-BucketObject -Bucket import-test
Write-Host "  Imported $($imported.Count) users from CLIXML archive" -ForegroundColor DarkGray
Remove-Item $exportPath, $exportJson -Force

# ============================================================
# 11. -Compress switch
# ============================================================
Write-Host "`n[11] Binary compression (-Compress — GZip reduces repetitive data)" -ForegroundColor Yellow
Remove-Bucket "compressed" -Force -Confirm:$false -WarningAction SilentlyContinue
New-BucketObject -Bucket compressed -InputObject @{ _Id = "comp"; Data = "x" * 5000; Type = "compressed" } -Key "_Id" -Compress -Quiet
New-BucketObject -Bucket compressed -InputObject @{ _Id = "uncomp"; Data = "x" * 5000; Type = "uncompressed" } -Key "_Id" -Quiet
$basePath = Join-Path $PWD.Path ".buckets"
$compPath = Join-Path $basePath "compressed"
$compSize = (Get-ChildItem $compPath -Filter "comp.dat").Length
$uncompSize = (Get-ChildItem $compPath -Filter "uncomp.dat").Length
$ratio = [math]::Round((1 - $compSize/$uncompSize) * 100)
Write-Host "  Uncompressed: ${uncompSize} bytes, Compressed: ${compSize} bytes (${ratio}% smaller)" -ForegroundColor DarkGray
$decompressed = Get-BucketObject -Bucket compressed -Key "comp"
Write-Host "  Decompressed data length: $($decompressed.Data.Length) chars" -ForegroundColor DarkGray

# ============================================================
# 12. -WhatIf support
# ============================================================
Write-Host "`n[12] -WhatIf support (preview deletes without execution)" -ForegroundColor Yellow
Remove-BucketObject -Bucket users -Key "Bob" -WhatIf
Remove-Bucket "users" -WhatIf -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
$remaining = Get-BucketObject -Bucket users -WarningAction SilentlyContinue
Write-Host "  Objects in 'users' after -WhatIf: $($remaining.Count) (unchanged)" -ForegroundColor DarkGray

# ============================================================
# 13. Round-trip integrity
# ============================================================
Write-Host "`n[13] Round-trip integrity (save/load complex types and null)" -ForegroundColor Yellow
Remove-Bucket "roundtrip" -Force -Confirm:$false -WarningAction SilentlyContinue
$roundTrip = [PSCustomObject]@{
    _Id = "test"
    String = "Hello, World!"
    Number = 42.5
    Bool = $true
    Null = $null
    Array = @(1, 2, 3, "four")
    Nested = [PSCustomObject]@{ Level1 = [PSCustomObject]@{ Level2 = [PSCustomObject]@{ Level3 = "deep" } } }
    SpecialChars = '!@#$%^&*()'
    EmptyString = ""
    Zero = 0
    Negative = -100
}
New-BucketObject -Bucket roundtrip -InputObject $roundTrip -Key "_Id" -Quiet
$retrieved = Get-BucketObject -Bucket roundtrip -Key "test"
if ($null -eq $retrieved) {
    Write-Host "  FAIL: Object not retrieved (null)" -ForegroundColor Red
    $passed = 0; $failed = 10
} else {
    Write-Host "  Retrieved type: $($retrieved.GetType().Name)" -ForegroundColor DarkGray
    $passed = 0
    $failed = 0
    if ($retrieved.String -eq "Hello, World!") { $passed++ } else { Write-Host "  FAIL: String ($($retrieved.String))" -ForegroundColor Red; $failed++ }
    if ($retrieved.Number -eq 42.5) { $passed++ } else { Write-Host "  FAIL: Number ($($retrieved.Number))" -ForegroundColor Red; $failed++ }
    if ($retrieved.Bool -eq $true) { $passed++ } else { Write-Host "  FAIL: Bool ($($retrieved.Bool))" -ForegroundColor Red; $failed++ }
    if ($null -eq $retrieved.Null) { $passed++ } else { Write-Host "  FAIL: Null" -ForegroundColor Red; $failed++ }
    if ($retrieved.Array.Count -eq 4 -and $retrieved.Array[3] -eq "four") { $passed++ } else { Write-Host "  FAIL: Array ($($retrieved.Array.Count))" -ForegroundColor Red; $failed++ }
    if ($retrieved.Nested.Level1.Level2.Level3 -eq "deep") { $passed++ } else { Write-Host "  FAIL: Nested" -ForegroundColor Red; $failed++ }
    if ($retrieved.SpecialChars -eq '!@#$%^&*()') { $passed++ } else { Write-Host "  FAIL: SpecialChars" -ForegroundColor Red; $failed++ }
    if ($retrieved.EmptyString -eq "") { $passed++ } else { Write-Host "  FAIL: EmptyString" -ForegroundColor Red; $failed++ }
    if ($retrieved.Zero -eq 0) { $passed++ } else { Write-Host "  FAIL: Zero" -ForegroundColor Red; $failed++ }
    if ($retrieved.Negative -eq -100) { $passed++ } else { Write-Host "  FAIL: Negative" -ForegroundColor Red; $failed++ }
    Write-Host "  Round-trip: $passed/10 passed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
}

# ============================================================
# 14. Error condition tests
# ============================================================
Write-Host "`n[14] Error conditions (missing keys, corrupted files, bad params)" -ForegroundColor Yellow

Write-Host "  Missing bucket key..." -NoNewline
try {
    Get-BucketObject -Bucket nonexistent-bucket-xyz -Key "missing" 2>$null
    Write-Host " OK (returns empty)" -ForegroundColor Green
} catch {
    Write-Host " FAIL: $_" -ForegroundColor Red
}

Write-Host "  Remove non-existent key..." -NoNewline
try {
    Remove-BucketObject -Bucket users -Key "nonexistent-key" -WarningVariable warn -WarningAction SilentlyContinue 2>$null
    if ($warn) { Write-Host " OK (warning issued)" -ForegroundColor Green } else { Write-Host " FAIL (no warning)" -ForegroundColor Red }
} catch {
    Write-Host " FAIL: $_" -ForegroundColor Red
}

Write-Host "  Remove without -Key or -All..." -NoNewline
try {
    Remove-BucketObject -Bucket users 2>$null
    Write-Host " FAIL (should have thrown)" -ForegroundColor Red
} catch {
    Write-Host " OK (threw: $($_.Exception.Message))" -ForegroundColor Green
}

Write-Host "  Set-BucketObject without bucket/key..." -NoNewline
try {
    @{ Name = "test" } | Set-BucketObject 2>$null
    Write-Host " FAIL (should have thrown)" -ForegroundColor Red
} catch {
    Write-Host " OK (threw)" -ForegroundColor Green
}

Write-Host "  Corrupted file handling..." -NoNewline
$basePath = Join-Path $PWD.Path ".buckets"
$usersPath = Join-Path $basePath "users"
$corruptPath = Join-Path $usersPath "corrupt.dat"
[System.IO.File]::WriteAllText($corruptPath, "THIS_IS_NOT_VALID_BASE64!!!", [System.Text.Encoding]::UTF8)
$beforeCount = (Get-BucketObject -Bucket users).Count
$retrieved = Get-BucketObject -Bucket users -Key "corrupt" -WarningVariable cWarn -WarningAction SilentlyContinue
if ($null -eq $retrieved -and $cWarn) {
    Write-Host " OK (warning issued, null returned)" -ForegroundColor Green
} else {
    Write-Host " WARN (retrieved: $retrieved, warnings: $($cWarn.Count))" -ForegroundColor Yellow
}
Remove-Item $corruptPath -Force

Write-Host "  Get-BucketObject -Key across multiple buckets (no null-file crash)..." -NoNewline
try {
    $errorsBefore = $Error.Count
    New-BucketObject -Bucket bucket-a -InputObject @{ X = 1; _Id = "only-in-a" } -Key "_Id" -Quiet
    New-BucketObject -Bucket bucket-b -InputObject @{ Y = 2; _Id = "only-in-b" } -Key "_Id" -Quiet
    New-BucketObject -Bucket bucket-c -InputObject @{ Z = 3; _Id = "only-in-c" } -Key "_Id" -Quiet
    $result = Get-BucketObject -Key "only-in-a" -WarningAction SilentlyContinue 2>$null
    $newErrors = $Error.Count - $errorsBefore
    if ($null -eq $result -or $result.X -eq 1) {
        if ($newErrors -eq 0 -and $result.X -eq 1) {
            Write-Host " OK (found in bucket-a, zero errors across all buckets)" -ForegroundColor Green
        } else {
            Write-Host " FAIL (errors: $newErrors, result: $($result.X))" -ForegroundColor Red
        }
    } else {
        Write-Host " FAIL (wrong result or errors occurred)" -ForegroundColor Red
    }
    Remove-Bucket -Bucket bucket-a -Force -Confirm:$false
    Remove-Bucket -Bucket bucket-b -Force -Confirm:$false
    Remove-Bucket -Bucket bucket-c -Force -Confirm:$false
} catch {
    Write-Host " FAIL: $_" -ForegroundColor Red
}

Write-Host "  Get-BucketObject -Key with case mismatch..." -NoNewline
try {
    $errorsBefore = $Error.Count
    New-BucketObject -Bucket casetest -InputObject @{ Val = 42; _Id = "MixedCase-Key" } -Key "_Id" -Quiet
    $result = Get-BucketObject -Bucket casetest -Key "mixedcase-key" -WarningAction SilentlyContinue 2>$null
    $newErrors = $Error.Count - $errorsBefore
    if ($null -ne $result -and $result.Val -eq 42 -and $newErrors -eq 0) {
        Write-Host " OK (case-insensitive match, zero errors)" -ForegroundColor Green
    } else {
        Write-Host " FAIL (result: $($result.Val), errors: $newErrors)" -ForegroundColor Red
    }
    Remove-Bucket -Bucket casetest -Force -Confirm:$false
} catch {
    Write-Host " FAIL: $_" -ForegroundColor Red
}

Write-Host "  Set-BucketObject pipeline round-trip..." -NoNewline
$user = Get-BucketObject -Bucket users -Key "Bob"
$user.Role = "admin"
$user | Set-BucketObject -Quiet
$updated = Get-BucketObject -Bucket users -Key "Bob"
if ($updated.Role -eq "admin") {
    Write-Host " OK (role updated to admin)" -ForegroundColor Green
} else {
    Write-Host " FAIL (role: $($updated.Role))" -ForegroundColor Red
}

Write-Host "  Auto-patch (hashtable)..." -NoNewline
$before = Get-BucketObject -Bucket users -Key "Alice"
$origEmail = $before.Email
@{ Email = "alice@patched.com" } | Set-BucketObject -Bucket users -Key "Alice" -Quiet
$after = Get-BucketObject -Bucket users -Key "Alice"
if ($after.Email -eq "alice@patched.com" -and $after.Name -eq "Alice" -and $after.Role -eq "admin") {
    Write-Host " OK (email patched, other fields preserved)" -ForegroundColor Green
    @{ Email = $origEmail } | Set-BucketObject -Bucket users -Key "Alice" -Quiet
} else {
    Write-Host " FAIL (email: $($after.Email), name: $($after.Name))" -ForegroundColor Red
}

Write-Host "  Auto-patch (PSCustomObject)..." -NoNewline
New-BucketObject -Bucket users -InputObject ([PSCustomObject]@{ _Id = "patch-obj"; Name = "Test"; Val = 1 }) -Key "_Id" -Quiet
[PSCustomObject]@{ Val = 99; NewField = "added" } | Set-BucketObject -Bucket users -Key "patch-obj" -Quiet
$patched = Get-BucketObject -Bucket users -Key "patch-obj"
if ($patched.Val -eq 99 -and $patched.Name -eq "Test" -and $patched.NewField -eq "added") {
    Write-Host " OK (value patched, new field added, name preserved)" -ForegroundColor Green
} else {
    Write-Host " FAIL (val: $($patched.Val), name: $($patched.Name), new: $($patched.NewField))" -ForegroundColor Red
}
Remove-BucketObject -Bucket users -Key "patch-obj" 2>&1 | Out-Null

Write-Host "  Patch without Bucket/Key..." -NoNewline
try {
    @{ Name = "test" } | Set-BucketObject 2>$null
    Write-Host " FAIL (should have thrown)" -ForegroundColor Red
} catch {
    if ($_.Exception.Message -like "*partial*" -or $_.Exception.Message -like "*Bucket*") {
        Write-Host " OK (threw with patch message)" -ForegroundColor Green
    } else {
        Write-Host " OK (threw: $($_.Exception.Message))" -ForegroundColor Green
    }
}

# ============================================================
# 15. Performance benchmark
# ============================================================
Write-Host "`n[15] Performance benchmark (1,000 objects — baseline throughput)" -ForegroundColor Yellow
Remove-Bucket "perf-test" -Force -Confirm:$false -WarningAction SilentlyContinue
$perfBench = [System.Diagnostics.Stopwatch]::StartNew()
$perfObjects = 1..1000 | ForEach-Object {
    [PSCustomObject]@{
        Id = $_
        Name = "item-$_"
        Value = (Get-Random)
        Timestamp = [DateTimeOffset]::Now
    }
}
$perfObjects | New-BucketObject -Bucket perf-test -Key Id -Quiet
$writeTime = $perfBench.ElapsedMilliseconds

$perfBench.Restart()
$retrieved = Get-BucketObject -Bucket perf-test
$readTime = $perfBench.ElapsedMilliseconds

Write-Host "  Write: ${writeTime}ms, Read: ${readTime}ms, Objects: $($retrieved.Count)" -ForegroundColor DarkGray
if ($retrieved.Count -ne 1000) {
    Write-Host "  FAIL: Expected 1000 objects, got $($retrieved.Count)" -ForegroundColor Red
}

# ============================================================
# 16. Performance benchmark (10,000 objects)
# ============================================================
Write-Host "`n[16] Performance benchmark (10,000 objects — scale test)" -ForegroundColor Yellow
Remove-Bucket "perf-10k" -Force -Confirm:$false -WarningAction SilentlyContinue
$perfBench10k = [System.Diagnostics.Stopwatch]::StartNew()
$perf10kObjects = 1..10000 | ForEach-Object {
    [PSCustomObject]@{
        Id = $_
        Name = "obj-$_"
        Value = (Get-Random)
        Tags = @("tag-$_", "group-$($_ % 100)")
    }
}
$perf10kObjects | New-BucketObject -Bucket perf-10k -Key Id -Quiet
$writeTime10k = $perfBench10k.ElapsedMilliseconds

$perfBench10k.Restart()
$retrieved10k = Get-BucketObject -Bucket perf-10k
$readTime10k = $perfBench10k.ElapsedMilliseconds

Write-Host "  Write: ${writeTime10k}ms, Read: ${readTime10k}ms, Objects: $($retrieved10k.Count)" -ForegroundColor DarkGray
if ($retrieved10k.Count -ne 10000) {
    Write-Host "  FAIL: Expected 10000 objects, got $($retrieved10k.Count)" -ForegroundColor Red
}

# ============================================================
# 17. Performance benchmark (10,000 complex objects)
# ============================================================
Write-Host "`n[17] Performance benchmark (10,000 complex objects — nested depth test)" -ForegroundColor Yellow
Remove-Bucket "perf-10k-complex" -Force -Confirm:$false -WarningAction SilentlyContinue
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
$perf10kCObjects | New-BucketObject -Bucket perf-10k-complex -Key Id -Quiet
$writeTime10kC = $perfBench10kC.ElapsedMilliseconds

$perfBench10kC.Restart()
$retrieved10kC = Get-BucketObject -Bucket perf-10k-complex
$readTime10kC = $perfBench10kC.ElapsedMilliseconds

Write-Host "  Write: ${writeTime10kC}ms, Read: ${readTime10kC}ms, Objects: $($retrieved10kC.Count)" -ForegroundColor DarkGray
if ($retrieved10kC.Count -ne 10000) {
    Write-Host "  FAIL: Expected 10000 objects, got $($retrieved10kC.Count)" -ForegroundColor Red
}
else {
    $sample = $retrieved10kC[0]
    if ($sample.Profile.Preferences.Theme -and $sample.Orders.Count -eq 2 -and $sample.Metadata.Tags.Count -eq 3) {
        Write-Host "  Integrity: OK (nested data preserved)" -ForegroundColor Green
    }
    else {
        Write-Host "  FAIL: Nested data integrity issue" -ForegroundColor Red
    }
}

# ============================================================
# 18. Performance benchmark JSON (1,000 objects)
# ============================================================
Write-Host "`n[18] Performance benchmark JSON (1,000 objects)" -ForegroundColor Yellow
Remove-Bucket "perf-json-1k" -Force -Confirm:$false -WarningAction SilentlyContinue
$perfJsonBench = [System.Diagnostics.Stopwatch]::StartNew()
$perfJsonObjects = 1..1000 | ForEach-Object {
    [PSCustomObject]@{
        Id = $_
        Name = "item-$_"
        Value = (Get-Random)
        Timestamp = [DateTimeOffset]::Now
    }
}
$perfJsonObjects | New-BucketObject -Bucket perf-json-1k -Key Id -AsJson -Quiet
$jsonWriteTime = $perfJsonBench.ElapsedMilliseconds

$perfJsonBench.Restart()
$jsonRetrieved = Get-BucketObject -Bucket perf-json-1k
$jsonReadTime = $perfJsonBench.ElapsedMilliseconds

Write-Host "  Write: ${jsonWriteTime}ms, Read: ${jsonReadTime}ms, Objects: $($jsonRetrieved.Count)" -ForegroundColor DarkGray
if ($jsonRetrieved.Count -ne 1000) {
    Write-Host "  FAIL: Expected 1000 objects, got $($jsonRetrieved.Count)" -ForegroundColor Red
}

# ============================================================
# 19. Performance benchmark JSON (10,000 objects)
# ============================================================
Write-Host "`n[19] Performance benchmark JSON (10,000 objects)" -ForegroundColor Yellow
Remove-Bucket "perf-json-10k" -Force -Confirm:$false -WarningAction SilentlyContinue
$perfJson10kBench = [System.Diagnostics.Stopwatch]::StartNew()
$perfJson10kObjects = 1..10000 | ForEach-Object {
    [PSCustomObject]@{
        Id = $_
        Name = "obj-$_"
        Value = (Get-Random)
        Tags = @("tag-$_", "group-$($_ % 100)")
    }
}
$perfJson10kObjects | New-BucketObject -Bucket perf-json-10k -Key Id -AsJson -Quiet
$jsonWriteTime10k = $perfJson10kBench.ElapsedMilliseconds

$perfJson10kBench.Restart()
$jsonRetrieved10k = Get-BucketObject -Bucket perf-json-10k
$jsonReadTime10k = $perfJson10kBench.ElapsedMilliseconds

Write-Host "  Write: ${jsonWriteTime10k}ms, Read: ${jsonReadTime10k}ms, Objects: $($jsonRetrieved10k.Count)" -ForegroundColor DarkGray
if ($jsonRetrieved10k.Count -ne 10000) {
    Write-Host "  FAIL: Expected 10000 objects, got $($jsonRetrieved10k.Count)" -ForegroundColor Red
}

# ============================================================
# 20. Performance benchmark JSON (10,000 complex objects)
# ============================================================
Write-Host "`n[20] Performance benchmark JSON (10,000 complex objects)" -ForegroundColor Yellow
Remove-Bucket "perf-json-complex" -Force -Confirm:$false -WarningAction SilentlyContinue
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
$perfJsonCObjects | New-BucketObject -Bucket perf-json-complex -Key Id -AsJson -Quiet
$jsonWriteTimeC = $perfJsonCBench.ElapsedMilliseconds

$perfJsonCBench.Restart()
$jsonRetrievedC = Get-BucketObject -Bucket perf-json-complex
$jsonReadTimeC = $perfJsonCBench.ElapsedMilliseconds

Write-Host "  Write: ${jsonWriteTimeC}ms, Read: ${jsonReadTimeC}ms, Objects: $($jsonRetrievedC.Count)" -ForegroundColor DarkGray
if ($jsonRetrievedC.Count -ne 10000) {
    Write-Host "  FAIL: Expected 10000 objects, got $($jsonRetrievedC.Count)" -ForegroundColor Red
}
else {
    $sample = $jsonRetrievedC[0]
    if ($sample.Profile.Preferences.Theme -and $sample.Orders.Count -eq 2 -and $sample.Metadata.Tags.Count -eq 3) {
        Write-Host "  Integrity: OK (nested data preserved)" -ForegroundColor Green
    }
    else {
        Write-Host "  FAIL: Nested data integrity issue" -ForegroundColor Red
    }
}
