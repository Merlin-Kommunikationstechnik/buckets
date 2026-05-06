#!/usr/bin/env pwsh
# Buckets Module — Interactive Test / Demo / Debug REPL
# A command-line playground for testing, demoing, and debugging the Buckets module.

$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot "../Buckets"

if (-not (Get-Module Buckets)) {
    Import-Module $modulePath -Force
}
else {
    Import-Module $modulePath -Force
}

# --- Helpers ---

function Clear-Buckets {
    $bucketDir = Join-Path $PWD.Path ".buckets"
    if (Test-Path $bucketDir) {
        Remove-Item $bucketDir -Recurse -Force
        Write-Host "  Wiped .buckets directory." -ForegroundColor DarkGray
    }
    else {
        Write-Host "  No .buckets directory found." -ForegroundColor DarkGray
    }
}

function Show-Buckets {
    $buckets = @(Get-Bucket -WarningAction SilentlyContinue)
    if ($buckets.Count -eq 0) {
        Write-Host "  No buckets found." -ForegroundColor DarkGray
        return
    }
    Write-Host ""
    $buckets | ForEach-Object {
        $stats = Get-BucketStats -Bucket $_.Name -WarningAction SilentlyContinue
        Write-Host "  $($_.Name)" -ForegroundColor Cyan -NoNewline
        Write-Host " — $($stats.ObjectCount) objects, $($stats.TotalSize)" -ForegroundColor DarkGray
    }
}

function Show-BucketObjects {
    $bucket = Read-Host "  Bucket name (or Enter for all)"
    if ([string]::IsNullOrWhiteSpace($bucket)) {
        $results = @(Get-BucketObject -WarningAction SilentlyContinue)
    }
    else {
        $results = @(Get-BucketObject -Bucket $bucket -WarningAction SilentlyContinue)
    }
    if ($results.Count -eq 0) {
        Write-Host "  No objects found." -ForegroundColor DarkGray
        return
    }
    Write-Host "`n  [$($results.Count) objects]" -ForegroundColor Cyan
    foreach ($obj in $results) {
        $key = if ($obj._BucketKey) { $obj._BucketKey } else { "(unknown)" }
        $file = if ($obj._BucketFile) { [System.IO.Path]::GetExtension($obj._BucketFile) } else { "" }
        Write-Host "  [$key$file]" -ForegroundColor Yellow -NoNewline
        $obj.PSObject.Properties | Where-Object { $_.Name -notmatch "^_" } | ForEach-Object {
            Write-Host " $($_.Name)=$($_.Value)" -ForegroundColor DarkGray -NoNewline
        }
        Write-Host ""
    }
}

function Show-BucketKeys {
    $bucket = Read-Host "  Bucket name"
    if ([string]::IsNullOrWhiteSpace($bucket)) { return }
    $keys = @(Get-BucketKeys -Bucket $bucket -WarningAction SilentlyContinue)
    if ($keys.Count -eq 0) {
        Write-Host "  No keys found." -ForegroundColor DarkGray
        return
    }
    Write-Host "`n  [$($keys.Count) keys]" -ForegroundColor Cyan
    $keys | ForEach-Object {
        $size = if ($_.Size -gt 1024) { "$([math]::Round($_.Size/1024,1)) KB" } else { "$($_.Size) B" }
        Write-Host "  $($_.Key)" -ForegroundColor Yellow -NoNewline
        Write-Host " ($size)" -ForegroundColor DarkGray
    }
}

