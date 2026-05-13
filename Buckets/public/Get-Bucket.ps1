function Get-Bucket {
    <#
    .SYNOPSIS
    Lists available buckets with object counts.
    .DESCRIPTION
    Scans the storage path for bucket directories and returns information about each,
    including name, path, and total object count (JSON + binary files). Supports nested
    buckets — any directory containing serialized objects is a bucket.

    By default only top-level buckets are shown with aggregated object counts (including
    all descendants). Use -Recurse to list all nested buckets with direct (non-aggregated)
    counts. The HasSubBuckets property indicates whether a bucket contains nested sub-buckets.

    Use -Tree to render a beautiful colorized tree view of all buckets.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Name
    Filter buckets by name pattern (substring match on full nested path).
    .PARAMETER Tree
    Render a tree view of all buckets and directories.
    .PARAMETER Objects
    Show individual objects in tree view. Only bucket directories are shown by default.
    .PARAMETER Raw
    Return structured tree objects instead of formatted text (for -Tree mode).
    .PARAMETER MaxFiles
    Maximum files to display per bucket in tree view. Truncated files shown as "... N more". Default: 5.
    .PARAMETER Depth
    Maximum nesting depth. In tree view, controls how many levels are rendered.
    In list/table view (with -Recurse), limits how deep subdirectories are scanned.
    Without -Recurse, limits aggregation depth (sub-bucket objects beyond this depth
    are not counted in the parent's ObjectCount).
    .PARAMETER Recurse
    List all nested buckets with direct (non-aggregated) object counts.
    .OUTPUTS
    PSCustomObject with Name, Path, ObjectCount, and HasSubBuckets properties, or tree output.
    .EXAMPLE
    Get-Bucket
    .EXAMPLE
    Get-Bucket "user"
    .EXAMPLE
    Get-Bucket -Recurse
    .EXAMPLE
    Get-Bucket -Tree
    .EXAMPLE
    Get-Bucket -Tree -Objects
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Name,
        [string]$Path,
        [switch]$Tree,
        [switch]$Objects,
        [switch]$Raw,
        [switch]$Recurse,
        [int]$MaxFiles = 5,
        [int]$Depth = [int]::MaxValue
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    if (-not [System.IO.Directory]::Exists($Path)) {
        if ($Tree) { Write-Host "No bucket storage found at '$Path'" -ForegroundColor DarkGray }
        return
    }

    if ($Tree) {
        function TreeSize {
            param([long]$Bytes)
            if ($Bytes -eq 0) { return "0 B" }
            $units = @("B", "KB", "MB", "GB", "TB")
            $unit = 0
            $size = [double]$Bytes
            while ($size -ge 1024 -and $unit -lt $units.Length - 1) {
                $size /= 1024
                $unit++
            }
            $rounded = [math]::Round($size)
            "$rounded $($units[$unit])"
        }

        function TreeItemCount {
            param([int]$Count)
            if ($Count -eq 1) { "1 item" } else { "$Count items" }
        }

        function ScanDir {
            param([string]$Dir, [string]$Root)
            $stats = @{ ObjectCount = 0; SizeBytes = 0; BucketCount = 0 }
            if (-not [System.IO.Directory]::Exists($Dir)) { return $stats }
            $di = [System.IO.DirectoryInfo]::new($Dir)
            $stats.ObjectCount += $di.GetFiles("*.dat").Length + $di.GetFiles("*.json").Length
            $di.GetFiles("*.dat") | ForEach-Object { $stats.SizeBytes += $_.Length }
            $di.GetFiles("*.json") | ForEach-Object { $stats.SizeBytes += $_.Length }

            foreach ($sub in $di.GetDirectories()) {
                if ($sub.Name -eq ".buckets") { continue }
                $childStats = ScanDir -Dir $sub.FullName -Root $Root
                $stats.ObjectCount += $childStats.ObjectCount
                $stats.SizeBytes += $childStats.SizeBytes
                $stats.BucketCount += $childStats.BucketCount
                if ($childStats.ObjectCount -gt 0) { $stats.BucketCount++ }
            }

            $isBucket = $stats.ObjectCount -gt 0
            if ($Dir -ne $Root -and -not $isBucket -and $stats.BucketCount -gt 0) { $isBucket = $true }

            if ($Dir -eq $Root) {
                $stats.IsBucket = $true
                $stats.IsRoot = $true
            }
            else {
                $stats.IsBucket = $isBucket
                $stats.IsRoot = $false
            }
            $stats
        }

        function BuildTree {
            param([string]$Dir, [string]$Root, [int]$CurrentDepth)

            $relPath = if ($Dir -eq $Root) {
                ""
            }
            else {
                $Dir.Substring($Root.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
            }

            $displayName = if ($Dir -eq $Root) {
                Split-Path $Root -Leaf
            }
            else {
                Split-Path $Dir -Leaf
            }

            $stats = ScanDir -Dir $Dir -Root $Root
            $type = if ($stats.IsRoot) { "Root" } else { "Bucket" }

            $node = [PSCustomObject]@{
                Name         = $displayName
                Type         = $type
                Path         = $relPath
                ObjectCount  = $stats.ObjectCount
                SizeBytes    = $stats.SizeBytes
                Depth        = $CurrentDepth
                Children     = [System.Collections.ArrayList]::new()
                _BucketName  = if ($stats.IsBucket -and -not $stats.IsRoot) { $relPath } else { "" }
                _BucketKey   = ""
            }
            $node.PSObject.TypeNames.Insert(0, "Buckets.Tree")

            $di = [System.IO.DirectoryInfo]::new($Dir)

            $subDirs = @()
            foreach ($sub in ($di.GetDirectories() | Sort-Object Name)) {
                if ($sub.Name -eq ".buckets") { continue }
                $subRelPath = $sub.FullName.Substring($Root.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
                if (-not [string]::IsNullOrWhiteSpace($script:TreeNameFilter)) {
                    $subRelPathSlash = $subRelPath.TrimEnd('/') + '/'
                    $filterSlash = $script:TreeNameFilter.TrimEnd('/') + '/'
                    $subContainedInFilter = $filterSlash.StartsWith($subRelPathSlash)
                    $filterContainedInSub = $subRelPathSlash.StartsWith($filterSlash)
                    if (-not $subContainedInFilter -and -not $filterContainedInSub) { continue }
                }
                $subHasFiles = $sub.Exists -and ($sub.GetFiles("*.dat").Length -gt 0 -or $sub.GetFiles("*.json").Length -gt 0)
                $subStats = if ($sub.Exists) { ScanDir -Dir $sub.FullName -Root $Root } else { @{ ObjectCount = 0; SizeBytes = 0; BucketCount = 0 } }
                if ($subHasFiles -or $subStats.BucketCount -gt 0) {
                    $subDirs += $sub
                }
            }

            foreach ($sub in $subDirs) {
                if ($CurrentDepth -lt $Depth -or $Objects) {
                    $child = BuildTree -Dir $sub.FullName -Root $Root -CurrentDepth ($CurrentDepth + 1)
                    $null = $node.Children.Add($child)
                }
            }

            if ($Objects) {
                foreach ($f in ($di.GetFiles("*.dat") + $di.GetFiles("*.json") | Sort-Object Name)) {
                    $keyName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                    $fNode = [PSCustomObject]@{
                        Name         = $keyName
                        Type         = "Object"
                        Path         = "$relPath/$keyName"
                        ObjectCount  = 1
                        SizeBytes    = $f.Length
                        Depth        = $CurrentDepth + 1
                        Children     = [System.Collections.ArrayList]::new()
                        _BucketName  = $relPath
                        _BucketKey   = $keyName
                    }
                    $fNode.PSObject.TypeNames.Insert(0, "Buckets.Tree")
                    $null = $node.Children.Add($fNode)
                }
            }

            $node
        }

        function RenderTree {
            param([PSCustomObject]$Node, [string]$Prefix, [bool]$IsLast, [bool]$IsRoot)

            if ($IsRoot) {
                $sizeStr = "$(TreeItemCount $Node.ObjectCount), $(TreeSize $Node.SizeBytes)"
                Write-Host "$($Node.Name) " -NoNewline -ForegroundColor $script:CAction
                Write-Host "($sizeStr)" -ForegroundColor DarkGray
            }
            else {
                $linePrefix = if ($IsLast) { "$Prefix└── " } else { "$Prefix├── " }

                if ($Node.Type -eq "Object") {
                    Write-Host "$linePrefix" -NoNewline -ForegroundColor DarkGray
                    Write-Host $Node.Name -ForegroundColor White
                }
                else {
                    $sizeStr = "$(TreeItemCount $Node.ObjectCount), $(TreeSize $Node.SizeBytes)"
                    Write-Host "$linePrefix" -NoNewline -ForegroundColor DarkGray
                    Write-Host "$($Node.Name) " -NoNewline -ForegroundColor Cyan
                    Write-Host "($sizeStr)" -ForegroundColor DarkGray
                }
            }

            $children = @($Node.Children)
            $bucketChildren = @($children | Where-Object { $_.Type -ne "Object" })
            $fileChildren = @($children | Where-Object { $_.Type -eq "Object" })

            $allItems = @()
            $allItems += $bucketChildren

            $truncatedFileCount = 0
            $childPrefix = if ($IsRoot) { "" } elseif ($IsLast) { "$Prefix    " } else { "$Prefix│   " }
            if ($fileChildren.Count -gt $MaxFiles) {
                $allItems += $fileChildren[0..($MaxFiles - 1)]
                $truncatedFileCount = $fileChildren.Count - $MaxFiles
            }
            else {
                $allItems += $fileChildren
            }

            for ($i = 0; $i -lt $allItems.Count; $i++) {
                $child = $allItems[$i]
                $childIsLast = $i -eq ($allItems.Count - 1)
                RenderTree -Node $child -Prefix $childPrefix -IsLast $childIsLast -IsRoot $false
            }

            if ($truncatedFileCount -gt 0) {
                Write-Host "$childPrefix└── " -NoNewline -ForegroundColor DarkGray
                Write-Host "... $truncatedFileCount more" -ForegroundColor $script:CNum
            }
        }

        $script:TreeNameFilter = $Name
        try {
            $root = BuildTree -Dir $Path -Root $Path -CurrentDepth 0
            if ($Raw) { return $root }
            RenderTree -Node $root -Prefix "" -IsLast $false -IsRoot $true
        }
        finally {
            $script:TreeNameFilter = $null
        }
        return
    }

    $results = [System.Collections.ArrayList]::new()

    if ($Recurse) {
        # Recursive mode: all directories, direct counts
        function Scan-Recurse {
            param([string]$Dir, [int]$currentDepth = 1)
            $di = [System.IO.DirectoryInfo]::new($Dir)
            $directCount = $di.GetFiles("*.dat").Length + $di.GetFiles("*.json").Length
            $hasSubBuckets = $false

            foreach ($child in $di.GetDirectories()) {
                if ($child.Name -eq ".buckets") { continue }
                $hasSubBuckets = $true
                if ($currentDepth -lt $Depth) {
                    Scan-Recurse -Dir $child.FullName -currentDepth ($currentDepth + 1)
                }
            }

            $relPath = $Dir.Substring($Path.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
            if ($directCount -gt 0 -or $hasSubBuckets) {
                $obj = [PSCustomObject]@{ Name = $relPath; ObjectCount = $directCount; HasSubBuckets = $hasSubBuckets }
                Add-HiddenProperty -Target $obj -Name 'Path' -Value $Dir
                $null = $results.Add($obj)
            }
        }

        $rootDi = [System.IO.DirectoryInfo]::new($Path)
        foreach ($subDir in $rootDi.GetDirectories()) {
            if ($subDir.Name -eq ".buckets") { continue }
            Scan-Recurse -Dir $subDir.FullName -currentDepth 1
        }
    }
    else {
        # Non-recursive mode: top-level only, aggregated counts
        function Get-AggregatedStats {
            param([string]$Dir, [int]$currentDepth = 1)
            $di = [System.IO.DirectoryInfo]::new($Dir)
            $count = $di.GetFiles("*.dat").Length + $di.GetFiles("*.json").Length
            $hasSubBuckets = $false

            foreach ($child in $di.GetDirectories()) {
                if ($child.Name -eq ".buckets") { continue }
                $hasSubBuckets = $true
                if ($currentDepth -lt $Depth) {
                    $childStats = Get-AggregatedStats -Dir $child.FullName -currentDepth ($currentDepth + 1)
                    $count += $childStats.TotalCount
                }
            }

            [PSCustomObject]@{ TotalCount = $count; HasSubBuckets = $hasSubBuckets }
        }

        $rootDi = [System.IO.DirectoryInfo]::new($Path)
        foreach ($subDir in $rootDi.GetDirectories()) {
            if ($subDir.Name -eq ".buckets") { continue }
            $stats = Get-AggregatedStats -Dir $subDir.FullName -currentDepth 1
            $obj = [PSCustomObject]@{ Name = $subDir.Name; ObjectCount = $stats.TotalCount; HasSubBuckets = $stats.HasSubBuckets }
            Add-HiddenProperty -Target $obj -Name 'Path' -Value $subDir.FullName
            $null = $results.Add($obj)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        if ($Name -match '[\*\?]') {
            $results = $results | Where-Object { $_.Name -like $Name }
        } else {
            $results = $results | Where-Object { $_.Name -like "*$Name*" }
        }
    }

    $results
}