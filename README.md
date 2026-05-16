# Buckets

<p align="center">
  <img src="logo.png" alt="Buckets Logo" width="256">
</p>

A PowerShell module for file-based PSObject storage. Store, retrieve, and manage PowerShell objects in simple "buckets" — directory-based collections with automatic serialization.

## Quick Start

```powershell
Import-Module ./Buckets

# Save objects (JSON by default) — alias: fill
New-BucketObject -InputObject @{ Name = "Alice"; Age = 30 } -KeyProperty Name

# Retrieve — alias: spill
Get-BucketObject | Select-Object Name, Age

# List buckets — alias: dip
Get-Bucket
```

## Storage Format

| Format | Default | Switch | Extension |
|--------|---------|--------|-----------|
| **JSON** | Yes | — | `.json` |
| **Binary** (PSSerializer) | No | `-AsBinary` | `.dat` |

JSON is the default format. Objects that exceed JSON depth trigger auto-depth increment (up to 100); if still truncated, they fall back to binary with a warning. Use `-BinaryDepth` to control binary serialization detail (default: `5`).

Binary files can be compressed via `-Compress` (GZip, ~95% reduction on repetitive data). Compression is auto-detected on read via magic bytes.

## Cmdlets

### New-BucketObject (alias: `fill`)

Saves PSObjects to a bucket. Creates the bucket if it doesn't exist.

```powershell
New-BucketObject
    [-InputObject] <PSObject>
    [[-Bucket] <string>]
    [[-Path] <string>]
    [[-Key] <string>]
    [-KeyProperty <string>]
    [-Depth <int>]
    [-BinaryDepth <int>]
    [-AsTimestamp]
    [-AsBinary]
    [-Compress]
    [-Expand]
    [-ExpandDepth <int>]
    [-Overwrite]
    [-AutoIndex]
    [-Quiet]
    [<CommonParameters>]
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-InputObject` | Object(s) to store | Required, accepts pipeline |
| `-Bucket` | Bucket name | `"default"` |
| `-Path` | Storage root directory | `$HOME/.buckets` |
| `-Key` | Literal filename (no extension) | GUID |
| `-KeyProperty` | Property name whose value becomes the filename | — |
| `-Depth` | JSON serialization depth (1–100) | `20` |
| `-BinaryDepth` | Binary serialization depth (1–100) | `5` |
| `-AsBinary` | Store in binary format (`.dat`) | `false` |
| `-Compress` | GZip compress binary output | `false` |
| `-Expand` | Decompose nested objects into sub-buckets. Only `[PSCustomObject]`, hashtables, and `ICollection` types are expanded — system types (FileInfo, Process, etc.) are saved as regular objects with a warning | `false` |
| `-ExpandDepth` | Max nesting depth for expansion (1–20) | `5` |
| `-Overwrite` | Overwrite existing objects with the same key | `false` |
| `-AutoIndex` | Append `_1`, `_2`, etc. to duplicate keys instead of skipping | `false` |
| `-Quiet` | Suppress output | `false` |

    )
New-BucketObject -Bucket users -InputObject $users -KeyProperty Name

# Special characters are sanitized (/, :, *, etc. become _)
```

Without `-Key` or `-KeyProperty`, each object gets a unique GUID filename.

#### Examples

```powershell
# Using the fill alias
@{ Name = "test" } | fill -Bucket demo

# Default: progress and summary
New-BucketObject -InputObject @{ Name = "test" }

# Verbose: per-object details
New-BucketObject -InputObject @{ Name = "test" } -Verbose

# Quiet: silent, no output
New-BucketObject -InputObject @{ Name = "test" } -Quiet

# Named bucket, keyed by property
New-BucketObject -Bucket users -InputObject $users -KeyProperty Email

# Binary format
New-BucketObject -Bucket users -InputObject $users -KeyProperty Name -AsBinary

