#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Interactive tutorial for the Buckets PowerShell module.
    Walks through all CRUD operations, filtering, pipelines, aliases,
    PSDrive, nested buckets, export/import, and bucket management.
#>

$ErrorActionPreference = "Stop"

$Sep = '─' * 55

function tut-wipe {
    $root = Get-BucketRoot
    $current = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object Name
    $toRemove = $current | Where-Object { $_ -notin $script:userBuckets }
    if ($toRemove) {
        Remove-Bucket -Bucket $toRemove -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        $script:tutorialBuckets = ($script:tutorialBuckets + $toRemove) | Select-Object -Unique
        $script:tutorialBuckets | Set-Content (Join-Path $root ".tutorial-buckets") -Force
    }
}

function tut-pause {
    Write-Host ""
    Write-Host "  $Sep" -ForegroundColor DarkGray
    Write-Host "  [Enter] next · [q] quit > " -NoNewline -ForegroundColor DarkGray
    $r = Read-Host
    if ($r -eq "q") { Write-Host ""; exit }
    tut-wipe
    cls
}

function tut-write-code($Code) {
    $clean = $Code -replace "`r`n", "`n"
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($clean, [ref]$tokens, [ref]$errors)

    $cm = @{}
    $cm[[System.Management.Automation.Language.TokenKind]::Generic] = 'Yellow'
    $cm[[System.Management.Automation.Language.TokenKind]::Parameter] = 'Cyan'
    $cm[[System.Management.Automation.Language.TokenKind]::Variable] = 'Green'
    $cm[[System.Management.Automation.Language.TokenKind]::SplattedVariable] = 'Green'
    $cm[[System.Management.Automation.Language.TokenKind]::StringLiteral] = 'DarkYellow'
    $cm[[System.Management.Automation.Language.TokenKind]::StringExpandable] = 'DarkYellow'
    $cm[[System.Management.Automation.Language.TokenKind]::HereStringLiteral] = 'DarkYellow'
    $cm[[System.Management.Automation.Language.TokenKind]::HereStringExpandable] = 'DarkYellow'
    $cm[[System.Management.Automation.Language.TokenKind]::Comment] = 'DarkGreen'
    $cm[[System.Management.Automation.Language.TokenKind]::Number] = 'Yellow'

    $tk = [System.Management.Automation.Language.TokenKind]
    foreach ($k in @('If','Else','ElseIf','ForEach','For','While','Do','Until','Function','Filter','Param','Begin','Process','End','Switch','Return','Break','Continue','Exit','Throw','Try','Catch','Finally','Using','Class','Enum','Var','Data','DynamicParam','Parallel','Sequence','InlineScript','Configuration','Workflow','From','In')) {
        $cm[$k -as $tk] = 'Cyan'
    }
    foreach ($k in @('Equals','Plus','Minus','Multiply','Divide','Rem','Format','PlusPlus','MinusMinus','PlusEquals','MinusEquals','MultiplyEquals','DivideEquals','And','Or','Xor','Band','Bor','Bxor','Bnot','Shl','Shr','Ieq','Ine','Igt','Ilt','Ige','Ile','Imatch','Inotmatch','Ilike','Inotlike','Icontains','Inotcontains','Iin','Inotin','Ireplace','Isplit','Ceq','Cne','Cgt','Clt','Cge','Cle','Cmatch','Cnotmatch','Clike','Cnotlike','Ccontains','Cnotcontains','Cin','Cnotin','Creplace','Csplit','Is','IsNot','As','Not','Join','DotDot','Pipe','Exclaim','Comma')) {
        $cm[$k -as $tk] = 'DarkGray'
    }

    $sorted = $tokens | Where-Object {
        $_.Kind -ne $tk::NewLine -and $_.Kind -ne $tk::LineBreak -and $_.Kind -ne $tk::EndOfInput
    } | Sort-Object { $_.Extent.StartOffset }

    $pos = 0
    foreach ($token in $sorted) {
        $start = $token.Extent.StartOffset
        $end = $token.Extent.EndOffset
        if ($start -gt $pos) {
            $len = [Math]::Min($start - $pos, $clean.Length - $pos)
            $lines = $clean.Substring($pos, $len) -split "`n", -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($i -gt 0) { Write-Host "" }
                Write-Host $lines[$i] -NoNewline
            }
        }
        $color = $cm[$token.Kind]
        $lines = $token.Extent.Text -split "`n", -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($i -gt 0) { Write-Host "" }
            if ($color) { Write-Host $lines[$i] -NoNewline -ForegroundColor $color }
            else { Write-Host $lines[$i] -NoNewline }
        }
        $pos = $end
    }
    if ($pos -lt $clean.Length) {
        $trailing = $clean.Substring($pos).TrimEnd("`r", "`n", " ", "`t")
        if ($trailing -ne "") { Write-Host $trailing }
    }
    Write-Host ""
    Write-Host ""
    Write-Host "output:" -ForegroundColor DarkGray
}

# ---------- setup ----------

cls
$mod = Join-Path $PSScriptRoot "../Buckets"
if (-not (Test-Path $mod)) { throw "Module not found at '$mod'" }
Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module $mod -Force
$ver = (Get-Module Buckets).Version
$root = Get-BucketRoot
$marker = Join-Path $root ".tutorial-buckets"
$script:tutorialBuckets = @()
if (Test-Path $marker) {
    $stale = Get-Content $marker
    if ($stale) {
        Remove-Bucket -Bucket $stale -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
    Remove-Item $marker -Force -ErrorAction SilentlyContinue
}
$script:userBuckets = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object Name
tut-wipe

Write-Host ""
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host "  Buckets Tutorial  v$ver" -ForegroundColor White
Write-Host "  file-based PSObject storage for PowerShell" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Choose a track:" -ForegroundColor White
Write-Host "    [1] Beginner  — CRUD basics (create, read, update, delete)" -ForegroundColor Yellow
Write-Host "    [2] Advanced  — Copy, Rename, PSDrive, nested buckets, pipelines" -ForegroundColor Yellow
Write-Host "    [3] Full      — everything" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Type 'q' at any pause to quit" -ForegroundColor DarkGray
Write-Host ""
do {
    $mode = (Read-Host "  Enter choice [1/2/3]").Trim()
} while ($mode -notin @("1","2","3"))
$Beg = $mode -in @("1","3")
$Adv = $mode -in @("2","3")
cls

if ($Beg) {
# ---------- chapter 1: Create ----------

Write-Host ""
Write-Host @"
  Let's save your first object — a simple hashtable describing a user. We give it
  an explicit key "Alice" with -Key, which becomes its key. By default,
  Buckets uses a binary format that preserves the full .NET type information, so
  hashtables, custom objects, even FileInfo — all survive the round trip.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$alice = @{ Name = "Alice"; Role = "admin"; Score = 95 }
New-BucketObject -InputObject $alice -Bucket users -Key "Alice"
'@
$alice = @{ Name = "Alice"; Role = "admin"; Score = 95 }
New-BucketObject -InputObject $alice -Bucket users -Key "Alice"
tut-pause

Write-Host ""
Write-Host @"
  Typing -Key for every object gets tedious. Instead, -KeyProperty tells Buckets to
  look at a specific property on your object and use its value as the key. Here, the
  property Name contains "Bob", so the key will be "Bob" automatically.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$bob = @{ Name = "Bob"; Role = "user"; Score = 72 }
$bob | fill -Bucket users -KeyProperty Name
'@
$bob = @{ Name = "Bob"; Role = "user"; Score = 72 }
$bob | fill -Bucket users -KeyProperty Name
tut-pause

Write-Host ""
Write-Host @"
  One of Buckets' superpowers: piping multiple objects at once. Send them one by one
  through the pipeline and Buckets saves each one. Mix -KeyProperty with pipeline
  input for batch inserts — it's the fastest way to load data.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$users = @(
    @{ Name = "Carol"; Role = "manager"; Score = 88 }
    @{ Name = "Dave"; Role = "user"; Score = 61 }
)
$users | fill -Bucket users -KeyProperty Name
'@
$users = @(
    @{ Name = "Carol"; Role = "manager"; Score = 88 }
    @{ Name = "Dave"; Role = "user"; Score = 61 }
)
$users | fill -Bucket users -KeyProperty Name
tut-pause

Write-Host ""
Write-Host @"
  What if you need a key that isn't a property of the object itself? That's what the
  bare -Key parameter is for — you decide the key, independent of the data inside.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$data = @{ Source = "import"; Items = 42 }
$data | fill -Bucket users -Key "external-ref"
'@
$data = @{ Source = "import"; Items = 42 }
$data | fill -Bucket users -Key "external-ref"
tut-pause

Write-Host ""
Write-Host @"
  JSON mode is for when you want human-readable files — configs, settings, anything you
  might edit by hand. Add -AsJson and Buckets stores a .json file instead of .dat.
  You can open it in any text editor.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$config = @{ Host = "localhost"; Port = 5432 }
$config | fill -Bucket config -Key "app-config" -AsJson
'@
$config = @{ Host = "localhost"; Port = 5432 }
$config | fill -Bucket config -Key "app-config" -AsJson
tut-pause

Write-Host ""
Write-Host @"
  For logs, metrics, or any time-series data, -AsTimestamp auto-generates a unique key
  from the current date and time. No two objects ever get the same name, and chronological
  ordering is built right in.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$events = @(
    @{ Event = "login"; User = "alice" }
    @{ Event = "logout"; User = "bob" }
)
$events | fill -Bucket events -AsTimestamp
'@
$events = @(
    @{ Event = "login"; User = "alice" }
    @{ Event = "logout"; User = "bob" }
)
$events | fill -Bucket events -AsTimestamp
tut-pause

Write-Host ""
Write-Host @"
  Already have an object with the same key? Without -Overwrite, Buckets skips it silently.
  Add -Overwrite to replace the existing object with the new one.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$alice = @{ Name = "Alice"; Role = "admin"; Score = 99 }
New-BucketObject -InputObject $alice -Bucket users -Key "Alice" -Overwrite
'@
$alice = @{ Name = "Alice"; Role = "admin"; Score = 99 }
New-BucketObject -InputObject $alice -Bucket users -Key "Alice" -Overwrite
tut-pause

Write-Host ""
Write-Host @"
  Repetitive data — logs, heartbeats, sensor readings — compresses extremely well. The
  -Compress flag applies GZip before writing, and Buckets auto-detects compressed files
  on read so you never have to think about it.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$logs = 1..30 | ForEach-Object { @{ Seq = $_; Msg = "Heartbeat OK" } }
fill -Bucket logs -InputObject $logs -Compress
'@
$logs = 1..30 | ForEach-Object { @{ Seq = $_; Msg = "Heartbeat OK" } }
fill -Bucket logs -InputObject $logs -Compress
tut-pause
}

