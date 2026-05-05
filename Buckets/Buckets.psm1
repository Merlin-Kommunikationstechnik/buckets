<#
.SYNOPSIS
    A PowerShell module for file-based PSObject storage using directory-backed buckets.
.DESCRIPTION
    Buckets provides a simple way to store, retrieve, and manage PowerShell objects
    in directory-based collections called "buckets". Objects are automatically serialized
    to binary (default) or JSON format, with auto-fallback to binary when JSON depth
    limits are exceeded.
#>

function Get-DefaultPath {
    return Join-Path $PWD.Path ".buckets"
}

function Get-BucketPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    return Join-Path $Path $Name
}

function Ensure-BucketExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $bucketPath = Get-BucketPath -Name $Name -Path $Path
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

        [int]$Depth = 20,

        [int]$BinaryDepth = 2,

        [switch]$AsTimestamp,

        [switch]$AsJson,

        [switch]$Overwrite,

        [switch]$Quiet
    )

    begin {
        $bucketPath = Ensure-BucketExists -Name $Bucket -Path $Path
        $extension = if ($AsJson) { ".json" } else { ".dat" }
        $savedCount = 0
        $warningCount = 0
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
                    $warningCount++
                    $index++
                    continue
                }
                $safeKey = $keyValue -replace '[\\/:\*\?"<>\|\.\[\]]', '_'
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
                $warningCount++
                $index++
                continue
            }

            $writeSuccess = $false
            if ($AsJson) {
                $warnVar = $null
                $json = ConvertTo-Json -InputObject $item -Depth $Depth -Compress -WarningAction SilentlyContinue -WarningVariable warnVar
                if ($warnVar -and $warnVar[0] -like "*truncated*") {
                    try {
                        $bytes = [System.Management.Automation.PSSerializer]::Serialize($item, $BinaryDepth)
                        $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bytes))
                        $filePath = [System.IO.Path]::ChangeExtension($filePath, ".dat")
                        [System.IO.File]::WriteAllText($filePath, $encoded, [System.Text.Encoding]::UTF8)
                        Write-Verbose "Object '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' exceeds JSON depth $Depth, saved as binary (.dat)"
                        $warningCount++
                        $writeSuccess = $true
                    }
                    catch {
                        Write-Verbose "Failed to serialize object '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' as binary: $_"
                        $warningCount++
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
                        $bytes = [System.Management.Automation.PSSerializer]::Serialize($item, $currentDepth)
                        $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bytes))
                        [System.IO.File]::WriteAllText($filePath, $encoded, [System.Text.Encoding]::UTF8)
                        $serialized = $true
                        if ($currentDepth -gt $BinaryDepth) {
                            Write-Verbose "Binary serialization required depth $currentDepth (default: $BinaryDepth)"
                            $warningCount++
                        }
                    }
                    catch {
                        $currentDepth++
                    }
                }
                if (-not $serialized) {
                    Write-Verbose "Failed to serialize object with key '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' at any depth"
                    $warningCount++
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
            Write-Host "Saved $savedCount object(s) to '$Bucket'" -ForegroundColor Green
            if ($warningCount -gt 0) {
                Write-Host "  $warningCount warning(s)" -ForegroundColor Yellow
            }
        }
    }
}

function Read-BucketFile {
    param(
        [System.IO.FileInfo]$File
    )

    $extension = $File.Extension
    $content = [System.IO.File]::ReadAllText($File.FullName, [System.Text.Encoding]::UTF8)

    if ($extension -eq ".dat") {
        $bytes = [System.Convert]::FromBase64String($content)
        $xml = [System.Text.Encoding]::UTF8.GetString($bytes)
        return [System.Management.Automation.PSSerializer]::Deserialize($xml)
    }
    else {
        return $content | ConvertFrom-Json
    }
}

