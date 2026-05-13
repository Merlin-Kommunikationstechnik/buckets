function Get-BucketStats {
    <#
    .SYNOPSIS
    Shows statistics for a bucket.
    .DESCRIPTION
    Returns object count, total storage size, and oldest/newest object timestamps
    for the specified bucket. Returns $null if the bucket does not exist.
    .PARAMETER Bucket
    Name of the bucket to analyze.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .OUTPUTS
    PSCustomObject with Name, Path, ObjectCount, TotalSize, OldestObject, and NewestObject
    properties. TotalSizeBytes is included as a hidden property.
    .EXAMPLE
    Get-BucketStats -Bucket users
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Bucket,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path
    if (-not [System.IO.Directory]::Exists($bucketPath)) {
        Write-Warning "Bucket '$Bucket' not found at '$bucketPath'"
        return
    }

    $di = [System.IO.DirectoryInfo]::new($bucketPath)
    $datFiles = @($di.GetFiles("*.dat"))
    $jsonFiles = @($di.GetFiles("*.json"))

    $fileObjects = $datFiles + $jsonFiles
    $totalSize = ($fileObjects | Measure-Object -Property Length -Sum).Sum
    $oldest = $null; $newest = $null
    foreach ($f in $fileObjects) {
        if ($null -eq $oldest -or $f.CreationTime -lt $oldest) { $oldest = $f.CreationTime }
        if ($null -eq $newest -or $f.CreationTime -gt $newest) { $newest = $f.CreationTime }
    }

    $obj = [PSCustomObject]@{
        Name         = $Bucket
        Path         = $bucketPath
        ObjectCount  = $fileObjects.Count
        TotalSize    = if ($totalSize) { "$([math]::Round($totalSize / 1KB, 2)) KB" } else { "0 KB" }
        OldestObject = $oldest
        NewestObject = $newest
    }
    Add-HiddenProperty -Target $obj -Name 'TotalSizeBytes' -Value $(if ($totalSize) { $totalSize } else { 0 })
    $obj
}