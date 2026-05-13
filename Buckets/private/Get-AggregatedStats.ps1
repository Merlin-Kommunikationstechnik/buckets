function Get-AggregatedStats {
            param([string]$Dir)
            $di = [System.IO.DirectoryInfo]::new($Dir)
            $count = $di.GetFiles("*.dat").Length + $di.GetFiles("*.json").Length
            $hasSubBuckets = $false

            foreach ($child in $di.GetDirectories()) {
                if ($child.Name -eq ".buckets") { continue }
                $hasSubBuckets = $true
                $childStats = Get-AggregatedStats -Dir $child.FullName
                $count += $childStats.TotalCount
            }

            [PSCustomObject]@{ TotalCount = $count; HasSubBuckets = $hasSubBuckets }
        }