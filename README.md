# Buckets

<p align="center">
  <img src="logo.png" alt="Buckets Logo" width="256">
</p>

A PowerShell module for file-based PSObject storage. Store, retrieve, and manage PowerShell objects in simple "buckets" — directory-based collections with automatic serialization.

## Quick Start

```powershell
Import-Module ./Buckets

# Save objects (binary by default)
New-BucketObject -InputObject @{ Name = "Alice"; Age = 30 } -Key Name

# Retrieve
Get-BucketObject | Select-Object Name, Age

# List buckets
Get-Bucket
```

## Storage Format

| Format | Default | Switch | Extension |
|--------|---------|--------|-----------|
| **Binary** (PSSerializer) | Yes | — | `.dat` |
| **JSON** | No | `-AsJson` | `.json` |

Objects that exceed JSON depth are automatically saved as binary with a warning. Use `-BinaryDepth` to control binary serialization detail (default: `2`).

## Cmdlets

### New-BucketObject

Saves PSObjects to a bucket. Creates the bucket if it doesn't exist.

```powershell
New-BucketObject
    [-InputObject] <PSObject>
    [[-Bucket] <string>]
    [[-Path] <string>]
    [[-Key] <string>]
    [-Depth <int>]
    [-BinaryDepth <int>]
    [-AsTimestamp]
    [-AsJson]
    [-Quiet]
    [<CommonParameters>]
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-InputObject` | Object(s) to store | Required, accepts pipeline |
| `-Bucket` | Bucket name | `"default"` |
| `-Path` | Storage root directory | `$PWD/.buckets` |
| `-Key` | Property name whose value becomes the filename | GUID |
| `-Depth` | JSON serialization depth | `20` |
| `-BinaryDepth` | Binary serialization depth | `2` |
| `-AsTimestamp` | Use timestamp as filename | `false` |
| `-AsJson` | Store as JSON instead of binary | `false` |
| `-Quiet` | Suppress all output (no progress, no summary) | `false` |
| `-Overwrite` | Overwrite existing objects with the same key | `false` |
| `-ArrayTracking` | Tag array items for later reconstruction via `-GroupArrays` | `false` |

Default behaviour: shows a progress indicator and final summary. Use `-Verbose` for per-object details.

#### Key Parameter

`-Key` takes a **property name**. The value of that property on each object becomes the filename:

```powershell
# Single object: creates Alice.dat
New-BucketObject -Bucket users -InputObject @{ Name = "Alice" } -Key Name

# Array: creates bob.dat, charlie.dat
$users = @(
    @{ Name = "Bob"; Age = 25 }
    @{ Name = "Charlie"; Age = 35 }
)
New-BucketObject -Bucket users -InputObject $users -Key Name

# Or pipe the array (add -ArrayTracking for grouping metadata)
$users | New-BucketObject -Bucket users -Key Name
$users | New-BucketObject -Bucket users -Key Name -ArrayTracking

# Special characters are sanitized (/, :, *, etc. become _)
```

Without `-Key`, each object gets a unique GUID filename.

#### Examples

```powershell
# Default: progress bar and summary
New-BucketObject -InputObject @{ Name = "test" }

# Verbose: per-object details
New-BucketObject -InputObject @{ Name = "test" } -Verbose

# Quiet: silent, no output
New-BucketObject -InputObject @{ Name = "test" } -Quiet

# Named bucket, keyed by property
New-BucketObject -Bucket users -InputObject $users -Key Email

# JSON format
New-BucketObject -Bucket users -InputObject $users -Key Name -AsJson

# Timestamp-based filenames
Get-Process | New-BucketObject -Bucket processes -AsTimestamp

# Array (each element stored individually)
$items | New-BucketObject -Bucket items

# Custom storage location
New-BucketObject -Path /tmp/buckets -InputObject $data -Key Name
```

---

### Get-BucketObject

Retrieves objects from one or more buckets.

```powershell
Get-BucketObject
    [[-Key] <string>]
    [[-Bucket] <string[]>]
    [-Path <string>]
    [-Match <hashtable>]
    [-Filter <scriptblock>]
    [-First <int>]
    [-Skip <int>]
    [-GroupArrays]
    [<CommonParameters>]
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Key` | Object key to retrieve | All objects |
| `-Bucket` | Bucket name(s) to search | All buckets |
| `-Path` | Storage root directory | `$PWD/.buckets` |
| `-Match` | Hashtable of exact-match filters | — |
| `-Filter` | ScriptBlock for custom filtering | — |
| `-First` | Return only the first N objects (or array groups) | — |
| `-Skip` | Skip the first N objects (or array groups) | — |
| `-GroupArrays` | Reassemble arrays stored as individual files | `false` |

Retrieved objects include metadata properties: `_BucketName`, `_BucketKey`, `_BucketFile`. Objects that were saved as part of an array also include `_ArrayId` and `_ArrayIndex` for grouping.

#### Array Tracking

Use `-ArrayTracking` to tag array items with `_ArrayId` (shared GUID) and `_ArrayIndex` (original position) so they can be reconstructed later:

```powershell
# Save array with tracking
$items = @(
    @{ _Id = "a1"; Name = "First" }
    @{ _Id = "a2"; Name = "Second" }
    @{ _Id = "a3"; Name = "Third" }
)
New-BucketObject -Bucket orders -InputObject $items -Key _Id -ArrayTracking

# Or pipe with tracking
$items | New-BucketObject -Bucket orders -Key _Id -ArrayTracking

# Read back with grouping
$result = Get-BucketObject -Bucket orders -GroupArrays
$result._ArrayItems  # The reassembled array, sorted by original index
```