function QuickSave {
    Write-Host "`n  --- Quick Save ---" -ForegroundColor Cyan
    $bucket = Read-Host "  Bucket name"
    $key = Read-Host "  Key (or Enter for auto-key)"
    $asJson = Read-Host "  JSON? (y/n)"
    $json = $asJson -eq "y"

    Write-Host "  Enter object as hashtable (e.g. Name=Alice; Age=30; Role=admin)" -ForegroundColor DarkGray
    $input = Read-Host "  "
    $hash = @{}
    $input -split ";" | ForEach-Object {
        $pair = $_.Trim() -split "=", 2
        if ($pair.Count -eq 2) {
            $hash[$pair[0].Trim()] = $pair[1].Trim()
        }
    }
    if ($hash.Count -eq 0) {
        Write-Host "  No valid key-value pairs." -ForegroundColor Red
        return
    }

    if ([string]::IsNullOrWhiteSpace($key)) {
        if ($json) {
            $hash | New-BucketObject -Bucket $bucket -AsJson -Quiet
        }
        else {
            $hash | New-BucketObject -Bucket $bucket -Quiet
        }
    }
    else {
        if ($json) {
            $hash | New-BucketObject -Bucket $bucket -KeyProperty "_Id" -Key $key -AsJson -Quiet
        }
        else {
            $hash | New-BucketObject -Bucket $bucket -KeyProperty "_Id" -Key $key -Quiet
        }
    }
    Write-Host "  Saved." -ForegroundColor Green
}

function QuickPatch {
    Write-Host "`n  --- Quick Patch (Set-BucketObject) ---" -ForegroundColor Cyan
    $bucket = Read-Host "  Bucket name"
    $key = Read-Host "  Key"
    Write-Host "  Enter fields to patch (Key=Value;Key2=Value2)" -ForegroundColor DarkGray
    $input = Read-Host "  "
    $hash = @{}
    $input -split ";" | ForEach-Object {
        $pair = $_.Trim() -split "=", 2
        if ($pair.Count -eq 2) {
            $hash[$pair[0].Trim()] = $pair[1].Trim()
        }
    }
    if ($hash.Count -eq 0) {
        Write-Host "  No valid key-value pairs." -ForegroundColor Red
        return
    }
    $hash | Set-BucketObject -Bucket $bucket -Key $key -Quiet
    Write-Host "  Patched." -ForegroundColor Green
}

function QuickRemove {
    Write-Host "`n  --- Quick Remove ---" -ForegroundColor Cyan
    $bucket = Read-Host "  Bucket name"
    $key = Read-Host "  Key (or Enter to remove ALL)"
    if ([string]::IsNullOrWhiteSpace($key)) {
        Remove-BucketObject -Bucket $bucket -All -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Write-Host "  All objects removed from '$bucket'." -ForegroundColor Green
    }
    else {
        Remove-BucketObject -Bucket $bucket -Key $key -WarningAction SilentlyContinue
        Write-Host "  Removed '$key' from '$bucket'." -ForegroundColor Green
    }
}

function QuickMove {
    Write-Host "`n  --- Quick Move (Copy+Delete Source) ---" -ForegroundColor Cyan
    $bucket = Read-Host "  Source bucket"
    $key = Read-Host "  Source key"
    $destBucket = Read-Host "  Destination bucket"
    $destKey = Read-Host "  Destination key (or Enter for same key)"
    if ([string]::IsNullOrWhiteSpace($destKey)) { $destKey = $key }
    Move-BucketObject -Bucket $bucket -Key $key -DestinationBucket $destBucket -DestinationKey $destKey -Quiet -WarningAction SilentlyContinue
    Write-Host "  Moved '$bucket/$key' -> '$destBucket/$destKey'." -ForegroundColor Green
}

function QuickRename {
    Write-Host "`n  --- Quick Rename ---" -ForegroundColor Cyan
    $bucket = Read-Host "  Bucket name"
    $key = Read-Host "  Current key"
    $newKey = Read-Host "  New key"
    Rename-BucketObject -Bucket $bucket -Key $key -NewKey $newKey -WarningAction SilentlyContinue
    Write-Host "  Renamed '$key' -> '$newKey'." -ForegroundColor Green
}

function QuickCopy {
    Write-Host "`n  --- Quick Copy ---" -ForegroundColor Cyan
    $bucket = Read-Host "  Source bucket"
    $key = Read-Host "  Source key"
    $destBucket = Read-Host "  Destination bucket"
    $destKey = Read-Host "  Destination key (or Enter for same key)"
    if ([string]::IsNullOrWhiteSpace($destKey)) { $destKey = $key }
    Copy-BucketObject -Bucket $bucket -Key $key -DestinationBucket $destBucket -DestinationKey $destKey -WarningAction SilentlyContinue
    Write-Host "  Copied '$bucket/$key' -> '$destBucket/$destKey'." -ForegroundColor Green
}

