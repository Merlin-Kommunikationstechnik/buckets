function New-BucketObject {
    <#
    .SYNOPSIS
    Saves a PSObject to a bucket. Creates the bucket if it doesn't exist.
    .DESCRIPTION
    Serializes one or more PowerShell objects and stores them in a bucket directory.
    Arrays are stored as individual files. By default objects are serialized to JSON
    format for human readability and interoperability. Use -AsBinary for .NET type
    preservation via PSSerializer. JSON depth is auto-incremented up to 100 to avoid
    truncation. If JSON still cannot faithfully represent the object, it falls back
    to binary format and emits a warning.
    .PARAMETER InputObject
    The object(s) to store. Accepts pipeline input. Arrays are stored as individual files.
    .PARAMETER Bucket
    Name of the bucket to save to. Creates the bucket if it doesn't exist. Default: "default".
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Key
    Literal filename (without extension).
    .PARAMETER KeyProperty
    Property name whose value becomes the filename. Special characters (/, :, *, ?, ", <, >, |, [, ]) are sanitized to underscores.
    .PARAMETER Depth
    Maximum depth for JSON serialization. Default: 20.
    .PARAMETER BinaryDepth
    Maximum depth for binary (PSSerializer) serialization. Default: 5.
    .PARAMETER AsTimestamp
    Use a timestamp-based filename (yyyyMMddHHmmssfff_index) instead of a GUID. Ignored if -Key or -KeyProperty is also specified.
    .PARAMETER AsBinary
    Store objects as binary (.dat) instead of JSON (.json). Use for full .NET type preservation.
    .PARAMETER Compress
    Enable GZip compression for binary files to reduce disk usage. Only effective with -AsBinary.
    .PARAMETER Quiet
    Suppress all output. No progress indicator, no summary.
    .PARAMETER Overwrite
    Overwrite existing objects with the same key. Default: $false.
    .PARAMETER AutoIndex
    When duplicate keys occur within the batch, append an incrementing index instead of skipping.
    First duplicate gets _1, second gets _2, etc. Compatible with -Overwrite. No effect on
    GUID or timestamp-based keys (already unique).
    .PARAMETER PassThru
    Emit a metadata object with details of the operation (StoredKeys, ExistingKeys, SanitizedKeys, OverwrittenKeys, counts, format).
    .OUTPUTS
    By default, a progress indicator and summary are shown.
    Use -PassThru to also get a metadata object. Use -Quiet for silent operation.
    .EXAMPLE
    New-BucketObject -Bucket users -InputObject $users -KeyProperty Name
    .EXAMPLE
    New-BucketObject -Bucket config -InputObject $config -Key "app-settings"
    .EXAMPLE
    New-BucketObject -Bucket users -InputObject $user -KeyProperty Name -AsBinary
    .EXAMPLE
    New-BucketObject -Bucket logs -InputObject $events -KeyProperty Level -AutoIndex
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][PSObject]$InputObject,
        [string]$Bucket = "default",
        [string]$Path,
        [string]$Key,
        [string]$KeyProperty,
        [ValidateRange(1, 100)][int]$Depth = 20,
        [ValidateRange(1, 100)][int]$BinaryDepth = 5,
        [switch]$AsTimestamp,
        [switch]$AsBinary,
        [switch]$Compress,
        [switch]$Overwrite,
        [switch]$AutoIndex,
        [switch]$Quiet,
        [switch]$PassThru,
        [object]$Funnel
    )

    begin {
        $bucketPath = Ensure-BucketExists -Name $Bucket -Path $Path
        $extension = if ($AsBinary) { ".dat" } else { ".json" }
        $savedCount = 0; $filteredCount = 0; $missingKeyCount = 0; $existingKeyCount = 0; $fallbackCount = 0; $formatFallbackCount = 0; $failedCount = 0
        $overwrittenCount = 0; $sanitizedCount = 0; $indexedCount = 0; $expandedCount = 0
        $storedKeys = [System.Collections.ArrayList]::new()
        $existingKeyKeys = [System.Collections.ArrayList]::new()
        $sanitizedKeys = [System.Collections.ArrayList]::new()
        $overwrittenKeys = [System.Collections.ArrayList]::new()
        $seenKeys = @{}
        $useVerbose = $VerbosePreference -eq 'Continue'
        $useQuiet = $Quiet.IsPresent
        $showProgress = -not $useVerbose -and -not $useQuiet
        $pipeline = [System.Collections.ArrayList]::new()

        $funnelDef = Resolve-Funnel $Funnel

        if ($AsTimestamp -and (-not [string]::IsNullOrWhiteSpace($Key) -or -not [string]::IsNullOrWhiteSpace($KeyProperty))) {
            Write-Verbose "Both -Key/-KeyProperty and -AsTimestamp specified. -Key/-KeyProperty takes precedence, -AsTimestamp ignored."
        }
    }

    process {
        if ($null -eq $InputObject) { return }

        $isCollection = $InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string] -and $InputObject -isnot [hashtable] -and $InputObject -isnot [System.Collections.IDictionary]

        if ($isCollection) {
            $totalForItems = $InputObject.Count
            $index = 0
            foreach ($raw in $InputObject) {
                $item = $raw
                if ($funnelDef) {
                    $matchesAppliesTo = -not $funnelDef.ContainsKey('AppliesTo') -or ($null -ne ($item | Where-Object $funnelDef.AppliesTo))
                    if ($matchesAppliesTo) {
                        $funnelItems = @($item | ForEach-Object $funnelDef.Transform) | Where-Object { $_ -ne $null }
                        if ($funnelItems.Count -eq 0) { $filteredCount++; $index++; continue }
                        $subIdx = 0
                        $expansionKeys = @{}
                        foreach ($subItem in $funnelItems) {
                            $subIdx++
                            $item = $subItem
                            $itemFilename = Get-BucketFilename -Item $item -Key $Key -KeyProperty $KeyProperty -AsTimestamp:$AsTimestamp.IsPresent -Index ($index + $subIdx - 1) -Extension $extension
                            if ($null -eq $itemFilename) { $missingKeyCount++; continue }
                            $keyName = if ($itemFilename.OriginalKey) { $itemFilename.OriginalKey } else { [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename) }
                            if ($funnelItems.Count -gt 1) {
                                $baseSafeKey = [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename)
                                $baseOrigKey = $keyName
                                if ($expansionKeys.ContainsKey($baseSafeKey)) {
                                    $idx = 1
                                    while ($true) {
                                        $candidateKey = "${baseSafeKey}_${idx}"
                                        if ($expansionKeys.ContainsKey($candidateKey)) { $idx++; continue }
                                        break
                                    }
                                    $safeKey = "${baseSafeKey}_${idx}"
                                    $keyName = "${baseOrigKey}_${idx}"
                                    $itemFilename = [PSCustomObject]@{ Filename = "${safeKey}${extension}"; Sanitized = $itemFilename.Sanitized; OriginalKey = $keyName }
                                }
                                $expansionKeys[[System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename)] = $true
                            }
                            if ($subIdx -gt 1) { $expandedCount++ }
                            if ($AutoIndex) {
                                $baseSafeKey = [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename)
                                $baseOrigKey = $keyName
                                $inBatchCollision = $seenKeys.ContainsKey($baseSafeKey)
                                $onDiskCollision = -not $Overwrite -and ([System.IO.File]::Exists((Join-Path $bucketPath "${baseSafeKey}.json")) -or [System.IO.File]::Exists((Join-Path $bucketPath "${baseSafeKey}.dat")))
                                if ($inBatchCollision -or $onDiskCollision) {
                                    $idx = 1
                                    while ($true) {
                                        $candidateKey = "${baseSafeKey}_${idx}"
                                        if ($seenKeys.ContainsKey($candidateKey)) { $idx++; continue }
                                        if (-not $Overwrite -and ([System.IO.File]::Exists((Join-Path $bucketPath "${candidateKey}.json")) -or [System.IO.File]::Exists((Join-Path $bucketPath "${candidateKey}.dat")))) { $idx++; continue }
                                        break
                                    }
                                    $safeKey = "${baseSafeKey}_${idx}"
                                    $keyName = "${baseOrigKey}_${idx}"
                                    $itemFilename = [PSCustomObject]@{ Filename = "${safeKey}${extension}"; Sanitized = $itemFilename.Sanitized; OriginalKey = $keyName }
                                    $indexedCount++
                                    $seenKeys[$safeKey] = $true
                                } else {
                                    $seenKeys[$baseSafeKey] = $true
                                }
                            }
                            if ($itemFilename.Sanitized) { $sanitizedCount++; $null = $sanitizedKeys.Add([PSCustomObject]@{ Original = $itemFilename.OriginalKey; Sanitized = [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename) }) }
                            $itemFilePath = Join-Path $bucketPath $itemFilename.Filename
                            $writeResult = Save-BucketFile -Path $itemFilePath -Item $item -Extension $extension -AsBinary:$AsBinary.IsPresent -Compress:$Compress.IsPresent -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite.IsPresent -BucketPath $bucketPath -Bucket $Bucket
                            if ($writeResult.Success) {
                                $savedCount++
                                $null = $storedKeys.Add($keyName)
                                if ($writeResult.Overwritten) { $overwrittenCount++; $null = $overwrittenKeys.Add($keyName) }
                                if ($showProgress -and $totalForItems -gt 50) {
                                    $percent = if ($totalForItems -gt 0) { [math]::Round(($savedCount / $totalForItems) * 100) } else { 0 }
                                    Write-Progress -Activity "Saving to '$Bucket'" -Status "$savedCount object(s) saved" -PercentComplete $percent -CurrentOperation ([System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename))
                                }
                            }
                            elseif ($writeResult.Skipped) { $existingKeyCount++; $null = $existingKeyKeys.Add($keyName) }
                            else { $failedCount++ }
                            if ($writeResult.Fallback) { $fallbackCount++ }
                            if ($writeResult.FormatFallback) { $formatFallbackCount++ }
                        }
                        $index += $subIdx - 1
                        continue
                    }
                }
                $itemFilename = Get-BucketFilename -Item $item -Key $Key -KeyProperty $KeyProperty -AsTimestamp:$AsTimestamp.IsPresent -Index $index -Extension $extension
                if ($null -eq $itemFilename) { $missingKeyCount++; $index++; continue }
                $keyName = if ($itemFilename.OriginalKey) { $itemFilename.OriginalKey } else { [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename) }
                if ($AutoIndex) {
                    $baseSafeKey = [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename)
                    $baseOrigKey = $keyName
                    $inBatchCollision = $seenKeys.ContainsKey($baseSafeKey)
                    $onDiskCollision = -not $Overwrite -and ([System.IO.File]::Exists((Join-Path $bucketPath "${baseSafeKey}.json")) -or [System.IO.File]::Exists((Join-Path $bucketPath "${baseSafeKey}.dat")))
                    if ($inBatchCollision -or $onDiskCollision) {
                        $idx = 1
                        while ($true) {
                            $candidateKey = "${baseSafeKey}_${idx}"
                            if ($seenKeys.ContainsKey($candidateKey)) { $idx++; continue }
                            if (-not $Overwrite -and ([System.IO.File]::Exists((Join-Path $bucketPath "${candidateKey}.json")) -or [System.IO.File]::Exists((Join-Path $bucketPath "${candidateKey}.dat")))) { $idx++; continue }
                            break
                        }
                        $safeKey = "${baseSafeKey}_${idx}"
                        $keyName = "${baseOrigKey}_${idx}"
                        $itemFilename = [PSCustomObject]@{ Filename = "${safeKey}${extension}"; Sanitized = $itemFilename.Sanitized; OriginalKey = $keyName }
                        $indexedCount++
                        $seenKeys[$safeKey] = $true
                    } else {
                        $seenKeys[$baseSafeKey] = $true
                    }
                }
                if ($itemFilename.Sanitized) { $sanitizedCount++; $null = $sanitizedKeys.Add([PSCustomObject]@{ Original = $itemFilename.OriginalKey; Sanitized = [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename) }) }
                $itemFilePath = Join-Path $bucketPath $itemFilename.Filename
                $writeResult = Save-BucketFile -Path $itemFilePath -Item $item -Extension $extension -AsBinary:$AsBinary.IsPresent -Compress:$Compress.IsPresent -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite.IsPresent -BucketPath $bucketPath -Bucket $Bucket
                if ($writeResult.Success) {
                    $savedCount++
                    $null = $storedKeys.Add($keyName)
                    if ($writeResult.Overwritten) { $overwrittenCount++; $null = $overwrittenKeys.Add($keyName) }
                    if ($showProgress -and $totalForItems -gt 50) {
                        $percent = if ($totalForItems -gt 0) { [math]::Round(($savedCount / $totalForItems) * 100) } else { 0 }
                        Write-Progress -Activity "Saving to '$Bucket'" -Status "$savedCount object(s) saved" -PercentComplete $percent -CurrentOperation ([System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename))
                    }
                }
                elseif ($writeResult.Skipped) { $existingKeyCount++; $null = $existingKeyKeys.Add($keyName) }
                else { $failedCount++ }
                if ($writeResult.Fallback) { $fallbackCount++ }
                if ($writeResult.FormatFallback) { $formatFallbackCount++ }
                $index++
            }
        }
        else {
            $null = $pipeline.Add($InputObject)
        }
    }

    end {
        if ($pipeline.Count -gt 0) {
            $totalForItems = $pipeline.Count
            $index = 0
            foreach ($raw in $pipeline) {
                $item = $raw
                if ($funnelDef) {
                    $matchesAppliesTo = -not $funnelDef.ContainsKey('AppliesTo') -or ($null -ne ($item | Where-Object $funnelDef.AppliesTo))
                    if ($matchesAppliesTo) {
                        $funnelItems = @($item | ForEach-Object $funnelDef.Transform) | Where-Object { $_ -ne $null }
                        if ($funnelItems.Count -eq 0) { $filteredCount++; $index++; continue }
                        $subIdx = 0
                        $expansionKeys = @{}
                        foreach ($subItem in $funnelItems) {
                            $subIdx++
                            $item = $subItem
                            $itemFilename = Get-BucketFilename -Item $item -Key $Key -KeyProperty $KeyProperty -AsTimestamp:$AsTimestamp.IsPresent -Index ($index + $subIdx - 1) -Extension $extension
                            if ($null -eq $itemFilename) { $missingKeyCount++; continue }
                            $keyName = if ($itemFilename.OriginalKey) { $itemFilename.OriginalKey } else { [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename) }
                            if ($funnelItems.Count -gt 1) {
                                $baseSafeKey = [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename)
                                $baseOrigKey = $keyName
                                if ($expansionKeys.ContainsKey($baseSafeKey)) {
                                    $idx = 1
                                    while ($true) {
                                        $candidateKey = "${baseSafeKey}_${idx}"
                                        if ($expansionKeys.ContainsKey($candidateKey)) { $idx++; continue }
                                        break
                                    }
                                    $safeKey = "${baseSafeKey}_${idx}"
                                    $keyName = "${baseOrigKey}_${idx}"
                                    $itemFilename = [PSCustomObject]@{ Filename = "${safeKey}${extension}"; Sanitized = $itemFilename.Sanitized; OriginalKey = $keyName }
                                }
                                $expansionKeys[[System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename)] = $true
                            }
                            if ($subIdx -gt 1) { $expandedCount++ }
                            if ($AutoIndex) {
                                $baseSafeKey = [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename)
                                $baseOrigKey = $keyName
                                $inBatchCollision = $seenKeys.ContainsKey($baseSafeKey)
                                $onDiskCollision = -not $Overwrite -and ([System.IO.File]::Exists((Join-Path $bucketPath "${baseSafeKey}.json")) -or [System.IO.File]::Exists((Join-Path $bucketPath "${baseSafeKey}.dat")))
                                if ($inBatchCollision -or $onDiskCollision) {
                                    $idx = 1
                                    while ($true) {
                                        $candidateKey = "${baseSafeKey}_${idx}"
                                        if ($seenKeys.ContainsKey($candidateKey)) { $idx++; continue }
                                        if (-not $Overwrite -and ([System.IO.File]::Exists((Join-Path $bucketPath "${candidateKey}.json")) -or [System.IO.File]::Exists((Join-Path $bucketPath "${candidateKey}.dat")))) { $idx++; continue }
                                        break
                                    }
                                    $safeKey = "${baseSafeKey}_${idx}"
                                    $keyName = "${baseOrigKey}_${idx}"
                                    $itemFilename = [PSCustomObject]@{ Filename = "${safeKey}${extension}"; Sanitized = $itemFilename.Sanitized; OriginalKey = $keyName }
                                    $indexedCount++
                                    $seenKeys[$safeKey] = $true
                                } else {
                                    $seenKeys[$baseSafeKey] = $true
                                }
                            }
                            if ($itemFilename.Sanitized) { $sanitizedCount++; $null = $sanitizedKeys.Add([PSCustomObject]@{ Original = $itemFilename.OriginalKey; Sanitized = [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename) }) }
                            $itemFilePath = Join-Path $bucketPath $itemFilename.Filename
                            $writeResult = Save-BucketFile -Path $itemFilePath -Item $item -Extension $extension -AsBinary:$AsBinary.IsPresent -Compress:$Compress.IsPresent -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite.IsPresent -BucketPath $bucketPath -Bucket $Bucket
                            if ($writeResult.Success) {
                                $savedCount++
                                $null = $storedKeys.Add($keyName)
                                if ($writeResult.Overwritten) { $overwrittenCount++; $null = $overwrittenKeys.Add($keyName) }
                                if ($showProgress -and $totalForItems -gt 50) {
                                    $percent = if ($totalForItems -gt 0) { [math]::Round(($savedCount / $totalForItems) * 100) } else { 0 }
                                    Write-Progress -Activity "Saving to '$Bucket'" -Status "$savedCount object(s) saved" -PercentComplete $percent -CurrentOperation ([System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename))
                                }
                            }
                            elseif ($writeResult.Skipped) { $existingKeyCount++; $null = $existingKeyKeys.Add($keyName) }
                            else { $failedCount++ }
                            if ($writeResult.Fallback) { $fallbackCount++ }
                            if ($writeResult.FormatFallback) { $formatFallbackCount++ }
                        }
                        $index += $subIdx - 1
                        continue
                    }
                }
                $itemFilename = Get-BucketFilename -Item $item -Key $Key -KeyProperty $KeyProperty -AsTimestamp:$AsTimestamp.IsPresent -Index $index -Extension $extension
                if ($null -eq $itemFilename) { $missingKeyCount++; $index++; continue }
                $keyName = if ($itemFilename.OriginalKey) { $itemFilename.OriginalKey } else { [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename) }
                if ($AutoIndex) {
                    $baseSafeKey = [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename)
                    $baseOrigKey = $keyName
                    $inBatchCollision = $seenKeys.ContainsKey($baseSafeKey)
                    $onDiskCollision = -not $Overwrite -and ([System.IO.File]::Exists((Join-Path $bucketPath "${baseSafeKey}.json")) -or [System.IO.File]::Exists((Join-Path $bucketPath "${baseSafeKey}.dat")))
                    if ($inBatchCollision -or $onDiskCollision) {
                        $idx = 1
                        while ($true) {
                            $candidateKey = "${baseSafeKey}_${idx}"
                            if ($seenKeys.ContainsKey($candidateKey)) { $idx++; continue }
                            if (-not $Overwrite -and ([System.IO.File]::Exists((Join-Path $bucketPath "${candidateKey}.json")) -or [System.IO.File]::Exists((Join-Path $bucketPath "${candidateKey}.dat")))) { $idx++; continue }
                            break
                        }
                        $safeKey = "${baseSafeKey}_${idx}"
                        $keyName = "${baseOrigKey}_${idx}"
                        $itemFilename = [PSCustomObject]@{ Filename = "${safeKey}${extension}"; Sanitized = $itemFilename.Sanitized; OriginalKey = $keyName }
                        $indexedCount++
                        $seenKeys[$safeKey] = $true
                    } else {
                        $seenKeys[$baseSafeKey] = $true
                    }
                }
                if ($itemFilename.Sanitized) { $sanitizedCount++; $null = $sanitizedKeys.Add([PSCustomObject]@{ Original = $itemFilename.OriginalKey; Sanitized = [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename) }) }
                $itemFilePath = Join-Path $bucketPath $itemFilename.Filename
                $writeResult = Save-BucketFile -Path $itemFilePath -Item $item -Extension $extension -AsBinary:$AsBinary.IsPresent -Compress:$Compress.IsPresent -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite.IsPresent -BucketPath $bucketPath -Bucket $Bucket
                if ($writeResult.Success) {
                    $savedCount++
                    $null = $storedKeys.Add($keyName)
                    if ($writeResult.Overwritten) { $overwrittenCount++; $null = $overwrittenKeys.Add($keyName) }
                    if ($showProgress -and $totalForItems -gt 50) {
                        $percent = if ($totalForItems -gt 0) { [math]::Round(($savedCount / $totalForItems) * 100) } else { 0 }
                        Write-Progress -Activity "Saving to '$Bucket'" -Status "$savedCount object(s) saved" -PercentComplete $percent -CurrentOperation ([System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename))
                    }
                }
                elseif ($writeResult.Skipped) { $existingKeyCount++; $null = $existingKeyKeys.Add($keyName) }
                else { $failedCount++ }
                if ($writeResult.Fallback) { $fallbackCount++ }
                if ($writeResult.FormatFallback) { $formatFallbackCount++ }
                $index++
            }
        }

        if ($showProgress -or $useVerbose) { Write-Progress -Activity "Saving to '$Bucket'" -Completed }
        if (-not $useQuiet) {
            $compressStr = if ($Compress) { " · compressed" } else { "" }
            Write-Host "$Bucket" -NoNewline -ForegroundColor $script:CPath
            Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
            Write-Host $savedCount -NoNewline -ForegroundColor $script:CNum
            Write-Host " objects" -NoNewline -ForegroundColor $script:CMuted
            if ($compressStr) { Write-Host $compressStr -NoNewline -ForegroundColor $script:CMuted }
            Write-Host ""
            if ($overwrittenCount -gt 0) {
                Write-Host "  " -NoNewline
                Write-Host $overwrittenCount -NoNewline -ForegroundColor $script:CNum
                Write-Host " overwritten" -ForegroundColor $script:CSkip
            }
            if ($expandedCount -gt 0) {
                Write-Host "  " -NoNewline
                Write-Host $expandedCount -NoNewline -ForegroundColor $script:CNum
                Write-Host " expanded (multi-emit funnel)" -ForegroundColor $script:CSkip
            }
            if ($indexedCount -gt 0) {
                Write-Host "  " -NoNewline
                Write-Host $indexedCount -NoNewline -ForegroundColor $script:CNum
                Write-Host " indexed (AutoIndex)" -ForegroundColor $script:CSkip
            }
            if ($sanitizedCount -gt 0) {
                Write-Host "  " -NoNewline
                Write-Host $sanitizedCount -NoNewline -ForegroundColor $script:CNum
                Write-Host " key name(s) sanitized" -ForegroundColor $script:CSkip
            }
            if ($missingKeyCount -gt 0) {
                Write-Host "  " -NoNewline
                Write-Host $missingKeyCount -NoNewline -ForegroundColor $script:CNum
                Write-Host " skipped (missing key)" -ForegroundColor $script:CSkip
            }
            if ($existingKeyCount -gt 0) {
                Write-Host "  " -NoNewline
                Write-Host $existingKeyCount -NoNewline -ForegroundColor $script:CNum
                $skipDisplay = if ($existingKeyKeys.Count -le 5) { $existingKeyKeys -join ", " } else { ($existingKeyKeys | Select-Object -First 5) -join ", " + " ... +$($existingKeyKeys.Count - 5) more" }
                Write-Host " skipped (existing key: $skipDisplay)" -ForegroundColor $script:CSkip
            }
            if ($filteredCount -gt 0) {
                Write-Host "  " -NoNewline
                Write-Host $filteredCount -NoNewline -ForegroundColor $script:CNum
                Write-Host " skipped (filtered by funnel)" -ForegroundColor $script:CSkip
            }
            if ($fallbackCount -gt 0) {
                Write-Host "  " -NoNewline
                Write-Host $fallbackCount -NoNewline -ForegroundColor $script:CNum
                Write-Host " depth fallback" -ForegroundColor $script:CSkip
            }
            if ($formatFallbackCount -gt 0) {
                Write-Warning "$formatFallbackCount object(s) too complex for JSON, saved as binary instead"
            }
            if ($failedCount -gt 0) {
                Write-Host "  " -NoNewline
                Write-Host $failedCount -NoNewline -ForegroundColor $script:CNum
                Write-Host " failed to serialize" -ForegroundColor $script:CError
            }
        }
        if ($PassThru) {
            Write-Output ([PSCustomObject]@{
                Bucket      = $Bucket
                Saved       = $savedCount
                Skipped     = $missingKeyCount + $existingKeyCount + $filteredCount
                Overwritten = $overwrittenCount
                Indexed     = $indexedCount
                Expanded    = $expandedCount
                Sanitized   = $sanitizedCount
                Failed      = $failedCount
                Total       = $savedCount + $missingKeyCount + $existingKeyCount + $filteredCount + $failedCount
                Format      = if ($AsBinary) { "Binary" } else { "JSON" }
                Compressed  = $Compress.IsPresent
                StoredKeys   = [string[]]$storedKeys
                ExistingKeys = [string[]]$existingKeyKeys
                SanitizedKeys = [PSCustomObject[]]$sanitizedKeys
                OverwrittenKeys = [string[]]$overwrittenKeys
            })
        }
    }
}