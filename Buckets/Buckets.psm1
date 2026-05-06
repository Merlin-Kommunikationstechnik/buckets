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

# Dynamic argument completer for -Bucket parameter
# Registered via Register-ArgumentCompleter at module load (see bottom of file)
function Get-BucketNameCompletions {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $path = if ($fakeBoundParameters.ContainsKey('Path')) { $fakeBoundParameters['Path'] } else { Get-DefaultPath }
    if (-not [System.IO.Directory]::Exists($path)) { return }

    $dirs = [System.IO.DirectoryInfo]::new($path).GetDirectories("$wordToComplete*")
    $dirs | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            $_.Name,
            $_.Name,
            'ParameterValue',
            $_.Name
        )
    }
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
    if (-not [System.IO.Directory]::Exists($bucketPath)) {
        $null = [System.IO.Directory]::CreateDirectory($bucketPath)
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
    (.dat) using PSSerializer for full .NET type preservation. Use -AsJson for
    human-readable JSON format. If JSON serialization fails on complex types,
    the object automatically falls back to binary format.
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
    # Save users with Name as the key
    New-BucketObject -Bucket users -InputObject $users -Key Name

    .EXAMPLE
    # Save config as JSON
    New-BucketObject -Bucket config -InputObject $config -Key _Id -AsJson

    .EXAMPLE
    # Save metrics keyed by Hour
    New-BucketObject -Bucket metrics -InputObject $metrics -Key Hour

    .EXAMPLE
    # Save logs with unique IDs, silent mode
    New-BucketObject -Bucket logs -InputObject $logEntries -Key Id -Quiet

    .EXAMPLE
    # Overwrite existing object
    New-BucketObject -Bucket users -InputObject @{ Name = "Alice"; Email = "alice@new.com"; Role = "manager"; Active = $true } -Key Name -Overwrite
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
        $fallbackCount = 0
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

            if ([System.IO.File]::Exists($filePath) -and -not $Overwrite) {
                Write-Verbose "Object with key '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' already exists in bucket '$Bucket'. Use -Overwrite to replace."
                $skippedCount++
                $index++
                continue
            }

            $writeSuccess = $false
            if ($AsJson) {
                try {
                    $json = ConvertTo-Json -InputObject $item -Depth $Depth -Compress -WarningAction SilentlyContinue
                    [System.IO.File]::WriteAllText($filePath, $json, [System.Text.Encoding]::UTF8)
                    $writeSuccess = $true
                }
                catch {
                    try {
                        $xml = [System.Management.Automation.PSSerializer]::Serialize($item, $BinaryDepth)
                        $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                        $filePath = [System.IO.Path]::ChangeExtension($filePath, ".dat")
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
                        Write-Verbose "Object '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' incompatible with JSON, saved as binary (.dat)"
                        $fallbackCount++
                        $writeSuccess = $true
                    }
                    catch {
                        Write-Verbose "Failed to serialize object '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' as binary: $_"
                        $failedCount++
                    }
                }
            }
            else {
                $currentDepth = $BinaryDepth
                $serialized = $false
                while (-not $serialized -and $currentDepth -le 10) {
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
                            $fallbackCount++
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
            if ($fallbackCount -gt 0) {
                Write-Host "  $fallbackCount required auto-incremented depth or binary fallback" -ForegroundColor DarkYellow
            }
            if ($failedCount -gt 0) {
                Write-Host "  $failedCount failed to serialize" -ForegroundColor Red
            }
        }
    }
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

            if ([System.IO.File]::Exists($filePath) -and -not $Overwrite) {
                Write-Verbose "Object with key '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' already exists in bucket '$Bucket'. Use -Overwrite to replace."
                $skippedCount++
                $index++
                continue
            }

            $writeSuccess = $false
            if ($AsBinary) {
                $currentDepth = $BinaryDepth
                $serialized = $false
                while (-not $serialized -and $currentDepth -le 10) {
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
                            $fallbackCount++
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
            else {
                try {
                    $json = ConvertTo-Json -InputObject $item -Depth $Depth -Compress -WarningAction SilentlyContinue
                    [System.IO.File]::WriteAllText($filePath, $json, [System.Text.Encoding]::UTF8)
                    $writeSuccess = $true
                }
                catch {
                    try {
                        $xml = [System.Management.Automation.PSSerializer]::Serialize($item, $BinaryDepth)
                        $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                        $filePath = [System.IO.Path]::ChangeExtension($filePath, ".dat")
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
                        Write-Verbose "Object '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' incompatible with JSON, saved as binary (.dat)"
                        $fallbackCount++
                        $writeSuccess = $true
                    }
                    catch {
                        Write-Verbose "Failed to serialize object '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' as binary: $_"
                        $failedCount++
                    }
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
            if ($fallbackCount -gt 0) {
                Write-Host "  $fallbackCount required binary fallback" -ForegroundColor DarkYellow
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

    if ($null -eq $File -or -not [System.IO.File]::Exists($File.FullName)) { return $null }

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
        $di = [System.IO.DirectoryInfo]::new($BucketPath)
        $target = $Key.ToLowerInvariant()
        foreach ($f in @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))) {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ($base.ToLowerInvariant() -eq $target) { return @($f) }
        }
        return @()
    }
    else {
        $di = [System.IO.DirectoryInfo]::new($BucketPath)
        return @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))
    }
}

