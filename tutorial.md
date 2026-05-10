# Buckets Tutorial


## 0. Introduction
---

### 0.1 What is Buckets?
---

Buckets is a PowerShell module for file-based PSObject storage.
Every object is a file, every bucket is a folder. There is no
database, no daemon, no config file — just the filesystem.

Two storage formats:
  Binary (.dat) — via PSSerializer. Fast, preserves full .NET type
                  information. Handles complex objects, circular refs.
  JSON    (.json) — via -AsJson. Human-readable, portable, editable
                  in any text editor.

### 0.2 Why Buckets?
---

Persistent       — objects outlive your PowerShell session
Shareable        — buckets are folders on disk; copy, sync, commit
Composable       — pipeline in, pipeline out; just pipe and go
Browsable        — Get-Bucket -Tree shows the full hierarchy
Self-describing  — filenames are keys, JSON files are readable
Expand/Collapse  — nested structures into browsable directory trees
Cross-platform   — PowerShell 7+ on Windows, macOS, Linux

### 0.3 How does it work?
---

Every bucket is a directory under a root path. The default root is:


```powershell
Get-BucketRoot
```



Each object is one file — .dat (binary, default) or .json (opt-in).
The filename (minus extension) is the object's key.

Current buckets:
.buckets (371 items, 56 KB)
└── logs (371 items, 56 KB)
  ├── eventlog (101 items, 16 KB)
  │   ├── Application (30 items, 5 KB)
  │   │   ├── 2026.05.08 (10 items, 2 KB)
  │   │   ├── 2026.05.09 (10 items, 2 KB)
  │   │   └── 2026.05.10 (10 items, 2 KB)
  │   ├── Security (24 items, 4 KB)
  │   │   ├── 2026.05.08 (8 items, 1 KB)
  │   │   ├── 2026.05.09 (8 items, 1 KB)
  │   │   └── 2026.05.10 (8 items, 1 KB)
  │   └── System (47 items, 8 KB)
  │       ├── 2026.05.08 (15 items, 2 KB)
  │       ├── 2026.05.09 (15 items, 2 KB)
  │       └── 2026.05.10 (17 items, 4 KB)
  └── syslog (270 items, 40 KB)
      ├── db01 (30 items, 4 KB)
      │   ├── 2026.05.08 (10 items, 1 KB)
      │   ├── 2026.05.09 (10 items, 1 KB)
      │   └── 2026.05.10 (10 items, 1 KB)
      ├── lb01 (60 items, 9 KB)
      │   ├── 2026.05.08 (20 items, 3 KB)
      │   ├── 2026.05.09 (20 items, 3 KB)
      │   └── 2026.05.10 (20 items, 3 KB)
      ├── web01 (120 items, 18 KB)
      │   ├── 2026.05.08 (40 items, 6 KB)
      │   ├── 2026.05.09 (40 items, 6 KB)
      │   └── 2026.05.10 (40 items, 6 KB)
      └── web02 (60 items, 9 KB)
          ├── 2026.05.08 (20 items, 3 KB)
          ├── 2026.05.09 (20 items, 3 KB)
          └── 2026.05.10 (20 items, 3 KB)
  (no buckets yet)

The six core cmdlets:

  fill   · New-BucketObject      write objects
  spill  · Get-BucketObject      read objects
  dip    · Get-Bucket            list buckets
  drain  · Remove-BucketObject   delete an object
  toss   · Remove-Bucket         delete a bucket

Defaults: Binary depth 5, JSON depth 20, path C:\Users\berfelde/.buckets
Override any of them with -BinaryDepth, -Depth, or -Path.

## 1. Create
---

### 1.1 Saving your first object
---

Let's save your first object — a simple hashtable describing a user. We give it
an explicit key "Alice" with -Key, which becomes its key. By default,
Buckets uses a binary format that preserves the full .NET type information, so
hashtables, custom objects, even FileInfo — all survive the round trip.


```powershell
$alice = @{ Name = "Alice"; Role = "admin"; Score = 95 }
New-BucketObject -InputObject $alice -Bucket users -Key "Alice"
```

users · 1 objects

### 1.2 Using -KeyProperty for automatic naming
---

Typing -Key for every object gets tedious. Instead, -KeyProperty tells Buckets to
look at a specific property on your object and use its value as the key. Here, the
property Name contains "Bob", so the key will be "Bob" automatically.


```powershell
$bob = @{ Name = "Bob"; Role = "user"; Score = 72 }
$bob | fill -Bucket users -KeyProperty Name
```

users · 1 objects

### 1.3 Piping multiple objects
---

One of Buckets' superpowers: piping multiple objects at once. Send them one by one
through the pipeline and Buckets saves each one. Mix -KeyProperty with pipeline
input for batch inserts — it's the fastest way to load data.


```powershell
$users = @(
  @{ Name = "Carol"; Role = "manager"; Score = 88 }
  @{ Name = "Dave"; Role = "user"; Score = 61 }
)
$users | fill -Bucket users -KeyProperty Name
```

users · 2 objects

### 1.4 Explicit -Key for independent naming
---

What if you need a key that isn't a property of the object itself? That's what the
bare -Key parameter is for — you decide the key, independent of the data inside.


```powershell
$data = @{ Source = "import"; Items = 42 }
$data | fill -Bucket users -Key "external-ref"
```

users · 1 objects

### 1.5 JSON output with -AsJson
---

JSON mode is for when you want human-readable files — configs, settings, anything you
might edit by hand. Add -AsJson and Buckets stores a .json file instead of .dat.
You can open it in any text editor.


```powershell
$config = @{ Host = "localhost"; Port = 5432 }
$config | fill -Bucket config -Key "app-config" -AsJson
```

config · 1 objects

### 1.6 Timestamp keys with -AsTimestamp
---

For logs, metrics, or any time-series data, -AsTimestamp auto-generates a unique key
from the current date and time. No two objects ever get the same name, and chronological
ordering is built right in.


```powershell
$events = @(
  @{ Event = "login"; User = "alice" }
  @{ Event = "logout"; User = "bob" }
)
$events | fill -Bucket events -AsTimestamp
```

events · 2 objects

### 1.7 Preventing overwrites with -Overwrite
---

Already have an object with the same key? Without -Overwrite, Buckets skips it silently.
Add -Overwrite to replace the existing object with the new one.


```powershell
$alice = @{ Name = "Alice"; Role = "admin"; Score = 99 }
New-BucketObject -InputObject $alice -Bucket users -Key "Alice" -Overwrite
```

users · 1 objects

### 1.8 Compression with -Compress
---

Repetitive data — logs, heartbeats, sensor readings — compresses extremely well. The
-Compress flag applies GZip before writing, and Buckets auto-detects compressed files
on read so you never have to think about it.


```powershell
$logs = 1..30 | ForEach-Object { @{ Seq = $_; Msg = "Heartbeat OK" } }
fill -Bucket logs -InputObject $logs -Compress
```

logs · 30 objects · compressed

## 1b. Create — quiet, verbose, and edge cases
---

### 1b.1 Quiet and verbose output
---

By default, fill shows a progress bar and a summary when saving. If you're scripting
or just want silence, -Quiet suppresses all output. For debugging, -Verbose prints
per-object details.


```powershell
$data = @{ Msg = "test" }
$data | fill -Bucket demo -Key "verbosity-demo" -Quiet
```


### 1b.2 PSCustomObject vs hashtable
---

Both hashtables and PSCustomObject work with Buckets. The difference: PSCustomObject
preserves the order of your properties, while a regular hashtable does not guarantee
ordering.


```powershell
$custom = [PSCustomObject]@{ Type = "PSCustomObject"; Ordered = $true }
$custom | fill -Bucket types -Key "custom"
$hash = @{ Type = "Hashtable" }
$hash | fill -Bucket types -Key "hash"
```

types · 1 objects
types · 1 objects

### 1b.3 Deeply nested objects
---

Buckets handles deeply nested objects with ease. The binary serializer preserves the
full object graph — nested PSCustomObjects, arrays, and all. This is exactly where
JSON would fall short.


```powershell
$nested = [PSCustomObject]@{
  Id = "deep"
  Metadata = [PSCustomObject]@{ App = "test"; Version = "1.0" }
  Items = @(
      [PSCustomObject]@{ Sku = "ABC"; Qty = 5 }
      [PSCustomObject]@{ Sku = "XYZ"; Qty = 3 }
  )
}
$nested | fill -Bucket nested -Key "deep"
```

nested · 1 objects

### 1b.4 Special characters in keys
---

Some characters — like /, :, *, ? — aren't valid in filenames. When you use them in a
key, Buckets automatically replaces them with underscores so the filesystem stays happy.


```powershell
$data = @{ Data = "sanitized key" }
$data | fill -Bucket special -Key "my/file:name*test"
```

special · 1 objects

### 1b.5 Empty keys after sanitization
---

Keys that sanitize to only underscores (like dots or special characters) are
silently skipped. Use -Verbose to see the module explain why.


```powershell
@{ X = 1 } | fill -Bucket demo -Key "..." -Quiet -Verbose
@{ X = 1 } | fill -Bucket demo -Key ". ." -Quiet -Verbose
```


## 2. Read — spill / Get-BucketObject
---

### 2.1 Spilling all objects
---

The counterpart to fill is spill (short for Get-BucketObject). With no arguments,
it returns every object from every bucket — useful for getting the lay of the land.


```powershell
spill
```

```

Port Host
---- ----
5432 localhost
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   

```

### 2.2 Filtering by bucket
---

Most of the time you want objects from a specific bucket. Pass -Bucket to narrow
the search to just one bucket.


```powershell
spill -Bucket team
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95

Name   : Bob
Joined : 11.11.2025 19:13:22
Role   : Designer
Skills : {Figma, CSS, HTML}
Level  : 2
Active : True
Score  : 72

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 88

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91
```

### 2.3 Positional bucket lookup
---

The first positional argument is the bucket name. Omit -Key to retrieve
all objects from that bucket.


```powershell
spill team
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95

Name   : Bob
Joined : 11.11.2025 19:13:22
Role   : Designer
Skills : {Figma, CSS, HTML}
Level  : 2
Active : True
Score  : 72

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 88

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91
```

### 2.4 Key lookup by name
---

Pass a key as the second positional argument (or with -Key). Keys are matched
case-insensitively and as prefixes by default.


```powershell
spill team "Alice"
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95
```

### 2.5 Exact key retrieval
---

Pass the exact full key name to retrieve just that one object.


```powershell
spill team -Key "Frank"
```

```

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91
```

### 2.6 Case-insensitive matching
---

Case doesn't matter. "alice" finds "Alice" because all key matching is
case-insensitive. No more guessing about capitalization.


```powershell
spill team -Key "alice"
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95
```

### 2.7 Handling missing keys
---

What happens when there's no match? Buckets returns nothing with a warning —
no crash, just a helpful nudge that nothing was found.


```powershell
spill -Bucket team -Key "Zoe"
```


### 2.8 Wildcards in bucket names
---

You can use wildcards in bucket names too. "t*" matches any bucket starting
with "t", making it easy to search groups of related buckets.


```powershell
spill -Bucket "t*"
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95

Name   : Bob
Joined : 11.11.2025 19:13:22
Role   : Designer
Skills : {Figma, CSS, HTML}
Level  : 2
Active : True
Score  : 72

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 88

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91

Type    : PSCustomObject
Ordered : True

Type : Hashtable
```

### 2.9 Querying multiple buckets
---

Pass multiple bucket names as an array. Buckets searches each one and combines
the results into a single list.


```powershell
spill -Bucket "team", "staff"
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95

Name   : Bob
Joined : 11.11.2025 19:13:22
Role   : Designer
Skills : {Figma, CSS, HTML}
Level  : 2
Active : True
Score  : 72

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 88

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91

Role   : HR
Name   : Dana
Score  : 70
Level  : 2
Active : True

Role   : Finance
Name   : Eric
Score  : 82
Level  : 3
Active : True

Role   : Marketing
Name   : Gina
Score  : 65
Level  : 1
Active : False
```

### 2.10 Metadata properties
---

Every object retrieved by Buckets carries metadata: _BucketName, _BucketKey, and
_BucketFile. These tell you exactly where the object came from — useful for
pipeline operations where context matters.


```powershell
spill -Bucket team -Key "Bob" | Select _BucketName, _BucketKey, _BucketFile
```

```

_BucketName _BucketKey _BucketFile
----------- ---------- -----------
team        Bob        C:\Users\berfelde\.buckets\team\Bob.dat
```

### 2.11 Piping to Select-Object
---

Since spill returns regular PowerShell objects, you can pipe them into Select-Object,
Sort-Object, Group-Object — anything you'd do with any other object in PowerShell.


```powershell
spill -Bucket team | Sort Score -Descending | Select Name, Role, Score
```

```

Name  Role      Score
----  ----      -----
Alice Developer    95
Frank Developer    91
Carol PM           88
Bob   Designer     72
```

### 2.12 Dot notation access
---

Access individual properties using standard dot notation. Store the result in a
variable and work with it like any other PowerShell object.


```powershell
$dev = spill -Bucket team -Key "Frank"
$dev.Name
$dev.Role
$dev.Level
$dev.Score
```


## 2a. Read — filtering with -Match
---

### 2a.1 Exact match filtering
---

-Match is Buckets' built-in filter for exact equality. Pass a hashtable of property
names and values, and Buckets returns only objects where every property matches
exactly.


```powershell
spill -Bucket team -Match @{ Role = "Developer" }
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91
```

### 2a.2 Matching null values
---

Special case: matching against . If a property is  on the object, or doesn't
exist at all, it counts as a match for . Useful for finding objects with missing
fields.


```powershell
spill -Bucket team -Match @{ Deleted = $null }
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95

Name   : Bob
Joined : 11.11.2025 19:13:22
Role   : Designer
Skills : {Figma, CSS, HTML}
Level  : 2
Active : True
Score  : 72

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 88

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91
```

### 2a.3 Multi-property matching
---

You can match on multiple properties at once — think of it as AND logic. All conditions
must be true for an object to be returned.


```powershell
spill -Bucket team -Match @{ Level = 3; Active = $true }
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 88
```

### 2a.4 Mixed type matching
---

Let's create some fresh data to demonstrate -Match with mixed types. Strings, numbers,
and booleans all work as match criteria.


```powershell
$data = @(
  @{ Name = "A"; Count = 5; Active = $true }
  @{ Name = "B"; Count = 10; Active = $false }
  @{ Name = "C"; Count = 5; Active = $true }
)
New-BucketObject -InputObject $data -Bucket match-demo -KeyProperty Name
spill -Bucket match-demo -Match @{ Count = 5; Active = $true }
```

```

Name Count Active
---- ----- ------
A        5   True
C        5   True
```

### 2a.5 Case-insensitive string matching
---

String matching with -Match is exact and case-insensitive. "red" matches "red" but
also "Red", "RED", and so on.


```powershell
$items = @(
  @{ Name = "alpha"; Color = "red" }
  @{ Name = "beta"; Color = "blue" }
  @{ Name = "gamma"; Color = "red" }
)
$items | fill -Bucket match-demo -KeyProperty Name
spill -Bucket match-demo -Match @{ Color = "red" }
```

```

Color Name
----- ----
red   alpha
red   gamma
```

### 2a.6 Top-level properties only
---

-Match only looks at top-level properties. If you need to drill into nested data like
.Settings.Enabled, you'll need -Filter instead.


```powershell
$data = @{ Id = "a"; Meta = @{ Name = "inner" } }
$data | fill -Bucket nested-match -KeyProperty Id
spill -Bucket nested-match -Match @{ Meta = $null }
```


## 2b. Read — comparison with -Filter
---

### 2b.1 Scriptblock filtering
---

