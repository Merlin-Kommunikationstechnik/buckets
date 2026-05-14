# Output Style Guide

Canonical conventions for all Buckets module, test, and demo script output.
Follow these rules so every script looks and feels the same.

## 1. Color Palette

| Semantic role | `ForegroundColor` | Used for |
|---|---|---|
| Action / heading | `Blue` | Section headers (`[bracket title]`), file/bucket names in progress output, major `===` section dividers in tests |
| Muted / metadata | `DarkGray` | Counters (`  N records`), detail lines, timestamps, separator lines, muted descriptive text |
| Number / version | `Magenta` | Object counts, version numbers, elapsed milliseconds |
| Technical info | `Cyan` | PowerShell version string, OS name, bucket paths in module output, test section titles (diag.ps1) |
| Error | `Red` | Error messages |
| Warning / skip | `Yellow` | Skipped items, warnings, interactive menu options (tutorials) |
| Tutorial title | `White` | Main instruction block body text in tutorials |
| Code comment | `DarkGreen` | Comments in syntax-highlighted code blocks (tutorials) |

## 2. Module Color Variables

Defined at `Buckets.psm1:37`:

```powershell
$script:CPath   = 'Cyan'       # bucket paths and keys
$script:CNum    = 'Magenta'    # object counts, numbers, elapsed times
$script:CAction = 'Blue'       # actions, file names
$script:CMuted  = 'DarkGray'   # metadata, separators, muted text
$script:CError  = 'Red'        # errors
$script:CSkip   = 'Yellow'     # skipped items, warnings
```

Module cmdlets reference these variables. Test/demo scripts use literal color names.

## 3. Banner: `Write-InfoBlock`

Scripts with standalone output (test suites, benchmarks, demos) open with a banner via a locally-defined `Write-InfoBlock` function and close with one. Pipeline scripts (ingest-*, simulate-*) and interactive tools may omit banners.

### Canonical Implementation

```powershell
function Write-InfoBlock {
    param([string]$Mode, [string]$ScriptTitle = "Script")
    $mod = Get-Module Buckets
    $pwsh = "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    $os = if ($IsMacOS) { "macOS" } elseif ($IsLinux) { "Linux" } else { "Windows" }
    $sep = "=" * 52
    if ($Mode -eq "top") {
        Write-Host $sep -ForegroundColor DarkGray
        Write-Host " Buckets Module" -NoNewline -ForegroundColor Blue
        Write-Host " v$($mod.Version)" -NoNewline -ForegroundColor Magenta
        Write-Host " $ScriptTitle" -ForegroundColor DarkGray
        Write-Host " $startTs" -NoNewline -ForegroundColor DarkGray
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host $pwsh -NoNewline -ForegroundColor Cyan
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host $os -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray
    }
    else {
        $elapsed = $sw.ElapsedMilliseconds
        $endTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host $sep -ForegroundColor DarkGray
        Write-Host " Done" -NoNewline -ForegroundColor Blue
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host "${elapsed}ms" -ForegroundColor Magenta
        Write-Host " $endTs" -NoNewline -ForegroundColor DarkGray
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host $pwsh -NoNewline -ForegroundColor Cyan
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host $os -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray
    }
}
```

### Customization Points

| Aspect | Rule |
|---|---|
| Script title | Pass as `-ScriptTitle` parameter. DarkGray, appended after version on the second line. |
| Footer label | Use `" Done"` for most scripts. Use `" Tests Complete"` only for `test.ps1`. |
| Elapsed time unit | Milliseconds (`"${elapsed}ms"`) for everything. Exception: long-running demos may use seconds (`"$([math]::Round($elapsed, 1))s"`). |
| Prerequisite variables | `$sw` (stopwatch) and `$startTs` (timestamp string) must be defined at script scope before the banner. |

### Script Titles (existing usage)

| Script | Title string | Notes |
|---|---|---|---|
| `.tests/test.ps1` | `"Test Suite"` | Has banner |
| `.tests/benchmark.ps1` | `"Benchmarks"` | Has banner |
| `.tests/perfcomp.ps1` | `"Perf Comparison"` | Has banner |
| `.tests/data.ps1` | `"Sysadmin Data"` | Has banner |
| `.tests/output.ps1` | — | Builds own output, no banner |
| `.tests/smoke.ps1` | — | No banner |
| `.tests/tools/explorer.ps1` | `"Explorer"` | Inline banner (no `Write-InfoBlock`) |
| `.tests/tools/repl.ps1` | `"REPL"` | Inline banner (no `Write-InfoBlock`) |
| `.tests/demo/demo-ui.ps1` | `"UI/UX Demo"` | Has banner |
| `.tests/demo/cim-inventory.ps1` | `"CIM Inventory"` | Has banner |
| `.tests/demo/ad-simulator.ps1` | `"AD Simulator"` | Has banner |
| `.tests/demo/demo-app.ps1` | — | Interactive app, no banner |
| `.tests/demo/ingest-eventlog.ps1` | — | Pipeline script, no banner |
| `.tests/demo/ingest-syslog.ps1` | — | Pipeline script, no banner |
| `.tests/demo/log-query-examples.ps1` | — | No banner |
| `.tests/demo/multi-emit-demo.ps1` | — | No banner (uses `===` header) |
| `.tests/demo/simulate-syslog.ps1` | — | Pipeline script, no banner |

### Required Script Prerequisites

```powershell
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
```

## 4. Section Headers

```powershell
Write-Host "[section-name]" -ForegroundColor Blue
Write-Host "`n[section-name]" -ForegroundColor Blue   # when following another section
```

- Bracketed lowercase-with-hyphens name
- Blue foreground
- Prefixed with newline when it follows another section

## 5. Detail / Count Lines

```powershell
Write-Host "  $($collection.Count) record-type records" -ForegroundColor DarkGray
```

- Exactly two-space indent
- DarkGray foreground
- `<value> <descriptive label> records`

## 6. Field Separator in Status Lines

The standard separator between fields is a middle dot surrounded by spaces:

```
" · "
```

This is `U+00B7` (middle dot). Used in `Write-InfoBlock`, module progress lines, and any multi-field status output.

## 7. Separator Lines

| Context | Character | Width | Color |
|---|---|---|---|
| Banner / footer | `=` | 52 | DarkGray |
| Major test sections | `=` | 40 | Blue |
| Tutorial pause | `─` (U+2500) | 55 | DarkGray |

## 8. Relationship Query Format

```powershell
Write-Host "`n  Q<N>: <description>" -ForegroundColor DarkGray
```

- Preceded by newline
- Two-space indent
- `Q<N>:` prefix
- DarkGray

## 9. Summary Block Format

```powershell
Write-Host "  Buckets created: <N>" -ForegroundColor DarkGray
Write-Host "  Objects created: <N>" -ForegroundColor DarkGray
```

- Two-space indent
- DarkGray
- Colon separator between label and value

## 10. Tutorial Conventions

- Main instruction text: `White`
- Menu options: `Yellow`
- Separator bars: `DarkGray`, `─` character, width 55
- Syntax-highlighted code: `tut-write-code` function with token-based coloring
  - Commands/operators: `Yellow`, `Cyan`
  - Parameters: `Cyan`
  - Variables: `Green`
  - Strings: `DarkYellow`
  - Comments: `DarkGreen`
  - Numbers: `Yellow`
- Pause footer: `"  [Enter] next · [q] quit > "` in DarkGray
