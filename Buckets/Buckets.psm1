<#
.SYNOPSIS
    A PowerShell module for file-based PSObject storage using directory-backed buckets.
.DESCRIPTION
    Buckets provides a simple way to store, retrieve, and manage PowerShell objects
    in directory-based collections called "buckets". Objects are automatically serialized
    to binary (default) or JSON format, with auto-fallback to binary when JSON depth
    limits are exceeded.
#>

# Bucket path caching for session
$script:BucketPathCache = @{}
$script:LastPWD = $PWD.Path

function Clear-BucketPathCache {
    $script:BucketPathCache.Clear()
    $script:LastPWD = $PWD.Path
}

function Get-DefaultPath {
    return Join-Path $PWD.Path ".buckets"
}

function Resolve-SafePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    try {
        $resolved = [System.IO.Path]::GetFullPath($Path)
        return $resolved
    }
    catch {
        throw "Invalid path '$Path': $_"
    }
}

function Get-BucketPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Path
    )

    if ($script:LastPWD -ne $PWD.Path) {
        Clear-BucketPathCache
    }

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $cacheKey = "${Path}|${Name}"
    if ($script:BucketPathCache.ContainsKey($cacheKey)) {
        return $script:BucketPathCache[$cacheKey]
    }
    $bucketPath = Resolve-SafePath -Path (Join-Path $Path $Name)
    $script:BucketPathCache[$cacheKey] = $bucketPath
    return $bucketPath
}

function Ensure-BucketExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $rootPath = Resolve-SafePath -Path $Path
    $bucketPath = Get-BucketPath -Name $Name -Path $rootPath
    if (-not $bucketPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Bucket path '$bucketPath' resolves outside of root '$rootPath'. Path traversal not allowed."
    }
    if (-not (Test-Path $bucketPath)) {
        $null = New-Item -Path $bucketPath -ItemType Directory -Force
    }
    return $bucketPath
}

function New-BucketObject {
    <#
    .SYNOPSIS
    Saves a PSObject to a bucket. Creates the bucket if it doesn't exist.
    .DESCRIPTION
    Serializes one or more PowerShell objects and stores them in a bucket directory.
    Arrays are stored as individual files. By default objects are serialized to binary
    (.dat) using PSSerializer. Use -AsJson for JSON format. If JSON serialization
    exceeds the depth limit, the object automatically falls back to binary format.
    .PARAMETER InputObject
    The object(s) to store. Accepts pipeline input. Arrays are stored as individual files.
    .PARAMETER Bucket
    Name of the bucket to save to. Creates the bucket if it doesn't exist. Default: "default".
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Key
    Property name whose value becomes the filename. Special characters (/, :, *, ?, ", <, >, |, ., []) are sanitized to underscores. If omitted, a GUID is used.
    .PARAMETER Depth
    Maximum depth for JSON serialization. Default: 20.
    .PARAMETER BinaryDepth
    Maximum depth for binary (PSSerializer) serialization. Default: 2.
    .PARAMETER AsTimestamp
    Use a timestamp-based filename (yyyyMMddHHmmssfff_index) instead of a GUID. Ignored if -Key is also specified.
    .PARAMETER AsJson
    Store objects as JSON (.json) instead of binary (.dat).
    .PARAMETER Compress
    Enable GZip compression for binary (.dat) files to reduce disk usage.
    .PARAMETER Quiet
    Suppress all output. No progress indicator, no summary.
    .PARAMETER Overwrite
    Overwrite existing objects with the same key. Default: $false.
    .OUTPUTS
    By default, a progress indicator and summary are shown.
    Use -Verbose for per-object details. Use -Quiet for silent operation.
    .EXAMPLE
    New-BucketObject -InputObject @{ Name = "Alice"; Age = 30 } -Key Name
    .EXAMPLE
    $users | New-BucketObject -Bucket users -Key Email -AsJson
    .EXAMPLE
    # Progress bar and summary (default)
    Get-Process | New-BucketObject -Bucket processes -AsTimestamp
    .EXAMPLE
    # Per-object verbose output
    Get-Process | New-BucketObject -Bucket processes -Verbose
    .EXAMPLE
    # Silent, no output
    Get-Process | New-BucketObject -Bucket processes -Quiet
    .EXAMPLE
    # Overwrite existing object
    New-BucketObject -Bucket users -InputObject @{ Name = "Alice"; Age = 31 } -Key Name -Overwrite
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]$InputObject,

        [string]$Bucket = "default",

        [string]$Path,

        [string]$Key,

        [ValidateRange(1, 100)]
        [int]$Depth = 20,

        [ValidateRange(1, 10)]
        [int]$BinaryDepth = 2,

        [switch]$AsTimestamp,

        [switch]$AsJson,

        [switch]$Compress,

        [switch]$Overwrite,

        [switch]$Quiet
    )

    begin {
        $bucketPath = Ensure-BucketExists -Name $Bucket -Path $Path
        $extension = if ($AsJson) { ".json" } else { ".dat" }
        $savedCount = 0
        $skippedCount = 0
        $autoDepthCount = 0
        $failedCount = 0
        $totalCount = 0
        $useVerbose = $VerbosePreference -eq 'Continue'
        $useQuiet = $Quiet.IsPresent
        $showProgress = -not $useVerbose -and -not $useQuiet

        if ($AsTimestamp -and -not [string]::IsNullOrWhiteSpace($Key)) {
            Write-Verbose "Both -Key and -AsTimestamp specified. -Key takes precedence, -AsTimestamp ignored."
        }
    }

    process {
        $isCollection = $InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string] -and $InputObject -isnot [hashtable] -and $InputObject -isnot [System.Collections.IDictionary]

        if ($isCollection) {
            $items = $InputObject
        }
        else {
            $items = [System.Collections.ArrayList]::new()
            $null = $items.Add($InputObject)
        }

        $totalCount += $items.Count

        $index = 0
        foreach ($item in $items) {
            if (-not [string]::IsNullOrWhiteSpace($Key)) {
                $keyValue = $item.$Key
                if ($null -eq $keyValue) {
                    Write-Verbose "Property '$Key' not found on object, skipping"
                    $skippedCount++
                    $index++
                    continue
                }
                $safeKey = $keyValue -replace '[\\/:\*\?"<>\|\.\[\]]', '_'
                if ([string]::IsNullOrWhiteSpace($safeKey) -or $safeKey -match '^_+$') {
                    Write-Verbose "Key for object is empty after sanitization ('$keyValue' -> '$safeKey'), skipping"
                    $skippedCount++
                    $index++
                    continue
                }
                $filename = "${safeKey}${extension}"
            }
            elseif ($AsTimestamp) {
                $filename = "$(Get-Date -Format 'yyyyMMddHHmmssfff')_${index}${extension}"
            }
            else {
                $filename = "$([Guid]::NewGuid())${extension}"
            }

            $filePath = Join-Path $bucketPath $filename

            if ((Test-Path $filePath) -and -not $Overwrite) {
                Write-Verbose "Object with key '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' already exists in bucket '$Bucket'. Use -Overwrite to replace."
                $skippedCount++
                $index++
                continue
            }

            $writeSuccess = $false
            if ($AsJson) {
                $warnVar = $null
                $json = ConvertTo-Json -InputObject $item -Depth $Depth -Compress -WarningAction SilentlyContinue -WarningVariable warnVar
                if ($warnVar -and $warnVar[0] -like "*truncated*") {
                    try {
                        $xml = [System.Management.Automation.PSSerializer]::Serialize($item, $BinaryDepth)
                        $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                        if ($Compress) {
                            $ms = [System.IO.MemoryStream]::new()
                            $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
                            $cs.Write($rawBytes, 0, $rawBytes.Length)
                            $cs.Close()
                            [System.IO.File]::WriteAllBytes($filePath, $ms.ToArray())
                        }
                        else {
                            [System.IO.File]::WriteAllBytes($filePath, $rawBytes)
                        }
                        $filePath = [System.IO.Path]::ChangeExtension($filePath, ".dat")
                        Write-Verbose "Object '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' exceeds JSON depth $Depth, saved as binary (.dat)"
                        $autoDepthCount++
                        $writeSuccess = $true
                    }
                    catch {
                        Write-Verbose "Failed to serialize object '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' as binary: $_"
                        $failedCount++
                    }
                }
                else {
                    [System.IO.File]::WriteAllText($filePath, $json, [System.Text.Encoding]::UTF8)
                    $writeSuccess = $true
                }
            }
            else {
                $currentDepth = $BinaryDepth
                $serialized = $false
                while (-not $serialized -and $currentDepth -le 5) {
                    try {
                        $xml = [System.Management.Automation.PSSerializer]::Serialize($item, $currentDepth)
                        $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                        if ($Compress) {
                            $ms = [System.IO.MemoryStream]::new()
                            $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
                            $cs.Write($rawBytes, 0, $rawBytes.Length)
                            $cs.Close()
                            [System.IO.File]::WriteAllBytes($filePath, $ms.ToArray())
                        }
                        else {
                            [System.IO.File]::WriteAllBytes($filePath, $rawBytes)
                        }
                        $serialized = $true
                        if ($currentDepth -gt $BinaryDepth) {
                            Write-Verbose "Binary serialization required depth $currentDepth (default: $BinaryDepth)"
                            $autoDepthCount++
                        }
                    }
                    catch {
                        $currentDepth++
                    }
                }
                if (-not $serialized) {
                    Write-Verbose "Failed to serialize object with key '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' at any depth"
                    $failedCount++
                }
                else {
                    $writeSuccess = $true
                }
            }

            if ($writeSuccess) {
                $currentKey = [System.IO.Path]::GetFileNameWithoutExtension($filename)
                $savedCount++

                if ($showProgress) {
                    $percent = if ($totalCount -gt 0) { [math]::Round(($savedCount / $totalCount) * 100) } else { 0 }
                    $activity = "Saving to '$Bucket'"
                    $status = "$savedCount object(s) saved"
                    Write-Progress -Activity $activity -Status $status -PercentComplete $percent -CurrentOperation $currentKey
                }
                elseif ($useVerbose) {
                    Write-Verbose "Saved [$Bucket/$currentKey] -> $filePath"
                }
            }

            $index++
        }
    }

    end {
        if ($showProgress) {
            Write-Progress -Activity "Saving to '$Bucket'" -Completed
            $summary = "Saved $savedCount object(s) to '$Bucket'"
            if ($Compress) { $summary += " (compressed)" }
            Write-Host $summary -ForegroundColor Green
            if ($skippedCount -gt 0) {
                Write-Host "  $skippedCount skipped (existing or missing key)" -ForegroundColor Yellow
            }
            if ($autoDepthCount -gt 0) {
                Write-Host "  $autoDepthCount required auto-incremented depth" -ForegroundColor DarkYellow
            }
            if ($failedCount -gt 0) {
                Write-Host "  $failedCount failed to serialize" -ForegroundColor Red
            }
        }
    }
}

