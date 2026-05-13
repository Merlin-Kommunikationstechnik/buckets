function Remove-Bucket {
    <#
    .SYNOPSIS
    Removes one or more buckets and all their objects.
    .DESCRIPTION
    Deletes bucket directories and their contents. Supports exact names, multiple
    buckets, and wildcard patterns (including nested bucket paths like "projects/myapp").
    Only removes directories containing bucket objects (or empty directories).
    Skips buckets with other file types.

    By default, only removes files in the target bucket and leaves nested bucket
    directories intact. Use -Recurse to remove the target and all nested buckets.

    Uses standard -Confirm/-WhatIf support (SupportsShouldProcess).
    -Force skips the confirmation prompt entirely.
    .PARAMETER Bucket
    Bucket name(s) or wildcard patterns to remove. Supports glob-style wildcards (*, ?).
    For nested buckets, use path notation like "projects/myapp".
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Recurse
    Remove the target bucket and all nested buckets beneath it. Without this flag,
    nested bucket directories are preserved.
    .PARAMETER Force
    Skip confirmation prompt and remove immediately.
    .PARAMETER WhatIf
    Preview which buckets would be removed without actually deleting them.
    .PARAMETER Quiet
    Suppress progress output.
    .EXAMPLE
    Remove-Bucket -Bucket users
    .EXAMPLE
    Remove-Bucket -Bucket "projects/myapp"
    .EXAMPLE
    Remove-Bucket -Bucket "temp*" -Force
    .EXAMPLE
    Remove-Bucket -Bucket projects -Recurse
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)][string[]]$Bucket,
        [string]$Path,
        [switch]$Recurse,
        [switch]$Force,
        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

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

    $matched = Find-MatchingBuckets -Root $Path -Patterns $Bucket

    if ($matched.Count -eq 0) {
        Write-Warning "No buckets match the specified pattern(s)"
        return
    }

    $removable = @()
    $skippedBuckets = @()
    foreach ($m in $matched) {
        $resolvedRoot = Resolve-SafePath -Path $Path
        $resolvedBucket = Resolve-SafePath -Path $m.Path
        if (-not $resolvedBucket.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $skippedBuckets += [PSCustomObject]@{ Name = $m.Name; Reason = "path resolves outside root" }
            continue
        }

        $di = [System.IO.DirectoryInfo]::new($m.Path)
        $allFiles = @($di.GetFiles())
        $otherFiles = @($allFiles | Where-Object { $_.Extension -notin ".dat", ".json" })
        if ($otherFiles.Count -gt 0) {
            $skippedBuckets += [PSCustomObject]@{ Name = $m.Name; Reason = "contains $($otherFiles.Count) non-bucket file(s): $($otherFiles.Name -join ', ')" }
            continue
        }

        $nestedBuckets = @()
        foreach ($subDir in $di.GetDirectories()) {
            if ($subDir.Name -eq ".buckets") { continue }
            if ($subDir.GetFiles("*.dat").Length -gt 0 -or $subDir.GetFiles("*.json").Length -gt 0) {
                $nestedBuckets += $subDir.Name
            }
        }

        $stats = Get-BucketStats -Bucket $m.Name -Path $Path
        $hasNested = $nestedBuckets.Count -gt 0

        $removable += [PSCustomObject]@{
            Name = $m.Name
            Objects = if ($stats) { $stats.ObjectCount } else { 0 }
            Size = if ($stats) { $stats.TotalSize } else { "0 KB" }
            Path = $m.Path
            HasNestedBuckets = $hasNested
            NestedBucketNames = $nestedBuckets
        }
    }

    if ($removable.Count -eq 0 -and $skippedBuckets.Count -eq 0) { return }

    # When -Recurse, deduplicate: only keep buckets that aren't subdirectories of other matched buckets
    if ($Recurse -and $removable.Count -gt 1) {
        $sorted = @($removable | Sort-Object { $_.Path.Length })
        $topLevel = @()
        foreach ($r in $sorted) {
            $isChild = $false
            foreach ($existing in $topLevel) {
                if ($r.Path.StartsWith($existing.Path + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $isChild = $true
                    break
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

    if ($removable.Count -eq 0 -and $skippedBuckets.Count -eq 0) { return }

    # Pre-confirmation summary (unless -Force or -Quiet)
    if (-not $Force -and -not $Quiet -and $removable.Count -gt 0) {
        $preserved = @()
        foreach ($r in $removable) {
            if ($r.HasNestedBuckets -and -not $Recurse) {
                $preserved += @($r.NestedBucketNames)
            } else {
                $preserved += @()
            }
        }
        Write-RemovalSummary -Title "Remove $($removable.Count) bucket(s)?" `
            -Names $removable.Name -Counts $removable.Objects -Sizes $removable.Size -Nested $preserved
    }

    # Skipped buckets (always shown if any)
    if ($skippedBuckets.Count -gt 0 -and -not $Quiet) {
        foreach ($s in $skippedBuckets) {
            Write-Host "  " -NoNewline -ForegroundColor $script:CMuted
            Write-Host "$($s.Name)" -NoNewline -ForegroundColor $script:CPath
            Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
            Write-Host "$($s.Reason)" -ForegroundColor $script:CError
        }
    }

    $removedCount = 0
    # Sort deepest paths first so children are deleted before parents
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
            $shouldRemove = $PSCmdlet.ShouldProcess($target, "Remove-Bucket")
        }

        if ($shouldRemove) {
            if ($r.HasNestedBuckets -and -not $Recurse) {
                $finalDirs = @($finalDi.GetDirectories())
                foreach ($f in $finalFiles) { $f.Delete() }
                foreach ($d in $finalDirs) {
                    $hasBucketFiles = $d.GetFiles("*.dat").Length -gt 0 -or $d.GetFiles("*.json").Length -gt 0
                    if (-not $hasBucketFiles -and $d.GetDirectories().Length -eq 0) {
                        $d.Delete()
                    }
                }
                $remainingDirs = @($finalDi.GetDirectories())
                if ($remainingDirs.Count -eq 0 -and $finalDi.GetFiles().Length -eq 0) {
                    $finalDi.Delete()
                }
                $cacheKeys = @($script:BucketPathCache.Keys) | Where-Object { $_ -like "*|$($r.Name)" }
                foreach ($ck in $cacheKeys) { $script:BucketPathCache.Remove($ck) }
            }
            elseif ($Recurse) {
                [System.IO.Directory]::Delete($r.Path, $true)
                $cacheKeys = @($script:BucketPathCache.Keys) | Where-Object { $_ -like "*|$($r.Name)*" }
                foreach ($ck in $cacheKeys) { $script:BucketPathCache.Remove($ck) }
            }
            else {
                $finalDirs = @($finalDi.GetDirectories())
                if ($finalDirs.Count -gt 0) {
                    Write-Warning "Bucket '$($r.Name)' contains non-bucket subdirectories, aborting"
                    continue
                }
                [System.IO.Directory]::Delete($r.Path, $true)
                $cacheKeys = @($script:BucketPathCache.Keys) | Where-Object { $_ -like "*|$($r.Name)" }
                foreach ($ck in $cacheKeys) { $script:BucketPathCache.Remove($ck) }
            }

            $removedCount++
            if (-not $Quiet) {
                Write-Host "$($r.Name)" -NoNewline -ForegroundColor $script:CPath
                Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
                $objLabel = if ($r.Objects -eq 1) { "1 object" } else { "$($r.Objects) objects" }
                Write-Host $objLabel -NoNewline -ForegroundColor $script:CNum
                Write-Host " removed" -ForegroundColor $script:CMuted
            }
        }
    }

    if ($removedCount -gt 1 -and -not $Quiet) {
        Write-Host $removedCount -NoNewline -ForegroundColor $script:CNum
        Write-Host " buckets removed" -ForegroundColor $script:CMuted
    }
}