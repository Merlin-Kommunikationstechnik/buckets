#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Interactive tutorial for the Buckets PowerShell module.
    Walks through all CRUD operations, filtering, pipelines, aliases,
    PSDrive, nested buckets, export/import, and bucket management.
#>

$ErrorActionPreference = "Stop"

# ---------- helpers ----------

$ScriptName = "Buckets Tutorial"
$Sep = "-" * 60

function tut-header($Title) {
    Write-Host "`n$Sep" -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "$Sep" -ForegroundColor DarkGray
}

function tut-cmd($Text) {
    Write-Host "  $ $Text" -ForegroundColor Yellow
}

function tut-info($Text) {
    Write-Host "  $Text" -ForegroundColor White
}

function tut-ok($Text) {
    Write-Host "  OK $Text" -ForegroundColor Green
}

function tut-note($Text) {
    Write-Host "  [$Text]" -ForegroundColor DarkGray
}

function tut-done {
    Write-Host "  Press Enter to continue, or type q to quit tutorial.`n" -NoNewline
    $r = Read-Host " >"
    if ($r -eq "q") { Write-Host "`n  Tutorial aborted. Bye!`n" -ForegroundColor Cyan; exit }
}

function tut-section($Num, $Title) {
    tut-header "$Num. $Title"
}

function tut-check($Cond, $Msg) {
    if ($Cond) { tut-ok $Msg } else { Write-Host "  FAIL $Msg" -ForegroundColor Red }
}

function tut-run($Desc, $ScriptBlock) {
    tut-cmd $Desc
    & $ScriptBlock
}

# ---------- setup ----------

Write-Host @"

  $('#' * 55)
  #    $ScriptName
  #    Buckets — file-based PSObject storage for PowerShell
  $('#' * 55)

"@ -ForegroundColor Cyan

# load module
if (-not (Get-Module Buckets -ErrorAction SilentlyContinue)) {
    $mod = Join-Path $PSScriptRoot "../Buckets"
    if (-not (Test-Path $mod)) { throw "Module not found at '$mod'" }
    Import-Module $mod -Force
    tut-ok "Module loaded from $mod"
} else {
    tut-ok "Module already loaded (v$(Get-Module Buckets | ForEach-Object Version))"
}

tut-info "Storage root: $(Get-BucketRoot)"
tut-note "Type 'q' at any pause to quit the tutorial"

# clean any prior tutorial data so cross-bucket queries stay fast
tut-note "Cleaning prior tutorial data for a fresh start"
$root = Get-BucketRoot
@("users", "config", "logs", "events", "demo", "temp", "scores", "temp2",
  "empty-test", "tmp", "source", "dest", "pass", "archive", "exported",
  "restored", "restored-json", "dir-listing") | ForEach-Object {
    $p = Join-Path $root $_
    if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
}
tut-done

# ---------- chapter 1: Create ----------

tut-section 1 "Create — fill / New-BucketObject"
tut-info "The alias 'fill' is short for New-BucketObject."
tut-info "Objects are saved as binary (.dat) by default for full .NET type fidelity."
tut-note "JSON format is available via -AsJson"

tut-run "Save a single hashtable to the users bucket" {
    fill -Bucket users -Key "Alice" -InputObject @{ Name = "Alice"; Role = "admin"; Score = 95 } -Quiet
}
tut-done

tut-run "Save with a custom key via -KeyProperty (value of Name becomes filename)" {
    $users = @(
        @{ Name = "Bob";   Role = "user";    Score = 72 }
        @{ Name = "Carol"; Role = "manager"; Score = 88 }
        @{ Name = "Dave";  Role = "user";    Score = 61 }
    )
    fill -Bucket users -InputObject $users -KeyProperty Name -Quiet
}
tut-info "Each user became a file: Bob.dat, Carol.dat, Dave.dat"
tut-done

tut-run "Literal key with -Key (explicit filename, no extension)" {
    fill -Bucket users -Key "external-ref" -InputObject @{ Source = "import"; Items = 42 } -Quiet
}
tut-done

tut-run "Timestamp-based keys — useful for logs, metrics" {
    @(
        @{ Event = "login"; User = "alice" }
        @{ Event = "logout"; User = "bob" }
    ) | fill -Bucket events -AsTimestamp -Quiet
}
tut-info "Filenames look like: 20260415_143022000_0.dat, 20260415_143022000_1.dat"
tut-done