For anything beyond exact equality, reach for -Filter. It takes a scriptblock where
 represents each object. You can use any PowerShell operator: -gt, -lt, -match,
-like, -and, -or, and more.


```powershell
spill -Bucket team -Filter { $_.Score -gt 80 }
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 88

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91
```

### 2b.2 Less-than-or-equal comparison
---

Less than or equal works the same way. Think of -Filter as writing a Where-Object
clause that runs inside Buckets rather than in the pipeline.


```powershell
spill -Bucket team -Filter { $_.Score -le 90 }
```

```

Name   : Bob
Joined : 11.11.2025 19:13:22
Role   : Designer
Skills : {Figma, CSS, HTML}
Level  : 2
Active : True
Score  : 72

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 88
```

### 2b.3 Regex pattern matching
---

Pattern matching with -match uses regular expressions. Here we find names starting
with A or E using the regex "^[AE]".


```powershell
spill -Bucket team -Filter { $_.Name -match "^[AE]" }
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95
```

### 2b.4 Wildcard matching with -like
---

The -like operator uses wildcard patterns. "*e*" matches any name containing the
letter "e" anywhere in the string.


```powershell
spill -Bucket team -Filter { $_.Name -like "*e*" }
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95
```

### 2b.5 Combining conditions with -and
---

Combine conditions with -and. Both must be true: score above 80 AND role is
"Developer".


```powershell
spill -Bucket team -Filter { $_.Score -gt 80 -and $_.Role -eq "Developer" }
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91
```

### 2b.6 Combining conditions with -or
---

Combine conditions with -or. Either can be true: role is "Designer" OR level above 3.


```powershell
spill -Bucket team -Filter { $_.Role -eq "Designer" -or $_.Level -gt 3 }
```

```

Name   : Bob
Joined : 11.11.2025 19:13:22
Role   : Designer
Skills : {Figma, CSS, HTML}
Level  : 2
Active : True
Score  : 72

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91
```

### 2b.7 String length checks
---

String length checks work because you're writing real PowerShell expressions. Here
we find objects where the Value property is longer than 5 characters.


```powershell
$items = @(
  @{ Name = "short"; Value = "abc" }
  @{ Name = "long";  Value = "abcdefghijk" }
)
$items | fill -Bucket str-test -KeyProperty Name
spill -Bucket str-test -Filter { $_.Value.Length -gt 5 }
```

```

Value       Name
-----       ----
abcdefghijk long
```

### 2b.8 Date comparisons
---

Date comparisons too — no special syntax needed. Compare DateTime properties with
-gt, -lt, or any other operator, just like you would in regular PowerShell.


```powershell
$cutoff = (Get-Date).AddDays(-100)
spill -Bucket team -Filter { $_.Joined -gt $cutoff }
```

```

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 88
```

### 2b.9 Nested property access
---

Nested properties are accessible via standard dot notation inside the scriptblock.
Here we check if an array property contains a value using -contains.


```powershell
spill -Bucket team -Filter { $_.Skills -contains "Rust" }
```

```

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91
```

### 2b.10 Cross-bucket filtering
---

Omitting -Bucket makes -Filter run against all buckets at once. This is a cross-bucket
query — useful for finding objects anywhere in your data.


```powershell
@{ Name = "HighScore"; Score = 90 } | fill -Bucket config -Key "app-config"
spill -Filter { $_.Score -gt 80 }
```

```

Score Name
----- ----
 90 HighScore
 82 Eric
 95 Alice
 88 Carol
 91 Frank
 99 Alice
 88 Carol
```

## 2c. Read — pagination with -First / -Skip
---

### 2c.1 Limiting results with -First
---

Pagination is built right in. -First limits the number of results returned. Useful
for previewing large datasets without loading everything.


```powershell
spill -Bucket team -First 3
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95

Name   : Bob
Joined : 11.11.2025 19:13:22
Role   : Designer
Skills : {Figma, CSS, HTML}
Level  : 2
Active : True
Score  : 72

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 88
```

### 2c.2 Skipping results with -Skip
---

Combine -Skip with -First to jump ahead. -Skip 1 -First 3 skips the first result and
returns the next three — a classic paging pattern.


```powershell
spill -Bucket team -Skip 1 -First 3
```

```

Name   : Bob
Joined : 11.11.2025 19:13:22
Role   : Designer
Skills : {Figma, CSS, HTML}
Level  : 2
Active : True
Score  : 72

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 88

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91
```

### 2c.3 Filtering with pagination
---

-First and -Skip work together with -Filter too. Here we filter for scores above 70,
then take only the first 3 results.


```powershell
spill -Bucket team -Filter { $_.Score -gt 70 } -First 3
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95

Name   : Bob
Joined : 11.11.2025 19:13:22
Role   : Designer
Skills : {Figma, CSS, HTML}
Level  : 2
Active : True
Score  : 72

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 88
```

## 3. Update — Set-BucketObject
---

### 3.1 Pipeline update with Set-BucketObject
---

Set-BucketObject updates an existing object in place. When piped from spill, it
auto-detects the bucket and key from the _BucketName and _BucketKey metadata —
no need to specify them again.


```powershell
spill -Bucket team -Key "Bob" | ForEach-Object {
  $_.Score = 99
  $_.Role = "Lead"
  $_
} | Set-BucketObject -Quiet
```


### 3.2 Explicit bucket and key
---

Without pipeline metadata, specify -Bucket and -Key explicitly. Pass the modified
object through -InputObject.


```powershell
$obj = spill -Bucket team -Key "Carol"
$obj.Score = 100
Set-BucketObject -Bucket team -Key "Carol" -InputObject $obj -Quiet
```


### 3.3 Partial update with hashtable
---

Need to update just one field? Pipe a hashtable with only the properties you want
to change. Buckets merges it with the existing object — partial updates work
seamlessly.


```powershell
$patch = @{ Email = "alice@contoso.com" }
$patch | Set-BucketObject -Bucket team -Key "Alice" -Quiet
```


### 3.4 Adding new properties
---

New properties are automatically added. If the property doesn't exist on the
original object, it gets appended without affecting existing fields.


```powershell
$patch = @{ Phone = "555-0100" }
$patch | Set-BucketObject -Bucket team -Key "Alice" -Quiet
```


### 3.5 Preserving unchanged properties
---

Properties you don't mention in the update stay untouched. Only the keys in your
patch hashtable are modified.


```powershell
$patch = @{ City = "Portland" }
$patch | Set-BucketObject -Bucket team -Key "Alice" -Quiet
```


### 3.6 Format preservation
---

Format preservation: JSON objects stay as .json, binary objects stay as .dat.
Set-BucketObject always writes back in the original format.


```powershell
$config = @{ Host = "localhost"; Port = 5432 }
$config | fill -Bucket config -Key "db-settings" -AsJson
$patch = @{ UpdatedAt = Get-Date; Host = "prod-server" }
$patch | Set-BucketObject -Bucket config -Key "db-settings" -Quiet
```


### 3.7 Missing metadata warning
---

What happens if you pipe to Set-BucketObject without metadata AND without explicit
-Bucket/-Key? It throws — it has no idea where to save.


```powershell
try { @{ X = 1 } | Set-BucketObject -Quiet -ErrorAction Stop }
catch { Write-Host "    Error: -Bucket and -Key required" -ForegroundColor Green }
```

  Error: -Bucket and -Key required

## 4. Delete — Remove-BucketObject
---

### 4.1 Preview with -WhatIf
---

-WhatIf previews what would be deleted without actually removing anything. Always
safe to try before you delete.


```powershell
Remove-BucketObject -Bucket team -Key "Bob" -WhatIf
```


### 4.2 Deleting by key
---

Delete by key is straightforward. Pass the key of the object you want to remove.


```powershell
Remove-BucketObject -Bucket team -Key "Bob" -Quiet
spill -Bucket team
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95
Email  : alice@contoso.com
Phone  : 555-0100
City   : Portland

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 100

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91
```

### 4.3 Deleting non-existent key
---

Trying to delete a non-existent key issues a warning but doesn't throw an error.
Buckets is forgiving about missing objects.


```powershell
Remove-BucketObject -Bucket team -Key "Zoe"
```


### 4.4 Key or all requirement
---

You must specify either -Key, -All, or a filter. Without one of these, the parameter
set validation rejects the command.


```powershell
Remove-BucketObject -Bucket team -ErrorAction SilentlyContinue
```


### 4.5 Delete with -Match
---

-Match works with deletion too. Delete all objects matching certain criteria in
one command.


```powershell
Remove-BucketObject -Bucket team -Match @{ Role = "QA" } -Quiet
spill -Bucket team
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95
Email  : alice@contoso.com
Phone  : 555-0100
City   : Portland

Role   : Designer
Name   : Bob
Joined : 11.11.2025 19:13:23
Active : True
Skills : {Figma, CSS, HTML}
Level  : 2
Score  : 72

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 100

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91
```

### 4.6 Delete with -Filter
---

-Filter works the same way — delete objects that pass the scriptblock condition.
Here, any inactive member gets removed.


```powershell
Remove-BucketObject -Bucket team -Filter { $_.Active -eq $false } -Quiet
spill -Bucket team
```

```

Name   : Alice
Joined : 10.05.2025 19:13:22
Role   : Developer
Skills : {PowerShell, C#, Azure}
Level  : 3
Active : True
Score  : 95
Email  : alice@contoso.com
Phone  : 555-0100
City   : Portland

Role   : Designer
Name   : Bob
Joined : 11.11.2025 19:13:23
Active : True
Skills : {Figma, CSS, HTML}
Level  : 2
Score  : 72

Name   : Carol
Joined : 09.02.2026 19:13:22
Role   : PM
Skills : {Agile, Jira, Confluence}
Level  : 3
Active : True
Score  : 100

Name   : Frank
Joined : 26.12.2024 19:13:22
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Level  : 4
Active : True
Score  : 91
```

### 4.7 Delete all with -All
---

-All deletes every object in the bucket. A clean slate.


```powershell
Remove-BucketObject -Bucket team -All -Quiet
spill -Bucket team
```


### 4.8 Passthru metadata
---

-PassThru returns metadata about what was deleted. Useful for logging, auditing,
or confirmation messages.


```powershell
$tmp = @{ Data = "gone" }
$tmp | fill -Bucket temp -Key "bye-bye" -Quiet
Remove-BucketObject -Bucket temp -Key "bye-bye" -PassThru -Quiet
```

```

Bucket Key
------ ---
temp   bye-bye.dat
```

## 5. Object Operations — Copy, Rename, Move
---

### 5.1 Copy within a bucket
---

Copy an object within the same bucket but with a different key. The original stays
untouched — this is a true copy, not a move.


```powershell
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "Alice-Backup" -Quiet
spill -Bucket team -Key "Alice-Backup"
```

```

Role   : Developer
Name   : Alice
Joined : 10.05.2025 19:13:23
Active : True
Skills : {PowerShell, C#, Azure}
Level  : 3
Score  : 95
```

### 5.2 Copy across buckets
---

Copy across buckets too. Specify -DestinationBucket to copy to a different bucket.


```powershell
Copy-BucketObject -Bucket team -Key "Alice" -DestinationBucket archive -Quiet
spill -Bucket archive -Key "Alice"
```

```

Role   : Developer
Name   : Alice
Joined : 10.05.2025 19:13:23
Active : True
Skills : {PowerShell, C#, Azure}
Level  : 3
Score  : 95
```

### 5.3 Copy with passthru
---

-PassThru on Copy-BucketObject returns metadata about the destination: source,
destination, and new key — useful for pipeline logging.


```powershell
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "Alice-pass" -PassThru -Quiet
Remove-BucketObject -Bucket team -Key "Alice-pass" -Quiet
```

```

SourceBucket SourceKey DestinationBucket DestinationKey
------------ --------- ----------------- --------------
team         Alice     team              Alice-pass
```

### 5.4 Rename an object
---

Rename changes the key of an existing object in place. The format (binary or JSON)
is preserved through the rename.


```powershell
$tmp = @{ Data = "rename me" }
$tmp | fill -Bucket tmp -Key "old-name" -Quiet
Rename-BucketObject -Bucket tmp -Key "old-name" -NewKey "new-name" -Quiet
```


### 5.5 Rename preserves format
---

Renaming a JSON object preserves the .json extension too. Format is always
maintained — you never have to worry about it.


```powershell
$tmp = @{ Format = "json" }
$tmp | fill -Bucket tmp-json -Key "json-old" -AsJson -Quiet
Rename-BucketObject -Bucket tmp-json -Key "json-old" -NewKey "json-new" -PassThru -Quiet
```

```

Bucket   OldKey   NewKey
------   ------   ------
tmp-json json-old json-new
```

### 5.6 Move between buckets
---

Move combines copy + delete in one operation. The object is copied to the
destination and removed from the source.


```powershell
$data = @(
  @{ Id = "obj1"; Value = "move me" }
)
$data | fill -Bucket source -KeyProperty Id -Quiet
Move-BucketObject -Bucket source -Key "obj1" -DestinationBucket dest -Quiet
```


### 5.7 Move with rename
---

Move with rename: specify a different key in the target bucket to rename
as part of the move.


```powershell
$tmp = @{ Data = "moved+renamed" }
$tmp | fill -Bucket origin -Key "orig-key" -Quiet
Move-BucketObject -Bucket origin -Key "orig-key" -DestinationBucket final -DestinationKey "new-key" -Quiet
```


### 5.8 Move with passthru
---

-PassThru on Move returns metadata about both the source and destination
objects.


```powershell
$tmp = @{ X = 1 }
$tmp | fill -Bucket move-src -Key "m-pass" -Quiet
Move-BucketObject -Bucket move-src -Key "m-pass" -DestinationBucket move-dst -PassThru -Quiet
```

```

SourceBucket SourceKey DestinationBucket DestinationKey
------------ --------- ----------------- --------------
move-src     m-pass    move-dst          m-pass
```

### 5.9 Passthru on all operations
---

All three operations — Copy, Rename, Move — support -PassThru. Chain them
together for auditable object management.


```powershell
$tmp = @{ X = 1 }
$tmp | fill -Bucket pass -Key "src-key" -Quiet
Copy-BucketObject -Bucket pass -Key "src-key" -DestinationKey "cp-key" -PassThru -Quiet
Rename-BucketObject -Bucket pass -Key "cp-key" -NewKey "rn-key" -PassThru -Quiet
Move-BucketObject -Bucket pass -Key "src-key" -DestinationBucket pass -DestinationKey "mv-key" -PassThru -Quiet
```

```

SourceBucket SourceKey DestinationBucket DestinationKey
------------ --------- ----------------- --------------
pass         src-key   pass              cp-key
```
```

Bucket OldKey NewKey
------ ------ ------
pass   cp-key rn-key
```
```

SourceBucket SourceKey DestinationBucket DestinationKey
------------ --------- ----------------- --------------
pass         src-key   pass              mv-key
```

## 6. Bucket Management — dip / Get-Bucket
---

### 6.1 Listing buckets with dip
---

dip (short for Get-Bucket) lists all your buckets with their object counts and
timestamps. It's the first command to run when you want an overview.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
dip
```

```

Name         ObjectCount HasSubBuckets
----         ----------- -------------
archive                1         False
config                 3         False
demo                   2         False
dest                   1         False
events                 4         False
final                  1         False
logs                 431          True
match-demo             6         False
move-dst               1         False
move-src               0         False
nested                 1         False
nested-match           1         False
origin                 0         False
pass                   2         False
source                 0         False
special                1         False
staff                  7         False
str-test               2         False
team                   5         False
temp                   0         False
tmp                    1         False
tmp-json               1         False
types                  2         False
users                  5         False
```

### 6.2 Filtering by name
---

Filter buckets by name with a substring match. "team" matches "team" and any
other bucket with "team" in the name.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
dip "team"
```

