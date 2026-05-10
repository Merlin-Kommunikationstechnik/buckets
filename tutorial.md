# Buckets Tutorial


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

Host      Port
----      ----
localhost 5432
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            

```

### 2.2 Filtering by bucket
---

Most of the time you want objects from a specific bucket. Pass -Bucket to narrow
the search to just one bucket.


```powershell
spill -Bucket team
```

```

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95

Level  : 2
Joined : 11.11.2025 16:56:57
Name   : Bob
Role   : Designer
Active : True
Skills : {Figma, CSS, HTML}
Score  : 72

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
Score  : 88

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95

Level  : 2
Joined : 11.11.2025 16:56:57
Name   : Bob
Role   : Designer
Active : True
Skills : {Figma, CSS, HTML}
Score  : 72

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
Score  : 88

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95
```

### 2.5 Exact key retrieval
---

Pass the exact full key name to retrieve just that one object.


```powershell
spill team -Key "Frank"
```

```

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95

Level  : 2
Joined : 11.11.2025 16:56:57
Name   : Bob
Role   : Designer
Active : True
Skills : {Figma, CSS, HTML}
Score  : 72

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
Score  : 88

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95

Level  : 2
Joined : 11.11.2025 16:56:57
Name   : Bob
Role   : Designer
Active : True
Skills : {Figma, CSS, HTML}
Score  : 72

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
Score  : 88

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
Score  : 91

Score  : 70
Level  : 2
Role   : HR
Name   : Dana
Active : True

Score  : 82
Level  : 3
Role   : Finance
Name   : Eric
Active : True

Score  : 65
Level  : 1
Role   : Marketing
Name   : Gina
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95

Level  : 2
Joined : 11.11.2025 16:56:57
Name   : Bob
Role   : Designer
Active : True
Skills : {Figma, CSS, HTML}
Score  : 72

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
Score  : 88

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
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

Name Active Count
---- ------ -----
A      True     5
C      True     5
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
Score  : 88

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
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

Level  : 2
Joined : 11.11.2025 16:56:57
Name   : Bob
Role   : Designer
Active : True
Skills : {Figma, CSS, HTML}
Score  : 72

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
Score  : 91
```

### 2b.6 Combining conditions with -or
---

Combine conditions with -or. Either can be true: role is "Designer" OR level above 3.


```powershell
spill -Bucket team -Filter { $_.Role -eq "Designer" -or $_.Level -gt 3 }
```

```

Level  : 2
Joined : 11.11.2025 16:56:57
Name   : Bob
Role   : Designer
Active : True
Skills : {Figma, CSS, HTML}
Score  : 72

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
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

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
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

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95

Level  : 2
Joined : 11.11.2025 16:56:57
Name   : Bob
Role   : Designer
Active : True
Skills : {Figma, CSS, HTML}
Score  : 72

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
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

Level  : 2
Joined : 11.11.2025 16:56:57
Name   : Bob
Role   : Designer
Active : True
Skills : {Figma, CSS, HTML}
Score  : 72

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
Score  : 88

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95

Level  : 2
Joined : 11.11.2025 16:56:57
Name   : Bob
Role   : Designer
Active : True
Skills : {Figma, CSS, HTML}
Score  : 72

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95
Email  : alice@contoso.com
Phone  : 555-0100
City   : Portland

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
Score  : 100

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95
Email  : alice@contoso.com
Phone  : 555-0100
City   : Portland

Level  : 2
Joined : 11.11.2025 16:56:57
Name   : Bob
Role   : Designer
Active : True
Skills : {Figma, CSS, HTML}
Score  : 72

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
Score  : 100

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 95
Email  : alice@contoso.com
Phone  : 555-0100
City   : Portland

Level  : 2
Joined : 11.11.2025 16:56:57
Name   : Bob
Role   : Designer
Active : True
Skills : {Figma, CSS, HTML}
Score  : 72

