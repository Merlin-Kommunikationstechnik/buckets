function Ensure-BucketExists {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
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