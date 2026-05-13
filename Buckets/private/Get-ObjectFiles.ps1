function Get-ObjectFiles {
    param([string]$BucketPath, [string]$Key)

    $di = [System.IO.DirectoryInfo]::new($BucketPath)
    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $results = [System.Collections.ArrayList]::new()
        $target = $Key.ToLowerInvariant()
        foreach ($f in @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))) {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            $baseLower = $base.ToLowerInvariant()
            if ($baseLower -eq $target -or $baseLower.StartsWith("${target}_") -or $baseLower.StartsWith("${target}.")) {
                $null = $results.Add($f)
            }
        }
        return $results.ToArray()
    }
    else {
        return @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))
    }
}