if ($Beg) {
# section 1b

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  1b. Create — quiet, verbose, and edge cases" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

Write-Host ""
Write-Host @"
  By default, fill shows a progress bar and a summary when saving. If you're scripting
  or just want silence, -Quiet suppresses all output. For debugging, -Verbose prints
  per-object details.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$data = @{ Msg = "test" }
$data | fill -Bucket demo -Key "verbosity-demo" -Quiet
'@
$data = @{ Msg = "test" }
$data | fill -Bucket demo -Key "verbosity-demo" -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Both hashtables and PSCustomObject work with Buckets. The difference: PSCustomObject
  preserves the order of your properties, while a regular hashtable does not guarantee
  ordering.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$custom = [PSCustomObject]@{ Type = "PSCustomObject"; Ordered = $true }
$custom | fill -Bucket types -Key "custom"
$hash = @{ Type = "Hashtable" }
$hash | fill -Bucket types -Key "hash"
'@
$custom = [PSCustomObject]@{ Type = "PSCustomObject"; Ordered = $true }
$custom | fill -Bucket types -Key "custom"
$hash = @{ Type = "Hashtable" }
$hash | fill -Bucket types -Key "hash"
tut-pause

Write-Host ""
Write-Host @"
  Buckets handles deeply nested objects with ease. The binary serializer preserves the
  full object graph — nested PSCustomObjects, arrays, and all. This is exactly where
  JSON would fall short.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$nested = [PSCustomObject]@{
    Id = "deep"
    Metadata = [PSCustomObject]@{ App = "test"; Version = "1.0" }
    Items = @(
        [PSCustomObject]@{ Sku = "ABC"; Qty = 5 }
        [PSCustomObject]@{ Sku = "XYZ"; Qty = 3 }
    )
}
$nested | fill -Bucket nested -Key "deep"
'@
$nested = [PSCustomObject]@{
    Id = "deep"
    Metadata = [PSCustomObject]@{ App = "test"; Version = "1.0" }
    Items = @(
        [PSCustomObject]@{ Sku = "ABC"; Qty = 5 }
        [PSCustomObject]@{ Sku = "XYZ"; Qty = 3 }
    )
}
$nested | fill -Bucket nested -Key "deep"
tut-pause

Write-Host ""
Write-Host @"
  Some characters — like /, :, *, ? — aren't valid in filenames. When you use them in a
  key, Buckets automatically replaces them with underscores so the filesystem stays happy.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$data = @{ Data = "sanitized key" }
$data | fill -Bucket special -Key "my/file:name*test"
'@
$data = @{ Data = "sanitized key" }
$data | fill -Bucket special -Key "my/file:name*test"
tut-pause

Write-Host ""
Write-Host @"
  Buckets won't let you create a key that's empty or becomes empty after sanitization.
  It throws an error right away so you don't end up with objects you can't find.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
try { @{ X = 1 } | fill -Bucket demo -Key "" -Quiet -ErrorAction Stop }
catch { Write-Host "    empty key rejected" -ForegroundColor Green }
try { @{ X = 1 } | fill -Bucket demo -Key ". ." -Quiet -ErrorAction Stop }
catch { Write-Host "    invalid key rejected" -ForegroundColor Green }
'@
try { @{ X = 1 } | fill -Bucket demo -Key "" -Quiet -ErrorAction Stop }
catch { Write-Host "    empty key rejected" -ForegroundColor Green }
try { @{ X = 1 } | fill -Bucket demo -Key ". ." -Quiet -ErrorAction Stop }
catch { Write-Host "    invalid key rejected" -ForegroundColor Green }
tut-pause
}

if ($Beg) {
# ---------- chapter 2: Read ----------

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  2. Read — spill / Get-BucketObject" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

Write-Host ""
Write-Host @"
  The counterpart to fill is spill (short for Get-BucketObject). With no arguments,
  it returns every object from every bucket — useful for getting the lay of the land.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill
'@
spill
tut-pause

Write-Host ""
Write-Host @"
  Most of the time you want objects from a specific bucket. Pass -Bucket to narrow
  the search to just one bucket.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users
'@
spill -Bucket users
tut-pause

Write-Host ""
Write-Host @"
  If you know the key, pass it positionally as the first argument. Keys are matched
  case-insensitively and as prefixes, so "alice" matches "Alice" too.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill "Alice" -Bucket users
'@
spill "Alice" -Bucket users
tut-pause

Write-Host ""
Write-Host @"
  For an exact match, just pass the full key name. Keys are still matched
  case-insensitively, so you don't need to worry about capitalization.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill "external-ref" -Bucket users
'@
spill "external-ref" -Bucket users
tut-pause

Write-Host ""
Write-Host @"
  Case doesn't matter. "alice" finds "Alice" because all key matching is
  case-insensitive. No more guessing about capitalization.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill "alice" -Bucket users
'@
spill "alice" -Bucket users
tut-pause

Write-Host ""
Write-Host @"
  What happens when there's no match? Buckets returns nothing with a warning —
  no crash, just a helpful nudge that nothing was found.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Key "NoOneHere"
'@
spill -Bucket users -Key "NoOneHere"
tut-pause

Write-Host ""
Write-Host @"
  You can use wildcards in bucket names too. "use*" matches any bucket starting
  with "use", making it easy to search groups of related buckets.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket "use*"
'@
spill -Bucket "use*"
tut-pause

Write-Host ""
Write-Host @"
  Pass multiple bucket names as an array. Buckets searches each one and combines
  the results into a single list.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket "users", "logs"
'@
spill -Bucket "users", "logs"
tut-pause

Write-Host ""
Write-Host @"
  Every object retrieved by Buckets carries metadata: _BucketName, _BucketKey, and
  _BucketFile. These tell you exactly where the object came from — useful for
  pipeline operations where context matters.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Key "Bob" | Select-Object _BucketName, _BucketKey, _BucketFile
'@
spill -Bucket users -Key "Bob" | Select-Object _BucketName, _BucketKey, _BucketFile
tut-pause

Write-Host ""
Write-Host @"
  Since spill returns regular PowerShell objects, you can pipe them into Select-Object,
  Sort-Object, Group-Object — anything you'd do with any other object in PowerShell.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users | Select-Object Name, Role, Score | Sort-Object Score -Descending
'@
spill -Bucket users | Select-Object Name, Role, Score | Sort-Object Score -Descending
tut-pause

Write-Host ""
Write-Host @"
  Access individual properties using standard dot notation. Store the result in a
  variable and work with it like any other PowerShell object.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$bob = spill -Bucket users -Key "Bob"
"  Name: $($bob.Name) | Role: $($bob.Role) | Score: $($bob.Score)"
'@
$bob = spill -Bucket users -Key "Bob"
"  Name: $($bob.Name) | Role: $($bob.Role) | Score: $($bob.Score)"
tut-pause
}

