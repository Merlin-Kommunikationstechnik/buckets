#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Buckets Module — Interactive Tutorial
.DESCRIPTION
    Chapter-by-chapter walkthrough of the Buckets module. Each chapter
    introduces a concept, explains the why, and demonstrates the how.
    Run the whole script or jump to a chapter by setting $chapter.
#>

param(
    [int]$Chapter = 1
)

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../../Buckets" -Force

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$createdBuckets = [System.Collections.ArrayList]::new()

function Use-Bucket {
    param([string]$Bucket)
    $null = $createdBuckets.Add($Bucket)
}

function Write-ChapterHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Blue
    Write-Host "║  $($Title.PadRight(40))║" -ForegroundColor Blue
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Blue
}

function Write-Section {
    param([string]$Number, [string]$Title)
    Write-Host ""
    Write-Host "── $Number $Title ────────────────────────" -ForegroundColor Blue
}

# ============================================================
# Chapter 1: Introduction
# ============================================================
$mod = Get-Module Buckets
$pwsh = "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
$os = if ($IsMacOS) { "macOS" } elseif ($IsLinux) { "Linux" } else { "Windows" }
$sep = "=" * 52

Write-Host $sep -ForegroundColor DarkGray
Write-Host " Buckets Module" -NoNewline -ForegroundColor Blue
Write-Host " v$($mod.Version)" -NoNewline -ForegroundColor Magenta
Write-Host " Tutorial" -ForegroundColor DarkGray
Write-Host " $startTs" -NoNewline -ForegroundColor DarkGray
Write-Host " · " -NoNewline -ForegroundColor DarkGray
Write-Host $pwsh -NoNewline -ForegroundColor Cyan
Write-Host " · " -NoNewline -ForegroundColor DarkGray
Write-Host $os -ForegroundColor DarkGray
Write-Host $sep -ForegroundColor DarkGray

Write-ChapterHeader "Chapter 1: Introduction"

Write-Section "1.1" "What is Buckets?"

Write-Host ""
Write-Host "  Buckets is a PowerShell module for file-based PSObject storage." -ForegroundColor White
Write-Host "  Every object is a file, every bucket is a folder. There is no" -ForegroundColor DarkGray
Write-Host "  database, no daemon, no config file — just the filesystem." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  ┌─────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
Write-Host "  │" -NoNewline -ForegroundColor DarkGray
Write-Host "  Store PSObjects as files   " -NoNewline -ForegroundColor White
Write-Host "                     │" -ForegroundColor DarkGray
Write-Host "  │" -NoNewline -ForegroundColor DarkGray
Write-Host "  Read them back as objects   " -NoNewline -ForegroundColor White
Write-Host "                     │" -ForegroundColor DarkGray
Write-Host "  │" -NoNewline -ForegroundColor DarkGray
Write-Host "  Organize in directory-backed buckets " -NoNewline -ForegroundColor White
Write-Host "        │" -ForegroundColor DarkGray
Write-Host "  │" -NoNewline -ForegroundColor DarkGray
Write-Host "  Share by copying the folder  " -NoNewline -ForegroundColor White
Write-Host "                     │" -ForegroundColor DarkGray
Write-Host "  └─────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Two storage formats:" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Binary" -NoNewline -ForegroundColor Cyan
Write-Host "  —  " -NoNewline -ForegroundColor DarkGray
Write-Host ".dat" -NoNewline -ForegroundColor Magenta
Write-Host "  via PSSerializer (default, fast, handles complex objects)" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "JSON" -NoNewline -ForegroundColor Cyan
Write-Host "   —  " -NoNewline -ForegroundColor DarkGray
Write-Host ".json" -NoNewline -ForegroundColor Magenta
Write-Host " via " -NoNewline -ForegroundColor DarkGray
Write-Host "-AsJson" -NoNewline -ForegroundColor Cyan
Write-Host " (readable, portable)" -ForegroundColor DarkGray

Write-Section "1.2" "Why Buckets?"

Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Persistent" -NoNewline -ForegroundColor Green
Write-Host "  — objects outlive your PowerShell session" -ForegroundColor DarkGray
Write-Host "            write today, read tomorrow, read next week" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Shareable" -NoNewline -ForegroundColor Green
Write-Host "  — buckets are folders on disk; copy them, sync them," -ForegroundColor DarkGray
Write-Host "            commit them to version control" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Composable" -NoNewline -ForegroundColor Green
Write-Host "  — pipeline in, pipeline out" -ForegroundColor DarkGray
Write-Host "            " -NoNewline
Write-Host "Get-Process | fill -Bucket procs" -NoNewline -ForegroundColor Cyan
Write-Host "  just works" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Browsable" -NoNewline -ForegroundColor Green
Write-Host "  — " -NoNewline -ForegroundColor DarkGray
Write-Host "Get-Bucket -Tree" -NoNewline -ForegroundColor Cyan
Write-Host "  shows the full hierarchy at a glance" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Self-describing" -NoNewline -ForegroundColor Green
Write-Host "  — filenames are keys, directories structure your data," -ForegroundColor DarkGray
Write-Host "            JSON files are human-readable" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Expand / Collapse" -NoNewline -ForegroundColor Green
Write-Host "  — decompose nested structures into browsable" -ForegroundColor DarkGray
Write-Host "            directory trees, reconstruct on read" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Cross-platform" -NoNewline -ForegroundColor Green
Write-Host "  — PowerShell 7+ on Windows, macOS, Linux" -ForegroundColor DarkGray
Write-Host "            same behaviour everywhere" -ForegroundColor DarkGray