function Find-ObjectFile {
    param(
        [string]$BucketPath,
        [string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($Key) -or -not [System.IO.Directory]::Exists($BucketPath)) { return $null }

    $di = [System.IO.DirectoryInfo]::new($BucketPath)
    $target = $Key.ToLowerInvariant()
    foreach ($f in @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        if ($base.ToLowerInvariant() -eq $target) { return $f }
    }
    return $null
}

function Get-ObjectProperty {
    param(
        [PSObject]$Object,
        [string]$PropertyName
    )

    $hasValue = $false
    $value = $null

    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($PropertyName)) {
            $hasValue = $true
            $value = $Object[$PropertyName]
        }
    }
    elseif ($null -ne $Object.PSObject.Properties[$PropertyName]) {
        $hasValue = $true
        $value = $Object.$PropertyName
    }

    return @{ HasValue = $hasValue; Value = $value }
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
    Specific object key to retrieve. Looks for both .json and .dat files. Case-insensitive.
    .PARAMETER Match
    Hashtable of property-value pairs for exact-match filtering. All pairs must match. Supports $null values.
    .PARAMETER Filter
    ScriptBlock for custom filtering. Use $_ to reference object properties (e.g., { $_.Age -gt 30 }).
    .PARAMETER First
    Return only the first N objects.
    .PARAMETER Skip
    Skip the first N objects before returning results.
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
    .EXAMPLE
    Get-BucketObject -First 10 -Skip 20
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 1)]
        [string[]]$Bucket,

        [string]$Path,

        [Parameter(Position = 0)]
        [string]$Key,

        [hashtable]$Match,

        [scriptblock]$Filter,

        [int]$First,

        [int]$Skip
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
        if ([System.IO.Directory]::Exists($Path)) {
            $bucketPaths += [System.IO.DirectoryInfo]::new($Path).GetDirectories() | ForEach-Object { $_.FullName }
        }
    }

    $emitted = 0
    $skipped = 0

    foreach ($bucketPath in $bucketPaths) {
        if (-not [System.IO.Directory]::Exists($bucketPath)) { continue }
        if ($First -gt 0 -and $emitted -ge $First) { break }

        $bucketName = Split-Path $bucketPath -Leaf

        $files = Get-ObjectFiles -BucketPath $bucketPath -Key $Key

        foreach ($file in $files) {
            if ($null -eq $file -or -not [System.IO.File]::Exists($file.FullName)) { continue }
            if ($First -gt 0 -and $emitted -ge $First) { break }

            $obj = Read-BucketFile -File $file
            if ($null -eq $obj) { continue }

            if ($Match) {
                $hit = $true
                foreach ($kvp in $Match.GetEnumerator()) {
                    $propName = $kvp.Name
                    $expectedValue = $kvp.Value
                    $prop = Get-ObjectProperty -Object $obj -PropertyName $propName

                    $matchesValue = if ($null -eq $expectedValue) {
                        -not $prop.HasValue
                    }
                    elseif (-not $prop.HasValue) {
                        $false
                    }
                    else {
                        $prop.Value -eq $expectedValue
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

            if ($Skip -gt 0 -and $skipped -lt $Skip) {
                $skipped++
                continue
            }

            $obj | Add-Member -NotePropertyName "_BucketName" -NotePropertyValue $bucketName -Force
            $obj | Add-Member -NotePropertyName "_BucketKey" -NotePropertyValue ([System.IO.Path]::GetFileNameWithoutExtension($file.Name)) -Force
            $obj | Add-Member -NotePropertyName "_BucketFile" -NotePropertyValue $file.FullName -Force
            Write-Output $obj
            $emitted++
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
    $user = Get-BucketObject -Bucket users -Key "Alice"
    $user.Role = "manager"
    $user | Set-BucketObject

    .EXAMPLE
    # Partial update: only specified properties are merged into the existing object
    Set-BucketObject -InputObject @{ Role = "admin" } -Bucket users -Key Name

    .EXAMPLE
    # Quiet mode with no output
    Get-BucketObject -Bucket logs -Key "log-001" | ForEach-Object { $_.Level = "INFO"; $_ } | Set-BucketObject -Quiet
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
            if (-not [System.IO.Directory]::Exists($bucketPath)) {
                throw "Bucket '$Bucket' not found at '$bucketPath'"
            }
        }

        $file = Find-ObjectFile -BucketPath $bucketPath -Key $Key
        if ($null -eq $file) {
            throw "Object with key '$Key' not found in bucket '$Bucket'"
        }

        $filePath = $file.FullName
        $useJson = $file.Extension -eq ".json" -or $AsJson

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
            try {
                $json = ConvertTo-Json -InputObject $InputObject -Depth $Depth -Compress -WarningAction SilentlyContinue
                [System.IO.File]::WriteAllText($filePath, $json, [System.Text.Encoding]::UTF8)
                $writeSuccess = $true
            }
            catch {
                try {
                    $xml = [System.Management.Automation.PSSerializer]::Serialize($InputObject, $BinaryDepth)
                    $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                    if (Test-Path $filePath) { Remove-Item $filePath -Force }
                    $filePath = [System.IO.Path]::ChangeExtension($filePath, ".dat")
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
                    Write-Verbose "Object '$Key' incompatible with JSON, saved as binary (.dat)"
                    $writeSuccess = $true
                }
                catch {
                    throw "Failed to serialize object '$Key' as binary: $_"
                }
            }
        }
        else {
            $currentDepth = $BinaryDepth
            $serialized = $false
            while (-not $serialized -and $currentDepth -le 10) {
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
    object, -All to clear the entire bucket, or -Match/-Filter for bulk deletion.
    .PARAMETER Bucket
    Name of the bucket containing the object(s) to remove.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Key
    Object key to remove. Looks for both .json and .dat files. Case-insensitive.
    .PARAMETER All
    Remove all objects from the bucket.
    .PARAMETER Match
    Hashtable of property-value pairs for bulk deletion. All pairs must match. Supports $null values.
    .PARAMETER Filter
    ScriptBlock for custom bulk deletion. Use $_ to reference object properties.
    .PARAMETER PassThru
    Return metadata for removed objects.
    .EXAMPLE
    # Remove a single log entry by Id
    Remove-BucketObject -Bucket logs -Key "log-003"

    .EXAMPLE
    # Remove all objects from a bucket
    Remove-BucketObject -Bucket temp -All -PassThru

    .EXAMPLE
    # Remove all inactive users
    Remove-BucketObject -Bucket users -Match @{ Active = $false } -PassThru

    .EXAMPLE
    # Remove objects matching a scriptblock
    Remove-BucketObject -Bucket orders -Filter { $_.Status -eq "cancelled" }

    .EXAMPLE
    # Preview removal without executing
    Remove-BucketObject -Bucket users -Key "Charlie" -WhatIf
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

        [Parameter(ParameterSetName = 'ByFilter')]
        [hashtable]$Match,

        [Parameter(ParameterSetName = 'ByFilter')]
        [scriptblock]$Filter,

        [switch]$PassThru,

        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path

    if (-not [System.IO.Directory]::Exists($bucketPath)) {
        Write-Verbose "Bucket '$Bucket' not found at '$bucketPath'"
        return
    }

    if ($All) {
        $di = [System.IO.DirectoryInfo]::new($bucketPath)
        $allFiles = @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))

        if ($allFiles.Count -eq 0) {
            Write-Verbose "Bucket '$Bucket' is already empty"
            return
        }

        $target = "$($allFiles.Count) object(s) from bucket '$Bucket'"
        if ($PSCmdlet.ShouldProcess($target, "Remove-BucketObject")) {
            $allFiles | ForEach-Object { [System.IO.File]::Delete($_.FullName) }
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
        $file = Find-ObjectFile -BucketPath $bucketPath -Key $Key

        if ($null -eq $file) {
            Write-Warning "Object with key '$Key' not found in bucket '$Bucket'"
        }
        elseif ($PSCmdlet.ShouldProcess("object '$Key' from bucket '$Bucket'", "Remove-BucketObject")) {
            if ($PassThru) {
                [PSCustomObject]@{
                    Bucket   = $Bucket
                    Key      = $Key
                    FilePath = $file.FullName
                }
            }
            [System.IO.File]::Delete($file.FullName)
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'ByFilter') {
        $di = [System.IO.DirectoryInfo]::new($bucketPath)
        $allFiles = @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))

        if ($allFiles.Count -eq 0) {
            Write-Verbose "Bucket '$Bucket' is already empty"
            return
        }

        $matchedFiles = @()
        foreach ($file in $allFiles) {
            $obj = Read-BucketFile -File $file
            if ($null -eq $obj) { continue }

            if ($Match) {
                $hit = $true
                foreach ($kvp in $Match.GetEnumerator()) {
                    $propName = $kvp.Name
                    $expectedValue = $kvp.Value
                    $prop = Get-ObjectProperty -Object $obj -PropertyName $propName

                    $matchesValue = if ($null -eq $expectedValue) {
                        -not $prop.HasValue
                    }
                    elseif (-not $prop.HasValue) {
                        $false
                    }
                    else {
                        $prop.Value -eq $expectedValue
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

            $matchedFiles += $file
        }

        if ($matchedFiles.Count -eq 0) {
            Write-Verbose "No objects matched the filter criteria in bucket '$Bucket'"
            return
        }

        $target = "$($matchedFiles.Count) matching object(s) from bucket '$Bucket'"
        if ($PSCmdlet.ShouldProcess($target, "Remove-BucketObject")) {
            foreach ($f in $matchedFiles) {
                if ($PassThru) {
                    [PSCustomObject]@{
                        Bucket   = $Bucket
                        Key      = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                        FilePath = $f.FullName
                    }
                }
                [System.IO.File]::Delete($f.FullName)
            }
        }
        elseif (-not $WhatIfPreference) {
            Write-Verbose "Would remove $($matchedFiles.Count) object(s) from bucket '$Bucket'"
        }
    }
    else {
        throw "Specify either -Key, -All, or -Match/-Filter"
    }
}

function Get-BucketKeys {
    <#
    .SYNOPSIS
    Lists object keys in a bucket without deserializing objects.
    .DESCRIPTION
    Fast key enumeration that reads filenames only, avoiding the overhead of
    deserializing object data. Returns keys with their file format and size.
    .PARAMETER Bucket
    Bucket name to scan. If omitted, scans all buckets under -Path. Supports wildcards.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Match
    Filter keys by pattern (wildcard). Case-insensitive.
    .OUTPUTS
    PSCustomObject with Bucket, Key, Format, and Size properties.
    .EXAMPLE
    Get-BucketKeys -Bucket users
    .EXAMPLE
    Get-BucketKeys -Match "*admin*"
    .EXAMPLE
    Get-BucketKeys | Where-Object { $_.Format -eq "json" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Bucket,

        [string]$Path,

        [string]$Match
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    $bucketPaths = @()
    if (-not [string]::IsNullOrWhiteSpace($Bucket)) {
        if ($Bucket -match '[\*\?]') {
            $cachedBuckets = Get-Bucket -Path $Path
            $matched = $cachedBuckets | Where-Object { $_.Name -like $Bucket }
            $bucketPaths += $matched | ForEach-Object { $_.Path }
        }
        else {
            $bucketPaths += Get-BucketPath -Name $Bucket -Path $Path
        }
    }
    else {
        if ([System.IO.Directory]::Exists($Path)) {
            $bucketPaths += [System.IO.DirectoryInfo]::new($Path).GetDirectories() | ForEach-Object { $_.FullName }
        }
    }

    foreach ($bucketPath in $bucketPaths) {
        if (-not [System.IO.Directory]::Exists($bucketPath)) { continue }

        $bucketName = Split-Path $bucketPath -Leaf
        $di = [System.IO.DirectoryInfo]::new($bucketPath)
        $files = @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))

        foreach ($f in $files) {
            $key = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)

            if (-not [string]::IsNullOrWhiteSpace($Match) -and $key -notlike $Match) { continue }

            [PSCustomObject]@{
                Bucket = $bucketName
                Key    = $key
                Format = if ($f.Extension -eq ".json") { "json" } else { "dat" }
                Size   = $f.Length
            }
        }
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

    if (-not [System.IO.Directory]::Exists($Path)) {
        return
    }

    $buckets = @([System.IO.DirectoryInfo]::new($Path).GetDirectories())

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $buckets = $buckets | Where-Object { $_.Name -like "*$Name*" }
    }

    $buckets | ForEach-Object {
        $bucketDir = $_
        $datFiles = [System.IO.Directory]::GetFiles($bucketDir.FullName, "*.dat")
        $jsonFiles = [System.IO.Directory]::GetFiles($bucketDir.FullName, "*.json")
        [PSCustomObject]@{
            Name        = $bucketDir.Name
            Path        = $bucketDir.FullName
            ObjectCount = $datFiles.Length + $jsonFiles.Length
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

    if (-not [System.IO.Directory]::Exists($bucketPath)) {
        Write-Warning "Bucket '$Bucket' not found at '$bucketPath'"
        return
    }

    $di = [System.IO.DirectoryInfo]::new($bucketPath)
    $datFiles = @($di.GetFiles("*.dat"))
    $jsonFiles = @($di.GetFiles("*.json"))
    $fileObjects = $datFiles + $jsonFiles

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
    Uses standard -Confirm/-WhatIf support (SupportsShouldProcess).
    -Confirm:$false skips the confirmation prompt.
    .PARAMETER Bucket
    Bucket name(s) or wildcard patterns to remove. Supports glob-style wildcards (*, ?).
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER WhatIf
    Preview which buckets would be removed without actually deleting them.
    .PARAMETER Confirm
    Prompt for confirmation before removal. Default: prompts (ConfirmImpact = High).
    Use -Confirm:$false to skip.
    .EXAMPLE
    Remove-Bucket -Bucket users
    .EXAMPLE
    Remove-Bucket -Bucket "temp*" -Confirm:$false
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

    $allBuckets = @()
    if ([System.IO.Directory]::Exists($Path)) {
        $allBuckets = @([System.IO.DirectoryInfo]::new($Path).GetDirectories()) | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Path = $_.FullName
            }
        }
    }

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
        $subDirs = @($di.GetDirectories())
        if ($subDirs.Count -gt 0) {
            $skippedBuckets += [PSCustomObject]@{ Name = $m.Name; Reason = "contains subdirectories" }
            continue
        }

        $allFiles = @($di.GetFiles())
        $otherFiles = @($allFiles | Where-Object { $_.Extension -notin ".dat", ".json" })

        if ($otherFiles.Count -gt 0) {
            $skippedBuckets += [PSCustomObject]@{
                Name   = $m.Name
                Reason = "contains $($otherFiles.Count) non-bucket file(s): $($otherFiles.Name -join ', ')"
            }
            continue
        }

        $datFiles = @($di.GetFiles("*.dat"))
        $jsonFiles = @($di.GetFiles("*.json"))
        $stats = Get-BucketStats -Bucket $m.Name -Path $Path
        $removable += [PSCustomObject]@{
            Name       = $m.Name
            Objects    = if ($stats) { $stats.ObjectCount } else { 0 }
            Size       = if ($stats) { $stats.TotalSize } else { "0 KB" }
            Path       = $m.Path
        }
    }

    if ($removable.Count -eq 0 -and $skippedBuckets.Count -eq 0) { return }

    if ($WhatIfPreference) {
        if ($removable.Count -gt 0) {
            Write-Host "  What if: Remove the following bucket(s):" -ForegroundColor Yellow
            foreach ($r in $removable) {
                Write-Host "    $($r.Name) ($($r.Objects) objects, $($r.Size))" -ForegroundColor DarkGray
            }
        }
        if ($skippedBuckets.Count -gt 0) {
            Write-Host "`n  Skipped:" -ForegroundColor Yellow
            foreach ($s in $skippedBuckets) {
                Write-Host "    $($s.Name) — $($s.Reason)" -ForegroundColor Red
            }
        }
        return
    }

    if ($removable.Count -eq 0 -and $skippedBuckets.Count -eq 0) { return }

    $removedCount = 0
    foreach ($r in $removable) {
        $finalDi = [System.IO.DirectoryInfo]::new($r.Path)
        $finalFiles = @($finalDi.GetFiles())
        $finalOther = @($finalFiles | Where-Object { $_.Extension -notin ".dat", ".json" })
        if ($finalOther.Count -gt 0) {
            Write-Warning "Bucket '$($r.Name)' now contains non-bucket files, aborting: $($finalOther.Name -join ', ')"
            continue
        }
        $finalDirs = @($finalDi.GetDirectories())
        if ($finalDirs.Count -gt 0) {
            Write-Warning "Bucket '$($r.Name)' now contains subdirectories, aborting"
            continue
        }

        $target = "bucket '$($r.Name)' ($($r.Objects) object(s), $($r.Size))"
        if ($PSCmdlet.ShouldProcess($target, "Remove-Bucket")) {
            Write-Verbose "Removing bucket '$($r.Name)' ($($r.Objects) object(s))"
            [System.IO.Directory]::Delete($r.Path, $true)
            $cacheKeys = @($script:BucketPathCache.Keys) | Where-Object { $_ -like "*|$($r.Name)" }
            foreach ($ck in $cacheKeys) { $script:BucketPathCache.Remove($ck) }
            $removedCount++
        }
    }

    if ($removedCount -gt 0) {
        Write-Host "  Removed $removedCount bucket(s)" -ForegroundColor Green
    }
    if ($skippedBuckets.Count -gt 0) {
        Write-Host "`n  Skipped:" -ForegroundColor Yellow
        foreach ($s in $skippedBuckets) {
            Write-Host "    $($s.Name) — $($s.Reason)" -ForegroundColor Red
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
    if (-not [System.IO.Directory]::Exists($sourceBucketPath)) {
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

    $sourceFile = Find-ObjectFile -BucketPath $sourceBucketPath -Key $Key
    if ($null -eq $sourceFile) {
        throw "Object with key '$Key' not found in bucket '$Bucket'"
    }

    $destBucketPath = Ensure-BucketExists -Name $DestinationBucket -Path $Path
    $destJsonPath = Join-Path $destBucketPath "${safeDestKey}.json"
    $destDatPath = Join-Path $destBucketPath "${safeDestKey}.dat"

    if ([System.IO.File]::Exists($destJsonPath) -or [System.IO.File]::Exists($destDatPath)) {
        throw "Object with key '$safeDestKey' already exists in bucket '$DestinationBucket'. Use a different key."
    }

    $ext = $sourceFile.Extension
    $destFile = Join-Path $destBucketPath "${safeDestKey}${ext}"

    [System.IO.File]::Copy($sourceFile, $destFile)
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
    if (-not [System.IO.Directory]::Exists($bucketPath)) {
        throw "Bucket '$Bucket' not found at '$bucketPath'"
    }

    $safeNewKey = $NewKey -replace '[\\/:\*\?"<>\|\.\[\]]', '_'
    if ([string]::IsNullOrWhiteSpace($safeNewKey) -or $safeNewKey -match '^_+$') {
        throw "New key '$NewKey' is invalid after sanitization"
    }

    $sourceFile = Find-ObjectFile -BucketPath $bucketPath -Key $Key
    if ($null -eq $sourceFile) {
        throw "Object with key '$Key' not found in bucket '$Bucket'"
    }

    $ext = $sourceFile.Extension
    $destJsonPath = Join-Path $bucketPath "${safeNewKey}.json"
    $destDatPath = Join-Path $bucketPath "${safeNewKey}.dat"
    if ([System.IO.File]::Exists($destJsonPath) -or [System.IO.File]::Exists($destDatPath)) {
        throw "Object with key '$safeNewKey' already exists in bucket '$Bucket'"
    }

    $destFile = Join-Path $bucketPath "${safeNewKey}${ext}"

    [System.IO.File]::Move($sourceFile, $destFile)
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
    # Archive a log entry to a backup bucket
    Move-BucketObject -Bucket logs -Key "log-004" -DestinationBucket archive

    .EXAMPLE
    # Rename an order within the same bucket
    Move-BucketObject -Bucket orders -Key "ORD-001" -DestinationKey "ORD-legacy-001"
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
    if (-not [System.IO.Directory]::Exists($sourceBucketPath)) {
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

    $sourceFile = Find-ObjectFile -BucketPath $sourceBucketPath -Key $Key
    if ($null -eq $sourceFile) {
        throw "Object with key '$Key' not found in bucket '$Bucket'"
    }

    $destBucketPath = Ensure-BucketExists -Name $DestinationBucket -Path $Path
    $destJsonPath = Join-Path $destBucketPath "${safeDestKey}.json"
    $destDatPath = Join-Path $destBucketPath "${safeDestKey}.dat"

    if ([System.IO.File]::Exists($destJsonPath) -or [System.IO.File]::Exists($destDatPath)) {
        throw "Object with key '$safeDestKey' already exists in bucket '$DestinationBucket'. Use a different key."
    }

    $ext = $sourceFile.Extension
    $destFile = Join-Path $destBucketPath "${safeDestKey}${ext}"

    [System.IO.File]::Copy($sourceFile, $destFile)
    [System.IO.File]::Delete($sourceFile)

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
    .PARAMETER Compress
    Enable GZip compression for CLIXML archives.
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

        [switch]$Compress,

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
    if (-not [System.IO.Directory]::Exists($outputDir)) {
        $null = [System.IO.Directory]::CreateDirectory($outputDir)
    }

    if ($AsJson) {
        $json = ConvertTo-Json -InputObject $allObjects -Depth 20 -Compress
        [System.IO.File]::WriteAllText($OutputFile, $json, [System.Text.Encoding]::UTF8)
    }
    else {
        $xml = [System.Management.Automation.PSSerializer]::Serialize($allObjects, 10)
        $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
        if ($Compress) {
            $ms = [System.IO.MemoryStream]::new()
            $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
            $cs.Write($rawBytes, 0, $rawBytes.Length)
            $cs.Close()
            [System.IO.File]::WriteAllBytes($OutputFile, $ms.ToArray())
        }
        else {
            [System.IO.File]::WriteAllBytes($OutputFile, $rawBytes)
        }
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

        [Parameter(Mandatory = $true)]
        [string]$InputFile,

        [switch]$AsJson,

        [switch]$Overwrite,

        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    if (-not [System.IO.File]::Exists($InputFile)) {
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
            $isCompressed = $rawBytes.Length -ge 2 -and $rawBytes[0] -eq 0x1F -and $rawBytes[1] -eq 0x8B
            if ($isCompressed) {
                $ms = [System.IO.MemoryStream]::new($rawBytes)
                $decompressed = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
                $reader = [System.IO.StreamReader]::new($decompressed)
                $content = $reader.ReadToEnd()
                $reader.Close()
                $decompressed.Close()
                $objects = [System.Management.Automation.PSSerializer]::Deserialize($content)
            }
            else {
                $objects = [System.Management.Automation.PSSerializer]::Deserialize([System.Text.Encoding]::UTF8.GetString($rawBytes))
            }
        }
        catch {
            throw "Failed to deserialize archive file '$InputFile': $_"
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
        $filePath = $null
        if ([System.IO.File]::Exists($jsonPath)) { $filePath = $jsonPath }
        elseif ([System.IO.File]::Exists($datPath)) { $filePath = $datPath }

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
    'Get-BucketKeys',
    'Remove-Bucket',
    'Copy-BucketObject',
    'Rename-BucketObject',
    'Move-BucketObject',
    'Export-Bucket',
    'Import-Bucket'
)

# Tab completion for -Bucket and -DestinationBucket parameters
$script:CompleterBlock = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $path = if ($fakeBoundParameters.ContainsKey('Path')) { $fakeBoundParameters['Path'] } else { Join-Path $PWD.Path ".buckets" }
    if (-not [System.IO.Directory]::Exists($path)) { return }

    [System.IO.DirectoryInfo]::new($path).GetDirectories("$wordToComplete*") | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Name)
    }
}

# Tab completion for -Key parameter (requires -Bucket to be specified)
$script:KeyCompleterBlock = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $bucket = $fakeBoundParameters['Bucket']
    if (-not $bucket) { return }

    $path = if ($fakeBoundParameters.ContainsKey('Path')) { $fakeBoundParameters['Path'] } else { Join-Path $PWD.Path ".buckets" }
    $bucketPath = Join-Path $path $bucket
    if (-not [System.IO.Directory]::Exists($bucketPath)) { return }

    $di = [System.IO.DirectoryInfo]::new($bucketPath)
    $files = $di.GetFiles("$wordToComplete*.dat") + $di.GetFiles("$wordToComplete*.json")

    $files | ForEach-Object {
        $key = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        [System.Management.Automation.CompletionResult]::new($key, $key, 'ParameterValue', "$($_.Extension.TrimStart('.')) key")
    }
}

@('New-BucketObject', 'Get-BucketObject', 'Set-BucketObject', 'Remove-BucketObject',
  'Get-BucketStats', 'Remove-Bucket', 'Copy-BucketObject', 'Rename-BucketObject',
  'Move-BucketObject', 'Export-Bucket', 'Import-Bucket') | ForEach-Object {
    Register-ArgumentCompleter -CommandName $_ -ParameterName Bucket -ScriptBlock $script:CompleterBlock
}

Register-ArgumentCompleter -CommandName Copy-BucketObject -ParameterName DestinationBucket -ScriptBlock $script:CompleterBlock
Register-ArgumentCompleter -CommandName Move-BucketObject -ParameterName DestinationBucket -ScriptBlock $script:CompleterBlock

# Key completion for cmdlets that take a -Key
@('Get-BucketObject', 'Set-BucketObject', 'Remove-BucketObject',
  'Copy-BucketObject', 'Rename-BucketObject', 'Move-BucketObject') | ForEach-Object {
    Register-ArgumentCompleter -CommandName $_ -ParameterName Key -ScriptBlock $script:KeyCompleterBlock
}