if ($Beg) {
# section 2a

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  2a. Read — filtering with -Match" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

Write-Host ""
Write-Host @"
  -Match is Buckets' built-in filter for exact equality. Pass a hashtable of property
  names and values, and Buckets returns only objects where every property matches
  exactly.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Match @{ Role = "admin" }
'@
spill -Bucket users -Match @{ Role = "admin" }
tut-pause

Write-Host ""
Write-Host @"
  Special case: matching against $null. If a property is $null on the object, or doesn't
  exist at all, it counts as a match for $null. Useful for finding objects with missing
  fields.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Match @{ Deleted = $null }
'@
spill -Bucket users -Match @{ Deleted = $null }
tut-pause

Write-Host ""
Write-Host @"
  You can match on multiple properties at once — think of it as AND logic. All conditions
  must be true for an object to be returned.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Match @{ Role = "user"; Score = 72 }
'@
spill -Bucket users -Match @{ Role = "user"; Score = 72 }
tut-pause

Write-Host ""
Write-Host @"
  Let's create some fresh data to demonstrate -Match with mixed types. Strings, numbers,
  and booleans all work as match criteria.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$data = @(
    @{ Name = "A"; Count = 5; Active = $true }
    @{ Name = "B"; Count = 10; Active = $false }
    @{ Name = "C"; Count = 5; Active = $true }
)
New-BucketObject -InputObject $data -Bucket match-demo -KeyProperty Name
spill -Bucket match-demo -Match @{ Count = 5; Active = $true }
'@
$data = @(
    @{ Name = "A"; Count = 5; Active = $true }
    @{ Name = "B"; Count = 10; Active = $false }
    @{ Name = "C"; Count = 5; Active = $true }
)
New-BucketObject -InputObject $data -Bucket match-demo -KeyProperty Name
spill -Bucket match-demo -Match @{ Count = 5; Active = $true }
tut-pause

Write-Host ""
Write-Host @"
  String matching with -Match is exact and case-insensitive. "red" matches "red" but
  also "Red", "RED", and so on.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$items = @(
    @{ Name = "alpha"; Color = "red" }
    @{ Name = "beta"; Color = "blue" }
    @{ Name = "gamma"; Color = "red" }
)
$items | fill -Bucket match-demo -KeyProperty Name
spill -Bucket match-demo -Match @{ Color = "red" }
'@
$items = @(
    @{ Name = "alpha"; Color = "red" }
    @{ Name = "beta"; Color = "blue" }
    @{ Name = "gamma"; Color = "red" }
)
$items | fill -Bucket match-demo -KeyProperty Name
spill -Bucket match-demo -Match @{ Color = "red" }
tut-pause

Write-Host ""
Write-Host @"
  -Match only looks at top-level properties. If you need to drill into nested data like
  $_.Settings.Enabled, you'll need -Filter instead.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$data = @{ Id = "a"; Meta = @{ Name = "inner" } }
$data | fill -Bucket nested-match -KeyProperty Id
spill -Bucket nested-match -Match @{ Meta = $null }
'@
$data = @{ Id = "a"; Meta = @{ Name = "inner" } }
$data | fill -Bucket nested-match -KeyProperty Id
spill -Bucket nested-match -Match @{ Meta = $null }
tut-pause
}

if ($Beg) {
# section 2b

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  2b. Read — comparison with -Filter" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

Write-Host ""
Write-Host @"
  For anything beyond exact equality, reach for -Filter. It takes a scriptblock where
  $_ represents each object. You can use any PowerShell operator: -gt, -lt, -match,
  -like, -and, -or, and more.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Filter { $_.Score -gt 80 }
'@
spill -Bucket users -Filter { $_.Score -gt 80 }
tut-pause

Write-Host ""
Write-Host @"
  Less than or equal works the same way. Think of -Filter as writing a Where-Object
  clause that runs inside Buckets rather than in the pipeline.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Filter { $_.Score -le 70 }
'@
spill -Bucket users -Filter { $_.Score -le 70 }
tut-pause

Write-Host ""
Write-Host @"
  Pattern matching with -match uses regular expressions. Here we find names starting
  with A or D using the regex "^[AD]".
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Filter { $_.Name -match "^[AD]" }
'@
spill -Bucket users -Filter { $_.Name -match "^[AD]" }
tut-pause

Write-Host ""
Write-Host @"
  The -like operator uses wildcard patterns. "*o*" matches any name containing the
  letter "o" anywhere in the string.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Filter { $_.Name -like "*o*" }
'@
spill -Bucket users -Filter { $_.Name -like "*o*" }
tut-pause

Write-Host ""
Write-Host @"
  Combine conditions with -and. Both must be true: score above 70 AND role is "user".
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Filter { $_.Score -gt 70 -and $_.Role -eq "user" }
'@
spill -Bucket users -Filter { $_.Score -gt 70 -and $_.Role -eq "user" }
tut-pause

Write-Host ""
Write-Host @"
  Combine conditions with -or. Either can be true: role is "admin" OR score above 80.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Filter { $_.Role -eq "admin" -or $_.Score -gt 80 }
'@
spill -Bucket users -Filter { $_.Role -eq "admin" -or $_.Score -gt 80 }
tut-pause

Write-Host ""
Write-Host @"
  String length checks work because you're writing real PowerShell expressions. Here
  we find objects where the Value property is longer than 5 characters.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$items = @(
    @{ Name = "short"; Value = "abc" }
    @{ Name = "long";  Value = "abcdefghijk" }
)
$items | fill -Bucket str-test -KeyProperty Name
spill -Bucket str-test -Filter { $_.Value.Length -gt 5 }
'@
$items = @(
    @{ Name = "short"; Value = "abc" }
    @{ Name = "long";  Value = "abcdefghijk" }
)
$items | fill -Bucket str-test -KeyProperty Name
spill -Bucket str-test -Filter { $_.Value.Length -gt 5 }
tut-pause

Write-Host ""
Write-Host @"
  Date comparisons too — no special syntax needed. Compare DateTime properties with
  -gt, -lt, or any other operator, just like you would in regular PowerShell.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$events = @(
    @{ Id = "old"; Stamp = (Get-Date).AddDays(-10) }
    @{ Id = "new"; Stamp = Get-Date }
)
$events | fill -Bucket date-test -KeyProperty Id
$cutoff = (Get-Date).AddDays(-5)
spill -Bucket date-test -Filter { $_.Stamp -gt $cutoff }
'@
$events = @(
    @{ Id = "old"; Stamp = (Get-Date).AddDays(-10) }
    @{ Id = "new"; Stamp = Get-Date }
)
$events | fill -Bucket date-test -KeyProperty Id
$cutoff = (Get-Date).AddDays(-5)
spill -Bucket date-test -Filter { $_.Stamp -gt $cutoff }
tut-pause

Write-Host ""
Write-Host @"
  Nested properties are accessible via standard dot notation inside the scriptblock.
  $_.Settings.Enabled drills into the Settings hashtable to check the Enabled flag.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$items = @(
    @{ Id = "x"; Settings = @{ Enabled = $true; Level = 5 } }
    @{ Id = "y"; Settings = @{ Enabled = $false; Level = 3 } }
)
$items | fill -Bucket nested-filter -KeyProperty Id
spill -Bucket nested-filter -Filter { $_.Settings.Enabled -eq $true }
'@
$items = @(
    @{ Id = "x"; Settings = @{ Enabled = $true; Level = 5 } }
    @{ Id = "y"; Settings = @{ Enabled = $false; Level = 3 } }
)
$items | fill -Bucket nested-filter -KeyProperty Id
spill -Bucket nested-filter -Filter { $_.Settings.Enabled -eq $true }
tut-pause

Write-Host ""
Write-Host @"
  Omitting -Bucket makes -Filter run against all buckets at once. This is a cross-bucket
  query — useful for finding objects anywhere in your data.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Filter { $_.Score -gt 80 }
'@
spill -Filter { $_.Score -gt 80 }
tut-pause
}

