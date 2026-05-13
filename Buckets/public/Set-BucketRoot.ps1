function Set-BucketRoot {
    <#
    .SYNOPSIS
    Change the default bucket storage directory for the current session.
    .DESCRIPTION
    Overrides the default $HOME/.buckets path. Persists only for the current session.
    For persistent overrides, set $env:BUCKETS_ROOT in your profile.
    Automatically updates the 'buckets:' PSDrive to point to the new location.
    .PARAMETER Path
    The directory to use as the new bucket root. Created if it doesn't exist.
    .EXAMPLE
    Set-BucketRoot /data/my-buckets
    .EXAMPLE
    Set-BucketRoot $env:HOME/.config/buckets
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)][string]$Path)

    $resolved = Resolve-SafePath $Path
    if (-not (Test-Path $resolved)) { New-Item -ItemType Directory -Path $resolved -Force | Out-Null }
    $script:BucketRoot = $resolved
    & $script:ClearCache
    Write-Verbose "Bucket root set to: $resolved"
    Sync-BucketDrive
}