function QuickExportImport {
    Write-Host "`n  --- Quick Export/Import ---" -ForegroundColor Cyan
    Write-Host "  [1] Export" -ForegroundColor White
    Write-Host "  [2] Import" -ForegroundColor White
    $choice = Read-Host -Prompt "  >"
    $bucketDir = Join-Path $PWD.Path ".buckets"
    switch ($choice) {
        "1" {
            $bucket = Read-Host "  Bucket name"
            $file = Read-Host "  Output file path"
            if ([string]::IsNullOrWhiteSpace($file)) {
                $file = Join-Path $bucketDir "$bucket-export.clixml"
            }
            Export-Bucket -Bucket $bucket -OutputFile $file -Quiet
            Write-Host "  Exported to '$file'." -ForegroundColor Green
        }
        "2" {
            $bucket = Read-Host "  Target bucket name"
            $file = Read-Host "  Input file path"
            if (-not (Test-Path $file)) {
                Write-Host "  File not found: $file" -ForegroundColor Red
                return
            }
            Import-Bucket -Bucket $bucket -InputFile $file -Quiet
            Write-Host "  Imported into '$bucket'." -ForegroundColor Green
        }
        default { Write-Host "  Unknown option." -ForegroundColor Red }
    }
}

function QuickArrayTest {
    Write-Host "`n  --- Quick Array Save/Load ---" -ForegroundColor Cyan
    $bucket = Read-Host "  Bucket name"
    $arrayKey = Read-Host "  ArrayKey (name for .arrays/<key>/ dir)"
    Write-Host "  Enter items (one per line, Key=Value;Key2=Value2). Empty line to finish." -ForegroundColor DarkGray
    $items = [System.Collections.ArrayList]::new()
    while ($true) {
        $input = Read-Host "  "
        if ([string]::IsNullOrWhiteSpace($input)) { break }
        $hash = @{}
        $input -split ";" | ForEach-Object {
            $pair = $_.Trim() -split "=", 2
            if ($pair.Count -eq 2) {
                $hash[$pair[0].Trim()] = $pair[1].Trim()
            }
        }
        if ($hash.Count -gt 0) {
            $null = $items.Add($hash)
        }
    }
    if ($items.Count -eq 0) {
        Write-Host "  No items entered." -ForegroundColor Red
        return
    }
    New-BucketObject -Bucket $bucket -InputObject $items -KeyProperty "_Id" -ArrayKey $arrayKey -Quiet
    Write-Host "  Saved $($items.Count) items to .arrays/$arrayKey/." -ForegroundColor Green

    Write-Host "`n  Reload as grouped array..." -ForegroundColor DarkGray
    $grouped = @(Get-BucketObject -Bucket $bucket -GroupArrays -WarningAction SilentlyContinue)
    foreach ($g in $grouped) {
        if ($g._ArrayGroup -eq $true) {
            Write-Host "  Array group ($($g._ArrayItems.Count) items):" -ForegroundColor Cyan
            $g._ArrayItems | ForEach-Object {
                Write-Host "    $_" -ForegroundColor DarkGray
            }
        }
        else {
            Write-Host "  Standalone: $g" -ForegroundColor DarkGray
        }
    }
}

function QuickCompress {
    Write-Host "`n  --- Quick Compress Test ---" -ForegroundColor Cyan
    $bucket = Read-Host "  Bucket name"
    $key = Read-Host "  Key"
    $data = "x" * 2000
    $hash = @{ _Id = $key; Data = $data; Type = "compressed" }
    New-BucketObject -Bucket $bucket -InputObject $hash -KeyProperty "_Id" -Compress -Quiet
    $basePath = Join-Path $PWD.Path ".buckets"
    $bPath = Join-Path $basePath $bucket
    $filePath = Join-Path $bPath "$key.dat"
    $size = (Get-ChildItem $filePath).Length
    Write-Host "  Saved compressed: $size bytes (vs ~$($data.Length + 200) uncompressed)" -ForegroundColor Green
    $retrieved = Get-BucketObject -Bucket $bucket -Key $key
    Write-Host "  Round-trip OK, data length: $($retrieved.Data.Length)" -ForegroundColor Green
}

