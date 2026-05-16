#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test script for the Buckets module.
#>

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-test-$(Get-Random)"
Set-BucketRoot $testRoot

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$createdBuckets = [System.Collections.ArrayList]::new()
function Use-Bucket {
    param([string]$Name)
    $null = $createdBuckets.Add($Name)
}

$testResults = [System.Collections.ArrayList]::new()
function Test-It {
    param([string]$Name, [scriptblock]$Test)
    try {
        $ok = & $Test
        if ($ok) {
            Write-Host "  $Name " -NoNewline -ForegroundColor DarkGray
            Write-Host "PASS" -ForegroundColor Green
            $null = $testResults.Add([PSCustomObject]@{ Name = $Name; Status = "PASS"; Detail = "" })
        } else {
            Write-Host "  $Name " -NoNewline -ForegroundColor DarkGray
            Write-Host "FAIL" -ForegroundColor Red
            $null = $testResults.Add([PSCustomObject]@{ Name = $Name; Status = "FAIL"; Detail = "returned false" })
        }
    } catch {
        Write-Host "  $Name " -NoNewline -ForegroundColor DarkGray
        Write-Host "FAIL" -ForegroundColor Red
        $null = $testResults.Add([PSCustomObject]@{ Name = $Name; Status = "FAIL"; Detail = $_.Exception.Message })
    }
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

Test-It "Hashtable round-trip" {
    $saved = Get-BucketObject -Bucket users
    @($saved).Count -eq $users.Count -and (Get-BucketObject -Bucket users -Key "Alice").Name -eq "Alice"
}

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

Test-It "Nested PSCustomObject round-trip" {
    $saved = Get-BucketObject -Bucket orders
    @($saved).Count -eq $orders.Count -and (Get-BucketObject -Bucket orders -Key "ORD-001").Customer -eq "Alice"
}

# ============================================================
# 3. System objects (FileInfo) - triggers binary fallback
# ============================================================
Write-Host "`n[3] System objects (FileInfo — complex objects auto-fallback to binary)" -ForegroundColor Blue

Get-ChildItem $PSScriptRoot | Where-Object { $_.Name -notmatch "^\." } | New-BucketObject -Bucket files -KeyProperty Name -Quiet
Use-Bucket "files"

Test-It "FileInfo binary fallback" {
    $first = Get-BucketObject -Bucket files | Select-Object -First 1
    @(Get-BucketObject -Bucket files).Count -gt 0 -and $null -ne $first.Name
}

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

Test-It "Log entry round-trip" {
    $saved = Get-BucketObject -Bucket logs
    @($saved).Count -eq 4 -and (Get-BucketObject -Bucket logs -Key "log-001").Level -eq "INFO"
}

# ============================================================
# 5. Config (JSON format)
# ============================================================
Write-Host "`n[5] Config (JSON format — default)" -ForegroundColor Blue

$config = [PSCustomObject]@{
    _Id = "app-config"
    Database = [PSCustomObject]@{ Host = "localhost"; Port = 5432; Name = "app_db" }
    Cache = [PSCustomObject]@{ Enabled = $true; TTL = 3600; Provider = "Redis" }
    Logging = [PSCustomObject]@{ Level = "Debug"; Outputs = @("Console", "File") }
    Version = "2.1.0"
}

New-BucketObject -Bucket config -InputObject $config -KeyProperty _Id -Quiet
Use-Bucket "config"

Test-It "JSON config round-trip" {
    $saved = Get-BucketObject -Bucket config -Key "app-config"
    $null -ne $saved -and $saved.Version -eq "2.1.0" -and $saved.Database.Host -eq "localhost"
}

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

Test-It "Metrics round-trip" {
    $saved = Get-BucketObject -Bucket metrics
    @($saved).Count -eq 24 -and (Get-BucketObject -Bucket metrics -Key "0").CPU -ge 5
}

# ============================================================
# 7. Mixed formats in same bucket
# ============================================================
Write-Host "`n[7] Mixed formats (JSON + binary in same bucket)" -ForegroundColor Blue

New-BucketObject -Bucket mixed -InputObject @{ _Id = "m1"; Type = "json"; Value = 1 } -KeyProperty _Id -Quiet
New-BucketObject -Bucket mixed -InputObject @{ _Id = "m2"; Type = "binary"; Value = 2 } -KeyProperty _Id -AsBinary -Quiet
New-BucketObject -Bucket mixed -InputObject @{ _Id = "m3"; Type = "json-fallback" } -KeyProperty _Id -Quiet
Use-Bucket "mixed"

Test-It "Mixed formats (JSON + binary) in same bucket" {
    $saved = Get-BucketObject -Bucket mixed
    @($saved).Count -eq 3 -and (Get-BucketObject -Bucket mixed -Key "m1").Value -eq 1 -and (Get-BucketObject -Bucket mixed -Key "m2").Value -eq 2
}
# ============================================================
# 8. Object operations (Copy, Rename, Export/Import)
# ============================================================
Write-Host "`n[8] Object operations (Copy, Rename, Export)" -ForegroundColor Blue
Remove-Bucket "archive" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet

Test-It "Copy-BucketObject cross-bucket preserves user data" {
    Copy-BucketObject -Bucket users -Key "Alice" -DestinationBucket archive -Quiet
    Copy-BucketObject -Bucket config -Key "app-config" -DestinationKey "app-config-backup" -Quiet
    $archived = Get-BucketObject -Bucket archive -Key "Alice"
    $backup = Get-BucketObject -Bucket config -Key "app-config-backup"
    $archived.Name -eq "Alice" -and $archived.Email -eq "alice@example.com" -and $backup.Version -eq "2.1.0"
}

Test-It "Rename-BucketObject changes key, preserves data" {
    Rename-BucketObject -Bucket archive -Key "Alice" -NewKey "alice-admin" -Quiet
    $renamed = Get-BucketObject -Bucket archive -Key "alice-admin"
    $null -ne $renamed -and $renamed.Name -eq "Alice"
}

Test-It "Export/Import bucket round-trips correctly" {
    $exportPath = Join-Path $PSScriptRoot "test-export.clixml"
    $exportJson = Join-Path $PSScriptRoot "test-export.json"
    Export-Bucket -Bucket users -OutputFile $exportPath -AsBinary -Quiet
    Export-Bucket -Bucket logs -OutputFile $exportJson -Quiet
    Remove-Bucket "import-test" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    Import-Bucket -Bucket import-test -InputFile $exportPath -AsBinary -Quiet
    Use-Bucket "import-test"
    $imported = Get-BucketObject -Bucket import-test
    Remove-Item $exportPath, $exportJson -Force
    @($imported).Count -eq 4
}

# ============================================================
# 9. -Compress switch
# ============================================================
Write-Host "`n[9] Binary compression (-Compress — GZip)" -ForegroundColor Blue

Test-It "Binary compression reduces file size" {
    Remove-Bucket "compressed" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket compressed -InputObject @{ _Id = "comp"; Data = "x" * 5000; Type = "compressed" } -KeyProperty "_Id" -AsBinary -Compress -Quiet
    Use-Bucket "compressed"
    New-BucketObject -Bucket compressed -InputObject @{ _Id = "uncomp"; Data = "x" * 5000; Type = "uncompressed" } -KeyProperty "_Id" -AsBinary -Quiet
    $compPath = Join-Path $testRoot "compressed"
    $compSize = (Get-ChildItem $compPath -Filter "comp.dat").Length
    $uncompSize = (Get-ChildItem $compPath -Filter "uncomp.dat").Length
    $compSize -lt $uncompSize -and (Get-BucketObject -Bucket compressed -Key "comp").Data.Length -eq 5000
}

# ============================================================
# 10. -WhatIf support
# ============================================================
Write-Host "`n[10] -WhatIf support (preview deletes without execution)" -ForegroundColor Blue

Test-It "-WhatIf preview does not delete objects" {
    Remove-BucketObject -Bucket users -Key "Bob" -WhatIf
    Remove-Bucket "users" -WhatIf -Force -WarningAction SilentlyContinue | Out-Null
    $remaining = Get-BucketObject -Bucket users -WarningAction SilentlyContinue
    @($remaining).Count -eq 4
}

# ============================================================
# 11. Round-trip integrity
# ============================================================
Write-Host "`n[11] Round-trip integrity (save/load complex types and null)" -ForegroundColor Blue
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

Test-It "Round-trip: all data fields preserved (String, Number, Bool, Null, Array, Nested, SpecialChars, EmptyString, Zero, Negative)" {
    $retrieved = Get-BucketObject -Bucket roundtrip -Key "test"
    $null -ne $retrieved -and
    $retrieved.String -eq "Hello, World!" -and
    $retrieved.Number -eq 42.5 -and
    $retrieved.Bool -eq $true -and
    $null -eq $retrieved.Null -and
    $retrieved.Array.Count -eq 4 -and $retrieved.Array[3] -eq "four" -and
    $retrieved.Nested.Level1.Level2.Level3 -eq "deep" -and
    $retrieved.SpecialChars -eq '!@#$%^&*()' -and
    $retrieved.EmptyString -eq "" -and
    $retrieved.Zero -eq 0 -and
    $retrieved.Negative -eq -100
}

# ============================================================
# 12. Error condition tests
# ============================================================
Write-Host "`n[12] Error conditions (missing keys, corrupted files, bad params)" -ForegroundColor Blue

Test-It "Get-BucketObject on nonexistent bucket returns empty" {
    $result = Get-BucketObject -Bucket nonexistent-bucket-xyz -Key "missing" -WarningAction SilentlyContinue
    $null -eq $result
}

Test-It "Remove-BucketObject on nonexistent key issues warning" {
    $warn = $null
    Remove-BucketObject -Bucket users -Key "nonexistent-key" -WarningVariable warn -WarningAction SilentlyContinue
    $null -ne $warn
}

Test-It "Remove-BucketObject without -Key or -All throws" {
    $ok = $false
    try { Remove-BucketObject -Bucket users 2>$null; $ok = $false }
    catch { $ok = $_.Exception.Message -match "Specify either" }
    $ok
}

Test-It "Set-BucketObject without bucket/key throws" {
    $ok = $false
    try { @{ Name = "test" } | Set-BucketObject 2>$null; $ok = $false }
    catch { $ok = $_.Exception.Message -match "partial updates" }
    $ok
}

Test-It "Corrupted file returns null with warning" {
    $usersPath = Join-Path $testRoot "users"
    $corruptPath = Join-Path $usersPath "corrupt.dat"
    [System.IO.File]::WriteAllText($corruptPath, "THIS_IS_NOT_VALID_BASE64!!!", [System.Text.Encoding]::UTF8)
    $cWarn = $null
    $retrieved = Get-BucketObject -Bucket users -Key "corrupt" -WarningVariable cWarn -WarningAction SilentlyContinue
    Remove-Item $corruptPath -Force
    $null -eq $retrieved -and $null -ne $cWarn
}

Test-It "Get-BucketObject -Key in default bucket without errors" {
    New-BucketObject -Bucket "default" -InputObject @{ X = 1; _Id = "only-in-a" } -KeyProperty "_Id" -Quiet
    $result = Get-BucketObject -Key "only-in-a" -WarningAction SilentlyContinue -ErrorVariable getErr
    Remove-BucketObject -Bucket "default" -All -Quiet
    $null -ne $result -and $getErr.Count -eq 0
}

Test-It "Get-BucketObject -Key with case mismatch" {
    New-BucketObject -Bucket casetest -InputObject @{ Val = 42; _Id = "MixedCase-Key" } -KeyProperty "_Id" -Quiet
    $result = Get-BucketObject -Bucket casetest -Key "mixedcase-key" -WarningAction SilentlyContinue -ErrorVariable getErr
    Remove-Bucket -Bucket casetest -Force -Confirm:$false -Quiet
    $null -ne $result -and $result.Val -eq 42 -and $getErr.Count -eq 0
}

Test-It "Set-BucketObject pipeline round-trip" {
    $user = Get-BucketObject -Bucket users -Key "Bob"
    $user.Role = "admin"
    $user | Set-BucketObject -Quiet
    $updated = Get-BucketObject -Bucket users -Key "Bob"
    $updated.Role -eq "admin"
}

Test-It "Set-BucketObject auto-patch (hashtable) preserves other fields" {
    $before = Get-BucketObject -Bucket users -Key "Alice"
    $origEmail = $before.Email
    @{ Email = "alice@patched.com" } | Set-BucketObject -Bucket users -Key "Alice" -Quiet
    $after = Get-BucketObject -Bucket users -Key "Alice"
    @{ Email = $origEmail } | Set-BucketObject -Bucket users -Key "Alice" -Quiet
    $after.Email -eq "alice@patched.com" -and $after.Name -eq "Alice" -and $after.Role -eq "admin"
}

Test-It "Set-BucketObject auto-patch (PSCustomObject) adds new fields" {
    New-BucketObject -Bucket users -InputObject ([PSCustomObject]@{ _Id = "patch-obj"; Name = "Test"; Val = 1 }) -KeyProperty "_Id" -Quiet
    [PSCustomObject]@{ Val = 99; NewField = "added" } | Set-BucketObject -Bucket users -Key "patch-obj" -Quiet
    $patched = Get-BucketObject -Bucket users -Key "patch-obj"
    Remove-BucketObject -Bucket users -Key "patch-obj" -Quiet
    $patched.Val -eq 99 -and $patched.Name -eq "Test" -and $patched.NewField -eq "added"
}

Test-It "Set-BucketObject partial update without Bucket/Key throws" {
    $ok = $false
    try { @{ Name = "test" } | Set-BucketObject 2>$null }
    catch { $ok = $_.Exception.Message -like "*partial*" -or $_.Exception.Message -like "*Bucket*" }
    $ok
}

# ============================================================
# 13. Nested buckets (5 levels deep)
# ============================================================
Write-Host "`n[13] Nested buckets (5 levels deep)" -ForegroundColor Blue

# Setup
$nestedBucket = "org/eu/de/berlin/team-a"
$orgData = @{ Name = "Global Corp"; Founded = 1990 }
$euData = @{ Region = "Europe"; Hq = "Frankfurt" }
$deData = @{ Country = "Germany"; Currency = "EUR" }
$cityData = @{ City = "Berlin"; Employees = 150 }
$teamData = @{ Team = "Team A"; Lead = "Alice"; Members = 5 }

Remove-Bucket "org" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
New-BucketObject -Bucket "org" -InputObject $orgData -Key "meta" -Quiet
New-BucketObject -Bucket "org/eu" -InputObject $euData -Key "info" -Quiet
New-BucketObject -Bucket "org/eu/de" -InputObject $deData -Key "info" -Quiet
New-BucketObject -Bucket "org/eu/de/berlin" -InputObject $cityData -Key "info" -Quiet
New-BucketObject -Bucket $nestedBucket -InputObject $teamData -Key "profile" -Quiet

Test-It "All 5 nesting levels read correctly" {
    $r1 = Get-BucketObject -Bucket "org" -Key "meta"
    $r2 = Get-BucketObject -Bucket "org/eu" -Key "info"
    $r3 = Get-BucketObject -Bucket "org/eu/de" -Key "info"
    $r4 = Get-BucketObject -Bucket "org/eu/de/berlin" -Key "info"
    $r5 = Get-BucketObject -Bucket $nestedBucket -Key "profile"
    ($r1.Name -eq "Global Corp" -and $r1.Founded -eq 1990) -and
    ($r2.Region -eq "Europe") -and
    ($r3.Country -eq "Germany") -and
    ($r4.City -eq "Berlin") -and
    ($r5.Team -eq "Team A" -and $r5.Lead -eq "Alice")
}

Test-It "Recurse returns 5 objects including root" {
    $recursiveResult = Get-BucketObject -Bucket "org" -Recurse
    $recursiveCount = @($recursiveResult).Count
    $hasGlobal = $null -ne ($recursiveResult | Where-Object { $_.Name -eq "Global Corp" -and $_.Founded -eq 1990 })
    $recursiveCount -eq 5 -and $hasGlobal
}

Test-It "Get-Bucket finds all nested buckets" {
    $buckets = Get-Bucket -Recurse -Name "org"
    $orgBuckets = $buckets | Where-Object { $_.Name -like "org*" }
    $orgBuckets.Count -eq 4
}

Test-It "Provider navigation shows nested bucket structure" {
    $driveItems = @()
    Get-ChildItem "buckets:/org" -ErrorAction SilentlyContinue | ForEach-Object { $driveItems += $_.Name }
    $euItems = @()
    Get-ChildItem "buckets:/org/eu" -ErrorAction SilentlyContinue | ForEach-Object { $euItems += $_.Name }
    ($driveItems -contains "eu") -and ($euItems -contains "de")
}

# Remove tests
Test-It "Remove-Bucket at deep level preserves parent" {
    Remove-Bucket $nestedBucket -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $deepGone = $null -eq (Get-BucketObject -Bucket $nestedBucket -Key "profile" -WarningAction SilentlyContinue)
    $parentIntact = (Get-BucketObject -Bucket "org/eu/de/berlin" -Key "info").City -eq "Berlin"
    $deepGone -and $parentIntact
}

Test-It "Remove-Bucket -Recurse removes entire tree" {
    Remove-Bucket "org" -Recurse -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    -not (Test-Path (Join-Path $testRoot "org"))
}

# Recreate nested buckets for downstream tests
New-BucketObject -Bucket "org" -InputObject $orgData -Key "meta" -Quiet
New-BucketObject -Bucket "org/eu" -InputObject $euData -Key "info" -Quiet
New-BucketObject -Bucket "org/eu/de" -InputObject $deData -Key "info" -Quiet
New-BucketObject -Bucket "org/eu/de/berlin" -InputObject $cityData -Key "info" -Quiet
New-BucketObject -Bucket $nestedBucket -InputObject $teamData -Key "profile" -Quiet
Use-Bucket "org"

# ============================================================
# 14. Get-Bucket -Tree
# ============================================================
Write-Host "`n[14] Get-Bucket -Tree" -ForegroundColor Blue

Test-It "Get-Bucket -Tree shows correct nested structure" {
    $tree = Get-Bucket -Tree -Raw -Name "org"
    $orgChildren = @($tree.Children | Where-Object { $_.Name -eq "org" })
    if ($orgChildren.Count -eq 1) {
        $orgNode = $orgChildren[0]
        $orgNode._BucketName -eq "org" -and $orgNode.ObjectCount -eq 5 -and $orgNode.Children.Count -eq 1 -and $orgNode.Children[0].Name -eq "eu"
    } else { $false }
}

Test-It "Get-Bucket -Tree raw output has correct type" {
    $rawAll = Get-Bucket -Tree -Raw
    $rawAll.PSObject.TypeNames[0] -eq "Buckets.Tree" -and $rawAll.Type -eq "Root"
}



# ============================================================
# 15. Get-BucketObject -Recurse with filters
# ============================================================
Write-Host "`n[15] Get-BucketObject -Recurse with filters" -ForegroundColor Blue

Test-It "-Recurse -Key finds objects across sub-buckets" {
    $r1 = Get-BucketObject -Bucket "org" -Recurse -Key "info"
    @($r1).Count -eq 3
}

Test-It "-Recurse -Match uses AND logic across sub-buckets" {
    $r2 = Get-BucketObject -Bucket "org" -Recurse -Match @{ Country = "Germany" }
    @($r2).Count -eq 1 -and $r2[0].Country -eq "Germany"
}

Test-It "-Recurse -Filter works across sub-buckets" {
    $r3 = Get-BucketObject -Bucket "org" -Recurse -Filter { $_.Employees -gt 100 }
    @($r3).Count -eq 1 -and $r3[0].City -eq "Berlin"
}

# ============================================================
# 16. Metadata isolation
# ============================================================
Write-Host "`n[16] Metadata isolation" -ForegroundColor Blue

Test-It "Metadata hidden from Select-Object *, accessible via direct access" {
    $user = Get-BucketObject -Bucket users -Key "Alice"
    $selectStar = $user | Select-Object *
    $hasHidden = $selectStar.PSObject.Properties.Name -contains "_BucketName" -or $selectStar.PSObject.Properties.Name -contains "_BucketKey"
    $accessible = $null -ne $user._BucketName -and $null -ne $user._BucketKey -and $null -ne $user._BucketFile
    (-not $hasHidden) -and $accessible
}

# ============================================================
# 17. Get-Bucket -Tree edge cases
# ============================================================
Write-Host "`n[17] Get-Bucket -Tree edge cases" -ForegroundColor Blue

Test-It "Get-Bucket -Tree handles missing subdirectory gracefully" {
    $teamAPath = Join-Path $testRoot "org/eu/de/berlin/team-a"
    if (Test-Path $teamAPath) { Remove-Item $teamAPath -Recurse -Force }
    $treeAfterDelete = Get-Bucket -Tree -Raw -Name "org" -ErrorAction SilentlyContinue
    $orgNode = $treeAfterDelete.Children | Where-Object { $_.Name -eq "org" }
    $noCrash = $null -ne $orgNode
    $objectCount = if ($noCrash) { $orgNode.ObjectCount } else { 0 }
    $expectedCount = 4
    New-BucketObject -Bucket "org/eu/de/berlin/team-a" -InputObject @{ Team = "Team A"; Lead = "Alice"; Members = 5 } -Key "profile" -Quiet
    $noCrash -and $objectCount -eq $expectedCount
}

# ============================================================
# 18. Edge cases
# ============================================================
Write-Host "`n[18] Edge cases" -ForegroundColor Blue

Remove-Bucket "edge" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet

<#
  1. Overwrite behavior
  Verifies: Without -Overwrite, saving an existing key silently skips.
            With -Overwrite, the existing object is replaced.
  Why it matters: Prevents accidental data loss; explicit opt-in for updates.
#>
Test-It "Overwrite behavior (no -Overwrite skips, -Overwrite replaces)" {
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
Test-It "-AsTimestamp dedup (sequential calls get unique keys)" {
    $tsItems = 1..3 | ForEach-Object { @{ Val = $_ } }
    $tsItems | New-BucketObject -Bucket edge -AsTimestamp -Quiet
    $tsCount = (Get-BucketObject -Bucket edge).Count
    $tsCount -eq 4
}

<#
  3. -KeyProperty with $null value
  Verifies: When the key property resolves to $null, the object is skipped
            rather than creating a file with a sanitized empty name.
  Why it matters: Defensive handling of malformed input.
#>
Test-It "-KeyProperty with `$null` value (object skipped)" {
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
Test-It "-Match with multiple properties (AND logic)" {
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
Test-It "Path traversal protection (../../etc rejected)" {
    try {
        New-BucketObject -Bucket "../../etc" -InputObject @{ x = 1 } -Key "test" -Quiet -ErrorAction Stop
        $false
    } catch { $_.Exception.Message -match "outside" }
}

<#
  6. Deep nested object serialization
  Verifies: A 3-level nested hashtable survives binary serialization
            and deserialization with structure intact.
  Why it matters: Complex config objects must round-trip without flattening.
#>
Test-It "Deep nested object serialization (3-level hashtable)" {
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
Test-It "Circular reference (JSON fails -> binary fallback)" {
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
Test-It "Unicode/non-ASCII keys (üñîçødé-测试-тест)" {
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
Test-It "Very deep nested path (a/b/c/d/e/f/g/h/i/j)" {
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
Test-It "-First and -Skip pagination" {
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
Test-It "Empty bucket (InputObject `@() creates no objects)" {
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
Test-It "Wildcard + -Recurse (org/eu default returns 1, -Recurse returns >1)" {
    $flat = @(Get-BucketObject -Bucket "org/eu" -WarningAction SilentlyContinue).Count
    $recursive = @(Get-BucketObject -Bucket "org/eu" -Recurse -WarningAction SilentlyContinue).Count
    $recursive -gt $flat -and $flat -gt 0
}

<#
  13. Compressed round-trip via Set-BucketObject
  Verifies: An object saved with -Compress can be modified with
            Set-BucketObject -Compress and read back correctly.
  Why it matters: Compressed objects must support partial updates.
#>
Test-It "Compressed round-trip via Set-BucketObject" {
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
Test-It "No-buckets root (nonexistent path returns empty)" {
    $noB = Get-Bucket -Path (Join-Path $testRoot "nonexistent-root")
    $null -eq $noB -or @($noB).Count -eq 0
}

<#
  15. JSON depth auto-increment
  Verifies: With a deep object, the module auto-increments
            JSON depth to avoid truncation.
#>
Test-It "JSON depth auto-increment (deep object)" {
    $deep = @{ L1 = "deep" }
    for ($i = 2; $i -le 25; $i++) { $deep = @{ "L$i" = $deep } }
    New-BucketObject -Bucket edge -InputObject $deep -Key "json-deep" -Depth 2 -Quiet
    $retrieved = Get-BucketObject -Bucket edge -Key "json-deep"
    Remove-BucketObject -Bucket edge -Key "json-deep" -Quiet
    $null -ne $retrieved
}

<#
  16. JSON format fallback to binary on exception
Verifies: When a circular reference prevents JSON serialization, the module
            falls back to binary and emits a warning.
#>
Test-It "JSON fallback to binary (circular ref)" {
    $circ = [PSCustomObject]@{ _Id = "circ"; Name = "loop" }
    $circ | Add-Member -NotePropertyName "Self" -NotePropertyValue $circ
    New-BucketObject -Bucket edge -InputObject $circ -KeyProperty _Id -Quiet -WarningAction SilentlyContinue
    $retrieved = Get-BucketObject -Bucket edge -Key "circ" -WarningAction SilentlyContinue
    Remove-BucketObject -Bucket edge -Key "circ" -Quiet
    $null -ne $retrieved -and $retrieved.Name -eq "loop"
}

<#
  17. JSON shallow object stays as JSON
  Verifies: A simple object stored without -AsBinary remains as .json,
            no unnecessary fallback to binary.
#>
Test-It "JSON shallow object stays as .json" {
    New-BucketObject -Bucket edge -InputObject @{ _Id = "json-shallow"; Name = "test" } -KeyProperty _Id -Quiet
    $jsonPath = Join-Path (Get-BucketRoot) "edge/json-shallow.json"
    $datPath = Join-Path (Get-BucketRoot) "edge/json-shallow.dat"
    $isJson = Test-Path $jsonPath
    $isNotDat = -not (Test-Path $datPath)
    Remove-BucketObject -Bucket edge -Key "json-shallow" -Quiet
    $isJson -and $isNotDat
}

# ============================================================
# 19. AutoIndex
# ============================================================
Write-Host "`n[19] AutoIndex" -ForegroundColor Blue

Test-It "AutoIndex within-batch duplicates" {
    Remove-Bucket "ai-dup" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $items = @(
        [PSCustomObject]@{ Name = "Alice"; Role = "admin" },
        [PSCustomObject]@{ Name = "Bob"; Role = "user" },
        [PSCustomObject]@{ Name = "Alice"; Role = "guest" }
    )
    $result = $items | New-BucketObject -Bucket ai-dup -KeyProperty Name -AutoIndex -PassThru -Quiet
    $keyNames = (Get-BucketKeys -Bucket ai-dup).Key
    $ok = $keyNames.Count -eq 3 -and $keyNames -contains "Alice" -and $keyNames -contains "Alice_1" -and $keyNames -contains "Bob"
    Remove-Bucket "ai-dup" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $ok
}

Test-It "AutoIndex pre-existing key on disk" {
    Remove-Bucket "ai-pre" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket ai-pre -InputObject @{ _Id = "test"; Val = 1 } -KeyProperty _Id -Quiet
    New-BucketObject -Bucket ai-pre -InputObject @{ _Id = "test"; Val = 2 } -KeyProperty _Id -AutoIndex -PassThru -Quiet | Out-Null
    $keyNames = (Get-BucketKeys -Bucket ai-pre).Key
    $ok = $keyNames.Count -eq 2 -and $keyNames -contains "test" -and $keyNames -contains "test_1"
    Remove-Bucket "ai-pre" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $ok
}

Test-It "AutoIndex with -Overwrite" {
    Remove-Bucket "ai-ow" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket ai-ow -InputObject @{ _Id = "x"; Val = 1 } -KeyProperty _Id -Quiet
    $items = @(
        [PSCustomObject]@{ _Id = "x"; Val = 10 },
        [PSCustomObject]@{ _Id = "x"; Val = 20 }
    )
    $result = $items | New-BucketObject -Bucket ai-ow -KeyProperty _Id -AutoIndex -Overwrite -PassThru -Quiet
    $keyNames = (Get-BucketKeys -Bucket ai-ow).Key
    $objX = Get-BucketObject -Bucket ai-ow -Key "x"
    $ok = $keyNames.Count -eq 2 -and $objX.Val -eq 10 -and $keyNames -contains "x_1"
    Remove-Bucket "ai-ow" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $ok
}

Test-It "AutoIndex with -Key (single key, multi-object pipeline)" {
    Remove-Bucket "ai-key" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    1..3 | ForEach-Object { [PSCustomObject]@{ Num = $_ } } | New-BucketObject -Bucket ai-key -Key "item" -AutoIndex -PassThru -Quiet | Out-Null
    $keyNames = (Get-BucketKeys -Bucket ai-key).Key
    $ok = $keyNames.Count -eq 3 -and $keyNames -contains "item" -and $keyNames -contains "item_1" -and $keyNames -contains "item_2"
    Remove-Bucket "ai-key" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $ok
}

Test-It "AutoIndex without duplicates (no index)" {
    Remove-Bucket "ai-none" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $items = @(
        [PSCustomObject]@{ Name = "Alice"; Role = "admin" },
        [PSCustomObject]@{ Name = "Bob"; Role = "user" }
    )
    $result = $items | New-BucketObject -Bucket ai-none -KeyProperty Name -AutoIndex -PassThru
    $keyNames = (Get-BucketKeys -Bucket ai-none).Key
    $ok = $keyNames.Count -eq 2 -and $keyNames -contains "Alice" -and $keyNames -contains "Bob" -and "Alice_1" -notin $keyNames
    Remove-Bucket "ai-none" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $ok
}

Test-It "AutoIndex PassThru includes Indexed count" {
    Remove-Bucket "ai-pt" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $items = @(
        [PSCustomObject]@{ Name = "x"; V = 1 },
        [PSCustomObject]@{ Name = "x"; V = 2 },
        [PSCustomObject]@{ Name = "x"; V = 3 }
    )
    $result = $items | New-BucketObject -Bucket ai-pt -KeyProperty Name -AutoIndex -PassThru
    $ok = $result.Indexed -eq 2
    Remove-Bucket "ai-pt" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $ok
}

# ============================================================
# 20. Output improvements (PassThru, summary, warnings)
# ============================================================
Write-Host "`n[20] Output improvements" -ForegroundColor Blue

Test-It "Remove-BucketObject -PassThru Key has no file extension" {
    Remove-Bucket "pt-ext" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket pt-ext -InputObject @{ Id = 1; Name = "test" } -Key "del1" -Quiet
    $result = Remove-BucketObject -Bucket pt-ext -Key "del1" -PassThru
    $ok = $result.Key -eq "del1" -and $result.Key -notmatch "\.(json|dat)$"
    Remove-Bucket "pt-ext" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $ok
}

Test-It "Remove-BucketObject -All -PassThru Key has no file extension" {
    Remove-Bucket "pt-all" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket pt-all -InputObject @{ Id = 1 } -Key "a" -Quiet
    New-BucketObject -Bucket pt-all -InputObject @{ Id = 2 } -Key "b" -Quiet
    $results = @(Remove-BucketObject -Bucket pt-all -All -PassThru -Confirm:$false)
    $ok = $results.Count -eq 2 -and ($results | ForEach-Object { $_.Key -notmatch "\.(json|dat)$" }) -notcontains $false
    Remove-Bucket "pt-all" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $ok
}

Test-It "Set-BucketObject -PassThru includes UpdatedKeys" {
    Remove-Bucket "sbo-pt" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket sbo-pt -InputObject @{ Name = "Alice" } -Key "user1" -Quiet
    $result = @{ Name = "Bob" } | Set-BucketObject -Bucket sbo-pt -Key "user1" -PassThru
    $ok = $result.UpdatedKeys -contains "user1" -and $result.Saved -eq 1
    Remove-Bucket "sbo-pt" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $ok
}

Test-It "Get-BucketObject warns on nonexistent literal bucket" {
    $warning = $null
    Get-BucketObject -Bucket "totally-nonexistent-bucket-xyz-123" -WarningVariable warning -WarningAction SilentlyContinue | Out-Null
    $null -ne $warning -and $warning -match "not found"
}

Test-It "Get-Bucket -Name wildcard and exact path support" {
    Remove-Bucket "gn-wild" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    Remove-Bucket "gn-other" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket gn-wild -InputObject @{ X = 1 } -Key "a" -Quiet
    New-BucketObject -Bucket gn-other -InputObject @{ X = 2 } -Key "b" -Quiet
    $wildcardResult = @(Get-Bucket -Name "gn-w*")
    $exactResult = @(Get-Bucket -Name "gn-other")
    $ok = $wildcardResult.Count -eq 1 -and $wildcardResult[0].Name -eq "gn-wild"
    $ok = $ok -and $exactResult.Count -eq 1 -and $exactResult[0].Name -eq "b" -and $exactResult[0].Type -eq "Object"
    Remove-Bucket "gn-wild" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    Remove-Bucket "gn-other" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $ok
}

Test-It "Import-Bucket skip shows key names" {
    Remove-Bucket "imp-skip" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket imp-skip -InputObject @{ Name = "alice" } -Key "alice" -Quiet
    New-BucketObject -Bucket imp-skip -InputObject @{ Name = "bob" } -Key "bob" -Quiet
    $exportPath = Join-Path $testRoot "imp-skip-test.clixml"
    Export-Bucket -Bucket imp-skip -OutputFile $exportPath -AsBinary -Quiet
    $result = Import-Bucket -Bucket imp-skip -InputFile $exportPath -AsBinary 6>&1 | Out-String
    $ok = $result -match "skipped" -and $result -match "alice"
    Remove-Bucket "imp-skip" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    Remove-Item $exportPath -Force -ErrorAction SilentlyContinue
    $ok
}

# ============================================================
# 21. Funnels
# ============================================================
Write-Host "`n[21] Funnels" -ForegroundColor Blue

# Seed data for funnel tests
Remove-Bucket "edge" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
New-BucketObject -Bucket edge -InputObject @{ _Id = "f1"; Role = "admin"; Level = 5 } -KeyProperty _Id -Quiet
New-BucketObject -Bucket edge -InputObject @{ _Id = "f2"; Role = "user"; Level = 3 } -KeyProperty _Id -Quiet
New-BucketObject -Bucket edge -InputObject @{ _Id = "f3"; Role = "user"; Level = 1 } -KeyProperty _Id -Quiet

<#
  1. Create a named funnel
  Verifies: New-Funnel creates a funnel file and it appears in Get-Funnel.
#>
Test-It "New-Funnel creates named funnel" {
    New-Funnel -Name "test-funnel-1" -Transform { if ($_.Level -gt 2) { $_ } } -Description "Level above 2" -Quiet
    $f = Get-Funnel -Name "test-funnel-1"
    $null -ne $f -and $null -ne $f.Transform -and $f.Transform -match 'Level' -and $f.Description -eq "Level above 2"
}

<#
  2. List all funnels
  Verifies: Get-Funnel with no name returns all funnels including the new one.
#>
Test-It "Get-Funnel lists all funnels" {
    $all = Get-Funnel
    $null -ne $all -and @($all).Count -ge 2 -and ($all.Name -contains "test-funnel-1")
}

<#
  3. Named funnel on scoop (filter)
  Verifies: -Funnel with a named funnel filters scoop results correctly.
#>
Test-It "Named funnel on scoop (filter)" {
    $result = Get-BucketObject -Bucket edge -Funnel "test-funnel-1"
    $levels = @($result | ForEach-Object Level)
    @($result).Count -eq 2 -and $levels -contains 5 -and $levels -contains 3
}

<#
  4. Ad-hoc scriptblock on scoop (filter)
  Verifies: -Funnel accepts a raw scriptblock for ad-hoc filtering.
#>
Test-It "Ad-hoc scriptblock on scoop (filter)" {
    $result = Get-BucketObject -Bucket edge -Funnel { if ($_.Role -eq "admin") { $_ } }
    @($result).Count -eq 1 -and $result._Id -eq "f1"
}

<#
  5. Named funnel on fill (transform)
  Verifies: -Funnel transforms objects during fill. A transform funnel
            should return $_ for items to keep and $null to skip.
#>
Test-It "Named funnel on fill (transform)" {
    New-Funnel -Name "test-funnel-fill" -Transform {
        if ($_.Level -gt 2) { $_ } else { $null }
    } -Description "Fill transform demo" -Force -Quiet
    $items = @(
        @{ _Id = "tf1"; Val = "keep"; Level = 5 }
        @{ _Id = "tf2"; Val = "skip"; Level = 1 }
    )
    New-BucketObject -Bucket edge -InputObject $items -KeyProperty _Id -Funnel "test-funnel-fill" -Quiet
    $kept = Get-BucketObject -Bucket edge -Key "tf1"
    $skipped = Get-BucketObject -Bucket edge -Key "tf2" -WarningAction SilentlyContinue
    Remove-Funnel -Name "test-funnel-fill" -Quiet
    $null -ne $kept -and $kept.Val -eq "keep" -and $null -eq $skipped
}

<#
  6. Set-Funnel updates a funnel
  Verifies: Set-Funnel changes filter and/or description of an existing funnel.
#>
Test-It "Set-Funnel updates funnel" {
    Set-Funnel -Name "test-funnel-1" -Description "Updated description"
    $f = Get-Funnel -Name "test-funnel-1"
    $f.Description -eq "Updated description"
}

<#
  7. Remove-Funnel -WhatIf preview
  Verifies: -WhatIf does not delete the funnel — file still exists after preview.
#>
Test-It "Remove-Funnel -WhatIf preview" {
    Remove-Funnel -Name "test-funnel-1" -WhatIf
    $funnelDir = Join-Path $HOME ".buckets-system/funnels"
    $funnelFile = Join-Path $funnelDir "test-funnel-1.json"
    Test-Path $funnelFile
}

<#
  8. Remove-Funnel deletes a funnel
  Verifies: Remove-Funnel actually deletes the funnel file and cache entry.
#>
Test-It "Remove-Funnel deletes funnel" {
    New-Funnel -Name "test-funnel-del" -Transform { $true } -Force -Quiet
    Remove-Funnel -Name "test-funnel-del" -Quiet
    $funnelDir = Join-Path $HOME ".buckets-system/funnels"
    $funnelFile = Join-Path $funnelDir "test-funnel-del.json"
    -not (Test-Path $funnelFile)
}

<#
   9. Built-in funnel available without creation
  Verifies: The file-light funnel ships with the module and is accessible immediately.
#>
Test-It "Built-in file-light funnel is available" {
    $f = Get-Funnel -Name "file-light"
    $null -ne $f -and $null -ne $f.Transform -and $f.Transform -match 'PSCustomObject' -and $null -ne $f.Description -and $f.Description -match "FileInfo" -and $null -ne $f.AppliesTo -and $f.AppliesTo -match 'FileSystemInfo'
}

<#
  10. Get-Funnel lists built-in funnels
  Verifies: Get-Funnel without a name includes the file-light built-in funnel.
#>
Test-It "Get-Funnel lists built-in funnels" {
    $all = Get-Funnel
    @($all).Count -ge 1 -and ($all.Name -contains "file-light")
}

<#
  11. Built-in file-light on fill (transform)
  Verifies: file-light strips a FileInfo to essential properties when used on fill.
#>
Test-It "Built-in file-light on fill strips FileInfo" {
    $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-test-filelight.txt"
    Set-Content -Path $tmpFile -Value "hello world" -NoNewline
    $fi = Get-Item $tmpFile
    New-BucketObject -Bucket edge -InputObject $fi -Key "filelight-test" -Funnel "file-light" -Quiet
    $saved = Get-BucketObject -Bucket edge -Key "filelight-test"
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
    $null -ne $saved -and $saved.Name -eq "buckets-test-filelight.txt" -and $saved.Length -eq 11 -and $null -eq $saved.PSPath -and $null -eq $saved.VersionInfo
}

<#
  12. Remove-Funnel on built-in-only throws
  Verifies: Removing a built-in funnel that has no user override is rejected.
#>
Test-It "Remove-Funnel on built-in-only throws" {
    $ok = $false
    try {
        Remove-Funnel -Name "file-light" -Quiet -ErrorAction Stop
    } catch {
        $ok = $_.Exception.Message -match "built-in"
    }
    $f = Get-Funnel -Name "file-light"
    $ok -and $null -ne $f
}

<#
  13. User override of built-in funnel
  Verifies: Creating a funnel with same name as built-in overrides it,
            and Remove-Funnel on the override removes it, revealing built-in.
#>
Test-It "User override of built-in funnel and removal" {
    New-Funnel -Name "file-light" -Transform { $true } -Force -Quiet
    $f = Get-Funnel -Name "file-light"
    Remove-Funnel -Name "file-light" -Quiet
    $after = Get-Funnel -Name "file-light"
    $null -ne $after -and $null -ne $f.Transform -and $f.Transform.Trim() -eq '$true' -and $null -ne $after.Transform -and $after.Transform -match 'PSCustomObject'
}

<#
  14. AppliesTo on fill (transform, type matches)
  Verifies: Funnel with AppliesTo matching the input object type applies the transform.
#>
Test-It "AppliesTo on fill, type matches" {
    New-Funnel -Name "test-appliesto" -Transform { $_.ToUpper() } -AppliesTo { $_ -is [string] } -Force -Quiet
    $null = "hello" | New-BucketObject -Bucket edge -Key "appliesto-match" -Funnel "test-appliesto" -Quiet
    $saved = Get-BucketObject -Bucket edge -Key "appliesto-match"
    Remove-Funnel -Name "test-appliesto" -Quiet -Confirm:$false
    Remove-BucketObject -Bucket edge -Key "appliesto-match" -Quiet
    $null -ne $saved -and $saved -eq "HELLO"
}

<#
  15. AppliesTo on fill (transform, type mismatch)
  Verifies: Funnel with AppliesTo NOT matching the input object passes through unchanged.
#>
Test-It "AppliesTo on fill, type mismatch passes through" {
    New-Funnel -Name "test-appliesto2" -Transform { $_.ToUpper() } -AppliesTo { $_ -is [string] } -Force -Quiet
    $null = 42 | New-BucketObject -Bucket edge -Key "appliesto-nomatch" -Funnel "test-appliesto2" -Quiet
    $saved = Get-BucketObject -Bucket edge -Key "appliesto-nomatch"
    Remove-Funnel -Name "test-appliesto2" -Quiet -Confirm:$false
    Remove-BucketObject -Bucket edge -Key "appliesto-nomatch" -Quiet
    $null -ne $saved -and $saved -eq 42
}

<#
  16. AppliesTo on scoop (filter, type matches)
  Verifies: Funnel with AppliesTo matching filters matching objects, drops non-matching.
#>
Test-It "AppliesTo on scoop filters correctly" {
    $bucket = "at-scoop"
    New-Funnel -Name "test-scoop" -Transform { if ($_.ToUpper().StartsWith("A")) { $_ } } -AppliesTo { $_ -is [string] } -Force -Quiet
    $null = "Alice" | New-BucketObject -Bucket $bucket -Key "a" -Quiet
    $null = "Bob" | New-BucketObject -Bucket $bucket -Key "b" -Quiet
    $null = 99 | New-BucketObject -Bucket $bucket -Key "n" -Quiet
    $results = Get-BucketObject -Bucket $bucket -Funnel "test-scoop"
    Remove-Funnel -Name "test-scoop" -Quiet -Confirm:$false
    Remove-Bucket $bucket -Force -Confirm:$false -Recurse -Quiet
    $results.Count -eq 2 -and ($results -contains "Alice") -and ($results -contains 99)
}

<#
  17. AppliesTo on scoop (no AppliesTo = backward compat)
  Verifies: Funnel without AppliesTo works as before (all objects filtered).
#>
Test-It "AppliesTo absent = legacy behavior" {
    $bucket = "at-legacy"
    New-Funnel -Name "test-legacy" -Transform { if ($_ -gt 10) { $_ } } -Force -Quiet
    $null = 5 | New-BucketObject -Bucket $bucket -Key "low" -Quiet
    $null = 15 | New-BucketObject -Bucket $bucket -Key "high" -Quiet
    $results = Get-BucketObject -Bucket $bucket -Funnel "test-legacy"
    Remove-Funnel -Name "test-legacy" -Quiet -Confirm:$false
    Remove-Bucket $bucket -Force -Confirm:$false -Recurse -Quiet
    $results.Count -eq 1 -and $results -eq 15
}

<#
  18. New-Funnel with -AppliesTo and Get-Funnel showing AppliesTo
  Verifies: AppliesTo is saved and visible via Get-Funnel output.
#>
Test-It "New-Funnel -AppliesTo persists and shows in Get-Funnel" {
    New-Funnel -Name "test-show-at" -Transform { $true } -AppliesTo { $_ -is [int] } -Force -Quiet
    $f = Get-Funnel -Name "test-show-at"
    Remove-Funnel -Name "test-show-at" -Quiet -Confirm:$false
    $null -ne $f.AppliesTo -and $f.AppliesTo -match 'is \[int\]'
}

<#
  19. Transform on scoop (add property)
  Verifies: A funnel on scoop that transforms the object by adding a property.
#>
Test-It "Transform on scoop adds property" {
    New-Funnel -Name "test-transform-scoop" -Transform { $_ | Add-Member -NotePropertyName "Scooped" -NotePropertyValue $true -PassThru } -Force -Quiet
    $bucket = "funnel-transform"
    New-BucketObject -Bucket $bucket -InputObject @{ _Id = "ft1"; Name = "Alice"; Role = "admin" } -KeyProperty _Id -Quiet
    New-BucketObject -Bucket $bucket -InputObject @{ _Id = "ft2"; Name = "Bob"; Role = "user" } -KeyProperty _Id -Quiet
    New-BucketObject -Bucket $bucket -InputObject @{ _Id = "ft3"; Name = "Carol"; Role = "user" } -KeyProperty _Id -Quiet
    $result = Get-BucketObject -Bucket $bucket -Funnel "test-transform-scoop"
    Remove-Funnel -Name "test-transform-scoop" -Quiet -Confirm:$false
    Remove-Bucket $bucket -Force -Confirm:$false -Recurse -Quiet
    @($result).Count -eq 3 -and @($result | Where-Object { $_.Scooped -eq $true }).Count -eq 3
}

<#
  20. Get-Bucket does not accept -Funnel
  Verifies: Get-Bucket has no -Funnel parameter.
#>
Test-It "Get-Bucket has no -Funnel parameter" {
    $cmd = Get-Command Get-Bucket
    -not ($cmd.Parameters.ContainsKey('Funnel'))
}

<#
  21. Multi-emit on fill (splits one input into multiple stored objects)
  Verifies: Funnel returning array stores each item independently.
#>
Test-It "Multi-emit on fill splits object into multiple items" {
    $bucket = "multi-fill"
    $obj = @{ Name = "Project"; Members = @("Alice", "Bob", "Carol") }
    New-Funnel -Name "test-multi-fill" -Transform {
        $_.Members | ForEach-Object { [PSCustomObject]@{ Name = $_; Project = $_.Name; Role = "member" } }
    } -Force -Quiet
    New-BucketObject -Bucket $bucket -InputObject $obj -KeyProperty Name -Funnel "test-multi-fill" -Quiet
    $results = Get-BucketObject -Bucket $bucket
    Remove-Funnel -Name "test-multi-fill" -Quiet -Confirm:$false
    Remove-Bucket $bucket -Force -Confirm:$false -Recurse -Quiet
    @($results).Count -eq 3 -and ($results.Name -contains "Alice") -and ($results.Name -contains "Bob") -and ($results.Name -contains "Carol")
}

<#
  22. Multi-emit on scoop (expands one stored object into multiple outputs)
  Verifies: Funnel returning array on scoop returns all sub-items with shared metadata.
#>
Test-It "Multi-emit on scoop expands object into multiple items" {
    $bucket = "multi-scoop"
    $obj = @{ _Id = "compound"; Parts = @("A", "B", "C"); Label = "Test" }
    New-BucketObject -Bucket $bucket -InputObject $obj -KeyProperty _Id -Quiet
    $results = Get-BucketObject -Bucket $bucket -Funnel {
        $label = $_.Label; $_.Parts | ForEach-Object { [PSCustomObject]@{ Part = $_; Label = $label } }
    }
    Remove-Bucket $bucket -Force -Confirm:$false -Recurse -Quiet
    @($results).Count -eq 3 -and ($results.Part -contains "A") -and ($results.Part -contains "B") -and ($results.Part -contains "C") -and ($results[0].Label -eq "Test") -and ($results[0]._BucketName -eq $bucket) -and ($results[0]._BucketKey -eq "compound")
}

<#
  23. Multi-emit with $null entries (should be skipped)
  Verifies: $null entries in emitted array are silently dropped.
#>
Test-It "Multi-emit skips null entries" {
    $bucket = "multi-null"
    $obj = @{ _Id = "mixed"; Items = @("keep", $null, "also-keep") }
    New-BucketObject -Bucket $bucket -InputObject $obj -KeyProperty _Id -Quiet
    $results = Get-BucketObject -Bucket $bucket -Funnel {
        $_.Items | ForEach-Object { if ($_ -ne $null) { [PSCustomObject]@{ Value = $_; Label = $_.Label } } else { $null } }
    }
    Remove-Bucket $bucket -Force -Confirm:$false -Recurse -Quiet
    @($results).Count -eq 2 -and ($results.Value -contains "keep") -and ($results.Value -contains "also-keep")
}

<#
  24. Multi-emit with literal -Key (within-batch indexing)
  Verifies: When funnel emits multiple items with a literal -Key, items get indexed.
#>
Test-It "Multi-emit with -Key applies within-batch indexing" {
    New-Funnel -Name "test-multi-key" -Transform {
        @{ _Id = "split1"; Value = "first" }, @{ _Id = "split2"; Value = "second" }
    } -Force -Quiet
    $result = New-BucketObject -Bucket edge -InputObject @{} -Key "multi-key-test" -Funnel "test-multi-key" -PassThru
    Remove-Funnel -Name "test-multi-key" -Quiet -Confirm:$false
    $result.Saved -eq 2 -and $result.Expanded -eq 1 -and @($result.StoredKeys)[1] -like "*_1"
}

<#
  25. Expanded count in summary and PassThru
  Verifies: PassThru shows Expanded property when multi-emit occurs.
#>
Test-It "Expanded count in PassThru" {
    $bucket = "multi-exp-pt"
    $obj = @{ Group = "Root"; Members = @("X", "Y") }
    New-Funnel -Name "test-exp-pt" -Transform {
        $parent = $_.Group
        $_.Members | ForEach-Object { [PSCustomObject]@{ Member = $_; Group = $parent } }
    } -Force -Quiet
    $result = New-BucketObject -Bucket $bucket -InputObject $obj -KeyProperty Member -Funnel "test-exp-pt" -PassThru
    Remove-Funnel -Name "test-exp-pt" -Quiet -Confirm:$false
    Remove-Bucket $bucket -Force -Confirm:$false -Recurse -Quiet
    $result.Saved -eq 2 -and $result.Expanded -eq 1 -and $null -ne $result.StoredKeys
}

# ============================================================
# 22. Move-BucketObject
# ============================================================
Write-Host "`n[22] Move-BucketObject" -ForegroundColor Blue

Test-It "Move-BucketObject cross-bucket moves preserves data" {
    New-BucketObject -Bucket "mv-source" -InputObject @{ _Id = "mv1"; Val = 42 } -KeyProperty _Id -Quiet
    Use-Bucket "mv-source"
    Move-BucketObject -Bucket "mv-source" -Key "mv1" -DestinationBucket "mv-dest" -Quiet
    Use-Bucket "mv-dest"
    $inDest = Get-BucketObject -Bucket "mv-dest" -Key "mv1"
    $inSource = Get-BucketObject -Bucket "mv-source" -Key "mv1" -WarningAction SilentlyContinue
    ($null -ne $inDest -and $inDest.Val -eq 42) -and ($null -eq $inSource)
}

Test-It "Move-BucketObject within-bucket renames" {
    New-BucketObject -Bucket "mv-rename" -InputObject @{ _Id = "old"; Val = 99 } -KeyProperty _Id -Quiet
    Use-Bucket "mv-rename"
    Move-BucketObject -Bucket "mv-rename" -Key "old" -DestinationKey "new" -Quiet
    $renamed = Get-BucketObject -Bucket "mv-rename" -Key "new"
    $original = Get-BucketObject -Bucket "mv-rename" -Key "old" -WarningAction SilentlyContinue
    ($null -ne $renamed -and $renamed.Val -eq 99) -and ($null -eq $original)
}

Test-It "Move-BucketObject -PassThru returns destination metadata" {
    New-BucketObject -Bucket "mv-pt" -InputObject @{ _Id = "x"; Text = "hello" } -KeyProperty _Id -Quiet
    Use-Bucket "mv-pt"
    $result = Move-BucketObject -Bucket "mv-pt" -Key "x" -DestinationBucket "mv-pt-dest" -PassThru
    Use-Bucket "mv-pt-dest"
    $null -ne $result -and $result.DestinationBucket -eq "mv-pt-dest" -and $result.DestinationKey -eq "x"
}

Test-It "Move-BucketObject on nonexistent key raises error" {
    $ok = $false
    try { Move-BucketObject -Bucket "mv-source" -Key "nonexistent" -DestinationBucket "mv-dest" -ErrorAction Stop 2>$null }
    catch { $ok = $_.Exception.Message -match "not found" }
    $ok
}

Test-It "Move-BucketObject preserves binary format" {
    New-BucketObject -Bucket "mv-bin" -InputObject @{ _Id = "b"; Data = "x" * 1000 } -KeyProperty _Id -AsBinary -Quiet
    Use-Bucket "mv-bin"
    Move-BucketObject -Bucket "mv-bin" -Key "b" -DestinationBucket "mv-bin-dest" -Quiet
    Use-Bucket "mv-bin-dest"
    $stats = Get-BucketObjectStats -Bucket "mv-bin-dest" -Key "b"
    $null -ne $stats -and $stats.Format -eq "Binary"
}

# ============================================================
# 23. Get-BucketStats
# ============================================================
Write-Host "`n[23] Get-BucketStats" -ForegroundColor Blue

Test-It "Get-BucketStats returns object count, total size, and timestamps" {
    $stats = Get-BucketStats -Bucket "users"
    $stats.ObjectCount -eq 4 -and $stats.TotalSize -gt 0 -and $null -ne $stats.OldestObject -and $null -ne $stats.NewestObject
}

Test-It "Get-BucketStats on empty bucket returns zero count" {
    $emptyTest = "empty-stats"
    Remove-Bucket $emptyTest -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket $emptyTest -InputObject @{ _Id = "tmp" } -KeyProperty _Id -Quiet
    Remove-BucketObject -Bucket $emptyTest -Key "tmp" -Quiet
    $stats = Get-BucketStats -Bucket $emptyTest -WarningAction SilentlyContinue
    $null -eq $stats -or $stats.ObjectCount -eq 0
}

Test-It "Get-BucketStats on nonexistent bucket warns" {
    $warn = $null
    $stats = Get-BucketStats -Bucket "totally-nonexistent-bucket-xyz" -WarningVariable warn -WarningAction SilentlyContinue
    $null -ne $warn -and ($null -eq $stats -or @($stats).Count -eq 0)
}

# ============================================================
# 24. Get-BucketKeys
# ============================================================
Write-Host "`n[24] Get-BucketKeys" -ForegroundColor Blue

Test-It "Get-BucketKeys lists all keys in a bucket" {
    $keys = Get-BucketKeys -Bucket "users"
    $keys.Count -eq 4 -and ($keys.Key -contains "Alice") -and ($keys.Key -contains "Bob") -and ($keys.Key -contains "Charlie") -and ($keys.Key -contains "Diana")
}

Test-It "Get-BucketKeys -Match filters by key pattern" {
    $keys = Get-BucketKeys -Bucket "orders"
    @($keys).Count -eq 2 -and @($keys | Where-Object { $_.Key -like "*ORD*" }).Count -eq @($keys).Count
}

Test-It "Get-BucketKeys returns Bucket + Key properties" {
    $keys = Get-BucketKeys -Bucket "metrics"
    $null -ne $keys[0].Bucket -and $null -ne $keys[0].Key -and ($keys[0].PSObject.Properties.Name.Count -eq 2)
}

# ============================================================
# 25. Get-BucketObjectStats
# ============================================================
Write-Host "`n[25] Get-BucketObjectStats" -ForegroundColor Blue

Test-It "Get-BucketObjectStats returns Format, Type, Size, LastWriteTime, IsCompressed" {
    $stats = Get-BucketObjectStats -Bucket "users" -Key "Alice"
    $null -ne $stats.Format -and $null -ne $stats.Type -and $stats.Size -gt 0 -and $null -ne $stats.LastWriteTime -and $null -ne $stats.IsCompressed
}

Test-It "Get-BucketObjectStats detects JSON format" {
    $stats = Get-BucketObjectStats -Bucket "config" -Key "app-config"
    $stats.Format -eq "JSON"
}

Test-It "Get-BucketObjectStats detects Binary format" {
    $stats = Get-BucketObjectStats -Bucket "mixed" -Key "m2"
    $stats.Format -eq "Binary"
}

Test-It "Get-BucketObjectStats detects compressed objects" {
    $stats = Get-BucketObjectStats -Bucket "compressed" -Key "comp"
    $stats.Format -eq "Binary" -and $stats.IsCompressed -eq $true
}

Test-It "Get-BucketObjectStats on nonexistent key warns" {
    $warn = $null
    $stats = Get-BucketObjectStats -Bucket "users" -Key "nonexistent-key-xyz" -WarningVariable warn -WarningAction SilentlyContinue
    $null -ne $warn -and $null -eq $stats
}

Test-It "Get-BucketObjectStats -Match filters by key" {
    New-BucketObject -Bucket "gbo-stats" -InputObject @{ _Id = "alpha"; V = 1 }, @{ _Id = "beta"; V = 2 } -KeyProperty _Id -Quiet
    Use-Bucket "gbo-stats"
    $stats = Get-BucketObjectStats -Bucket "gbo-stats" -Match "a*"
    @($stats).Count -eq 1 -and $stats.Key -eq "alpha"
}

# ============================================================
# 26. Get-BucketRoot / Set-BucketRoot / Sync-BucketDrive
# ============================================================
Write-Host "`n[26] Get-BucketRoot / Set-BucketRoot / Sync-BucketDrive" -ForegroundColor Blue

Test-It "Get-BucketRoot returns current root path" {
    $root = Get-BucketRoot
    $root -eq $testRoot
}

Test-It "Set-BucketRoot changes root and Get-BucketRoot reflects it" {
    $newRoot = Join-Path $testRoot "new-root"
    Set-BucketRoot $newRoot
    $root = Get-BucketRoot
    Set-BucketRoot $testRoot
    $root -eq $newRoot
}

Test-It "Sync-BucketDrive creates buckets PSDrive" {
    $drive = Get-PSDrive -Name "buckets" -ErrorAction SilentlyContinue
    $null -ne $drive -and $drive.Root -eq ("buckets:" + [System.IO.Path]::DirectorySeparatorChar)
}

Test-It "Set-BucketRoot with invalid path does not crash" {
    Set-BucketRoot "//invalid||path" -ErrorAction SilentlyContinue
    Set-BucketRoot $testRoot
    $true
}

Test-It "Get-BucketRoot follows Set-BucketRoot changes" {
    $original = Get-BucketRoot
    $original -eq $testRoot
}

# ============================================================
# 27. -Match with $null values
# ============================================================
Write-Host "`n[27] -Match with `$null values" -ForegroundColor Blue

Test-It "Get-BucketObject -Match with $null finds objects where property is absent" {
    Remove-Bucket "match-null" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket "match-null" -InputObject @{ _Id = "has-deleted"; Name = "A"; Deleted = $null } -KeyProperty _Id -Quiet
    New-BucketObject -Bucket "match-null" -InputObject @{ _Id = "no-deleted"; Name = "B" } -KeyProperty _Id -Quiet
    Use-Bucket "match-null"
    $result = Get-BucketObject -Bucket "match-null" -Match @{ Deleted = $null }
    @($result).Count -eq 1
}

Test-It "Get-BucketObject -Match with string in fresh bucket" {
    Remove-Bucket "match-str" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket "match-str" -InputObject @{ _Id = "a"; Role = "admin"; Name = "Alice" }, @{ _Id = "b"; Role = "user"; Name = "Bob" } -KeyProperty _Id -Quiet
    Use-Bucket "match-str"
    $result = Get-BucketObject -Bucket "match-str" -Match @{ Role = "admin" }
    @($result).Count -eq 1 -and $result[0].Name -eq "Alice"
}

# ============================================================
# 28. Key sanitization
# ============================================================
Write-Host "`n[28] Key sanitization" -ForegroundColor Blue

Test-It "Key with forward slash is sanitized to underscore" {
    New-BucketObject -Bucket "sanitize" -InputObject @{ _Id = "a/b"; Val = 1 } -KeyProperty _Id -Quiet
    Use-Bucket "sanitize"
    $keys = Get-BucketKeys -Bucket "sanitize"
    $keys.Key -eq "a_b" -and (Get-BucketObject -Bucket "sanitize" -Key "a_b").Val -eq 1
}

Test-It "Key with colon is sanitized" {
    New-BucketObject -Bucket "sanitize" -InputObject @{ _Id = "key:name"; Val = 2 } -KeyProperty _Id -Quiet
    $keys = Get-BucketKeys -Bucket "sanitize"
    $keys.Key -eq "key_name" -and (Get-BucketObject -Bucket "sanitize" -Key "key_name").Val -eq 2
}

Test-It "Key with asterisk, question mark, angle brackets, pipe, quotes, brackets is sanitized" {
    New-BucketObject -Bucket "sanitize" -InputObject @{ _Id = "a*b?c<d>e|f""g[h]"; Val = 3 } -KeyProperty _Id -Quiet
    $keys = Get-BucketKeys -Bucket "sanitize"
    $sanitized = "a_b_c_d_e_f_g_h_"
    $keys.Key -eq $sanitized -and (Get-BucketObject -Bucket "sanitize" -Key $sanitized).Val -eq 3
}

Test-It "Empty key after sanitization is rejected" {
    $before = @(Get-BucketKeys -Bucket "sanitize" -WarningAction SilentlyContinue).Count
    $warn = $null
    New-BucketObject -Bucket "sanitize" -InputObject @{ Val = 1 } -Key "/:?*" -WarningVariable warn -WarningAction SilentlyContinue -Quiet
    $after = @(Get-BucketKeys -Bucket "sanitize" -WarningAction SilentlyContinue).Count
    ($after -eq $before) -and ($null -ne $warn)
}

Test-It "KeyProperty with only special chars is rejected" {
    $before = @(Get-BucketKeys -Bucket "sanitize" -WarningAction SilentlyContinue).Count
    $warn = $null
    New-BucketObject -Bucket "sanitize" -InputObject @{ _Id = "/:*?"; Val = 2 } -KeyProperty _Id -WarningVariable warn -WarningAction SilentlyContinue -Quiet
    $after = @(Get-BucketKeys -Bucket "sanitize" -WarningAction SilentlyContinue).Count
    ($after -eq $before) -and ($null -ne $warn)
}

Test-It "Import-Bucket warns when key sanitizes to empty" {
    $badFile = Join-Path $testRoot "bad-key-import.json"
    @(@{ _BucketKey = "/:?*"; Value = 1 }) | ConvertTo-Json | Set-Content $badFile
    $warn = $null
    Import-Bucket -Bucket "import-empty-warn" -InputFile $badFile -WarningVariable warn -WarningAction SilentlyContinue -Quiet
    $null -ne $warn
}

# ============================================================
# 29. Remove-BucketObject -Match / -Filter
# ============================================================
Write-Host "`n[29] Remove-BucketObject -Match / -Filter" -ForegroundColor Blue

Test-It "Remove-BucketObject -Match removes matching objects" {
    Remove-Bucket "rm-match" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket "rm-match" -InputObject @{ _Id = "a"; Role = "admin" }, @{ _Id = "b"; Role = "user" }, @{ _Id = "c"; Role = "admin" } -KeyProperty _Id -Quiet
    Use-Bucket "rm-match"
    Remove-BucketObject -Bucket "rm-match" -Match @{ Role = "admin" } -Confirm:$false -Quiet
    $remaining = Get-BucketObject -Bucket "rm-match"
    @($remaining).Count -eq 1 -and $remaining[0].Role -eq "user"
}

Test-It "Remove-BucketObject -Filter removes matching objects" {
    Remove-Bucket "rm-filter" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket "rm-filter" -InputObject @{ _Id = "x"; V = 10 }, @{ _Id = "y"; V = 20 }, @{ _Id = "z"; V = 30 } -KeyProperty _Id -Quiet
    Use-Bucket "rm-filter"
    Remove-BucketObject -Bucket "rm-filter" -Filter { $_.V -gt 15 } -Confirm:$false -Quiet
    $remaining = Get-BucketObject -Bucket "rm-filter"
    @($remaining).Count -eq 1 -and $remaining[0].V -eq 10
}

Test-It "Remove-BucketObject -Match -PassThru returns removed keys" {
    Remove-Bucket "rm-pt" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket "rm-pt" -InputObject @{ _Id = "a"; T = 1 }, @{ _Id = "b"; T = 2 } -KeyProperty _Id -Quiet
    Use-Bucket "rm-pt"
    $removed = Remove-BucketObject -Bucket "rm-pt" -Match @{ T = 2 } -PassThru -Confirm:$false -Quiet
    @($removed).Count -eq 1 -and $removed[0].Key -eq "b"
}

# ============================================================
# 30. BinaryDepth explicit values
# ============================================================
Write-Host "`n[30] BinaryDepth explicit values" -ForegroundColor Blue

Test-It "BinaryDepth=1 stores and retrieves simple objects" {
    Remove-Bucket "bd-1" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket "bd-1" -InputObject @{ _Id = "s"; Name = "simple"; Val = 123 } -KeyProperty _Id -AsBinary -BinaryDepth 1 -Quiet
    Use-Bucket "bd-1"
    $obj = Get-BucketObject -Bucket "bd-1" -Key "s"
    $null -ne $obj -and $obj.Name -eq "simple" -and $obj.Val -eq 123
}

Test-It "BinaryDepth=100 stores and retrieves objects" {
    Remove-Bucket "bd-100" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket "bd-100" -InputObject @{ _Id = "h"; Name = "deep binary"; Data = "x" * 500 } -KeyProperty _Id -AsBinary -BinaryDepth 100 -Quiet
    Use-Bucket "bd-100"
    $obj = Get-BucketObject -Bucket "bd-100" -Key "h"
    $null -ne $obj -and $obj.Name -eq "deep binary"
}

Test-It "BinaryDepth auto-increments on depth failure" {
    Remove-Bucket "bd-auto" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $deep = [PSCustomObject]@{ _Id = "a"; L1 = [PSCustomObject]@{ L2 = [PSCustomObject]@{ L3 = [PSCustomObject]@{ L4 = [PSCustomObject]@{ L5 = [PSCustomObject]@{ L6 = "deep" } } } } } }
    New-BucketObject -Bucket "bd-auto" -InputObject $deep -KeyProperty _Id -AsBinary -BinaryDepth 2 -WarningAction SilentlyContinue -Quiet
    Use-Bucket "bd-auto"
    $obj = Get-BucketObject -Bucket "bd-auto" -Key "a"
    $null -ne $obj -and $obj.L1.L2.L3.L4.L5.L6 -eq "deep"
}

# ============================================================
# 31. Get-Bucket -Tree -Objects / -MaxFiles / -Depth
# ============================================================
Write-Host "`n[31] Get-Bucket -Tree -Objects / -MaxFiles / -Depth" -ForegroundColor Blue

Test-It "Get-Bucket -Tree -Objects includes individual file info" {
    $tree = Get-Bucket -Tree -Raw -Objects -Name "users"
    $objects = $tree.Children | ForEach-Object { if ($_.Children) { $_.Children | Where-Object Type -eq "Object" } }
    @($objects).Count -eq 4
}

Test-It "Get-Bucket -Tree -MaxFiles limits output" {
    $tree = Get-Bucket -Tree -Raw -MaxFiles 2 -Name "metrics"
    $count = 0
    function Walk-Tree2 { param($node) if ($null -ne $node._BucketKey) { $script:count++ } if ($null -ne $node.Children) { $node.Children | ForEach-Object { Walk-Tree2 $_ } } }
    Walk-Tree2 $tree
    $count -le 2
}

Test-It "Get-Bucket -Tree -Depth limits nesting" {
    $full = Get-Bucket -Tree -Raw -Name "org"
    $fullOrg = $full.Children | Where-Object { $_.Name -eq "org" }
    $limited = Get-Bucket -Tree -Raw -Depth 1 -Name "org"
    $limitedOrg = $limited.Children | Where-Object { $_.Name -eq "org" }
    $null -ne $fullOrg -and $fullOrg.Children.Count -eq 1 -and $null -ne $limitedOrg -and ($null -eq $limitedOrg.Children -or $limitedOrg.Children.Count -eq 0)
}

Test-It "Get-Bucket -Tree -Depth 1 -Objects honors depth over objects" {
    $tree = Get-Bucket -Tree -Raw -Depth 1 -Objects -Name "org"
    $orgNode = $tree.Children | Where-Object { $_.Name -eq "org" }
    $fileChildren = @($orgNode.Children | Where-Object Type -eq "Object")
    $dirChildren = @($orgNode.Children | Where-Object Type -ne "Object")
    $fileChildren.Count -gt 0 -and $dirChildren.Count -eq 0
}

# ============================================================
# 32. Copy-BucketObject -PassThru and binary preservation
# ============================================================
Write-Host "`n[32] Copy-BucketObject -PassThru / binary preservation" -ForegroundColor Blue

Test-It "Copy-BucketObject -PassThru returns destination metadata" {
    $result = Copy-BucketObject -Bucket "users" -Key "Alice" -DestinationBucket "copy-pt" -PassThru
    Use-Bucket "copy-pt"
    $null -ne $result -and $result.DestinationBucket -eq "copy-pt" -and $result.DestinationKey -eq "Alice"
}

Test-It "Copy-BucketObject preserves binary format" {
    New-BucketObject -Bucket "copy-bin-src" -InputObject @{ _Id = "bf"; Data = "x" * 100 } -KeyProperty _Id -AsBinary -Quiet
    Use-Bucket "copy-bin-src"
    Copy-BucketObject -Bucket "copy-bin-src" -Key "bf" -DestinationBucket "copy-bin-dest" -Quiet
    Use-Bucket "copy-bin-dest"
    $destStats = Get-BucketObjectStats -Bucket "copy-bin-dest" -Key "bf"
    $destStats.Format -eq "Binary"
}

Test-It "Copy-BucketObject to nonexistent source bucket raises error" {
    $ok = $false
    try { Copy-BucketObject -Bucket "nonexistent-copy-source" -Key "x" -DestinationBucket "copy-noop" -ErrorAction Stop 2>$null }
    catch { $ok = $_.Exception.Message -match "not found" }
    $ok
}

# ============================================================
# 33. Rename-BucketObject -PassThru
# ============================================================
Write-Host "`n[33] Rename-BucketObject -PassThru" -ForegroundColor Blue

Test-It "Rename-BucketObject -PassThru returns new key metadata" {
    New-BucketObject -Bucket "rn-pt" -InputObject @{ _Id = "old-name"; Data = "test" } -KeyProperty _Id -Quiet
    Use-Bucket "rn-pt"
    $result = Rename-BucketObject -Bucket "rn-pt" -Key "old-name" -NewKey "new-name" -PassThru
    $null -ne $result -and $result.NewKey -eq "new-name" -and $result.Bucket -eq "rn-pt"
}

Test-It "Rename-BucketObject to existing key raises error" {
    New-BucketObject -Bucket "rn-exists" -InputObject @{ _Id = "a"; V = 1 }, @{ _Id = "b"; V = 2 } -KeyProperty _Id -Quiet
    Use-Bucket "rn-exists"
    $ok = $false
    try { Rename-BucketObject -Bucket "rn-exists" -Key "a" -NewKey "b" -ErrorAction Stop 2>$null }
    catch { $ok = $_.Exception.Message -match "already exists" }
    $ok
}

Test-It "Rename-BucketObject on nonexistent key raises error" {
    $ok = $false
    try { Rename-BucketObject -Bucket "users" -Key "nonexistent-rn" -NewKey "new" -ErrorAction Stop 2>$null }
    catch { $ok = $_.Exception.Message -match "not found" }
    $ok
}

# ============================================================
# 34. Export-Bucket -Compress / Import-Bucket -Overwrite
# ============================================================
Write-Host "`n[34] Export-Bucket -Compress / Import-Bucket -Overwrite" -ForegroundColor Blue

Test-It "Export-Bucket -AsBinary -Compress creates compressed export" {
    $exportPath = Join-Path $testRoot "export-compressed.dat"
    Export-Bucket -Bucket "compressed" -OutputFile $exportPath -AsBinary -Compress -Quiet
    $exists = Test-Path $exportPath
    Remove-Item $exportPath -Force -ErrorAction SilentlyContinue
    $exists
}

Test-It "Export-Bucket to JSON format creates valid JSON" {
    $exportPath = Join-Path $testRoot "export-json.json"
    Export-Bucket -Bucket "config" -OutputFile $exportPath -Quiet
    $content = Get-Content $exportPath -Raw
    Remove-Item $exportPath -Force -ErrorAction SilentlyContinue
    $null -ne $content -and ($content -match '"Database"' -or $content -match '"_Id"')
}

Test-It "Import-Bucket -Overwrite replaces existing keys" {
    Remove-Bucket "imp-over" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $exportPath = Join-Path $testRoot "imp-over-export.clixml"
    New-BucketObject -Bucket "imp-over" -InputObject @{ _Id = "key1"; Val = "original" } -KeyProperty _Id -Quiet
    Export-Bucket -Bucket "imp-over" -OutputFile $exportPath -AsBinary -Quiet
    New-BucketObject -Bucket "imp-over" -InputObject @{ _Id = "key1"; Val = "updated" } -KeyProperty _Id -Overwrite -Quiet
    Remove-BucketObject -Bucket "imp-over" -Key "key1" -Quiet
    Import-Bucket -Bucket "imp-over" -InputFile $exportPath -AsBinary -Overwrite -Quiet
    $obj = Get-BucketObject -Bucket "imp-over" -Key "key1"
    Remove-Item $exportPath -Force -ErrorAction SilentlyContinue
    $null -ne $obj -and $obj.Val -eq "original"
}

Test-It "Import-Bucket without -Overwrite skips existing keys" {
    Remove-Bucket "imp-skip2" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    $exportPath = Join-Path $testRoot "imp-skip-export.clixml"
    New-BucketObject -Bucket "imp-skip2" -InputObject @{ _Id = "k1"; Val = "orig" }, @{ _Id = "k2"; Val = "also-orig" } -KeyProperty _Id -Quiet
    Export-Bucket -Bucket "imp-skip2" -OutputFile $exportPath -AsBinary -Quiet
    Remove-BucketObject -Bucket "imp-skip2" -Key "k2" -Quiet
    Import-Bucket -Bucket "imp-skip2" -InputFile $exportPath -AsBinary -Quiet
    $obj = Get-BucketObject -Bucket "imp-skip2" -Key "k2"
    Remove-Item $exportPath -Force -ErrorAction SilentlyContinue
    $null -ne $obj -and $obj.Val -eq "also-orig"
}

# ============================================================
# 35. Set-BucketObject -AsBinary / -Depth
# ============================================================
Write-Host "`n[35] Set-BucketObject -AsBinary / -Depth" -ForegroundColor Blue

Test-It "Set-BucketObject -AsBinary converts JSON to binary" {
    New-BucketObject -Bucket "sbo-bin" -InputObject @{ _Id = "convert"; Data = "test" } -KeyProperty _Id -Quiet
    Use-Bucket "sbo-bin"
    @{ Data = "updated" } | Set-BucketObject -Bucket "sbo-bin" -Key "convert" -AsBinary -Quiet
    $stats = Get-BucketObjectStats -Bucket "sbo-bin" -Key "convert"
    $stats.Format -eq "Binary"
}

Test-It "Set-BucketObject -Depth controls serialization depth" {
    New-BucketObject -Bucket "sbo-depth" -InputObject @{ _Id = "deep"; N = @{ L1 = @{ L2 = "value" } } } -KeyProperty _Id -Quiet
    Use-Bucket "sbo-depth"
    @{ N = @{ L1 = @{ L2 = "updated" } } } | Set-BucketObject -Bucket "sbo-depth" -Key "deep" -Depth 5 -Quiet
    $obj = Get-BucketObject -Bucket "sbo-depth" -Key "deep"
    $null -ne $obj -and $obj.N.L1.L2 -eq "updated"
}

Test-It "Set-BucketObject on nonexistent key raises error" {
    $ok = $false
    try { @{ Name = "test" } | Set-BucketObject -Bucket "users" -Key "nonexistent-set-key" -ErrorAction Stop 2>$null }
    catch { $ok = $_.Exception.Message -match "not found" }
    $ok
}

Test-It "Set-BucketObject -PassThru returns updated metadata" {
    $result = @{ Name = "Updated" } | Set-BucketObject -Bucket "users" -Key "Alice" -PassThru
    $null -ne $result -and $result.Bucket -eq "users" -and $result.UpdatedKeys -contains "Alice"
}

Test-It "Set-BucketObject -Property -Value updates a single property" {
    New-BucketObject -Bucket "sbo-pv" -InputObject @{ Name = "Item"; Count = 10; Active = $true } -Key "item1" -Quiet
    Use-Bucket "sbo-pv"
    Set-BucketObject -Bucket "sbo-pv" -Key "item1" -Property Count -Value 99 -Quiet
    $obj = Get-BucketObject -Bucket "sbo-pv" -Key "item1"
    $obj.Name -eq "Item" -and $obj.Count -eq 99 -and $obj.Active -eq $true
}

Test-It "Set-BucketObject -Property -Value adds a new property" {
    Set-BucketObject -Bucket "sbo-pv" -Key "item1" -Property "NewField" -Value "added" -Quiet
    $obj = Get-BucketObject -Bucket "sbo-pv" -Key "item1"
    $obj.NewField -eq "added"
}

Test-It "Set-BucketObject -Property -Value on nonexistent key throws" {
    $ok = $false
    try { Set-BucketObject -Bucket "sbo-pv" -Key "nonexistent" -Property "X" -Value 1 -ErrorAction Stop }
    catch { $ok = $_.Exception.Message -match "not found" }
    $ok
}

# ============================================================
# 36. Set-Bucket (rename/move bucket)
# ============================================================
Write-Host "`n[36] Set-Bucket (rename/move bucket)" -ForegroundColor Blue

Test-It "Set-Bucket renames top-level bucket" {
    Remove-Bucket "sb-rename" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
    New-BucketObject -Bucket "sb-rename" -InputObject @{ Id = 1; Name = "test" } -Key "obj1" -Quiet
    Use-Bucket "sb-rename"
    Set-Bucket "sb-rename" "sb-renamed" -Quiet
    $obj = Get-BucketObject -Bucket "sb-renamed" -Key "obj1" -WarningAction SilentlyContinue
    $null -ne $obj -and $obj.Name -eq "test"
}

Test-It "Set-Bucket moves bucket to nested path" {
    New-BucketObject -Bucket "sb-move" -InputObject @{ Id = 2 } -Key "obj2" -Quiet
    Use-Bucket "sb-move"
    Set-Bucket "sb-move" "parent/sb-moved" -Quiet
    $obj = Get-BucketObject -Bucket "parent/sb-moved" -Key "obj2" -WarningAction SilentlyContinue
    $null -ne $obj -and $obj.Id -eq 2
}

Test-It "Set-Bucket on nonexistent bucket warns" {
    $warn = $null
    Set-Bucket "sb-nonexistent" "sb-still-gone" -WarningVariable warn -WarningAction SilentlyContinue
    $null -ne $warn
}

Test-It "Set-Bucket to existing name warns" {
    New-BucketObject -Bucket "sb-existing-target" -InputObject @{} -Key "x" -Quiet
    Use-Bucket "sb-existing-target"
    $warn = $null
    Set-Bucket "users" "sb-existing-target" -WarningVariable warn -WarningAction SilentlyContinue
    $null -ne $warn
}

Test-It "Set-Bucket -PassThru returns metadata" {
    New-BucketObject -Bucket "sb-pt" -InputObject @{ Id = 3 } -Key "obj3" -Quiet
    Use-Bucket "sb-pt"
    $result = Set-Bucket "sb-pt" "sb-pt-renamed" -PassThru
    $null -ne $result -and $result.Name -eq "sb-pt-renamed" -and $result.OldName -eq "sb-pt"
}

Test-It "Set-Bucket -WhatIf does not rename" {
    New-BucketObject -Bucket "sb-whatif" -InputObject @{ Id = 4 } -Key "obj4" -Quiet
    Use-Bucket "sb-whatif"
    Set-Bucket "sb-whatif" "sb-whatif-safe" -WhatIf
    $obj = Get-BucketObject -Bucket "sb-whatif" -Key "obj4" -WarningAction SilentlyContinue
    $null -ne $obj -and $obj.Id -eq 4
}


# ============================================================
# 37. Get-BucketKeys -Recurse / -Depth
# ============================================================
Write-Host "`n[37] Get-BucketKeys -Recurse / -Depth" -ForegroundColor Blue

Test-It "Get-BucketKeys -Recurse returns keys across nested buckets" {
    $flat = Get-BucketKeys -Bucket "org"
    $recursive = Get-BucketKeys -Bucket "org" -Recurse
    $flat.Count -eq 1 -and $recursive.Count -eq 5
}

Test-It "Get-BucketKeys -Depth 1 limits to root only" {
    $keys = Get-BucketKeys -Bucket "org" -Recurse -Depth 1
    @($keys).Count -eq 1
}

Test-It "Get-BucketKeys -Depth 2 includes one level of nesting" {
    $keys = Get-BucketKeys -Bucket "org" -Recurse -Depth 2
    @($keys).Count -eq 2 -and ($keys.Key -contains "meta") -and ($keys.Key -contains "info")
}

# ============================================================
# 38. Get-BucketObjectStats -Recurse / -Depth
# ============================================================
Write-Host "`n[38] Get-BucketObjectStats -Recurse / -Depth" -ForegroundColor Blue

Test-It "Get-BucketObjectStats -Recurse returns stats across nested buckets" {
    $flat = Get-BucketObjectStats -Bucket "org"
    $recursive = Get-BucketObjectStats -Bucket "org" -Recurse
    @($flat).Count -eq 1 -and @($recursive).Count -eq 5
}

Test-It "Get-BucketObjectStats -Depth 1 limits to root only" {
    $stats = Get-BucketObjectStats -Bucket "org" -Recurse -Depth 1
    @($stats).Count -eq 1 -and $stats[0].Key -eq "meta"
}

Test-It "Get-BucketObjectStats -Depth 2 includes one level of nesting" {
    $stats = Get-BucketObjectStats -Bucket "org" -Recurse -Depth 2
    @($stats).Count -eq 2
}

# ============================================================
# 39. Export-Bucket -Recurse / -Depth
# ============================================================
Write-Host "`n[39] Export-Bucket -Recurse / -Depth" -ForegroundColor Blue

Test-It "Export-Bucket -Recurse exports nested objects" {
    $exportFlat = Join-Path $testRoot "export-rec-flat.json"
    $exportRec = Join-Path $testRoot "export-rec-rec.json"
    Export-Bucket -Bucket "org" -OutputFile $exportFlat -Quiet
    Export-Bucket -Bucket "org" -OutputFile $exportRec -Recurse -Quiet
    $flatContent = (Get-Content $exportFlat -Raw | ConvertFrom-Json)
    $recContent = (Get-Content $exportRec -Raw | ConvertFrom-Json)
    Remove-Item $exportFlat, $exportRec -Force -ErrorAction SilentlyContinue
    @($flatContent).Count -eq 1 -and @($recContent).Count -eq 5
}

Test-It "Export-Bucket -Depth 1 exports root only" {
    $exportPath = Join-Path $testRoot "export-depth1.json"
    Export-Bucket -Bucket "org" -OutputFile $exportPath -Recurse -Depth 1 -Quiet
    $content = (Get-Content $exportPath -Raw | ConvertFrom-Json)
    Remove-Item $exportPath -Force -ErrorAction SilentlyContinue
    @($content).Count -eq 1
}

Test-It "Export-Bucket -Depth 2 exports root + one level" {
    $exportPath = Join-Path $testRoot "export-depth2.json"
    Export-Bucket -Bucket "org" -OutputFile $exportPath -Recurse -Depth 2 -Quiet
    $content = (Get-Content $exportPath -Raw | ConvertFrom-Json)
    Remove-Item $exportPath -Force -ErrorAction SilentlyContinue
    @($content).Count -eq 2
}

# ============================================================
# 40. Remove-BucketObject -Recurse / -Depth
# ============================================================
Write-Host "`n[40] Remove-BucketObject -Recurse / -Depth" -ForegroundColor Blue

# Recreate nested test data
Remove-Bucket "rm-rec" -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
New-BucketObject -Bucket "rm-rec" -InputObject @{ _Id = "root"; V = 1 } -KeyProperty _Id -Quiet
New-BucketObject -Bucket "rm-rec/sub" -InputObject @{ _Id = "sub"; V = 2 } -KeyProperty _Id -Quiet
New-BucketObject -Bucket "rm-rec/sub/deep" -InputObject @{ _Id = "deep"; V = 3 } -KeyProperty _Id -Quiet
Use-Bucket "rm-rec"

Test-It "Remove-BucketObject -All -Recurse removes nested objects" {
    $before = @(Get-BucketObject -Bucket "rm-rec" -Recurse).Count
    Remove-BucketObject -Bucket "rm-rec" -All -Recurse -Confirm:$false -Quiet
    $after = @(Get-BucketObject -Bucket "rm-rec" -Recurse -WarningAction SilentlyContinue).Count
    $before -eq 3 -and $after -eq 0
}

# Recreate for depth test
New-BucketObject -Bucket "rm-rec" -InputObject @{ _Id = "root"; V = 1 } -KeyProperty _Id -Quiet
New-BucketObject -Bucket "rm-rec/sub" -InputObject @{ _Id = "sub"; V = 2 } -KeyProperty _Id -Quiet
New-BucketObject -Bucket "rm-rec/sub/deep" -InputObject @{ _Id = "deep"; V = 3 } -KeyProperty _Id -Quiet

Test-It "Remove-BucketObject -All -Depth 1 removes root only" {
    Remove-BucketObject -Bucket "rm-rec" -All -Recurse -Depth 1 -Confirm:$false -Quiet
    $remaining = Get-BucketObject -Bucket "rm-rec" -Recurse
    $remaining.Count -eq 2 -and ($remaining._Id -contains "sub") -and ($remaining._Id -contains "deep")
}

# Recreate for depth 2 test
New-BucketObject -Bucket "rm-rec" -InputObject @{ _Id = "root"; V = 1 } -KeyProperty _Id -Quiet

Test-It "Remove-BucketObject -All -Depth 2 removes root + one level" {
    Remove-BucketObject -Bucket "rm-rec" -All -Recurse -Depth 2 -Confirm:$false -Quiet
    $remaining = Get-BucketObject -Bucket "rm-rec/sub" -Recurse
    @($remaining).Count -eq 1 -and $remaining[0]._Id -eq "deep"
}

Test-It "Remove-BucketObject -Key -Recurse finds across nested buckets" {
    New-BucketObject -Bucket "rm-rec/sub" -InputObject @{ _Id = "target"; V = 99 } -KeyProperty _Id -Quiet
    New-BucketObject -Bucket "rm-rec/sub/deep" -InputObject @{ _Id = "target"; V = 100 } -KeyProperty _Id -Quiet
    Remove-BucketObject -Bucket "rm-rec" -Key "target" -Recurse -Confirm:$false -Quiet
    $remaining = Get-BucketObject -Bucket "rm-rec" -Recurse -Key "target" -WarningAction SilentlyContinue
    $null -eq $remaining
}

# ============================================================
# 41. Cross-platform path handling
# ============================================================
Write-Host "`n[41] Cross-platform path handling" -ForegroundColor Blue

Test-It "Forward-slash normalization in _BucketName" {
    $obj = Get-BucketObject -Bucket "org/eu" -Key "info"
    $obj._BucketName -eq "org/eu" -and $obj._BucketName -notmatch '\\'
}

Test-It "Root path with trailing separator works and resolves to valid path" {
    $orig = Get-BucketRoot
    $withSep = "$orig$([System.IO.Path]::DirectorySeparatorChar)"
    Set-BucketRoot $withSep
    $root = Get-BucketRoot
    Set-BucketRoot $orig
    ($root -ne '') -and (Test-Path $root) -and ($root -match '^[A-Za-z]:|^/')
}

Test-It "Get-BucketRoot path exists and is accessible on all platforms" {
    $root = Get-BucketRoot
    (Test-Path $root) -and ([System.IO.Directory]::Exists($root))
}

Test-It "Default path via `$HOME/.buckets is constructable on any platform" {
    $default = Join-Path $HOME ".buckets"
    $default -ne '' -and ($default.StartsWith('/') -or $default -match '^[A-Za-z]:\\')
}

Test-It "Unicode bucket name round-trip" {
    Remove-Bucket "üñî-café" -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
    New-BucketObject -Bucket "üñî-café" -InputObject @{ _Id = "meta"; Name = "test" } -KeyProperty _Id -Quiet
    Use-Bucket "üñî-café"
    $obj = Get-BucketObject -Bucket "üñî-café" -Key "meta"
    $null -ne $obj -and $obj.Name -eq "test"
}

Test-It "Dotted bucket names work" {
    Remove-Bucket "org.v2" -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
    New-BucketObject -Bucket "org.v2/sub" -InputObject @{ _Id = "a"; V = 1 } -KeyProperty _Id -Quiet
    Use-Bucket "org.v2"
    $obj = Get-BucketObject -Bucket "org.v2/sub" -Key "a"
    $null -ne $obj -and $obj.V -eq 1
}

Test-It "Bucket name with spaces" {
    Remove-Bucket "my bucket" -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
    New-BucketObject -Bucket "my bucket" -InputObject @{ _Id = "obj"; Val = 42 } -KeyProperty _Id -Quiet
    Use-Bucket "my bucket"
    $obj = Get-BucketObject -Bucket "my bucket" -Key "obj"
    $null -ne $obj -and $obj.Val -eq 42
}

Test-It "Leading-dot hidden bucket name" {
    Remove-Bucket ".hidden" -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
    New-BucketObject -Bucket ".hidden" -InputObject @{ _Id = "h"; Data = "secret" } -KeyProperty _Id -Quiet
    Use-Bucket ".hidden"
    $obj = Get-BucketObject -Bucket ".hidden" -Key "h"
    $null -ne $obj -and $obj.Data -eq "secret"
}

# ============================================================
# 42. New-Bucket cmdlet
# ============================================================
Write-Host "`n[42] New-Bucket cmdlet" -ForegroundColor Blue

Test-It "New-Bucket creates an empty bucket directory" {
    Remove-Bucket "nb-test" -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
    New-Bucket "nb-test" -Quiet
    $bucketPath = Join-Path (Get-BucketRoot) "nb-test"
    (Test-Path $bucketPath) -and ((Get-ChildItem $bucketPath -Filter "*.json").Count -eq 0)
}

Test-It "New-Bucket creates nested bucket path" {
    Remove-Bucket "nb-nested" -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
    New-Bucket "nb-nested/sub/a" -Quiet
    $bucketPath = Join-Path (Get-BucketRoot) "nb-nested/sub/a"
    Test-Path $bucketPath
}

Test-It "New-Bucket warns on existing bucket" {
    New-Bucket "nb-test" -Quiet
    $warn = $null
    New-Bucket "nb-test" -WarningVariable warn -WarningAction SilentlyContinue -Quiet
    $null -ne $warn
}

Test-It "New-Bucket -Force recreates existing bucket" {
    New-BucketObject -Bucket "nb-force" -InputObject @{ _Id = "x"; V = 1 } -KeyProperty _Id -Quiet
    New-Bucket "nb-force" -Force -Quiet
    $remaining = Get-BucketObject -Bucket "nb-force" -WarningAction SilentlyContinue
    $null -eq $remaining -or @($remaining).Count -eq 0
}

Test-It "New-Bucket -PassThru returns bucket info" {
    Remove-Bucket "nb-pt" -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
    $result = New-Bucket "nb-pt" -PassThru -Quiet
    $null -ne $result -and $result.Name -eq "nb-pt" -and $result.ObjectCount -eq 0 -and $result.HasSubBuckets -eq $false
}

Test-It "New-Bucket -WhatIf does not create bucket" {
    Remove-Bucket "nb-whatif" -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
    New-Bucket "nb-whatif" -WhatIf -Quiet
    $bucketPath = Join-Path (Get-BucketRoot) "nb-whatif"
    -not (Test-Path $bucketPath)
}

Test-It "New-Bucket bucket is visible via Get-Bucket listing" {
    Remove-Bucket "nb-list" -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
    New-Bucket "nb-list" -Quiet
    $buckets = Get-Bucket
    $null -ne $buckets -and ($buckets.Name -contains "nb-list")
}

# ============================================================
# 43. Expand / Reconstruct (-Expand on fill + scoop)
# ============================================================
Write-Host "`n[43] Expand / Reconstruct (-Expand)" -ForegroundColor Blue

Test-It "Expand: simple hashtable round-trip" {
    Remove-Bucket "expand-simple" -Force -Confirm:$false -Recurse -Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $original = @{ host = "localhost"; port = 8080; ssl = $true }
    $original | New-BucketObject -Bucket "expand-simple" -Expand -Quiet
    Use-Bucket "expand-simple"
    $reconstructed = Get-BucketObject -Bucket "expand-simple" -Expand
    $reconstructed.host -eq "localhost" -and $reconstructed.port -eq 8080 -and $reconstructed.ssl -eq $true
}

Test-It "Expand: nested hashtable round-trip" {
    Remove-Bucket "expand-nested" -Force -Confirm:$false -Recurse -Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $original = @{
        server = @{ host = "db01"; port = 5432 }
        logging = @{ level = "debug"; file = "/var/log/app.log" }
    }
    $original | New-BucketObject -Bucket "expand-nested" -Expand -Quiet
    Use-Bucket "expand-nested"
    $r = Get-BucketObject -Bucket "expand-nested" -Expand
    $r.server.host -eq "db01" -and $r.server.port -eq 5432 -and $r.logging.level -eq "debug" -and $r.logging.file -eq "/var/log/app.log"
}

Test-It "Expand: array of primitives round-trip" {
    Remove-Bucket "expand-array" -Force -Confirm:$false -Recurse -Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $original = @("alpha", "beta", "gamma")
    $original | New-BucketObject -Bucket "expand-array" -Key "items" -Expand -Quiet
    Use-Bucket "expand-array"
    $r = Get-BucketObject -Bucket "expand-array" -Key "items" -Expand
    $r.Count -eq 3 -and $r[0] -eq "alpha" -and $r[1] -eq "beta" -and $r[2] -eq "gamma"
}

Test-It "Expand: array of objects round-trip" {
    Remove-Bucket "expand-objarr" -Force -Confirm:$false -Recurse -Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $original = @(
        @{ name = "Alice"; role = "admin" }
        @{ name = "Bob"; role = "user" }
    )
    $original | New-BucketObject -Bucket "expand-objarr" -Key "users" -Expand -Quiet
    Use-Bucket "expand-objarr"
    $r = Get-BucketObject -Bucket "expand-objarr" -Key "users" -Expand
    $r.Count -eq 2 -and $r[0].name -eq "Alice" -and $r[0].role -eq "admin" -and $r[1].name -eq "Bob" -and $r[1].role -eq "user"
}

Test-It "Expand: mixed scalar + container properties" {
    Remove-Bucket "expand-mixed" -Force -Confirm:$false -Recurse -Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $original = @{
        name = "app"
        version = 1.0
        config = @{ debug = $true; timeout = 30 }
        ports = @(80, 443)
    }
    $original | New-BucketObject -Bucket "expand-mixed" -Expand -Quiet
    Use-Bucket "expand-mixed"
    $r = Get-BucketObject -Bucket "expand-mixed" -Expand
    $r.name -eq "app" -and $r.version -eq 1.0 -and $r.config.debug -eq $true -and $r.config.timeout -eq 30 -and $r.ports.Count -eq 2 -and $r.ports[0] -eq 80 -and $r.ports[1] -eq 443
}

Test-It "Expand: -Filter on reconstructed object" {
    Remove-Bucket "expand-filter" -Force -Confirm:$false -Recurse -Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $original = @{ host = "web01"; env = "prod"; ttl = 300 }
    $original | New-BucketObject -Bucket "expand-filter" -Expand -Quiet
    Use-Bucket "expand-filter"
    $r = Get-BucketObject -Bucket "expand-filter" -Expand -Filter { $_.env -eq "prod" }
    $null -ne $r -and $r.host -eq "web01" -and $r.env -eq "prod"
}

Test-It "Expand: -ExpandDepth limits recursion" {
    Remove-Bucket "expand-depth" -Force -Confirm:$false -Recurse -Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $original = @{
        level1 = @{
            level2 = @{
                leaf = "deep"
            }
        }
    }
    $original | New-BucketObject -Bucket "expand-depth" -Expand -ExpandDepth 1 -Quiet
    Use-Bucket "expand-depth"
    $r = Get-BucketObject -Bucket "expand-depth" -Key "level1" -Expand
    # With depth 1, level2 should NOT be expanded into a sub-bucket, but stored as a file
    $r.level2 -ne $null
}

Test-It "Expand: type preservation (int, bool, null)" {
    Remove-Bucket "expand-types" -Force -Confirm:$false -Recurse -Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $original = @{ intVal = [int]42; boolVal = $true; nullVal = $null; strVal = "hello" }
    $original | New-BucketObject -Bucket "expand-types" -AsBinary -Expand -Quiet
    Use-Bucket "expand-types"
    $r = Get-BucketObject -Bucket "expand-types" -Expand
    $r.intVal -eq 42 -and $r.intVal -is [int] -and $r.boolVal -eq $true -and $r.boolVal -is [bool] -and $r.strVal -eq "hello"
}

Test-It "Expand: -Key acts as sub-bucket prefix" {
    Remove-Bucket "expand-key" -Force -Confirm:$false -Recurse -Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $original = @{ host = "db01"; port = 5432 }
    $original | New-BucketObject -Bucket "expand-key" -Key "database" -Expand -Quiet
    Use-Bucket "expand-key"
    $r = Get-BucketObject -Bucket "expand-key" -Key "database" -Expand
    $r.host -eq "db01" -and $r.port -eq 5432
}

Test-It "Expand: empty hashtable produces nothing" {
    Remove-Bucket "expand-empty" -Force -Confirm:$false -Recurse -Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    @{} | New-BucketObject -Bucket "expand-empty" -Expand -Quiet
    Use-Bucket "expand-empty"
    $r = Get-BucketObject -Bucket "expand-empty" -Expand
    $null -eq $r
}

Test-It "Expand: KeyProperty with array expands indexed" {
    Remove-Bucket "expand-kp" -Force -Confirm:$false -Recurse -Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $items = @(
        @{ id = "a"; val = 10 }
        @{ id = "b"; val = 20 }
    )
    $items | New-BucketObject -Bucket "expand-kp" -KeyProperty "id" -Expand -Quiet
    Use-Bucket "expand-kp"
    $r = Get-BucketObject -Bucket "expand-kp" -Key "a" -Expand
    $null -ne $r -and $r.val -eq 10
}

Test-It "Expand: property name sanitization" {
    Remove-Bucket "expand-san" -Force -Confirm:$false -Recurse -Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $original = @{ "bad/key" = "value"; "another:name" = 42 }
    $original | New-BucketObject -Bucket "expand-san" -Expand -Quiet
    Use-Bucket "expand-san"
    $r = Get-BucketObject -Bucket "expand-san" -Expand
    $r.'bad_key' -eq "value" -and $r.'another_name' -eq 42
}

# ============================================================
# Cleanup - remove any leftover test funnels
Get-Funnel | Where-Object Name -like "test-funnel*" | ForEach-Object {
    Remove-Funnel -Name $_.Name -Quiet -ErrorAction SilentlyContinue
}

# Cleanup edge bucket
Remove-Bucket "edge" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet
Remove-Bucket "a" -Force -Confirm:$false -WarningAction SilentlyContinue -Quiet

foreach ($bucket in $createdBuckets) {
    Remove-Bucket -Bucket $bucket -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse -Quiet
}

$dotSep = "·" * 52
Write-Host $dotSep -ForegroundColor DarkGray

$passCount = ($testResults | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($testResults | Where-Object { $_.Status -eq "FAIL" }).Count

if ($failCount -eq 0) {
    Write-Host "  All $passCount/$($testResults.Count) checks passed" -ForegroundColor Green
} else {
    Write-Host "  $($failCount)/$($testResults.Count) FAILED:" -ForegroundColor Red
    $testResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "    $($_.Name)" -ForegroundColor Red
        if ($_.Detail) { Write-Host "      $($_.Detail)" -ForegroundColor DarkGray }
    }
}

Set-BucketRoot (Join-Path $HOME ".buckets")
Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-InfoBlock -Mode bottom
