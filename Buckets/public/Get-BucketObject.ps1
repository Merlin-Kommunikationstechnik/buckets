function Get-BucketObject {
    <#
    .SYNOPSIS
    Retrieves objects from one or more buckets.
    .DESCRIPTION
    Reads serialized objects from bucket directories. When no bucket is specified,
    reads from the "default" bucket. Supports exact-match hashtable
    filtering (-Match) and arbitrary scriptblock filtering (-Filter).
    Retrieved objects include metadata properties: _BucketName, _BucketKey, _BucketFile.
    .PARAMETER Bucket
    Bucket name(s) to search (Position 0). If omitted, reads from the "default" bucket. Supports wildcards.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Key
    Object key to retrieve (Position 1). Case-insensitive prefix match. Looks for both JSON and binary files.
    .PARAMETER Match
    Hashtable of property-value pairs for exact-match filtering. All pairs must match. Supports $null values.
    .PARAMETER Filter
    ScriptBlock for custom filtering. Use $_ to reference object properties (e.g., { $_.Age -gt 30 }).
    .PARAMETER Recurse
    Recurse into nested sub-buckets. Without this switch, only returns objects from the specified bucket directory.
    .PARAMETER First
    Return only the first N objects.
    .PARAMETER Skip
    Skip the first N objects before returning results.
    .OUTPUTS
    Deserialized PSObjects with _BucketName, _BucketKey, and _BucketFile metadata.
    .EXAMPLE
    Get-BucketObject users
    .EXAMPLE
    Get-BucketObject users "Alice"
    .EXAMPLE
    Get-BucketObject -Bucket users -Match @{ Role = "admin" }
    .EXAMPLE
    Get-BucketObject -Bucket users -Match @{ Deleted = $null }
    .EXAMPLE
    Get-BucketObject -Filter { $_.Status -eq "shipped" -and $_.Shipping.Method -eq "Express" }
    .EXAMPLE
    Get-BucketObject -Bucket users, orders
    .EXAMPLE
    Get-BucketObject -Bucket org
    .EXAMPLE
    Get-BucketObject -First 10 -Skip 20
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string[]]$Bucket,
        [string]$Path,
        [Parameter(Position = 1)][string]$Key,
        [hashtable]$Match,
        [scriptblock]$Filter,
        [switch]$Recurse,
        [int]$First,
        [int]$Skip,
        [object]$Funnel
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    $bucketPaths = @()
    if ($Bucket -and $Bucket.Count -gt 0) {
        $cachedBuckets = $null
        foreach ($b in $Bucket) {
            if ($b -match '[\*\?]') {
                if ($null -eq $cachedBuckets) { $cachedBuckets = Get-Bucket -Path $Path -Recurse:$Recurse }
                $matched = $cachedBuckets | Where-Object { $_.Name -like $b }
                $bucketPaths += $matched | ForEach-Object { $_.Path }
            }
            else {
                $bp = Get-BucketPath -Name $b -Path $Path
                $bucketPaths += $bp
                if ($Recurse) {
                    $nested = Get-Bucket -Path $Path -Recurse | Where-Object { $_.Name -like "$b/*" }
                    $bucketPaths += $nested | ForEach-Object { $_.Path }
                }
            }
        }
    }
    else {
        $bucketPaths += Get-BucketPath -Name "default" -Path $Path
    }

    $funnelDef = Resolve-Funnel $Funnel

    $allObjects = [System.Collections.ArrayList]::new()
    $warnedBuckets = @{}

    foreach ($bucketPath in $bucketPaths) {
        if (-not [System.IO.Directory]::Exists($bucketPath)) {
            $bucketLeaf = Split-Path $bucketPath -Leaf
            if (-not $warnedBuckets.ContainsKey($bucketLeaf)) {
                Write-Warning "Bucket '$bucketLeaf' not found"
                $warnedBuckets[$bucketLeaf] = $true
            }
            continue
        }
        $bucketName = Split-Path $bucketPath -Leaf
        $files = Get-ObjectFiles -BucketPath $bucketPath -Key $Key

        foreach ($file in $files) {
            if ($null -eq $file -or -not [System.IO.File]::Exists($file.FullName)) { continue }
            $obj = Read-BucketFile -File $file
            if ($null -eq $obj) { continue }

            if ($Match -and -not (Test-MatchFilter -Object $obj -Match $Match)) { continue }

            if ($Filter) {
                if ($null -eq ($obj | Where-Object $Filter)) { continue }
            }

            if ($funnelDef) {
                $matchesAppliesTo = -not $funnelDef.ContainsKey('AppliesTo') -or ($null -ne ($obj | Where-Object $funnelDef.AppliesTo))
                if ($matchesAppliesTo) {
                    $funnelItems = @($obj | ForEach-Object $funnelDef.Transform) | Where-Object { $_ -ne $null }
                    foreach ($subItem in $funnelItems) {
                        $relativePath = $file.FullName.Substring($bucketPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
                        $keyWithoutExt = [System.IO.Path]::ChangeExtension($relativePath, $null).TrimEnd('.')
                        Add-HiddenProperty -Target $subItem -Name '_BucketName' -Value $bucketName
                        Add-HiddenProperty -Target $subItem -Name '_BucketKey' -Value $keyWithoutExt
                        Add-HiddenProperty -Target $subItem -Name '_BucketFile' -Value $file.FullName
                        $null = $allObjects.Add($subItem)
                    }
                    continue
                }
            }

            $relativePath = $file.FullName.Substring($bucketPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
            $keyWithoutExt = [System.IO.Path]::ChangeExtension($relativePath, $null).TrimEnd('.')
            Add-HiddenProperty -Target $obj -Name '_BucketName' -Value $bucketName
            Add-HiddenProperty -Target $obj -Name '_BucketKey' -Value $keyWithoutExt
            Add-HiddenProperty -Target $obj -Name '_BucketFile' -Value $file.FullName
            $null = $allObjects.Add($obj)
        }
    }

    $emitted = 0; $skipped = 0
    foreach ($obj in $allObjects) {
        if ($Skip -gt 0 -and $skipped -lt $Skip) { $skipped++; continue }
        if ($First -gt 0 -and $emitted -ge $First) { break }
        Write-Output $obj; $emitted++
    }
}