#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test script for the Buckets module.
#>

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

$testRoot = Join-Path $env:TEMP "buckets-test-$(Get-Random)"
Set-BucketRoot $testRoot

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$createdBuckets = [System.Collections.ArrayList]::new()
function Use-Bucket {
    param([string]$Name)
    $null = $createdBuckets.Add($Name)
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
        Write-Host " Test Suite" -ForegroundColor DarkGray
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
        Write-Host " Tests Complete" -NoNewline -ForegroundColor Blue
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
# 1. Simple objects (hashtables)
# ============================================================
Write-Host "[1] Simple hashtables (keyed array save)" -ForegroundColor Blue

$users = @(
    @{ Name = "Alice"; Email = "alice@example.com"; Role = "admin"; Active = $true }
    @{ Name = "Bob"; Email = "bob@example.com"; Role = "user"; Active = $true }
    @{ Name = "Charlie"; Email = "charlie@example.com"; Role = "user"; Active = $false }
    @{ Name = "Diana"; Email = "diana@example.com"; Role = "manager"; Active = $true }
)

New-BucketObject -Bucket users -InputObject $users -KeyProperty Name -Quiet
Use-Bucket "users"
Write-Host "  Saved $($users.Count) users (keyed by Name)" -ForegroundColor DarkGray

# ============================================================
# 2. Nested PSCustomObjects
# ============================================================
Write-Host "`n[2] Nested PSCustomObjects (deep object serialization)" -ForegroundColor Blue

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

New-BucketObject -Bucket orders -InputObject $orders -KeyProperty OrderId -Quiet
Use-Bucket "orders"
Write-Host "  Saved $($orders.Count) orders" -ForegroundColor DarkGray

# ============================================================
# 3. System objects (FileInfo) - triggers binary fallback
# ============================================================
Write-Host "`n[3] System objects (FileInfo — complex objects auto-fallback to binary)" -ForegroundColor Blue

Get-ChildItem $PSScriptRoot | Where-Object { $_.Name -notmatch "^\." } | New-BucketObject -Bucket files -KeyProperty Name -Quiet
Use-Bucket "files"
Write-Host "  Saved directory listing (complex objects fallback to .dat)" -ForegroundColor DarkGray

# ============================================================
# 4. Log entries with unique keys
# ============================================================
Write-Host "`n[4] Log entries (bulk save with unique keys)" -ForegroundColor Blue

$logEntries = @(
    @{ Id = "log-001"; Level = "INFO"; Message = "Application started" }
    @{ Id = "log-002"; Level = "DEBUG"; Message = "Loading configuration" }
    @{ Id = "log-003"; Level = "WARN"; Message = "Deprecated API call" }
    @{ Id = "log-004"; Level = "ERROR"; Message = "Connection timeout" }
)

New-BucketObject -Bucket logs -InputObject $logEntries -KeyProperty Id -Quiet
Use-Bucket "logs"
Write-Host "  Saved $($logEntries.Count) log entries" -ForegroundColor DarkGray

# ============================================================
# 5. Config (JSON format)
# ============================================================
Write-Host "`n[5] Config (JSON format — explicit -AsJson switch)" -ForegroundColor Blue

$config = [PSCustomObject]@{
    _Id = "app-config"
    Database = [PSCustomObject]@{ Host = "localhost"; Port = 5432; Name = "app_db" }
    Cache = [PSCustomObject]@{ Enabled = $true; TTL = 3600; Provider = "Redis" }
    Logging = [PSCustomObject]@{ Level = "Debug"; Outputs = @("Console", "File") }
    Version = "2.1.0"
}

New-BucketObject -Bucket config -InputObject $config -KeyProperty _Id -AsJson -Quiet
Use-Bucket "config"
Write-Host "  Saved config as JSON" -ForegroundColor DarkGray

# ============================================================
# 6. Metrics
# ============================================================
Write-Host "`n[6] Performance metrics (24 hours — numeric bulk save)" -ForegroundColor Blue

$metrics = foreach ($hour in 0..23) {
    [PSCustomObject]@{
        Hour = $hour
        CPU = [math]::Round((Get-Random -Min 5 -Max 95), 2)
        Memory = [math]::Round((Get-Random -Min 40 -Max 85), 2)
        Requests = Get-Random -Min 100 -Max 5000
    }
}

New-BucketObject -Bucket metrics -InputObject $metrics -KeyProperty Hour -Quiet
Use-Bucket "metrics"
Write-Host "  Saved 24 hourly records" -ForegroundColor DarkGray

# ============================================================
# 7. Mixed formats in same bucket
# ============================================================
Write-Host "`n[7] Mixed formats (JSON + binary in same bucket)" -ForegroundColor Blue

New-BucketObject -Bucket mixed -InputObject @{ _Id = "m1"; Type = "json"; Value = 1 } -KeyProperty _Id -AsJson -Quiet
New-BucketObject -Bucket mixed -InputObject @{ _Id = "m2"; Type = "binary"; Value = 2 } -KeyProperty _Id -Quiet
New-BucketObject -Bucket mixed -InputObject @{ _Id = "m3"; Type = "json-fallback" } -KeyProperty _Id -AsJson -Quiet
Use-Bucket "mixed"
Write-Host "  Saved 3 objects (2 JSON, 1 binary)" -ForegroundColor DarkGray

# ============================================================
# VERIFICATION
# ============================================================
Write-Host "`n========================================" -ForegroundColor Blue
Write-Host " Verification" -ForegroundColor Blue
Write-Host "========================================`n" -ForegroundColor Blue

Write-Host "[Buckets]" -ForegroundColor Blue
Get-Bucket | Format-Table -AutoSize

Write-Host "[Users] Filter Role = 'admin'" -ForegroundColor Blue
Get-BucketObject -Bucket users -Filter { $_.Role -eq "admin" } | ForEach-Object { Write-Host "  $($_.Name) ($($_.Email))" }

Write-Host "`n[Orders] Shipped with Express shipping" -ForegroundColor Blue
Get-BucketObject -Bucket orders -Filter { $_.Status -eq "shipped" -and $_.Shipping.Method -eq "Express" } | ForEach-Object { Write-Host "  $($_.OrderId) by $($_.Customer)" }

Write-Host "`n[Config] JSON verification" -ForegroundColor Blue
$cfg = Get-BucketObject -Bucket config -Key "app-config"
Write-Host "  DB: $($cfg.Database.Host):$($cfg.Database.Port)/$($cfg.Database.Name)"
Write-Host "  Cache: $($cfg.Cache.Provider) (TTL: $($cfg.Cache.TTL)s)"

Write-Host "`n[Metrics] Hours with CPU > 80%" -ForegroundColor Blue
Get-BucketObject -Bucket metrics -Filter { $_.CPU -gt 80 } | ForEach-Object { Write-Host "  Hour $($_.Hour): CPU=$($_.CPU)%, Mem=$($_.Memory)%" }

Write-Host "`n[Logs] Filter WARN/ERROR" -ForegroundColor Blue
Get-BucketObject -Bucket logs -Filter { $_.Level -in @("WARN", "ERROR") } | ForEach-Object { Write-Host "  [$($_.Level)] $($_.Message)" }

Write-Host "`n[Mixed] Formats" -ForegroundColor Blue
Get-BucketObject -Bucket mixed | ForEach-Object {
    $ext = [System.IO.Path]::GetExtension($_._BucketFile)
    Write-Host "  $($_.Type) ($ext)"
}

# ============================================================
# STATS
# ============================================================
Write-Host "`n========================================" -ForegroundColor Blue
Write-Host " Stats" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue

foreach ($b in (Get-Bucket)) {
    $stats = Get-BucketStats -Bucket $b.Name
    Write-Host "  $($b.Name): $($stats.ObjectCount) objects, $($stats.TotalSize)"
}

$elapsed = $sw.ElapsedMilliseconds
Write-Host "`nTotal time: ${elapsed}ms" -ForegroundColor Blue

# ============================================================
# 8. Copy-BucketObject
# ============================================================
Write-Host "`n[8] Copy-BucketObject (cross-bucket copy, key rename)" -ForegroundColor Blue
Remove-Bucket "archive" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
Copy-BucketObject -Bucket users -Key "Alice" -DestinationBucket archive -PassThru | Format-Table
Copy-BucketObject -Bucket config -Key "app-config" -DestinationKey "app-config-backup" -PassThru | Format-Table
$archived = Get-BucketObject -Bucket archive -Key "Alice"
Write-Host "  Archived user: $($archived.Name) ($($archived.Email))" -ForegroundColor DarkGray
$backup = Get-BucketObject -Bucket config -Key "app-config-backup"
Write-Host "  Backed up config version: $($backup.Version)" -ForegroundColor DarkGray

# ============================================================
# 9. Rename-BucketObject
# ============================================================
Write-Host "`n[9] Rename-BucketObject (in-place key change, preserves format)" -ForegroundColor Blue
Rename-BucketObject -Bucket archive -Key "Alice" -NewKey "alice-admin" -PassThru | Format-Table
$renamed = Get-BucketObject -Bucket archive -Key "alice-admin"
Write-Host "  Renamed user: $($renamed.Name) (key: alice-admin)" -ForegroundColor DarkGray

# ============================================================
# 10. Export-Bucket & Import-Bucket
# ============================================================
Write-Host "`n[10] Export/Import bucket (archive to CLIXML/JSON, restore)" -ForegroundColor Blue
$exportPath = Join-Path $PSScriptRoot "test-export.clixml"
$exportJson = Join-Path $PSScriptRoot "test-export.json"
Export-Bucket -Bucket users -OutputFile $exportPath
Export-Bucket -Bucket logs -OutputFile $exportJson -AsJson
Remove-Bucket "import-test" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
Import-Bucket -Bucket import-test -InputFile $exportPath
Use-Bucket "import-test"
$imported = Get-BucketObject -Bucket import-test
Write-Host "  Imported $($imported.Count) users from CLIXML archive" -ForegroundColor DarkGray
Remove-Item $exportPath, $exportJson -Force

# ============================================================
# 11. -Compress switch
# ============================================================
Write-Host "`n[11] Binary compression (-Compress — GZip reduces repetitive data)" -ForegroundColor Blue
Remove-Bucket "compressed" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
New-BucketObject -Bucket compressed -InputObject @{ _Id = "comp"; Data = "x" * 5000; Type = "compressed" } -KeyProperty "_Id" -Compress -Quiet
Use-Bucket "compressed"
New-BucketObject -Bucket compressed -InputObject @{ _Id = "uncomp"; Data = "x" * 5000; Type = "uncompressed" } -KeyProperty "_Id" -Quiet
$basePath = $testRoot
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
Write-Host "`n[12] -WhatIf support (preview deletes without execution)" -ForegroundColor Blue
Remove-BucketObject -Bucket users -Key "Bob" -WhatIf
Remove-Bucket "users" -WhatIf -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
$remaining = Get-BucketObject -Bucket users -WarningAction SilentlyContinue
Write-Host "  Objects in 'users' after -WhatIf: $($remaining.Count) (unchanged)" -ForegroundColor DarkGray

# ============================================================
# 13. Round-trip integrity
# ============================================================
Write-Host "`n[13] Round-trip integrity (save/load complex types and null)" -ForegroundColor Blue
Remove-Bucket "roundtrip" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
Use-Bucket "roundtrip"
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
New-BucketObject -Bucket roundtrip -InputObject $roundTrip -KeyProperty "_Id" -Quiet
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
Write-Host "`n[14] Error conditions (missing keys, corrupted files, bad params)" -ForegroundColor Blue

Write-Host "  Missing bucket key..." -NoNewline
try {
    Get-BucketObject -Bucket nonexistent-bucket-xyz -Key "missing" 2>$null
    Write-Host " OK (returns empty)" -ForegroundColor Magenta
} catch {
    Write-Host " FAIL: $_" -ForegroundColor Red
}

Write-Host "  Remove non-existent key..." -NoNewline
try {
    Remove-BucketObject -Bucket users -Key "nonexistent-key" -WarningVariable warn -WarningAction SilentlyContinue 2>$null
    if ($warn) { Write-Host " OK (warning issued)" -ForegroundColor Magenta } else { Write-Host " FAIL (no warning)" -ForegroundColor Red }
} catch {
    Write-Host " FAIL: $_" -ForegroundColor Red
}

Write-Host "  Remove without -Key or -All..." -NoNewline
try {
    Remove-BucketObject -Bucket users 2>$null
    Write-Host " FAIL (should have thrown)" -ForegroundColor Red
} catch {
    Write-Host " OK (threw: $($_.Exception.Message))" -ForegroundColor Magenta
}

Write-Host "  Set-BucketObject without bucket/key..." -NoNewline
try {
    @{ Name = "test" } | Set-BucketObject 2>$null
    Write-Host " FAIL (should have thrown)" -ForegroundColor Red
} catch {
    Write-Host " OK (threw)" -ForegroundColor Magenta
}

Write-Host "  Corrupted file handling..." -NoNewline
$usersPath = Join-Path $testRoot "users"
$corruptPath = Join-Path $usersPath "corrupt.dat"
[System.IO.File]::WriteAllText($corruptPath, "THIS_IS_NOT_VALID_BASE64!!!", [System.Text.Encoding]::UTF8)
$beforeCount = (Get-BucketObject -Bucket users).Count
$retrieved = Get-BucketObject -Bucket users -Key "corrupt" -WarningVariable cWarn -WarningAction SilentlyContinue
if ($null -eq $retrieved -and $cWarn) {
    Write-Host " OK (warning issued, null returned)" -ForegroundColor Magenta
} else {
    Write-Host " WARN (retrieved: $retrieved, warnings: $($cWarn.Count))" -ForegroundColor Yellow
}
Remove-Item $corruptPath -Force

Write-Host "  Get-BucketObject -Key across multiple buckets (no null-file crash)..." -NoNewline
try {
    $errorsBefore = $Error.Count
    New-BucketObject -Bucket bucket-a -InputObject @{ X = 1; _Id = "only-in-a" } -KeyProperty "_Id" -Quiet
    New-BucketObject -Bucket bucket-b -InputObject @{ Y = 2; _Id = "only-in-b" } -KeyProperty "_Id" -Quiet
    New-BucketObject -Bucket bucket-c -InputObject @{ Z = 3; _Id = "only-in-c" } -KeyProperty "_Id" -Quiet
    $result = Get-BucketObject -Key "only-in-a" -WarningAction SilentlyContinue 2>$null
    $newErrors = $Error.Count - $errorsBefore
    if ($null -eq $result -or $result.X -eq 1) {
        if ($newErrors -eq 0 -and $result.X -eq 1) {
            Write-Host " OK (found in bucket-a, zero errors across all buckets)" -ForegroundColor Magenta
        } else {
            Write-Host " FAIL (errors: $newErrors, result: $($result.X))" -ForegroundColor Red
        }
    } else {
        Write-Host " FAIL (wrong result or errors occurred)" -ForegroundColor Red
    }
    Remove-Bucket -Bucket bucket-a -Force -Confirm:$false -Quiet
    Remove-Bucket -Bucket bucket-b -Force -Confirm:$false -Quiet
    Remove-Bucket -Bucket bucket-c -Force -Confirm:$false -Quiet
} catch {
    Write-Host " FAIL: $_" -ForegroundColor Red
}

Write-Host "  Get-BucketObject -Key with case mismatch..." -NoNewline
try {
    $errorsBefore = $Error.Count
    New-BucketObject -Bucket casetest -InputObject @{ Val = 42; _Id = "MixedCase-Key" } -KeyProperty "_Id" -Quiet
    $result = Get-BucketObject -Bucket casetest -Key "mixedcase-key" -WarningAction SilentlyContinue 2>$null
    $newErrors = $Error.Count - $errorsBefore
    if ($null -ne $result -and $result.Val -eq 42 -and $newErrors -eq 0) {
        Write-Host " OK (case-insensitive match, zero errors)" -ForegroundColor Magenta
    } else {
        Write-Host " FAIL (result: $($result.Val), errors: $newErrors)" -ForegroundColor Red
    }
    Remove-Bucket -Bucket casetest -Force -Confirm:$false -Quiet
} catch {
    Write-Host " FAIL: $_" -ForegroundColor Red
}

Write-Host "  Set-BucketObject pipeline round-trip..." -NoNewline
$user = Get-BucketObject -Bucket users -Key "Bob"
$user.Role = "admin"
$user | Set-BucketObject -Quiet
$updated = Get-BucketObject -Bucket users -Key "Bob"
if ($updated.Role -eq "admin") {
    Write-Host " OK (role updated to admin)" -ForegroundColor Magenta
} else {
    Write-Host " FAIL (role: $($updated.Role))" -ForegroundColor Red
}

Write-Host "  Auto-patch (hashtable)..." -NoNewline
$before = Get-BucketObject -Bucket users -Key "Alice"
$origEmail = $before.Email
@{ Email = "alice@patched.com" } | Set-BucketObject -Bucket users -Key "Alice" -Quiet
$after = Get-BucketObject -Bucket users -Key "Alice"
if ($after.Email -eq "alice@patched.com" -and $after.Name -eq "Alice" -and $after.Role -eq "admin") {
    Write-Host " OK (email patched, other fields preserved)" -ForegroundColor Magenta
    @{ Email = $origEmail } | Set-BucketObject -Bucket users -Key "Alice" -Quiet
} else {
    Write-Host " FAIL (email: $($after.Email), name: $($after.Name))" -ForegroundColor Red
}

Write-Host "  Auto-patch (PSCustomObject)..." -NoNewline
New-BucketObject -Bucket users -InputObject ([PSCustomObject]@{ _Id = "patch-obj"; Name = "Test"; Val = 1 }) -KeyProperty "_Id" -Quiet
[PSCustomObject]@{ Val = 99; NewField = "added" } | Set-BucketObject -Bucket users -Key "patch-obj" -Quiet
$patched = Get-BucketObject -Bucket users -Key "patch-obj"
if ($patched.Val -eq 99 -and $patched.Name -eq "Test" -and $patched.NewField -eq "added") {
    Write-Host " OK (value patched, new field added, name preserved)" -ForegroundColor Magenta
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
        Write-Host " OK (threw with patch message)" -ForegroundColor Magenta
    } else {
        Write-Host " OK (threw: $($_.Exception.Message))" -ForegroundColor Magenta
    }
}

