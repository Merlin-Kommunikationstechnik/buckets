$script:DefaultPath = Join-Path $PWD.Path ".buckets"

function Get-BucketPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Path = $script:DefaultPath
    )

    return Join-Path $Path $Name
}

function Ensure-BucketExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Path = $script:DefaultPath
    )

    $bucketPath = Get-BucketPath -Name $Name -Path $Path
    if (-not (Test-Path $bucketPath)) {
        $null = New-Item -Path $bucketPath -ItemType Directory -Force
    }
    return $bucketPath
}

function Save-BucketObject {
    <#
    .SYNOPSIS
    Saves a PSObject to a bucket. Creates the bucket if it doesn't exist.
    .PARAMETER Key
    Property name to use as the object key. The value of this property on each object becomes the filename.
    If omitted, a GUID is used.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]$InputObject,

        [string]$Bucket = "default",

        [string]$Path = $script:DefaultPath,

        [string]$Key,

        [int]$Depth = 20,

        [int]$BinaryDepth = 2,

        [switch]$AsTimestamp,

        [switch]$AsJson
    )

    begin {
        $bucketPath = Ensure-BucketExists -Name $Bucket -Path $Path
        $extension = if ($AsJson) { ".json" } else { ".dat" }
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

        $index = 0
        foreach ($item in $items) {
            if (-not [string]::IsNullOrWhiteSpace($Key)) {
                $keyValue = $item.$Key
                if ($null -eq $keyValue) {
                    Write-Warning "Property '$Key' not found on object, skipping"
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

            if ($AsJson) {
                $warnVar = $null
                $json = ConvertTo-Json -InputObject $item -Depth $Depth -Compress -WarningAction SilentlyContinue -WarningVariable warnVar
            if ($warnVar -and $warnVar[0] -like "*truncated*") {
                    try {
                        $bytes = [System.Management.Automation.PSSerializer]::Serialize($item, $BinaryDepth)
                        $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bytes))
                        $filePath = [System.IO.Path]::ChangeExtension($filePath, ".dat")
                        [System.IO.File]::WriteAllText($filePath, $encoded, [System.Text.Encoding]::UTF8)
                        Write-Warning "Object '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' exceeds JSON depth $Depth, saved as binary (.dat)"
                    }
                    catch {
                        Write-Warning "Failed to serialize object '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' as binary: $_"
                        $index++
                        continue
                    }
                }
                else {
                    [System.IO.File]::WriteAllText($filePath, $json, [System.Text.Encoding]::UTF8)
                }
            }
            else {
                try {
                    $bytes = [System.Management.Automation.PSSerializer]::Serialize($item, $BinaryDepth)
                    $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bytes))
                    [System.IO.File]::WriteAllText($filePath, $encoded, [System.Text.Encoding]::UTF8)
                }
                catch {
                    Write-Warning "Failed to serialize object with key '$([System.IO.Path]::GetFileNameWithoutExtension($filename))': $_"
                    $index++
                    continue
                }
            }

            [PSCustomObject]@{
                Bucket   = $Bucket
                Key      = [System.IO.Path]::GetFileNameWithoutExtension($filename)
                FilePath = $filePath
            }

            $index++
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
    Retrieves objects from a bucket.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Bucket,

        [string]$Path = $script:DefaultPath,

        [string]$Key,

        [hashtable]$Filter,

        [scriptblock]$Where
    )

    $bucketPaths = if ($Bucket -and $Bucket.Count -gt 0) {
        foreach ($b in $Bucket) {
            Get-BucketPath -Name $b -Path $Path
        }
    }
    else {
        if (Test-Path $Path) {
            Get-ChildItem -Path $Path -Directory | ForEach-Object { $_.FullName }
        }
    }

    foreach ($bucketPath in $bucketPaths) {
        if (-not (Test-Path $bucketPath)) { continue }

        $bucketName = Split-Path $bucketPath -Leaf

        $files = Get-ObjectFiles -BucketPath $bucketPath -Key $Key

        foreach ($file in $files) {
            $obj = Read-BucketFile -File $file

            if ($Filter) {
                $match = $true
                foreach ($kvp in $Filter.GetEnumerator()) {
                    if ($obj.$($kvp.Name) -ne $kvp.Value) {
                        $match = $false
                        break
                    }
                }
                if (-not $match) { continue }
            }

            if ($Where) {
                $passed = $null -ne ($obj | Where-Object $Where)
                if (-not $passed) { continue }
            }

            $obj | Add-Member -NotePropertyName "_BucketName" -NotePropertyValue $bucketName -Force
            $obj | Add-Member -NotePropertyName "_BucketKey" -NotePropertyValue ([System.IO.Path]::GetFileNameWithoutExtension($file.Name)) -Force
            $obj | Add-Member -NotePropertyName "_BucketFile" -NotePropertyValue $file.FullName -Force
            Write-Output $obj
        }
    }
}

