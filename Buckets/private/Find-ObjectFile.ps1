function Find-ObjectFile {
    param([string]$BucketPath, [string]$Key)

    if ([string]::IsNullOrWhiteSpace($Key) -or -not [System.IO.Directory]::Exists($BucketPath)) { return $null }

    $di = [System.IO.DirectoryInfo]::new($BucketPath)
    $target = $Key.ToLowerInvariant()

    foreach ($f in @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $baseLower = $base.ToLowerInvariant()
        if ($baseLower -eq $target -or $baseLower.StartsWith("${target}_") -or $baseLower.StartsWith("${target}.")) { return $f }
    }

    return $null
}