# Timestamp-based filenames
Get-Process | New-BucketObject -Bucket processes -AsTimestamp

# Compressed binary
New-BucketObject -Bucket logs -InputObject $logs -AsBinary -Compress

# Custom storage location
New-BucketObject -Path /tmp/buckets -InputObject $data -KeyProperty Name

# Expand a PSCustomObject into browsable sub-buckets
[PSCustomObject]@{ host = "localhost"; config = @{ port = 8080; ssl = $true } } | fill -Bucket demo -Expand

# Expand with -Key: sub-bucket prefix
[PSCustomObject]@{ name = "app"; version = 1.0 } | fill -Bucket demo -Key "service" -Expand

# Expand with -ExpandDepth: limit nesting
[PSCustomObject]@{ level1 = @{ level2 = @{ leaf = "deep" } } } | fill -Bucket demo -Expand -ExpandDepth 1

# Expand a PSCustomObject array with -KeyProperty (each item gets its own sub-bucket)
@{ id = "a"; val = 10 }, @{ id = "b"; val = 20 } | fill -Bucket demo -KeyProperty id -Expand
```

---

### Get-BucketObject (alias: `scoop`)

Retrieves objects from one or more buckets. Recursion into nested sub-buckets is enabled by default.
Warns on nonexistent literal (non-wildcard) bucket names.

```powershell
Get-BucketObject
    [[-Bucket] <string[]>]
    [[-Key] <string[]>]
    [-Path <string>]
    [-Match <hashtable>]
    [-Filter <scriptblock>]
    [-Recurse]
    [-NoRecurse]
    [-Expand]
    [-First <int>]
    [-Skip <int>]
    [<CommonParameters>]
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Bucket` | Bucket name(s) to search (supports wildcards `*`, `?`). Position 0. | All buckets |
| `-Key` | Object key(s) to retrieve (prefix match, case-insensitive, accepts array). Position 1. | All objects |
| `-Path` | Storage root directory | `$HOME/.buckets` |
| `-Match` | Hashtable of exact-match filters (supports `$null` for absent properties) | — |
| `-Filter` | ScriptBlock for custom filtering (`$_` references the object) | — |
| `-Recurse` | Included for backward compatibility. Recursion is now the default. | — |
| `-NoRecurse` | Suppress recursion — only return objects from the specified bucket directory | — |
| `-Expand` | Reconstruct expanded sub-buckets back into nested objects | `false` |
| `-First` | Return only the first N objects | — |
| `-Skip` | Skip the first N objects | — |

Retrieved objects include metadata properties: `_BucketName`, `_BucketKey`, `_BucketFile`.

#### Examples

```powershell
# Using the spill alias
spill users
spill users "Alice"

# All objects from a bucket (positional)
Get-BucketObject users

# Specific object by bucket and key (positional)
Get-BucketObject users "Alice"

# All objects from all buckets
Get-BucketObject

# From multiple buckets
Get-BucketObject -Bucket users, orders

# Wildcard patterns
Get-BucketObject -Bucket "user*"

# By key within a bucket
Get-BucketObject -Key "Alice" -Bucket users

# Hashtable filter (exact match)
Get-BucketObject -Bucket users -Match @{ Role = "admin" }

# Match null (property must be absent)
Get-BucketObject -Bucket users -Match @{ Deleted = $null }

# ScriptBlock filter (full expression support)
Get-BucketObject -Bucket users -Filter { $_.Age -gt 30 }
Get-BucketObject -Bucket users -Filter { $_.Role -eq "admin" -and $_.Score -ge 90 }
Get-BucketObject -Filter { $_.Name -match "^[AD]" }

# Cross-bucket with filter
Get-BucketObject -Filter { $_.Price -gt 20 }

# Search for a key across all buckets
Get-BucketObject -Key "special-item"

# Limit results
Get-BucketObject -Bucket users -First 10
Get-BucketObject -Bucket users -Skip 5 -First 5