function Update-BucketObject {
    <#
    .SYNOPSIS
    Updates an existing object in a bucket.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [string]$Path = $script:DefaultPath,

        [int]$Depth = 20,

        [int]$BinaryDepth = 2,

        [switch]$AsJson
    )

    begin {
        $bucketPath = Get-BucketPath -Name $Bucket -Path $Path
        if (-not (Test-Path $bucketPath)) {
            throw "Bucket '$Bucket' not found at '$bucketPath'"
        }
    }

    process {
        $jsonPath = Join-Path $bucketPath "$Key.json"
        $datPath = Join-Path $bucketPath "$Key.dat"

        $filePath = if (Test-Path $jsonPath) { $jsonPath }
        elseif (Test-Path $datPath) { $datPath }
        else {
            throw "Object with key '$Key' not found in bucket '$Bucket'"
        }

        $useJson = $filePath -like "*.json" -or $AsJson

        if ($useJson) {
            $warnVar = $null
            $json = ConvertTo-Json -InputObject $InputObject -Depth $Depth -Compress -WarningAction SilentlyContinue -WarningVariable warnVar
            if ($warnVar -and $warnVar[0] -like "*truncated*") {
                try {
                    $bytes = [System.Management.Automation.PSSerializer]::Serialize($InputObject, $BinaryDepth)
                    $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bytes))
                    $filePath = [System.IO.Path]::ChangeExtension($filePath, ".dat")
                    [System.IO.File]::WriteAllText($filePath, $encoded, [System.Text.Encoding]::UTF8)
                    Write-Warning "Object '$Key' exceeds JSON depth $Depth, saved as binary (.dat)"
                }
                catch {
                    Write-Warning "Failed to serialize object '$Key' as binary: $_"
                    throw
                }
            }
            else {
                [System.IO.File]::WriteAllText($filePath, $json, [System.Text.Encoding]::UTF8)
            }
        }
        else {
            $bytes = [System.Management.Automation.PSSerializer]::Serialize($InputObject, $BinaryDepth)
            $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bytes))
            [System.IO.File]::WriteAllText($filePath, $encoded, [System.Text.Encoding]::UTF8)
        }

        return [PSCustomObject]@{
            Bucket   = $Bucket
            Key      = $Key
            FilePath = $filePath
        }
    }
}

function Remove-BucketObject {
    <#
    .SYNOPSIS
    Removes an object from a bucket.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [string]$Path = $script:DefaultPath,

        [string]$Key,

        [switch]$All
    )

    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path

    if (-not (Test-Path $bucketPath)) {
        return
    }

    if ($All) {
        Get-ChildItem -Path $bucketPath -Filter "*.json" | Remove-Item -Force
        Get-ChildItem -Path $bucketPath -Filter "*.dat" | Remove-Item -Force
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Key)) {
        $jsonPath = Join-Path $bucketPath "$Key.json"
        $datPath = Join-Path $bucketPath "$Key.dat"
        if (Test-Path $jsonPath) {
            Remove-Item -Path $jsonPath -Force
        }
        elseif (Test-Path $datPath) {
            Remove-Item -Path $datPath -Force
        }
        else {
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
    Lists available buckets.
    #>
    [CmdletBinding()]
    param(
        [string]$Path = $script:DefaultPath,

        [string]$Name
    )

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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [string]$Path = $script:DefaultPath
    )

    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path

    if (-not (Test-Path $bucketPath)) {
        throw "Bucket '$Bucket' not found at '$bucketPath'"
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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Bucket,

        [string]$Path = $script:DefaultPath,

        [switch]$Force,

        [switch]$WhatIf
    )

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

    if (-not $Force -and -not $WhatIf) {
        Write-Host "The following bucket(s) will be removed:"
        foreach ($m in $matched) {
            $fileCount = (Get-BucketStats -Bucket $m.Name -Path $Path).ObjectCount
            Write-Host "  '$($m.Name)' ($fileCount object(s)) at $($m.Path)"
        }
        $response = Read-Host "Proceed? (Y/N)"
        if ($response -notmatch '^[yY]') {
            Write-Host "Cancelled"
            return
        }
    }

    foreach ($m in $matched) {
        $fileCount = (Get-BucketStats -Bucket $m.Name -Path $Path).ObjectCount

        if ($WhatIf) {
            Write-Host "Removing bucket '$($m.Name)' ($fileCount object(s))"
            Write-Host "  Path: $($m.Path)"
            Write-Host "[WhatIf] Would remove: $($m.Path)"
            continue
        }

        Write-Host "Removing bucket '$($m.Name)' ($fileCount object(s))"
        Write-Host "  Path: $($m.Path)"

        Remove-Item -Path $m.Path -Recurse -Force
        Write-Host "Bucket '$($m.Name)' removed"
    }
}

Remove-Item -Path Alias:Save-BucketObject -ErrorAction SilentlyContinue
Remove-Item -Path Alias:Get-BucketObject -ErrorAction SilentlyContinue