```

Name ObjectCount HasSubBuckets
---- ----------- -------------
team           5         False
```

### 6.3 Bucket statistics
---

Get-BucketStats shows detailed statistics: object count, total size on disk, and
creation/modification timestamps for a specific bucket.


```powershell
Get-BucketStats -Bucket team
```

```

Name         : team
Path         : C:\Users\berfelde\.buckets\team
ObjectCount  : 5
TotalSize    : 5.68 KB
OldestObject : 10.05.2026 19:13:23
NewestObject : 10.05.2026 19:13:25
```

### 6.4 Listing keys
---

Get-BucketKeys lists every key in a bucket — just the key names,
no deserialization overhead. For format, size, type, and compression,
use Get-BucketObjectStats.


```powershell
Get-BucketKeys -Bucket team
```

```

Bucket Key
------ ---
team   Alice-Backup
team   Alice
team   Bob
team   Carol
team   Frank
```

### 6.5 Object statistics
---

Get-BucketObjectStats returns detailed per-object metadata: format, type,
size, last modified, and compression status.


```powershell
Get-BucketObjectStats -Bucket team
```

```

Bucket        : team
Key           : Alice-Backup
Format        : Binary
Type          : Object
Size          : 1167
LastWriteTime : 10.05.2026 19:13:25
IsCompressed  : False

Bucket        : team
Key           : Alice
Format        : Binary
Type          : Object
Size          : 1167
LastWriteTime : 10.05.2026 19:13:25
IsCompressed  : False

Bucket        : team
Key           : Bob
Format        : Binary
Type          : Object
Size          : 1159
LastWriteTime : 10.05.2026 19:13:25
IsCompressed  : False

Bucket        : team
Key           : Carol
Format        : Binary
Type          : Object
Size          : 1162
LastWriteTime : 10.05.2026 19:13:25
IsCompressed  : False

Bucket        : team
Key           : Frank
Format        : Binary
Type          : Object
Size          : 1165
LastWriteTime : 10.05.2026 19:13:25
IsCompressed  : False
```

### 6.6 Filtering keys by pattern
---

Filter keys by pattern with -Match. "A*" matches all keys starting with "A".


```powershell
Get-BucketKeys -Bucket team -Match "A*"
```

```

Bucket Key
------ ---
team   Alice-Backup
team   Alice
```

### 6.7 Keys across all buckets
---

Get-BucketKeys across all buckets with the wildcard "*" — a complete inventory
of every object stored.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-BucketKeys -Bucket "*"
```

```

