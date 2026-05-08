# Buckets — PowerShell Module

## Project Overview
PowerShell module for file-based PSObject storage using directory-backed "buckets".

## Structure
- `Buckets/Buckets.psm1` — module code (all cmdlets)
- `Buckets/Buckets.psd1` — module manifest
- `.tests/test.ps1` — test suite
- `README.md` — documentation

## Storage Conventions
- Default path: `$HOME/.buckets` (overridable via `-Path`)
- Default format: Binary via `PSSerializer` (`.dat`)
- JSON format: `-AsJson` switch (`.json`)
- Auto-fallback: JSON depth overflow → binary with warning
- `BinaryDepth` default: 5 (ValidateRange 1-100), `Depth` default: 20
- Arrays stored as individual files
- Key sanitization: `/`, `:`, `*`, `?`, `"`, `<`, `>`, `|`, `.`, `[`, `]` → `_`
- Empty keys after sanitization are rejected

## Cmdlets

| Cmdlet | Key Params |
|--------|-----------|
| `New-BucketObject` | `-InputObject` (pipeline), `-Bucket` (default "default"), `-Key`, `-AsJson`, `-AsTimestamp`, `-Depth`, `-BinaryDepth`, `-Compress`, `-Quiet`, `-Overwrite` |
| `Get-BucketObject` | `-Key` (positional 0), `-Bucket` (positional 1, wildcards ok, all if omitted), `-Match` (hashtable, supports $null), `-Filter` (scriptblock with `$_`) |
| `Set-BucketObject` | `-InputObject` (pipeline binds `_BucketName`/`_BucketKey` or partial update), `-Bucket`, `-Key`, `-AsJson`, `-Compress`, `-Quiet` |
| `Remove-BucketObject` | `-Bucket`, `-Key` or `-All` (param sets), `-PassThru`, `-WhatIf` (SupportsShouldProcess) |
| `Copy-BucketObject` | `-Bucket`, `-Key`, `-DestinationBucket`, `-DestinationKey`, `-PassThru` |
| `Rename-BucketObject` | `-Bucket`, `-Key`, `-NewKey`, `-PassThru` |
| `Export-Bucket` | `-Bucket`, `-OutputFile`, `-AsJson`, `-Quiet` |
| `Import-Bucket` | `-Bucket`, `-InputFile`, `-AsJson`, `-Overwrite`, `-Quiet` |
| `Get-Bucket` | `-Name` (positional 0, substring filter) |
| `Get-BucketStats` | `-Bucket` (returns count, size, timestamps) |
| `Remove-Bucket` | `-Bucket` (positional, wildcards ok), `-Force`, `-Confirm` (SupportsShouldProcess) |

### Remove-Bucket Safety
Only removes buckets containing exclusively `.dat`/`.json` files (or empty directories). Skips buckets with other file types with a warning. Uses standard `-Confirm` support (SupportsShouldProcess).

### Remove-BucketObject Safety
Uses `SupportsShouldProcess` for `-WhatIf` support. Parameter sets enforce `-Key` or `-All` (mutually exclusive).

### Compression
`-Compress` switch enables GZip compression for binary (`.dat`) files. Automatically detected on read via magic bytes (0x1F 0x8B). Achieves ~95% reduction on repetitive data.

## Gotchas — Do NOT Do These
- `Get-ChildItem -Include "*.json", "*.dat"` fails without `-Recurse` — use separate `-Filter` calls
- `@($InputObject)` enumerates hashtables into key-value pairs — wrap single items in `System.Collections.ArrayList`
- `-Filter` scriptblock must use `$_` prefix — `Set-Variable` injection does not work with scriptblocks
- `ConvertTo-Json -WarningVariable` captures truncation warnings to trigger binary fallback
- Module removes built-in aliases `Save-BucketObject` and `Get-BucketObject` at load
- `-Key` is a PROPERTY NAME on the input object, not the literal filename. Use `-Key "_Id"` with an `_Id` property, or use `-AsTimestamp`

## Release Workflow
1. `git push`
2. `gh workflow run "Release Buckets" --ref main -f release_type=<patch|minor|major>`
3. Monitor at the returned URL and notify user when done

## Testing
```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File .tests/test.ps1
```
Test script wipes `.buckets` directory, then runs: hashtables, nested objects, FileInfo (binary fallback), logs, JSON config, metrics, mixed formats, Copy/Rename/Export/Import, compression, -WhatIf, round-trip integrity (10/10 checks), error conditions, performance benchmark (1000 objects).

## Code Style
- No emojis in code or comments
- Parameter descriptions in README and help must match actual code exactly
- All exported cmdlets need full comment-based help with examples
- Binary format is the default (handles complex system objects)
- `New-BucketObject` default: progress + summary; `-Verbose` for per-object details; `-Quiet` for silence
- Default path resolves dynamically at call time via `Get-DefaultPath` (not at module load)
- `Set-BucketObject` outputs result by default; use `-Quiet` for silence
- Binary serialization auto-increments depth up to 5 if initial depth fails
- `Remove-BucketObject -All` warns on empty bucket
- Corrupted files emit warning and return $null (don't break enumeration)
- Bucket paths cached per session via `$script:BucketPathCache`
- Path traversal protection: resolved paths must stay within root
- `Depth` validated 1-100, `BinaryDepth` validated 1-10