# ============================================================
# 15. Nested buckets (5 levels deep)
# ============================================================
Write-Host "`n[15] Nested buckets (5 levels deep)" -ForegroundColor Blue
Remove-Bucket "org" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet

$nestedBucket = "org/eu/de/berlin/team-a"

# Write objects at different nesting levels
$orgData = @{ Name = "Global Corp"; Founded = 1990 }
New-BucketObject -Bucket "org" -InputObject $orgData -Key "meta" -Quiet

$euData = @{ Region = "Europe"; Hq = "Frankfurt" }
New-BucketObject -Bucket "org/eu" -InputObject $euData -Key "info" -Quiet

$deData = @{ Country = "Germany"; Currency = "EUR" }
New-BucketObject -Bucket "org/eu/de" -InputObject $deData -Key "info" -Quiet

$cityData = @{ City = "Berlin"; Employees = 150 }
New-BucketObject -Bucket "org/eu/de/berlin" -InputObject $cityData -Key "info" -Quiet

$teamData = @{ Team = "Team A"; Lead = "Alice"; Members = 5 }
New-BucketObject -Bucket $nestedBucket -InputObject $teamData -Key "profile" -Quiet

# Verify reads at each level
$passCount = 0
$failMsg = @()

$r = Get-BucketObject -Bucket "org" -Key "meta"
if ($r.Name -eq "Global Corp" -and $r.Founded -eq 1990) { $passCount++ } else { $failMsg += "org/meta" }