Bucket                               Key
------                               ---
archive                              Alice
config                               app-config
config                               db-settings
config                               app-config
demo                                 verbosity-demo
demo                                 _ _
dest                                 obj1
events                               20260510191323158_0
events                               20260510191323159_1
events                               20260510191324090_0
events                               20260510191324104_1
final                                new-key
logs/eventlog/Application/2026.05.08 20260510185259969_0
logs/eventlog/Application/2026.05.08 20260510185259970_1
logs/eventlog/Application/2026.05.08 20260510185259971_2
logs/eventlog/Application/2026.05.08 20260510185259972_3
logs/eventlog/Application/2026.05.08 20260510185259972_4
logs/eventlog/Application/2026.05.08 20260510185259973_5
logs/eventlog/Application/2026.05.08 20260510185259974_6
logs/eventlog/Application/2026.05.08 20260510185259974_7
logs/eventlog/Application/2026.05.08 20260510185259975_8
logs/eventlog/Application/2026.05.08 20260510185259976_9
logs/eventlog/Application/2026.05.09 20260510185300035_0
logs/eventlog/Application/2026.05.09 20260510185300036_1
logs/eventlog/Application/2026.05.09 20260510185300037_2
logs/eventlog/Application/2026.05.09 20260510185300038_3
logs/eventlog/Application/2026.05.09 20260510185300039_4
logs/eventlog/Application/2026.05.09 20260510185300039_5
logs/eventlog/Application/2026.05.09 20260510185300040_6
logs/eventlog/Application/2026.05.09 20260510185300040_7
logs/eventlog/Application/2026.05.09 20260510185300041_8
logs/eventlog/Application/2026.05.09 20260510185300042_9
logs/eventlog/Application/2026.05.10 20260510185300103_0
logs/eventlog/Application/2026.05.10 20260510185300104_1
logs/eventlog/Application/2026.05.10 20260510185300104_2
logs/eventlog/Application/2026.05.10 20260510185300105_3
logs/eventlog/Application/2026.05.10 20260510185300106_4
logs/eventlog/Application/2026.05.10 20260510185300107_5
logs/eventlog/Application/2026.05.10 20260510185300109_6
logs/eventlog/Application/2026.05.10 20260510185300110_7
logs/eventlog/Application/2026.05.10 20260510185300111_8
logs/eventlog/Application/2026.05.10 20260510185300112_9
logs/eventlog/Security/2026.05.08    20260510185259978_0
logs/eventlog/Security/2026.05.08    20260510185259979_1
logs/eventlog/Security/2026.05.08    20260510185259981_2
logs/eventlog/Security/2026.05.08    20260510185259984_3
logs/eventlog/Security/2026.05.08    20260510185259985_4
logs/eventlog/Security/2026.05.08    20260510185259987_5
logs/eventlog/Security/2026.05.08    20260510185259988_6
logs/eventlog/Security/2026.05.08    20260510185259988_7
logs/eventlog/Security/2026.05.09    20260510185300051_0
logs/eventlog/Security/2026.05.09    20260510185300052_1
logs/eventlog/Security/2026.05.09    20260510185300053_2
logs/eventlog/Security/2026.05.09    20260510185300053_3
logs/eventlog/Security/2026.05.09    20260510185300054_4
logs/eventlog/Security/2026.05.09    20260510185300055_5
logs/eventlog/Security/2026.05.09    20260510185300056_6
logs/eventlog/Security/2026.05.09    20260510185300056_7
logs/eventlog/Security/2026.05.10    20260510185300114_0
logs/eventlog/Security/2026.05.10    20260510185300115_1
logs/eventlog/Security/2026.05.10    20260510185300115_2
logs/eventlog/Security/2026.05.10    20260510185300116_3
logs/eventlog/Security/2026.05.10    20260510185300117_4
logs/eventlog/Security/2026.05.10    20260510185300117_5
logs/eventlog/Security/2026.05.10    20260510185300118_6
logs/eventlog/Security/2026.05.10    20260510185300119_7
logs/eventlog/System/2026.05.08      20260510185259934_0
logs/eventlog/System/2026.05.08      20260510185259935_1
logs/eventlog/System/2026.05.08      20260510185259935_2
logs/eventlog/System/2026.05.08      20260510185259936_3
logs/eventlog/System/2026.05.08      20260510185259937_4
logs/eventlog/System/2026.05.08      20260510185259937_5
logs/eventlog/System/2026.05.08      20260510185259938_6
logs/eventlog/System/2026.05.08      20260510185259939_7
logs/eventlog/System/2026.05.08      20260510185259939_8
logs/eventlog/System/2026.05.08      20260510185259940_9
logs/eventlog/System/2026.05.08      20260510185259941_10
logs/eventlog/System/2026.05.08      20260510185259941_11
logs/eventlog/System/2026.05.08      20260510185259942_12
logs/eventlog/System/2026.05.08      20260510185259943_13
logs/eventlog/System/2026.05.08      20260510185259943_14
logs/eventlog/System/2026.05.09      20260510185259992_0
logs/eventlog/System/2026.05.09      20260510185259993_1
logs/eventlog/System/2026.05.09      20260510185259993_2
logs/eventlog/System/2026.05.09      20260510185259994_3
logs/eventlog/System/2026.05.09      20260510185259995_4
logs/eventlog/System/2026.05.09      20260510185259996_5
logs/eventlog/System/2026.05.09      20260510185259996_6
logs/eventlog/System/2026.05.09      20260510185259997_7
logs/eventlog/System/2026.05.09      20260510185259998_8
logs/eventlog/System/2026.05.09      20260510185259998_9
logs/eventlog/System/2026.05.09      20260510185259999_10
logs/eventlog/System/2026.05.09      20260510185300029_11
logs/eventlog/System/2026.05.09      20260510185300030_12
logs/eventlog/System/2026.05.09      20260510185300031_13
logs/eventlog/System/2026.05.09      20260510185300032_14
logs/eventlog/System/2026.05.10      20260510185300060_0
logs/eventlog/System/2026.05.10      20260510185300061_1
logs/eventlog/System/2026.05.10      20260510185300076_2
logs/eventlog/System/2026.05.10      20260510185300077_3
logs/eventlog/System/2026.05.10      20260510185300079_4
logs/eventlog/System/2026.05.10      20260510185300080_5
logs/eventlog/System/2026.05.10      20260510185300081_6
logs/eventlog/System/2026.05.10      20260510185300081_7
logs/eventlog/System/2026.05.10      20260510185300082_8
logs/eventlog/System/2026.05.10      20260510185300083_10
logs/eventlog/System/2026.05.10      20260510185300083_9
logs/eventlog/System/2026.05.10      20260510185300084_11
logs/eventlog/System/2026.05.10      20260510185300098_12
logs/eventlog/System/2026.05.10      20260510185300099_13
logs/eventlog/System/2026.05.10      20260510185300100_14
logs/eventlog/System/2026.05.10      20260510185438663_0
logs/eventlog/System/2026.05.10      20260510185438664_1
logs/syslog/db01/2026.05.08          20260510185259800_0
logs/syslog/db01/2026.05.08          20260510185259801_1
logs/syslog/db01/2026.05.08          20260510185259801_2
logs/syslog/db01/2026.05.08          20260510185259802_3
logs/syslog/db01/2026.05.08          20260510185259803_4
logs/syslog/db01/2026.05.08          20260510185259804_5
logs/syslog/db01/2026.05.08          20260510185259804_6
logs/syslog/db01/2026.05.08          20260510185259805_7
logs/syslog/db01/2026.05.08          20260510185259806_8
logs/syslog/db01/2026.05.08          20260510185259806_9
logs/syslog/db01/2026.05.09          20260510185259813_0
logs/syslog/db01/2026.05.09          20260510185259814_1
logs/syslog/db01/2026.05.09          20260510185259814_2
logs/syslog/db01/2026.05.09          20260510185259815_3
logs/syslog/db01/2026.05.09          20260510185259816_4
logs/syslog/db01/2026.05.09          20260510185259816_5
logs/syslog/db01/2026.05.09          20260510185259817_6
logs/syslog/db01/2026.05.09          20260510185259818_7
logs/syslog/db01/2026.05.09          20260510185259818_8
logs/syslog/db01/2026.05.09          20260510185259819_9
logs/syslog/db01/2026.05.10          20260510185259832_0
logs/syslog/db01/2026.05.10          20260510185259833_1
logs/syslog/db01/2026.05.10          20260510185259834_2
logs/syslog/db01/2026.05.10          20260510185259834_3
logs/syslog/db01/2026.05.10          20260510185259835_4
logs/syslog/db01/2026.05.10          20260510185259836_5
logs/syslog/db01/2026.05.10          20260510185259836_6
logs/syslog/db01/2026.05.10          20260510185259837_7
logs/syslog/db01/2026.05.10          20260510185259838_8
logs/syslog/db01/2026.05.10          20260510185259839_9
logs/syslog/lb01/2026.05.08          20260510185259843_0
logs/syslog/lb01/2026.05.08          20260510185259843_1
logs/syslog/lb01/2026.05.08          20260510185259844_2
logs/syslog/lb01/2026.05.08          20260510185259846_3
logs/syslog/lb01/2026.05.08          20260510185259847_4
logs/syslog/lb01/2026.05.08          20260510185259848_5
logs/syslog/lb01/2026.05.08          20260510185259848_6
logs/syslog/lb01/2026.05.08          20260510185259849_7
logs/syslog/lb01/2026.05.08          20260510185259851_8
logs/syslog/lb01/2026.05.08          20260510185259851_9
logs/syslog/lb01/2026.05.08          20260510185259852_10
logs/syslog/lb01/2026.05.08          20260510185259853_11
logs/syslog/lb01/2026.05.08          20260510185259853_12
logs/syslog/lb01/2026.05.08          20260510185259854_13
logs/syslog/lb01/2026.05.08          20260510185259855_14
logs/syslog/lb01/2026.05.08          20260510185259855_15
logs/syslog/lb01/2026.05.08          20260510185259856_16
logs/syslog/lb01/2026.05.08          20260510185259858_17
logs/syslog/lb01/2026.05.08          20260510185259859_18
logs/syslog/lb01/2026.05.08          20260510185259860_19
logs/syslog/lb01/2026.05.09          20260510185259872_0
logs/syslog/lb01/2026.05.09          20260510185259873_1
logs/syslog/lb01/2026.05.09          20260510185259873_2
logs/syslog/lb01/2026.05.09          20260510185259875_3
logs/syslog/lb01/2026.05.09          20260510185259876_4
logs/syslog/lb01/2026.05.09          20260510185259876_5
logs/syslog/lb01/2026.05.09          20260510185259877_6
logs/syslog/lb01/2026.05.09          20260510185259878_7
logs/syslog/lb01/2026.05.09          20260510185259878_8
logs/syslog/lb01/2026.05.09          20260510185259879_9
logs/syslog/lb01/2026.05.09          20260510185259880_10
logs/syslog/lb01/2026.05.09          20260510185259880_11
logs/syslog/lb01/2026.05.09          20260510185259881_12
logs/syslog/lb01/2026.05.09          20260510185259889_13
logs/syslog/lb01/2026.05.09          20260510185259890_14
logs/syslog/lb01/2026.05.09          20260510185259892_15
logs/syslog/lb01/2026.05.09          20260510185259893_16
logs/syslog/lb01/2026.05.09          20260510185259894_17
logs/syslog/lb01/2026.05.09          20260510185259894_18
logs/syslog/lb01/2026.05.09          20260510185259895_19
logs/syslog/lb01/2026.05.10          20260510185259899_0
logs/syslog/lb01/2026.05.10          20260510185259908_1
logs/syslog/lb01/2026.05.10          20260510185259909_2
logs/syslog/lb01/2026.05.10          20260510185259912_3
logs/syslog/lb01/2026.05.10          20260510185259912_4
logs/syslog/lb01/2026.05.10          20260510185259913_5
logs/syslog/lb01/2026.05.10          20260510185259914_6
logs/syslog/lb01/2026.05.10          20260510185259915_7
logs/syslog/lb01/2026.05.10          20260510185259915_8
logs/syslog/lb01/2026.05.10          20260510185259916_9
logs/syslog/lb01/2026.05.10          20260510185259917_10
logs/syslog/lb01/2026.05.10          20260510185259917_11
logs/syslog/lb01/2026.05.10          20260510185259918_12
logs/syslog/lb01/2026.05.10          20260510185259919_13
logs/syslog/lb01/2026.05.10          20260510185259920_14
logs/syslog/lb01/2026.05.10          20260510185259921_15
logs/syslog/lb01/2026.05.10          20260510185259921_16
logs/syslog/lb01/2026.05.10          20260510185259925_17
logs/syslog/lb01/2026.05.10          20260510185259926_18
logs/syslog/lb01/2026.05.10          20260510185259926_19
logs/syslog/web01/2026.05.08         20260510185259555_0
logs/syslog/web01/2026.05.08         20260510185259556_1
logs/syslog/web01/2026.05.08         20260510185259557_2
logs/syslog/web01/2026.05.08         20260510185259558_3
logs/syslog/web01/2026.05.08         20260510185259558_4
logs/syslog/web01/2026.05.08         20260510185259559_5
logs/syslog/web01/2026.05.08         20260510185259560_6
logs/syslog/web01/2026.05.08         20260510185259560_7
logs/syslog/web01/2026.05.08         20260510185259561_8
logs/syslog/web01/2026.05.08         20260510185259561_9
logs/syslog/web01/2026.05.08         20260510185259562_10
logs/syslog/web01/2026.05.08         20260510185259563_11
logs/syslog/web01/2026.05.08         20260510185259563_12
logs/syslog/web01/2026.05.08         20260510185259564_13
logs/syslog/web01/2026.05.08         20260510185259565_14
logs/syslog/web01/2026.05.08         20260510185259565_15
logs/syslog/web01/2026.05.08         20260510185259566_16
logs/syslog/web01/2026.05.08         20260510185259568_17
logs/syslog/web01/2026.05.08         20260510185259569_18
logs/syslog/web01/2026.05.08         20260510185259569_19
logs/syslog/web01/2026.05.08         20260510185259570_20
logs/syslog/web01/2026.05.08         20260510185259571_21
logs/syslog/web01/2026.05.08         20260510185259571_22
logs/syslog/web01/2026.05.08         20260510185259572_23
logs/syslog/web01/2026.05.08         20260510185259573_24
logs/syslog/web01/2026.05.08         20260510185259573_25
logs/syslog/web01/2026.05.08         20260510185259574_26
logs/syslog/web01/2026.05.08         20260510185259581_27
logs/syslog/web01/2026.05.08         20260510185259582_28
logs/syslog/web01/2026.05.08         20260510185259583_29
logs/syslog/web01/2026.05.08         20260510185259583_30
logs/syslog/web01/2026.05.08         20260510185259584_31
logs/syslog/web01/2026.05.08         20260510185259585_32
logs/syslog/web01/2026.05.08         20260510185259585_33
logs/syslog/web01/2026.05.08         20260510185259586_34
logs/syslog/web01/2026.05.08         20260510185259587_35
logs/syslog/web01/2026.05.08         20260510185259587_36
logs/syslog/web01/2026.05.08         20260510185259588_37
logs/syslog/web01/2026.05.08         20260510185259589_38
logs/syslog/web01/2026.05.08         20260510185259589_39
logs/syslog/web01/2026.05.09         20260510185259596_0
logs/syslog/web01/2026.05.09         20260510185259596_1
logs/syslog/web01/2026.05.09         20260510185259597_2
logs/syslog/web01/2026.05.09         20260510185259598_3
logs/syslog/web01/2026.05.09         20260510185259599_4
logs/syslog/web01/2026.05.09         20260510185259619_5
logs/syslog/web01/2026.05.09         20260510185259620_6
logs/syslog/web01/2026.05.09         20260510185259621_7
logs/syslog/web01/2026.05.09         20260510185259621_8
logs/syslog/web01/2026.05.09         20260510185259622_9
logs/syslog/web01/2026.05.09         20260510185259623_10
logs/syslog/web01/2026.05.09         20260510185259623_11
logs/syslog/web01/2026.05.09         20260510185259624_12
logs/syslog/web01/2026.05.09         20260510185259625_13
logs/syslog/web01/2026.05.09         20260510185259625_14
logs/syslog/web01/2026.05.09         20260510185259626_15
logs/syslog/web01/2026.05.09         20260510185259632_16
logs/syslog/web01/2026.05.09         20260510185259632_17
logs/syslog/web01/2026.05.09         20260510185259633_18
logs/syslog/web01/2026.05.09         20260510185259634_19
logs/syslog/web01/2026.05.09         20260510185259635_20
logs/syslog/web01/2026.05.09         20260510185259636_21
logs/syslog/web01/2026.05.09         20260510185259636_22
logs/syslog/web01/2026.05.09         20260510185259637_23
logs/syslog/web01/2026.05.09         20260510185259640_24
logs/syslog/web01/2026.05.09         20260510185259642_25
logs/syslog/web01/2026.05.09         20260510185259643_26
logs/syslog/web01/2026.05.09         20260510185259643_27
logs/syslog/web01/2026.05.09         20260510185259644_28
logs/syslog/web01/2026.05.09         20260510185259645_29
logs/syslog/web01/2026.05.09         20260510185259645_30
logs/syslog/web01/2026.05.09         20260510185259646_31
logs/syslog/web01/2026.05.09         20260510185259647_32
logs/syslog/web01/2026.05.09         20260510185259647_33
logs/syslog/web01/2026.05.09         20260510185259648_34
logs/syslog/web01/2026.05.09         20260510185259648_35
logs/syslog/web01/2026.05.09         20260510185259649_36
logs/syslog/web01/2026.05.09         20260510185259650_37
logs/syslog/web01/2026.05.09         20260510185259650_38
logs/syslog/web01/2026.05.09         20260510185259651_39
logs/syslog/web01/2026.05.10         20260510185259680_0
logs/syslog/web01/2026.05.10         20260510185259681_1
logs/syslog/web01/2026.05.10         20260510185259684_2
logs/syslog/web01/2026.05.10         20260510185259685_3
logs/syslog/web01/2026.05.10         20260510185259686_4
logs/syslog/web01/2026.05.10         20260510185259686_5
logs/syslog/web01/2026.05.10         20260510185259687_6
logs/syslog/web01/2026.05.10         20260510185259688_7
logs/syslog/web01/2026.05.10         20260510185259688_8
logs/syslog/web01/2026.05.10         20260510185259689_9
logs/syslog/web01/2026.05.10         20260510185259690_10
logs/syslog/web01/2026.05.10         20260510185259690_11
logs/syslog/web01/2026.05.10         20260510185259691_12
logs/syslog/web01/2026.05.10         20260510185259691_13
logs/syslog/web01/2026.05.10         20260510185259692_14
logs/syslog/web01/2026.05.10         20260510185259693_15
logs/syslog/web01/2026.05.10         20260510185259693_16
logs/syslog/web01/2026.05.10         20260510185259694_17
logs/syslog/web01/2026.05.10         20260510185259695_18
logs/syslog/web01/2026.05.10         20260510185259695_19
logs/syslog/web01/2026.05.10         20260510185259696_20
logs/syslog/web01/2026.05.10         20260510185259697_21
logs/syslog/web01/2026.05.10         20260510185259697_22
logs/syslog/web01/2026.05.10         20260510185259698_23
logs/syslog/web01/2026.05.10         20260510185259698_24
logs/syslog/web01/2026.05.10         20260510185259699_25
logs/syslog/web01/2026.05.10         20260510185259700_26
logs/syslog/web01/2026.05.10         20260510185259701_27
logs/syslog/web01/2026.05.10         20260510185259702_28
logs/syslog/web01/2026.05.10         20260510185259703_29
logs/syslog/web01/2026.05.10         20260510185259703_30
logs/syslog/web01/2026.05.10         20260510185259704_31
logs/syslog/web01/2026.05.10         20260510185259705_32
logs/syslog/web01/2026.05.10         20260510185259707_33
logs/syslog/web01/2026.05.10         20260510185259707_34
logs/syslog/web01/2026.05.10         20260510185259708_35
logs/syslog/web01/2026.05.10         20260510185259709_36
logs/syslog/web01/2026.05.10         20260510185259709_37
logs/syslog/web01/2026.05.10         20260510185259710_38
logs/syslog/web01/2026.05.10         20260510185259711_39
logs/syslog/web02/2026.05.08         20260510185259723_0
logs/syslog/web02/2026.05.08         20260510185259724_1
logs/syslog/web02/2026.05.08         20260510185259725_2
logs/syslog/web02/2026.05.08         20260510185259726_3
logs/syslog/web02/2026.05.08         20260510185259726_4
logs/syslog/web02/2026.05.08         20260510185259727_5
logs/syslog/web02/2026.05.08         20260510185259728_6
logs/syslog/web02/2026.05.08         20260510185259728_7
logs/syslog/web02/2026.05.08         20260510185259729_8
logs/syslog/web02/2026.05.08         20260510185259730_10
logs/syslog/web02/2026.05.08         20260510185259730_9
logs/syslog/web02/2026.05.08         20260510185259731_11
logs/syslog/web02/2026.05.08         20260510185259732_12
logs/syslog/web02/2026.05.08         20260510185259733_13
logs/syslog/web02/2026.05.08         20260510185259735_14
logs/syslog/web02/2026.05.08         20260510185259736_15
logs/syslog/web02/2026.05.08         20260510185259737_16
logs/syslog/web02/2026.05.08         20260510185259738_17
logs/syslog/web02/2026.05.08         20260510185259738_18
logs/syslog/web02/2026.05.08         20260510185259740_19
logs/syslog/web02/2026.05.09         20260510185259753_0
logs/syslog/web02/2026.05.09         20260510185259754_1
logs/syslog/web02/2026.05.09         20260510185259754_2
logs/syslog/web02/2026.05.09         20260510185259755_3
logs/syslog/web02/2026.05.09         20260510185259756_4
logs/syslog/web02/2026.05.09         20260510185259756_5
logs/syslog/web02/2026.05.09         20260510185259757_6
logs/syslog/web02/2026.05.09         20260510185259758_7
logs/syslog/web02/2026.05.09         20260510185259758_8
logs/syslog/web02/2026.05.09         20260510185259759_9
logs/syslog/web02/2026.05.09         20260510185259760_10
logs/syslog/web02/2026.05.09         20260510185259760_11
logs/syslog/web02/2026.05.09         20260510185259761_12
logs/syslog/web02/2026.05.09         20260510185259761_13
logs/syslog/web02/2026.05.09         20260510185259762_14
logs/syslog/web02/2026.05.09         20260510185259763_15
logs/syslog/web02/2026.05.09         20260510185259764_16
logs/syslog/web02/2026.05.09         20260510185259765_17
logs/syslog/web02/2026.05.09         20260510185259766_18
logs/syslog/web02/2026.05.09         20260510185259767_19
logs/syslog/web02/2026.05.10         20260510185259771_0
logs/syslog/web02/2026.05.10         20260510185259772_1
logs/syslog/web02/2026.05.10         20260510185259773_2
logs/syslog/web02/2026.05.10         20260510185259773_3
logs/syslog/web02/2026.05.10         20260510185259774_4
logs/syslog/web02/2026.05.10         20260510185259775_5
logs/syslog/web02/2026.05.10         20260510185259775_6
logs/syslog/web02/2026.05.10         20260510185259776_7
logs/syslog/web02/2026.05.10         20260510185259777_8
logs/syslog/web02/2026.05.10         20260510185259778_10
logs/syslog/web02/2026.05.10         20260510185259778_9
logs/syslog/web02/2026.05.10         20260510185259779_11
logs/syslog/web02/2026.05.10         20260510185259780_12
logs/syslog/web02/2026.05.10         20260510185259780_13
logs/syslog/web02/2026.05.10         20260510185259789_14
logs/syslog/web02/2026.05.10         20260510185259790_15
logs/syslog/web02/2026.05.10         20260510185259791_16
logs/syslog/web02/2026.05.10         20260510185259793_17
logs/syslog/web02/2026.05.10         20260510185259793_18
logs/syslog/web02/2026.05.10         20260510185259794_19
logs                                 07249bc2-130f-4d4f-a4f2-e201bcf3f65a
logs                                 0cb0d779-5a19-4dc2-a7f0-024ea493bbf2
logs                                 0e2fa96f-2242-441d-ab80-4ca8f16ed8ef
logs                                 1a0d30e3-b98c-42e6-943d-9e48055b7b1d
logs                                 1a58e979-a5e1-4078-8f73-4364da935d2e
logs                                 1c47deb9-02fa-444e-9707-df7cd8bda2fc
logs                                 1cf9f9c4-0f70-408e-ad5f-8ea15d2d36ef
logs                                 256b9b9e-4a68-4be7-b2ad-3c180bb5382a
logs                                 32b4a27f-bfe8-4484-ad45-025995869088
logs                                 347fd291-f57b-42fa-9cd6-ed02c9122b9a
logs                                 3700ff6e-e6a7-4cd6-8dad-24aca53f7eef
logs                                 385fa0c0-22fe-40bc-b76e-9279224ded93
logs                                 423ee420-d317-4d5b-98c6-04215063d012
logs                                 4247520d-1611-4f9f-89f5-94e84b0211a5
logs                                 4840466d-b361-4040-bb73-6557c6634a7d
logs                                 4b84bf6c-7129-47bc-881c-5090c9893cb4
logs                                 544a0577-9e00-4c2d-9780-a6b71c3ae761
logs                                 577a2b3e-f8e6-4675-b23b-1410820da559
logs                                 58193e04-209f-46b8-845b-6b9b99c4809d
logs                                 5b5edc13-f803-4ae4-83a8-bfce01c3ffac
logs                                 5cf93dc2-9410-450c-b7d6-3a7871160058
logs                                 5ee84a8f-2834-4b74-a324-3d732222ce20
logs                                 6e34e554-9970-4f85-98a7-969dcf861947
logs                                 73b229b0-45f9-417c-a385-0ccd2dedc2d7
logs                                 73fc8fd5-6862-4552-8bda-ea58c245a9db
logs                                 775089de-f6be-488b-8263-35078bd0f449
logs                                 7ce7b45e-6c7e-425c-bcdf-b4a78e403110
logs                                 812879f9-3d75-4355-a93d-f44fdfd540fa
logs                                 83b736a3-c5cf-4808-98e4-f50ef44e7e53
logs                                 873d60dc-a971-4e84-865c-0ceebeea9c80
logs                                 8c5f47d3-1165-496f-b9f7-3658eb2de538
logs                                 8d61201b-f8de-4022-836f-6c028ef42c47
logs                                 9ae738c5-c6aa-4367-8ecf-7338e7c8d964
logs                                 9bad40d0-dd17-4fa5-a8a0-f2cd8b618e65
logs                                 9dc2e1b4-667c-461f-99ff-f225a9fdd51e
logs                                 a32d433a-eb85-458a-adec-e7967088e179
logs                                 a75fcb63-6b57-48df-95fd-c53e03afc2d4
logs                                 add65aa9-ea8e-44f7-8161-e8c310df7beb
logs                                 b0ebd556-3ae0-416f-935f-ecac70f98fed
logs                                 b14024ac-a642-421e-923f-d811c24ba7e8
logs                                 b4466e84-e213-4b2b-828a-4604d7369d6c
logs                                 b4550f8e-b7c9-42f8-aed6-4197b281adf0
logs                                 b793f15c-3ad1-4879-ab21-fe935f9caf44
logs                                 b95bb961-5370-4503-8f69-68e9654ceff4
logs                                 b98f9952-2151-46c1-a64e-c4022abd9119
logs                                 baa77c3e-48dd-41b9-8d08-a658f70172e4
logs                                 be1040ad-1ea6-42d6-828e-8a87bd1323b2
logs                                 bed1012f-0d31-4f75-a372-74c17c78d7a6
logs                                 c186a214-dc71-445c-9ad9-5cfd95fc67e2
logs                                 cc8c6992-3bac-40fd-bd08-a6d2c4f3bf52
logs                                 de573de7-d1bc-4e5d-b537-582542f42ed1
logs                                 e2633f43-e26e-48f6-9a50-12472f4e1ccf
logs                                 e36a050f-af5f-4b97-8f9b-2c6a820d3108
logs                                 e4f14276-a6c1-4cc2-a8bf-712994850151
logs                                 e60bc4f4-779f-4f7a-9872-5fc7d9963105
logs                                 e928f7fe-6cc2-439c-930a-fa65a085ee28
logs                                 f0c01591-936a-4964-a760-613b1a8e6708
logs                                 fb99026a-2526-43d9-8d68-e248e2e4dccb
logs                                 fbf82425-8ba7-49da-9244-f7fb0c93eb0a
logs                                 fe2859d8-6f37-4a0b-8caf-61aab2a60394
match-demo                           A
match-demo                           alpha
match-demo                           B
match-demo                           beta
match-demo                           C
match-demo                           gamma
move-dst                             m-pass
nested                               deep
nested-match                         a
pass                                 mv-key
pass                                 rn-key
special                              my_file_name_test
staff                                Alice
staff                                Bob
staff                                Carol
staff                                Dana
staff                                Eric
staff                                Frank
staff                                Gina
str-test                             long
str-test                             short
team                                 Alice-Backup
team                                 Alice
team                                 Bob
team                                 Carol
team                                 Frank
tmp                                  new-name
tmp-json                             json-new
types                                custom
types                                hash
users                                Alice
users                                Bob
users                                Carol
users                                Dave
users                                external-ref
```

### 6.8 Tree view
---

The -Tree parameter renders your buckets as a visual directory tree. -MaxFiles
limits how many objects are shown per bucket.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -MaxFiles 10
```

