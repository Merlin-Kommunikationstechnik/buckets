function Set-BucketObject {
    <#
    .SYNOPSIS
    Updates an existing object in a bucket.
    .DESCRIPTION
    Automatically detects whether the pipeline input is a full object replacement or a partial update.

    If the piped object contains _BucketName and _BucketKey metadata (from Get-BucketObject),
    the entire object replaces the stored version. If the piped object lacks metadata, only
    its properties are merged into the existing object (partial update).

    Use -Property and -Value to set a single property without reading the object first.

    Preserves the storage format (JSON or binary) of the existing file. If JSON serialization
    fails on complex types, falls back to binary format.
    .PARAMETER InputObject
    The object to store. Accepts pipeline input. If it has _BucketName and _BucketKey metadata,
    bucket and key are auto-resolved. Otherwise -Bucket and -Key are required.
    .PARAMETER Bucket
    Name of the bucket containing the object. Auto-resolved from pipeline metadata if omitted.
    Required when piping partial updates.
    .PARAMETER Key
    Object key to update. Auto-resolved from pipeline metadata if omitted.
    Required when piping partial updates.
    .PARAMETER Property
    Name of the property to update. Requires -Value. When specified, reads the existing object,
    sets the property, and saves it back.
    .PARAMETER Value
    New value for the property specified by -Property.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Depth
    Maximum depth for JSON serialization. Default: 20.
    .PARAMETER BinaryDepth
    Maximum depth for binary (PSSerializer) serialization. Default: 5.
    .PARAMETER AsBinary
    Force binary (.dat) format for the updated file. Default is JSON (.json).
    .PARAMETER Compress
    Enable GZip compression for binary files. Only effective with -AsBinary.
    .PARAMETER Quiet
    Suppress all output. No summary.
    .EXAMPLE
    $user = Get-BucketObject -Bucket users -Key "Alice"
    $user.Role = "manager"
    $user | Set-BucketObject
    .EXAMPLE
    Set-BucketObject -InputObject @{ Role = "admin" } -Bucket users -Key Name
    .EXAMPLE
    Get-BucketObject -Bucket logs -Key "log-001" | ForEach-Object { $_.Level = "INFO"; $_ } | Set-BucketObject -Quiet
    .EXAMPLE
    Set-BucketObject -Bucket team -Key "Bob" -Property Score -Value 100
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Pipeline")]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = "Pipeline")]
        [PSObject]$InputObject,
        [Parameter(ValueFromPipelineByPropertyName = $true, ParameterSetName = "Pipeline")]
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "PropertyValue", ValueFromPipelineByPropertyName = $true)]
        [Alias("_BucketKey")]
        [string]$Key,
        [Parameter(ValueFromPipelineByPropertyName = $true, ParameterSetName = "Pipeline")]
        [Parameter(Position = 1, ParameterSetName = "PropertyValue", ValueFromPipelineByPropertyName = $true)]
        [Alias("_BucketName")]
        [string]$Bucket = 'default',
        [Parameter(Mandatory = $true, Position = 2, ParameterSetName = "PropertyValue")]
        [string]$Property,
        [Parameter(Mandatory = $true, Position = 3, ParameterSetName = "PropertyValue")]
        [PSObject]$Value,
        [string]$Path,
        [ValidateRange(1, 100)][int]$Depth = 20,
        [ValidateRange(1, 100)][int]$BinaryDepth = 5,
        [switch]$AsBinary,
        [switch]$Compress,
        [switch]$PassThru,
        [switch]$Quiet
    )

    begin {
        $bucketPath = $null; $savedCount = 0; $lastBucket = ''
        $useVerbose = $VerbosePreference -eq 'Continue'; $useQuiet = $Quiet.IsPresent
        $updatedKeys = [System.Collections.ArrayList]::new()
        $isPropertySet = $PSCmdlet.ParameterSetName -eq "PropertyValue"
        $isPatch = $false
    }

    process {
        if ($null -eq $bucketPath) {
            if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
            $Path = Resolve-SafePath -Path $Path
        }

        if ($isPropertySet) {
            if ([string]::IsNullOrWhiteSpace($Bucket) -or [string]::IsNullOrWhiteSpace($Key)) {
                throw "When using -Property and -Value, you must specify -Bucket and -Key."
            }
        }
        else {
            $isPatch = -not ($InputObject.PSObject.Properties['_BucketName'] -and $InputObject.PSObject.Properties['_BucketKey'])

            if ($isPatch) {
                if ([string]::IsNullOrWhiteSpace($Bucket) -or [string]::IsNullOrWhiteSpace($Key)) {
                    throw "When piping partial updates, you must specify -Bucket and -Key explicitly."
                }
            }
            else {
                if ([string]::IsNullOrWhiteSpace($Bucket) -or [string]::IsNullOrWhiteSpace($Key)) {
                    if ($InputObject.PSObject.Properties['_BucketName']) { $Bucket = $InputObject._BucketName }
                    if ($InputObject.PSObject.Properties['_BucketKey']) { $Key = $InputObject._BucketKey }
                    if ([string]::IsNullOrWhiteSpace($Bucket) -or [string]::IsNullOrWhiteSpace($Key)) {
                        throw "Cannot determine bucket and key. Use -Bucket and -Key parameters, or pipe an object from Get-BucketObject."
                    }
                }
            }

            if ($InputObject.PSObject.Properties[$Key]) {
                $resolvedKey = $InputObject.$Key
                if ($null -ne $resolvedKey) { $Key = $resolvedKey -replace '[\\/:\*\?"<>\|\[\]]', '_' }
            }
        }

        if ($null -eq $bucketPath) {
            $bucketPath = Get-BucketPath -Name $Bucket -Path $Path
            if (-not [System.IO.Directory]::Exists($bucketPath)) {
                throw "Bucket '$Bucket' not found at '$bucketPath'"
            }
        }

        # Resolve matching file(s) — supports wildcards in Key
        $matchingFiles = @()
        $hasKeyWildcard = $Key -match '[\*\?]'
        if ($hasKeyWildcard) {
            $di = [System.IO.DirectoryInfo]::new($bucketPath)
            $target = $Key.ToLowerInvariant()
            $matchingFiles = @(foreach ($f in @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))) {
                $baseLower = [System.IO.Path]::GetFileNameWithoutExtension($f.Name).ToLowerInvariant()
                if ($baseLower -like $target) { $f }
            })
            if ($matchingFiles.Count -eq 0) {
                throw "No objects matching key pattern '$Key' found in bucket '$Bucket'"
            }
        } else {
            $file = Find-ObjectFile -BucketPath $bucketPath -Key $Key
            if ($null -eq $file) {
                throw "Object with key '$Key' not found in bucket '$Bucket'"
            }
            $matchingFiles = @($file)
        }

        if ($hasKeyWildcard -and -not $isPropertySet) { $isPatch = $true }

        foreach ($file in $matchingFiles) {
            $fileKey = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $filePath = $file.FullName
            $useJson = $file.Extension -eq ".json" -and -not $AsBinary
            $objectToSave = $InputObject

            if ($isPropertySet) {
                $existing = Read-BucketFile -File ([System.IO.FileInfo]::new($filePath))
                if ($null -eq $existing) { throw "Failed to read existing object '$fileKey' in bucket '$Bucket'" }
                if ($existing -is [hashtable]) { $existing[$Property] = $Value }
                elseif ($existing.PSObject.Properties[$Property]) { $existing.PSObject.Properties[$Property].Value = $Value }
                else { $existing | Add-Member -NotePropertyName $Property -NotePropertyValue $Value }
                $objectToSave = $existing
            }
            elseif ($isPatch) {
                $existing = Read-BucketFile -File ([System.IO.FileInfo]::new($filePath))
                if ($null -eq $existing) { throw "Failed to read existing object '$fileKey' in bucket '$Bucket'" }
                if ($InputObject -is [hashtable]) {
                    if ($existing -is [hashtable]) {
                        foreach ($kvp in $InputObject.GetEnumerator()) { $existing[$kvp.Key] = $kvp.Value }
                    }
                    else {
                        foreach ($kvp in $InputObject.GetEnumerator()) {
                            if ($existing.PSObject.Properties[$kvp.Key]) { $existing.PSObject.Properties[$kvp.Key].Value = $kvp.Value }
                            else { $existing | Add-Member -NotePropertyName $kvp.Key -NotePropertyValue $kvp.Value }
                        }
                    }
                }
                else {
                    foreach ($prop in $InputObject.PSObject.Properties) {
                        if ($prop.IsSettable) {
                            if ($existing -is [hashtable]) { $existing[$prop.Name] = $prop.Value }
                            elseif ($existing.PSObject.Properties[$prop.Name]) { $existing.PSObject.Properties[$prop.Name].Value = $prop.Value }
                            else { $existing | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value }
                        }
                    }
                }
                $objectToSave = $existing
            }

            $writeSuccess = $false
            if ($PSCmdlet.ShouldProcess("$Bucket/$fileKey", "Update object")) {
                if ($useJson) {
                    try {
                        $json = ConvertTo-Json -InputObject $objectToSave -Depth $Depth -Compress -WarningAction SilentlyContinue
                        [System.IO.File]::WriteAllText($filePath, $json, [System.Text.Encoding]::UTF8)
                        $writeSuccess = $true
                    }
                    catch {
                        $tmpBinary = $null
                        try {
                            $xml = [System.Management.Automation.PSSerializer]::Serialize($objectToSave, $BinaryDepth)
                            $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                            $binaryFilePath = [System.IO.Path]::ChangeExtension($filePath, ".dat")
                            $tmpBinary = $binaryFilePath + ".tmp"
                            if ($Compress) {
                                $ms = [System.IO.MemoryStream]::new()
                                try {
                                    $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
                                    try { $cs.Write($rawBytes, 0, $rawBytes.Length) }
                                    finally { $cs.Close() }
                                    [System.IO.File]::WriteAllBytes($tmpBinary, $ms.ToArray())
                                }
                                finally { $ms.Dispose() }
                            }
                            else { [System.IO.File]::WriteAllBytes($tmpBinary, $rawBytes) }
                            if (Test-Path $filePath) { Remove-Item $filePath -Force }
                            [System.IO.File]::Move($tmpBinary, $binaryFilePath)
                            $tmpBinary = $null
                            $filePath = $binaryFilePath
                            Write-Warning "Object '$fileKey' too complex for JSON, saved as binary instead"
                            $writeSuccess = $true
                        }
                        catch {
                            if ($null -ne $tmpBinary -and (Test-Path $tmpBinary)) { Remove-Item $tmpBinary -Force -ErrorAction SilentlyContinue }
                            throw "Failed to serialize object '$fileKey' as binary: $_"
                        }
                    }
                }
                else {
                    $oldFilePath = if ($AsBinary -and $filePath -like "*.json") { $filePath } else { $null }
                    if ($AsBinary -and $filePath -like "*.json") {
                        $filePath = [System.IO.Path]::ChangeExtension($filePath, ".dat")
                    }
                    $currentDepth = $BinaryDepth; $serialized = $false
                    $maxLoopDepth = [Math]::Max(10, $BinaryDepth)
                    $tmpFilePath = $filePath + ".tmp"
                    try {
                        while (-not $serialized -and $currentDepth -le $maxLoopDepth) {
                            try {
                                $xml = [System.Management.Automation.PSSerializer]::Serialize($objectToSave, $currentDepth)
                                $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                                if ($Compress) {
                                    $ms = [System.IO.MemoryStream]::new()
                                    try {
                                        $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
                                        try { $cs.Write($rawBytes, 0, $rawBytes.Length) }
                                        finally { $cs.Close() }
                                        [System.IO.File]::WriteAllBytes($tmpFilePath, $ms.ToArray())
                                    }
                                    finally { $ms.Dispose() }
                                }
                                else { [System.IO.File]::WriteAllBytes($tmpFilePath, $rawBytes) }
                                $serialized = $true
                                if ($currentDepth -gt $BinaryDepth) { Write-Verbose "Binary serialization required depth $currentDepth (default: $BinaryDepth)" }
                            }
                            catch { $currentDepth++ }
                        }
                        if (-not $serialized) { throw "Failed to serialize object '$fileKey' at any binary depth" }
                        if ($null -ne $oldFilePath -and (Test-Path $oldFilePath)) { Remove-Item $oldFilePath -Force }
                        [System.IO.File]::Move($tmpFilePath, $filePath, $true)
                        $writeSuccess = $true
                    }
                    finally {
                        if (Test-Path $tmpFilePath) { Remove-Item $tmpFilePath -Force -ErrorAction SilentlyContinue }
                    }
                }
            }
            else {
                $writeSuccess = $true
            }

            if ($writeSuccess) {
                $savedCount++
                $lastBucket = $Bucket
                $null = $updatedKeys.Add($fileKey)
                if ($useVerbose) { Write-Verbose "Updated [$Bucket/$fileKey] -> $filePath" }
            }
        }
    }

    end {
        if ($savedCount -gt 0 -and -not $useVerbose -and -not $useQuiet) {
            Write-Host "$lastBucket" -NoNewline -ForegroundColor $script:CPath
            Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
            Write-Host $savedCount -NoNewline -ForegroundColor $script:CNum
            Write-Host " updated" -ForegroundColor $script:CMuted
            if ($savedCount -le 5) {
                Write-Host "  " -NoNewline
                Write-Host ($updatedKeys -join ", ") -ForegroundColor $script:CNum
            } else {
                Write-Host "  " -NoNewline
                Write-Host (($updatedKeys | Select-Object -First 5) -join ", ") -NoNewline -ForegroundColor $script:CNum
                Write-Host " ..." -NoNewline -ForegroundColor $script:CMuted
                Write-Host " +$($savedCount - 5) more" -ForegroundColor $script:CMuted
            }
        }
        if ($PassThru -and $savedCount -gt 0) {
            Write-Output ([PSCustomObject]@{
                Bucket      = $lastBucket
                Saved       = $savedCount
                UpdatedKeys = [string[]]$updatedKeys
                Format      = if ($AsBinary) { "Binary" } else { "JSON" }
                Compressed  = $Compress.IsPresent
            })
        }
    }
}