tut-run "JSON format with -AsJson" {
    $config = @{
        _Id = "app-config"
        Host = "localhost"
        Port = 5432
        Features = @("auth", "audit", "cache")
    }
    fill -Bucket config -Key "app-config" -InputObject $config -AsJson -Quiet
}
tut-info "Stored as app-config.json (readable, editable)"
tut-done

tut-run "Compressed binary — GZip for repetitive data (~95% reduction)" {
    $logs = 1..30 | ForEach-Object { @{ Seq = $_; Msg = "Heartbeat OK"; Stamp = Get-Date } }
    fill -Bucket logs -Key "heartbeat" -InputObject $logs -Compress -Quiet
}
tut-info "Auto-detected on read via magic bytes (0x1F 0x8B)"
tut-done

tut-section "1b" "Create — default behavior vs -Quiet vs -Verbose"
tut-info "Without -Quiet: shows progress bar + summary"
tut-info "With -Quiet:   silent, no output"
tut-info "With -Verbose: per-object details"
tut-run "Quick example (quiet)" {
    fill -Bucket demo -Key "verbosity-demo" -InputObject @{ Msg = "test" } -Quiet
}
tut-done

# ---------- chapter 2: Read ----------

tut-section 2 "Read — spill / Get-BucketObject"
tut-info "The alias 'spill' is short for Get-BucketObject."
tut-info "Read from all buckets, a specific bucket, by key, or with filters."

tut-run "All objects from all buckets" {
    $all = spill -WarningAction SilentlyContinue
    tut-ok "$($all.Count) objects across all buckets"
}

tut-run "From a specific bucket" {
    spill -Bucket users
}

tut-run "By key (positional, case-insensitive prefix match)" {
    spill "Alice" -Bucket users
}

tut-run "Wildcard bucket names" {
    spill -Bucket "use*"
}

tut-run "Metadata properties: _BucketName, _BucketKey, _BucketFile" {
    spill -Bucket users -Key "Bob" | Select-Object _BucketName, _BucketKey, _BucketFile
}

tut-run "Pipelines — select, sort, group" {
    spill -Bucket users | Select-Object Name, Role, Score | Sort-Object Score -Descending
}
tut-done

tut-section "2a" "Read — filtering with -Match (exact match)"
tut-info "-Match uses a hashtable for exact equality. Supports `$null for absent properties."

tut-run "Exact match: Role = 'admin'" {
    spill -Bucket users -Match @{ Role = "admin" }
}

tut-run "Match with `$null (property must be absent)" {
    spill -Bucket users -Match @{ Deleted = $null }
}

tut-run "Multi-property match" {
    spill -Bucket users -Match @{ Role = "user"; Score = 72 }
}
tut-done

tut-section "2b" "Read — comparison with -Filter (scriptblock)"
tut-info "-Filter uses a scriptblock with `$_ referencing the object."
tut-info "Supports full PowerShell expressions: -gt, -lt, -match, -like, -and, -or, etc."

tut-run "Greater than: Score -gt 80" {
    spill -Bucket users -Filter { $_.Score -gt 80 }
}

tut-run "Pattern match: Name starts with A or D" {
    spill -Bucket users -Filter { $_.Name -match "^[AD]" }
}

tut-run "Multi-condition: Score > 70 AND Role is 'user'" {
    spill -Bucket users -Filter { $_.Score -gt 70 -and $_.Role -eq "user" }
}

tut-run "Cross-bucket filter (no -Bucket specified)" {
    spill -Filter { $_.Score -gt 80 }
}
tut-done

tut-section "2c" "Read — pagination with -First / -Skip"

tut-run "First 2 results" {
    spill -Bucket users -First 2
}

tut-run "Skip 1, take 2" {
    spill -Bucket users -Skip 1 -First 2
}

tut-run "Combined with -Filter" {
    spill -Bucket users -Filter { $_.Score -gt 60 } -First 3
}
tut-done

# ---------- chapter 3: Update ----------

tut-section 3 "Update — Set-BucketObject"
tut-info "Set-BucketObject updates an existing object in place."
tut-info "It auto-detects bucket and key from _BucketName / _BucketKey when piped."