# Expand: reconstruct expanded sub-buckets back into nested objects
Get-BucketObject -Bucket demo -Expand

# Expand with -Key
Get-BucketObject -Bucket demo -Key "service" -Expand

# Multi-key retrieve (string array)
Get-BucketObject -Bucket team -Key "Grace", "Heidi", "Ivan"
```

---

### Set-BucketObject

Updates an existing object in a bucket. Preserves the storage format.
Outputs a summary line with updated key names by default. Use `-PassThru` to emit updated objects to the pipeline.

```powershell
Set-BucketObject
    [-InputObject] <PSObject>
    [[-Bucket] <string>]
    [[-Key] <string>]
    [[-Path] <string>]
    [-Depth <int>]
    [-BinaryDepth <int>]
    [-AsBinary]
    [-Compress]
    [-PassThru]
    [-Quiet]
    [<CommonParameters>]

Set-BucketObject
    -Bucket <string>
    -Key <string>
    -Property <string>
    -Value <Object>
    [[-Path] <string>]
    [-Depth <int>]
    [-BinaryDepth <int>]
    [-AsBinary]
    [-Compress]
    [-PassThru]
    [-Quiet]
    [<CommonParameters>]
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-InputObject` | Updated object. Pipeline input binds `_BucketName` and `_BucketKey` automatically | Required, accepts pipeline |
| `-Bucket` | Bucket name (optional when piped from `Get-BucketObject`) | Bound from pipeline or required |
| `-Key` | Object key (optional when piped from `Get-BucketObject`) | Bound from pipeline or required |
| `-Property` | Property name to update. Requires `-Value` | — |
| `-Value` | New value for `-Property` | — |
| `-Path` | Storage root directory | `$HOME/.buckets` |
| `-Depth` | JSON serialization depth | `20` |
| `-BinaryDepth` | Binary serialization depth (1–100) | `5` |
| `-AsBinary` | Force binary format | — |
| `-Compress` | GZip compress binary output | `false` |
| `-PassThru` | Emit PSCustomObject with Bucket and Key to pipeline | `false` |
| `-Quiet` | Suppress all output | `false` |

#### Examples

```powershell
# Pipeline: modify and save back (auto-detects bucket/key from metadata)
Get-BucketObject -Bucket users -Key "Alice" | ForEach-Object {
    $_.Age = 31
    $_
} | Set-BucketObject

# Explicit parameters
$user = Get-BucketObject -Bucket users -Key "Alice"
$user.Email = "alice@new.com"
Set-BucketObject -Bucket users -Key "Alice" -InputObject $user

# Single property update — no read needed
Set-BucketObject -Bucket team -Key "Bob" -Property Score -Value 100

# Using the blend alias
blend team Bob -Property Role -Value "Lead"
```

---

### Remove-BucketObject

Removes an object from a bucket.

```powershell
Remove-BucketObject
    [-Bucket] <string>
    [[-Path] <string>]
    [[-Key] <string>]
    [-All]
    [-Match <hashtable>]
    [-Filter <scriptblock>]
    [-PassThru]
    [-Quiet]
    [-WhatIf]
    [-Confirm]
    [<CommonParameters>]
```

| Parameter | Description |
|-----------|-------------|
| `-Bucket` | Bucket name |
| `-Path` | Storage root directory |
| `-Key` | Object key to remove |
| `-All` | Remove all objects from the bucket |
| `-Match` | Hashtable filter (exact match, supports `$null`) |
| `-Filter` | ScriptBlock filter (`$_` references the object) |
| `-PassThru` | Return the removed object's metadata (Key without file extension) |
| `-Quiet` | Suppress output |
| `-WhatIf` | Preview without removing |

#### Examples

```powershell
# Remove by key
Remove-BucketObject -Bucket users -Key "Alice"

# Remove all objects from bucket
Remove-BucketObject -Bucket users -All

