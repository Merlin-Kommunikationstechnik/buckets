function New-Bucket {
    <#
    .SYNOPSIS
    Creates an empty bucket directory.
    .DESCRIPTION
    Creates a new bucket directory at the storage path. Supports nested buckets
    (e.g. "org/eu/de"). If the bucket already exists, emits a warning and skips
    unless -Force is used to recreate it.
    .PARAMETER Name
    Bucket name to create (Position 0). Supports nested paths like "org/eu/de".
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Force
    Delete and recreate the bucket if it already exists.
    .PARAMETER PassThru
    Return a bucket info object with Name and Path properties.
    .PARAMETER Quiet
    Suppress output.
    .EXAMPLE
    New-Bucket users
    .EXAMPLE
    New-Bucket "org/eu/de"
    .EXAMPLE
    New-Bucket users -Force
    .EXAMPLE
    New-Bucket users -PassThru
    .EXAMPLE
    New-Bucket users -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Name,
        [string]$Path,
        [switch]$Force,
        [switch]$PassThru,
        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    $bucketPath = Get-BucketPath -Name $Name -Path $Path

    $exists = [System.IO.Directory]::Exists($bucketPath)

    if ($exists -and -not $Force) {
        Write-Warning "Bucket '$Name' already exists"
        if ($PassThru) {
            $obj = [PSCustomObject]@{ Name = $Name; ObjectCount = 0; HasSubBuckets = $false }
            Add-HiddenProperty -Target $obj -Name 'Path' -Value $bucketPath
            $obj
        }
        return
    }

    if ($PSCmdlet.ShouldProcess("bucket '$Name'", "Create")) {
        if ($exists -and $Force) {
            Remove-BucketItem -Bucket $Name -Path $Path -Drop -Force -Quiet
        }
        Ensure-BucketExists -Name $Name -Path $Path | Out-Null

        if (-not $Quiet) {
            Write-Host "$Name" -NoNewline -ForegroundColor $script:CPath
            Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
            Write-Host "created" -ForegroundColor $script:CMuted
        }

        if ($PassThru) {
            $obj = [PSCustomObject]@{ Name = $Name; ObjectCount = 0; HasSubBuckets = $false }
            Add-HiddenProperty -Target $obj -Name 'Path' -Value $bucketPath
            $obj
        }
    }
}
