function Get-BucketStats {
    <#
    .SYNOPSIS
    Shows statistics for a bucket.
    .DESCRIPTION
    Returns object count, total storage size, and oldest/newest object timestamps
    for the specified bucket. Returns $null if the bucket does not exist.
    With -Recurse, shows stats for all sub-buckets recursively (respects -Depth).
    .PARAMETER Bucket
    Name of the bucket to analyze.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Recurse
    Show stats for all sub-buckets recursively (one row per bucket).
    .PARAMETER Depth
    Maximum nesting depth when recursing. Default: unlimited.
    .OUTPUTS
    PSCustomObject with Name, Path, ObjectCount, TotalSize, HasSubBuckets,
    OldestObject, and NewestObject properties. TotalSizeBytes is hidden.
    .EXAMPLE
    Get-BucketStats -Bucket users
    .EXAMPLE
    Get-BucketStats -Bucket inventory -Recurse
    .EXAMPLE
    Get-BucketStats -Bucket inventory -Recurse -Depth 2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Bucket,
        [string]$Path,
        [switch]$Recurse,
        [int]$Depth = [int]::MaxValue
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path
    if (-not [System.IO.Directory]::Exists($bucketPath)) {
        Write-Warning "Bucket '$Bucket' not found at '$bucketPath'"
        return
    }

    $results = [System.Collections.ArrayList]::new()

    function _EnumStats {
        param([string]$Dir, [string]$Rel, [int]$CDepth)
        $di = [System.IO.DirectoryInfo]::new($Dir)
        $files = @($di.GetFiles("*.dat")) + @($di.GetFiles("*.json"))
        $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
        $oldest = $null; $newest = $null
        foreach ($f in $files) {
            if ($null -eq $oldest -or $f.CreationTime -lt $oldest) { $oldest = $f.CreationTime }
            if ($null -eq $newest -or $f.CreationTime -gt $newest) { $newest = $f.CreationTime }
        }
        $hasSub = @($di.GetDirectories() | Where-Object Name -ne '.buckets').Count -gt 0

        $obj = [PSCustomObject]@{
            Name         = $Rel
            Path         = $Dir
            ObjectCount  = $files.Count
            TotalSize    = if ($totalSize) { "$([math]::Round($totalSize / 1KB, 2)) KB" } else { "0 KB" }
            HasSubBuckets = $hasSub
            OldestObject = $oldest
            NewestObject = $newest
        }
        Add-HiddenProperty -Target $obj -Name 'TotalSizeBytes' -Value $(if ($totalSize) { $totalSize } else { 0 })
        $null = $results.Add($obj)

        if ($Recurse) {
            foreach ($child in ($di.GetDirectories() | Sort-Object Name)) {
                if ($child.Name -eq ".buckets") { continue }
                if ($CDepth -ge $Depth) { break }
                $childRel = "$Rel/$($child.Name)"
                _EnumStats -Dir $child.FullName -Rel $childRel -CDepth ($CDepth + 1)
            }
        }
    }

    _EnumStats -Dir $bucketPath -Rel $Bucket -CDepth 1

    if ($results.Count -eq 0) { return }
    $results
}