Write-Section "1.3" "How does it work?"

Write-Host ""
Write-Host "  Every bucket is a directory under " -NoNewline -ForegroundColor DarkGray
Write-Host "`$HOME/.buckets" -NoNewline -ForegroundColor Cyan
Write-Host " (overridable via " -NoNewline -ForegroundColor DarkGray
Write-Host "-Path" -NoNewline -ForegroundColor Cyan
Write-Host ")." -ForegroundColor DarkGray
Write-Host "  Each object is one file — " -NoNewline -ForegroundColor DarkGray
Write-Host ".dat" -NoNewline -ForegroundColor Magenta
Write-Host " (binary, default) or " -NoNewline -ForegroundColor DarkGray
Write-Host ".json" -NoNewline -ForegroundColor Magenta
Write-Host " (opt-in)." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  \$HOME/.buckets/" -ForegroundColor Cyan
Write-Host "    users/" -ForegroundColor Cyan
Write-Host "      Alice.dat" -NoNewline -ForegroundColor DarkGray
Write-Host "      ← key: Alice" -ForegroundColor DarkGray
Write-Host "      Bob.dat" -NoNewline -ForegroundColor DarkGray
Write-Host "        ← key: Bob" -ForegroundColor DarkGray
Write-Host "    config/" -ForegroundColor Cyan
Write-Host "      app.json" -NoNewline -ForegroundColor DarkGray
Write-Host "       ← JSON format, key: app" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Four core cmdlets:" -ForegroundColor DarkGray
Write-Host ""
Write-Host "    " -NoNewline
Write-Host "fill" -NoNewline -ForegroundColor Green
Write-Host "    · " -NoNewline -ForegroundColor DarkGray
Write-Host "New-BucketObject" -NoNewline -ForegroundColor Cyan
Write-Host "      write objects to a bucket" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "spill" -NoNewline -ForegroundColor Green
Write-Host "   · " -NoNewline -ForegroundColor DarkGray
Write-Host "Get-BucketObject" -NoNewline -ForegroundColor Cyan
Write-Host "      read objects from a bucket" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "dip" -NoNewline -ForegroundColor Green
Write-Host "    · " -NoNewline -ForegroundColor DarkGray
Write-Host "Set-BucketObject" -NoNewline -ForegroundColor Cyan
Write-Host "      update an existing object" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "rmo" -NoNewline -ForegroundColor Green
Write-Host "   · " -NoNewline -ForegroundColor DarkGray
Write-Host "Remove-BucketObject" -NoNewline -ForegroundColor Cyan
Write-Host "  delete an object" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Supporting cmdlets:" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Get-Bucket" -NoNewline -ForegroundColor Cyan
Write-Host "          list / tree view of all buckets" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Get-BucketStats" -NoNewline -ForegroundColor Cyan
Write-Host "    object count, size, timestamps per bucket" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Get-BucketKeys" -NoNewline -ForegroundColor Cyan
Write-Host "      list keys matching a pattern" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Copy-BucketObject" -NoNewline -ForegroundColor Cyan
Write-Host "  copy objects between buckets" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Rename-BucketObject" -NoNewline -ForegroundColor Cyan
Write-Host "  rename an object key" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Export-Bucket" -NoNewline -ForegroundColor Cyan
Write-Host "      export to CLIXML or JSON" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Import-Bucket" -NoNewline -ForegroundColor Cyan
Write-Host "      import from CLIXML or JSON" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Default path: " -NoNewline -ForegroundColor DarkGray
Write-Host "\$HOME/.buckets" -NoNewline -ForegroundColor Cyan
Write-Host "  ·  Override: " -NoNewline -ForegroundColor DarkGray
Write-Host "-Path" -NoNewline -ForegroundColor Cyan
Write-Host "  ·  Binary depth: " -NoNewline -ForegroundColor DarkGray
Write-Host "5" -NoNewline -ForegroundColor Magenta
Write-Host "  ·  JSON depth: " -NoNewline -ForegroundColor DarkGray
Write-Host "20" -ForegroundColor Magenta

Write-Section "Next"
Write-Host ""
Write-Host "  This concludes the introduction. The next chapter covers" -ForegroundColor DarkGray
Write-Host "  writing your first objects with " -NoNewline -ForegroundColor DarkGray
Write-Host "New-BucketObject" -NoNewline -ForegroundColor Cyan
Write-Host "." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Run the tutorial with a specific chapter:" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "pwsh .tests/demo/tutorial.ps1 -Chapter 2" -ForegroundColor Cyan

# Cleanup
foreach ($b in $createdBuckets) {
    Remove-Bucket $b -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse
}

$elapsed = $sw.Elapsed.TotalSeconds
$endTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host $sep -ForegroundColor DarkGray
Write-Host " Done" -NoNewline -ForegroundColor Blue
Write-Host " · " -NoNewline -ForegroundColor DarkGray
Write-Host "$([math]::Round($elapsed, 1))s" -ForegroundColor Magenta
Write-Host " $endTs" -NoNewline -ForegroundColor DarkGray
Write-Host " · " -NoNewline -ForegroundColor DarkGray
Write-Host $pwsh -NoNewline -ForegroundColor Cyan
Write-Host " · " -NoNewline -ForegroundColor DarkGray
Write-Host $os -ForegroundColor DarkGray
Write-Host $sep -ForegroundColor DarkGray