function Read-BucketFile {
    param(
        [System.IO.FileInfo]$File
    )

    $extension = $File.Extension
    $rawBytes = [System.IO.File]::ReadAllBytes($File.FullName)

    if ($extension -eq ".dat") {
        try {
            $decoded = $null
            $isCompressed = $rawBytes.Length -ge 2 -and $rawBytes[0] -eq 0x1F -and $rawBytes[1] -eq 0x8B
            if ($isCompressed) {
                try {
                    $ms = [System.IO.MemoryStream]::new($rawBytes)
                    $decompressed = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
                    $reader = [System.IO.StreamReader]::new($decompressed)
                    $decoded = $reader.ReadToEnd()
                    $reader.Close()
                    $decompressed.Close()
                }
                catch {
                    Write-Warning "Failed to decompress '$($File.Name)': $_"
                    return $null
                }
            }
            else {
                $decoded = [System.Text.Encoding]::UTF8.GetString($rawBytes)
                if (-not $decoded.StartsWith('<Objs') -and -not $decoded.StartsWith('<?xml')) {
                    $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($decoded))
                }
            }
            return [System.Management.Automation.PSSerializer]::Deserialize($decoded)
        }
        catch {
            Write-Warning "Failed to deserialize '$($File.Name)': $_"
            return $null
        }
    }
    else {
        try {
            $content = [System.Text.Encoding]::UTF8.GetString($rawBytes)
            if ($content.StartsWith([char]0xFEFF)) {
                $content = $content.Substring(1)
            }
            return $content | ConvertFrom-Json
        }
        catch {
            Write-Warning "Failed to parse JSON '$($File.Name)': $_"
            return $null
        }
    }
}

