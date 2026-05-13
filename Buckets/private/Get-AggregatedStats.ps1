function Get-AggregatedStats {
    param([string]$Dir, [int]$currentDepth = 1, [int]$Depth = [int]::MaxValue)
    $di = [System.IO.DirectoryInfo]::new($Dir)
    $count = $di.GetFiles("*.dat").Length + $di.GetFiles("*.json").Length
    $hasSubBuckets = $false

    foreach ($child in $di.GetDirectories()) {
        if ($child.Name -eq ".buckets") { continue }
        $hasSubBuckets = $true
        if ($currentDepth -lt $Depth) {
            $childStats = Get-AggregatedStats -Dir $child.FullName -currentDepth ($currentDepth + 1) -Depth $Depth
            $count += $childStats.TotalCount
        }
    }

    [PSCustomObject]@{ TotalCount = $count; HasSubBuckets = $hasSubBuckets }
}