Level  : 3
Joined : 09.02.2026 16:56:57
Name   : Carol
Role   : PM
Active : True
Skills : {Agile, Jira, Confluence}
Score  : 100

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
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
events                 2         False
final                  1         False
logs                  30         False
match-demo             6         False
move-dst               1         False
move-src               0         False
nested                 1         False
nested-match           1         False
origin                 0         False
pass                   2         False
source                 0         False
special                1         False
staff                  3         False
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
OldestObject : 10.05.2026 16:56:57
NewestObject : 10.05.2026 16:56:58
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
LastWriteTime : 10.05.2026 16:56:58
IsCompressed  : False

Bucket        : team
Key           : Alice
Format        : Binary
Type          : Object
Size          : 1167
LastWriteTime : 10.05.2026 16:56:58
IsCompressed  : False

Bucket        : team
Key           : Bob
Format        : Binary
Type          : Object
Size          : 1159
LastWriteTime : 10.05.2026 16:56:58
IsCompressed  : False

Bucket        : team
Key           : Carol
Format        : Binary
Type          : Object
Size          : 1162
LastWriteTime : 10.05.2026 16:56:58
IsCompressed  : False

Bucket        : team
Key           : Frank
Format        : Binary
Type          : Object
Size          : 1166
LastWriteTime : 10.05.2026 16:56:58
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

Bucket       Key
------       ---
archive      Alice
config       app-config
config       db-settings
config       app-config
demo         verbosity-demo
demo         _ _
dest         obj1
events       20260510165657296_0
events       20260510165657298_1
final        new-key
logs         0177720e-7501-4e21-b0c2-798357dc2164
logs         033d63a4-6526-432f-a31d-4ad2a316e280
logs         04635bc9-5b35-41bc-a9a6-cac1f8f143bf
logs         0ba82c1d-44e6-4807-816a-cdc0eb61d46d
logs         225a228b-fb59-4c4c-9b8b-d5dfff4edc30
logs         24458b9c-28fe-4934-b1a6-6bca14e82f91
logs         24bb2624-8e7b-4598-bd19-68a5b712d59a
logs         27388a81-b113-4970-92d0-3e5752c96d0a
logs         366df0e7-0906-4c20-b35f-510472fd8017
logs         3d85c456-9442-418f-90c1-42c4510286cc
logs         3f995732-9fc9-4160-abf1-6f805a9b9011
logs         52fb9564-b908-4207-afd5-3d4837533ab4
logs         60446ac0-28e1-48ff-a642-5b113a3d8708
logs         649be16d-cf67-44e8-a45d-ba092d706ac0
logs         736fbb80-7769-4ba1-94df-3ec69eb9c7fe
logs         7657003b-6c1b-469b-b8b9-32702508a36a
logs         794a9f4b-8187-400e-83f3-4b456518b85f
logs         7af80626-5fac-48e6-84b4-07892b0a75b8
logs         914c5b19-c1ba-4bdd-947e-e55bc7cbf302
logs         94bcfd37-3253-47b2-b7b1-3581d6faed7a
logs         9722d6ee-a135-427d-bc2a-7a4c27627d99
logs         a01c71df-2034-4cf7-97a2-2f9797d93da9
logs         acae4ad2-a4c0-48ec-8fa3-e77ed14ee1e1
logs         b45e746c-9d83-4172-baae-353271db5672
logs         b9fea692-67cb-4e29-ad86-73f2d7e09c75
logs         c4864bda-42ea-4c61-ba53-2bc0170e3354
logs         d8c9543b-b2c8-4608-947c-1d494f2ad928
logs         e34738d8-130b-4646-b8d9-b3b30ad403fa
logs         ed823dec-c97f-4016-9f7d-5b6fddfa1ef3
logs         fa647234-1485-4f38-bec5-5917935a1e6d
match-demo   A
match-demo   alpha
match-demo   B
match-demo   beta
match-demo   C
match-demo   gamma
move-dst     m-pass
nested       deep
nested-match a
pass         mv-key
pass         rn-key
special      my_file_name_test
staff        Dana
staff        Eric
staff        Gina
str-test     long
str-test     short
team         Alice-Backup
team         Alice
team         Bob
team         Carol
team         Frank
tmp          new-name
tmp-json     json-new
types        custom
types        hash
users        Alice
users        Bob
users        Carol
users        Dave
users        external-ref
```

### 6.8 Tree view
---

The -Tree parameter renders your buckets as a visual directory tree. -MaxFiles
limits how many objects are shown per bucket.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -MaxFiles 10
```