# Remove matching objects
Remove-BucketObject -Bucket users -Match @{ Status = "inactive" }

# Remove with WhatIf preview
Remove-BucketObject -Bucket temp -All -WhatIf
```

---

### Copy-BucketObject

Copies an object within or between buckets.

```powershell
Copy-BucketObject
    [-Bucket] <string>
    [[-Path] <string>]
    [-Key] <string>
    [-DestinationBucket <string>]
    [-DestinationKey <string>]
    [-PassThru]
    [-Quiet]
    [<CommonParameters>]
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Bucket` | Source bucket name | Required |
| `-Key` | Source object key | Required |
| `-DestinationBucket` | Destination bucket name | Same as `-Bucket` |
| `-DestinationKey` | Destination object key | Same as `-Key` |
| `-Path` | Storage root directory | `$HOME/.buckets` |
| `-PassThru` | Return metadata for the copied object | `false` |

#### Examples

```powershell
# Copy within same bucket
Copy-BucketObject -Bucket users -Key "Alice" -DestinationKey "Alice-Backup"

# Copy to another bucket
Copy-BucketObject -Bucket users -Key "Alice" -DestinationBucket archive
```

---

### Rename-BucketObject

Renames an object within a bucket.

```powershell
Rename-BucketObject
    [-Bucket] <string>
    [[-Path] <string>]
    [-Key] <string>
    [-NewKey] <string>
    [-PassThru]
    [-Quiet]
    [<CommonParameters>]
```

#### Examples

```powershell
Rename-BucketObject -Bucket users -Key "Alice" -NewKey "Alice-Smith"
```

---

### Move-BucketObject

Moves an object between buckets (copy + delete original).

```powershell
Move-BucketObject
    [-Bucket] <string>
    [[-Path] <string>]
    [-Key] <string>
    [-DestinationBucket <string>]
    [-DestinationKey <string>]
    [-PassThru]
    [-Quiet]
    [<CommonParameters>]
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Bucket` | Source bucket name | Required |
| `-Key` | Source object key | Required |
| `-DestinationBucket` | Destination bucket name | Same as `-Bucket` |
| `-DestinationKey` | Destination object key | Same as `-Key` |

#### Examples

```powershell
# Move to another bucket
Move-BucketObject -Bucket users -Key "Alice" -DestinationBucket archive

# Rename during move
Move-BucketObject -Bucket users -Key "Alice" -DestinationBucket archive -DestinationKey "Alice-2024"
```

---

### Get-Bucket (alias: `dip`)

Lists available buckets with object counts. Supports tree visualization.

```powershell
Get-Bucket
    [[-Name] <string>]
    [-Path <string>]
    [-Recurse]
    [-Tree]
    [-Objects]
    [-Raw]
    [-MaxFiles <int>]
    [-Depth <int>]
    [<CommonParameters>]
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Name` | Filter buckets by name (wildcards `*`/`?` supported; substring match if no wildcards) | All buckets |
| `-Path` | Storage root directory | `$HOME/.buckets` |
| `-Tree` | Render a colorized tree view of all buckets and files | `false` |
| `-Objects` | Show individual files in tree view | `false` (directories only) |
| `-Raw` | Return structured tree objects (`Buckets.Tree`) instead of formatted text | `false` |
| `-MaxFiles` | Max files per bucket in tree view | `5` |
| `-Depth` | Max depth to display in tree view | Unlimited |

#### Examples

```powershell
# Using the dip alias
dip
dip -Tree

# List all buckets (recursive scan)
Get-Bucket

# Filter by name pattern
Get-Bucket "user"

# Tree view
Get-Bucket -Tree

# Tree view without individual objects
Get-Bucket -Tree -Objects

# Tree view showing up to 20 files per bucket
Get-Bucket -Tree -MaxFiles 20

