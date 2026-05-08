#!/usr/bin/env pwsh
# Buckets Module — Interactive Bucket Explorer
# Navigate buckets and their contents via a logical tree structure.

$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot "../../Buckets"

if (-not (Get-Module Buckets)) {
    Import-Module $modulePath -Force
}
else {
    Import-Module $modulePath -Force
}

$startTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$mod = Get-Module Buckets
$pwsh = "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
$os = if ($IsMacOS) { "macOS" } elseif ($IsLinux) { "Linux" } else { "Windows" }
$sep = "=" * 52

# --- Helpers ---

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { "$([math]::Round($Bytes/1GB,1)) GB" }
    elseif ($Bytes -ge 1MB) { "$([math]::Round($Bytes/1MB,1)) MB" }
    elseif ($Bytes -ge 1KB) { "$([math]::Round($Bytes/1KB,1)) KB" }
    else { "$Bytes B" }
}

function Format-Value {
    param($Value, [int]$MaxLen = 80)
    if ($null -eq $Value) { return "$null" }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $count = @($Value).Count
        return "[$count items]"
    }
    $str = $Value.ToString()
    if ($str.Length -gt $MaxLen) {
        return $str.Substring(0, $MaxLen) + "..."
    }
    return $str
}

function Get-RootPath {
    return Join-Path $HOME ".buckets"
}

function Scan-Buckets {
    $root = Get-RootPath
    if (-not [System.IO.Directory]::Exists($root)) {
        return @()
    }
    $buckets = [System.Collections.ArrayList]::new()
    $di = [System.IO.DirectoryInfo]::new($root)
    foreach ($d in $di.GetDirectories()) {
        $stats = Get-BucketStats -Bucket $d.Name -WarningAction SilentlyContinue
        $null = $buckets.Add([PSCustomObject]@{
            Name        = $d.Name
            ObjectCount = $stats.ObjectCount
            TotalSize   = $stats.TotalSizeBytes
            TotalSizeF  = $stats.TotalSize
            Modified    = $stats.NewestObject
            Oldest      = $stats.OldestObject
        })
    }
    return @($buckets)
}