function QuickBulk {
    Write-Host "`n  --- Quick Bulk Save ---" -ForegroundColor Cyan
    $bucket = Read-Host "  Bucket name"
    $count = Read-Host "  Number of objects"
    $count = [int]$count
    Write-Host "  Generating $count objects..." -ForegroundColor DarkGray
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $objects = 1..$count | ForEach-Object {
        [PSCustomObject]@{
            Id = $_
            Name = "item-$_"
            Value = (Get-Random)
        }
    }
    $objects | New-BucketObject -Bucket $bucket -KeyProperty Id -Quiet
    $writeTime = $sw.ElapsedMilliseconds
    $sw.Restart()
    $retrieved = @(Get-BucketObject -Bucket $bucket -WarningAction SilentlyContinue)
    $readTime = $sw.ElapsedMilliseconds
    Write-Host "  Write: ${writeTime}ms, Read: ${readTime}ms, Objects: $($retrieved.Count)" -ForegroundColor Green
}

function QuickFilter {
    Write-Host "`n  --- Quick Filter ---" -ForegroundColor Cyan
    $bucket = Read-Host "  Bucket name"
    Write-Host "  [1] -Match (hashtable)" -ForegroundColor White
    Write-Host "  [2] -Filter (scriptblock)" -ForegroundColor White
    $choice = Read-Host -Prompt "  >"
    switch ($choice) {
        "1" {
            Write-Host "  Enter match criteria (Key=Value;Key2=Value2)" -ForegroundColor DarkGray
            $input = Read-Host "  "
            $match = @{}
            $input -split ";" | ForEach-Object {
                $pair = $_.Trim() -split "=", 2
                if ($pair.Count -eq 2) {
                    $match[$pair[0].Trim()] = $pair[1].Trim()
                }
            }
            $results = @(Get-BucketObject -Bucket $bucket -Match $match -WarningAction SilentlyContinue)
            Write-Host "  Found $($results.Count) matches." -ForegroundColor Green
            $results | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        }
        "2" {
            Write-Host "  Enter filter scriptblock (e.g. `$_.Role -eq 'admin')" -ForegroundColor DarkGray
            $filter = Read-Host "  { }"
            $sb = [scriptblock]::Create($filter)
            $results = @(Get-BucketObject -Bucket $bucket -Filter $sb -WarningAction SilentlyContinue)
            Write-Host "  Found $($results.Count) matches." -ForegroundColor Green
            $results | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        }
        default { Write-Host "  Unknown option." -ForegroundColor Red }
    }
}

function QuickDebug {
    Write-Host "`n  --- Quick Debug (raw file inspection) ---" -ForegroundColor Cyan
    $bucket = Read-Host "  Bucket name"
    $key = Read-Host "  Key (partial match ok)"
    $basePath = Join-Path $PWD.Path ".buckets"
    $bucketPath = Join-Path $basePath $bucket
    $arraysPath = Join-Path $bucketPath ".arrays"

    $files = @()
    if (Test-Path $bucketPath) {
        $di = [System.IO.DirectoryInfo]::new($bucketPath)
        $files += @($di.GetFiles("*.dat"))
        $files += @($di.GetFiles("*.json"))
    }
    if (Test-Path $arraysPath) {
        $adi = [System.IO.DirectoryInfo]::new($arraysPath)
        foreach ($sub in $adi.GetDirectories()) {
            $files += @($sub.GetFiles("*.dat"))
            $files += @($sub.GetFiles("*.json"))
        }
    }

    $matched = @($files | Where-Object { $_.Name.ToLowerInvariant().StartsWith($key.ToLowerInvariant()) })
    if ($matched.Count -eq 0) {
        Write-Host "  No matching files found." -ForegroundColor DarkGray
        return
    }

    Write-Host "`n  [$($matched.Count) matching files]" -ForegroundColor Cyan
    foreach ($f in $matched) {
        $relPath = $f.FullName.Substring($basePath.Length + 1)
        Write-Host "`n  File: $relPath" -ForegroundColor Yellow
        Write-Host "  Size: $($f.Length) bytes" -ForegroundColor DarkGray
        Write-Host "  Modified: $($f.LastWriteTime)" -ForegroundColor DarkGray

        if ($f.Extension -eq ".json") {
            $content = [System.IO.File]::ReadAllText($f.FullName)
            if ($content.Length -gt 500) {
                Write-Host "  Content (first 500 chars):" -ForegroundColor DarkGray
                Write-Host "  $($content.Substring(0, 500))..." -ForegroundColor DarkGray
            }
            else {
                Write-Host "  Content:" -ForegroundColor DarkGray
                $content -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            }
        }
        elseif ($f.Extension -eq ".dat") {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            if ($bytes[0] -eq 0x1F -and $bytes[1] -eq 0x8B) {
                Write-Host "  Format: GZip compressed binary" -ForegroundColor DarkGray
            }
            else {
                $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                if ($text -match "<Obj ") {
                    Write-Host "  Format: CLIXML (binary)" -ForegroundColor DarkGray
                }
                else {
                    Write-Host "  Format: Unknown binary" -ForegroundColor DarkGray
                }
            }
            Write-Host "  First 120 chars (if readable):" -ForegroundColor DarkGray
            try {
                $preview = [System.Text.Encoding]::UTF8.GetString($bytes)
                if ($preview.Length -gt 120) { $preview = $preview.Substring(0, 120) + "..." }
                Write-Host "    $preview" -ForegroundColor DarkGray
            }
            catch {
                Write-Host "    (not readable as UTF-8)" -ForegroundColor DarkGray
            }
        }
    }
}