tut-run "Pipeline round-trip: get, modify, save" {
    spill -Bucket users -Key "Bob" | ForEach-Object {
        $_.Score = 99
        $_.Role = "admin"
        $_
    } | Set-BucketObject -Quiet
    $updated = spill -Bucket users -Key "Bob"
    tut-check ($updated.Score -eq 99 -and $updated.Role -eq "admin") "Bob's score=99, role=admin"
}

tut-run "Explicit bucket/key (no pipeline)" {
    $obj = spill -Bucket users -Key "Carol"
    $obj.Score = 100
    Set-BucketObject -Bucket users -Key "Carol" -InputObject $obj -Quiet
    tut-check ((spill -Bucket users -Key "Carol").Score -eq 100) "Carol's score=100"
}

tut-run "Partial update — patch a hashtable onto existing" {
    @{ Email = "alice@new.com" } | Set-BucketObject -Bucket users -Key "Alice" -Quiet
    tut-check ((spill -Bucket users -Key "Alice").Email -eq "alice@new.com") "Alice email patched"
}

tut-info "Format is preserved: JSON stays JSON, binary stays binary"
tut-done

# ---------- chapter 4: Delete ----------

tut-section 4 "Delete — Remove-BucketObject"
tut-info "Remove-BucketObject supports -Key, -All, -Match, -Filter."
tut-info "SupportsShouldProcess: -WhatIf and -Confirm work."

tut-run "-WhatIf preview (does not delete)" {
    Remove-BucketObject -Bucket users -Key "external-ref" -WhatIf
}
tut-info "No actual deletion occurred."

tut-run "Delete by key" {
    Remove-BucketObject -Bucket users -Key "external-ref" -Quiet
    $check = spill -Bucket users -Key "external-ref" -WarningAction SilentlyContinue
    tut-check (-not $check) "external-ref removed"
}

tut-run "Delete with -Match filter" {
    fill -Bucket temp -InputObject @(
        @{ Id = "t1"; Status = "stale" }
        @{ Id = "t2"; Status = "stale" }
        @{ Id = "t3"; Status = "active" }
    ) -KeyProperty Id -Quiet
    Remove-BucketObject -Bucket temp -Match @{ Status = "stale" } -Quiet
    $remaining = spill -Bucket temp
    tut-check ($remaining.Count -eq 1 -and $remaining[0].Id -eq "t3") "Only t3 remains"
    Remove-Bucket temp -Force -Confirm:$false -WarningAction SilentlyContinue
}

tut-run "Delete with -Filter (comparison)" {
    fill -Bucket scores -InputObject @(
        @{ Name = "low1"; Score = 30 }
        @{ Name = "low2"; Score = 45 }
        @{ Name = "high1"; Score = 92 }
    ) -KeyProperty Name -Quiet
    Remove-BucketObject -Bucket scores -Filter { $_.Score -lt 50 } -Quiet
    $remaining = spill -Bucket scores -WarningAction SilentlyContinue
    tut-check ($remaining.Count -eq 1 -and $remaining[0].Score -eq 92) "Only high1 remains"
    Remove-Bucket scores -Force -Confirm:$false -WarningAction SilentlyContinue
}

tut-run "-PassThru returns removed metadata" {
    fill -Bucket temp2 -Key "bye-bye" -InputObject @{ Data = "gone" } -Quiet
    $removed = Remove-BucketObject -Bucket temp2 -Key "bye-bye" -PassThru -Quiet
    tut-check ($removed.Key -eq "bye-bye.dat") "PassThru returned metadata"
    Remove-Bucket temp2 -Force -Confirm:$false -WarningAction SilentlyContinue
}

tut-run "Remove-All with empty bucket warning" {
    fill -Bucket empty-test -Key "only-one" -InputObject @{ X = 1 } -Quiet
    Remove-BucketObject -Bucket empty-test -Key "only-one" -Quiet
    Remove-BucketObject -Bucket empty-test -All -Quiet
    tut-note "Warns if bucket is already empty (no-op)"
    Remove-Bucket empty-test -Force -Confirm:$false -WarningAction SilentlyContinue
}
tut-done

# ---------- chapter 5: Copy, Rename, Move ----------

tut-section 5 "Object Operations — Copy, Rename, Move"

tut-run "Copy-BucketObject — within same bucket, new key" {
    Copy-BucketObject -Bucket users -Key "Alice" -DestinationKey "Alice-Backup" -Quiet
    tut-check ((spill -Bucket users -Key "Alice-Backup").Name -eq "Alice") "Alice backup exists"
    Remove-BucketObject -Bucket users -Key "Alice-Backup" -Quiet
}