.buckets (478 items, 97 KB)
├── archive (1 item, 1 KB)
├── config (3 items, 540 B)
├── demo (2 items, 653 B)
├── dest (1 item, 415 B)
├── events (4 items, 2 KB)
├── final (1 item, 337 B)
├── logs (431 items, 71 KB)
│   ├── eventlog (101 items, 16 KB)
│   │   ├── Application (30 items, 5 KB)
│   │   │   ├── 2026.05.08 (10 items, 2 KB)
│   │   │   ├── 2026.05.09 (10 items, 2 KB)
│   │   │   └── 2026.05.10 (10 items, 2 KB)
│   │   ├── Security (24 items, 4 KB)
│   │   │   ├── 2026.05.08 (8 items, 1 KB)
│   │   │   ├── 2026.05.09 (8 items, 1 KB)
│   │   │   └── 2026.05.10 (8 items, 1 KB)
│   │   └── System (47 items, 8 KB)
│   │       ├── 2026.05.08 (15 items, 2 KB)
│   │       ├── 2026.05.09 (15 items, 2 KB)
│   │       └── 2026.05.10 (17 items, 4 KB)
│   └── syslog (270 items, 40 KB)
│       ├── db01 (30 items, 4 KB)
│       │   ├── 2026.05.08 (10 items, 1 KB)
│       │   ├── 2026.05.09 (10 items, 1 KB)
│       │   └── 2026.05.10 (10 items, 1 KB)
│       ├── lb01 (60 items, 9 KB)
│       │   ├── 2026.05.08 (20 items, 3 KB)
│       │   ├── 2026.05.09 (20 items, 3 KB)
│       │   └── 2026.05.10 (20 items, 3 KB)
│       ├── web01 (120 items, 18 KB)
│       │   ├── 2026.05.08 (40 items, 6 KB)
│       │   ├── 2026.05.09 (40 items, 6 KB)
│       │   └── 2026.05.10 (40 items, 6 KB)
│       └── web02 (60 items, 9 KB)
│           ├── 2026.05.08 (20 items, 3 KB)
│           ├── 2026.05.09 (20 items, 3 KB)
│           └── 2026.05.10 (20 items, 3 KB)
├── match-demo (6 items, 3 KB)
├── move-dst (1 item, 326 B)
├── nested (1 item, 1 KB)
├── nested-match (1 item, 604 B)
├── pass (2 items, 652 B)
├── special (1 item, 337 B)
├── staff (7 items, 7 KB)
├── str-test (2 items, 835 B)
├── team (5 items, 5 KB)
├── tmp (1 item, 333 B)
├── tmp-json (1 item, 20 B)
├── types (2 items, 658 B)
└── users (5 items, 2 KB)

### 6.9 Bucket-only tree
---

Without -Objects, the tree shows buckets only — a clean structural view without
individual objects cluttering the output.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree
```

.buckets (478 items, 97 KB)
├── archive (1 item, 1 KB)
├── config (3 items, 541 B)
├── demo (2 items, 653 B)
├── dest (1 item, 415 B)
├── events (4 items, 2 KB)
├── final (1 item, 337 B)
├── logs (431 items, 71 KB)
│   ├── eventlog (101 items, 16 KB)
│   │   ├── Application (30 items, 5 KB)
│   │   │   ├── 2026.05.08 (10 items, 2 KB)
│   │   │   ├── 2026.05.09 (10 items, 2 KB)
│   │   │   └── 2026.05.10 (10 items, 2 KB)
│   │   ├── Security (24 items, 4 KB)
│   │   │   ├── 2026.05.08 (8 items, 1 KB)
│   │   │   ├── 2026.05.09 (8 items, 1 KB)
│   │   │   └── 2026.05.10 (8 items, 1 KB)
│   │   └── System (47 items, 8 KB)
│   │       ├── 2026.05.08 (15 items, 2 KB)
│   │       ├── 2026.05.09 (15 items, 2 KB)
│   │       └── 2026.05.10 (17 items, 4 KB)
│   └── syslog (270 items, 40 KB)
│       ├── db01 (30 items, 4 KB)
│       │   ├── 2026.05.08 (10 items, 1 KB)
│       │   ├── 2026.05.09 (10 items, 1 KB)
│       │   └── 2026.05.10 (10 items, 1 KB)
│       ├── lb01 (60 items, 9 KB)
│       │   ├── 2026.05.08 (20 items, 3 KB)
│       │   ├── 2026.05.09 (20 items, 3 KB)
│       │   └── 2026.05.10 (20 items, 3 KB)
│       ├── web01 (120 items, 18 KB)
│       │   ├── 2026.05.08 (40 items, 6 KB)
│       │   ├── 2026.05.09 (40 items, 6 KB)
│       │   └── 2026.05.10 (40 items, 6 KB)
│       └── web02 (60 items, 9 KB)
│           ├── 2026.05.08 (20 items, 3 KB)
│           ├── 2026.05.09 (20 items, 3 KB)
│           └── 2026.05.10 (20 items, 3 KB)
├── match-demo (6 items, 3 KB)
├── move-dst (1 item, 326 B)
├── nested (1 item, 1 KB)
├── nested-match (1 item, 604 B)
├── pass (2 items, 652 B)
├── special (1 item, 337 B)
├── staff (7 items, 7 KB)
├── str-test (2 items, 835 B)
├── team (5 items, 6 KB)
├── tmp (1 item, 333 B)
├── tmp-json (1 item, 20 B)
├── types (2 items, 658 B)
└── users (5 items, 2 KB)

### 6.10 Tree with objects
---

Add -Objects to include individual objects in the tree. Every leaf object is
visible.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -Objects
```

.buckets (478 items, 97 KB)
├── archive (1 item, 1 KB)
│   └── Alice
├── config (3 items, 541 B)
│   ├── app-config
│   ├── app-config
│   └── db-settings
├── demo (2 items, 653 B)
│   ├── _ _
│   └── verbosity-demo
├── dest (1 item, 415 B)
│   └── obj1
├── events (4 items, 2 KB)
│   ├── 20260510191323158_0
│   ├── 20260510191323159_1
│   ├── 20260510191324090_0
│   └── 20260510191324104_1
├── final (1 item, 337 B)
│   └── new-key
├── logs (431 items, 71 KB)
│   ├── eventlog (101 items, 16 KB)
│   │   ├── Application (30 items, 5 KB)
│   │   │   ├── 2026.05.08 (10 items, 2 KB)
│   │   │   │   ├── 20260510185259969_0
│   │   │   │   ├── 20260510185259970_1
│   │   │   │   ├── 20260510185259971_2
│   │   │   │   ├── 20260510185259972_3
│   │   │   │   └── 20260510185259972_4
│   │   │   │   └── ... 5 more
│   │   │   ├── 2026.05.09 (10 items, 2 KB)
│   │   │   │   ├── 20260510185300035_0
│   │   │   │   ├── 20260510185300036_1
│   │   │   │   ├── 20260510185300037_2
│   │   │   │   ├── 20260510185300038_3
│   │   │   │   └── 20260510185300039_4
│   │   │   │   └── ... 5 more
│   │   │   └── 2026.05.10 (10 items, 2 KB)
│   │   │       ├── 20260510185300103_0
│   │   │       ├── 20260510185300104_1
│   │   │       ├── 20260510185300104_2
│   │   │       ├── 20260510185300105_3
│   │   │       └── 20260510185300106_4
│   │   │       └── ... 5 more
│   │   ├── Security (24 items, 4 KB)
│   │   │   ├── 2026.05.08 (8 items, 1 KB)
│   │   │   │   ├── 20260510185259978_0
│   │   │   │   ├── 20260510185259979_1
│   │   │   │   ├── 20260510185259981_2
│   │   │   │   ├── 20260510185259984_3
│   │   │   │   └── 20260510185259985_4
│   │   │   │   └── ... 3 more
│   │   │   ├── 2026.05.09 (8 items, 1 KB)
│   │   │   │   ├── 20260510185300051_0
│   │   │   │   ├── 20260510185300052_1
│   │   │   │   ├── 20260510185300053_2
│   │   │   │   ├── 20260510185300053_3
│   │   │   │   └── 20260510185300054_4
│   │   │   │   └── ... 3 more
│   │   │   └── 2026.05.10 (8 items, 1 KB)
│   │   │       ├── 20260510185300114_0
│   │   │       ├── 20260510185300115_1
│   │   │       ├── 20260510185300115_2
│   │   │       ├── 20260510185300116_3
│   │   │       └── 20260510185300117_4
│   │   │       └── ... 3 more
│   │   └── System (47 items, 8 KB)
│   │       ├── 2026.05.08 (15 items, 2 KB)
│   │       │   ├── 20260510185259934_0
│   │       │   ├── 20260510185259935_1
│   │       │   ├── 20260510185259935_2
│   │       │   ├── 20260510185259936_3
│   │       │   └── 20260510185259937_4
│   │       │   └── ... 10 more
│   │       ├── 2026.05.09 (15 items, 2 KB)
│   │       │   ├── 20260510185259992_0
│   │       │   ├── 20260510185259993_1
│   │       │   ├── 20260510185259993_2
│   │       │   ├── 20260510185259994_3
│   │       │   └── 20260510185259995_4
│   │       │   └── ... 10 more
│   │       └── 2026.05.10 (17 items, 4 KB)
│   │           ├── 20260510185300060_0
│   │           ├── 20260510185300061_1
│   │           ├── 20260510185300076_2
│   │           ├── 20260510185300077_3
│   │           └── 20260510185300079_4
│   │           └── ... 12 more
│   ├── syslog (270 items, 40 KB)
│   │   ├── db01 (30 items, 4 KB)
│   │   │   ├── 2026.05.08 (10 items, 1 KB)
│   │   │   │   ├── 20260510185259800_0
│   │   │   │   ├── 20260510185259801_1
│   │   │   │   ├── 20260510185259801_2
│   │   │   │   ├── 20260510185259802_3
│   │   │   │   └── 20260510185259803_4
│   │   │   │   └── ... 5 more
│   │   │   ├── 2026.05.09 (10 items, 1 KB)
│   │   │   │   ├── 20260510185259813_0
│   │   │   │   ├── 20260510185259814_1
│   │   │   │   ├── 20260510185259814_2
│   │   │   │   ├── 20260510185259815_3
│   │   │   │   └── 20260510185259816_4
│   │   │   │   └── ... 5 more
│   │   │   └── 2026.05.10 (10 items, 1 KB)
│   │   │       ├── 20260510185259832_0
│   │   │       ├── 20260510185259833_1
│   │   │       ├── 20260510185259834_2
│   │   │       ├── 20260510185259834_3
│   │   │       └── 20260510185259835_4
│   │   │       └── ... 5 more
│   │   ├── lb01 (60 items, 9 KB)
│   │   │   ├── 2026.05.08 (20 items, 3 KB)
│   │   │   │   ├── 20260510185259843_0
│   │   │   │   ├── 20260510185259843_1
│   │   │   │   ├── 20260510185259844_2
│   │   │   │   ├── 20260510185259846_3
│   │   │   │   └── 20260510185259847_4
│   │   │   │   └── ... 15 more
│   │   │   ├── 2026.05.09 (20 items, 3 KB)
│   │   │   │   ├── 20260510185259872_0
│   │   │   │   ├── 20260510185259873_1
│   │   │   │   ├── 20260510185259873_2
│   │   │   │   ├── 20260510185259875_3
│   │   │   │   └── 20260510185259876_4
│   │   │   │   └── ... 15 more
│   │   │   └── 2026.05.10 (20 items, 3 KB)
│   │   │       ├── 20260510185259899_0
│   │   │       ├── 20260510185259908_1
│   │   │       ├── 20260510185259909_2
│   │   │       ├── 20260510185259912_3
│   │   │       └── 20260510185259912_4
│   │   │       └── ... 15 more
│   │   ├── web01 (120 items, 18 KB)
│   │   │   ├── 2026.05.08 (40 items, 6 KB)
│   │   │   │   ├── 20260510185259555_0
│   │   │   │   ├── 20260510185259556_1
│   │   │   │   ├── 20260510185259557_2
│   │   │   │   ├── 20260510185259558_3
│   │   │   │   └── 20260510185259558_4
│   │   │   │   └── ... 35 more
│   │   │   ├── 2026.05.09 (40 items, 6 KB)
│   │   │   │   ├── 20260510185259596_0
│   │   │   │   ├── 20260510185259596_1
│   │   │   │   ├── 20260510185259597_2
│   │   │   │   ├── 20260510185259598_3
│   │   │   │   └── 20260510185259599_4
│   │   │   │   └── ... 35 more
│   │   │   └── 2026.05.10 (40 items, 6 KB)
│   │   │       ├── 20260510185259680_0
│   │   │       ├── 20260510185259681_1
│   │   │       ├── 20260510185259684_2
│   │   │       ├── 20260510185259685_3
│   │   │       └── 20260510185259686_4
│   │   │       └── ... 35 more
│   │   └── web02 (60 items, 9 KB)
│   │       ├── 2026.05.08 (20 items, 3 KB)
│   │       │   ├── 20260510185259723_0
│   │       │   ├── 20260510185259724_1
│   │       │   ├── 20260510185259725_2
│   │       │   ├── 20260510185259726_3
│   │       │   └── 20260510185259726_4
│   │       │   └── ... 15 more
│   │       ├── 2026.05.09 (20 items, 3 KB)
│   │       │   ├── 20260510185259753_0
│   │       │   ├── 20260510185259754_1
│   │       │   ├── 20260510185259754_2
│   │       │   ├── 20260510185259755_3
│   │       │   └── 20260510185259756_4
│   │       │   └── ... 15 more
│   │       └── 2026.05.10 (20 items, 3 KB)
│   │           ├── 20260510185259771_0
│   │           ├── 20260510185259772_1
│   │           ├── 20260510185259773_2
│   │           ├── 20260510185259773_3
│   │           └── 20260510185259774_4
│   │           └── ... 15 more
│   ├── 07249bc2-130f-4d4f-a4f2-e201bcf3f65a
│   ├── 0cb0d779-5a19-4dc2-a7f0-024ea493bbf2
│   ├── 0e2fa96f-2242-441d-ab80-4ca8f16ed8ef
│   ├── 1a0d30e3-b98c-42e6-943d-9e48055b7b1d
│   └── 1a58e979-a5e1-4078-8f73-4364da935d2e
│   └── ... 55 more
├── match-demo (6 items, 3 KB)
│   ├── A
│   ├── alpha
│   ├── B
│   ├── beta
│   └── C
│   └── ... 1 more
├── move-dst (1 item, 326 B)
│   └── m-pass
├── nested (1 item, 1 KB)
│   └── deep
├── nested-match (1 item, 604 B)
│   └── a
├── pass (2 items, 652 B)
│   ├── mv-key
│   └── rn-key
├── special (1 item, 337 B)
│   └── my_file_name_test
├── staff (7 items, 7 KB)
│   ├── Alice
│   ├── Bob
│   ├── Carol
│   ├── Dana
│   └── Eric
│   └── ... 2 more
├── str-test (2 items, 835 B)
│   ├── long
│   └── short
├── team (5 items, 6 KB)
│   ├── Alice-Backup
│   ├── Alice
│   ├── Bob
│   ├── Carol
│   └── Frank
├── tmp (1 item, 333 B)
│   └── new-name
├── tmp-json (1 item, 20 B)
│   └── json-new
├── types (2 items, 658 B)
│   ├── custom
│   └── hash
└── users (5 items, 2 KB)
  ├── Alice
  ├── Bob
  ├── Carol
  ├── Dave
  └── external-ref