function Get-ObjectFiles {
    param(
        [string]$BucketPath,
        [string]$Key
    )

    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $jsonFile = Get-ChildItem -Path $BucketPath -Filter "$Key.json" -ErrorAction SilentlyContinue
        if ($jsonFile) { return @($jsonFile)[0] }
        $datFile = Get-ChildItem -Path $BucketPath -Filter "$Key.dat" -ErrorAction SilentlyContinue
        if ($datFile) { return @($datFile)[0] }
        return $null
    }
    else {
        $jsonFiles = @(Get-ChildItem -Path $BucketPath -Filter "*.json" -ErrorAction SilentlyContinue)
        $datFiles = @(Get-ChildItem -Path $BucketPath -Filter "*.dat" -ErrorAction SilentlyContinue)
        return $jsonFiles + $datFiles
    }
}

function Get-BucketObject {
    <#
    .SYNOPSIS
    Retrieves objects from one or more buckets.
    .DESCRIPTION
    Reads serialized objects from bucket directories. When no bucket is specified,
    searches all buckets under the storage path. Supports exact-match hashtable
    filtering (-Match) and arbitrary scriptblock filtering (-Filter).
    Retrieved objects include metadata properties: _BucketName, _BucketKey, _BucketFile.
    .PARAMETER Bucket
    Bucket name(s) to search. If omitted, searches all buckets under -Path. Supports wildcards.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Key
    Specific object key to retrieve. Looks for both .json and .dat files.
    .PARAMETER Match
    Hashtable of property-value pairs for exact-match filtering. All pairs must match. Supports $null values.
    .PARAMETER Filter
    ScriptBlock for custom filtering. Use $_ to reference object properties (e.g., { $_.Age -gt 30 }).
    .OUTPUTS
    Deserialized PSObjects with _BucketName, _BucketKey, and _BucketFile metadata.
    .EXAMPLE
    Get-BucketObject -Bucket users -Match @{ Role = "admin" }
    .EXAMPLE
    Get-BucketObject -Bucket users -Match @{ Deleted = $null }
    .EXAMPLE
    Get-BucketObject -Filter { $_.Status -eq "shipped" -and $_.Shipping.Method -eq "Express" }
    .EXAMPLE
    Get-BucketObject -Bucket users, orders
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 1)]
        [string[]]$Bucket,

        [string]$Path,

        [Parameter(Position = 0)]
        [string]$Key,

        [hashtable]$Match,

        [scriptblock]$Filter
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    $bucketPaths = @()
    if ($Bucket -and $Bucket.Count -gt 0) {
        $cachedBuckets = $null
        foreach ($b in $Bucket) {
            if ($b -match '[\*\?]') {
                if ($null -eq $cachedBuckets) {
                    $cachedBuckets = Get-Bucket -Path $Path
                }
                $matched = $cachedBuckets | Where-Object { $_.Name -like $b }
                $bucketPaths += $matched | ForEach-Object { $_.Path }
            }
            else {
                $bucketPaths += Get-BucketPath -Name $b -Path $Path
            }
        }
    }
    else {
        if (Test-Path $Path) {
            $bucketPaths += Get-ChildItem -Path $Path -Directory | ForEach-Object { $_.FullName }
        }
    }

    foreach ($bucketPath in $bucketPaths) {
        if (-not (Test-Path $bucketPath)) { continue }

        $bucketName = Split-Path $bucketPath -Leaf

        $files = Get-ObjectFiles -BucketPath $bucketPath -Key $Key

        foreach ($file in @($files)) {
            $obj = Read-BucketFile -File $file
            if ($null -eq $obj) { continue }

            if ($Match) {
                $hit = $true
                foreach ($kvp in $Match.GetEnumerator()) {
                    $propName = $kvp.Name
                    $expectedValue = $kvp.Value
                    $hasProperty = $null -ne $obj.PSObject.Properties[$propName]
                    if ($hasProperty) {
                        $actualValue = $obj.$propName
                    }
                    else {
                        $actualValue = $null
                    }

                    $matchesValue = if ($null -eq $expectedValue) {
                        $null -eq $actualValue
                    }
                    elseif ($null -eq $actualValue) {
                        $false
                    }
                    else {
                        $actualValue -eq $expectedValue
                    }

                    if (-not $matchesValue) {
                        $hit = $false
                        break
                    }
                }
                if (-not $hit) { continue }
            }

            if ($Filter) {
                if ($null -eq ($obj | Where-Object $Filter)) { continue }
            }

            $obj | Add-Member -NotePropertyName "_BucketName" -NotePropertyValue $bucketName -Force
            $obj | Add-Member -NotePropertyName "_BucketKey" -NotePropertyValue ([System.IO.Path]::GetFileNameWithoutExtension($file.Name)) -Force
            $obj | Add-Member -NotePropertyName "_BucketFile" -NotePropertyValue $file.FullName -Force
            Write-Output $obj
        }
    }
}

