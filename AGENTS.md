# Buckets — PowerShell Module

## Project Overview
PowerShell module for file-based PSObject storage using directory-backed "buckets".

## Structure
- `buckets/buckets.psm1` — module code (all cmdlets)
- `buckets/buckets.psd1` — module manifest
- `tests/test.ps1` — test suite
- `README.md` — documentation

## Storage Conventions
- Default path: `$PWD/.buckets` (overridable via `-Path`)
- Default format: Binary via `PSSerializer` (`.dat`)
- JSON format: `-AsJson` switch (`.json`)
- Auto-fallback: JSON depth overflow → binary with warning
- `BinaryDepth` default: 2, `Depth` default: 20
- Arrays stored as individual files
- Key sanitization: `/`, `:`, `*`, `?`, `"`, `<`, `>`, `|`, `.`, `[`, `]` → `_`

## Cmdlets

| Cmdlet | Key Params |
|--------|-----------|
| `New-BucketObject` | `-InputObject` (pipeline), `-Bucket` (default "default"), `-Key`, `-AsJson`, `-AsTimestamp`, `-Depth`, `-BinaryDepth`, `-Quiet` |
| `Get-BucketObject` | `-Key` (positional 0), `-Bucket` (positional 1, wildcards ok, all if omitted), `-Match` (hashtable), `-Filter` (scriptblock with `$_`) |
| `Set-BucketObject` | `-InputObject` (pipeline), `-Bucket`, `-Key`, `-AsJson` |
| `Remove-BucketObject` | `-Bucket`, `-Key` or `-All` |
| `Get-Bucket` | `-Name` (positional 0, substring filter) |
| `Get-BucketStats` | `-Bucket` (returns count, size, timestamps) |
| `Remove-Bucket` | `-Bucket` (positional, wildcards ok), `-Force`, `-WhatIf` |

### Remove-Bucket Safety
Only removes buckets containing exclusively `.dat`/`.json` files (or empty directories). Skips buckets with other file types with a warning.

## Gotchas — Do NOT Do These
- `Get-ChildItem -Include "*.json", "*.dat"` fails without `-Recurse` — use separate `-Filter` calls
- `@($InputObject)` enumerates hashtables into key-value pairs — wrap single items in `System.Collections.ArrayList`
- `-Filter` scriptblock must use `$_` prefix — `Set-Variable` injection does not work with scriptblocks
- `ConvertTo-Json -WarningVariable` captures truncation warnings to trigger binary fallback
- Module removes built-in aliases `Save-BucketObject` and `Get-BucketObject` at load

## Testing
```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File .tests/test.ps1
```
Test script starts by cleaning all existing buckets. Tests: hashtables, nested objects, FileInfo (binary fallback), logs, JSON config, metrics, mixed formats.

## Code Style
- No emojis in code or comments
- Parameter descriptions in README and help must match actual code exactly
- All exported cmdlets need full comment-based help with examples
- Binary format is the default (handles complex system objects)
- `New-BucketObject` default: progress + summary; `-Verbose` for per-object details; `-Quiet` for silence
