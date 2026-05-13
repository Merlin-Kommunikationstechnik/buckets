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
    Root directory for bucket storage. Default: $HOME/.buckets.
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
        [Parameter(Mandatory = $true)][string]$Bucket,
        [string]$Path,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$NewKey,
        [switch]$PassThru,
        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path
    if (-not [System.IO.Directory]::Exists($bucketPath)) {
        throw "Bucket '$Bucket' not found at '$bucketPath'"
    }

    $safeNewKey = $NewKey -replace '[\\/:\*\?"<>\|\[\]]', '_'
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
        [PSCustomObject]@{ Bucket = $Bucket; OldKey = $Key; NewKey = $safeNewKey }
    }
    elseif (-not $Quiet) {
        Write-Host "$Bucket/$Key" -NoNewline -ForegroundColor $script:CPath
        Write-Host " → " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "$safeNewKey" -ForegroundColor $script:CPath
    }
}