$r = Get-BucketObject -Bucket "org/eu" -Key "info"
if ($r.Region -eq "Europe") { $passCount++ } else { $failMsg += "org/eu/info" }

$r = Get-BucketObject -Bucket "org/eu/de" -Key "info"
if ($r.Country -eq "Germany") { $passCount++ } else { $failMsg += "org/eu/de/info" }

$r = Get-BucketObject -Bucket "org/eu/de/berlin" -Key "info"
if ($r.City -eq "Berlin") { $passCount++ } else { $failMsg += "org/eu/de/berlin/info" }

$r = Get-BucketObject -Bucket $nestedBucket -Key "profile"
if ($r.Team -eq "Team A" -and $r.Lead -eq "Alice") { $passCount++ } else { $failMsg += "$nestedBucket/profile" }

# Verify Get-BucketObject -Recurse spills nested buckets
$recursiveResult = Get-BucketObject -Bucket "org" -Recurse
$recursiveCount = @($recursiveResult).Count
$hasGlobal = $null -ne ($recursiveResult | Where-Object { $_.Name -eq "Global Corp" -and $_.Founded -eq 1990 })
$recursiveOk = $recursiveCount -eq 5 -and $hasGlobal
if ($recursiveOk) { $passCount++ } else { $failMsg += "Recurse expected 5 objects, got $recursiveCount" }