### 6.11 Raw tree output
---

The -Raw switch returns tree objects as pipeable data instead of formatted text.
Useful for further processing or custom display.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -Raw | Select-Object -First 2
```

```

Name        : .buckets
Type        : Root
Path        : 
ObjectCount : 478
SizeBytes   : 99741
Depth       : 0
Children    : {@{Name=archive; Type=Bucket; Path=archive; ObjectCount=1; SizeBytes=1167; Depth=1; Children=System.Collections.ArrayList; _BucketName=archive; _BucketKey=}, @{Name=config; Type=Bucket; Path=config; ObjectCount=3; SizeBytes=541; Depth=1; Children=System.Collections.ArrayList; _BucketName=config; _BucketKey=}, @{Name=demo; Type=Bucket; Path=demo; ObjectCount=2; SizeBytes=653; Depth=1; Children=System.Collections.ArrayList; _BucketName=demo; _BucketKey=}, @{Name=dest; Type=Bucket; Path=dest; ObjectCount=1; SizeBytes=415; Depth=1; Children=System.Collections.ArrayList; _BucketName=dest; _BucketKey=}…}
_BucketName : 
_BucketKey  :
```

### 6.12 Depth-limited tree
---

-Depth limits how many levels of nesting the tree traverses. Depth 1 shows
only top-level buckets.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -Depth 1
```

.buckets (478 items, 97 KB)

### 6.13 Tree to JSON
---

Pipe Raw tree output to ConvertTo-Json for a structured JSON representation of
your bucket hierarchy.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -Raw | ConvertTo-Json -Depth 5 | Select-Object -First 5
```

```
{
"Name": ".buckets",
"Type": "Root",
"Path": "",
"ObjectCount": 478,
"SizeBytes": 99741,
"Depth": 0,
"Children": [
  {
    "Name": "archive",
    "Type": "Bucket",
    "Path": "archive",
    "ObjectCount": 1,
    "SizeBytes": 1167,
    "Depth": 1,
    "Children": [],
    "_BucketName": "archive",
    "_BucketKey": ""
  },
  {
    "Name": "config",
    "Type": "Bucket",
    "Path": "config",
    "ObjectCount": 3,
    "SizeBytes": 541,
    "Depth": 1,
    "Children": [],
    "_BucketName": "config",
    "_BucketKey": ""
  },
  {
    "Name": "demo",
    "Type": "Bucket",
    "Path": "demo",
    "ObjectCount": 2,
    "SizeBytes": 653,
    "Depth": 1,
    "Children": [],
    "_BucketName": "demo",
    "_BucketKey": ""
  },
  {
    "Name": "dest",
    "Type": "Bucket",
    "Path": "dest",
    "ObjectCount": 1,
    "SizeBytes": 415,
    "Depth": 1,
    "Children": [],
    "_BucketName": "dest",
    "_BucketKey": ""
  },
  {
    "Name": "events",
    "Type": "Bucket",
    "Path": "events",
    "ObjectCount": 4,
    "SizeBytes": 1662,
    "Depth": 1,
    "Children": [],
    "_BucketName": "events",
    "_BucketKey": ""
  },
  {
    "Name": "final",
    "Type": "Bucket",
    "Path": "final",
    "ObjectCount": 1,
    "SizeBytes": 337,
    "Depth": 1,
    "Children": [],
    "_BucketName": "final",
    "_BucketKey": ""
  },
  {
    "Name": "logs",
    "Type": "Bucket",
    "Path": "logs",
    "ObjectCount": 431,
    "SizeBytes": 72487,
    "Depth": 1,
    "Children": [
      {
        "Name": "eventlog",
        "Type": "Bucket",
        "Path": "logs/eventlog",
        "ObjectCount": 101,
        "SizeBytes": 16644,
        "Depth": 2,
        "Children": [
          "@{Name=Application; Type=Bucket; Path=logs/eventlog/Application; ObjectCount=30; SizeBytes=4685; Depth=3; Children=System.Collections.ArrayList; _BucketName=logs/eventlog/Application; _BucketKey=}",
          "@{Name=Security; Type=Bucket; Path=logs/eventlog/Security; ObjectCount=24; SizeBytes=3664; Depth=3; Children=System.Collections.ArrayList; _BucketName=logs/eventlog/Security; _BucketKey=}",
          "@{Name=System; Type=Bucket; Path=logs/eventlog/System; ObjectCount=47; SizeBytes=8295; Depth=3; Children=System.Collections.ArrayList; _BucketName=logs/eventlog/System; _BucketKey=}"
        ],
        "_BucketName": "logs/eventlog",
        "_BucketKey": ""
      },
      {
        "Name": "syslog",
        "Type": "Bucket",
        "Path": "logs/syslog",
        "ObjectCount": 270,
        "SizeBytes": 41075,
        "Depth": 2,
        "Children": [
          "@{Name=db01; Type=Bucket; Path=logs/syslog/db01; ObjectCount=30; SizeBytes=4503; Depth=3; Children=System.Collections.ArrayList; _BucketName=logs/syslog/db01; _BucketKey=}",
          "@{Name=lb01; Type=Bucket; Path=logs/syslog/lb01; ObjectCount=60; SizeBytes=9115; Depth=3; Children=System.Collections.ArrayList; _BucketName=logs/syslog/lb01; _BucketKey=}",
          "@{Name=web01; Type=Bucket; Path=logs/syslog/web01; ObjectCount=120; SizeBytes=18351; Depth=3; Children=System.Collections.ArrayList; _BucketName=logs/syslog/web01; _BucketKey=}",
          "@{Name=web02; Type=Bucket; Path=logs/syslog/web02; ObjectCount=60; SizeBytes=9106; Depth=3; Children=System.Collections.ArrayList; _BucketName=logs/syslog/web02; _BucketKey=}"
        ],
        "_BucketName": "logs/syslog",
        "_BucketKey": ""
      }
    ],
    "_BucketName": "logs",
    "_BucketKey": ""
  },
  {
    "Name": "match-demo",
    "Type": "Bucket",
    "Path": "match-demo",
    "ObjectCount": 6,
    "SizeBytes": 2741,
    "Depth": 1,
    "Children": [],
    "_BucketName": "match-demo",
    "_BucketKey": ""
  },
  {
    "Name": "move-dst",
    "Type": "Bucket",
    "Path": "move-dst",
    "ObjectCount": 1,
    "SizeBytes": 326,
    "Depth": 1,
    "Children": [],
    "_BucketName": "move-dst",
    "_BucketKey": ""
  },
  {
    "Name": "nested",
    "Type": "Bucket",
    "Path": "nested",
    "ObjectCount": 1,
    "SizeBytes": 1039,
    "Depth": 1,
    "Children": [],
    "_BucketName": "nested",
    "_BucketKey": ""
  },
  {
    "Name": "nested-match",
    "Type": "Bucket",
    "Path": "nested-match",
    "ObjectCount": 1,
    "SizeBytes": 604,
    "Depth": 1,
    "Children": [],
    "_BucketName": "nested-match",
    "_BucketKey": ""
  },
  {
    "Name": "pass",
    "Type": "Bucket",
    "Path": "pass",
    "ObjectCount": 2,
    "SizeBytes": 652,
    "Depth": 1,
    "Children": [],
    "_BucketName": "pass",
    "_BucketKey": ""
  },
  {
    "Name": "special",
    "Type": "Bucket",
    "Path": "special",
    "ObjectCount": 1,
    "SizeBytes": 337,
    "Depth": 1,
    "Children": [],
    "_BucketName": "special",
    "_BucketKey": ""
  },
  {
    "Name": "staff",
    "Type": "Bucket",
    "Path": "staff",
    "ObjectCount": 7,
    "SizeBytes": 6685,
    "Depth": 1,
    "Children": [],
    "_BucketName": "staff",
    "_BucketKey": ""
  },
  {
    "Name": "str-test",
    "Type": "Bucket",
    "Path": "str-test",
    "ObjectCount": 2,
    "SizeBytes": 835,
    "Depth": 1,
    "Children": [],
    "_BucketName": "str-test",
    "_BucketKey": ""
  },
  {
    "Name": "team",
    "Type": "Bucket",
    "Path": "team",
    "ObjectCount": 5,
    "SizeBytes": 5820,
    "Depth": 1,
    "Children": [],
    "_BucketName": "team",
    "_BucketKey": ""
  },
  {
    "Name": "tmp",
    "Type": "Bucket",
    "Path": "tmp",
    "ObjectCount": 1,
    "SizeBytes": 333,
    "Depth": 1,
    "Children": [],
    "_BucketName": "tmp",
    "_BucketKey": ""
  },
  {
    "Name": "tmp-json",
    "Type": "Bucket",
    "Path": "tmp-json",
    "ObjectCount": 1,
    "SizeBytes": 20,
    "Depth": 1,
    "Children": [],
    "_BucketName": "tmp-json",
    "_BucketKey": ""
  },
  {
    "Name": "types",
    "Type": "Bucket",
    "Path": "types",
    "ObjectCount": 2,
    "SizeBytes": 658,
    "Depth": 1,
    "Children": [],
    "_BucketName": "types",
    "_BucketKey": ""
  },
  {
    "Name": "users",
    "Type": "Bucket",
    "Path": "users",
    "ObjectCount": 5,
    "SizeBytes": 2429,
    "Depth": 1,
    "Children": [],
    "_BucketName": "users",
    "_BucketKey": ""
  }
],
"_BucketName": "",
"_BucketKey": ""
}
```

### 6.14 Clean summary table
---

Select Name and ObjectCount from dip for a clean table of buckets with their
object counts.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
dip | Select-Object Name, ObjectCount
```

```

Name         ObjectCount
----         -----------
archive                1
config                 3
demo                   2
dest                   1
events                 4
final                  1
logs                 431
match-demo             6
move-dst               1
move-src               0
nested                 1
nested-match           1
origin                 0
pass                   2
source                 0
special                1
staff                  7
str-test               2
team                   5
temp                   0
tmp                    1
tmp-json               1
types                  2
users                  5
```

## 6a. Remove-Bucket — safety and wildcards
---

### 6a.1 Preview removal
---

-WhatIf previews what would be removed without actually deleting anything.


```powershell
Remove-Bucket "team" -WhatIf
```


What if: Remove the following bucket(s)
  team (5 objects, 5.68 KB)


### 6a.2 Wildcard preview
---

Wildcard patterns work too. Preview removing all buckets matching a pattern.


```powershell
Remove-Bucket "t*" -WhatIf
```


What if: Remove the following bucket(s)
  team (5 objects, 5.68 KB)
  temp (0 objects, 0 KB)
  tmp (1 object, 0.33 KB)
  tmp-json (1 object, 0.02 KB)
  types (2 objects, 0.64 KB)


### 6a.3 Remove a single bucket
---

Remove a single bucket. Make sure it contains only bucket object files — Buckets
refuses to remove directories with other file types.


```powershell
$tmp = @{ A = 1 }
$tmp | fill -Bucket temp-remove -Key "x" -Quiet
Remove-Bucket temp-remove -Force -Confirm:$false
```

temp-remove · 1 object removed

### 6a.4 Safety check on removal
---

Safety first: Remove-Bucket checks that a directory contains only bucket files.
If it finds unexpected file types (like .exe), it skips the directory with a
warning rather than deleting it.


```powershell
$badDir = Join-Path (Get-BucketRoot) "not-a-bucket"
$null = New-Item -ItemType Directory -Path $badDir -Force
Set-Content -Path (Join-Path $badDir "evil.exe") -Value "x" -NoNewline
Remove-Bucket "not-a-bucket" -Force -Confirm:$false -WarningAction SilentlyContinue 2>$null
Remove-Item $badDir -Recurse -Force -ErrorAction SilentlyContinue
```

not-a-bucket · contains 1 non-bucket file(s): evil.exe

## 7. Export / Import — Export-Bucket, Import-Bucket
---


### 7.1 Export to CLIXML
---

Export saves an entire bucket to an archive file. CLIXML (the default) preserves
.NET type information for perfect round-trip fidelity.


```powershell
Export-Bucket -Bucket team -OutputFile (Join-Path $exportDir "team.clixml") -Quiet
```


### 7.2 Export to JSON
---

Export to JSON for human-readable archives. Same data, different format —
useful when you need to inspect or share the data outside of PowerShell.


```powershell
Export-Bucket -Bucket team -OutputFile (Join-Path $exportDir "team.json") -AsJson -Quiet
```


### 7.3 Wildcard export
---

Wildcards work for batch exports. Export multiple buckets that match a pattern
into a single archive file.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Export-Bucket -Bucket "t*","config" -OutputFile (Join-Path $exportDir "multi-export.clixml") -Quiet
```


### 7.4 Import from CLIXML
---

Import restores from a CLIXML archive into a new bucket. Objects are recreated
with their original keys and data.


```powershell
Import-Bucket -Bucket restored -InputFile (Join-Path $exportDir "team.clixml") -Quiet
```


### 7.5 Import from JSON
---

Import from JSON works the same way. The JSON file is parsed and each object
is stored in the specified bucket.


```powershell
Import-Bucket -Bucket restored-json -InputFile (Join-Path $exportDir "team.json") -AsJson -Quiet
```


### 7.6 Overwrite on import
---

-Overwrite on import replaces existing keys instead of skipping them. With
-Overwrite, a second import doesn't create duplicates.


```powershell
Import-Bucket -Bucket import-over -InputFile (Join-Path $exportDir "team.clixml") -Quiet
Import-Bucket -Bucket import-over -InputFile (Join-Path $exportDir "team.clixml") -Overwrite -Quiet
```


### 7.7 Inspecting JSON archives
---

JSON archives are plain text. Open them in any editor to inspect or modify
before importing.


```powershell
Get-Content (Join-Path $exportDir "team.json") -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 5 | Select-Object -First 3
```

```
[
{
  "Role": "Developer",
  "Name": "Alice",
  "Joined": "2025-05-10T19:13:23.4575364+02:00",
  "Active": true,
  "Skills": [
    "PowerShell",
    "C#",
    "Azure"
  ],
  "Level": 3,
  "Score": 95
},
{
  "Role": "Developer",
  "Name": "Alice",
  "Joined": "2025-05-10T19:13:23.4575364+02:00",
  "Active": true,
  "Skills": [
    "PowerShell",
    "C#",
    "Azure"
  ],
  "Level": 3,
  "Score": 95
},
{
  "Role": "Designer",
  "Name": "Bob",
  "Joined": "2025-11-11T19:13:23.4604761+01:00",
  "Active": true,
  "Skills": [
    "Figma",
    "CSS",
    "HTML"
  ],
  "Level": 2,
  "Score": 72
},
{
  "Role": "PM",
  "Name": "Carol",
  "Joined": "2026-02-09T19:13:23.4606118+01:00",
  "Active": true,
  "Skills": [
    "Agile",
    "Jira",
    "Confluence"
  ],
  "Level": 3,
  "Score": 88
},
{
  "Role": "Developer",
  "Name": "Frank",
  "Joined": "2024-12-26T19:13:23.460695+01:00",
  "Active": true,
  "Skills": [
    "Rust",
    "Go",
    "Kubernetes"
  ],
  "Level": 4,
  "Score": 91
}
]
```

## 8. PSDrive — navigate buckets like a filesystem
---

### 8.1 The buckets: drive
---

Buckets registers a custom PSDrive called "buckets:". You can navigate it with
cd, Get-ChildItem, Get-Content — just like any other drive.


```powershell
Get-PSDrive -Name buckets
```

```