if ($Beg) {
# section 2c

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  2c. Read — pagination with -First / -Skip" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

Write-Host ""
Write-Host @"
  Pagination is built right in. -First limits the number of results returned. Useful
  for previewing large datasets without loading everything.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -First 2
'@
spill -Bucket users -First 2
tut-pause

Write-Host ""
Write-Host @"
  Combine -Skip with -First to jump ahead. -Skip 1 -First 2 skips the first result and
  returns the next two — a classic paging pattern.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Skip 1 -First 2
'@
spill -Bucket users -Skip 1 -First 2
tut-pause

Write-Host ""
Write-Host @"
  -First and -Skip work together with -Filter too. Here we filter for scores above 60,
  then take only the first 3 results.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Filter { $_.Score -gt 60 } -First 3
'@
spill -Bucket users -Filter { $_.Score -gt 60 } -First 3
tut-pause
}

if ($Beg) {
# ---------- chapter 3: Update ----------

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  3. Update — Set-BucketObject" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

Write-Host ""
Write-Host @"
  Set-BucketObject updates an existing object in place. When piped from spill, it
  auto-detects the bucket and key from the _BucketName and _BucketKey metadata —
  no need to specify them again.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Key "Bob" | ForEach-Object {
    $_.Score = 99
    $_.Role = "admin"
    $_
} | Set-BucketObject -Quiet
'@
spill -Bucket users -Key "Bob" | ForEach-Object {
    $_.Score = 99
    $_.Role = "admin"
    $_
} | Set-BucketObject -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Without pipeline metadata, specify -Bucket and -Key explicitly. Pass the modified
  object through -InputObject.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$obj = spill -Bucket users -Key "Carol"
$obj.Score = 100
Set-BucketObject -Bucket users -Key "Carol" -InputObject $obj -Quiet
'@
$obj = spill -Bucket users -Key "Carol"
$obj.Score = 100
Set-BucketObject -Bucket users -Key "Carol" -InputObject $obj -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Need to update just one field? Pipe a hashtable with only the properties you want
  to change. Buckets merges it with the existing object — partial updates work
  seamlessly.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$patch = @{ Email = "alice@new.com" }
$patch | Set-BucketObject -Bucket users -Key "Alice" -Quiet
'@
$patch = @{ Email = "alice@new.com" }
$patch | Set-BucketObject -Bucket users -Key "Alice" -Quiet
tut-pause

Write-Host ""
Write-Host @"
  New properties are automatically added. If the property doesn't exist on the
  original object, it gets appended without affecting existing fields.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$patch = @{ Phone = "555-0100" }
$patch | Set-BucketObject -Bucket users -Key "Alice" -Quiet
'@
$patch = @{ Phone = "555-0100" }
$patch | Set-BucketObject -Bucket users -Key "Alice" -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Properties you don't mention in the update stay untouched. Only the keys in your
  patch hashtable are modified.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$patch = @{ City = "Portland" }
$patch | Set-BucketObject -Bucket users -Key "Alice" -Quiet
'@
$patch = @{ City = "Portland" }
$patch | Set-BucketObject -Bucket users -Key "Alice" -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Format preservation: JSON objects stay as .json, binary objects stay as .dat.
  Set-BucketObject always writes back in the original format.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$patch = @{ UpdatedAt = Get-Date; Host = "prod-server" }
$patch | Set-BucketObject -Bucket config -Key "app-config" -Quiet
'@
$patch = @{ UpdatedAt = Get-Date; Host = "prod-server" }
$patch | Set-BucketObject -Bucket config -Key "app-config" -Quiet
tut-pause

Write-Host ""
Write-Host @"
  What happens if you pipe to Set-BucketObject without metadata AND without explicit
  -Bucket/-Key? It throws — it has no idea where to save.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
try { @{ X = 1 } | Set-BucketObject -Quiet -ErrorAction Stop }
catch { Write-Host "    Error: -Bucket and -Key required" -ForegroundColor Green }
'@
try { @{ X = 1 } | Set-BucketObject -Quiet -ErrorAction Stop }
catch { Write-Host "    Error: -Bucket and -Key required" -ForegroundColor Green }
tut-pause
}

if ($Beg) {
# ---------- chapter 4: Delete ----------

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  4. Delete — Remove-BucketObject" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

Write-Host ""
Write-Host @"
  -WhatIf previews what would be deleted without actually removing anything. Always
  safe to try before you delete.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-BucketObject -Bucket users -Key "external-ref" -WhatIf
'@
Remove-BucketObject -Bucket users -Key "external-ref" -WhatIf
tut-pause

Write-Host ""
Write-Host @"
  Delete by key is straightforward. Pass the key of the object you want to remove.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-BucketObject -Bucket users -Key "external-ref" -Quiet
'@
Remove-BucketObject -Bucket users -Key "external-ref" -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Trying to delete a non-existent key issues a warning but doesn't throw an error.
  Buckets is forgiving about missing objects.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-BucketObject -Bucket users -Key "no-one-here" -WarningVariable w -WarningAction SilentlyContinue 2>$null
'@
Remove-BucketObject -Bucket users -Key "no-one-here" -WarningVariable w -WarningAction SilentlyContinue 2>$null
tut-pause

Write-Host ""
Write-Host @"
  You must specify either -Key, -All, or a filter. Without one of these, the parameter
  set validation rejects the command.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-BucketObject -Bucket users -ErrorAction SilentlyContinue
'@
Remove-BucketObject -Bucket users -ErrorAction SilentlyContinue
tut-pause

Write-Host ""
Write-Host @"
  -Match works with deletion too. Delete all objects matching certain criteria in
  one command.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$data = @(
    @{ Id = "t1"; Status = "stale" }
    @{ Id = "t2"; Status = "stale" }
    @{ Id = "t3"; Status = "active" }
)
New-BucketObject -InputObject $data -Bucket temp -KeyProperty Id -Quiet
Remove-BucketObject -Bucket temp -Match @{ Status = "stale" } -Quiet
'@
$data = @(
    @{ Id = "t1"; Status = "stale" }
    @{ Id = "t2"; Status = "stale" }
    @{ Id = "t3"; Status = "active" }
)
New-BucketObject -InputObject $data -Bucket temp -KeyProperty Id -Quiet
Remove-BucketObject -Bucket temp -Match @{ Status = "stale" } -Quiet
tut-pause

Write-Host ""
Write-Host @"
  -Filter works the same way — delete objects that pass the scriptblock condition.
  Here, any object with Score below 50 gets removed.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$scores = @(
    @{ Name = "low1"; Score = 30 }
    @{ Name = "low2"; Score = 45 }
    @{ Name = "high1"; Score = 92 }
)
$scores | fill -Bucket scores -KeyProperty Name -Quiet
Remove-BucketObject -Bucket scores -Filter { $_.Score -lt 50 } -Quiet
'@
$scores = @(
    @{ Name = "low1"; Score = 30 }
    @{ Name = "low2"; Score = 45 }
    @{ Name = "high1"; Score = 92 }
)
$scores | fill -Bucket scores -KeyProperty Name -Quiet
Remove-BucketObject -Bucket scores -Filter { $_.Score -lt 50 } -Quiet
tut-pause

Write-Host ""
Write-Host @"
  -All deletes every object in the bucket. A clean slate.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$data = @(
    @{ Id = "a"; Data = "x" }
    @{ Id = "b"; Data = "y" }
    @{ Id = "c"; Data = "z" }
)
$data | fill -Bucket all-test -KeyProperty Id -Quiet
Remove-BucketObject -Bucket all-test -All -Quiet
'@
$data = @(
    @{ Id = "a"; Data = "x" }
    @{ Id = "b"; Data = "y" }
    @{ Id = "c"; Data = "z" }
)
$data | fill -Bucket all-test -KeyProperty Id -Quiet
Remove-BucketObject -Bucket all-test -All -Quiet
tut-pause

Write-Host ""
Write-Host @"
  -PassThru returns metadata about what was deleted. Useful for logging, auditing,
  or confirmation messages.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ Data = "gone" }
