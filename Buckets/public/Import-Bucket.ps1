function Import-Bucket {
    <#
    .SYNOPSIS
    Imports objects from an archive file into a bucket.
    .DESCRIPTION
    Reads objects from a JSON or CLIXML archive file and stores them in a bucket.
    Format is auto-detected by file extension (.json = JSON, otherwise = CLIXML/binary).
    Use -AsBinary to force CLIXML/binary format regardless of extension.
    Preserves original keys if objects have _BucketKey metadata; otherwise generates new keys.
    .PARAMETER Bucket
    Destination bucket name. Creates the bucket if it doesn't exist.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER InputFile
    Path to the archive file to import.
    .PARAMETER AsBinary
    Force import from CLIXML/binary format (auto-detected by file extension if omitted).
    .PARAMETER Overwrite
    Overwrite existing objects with the same key.
    .PARAMETER Quiet
    Suppress all output.
    .EXAMPLE
    Import-Bucket -Bucket users -InputFile "./users-backup.json"
    .EXAMPLE
    Import-Bucket -Bucket config -InputFile "./config-backup.clixml" -AsBinary
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Bucket,
        [Parameter(Mandatory = $true)][string]$InputFile,
        [string]$Path,
[switch]$AsBinary,
        [switch]$Overwrite,
        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    if (-not [System.IO.File]::Exists($InputFile)) {
        throw "Input file '$InputFile' not found"
    }

    $rawBytes = [System.IO.File]::ReadAllBytes($InputFile)
    $useJson = -not $AsBinary -and $InputFile -like "*.json"

    if ($useJson) {
        $content = [System.IO.File]::ReadAllText($InputFile, [System.Text.Encoding]::UTF8)
        $objects = $content | ConvertFrom-Json
    }
    else {
        try {
            $isCompressed = $rawBytes.Length -ge 2 -and $rawBytes[0] -eq 0x1F -and $rawBytes[1] -eq 0x8B
            if ($isCompressed) {
                $ms = [System.IO.MemoryStream]::new($rawBytes)
                try {
                    $decompressed = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
                    try {
                        $reader = [System.IO.StreamReader]::new($decompressed)
                        try { $content = $reader.ReadToEnd() }
                        finally { $reader.Close() }
                    }
                    finally { $decompressed.Close() }
                }
                finally { $ms.Dispose() }
                $objects = Read-SafeClixml -Clixml $content
            }
            else {
                $objects = Read-SafeClixml -Clixml ([System.Text.Encoding]::UTF8.GetString($rawBytes))
            }
        }
        catch {
            throw "Failed to deserialize archive file '$InputFile': $_"
        }
    }

    if ($null -eq $objects) { throw "Failed to deserialize archive file '$InputFile'" }

    $objectArray = @($objects)
    Write-Verbose "Loaded $($objectArray.Count) objects from '$InputFile'"

    $bucketPath = Ensure-BucketExists -Name $Bucket -Path $Path
    $importedCount = 0; $skippedCount = 0
    $skippedKeys = [System.Collections.ArrayList]::new()

    foreach ($obj in $objectArray) {
        $key = if ($obj.PSObject.Properties['_BucketKey']) { $obj._BucketKey } else { [Guid]::NewGuid().ToString() }
        $safeKey = $key -replace '[\\/:\*\?"<>\|\[\]]', '_'
        if ([string]::IsNullOrWhiteSpace($safeKey) -or $safeKey -match '^_+$') {
            Write-Warning "Key '$key' in imported object is invalid after sanitization, using GUID instead"
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
            $null = $skippedKeys.Add($safeKey)
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
        Write-Host "$([System.IO.Path]::GetFileName($InputFile))" -NoNewline -ForegroundColor $script:CAction
        Write-Host " → " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "$Bucket" -NoNewline -ForegroundColor $script:CPath
        Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
        Write-Host $importedCount -NoNewline -ForegroundColor $script:CNum
        Write-Host " objects" -ForegroundColor $script:CMuted
        if ($skippedCount -gt 0) {
            Write-Host "  " -NoNewline
            Write-Host $skippedCount -NoNewline -ForegroundColor $script:CNum
            $skipDisplay = if ($skippedKeys.Count -le 5) { $skippedKeys -join ", " } else { ($skippedKeys | Select-Object -First 5) -join ", " + " ... +$($skippedKeys.Count - 5) more" }
            Write-Host " skipped (existing keys: $skipDisplay)" -ForegroundColor $script:CSkip
        }
    }
}