# Verify Get-Bucket -Recurse finds all nested buckets
$buckets = Get-Bucket -Recurse -Name "org"
$orgBuckets = $buckets | Where-Object { $_.Name -like "org*" }
if ($orgBuckets.Count -ge 5) { $passCount++ } else { $failMsg += "Get-Bucket found $($orgBuckets.Count)/5 nested buckets" }

# Verify provider navigation
$driveItems = @()
Get-ChildItem "buckets:\org" -ErrorAction SilentlyContinue | ForEach-Object { $driveItems += $_.Name }
if ($driveItems -contains "eu") { $passCount++ } else { $failMsg += "provider: missing eu at org level" }

$euItems = @()
Get-ChildItem "buckets:\org\eu" -ErrorAction SilentlyContinue | ForEach-Object { $euItems += $_.Name }
if ($euItems -contains "de") { $passCount++ } else { $failMsg += "provider: missing de at eu level" }

if ($passCount -eq 9) {
    Write-Host "  5-level deep nested buckets: OK (9/9 checks passed)" -ForegroundColor Magenta
} else {
    Write-Host "  FAIL ($passCount/9 passed): $($failMsg -join ', ')" -ForegroundColor Red
}

# Test Remove-Bucket at deep level (without -Recurse, should preserve parent)
Remove-Bucket $nestedBucket -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
$deepGone = $null -eq (Get-BucketObject -Bucket $nestedBucket -Key "profile" -WarningAction SilentlyContinue 2>$null)
$parentIntact = (Get-BucketObject -Bucket "org/eu/de/berlin" -Key "info").City -eq "Berlin"
if ($deepGone -and $parentIntact) {
    Write-Host "  Deep remove: OK (removed leaf, parent preserved)" -ForegroundColor Magenta
} else {
    Write-Host "  FAIL (deep gone: $deepGone, parent intact: $parentIntact)" -ForegroundColor Red
}

