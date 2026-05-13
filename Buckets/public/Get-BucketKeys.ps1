function Get-BucketKeys {
    <#
    .SYNOPSIS
    Lists object keys in a bucket without deserializing objects.
    .DESCRIPTION
    Fast key enumeration that reads filenames only, avoiding the overhead of
    deserializing object data. Returns only Bucket and Key per object.
    For detailed per-object statistics (format, size, type, timestamps, compression),
    use Get-BucketObjectStats.
    .PARAMETER Bucket
    Bucket name to scan. If omitted, scans all buckets under -Path. Supports wildcards.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Match
    Filter keys by pattern (wildcard). Case-insensitive.
    .OUTPUTS
    PSCustomObject with Bucket and Key properties.
    .EXAMPLE
    Get-BucketKeys -Bucket users
    .EXAMPLE
    Get-BucketKeys -Match "*admin*"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Bucket,
        [string]$Path,
        [string]$Match
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    $bucketPaths = @()
    if (-not [string]::IsNullOrWhiteSpace($Bucket)) {
        if ($Bucket -match '[\*\?]') {
            $cachedBuckets = Get-Bucket -Path $Path -Recurse
            $matched = $cachedBuckets | Where-Object { $_.Name -like $Bucket }
            $bucketPaths += $matched | ForEach-Object { $_.Path }
        }
        else {
            $bucketPaths += Get-BucketPath -Name $Bucket -Path $Path
        }
    }
    else {
        if ([System.IO.Directory]::Exists($Path)) {
            $bucketPaths += [System.IO.DirectoryInfo]::new($Path).GetDirectories() | ForEach-Object { $_.FullName }
        }
    }

    foreach ($bucketPath in $bucketPaths) {
        if (-not [System.IO.Directory]::Exists($bucketPath)) { continue }
        $bucketName = $bucketPath.Substring($Path.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
        $di = [System.IO.DirectoryInfo]::new($bucketPath)
        $files = @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))
        foreach ($f in $files) {
            $key = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if (-not [string]::IsNullOrWhiteSpace($Match) -and $key -notlike $Match) { continue }
            [PSCustomObject]@{
                Bucket = $bucketName
                Key    = $key
            }
        }
    }
}