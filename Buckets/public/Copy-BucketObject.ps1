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
    Root directory for bucket storage. Default: $HOME/.buckets.
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
        [Parameter(Mandatory = $true)][string]$Bucket,
        [string]$DestinationBucket,
        [string]$Path,
        [Parameter(Mandatory = $true)][string]$Key,
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

    if ([string]::IsNullOrWhiteSpace($DestinationBucket)) { $DestinationBucket = $Bucket }
    if ([string]::IsNullOrWhiteSpace($DestinationKey)) { $DestinationKey = $Key }

    $safeDestKey = $DestinationKey -replace '[\\/:\*\?"<>\|\[\]]', '_'
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
            SourceBucket = $Bucket; SourceKey = $Key; DestinationBucket = $DestinationBucket
            DestinationKey = $safeDestKey
        }
    }
    elseif (-not $Quiet) {
        Write-Host "$Bucket/$Key" -NoNewline -ForegroundColor $script:CPath
        Write-Host " → " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "$DestinationBucket/$safeDestKey" -ForegroundColor $script:CPath
    }
}