Name           Used (GB)     Free (GB) Provider      Root                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        CurrentLocation
----           ---------     --------- --------      ----                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ---------------
buckets                                Buckets       buckets:\
```

### 8.2 Listing buckets
---

List all buckets with Get-ChildItem on the drive root. Each bucket appears as
a container (directory).


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-ChildItem "buckets:\"
```

```

Type  LastWriteTime             CreationTime                      Size Name
----  -------------             ------------                      ---- ----
b--   10.05.2026 19:13:25       10.05.2026 19:13:25               1 KB archive
b--   10.05.2026 19:13:24       10.05.2026 19:13:23              541 B config
b--   10.05.2026 19:13:23       10.05.2026 19:13:23              653 B demo
b--   10.05.2026 19:13:25       10.05.2026 19:13:25              415 B dest
b--   10.05.2026 19:13:24       10.05.2026 19:13:23               2 KB events
b--   10.05.2026 19:13:25       10.05.2026 19:13:25              337 B final
b--   10.05.2026 19:13:27       10.05.2026 19:13:27               5 KB import-over
b--   10.05.2026 19:13:24       10.05.2026 18:52:59              71 KB logs
b--   10.05.2026 19:13:24       10.05.2026 19:13:24               3 KB match-demo
b--   10.05.2026 19:13:25       10.05.2026 19:13:25              326 B move-dst
b--   10.05.2026 19:13:25       10.05.2026 19:13:25                0 B move-src
b--   10.05.2026 19:13:23       10.05.2026 19:13:23               1 KB nested
b--   10.05.2026 19:13:24       10.05.2026 19:13:24              604 B nested-match
b--   10.05.2026 19:13:25       10.05.2026 19:13:25                0 B origin
b--   10.05.2026 19:13:25       10.05.2026 19:13:25              652 B pass
b--   10.05.2026 19:13:27       10.05.2026 19:13:27               5 KB restored
b--   10.05.2026 19:13:27       10.05.2026 19:13:27               4 KB restored-json
b--   10.05.2026 19:13:25       10.05.2026 19:13:25                0 B source
b--   10.05.2026 19:13:23       10.05.2026 19:13:23              337 B special
b--   10.05.2026 19:13:25       10.05.2026 19:13:23               7 KB staff
b--   10.05.2026 19:13:24       10.05.2026 19:13:24              835 B str-test
b--   10.05.2026 19:13:25       10.05.2026 19:13:23               6 KB team
b--   10.05.2026 19:13:25       10.05.2026 19:13:25                0 B temp
b--   10.05.2026 19:13:25       10.05.2026 19:13:25              333 B tmp
b--   10.05.2026 19:13:25       10.05.2026 19:13:25               20 B tmp-json
b--   10.05.2026 19:13:23       10.05.2026 19:13:23              658 B types
b--   10.05.2026 19:13:23       10.05.2026 19:13:23               2 KB users
```

### 8.3 Formatting bucket output
---

Format the output with Select-Object for a cleaner table of bucket names,
sizes, and timestamps.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-ChildItem "buckets:\" | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
```

```

Name          Length LastWriteTime
----          ------ -------------
archive              10.05.2026 19:13:25
config               10.05.2026 19:13:24
demo                 10.05.2026 19:13:23
dest                 10.05.2026 19:13:25
events               10.05.2026 19:13:24
final                10.05.2026 19:13:25
import-over          10.05.2026 19:13:27
logs                 10.05.2026 19:13:24
match-demo           10.05.2026 19:13:24
move-dst             10.05.2026 19:13:25
move-src             10.05.2026 19:13:25
nested               10.05.2026 19:13:23
nested-match         10.05.2026 19:13:24
origin               10.05.2026 19:13:25
pass                 10.05.2026 19:13:25
restored             10.05.2026 19:13:27
restored-json        10.05.2026 19:13:27
source               10.05.2026 19:13:25
special              10.05.2026 19:13:23
staff                10.05.2026 19:13:25
str-test             10.05.2026 19:13:24
team                 10.05.2026 19:13:25
temp                 10.05.2026 19:13:25
tmp                  10.05.2026 19:13:25
tmp-json             10.05.2026 19:13:25
types                10.05.2026 19:13:23
users                10.05.2026 19:13:23
```

### 8.4 Browsing objects in a bucket
---

Enter a bucket and list its objects. Each stored object appears as a file in
the PSDrive.


```powershell
Get-ChildItem "buckets:\team" | Select-Object Name, Length, LastWriteTime
```

```

Name         Length LastWriteTime
----         ------ -------------
Alice-Backup        10.05.2026 19:13:25
Alice               10.05.2026 19:13:25
Bob                 10.05.2026 19:13:25
Carol               10.05.2026 19:13:25
Frank               10.05.2026 19:13:25
```

### 8.5 Filtering containers
---

Filter by PSIsContainer to see only buckets (containers) or only leaf objects.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-ChildItem "buckets:\" | Where-Object { $_.PSIsContainer }
```

```

Type  LastWriteTime             CreationTime                      Size Name
----  -------------             ------------                      ---- ----
b--   10.05.2026 19:13:25       10.05.2026 19:13:25               1 KB archive
b--   10.05.2026 19:13:24       10.05.2026 19:13:23              541 B config
b--   10.05.2026 19:13:23       10.05.2026 19:13:23              653 B demo
b--   10.05.2026 19:13:25       10.05.2026 19:13:25              415 B dest
b--   10.05.2026 19:13:24       10.05.2026 19:13:23               2 KB events
b--   10.05.2026 19:13:25       10.05.2026 19:13:25              337 B final
b--   10.05.2026 19:13:27       10.05.2026 19:13:27               5 KB import-over
b--   10.05.2026 19:13:24       10.05.2026 18:52:59              71 KB logs
b--   10.05.2026 19:13:24       10.05.2026 19:13:24               3 KB match-demo
b--   10.05.2026 19:13:25       10.05.2026 19:13:25              326 B move-dst
b--   10.05.2026 19:13:25       10.05.2026 19:13:25                0 B move-src
b--   10.05.2026 19:13:23       10.05.2026 19:13:23               1 KB nested
b--   10.05.2026 19:13:24       10.05.2026 19:13:24              604 B nested-match
b--   10.05.2026 19:13:25       10.05.2026 19:13:25                0 B origin
b--   10.05.2026 19:13:25       10.05.2026 19:13:25              652 B pass
b--   10.05.2026 19:13:27       10.05.2026 19:13:27               5 KB restored
b--   10.05.2026 19:13:27       10.05.2026 19:13:27               4 KB restored-json
b--   10.05.2026 19:13:25       10.05.2026 19:13:25                0 B source
b--   10.05.2026 19:13:23       10.05.2026 19:13:23              337 B special
b--   10.05.2026 19:13:25       10.05.2026 19:13:23               7 KB staff
b--   10.05.2026 19:13:24       10.05.2026 19:13:24              835 B str-test
b--   10.05.2026 19:13:25       10.05.2026 19:13:23               6 KB team
b--   10.05.2026 19:13:25       10.05.2026 19:13:25                0 B temp
b--   10.05.2026 19:13:25       10.05.2026 19:13:25              333 B tmp
b--   10.05.2026 19:13:25       10.05.2026 19:13:25               20 B tmp-json
b--   10.05.2026 19:13:23       10.05.2026 19:13:23              658 B types
b--   10.05.2026 19:13:23       10.05.2026 19:13:23               2 KB users
```

### 8.6 Reading objects
---

Read an object with Get-Content (or cat). It deserializes the stored data back
into a live PowerShell object — no manual parsing needed.


```powershell
Get-Content "buckets:\team\Alice" | Select-Object Name, Role, Score
```

```

Name  Role      Score
----  ----      -----
Alice Developer    95
```

### 8.7 Round-trip: read, modify, write
---

The full round-trip in the PSDrive: read with Get-Content, modify the property,
write back with Set-Content. Works just like a file but with live objects.


```powershell
$obj = Get-Content "buckets:\team\Carol"
$obj.Score = 95
$obj | Set-Content "buckets:\team\Carol"
```


### 8.8 Removing objects
---

Remove-Item works in the PSDrive too. Delete an object by its path.


```powershell
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "psdrive-remove-test" -Quiet
Remove-Item "buckets:\team\psdrive-remove-test" -Force
```


### 8.9 Testing existence
---

Test-Path checks whether an object exists in the drive. Useful for conditional
logic.


```powershell
Test-Path "buckets:\team\Alice"
Test-Path "buckets:\team\NonExistent"
```


### 8.10 Copying objects
---

Copy-Item works across buckets in the PSDrive. Copy objects from one bucket
to another using familiar filesystem commands.


```powershell
Copy-Item "buckets:\team\Alice" "buckets:\team\Alice-pscopy" -Force
Remove-BucketObject -Bucket team -Key "Alice-pscopy" -Quiet
```


### 8.11 Tab completion
---

Tab completion works throughout the PSDrive. Try typing "buckets:\" and pressing
Tab — it completes bucket names and object keys.

## 9. Nested Buckets — directory hierarchy
---

### 9.1 Creating nested buckets
---

Bucket names with forward slashes create nested directory structures on disk.
This is how you organize data hierarchically — like folders within folders,
each level a real subdirectory.


```powershell
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
```


### 9.2 Wildcards in nested paths
---

Wildcards work in nested paths. "org/eu/*/cities" matches city buckets under
any EU country — Germany, UK, and so on.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
spill -Bucket "org/eu/*/cities"
```

```

Name       Population Country
----       ---------- -------
Berlin        3600000 DE
Munich        1500000 DE
London        8900000 UK
Manchester     550000 UK
```

### 9.3 Querying nested buckets directly
---

Query a nested path directly by its full bucket name. Same spill command,
just a deeper path.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
spill -Bucket "org/eu/de/cities"
```

```

Name   Population Country
----   ---------- -------
Berlin    3600000 DE
Munich    1500000 DE
```

### 9.4 Multi-level wildcards
---

Wildcards at multiple levels for deep queries. "org/*/de/*" matches anything
under any country's "de" sub-bucket.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
spill -Bucket "org/*/de/*"
```

```

Name   Population Country
----   ---------- -------
Berlin    3600000 DE
Munich    1500000 DE
                

```

### 9.5 Recursive bucket listing
---

Get-Bucket with -Recurse shows the full nested structure. It traverses all
sub-buckets recursively.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-Bucket -Name "org" -Recurse
```

```

Name             ObjectCount HasSubBuckets
----             ----------- -------------
org/eu/de/cities           2         False
org/eu/de/depts            2         False
org/eu/de                  0          True
org/eu/uk/cities           2         False
org/eu/uk                  0          True
org/eu                     0          True
org/us/cities              1         False
org/us                     0          True
org                        0          True
```

### 9.6 Tree view of nested buckets
---

Tree view visualizes the nesting hierarchy. Each level is indented, making
it easy to see the organizational structure at a glance.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-Bucket -Name "org" -Tree -Objects -MaxFiles 10
```

.buckets (500 items, 114 KB)
└── org (7 items, 3 KB)
  ├── eu (6 items, 3 KB)
  │   ├── de (4 items, 2 KB)
  │   │   ├── cities (2 items, 1 KB)
  │   │   │   ├── Berlin
  │   │   │   └── Munich
  │   │   └── depts (2 items, 838 B)
  │   │       ├── Engineering
  │   │       └── Marketing
  │   └── uk (2 items, 1 KB)
  │       └── cities (2 items, 1 KB)
  │           ├── London
  │           └── Manchester
  └── us (1 item, 516 B)
      └── cities (1 item, 516 B)
          └── New York

### 9.7 PSDrive with nested paths
---

PSDrive supports nested paths too. Navigate into org/eu/de/cities with
Get-ChildItem just like you would with a filesystem path.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-ChildItem "buckets:\org\eu\de\cities" | Select-Object Name
```

```

Name
----
Berlin
Munich
```

### 9.8 Recursive PSDrive listing
---

Recursive listing in PSDrive with the -Recurse flag. Shows everything under
the org tree.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-ChildItem "buckets:\org" -Recurse | Select-Object Name | Format-Table -AutoSize
```

```

Name
----
eu
de
cities
Berlin
Munich
depts
Engineering
Marketing
uk
cities
London
Manchester
us
cities
New York
```

### 9.9 Stats on nested buckets
---

Stats work on nested buckets too. Get-BucketStats handles the full path.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-BucketStats -Bucket "org/eu/de/cities"
```

```

Name         : org/eu/de/cities
Path         : C:\Users\berfelde\.buckets\org\eu\de\cities
ObjectCount  : 2
TotalSize    : 1 KB
OldestObject : 10.05.2026 19:13:27
NewestObject : 10.05.2026 19:13:27
```

### 9.10 Keys on nested buckets
---

List keys in a nested bucket with Get-BucketKeys. Same command, just a
deeper bucket path.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-BucketKeys -Bucket "org/eu/de/cities"
```

```

Bucket           Key
------           ---
org/eu/de/cities Berlin
org/eu/de/cities Munich
```

### 9.11 Cross-bucket filtering with wildcards
---

Combine wildcards with -Filter for cross-bucket queries in nested hierarchies.
Find all cities with population over 2 million across any country.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
spill -Bucket "org/*/cities" -Filter { $_.Population -gt 2000000 }
```

```

Name     Population Country
----     ---------- -------
Berlin      3600000 DE
London      8900000 UK
New York    8300000 US
```

### 9.12 Removing nested trees
---

Remove-Bucket with -Recurse deletes an entire nested tree. A single command
removes org and everything under it.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Remove-Bucket "org" -Recurse -Force -Confirm:$false
```

org · 0 objects removed

## 10. Sleek Pipeline Patterns
---

### 10.1 Generate and fill
---

Buckets is designed for pipeline-first usage. Most cmdlets accept pipeline
input and emit objects with metadata. Here's how to chain them together.


```powershell
1..5 | ForEach-Object { @{ Name = "item-$_"; Value = $_ * 10 } } |
  fill -Bucket "dir-listing" -KeyProperty Name -Quiet
```


### 10.2 Chain filter, modify, save
---

Chain multiple operations in one pipeline: filter objects with -Filter, modify
them with ForEach-Object, and save back with Set-BucketObject. All in one flow.


```powershell
spill -Bucket team -Filter { $_.Role -eq "Developer" } |
  ForEach-Object { $_.Score = $_.Score + 5; $_ } |
  Set-BucketObject -PassThru
```

```

Bucket Key
------ ---
team   Alice-Backup
team   Alice
team   Frank
```

### 10.3 Filter, sort, project
---

Filter, sort, and project in one pipeline. Where-Object filters, Sort-Object
orders, Select-Object picks the properties you want.


```powershell
spill -Bucket team | Where-Object { $_.Score -gt 80 } |
  Sort-Object Score -Descending |
  Select-Object Name, Role, Score
```

```

