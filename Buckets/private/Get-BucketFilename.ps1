function Get-BucketFilename {
    param($Item, [string]$Key, [string]$KeyProperty, [bool]$AsTimestamp, [int]$Index, [string]$Extension)

    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $safeKey = $Key -replace '[\\/:\*\?"<>\|\[\]]', '_'
        if ([string]::IsNullOrWhiteSpace($safeKey) -or $safeKey -match '^_+$') {
            Write-Warning "Key is empty after sanitization ('$Key' -> '$safeKey'), skipping"
            return $null
        }
        return [PSCustomObject]@{ Filename = "${safeKey}${Extension}"; Sanitized = $safeKey -ne $Key; OriginalKey = $Key }
    }

    if (-not [string]::IsNullOrWhiteSpace($KeyProperty)) {
        $keyValue = $Item.$KeyProperty
        if ($null -eq $keyValue) {
            Write-Warning "Property '$KeyProperty' not found on object, skipping"
            return $null
        }
        $safeKey = $keyValue -replace '[\\/:\*\?"<>\|\[\]]', '_'
        if ([string]::IsNullOrWhiteSpace($safeKey) -or $safeKey -match '^_+$') {
            Write-Warning "Key for object is empty after sanitization ('$keyValue' -> '$safeKey'), skipping"
            return $null
        }
        return [PSCustomObject]@{ Filename = "${safeKey}${Extension}"; Sanitized = $safeKey -ne "$keyValue"; OriginalKey = "$keyValue" }
    }

    if ($AsTimestamp) {
        return [PSCustomObject]@{ Filename = "$(Get-Date -Format 'yyyyMMddHHmmssfff')_${Index}${Extension}"; Sanitized = $false; OriginalKey = $null }
    }

    return [PSCustomObject]@{ Filename = "$([Guid]::NewGuid())${Extension}"; Sanitized = $false; OriginalKey = $null }
}