function Get-ObjectProperty {
    param([PSObject]$Object, [string]$PropertyName)

    $hasValue = $false
    $value = $null

    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($PropertyName)) { $hasValue = $true; $value = $Object[$PropertyName] }
    }
    elseif ($null -ne $Object.PSObject.Properties[$PropertyName]) {
        $hasValue = $true; $value = $Object.$PropertyName
    }

    return @{ HasValue = $hasValue; Value = $value }
}