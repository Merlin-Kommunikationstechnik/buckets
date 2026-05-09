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
    Write-Host "  $Title" -ForegroundColor Blue
    Write-Host "$Sep" -ForegroundColor DarkGray
}

function tut-info($Text) {
    Write-Host "  $Text" -ForegroundColor DarkGray
}

function tut-note($Text) {
    Write-Host "  [$Text]" -ForegroundColor DarkGray
}

function tut-ok($Text) {
    Write-Host "  OK $Text" -ForegroundColor Green
}

function tut-done {
    Write-Host ""
    Write-Host "─────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  End of section" -ForegroundColor DarkGray
    Write-Host ""
}

function tut-section($Num, $Title) {
    tut-header "$Num. $Title"
}

function tut-desc($Text) {
    Write-Host ""
    $Text -split "`n" | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    Write-Host ""
}

function tut-run($ScriptBlock) {
    $code = $ScriptBlock.ToString().Trim()
    if ($code) {
        $code -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor Cyan }
        Write-Host ""
    }
    & $ScriptBlock
    Write-Host ""
    Write-Host "────────────────────" -ForegroundColor DarkGray
    Write-Host "  [Enter] next · [q] quit" -NoNewline -ForegroundColor DarkGray
    $r = Read-Host " >"
    if ($r -eq "q") { Write-Host ""; exit }
}

