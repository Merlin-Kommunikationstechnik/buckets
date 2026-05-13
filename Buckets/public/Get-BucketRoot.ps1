function Get-BucketRoot {
    <#
    .SYNOPSIS
    Returns the current default bucket storage directory.
    .DESCRIPTION
    Returns the active bucket root in priority order:
    1. Session override (Set-BucketRoot)
    2. Environment variable ($env:BUCKETS_ROOT)
    3. Home directory fallback ($HOME/.buckets)
    .EXAMPLE
    Get-BucketRoot
    #>
    [CmdletBinding()]
    param()
    return Get-DefaultPath
}