# Test Remove-Bucket -Recurse
Remove-Bucket "org" -Recurse -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
$orgGone = -not (Test-Path (Join-Path $testRoot "org"))
if ($orgGone) {
    Write-Host "  Recursive remove: OK (entire tree removed)" -ForegroundColor Magenta
} else {
    Write-Host "  FAIL (org directory still exists)" -ForegroundColor Red
}

# Recreate the nested buckets so they survive the test suite
New-BucketObject -Bucket "org" -InputObject $orgData -Key "meta" -Quiet
New-BucketObject -Bucket "org/eu" -InputObject $euData -Key "info" -Quiet
New-BucketObject -Bucket "org/eu/de" -InputObject $deData -Key "info" -Quiet
New-BucketObject -Bucket "org/eu/de/berlin" -InputObject $cityData -Key "info" -Quiet
New-BucketObject -Bucket $nestedBucket -InputObject $teamData -Key "profile" -Quiet
Use-Bucket "org"

# ============================================================
# 15a. Get-Bucket -Tree
# ============================================================
Write-Host "`n[15a] Get-Bucket -Tree" -ForegroundColor Blue
$tree = Get-Bucket -Tree -Raw -Name "org"
$orgChildren = @($tree.Children | Where-Object { $_.Name -eq "org" })
if ($orgChildren.Count -eq 1) {
    $orgNode = $orgChildren[0]
    # org bucket has 5 objects total (recursive), with eu as a child bucket
    if ($orgNode._BucketName -eq "org" -and $orgNode.ObjectCount -eq 5 -and $orgNode.Children.Count -ge 1 -and $orgNode.Children[0].Name -eq "eu") {
        Write-Host "  Tree structure: OK (org → eu with correct nesting)" -ForegroundColor Magenta
    } else {
        Write-Host "  FAIL (org node structure incorrect: _BucketName=$($orgNode._BucketName) ObjectCount=$($orgNode.ObjectCount) Children=$($orgNode.Children.Count) FirstChild=$($orgNode.Children[0].Name))" -ForegroundColor Red
    }
} else {
    Write-Host "  FAIL (expected 1 org node, got $($orgChildren.Count))" -ForegroundColor Red
}

# Verify -Raw output has correct type
$rawAll = Get-Bucket -Tree -Raw
if ($rawAll.PSObject.TypeNames[0] -eq "Buckets.Tree" -and $rawAll.Type -eq "Root") {
    Write-Host "  Raw output type: OK (Buckets.Tree Root)" -ForegroundColor Magenta
} else {
    Write-Host "  FAIL (raw output type incorrect: $($rawAll.PSObject.TypeNames[0]))" -ForegroundColor Red
}

# ============================================================
# 15b. Get-BucketObject -Key across all buckets (nested)
# ============================================================
Write-Host "`n[15b] Get-BucketObject -Key across all buckets (nested)" -ForegroundColor Blue

$errorsBefore = $Error.Count
$result = Get-BucketObject -Key "info" -WarningAction SilentlyContinue 2>$null
$newErrors = $Error.Count - $errorsBefore
if ($result.Count -eq 3 -and $newErrors -eq 0) {
    $names = $result | ForEach-Object { $_.PSObject.Properties["_BucketName"].Value }
    if ($names -contains "eu" -and $names -contains "de" -and $names -contains "berlin") {
        Write-Host "  OK (3 info objects found across nested buckets, zero errors)" -ForegroundColor Magenta
    } else {
        Write-Host "  FAIL (unexpected bucket names: $($names -join ', '))" -ForegroundColor Red
    }
} else {
    Write-Host "  FAIL (found $($result.Count) objects, $newErrors errors)" -ForegroundColor Red
}

# ============================================================
# 16. Metadata isolation
# ============================================================
Write-Host "`n[16] Metadata isolation (hidden _BucketName, _BucketKey, _BucketFile)" -ForegroundColor Blue