function Set-BucketObject {
    <#
    .SYNOPSIS
    Updates an existing object in a bucket.
    .DESCRIPTION
    Automatically detects whether the pipeline input is a full object replacement or a partial update.

    If the piped object contains _BucketName and _BucketKey metadata (from Get-BucketObject),
    the entire object replaces the stored version. If the piped object lacks metadata, only
    its properties are merged into the existing object (partial update).

    Preserves the storage format (JSON or binary) of the existing file unless -AsJson forces
    a format change. If JSON serialization exceeds the depth limit, the object automatically
    falls back to binary format.
    .PARAMETER InputObject
    The object to store. Accepts pipeline input. If it has _BucketName and _BucketKey metadata,
    bucket and key are auto-resolved. Otherwise -Bucket and -Key are required.
    .PARAMETER Bucket
    Name of the bucket containing the object. Auto-resolved from pipeline metadata if omitted.
    Required when piping partial updates.
    .PARAMETER Key
    Object key to update. Auto-resolved from pipeline metadata if omitted.
    Required when piping partial updates.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Depth
    Maximum depth for JSON serialization. Default: 20.
    .PARAMETER BinaryDepth
    Maximum depth for binary (PSSerializer) serialization. Default: 2.
    .PARAMETER AsJson
    Force JSON format for the updated file.
    .PARAMETER Compress
    Enable GZip compression for binary (.dat) files.
    .PARAMETER Quiet
    Suppress all output. No summary.
    .EXAMPLE
    # Full replacement: object has metadata from Get-BucketObject
    Get-BucketObject -Bucket users -Key "Alice" | ForEach-Object { $_.Age = 31; $_ } | Set-BucketObject
    .EXAMPLE
    # Partial update: piped object has no metadata, only specified properties are merged
    @{ Age = 32; Active = $true } | Set-BucketObject -Bucket users -Key "Alice"
    .EXAMPLE
    # Explicit full replacement
    $user = Get-BucketObject -Bucket users -Key "Alice"
    $user.Email = "alice@new.com"
    Set-BucketObject -Bucket users -Key "Alice" -InputObject $user
    .EXAMPLE
    # Quiet mode with no output
    Get-BucketObject -Bucket users -Key "Alice" | ForEach-Object { $_.Age = 31; $_ } | Set-BucketObject -Quiet
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [PSObject]$InputObject,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [Alias("_BucketName")]
        [string]$Bucket,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [Alias("_BucketKey")]
        [string]$Key,

        [string]$Path,

        [ValidateRange(1, 100)]
        [int]$Depth = 20,

        [ValidateRange(1, 10)]
        [int]$BinaryDepth = 2,

        [switch]$AsJson,

        [switch]$Compress,

        [switch]$Quiet
    )

    begin {
        $bucketPath = $null
        $savedCount = 0
        $useVerbose = $VerbosePreference -eq 'Continue'
        $useQuiet = $Quiet.IsPresent
    }

    process {
        $isPatch = -not ($InputObject.PSObject.Properties['_BucketName'] -and $InputObject.PSObject.Properties['_BucketKey'])

        if ($null -eq $bucketPath) {
            if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
            $Path = Resolve-SafePath -Path $Path
        }

        if ($isPatch) {
            if ([string]::IsNullOrWhiteSpace($Bucket) -or [string]::IsNullOrWhiteSpace($Key)) {
                throw "When piping partial updates, you must specify -Bucket and -Key explicitly."
            }
        }
        else {
            if ([string]::IsNullOrWhiteSpace($Bucket) -or [string]::IsNullOrWhiteSpace($Key)) {
                if ($InputObject.PSObject.Properties['_BucketName']) {
                    $Bucket = $InputObject._BucketName
                }
                if ($InputObject.PSObject.Properties['_BucketKey']) {
                    $Key = $InputObject._BucketKey
                }
                if ([string]::IsNullOrWhiteSpace($Bucket) -or [string]::IsNullOrWhiteSpace($Key)) {
                    throw "Cannot determine bucket and key. Use -Bucket and -Key parameters, or pipe an object from Get-BucketObject."
                }
            }
        }

        # Extract key value from property name (consistent with New-BucketObject)
        if ($InputObject.PSObject.Properties[$Key]) {
            $resolvedKey = $InputObject.$Key
            if ($null -ne $resolvedKey) {
                $Key = $resolvedKey -replace '[\\/:\*\?"<>\|\.\[\]]', '_'
            }
        }

        if ($null -eq $bucketPath) {
            $bucketPath = Get-BucketPath -Name $Bucket -Path $Path
            if (-not (Test-Path $bucketPath)) {
                throw "Bucket '$Bucket' not found at '$bucketPath'"
            }
        }

        $jsonPath = Join-Path $bucketPath "$Key.json"
        $datPath = Join-Path $bucketPath "$Key.dat"

        $filePath = if (Test-Path $jsonPath) { $jsonPath }
        elseif (Test-Path $datPath) { $datPath }
        else {
            throw "Object with key '$Key' not found in bucket '$Bucket'"
        }

        $useJson = $filePath -like "*.json" -or $AsJson

        if ($isPatch) {
            $existing = Read-BucketFile -File ([System.IO.FileInfo]::new($filePath))
            if ($null -eq $existing) {
                throw "Failed to read existing object '$Key' in bucket '$Bucket'"
            }
            if ($InputObject -is [hashtable]) {
                if ($existing -is [hashtable]) {
                    foreach ($kvp in $InputObject.GetEnumerator()) {
                        $existing[$kvp.Key] = $kvp.Value
                    }
                }
                else {
                    foreach ($kvp in $InputObject.GetEnumerator()) {
                        if ($existing.PSObject.Properties[$kvp.Key]) {
                            $existing.PSObject.Properties[$kvp.Key].Value = $kvp.Value
                        }
                        else {
                            $existing | Add-Member -NotePropertyName $kvp.Key -NotePropertyValue $kvp.Value
                        }
                    }
                }
            }
            else {
                foreach ($prop in $InputObject.PSObject.Properties) {
                    if ($prop.IsSettable) {
                        if ($existing -is [hashtable]) {
                            $existing[$prop.Name] = $prop.Value
                        }
                        elseif ($existing.PSObject.Properties[$prop.Name]) {
                            $existing.PSObject.Properties[$prop.Name].Value = $prop.Value
                        }
                        else {
                            $existing | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
                        }
                    }
                }
            }
            $InputObject = $existing
        }

        $writeSuccess = $false
        if ($useJson) {
            $warnVar = $null
            $json = ConvertTo-Json -InputObject $InputObject -Depth $Depth -Compress -WarningAction SilentlyContinue -WarningVariable warnVar
            if ($warnVar -and $warnVar[0] -like "*truncated*") {
                try {
                    $xml = [System.Management.Automation.PSSerializer]::Serialize($InputObject, $BinaryDepth)
                    $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                    if ($Compress) {
                        $ms = [System.IO.MemoryStream]::new()
                        $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
                        $cs.Write($rawBytes, 0, $rawBytes.Length)
                        $cs.Close()
                        [System.IO.File]::WriteAllBytes($filePath, $ms.ToArray())
                    }
                    else {
                        [System.IO.File]::WriteAllBytes($filePath, $rawBytes)
                    }
                    $filePath = [System.IO.Path]::ChangeExtension($filePath, ".dat")
                    Write-Verbose "Object '$Key' exceeds JSON depth $Depth, saved as binary (.dat)"
                    $writeSuccess = $true
                }
                catch {
                    throw "Failed to serialize object '$Key' as binary: $_"
                }
            }
            else {
                [System.IO.File]::WriteAllText($filePath, $json, [System.Text.Encoding]::UTF8)
                $writeSuccess = $true
            }
        }
        else {
            $currentDepth = $BinaryDepth
            $serialized = $false
            while (-not $serialized -and $currentDepth -le 5) {
                try {
                    $xml = [System.Management.Automation.PSSerializer]::Serialize($InputObject, $currentDepth)
                    $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                    if ($Compress) {
                        $ms = [System.IO.MemoryStream]::new()
                        $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
                        $cs.Write($rawBytes, 0, $rawBytes.Length)
                        $cs.Close()
                        [System.IO.File]::WriteAllBytes($filePath, $ms.ToArray())
                    }
                    else {
                        [System.IO.File]::WriteAllBytes($filePath, $rawBytes)
                    }
                    $serialized = $true
                    if ($currentDepth -gt $BinaryDepth) {
                        Write-Verbose "Binary serialization required depth $currentDepth (default: $BinaryDepth)"
                    }
                }
                catch {
                    $currentDepth++
                }
            }
            if (-not $serialized) {
                throw "Failed to serialize object '$Key' at any binary depth"
            }
            $writeSuccess = $true
        }

        if ($writeSuccess) {
            $savedCount++
            if ($useVerbose) {
                Write-Verbose "Updated [$Bucket/$Key] -> $filePath"
            }
            elseif (-not $useQuiet) {
                $result = [PSCustomObject]@{
                    Bucket   = $Bucket
                    Key      = $Key
                    FilePath = $filePath
                }
                Write-Output $result
            }
        }
    }

    end {
        if ($savedCount -gt 0 -and -not $useVerbose -and -not $useQuiet) {
            Write-Host "Updated $savedCount object(s) in '$Bucket'" -ForegroundColor Green
        }
    }
}