tut-run "Copy-BucketObject — across buckets" {
    Copy-BucketObject -Bucket users -Key "Alice" -DestinationBucket archive -Quiet
    tut-check ((spill -Bucket archive -Key "Alice").Name -eq "Alice") "Alice copied to archive"
    Remove-BucketObject -Bucket archive -Key "Alice" -Quiet
    Remove-Bucket archive -Force -Confirm:$false -WarningAction SilentlyContinue
}

tut-run "Rename-BucketObject — in-place key rename, preserves format" {
    fill -Bucket tmp -Key "old-name" -InputObject @{ Data = "rename me" } -Quiet
    Rename-BucketObject -Bucket tmp -Key "old-name" -NewKey "new-name" -Quiet
    $found = spill -Bucket tmp -Key "new-name"
    tut-check ($found.Data -eq "rename me") "Renamed, data intact"
    Remove-Bucket tmp -Force -Confirm:$false -WarningAction SilentlyContinue
}

tut-run "Move-BucketObject — copy across buckets + delete original" {
    fill -Bucket source -InputObject @(
        @{ Id = "obj1"; Value = "move me" }
    ) -KeyProperty Id -Quiet
    Move-BucketObject -Bucket source -Key "obj1" -DestinationBucket dest -Quiet
    $inSrc = spill -Bucket source -Key "obj1" -WarningAction SilentlyContinue
    $inDst = spill -Bucket dest -Key "obj1" -WarningAction SilentlyContinue
    tut-check ((-not $inSrc) -and $inDst.Value -eq "move me") "Moved, original gone"
    Remove-Bucket source -Force -Confirm:$false -WarningAction SilentlyContinue
    Remove-Bucket dest -Force -Confirm:$false -WarningAction SilentlyContinue
}

tut-run "-PassThru on all three returns metadata" {
    fill -Bucket pass -Key "src-key" -InputObject @{ X = 1 } -Quiet
    $r1 = Copy-BucketObject -Bucket pass -Key "src-key" -DestinationKey "cp-key" -PassThru -Quiet
    $r2 = Rename-BucketObject -Bucket pass -Key "cp-key" -NewKey "rn-key" -PassThru -Quiet
    $r3 = Move-BucketObject -Bucket pass -Key "src-key" -DestinationBucket pass -DestinationKey "mv-key" -PassThru -Quiet
    tut-check (($r1.DestinationKey -eq "cp-key") -and $r2.NewKey -eq "rn-key" -and $r3.DestinationKey -eq "mv-key") "All PassThru worked"
    Remove-Bucket pass -Force -Confirm:$false -WarningAction SilentlyContinue
}
tut-done

# ---------- chapter 6: Bucket Management ----------

tut-section 6 "Bucket Management — dip / Get-Bucket, Get-BucketStats, Get-BucketKeys"

tut-info "The alias 'dip' is short for Get-Bucket."

tut-run "List all buckets (recursive)" {
    dip
}

tut-run "Filter by name (substring match)" {
    dip "user"
}

tut-run "Get-BucketStats — count, size, timestamps" {
    Get-BucketStats -Bucket users
}

tut-run "Get-BucketKeys — list keys with format and size" {
    Get-BucketKeys -Bucket users
}

tut-run "Get-BucketKeys with pattern match" {
    Get-BucketKeys -Bucket users -Match "A*"
}

tut-run "Tree view — Get-Bucket -Tree" {
    Get-Bucket -Tree -MaxFiles 10
}

tut-run "Tree view, buckets only (no individual files)" {
    Get-Bucket -Tree
}

tut-run "Tree view with files" {
    Get-Bucket -Tree -Objects
}

tut-run "Raw tree objects (pipeable)" {
    Get-Bucket -Tree -Raw | Select-Object -First 2
}
tut-done

tut-section "6a" "Remove-Bucket — safety and wildcards"

tut-run "WhatIf preview" {
    Remove-Bucket "users" -WhatIf
}

tut-run "Wildcard pattern" {
    Remove-Bucket "config" -WhatIf
}

tut-info "Remove-Bucket only removes dirs with .dat/.json files (or empty). Skips others with a warning."
tut-done

# ---------- chapter 7: Export / Import ----------

tut-section 7 "Export / Import — Export-Bucket, Import-Bucket"

