function Find-ObjectFile {
    param([string]$BucketPath, [string]$Key)

    if ([string]::IsNullOrWhiteSpace($Key) -or -not [System.IO.Directory]::Exists($BucketPath)) { return $null }

    $di = [System.IO.DirectoryInfo]::new($BucketPath)
    $target = $Key.ToLowerInvariant()
    $hasWildcard = $target -match '[\*\?]'

    foreach ($f in @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))) {
        $baseLower = [System.IO.Path]::GetFileNameWithoutExtension($f.Name).ToLowerInvariant()
        if ($hasWildcard) { if ($baseLower -like $target) { return $f } }
        elseif ($baseLower -eq $target) { return $f }
    }

    return $null
}