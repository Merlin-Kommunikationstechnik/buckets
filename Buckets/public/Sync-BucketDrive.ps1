function Sync-BucketDrive {
    <#
    .SYNOPSIS
    Creates or updates the 'buckets:' PSDrive to point to the current bucket root.
    .DESCRIPTION
    Automatically called on module import and by Set-BucketRoot.
    Can also be called manually to refresh after changing $env:BUCKETS_ROOT.
    .EXAMPLE
    Sync-BucketDrive
    .EXAMPLE
    $env:BUCKETS_ROOT = "/data/buckets"
    Sync-BucketDrive
    #>
    [CmdletBinding()]
    param()

    $root = Get-DefaultPath
    $driveName = 'buckets'
    $existing = Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue
    if ($existing) { Remove-PSDrive -Name $driveName -Force -ErrorAction SilentlyContinue }
    try {
        Write-Verbose "Creating PSDrive '$driveName' -> $root"
        New-PSDrive -Name $driveName -PSProvider Buckets -Root $root -Scope Global | Out-Null
    }
    catch { Write-Warning "Failed to create PSDrive '$driveName': $_" }
}