Name  Role      Score
----  ----      -----
Alice Developer   100
Alice Developer   100
Frank Developer    96
Carol PM           95
```

### 10.4 Cross-bucket iteration
---

Cross-bucket query: iterate over multiple buckets and filter each one, then
project the results with bucket metadata included.


```powershell
@{ Name = "HighScore"; Score = 90 } | fill -Bucket config -Key "app-config"
@{ Name = "DemoItem"; Score = 85 } | fill -Bucket demo -Key "demo-score"
$buckets = @("team", "config", "demo")
$buckets | ForEach-Object { spill -Bucket $_ -Filter { $_.Score -gt 80 } } |
  Select-Object _BucketName, Name, Score
```

```

_BucketName Name      Score
----------- ----      -----
team        Alice       100
team        Alice       100
team        Carol        95
team        Frank        96
config      HighScore    90
demo        DemoItem     85
```

### 10.5 Group by bucket
---

Group by bucket name to see how objects are distributed across your buckets.


```powershell
@{ Name = "HighScore"; Score = 90 } | fill -Bucket config -Key "app-config"
spill | Group-Object _BucketName | Select-Object Name, Count
```

```

Name          Count
----          -----
2026.05.08      123
2026.05.09      123
2026.05.10      125
archive           1
config            3
demo              3
dest              1
dir-listing       5
events            4
final             1
import-over       5
logs             60
match-demo        6
move-dst          1
nested            1
nested-match      1
pass              2
restored          5
restored-json     5
special           1
staff             7
str-test          2
team              5
tmp               1
tmp-json          1
types             2
users             5
```

### 10.6 Group by property
---

Group-Object aggregates data within a bucket. Here we count how many team
members have each role.


```powershell
spill -Bucket team | Group-Object Role | Select-Object Name, Count
```

```

Name      Count
----      -----
Designer      1
Developer     3
PM            1
```

### 10.7 Statistics with Measure-Object
---

Measure-Object gives you statistics — average, minimum, maximum — for any
numeric property across your objects.


```powershell
$scores = spill -Bucket team | Measure-Object Score -Average -Minimum -Maximum
Write-Host "    Score stats: avg=$([math]::Round($scores.Average,1)) min=$($scores.Minimum) max=$($scores.Maximum)"
```

  Score stats: avg=92.6 min=72 max=100

### 10.8 Export to CSV
---

Export spilled data to CSV for use in Excel, Python, or any tool that reads
tabular data.


```powershell
$csvPath = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-team.csv"
spill -Bucket team | Select-Object Name, Role, Score | Export-Csv -Path $csvPath -NoTypeInformation
Remove-Item $csvPath -Force -ErrorAction SilentlyContinue
```


### 10.9 Filter comparison
---

-Filter runs inside Buckets (faster), Where-Object runs in the pipeline (more
flexible). Both produce the same result — choose based on your needs.


```powershell
spill -Bucket team -Filter { $_.Score -gt 80 }
spill -Bucket team | Where-Object { $_.Score -gt 80 }
```

```

Role   : Developer
Name   : Alice
Joined : 10.05.2025 19:13:23
Active : True
Skills : {PowerShell, C#, Azure}
Level  : 3
Score  : 100

Role   : Developer
Name   : Alice
Joined : 10.05.2025 19:13:23
Active : True
Skills : {PowerShell, C#, Azure}
Level  : 3
Score  : 100

Score  : 95
Name   : Carol
Joined : 09.02.2026 19:13:23
Active : True
Skills : {Agile, Jira, Confluence}
Level  : 3
Role   : PM

Role   : Developer
Name   : Frank
Joined : 26.12.2024 19:13:23
Active : True
Skills : {Rust, Go, Kubernetes}
Level  : 4
Score  : 96
```
```

Role   : Developer
Name   : Alice
Joined : 10.05.2025 19:13:23
Active : True
Skills : {PowerShell, C#, Azure}
Level  : 3
Score  : 100

Role   : Developer
Name   : Alice
Joined : 10.05.2025 19:13:23
Active : True
Skills : {PowerShell, C#, Azure}
Level  : 3
Score  : 100

Score  : 95
Name   : Carol
Joined : 09.02.2026 19:13:23
Active : True
Skills : {Agile, Jira, Confluence}
Level  : 3
Role   : PM

Role   : Developer
Name   : Frank
Joined : 26.12.2024 19:13:23
Active : True
Skills : {Rust, Go, Kubernetes}
Level  : 4
Score  : 96
```

### 10.10 Custom formatting
---

Custom formatting with ForEach-Object. Transform each object into a formatted
string for display or logging.


```powershell
spill -Bucket team | ForEach-Object {
  "[$($_.Role)] $($_.Name) — Score: $($_.Score)"
}
```

```
[Developer] Alice — Score: 100
[Developer] Alice — Score: 100
[Designer] Bob — Score: 72
[PM] Carol — Score: 95
[Developer] Frank — Score: 96
```

### 10.11 Conditional JSON output
---

Conditional pipeline: filter first, then convert only matching objects to JSON.


```powershell
spill -Bucket team -Filter { $_.Score -gt 80 } | ConvertTo-Json -Depth 5
```

```
[
{
  "Role": "Developer",
  "Name": "Alice",
  "Joined": "2025-05-10T19:13:23.4575364+02:00",
  "Active": true,
  "Skills": [
    "PowerShell",
    "C#",
    "Azure"
  ],
  "Level": 3,
  "Score": 100
},
{
  "Role": "Developer",
  "Name": "Alice",
  "Joined": "2025-05-10T19:13:23.4575364+02:00",
  "Active": true,
  "Skills": [
    "PowerShell",
    "C#",
    "Azure"
  ],
  "Level": 3,
  "Score": 100
},
{
  "Score": 95,
  "Name": "Carol",
  "Joined": "2026-02-09T19:13:23.4606118+01:00",
  "Active": true,
  "Skills": [
    "Agile",
    "Jira",
    "Confluence"
  ],
  "Level": 3,
  "Role": "PM"
},
{
  "Role": "Developer",
  "Name": "Frank",
  "Joined": "2024-12-26T19:13:23.460695+01:00",
  "Active": true,
  "Skills": [
    "Rust",
    "Go",
    "Kubernetes"
  ],
  "Level": 4,
  "Score": 96
}
]
```

### 10.12 Round-trip verification
---

Save then immediately read to verify round-trip integrity. What you write is
exactly what you get back.


```powershell
$tmp = @{ Id = "smoke"; Value = 42 }
$tmp | fill -Bucket smoke-test -KeyProperty Id -Quiet
spill -Bucket smoke-test | Select-Object Id, Value
```

```

Id    Value
--    -----
smoke    42
```

## 11. Aliases & Shortcuts Reference
---

Three aliases are exported by the module:

  fill   = New-BucketObject     — save objects
  spill  = Get-BucketObject     — retrieve objects
  dip    = Get-Bucket            — list buckets

Additional shortcuts:
  ls     = Get-ChildItem         — overridden globally (used in buckets: drive)
  cat    = Get-Content           — built-in, works with buckets: drive

Pipeline parameter binding via metadata:
  _BucketName   → -Bucket   (on Set-BucketObject)
  _BucketKey    → -Key      (on Set-BucketObject)
  _BucketFile   → full path to the stored file


## 12. Sysadmin Scenarios
---


This section teaches Buckets from the ground up using real-world data:
server inventory, incident logs, health reports, and cross-bucket
correlation. Each lesson builds on the last, starting simple and growing
in complexity.


### 12.1 Storing your server inventory
---

The fill alias (short for New-BucketObject) saves objects into named
storage areas called buckets. Here we store our server inventory — each
server record becomes an object keyed by its hostname via -KeyProperty.
The -Quiet switch suppresses the summary output.


```powershell
$script:Servers | fill -Bucket servers -KeyProperty Hostname -Quiet
```


### 12.2 Finding unhealthy servers
---

The spill alias (short for Get-BucketObject) retrieves stored objects.
-Filter takes a scriptblock to match conditions — like Where-Object.
Find servers that aren't fully online: -ne means "not equal".


```powershell
spill -Bucket servers -Filter { $_.Status -ne "online" }
```

```

Hostname : app-01
Status   : offline
RAM      : 16
CPU      : 8
Disk     : 200
Location : DC2
Role     : app
OS       : Rocky 9
IP       : 10.0.2.50

Hostname : db-02
Status   : degraded
RAM      : 32
CPU      : 8
Disk     : 500
Location : DC2
Role     : database
OS       : Debian 12
IP       : 10.0.2.20
```

### 12.3 Targeting servers by role and specs
---

Combine two conditions in a single -Filter scriptblock with -and. Find
database servers that have at least 16 GB RAM — ideal for identifying
hosts that can handle a specific workload.


```powershell
spill -Bucket servers -Filter { $_.RAM -ge 16 -and $_.Role -eq "database" }
```

```

Hostname : db-01
Status   : online
RAM      : 32
CPU      : 8
Disk     : 500
Location : DC1
Role     : database
OS       : Debian 12
IP       : 10.0.1.20

Hostname : db-02
Status   : degraded
RAM      : 32
CPU      : 8
Disk     : 500
Location : DC2
Role     : database
OS       : Debian 12
IP       : 10.0.2.20
```

### 12.4 Grouping servers by datacenter
---

Group-Object is your friend for datacenter inventory. Group servers by
their Location property to see how many hosts live in each DC.


```powershell
spill -Bucket servers | Group-Object Location
```

```

Count Name                      Group
----- ----                      -----
  5 DC1                       {@{Hostname=backup-01; Status=online; RAM=8; CPU=4; Disk=2000; Location=DC1; Role=backup; OS=FreeBSD 14; IP=10.0.1.1}, @{Hostname=cache-01; Status=online; RAM=16; CPU=2; Disk=60; Location=DC1; Role=cache; OS=Alpine 3.18; IP=10.0.1.30}, @{Hostname=db-01; Status=online; RAM=32; CPU=8; Disk=500; Location=DC1; Role=database; OS=Debian 12; IP=10.0.1.20}, @{Hostname=web-01; Status=online; RAM=8; CPU=4; Disk=120; Location=DC1; Role=web; OS=Ubuntu 22.04; IP=10.0.1.10}…}
  3 DC2                       {@{Hostname=app-01; Status=offline; RAM=16; CPU=8; Disk=200; Location=DC2; Role=app; OS=Rocky 9; IP=10.0.2.50}, @{Hostname=db-02; Status=degraded; RAM=32; CPU=8; Disk=500; Location=DC2; Role=database; OS=Debian 12; IP=10.0.2.20}, @{Hostname=mon-01; Status=online; RAM=4; CPU=2; Disk=250; Location=DC2; Role=monitoring; OS=Ubuntu 22.04; IP=10.0.1.40}}
```

### 12.5 Capacity planning totals
---

Measure-Object sums up total compute resources across all servers. Handy
for capacity planning — how much CPU, RAM, and disk do you have in total?


```powershell
spill -Bucket servers | Measure-Object CPU, RAM, Disk -Sum
```

```

Count             : 8
Average           : 
Sum               : 40
Maximum           : 
Minimum           : 
StandardDeviation : 
Property          : CPU

Count             : 8
Average           : 
Sum               : 124
Maximum           : 
Minimum           : 
StandardDeviation : 
Property          : RAM

Count             : 8
Average           : 
Sum               : 3750
Maximum           : 
Minimum           : 
StandardDeviation : 
Property          : Disk
```

### 12.6 Logging incidents with timestamps
---

-AsTimestamp gives each incident a unique key based on the current time —
perfect for time-series event logs where you never want a key collision.


```powershell
$script:Incidents | fill -Bucket incidents -AsTimestamp -Quiet
```


### 12.7 Triage critical incidents
---

Focus on what matters: ERROR and CRIT severity levels. The -in operator
inside the -Filter scriptblock matches against multiple values at once.


```powershell
spill -Bucket incidents -Filter { $_.Severity -in @("ERROR","CRIT") }
```

```

Message                   Severity Timestamp           Source
-------                   -------- ---------           ------
Connection pool exhausted ERROR    10.05.2026 17:13:29 web-01
Service unreachable       ERROR    10.05.2026 18:58:29 app-01
Disk /dev/sda1 at 97%     CRIT     10.05.2026 19:08:29 app-01
Connection pool exhausted ERROR    10.05.2026 17:13:29 web-01
Service unreachable       ERROR    10.05.2026 18:58:29 app-01
Disk /dev/sda1 at 97%     CRIT     10.05.2026 19:08:29 app-01
```

### 12.8 Batch maintenance mode
---

Set-BucketObject updates existing objects in place. Spill the web servers,
use Add-Member to attach a Maintenance property (deserialized objects don't
accept dot-property assignment), then pipe through Set-BucketObject to
persist. The summary confirms how many were updated.


```powershell
spill -Bucket servers -Filter { $_.Role -eq "web" } |
  ForEach-Object { $_ | Add-Member Maintenance $true -Force; $_ } |
  Set-BucketObject
```

servers · 2 updated

### 12.9 Health summary report
---

Generate a quick health report: sort servers by status so offline and
degraded machines float to the top. Select only the fields that matter.


```powershell
spill -Bucket servers | Select Hostname, Status, Location | Sort-Object Status
```

```

Hostname  Status   Location
--------  ------   --------
db-02     degraded DC2
app-01    offline  DC2
backup-01 online   DC1
cache-01  online   DC1
db-01     online   DC1
mon-01    online   DC2
web-01    online   DC1
web-02    online   DC1
```

### 12.10 Cross-bucket correlation
---

Cross-bucket queries connect related data. Spill critical incidents from
the incidents bucket, then look up each affected server by hostname with
-Key. This ties your event log to your inventory in one pipeline.


```powershell
$crit = spill -Bucket incidents -Filter { $_.Severity -eq "CRIT" }
$crit | ForEach-Object {
  $svr = spill -Bucket servers -Key $_.Source
  [PSCustomObject]@{ Incident = $_.Message; Server = $svr.Hostname; Status = $svr.Status }
}
```

```

Incident              Server Status
--------              ------ ------
Disk /dev/sda1 at 97% app-01 offline
Disk /dev/sda1 at 97% app-01 offline
Disk /dev/sda1 at 97% app-01 offline
```

Congratulations!
---

You've completed the Buckets tutorial. All tutorial data has been
cleaned up — your system is exactly as it was before we started.



  What you learned:

  fill / spill / dip / toss / drain
                               — save, read, list, delete buckets, delete objects
  -Key / -KeyProperty          — naming objects
  -Overwrite / -AsTimestamp    — replacement and timestamp keys
  -AsJson / -Compress          — storage formats
  -Match (exact)               — hashtable-based filtering
  -Filter (scriptblock)        — expression-based comparison (-gt, -like, -contains, -match)
  Nested property filtering    — .Settings.Enabled with -Filter
  -First / -Skip               — pagination
  Set-BucketObject             — update in place (pipeline + explicit)
  Partial update / patch       — add properties with hashtable pipe
  drain / toss                 — delete objects, delete buckets
  -WhatIf / -PassThru          — safety preview and metadata capture
  Copy / Rename / Move         — object operations with and without pass-through
  PSDrive operations           — Get-Content, Set-Content, Copy-Item, Remove-Item, Test-Path
  Export / Import              — archive & restore with CLIXML and JSON
  Get-Bucket -Tree             — visual tree view with -Objects, -Raw, -Depth
  Get-BucketStats              — bucket statistics
  Get-BucketKeys               — object key listing
  Get-BucketObjectStats        — detailed per-object statistics
  Nested buckets               — org/eu/de/cities hierarchy with wildcards
  Pipeline patterns            — chain, group, measure, export-csv, expand, custom format
  Cross-bucket queries         — -Filter across all buckets
  Edge cases                   —  values, special chars, empty keys, safety guards
  Format preservation          — JSON stays .json, binary stays .dat through Rename/Copy
  Server/event management      — inventory, incidents, health reports, cross-bucket correlation

Learn more: Get-Help <cmdlet> -Full
See also:   README.md, .tests/demo/*.ps1


---

Happy Bucketing!