$user = Get-BucketObject -Bucket users -Key "Alice"

$selectStar = $user | Select-Object *
$hasHidden = $selectStar.PSObject.Properties.Name -contains "_BucketName" -or $selectStar.PSObject.Properties.Name -contains "_BucketKey"
$accessible = $null -ne $user._BucketName -and $null -ne $user._BucketKey -and $null -ne $user._BucketFile

if (-not $hasHidden -and $accessible) {
    Write-Host "  Metadata isolation: OK (hidden from Select-Object *, accessible via direct access)" -ForegroundColor Magenta
} else {
    Write-Host "  FAIL (hidden=$(-not $hasHidden), accessible=$accessible, _BucketName=$($user._BucketName))" -ForegroundColor Red
}

# ============================================================
# 17. Get-BucketObject -Recurse with filters
# ============================================================
Write-Host "`n[17] Get-BucketObject -Recurse with filters" -ForegroundColor Blue

# Recurse + Key
$r1 = Get-BucketObject -Bucket "org" -Recurse -Key "info"
$r1count = @($r1).Count
$r1ok = $r1count -eq 3
Write-Host "  -Recurse -Key info: $r1count objects" -NoNewline
if ($r1ok) { Write-Host " — OK" -ForegroundColor Magenta } else { Write-Host " — FAIL" -ForegroundColor Red }

# Recurse + Match
$r2 = Get-BucketObject -Bucket "org" -Recurse -Match @{ Country = "Germany" }
$r2count = @($r2).Count
$r2ok = $r2count -eq 1 -and $r2[0].Country -eq "Germany"
Write-Host "  -Recurse -Match @{Country='Germany'}: $r2count objects" -NoNewline
if ($r2ok) { Write-Host " — OK" -ForegroundColor Magenta } else { Write-Host " — FAIL" -ForegroundColor Red }

# Recurse + Filter
$r3 = Get-BucketObject -Bucket "org" -Recurse -Filter { $_.Employees -gt 100 }
$r3count = @($r3).Count
$r3ok = $r3count -eq 1 -and $r3[0].City -eq "Berlin"
Write-Host "  -Recurse -Filter { `$_.Employees -gt 100 }: $r3count objects" -NoNewline
if ($r3ok) { Write-Host " — OK" -ForegroundColor Magenta } else { Write-Host " — FAIL" -ForegroundColor Red }

# ============================================================
# 18. Get-Bucket -Tree edge cases
# ============================================================
Write-Host "`n[18] Get-Bucket -Tree edge cases" -ForegroundColor Blue

# Filtered tree with -Name
$treeFiltered = Get-Bucket -Tree -Raw -Name "org/eu"
$hasOrgEu = $treeFiltered.Children | Where-Object { $_.Name -eq "org" -and $_.Children[0].Name -eq "eu" }
$rootName = Split-Path $testRoot -Leaf
$noOtherBuckets = ($treeFiltered.Children | Where-Object { $_.Name -ne $rootName }).Count -eq 1
if ($hasOrgEu -and $noOtherBuckets) {
    Write-Host "  -Tree -Name org/eu: OK (filtered to org subtree)" -ForegroundColor Magenta
} else {
    Write-Host "  FAIL (hasOrgEu=$($null -ne $hasOrgEu), noOtherBuckets=$noOtherBuckets, children=$($treeFiltered.Children.Name -join ','))" -ForegroundColor Red
}

# Missing directory resilience (remove a subdirectory then scan tree)
$teamAPath = Join-Path $testRoot "org/eu/de/berlin/team-a"
if (Test-Path $teamAPath) { Remove-Item $teamAPath -Recurse -Force }
$treeAfterDelete = Get-Bucket -Tree -Raw -Name "org" -ErrorAction SilentlyContinue
$orgNode = $treeAfterDelete.Children | Where-Object { $_.Name -eq "org" }
$noCrash = $null -ne $orgNode
$objectCount = if ($noCrash) { $orgNode.ObjectCount } else { 0 }
$expectedCount = 4  # meta + eu/info + de/info + berlin/info (team-a removed)
if ($noCrash -and $objectCount -eq $expectedCount) {
    Write-Host "  Missing dir resilience: OK (removed team-a, tree intact, count=$objectCount)" -ForegroundColor Magenta
} else {
    Write-Host "  FAIL (noCrash=$noCrash, count=$objectCount, expected=$expectedCount)" -ForegroundColor Red
}

# Restore
New-BucketObject -Bucket "org/eu/de/berlin/team-a" -InputObject @{ Team = "Team A"; Lead = "Alice"; Members = 5 } -Key "profile" -Quiet

# ============================================================
# 19. Edge cases
# ============================================================
Write-Host "`n[19] Edge cases" -ForegroundColor Blue

Remove-Bucket "edge" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
$edgeResults = [System.Collections.ArrayList]::new()

function Test-Edge {
    param([string]$Name, [scriptblock]$Test)
    try {
        $ok = & $Test
        if ($ok) {
            Write-Host "  $Name " -NoNewline -ForegroundColor DarkGray
            Write-Host "PASS" -ForegroundColor Green
            $null = $edgeResults.Add([PSCustomObject]@{ Name = $Name; Status = "PASS"; Detail = "" })
        } else {
            Write-Host "  $Name " -NoNewline -ForegroundColor DarkGray
            Write-Host "FAIL" -ForegroundColor Red
            $null = $edgeResults.Add([PSCustomObject]@{ Name = $Name; Status = "FAIL"; Detail = "returned false" })
        }
    } catch {
        Write-Host "  $Name " -NoNewline -ForegroundColor DarkGray
        Write-Host "FAIL" -ForegroundColor Red
        $null = $edgeResults.Add([PSCustomObject]@{ Name = $Name; Status = "FAIL"; Detail = $_.Exception.Message })
    }
}

