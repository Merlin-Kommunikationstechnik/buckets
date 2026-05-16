function Remove-BucketObject {
    <#
    .SYNOPSIS
    Removes objects from a bucket or deletes the bucket directory itself.
    .DESCRIPTION
    Removes objects from a bucket by key, match, filter, or all. Use -Drop to
    delete the bucket directory itself (safety-checked for .dat/.json only).
    Supports -WhatIf for preview and -PassThru for returning removed metadata.

    When removing by -Key, the bucket name defaults to "default" if omitted.
    When removing all objects (-Bucket alone), objects are removed but the
    bucket directory stays. Add -Drop to delete the container.
    .PARAMETER InputObject
    The object to remove. Accepts pipeline input. If it has _BucketName and _BucketKey
    metadata, bucket and key are auto-resolved.
    .PARAMETER Key
    Object key(s) to remove (Position 0, ByKey set). Accepts multiple values.
    Looks for both .json and .dat files. Case-insensitive.
    .PARAMETER Bucket
    Bucket name. In ByKey set, defaults to "default". Required in all other sets.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Match
    Hashtable of property-value pairs for bulk deletion. Supports $null values.
    .PARAMETER Filter
    ScriptBlock for custom bulk deletion. Use $_ to reference object properties.
    .PARAMETER Drop
    Delete the bucket directory itself (not just its objects). Safety-checked:
    only removes directories containing .dat/.json files (or empty).
    .PARAMETER Force
    Skip confirmation prompt when using -Drop.
    .PARAMETER Recurse
    Recurse into nested sub-buckets. Applies to -Drop, ByAll, and ByFilter.
    .PARAMETER Depth
    Maximum nesting depth when recursing. Default: unlimited.
    .PARAMETER PassThru
    Return metadata (Bucket, Key) for removed objects.
    .PARAMETER Quiet
    Suppress progress output.
    .EXAMPLE
    Remove-BucketObject -Bucket logs -Key "log-003"
    .EXAMPLE
    Remove-BucketObject -Bucket temp
    .EXAMPLE
    Remove-BucketObject -Bucket temp -Drop -Force
    .EXAMPLE
    Remove-BucketObject -Bucket users -Match @{ Active = $false }
    .EXAMPLE
    Remove-BucketObject -Bucket users -Filter { $_.Status -eq "cancelled" }
    .EXAMPLE
    Get-BucketObject -Bucket users -Match @{Role="guest"} | Remove-BucketObject
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByAll')]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [PSObject]$InputObject,

        [Parameter(Position = 0, ParameterSetName = 'ByKey')]
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [Alias('_BucketKey')]
        [string[]]$Key,

        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByAll')]
        [Parameter(Mandatory = $true, ParameterSetName = 'ByFilter')]
        [Parameter(Mandatory = $true, ParameterSetName = 'DropBucket')]
        [Parameter(ParameterSetName = 'ByKey')]
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [Alias('_BucketName')]
        [string[]]$Bucket = @('default'),

        [string]$Path,

        [Parameter(ParameterSetName = 'ByFilter')]
        [hashtable]$Match,

        [Parameter(ParameterSetName = 'ByFilter')]
        [scriptblock]$Filter,

        [Parameter(Mandatory = $true, ParameterSetName = 'DropBucket')]
        [switch]$Drop,

        [Parameter(ParameterSetName = 'DropBucket')]
        [switch]$Force,

        [Parameter(ParameterSetName = 'ByAll')]
        [Parameter(ParameterSetName = 'ByFilter')]
        [Parameter(ParameterSetName = 'DropBucket')]
        [Parameter(ParameterSetName = 'ByKey')]
        [switch]$Recurse,

        [Parameter(ParameterSetName = 'ByAll')]
        [Parameter(ParameterSetName = 'ByFilter')]
        [Parameter(ParameterSetName = 'DropBucket')]
        [Parameter(ParameterSetName = 'ByKey')]
        [int]$Depth = [int]::MaxValue,

        [switch]$PassThru,

        [switch]$Quiet
    )

    begin {
        $removedCount = 0; $lastBucket = ''; $removedKeys = [System.Collections.ArrayList]::new()
        $allProcessed = $false; $filterProcessed = $false; $dropProcessed = $false

        if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
        $Path = Resolve-SafePath -Path $Path

        if ($Drop) { $Force = $Force -or $PSBoundParameters.ContainsKey('Force') }

        function _GatherFiles {
            param([string]$Dir, [int]$CurrentDepth, [int]$MaxDepth, [string[]]$Key, [System.Collections.Generic.HashSet[string]]$Visited)
            $files = [System.Collections.ArrayList]::new()
            $di = [System.IO.DirectoryInfo]::new($Dir)
            $allFiles = @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))
            $keys = @($Key | Where-Object { $_ })
            if ($keys.Count -gt 0) {
                $targets = @($keys | ForEach-Object { $_.ToLowerInvariant() })
                $allFiles = @($allFiles | Where-Object {
                    $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name).ToLowerInvariant()
                    foreach ($t in $targets) {
                        $matched = if ($t -match '[\*\?]') { $base -like $t } else { $base -eq $t }
                        if ($matched) { return $true }
                    }
                    return $false
                })
            }
            foreach ($f in $allFiles) { $null = $files.Add($f) }
            if ($CurrentDepth -lt $MaxDepth) {
                foreach ($sub in $di.GetDirectories()) {
                    if ($sub.Name -eq '.buckets') { continue }
                    $subResolved = [System.IO.Path]::GetFullPath($(if ($null -ne $sub.LinkTarget) { $sub.LinkTarget } else { $sub.FullName }))
                    if ($Visited.Contains($subResolved)) { continue }
                    $null = $Visited.Add($subResolved)
                    foreach ($f in (_GatherFiles -Dir $sub.FullName -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -Key $Key -Visited $Visited)) { $null = $files.Add($f) }
                }
            }
            $files.ToArray()
        }
    }

    process {
        $fromPipeline = $false
        $bucketName = $Bucket[0]
        if ($null -ne $InputObject) {
            $hasMeta = $InputObject.PSObject.Properties['_BucketName'] -and $InputObject.PSObject.Properties['_BucketKey']
            if ($hasMeta) {
                if ([string]::IsNullOrWhiteSpace($bucketName) -or $bucketName -eq 'default') { $bucketName = $InputObject._BucketName; $Bucket = @($bucketName) }
                if ($null -eq $Key -or $Key.Count -eq 0 -or ($Key.Count -eq 1 -and [string]::IsNullOrWhiteSpace($Key[0]))) { $Key = @($InputObject._BucketKey) }
                $fromPipeline = $true
            }
        }

        if ($Drop) {
            if ($dropProcessed) { return }
            $dropProcessed = $true

            $resolvedRoot = Resolve-SafePath -Path $Path
            $bucketPaths = @()
            foreach ($b in $Bucket) {
                if ($b -match '[\*\?]') {
                    $matched = Find-MatchingBuckets -Root $Path -Patterns @($b)
                    foreach ($m in $matched) { $bucketPaths += $m.Path }
                } else {
                    $bucketPaths += Get-BucketPath -Name $b -Path $Path
                }
            }

            $removable = @()
            $skippedBuckets = @()
            foreach ($bPath in $bucketPaths) {
                if (-not [System.IO.Directory]::Exists($bPath)) { continue }
                $resolvedBucket = Resolve-SafePath -Path $bPath
                if (-not $resolvedBucket.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relName = $bPath.Substring($Path.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
                    $skippedBuckets += [PSCustomObject]@{ Name = $relName; Reason = "path resolves outside root" }
                    continue
                }

                $di = [System.IO.DirectoryInfo]::new($bPath)
                $allFiles = @($di.GetFiles())
                $otherFiles = @($allFiles | Where-Object { $_.Extension -notin ".dat", ".json" })
                if ($otherFiles.Count -gt 0) {
                    $relName = $bPath.Substring($Path.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
                    $skippedBuckets += [PSCustomObject]@{ Name = $relName; Reason = "contains $($otherFiles.Count) non-bucket file(s): $($otherFiles.Name -join ', ')" }
                    continue
                }

                $nestedBuckets = @()
                foreach ($subDir in $di.GetDirectories()) {
                    if ($subDir.Name -eq ".buckets") { continue }
                    if ($subDir.GetFiles("*.dat").Length -gt 0 -or $subDir.GetFiles("*.json").Length -gt 0) {
                        $nestedBuckets += $subDir.Name
                    }
                }

                $stats = Get-BucketStats -Bucket $bPath -Path $Path -ErrorAction SilentlyContinue
                $relName = $bPath.Substring($Path.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')

                $removable += [PSCustomObject]@{
                    Name = $relName
                    Objects = if ($stats) { $stats.ObjectCount } else { 0 }
                    Size = if ($stats) { $stats.TotalSize } else { "0 KB" }
                    Path = $bPath
                    HasNestedBuckets = $nestedBuckets.Count -gt 0
                    NestedBucketNames = $nestedBuckets
                }
            }

            if ($removable.Count -eq 0 -and $skippedBuckets.Count -eq 0) {
                Write-Warning "No buckets match '$Bucket'"
                return
            }

            if ($Recurse -and $removable.Count -gt 1) {
                $sorted = @($removable | Sort-Object { $_.Path.Length })
                $topLevel = @()
                foreach ($r in $sorted) {
                    $isChild = $false
                    foreach ($existing in $topLevel) {
                        if ($r.Path.StartsWith($existing.Path + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $isChild = $true; break
                        }
                    }
                    if (-not $isChild) { $topLevel += $r }
                }
                $removable = $topLevel
            }

            if ($WhatIfPreference) {
                if ($removable.Count -gt 0) {
                    Write-RemovalSummary -Title "What if: Remove the following bucket(s)" `
                        -Names $removable.Name -Counts $removable.Objects -Sizes $removable.Size -Nested $removable.NestedBucketNames
                }
                if ($skippedBuckets.Count -gt 0) {
                    Write-Host "  Skipped:" -ForegroundColor $script:CSkip
                    foreach ($s in $skippedBuckets) {
                        Write-Host "    " -NoNewline
                        Write-Host "$($s.Name)" -NoNewline -ForegroundColor $script:CPath
                        Write-Host " — " -NoNewline -ForegroundColor $script:CMuted
                        Write-Host "$($s.Reason)" -ForegroundColor $script:CError
                    }
                }
                return
            }

            if (-not $Force -and -not $Quiet -and $removable.Count -gt 0) {
                Write-RemovalSummary -Title "Remove $($removable.Count) bucket(s)?" `
                    -Names $removable.Name -Counts $removable.Objects -Sizes $removable.Size -Nested $removable.NestedBucketNames
            }

            if ($skippedBuckets.Count -gt 0 -and -not $Quiet) {
                foreach ($s in $skippedBuckets) {
                    Write-Host "  " -NoNewline -ForegroundColor $script:CMuted
                    Write-Host "$($s.Name)" -NoNewline -ForegroundColor $script:CPath
                    Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
                    Write-Host "$($s.Reason)" -ForegroundColor $script:CError
                }
            }

            $removedDirs = 0
            $removable = @($removable | Sort-Object { $_.Path.Length } -Descending)
            foreach ($r in $removable) {
                if (-not [System.IO.Directory]::Exists($r.Path)) { continue }
                $finalDi = [System.IO.DirectoryInfo]::new($r.Path)
                $finalFiles = @($finalDi.GetFiles())
                $finalOther = @($finalFiles | Where-Object { $_.Extension -notin ".dat", ".json" })
                if ($finalOther.Count -gt 0) {
                    Write-Warning "Bucket '$($r.Name)' now contains non-bucket files, aborting: $($finalOther.Name -join ', ')"
                    continue
                }

                $target = "bucket '$($r.Name)' ($($r.Objects) object(s), $($r.Size))"
                $shouldRemove = $Force
                if (-not $Force) {
                    $shouldRemove = $PSCmdlet.ShouldProcess($target, "Remove-BucketObject")
                }

                if ($shouldRemove) {
                    if ($r.HasNestedBuckets -and -not $Recurse) {
                        foreach ($f in $finalFiles) { $f.Delete() }
                        foreach ($d in $finalDi.GetDirectories()) {
                            if ($d.Name -eq '.buckets') { continue }
                            $hasBucketFiles = $d.GetFiles("*.dat").Length -gt 0 -or $d.GetFiles("*.json").Length -gt 0
                            if (-not $hasBucketFiles -and $d.GetDirectories().Length -eq 0) { $d.Delete() }
                        }
                        $remainingDirs = @($finalDi.GetDirectories())
                        if ($remainingDirs.Count -eq 0 -and $finalDi.GetFiles().Length -eq 0) { $finalDi.Delete() }
                        foreach ($ck in @($script:BucketPathCache.Keys | Where-Object { $_ -like "*|$($r.Name)" })) { $script:BucketPathCache.Remove($ck) }
                    } elseif ($Recurse) {
                        if ($Depth -eq [int]::MaxValue) {
                            [System.IO.Directory]::Delete($r.Path, $true)
                        } else {
                            function Remove-WithDepthLimit {
                                param([string]$Dir, [int]$CurrentDepth, [int]$MaxDepth)
                                $di = [System.IO.DirectoryInfo]::new($Dir)
                                foreach ($f in $di.GetFiles("*.dat")) { try { $f.Delete() } catch {} }
                                foreach ($f in $di.GetFiles("*.json")) { try { $f.Delete() } catch {} }
                                if ($CurrentDepth -lt $MaxDepth) {
                                    foreach ($sub in $di.GetDirectories()) {
                                        if ($sub.Name -eq '.buckets') { continue }
                                        Remove-WithDepthLimit -Dir $sub.FullName -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth
                                    }
                                }
                                $di.Refresh()
                                $remainingFiles = @($di.GetFiles())
                                $remainingDirs = @($di.GetDirectories() | Where-Object { $_.Name -ne '.buckets' })
                                if ($remainingFiles.Count -eq 0 -and $remainingDirs.Count -eq 0) { try { $di.Delete() } catch {} }
                            }
                            Remove-WithDepthLimit -Dir $r.Path -CurrentDepth 0 -MaxDepth $Depth
                        }
                        foreach ($ck in @($script:BucketPathCache.Keys | Where-Object { $_ -like "*|$($r.Name)*" })) { $script:BucketPathCache.Remove($ck) }
                    } else {
                        $finalDirs = @($finalDi.GetDirectories())
                        if ($finalDirs.Count -gt 0) {
                            Write-Warning "Bucket '$($r.Name)' contains non-bucket subdirectories, aborting"
                            continue
                        }
                        [System.IO.Directory]::Delete($r.Path, $true)
                        foreach ($ck in @($script:BucketPathCache.Keys | Where-Object { $_ -like "*|$($r.Name)" })) { $script:BucketPathCache.Remove($ck) }
                    }

                    $removedDirs++
                    if (-not $Quiet) {
                        Write-Host "$($r.Name)" -NoNewline -ForegroundColor $script:CPath
                        Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
                        $objLabel = if ($r.Objects -eq 1) { "1 object" } else { "$($r.Objects) objects" }
                        Write-Host $objLabel -NoNewline -ForegroundColor $script:CNum
                        Write-Host " removed" -ForegroundColor $script:CMuted
                    }
                }
            }

            if ($removedDirs -gt 1 -and -not $Quiet) {
                Write-Host $removedDirs -NoNewline -ForegroundColor $script:CNum
                Write-Host " buckets removed" -ForegroundColor $script:CMuted
            }
            return
        }

        if ($Key -and $Key.Count -gt 0 -and -not $fromPipeline) {
            $keys = @($Key | Where-Object { $_ })
            if ($keys.Count -gt 0) {
                $bucketPath = Get-BucketPath -Name $bucketName -Path $Path -ErrorAction SilentlyContinue
                if (-not $bucketPath -or -not [System.IO.Directory]::Exists($bucketPath)) {
                    Write-Warning "Bucket '$Bucket' not found"
                    return
                }

                $matchedFiles = @()
                if ($Recurse) {
                    $gv = [System.Collections.Generic.HashSet[string]]::new(); $matchedFiles = _GatherFiles -Dir $bucketPath -CurrentDepth 1 -MaxDepth $Depth -Key $keys -Visited $gv
                } else {
                    foreach ($singleKey in $keys) {
                        $file = Find-ObjectFile -BucketPath $bucketPath -Key $singleKey
                        if ($file) { $matchedFiles += $file }
                    }
                }
                if ($matchedFiles.Count -eq 0) {
                    Write-Warning "Object with key '$($Key -join ', ')' not found in bucket '$Bucket'"
                } else {
                    foreach ($file in $matchedFiles) {
                        $fileKey = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                        if ($PSCmdlet.ShouldProcess("object '$fileKey' from bucket '$Bucket'", "Remove-BucketObject")) {
                            if ($PassThru) {
                                [PSCustomObject]@{ Bucket = $Bucket; Key = $fileKey }
                            }
                            [System.IO.File]::Delete($file.FullName)
                            $parentDir = [System.IO.Path]::GetDirectoryName($file.FullName)
                            if ($parentDir.StartsWith($bucketPath)) {
                                $parentDi = [System.IO.DirectoryInfo]::new($parentDir)
                                $remaining = @($parentDi.GetFiles()) + @($parentDi.GetDirectories())
                                if ($remaining.Count -eq 0) { try { [System.IO.Directory]::Delete($parentDir) } catch {} }
                            }
                            $removedCount++
                            $lastBucket = $Bucket
                            $null = $removedKeys.Add($fileKey)
                        }
                    }
                }
                return
            }
        }

        if ($fromPipeline -and $Key -and $Key.Count -gt 0) {
            $bucketPath = Get-BucketPath -Name $bucketName -Path $Path -ErrorAction SilentlyContinue
            if (-not $bucketPath -or -not [System.IO.Directory]::Exists($bucketPath)) { return }
            foreach ($singleKey in $Key) {
                $file = Find-ObjectFile -BucketPath $bucketPath -Key $singleKey
                if (-not $file) { continue }
                $fileKey = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                if ($PSCmdlet.ShouldProcess("object '$fileKey' from bucket '$Bucket'", "Remove-BucketObject")) {
                    if ($PassThru) { [PSCustomObject]@{ Bucket = $Bucket; Key = $fileKey } }
                    [System.IO.File]::Delete($file.FullName)
                    $parentDir = [System.IO.Path]::GetDirectoryName($file.FullName)
                    if ($parentDir.StartsWith($bucketPath)) {
                        $parentDi = [System.IO.DirectoryInfo]::new($parentDir)
                        $remaining = @($parentDi.GetFiles()) + @($parentDi.GetDirectories())
                        if ($remaining.Count -eq 0) { try { [System.IO.Directory]::Delete($parentDir) } catch {} }
                    }
                    $removedCount++; $lastBucket = $Bucket; $null = $removedKeys.Add($fileKey)
                }
            }
            return
        }

        $isFilter = $Match -or $Filter
        if ($isFilter) {
            if ($filterProcessed) { return }
            $filterProcessed = $true

            $bucketPath = Get-BucketPath -Name $bucketName -Path $Path
            if (-not [System.IO.Directory]::Exists($bucketPath)) { Write-Verbose "Bucket '$Bucket' not found"; return }

            $di = [System.IO.DirectoryInfo]::new($bucketPath)
            $allFiles = if ($Recurse) { $gv = [System.Collections.Generic.HashSet[string]]::new(); _GatherFiles -Dir $bucketPath -CurrentDepth 1 -MaxDepth $Depth -Visited $gv } else { @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat")) }

            if ($allFiles.Count -eq 0) { Write-Verbose "Bucket '$Bucket' is already empty"; return }

            if ($WhatIfPreference) {
                $matchedKeys = [System.Collections.ArrayList]::new()
                foreach ($file in $allFiles) {
                    $obj = Read-BucketFile -File $file
                    if ($null -eq $obj) { continue }
                    if ($Match -and -not (Test-MatchFilter -Object $obj -Match $Match)) { continue }
                    if ($Filter -and ($null -eq ($obj | Where-Object $Filter))) { continue }
                    $null = $matchedKeys.Add([System.IO.Path]::GetFileNameWithoutExtension($file.Name))
                }
                if ($matchedKeys.Count -eq 0) { Write-Verbose "No objects matched the filter criteria in bucket '$Bucket'"; return }
                Write-Host ""
                Write-Host "  What if: Remove " -NoNewline -ForegroundColor $script:CMuted
                Write-Host $matchedKeys.Count -NoNewline -ForegroundColor $script:CNum
                Write-Host " matching object(s) from " -NoNewline -ForegroundColor $script:CMuted
                Write-Host $Bucket -NoNewline -ForegroundColor $script:CPath
                $recurseNote = if ($Recurse) { " (recursive, depth ${Depth})" } else { "" }
                Write-Host "$recurseNote" -ForegroundColor $script:CMuted
                $showKeys = $matchedKeys | Select-Object -First 5
                foreach ($k in $showKeys) { Write-Host "    $k" -ForegroundColor $script:CMuted }
                if ($matchedKeys.Count -gt 5) { Write-Host "    ... and $($matchedKeys.Count - 5) more" -ForegroundColor $script:CMuted }
                Write-Host ""
                return
            }

            $target = "matching objects from bucket '$Bucket'"
            if (-not $PSCmdlet.ShouldProcess($target, "Remove-BucketObject")) { return }

            $matchedFiles = [System.Collections.ArrayList]::new()
            $matchedKeys = [System.Collections.ArrayList]::new()
            foreach ($file in $allFiles) {
                $obj = Read-BucketFile -File $file
                if ($null -eq $obj) { continue }
                if ($Match -and -not (Test-MatchFilter -Object $obj -Match $Match)) { continue }
                if ($Filter -and ($null -eq ($obj | Where-Object $Filter))) { continue }
                $null = $matchedFiles.Add($file)
                $null = $matchedKeys.Add([System.IO.Path]::GetFileNameWithoutExtension($file.Name))
            }

            if ($matchedFiles.Count -eq 0) { Write-Verbose "No objects matched the filter criteria in bucket '$Bucket'"; return }

            $matchSize = ($matchedFiles | Measure-Object -Property Length -Sum).Sum
            $sizeStr = if ($matchSize) { "$([math]::Round($matchSize / 1KB, 2)) KB" } else { "0 KB" }

            if (-not $Quiet) {
                Write-Host ""
                Write-Host "  Remove " -NoNewline -ForegroundColor $script:CMuted
                Write-Host $matchedFiles.Count -NoNewline -ForegroundColor $script:CNum
                Write-Host " matching object(s) from " -NoNewline -ForegroundColor $script:CMuted
                Write-Host $Bucket -NoNewline -ForegroundColor $script:CPath
                $recurseNote = if ($Recurse) { " (recursive, depth ${Depth})" } else { "" }
                Write-Host "$recurseNote ($sizeStr)" -ForegroundColor $script:CMuted
                $showKeys = $matchedKeys | Select-Object -First 5
                foreach ($k in $showKeys) { Write-Host "    " -NoNewline; Write-Host $k -ForegroundColor $script:CNum }
                if ($matchedKeys.Count -gt 5) { Write-Host "    ... and $($matchedKeys.Count - 5) more" -ForegroundColor $script:CMuted }
                Write-Host ""
            }

            foreach ($f in $matchedFiles) {
                if ($PassThru) {
                    $relPath = $f.FullName.Substring($bucketPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
                    $keyOnly = [System.IO.Path]::ChangeExtension($relPath, $null).TrimEnd('.')
                    [PSCustomObject]@{ Bucket = $Bucket; Key = $keyOnly }
                }
                [System.IO.File]::Delete($f.FullName)
                $removedCount++; $lastBucket = $Bucket; $null = $removedKeys.Add([System.IO.Path]::GetFileNameWithoutExtension($f.Name))
            }
            return
        }

        if ($fromPipeline) { return }

        $bucketPath = Get-BucketPath -Name $bucketName -Path $Path
        if (-not [System.IO.Directory]::Exists($bucketPath)) {
            Write-Verbose "Bucket '$Bucket' not found at '$bucketPath'"
            return
        }

        if ($allProcessed) { return }
        $allProcessed = $true

        $di = [System.IO.DirectoryInfo]::new($bucketPath)
        $allFiles = if ($Recurse) { $gv = [System.Collections.Generic.HashSet[string]]::new(); _GatherFiles -Dir $bucketPath -CurrentDepth 1 -MaxDepth $Depth -Visited $gv } else { @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat")) }

        if ($allFiles.Count -eq 0) { Write-Verbose "Bucket '$Bucket' is already empty"; return }

        $bucketSize = ($allFiles | Measure-Object -Property Length -Sum).Sum
        $sizeStr = if ($bucketSize) { "$([math]::Round($bucketSize / 1KB, 2)) KB" } else { "0 KB" }

        if ($WhatIfPreference) {
            Write-Host ""
            Write-Host "  What if: Remove all " -NoNewline -ForegroundColor $script:CMuted
            Write-Host $allFiles.Count -NoNewline -ForegroundColor $script:CNum
            Write-Host " object(s) from " -NoNewline -ForegroundColor $script:CMuted
            Write-Host $Bucket -NoNewline -ForegroundColor $script:CPath
            $recurseNote = if ($Recurse) { " (recursive, depth ${Depth})" } else { "" }
            Write-Host "$recurseNote ($sizeStr)" -ForegroundColor $script:CMuted
            Write-Host ""
            return
        }

        $target = "$($allFiles.Count) object(s) from bucket '$Bucket'"
        if ($PSCmdlet.ShouldProcess($target, "Remove-BucketObject")) {
            $allFiles | ForEach-Object { [System.IO.File]::Delete($_.FullName) }
            if ($Recurse) {
                $emptyDirKeys = [System.Collections.ArrayList]::new()
                $edVisited = [System.Collections.Generic.HashSet[string]]::new()
                function _EnumDirs { param([string]$D, [int]$CD, [System.Collections.Generic.HashSet[string]]$EDVisited)
                    $null = $emptyDirKeys.Add($D)
                    if ($CD -lt $Depth) {
                        foreach ($s in [System.IO.DirectoryInfo]::new($D).GetDirectories()) {
                            if ($s.Name -eq '.buckets') { continue }
                            $sResolved = [System.IO.Path]::GetFullPath($(if ($null -ne $s.LinkTarget) { $s.LinkTarget } else { $s.FullName }))
                            if ($EDVisited.Contains($sResolved)) { continue }
                            $null = $EDVisited.Add($sResolved)
                            _EnumDirs -D $s.FullName -CD ($CD + 1) -EDVisited $EDVisited
                        }
                    }
                }
                _EnumDirs -D $bucketPath -CD 1 -EDVisited $edVisited
                $emptyDirKeys | Sort-Object Length -Descending | ForEach-Object {
                    $d = [System.IO.DirectoryInfo]::new($_)
                    $d.Refresh()
                    $remaining = @($d.GetFiles()) + @($d.GetDirectories() | Where-Object { $_.Name -ne '.buckets' })
                    if ($remaining.Count -eq 0) { try { $d.Delete() } catch {} }
                }
            } else {
                foreach ($d in $di.GetDirectories()) {
                    if ($d.Name -eq ".buckets") { continue }
                    $remaining = @($d.GetFiles()) + @($d.GetDirectories())
                    if ($remaining.Count -eq 0) { [System.IO.Directory]::Delete($d.FullName) }
                }
            }
        }

        if ($PassThru) {
            foreach ($f in $allFiles) {
                $relPath = $f.FullName.Substring($bucketPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
                $keyOnly = [System.IO.Path]::ChangeExtension($relPath, $null).TrimEnd('.')
                [PSCustomObject]@{ Bucket = $Bucket; Key = $keyOnly }
            }
        }
        elseif (-not $WhatIfPreference -and -not $Quiet) {
            Write-Host "$Bucket" -NoNewline -ForegroundColor $script:CPath
            Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
            $objLabel = if ($allFiles.Count -eq 1) { "1 object" } else { "$($allFiles.Count) objects" }
            Write-Host $objLabel -NoNewline -ForegroundColor $script:CNum
            Write-Host " removed" -ForegroundColor $script:CMuted
        }
    }

    end {
        if ($removedCount -gt 0 -and -not $Quiet -and -not $WhatIfPreference) {
            Write-Host "$lastBucket" -NoNewline -ForegroundColor $script:CPath
            Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
            $objLabel = if ($removedCount -eq 1) { "1 object" } else { "$removedCount objects" }
            Write-Host $objLabel -NoNewline -ForegroundColor $script:CNum
            Write-Host " removed" -ForegroundColor $script:CMuted
        }
    }
}