.buckets (71 items, 29 KB)
├── archive (1 item, 1 KB)
├── config (3 items, 541 B)
├── demo (2 items, 653 B)
├── dest (1 item, 415 B)
├── events (2 items, 831 B)
├── final (1 item, 337 B)
├── logs (30 items, 7 KB)
├── match-demo (6 items, 3 KB)
├── move-dst (1 item, 326 B)
├── nested (1 item, 1 KB)
├── nested-match (1 item, 604 B)
├── pass (2 items, 652 B)
├── special (1 item, 337 B)
├── staff (3 items, 2 KB)
├── str-test (2 items, 835 B)
├── team (5 items, 6 KB)
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

.buckets (71 items, 29 KB)
├── archive (1 item, 1 KB)
├── config (3 items, 541 B)
├── demo (2 items, 653 B)
├── dest (1 item, 415 B)
├── events (2 items, 831 B)
├── final (1 item, 337 B)
├── logs (30 items, 7 KB)
├── match-demo (6 items, 3 KB)
├── move-dst (1 item, 326 B)
├── nested (1 item, 1 KB)
├── nested-match (1 item, 604 B)
├── pass (2 items, 652 B)
├── special (1 item, 337 B)
├── staff (3 items, 2 KB)
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

.buckets (71 items, 29 KB)
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
├── events (2 items, 831 B)
│   ├── 20260510165657296_0
│   └── 20260510165657298_1
├── final (1 item, 337 B)
│   └── new-key
├── logs (30 items, 7 KB)
│   ├── 0177720e-7501-4e21-b0c2-798357dc2164
│   ├── 033d63a4-6526-432f-a31d-4ad2a316e280
│   ├── 04635bc9-5b35-41bc-a9a6-cac1f8f143bf
│   ├── 0ba82c1d-44e6-4807-816a-cdc0eb61d46d
│   └── 225a228b-fb59-4c4c-9b8b-d5dfff4edc30
│   └── ... 25 more
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
├── staff (3 items, 2 KB)
│   ├── Dana
│   ├── Eric
│   └── Gina
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
ObjectCount : 71
SizeBytes   : 29219
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