# Raw tree data as JSON
Get-Bucket -Tree -Raw | ConvertTo-Json -Depth 5
```

---

### Get-BucketKeys

Lists object keys within a bucket. Returns only `Bucket` and `Key` per object —
for detailed per-object statistics (format, type, size, timestamps, compression),
use `Get-BucketObjectStats`.

```powershell
Get-BucketKeys
    [[-Bucket] <string>]
    [-Path <string>]
    [-Match <string>]
    [<CommonParameters>]
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Bucket` | Bucket name (supports wildcards `*`, `?`) | All top-level buckets |
| `-Path` | Storage root directory | `$HOME/.buckets` |
| `-Match` | Wildcard filter on key names (case-insensitive, `-like`) | All keys |

Returns `PSCustomObject` with `Bucket` and `Key`.

#### Examples

```powershell
# All keys in a bucket
Get-BucketKeys -Bucket users

# Keys matching a pattern
Get-BucketKeys -Bucket orders -Match "ORD-*"

# Keys across multiple buckets
Get-BucketKeys -Bucket "temp*"
```

---

### Get-BucketObjectStats

Returns detailed per-object statistics (format, type, size, timestamps, compression).

```powershell
Get-BucketObjectStats
    [[-Bucket] <string>]
    [[-Key] <string>]
    [-Path <string>]
    [-Match <string>]
    [<CommonParameters>]
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Bucket` | Bucket name (supports wildcards `*`, `?`) | All top-level buckets |
| `-Key` | Exact key to look up (single-object stats) | All objects |
| `-Path` | Storage root directory | `$HOME/.buckets` |
| `-Match` | Wildcard filter on key names (case-insensitive, `-like`) | All keys |

Returns `PSCustomObject` with `Bucket`, `Key`, `Format`, `Type`, `Size`, `LastWriteTime`, and `IsCompressed`. `Path` is included as a hidden property.

| Property | Description |
|----------|-------------|
| `Bucket` | Bucket name |
| `Key` | Object key |
| `Format` | `"JSON"` or `"Binary"` |
| `Type` | `"Object"`, `"Array"`, or `"Value"` (peeked from file content) |
| `Size` | File size in bytes |
| `LastWriteTime` | Last modified timestamp |
| `IsCompressed` | `$true` if gzip-compressed binary |
| `Path` | (hidden) Full file path |

#### Examples

```powershell
# Stats for all objects in a bucket
Get-BucketObjectStats -Bucket users

# Stats for a specific key
Get-BucketObjectStats -Bucket users -Key "alice"

# Filter by key pattern
Get-BucketObjectStats -Bucket orders -Match "ORD-*"

# Find compressed objects
Get-BucketObjectStats -Bucket data | Where-Object { $_.IsCompressed }

# Find arrays
Get-BucketObjectStats -Bucket users | Where-Object { $_.Type -eq "Array" }
```

---

### Get-BucketStats

Shows statistics for a bucket.

```powershell
Get-BucketStats
    [-Bucket] <string>
    [[-Path] <string>]
    [<CommonParameters>]
```

| Property | Description |
|----------|-------------|
| `Name` | Bucket name |
| `Path` | Full filesystem path to the bucket directory |
| `ObjectCount` | Number of objects in the bucket |
| `TotalSize` | Human-readable total size (e.g. "12.5 KB") |
| `TotalSizeBytes` | (hidden) Raw size in bytes |
| `OldestObject` | Creation time of the oldest object |
| `NewestObject` | Creation time of the newest object |

#### Examples

```powershell
Get-BucketStats -Bucket users
```

Output:
```
Name         : users
Path         : /home/user/.buckets/users
ObjectCount  : 5
TotalSize    : 12.5 KB
OldestObject : 2024-01-15 10:30:00
NewestObject : 2024-01-20 14:22:00
```

---

### Remove-Bucket

Removes one or more buckets and all their contents. Supports wildcards and nested buckets.

Shows a colored summary of buckets to be removed before confirmation, listing object counts and sizes. Skipped buckets (containing non-bucket files) are shown with reasons.

```powershell
Remove-Bucket
    [-Bucket] <string[]>
    [[-Path] <string>]
    [-Recurse]
    [-Force]
    [-Quiet]
    [-WhatIf]
    [-Confirm]
    [<CommonParameters>]