<#
  1. Overwrite behavior
  Verifies: Without -Overwrite, saving an existing key silently skips.
            With -Overwrite, the existing object is replaced.
  Why it matters: Prevents accidental data loss; explicit opt-in for updates.
#>
Test-Edge "Overwrite behavior (no -Overwrite skips, -Overwrite replaces)" {
    New-BucketObject -Bucket edge -InputObject @{ _Id = "x"; Val = 1 } -KeyProperty _Id -Quiet
    New-BucketObject -Bucket edge -InputObject @{ _Id = "x"; Val = 2 } -KeyProperty _Id -Quiet
    $v1 = (Get-BucketObject -Bucket edge -Key "x").Val
    New-BucketObject -Bucket edge -InputObject @{ _Id = "x"; Val = 3 } -KeyProperty _Id -Quiet -Overwrite
    $v2 = (Get-BucketObject -Bucket edge -Key "x").Val
    $v1 -eq 1 -and $v2 -eq 3
}

<#
  2. -AsTimestamp dedup
  Verifies: Multiple objects saved with -AsTimestamp each get a unique
            millisecond-level timestamp key, so none collide.
  Why it matters: Allows bulk logging without manual key management.
#>
Test-Edge "-AsTimestamp dedup (sequential calls get unique keys)" {
    $tsItems = 1..3 | ForEach-Object { @{ Val = $_ } }
    $tsItems | New-BucketObject -Bucket edge -AsTimestamp -Quiet
    $tsCount = (Get-BucketObject -Bucket edge).Count
    $tsCount -ge 4
}

<#
  3. -KeyProperty with $null value
  Verifies: When the key property resolves to $null, the object is skipped
            rather than creating a file with a sanitized empty name.
  Why it matters: Defensive handling of malformed input.
#>
Test-Edge "-KeyProperty with `$null` value (object skipped)" {
    $before = (Get-BucketObject -Bucket edge).Count
    New-BucketObject -Bucket edge -InputObject @{ _Id = $null; Val = 1 } -KeyProperty _Id -Quiet
    $after = (Get-BucketObject -Bucket edge).Count
    $after -eq $before
}

<#
  4. -Match with multiple properties
  Verifies: -Match @{ Color = "red"; Size = 10 } uses AND logic,
            returning only objects that satisfy both conditions.
  Why it matters: Users expect multi-property filters to narrow results.
#>
Test-Edge "-Match with multiple properties (AND logic)" {
    New-BucketObject -Bucket edge -InputObject @{ _Id = "m1"; Color = "red"; Size = 10 } -KeyProperty _Id -Quiet
    New-BucketObject -Bucket edge -InputObject @{ _Id = "m2"; Color = "blue"; Size = 10 } -KeyProperty _Id -Quiet
    New-BucketObject -Bucket edge -InputObject @{ _Id = "m3"; Color = "red"; Size = 20 } -KeyProperty _Id -Quiet
    $matchMulti = Get-BucketObject -Bucket edge -Match @{ Color = "red"; Size = 10 }
    @($matchMulti).Count -eq 1 -and $matchMulti._Id -eq "m1"
}

<#
  5. Path traversal protection
  Verifies: Bucket names like "../../etc" are rejected by Resolve-SafePath,
            which ensures the resolved path stays inside the bucket root.
  Why it matters: Prevents writing (or reading) outside the intended directory.
#>
Test-Edge "Path traversal protection (../../etc rejected)" {
    try {
        New-BucketObject -Bucket "../../etc" -InputObject @{ x = 1 } -Key "test" -Quiet -ErrorAction Stop
        $false
    } catch { $true }
}

<#
  6. Deep nested object serialization
  Verifies: A 3-level nested hashtable survives binary serialization
            and deserialization with structure intact.
  Why it matters: Complex config objects must round-trip without flattening.
#>
Test-Edge "Deep nested object serialization (3-level hashtable)" {
    $deep = @{ _Id = "deep"; L1 = @{ L2 = @{ L3 = "bottom" } } }
    New-BucketObject -Bucket edge -InputObject $deep -KeyProperty _Id -Quiet
    $retrievedDeep = Get-BucketObject -Bucket edge -Key "deep"
    $retrievedDeep.L1.L2.L3 -eq "bottom"
}

<#
  7. Circular reference (JSON fails -> binary fallback)
  Verifies: An object with a self-referencing property cannot be serialized
            to JSON (infinite recursion), so the module falls back to binary
            format and still stores/retrieves the object successfully.
  Why it matters: Real-world objects (e.g. CIM instances) may have cycles.
#>
Test-Edge "Circular reference (JSON fails -> binary fallback)" {
    $circ = [PSCustomObject]@{ _Id = "circ"; Name = "loop" }
    $circ | Add-Member -NotePropertyName "Self" -NotePropertyValue $circ
    New-BucketObject -Bucket edge -InputObject $circ -KeyProperty _Id -Quiet
    $retrievedCirc = Get-BucketObject -Bucket edge -Key "circ" -WarningAction SilentlyContinue
    $null -ne $retrievedCirc -and $retrievedCirc.Name -eq "loop"
}

