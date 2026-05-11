# `-Expand` / `-Collapse` Design Spec

## Concept

Allow structured data (nested hashtables, arrays, scalars) to be decomposed into
a bucket hierarchy on write (`fill -Expand`) and reconstructed back to the
original structure on read (`spill -Collapse`).

## Write side: `New-BucketObject -Expand`

Recursively walks the input and stores every scalar leaf as a separate file.
The structure determines the path: hashtable keys become subdirectory names,
array indices (or `-KeyProperty` values) become subdirectory names.

### Expansion rules

| Input | Behavior |
|---|---|
| **IDictionary** at structural level (not an array element) | Each key becomes a path component; recurse into the value |
| **IDictionary** that is an **array element** | Store as **single object** using `-KeyProperty` for the filename |
| **IEnumerable** (not string, not dict) at any level | Expand each element; write `_array.json` with ordered key list |
| **Scalar** | Store as leaf file at the accumulated path (last component = file key) |

### Array marker: `_array.json`

When an array is expanded, a marker file `_array.json` is written in the same
bucket directory. Content is a simple JSON array of key names in original
order: `["Alice","Bob"]` or `["0","1","2"]`.

This marker is the **only** way to distinguish an expanded array from a
naturally occurring set of files with numeric or named keys.

- Empty arrays → `_array.json` → `[]`, no data files
- Single-element arrays → marker prevents ambiguity with single-key hashtable

### Examples

```powershell
# Simple array of scalars
@("a", "b", "c") | fill -Bucket "letters" -Expand
# → letters/0.dat       ("a")
# → letters/1.dat       ("b")
# → letters/2.dat       ("c")
# → letters/_array.json → ["0","1","2"]

# Flat hashtable
@{ theme = "dark"; lang = "de" } | fill -Bucket "cfg" -Expand
# → cfg/theme.dat   ("dark")
# → cfg/lang.dat    ("de")
#   (no _array.json → reconstructs as hashtable)

# Nested: array of objects + scalar hashtable
$app = @{
    users  = @(
        @{ Name = "Alice"; Role = "Admin" }
        @{ Name = "Bob";   Role = "User"  }
    )
    config = @{ theme = "dark"; lang = "de" }
}
$app | fill -Bucket "app" -Expand -KeyProperty Name
# → app/users/Alice.dat    (@{Name="Alice";Role="Admin"})
# → app/users/Bob.dat      (@{Name="Bob";Role="User"})
# → app/users/_array.json  → ["Alice","Bob"]
# → app/config/theme.dat   ("dark")
# → app/config/lang.dat    ("de")
```

### Parameter interactions

| Param | How it propagates |
|---|---|
| `-KeyProperty` | Used to derive array element sub-paths when elements are hashtables |
| `-Key` | Literal key for array elements (overrides `-KeyProperty` if both set) |
| `-AsTimestamp` | Used for auto-generated keys when path has only one component |
| `-Overwrite` | Passed to each `Save-BucketFile` call |
| `-AsBinary` / `-Compress` | Passed to each leaf save |
| `-Quiet` | Suppresses summary output |
| `-Depth` / `-BinaryDepth` | Passed to each `Save-BucketFile` call |

## Read side: `Get-BucketObject -Collapse`

Walks the bucket tree and reconstructs the original structure from the expanded
files and `_array.json` markers.

### Collapse algorithm

1. List all `.dat`/`.json` leaf objects in the bucket (non-recursive)
2. List all sub-buckets (child directories containing bucket files)
3. If `_array.json` exists in this bucket:
   - Read the ordered key list
   - For each key: if a leaf exists with that key, include it; if a sub-bucket
     exists with that name, recursively collapse it
   - Return the result as `[array]`
4. If no `_array.json`:
   - Collect all leaf objects as key→value pairs
   - For each sub-bucket: key → recursively collapsed value
   - Return the result as `[hashtable]`

### Examples

```powershell
spill -Bucket "app" -Collapse -KeyProperty Name
# → @{
#       users  = @(@{Name="Alice";Role="Admin"}, @{Name="Bob";Role="User"})
#       config = @{ theme = "dark"; lang = "de" }
#   }

spill -Bucket "letters" -Collapse
# → @("a", "b", "c")
```

### Behavior on non-expanded buckets

If no `_array.json` is found and the bucket has leaf objects:
- Return a hashtable keyed by object key
- Falls back gracefully to existing behavior (objects returned individually
  when `-Collapse` is not specified)

## Implementation plan

### Files to modify
- `Buckets/Buckets.psm1`

### New-BucketObject changes (~120-180 lines)

1. Add `[switch]$Expand` parameter
2. In `process` block, when `-Expand`:
   - Call new `Expand-IntoBuckets` helper instead of existing logic
   - Skip `Ensure-BucketExists` in `begin` (handled per-leaf)
3. New helper `Expand-IntoBuckets`:
   - Recursive tree walker handling IDictionary, IEnumerable, scalars
   - Accepts `$Item`, `$FullPath` (accumulated bucket path), `$IsArrayElement`
   - For arrays: writes `_array.json` via `Save-ArrayMarker`
4. `Save-ArrayMarker`:
   - Serializes key list as JSON to `$bucketPath/_array.json`
5. Leaf storage via existing `Save-BucketFile`
6. Summary: `"Expanded N leaf values across M buckets"`
7. `Expand-IntoBuckets` for IDictionary with `$IsArrayElement`:
   - `$true` → store as single object via Save-BucketFile
   - `$false` → iterate key-value pairs, recurse into each value

### Get-BucketObject changes (~80-120 lines)

1. Add `[switch]$Collapse` parameter
2. When `-Collapse`, call new `Collapse-Bucket` helper
3. New helper `Collapse-Bucket`:
   - `Get-BucketObject -Bucket $name` for leaf objects (+metadata)
   - `Get-Bucket -Name "$name/*"` for sub-buckets
   - Check for `_array.json` via `Test-Path`
   - Reconstruct array or hashtable accordingly
4. Recursive for nested sub-buckets

### Edge cases

| Case | Handling |
|---|---|
| Empty hashtable | No keys → nothing stored, silently skipped |
| Null values | Skipped (existing behavior via `if ($null -eq $InputObject)`) |
| Key sanitization failure (all `_`) | Skipped with verbose message |
| Circular references | Depth limit (100) + HashSet with reference equality |
| PSObject / custom object | Treated as scalar (not expanded); stored via serialization |
| Multiple pipeline items | Each expanded independently; `-Overwrite` controls conflicts |
| `-Collapse` with `-Key` | Not supported (partial read can't reconstruct); warn or ignore |
| Non-expanded bucket + `-Collapse` | Return as hashtable (best-effort) |
| Corrupted `_array.json` | Warning, fall back to hashtable reconstruction |
