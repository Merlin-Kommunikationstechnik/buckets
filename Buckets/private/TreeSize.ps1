function TreeSize {
            param([long]$Bytes)
            if ($Bytes -eq 0) { return "0 B" }
            $units = @("B", "KB", "MB", "GB", "TB")
            $unit = 0
            $size = [double]$Bytes
            while ($size -ge 1024 -and $unit -lt $units.Length - 1) {
                $size /= 1024
                $unit++
            }
            $rounded = [math]::Round($size)
            "$rounded $($units[$unit])"
        }