function Remove-BucketObject {
    <#
    .SYNOPSIS
    Removes an object from a bucket.
    .DESCRIPTION
    Deletes a specific object file from a bucket directory. Use -Key to remove a single
    object or -All to clear the entire bucket.
    .PARAMETER Bucket
    Name of the bucket containing the object(s) to remove.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Key
    Object key to remove. Looks for both .json and .dat files.
    .PARAMETER All
    Remove all objects from the bucket.
    .PARAMETER PassThru
    Return metadata for removed objects.
    .EXAMPLE
    Remove-BucketObject -Bucket users -Key "Alice"
    .EXAMPLE
    Remove-BucketObject -Bucket temp -All -PassThru
    .EXAMPLE
    Remove-BucketObject -Bucket users -Key "Alice" -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByKey')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [string]$Path,

        [Parameter(ParameterSetName = 'ByKey')]
        [string]$Key,

        [Parameter(ParameterSetName = 'All')]
        [switch]$All,

        [switch]$PassThru,

        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path

    if (-not (Test-Path $bucketPath)) {
        Write-Verbose "Bucket '$Bucket' not found at '$bucketPath'"
        return
    }

    if ($All) {
        $jsonFiles = @(Get-ChildItem -Path $bucketPath -Filter "*.json" -ErrorAction SilentlyContinue)
        $datFiles = @(Get-ChildItem -Path $bucketPath -Filter "*.dat" -ErrorAction SilentlyContinue)
        $allFiles = $jsonFiles + $datFiles

        if ($allFiles.Count -eq 0) {
            Write-Verbose "Bucket '$Bucket' is already empty"
            return
        }

        $target = "$($allFiles.Count) object(s) from bucket '$Bucket'"
        if ($PSCmdlet.ShouldProcess($target, "Remove-BucketObject")) {
            $allFiles | Remove-Item -Force
        }

        if ($PassThru) {
            foreach ($f in $allFiles) {
                [PSCustomObject]@{
                    Bucket   = $Bucket
                    Key      = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                    FilePath = $f.FullName
                }
            }
        }
        elseif (-not $WhatIfPreference) {
            Write-Verbose "Removed $($allFiles.Count) object(s) from bucket '$Bucket'"
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Key)) {
        $jsonPath = Join-Path $bucketPath "$Key.json"
        $datPath = Join-Path $bucketPath "$Key.dat"

        $found = $false
        $foundPath = $null
        if (Test-Path $jsonPath) {
            $found = $true
            $foundPath = $jsonPath
        }
        elseif (Test-Path $datPath) {
            $found = $true
            $foundPath = $datPath
        }

        if (-not $found) {
            Write-Warning "Object with key '$Key' not found in bucket '$Bucket'"
        }
        elseif ($PSCmdlet.ShouldProcess("object '$Key' from bucket '$Bucket'", "Remove-BucketObject")) {
            if ($PassThru) {
                [PSCustomObject]@{
                    Bucket   = $Bucket
                    Key      = $Key
                    FilePath = $foundPath
                }
            }
            Remove-Item -Path $foundPath -Force
        }
    }
    else {
        throw "Specify either -Key or -All"
    }
}

function Get-Bucket {
    <#
    .SYNOPSIS
    Lists available buckets with object counts.
    .DESCRIPTION
    Scans the storage path for bucket directories and returns information about each,
    including name, path, and total object count (JSON + binary files).
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Name
    Filter buckets by name pattern (substring match).
    .OUTPUTS
    PSCustomObject with Name, Path, and ObjectCount properties.
    .EXAMPLE
    Get-Bucket
    .EXAMPLE
    Get-Bucket "user"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name,

        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    if (-not (Test-Path $Path)) {
        return
    }

    $buckets = Get-ChildItem -Path $Path -Directory

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $buckets = $buckets | Where-Object { $_.Name -like "*$Name*" }
    }

    $buckets | ForEach-Object {
        $allFiles = @(Get-ChildItem -Path $_.FullName -File -ErrorAction SilentlyContinue)
        $count = ($allFiles | Where-Object { $_.Extension -in '.json', '.dat' }).Count
        [PSCustomObject]@{
            Name        = $_.Name
            Path        = $_.FullName
            ObjectCount = $count
        }
    }
}

function Get-BucketStats {
    <#
    .SYNOPSIS
    Shows statistics for a bucket.
    .DESCRIPTION
    Returns object count, total storage size, and oldest/newest object timestamps
    for the specified bucket. Returns $null if the bucket does not exist.
    .PARAMETER Bucket
    Name of the bucket to analyze.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .OUTPUTS
    PSCustomObject with Name, Path, ObjectCount, TotalSize, OldestObject, and NewestObject properties.
    .EXAMPLE
    Get-BucketStats -Bucket users
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path

    if (-not (Test-Path $bucketPath)) {
        Write-Warning "Bucket '$Bucket' not found at '$bucketPath'"
        return
    }

    $fileObjects = @((Get-ChildItem -Path $bucketPath -Filter "*.dat" -ErrorAction SilentlyContinue)) + @((Get-ChildItem -Path $bucketPath -Filter "*.json" -ErrorAction SilentlyContinue))

    $totalSize = ($fileObjects | Measure-Object -Property Length -Sum).Sum

    $oldest = $null
    $newest = $null
    foreach ($f in $fileObjects) {
        if ($null -eq $oldest -or $f.CreationTime -lt $oldest) { $oldest = $f.CreationTime }
        if ($null -eq $newest -or $f.CreationTime -gt $newest) { $newest = $f.CreationTime }
    }

    [PSCustomObject]@{
        Name         = $Bucket
        Path         = $bucketPath
        ObjectCount  = $fileObjects.Count
        TotalSize    = if ($totalSize) { "$([math]::Round($totalSize / 1KB, 2)) KB" } else { "0 KB" }
        OldestObject = $oldest
        NewestObject = $newest
    }
}