```

| Parameter | Description |
|-----------|-------------|
| `-Bucket` | Bucket name(s) or wildcard patterns (`*`, `?`). Nested paths like `"projects/myapp"` |
| `-Path` | Storage root directory |
| `-Recurse` | Remove target bucket AND all nested sub-buckets |
| `-Force` | Skip confirmation prompt and remove immediately |
| `-Quiet` | Suppress progress output |
| `-WhatIf` | Preview what would be removed |

#### Examples

```powershell
# Single bucket (with confirmation)
Remove-Bucket -Bucket users

# Multiple buckets
Remove-Bucket -Bucket users, temp -Force

# Wildcard patterns
Remove-Bucket -Bucket "temp*" -Force
Remove-Bucket -Bucket "*_archive" -Force

# Nested bucket with all sub-buckets
Remove-Bucket -Bucket "projects/myapp" -Recurse

# All buckets (with confirmation)
Remove-Bucket *

# Preview without removing
Remove-Bucket * -WhatIf
```

Safe by design: only removes directories containing exclusively `.dat`/`.json` files (or empty). Skips buckets with other file types with a warning.

---

### Export-Bucket

Exports an entire bucket to a single archive file.

```powershell
Export-Bucket
    [-Bucket] <string[]>
    [-OutputFile] <string>
    [-Path <string>]
    [-AsBinary]
    [-Compress]
    [-Quiet]
    [<CommonParameters>]
```

| Parameter | Description |
|-----------|-------------|
| `-Bucket` | Bucket name(s) to export (supports wildcards) |
| `-OutputFile` | Output archive file path |
| `-Path` | Storage root directory |
| `-AsBinary` | Export as CLIXML binary archive (default: JSON) |
| `-Compress` | GZip compress binary archives |
| `-Quiet` | Suppress output |

#### Examples

```powershell
Export-Bucket -Bucket users -OutputFile users-backup.json
Export-Bucket -Bucket "projects/*" -OutputFile projects-backup.clixml -AsBinary
```

---

### Import-Bucket

Imports objects from an archive file into a bucket. Skipped objects (existing keys) are listed by name in the summary output.

```powershell
Import-Bucket
    [-Bucket] <string>
    [-InputFile] <string>
    [-AsBinary]
    [-Overwrite]
    [-Quiet]
    [<CommonParameters>]
```

| Parameter | Description |
|-----------|-------------|
| `-Bucket` | Destination bucket name |
| `-InputFile` | Archive file to import |
| `-AsBinary` | Force CLIXML/binary import (auto-detected by extension) |
| `-Overwrite` | Overwrite existing objects |
| `-Quiet` | Suppress output |

#### Examples

```powershell
Import-Bucket -Bucket users -InputFile users-backup.json
Import-Bucket -Bucket projects -InputFile projects-backup.clixml -Overwrite
```

---

### Set-BucketRoot / Get-BucketRoot

Override or query the session's bucket storage root.

```powershell
Set-BucketRoot [-Path] <string>
Get-BucketRoot
```

`Set-BucketRoot` changes the default root for the current session. `Get-BucketRoot` returns the effective root (priority: session override > `$env:BUCKETS_ROOT` > `$HOME/.buckets`).

```powershell
# Override root for the session
Set-BucketRoot /mnt/storage/buckets

