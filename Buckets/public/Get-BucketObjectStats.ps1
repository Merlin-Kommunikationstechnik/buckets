function Get-BucketObjectStats {
    <#
    .SYNOPSIS
    Returns detailed per-object statistics for objects in a bucket.
    .DESCRIPTION
    Enumerates objects and reads lightweight metadata (format, size, type, timestamps,
    compression status) without full deserialization. Peeks at file content to determine
    object type (Object, Array, or Value) from the first bytes.
    .PARAMETER Bucket
    Bucket name to scan. If omitted, scans all buckets under -Path. Supports wildcards.
    .PARAMETER Key
    Object key(s) to look up. Accepts multiple values (e.g. -Key "alpha", "beta").
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Match
    Filter keys by pattern (wildcard). Case-insensitive.
    .PARAMETER Recurse
    Recurse into nested sub-buckets. Without this switch, only returns stats from the specified bucket directory.
    .PARAMETER Depth
    Maximum nesting depth when recursing. Default: unlimited.
    .OUTPUTS
    PSCustomObject with Bucket, Key, Format, Type, Size, LastWriteTime, and IsCompressed
    properties. Path is included as a hidden property.
    .EXAMPLE
    Get-BucketObjectStats -Bucket users
    .EXAMPLE
    Get-BucketObjectStats -Bucket users -Match "*admin*"
    .EXAMPLE
    Get-BucketObjectStats -Bucket users -Key "alice"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string[]]$Key,
        [Parameter(Position = 1)][string]$Bucket,
        [string]$Path,
        [string]$Match,
        [switch]$Recurse,
        [int]$Depth = [int]::MaxValue
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    $bucketPaths = @()
    if (-not [string]::IsNullOrWhiteSpace($Bucket)) {
        if ($Bucket -match '[\*\?]') {
            $cachedBuckets = Get-Bucket -Path $Path -Recurse -Depth $Depth
            $matched = $cachedBuckets | Where-Object { $_.Name -like $Bucket }
            $bucketPaths += $matched | ForEach-Object { $_.Path }
        }
        else {
            $bp = Get-BucketPath -Name $Bucket -Path $Path
            $bucketPaths += $bp
            if ($Recurse) {
                $nested = Get-Bucket -Path $Path -Recurse -Depth $Depth | Where-Object { $_.Name -like "$Bucket/*" }
                $bucketPaths += $nested | ForEach-Object { $_.Path }
            }
        }
    }
    else {
        if ([System.IO.Directory]::Exists($Path)) {
            $bucketPaths += [System.IO.DirectoryInfo]::new($Path).GetDirectories() | ForEach-Object { $_.FullName }
        }
    }

    $results = [System.Collections.ArrayList]::new()

    foreach ($bucketPath in $bucketPaths) {
        if (-not [System.IO.Directory]::Exists($bucketPath)) { continue }
        $bucketName = $bucketPath.Substring($Path.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
        $di = [System.IO.DirectoryInfo]::new($bucketPath)

        $keys = @($Key | Where-Object { $_ })
        if ($keys.Count -gt 0) {
            foreach ($singleKey in $keys) {
                $jsonFile = [System.IO.Path]::Combine($bucketPath, "${singleKey}.json")
                $datFile = [System.IO.Path]::Combine($bucketPath, "${singleKey}.dat")
                $found = $false
                foreach ($filePath in @($datFile, $jsonFile)) {
                    if ([System.IO.File]::Exists($filePath)) {
                        $f = [System.IO.FileInfo]::new($filePath)
                        $info = Resolve-ObjectType -FileInfo $f
                        $entry = [PSCustomObject]@{
                            Bucket        = $bucketName
                            Key           = $singleKey
                            Format        = if ($f.Extension -eq ".json") { "JSON" } else { "Binary" }
                            Type          = $info.Type
                            Size          = $f.Length
                            LastWriteTime = $f.LastWriteTime
                            IsCompressed  = $info.IsCompressed
                        }
                        Add-HiddenProperty -Target $entry -Name 'Path' -Value $f.FullName
                        $null = $results.Add($entry)
                        $found = $true
                        break
                    }
                }
                if (-not $found) {
                    Write-Warning "Key '$singleKey' not found in bucket '$bucketName'"
                }
            }
            continue
        }

        $files = @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))
        foreach ($f in $files) {
            $fKey = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if (-not [string]::IsNullOrWhiteSpace($Match) -and $fKey -notlike $Match) { continue }
            $info = Resolve-ObjectType -FileInfo $f
            $entry = [PSCustomObject]@{
                Bucket        = $bucketName
                Key           = $fKey
                Format        = if ($f.Extension -eq ".json") { "JSON" } else { "Binary" }
                Type          = $info.Type
                Size          = $f.Length
                LastWriteTime = $f.LastWriteTime
                IsCompressed  = $info.IsCompressed
            }
            Add-HiddenProperty -Target $entry -Name 'Path' -Value $f.FullName
            $null = $results.Add($entry)
        }
    }

    $results
}