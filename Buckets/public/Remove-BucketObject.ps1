function Remove-BucketObject {
    <#
    .SYNOPSIS
    Removes an object from a bucket.
    .DESCRIPTION
    Deletes a specific object file from a bucket directory. Use -Key to remove a single
    object, -All to clear the entire bucket, or -Match/-Filter for bulk deletion.
    .PARAMETER InputObject
    The object to remove. Accepts pipeline input. If it has _BucketName and _BucketKey metadata,
    bucket and key are auto-resolved. Otherwise -Bucket and -Key are required.
    .PARAMETER Bucket
    Name of the bucket containing the object(s) to remove.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Key
    Object key to remove. Looks for both JSON and binary files. Case-insensitive.
    .PARAMETER All
    Remove all objects from the bucket.
    .PARAMETER Match
    Hashtable of property-value pairs for bulk deletion. All pairs must match. Supports $null values.
    .PARAMETER Filter
    ScriptBlock for custom bulk deletion. Use $_ to reference object properties.
    .PARAMETER Recurse
    Recurse into nested sub-buckets. Without this switch, only acts on the specified bucket directory.
    Only applies to -All and -Match/-Filter. When used with -Key, searches for the key across all sub-buckets.
    .PARAMETER Depth
    Maximum nesting depth when recursing. Default: unlimited.
    .PARAMETER PassThru
    Return metadata for removed objects.
    .PARAMETER Quiet
    Suppress progress output.
    .EXAMPLE
    Remove-BucketObject -Bucket logs -Key "log-003"
    .EXAMPLE
    Remove-BucketObject -Bucket temp -All -PassThru
    .EXAMPLE
    Remove-BucketObject -Bucket users -Match @{ Active = $false } -PassThru
    .EXAMPLE
    Remove-BucketObject -Bucket orders -Filter { $_.Status -eq "cancelled" }
    .EXAMPLE
    Remove-BucketObject -Bucket users -Key "Charlie" -WhatIf
    .EXAMPLE
    Get-BucketObject -Bucket users -Match @{Role="guest"} | Remove-BucketObject
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByKey')]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)][PSObject]$InputObject,
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)][Alias('_BucketName')][string]$Bucket,
        [string]$Path,
        [Parameter(ParameterSetName = 'ByKey', ValueFromPipelineByPropertyName = $true)][Alias('_BucketKey')][string]$Key,
        [Parameter(ParameterSetName = 'All')][switch]$All,
        [Parameter(ParameterSetName = 'ByFilter')][hashtable]$Match,
        [Parameter(ParameterSetName = 'ByFilter')][scriptblock]$Filter,
        [switch]$Recurse,
        [int]$Depth = [int]::MaxValue,
        [switch]$PassThru,
        [switch]$Quiet
    )

    begin {
        $removedCount = 0; $lastBucket = ''; $removedKeys = [System.Collections.ArrayList]::new()
        $allProcessed = $false; $filterProcessed = $false

        if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
        $Path = Resolve-SafePath -Path $Path

        function _GatherFiles {
            param([string]$Dir, [int]$CurrentDepth, [int]$MaxDepth, [string]$Key)
            $files = @()
            $di = [System.IO.DirectoryInfo]::new($Dir)
            $allFiles = @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))
            if ($Key) {
                $target = $Key.ToLowerInvariant()
                $allFiles = @($allFiles | Where-Object {
                    $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name).ToLowerInvariant()
                    $base -eq $target -or $base.StartsWith("${target}_") -or $base.StartsWith("${target}.")
                })
            }
            $files += $allFiles
            if ($CurrentDepth -lt $MaxDepth) {
                foreach ($sub in $di.GetDirectories()) {
                    if ($sub.Name -eq '.buckets') { continue }
                    $files += _GatherFiles -Dir $sub.FullName -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -Key $Key
                }
            }
            $files
        }
    }

    process {
        if ($null -ne $InputObject) {
            $hasMeta = $InputObject.PSObject.Properties['_BucketName'] -and $InputObject.PSObject.Properties['_BucketKey']
            if ($hasMeta) {
                if ([string]::IsNullOrWhiteSpace($Bucket)) { $Bucket = $InputObject._BucketName }
                if ([string]::IsNullOrWhiteSpace($Key)) { $Key = $InputObject._BucketKey }
            }
        }

        $bucketPath = Get-BucketPath -Name $Bucket -Path $Path

        if (-not [System.IO.Directory]::Exists($bucketPath)) {
            Write-Verbose "Bucket '$Bucket' not found at '$bucketPath'"
            return
        }

        if ($All) {
            if ($allProcessed) { return }
            $allProcessed = $true

            $di = [System.IO.DirectoryInfo]::new($bucketPath)
            $allFiles = if ($Recurse) { _GatherFiles -Dir $bucketPath -CurrentDepth 0 -MaxDepth $Depth } else { @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat")) }

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
                    function _EnumDirs { param([string]$D, [int]$CD)
                        $null = $emptyDirKeys.Add($D)
                        if ($CD -lt $Depth) {
                            foreach ($s in [System.IO.DirectoryInfo]::new($D).GetDirectories()) {
                                if ($s.Name -ne '.buckets') { _EnumDirs -D $s.FullName -CD ($CD + 1) }
                            }
                        }
                    }
                    _EnumDirs -D $bucketPath -CD 0
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
            return
        }

        if (-not [string]::IsNullOrWhiteSpace($Key)) {
            $matchedFiles = if ($Recurse) { _GatherFiles -Dir $bucketPath -CurrentDepth 0 -MaxDepth $Depth -Key $Key } else { @() }
            if (-not $Recurse) {
                $file = Find-ObjectFile -BucketPath $bucketPath -Key $Key
                if ($file) { $matchedFiles = @($file) }
            }
            if ($matchedFiles.Count -eq 0) {
                Write-Warning "Object with key '$Key' not found in bucket '$Bucket'"
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
                            if ($remaining.Count -eq 0) {
                                try { [System.IO.Directory]::Delete($parentDir) } catch {}
                            }
                        }
                        $removedCount++
                        $lastBucket = $Bucket
                        $null = $removedKeys.Add($fileKey)
                    }
                }
            }
            return
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByFilter') {
            if ($filterProcessed) { return }
            $filterProcessed = $true

            $di = [System.IO.DirectoryInfo]::new($bucketPath)
            $allFiles = if ($Recurse) { _GatherFiles -Dir $bucketPath -CurrentDepth 0 -MaxDepth $Depth } else { @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat")) }

            if ($allFiles.Count -eq 0) { Write-Verbose "Bucket '$Bucket' is already empty"; return }

            $matchedFiles = @()
            $matchedKeys = @()
            foreach ($file in $allFiles) {
                $obj = Read-BucketFile -File $file
                if ($null -eq $obj) { continue }
                if ($Match -and -not (Test-MatchFilter -Object $obj -Match $Match)) { continue }
                if ($Filter) {
                    if ($null -eq ($obj | Where-Object $Filter)) { continue }
                }
                $matchedFiles += $file
                $matchedKeys += [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            }

            if ($matchedFiles.Count -eq 0) { Write-Verbose "No objects matched the filter criteria in bucket '$Bucket'"; return }

            $matchSize = ($matchedFiles | Measure-Object -Property Length -Sum).Sum
            $sizeStr = if ($matchSize) { "$([math]::Round($matchSize / 1KB, 2)) KB" } else { "0 KB" }

            if ($WhatIfPreference) {
                Write-Host ""
                Write-Host "  What if: Remove " -NoNewline -ForegroundColor $script:CMuted
                Write-Host $matchedFiles.Count -NoNewline -ForegroundColor $script:CNum
                Write-Host " matching object(s) from " -NoNewline -ForegroundColor $script:CMuted
                Write-Host $Bucket -NoNewline -ForegroundColor $script:CPath
                $recurseNote = if ($Recurse) { " (recursive, depth ${Depth})" } else { "" }
                Write-Host "$recurseNote ($sizeStr)" -ForegroundColor $script:CMuted
                $showKeys = $matchedKeys | Select-Object -First 5
                foreach ($k in $showKeys) {
                    Write-Host "    $k" -ForegroundColor $script:CMuted
                }
                if ($matchedKeys.Count -gt 5) {
                    Write-Host "    ... and $($matchedKeys.Count - 5) more" -ForegroundColor $script:CMuted
                }
                Write-Host ""
                return
            }

            if (-not $Quiet) {
                Write-Host ""
                Write-Host "  Remove " -NoNewline -ForegroundColor $script:CMuted
                Write-Host $matchedFiles.Count -NoNewline -ForegroundColor $script:CNum
                Write-Host " matching object(s) from " -NoNewline -ForegroundColor $script:CMuted
                Write-Host $Bucket -NoNewline -ForegroundColor $script:CPath
                $recurseNote = if ($Recurse) { " (recursive, depth ${Depth})" } else { "" }
                Write-Host "$recurseNote ($sizeStr)" -ForegroundColor $script:CMuted
                $showKeys = $matchedKeys | Select-Object -First 5
                foreach ($k in $showKeys) {
                    Write-Host "    " -NoNewline
                    Write-Host $k -ForegroundColor $script:CNum
                }
                if ($matchedKeys.Count -gt 5) {
                    Write-Host "    ... and $($matchedKeys.Count - 5) more" -ForegroundColor $script:CMuted
                }
                Write-Host ""
            }

            $target = "$($matchedFiles.Count) matching object(s) from bucket '$Bucket'"
            if ($PSCmdlet.ShouldProcess($target, "Remove-BucketObject")) {
                foreach ($f in $matchedFiles) {
                    if ($PassThru) {
                        $relPath = $f.FullName.Substring($bucketPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
                        $keyOnly = [System.IO.Path]::ChangeExtension($relPath, $null).TrimEnd('.')
                        [PSCustomObject]@{ Bucket = $Bucket; Key = $keyOnly }
                    }
                    [System.IO.File]::Delete($f.FullName)
                }
                if (-not $PassThru -and -not $Quiet) {
                    Write-Host "$Bucket" -NoNewline -ForegroundColor $script:CPath
                    Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
                    $objLabel = if ($matchedFiles.Count -eq 1) { "1 object" } else { "$($matchedFiles.Count) objects" }
                    Write-Host $objLabel -NoNewline -ForegroundColor $script:CNum
                    Write-Host " removed (matched)" -ForegroundColor $script:CMuted
                }
            }
            elseif (-not $WhatIfPreference) { Write-Verbose "Would remove $($matchedFiles.Count) object(s) from bucket '$Bucket'" }
            return
        }

        throw "Specify either -Key, -All, or -Match/-Filter"
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