# Query current root
Get-BucketRoot
```

---

### Sync-BucketDrive

Creates or updates the `buckets:` PSDrive using the custom Buckets provider.

```powershell
Sync-BucketDrive
```

Called automatically on module import and by `Set-BucketRoot`. Run manually after changing `$env:BUCKETS_ROOT`.

```powershell
# Navigate buckets like a filesystem
buckets:\> dir
buckets:\users\> cd alice.dat
buckets:\users\alice.dat> cat
```

---

## Pipeline Support

Most cmdlets accept pipeline input:

```powershell
# Save pipeline output directly
Get-ChildItem / | New-BucketObject -Bucket root -KeyProperty Name

# Retrieve and filter
Get-BucketObject -Bucket users | Where-Object { $_.Age -gt 30 }

# Retrieve, modify, update
Get-BucketObject -Bucket users | ForEach-Object {
    $_.LastUpdated = Get-Date
    $_
} | Set-BucketObject
```

`Set-BucketObject` auto-detects bucket and key from `_BucketName` and `_BucketKey` metadata properties, so you can pipe results from `Get-BucketObject` directly.

---

## Storage Structure

### Expand layout

When an object is saved with `-Expand`, its properties become sub-buckets and files instead of a single file:

```
.buckets/expand-demo/
├── host.dat              (scalar property)
├── port.dat              (scalar property)
└── config/               (nested object becomes sub-bucket)
    ├── port.dat
    └── ssl.dat
```

Retrieving with `-Expand` reconstructs the original nested object.

**Safety guard**: Only `[PSCustomObject]`, hashtables (`IDictionary`), and true collections (`ICollection`) are expandable. System types (FileInfo, Process, ServiceController, XmlDocument, etc.) are saved as regular objects with a warning — this prevents accidental disk flooding from deeply nested system object expansion.

### Standard nesting

Buckets support nesting via path separators in bucket names. Nested buckets are real subdirectories:

```
.buckets/
├── users/
│   ├── alice.json          (JSON)
│   ├── bob.json            (JSON)
│   └── charlie.dat         (binary, saved with -AsBinary)
├── orders/
│   ├── 2024/
│   │   ├── ORD-001.json
│   │   └── ORD-002.json
│   └── 2025/
│       └── ORD-003.json
├── ad/                    (nested hierarchy example)
│   ├── eu/
│   │   ├── de/
│   │   │   └── berlin/
│   │   │       ├── computers/
│   │   │       ├── groups/
│   │   │       └── users/
│   │   └── uk/
│   │       └── london/
│   │           ├── computers/
│   │           ├── groups/
│   │           └── users/
│   └── us/
└── default/
    ├── a1b2c3.json
    └── d4e5f6.json
```

Use nested bucket paths like `Get-BucketObject -Bucket "ad/eu/de/berlin/users"` or wildcards like `Get-BucketObject -Bucket "ad/*/*/users"`.

---

## Building from Source

The module includes a C# PSProvider component that must be compiled for PSDrive support:

```powershell
# Using the build script
./build.ps1

# Manual dotnet build
dotnet build Buckets/BucketsProvider.csproj
```

On macOS, use `build.ps1` or `dotnet build` directly (`Add-Type` may fail due to missing framework assemblies).

## Importing the Module

```powershell
# From current directory
Import-Module ./Buckets

# From module path
Import-Module Buckets

# Dot-source for development
. ./Buckets/Buckets.psm1
```

## PSDrive Provider

The module registers a `buckets:` PSDrive backed by a custom PowerShell provider. Navigate buckets like a filesystem:

```powershell
# List all buckets
buckets:\> dir

    Type LastWriteTime          CreationTime               Size Name
    ---- -------------          ------------               ---- ----
    b--  05/08/2026 10:30:00   05/08/2026 10:30:00       1 KB users
    b--  05/08/2026 10:31:00   05/08/2026 10:31:00       2 KB orders
    b--  05/08/2026 10:32:00   05/08/2026 10:32:00       4 KB ad

# Enter a bucket
buckets:\> cd users