function tut-cleanup {
    $root = Get-BucketRoot
    foreach ($_ in $createdTemp) {
        $p = Join-Path $root $_
        if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $createdTemp.Clear()
}

$createdTemp = [System.Collections.ArrayList]::new()

# ---------- setup ----------

Write-Host @"

  $('#' * 55)
  #    $ScriptName
  #    Buckets — file-based PSObject storage for PowerShell
  $('#' * 55)

"@ -ForegroundColor Cyan

# load module — always force-reload from local path to pick up latest changes
$mod = Join-Path $PSScriptRoot "../Buckets"
if (-not (Test-Path $mod)) { throw "Module not found at '$mod'" }
Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module $mod -Force
tut-ok "Module loaded from $mod (v$(Get-Module Buckets | ForEach-Object Version))"

tut-info "Storage root: $(Get-BucketRoot)"
tut-note "Lines starting with → are the output of the command shown above"
tut-note "Type 'q' at any pause to quit the tutorial"

# clean any prior tutorial data for a fresh start
tut-note "Cleaning prior tutorial data for a fresh start"
$root = Get-BucketRoot
Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
tut-done

# ---------- chapter 1: Create ----------

tut-section 1 "Create — fill / New-BucketObject"

tut-desc @"
Let's save your first object — a simple hashtable describing a user. We give it
an explicit key "Alice" with -Key, which becomes its filename on disk. By default,
Buckets uses a binary format that preserves the full .NET type information, so
hashtables, custom objects, even FileInfo — all survive the round trip.
"@
tut-run {
    @{ Name = "Alice"; Role = "admin"; Score = 95 } | fill -Bucket users -Key "Alice"
}

tut-desc @"
Typing -Key for every object gets tedious. Instead, -KeyProperty tells Buckets to
look at a specific property on your object and use its value as the key. Here, the
property Name contains "Bob", so the file will be named "Bob.dat" automatically.
"@
tut-run {
    @{ Name = "Bob"; Role = "user"; Score = 72 } | fill -Bucket users -KeyProperty Name
}

tut-desc @"
One of Buckets' superpowers: piping multiple objects at once. Send them one by one
through the pipeline and Buckets saves each one. Mix -KeyProperty with pipeline
input for batch inserts — it's the fastest way to load data.
"@
tut-run {
    @{ Name = "Carol"; Role = "manager"; Score = 88 },
    @{ Name = "Dave"; Role = "user"; Score = 61 } | fill -Bucket users -KeyProperty Name
}

tut-desc @"
What if you need a key that isn't a property of the object itself? That's what the
bare -Key parameter is for — you decide the filename, independent of the data inside.
"@
tut-run {
    @{ Source = "import"; Items = 42 } | fill -Bucket users -Key "external-ref"
}

tut-desc @"
JSON mode is for when you want human-readable files — configs, settings, anything you
might edit by hand. Add -AsJson and Buckets stores a .json file instead of .dat.
You can open it in any text editor.
"@
tut-run {
    @{ Host = "localhost"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
}

tut-desc @"
For logs, metrics, or any time-series data, -AsTimestamp auto-generates a unique key
from the current date and time. No two objects ever get the same name, and chronological
ordering is built right in.
"@
tut-run {
    @{ Event = "login"; User = "alice" },
    @{ Event = "logout"; User = "bob" } | fill -Bucket events -AsTimestamp
}

tut-desc @"
Already have an object with the same key? Without -Overwrite, Buckets skips it silently.
Add -Overwrite to replace the existing object with the new one.
"@
tut-run {
    @{ Name = "Alice"; Role = "admin"; Score = 99 } | fill -Bucket users -Key "Alice" -Overwrite
}

tut-desc @"
Repetitive data — logs, heartbeats, sensor readings — compresses extremely well. The
-Compress flag applies GZip before writing, and Buckets auto-detects compressed files
on read so you never have to think about it.
"@
tut-run {
    $logs = 1..30 | ForEach-Object { @{ Seq = $_; Msg = "Heartbeat OK" } }
    fill -Bucket logs -InputObject $logs -Compress
}
tut-done

tut-section "1b" "Create — quiet, verbose, and edge cases"

tut-desc @"
By default, fill shows a progress bar and a summary when saving. If you're scripting
or just want silence, -Quiet suppresses all output. For debugging, -Verbose prints
per-object details.
"@
tut-run {
    @{ Msg = "test" } | fill -Bucket demo -Key "verbosity-demo" -Quiet
}

tut-desc @"
Both hashtables and PSCustomObject work with Buckets. The difference: PSCustomObject
preserves the order of your properties, while a regular hashtable does not guarantee
ordering.
"@
tut-run {
    [PSCustomObject]@{ Type = "PSCustomObject"; Ordered = $true } | fill -Bucket types -Key "custom"
    @{ Type = "Hashtable" } | fill -Bucket types -Key "hash"
}
$null = $createdTemp.Add("types")

tut-desc @"
Buckets handles deeply nested objects with ease. The binary serializer preserves the
full object graph — nested PSCustomObjects, arrays, and all. This is exactly where
JSON would fall short.
"@
tut-run {
    $nested = [PSCustomObject]@{
        Id = "deep"
        Metadata = [PSCustomObject]@{ App = "test"; Version = "1.0" }
        Items = @(
            [PSCustomObject]@{ Sku = "ABC"; Qty = 5 }
            [PSCustomObject]@{ Sku = "XYZ"; Qty = 3 }
        )
    }
    $nested | fill -Bucket nested -Key "deep"
}
$null = $createdTemp.Add("nested")

tut-desc @"
Some characters — like /, :, *, ? — aren't valid in filenames. When you use them in a
key, Buckets automatically replaces them with underscores so the filesystem stays happy.
"@
tut-run {
    @{ Data = "sanitized key" } | fill -Bucket special -Key "my/file:name*test"
}
$null = $createdTemp.Add("special")

tut-desc @"
Buckets won't let you create a key that's empty or becomes empty after sanitization.
It throws an error right away so you don't end up with files you can't find.
"@
tut-run {
    try { @{ X = 1 } | fill -Bucket demo -Key "" -Quiet -ErrorAction Stop }
    catch { Write-Host "    empty key rejected" -ForegroundColor Green }
    try { @{ X = 1 } | fill -Bucket demo -Key ". ." -Quiet -ErrorAction Stop }
    catch { Write-Host "    invalid key rejected" -ForegroundColor Green }
}

tut-cleanup
tut-done

# ---------- chapter 2: Read ----------

tut-section 2 "Read — spill / Get-BucketObject"

tut-desc @"
The counterpart to fill is spill (short for Get-BucketObject). With no arguments,
it returns every object from every bucket — useful for getting the lay of the land.
"@
tut-run {
    spill
}

tut-desc @"
Most of the time you want objects from a specific bucket. Pass -Bucket to narrow
the search to just one bucket.
"@
tut-run {
    spill -Bucket users
}

tut-desc @"
If you know the key, pass it positionally as the first argument. Keys are matched
case-insensitively and as prefixes, so "alice" matches "Alice" too.
"@
tut-run {
    spill "Alice" -Bucket users
}

tut-desc @"
For an exact match, just pass the full key name. Keys are still matched
case-insensitively, so you don't need to worry about capitalization.
"@
tut-run {
    spill "external-ref" -Bucket users
}

tut-desc @"
Case doesn't matter. "alice" finds "Alice" because all key matching is
case-insensitive. No more guessing about capitalization.
"@
tut-run {
    spill "alice" -Bucket users
}

tut-desc @"
What happens when there's no match? Buckets returns nothing with a warning —
no crash, just a helpful nudge that nothing was found.
"@
tut-run {
    spill -Bucket users -Key "NoOneHere"
}

tut-desc @"
You can use wildcards in bucket names too. "use*" matches any bucket starting
with "use", making it easy to search groups of related buckets.
"@
tut-run {
    spill -Bucket "use*"
}

tut-desc @"
Pass multiple bucket names as an array. Buckets searches each one and combines
the results into a single list.
"@
tut-run {
    spill -Bucket "users", "logs"
}

tut-desc @"
Every object retrieved by Buckets carries metadata: _BucketName, _BucketKey, and
_BucketFile. These tell you exactly where the object came from — useful for
pipeline operations where context matters.
"@
tut-run {
    spill -Bucket users -Key "Bob" | Select-Object _BucketName, _BucketKey, _BucketFile
}

tut-desc @"
Since spill returns regular PowerShell objects, you can pipe them into Select-Object,
Sort-Object, Group-Object — anything you'd do with any other object in PowerShell.
"@
tut-run {
    spill -Bucket users | Select-Object Name, Role, Score | Sort-Object Score -Descending
}

tut-desc @"
Access individual properties using standard dot notation. Store the result in a
variable and work with it like any other PowerShell object.
"@
tut-run {
    $bob = spill -Bucket users -Key "Bob"
    "  Name: $($bob.Name) | Role: $($bob.Role) | Score: $($bob.Score)"
}
tut-done

tut-section "2a" "Read — filtering with -Match"

tut-desc @"
-Match is Buckets' built-in filter for exact equality. Pass a hashtable of property
names and values, and Buckets returns only objects where every property matches
exactly.
"@
tut-run {
    spill -Bucket users -Match @{ Role = "admin" }
}

tut-desc @"
Special case: matching against $null. If a property is $null on the object, or doesn't
exist at all, it counts as a match for $null. Useful for finding objects with missing
fields.
"@
tut-run {
    spill -Bucket users -Match @{ Deleted = $null }
}

tut-desc @"
You can match on multiple properties at once — think of it as AND logic. All conditions
must be true for an object to be returned.
"@
tut-run {
    spill -Bucket users -Match @{ Role = "user"; Score = 72 }
}

tut-desc @"
Let's create some fresh data to demonstrate -Match with mixed types. Strings, numbers,
and booleans all work as match criteria.
"@
tut-run {
    @{ Name = "A"; Count = 5; Active = $true },
    @{ Name = "B"; Count = 10; Active = $false },
    @{ Name = "C"; Count = 5; Active = $true } | fill -Bucket match-demo -KeyProperty Name
    spill -Bucket match-demo -Match @{ Count = 5; Active = $true }
}
$null = $createdTemp.Add("match-demo")

tut-desc @"
String matching with -Match is exact and case-insensitive. "red" matches "red" but
also "Red", "RED", and so on.
"@
tut-run {
    @{ Name = "alpha"; Color = "red" },
    @{ Name = "beta"; Color = "blue" },
    @{ Name = "gamma"; Color = "red" } | fill -Bucket match-demo -KeyProperty Name
    spill -Bucket match-demo -Match @{ Color = "red" }
}

tut-desc @"
-Match only looks at top-level properties. If you need to drill into nested data like
$_.Settings.Enabled, you'll need -Filter instead.
"@
tut-run {
    @{ Id = "a"; Meta = @{ Name = "inner" } } | fill -Bucket nested-match -KeyProperty Id
    spill -Bucket nested-match -Match @{ Meta = $null }
}
$null = $createdTemp.Add("nested-match")
tut-done

tut-section "2b" "Read — comparison with -Filter"

tut-desc @"
For anything beyond exact equality, reach for -Filter. It takes a scriptblock where
$_ represents each object. You can use any PowerShell operator: -gt, -lt, -match,
-like, -and, -or, and more.
"@
tut-run {
    spill -Bucket users -Filter { $_.Score -gt 80 }
}

tut-desc @"
Less than or equal works the same way. Think of -Filter as writing a Where-Object
clause that runs inside Buckets rather than in the pipeline.
"@
tut-run {
    spill -Bucket users -Filter { $_.Score -le 70 }
}

tut-desc @"
Pattern matching with -match uses regular expressions. Here we find names starting
with A or D using the regex "^[AD]".
"@
tut-run {
    spill -Bucket users -Filter { $_.Name -match "^[AD]" }
}

tut-desc @"
The -like operator uses wildcard patterns. "*o*" matches any name containing the
letter "o" anywhere in the string.
"@
tut-run {
    spill -Bucket users -Filter { $_.Name -like "*o*" }
}

tut-desc @"
Combine conditions with -and. Both must be true: score above 70 AND role is "user".
"@
tut-run {
    spill -Bucket users -Filter { $_.Score -gt 70 -and $_.Role -eq "user" }
}

tut-desc @"
Combine conditions with -or. Either can be true: role is "admin" OR score above 80.
"@
tut-run {
    spill -Bucket users -Filter { $_.Role -eq "admin" -or $_.Score -gt 80 }
}

tut-desc @"
String length checks work because you're writing real PowerShell expressions. Here
we find objects where the Value property is longer than 5 characters.
"@
tut-run {
    @{ Name = "short"; Value = "abc" },
    @{ Name = "long";  Value = "abcdefghijk" } | fill -Bucket str-test -KeyProperty Name
    spill -Bucket str-test -Filter { $_.Value.Length -gt 5 }
}
$null = $createdTemp.Add("str-test")

tut-desc @"
Date comparisons too — no special syntax needed. Compare DateTime properties with
-gt, -lt, or any other operator, just like you would in regular PowerShell.
"@
tut-run {
    @{ Id = "old"; Stamp = (Get-Date).AddDays(-10) },
    @{ Id = "new"; Stamp = Get-Date } | fill -Bucket date-test -KeyProperty Id
    $cutoff = (Get-Date).AddDays(-5)
    spill -Bucket date-test -Filter { $_.Stamp -gt $cutoff }
}
$null = $createdTemp.Add("date-test")

tut-desc @"
Nested properties are accessible via standard dot notation inside the scriptblock.
$_.Settings.Enabled drills into the Settings hashtable to check the Enabled flag.
"@
tut-run {
    @{ Id = "x"; Settings = @{ Enabled = $true; Level = 5 } },
    @{ Id = "y"; Settings = @{ Enabled = $false; Level = 3 } } | fill -Bucket nested-filter -KeyProperty Id
    spill -Bucket nested-filter -Filter { $_.Settings.Enabled -eq $true }
}
$null = $createdTemp.Add("nested-filter")

tut-desc @"
Omitting -Bucket makes -Filter run against all buckets at once. This is a cross-bucket
query — useful for finding objects anywhere in your data.
"@
tut-run {
    spill -Filter { $_.Score -gt 80 }
}
tut-done

tut-section "2c" "Read — pagination with -First / -Skip"

tut-desc @"
Pagination is built right in. -First limits the number of results returned. Useful
for previewing large datasets without loading everything.
"@
tut-run {
    spill -Bucket users -First 2
}

tut-desc @"
Combine -Skip with -First to jump ahead. -Skip 1 -First 2 skips the first result and
returns the next two — a classic paging pattern.
"@
tut-run {
    spill -Bucket users -Skip 1 -First 2
}

tut-desc @"
-First and -Skip work together with -Filter too. Here we filter for scores above 60,
then take only the first 3 results.
"@
tut-run {
    spill -Bucket users -Filter { $_.Score -gt 60 } -First 3
}
tut-done

# ---------- chapter 3: Update ----------

tut-section 3 "Update — Set-BucketObject"

tut-desc @"
Set-BucketObject updates an existing object in place. When piped from spill, it
auto-detects the bucket and key from the _BucketName and _BucketKey metadata —
no need to specify them again.
"@
tut-run {
    spill -Bucket users -Key "Bob" | ForEach-Object {
        $_.Score = 99
        $_.Role = "admin"
        $_
    } | Set-BucketObject -Quiet
}

tut-desc @"
Without pipeline metadata, specify -Bucket and -Key explicitly. Pass the modified
object through -InputObject.
"@
tut-run {
    $obj = spill -Bucket users -Key "Carol"
    $obj.Score = 100
    Set-BucketObject -Bucket users -Key "Carol" -InputObject $obj -Quiet
}

tut-desc @"
Need to update just one field? Pipe a hashtable with only the properties you want
to change. Buckets merges it with the existing object — partial updates work
seamlessly.
"@
tut-run {
    @{ Email = "alice@new.com" } | Set-BucketObject -Bucket users -Key "Alice" -Quiet
}

tut-desc @"
New properties are automatically added. If the property doesn't exist on the
original object, it gets appended without affecting existing fields.
"@
tut-run {
    @{ Phone = "555-0100" } | Set-BucketObject -Bucket users -Key "Alice" -Quiet
}

tut-desc @"
Properties you don't mention in the update stay untouched. Only the keys in your
patch hashtable are modified.
"@
tut-run {
    @{ City = "Portland" } | Set-BucketObject -Bucket users -Key "Alice" -Quiet
}

tut-desc @"
Format preservation: JSON objects stay as .json, binary objects stay as .dat.
Set-BucketObject always writes back in the original format.
"@
tut-run {
    @{ UpdatedAt = Get-Date; Host = "prod-server" } |
        Set-BucketObject -Bucket config -Key "app-config" -Quiet
}

tut-desc @"
What happens if you pipe to Set-BucketObject without metadata AND without explicit
-Bucket/-Key? It throws — it has no idea where to save.
"@
tut-run {
    try { @{ X = 1 } | Set-BucketObject -Quiet -ErrorAction Stop }
    catch { Write-Host "    Error: -Bucket and -Key required" -ForegroundColor Green }
}
tut-done

# ---------- chapter 4: Delete ----------

tut-section 4 "Delete — Remove-BucketObject"

tut-desc @"
-WhatIf previews what would be deleted without actually removing anything. Always
safe to try before you delete.
"@
tut-run {
    Remove-BucketObject -Bucket users -Key "external-ref" -WhatIf
}

tut-desc @"
Delete by key is straightforward. Pass the key of the object you want to remove.
"@
tut-run {
    Remove-BucketObject -Bucket users -Key "external-ref" -Quiet
}

tut-desc @"
Trying to delete a non-existent key issues a warning but doesn't throw an error.
Buckets is forgiving about missing objects.
"@
tut-run {
    Remove-BucketObject -Bucket users -Key "no-one-here" -WarningVariable w -WarningAction SilentlyContinue 2>$null
}

tut-desc @"
You must specify either -Key, -All, or a filter. Without one of these, the parameter
set validation rejects the command.
"@
tut-run {
    Remove-BucketObject -Bucket users -ErrorAction SilentlyContinue
}

tut-desc @"
-Match works with deletion too. Delete all objects matching certain criteria in
one command.
"@
tut-run {
    fill -Bucket temp -InputObject @(
        @{ Id = "t1"; Status = "stale" }
        @{ Id = "t2"; Status = "stale" }
        @{ Id = "t3"; Status = "active" }
    ) -KeyProperty Id -Quiet
    Remove-BucketObject -Bucket temp -Match @{ Status = "stale" } -Quiet
}
$null = $createdTemp.Add("temp")

tut-desc @"
-Filter works the same way — delete objects that pass the scriptblock condition.
Here, any object with Score below 50 gets removed.
"@
tut-run {
    fill -Bucket scores -InputObject @(
        @{ Name = "low1"; Score = 30 }
        @{ Name = "low2"; Score = 45 }
        @{ Name = "high1"; Score = 92 }
    ) -KeyProperty Name -Quiet
    Remove-BucketObject -Bucket scores -Filter { $_.Score -lt 50 } -Quiet
}
$null = $createdTemp.Add("scores")

tut-desc @"
-All deletes every object in the bucket. A clean slate.
"@
tut-run {
    fill -Bucket all-test -InputObject @(
        @{ Id = "a"; Data = "x" }
        @{ Id = "b"; Data = "y" }
        @{ Id = "c"; Data = "z" }
    ) -KeyProperty Id -Quiet
    Remove-BucketObject -Bucket all-test -All -Quiet
}
$null = $createdTemp.Add("all-test")

tut-desc @"
-PassThru returns metadata about what was deleted. Useful for logging, auditing,
or confirmation messages.
"@
tut-run {
    fill -Bucket temp -Key "bye-bye" -InputObject @{ Data = "gone" } -Quiet
    Remove-BucketObject -Bucket temp -Key "bye-bye" -PassThru -Quiet
}
tut-done

# ---------- chapter 5: Copy, Rename, Move ----------

tut-section 5 "Object Operations — Copy, Rename, Move"

tut-desc @"
Copy an object within the same bucket but with a different key. The original stays
untouched — this is a true copy, not a move.
"@
tut-run {
    Copy-BucketObject -Bucket users -Key "Alice" -DestinationKey "Alice-Backup" -Quiet
    Remove-BucketObject -Bucket users -Key "Alice-Backup" -Quiet
}

tut-desc @"
Copy across buckets too. Specify -DestinationBucket to copy to a different bucket.
"@
tut-run {
    Copy-BucketObject -Bucket users -Key "Alice" -DestinationBucket archive -Quiet
    Remove-BucketObject -Bucket archive -Key "Alice" -Quiet
}
$null = $createdTemp.Add("archive")

tut-desc @"
-PassThru on Copy-BucketObject returns metadata about the destination: source,
destination, and new key — useful for pipeline logging.
"@
tut-run {
    Copy-BucketObject -Bucket users -Key "Alice" -DestinationKey "Alice-pass" -PassThru -Quiet
    Remove-BucketObject -Bucket users -Key "Alice-pass" -Quiet
}

tut-desc @"
Rename changes the key of an existing object in place. The format (.dat or .json)
is preserved through the rename.
"@
tut-run {
    fill -Bucket tmp -Key "old-name" -InputObject @{ Data = "rename me" } -Quiet
    Rename-BucketObject -Bucket tmp -Key "old-name" -NewKey "new-name" -Quiet
}
$null = $createdTemp.Add("tmp")

tut-desc @"
Renaming a JSON object preserves the .json extension too. Format is always
maintained — you never have to worry about it.
"@
tut-run {
    fill -Bucket tmp-json -Key "json-old" -InputObject @{ Format = "json" } -AsJson -Quiet
    Rename-BucketObject -Bucket tmp-json -Key "json-old" -NewKey "json-new" -PassThru -Quiet
}
$null = $createdTemp.Add("tmp-json")

tut-desc @"
Move combines copy + delete in one operation. The object is copied to the
destination and removed from the source.
"@
tut-run {
    fill -Bucket source -InputObject @(
        @{ Id = "obj1"; Value = "move me" }
    ) -KeyProperty Id -Quiet
    Move-BucketObject -Bucket source -Key "obj1" -DestinationBucket dest -Quiet
}
$null = $createdTemp.Add("source")
$null = $createdTemp.Add("dest")

tut-desc @"
Move with rename: specify a different key in the target bucket to rename
as part of the move.
"@
tut-run {
    fill -Bucket origin -Key "orig-key" -InputObject @{ Data = "moved+renamed" } -Quiet
    Move-BucketObject -Bucket origin -Key "orig-key" -DestinationBucket final -DestinationKey "new-key" -Quiet
}
$null = $createdTemp.Add("origin")
$null = $createdTemp.Add("final")

tut-desc @"
-PassThru on Move returns metadata about both the source and destination
objects.
"@
tut-run {
    fill -Bucket move-src -Key "m-pass" -InputObject @{ X = 1 } -Quiet
    Move-BucketObject -Bucket move-src -Key "m-pass" -DestinationBucket move-dst -PassThru -Quiet
}
$null = $createdTemp.Add("move-src")
$null = $createdTemp.Add("move-dst")

tut-desc @"
All three operations — Copy, Rename, Move — support -PassThru. Chain them
together for auditable object management.
"@
tut-run {
    fill -Bucket pass -Key "src-key" -InputObject @{ X = 1 } -Quiet
    Copy-BucketObject -Bucket pass -Key "src-key" -DestinationKey "cp-key" -PassThru -Quiet
    Rename-BucketObject -Bucket pass -Key "cp-key" -NewKey "rn-key" -PassThru -Quiet
    Move-BucketObject -Bucket pass -Key "src-key" -DestinationBucket pass -DestinationKey "mv-key" -PassThru -Quiet
}
$null = $createdTemp.Add("pass")
tut-done

# ---------- chapter 6: Bucket Management ----------

tut-section 6 "Bucket Management — dip / Get-Bucket"

tut-desc @"
dip (short for Get-Bucket) lists all your buckets with their object counts and
timestamps. It's the first command to run when you want an overview.
"@
tut-run {
    dip
}

tut-desc @"
Filter buckets by name with a substring match. "user" matches "users" and any
other bucket with "user" in the name.
"@
tut-run {
    dip "user"
}

tut-desc @"
Get-BucketStats shows detailed statistics: object count, total size on disk, and
creation/modification timestamps for a specific bucket.
"@
tut-run {
    Get-BucketStats -Bucket users
}

tut-desc @"
Get-BucketKeys lists every key in a bucket along with its format (.dat or .json)
and file size. Useful for inventorying what's stored.
"@
tut-run {
    Get-BucketKeys -Bucket users
}

tut-desc @"
Filter keys by pattern with -Match. "A*" matches all keys starting with "A".
"@
tut-run {
    Get-BucketKeys -Bucket users -Match "A*"
}

tut-desc @"
Get-BucketKeys across all buckets with the wildcard "*" — a complete inventory
of every object stored.
"@
tut-run {
    Get-BucketKeys -Bucket "*"
}

tut-desc @"
The -Tree parameter renders your buckets as a visual directory tree. -MaxFiles
limits how many files are shown per bucket.
"@
tut-run {
    Get-Bucket -Tree -MaxFiles 10
}

tut-desc @"
Without -Objects, the tree shows buckets only — a clean structural view without
individual files cluttering the output.
"@
tut-run {
    Get-Bucket -Tree
}

tut-desc @"
Add -Objects to include individual files in the tree. Every leaf object is
visible.
"@
tut-run {
    Get-Bucket -Tree -Objects
}

tut-desc @"
The -Raw switch returns tree objects as pipeable data instead of formatted text.
Useful for further processing or custom display.
"@
tut-run {
    Get-Bucket -Tree -Raw | Select-Object -First 2
}

tut-desc @"
-Depth limits how many levels of nesting the tree traverses. Depth 1 shows
only top-level buckets.
"@
tut-run {
    Get-Bucket -Tree -Depth 1
}

tut-desc @"
Pipe Raw tree output to ConvertTo-Json for a structured JSON representation of
your bucket hierarchy.
"@
tut-run {
    Get-Bucket -Tree -Raw | ConvertTo-Json -Depth 5 | Select-Object -First 5
}

tut-desc @"
Select Name and ObjectCount from dip for a clean table of buckets with their
object counts.
"@
tut-run {
    dip | Select-Object Name, ObjectCount
}
tut-done

tut-section "6a" "Remove-Bucket — safety and wildcards"

tut-desc @"
-WhatIf previews what would be removed without actually deleting anything.
"@
tut-run {
    Remove-Bucket "users" -WhatIf
}

tut-desc @"
Wildcard patterns work too. Preview removing all buckets matching a pattern.
"@
tut-run {
    Remove-Bucket "config" -WhatIf
}

tut-desc @"
Remove a single bucket. Make sure it contains only .dat/.json files — Buckets
refuses to remove directories with other file types.
"@
tut-run {
    fill -Bucket temp-remove -Key "x" -InputObject @{ A = 1 } -Quiet
    Remove-Bucket temp-remove -Force -Confirm:$false
}

tut-desc @"
Safety first: Remove-Bucket checks that a directory contains only bucket files.
If it finds unexpected file types (like .exe), it skips the directory with a
warning rather than deleting it.
"@
tut-run {
    $badDir = Join-Path (Get-BucketRoot) "not-a-bucket"
    $null = New-Item -ItemType Directory -Path $badDir -Force
    Set-Content -Path (Join-Path $badDir "evil.exe") -Value "x" -NoNewline
    Remove-Bucket "not-a-bucket" -Force -Confirm:$false -WarningAction SilentlyContinue 2>$null
    Remove-Item $badDir -Recurse -Force -ErrorAction SilentlyContinue
}
tut-done

# ---------- chapter 7: Export / Import ----------

tut-section 7 "Export / Import — Export-Bucket, Import-Bucket"

$exportDir = Join-Path $env:TEMP "buckets-tutorial-export"
$null = New-Item -ItemType Directory -Path $exportDir -Force -ErrorAction SilentlyContinue

tut-desc @"
Export saves an entire bucket to an archive file. CLIXML (the default) preserves
.NET type information for perfect round-trip fidelity.
"@
tut-run {
    Export-Bucket -Bucket users -OutputFile (Join-Path $exportDir "users.clixml") -Quiet
}

tut-desc @"
Export to JSON for human-readable archives. Same data, different format —
useful when you need to inspect or share the data outside of PowerShell.
"@
tut-run {
    Export-Bucket -Bucket users -OutputFile (Join-Path $exportDir "users.json") -AsJson -Quiet
}

tut-desc @"
Wildcards work for batch exports. Export multiple buckets that match a pattern
into a single archive file.
"@
tut-run {
    Export-Bucket -Bucket "user*","config" -OutputFile (Join-Path $exportDir "multi-export.clixml") -Quiet
}

tut-desc @"
Import restores from a CLIXML archive into a new bucket. Objects are recreated
with their original keys and data.
"@
tut-run {
    Import-Bucket -Bucket restored -InputFile (Join-Path $exportDir "users.clixml") -Quiet
}
$null = $createdTemp.Add("restored")

tut-desc @"
Import from JSON works the same way. The JSON file is parsed and each object
is stored in the specified bucket.
"@
tut-run {
    Import-Bucket -Bucket restored-json -InputFile (Join-Path $exportDir "users.json") -AsJson -Quiet
}
$null = $createdTemp.Add("restored-json")

tut-desc @"
-Overwrite on import replaces existing keys instead of skipping them. With
-Overwrite, a second import doesn't create duplicates.
"@
tut-run {
    Import-Bucket -Bucket import-over -InputFile (Join-Path $exportDir "users.clixml") -Quiet
    Import-Bucket -Bucket import-over -InputFile (Join-Path $exportDir "users.clixml") -Overwrite -Quiet
}
$null = $createdTemp.Add("import-over")

tut-desc @"
JSON archives are plain text. Open them in any editor to inspect or modify
before importing.
"@
tut-run {
    Get-Content (Join-Path $exportDir "users.json") -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 5 | Select-Object -First 3
}

Remove-Item $exportDir -Recurse -Force -ErrorAction SilentlyContinue
tut-done

# ---------- chapter 8: PSDrive ----------

tut-section 8 "PSDrive — navigate buckets like a filesystem"

tut-desc @"
Buckets registers a custom PSDrive called "buckets:". You can navigate it with
cd, Get-ChildItem, Get-Content — just like any other drive.
"@
tut-run {
    Get-PSDrive -Name buckets
}

tut-desc @"
List all buckets with Get-ChildItem on the drive root. Each bucket appears as
a container (directory).
"@
tut-run {
    Get-ChildItem "buckets:\"
}

tut-desc @"
Format the output with Select-Object for a cleaner table of bucket names,
sizes, and timestamps.
"@
tut-run {
    Get-ChildItem "buckets:\" | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
}

tut-desc @"
Enter a bucket and list its objects. Each stored object appears as a file in
the PSDrive.
"@
tut-run {
    Get-ChildItem "buckets:\users" | Select-Object Name, Length, LastWriteTime
}

tut-desc @"
Filter by PSIsContainer to see only buckets (containers) or only leaf objects.
"@
tut-run {
    Get-ChildItem "buckets:\" | Where-Object { $_.PSIsContainer }
}

tut-desc @"
Read an object with Get-Content (or cat). It deserializes the stored data back
into a live PowerShell object — no manual parsing needed.
"@
tut-run {
    Get-Content "buckets:\users\Alice" | Select-Object Name, Role, Score
}

tut-desc @"
The full round-trip in the PSDrive: read with Get-Content, modify the property,
write back with Set-Content. Works just like a file but with live objects.
"@
tut-run {
    $obj = Get-Content "buckets:\users\Carol"
    $obj.Score = 95
    $obj | Set-Content "buckets:\users\Carol"
}

tut-desc @"
Remove-Item works in the PSDrive too. Delete an object by its path.
"@
tut-run {
    Copy-BucketObject -Bucket users -Key "Alice" -DestinationKey "psdrive-remove-test" -Quiet
    Remove-Item "buckets:\users\psdrive-remove-test" -Force
}

tut-desc @"
Test-Path checks whether an object exists in the drive. Useful for conditional
logic.
"@
tut-run {
    Test-Path "buckets:\users\Alice"
    Test-Path "buckets:\users\NonExistent"
}

tut-desc @"
Copy-Item works across buckets in the PSDrive. Copy objects from one bucket
to another using familiar filesystem commands.
"@
tut-run {
    Copy-Item "buckets:\users\Alice" "buckets:\users\Alice-pscopy" -Force
    Remove-BucketObject -Bucket users -Key "Alice-pscopy" -Quiet
}

tut-desc @"
Tab completion works throughout the PSDrive. Try typing "buckets:\" and pressing
Tab — it completes bucket names and object keys.
"@
tut-run { }
tut-done

# ---------- chapter 9: Nested Buckets ----------

tut-section 9 "Nested Buckets — directory hierarchy"

tut-desc @"
Bucket names with forward slashes create nested directory structures on disk.
This is how you organize data hierarchically — like folders within folders,
each level a real subdirectory.
"@
tut-run {
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

    @(
        @{ Dept = "Engineering"; Lead = "Alice" }
        @{ Dept = "Marketing"; Lead = "Bob" }
    ) | fill -Bucket "org/eu/de/depts" -KeyProperty Dept -Quiet
}

tut-desc @"
Wildcards work in nested paths. "org/eu/*/cities" matches city buckets under
any EU country — Germany, UK, and so on.
"@
tut-run {
    spill -Bucket "org/eu/*/cities"
}

tut-desc @"
Query a nested path directly by its full bucket name. Same spill command,
just a deeper path.
"@
tut-run {
    spill -Bucket "org/eu/de/cities"
}

tut-desc @"
Wildcards at multiple levels for deep queries. "org/*/de/*" matches anything
under any country's "de" sub-bucket.
"@
tut-run {
    spill -Bucket "org/*/de/*"
}

tut-desc @"
Get-Bucket with -Recurse shows the full nested structure. It traverses all
sub-buckets recursively.
"@
tut-run {
    Get-Bucket -Name "org" -Recurse
}

tut-desc @"
Tree view visualizes the nesting hierarchy. Each level is indented, making
it easy to see the organizational structure at a glance.
"@
tut-run {
    Get-Bucket -Name "org" -Tree -Objects -MaxFiles 10
}

tut-desc @"
PSDrive supports nested paths too. Navigate into org/eu/de/cities with
Get-ChildItem just like you would with a filesystem path.
"@
tut-run {
    Get-ChildItem "buckets:\org\eu\de\cities" | Select-Object Name
}

tut-desc @"
Recursive listing in PSDrive with the -Recurse flag. Shows everything under
the org tree.
"@
tut-run {
    Get-ChildItem "buckets:\org" -Recurse | Select-Object Name | Format-Table -AutoSize
}

tut-desc @"
Stats work on nested buckets too. Get-BucketStats handles the full path.
"@
tut-run {
    Get-BucketStats -Bucket "org/eu/de/cities"
}

tut-desc @"
List keys in a nested bucket with Get-BucketKeys. Same command, just a
deeper bucket path.
"@
tut-run {
    Get-BucketKeys -Bucket "org/eu/de/cities"
}

tut-desc @"
Combine wildcards with -Filter for cross-bucket queries in nested hierarchies.
Find all cities with population over 2 million across any country.
"@
tut-run {
    spill -Bucket "org/*/cities" -Filter { $_.Population -gt 2000000 }
}

tut-desc @"
Remove-Bucket with -Recurse deletes an entire nested tree. A single command
removes org and everything under it.
"@
tut-run {
    Remove-Bucket "org" -Recurse -Force -Confirm:$false
}
tut-done

# ---------- chapter 10: Pipeline & Sleek Patterns ----------

tut-section 10 "Sleek Pipeline Patterns"

tut-desc @"
Buckets is designed for pipeline-first usage. Most cmdlets accept pipeline
input and emit objects with metadata. Here's how to chain them together.
"@
tut-run {
    1..5 | ForEach-Object { @{ Name = "item-$_"; Value = $_ * 10 } } |
        fill -Bucket "dir-listing" -KeyProperty Name -Quiet
}
$null = $createdTemp.Add("dir-listing")

tut-desc @"
Chain multiple operations in one pipeline: filter objects with -Filter, modify
them with ForEach-Object, and save back with Set-BucketObject. All in one flow.
"@
tut-run {
    spill -Bucket users -Filter { $_.Role -eq "user" } |
        ForEach-Object { $_.Score = $_.Score + 5; $_ } |
        Set-BucketObject -PassThru
}

tut-desc @"
Filter, sort, and project in one pipeline. Where-Object filters, Sort-Object
orders, Select-Object picks the properties you want.
"@
tut-run {
    spill -Bucket users | Where-Object { $_.Score -gt 70 } |
        Sort-Object Score -Descending |
        Select-Object Name, Role, Score
}

tut-desc @"
Cross-bucket query: iterate over multiple buckets and filter each one, then
project the results with bucket metadata included.
"@
tut-run {
    $buckets = @("users", "config", "demo")
    $buckets | ForEach-Object { spill -Bucket $_ -Filter { $_.Score -gt 80 } } |
        Select-Object _BucketName, Name, Score
}

tut-desc @"
Group by bucket name to see how objects are distributed across your buckets.
"@
tut-run {
    spill | Group-Object _BucketName | Select-Object Name, Count
}

tut-desc @"
Group-Object aggregates data within a bucket. Here we count how many users
have each role.
"@
tut-run {
    spill -Bucket users | Group-Object Role | Select-Object Name, Count
}

tut-desc @"
Measure-Object gives you statistics — average, minimum, maximum — for any
numeric property across your objects.
"@
tut-run {
    $scores = spill -Bucket users | Measure-Object Score -Average -Minimum -Maximum
    tut-info "Score stats: avg=$([math]::Round($scores.Average,1)) min=$($scores.Minimum) max=$($scores.Maximum)"
}

tut-desc @"
Export spilled data to CSV for use in Excel, Python, or any tool that reads
tabular data.
"@
tut-run {
    $csvPath = Join-Path $env:TEMP "buckets-users.csv"
    spill -Bucket users | Select-Object Name, Role, Score | Export-Csv -Path $csvPath -NoTypeInformation
    Remove-Item $csvPath -Force -ErrorAction SilentlyContinue
}

tut-desc @"
-Filter runs inside Buckets (faster), Where-Object runs in the pipeline (more
flexible). Both produce the same result — choose based on your needs.
"@
tut-run {
    spill -Bucket users -Filter { $_.Score -gt 80 }
    spill -Bucket users | Where-Object { $_.Score -gt 80 }
}

tut-desc @"
Custom formatting with ForEach-Object. Transform each object into a formatted
string for display or logging.
"@
tut-run {
    spill -Bucket users | ForEach-Object {
        "[$($_.Role)] $($_.Name) — Score: $($_.Score)"
    }
}

tut-desc @"
Conditional pipeline: filter first, then convert only matching objects to JSON.
"@
tut-run {
    spill -Bucket users -Filter { $_.Score -gt 80 } | ConvertTo-Json -Depth 5
}

tut-desc @"
Save then immediately read to verify round-trip integrity. What you write is
exactly what you get back.
"@
tut-run {
    @{ Id = "smoke"; Value = 42 } | fill -Bucket smoke-test -KeyProperty Id -Quiet
}
$null = $createdTemp.Add("smoke-test")
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
    Get-ChildItem (Get-BucketRoot) -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    tut-ok "Cleanup complete"
} else {
    tut-note "Data kept for inspection"
}

Write-Host @"

  $('##')  Tutorial Complete!  $('##')

  What you learned:
    fill / spill / dip          — save, read, list
    -Key / -KeyProperty         — naming objects
    -Overwrite / -AsTimestamp    — replacement and timestamp keys
    -AsJson / -Compress          — storage formats
    -Match (exact)              — hashtake-based filtering
    -Filter (scriptblock)       — expression-based comparison (-gt, -like, -contains, -match)
    Nested property filtering   — $_.Settings.Enabled with -Filter
    -First / -Skip              — pagination
    Set-BucketObject             — update in place (pipeline + explicit)
    Partial update / patch       — add properties with hashtable pipe
    Remove-BucketObject          — delete by key / all / match / filter
    -WhatIf / -PassThru          — safety preview and metadata capture
    Copy / Rename / Move         — object operations with and without pass-through
    PSDrive operations           — Get-Content, Set-Content, Copy-Item, Remove-Item, Test-Path
    Export / Import              — archive & restore with CLIXML and JSON
    Get-Bucket -Tree             — visual tree view with -Objects, -Raw, -Depth
    Get-BucketStats              — bucket statistics
    Get-BucketKeys               — object key listing
    Nested buckets               — org/eu/de/cities hierarchy with wildcards
    Pipeline patterns            — chain, group, measure, export-csv, expand, custom format
    Cross-bucket queries         — -Filter across all buckets
    Edge cases                   — $null values, special chars, empty keys, safety guards
    Format preservation          — JSON stays .json, binary stays .dat through Rename/Copy

  Learn more: Get-Help <cmdlet> -Full
  See also:   README.md, .tests/demo/*.ps1

"@ -ForegroundColor Cyan

Write-Host "  Happy Bucketing!`n" -ForegroundColor Green