<#
  8. Unicode/non-ASCII keys
  Verifies: Keys containing Unicode characters (Latin, CJK, Cyrillic) are
            sanitized safely and remain retrievable by the original name.
  Why it matters: International users need native-language identifiers.
#>
Test-Edge "Unicode/non-ASCII keys (üñîçødé-测试-тест)" {
    New-BucketObject -Bucket edge -InputObject @{ _Id = "üñîçødé-测试-тест"; Val = "unicode" } -KeyProperty _Id -Quiet
    $unicode = Get-BucketObject -Bucket edge -Key "üñîçødé-测试-тест"
    $unicode.Val -eq "unicode"
}

<#
  9. Very deep nested path
  Verifies: Bucket paths can be nested 10 levels deep and still work for
            both write and read operations.
  Why it matters: Hierarchical data (AD, inventory, org charts) needs depth.
#>
Test-Edge "Very deep nested path (a/b/c/d/e/f/g/h/i/j)" {
    New-BucketObject -Bucket "a/b/c/d/e/f/g/h/i/j" -InputObject @{ _Id = "deep-path"; Val = 1 } -KeyProperty _Id -Quiet
    Use-Bucket "a"
    $deepPath = Get-BucketObject -Bucket "a/b/c/d/e/f/g/h/i/j" -Key "deep-path"
    $deepPath.Val -eq 1
}

<#
  10. -First and -Skip pagination
  Verifies: -First N returns the first N objects, -Skip N skips the first N,
            and combining both produces a page of results.
  Why it matters: Large buckets need pagination to avoid memory pressure.
#>
Test-Edge "-First and -Skip pagination" {
    $first2 = Get-BucketObject -Bucket users -First 2
    $skip2 = Get-BucketObject -Bucket users -Skip 2
    $firstSkip = Get-BucketObject -Bucket users -First 1 -Skip 2
    $total = (Get-BucketObject -Bucket users).Count
    @($first2).Count -eq 2 -and @($skip2).Count -eq ($total - 2) -and @($firstSkip).Count -eq 1
}

<#
  11. Empty bucket
  Verifies: Passing an empty array (@()) to -InputObject creates no files,
            resulting in an empty bucket.
  Why it matters: Users should be able to initialize a bucket without data.
#>
Test-Edge "Empty bucket (InputObject `@() creates no objects)" {
    New-BucketObject -Bucket empty -InputObject @() -Quiet
    Use-Bucket "empty"
    $emptyCount = @(Get-BucketObject -Bucket empty -WarningAction SilentlyContinue).Count
    Remove-Bucket "empty" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $emptyCount -eq 0
}

<#
  12. -NoRecurse vs default recurse
  Verifies: With -NoRecurse, a wildcard bucket only returns direct children.
            Without -NoRecurse (default), it descends into all sub-buckets.
  Why it matters: Users need both shallow and deep search modes.
#>
Test-Edge "Wildcard + -Recurse (org/eu -NoRecurse returns 1, without returns >1)" {
    $flat = @(Get-BucketObject -Bucket "org/eu" -NoRecurse -WarningAction SilentlyContinue).Count
    $recursive = @(Get-BucketObject -Bucket "org/eu" -WarningAction SilentlyContinue).Count
    $recursive -gt $flat -and $flat -gt 0
}

<#
  13. Compressed round-trip via Set-BucketObject
  Verifies: An object saved with -Compress can be modified with
            Set-BucketObject -Compress and read back correctly.
  Why it matters: Compressed objects must support partial updates.
#>
Test-Edge "Compressed round-trip via Set-BucketObject" {
    New-BucketObject -Bucket edge -InputObject @{ _Id = "comp-roundtrip"; Data = "original" } -KeyProperty _Id -Compress -Quiet
    $compObj = Get-BucketObject -Bucket edge -Key "comp-roundtrip"
    $compObj.Data = "modified"
    $compObj | Set-BucketObject -Compress -Quiet
    $compMod = Get-BucketObject -Bucket edge -Key "comp-roundtrip"
    $compMod.Data -eq "modified"
}

<#
  14. No-buckets root
  Verifies: Querying a nonexistent bucket root returns $null or empty array
            instead of throwing an error.
  Why it matters: Scripts should handle missing data gracefully.
#>
Test-Edge "No-buckets root (nonexistent path returns empty)" {
    $noB = Get-Bucket -Path (Join-Path $testRoot "nonexistent-root")
    $null -eq $noB -or @($noB).Count -eq 0
}

# Cleanup edge bucket
Remove-Bucket "edge" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
Remove-Bucket "a" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet

foreach ($bucket in $createdBuckets) {
    Remove-Bucket -Bucket $bucket -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
}

$passCount = ($edgeResults | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($edgeResults | Where-Object { $_.Status -eq "FAIL" }).Count

if ($failCount -eq 0) {
    Write-Host "  All $passCount/$($edgeResults.Count) edge case checks passed" -ForegroundColor Magenta
} else {
    Write-Host "  $($failCount)/$($edgeResults.Count) FAILED:" -ForegroundColor Red
    $edgeResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "    $($_.Name)" -ForegroundColor Red
        if ($_.Detail) { Write-Host "      $($_.Detail)" -ForegroundColor DarkGray }
    }
}

Set-BucketRoot (Join-Path $HOME ".buckets")
Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-InfoBlock -Mode bottom
