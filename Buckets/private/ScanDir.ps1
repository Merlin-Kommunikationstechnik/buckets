function ScanDir {
            param([string]$Dir, [string]$Root)
            $stats = @{ ObjectCount = 0; SizeBytes = 0; BucketCount = 0 }
            if (-not [System.IO.Directory]::Exists($Dir)) { return $stats }
            $di = [System.IO.DirectoryInfo]::new($Dir)
            $stats.ObjectCount += $di.GetFiles("*.dat").Length + $di.GetFiles("*.json").Length
            $di.GetFiles("*.dat") | ForEach-Object { $stats.SizeBytes += $_.Length }
            $di.GetFiles("*.json") | ForEach-Object { $stats.SizeBytes += $_.Length }

            foreach ($sub in $di.GetDirectories()) {
                if ($sub.Name -eq ".buckets") { continue }
                $childStats = ScanDir -Dir $sub.FullName -Root $Root
                $stats.ObjectCount += $childStats.ObjectCount
                $stats.SizeBytes += $childStats.SizeBytes
                $stats.BucketCount += $childStats.BucketCount
                if ($childStats.ObjectCount -gt 0) { $stats.BucketCount++ }
            }

            $isBucket = $stats.ObjectCount -gt 0
            if ($Dir -ne $Root -and -not $isBucket -and $stats.BucketCount -gt 0) { $isBucket = $true }

            if ($Dir -eq $Root) {
                $stats.IsBucket = $true
                $stats.IsRoot = $true
            }
            else {
                $stats.IsBucket = $isBucket
                $stats.IsRoot = $false
            }
            $stats
        }