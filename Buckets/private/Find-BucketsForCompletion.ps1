function Find-BucketsForCompletion {
    param([string]$Dir, [string]$Root, [string]$Filter)

    $sep = '/'
    $idx = $Filter.IndexOf($sep)
    if ($idx -ge 0) {
        $prefix = $Filter.Substring(0, $idx)
        $rem = $Filter.Substring($idx + 1)
        $sub = Join-Path $Dir $prefix
        if (-not (Test-Path -LiteralPath $sub)) { return }
        Find-BucketsForCompletion -Dir $sub -Root $Root -Filter $rem
        return
    }

    $di = [System.IO.DirectoryInfo]::new($Dir)
    foreach ($child in $di.GetDirectories()) {
        if ($child.Name -eq ".buckets") { continue }
        $hasFiles = $child.GetFiles("*.dat").Length -gt 0 -or $child.GetFiles("*.json").Length -gt 0
        $hasSubDirs = $child.GetDirectories() | Where-Object { $_.Name -ne ".buckets" } | Select-Object -First 1
        if (-not $hasFiles -and -not $hasSubDirs) { continue }
        if ($Filter -ne "*" -and $child.Name -notlike "$Filter*") { continue }
        $rel = if ($Dir -eq $Root) { $child.Name } else {
            $parentRel = $Dir.Substring($Root.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
            "$parentRel/$($child.Name)"
        }
        $rel
    }
}