$exportDir = Join-Path $env:TEMP "buckets-tutorial-export"
$null = New-Item -ItemType Directory -Path $exportDir -Force -ErrorAction SilentlyContinue

tut-run "Export to CLIXML (binary archive)" {
    Export-Bucket -Bucket users -OutputFile (Join-Path $exportDir "users.clixml") -Quiet
    tut-ok "Exported to users.clixml"
}

tut-run "Export to JSON" {
    Export-Bucket -Bucket users -OutputFile (Join-Path $exportDir "users.json") -AsJson -Quiet
    tut-ok "Exported to users.json"
}

tut-run "Import from CLIXML" {
    Import-Bucket -Bucket restored -InputFile (Join-Path $exportDir "users.clixml") -Quiet
    $restored = spill -Bucket restored
    tut-check ($restored.Count -ge 3) "Imported $($restored.Count) objects"
    Remove-Bucket restored -Force -Confirm:$false -WarningAction SilentlyContinue
}

tut-run "Import from JSON" {
    Import-Bucket -Bucket restored-json -InputFile (Join-Path $exportDir "users.json") -AsJson -Quiet
    $restored = spill -Bucket "restored-json"
    tut-check ($restored.Count -ge 3) "Imported $($restored.Count) from JSON"
    Remove-Bucket "restored-json" -Force -Confirm:$false -WarningAction SilentlyContinue
}

Remove-Item $exportDir -Recurse -Force -ErrorAction SilentlyContinue
tut-done

# ---------- chapter 8: PSDrive ----------

tut-section 8 "PSDrive — navigate buckets like a filesystem"
tut-info "Buckets registers a buckets: PSDrive with a custom provider."
tut-info "Navigate with cd, list with dir, read objects with cat."

tut-run "Show the PSDrive" {
    Get-PSDrive -Name buckets
}

tut-run "List all buckets" {
    Get-ChildItem "buckets:\"
}

tut-run "Enter a bucket and list objects" {
    Get-ChildItem "buckets:\users" | Select-Object Name, Length, LastWriteTime
}

tut-run "Read an object with Get-Content (cat)" {
    Get-Content "buckets:\users\Alice" | Select-Object Name, Role, Score
}

tut-run "Pipeline: read, modify, write back" {
    $obj = Get-Content "buckets:\users\Carol"
    $obj.Score = 95
    $obj | Set-Content "buckets:\users\Carol"
    $check = Get-Content "buckets:\users\Carol"
    tut-check ($check.Score -eq 95) "Carol score updated via PSDrive"
}

tut-run "Tab-complete bucket names and object keys (try it!)"
tut-note "buckets:\ supports tab completion for all navigation commands"
tut-done

# ---------- chapter 9: Nested Buckets ----------

tut-section 9 "Nested Buckets — directory hierarchy"

tut-info "Bucket names support path separators (/, \) for nesting."
tut-info "Nested buckets are real subdirectories on disk."

tut-run "Create a hierarchy" {
    @(
        @{ Name = "Berlin"; Population = 3600000; Country = "DE" }
        @{ Name = "Munich"; Population = 1500000; Country = "DE" }
    ) | fill -Bucket "org/eu/de/cities" -KeyProperty Name -Quiet

    @(
        @{ Name = "London"; Population = 8900000; Country = "UK" }
        @{ Name = "Manchester"; Population = 550000; Country = "UK" }
    ) | fill -Bucket "org/eu/uk/cities" -KeyProperty Name -Quiet

    @(
        @{ Name = "New York"; Population = 8300000; Country = "US" }
    ) | fill -Bucket "org/us/cities" -KeyProperty Name -Quiet
    tut-ok "Nested hierarchy created"
}

tut-run "Query with wildcard — all EU cities" {
    spill -Bucket "org/eu/*/cities"
}

tut-run "Query nested path directly" {
    spill -Bucket "org/eu/de/cities"
}

tut-run "Tree view shows nesting" {
    Get-Bucket -Name "org" -Tree -NoObjects -MaxFiles 10
}

tut-run "PSDrive navigation for nested buckets" {
    Get-ChildItem "buckets:\org\eu\de\cities" | Select-Object Name
}

tut-info "Remove-Bucket with -Recurse deletes a nested bucket tree"
tut-run "Recursive remove" {
    Remove-Bucket "org" -Recurse -Force -Confirm:$false
    tut-check (-not (spill -Bucket "org/eu/de/cities" -WarningAction SilentlyContinue)) "org tree removed"
}
tut-done

