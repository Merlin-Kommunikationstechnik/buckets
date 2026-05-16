function Get-ObjectFiles {
    param([string]$BucketPath, [string[]]$Key)

    $di = [System.IO.DirectoryInfo]::new($BucketPath)
    $files = @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))
    $keys = @($Key | Where-Object { $_ })
    if ($keys.Count -eq 0) { return $files }

    $targets = @($keys | ForEach-Object { $_.ToLowerInvariant() })
    $results = [System.Collections.ArrayList]::new()
    foreach ($f in $files) {
        $baseLower = [System.IO.Path]::GetFileNameWithoutExtension($f.Name).ToLowerInvariant()
        foreach ($t in $targets) {
            $matched = if ($t -match '[\*\?]') { $baseLower -like $t } else { $baseLower -eq $t }
            if ($matched) { $null = $results.Add($f); break }
        }
    }
    return $results.ToArray()
}