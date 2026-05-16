function Scan-Recurse {
    param([string]$Dir, [int]$currentDepth = 1, [int]$Depth = [int]::MaxValue, [System.Collections.Generic.HashSet[string]]$Visited)
    $di = [System.IO.DirectoryInfo]::new($Dir)
    $directCount = $di.GetFiles("*.dat").Length + $di.GetFiles("*.json").Length
    $hasSubBuckets = $false

    if ($null -eq $Visited) { $Visited = [System.Collections.Generic.HashSet[string]]::new() }
    $dirResolved = [System.IO.Path]::GetFullPath($(if ($null -ne $di.LinkTarget) { $di.LinkTarget } else { $di.FullName }))
    if ($Visited.Contains($dirResolved)) { return }
    $null = $Visited.Add($dirResolved)

    foreach ($child in $di.GetDirectories()) {
        if ($child.Name -eq ".buckets") { continue }
        $childResolved = [System.IO.Path]::GetFullPath($(if ($null -ne $child.LinkTarget) { $child.LinkTarget } else { $child.FullName }))
        if ($Visited.Contains($childResolved)) { continue }
        $null = $Visited.Add($childResolved)
        $hasSubBuckets = $true
        if ($currentDepth -lt $Depth) {
            Scan-Recurse -Dir $child.FullName -currentDepth ($currentDepth + 1) -Depth $Depth -Visited $Visited
        }
    }

    $relPath = $Dir.Substring($Path.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
    if ($directCount -gt 0 -or $hasSubBuckets) {
        $obj = [PSCustomObject]@{ Name = $relPath; ObjectCount = $directCount; HasSubBuckets = $hasSubBuckets }
        Add-HiddenProperty -Target $obj -Name 'Path' -Value $Dir
        $null = $results.Add($obj)
    }
}