# Buckets — PowerShell Module

## Project Overview
PowerShell module for file-based PSObject storage using directory-backed "buckets".

## Priorities (in order)
1. **Safety** — don't touch what we shouldn't; protect the user from errors (path traversal guards, `SupportsShouldProcess`, empty key rejection, corrupted file warnings instead of hard failures)
2. **Cross-platform compatibility** — works on Windows, macOS, and Linux with the same behavior (path separators, case-sensitivity awareness, PowerShell 7+)
3. **Data integrity on store and retrieval** — round-trip fidelity is guaranteed; binary fallback on JSON depth overflow, compression preserves structure, corrupted files warn and return `$null` rather than crash
4. **Speed** — optimized for throughput (caching, binary as default, lazy enumeration, `ArrayList` for pipeline buffering)
5. **Filesystem abstraction** — user thinks in buckets and objects, not files and extensions; hide `.dat`/`.json` internals, no file extensions in UI, tree view shows bucket structure not filesystem hierarchy
6. **Sleek and pretty** — clean tree/list output, standardized cleanup patterns, consistent formatting

## Structure
- `Buckets/Buckets.psm1` — module code (all cmdlets)
- `Buckets/Buckets.psd1` — module manifest
- `.tests/test.ps1` — test suite
- `README.md` — documentation

## AI Agent Conventions
- When posting a plan comment on a GitHub issue, add the `agent.plan` label to the issue
- All AI agents must include the model name in their GitHub comments (e.g. `big-pickle`, `claude-sonnet-4`, `gpt-4o`)

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
| `Get-BucketObject` | `-Bucket` (positional 0, wildcards ok, all if omitted), `-Key` (positional 1), `-Match` (hashtable, supports $null), `-Filter` (scriptblock with `$_`), `-Recurse`, `-First`, `-Skip` |
| `Set-BucketObject` | `-InputObject` (pipeline binds `_BucketName`/`_BucketKey` or partial update), `-Bucket`, `-Key`, `-AsJson`, `-Compress`, `-Quiet` |
| `Remove-BucketObject` | `-Bucket`, `-Key` or `-All` (param sets), `-PassThru`, `-WhatIf` (SupportsShouldProcess) |
| `Copy-BucketObject` | `-Bucket`, `-Key`, `-DestinationBucket`, `-DestinationKey`, `-PassThru` |
| `Rename-BucketObject` | `-Bucket`, `-Key`, `-NewKey`, `-PassThru` |
| `Export-Bucket` | `-Bucket`, `-OutputFile`, `-AsJson`, `-Quiet` |
| `Import-Bucket` | `-Bucket`, `-InputFile`, `-AsJson`, `-Overwrite`, `-Quiet` |
| `Get-Bucket` | `-Name` (positional 0, substring filter) |
| `Get-BucketStats` | `-Bucket` (returns count, size, timestamps, visible Path) |
| `Get-BucketKeys` | `-Bucket` (positional 0, wildcards ok), `-Match` (returns Bucket + Key only) |
| `Get-BucketObjectStats` | `-Bucket` (positional 0, wildcards ok), `-Key` (positional 1), `-Match` (returns Format, Type, Size, LastWriteTime, IsCompressed) |
| `Remove-Bucket` | `-Bucket` (positional, wildcards ok), `-Force`, `-Confirm` (SupportsShouldProcess), `-Quiet`, `-Recurse` |

### Remove-Bucket Safety
Only removes buckets containing exclusively `.dat`/`.json` files (or empty directories). Skips buckets with other file types with a warning. Uses standard `-Confirm` support (SupportsShouldProcess). `-Force` skips confirmation entirely. Shows a colored pre-confirmation summary listing bucket names, object counts, and sizes before the standard confirmation prompt.

### Remove-BucketObject Safety
Uses `SupportsShouldProcess` for `-WhatIf` support. Parameter sets enforce `-Key` or `-All` (mutually exclusive). `-Match/-Filter` shows a pre-confirmation summary listing the first 5 matching keys and total size. Output shows `"bucket · N objects removed (matched)"` for filter operations, `"bucket · N objects removed"` for `-All`, and `"bucket/key · removed"` for single key.

### Compression
`-Compress` switch enables GZip compression for binary (`.dat`) files. Automatically detected on read via magic bytes (0x1F 0x8B). Achieves ~95% reduction on repetitive data.

## Gotchas

### Storage & Serialization
- `-Key` is a PROPERTY NAME on the input object, not the literal filename — use `-Key "_Id"` with an `_Id` property, or use `-AsTimestamp`
- `ConvertTo-Json -WarningVariable` captures truncation warnings to trigger binary fallback
- Corrupted files emit a warning and return `$null` (don't break enumeration)

### PowerShell
- `Get-ChildItem -Include "*.json", "*.dat"` fails without `-Recurse` — use separate `-Filter` calls
- `@($InputObject)` enumerates hashtables into key-value pairs — wrap single items in `System.Collections.ArrayList`
- `-Filter` scriptblock must use `$_` prefix — `Set-Variable` injection does not work with scriptblocks
- Module removes built-in aliases `Save-BucketObject` and `Get-BucketObject` at load

## Testing
```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File .tests/test.ps1      # Functional tests
pwsh -NoProfile -ExecutionPolicy Bypass -File .tests/benchmark.ps1  # Performance benchmarks
pwsh -NoProfile -ExecutionPolicy Bypass -File .tests/new.ps1       # Smoke test latest features
```
Tests wipe `.buckets` directory, then run functional tests: hashtables, nested objects, FileInfo (binary fallback), logs, JSON config, metrics, mixed formats, Copy/Rename/Export/Import, compression, -WhatIf, round-trip integrity (10/10 checks), error conditions, nested buckets with -Recurse, metadata isolation, and -Tree edge cases.

Benchmarks measure write/read throughput for 1k and 10k objects (simple + complex) in both binary and JSON formats.

## Scripts
- `.tests/test.ps1` — functional correctness tests
- `.tests/benchmark.ps1` — performance benchmarks
- `.tests/new.ps1` — smoke test for latest committed features (overwrite per commit)
- `.tests/demo/` — demo/showcase scripts
- `.tests/tools/` — utility/debug scripts (explorer, REPL, diag)

## Release Workflow
1. **Confirm with the user before releasing** — do not run the workflow without explicit confirmation
2. **Do NOT manually bump ModuleVersion** in `Buckets.psd1` — the workflow auto-bumps it
3. `git push`
4. `gh workflow run "Release Buckets" --ref main -f release_type=<patch|minor|major>`
5. Monitor at the returned URL and notify user when done

## Module Conventions
- No emojis in code or comments
- Parameter descriptions in README and help must match actual code exactly
- All exported cmdlets need full comment-based help with examples
- Binary format is the default (handles complex system objects)
- `New-BucketObject` default: progress + summary; `-Verbose` for per-object details; `-Quiet` for silence
- Default path resolves dynamically at call time via `Get-DefaultPath` (not at module load)
- `Set-BucketObject` outputs result by default; use `-Quiet` for silence
- Bucket paths cached per session via `$script:BucketPathCache`
- Path traversal protection: resolved paths must stay within root
