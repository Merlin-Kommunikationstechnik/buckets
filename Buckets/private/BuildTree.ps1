function BuildTree {
            param([string]$Dir, [string]$Root, [int]$CurrentDepth)

            $relPath = if ($Dir -eq $Root) {
                ""
            }
            else {
                $Dir.Substring($Root.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
            }

            $displayName = if ($Dir -eq $Root) {
                Split-Path $Root -Leaf
            }
            else {
                Split-Path $Dir -Leaf
            }

            $stats = ScanDir -Dir $Dir -Root $Root
            $type = if ($stats.IsRoot) { "Root" } else { "Bucket" }

            $node = [PSCustomObject]@{
                Name         = $displayName
                Type         = $type
                Path         = $relPath
                ObjectCount  = $stats.ObjectCount
                SizeBytes    = $stats.SizeBytes
                Depth        = $CurrentDepth
                Children     = [System.Collections.ArrayList]::new()
                _BucketName  = if ($stats.IsBucket -and -not $stats.IsRoot) { $relPath } else { "" }
                _BucketKey   = ""
            }
            $node.PSObject.TypeNames.Insert(0, "Buckets.Tree")

            $di = [System.IO.DirectoryInfo]::new($Dir)

            $subDirs = @()
            foreach ($sub in ($di.GetDirectories() | Sort-Object Name)) {
                if ($sub.Name -eq ".buckets") { continue }
                $subRelPath = $sub.FullName.Substring($Root.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
                if (-not [string]::IsNullOrWhiteSpace($script:TreeNameFilter)) {
                    $subRelPathSlash = $subRelPath.TrimEnd('/') + '/'
                    $filterSlash = $script:TreeNameFilter.TrimEnd('/') + '/'
                    $subContainedInFilter = $filterSlash.StartsWith($subRelPathSlash)
                    $filterContainedInSub = $subRelPathSlash.StartsWith($filterSlash)
                    if (-not $subContainedInFilter -and -not $filterContainedInSub) { continue }
                }
                $subHasFiles = $sub.Exists -and ($sub.GetFiles("*.dat").Length -gt 0 -or $sub.GetFiles("*.json").Length -gt 0)
                $subStats = if ($sub.Exists) { ScanDir -Dir $sub.FullName -Root $Root } else { @{ ObjectCount = 0; SizeBytes = 0; BucketCount = 0 } }
                if ($subHasFiles -or $subStats.BucketCount -gt 0) {
                    $subDirs += $sub
                }
            }

            foreach ($sub in $subDirs) {
                if ($CurrentDepth -lt $Depth -or $Objects) {
                    $child = BuildTree -Dir $sub.FullName -Root $Root -CurrentDepth ($CurrentDepth + 1)
                    $null = $node.Children.Add($child)
                }
            }

            if ($Objects) {
                foreach ($f in ($di.GetFiles("*.dat") + $di.GetFiles("*.json") | Sort-Object Name)) {
                    $keyName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                    $fNode = [PSCustomObject]@{
                        Name         = $keyName
                        Type         = "Object"
                        Path         = "$relPath/$keyName"
                        ObjectCount  = 1
                        SizeBytes    = $f.Length
                        Depth        = $CurrentDepth + 1
                        Children     = [System.Collections.ArrayList]::new()
                        _BucketName  = $relPath
                        _BucketKey   = $keyName
                    }
                    $fNode.PSObject.TypeNames.Insert(0, "Buckets.Tree")
                    $null = $node.Children.Add($fNode)
                }
            }

            $node
        }