function Remove-Bucket {
    <#
    .SYNOPSIS
    Removes one or more buckets and all their objects.
    .DESCRIPTION
    Deletes bucket directories and their contents. Supports exact names, multiple
    buckets, and wildcard patterns. Only removes directories containing .dat/.json
    files (or empty directories). Skips buckets with other file types.
    Uses standard -Confirm support for confirmation prompts.
    .PARAMETER Bucket
    Bucket name(s) or wildcard patterns to remove. Supports glob-style wildcards (*, ?).
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Force
    Skip confirmation prompt.
    .PARAMETER WhatIf
    Preview which buckets would be removed without actually deleting them.
    .EXAMPLE
    Remove-Bucket -Bucket users
    .EXAMPLE
    Remove-Bucket -Bucket "temp*" -Force
    .EXAMPLE
    Remove-Bucket * -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Bucket,

        [string]$Path,

        [switch]$Force
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    $matched = @()
    foreach ($pattern in $Bucket) {
        if ($pattern -match '[\*\?]') {
            $found = $allBuckets | Where-Object { $_.Name -like $pattern }
            if (-not $found) {
                Write-Warning "No buckets match pattern '$pattern'"
            }
            $matched += $found
        }
        elseif ($pattern -eq "*") {
            $matched += $allBuckets
        }
        else {
            $exact = $allBuckets | Where-Object { $_.Name -eq $pattern }
            if ($exact) {
                $matched += $exact
            }
            else {
                Write-Warning "Bucket '$pattern' not found at '$Path'"
            }
        }
    }

    if ($matched.Count -eq 0) { return }

    foreach ($m in $matched) {
        $allFiles = Get-ChildItem -Path $m.Path -File -ErrorAction SilentlyContinue
        $otherFiles = $allFiles | Where-Object { $_.Extension -notin ".dat", ".json" }
        if ($otherFiles) {
            Write-Warning "Bucket '$($m.Name)' contains non-bucket files, skipping:"
            foreach ($f in $otherFiles) {
                Write-Warning "  $($f.Name)"
            }
            continue
        }

        $stats = Get-BucketStats -Bucket $m.Name -Path $Path
        $fileCount = if ($stats) { $stats.ObjectCount } else { 0 }

        $target = "bucket '$($m.Name)' ($fileCount object(s)) at $($m.Path)"

        if ($Force -or $PSCmdlet.ShouldProcess($target, "Remove-Bucket")) {
            Write-Verbose "Removing bucket '$($m.Name)' ($fileCount object(s))"
            Remove-Item -Path $m.Path -Recurse -Force
            $cacheKeys = @($script:BucketPathCache.Keys) | Where-Object { $_ -like "*|$($m.Name)" }
            foreach ($ck in $cacheKeys) { $script:BucketPathCache.Remove($ck) }
            Write-Verbose "Bucket '$($m.Name)' removed"
        }
    }

    if (-not $WhatIfPreference) {
        $removed = $matched | Where-Object { -not (Test-Path $_.Path -ErrorAction SilentlyContinue) } | Measure-Object | Select-Object -ExpandProperty Count
        $skipped = $matched.Count - $removed
        if ($removed -gt 0 -or $skipped -gt 0) {
            Write-Host "$removed bucket(s) removed" -ForegroundColor Green
            if ($skipped -gt 0) {
                Write-Host "$skipped bucket(s) skipped (contains non-bucket files)" -ForegroundColor Yellow
            }
        }
    }
}

function Copy-BucketObject {
    <#
    .SYNOPSIS
    Copies an object within or between buckets.
    .DESCRIPTION
    Duplicates an object file from one bucket to another, optionally changing the key.
    Preserves the original serialization format (JSON or binary).
    .PARAMETER Bucket
    Source bucket name.
    .PARAMETER DestinationBucket
    Destination bucket name. Defaults to the same as -Bucket if omitted.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Key
    Source object key to copy.
    .PARAMETER DestinationKey
    Destination object key. Defaults to the source key if omitted.
    .PARAMETER PassThru
    Return metadata for the copied object.
    .EXAMPLE
    Copy-BucketObject -Bucket users -Key "Alice" -DestinationBucket archive
    .EXAMPLE
    Copy-BucketObject -Bucket config -Key "app-config" -DestinationKey "app-config-backup"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [string]$DestinationBucket,

        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [string]$DestinationKey,

        [switch]$PassThru,

        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    $sourceBucketPath = Get-BucketPath -Name $Bucket -Path $Path
    if (-not (Test-Path $sourceBucketPath)) {
        throw "Source bucket '$Bucket' not found at '$sourceBucketPath'"
    }

    if ([string]::IsNullOrWhiteSpace($DestinationBucket)) {
        $DestinationBucket = $Bucket
    }
    if ([string]::IsNullOrWhiteSpace($DestinationKey)) {
        $DestinationKey = $Key
    }

    $safeDestKey = $DestinationKey -replace '[\\/:\*\?"<>\|\.\[\]]', '_'
    if ([string]::IsNullOrWhiteSpace($safeDestKey) -or $safeDestKey -match '^_+$') {
        throw "Destination key '$DestinationKey' is invalid after sanitization"
    }

    $jsonPath = Join-Path $sourceBucketPath "$Key.json"
    $datPath = Join-Path $sourceBucketPath "$Key.dat"
    if (Test-Path $jsonPath) { $sourceFile = $jsonPath }
    elseif (Test-Path $datPath) { $sourceFile = $datPath }
    else {
        throw "Object with key '$Key' not found in bucket '$Bucket'"
    }

    $destBucketPath = Ensure-BucketExists -Name $DestinationBucket -Path $Path
    $destJsonPath = Join-Path $destBucketPath "${safeDestKey}.json"
    $destDatPath = Join-Path $destBucketPath "${safeDestKey}.dat"

    if ((Test-Path $destJsonPath) -or (Test-Path $destDatPath)) {
        throw "Object with key '$safeDestKey' already exists in bucket '$DestinationBucket'. Use a different key."
    }

    $ext = [System.IO.Path]::GetExtension($sourceFile)
    $destFile = Join-Path $destBucketPath "${safeDestKey}${ext}"

    Copy-Item -Path $sourceFile -Destination $destFile -Force
    Write-Verbose "Copied [$Bucket/$Key] to [$DestinationBucket/$safeDestKey]"

    if ($PassThru) {
        [PSCustomObject]@{
            SourceBucket = $Bucket
            SourceKey = $Key
            DestinationBucket = $DestinationBucket
            DestinationKey = $safeDestKey
            FilePath = $destFile
        }
    }
    elseif (-not $Quiet) {
        Write-Host "Copied '$Key' from '$Bucket' to '$DestinationBucket/$safeDestKey'" -ForegroundColor Green
    }
}

