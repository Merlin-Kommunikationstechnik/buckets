function Scan-Recurse {
    param([string]$Dir, [int]$currentDepth = 1, [int]$Depth = [int]::MaxValue)
    $di = [System.IO.DirectoryInfo]::new($Dir)
    $directCount = $di.GetFiles("*.dat").Length + $di.GetFiles("*.json").Length
    $hasSubBuckets = $false

    foreach ($child in $di.GetDirectories()) {
        if ($child.Name -eq ".buckets") { continue }
        $hasSubBuckets = $true
        if ($currentDepth -lt $Depth) {
            Scan-Recurse -Dir $child.FullName -currentDepth ($currentDepth + 1) -Depth $Depth
        }
    }

    $relPath = $Dir.Substring($Path.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
    if ($directCount -gt 0 -or $hasSubBuckets) {
        $obj = [PSCustomObject]@{ Name = $relPath; ObjectCount = $directCount; HasSubBuckets = $hasSubBuckets }
        Add-HiddenProperty -Target $obj -Name 'Path' -Value $Dir
        $null = $results.Add($obj)
    }
}