# List objects and nested buckets
buckets:\users> dir

    Type LastWriteTime          CreationTime               Size Name
    ---- -------------          ------------               ---- ----
    --o  05/08/2026 10:30:00   05/08/2026 10:30:00        1 KB alice
    --o  05/08/2026 10:30:00   05/08/2026 10:30:00        2 KB bob
    --o  05/08/2026 10:30:00   05/08/2026 10:30:00        1 KB charlie

# Read an object's content (deserialized)
buckets:\users> cat alice

Name  Age Email
----  --- -----
Alice  30 alice@example.com

# Nested buckets work as subdirectories
buckets:\> cd ad/eu/de/berlin/users
buckets:\ad\eu\de\berlin\users> dir
```

The `Type` column uses a visual indicator:
- `b--` — bucket (container directory)
- `--o` — object (`.dat` or `.json` file)

### Key provider capabilities

| Feature | Description |
|---------|-------------|
| Navigation | `cd`, `dir`, `ls` work as expected; nested buckets are real subdirectories |
| Content | `cat` / `Get-Content` deserializes and displays object content |
| New items | `New-Item` creates buckets (`-ItemType Directory`) or objects (omit type) |
| Copy/Move | `Copy-Item`, `Move-Item`, `Rename-Item` work across buckets |
| Remove | `Remove-Item` deletes objects; directory removal protected by safety checks |
| WhatIf | All write operations support `-WhatIf` / `-Confirm` |
| Tab completion | Tab-complete bucket names, object keys, and provider paths |
| Cross-drive | Full `buckets:` path completion in native cmdlets like `Get-ChildItem` |

### Column display format

Default columns shown by `dir` / `Get-ChildItem`:

| Column | Description |
|--------|-------------|
| Type | `b--` (bucket) or `--o` (object) |
| LastWriteTime | Last modification timestamp (25 char width) |
| CreationTime | Creation timestamp (25 char width) |
| Size | Human-readable size, right-aligned (12 char width) |
| Name | Bucket name or object key (filename without extension) |

### Content reading

`cat` / `Get-Content` deserializes the object and returns it as a PSObject for interactive inspection or piping:

```powershell
# Read and pipe to filter
buckets:\users> cat alice | Select-Object Name, Age

# Pipe to update
buckets:\users> cat alice | ForEach-Object { $_.Age = 31; $_ } | Set-Content alice
```

Writing multiple items to a file wraps them in an array. JSON and binary formats are auto-detected from the file extension.

The provider is created automatically on module import via `Sync-BucketDrive`. Re-create it manually after changing `$env:BUCKETS_ROOT`.

## API Reference

| Cmdlet (alias) | Description |
|----------------|-------------|
| `New-BucketObject` (`fill`) | Save objects to a bucket |
| `Get-BucketObject` (`scoop`) | Retrieve objects from buckets |
| `Set-BucketObject` (`blend`) | Update an existing object |
| `Remove-BucketObject` (`spill`) | Remove objects by key, filter, or all |
| `Copy-BucketObject` | Copy objects within or between buckets |
| `Rename-BucketObject` | Rename an object's key |
| `Move-BucketObject` | Move objects between buckets |
| `Get-Bucket` (`dip`) | List buckets (text or tree view) |
| `Get-BucketKeys` | List object keys in a bucket (Bucket + Key only) |
| `Get-BucketObjectStats` | Detailed per-object stats (format, type, size, timestamps, compression) |
| `Get-BucketStats` | Show bucket statistics (visible Path, hidden TotalSizeBytes) |
| `Remove-Bucket` (`drain`) | Remove buckets (supports wildcards, nested, WhatIf) |
| `Export-Bucket` | Export bucket to archive |
| `Import-Bucket` | Import objects from archive |
| `Set-BucketRoot` | Override session storage root |
| `Get-BucketRoot` | Query effective storage root |
| `Sync-BucketDrive` | Refresh the `buckets:` PSDrive |