function Scan-Arrays {
    param([string]$Bucket)
    $root = Get-RootPath
    $arraysPath = Join-Path $root "$Bucket/.arrays"
    if (-not [System.IO.Directory]::Exists($arraysPath)) {
        return @()
    }
    $groups = [System.Collections.ArrayList]::new()
    $adi = [System.IO.DirectoryInfo]::new($arraysPath)
    foreach ($sub in $adi.GetDirectories()) {
        $dat = @($sub.GetFiles("*.dat"))
        $json = @($sub.GetFiles("*.json"))
        $all = $dat + $json
        $size = ($all | ForEach-Object { $_.Length } | Measure-Object -Sum).Sum
        $null = $groups.Add([PSCustomObject]@{
            Key      = $sub.Name
            Count    = $all.Count
            Size     = $size
            SizeF    = Format-Size -Bytes $size
            Modified = ($all | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
            Format   = if ($json.Count -gt 0) { "JSON" } else { "Binary" }
        })
    }
    return @($groups)
}

function Scan-Objects {
    param([string]$Bucket)
    $root = Get-RootPath
    $bucketPath = Join-Path $root $Bucket
    if (-not [System.IO.Directory]::Exists($bucketPath)) {
        return @()
    }
    $files = [System.Collections.ArrayList]::new()
    $di = [System.IO.DirectoryInfo]::new($bucketPath)
    foreach ($f in $di.GetFiles("*.dat")) {
        $null = $files.Add([PSCustomObject]@{
            Key      = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            File     = $f.Name
            Size     = $f.Length
            SizeF    = Format-Size -Bytes $f.Length
            Modified = $f.LastWriteTime
            Format   = "Binary"
            InArray  = $false
        })
    }
    foreach ($f in $di.GetFiles("*.json")) {
        $null = $files.Add([PSCustomObject]@{
            Key      = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            File     = $f.Name
            Size     = $f.Length
            SizeF    = Format-Size -Bytes $f.Length
            Modified = $f.LastWriteTime
            Format   = "JSON"
            InArray  = $false
        })
    }
    return @($files)
}

function Scan-ArrayItems {
    param([string]$Bucket, [string]$ArrayKey)
    $root = Get-RootPath
    $arrayPath = Join-Path $root "$Bucket/.arrays/$ArrayKey"
    if (-not [System.IO.Directory]::Exists($arrayPath)) {
        return @()
    }
    $files = [System.Collections.ArrayList]::new()
    $di = [System.IO.DirectoryInfo]::new($arrayPath)
    foreach ($f in $di.GetFiles("*.dat")) {
        $null = $files.Add([PSCustomObject]@{
            Key      = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            File     = $f.Name
            Size     = $f.Length
            SizeF    = Format-Size -Bytes $f.Length
            Modified = $f.LastWriteTime
            Format   = "Binary"
        })
    }
    foreach ($f in $di.GetFiles("*.json")) {
        $null = $files.Add([PSCustomObject]@{
            Key      = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            File     = $f.Name
            Size     = $f.Length
            SizeF    = Format-Size -Bytes $f.Length
            Modified = $f.LastWriteTime
            Format   = "JSON"
        })
    }
    return @($files)
}

function Read-ObjectContent {
    param([string]$Bucket, [string]$Key, [string]$ArrayKey)
    if ($ArrayKey) {
        return Get-BucketObject -Bucket $Bucket -ArrayKey $ArrayKey -Key $Key -WarningAction SilentlyContinue
    }
    return Get-BucketObject -Bucket $Bucket -Key $Key -WarningAction SilentlyContinue
}

# --- UI ---

function Show-BucketList {
    $buckets = Scan-Buckets
    if ($buckets.Count -eq 0) {
        Write-Host ""
        Write-Host "  (no buckets found)" -ForegroundColor DarkGray
        Write-Host ""
        return @()
    }

    Write-Host ""
    Write-Host "  Buckets ($($buckets.Count))" -ForegroundColor Cyan
    Write-Host "  $("=" * 60)" -ForegroundColor DarkGray

    $totalSize = 0
    $totalObjects = 0
    for ($i = 0; $i -lt $buckets.Count; $i++) {
        $b = $buckets[$i]
        $isLast = $i -eq $buckets.Count - 1
        $connector = if ($isLast) { "`" " } else { "| " }
        $arrays = @(Scan-Arrays -Bucket $b.Name)
        $hasArrays = $arrays.Count -gt 0

        Write-Host "  $connector" -ForegroundColor DarkGray
        Write-Host "  +- " -ForegroundColor DarkGray -NoNewline
        Write-Host "$($b.Name)" -ForegroundColor Yellow -NoNewline
        Write-Host " [$($b.ObjectCount) objects, $($b.TotalSizeF)]" -ForegroundColor DarkGray -NoNewline
        if ($b.Modified) {
            Write-Host " (modified: $($b.Modified.ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor DarkGray
        }
        else {
            Write-Host ""
        }

        $totalSize += $b.TotalSize
        $totalObjects += $b.ObjectCount

        if ($hasArrays) {
            for ($j = 0; $j -lt $arrays.Count; $j++) {
                $a = $arrays[$j]
                $aLast = $j -eq $arrays.Count - 1
                $aConn = if ($isLast -and $aLast) { "   " } else { "|  " }
                $aBranch = if ($aLast) { "`--" } else { "|--" }
                Write-Host "  $aConn $aBranch " -ForegroundColor DarkGray -NoNewline
                Write-Host "$($a.Key)" -ForegroundColor Magenta -NoNewline
                Write-Host " [$($a.Count) items, $($a.SizeF), $($a.Format)]" -ForegroundColor DarkGray
            }
        }
    }

    Write-Host "  " -NoNewline
    Write-Host ("-" * 60) -ForegroundColor DarkGray
    Write-Host "  Total: " -ForegroundColor DarkGray -NoNewline
    Write-Host "$totalObjects objects, $(Format-Size -Bytes $totalSize)" -ForegroundColor Cyan
    Write-Host ""

    return $buckets
}

function Show-StandaloneObjects {
    param([string]$Bucket)
    $objects = Scan-Objects -Bucket $Bucket
    if ($objects.Count -eq 0) {
        Write-Host "  (no standalone objects)" -ForegroundColor DarkGray
        Write-Host ""
        return @()
    }

    Write-Host "  Standalone objects ($($objects.Count))" -ForegroundColor Cyan
    Write-Host "  $("=" * 60)" -ForegroundColor DarkGray

    for ($i = 0; $i -lt $objects.Count; $i++) {
        $o = $objects[$i]
        $isLast = $i -eq $objects.Count - 1
        $branch = if ($isLast) { "`--" } else { "|--" }
        $conn = if ($isLast) { "   " } else { "|  " }

        Write-Host "  $branch " -ForegroundColor DarkGray -NoNewline
        Write-Host "$($o.Key)" -ForegroundColor Yellow -NoNewline
        Write-Host " [$($o.SizeF), $($o.Format)]" -ForegroundColor DarkGray -NoNewline
        Write-Host " ($($o.Modified.ToString('MM-dd HH:mm')))" -ForegroundColor DarkGray
    }
    Write-Host ""

    return $objects
}

function Show-ArrayGroups {
    param([string]$Bucket)
    $arrays = Scan-Arrays -Bucket $Bucket
    if ($arrays.Count -eq 0) {
        Write-Host "  (no array groups)" -ForegroundColor DarkGray
        Write-Host ""
        return @()
    }

    Write-Host "  Array groups ($($arrays.Count))" -ForegroundColor Magenta
    Write-Host "  $("=" * 60)" -ForegroundColor DarkGray

    for ($i = 0; $i -lt $arrays.Count; $i++) {
        $a = $arrays[$i]
        $isLast = $i -eq $arrays.Count - 1
        $branch = if ($isLast) { "`--" } else { "|--" }

        Write-Host "  $branch " -ForegroundColor DarkGray -NoNewline
        Write-Host "$($a.Key)" -ForegroundColor Magenta -NoNewline
        Write-Host " [$($a.Count) items, $($a.SizeF), $($a.Format)]" -ForegroundColor DarkGray -NoNewline
        Write-Host " (modified: $($a.Modified.ToString('MM-dd HH:mm')))" -ForegroundColor DarkGray
    }
    Write-Host ""

    return $arrays
}

function Show-ArrayItems {
    param([string]$Bucket, [string]$ArrayKey)
    $items = Scan-ArrayItems -Bucket $Bucket -ArrayKey $ArrayKey
    if ($items.Count -eq 0) {
        Write-Host "  (no items in this array group)" -ForegroundColor DarkGray
        Write-Host ""
        return @()
    }

    Write-Host "  .arrays/$ArrayKey/ ($($items.Count) items)" -ForegroundColor Magenta
    Write-Host "  $("=" * 60)" -ForegroundColor DarkGray

    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]
        $isLast = $i -eq $items.Count - 1
        $branch = if ($isLast) { "`--" } else { "|--" }

        Write-Host "  $branch " -ForegroundColor DarkGray -NoNewline
        Write-Host "$($it.Key)" -ForegroundColor White -NoNewline
        Write-Host " [$($it.SizeF), $($it.Format)]" -ForegroundColor DarkGray -NoNewline
        Write-Host " ($($it.Modified.ToString('MM-dd HH:mm')))" -ForegroundColor DarkGray
    }
    Write-Host ""

    return $items
}

