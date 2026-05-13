function Test-MatchFilter {
    param([PSObject]$Object, [hashtable]$Match)
    foreach ($kvp in $Match.GetEnumerator()) {
        $prop = Get-ObjectProperty -Object $Object -PropertyName $kvp.Name
        $matchesValue = if ($null -eq $kvp.Value) { -not $prop.HasValue }
        elseif (-not $prop.HasValue) { $false }
        else { $prop.Value -eq $kvp.Value }
        if (-not $matchesValue) { return $false }
    }
    return $true
}