.buckets (71 items, 29 KB)

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
"ObjectCount": 71,
"SizeBytes": 29219,
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
    "ObjectCount": 2,
    "SizeBytes": 831,
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
    "ObjectCount": 30,
    "SizeBytes": 7448,
    "Depth": 1,
    "Children": [],
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
    "ObjectCount": 3,
    "SizeBytes": 2032,
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
    "SizeBytes": 5821,
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
events                 2
final                  1
logs                  30
match-demo             6
move-dst               1
move-src               0
nested                 1
nested-match           1
origin                 0
pass                   2
source                 0
special                1
staff                  3
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
  "Level": 3,
  "Joined": "2025-05-10T16:56:57.1526371+02:00",
  "Name": "Alice",
  "Role": "Developer",
  "Active": true,
  "Skills": [
    "PowerShell",
    "C#",
    "Azure"
  ],
  "Score": 95
},
{
  "Level": 3,
  "Joined": "2025-05-10T16:56:57.1526371+02:00",
  "Name": "Alice",
  "Role": "Developer",
  "Active": true,
  "Skills": [
    "PowerShell",
    "C#",
    "Azure"
  ],
  "Score": 95
},
{
  "Level": 2,
  "Joined": "2025-11-11T16:56:57.1554808+01:00",
  "Name": "Bob",
  "Role": "Designer",
  "Active": true,
  "Skills": [
    "Figma",
    "CSS",
    "HTML"
  ],
  "Score": 72
},
{
  "Level": 3,
  "Joined": "2026-02-09T16:56:57.1555755+01:00",
  "Name": "Carol",
  "Role": "PM",
  "Active": true,
  "Skills": [
    "Agile",
    "Jira",
    "Confluence"
  ],
  "Score": 88
},
{
  "Level": 4,
  "Joined": "2024-12-26T16:56:57.1556376+01:00",
  "Name": "Frank",
  "Role": "Developer",
  "Active": true,
  "Skills": [
    "Rust",
    "Go",
    "Kubernetes"
  ],
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
b--   10.05.2026 16:56:58       10.05.2026 16:56:58               1 KB archive
b--   10.05.2026 16:56:58       10.05.2026 16:56:57              541 B config
b--   10.05.2026 16:56:57       10.05.2026 16:56:57              653 B demo
b--   10.05.2026 16:56:58       10.05.2026 16:56:58              415 B dest
b--   10.05.2026 16:56:57       10.05.2026 16:56:57              831 B events
b--   10.05.2026 16:56:58       10.05.2026 16:56:58              337 B final
b--   10.05.2026 16:56:59       10.05.2026 16:56:59               5 KB import-over
b--   10.05.2026 16:56:57       10.05.2026 16:56:57               7 KB logs
b--   10.05.2026 16:56:57       10.05.2026 16:56:57               3 KB match-demo
b--   10.05.2026 16:56:58       10.05.2026 16:56:58              326 B move-dst
b--   10.05.2026 16:56:58       10.05.2026 16:56:58                0 B move-src
b--   10.05.2026 16:56:57       10.05.2026 16:56:57               1 KB nested
b--   10.05.2026 16:56:57       10.05.2026 16:56:57              604 B nested-match
b--   10.05.2026 16:56:58       10.05.2026 16:56:58                0 B origin
b--   10.05.2026 16:56:58       10.05.2026 16:56:58              652 B pass
b--   10.05.2026 16:56:59       10.05.2026 16:56:59               5 KB restored
b--   10.05.2026 16:56:59       10.05.2026 16:56:59               4 KB restored-json
b--   10.05.2026 16:56:58       10.05.2026 16:56:58                0 B source
b--   10.05.2026 16:56:57       10.05.2026 16:56:57              337 B special
b--   10.05.2026 16:56:57       10.05.2026 16:56:57               2 KB staff
b--   10.05.2026 16:56:57       10.05.2026 16:56:57              835 B str-test
b--   10.05.2026 16:56:58       10.05.2026 16:56:57               6 KB team
b--   10.05.2026 16:56:58       10.05.2026 16:56:58                0 B temp
b--   10.05.2026 16:56:58       10.05.2026 16:56:58              333 B tmp
b--   10.05.2026 16:56:58       10.05.2026 16:56:58               20 B tmp-json
b--   10.05.2026 16:56:57       10.05.2026 16:56:57              658 B types
b--   10.05.2026 16:56:57       10.05.2026 16:56:57               2 KB users
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
archive              10.05.2026 16:56:58
config               10.05.2026 16:56:58
demo                 10.05.2026 16:56:57
dest                 10.05.2026 16:56:58
events               10.05.2026 16:56:57
final                10.05.2026 16:56:58
import-over          10.05.2026 16:56:59
logs                 10.05.2026 16:56:57
match-demo           10.05.2026 16:56:57
move-dst             10.05.2026 16:56:58
move-src             10.05.2026 16:56:58
nested               10.05.2026 16:56:57
nested-match         10.05.2026 16:56:57
origin               10.05.2026 16:56:58
pass                 10.05.2026 16:56:58
restored             10.05.2026 16:56:59
restored-json        10.05.2026 16:56:59
source               10.05.2026 16:56:58
special              10.05.2026 16:56:57
staff                10.05.2026 16:56:57
str-test             10.05.2026 16:56:57
team                 10.05.2026 16:56:58
temp                 10.05.2026 16:56:58
tmp                  10.05.2026 16:56:58
tmp-json             10.05.2026 16:56:58
types                10.05.2026 16:56:57
users                10.05.2026 16:56:57
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
Alice-Backup        10.05.2026 16:56:58
Alice               10.05.2026 16:56:58
Bob                 10.05.2026 16:56:58
Carol               10.05.2026 16:56:58
Frank               10.05.2026 16:56:58
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
b--   10.05.2026 16:56:58       10.05.2026 16:56:58               1 KB archive
b--   10.05.2026 16:56:58       10.05.2026 16:56:57              541 B config
b--   10.05.2026 16:56:57       10.05.2026 16:56:57              653 B demo
b--   10.05.2026 16:56:58       10.05.2026 16:56:58              415 B dest
b--   10.05.2026 16:56:57       10.05.2026 16:56:57              831 B events
b--   10.05.2026 16:56:58       10.05.2026 16:56:58              337 B final
b--   10.05.2026 16:56:59       10.05.2026 16:56:59               5 KB import-over
b--   10.05.2026 16:56:57       10.05.2026 16:56:57               7 KB logs
b--   10.05.2026 16:56:57       10.05.2026 16:56:57               3 KB match-demo
b--   10.05.2026 16:56:58       10.05.2026 16:56:58              326 B move-dst
b--   10.05.2026 16:56:58       10.05.2026 16:56:58                0 B move-src
b--   10.05.2026 16:56:57       10.05.2026 16:56:57               1 KB nested
b--   10.05.2026 16:56:57       10.05.2026 16:56:57              604 B nested-match
b--   10.05.2026 16:56:58       10.05.2026 16:56:58                0 B origin
b--   10.05.2026 16:56:58       10.05.2026 16:56:58              652 B pass
b--   10.05.2026 16:56:59       10.05.2026 16:56:59               5 KB restored
b--   10.05.2026 16:56:59       10.05.2026 16:56:59               4 KB restored-json
b--   10.05.2026 16:56:58       10.05.2026 16:56:58                0 B source
b--   10.05.2026 16:56:57       10.05.2026 16:56:57              337 B special
b--   10.05.2026 16:56:57       10.05.2026 16:56:57               2 KB staff
b--   10.05.2026 16:56:57       10.05.2026 16:56:57              835 B str-test
b--   10.05.2026 16:56:58       10.05.2026 16:56:57               6 KB team
b--   10.05.2026 16:56:58       10.05.2026 16:56:58                0 B temp
b--   10.05.2026 16:56:58       10.05.2026 16:56:58              333 B tmp
b--   10.05.2026 16:56:58       10.05.2026 16:56:58               20 B tmp-json
b--   10.05.2026 16:56:57       10.05.2026 16:56:57              658 B types
b--   10.05.2026 16:56:57       10.05.2026 16:56:57               2 KB users
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

Name       Country Population
----       ------- ----------
Berlin     DE         3600000
Munich     DE         1500000
London     UK         8900000
Manchester UK          550000
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

Name   Country Population
----   ------- ----------
Berlin DE         3600000
Munich DE         1500000
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

Name   Country Population
----   ------- ----------
Berlin DE         3600000
Munich DE         1500000
                       

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

.buckets (93 items, 45 KB)
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
OldestObject : 10.05.2026 16:56:59
NewestObject : 10.05.2026 16:56:59
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

Name     Country Population
----     ------- ----------
Berlin   DE         3600000
London   UK         8900000
New York US         8300000
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
archive           1
config            3
demo              3
dest              1
dir-listing       5
events            2
final             1
import-over       5
logs             30
match-demo        6
move-dst          1
nested            1
nested-match      1
pass              2
restored          5
restored-json     5
special           1
staff             3
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

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 100

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 100

Level  : 3
Joined : 09.02.2026 16:56:57
Active : True
Name   : Carol
Role   : PM
Skills : {Agile, Jira, Confluence}
Score  : 95

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
Score  : 96
```
```

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 100

Level  : 3
Joined : 10.05.2025 16:56:57
Name   : Alice
Role   : Developer
Active : True
Skills : {PowerShell, C#, Azure}
Score  : 100

Level  : 3
Joined : 09.02.2026 16:56:57
Active : True
Name   : Carol
Role   : PM
Skills : {Agile, Jira, Confluence}
Score  : 95

Level  : 4
Joined : 26.12.2024 16:56:57
Name   : Frank
Role   : Developer
Active : True
Skills : {Rust, Go, Kubernetes}
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
  "Level": 3,
  "Joined": "2025-05-10T16:56:57.1526371+02:00",
  "Name": "Alice",
  "Role": "Developer",
  "Active": true,
  "Skills": [
    "PowerShell",
    "C#",
    "Azure"
  ],
  "Score": 100
},
{
  "Level": 3,
  "Joined": "2025-05-10T16:56:57.1526371+02:00",
  "Name": "Alice",
  "Role": "Developer",
  "Active": true,
  "Skills": [
    "PowerShell",
    "C#",
    "Azure"
  ],
  "Score": 100
},
{
  "Level": 3,
  "Joined": "2026-02-09T16:56:57.1555755+01:00",
  "Active": true,
  "Name": "Carol",
  "Role": "PM",
  "Skills": [
    "Agile",
    "Jira",
    "Confluence"
  ],
  "Score": 95
},
{
  "Level": 4,
  "Joined": "2024-12-26T16:56:57.1556376+01:00",
  "Name": "Frank",
  "Role": "Developer",
  "Active": true,
  "Skills": [
    "Rust",
    "Go",
    "Kubernetes"
  ],
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

OS       : Rocky 9
Hostname : app-01
RAM      : 16
Location : DC2
Status   : offline
Disk     : 200
Role     : app
IP       : 10.0.2.50
CPU      : 8

OS       : Debian 12
Hostname : db-02
RAM      : 32
Location : DC2
Status   : degraded
Disk     : 500
Role     : database
IP       : 10.0.2.20
CPU      : 8
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

OS       : Debian 12
Hostname : db-01
RAM      : 32
Location : DC1
Status   : online
Disk     : 500
Role     : database
IP       : 10.0.1.20
CPU      : 8

OS       : Debian 12
Hostname : db-02
RAM      : 32
Location : DC2
Status   : degraded
Disk     : 500
Role     : database
IP       : 10.0.2.20
CPU      : 8
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
  5 DC1                       {@{OS=FreeBSD 14; Hostname=backup-01; RAM=8; Location=DC1; Status=online; Disk=2000; Role=backup; IP=10.0.1.1; CPU=4}, @{OS=Alpine 3.18; Hostname=cache-01; RAM=16; Location=DC1; Status=online; Disk=60; Role=cache; IP=10.0.1.30; CPU=2}, @{OS=Debian 12; Hostname=db-01; RAM=32; Location=DC1; Status=online; Disk=500; Role=database; IP=10.0.1.20; CPU=8}, @{OS=Ubuntu 22.04; Hostname=web-01; RAM=8; Location=DC1; Status=online; Disk=120; Role=web; IP=10.0.1.10; CPU=4}…}
  3 DC2                       {@{OS=Rocky 9; Hostname=app-01; RAM=16; Location=DC2; Status=offline; Disk=200; Role=app; IP=10.0.2.50; CPU=8}, @{OS=Debian 12; Hostname=db-02; RAM=32; Location=DC2; Status=degraded; Disk=500; Role=database; IP=10.0.2.20; CPU=8}, @{OS=Ubuntu 22.04; Hostname=mon-01; RAM=4; Location=DC2; Status=online; Disk=250; Role=monitoring; IP=10.0.1.40; CPU=2}}
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

Severity Timestamp           Message                   Source
-------- ---------           -------                   ------
ERROR    10.05.2026 14:57:00 Connection pool exhausted web-01
ERROR    10.05.2026 16:42:00 Service unreachable       app-01
CRIT     10.05.2026 16:52:00 Disk /dev/sda1 at 97%     app-01
ERROR    10.05.2026 14:57:00 Connection pool exhausted web-01
ERROR    10.05.2026 16:42:00 Service unreachable       app-01
CRIT     10.05.2026 16:52:00 Disk /dev/sda1 at 97%     app-01
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

  fill / spill / dip           — save, read, list
  -Key / -KeyProperty          — naming objects
  -Overwrite / -AsTimestamp    — replacement and timestamp keys
  -AsJson / -Compress          — storage formats
  -Match (exact)               — hashtable-based filtering
  -Filter (scriptblock)        — expression-based comparison (-gt, -like, -contains, -match)
  Nested property filtering    — .Settings.Enabled with -Filter
  -First / -Skip               — pagination
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

