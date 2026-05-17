function Read-BucketFile {
    param([System.IO.FileInfo]$File)

    if ($null -eq $File -or -not [System.IO.File]::Exists($File.FullName)) { return $null }

    $extension = $File.Extension
    $rawBytes = [System.IO.File]::ReadAllBytes($File.FullName)

    if ($extension -eq ".dat") {
        try {
            $decoded = $null
            $isCompressed = $rawBytes.Length -ge 2 -and $rawBytes[0] -eq 0x1F -and $rawBytes[1] -eq 0x8B
            if ($isCompressed) {
                try {
                    $ms = [System.IO.MemoryStream]::new($rawBytes)
                    try {
                        $decompressed = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
                        try {
                            $reader = [System.IO.StreamReader]::new($decompressed)
                            try { $decoded = $reader.ReadToEnd() }
                            finally { $reader.Close() }
                        }
                        finally { $decompressed.Close() }
                    }
                    finally { $ms.Dispose() }
                }
                catch {
                    Write-Warning "Failed to decompress '$($File.Name)': $_"
                    return $null
                }
            }
            else {
                $decoded = [System.Text.Encoding]::UTF8.GetString($rawBytes)
                if (-not $decoded.StartsWith('<Objs') -and -not $decoded.StartsWith('<?xml')) {
                    $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($decoded))
                }
            }
            $obj = Read-SafeClixml -Clixml $decoded
            # Convert hashtables to PSCustomObject
            if ($obj -is [hashtable]) {
                $ordered = [ordered]@{}
                foreach ($kvp in $obj.GetEnumerator()) { $ordered[$kvp.Key] = $kvp.Value }
                return [PSCustomObject]$ordered
            }
            return $obj
        }
        catch {
            Write-Warning "Failed to deserialize '$($File.Name)': $_"
            return $null
        }
    }
    else {
        try {
            $content = [System.Text.Encoding]::UTF8.GetString($rawBytes)
            if ($content.StartsWith([char]0xFEFF)) { $content = $content.Substring(1) }
            $obj = $content | ConvertFrom-Json
            $obj = Restore-JsonTypes -InputObject $obj
            if ($obj -is [hashtable]) {
                $ordered = [ordered]@{}
                foreach ($kvp in $obj.GetEnumerator()) { $ordered[$kvp.Key] = $kvp.Value }
                return [PSCustomObject]$ordered
            }
            return $obj
        }
        catch {
            Write-Warning "Failed to parse JSON '$($File.Name)': $_"
            return $null
        }
    }
}