$tmp | fill -Bucket temp -Key "bye-bye" -Quiet
Remove-BucketObject -Bucket temp -Key "bye-bye" -PassThru -Quiet
'@
$tmp = @{ Data = "gone" }
$tmp | fill -Bucket temp -Key "bye-bye" -Quiet
Remove-BucketObject -Bucket temp -Key "bye-bye" -PassThru -Quiet
tut-pause
}

if ($Adv) {
# ---------- chapter 5: Copy, Rename, Move ----------

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  5. Object Operations — Copy, Rename, Move" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

Write-Host ""
Write-Host @"
  Copy an object within the same bucket but with a different key. The original stays
  untouched — this is a true copy, not a move.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Copy-BucketObject -Bucket users -Key "Alice" -DestinationKey "Alice-Backup" -Quiet
Remove-BucketObject -Bucket users -Key "Alice-Backup" -Quiet
'@
Copy-BucketObject -Bucket users -Key "Alice" -DestinationKey "Alice-Backup" -Quiet
Remove-BucketObject -Bucket users -Key "Alice-Backup" -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Copy across buckets too. Specify -DestinationBucket to copy to a different bucket.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Copy-BucketObject -Bucket users -Key "Alice" -DestinationBucket archive -Quiet
Remove-BucketObject -Bucket archive -Key "Alice" -Quiet
'@
Copy-BucketObject -Bucket users -Key "Alice" -DestinationBucket archive -Quiet
Remove-BucketObject -Bucket archive -Key "Alice" -Quiet
tut-pause

Write-Host ""
Write-Host @"
  -PassThru on Copy-BucketObject returns metadata about the destination: source,
  destination, and new key — useful for pipeline logging.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Copy-BucketObject -Bucket users -Key "Alice" -DestinationKey "Alice-pass" -PassThru -Quiet
Remove-BucketObject -Bucket users -Key "Alice-pass" -Quiet
'@
Copy-BucketObject -Bucket users -Key "Alice" -DestinationKey "Alice-pass" -PassThru -Quiet
Remove-BucketObject -Bucket users -Key "Alice-pass" -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Rename changes the key of an existing object in place. The format (.dat or .json)
  is preserved through the rename.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ Data = "rename me" }
$tmp | fill -Bucket tmp -Key "old-name" -Quiet
Rename-BucketObject -Bucket tmp -Key "old-name" -NewKey "new-name" -Quiet
'@
$tmp = @{ Data = "rename me" }
$tmp | fill -Bucket tmp -Key "old-name" -Quiet
Rename-BucketObject -Bucket tmp -Key "old-name" -NewKey "new-name" -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Renaming a JSON object preserves the .json extension too. Format is always
  maintained — you never have to worry about it.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ Format = "json" }
$tmp | fill -Bucket tmp-json -Key "json-old" -AsJson -Quiet
Rename-BucketObject -Bucket tmp-json -Key "json-old" -NewKey "json-new" -PassThru -Quiet
'@
$tmp = @{ Format = "json" }
$tmp | fill -Bucket tmp-json -Key "json-old" -AsJson -Quiet
Rename-BucketObject -Bucket tmp-json -Key "json-old" -NewKey "json-new" -PassThru -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Move combines copy + delete in one operation. The object is copied to the
  destination and removed from the source.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$data = @(
    @{ Id = "obj1"; Value = "move me" }
)
$data | fill -Bucket source -KeyProperty Id -Quiet
Move-BucketObject -Bucket source -Key "obj1" -DestinationBucket dest -Quiet
'@
$data = @(
    @{ Id = "obj1"; Value = "move me" }
)
$data | fill -Bucket source -KeyProperty Id -Quiet
Move-BucketObject -Bucket source -Key "obj1" -DestinationBucket dest -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Move with rename: specify a different key in the target bucket to rename
  as part of the move.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ Data = "moved+renamed" }
$tmp | fill -Bucket origin -Key "orig-key" -Quiet
Move-BucketObject -Bucket origin -Key "orig-key" -DestinationBucket final -DestinationKey "new-key" -Quiet
'@
$tmp = @{ Data = "moved+renamed" }
$tmp | fill -Bucket origin -Key "orig-key" -Quiet
Move-BucketObject -Bucket origin -Key "orig-key" -DestinationBucket final -DestinationKey "new-key" -Quiet
tut-pause

Write-Host ""
Write-Host @"
  -PassThru on Move returns metadata about both the source and destination
  objects.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ X = 1 }
$tmp | fill -Bucket move-src -Key "m-pass" -Quiet
Move-BucketObject -Bucket move-src -Key "m-pass" -DestinationBucket move-dst -PassThru -Quiet
'@
$tmp = @{ X = 1 }
$tmp | fill -Bucket move-src -Key "m-pass" -Quiet
Move-BucketObject -Bucket move-src -Key "m-pass" -DestinationBucket move-dst -PassThru -Quiet
tut-pause

Write-Host ""
Write-Host @"
  All three operations — Copy, Rename, Move — support -PassThru. Chain them
  together for auditable object management.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ X = 1 }
$tmp | fill -Bucket pass -Key "src-key" -Quiet
Copy-BucketObject -Bucket pass -Key "src-key" -DestinationKey "cp-key" -PassThru -Quiet
Rename-BucketObject -Bucket pass -Key "cp-key" -NewKey "rn-key" -PassThru -Quiet
Move-BucketObject -Bucket pass -Key "src-key" -DestinationBucket pass -DestinationKey "mv-key" -PassThru -Quiet
'@
$tmp = @{ X = 1 }
$tmp | fill -Bucket pass -Key "src-key" -Quiet
Copy-BucketObject -Bucket pass -Key "src-key" -DestinationKey "cp-key" -PassThru -Quiet
Rename-BucketObject -Bucket pass -Key "cp-key" -NewKey "rn-key" -PassThru -Quiet
Move-BucketObject -Bucket pass -Key "src-key" -DestinationBucket pass -DestinationKey "mv-key" -PassThru -Quiet
tut-pause
}

