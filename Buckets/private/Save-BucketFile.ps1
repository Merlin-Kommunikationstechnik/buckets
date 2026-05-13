function Save-BucketFile {
    param(
        [string]$Path, $Item, [string]$Extension, [bool]$AsBinary, [bool]$Compress,
        [int]$Depth = 20, [int]$BinaryDepth = 5, [bool]$Overwrite,
        [string]$BucketPath, [string]$Bucket
    )

    $result = @{ Success = $false; Skipped = $false; Fallback = $false; FormatFallback = $false; Overwritten = $false }
    $fileExisted = [System.IO.File]::Exists($Path)

    if ($fileExisted -and -not $Overwrite) {
        Write-Verbose "Object with key '$([System.IO.Path]::GetFileNameWithoutExtension($Path))' already exists in bucket '$Bucket'. Use -Overwrite to replace."
        $result.Skipped = $true
        return $result
    }

    $writeSuccess = $false
    if ($AsBinary) {
        $currentDepth = $BinaryDepth
        $maxLoopDepth = [Math]::Max(10, $BinaryDepth)
        while ($currentDepth -le $maxLoopDepth) {
            try {
                $xml = [System.Management.Automation.PSSerializer]::Serialize($Item, $currentDepth)
                $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                if ($Compress) {
                    $ms = [System.IO.MemoryStream]::new()
                    $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
                    $cs.Write($rawBytes, 0, $rawBytes.Length)
                    $cs.Close()
                    [System.IO.File]::WriteAllBytes($Path, $ms.ToArray())
                }
                else {
                    [System.IO.File]::WriteAllBytes($Path, $rawBytes)
                }
                if ($currentDepth -gt $BinaryDepth) { $result.Fallback = $true }
                $writeSuccess = $true
                break
            }
            catch { $currentDepth++ }
        }
    }
    else {
        try {
            $json = ConvertTo-Json -InputObject $Item -Depth $Depth -Compress -WarningAction SilentlyContinue
            [System.IO.File]::WriteAllText($Path, $json, [System.Text.Encoding]::UTF8)
            $writeSuccess = $true
        }
        catch {
            try {
                $xml = [System.Management.Automation.PSSerializer]::Serialize($Item, $BinaryDepth)
                $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                $finalPath = [System.IO.Path]::ChangeExtension($Path, ".dat")
                if ($Compress) {
                    $ms = [System.IO.MemoryStream]::new()
                    $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
                    $cs.Write($rawBytes, 0, $rawBytes.Length)
                    $cs.Close()
                    [System.IO.File]::WriteAllBytes($finalPath, $ms.ToArray())
                }
                else {
                    [System.IO.File]::WriteAllBytes($finalPath, $rawBytes)
                }
                $result.Fallback = $true
                $result.FormatFallback = $true
                $writeSuccess = $true
                Write-Warning "Object '$([System.IO.Path]::GetFileNameWithoutExtension($Path))' too complex for JSON, saved as binary instead"
            }
            catch {
                Write-Verbose "Failed to serialize object '$([System.IO.Path]::GetFileNameWithoutExtension($Path))' as binary: $_"
            }
        }
    }

    $result.Success = $writeSuccess
    if ($writeSuccess -and $fileExisted) { $result.Overwritten = $true }
    return $result
}