# ---------- chapter 10: Pipeline & Sleek Patterns ----------

tut-section 10 "Sleek Pipeline Patterns"

tut-info "Buckets is designed for pipeline-first usage."
tut-info "Most cmdlets accept pipeline input and emit objects with metadata."

tut-run "Save pipeline output directly" {
    Get-ChildItem $PSScriptRoot -File | Select-Object -First 5 |
        fill -Bucket "dir-listing" -KeyProperty Name -Quiet
    $count = (spill -Bucket "dir-listing").Count
    tut-check ($count -eq 5) "5 files saved from pipeline"
    Remove-Bucket "dir-listing" -Force -Confirm:$false -WarningAction SilentlyContinue
}

tut-run "Chain: spill → Where-Object → Set-BucketObject" {
    $updated = spill -Bucket users -Filter { $_.Role -eq "user" } |
        ForEach-Object { $_.Score = $_.Score + 5; $_ } |
        Set-BucketObject -Quiet -PassThru
    if ($updated) {
        $check = spill -Bucket users -Key $updated[0]._BucketKey
        tut-check ($check.Score -gt 0) "User scores bumped via pipeline chain"
    }
}

tut-run "Filter, sort, and project in one pipeline" {
    spill -Bucket users | Where-Object { $_.Score -gt 70 } |
        Sort-Object Score -Descending |
        Select-Object Name, Role, Score
}

tut-run "Cross-bucket query with -Filter (scoped to tutorial buckets)" {
    $buckets = @("users", "config", "demo")
    $buckets | ForEach-Object { spill -Bucket $_ -Filter { $_.Score -gt 80 } } |
        Select-Object _BucketName, Name, Score
}

tut-run "Group by bucket name" {
    spill | Group-Object _BucketName | Select-Object Name, Count
}
tut-done

# ---------- chapter 11: Aliases Quick Reference ----------

tut-section 11 "Aliases & Shortcuts Reference"

tut-info "Three aliases are exported by the module:"
Write-Host @"

    fill   = New-BucketObject     — save objects
    spill  = Get-BucketObject     — retrieve objects
    dip    = Get-Bucket            — list buckets

"@ -ForegroundColor Yellow
tut-info "Additional shortcuts:"
Write-Host @"
    ls     = Get-ChildItem         — overridden globally (used in buckets: drive)
    cat    = Get-Content           — built-in, works with buckets: drive

"@ -ForegroundColor Yellow

tut-info "Pipeline parameter binding via metadata:"
Write-Host @"
    _BucketName   → -Bucket   (on Set-BucketObject)
    _BucketKey    → -Key      (on Set-BucketObject)
    _BucketFile   → full path to the stored file

"@ -ForegroundColor DarkGray
tut-done

# ---------- cleanup ----------

tut-section "Cleanup" "Remove tutorial data"

$confirm = Read-Host "  Remove all tutorial buckets? (Y/n)"
if ($confirm -ne "n") {
    @("users", "config", "logs", "events", "demo", "restored", "restored-json", "dir-listing") |
        ForEach-Object { Remove-Bucket $_ -Force -Confirm:$false -WarningAction SilentlyContinue }
    tut-ok "Cleanup complete"
} else {
    tut-note "Data kept for inspection"
}

Write-Host @"

  $('##')  Tutorial Complete!  $('##')

  What you learned:
    fill / spill / dip          — save, read, list
    -Key / -KeyProperty         — naming objects
    -AsJson / -Compress          — storage formats
    -Match / -Filter            — exact & expression filtering
    -First / -Skip              — pagination
    Set-BucketObject             — update in place (pipeline + explicit)
    Remove-BucketObject          — delete by key / all / match / filter
    Copy / Rename / Move         — object operations
    Export / Import              — archive & restore
    Get-Bucket -Tree           — visual tree view
    Get-BucketStats              — bucket statistics
    Get-BucketKeys               — object key listing
    buckets: PSDrive             — navigate like a filesystem
    Nested buckets               — org/eu/de/cities hierarchy
    Pipeline patterns            — chain, filter, sort, project

  Learn more: Get-Help <cmdlet> -Full
  See also:   README.md, .tests/demo/*.ps1

"@ -ForegroundColor Cyan

Write-Host "  Happy Bucketing!`n" -ForegroundColor Green