if ($Adv) {
# ---------- chapter 6: Bucket Management ----------

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  6. Bucket Management — dip / Get-Bucket" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

Write-Host ""
Write-Host @"
  dip (short for Get-Bucket) lists all your buckets with their object counts and
  timestamps. It's the first command to run when you want an overview.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
dip
'@
dip
tut-pause

Write-Host ""
Write-Host @"
  Filter buckets by name with a substring match. "user" matches "users" and any
  other bucket with "user" in the name.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
dip "user"
'@
dip "user"
tut-pause

Write-Host ""
Write-Host @"
  Get-BucketStats shows detailed statistics: object count, total size on disk, and
  creation/modification timestamps for a specific bucket.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-BucketStats -Bucket users
'@
Get-BucketStats -Bucket users
tut-pause

Write-Host ""
Write-Host @"
  Get-BucketKeys lists every key in a bucket along with its format (.dat or .json)
  and file size. Useful for inventorying what's stored.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-BucketKeys -Bucket users
'@
Get-BucketKeys -Bucket users
tut-pause

Write-Host ""
Write-Host @"
  Filter keys by pattern with -Match. "A*" matches all keys starting with "A".
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-BucketKeys -Bucket users -Match "A*"
'@
Get-BucketKeys -Bucket users -Match "A*"
tut-pause

Write-Host ""
Write-Host @"
  Get-BucketKeys across all buckets with the wildcard "*" — a complete inventory
  of every object stored.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-BucketKeys -Bucket "*"
'@
Get-BucketKeys -Bucket "*"
tut-pause

Write-Host ""
Write-Host @"
  The -Tree parameter renders your buckets as a visual directory tree. -MaxFiles
  limits how many objects are shown per bucket.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-Bucket -Tree -MaxFiles 10
'@
Get-Bucket -Tree -MaxFiles 10
tut-pause

Write-Host ""
Write-Host @"
  Without -Objects, the tree shows buckets only — a clean structural view without
  individual objects cluttering the output.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-Bucket -Tree
'@
Get-Bucket -Tree
tut-pause

Write-Host ""
Write-Host @"
  Add -Objects to include individual objects in the tree. Every leaf object is
  visible.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-Bucket -Tree -Objects
'@
Get-Bucket -Tree -Objects
tut-pause

Write-Host ""
Write-Host @"
  The -Raw switch returns tree objects as pipeable data instead of formatted text.
  Useful for further processing or custom display.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-Bucket -Tree -Raw | Select-Object -First 2
'@
Get-Bucket -Tree -Raw | Select-Object -First 2
tut-pause

Write-Host ""
Write-Host @"
  -Depth limits how many levels of nesting the tree traverses. Depth 1 shows
  only top-level buckets.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-Bucket -Tree -Depth 1
'@
Get-Bucket -Tree -Depth 1
tut-pause

Write-Host ""
Write-Host @"
  Pipe Raw tree output to ConvertTo-Json for a structured JSON representation of
  your bucket hierarchy.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-Bucket -Tree -Raw | ConvertTo-Json -Depth 5 | Select-Object -First 5
'@
Get-Bucket -Tree -Raw | ConvertTo-Json -Depth 5 | Select-Object -First 5
tut-pause

Write-Host ""
Write-Host @"
  Select Name and ObjectCount from dip for a clean table of buckets with their
  object counts.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
dip | Select-Object Name, ObjectCount
'@
dip | Select-Object Name, ObjectCount
tut-pause
}

if ($Adv) {
# section 6a

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  6a. Remove-Bucket — safety and wildcards" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

Write-Host ""
Write-Host @"
  -WhatIf previews what would be removed without actually deleting anything.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-Bucket "users" -WhatIf
'@
Remove-Bucket "users" -WhatIf
tut-pause

Write-Host ""
Write-Host @"
  Wildcard patterns work too. Preview removing all buckets matching a pattern.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-Bucket "config" -WhatIf
'@
Remove-Bucket "config" -WhatIf
tut-pause

Write-Host ""
Write-Host @"
  Remove a single bucket. Make sure it contains only .dat/.json files — Buckets
  refuses to remove directories with other file types.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ A = 1 }
$tmp | fill -Bucket temp-remove -Key "x" -Quiet
Remove-Bucket temp-remove -Force -Confirm:$false
'@
$tmp = @{ A = 1 }
$tmp | fill -Bucket temp-remove -Key "x" -Quiet
Remove-Bucket temp-remove -Force -Confirm:$false
tut-pause

Write-Host ""
Write-Host @"
  Safety first: Remove-Bucket checks that a directory contains only bucket files.
  If it finds unexpected file types (like .exe), it skips the directory with a
  warning rather than deleting it.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$badDir = Join-Path (Get-BucketRoot) "not-a-bucket"
$null = New-Item -ItemType Directory -Path $badDir -Force
Set-Content -Path (Join-Path $badDir "evil.exe") -Value "x" -NoNewline
Remove-Bucket "not-a-bucket" -Force -Confirm:$false -WarningAction SilentlyContinue 2>$null
Remove-Item $badDir -Recurse -Force -ErrorAction SilentlyContinue
'@
$badDir = Join-Path (Get-BucketRoot) "not-a-bucket"
$null = New-Item -ItemType Directory -Path $badDir -Force
Set-Content -Path (Join-Path $badDir "evil.exe") -Value "x" -NoNewline
Remove-Bucket "not-a-bucket" -Force -Confirm:$false -WarningAction SilentlyContinue 2>$null
Remove-Item $badDir -Recurse -Force -ErrorAction SilentlyContinue
tut-pause
}

if ($Adv) {
# ---------- chapter 7: Export / Import ----------

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  7. Export / Import — Export-Bucket, Import-Bucket" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

$exportDir = Join-Path $env:TEMP "buckets-tutorial-export"
$null = New-Item -ItemType Directory -Path $exportDir -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host @"
  Export saves an entire bucket to an archive file. CLIXML (the default) preserves
  .NET type information for perfect round-trip fidelity.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Export-Bucket -Bucket users -OutputFile (Join-Path $exportDir "users.clixml") -Quiet
'@
Export-Bucket -Bucket users -OutputFile (Join-Path $exportDir "users.clixml") -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Export to JSON for human-readable archives. Same data, different format —
  useful when you need to inspect or share the data outside of PowerShell.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Export-Bucket -Bucket users -OutputFile (Join-Path $exportDir "users.json") -AsJson -Quiet
'@
Export-Bucket -Bucket users -OutputFile (Join-Path $exportDir "users.json") -AsJson -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Wildcards work for batch exports. Export multiple buckets that match a pattern
  into a single archive file.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Export-Bucket -Bucket "user*","config" -OutputFile (Join-Path $exportDir "multi-export.clixml") -Quiet
'@
Export-Bucket -Bucket "user*","config" -OutputFile (Join-Path $exportDir "multi-export.clixml") -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Import restores from a CLIXML archive into a new bucket. Objects are recreated
  with their original keys and data.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Import-Bucket -Bucket restored -InputFile (Join-Path $exportDir "users.clixml") -Quiet
'@
Import-Bucket -Bucket restored -InputFile (Join-Path $exportDir "users.clixml") -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Import from JSON works the same way. The JSON file is parsed and each object
  is stored in the specified bucket.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Import-Bucket -Bucket restored-json -InputFile (Join-Path $exportDir "users.json") -AsJson -Quiet
'@
Import-Bucket -Bucket restored-json -InputFile (Join-Path $exportDir "users.json") -AsJson -Quiet
tut-pause

Write-Host ""
Write-Host @"
  -Overwrite on import replaces existing keys instead of skipping them. With
  -Overwrite, a second import doesn't create duplicates.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Import-Bucket -Bucket import-over -InputFile (Join-Path $exportDir "users.clixml") -Quiet
Import-Bucket -Bucket import-over -InputFile (Join-Path $exportDir "users.clixml") -Overwrite -Quiet
'@
Import-Bucket -Bucket import-over -InputFile (Join-Path $exportDir "users.clixml") -Quiet
Import-Bucket -Bucket import-over -InputFile (Join-Path $exportDir "users.clixml") -Overwrite -Quiet
tut-pause

Write-Host ""
Write-Host @"
  JSON archives are plain text. Open them in any editor to inspect or modify
  before importing.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-Content (Join-Path $exportDir "users.json") -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 5 | Select-Object -First 3
'@
Get-Content (Join-Path $exportDir "users.json") -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 5 | Select-Object -First 3
tut-pause
}

Remove-Item $exportDir -Recurse -Force -ErrorAction SilentlyContinue