Without `-ArrayTracking`, objects are saved individually with no grouping metadata.

`-GroupArrays` returns wrapper objects with:
- `_ArrayGroup` — `$true` for array groups, absent for standalone objects
- `_ArrayItems` — the reassembled array (sorted by `_ArrayIndex`), with `_ArrayId`/`_ArrayIndex` stripped

#### Examples

```powershell
# All objects from all buckets
Get-BucketObject

# From a specific bucket
Get-BucketObject -Bucket users

# From multiple buckets
Get-BucketObject -Bucket users, orders

# Wildcard patterns
Get-BucketObject -Bucket "user*"
Get-BucketObject "Alice" "*_log"

# By key
Get-BucketObject "Alice"
Get-BucketObject "Alice" users

# Hashtable filter (exact match)
Get-BucketObject -Bucket users -Match @{ Role = "admin" }

# ScriptBlock filter (full expression support)
Get-BucketObject -Bucket users -Filter { $_.Age -gt 30 }
Get-BucketObject -Bucket users -Filter { $_.Role -eq "admin" -and $_.Score -ge 90 }
Get-BucketObject -Filter { $_.Name -match "^[AD]" }

# Cross-bucket with filter
Get-BucketObject -Filter { $_.Price -gt 20 }

# Search for a key across all buckets
Get-BucketObject -Key "special-item"

# Reassemble stored arrays
$result = Get-BucketObject -Bucket orders -GroupArrays
$result._ArrayItems  # Array items in original order

# Mixed: array groups + standalone objects
Get-BucketObject -Bucket orders -GroupArrays | ForEach-Object {
    if ($_.PSObject.Properties['_ArrayGroup'] -and $_._ArrayGroup) {
        "Array group: $($_._ArrayItems.Count) items"
    }
    else {
        "Standalone: $($_._Id)"
    }
}
```

---

### Set-BucketObject

Updates an existing object in a bucket. Preserves the storage format.

```powershell
Set-BucketObject
    [-InputObject] <PSObject>
    [[-Bucket] <string>]
    [[-Key] <string>]
    [[-Path] <string>]
    [-Depth <int>]
    [-BinaryDepth <int>]
    [-AsJson]
    [<CommonParameters>]
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-InputObject` | Updated object. Pipeline input binds `_BucketName` and `_BucketKey` automatically | Required, accepts pipeline |
| `-Bucket` | Bucket name (optional when piped from `Get-BucketObject`) | Bound from pipeline or required |
| `-Key` | Object key (optional when piped from `Get-BucketObject`) | Bound from pipeline or required |
| `-Path` | Storage root directory | `$PWD/.buckets` |
| `-Depth` | JSON serialization depth | `20` |
| `-BinaryDepth` | Binary serialization depth | `2` |
| `-AsJson` | Force JSON format | — |

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
    [<CommonParameters>]
```

#### Examples

```powershell
# Remove by key
Remove-BucketObject -Bucket users -Key "Alice"

# Remove all objects from bucket
Remove-BucketObject -Bucket users -All
```

---

### Get-Bucket

Lists available buckets with object counts.

```powershell
Get-Bucket
    [[-Name] <string>]
    [-Path <string>]
    [<CommonParameters>]
```

#### Examples

```powershell
# List all buckets
Get-Bucket

# Filter by name pattern
Get-Bucket "user"
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

#### Examples

```powershell
Get-BucketStats -Bucket users
```

Output:
```
Name         : users
Path         : /path/to/users
ObjectCount  : 5
TotalSize    : 12.5 KB
OldestObject : 2024-01-15 10:30:00
NewestObject : 2024-01-20 14:22:00
```

---

### Remove-Bucket

Removes one or more buckets and all their contents. Supports wildcard patterns.

```powershell
Remove-Bucket
    [-Bucket] <string[]>
    [[-Path] <string>]
    [-Force]
    [-WhatIf]
    [<CommonParameters>]
```

| Parameter | Description |
|-----------|-------------|
| `-Bucket` | Bucket name(s) or wildcard patterns |
| `-Path` | Storage root directory |
| `-Force` | Skip confirmation prompt |
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

# All buckets (with confirmation)
Remove-Bucket *

# Preview without removing
Remove-Bucket * -WhatIf
```

## Pipeline Support

Most cmdlets accept pipeline input:

```powershell
# Save pipeline output directly
Get-ChildItem / | New-BucketObject -Bucket root -Key Name

# Retrieve and filter
Get-BucketObject -Bucket users | Where-Object { $_.Age -gt 30 }

# Retrieve, modify, update
Get-BucketObject -Bucket users | ForEach-Object {
    $_.LastUpdated = Get-Date
    $_
} | Set-BucketObject
```

## Storage Structure

```
.buckets/
├── users/
│   ├── alice.dat          (binary)
│   ├── bob.dat            (binary)
│   └── charlie.json       (JSON, saved with -AsJson)
├── orders/
│   ├── 20240101.dat       (GUID key)
│   └── ORD-001.dat        (custom key)
└── default/
    ├── a1b2c3.dat
    └── d4e5f6.dat
```

## Importing the Module

```powershell
# From current directory
Import-Module ./Buckets

# From module path
Import-Module Buckets

# Dot-source for development
. ./Buckets/Buckets.psm1
```
