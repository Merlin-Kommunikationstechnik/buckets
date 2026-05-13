function Find-BucketsForCompletion {
        param([string]$Dir, [string]$Root, [string]$Filter)
        $di = [System.IO.DirectoryInfo]::new($Dir)
        $hasFiles = $di.GetFiles("*.dat").Length -gt 0 -or $di.GetFiles("*.json").Length -gt 0
        $relName = ""
        if ($Dir -ne $Root) {
            $relName = $Dir.Substring($Root.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
        }
        if ($hasFiles) {
            if ($Filter -eq "*" -or $relName -like "$Filter*" -or ($relName -contains $Filter)) {
                $relName
            }
        }
        foreach ($subDir in $di.GetDirectories()) {
            if ($subDir.Name -eq ".buckets") { continue }
            Find-BucketsForCompletion -Dir $subDir.FullName -Root $Root -Filter $Filter
        }
    }