function Find-MatchingBuckets {
        param([string]$Root, [string[]]$Patterns)

        function Scan-Dir {
            param([string]$Dir)
            $matched = @()
            if (-not [System.IO.Directory]::Exists($Dir)) { return $matched }
            $di = [System.IO.DirectoryInfo]::new($Dir)
            $relName = ""
            if ($Dir -ne $Root) {
                $relName = $Dir.Substring($Root.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
            }
            if ($Dir -ne $Root) {
                foreach ($pattern in $Patterns) {
                    if ($pattern -match '[\*\?]') {
                        if ($relName -like $pattern) {
                            $matched += [PSCustomObject]@{ Name = $relName; Path = $Dir }
                            break
                        }
                    }
                    elseif ($pattern -eq "*" -or $relName -eq $pattern -or ($relName -like "$pattern*") -or ($relName -like "*/$pattern") -or ($relName -like "*/$pattern/*") -or ($relName -like "$pattern/*")) {
                        $matched += [PSCustomObject]@{ Name = $relName; Path = $Dir }
                        break
                    }
                }
            }
            foreach ($subDir in $di.GetDirectories()) {
                if ($subDir.Name -eq ".buckets") { continue }
                $matched += Scan-Dir -Dir $subDir.FullName
            }
            $matched
        }

        if ([System.IO.Directory]::Exists($Root)) {
            Scan-Dir -Dir $Root
        }
    }