# --- Menu ---

function Show-Menu {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " Buckets REPL" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [buckets] List all buckets with stats" -ForegroundColor White
    Write-Host "  [objects]  Show objects in a bucket" -ForegroundColor White
    Write-Host "  [keys]     List keys in a bucket" -ForegroundColor White
    Write-Host ""
    Write-Host "  [save]     Quick save object" -ForegroundColor White
    Write-Host "  [patch]    Quick patch (Set-BucketObject)" -ForegroundColor White
    Write-Host "  [remove]   Remove object(s)" -ForegroundColor White
    Write-Host "  [move]     Move object (copy+delete)" -ForegroundColor White
    Write-Host "  [copy]     Copy object" -ForegroundColor White
    Write-Host "  [rename]   Rename object key" -ForegroundColor White
    Write-Host ""
    Write-Host "  [filter]   Filter objects (-Match/-Filter)" -ForegroundColor White
    Write-Host "  [array]    Array save/load test" -ForegroundColor White
    Write-Host "  [compress] Compress test" -ForegroundColor White
    Write-Host "  [bulk]     Bulk save benchmark" -ForegroundColor White
    Write-Host ""
    Write-Host "  [export]   Export/Import bucket" -ForegroundColor White
    Write-Host "  [debug]    Inspect raw files" -ForegroundColor White
    Write-Host "  [wipe]     Clear .buckets directory" -ForegroundColor White
    Write-Host ""
    Write-Host "  [q] Quit" -ForegroundColor White
}

# --- Main loop ---

Write-Host "  Buckets Interactive REPL" -ForegroundColor DarkGray
Write-Host "  Module: $((Get-Module Buckets).Version)" -ForegroundColor DarkGray

$running = $true
while ($running) {
    Show-Menu
    $choice = (Read-Host -Prompt "  >").Trim().ToLowerInvariant()
    Write-Host ""

    try {
        switch ($choice) {
            "buckets" { Show-Buckets }
            "objects" { Show-BucketObjects }
            "keys"    { Show-BucketKeys }
            "save"    { QuickSave }
            "patch"   { QuickPatch }
            "remove"  { QuickRemove }
            "move"    { QuickMove }
            "copy"    { QuickCopy }
            "rename"  { QuickRename }
            "filter"  { QuickFilter }
            "array"   { QuickArrayTest }
            "compress"{ QuickCompress }
            "bulk"    { QuickBulk }
            "export"  { QuickExportImport }
            "debug"   { QuickDebug }
            "wipe"    { Clear-Buckets }
            "q"       { $running = $false }
            default   { Write-Host "  Unknown command. Type 'q' to quit." -ForegroundColor Red }
        }
    }
    catch {
        Write-Host "  Error: $_" -ForegroundColor Red
    }
}

Write-Host "`n  Bye!`n" -ForegroundColor Cyan