function Rename-BucketObject {
    <#
    .SYNOPSIS
    Renames an object key within a bucket.
    .DESCRIPTION
    Moves an object file to a new key within the same bucket without re-serialization.
    Preserves the original format (JSON or binary).
    .PARAMETER Bucket
    Bucket name.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Key
    Current object key.
    .PARAMETER NewKey
    New object key.
    .PARAMETER PassThru
    Return metadata for the renamed object.
    .EXAMPLE
    Rename-BucketObject -Bucket users -Key "Alice" -NewKey "alice-smith"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [string]$NewKey,

        [switch]$PassThru,

        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path
    if (-not (Test-Path $bucketPath)) {
        throw "Bucket '$Bucket' not found at '$bucketPath'"
    }

    $safeNewKey = $NewKey -replace '[\\/:\*\?"<>\|\.\[\]]', '_'
    if ([string]::IsNullOrWhiteSpace($safeNewKey) -or $safeNewKey -match '^_+$') {
        throw "New key '$NewKey' is invalid after sanitization"
    }

    $jsonPath = Join-Path $bucketPath "$Key.json"
    $datPath = Join-Path $bucketPath "$Key.dat"
    if (Test-Path $jsonPath) { $sourceFile = $jsonPath }
    elseif (Test-Path $datPath) { $sourceFile = $datPath }
    else {
        throw "Object with key '$Key' not found in bucket '$Bucket'"
    }

    $ext = [System.IO.Path]::GetExtension($sourceFile)
    $destJsonPath = Join-Path $bucketPath "${safeNewKey}.json"
    $destDatPath = Join-Path $bucketPath "${safeNewKey}.dat"
    if ((Test-Path $destJsonPath) -or (Test-Path $destDatPath)) {
        throw "Object with key '$safeNewKey' already exists in bucket '$Bucket'"
    }

    $destFile = Join-Path $bucketPath "${safeNewKey}${ext}"

    Move-Item -Path $sourceFile -Destination $destFile -Force
    Write-Verbose "Renamed [$Bucket/$Key] to [$Bucket/$safeNewKey]"

    if ($PassThru) {
        [PSCustomObject]@{
            Bucket = $Bucket
            OldKey = $Key
            NewKey = $safeNewKey
            FilePath = $destFile
        }
    }
    elseif (-not $Quiet) {
        Write-Host "Renamed '$Key' to '$safeNewKey' in bucket '$Bucket'" -ForegroundColor Green
    }
}

function Move-BucketObject {
    <#
    .SYNOPSIS
    Moves an object within or between buckets.
    .DESCRIPTION
    Moves an object file from one bucket to another (or within the same bucket),
    optionally changing the key. Deletes the source file after successful copy.
    Preserves the original serialization format (JSON or binary).
    .PARAMETER Bucket
    Source bucket name.
    .PARAMETER DestinationBucket
    Destination bucket name. Defaults to the same as -Bucket if omitted.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Key
    Source object key to move.
    .PARAMETER DestinationKey
    Destination object key. Defaults to the source key if omitted.
    .PARAMETER PassThru
    Return metadata for the moved object.
    .PARAMETER Quiet
    Suppress all output.
    .EXAMPLE
    Move-BucketObject -Bucket todos -Key 1 -DestinationBucket archive
    .EXAMPLE
    Move-BucketObject -Bucket todos -Key 5 -DestinationKey 5b
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [string]$DestinationBucket,

        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [string]$DestinationKey,

        [switch]$PassThru,

        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    $sourceBucketPath = Get-BucketPath -Name $Bucket -Path $Path
    if (-not (Test-Path $sourceBucketPath)) {
        throw "Source bucket '$Bucket' not found at '$sourceBucketPath'"
    }

    if ([string]::IsNullOrWhiteSpace($DestinationBucket)) {
        $DestinationBucket = $Bucket
    }
    if ([string]::IsNullOrWhiteSpace($DestinationKey)) {
        $DestinationKey = $Key
    }

    $safeDestKey = $DestinationKey -replace '[\\/:\*\?"<>\|\.\[\]]', '_'
    if ([string]::IsNullOrWhiteSpace($safeDestKey) -or $safeDestKey -match '^_+$') {
        throw "Destination key '$DestinationKey' is invalid after sanitization"
    }

    $jsonPath = Join-Path $sourceBucketPath "$Key.json"
    $datPath = Join-Path $sourceBucketPath "$Key.dat"
    if (Test-Path $jsonPath) { $sourceFile = $jsonPath }
    elseif (Test-Path $datPath) { $sourceFile = $datPath }
    else {
        throw "Object with key '$Key' not found in bucket '$Bucket'"
    }

    $destBucketPath = Ensure-BucketExists -Name $DestinationBucket -Path $Path
    $destJsonPath = Join-Path $destBucketPath "${safeDestKey}.json"
    $destDatPath = Join-Path $destBucketPath "${safeDestKey}.dat"

    if ((Test-Path $destJsonPath) -or (Test-Path $destDatPath)) {
        throw "Object with key '$safeDestKey' already exists in bucket '$DestinationBucket'. Use a different key."
    }

    $ext = [System.IO.Path]::GetExtension($sourceFile)
    $destFile = Join-Path $destBucketPath "${safeDestKey}${ext}"

    Copy-Item -Path $sourceFile -Destination $destFile -Force
    Remove-Item -Path $sourceFile -Force

    Write-Verbose "Moved [$Bucket/$Key] to [$DestinationBucket/$safeDestKey]"

    if ($PassThru) {
        [PSCustomObject]@{
            SourceBucket = $Bucket
            SourceKey = $Key
            DestinationBucket = $DestinationBucket
            DestinationKey = $safeDestKey
            FilePath = $destFile
        }
    }
    elseif (-not $Quiet) {
        Write-Host "Moved '$Key' from '$Bucket' to '$DestinationBucket/$safeDestKey'" -ForegroundColor Green
    }
}

