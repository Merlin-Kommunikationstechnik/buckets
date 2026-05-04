# Buckets

<p align="center">
  <img src="logo.png" alt="Buckets Logo" width="256">
</p>

A PowerShell module for file-based PSObject storage. Store, retrieve, and manage PowerShell objects in simple "buckets" — directory-based collections with automatic serialization.

## Quick Start

```powershell
Import-Module ./Buckets

# Save objects (binary by default)
Save-BucketObject -InputObject @{ Name = "Alice"; Age = 30 } -Key Name

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

### Save-BucketObject

Saves PSObjects to a bucket. Creates the bucket if it doesn't exist.

```powershell
Save-BucketObject
    [-InputObject] <PSObject>
    [[-Bucket] <string>]
    [[-Path] <string>]
    [[-Key] <string>]
    [-Depth <int>]
    [-BinaryDepth <int>]
    [-AsTimestamp]
    [-AsJson]
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

#### Key Parameter

`-Key` takes a **property name**. The value of that property on each object becomes the filename:

```powershell
# Single object: creates Alice.json
Save-BucketObject -Bucket users -InputObject @{ Name = "Alice" } -Key Name

# Array: creates bob.json, charlie.json
$users = @(
    @{ Name = "Bob"; Age = 25 }
    @{ Name = "Charlie"; Age = 35 }
)
Save-BucketObject -Bucket users -InputObject $users -Key Name

# Special characters are sanitized (/, :, *, etc. become _)
```

Without `-Key`, each object gets a unique GUID filename.

#### Examples

```powershell
# Default bucket, binary, GUID filename
Save-BucketObject -InputObject @{ Name = "test" }

# Named bucket, keyed by property
Save-BucketObject -Bucket users -InputObject $users -Key Email

# JSON format
Save-BucketObject -Bucket users -InputObject $users -Key Name -AsJson

# Timestamp-based filenames
Get-Process | Save-BucketObject -Bucket processes -AsTimestamp

# Array (each element stored individually)
$items | Save-BucketObject -Bucket items

# Custom storage location
Save-BucketObject -Path /tmp/buckets -InputObject $data -Key Name
```

---

### Get-BucketObject

Retrieves objects from one or more buckets.

```powershell
Get-BucketObject
    [[-Bucket] <string[]>]
    [[-Path] <string>]
    [[-Key] <string>]
    [-Filter <hashtable>]
    [-Where <scriptblock>]
    [<CommonParameters>]
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Bucket` | Bucket name(s) to search | All buckets |
| `-Path` | Storage root directory | `$PWD/.buckets` |
| `-Key` | Object key to retrieve | All objects |
| `-Filter` | Hashtable of exact-match filters | — |
| `-Where` | ScriptBlock for custom filtering | — |

Retrieved objects include metadata properties: `_BucketName`, `_BucketKey`, `_BucketFile`.

#### Examples

```powershell
# All objects from all buckets
Get-BucketObject

# From a specific bucket
Get-BucketObject -Bucket users

# From multiple buckets
Get-BucketObject -Bucket users, orders

# By key
Get-BucketObject -Bucket users -Key "Alice"

# Hashtable filter (exact match)
Get-BucketObject -Bucket users -Filter @{ Role = "admin" }

# ScriptBlock filter (full expression support)
Get-BucketObject -Bucket users -Where { $_.Age -gt 30 }
Get-BucketObject -Bucket users -Where { $_.Role -eq "admin" -and $_.Score -ge 90 }
Get-BucketObject -Where { $_.Name -match "^[AD]" }

# Cross-bucket with filter
Get-BucketObject -Where { $_.Price -gt 20 }

# Search for a key across all buckets
Get-BucketObject -Key "special-item"
```

---

### Update-BucketObject

Updates an existing object in a bucket. Preserves the storage format.

```powershell
Update-BucketObject
    [-InputObject] <PSObject>
    [-Bucket] <string>
    [-Key] <string>
    [[-Path] <string>]
    [-Depth <int>]
    [-BinaryDepth <int>]
    [-AsJson]
    [<CommonParameters>]
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-InputObject` | Updated object | Required, accepts pipeline |
| `-Bucket` | Bucket name | Required |
| `-Key` | Object key to update | Required |
| `-Path` | Storage root directory | `$PWD/.buckets` |
| `-Depth` | JSON serialization depth | `20` |
| `-BinaryDepth` | Binary serialization depth | `2` |
| `-AsJson` | Force JSON format | — |

#### Examples

```powershell
# Update via pipeline
Get-BucketObject -Bucket users -Key "Alice" | ForEach-Object {
    $_.Age = 31
    $_
} | Update-BucketObject -Bucket users -Key "Alice"

# Update with explicit object
$user = Get-BucketObject -Bucket users -Key "Alice"
$user.Email = "alice@new.com"
Update-BucketObject -Bucket users -Key "Alice" -InputObject $user
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
    [[-Path] <string>]
    [[-Name] <string>]
    [<CommonParameters>]
```

#### Examples

```powershell
# List all buckets
Get-Bucket

# Filter by name pattern
Get-Bucket -Name "user"
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
Get-ChildItem / | Save-BucketObject -Bucket root -Key Name

# Retrieve and filter
Get-BucketObject -Bucket users | Where-Object { $_.Age -gt 30 }

# Retrieve, modify, update
Get-BucketObject -Bucket users | ForEach-Object {
    $_.LastUpdated = Get-Date
    $_
} | Update-BucketObject -Bucket users -Key $_._BucketKey
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
