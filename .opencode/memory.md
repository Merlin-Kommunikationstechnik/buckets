## Project Overview
- **Name**: Buckets - PowerShell module for file-based PSObject storage
- **Repo**: https://github.com/kort3x/buckets
- **Structure**: `Buckets/Buckets.psm1` (module), `Buckets/Buckets.psd1` (manifest), `tests/test.ps1`, `README.md`
- **Purpose**: Store, retrieve, and manage PowerShell objects in directory-backed "buckets" with automatic serialization

## Storage
- **Default path**: `$PWD/.buckets` (overridable via `-Path` on any cmdlet)
- **Default format**: Binary via `PSSerializer` (`.dat` extension)
- **JSON format**: Available via `-AsJson` switch (`.json` extension)
- **Auto-fallback**: JSON serialization exceeding depth limit falls back to binary with warning
- **`BinaryDepth`**: Defaults to 2 (keeps file sizes small for complex system objects)
- **`Depth`**: JSON serialization depth, defaults to 20
- **Arrays**: Stored as individual files, not as a single collection
- **Key sanitization**: Special characters (`/`, `:`, `*`, `?`, `"`, `<`, `>`, `|`, `.`, `[`, `]`) replaced with underscores

## Cmdlets
### Save-BucketObject
- `-InputObject` (mandatory, pipeline): Object(s) to store
- `-Bucket`: Bucket name, default `"default"`; auto-creates if missing
- `-Key`: Property name whose value becomes filename; defaults to GUID if omitted
- `-AsTimestamp`: Use `yyyyMMddHHmmssfff_index` as filename instead of GUID
- `-AsJson`: Store as JSON instead of binary
- `-Depth`: JSON depth (default 20), `-BinaryDepth`: Binary depth (default 2)
- Outputs: `PSCustomObject` with `Bucket`, `Key`, `FilePath`

### Get-BucketObject
- `-Bucket`: Bucket name(s); if omitted, searches all buckets under `-Path`
- `-Key`: Specific object key to retrieve
- `-Match`: Hashtable for exact-match filtering (all pairs must match)
- `-Filter`: ScriptBlock for custom filtering (use `$_` to reference properties)
- Adds metadata to returned objects: `_BucketName`, `_BucketKey`, `_BucketFile`
- Uses `Get-ChildItem -Filter` (not `-Include`) to find files - `-Include` doesn't work without `-Recurse`

### Update-BucketObject
- `-InputObject` (mandatory, pipeline): Updated object
- `-Bucket`, `-Key` (mandatory): Identifies existing object
- Preserves storage format of existing file unless `-AsJson` forces change
- JSON depth overflow falls back to binary

### Remove-BucketObject
- `-Bucket` (mandatory), `-Key` or `-All`
- Throws if neither `-Key` nor `-All` provided

### Get-Bucket
- Lists buckets with name, path, object count
- `-Name`: Substring filter on bucket name

### Get-BucketStats
- `-Bucket` (mandatory): Returns object count, total size, oldest/newest timestamps

### Remove-Bucket
- `-Bucket` (positional, mandatory): Supports exact names, multiple names, wildcard patterns (`*`, `?`)
- `-Force`: Skip confirmation prompt
- `-WhatIf`: Preview what would be removed
- **Safety**: Only removes buckets containing exclusively `.dat`/`.json` files (or empty). Buckets with other file types are skipped with a warning

## Internal Helpers (not exported)
- `Get-BucketPath`: Constructs full bucket directory path
- `Ensure-BucketExists`: Creates bucket directory if missing
- `Read-BucketFile`: Deserializes `.dat` (PSSerializer) or `.json` (ConvertFrom-Json) files
- `Get-ObjectFiles`: Finds object files by key or all files (searches both extensions)

## Gotchas & Fixes
- `Get-ChildItem -Include "*.json", "*.dat"` fails without `-Recurse` → use separate `-Filter` calls
- `@($InputObject)` enumerates hashtables into key-value pairs → wrap single items in `System.Collections.ArrayList`
- `ConvertTo-Json -WarningVariable` captures truncation warnings to trigger binary fallback
- `-Filter` scriptblock must use `$_` prefix for property access (standard `Where-Object` syntax); `Set-Variable` injection does not work with scriptblocks
- Module removes aliased `Save-BucketObject` and `Get-BucketObject` at load (built-in aliases conflict)

## Testing
- Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/test.ps1`
- Tests: hashtables, nested PSCustomObjects, FileInfo (binary fallback), logs, JSON config, metrics, mixed formats
- Script starts by cleaning all existing buckets

## Conventions
- Binary format is default to handle complex system objects (e.g., `FileInfo`)
- All exported cmdlets have full comment-based help with examples
- No emojis in code or comments
- Parameter descriptions match actual code behavior exactly