function Export-Bucket {
    <#
    .SYNOPSIS
    Exports a bucket to a single archive file.
    .DESCRIPTION
    Serializes all objects in a bucket to a single JSON or CLIXML archive file.
    Includes object metadata (_BucketName, _BucketKey) for easy restoration.
    .PARAMETER Bucket
    Bucket name to export. Supports wildcards.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER OutputFile
    Path to the output archive file.
    .PARAMETER AsJson
    Export as JSON archive (default is CLIXML/PSSerializer).
    .PARAMETER Quiet
    Suppress all output.
    .EXAMPLE
    Export-Bucket -Bucket users -OutputFile "./users-backup.clixml"
    .EXAMPLE
    Export-Bucket -Bucket "config*" -OutputFile "./config-backup.json" -AsJson
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Bucket,

        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$OutputFile,

        [switch]$AsJson,

        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    $allObjects = @()
    $exportedBuckets = 0
    $exportedObjects = 0

    foreach ($b in $Bucket) {
        $objects = Get-BucketObject -Bucket $b -Path $Path
        if ($objects) {
            $allObjects += $objects
            $exportedBuckets++
            $exportedObjects += @($objects).Count
        }
    }

    if ($allObjects.Count -eq 0) {
        Write-Warning "No objects found to export for buckets: $($Bucket -join ', ')"
        return
    }

    $outputDir = [System.IO.Path]::GetDirectoryName((Resolve-SafePath -Path $OutputFile))
    if (-not (Test-Path $outputDir)) {
        $null = New-Item -Path $outputDir -ItemType Directory -Force
    }

    if ($AsJson) {
        $json = ConvertTo-Json -InputObject $allObjects -Depth 20 -Compress
        [System.IO.File]::WriteAllText($OutputFile, $json, [System.Text.Encoding]::UTF8)
    }
    else {
        $xml = [System.Management.Automation.PSSerializer]::Serialize($allObjects, 5)
        $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
        [System.IO.File]::WriteAllBytes($OutputFile, $rawBytes)
    }

    if (-not $Quiet) {
        Write-Host "Exported $exportedObjects object(s) from $exportedBuckets bucket(s) to '$OutputFile'" -ForegroundColor Green
    }
}

function Import-Bucket {
    <#
    .SYNOPSIS
    Imports objects from an archive file into a bucket.
    .DESCRIPTION
    Reads objects from a CLIXML or JSON archive file and stores them in a bucket.
    Preserves original keys if objects have _BucketKey metadata; otherwise generates new keys.
    .PARAMETER Bucket
    Destination bucket name. Creates the bucket if it doesn't exist.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER InputFile
    Path to the archive file to import.
    .PARAMETER AsJson
    Force import from JSON format (auto-detected by file extension if omitted).
    .PARAMETER Overwrite
    Overwrite existing objects with the same key.
    .PARAMETER Quiet
    Suppress all output.
    .EXAMPLE
    Import-Bucket -Bucket users -InputFile "./users-backup.clixml"
    .EXAMPLE
    Import-Bucket -Bucket config -InputFile "./config-backup.json" -Overwrite
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$InputFile,

        [switch]$AsJson,

        [switch]$Overwrite,

        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    if (-not (Test-Path $InputFile)) {
        throw "Input file '$InputFile' not found"
    }

    $rawBytes = [System.IO.File]::ReadAllBytes($InputFile)
    $useJson = $AsJson -or $InputFile -like "*.json"

    if ($useJson) {
        $content = [System.Text.Encoding]::UTF8.GetString($rawBytes)
        $objects = $content | ConvertFrom-Json
    }
    else {
        try {
            $objects = [System.Management.Automation.PSSerializer]::Deserialize([System.Text.Encoding]::UTF8.GetString($rawBytes))
        }
        catch {
            try {
                $content = [System.Text.Encoding]::UTF8.GetString($rawBytes)
                $objects = [System.Management.Automation.PSSerializer]::Deserialize($content)
            }
            catch {
                throw "Failed to deserialize archive file '$InputFile': $_"
            }
        }
    }

    if ($null -eq $objects) {
        throw "Failed to deserialize archive file '$InputFile'"
    }

    $objectArray = @($objects)
    Write-Verbose "Loaded $($objectArray.Count) objects from '$InputFile'"

    $bucketPath = Ensure-BucketExists -Name $Bucket -Path $Path
    $importedCount = 0
    $skippedCount = 0

    foreach ($obj in $objectArray) {
        $key = if ($obj.PSObject.Properties['_BucketKey']) { $obj._BucketKey } else { [Guid]::NewGuid().ToString() }
        $safeKey = $key -replace '[\\/:\*\?"<>\|\.\[\]]', '_'
        if ([string]::IsNullOrWhiteSpace($safeKey) -or $safeKey -match '^_+$') {
            $safeKey = [Guid]::NewGuid().ToString()
        }

        $jsonPath = Join-Path $bucketPath "${safeKey}.json"
        $datPath = Join-Path $bucketPath "${safeKey}.dat"
        $filePath = if (Test-Path $jsonPath) { $jsonPath } elseif (Test-Path $datPath) { $datPath } else { $null }

        if ($filePath -and -not $Overwrite) {
            Write-Verbose "Object with key '$safeKey' already exists in bucket '$Bucket'. Use -Overwrite to replace."
            $skippedCount++
            continue
        }

        $ext = if ($filePath) { [System.IO.Path]::GetExtension($filePath) } else { ".dat" }
        $finalPath = Join-Path $bucketPath "${safeKey}${ext}"

        if ($ext -eq ".json") {
            $json = ConvertTo-Json -InputObject $obj -Depth 20 -Compress
            [System.IO.File]::WriteAllText($finalPath, $json, [System.Text.Encoding]::UTF8)
        }
        else {
            $xml = [System.Management.Automation.PSSerializer]::Serialize($obj, 5)
            $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
            [System.IO.File]::WriteAllBytes($finalPath, $rawBytes)
        }

        $importedCount++
    }

    if (-not $Quiet) {
        Write-Host "Imported $importedCount object(s) into '$Bucket'" -ForegroundColor Green
        if ($skippedCount -gt 0) {
            Write-Host "  $skippedCount skipped (existing keys)" -ForegroundColor Yellow
        }
    }
}

# Only export public cmdlets — internal functions remain private
Export-ModuleMember -Function @(
    'New-BucketObject',
    'Get-BucketObject',
    'Set-BucketObject',
    'Remove-BucketObject',
    'Get-Bucket',
    'Get-BucketStats',
    'Remove-Bucket',
    'Copy-BucketObject',
    'Rename-BucketObject',
    'Move-BucketObject',
    'Export-Bucket',
    'Import-Bucket'
)