function Show-ObjectDetail {
    param([string]$Bucket, [string]$Key, [string]$ArrayKey)
    $obj = Read-ObjectContent -Bucket $Bucket -Key $Key -ArrayKey $ArrayKey
    if (-not $obj) {
        Write-Host "  Object not found or corrupted." -ForegroundColor Red
        Write-Host ""
        return
    }

    $title = if ($ArrayKey) { ".arrays/$ArrayKey/$Key" } else { "$Bucket/$Key" }
    Write-Host "  Object: $title" -ForegroundColor Cyan
    Write-Host "  $("=" * 60)" -ForegroundColor DarkGray

    foreach ($prop in $obj.PSObject.Properties | Where-Object { $_.Name -notmatch "^_" }) {
        $val = Format-Value -Value $prop.Value
        Write-Host "  " -NoNewline
        Write-Host "$($prop.Name)" -ForegroundColor Yellow -NoNewline
        Write-Host " = " -ForegroundColor DarkGray -NoNewline
        Write-Host "$val" -ForegroundColor White
    }

    # Show internal metadata
    $internal = @($obj.PSObject.Properties | Where-Object { $_.Name -match "^_" })
    if ($internal.Count -gt 0) {
        Write-Host ""
        Write-Host "  (internal)" -ForegroundColor DarkGray
        foreach ($prop in $internal) {
            $val = Format-Value -Value $prop.Value
            Write-Host "  " -NoNewline
            Write-Host "$($prop.Name)" -ForegroundColor DarkGray -NoNewline
            Write-Host " = " -ForegroundColor DarkGray -NoNewline
            Write-Host "$val" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}

function Show-Help {
    Write-Host ""
    Write-Host "  Commands:" -ForegroundColor Cyan
    Write-Host "    cd <bucket>        Enter a bucket" -ForegroundColor White
    Write-Host "    cd ..              Go back" -ForegroundColor White
    Write-Host "    cd <bucket>/<key>  Enter an array group" -ForegroundColor White
    Write-Host "    ls                 List current view" -ForegroundColor White
    Write-Host "    cat <key>          View object details" -ForegroundColor White
    Write-Host "    find <pattern>     Search keys across all buckets" -ForegroundColor White
    Write-Host "    stats              Show bucket statistics" -ForegroundColor White
    Write-Host "    tree               Show full tree of all buckets" -ForegroundColor White
    Write-Host "    wipe               Clear .buckets directory" -ForegroundColor White
    Write-Host "    q                  Quit" -ForegroundColor White
    Write-Host "    ?                  Show this help" -ForegroundColor White
    Write-Host ""
}

# --- State machine ---

$state = "root"  # root | bucket | array
$stateBucket = ""
$stateArrayKey = ""

function Render-View {
    switch ($state) {
        "root" {
            Write-Host "  /" -ForegroundColor Cyan
            $script:currentItems = Show-BucketList
        }
        "bucket" {
            Write-Host "  /$stateBucket" -ForegroundColor Cyan
            Show-StandaloneObjects -Bucket $stateBucket
            Show-ArrayGroups -Bucket $stateBucket
        }
        "array" {
            Write-Host "  /$stateBucket/$stateArrayKey" -ForegroundColor Magenta
            Show-ArrayItems -Bucket $stateBucket -ArrayKey $stateArrayKey
        }
    }
}

function Handle-Command {
    param([string]$UserInput)
    $parts = $UserInput -split "\s+"
    $cmd = $parts[0].ToLowerInvariant()
    $arg = if ($parts.Count -gt 1) { $parts[1] } else { "" }

    switch ($cmd) {
        "q" {
            return $false
        }
        "?" {
            Show-Help
            return $true
        }
        "cd" {
            if ($arg -eq ".." -or $arg -eq "") {
                if ($state -eq "array") {
                    $script:state = "bucket"
                    $script:stateArrayKey = ""
                }
                elseif ($state -eq "bucket") {
                    $script:state = "root"
                    $script:stateBucket = ""
                }
                else {
                    Write-Host "  Already at root." -ForegroundColor DarkGray
                    Write-Host ""
                }
            }
            elseif ($arg -match "/") {
                $bucketPart, $arrayPart = $arg -split "/", 2
                $buckets = Scan-Buckets
                $match = $buckets | Where-Object { $_.Name -eq $bucketPart }
                if (-not $match) {
                    Write-Host "  Bucket '$bucketPart' not found." -ForegroundColor Red
                    Write-Host ""
                    return $true
                }
                $script:state = "array"
                $script:stateBucket = $bucketPart
                $script:stateArrayKey = $arrayPart
                $arrays = Scan-Arrays -Bucket $stateBucket
                $aMatch = $arrays | Where-Object { $_.Key -eq $arrayPart }
                if (-not $aMatch) {
                    Write-Host "  Array group '$arrayPart' not found in '$bucketPart'." -ForegroundColor Red
                    Write-Host ""
                    return $true
                }
            }
            else {
                $buckets = Scan-Buckets
                $match = $buckets | Where-Object { $_.Name -eq $arg }
                if (-not $match) {
                    Write-Host "  Bucket '$arg' not found." -ForegroundColor Red
                    Write-Host ""
                    return $true
                }
                $script:state = "bucket"
                $script:stateBucket = $arg
            }
            return $true
        }
        "ls" {
            Render-View
            return $true
        }
        "cat" {
            if ([string]::IsNullOrWhiteSpace($arg)) {
                Write-Host "  Usage: cat <key>" -ForegroundColor Red
                Write-Host ""
                return $true
            }
            switch ($state) {
                "root" {
                    Write-Host "  Enter a bucket first (cd <bucket>)" -ForegroundColor Red
                    Write-Host ""
                    return $true
                }
                "bucket" {
                    Show-ObjectDetail -Bucket $stateBucket -Key $arg
                }
                "array" {
                    Show-ObjectDetail -Bucket $stateBucket -Key $arg -ArrayKey $stateArrayKey
                }
            }
            return $true
        }
        "find" {
            if ([string]::IsNullOrWhiteSpace($arg)) {
                Write-Host "  Usage: find <pattern>" -ForegroundColor Red
                Write-Host ""
                return $true
            }
            Write-Host ""
            Write-Host "  Searching for '*$arg*' across all buckets..." -ForegroundColor Cyan
            Write-Host ""
            $buckets = Scan-Buckets
            $found = 0
            foreach ($b in $buckets) {
                $standalone = @(Scan-Objects -Bucket $b.Name)
                $matched = $standalone | Where-Object { $_.Key -like "*$arg*" }
                foreach ($m in $matched) {
                    Write-Host "  " -NoNewline
                    Write-Host "$($b.Name)/" -ForegroundColor Yellow -NoNewline
                    Write-Host "$($m.Key)" -ForegroundColor White -NoNewline
                    Write-Host " [$($m.SizeF), $($m.Format)]" -ForegroundColor DarkGray
                    $found++
                }
                $arrays = @(Scan-Arrays -Bucket $b.Name)
                foreach ($a in $arrays) {
                    $items = @(Scan-ArrayItems -Bucket $b.Name -ArrayKey $a.Key)
                    $matchedItems = $items | Where-Object { $_.Key -like "*$arg*" }
                    foreach ($m in $matchedItems) {
                        Write-Host "  " -NoNewline
                        Write-Host "$($b.Name)/.arrays/$($a.Key)/" -ForegroundColor Magenta -NoNewline
                        Write-Host "$($m.Key)" -ForegroundColor White -NoNewline
                        Write-Host " [$($m.SizeF), $($m.Format)]" -ForegroundColor DarkGray
                        $found++
                    }
                }
            }
            if ($found -eq 0) {
                Write-Host "  No matches." -ForegroundColor DarkGray
            }
            else {
                Write-Host ""
                Write-Host "  $found matches found." -ForegroundColor Cyan
            }
            Write-Host ""
            return $true
        }
        "stats" {
            Write-Host ""
            Write-Host "  Bucket Statistics" -ForegroundColor Cyan
            Write-Host "  $("=" * 60)" -ForegroundColor DarkGray
            $buckets = Scan-Buckets
            foreach ($b in $buckets) {
                $stats = Get-BucketStats -Bucket $b.Name -WarningAction SilentlyContinue
                Write-Host ""
                Write-Host "  $($b.Name)" -ForegroundColor Yellow
                Write-Host "    Objects:      $($stats.ObjectCount)" -ForegroundColor DarkGray
                Write-Host "    Total size:   $($stats.TotalSize)" -ForegroundColor DarkGray
                if ($stats.OldestObject) { Write-Host "    Oldest:       $($stats.OldestObject.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor DarkGray }
                if ($stats.NewestObject) { Write-Host "    Newest:       $($stats.NewestObject.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor DarkGray }
            }
            Write-Host ""
            return $true
        }
        "tree" {
            Write-Host ""
            Write-Host "  Full Bucket Tree" -ForegroundColor Cyan
            Write-Host "  $("=" * 60)" -ForegroundColor DarkGray
            $buckets = Scan-Buckets
            for ($i = 0; $i -lt $buckets.Count; $i++) {
                $b = $buckets[$i]
                $isLast = $i -eq $buckets.Count - 1
                $conn = if ($isLast) { "`" " } else { "| " }
                Write-Host "  $conn" -ForegroundColor DarkGray
                Write-Host "  +- " -ForegroundColor DarkGray -NoNewline
                Write-Host "$($b.Name)" -ForegroundColor Yellow -NoNewline
                Write-Host " [$($b.ObjectCount) objects, $($b.TotalSizeF)]" -ForegroundColor DarkGray

                $standalone = @(Scan-Objects -Bucket $b.Name)
                $arrays = @(Scan-Arrays -Bucket $b.Name)
                $totalItems = $standalone.Count + $arrays.Count
                $idx = 0
                foreach ($o in $standalone) {
                    $idx++
                    $oLast = $idx -eq $totalItems
                    $oConn = if ($isLast -and $oLast) { "   " } else { "|  " }
                    $oBranch = if ($oLast) { "`--" } else { "|--" }
                    Write-Host "  $oConn $oBranch " -ForegroundColor DarkGray -NoNewline
                    Write-Host "$($o.Key)" -ForegroundColor White -NoNewline
                    Write-Host " [$($o.SizeF), $($o.Format)]" -ForegroundColor DarkGray
                }
                foreach ($a in $arrays) {
                    $idx++
                    $aLast = $idx -eq $totalItems
                    $aConn = if ($isLast -and $aLast) { "   " } else { "|  " }
                    $aBranch = if ($aLast) { "`--" } else { "|--" }
                    Write-Host "  $aConn $aBranch " -ForegroundColor DarkGray -NoNewline
                    Write-Host "$($a.Key)" -ForegroundColor Magenta -NoNewline
                    Write-Host " [$($a.Count) items, $($a.SizeF)]" -ForegroundColor DarkGray

                    $items = @(Scan-ArrayItems -Bucket $b.Name -ArrayKey $a.Key)
                    for ($j = 0; $j -lt $items.Count; $j++) {
                        $it = $items[$j]
                        $itLast = $j -eq $items.Count - 1
                        $itConn = if ($isLast -and $aLast -and $itLast) { "       " } elseif ($aLast) { "       " } else { "|     " }
                        $itBranch = if ($itLast) { "`---" } else { "|---" }
                        $innerConn = if ($aLast) { "    " } else { "|   " }
                        Write-Host "  $aConn $innerConn $itConn $itBranch " -ForegroundColor DarkGray -NoNewline
                        Write-Host "$($it.Key)" -ForegroundColor White -NoNewline
                        Write-Host " [$($it.SizeF), $($it.Format)]" -ForegroundColor DarkGray
                    }
                }
            }
            Write-Host ""
            return $true
        }
        "wipe" {
            $confirm = Read-Host "  Wipe .buckets directory? (y/n)"
            if ($confirm -eq "y") {
                $root = Get-RootPath
                if (Test-Path $root) {
                    Remove-Item $root -Recurse -Force
                    Write-Host "  Wiped." -ForegroundColor Green
                    $script:state = "root"
                    $script:stateBucket = ""
                    $script:stateArrayKey = ""
                }
                else {
                    Write-Host "  No .buckets directory." -ForegroundColor DarkGray
                }
            }
            else {
                Write-Host "  Cancelled." -ForegroundColor DarkGray
            }
            Write-Host ""
            return $true
        }
        default {
            Write-Host "  Unknown command: $cmd. Type ? for help." -ForegroundColor Red
            Write-Host ""
            return $true
        }
    }
}

# --- Main loop ---

Write-Host $sep -ForegroundColor DarkGray
Write-Host " Buckets Module" -NoNewline -ForegroundColor Blue
Write-Host " v$($mod.Version)" -NoNewline -ForegroundColor Magenta
Write-Host " Explorer" -ForegroundColor DarkGray
Write-Host " $startTs" -NoNewline -ForegroundColor DarkGray
Write-Host " · " -NoNewline -ForegroundColor DarkGray
Write-Host $pwsh -NoNewline -ForegroundColor Cyan
Write-Host " · " -NoNewline -ForegroundColor DarkGray
Write-Host $os -ForegroundColor DarkGray
Write-Host "  Root: $(Get-RootPath)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Type ? for help, q to quit." -ForegroundColor DarkGray

$running = $true
while ($running) {
    Render-View
    $prompt = switch ($state) {
        "root"  { "/> " }
        "bucket" { "/$stateBucket> " }
        "array" { "/$stateBucket/$stateArrayKey> " }
    }
    $userCmd = Read-Host -Prompt $prompt
    $running = Handle-Command -UserInput $userCmd
}

$endTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host $sep -ForegroundColor DarkGray
Write-Host " Bye" -NoNewline -ForegroundColor Cyan
Write-Host " · " -NoNewline -ForegroundColor DarkGray
Write-Host $endTs -ForegroundColor DarkGray
Write-Host $sep -ForegroundColor DarkGray
