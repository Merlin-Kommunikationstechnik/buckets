function Get-BucketPath {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Path
    )

    if ($script:LastPWD -ne $PWD.Path) { & $script:ClearCache }
    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $cacheKey = "${Path}|${Name}"
    if ($script:BucketPathCache.ContainsKey($cacheKey)) {
        return $script:BucketPathCache[$cacheKey]
    }
    $bucketPath = Resolve-SafePath -Path (Join-Path $Path $Name)
    $script:BucketPathCache[$cacheKey] = $bucketPath
    return $bucketPath
}