if ($Adv) {
# ---------- chapter 8: PSDrive ----------

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  8. PSDrive — navigate buckets like a filesystem" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

Write-Host ""
Write-Host @"
  Buckets registers a custom PSDrive called "buckets:". You can navigate it with
  cd, Get-ChildItem, Get-Content — just like any other drive.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-PSDrive -Name buckets
'@
Get-PSDrive -Name buckets
tut-pause

Write-Host ""
Write-Host @"
  List all buckets with Get-ChildItem on the drive root. Each bucket appears as
  a container (directory).
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-ChildItem "buckets:\"
'@
Get-ChildItem "buckets:\"
tut-pause

Write-Host ""
Write-Host @"
  Format the output with Select-Object for a cleaner table of bucket names,
  sizes, and timestamps.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-ChildItem "buckets:\" | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
'@
Get-ChildItem "buckets:\" | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
tut-pause

Write-Host ""
Write-Host @"
  Enter a bucket and list its objects. Each stored object appears as a file in
  the PSDrive.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-ChildItem "buckets:\users" | Select-Object Name, Length, LastWriteTime
'@
Get-ChildItem "buckets:\users" | Select-Object Name, Length, LastWriteTime
tut-pause

Write-Host ""
Write-Host @"
  Filter by PSIsContainer to see only buckets (containers) or only leaf objects.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-ChildItem "buckets:\" | Where-Object { $_.PSIsContainer }
'@
Get-ChildItem "buckets:\" | Where-Object { $_.PSIsContainer }
tut-pause

Write-Host ""
Write-Host @"
  Read an object with Get-Content (or cat). It deserializes the stored data back
  into a live PowerShell object — no manual parsing needed.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-Content "buckets:\users\Alice" | Select-Object Name, Role, Score
'@
Get-Content "buckets:\users\Alice" | Select-Object Name, Role, Score
tut-pause

Write-Host ""
Write-Host @"
  The full round-trip in the PSDrive: read with Get-Content, modify the property,
  write back with Set-Content. Works just like a file but with live objects.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$obj = Get-Content "buckets:\users\Carol"
$obj.Score = 95
$obj | Set-Content "buckets:\users\Carol"
'@
$obj = Get-Content "buckets:\users\Carol"
$obj.Score = 95
$obj | Set-Content "buckets:\users\Carol"
tut-pause

Write-Host ""
Write-Host @"
  Remove-Item works in the PSDrive too. Delete an object by its path.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Copy-BucketObject -Bucket users -Key "Alice" -DestinationKey "psdrive-remove-test" -Quiet
Remove-Item "buckets:\users\psdrive-remove-test" -Force
'@
Copy-BucketObject -Bucket users -Key "Alice" -DestinationKey "psdrive-remove-test" -Quiet
Remove-Item "buckets:\users\psdrive-remove-test" -Force
tut-pause

Write-Host ""
Write-Host @"
  Test-Path checks whether an object exists in the drive. Useful for conditional
  logic.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Test-Path "buckets:\users\Alice"
Test-Path "buckets:\users\NonExistent"
'@
Test-Path "buckets:\users\Alice"
Test-Path "buckets:\users\NonExistent"
tut-pause

Write-Host ""
Write-Host @"
  Copy-Item works across buckets in the PSDrive. Copy objects from one bucket
  to another using familiar filesystem commands.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Copy-Item "buckets:\users\Alice" "buckets:\users\Alice-pscopy" -Force
Remove-BucketObject -Bucket users -Key "Alice-pscopy" -Quiet
'@
Copy-Item "buckets:\users\Alice" "buckets:\users\Alice-pscopy" -Force
Remove-BucketObject -Bucket users -Key "Alice-pscopy" -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Tab completion works throughout the PSDrive. Try typing "buckets:\" and pressing
  Tab — it completes bucket names and object keys.
"@ -ForegroundColor White
tut-pause
}

if ($Adv) {
# ---------- chapter 9: Nested Buckets ----------

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  9. Nested Buckets — directory hierarchy" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

Write-Host ""
Write-Host @"
  Bucket names with forward slashes create nested directory structures on disk.
  This is how you organize data hierarchically — like folders within folders,
  each level a real subdirectory.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$deCities = @(
    @{ Name = "Berlin"; Population = 3600000; Country = "DE" }
    @{ Name = "Munich"; Population = 1500000; Country = "DE" }
)
New-BucketObject -InputObject $deCities -Bucket "org/eu/de/cities" -KeyProperty Name -Quiet

$ukCities = @(
    @{ Name = "London"; Population = 8900000; Country = "UK" }
    @{ Name = "Manchester"; Population = 550000; Country = "UK" }
)
$ukCities | fill -Bucket "org/eu/uk/cities" -KeyProperty Name -Quiet

$usCities = @(
    @{ Name = "New York"; Population = 8300000; Country = "US" }
)
$usCities | fill -Bucket "org/us/cities" -KeyProperty Name -Quiet

$deDepts = @(
    @{ Dept = "Engineering"; Lead = "Alice" }
    @{ Dept = "Marketing"; Lead = "Bob" }
)
$deDepts | fill -Bucket "org/eu/de/depts" -KeyProperty Dept -Quiet
'@
$deCities = @(
    @{ Name = "Berlin"; Population = 3600000; Country = "DE" }
    @{ Name = "Munich"; Population = 1500000; Country = "DE" }
)
New-BucketObject -InputObject $deCities -Bucket "org/eu/de/cities" -KeyProperty Name -Quiet

$ukCities = @(
    @{ Name = "London"; Population = 8900000; Country = "UK" }
    @{ Name = "Manchester"; Population = 550000; Country = "UK" }
)
$ukCities | fill -Bucket "org/eu/uk/cities" -KeyProperty Name -Quiet

$usCities = @(
    @{ Name = "New York"; Population = 8300000; Country = "US" }
)
$usCities | fill -Bucket "org/us/cities" -KeyProperty Name -Quiet

$deDepts = @(
    @{ Dept = "Engineering"; Lead = "Alice" }
    @{ Dept = "Marketing"; Lead = "Bob" }
)
$deDepts | fill -Bucket "org/eu/de/depts" -KeyProperty Dept -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Wildcards work in nested paths. "org/eu/*/cities" matches city buckets under
  any EU country — Germany, UK, and so on.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket "org/eu/*/cities"
'@
spill -Bucket "org/eu/*/cities"
tut-pause

Write-Host ""
Write-Host @"
  Query a nested path directly by its full bucket name. Same spill command,
  just a deeper path.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket "org/eu/de/cities"
'@
spill -Bucket "org/eu/de/cities"
tut-pause

Write-Host ""
Write-Host @"
  Wildcards at multiple levels for deep queries. "org/*/de/*" matches anything
  under any country's "de" sub-bucket.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket "org/*/de/*"
'@
spill -Bucket "org/*/de/*"
tut-pause

Write-Host ""
Write-Host @"
  Get-Bucket with -Recurse shows the full nested structure. It traverses all
  sub-buckets recursively.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-Bucket -Name "org" -Recurse
'@
Get-Bucket -Name "org" -Recurse
tut-pause

Write-Host ""
Write-Host @"
  Tree view visualizes the nesting hierarchy. Each level is indented, making
  it easy to see the organizational structure at a glance.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-Bucket -Name "org" -Tree -Objects -MaxFiles 10
'@
Get-Bucket -Name "org" -Tree -Objects -MaxFiles 10
tut-pause

Write-Host ""
Write-Host @"
  PSDrive supports nested paths too. Navigate into org/eu/de/cities with
  Get-ChildItem just like you would with a filesystem path.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-ChildItem "buckets:\org\eu\de\cities" | Select-Object Name
'@
Get-ChildItem "buckets:\org\eu\de\cities" | Select-Object Name
tut-pause

Write-Host ""
Write-Host @"
  Recursive listing in PSDrive with the -Recurse flag. Shows everything under
  the org tree.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-ChildItem "buckets:\org" -Recurse | Select-Object Name | Format-Table -AutoSize
'@
Get-ChildItem "buckets:\org" -Recurse | Select-Object Name | Format-Table -AutoSize
tut-pause

Write-Host ""
Write-Host @"
  Stats work on nested buckets too. Get-BucketStats handles the full path.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-BucketStats -Bucket "org/eu/de/cities"
'@
Get-BucketStats -Bucket "org/eu/de/cities"
tut-pause

Write-Host ""
Write-Host @"
  List keys in a nested bucket with Get-BucketKeys. Same command, just a
  deeper bucket path.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-BucketKeys -Bucket "org/eu/de/cities"
'@
Get-BucketKeys -Bucket "org/eu/de/cities"
tut-pause

Write-Host ""
Write-Host @"
  Combine wildcards with -Filter for cross-bucket queries in nested hierarchies.
  Find all cities with population over 2 million across any country.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket "org/*/cities" -Filter { $_.Population -gt 2000000 }
'@
spill -Bucket "org/*/cities" -Filter { $_.Population -gt 2000000 }
tut-pause

Write-Host ""
Write-Host @"
  Remove-Bucket with -Recurse deletes an entire nested tree. A single command
  removes org and everything under it.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-Bucket "org" -Recurse -Force -Confirm:$false
'@
Remove-Bucket "org" -Recurse -Force -Confirm:$false
tut-pause
}