function Get-ObjectFiles {
    param(
        [string]$BucketPath,

        [string]$Key
    )

    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $jsonFile = Get-ChildItem -Path $BucketPath -Filter "$Key.json" -ErrorAction SilentlyContinue
        if ($jsonFile) { return $jsonFile }
        return Get-ChildItem -Path $BucketPath -Filter "$Key.dat" -ErrorAction SilentlyContinue
    }
    else {
        $jsonFiles = Get-ChildItem -Path $BucketPath -Filter "*.json" -ErrorAction SilentlyContinue
        $datFiles = Get-ChildItem -Path $BucketPath -Filter "*.dat" -ErrorAction SilentlyContinue
        return @($jsonFiles) + @($datFiles)
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

        foreach ($file in $files) {
            $obj = Read-BucketFile -File $file

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
    Replaces an existing object file with new data. Preserves the storage format (JSON or binary)
    of the existing file unless -AsJson forces a format change. If JSON serialization exceeds
    the depth limit, the object automatically falls back to binary format.
    .PARAMETER InputObject
    The updated object to store. Accepts pipeline input. Pipeline objects with _BucketName and _BucketKey metadata auto-resolve bucket and key.
    .PARAMETER Bucket
    Name of the bucket containing the object. Auto-resolved from pipeline metadata if omitted.
    .PARAMETER Key
    Object key to update. Auto-resolved from pipeline metadata if omitted.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Depth
    Maximum depth for JSON serialization. Default: 20.
    .PARAMETER BinaryDepth
    Maximum depth for binary (PSSerializer) serialization. Default: 2.
    .PARAMETER AsJson
    Force JSON format for the updated file.
    .PARAMETER Quiet
    Suppress all output. No summary.
    .PARAMETER PassThru
    Return the updated object metadata. Default: $true.
    .OUTPUTS
    PSCustomObject with Bucket, Key, and FilePath properties (unless -Quiet is used).
    .EXAMPLE
    # Pipeline: modifies retrieved object and saves it back (auto-detects bucket/key)
    Get-BucketObject -Bucket users -Key "Alice" | ForEach-Object { $_.Age = 31; $_ } | Set-BucketObject
    .EXAMPLE
    # Explicit parameters
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

        [int]$Depth = 20,

        [int]$BinaryDepth = 2,

        [switch]$AsJson,

        [switch]$Quiet
    )

    begin {
        $bucketPath = $null
        $savedCount = 0
        $useVerbose = $VerbosePreference -eq 'Continue'
        $useQuiet = $Quiet.IsPresent
    }

    process {
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

        if ($null -eq $bucketPath) {
            if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
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

        $writeSuccess = $false
        if ($useJson) {
            $warnVar = $null
            $json = ConvertTo-Json -InputObject $InputObject -Depth $Depth -Compress -WarningAction SilentlyContinue -WarningVariable warnVar
            if ($warnVar -and $warnVar[0] -like "*truncated*") {
                try {
                    $bytes = [System.Management.Automation.PSSerializer]::Serialize($InputObject, $BinaryDepth)
                    $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bytes))
                    $filePath = [System.IO.Path]::ChangeExtension($filePath, ".dat")
                    [System.IO.File]::WriteAllText($filePath, $encoded, [System.Text.Encoding]::UTF8)
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
                    $bytes = [System.Management.Automation.PSSerializer]::Serialize($InputObject, $currentDepth)
                    $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bytes))
                    [System.IO.File]::WriteAllText($filePath, $encoded, [System.Text.Encoding]::UTF8)
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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [string]$Path,

        [string]$Key,

        [switch]$All,

        [switch]$PassThru
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path

    if (-not (Test-Path $bucketPath)) {
        Write-Verbose "Bucket '$Bucket' not found at '$bucketPath'"
        return
    }

    if ($All) {
        $jsonFiles = Get-ChildItem -Path $bucketPath -Filter "*.json" -ErrorAction SilentlyContinue
        $datFiles = Get-ChildItem -Path $bucketPath -Filter "*.dat" -ErrorAction SilentlyContinue
        $allFiles = @($jsonFiles) + @($datFiles)

        if ($allFiles.Count -eq 0) {
            Write-Verbose "Bucket '$Bucket' is already empty"
            return
        }

        $allFiles | Remove-Item -Force

        if ($PassThru) {
            foreach ($f in $allFiles) {
                [PSCustomObject]@{
                    Bucket   = $Bucket
                    Key      = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                    FilePath = $f.FullName
                }
            }
        }
        else {
            Write-Verbose "Removed $($allFiles.Count) object(s) from bucket '$Bucket'"
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Key)) {
        $jsonPath = Join-Path $bucketPath "$Key.json"
        $datPath = Join-Path $bucketPath "$Key.dat"

        $found = $false
        if (Test-Path $jsonPath) {
            if ($PassThru) {
                [PSCustomObject]@{
                    Bucket   = $Bucket
                    Key      = $Key
                    FilePath = $jsonPath
                }
            }
            Remove-Item -Path $jsonPath -Force
            $found = $true
        }
        elseif (Test-Path $datPath) {
            if ($PassThru) {
                [PSCustomObject]@{
                    Bucket   = $Bucket
                    Key      = $Key
                    FilePath = $datPath
                }
            }
            Remove-Item -Path $datPath -Force
            $found = $true
        }

        if (-not $found) {
            Write-Warning "Object with key '$Key' not found in bucket '$Bucket'"
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

    if (-not (Test-Path $Path)) {
        return
    }

    $buckets = Get-ChildItem -Path $Path -Directory

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $buckets = $buckets | Where-Object { $_.Name -like "*$Name*" }
    }

    $buckets | ForEach-Object {
        $jsonCount = (Get-ChildItem -Path $_.FullName -Filter "*.json" -ErrorAction SilentlyContinue).Count
        $datCount = (Get-ChildItem -Path $_.FullName -Filter "*.dat" -ErrorAction SilentlyContinue).Count
        $count = $jsonCount + $datCount
        [PSCustomObject]@{
            Name       = $_.Name
            Path       = $_.FullName
            ObjectCount = if ($count) { $count } else { 0 }
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
    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path

    if (-not (Test-Path $bucketPath)) {
        Write-Warning "Bucket '$Bucket' not found at '$bucketPath'"
        return
    }

    $jsonFiles = Get-ChildItem -Path $bucketPath -Filter "*.json" -ErrorAction SilentlyContinue
    $datFiles = Get-ChildItem -Path $bucketPath -Filter "*.dat" -ErrorAction SilentlyContinue
    $files = @($jsonFiles) + @($datFiles)
    $fileObjects = $files | ForEach-Object { $_ }

    $totalSize = ($fileObjects | Measure-Object -Property Length -Sum).Sum

    [PSCustomObject]@{
        Name         = $Bucket
        Path         = $bucketPath
        ObjectCount  = $fileObjects.Count
        TotalSize    = if ($totalSize) { "$([math]::Round($totalSize / 1KB, 2)) KB" } else { "0 KB" }
        OldestObject = if ($fileObjects) { ($fileObjects | Sort-Object CreationTime | Select-Object -First 1).CreationTime } else { $null }
        NewestObject = if ($fileObjects) { ($fileObjects | Sort-Object CreationTime -Descending | Select-Object -First 1).CreationTime } else { $null }
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

    $allBuckets = Get-Bucket -Path $Path

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

Remove-Item -Path Alias:New-BucketObject -ErrorAction SilentlyContinue
Remove-Item -Path Alias:Get-BucketObject -ErrorAction SilentlyContinue
