function Export-Bucket {
    <#
    .SYNOPSIS
    Exports a bucket to a single archive file.
    .DESCRIPTION
    Serializes all objects in a bucket to a single JSON or CLIXML archive file.
    Includes object metadata (_BucketName, _BucketKey) for easy restoration.
    Default format is JSON. Use -AsBinary for CLIXML/PSSerializer format with full .NET type preservation.
    .PARAMETER Bucket
    Bucket name to export. Supports wildcards.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER OutputFile
    Path to the output archive file.
    .PARAMETER AsBinary
    Export as CLIXML/PSSerializer binary archive (default is JSON).
    .PARAMETER Compress
    Enable GZip compression for CLIXML archives. Only effective with -AsBinary.
    .PARAMETER Recurse
    Recurse into nested sub-buckets. Without this switch, only exports objects from the specified bucket directory.
    .PARAMETER Depth
    Maximum nesting depth when recursing. Default: unlimited.
    .PARAMETER Quiet
    Suppress all output.
    .EXAMPLE
    Export-Bucket -Bucket users -OutputFile "./users-backup.json"
    .EXAMPLE
    Export-Bucket -Bucket "config*" -OutputFile "./config-backup.clixml" -AsBinary
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string[]]$Bucket,
        [string]$Path,
        [Parameter(Mandatory = $true)][string]$OutputFile,
        [switch]$AsBinary,
        [switch]$Compress,
        [switch]$Recurse,
        [int]$Depth = [int]::MaxValue,
        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    $allObjects = [System.Collections.ArrayList]::new()
    $exportedBuckets = 0
    $exportedObjects = 0

    foreach ($b in $Bucket) {
        $objects = Get-BucketObject -Bucket $b -Path $Path -Recurse:$Recurse -Depth $Depth
        if ($objects) {
            $null = $allObjects.AddRange(@($objects))
            $exportedBuckets++
            $exportedObjects += @($objects).Count
        }
    }

    if ($allObjects.Count -eq 0) {
        Write-Warning "No objects found to export for buckets: $($Bucket -join ', ')"
        return
    }

    $outputDir = [System.IO.Path]::GetDirectoryName((Resolve-SafePath -Path $OutputFile))
    if (-not [System.IO.Directory]::Exists($outputDir)) {
        $null = [System.IO.Directory]::CreateDirectory($outputDir)
    }

    if ($AsBinary) {
        $xml = [System.Management.Automation.PSSerializer]::Serialize($allObjects, 10)
        $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
        if ($Compress) {
            $ms = [System.IO.MemoryStream]::new()
            try {
                $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
                try { $cs.Write($rawBytes, 0, $rawBytes.Length) }
                finally { $cs.Close() }
                [System.IO.File]::WriteAllBytes($OutputFile, $ms.ToArray())
            }
            finally { $ms.Dispose() }
        }
        else {
            [System.IO.File]::WriteAllBytes($OutputFile, $rawBytes)
        }
    }
    else {
        $json = ConvertTo-Json -InputObject $allObjects -Depth 20 -Compress
        [System.IO.File]::WriteAllText($OutputFile, $json, [System.Text.Encoding]::UTF8)
    }

    if (-not $Quiet) {
        $bucketArg = if ($Bucket -is [array]) { $Bucket -join ', ' } else { $Bucket }
        Write-Host "$bucketArg" -NoNewline -ForegroundColor $script:CPath
        Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
        Write-Host $exportedObjects -NoNewline -ForegroundColor $script:CNum
        Write-Host " objects → " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "$([System.IO.Path]::GetFileName($OutputFile))" -ForegroundColor $script:CAction
    }
}