if ($Adv) {
# ---------- chapter 10: Pipeline & Sleek Patterns ----------

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  10. Sleek Pipeline Patterns" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

Write-Host ""
Write-Host @"
  Buckets is designed for pipeline-first usage. Most cmdlets accept pipeline
  input and emit objects with metadata. Here's how to chain them together.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
1..5 | ForEach-Object { @{ Name = "item-$_"; Value = $_ * 10 } } |
    fill -Bucket "dir-listing" -KeyProperty Name -Quiet
'@
1..5 | ForEach-Object { @{ Name = "item-$_"; Value = $_ * 10 } } |
    fill -Bucket "dir-listing" -KeyProperty Name -Quiet
tut-pause

Write-Host ""
Write-Host @"
  Chain multiple operations in one pipeline: filter objects with -Filter, modify
  them with ForEach-Object, and save back with Set-BucketObject. All in one flow.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Filter { $_.Role -eq "user" } |
    ForEach-Object { $_.Score = $_.Score + 5; $_ } |
    Set-BucketObject -PassThru
'@
spill -Bucket users -Filter { $_.Role -eq "user" } |
    ForEach-Object { $_.Score = $_.Score + 5; $_ } |
    Set-BucketObject -PassThru
tut-pause

Write-Host ""
Write-Host @"
  Filter, sort, and project in one pipeline. Where-Object filters, Sort-Object
  orders, Select-Object picks the properties you want.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users | Where-Object { $_.Score -gt 70 } |
    Sort-Object Score -Descending |
    Select-Object Name, Role, Score
'@
spill -Bucket users | Where-Object { $_.Score -gt 70 } |
    Sort-Object Score -Descending |
    Select-Object Name, Role, Score
tut-pause

Write-Host ""
Write-Host @"
  Cross-bucket query: iterate over multiple buckets and filter each one, then
  project the results with bucket metadata included.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$buckets = @("users", "config", "demo")
$buckets | ForEach-Object { spill -Bucket $_ -Filter { $_.Score -gt 80 } } |
    Select-Object _BucketName, Name, Score
'@
$buckets = @("users", "config", "demo")
$buckets | ForEach-Object { spill -Bucket $_ -Filter { $_.Score -gt 80 } } |
    Select-Object _BucketName, Name, Score
tut-pause

Write-Host ""
Write-Host @"
  Group by bucket name to see how objects are distributed across your buckets.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill | Group-Object _BucketName | Select-Object Name, Count
'@
spill | Group-Object _BucketName | Select-Object Name, Count
tut-pause

Write-Host ""
Write-Host @"
  Group-Object aggregates data within a bucket. Here we count how many users
  have each role.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users | Group-Object Role | Select-Object Name, Count
'@
spill -Bucket users | Group-Object Role | Select-Object Name, Count
tut-pause

Write-Host ""
Write-Host @"
  Measure-Object gives you statistics — average, minimum, maximum — for any
  numeric property across your objects.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$scores = spill -Bucket users | Measure-Object Score -Average -Minimum -Maximum
Write-Host "    Score stats: avg=$([math]::Round($scores.Average,1)) min=$($scores.Minimum) max=$($scores.Maximum)"
'@
$scores = spill -Bucket users | Measure-Object Score -Average -Minimum -Maximum
Write-Host "    Score stats: avg=$([math]::Round($scores.Average,1)) min=$($scores.Minimum) max=$($scores.Maximum)"
tut-pause

Write-Host ""
Write-Host @"
  Export spilled data to CSV for use in Excel, Python, or any tool that reads
  tabular data.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$csvPath = Join-Path $env:TEMP "buckets-users.csv"
spill -Bucket users | Select-Object Name, Role, Score | Export-Csv -Path $csvPath -NoTypeInformation
Remove-Item $csvPath -Force -ErrorAction SilentlyContinue
'@
$csvPath = Join-Path $env:TEMP "buckets-users.csv"
spill -Bucket users | Select-Object Name, Role, Score | Export-Csv -Path $csvPath -NoTypeInformation
Remove-Item $csvPath -Force -ErrorAction SilentlyContinue
tut-pause

Write-Host ""
Write-Host @"
  -Filter runs inside Buckets (faster), Where-Object runs in the pipeline (more
  flexible). Both produce the same result — choose based on your needs.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Filter { $_.Score -gt 80 }
spill -Bucket users | Where-Object { $_.Score -gt 80 }
'@
spill -Bucket users -Filter { $_.Score -gt 80 }
spill -Bucket users | Where-Object { $_.Score -gt 80 }
tut-pause

Write-Host ""
Write-Host @"
  Custom formatting with ForEach-Object. Transform each object into a formatted
  string for display or logging.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users | ForEach-Object {
    "[$($_.Role)] $($_.Name) — Score: $($_.Score)"
}
'@
spill -Bucket users | ForEach-Object {
    "[$($_.Role)] $($_.Name) — Score: $($_.Score)"
}
tut-pause

Write-Host ""
Write-Host @"
  Conditional pipeline: filter first, then convert only matching objects to JSON.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
spill -Bucket users -Filter { $_.Score -gt 80 } | ConvertTo-Json -Depth 5
'@
spill -Bucket users -Filter { $_.Score -gt 80 } | ConvertTo-Json -Depth 5
tut-pause

Write-Host ""
Write-Host @"
  Save then immediately read to verify round-trip integrity. What you write is
  exactly what you get back.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ Id = "smoke"; Value = 42 }
$tmp | fill -Bucket smoke-test -KeyProperty Id -Quiet
'@
$tmp = @{ Id = "smoke"; Value = 42 }
$tmp | fill -Bucket smoke-test -KeyProperty Id -Quiet
tut-pause
}

if ($Adv) {
# ---------- chapter 11: Aliases Quick Reference ----------

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  11. Aliases & Shortcuts Reference" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

Write-Host ""

Write-Host "  Three aliases are exported by the module:" -ForegroundColor DarkGray
Write-Host @"

    fill   = New-BucketObject     — save objects
    spill  = Get-BucketObject     — retrieve objects
    dip    = Get-Bucket            — list buckets

"@ -ForegroundColor Yellow

Write-Host "  Additional shortcuts:" -ForegroundColor DarkGray
Write-Host @"
    ls     = Get-ChildItem         — overridden globally (used in buckets: drive)
    cat    = Get-Content           — built-in, works with buckets: drive

"@ -ForegroundColor Yellow

Write-Host "  Pipeline parameter binding via metadata:" -ForegroundColor DarkGray
Write-Host @"
    _BucketName   → -Bucket   (on Set-BucketObject)
    _BucketKey    → -Key      (on Set-BucketObject)
    _BucketFile   → full path to the stored file

"@ -ForegroundColor White
tut-pause
}

# ---------- cleanup ----------

cls
Write-Host "`n  $Sep" -ForegroundColor DarkGray
Write-Host "  Cleanup — Remove tutorial data" -ForegroundColor Blue
Write-Host "  $Sep" -ForegroundColor DarkGray

$confirm = Read-Host "`n  Remove all tutorial buckets? (Y/n)"
if ($confirm -ne "n") {
    Get-ChildItem (Get-BucketRoot) -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  OK Cleanup complete" -ForegroundColor Green
} else {
    Write-Host "  [Data kept for inspection]" -ForegroundColor DarkGray
}

Write-Host @"

  $('##')  Tutorial Complete!  $('##')

  What you learned:
    fill / spill / dip          — save, read, list
    -Key / -KeyProperty         — naming objects
    -Overwrite / -AsTimestamp    — replacement and timestamp keys
    -AsJson / -Compress          — storage formats
    -Match (exact)              — hashtable-based filtering
    -Filter (scriptblock)       — expression-based comparison (-gt, -like, -contains, -match)
    Nested property filtering   — `$_.Settings.Enabled with -Filter
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
    Edge cases                   — `$null values, special chars, empty keys, safety guards
    Format preservation          — JSON stays .json, binary stays .dat through Rename/Copy

  Learn more: Get-Help <cmdlet> -Full
  See also:   README.md, .tests/demo/*.ps1

"@ -ForegroundColor Cyan

Write-Host "  Happy Bucketing!`n" -ForegroundColor Green
