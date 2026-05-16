function Resolve-ObjectType {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$FileInfo)
    $isCompressed = $false
    if ($FileInfo.Extension -eq ".json") {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($FileInfo.FullName)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes).TrimStart()
            if ($text.StartsWith("[")) { return @{ Type = "Array"; IsCompressed = $false } }
            if ($text.StartsWith("{")) { return @{ Type = "Object"; IsCompressed = $false } }
            return @{ Type = "Value"; IsCompressed = $false }
        } catch {
            return @{ Type = "Object"; IsCompressed = $false }
        }
    }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($FileInfo.FullName)
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0x1F -and $bytes[1] -eq 0x8B) {
            $isCompressed = $true
            try {
                $ms = [System.IO.MemoryStream]::new($bytes)
                try {
                    $gz = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
                    try {
                        $buf = [byte[]]::new(2048)
                        $null = $gz.Read($buf, 0, 2048)
                        $text = [System.Text.Encoding]::UTF8.GetString($buf).TrimStart()
                    }
                    finally { $gz.Close() }
                }
                finally { $ms.Dispose() }
                if ($text -match '<T>\s*\[.*?\]') { return @{ Type = "Array"; IsCompressed = $true } }
                if ($text -match '<T>\s*System\.Collections\.(ArrayList|Generic\.List)') { return @{ Type = "Array"; IsCompressed = $true } }
                if ($text -match '<T>\s*System\.(String|Int\d+|Boolean|Double|Single|Decimal|Long|Float|Byte)') { return @{ Type = "Value"; IsCompressed = $true } }
                return @{ Type = "Object"; IsCompressed = $true }
            } catch {
                return @{ Type = "Object"; IsCompressed = $true }
            }
        }
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        if ($text -match '<T>\s*\[.*?\]') { return @{ Type = "Array"; IsCompressed = $false } }
        if ($text -match '<T>\s*System\.Collections\.(ArrayList|Generic\.List)') { return @{ Type = "Array"; IsCompressed = $false } }
        if ($text -match '<T>\s*System\.(String|Int\d+|Boolean|Double|Single|Decimal|Long|Float|Byte)') { return @{ Type = "Value"; IsCompressed = $false } }
        return @{ Type = "Object"; IsCompressed = $false }
    } catch {
        return @{ Type = "Object"; IsCompressed = $false }
    }
}