function Get-FunnelDefinition {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($script:FunnelCache.ContainsKey($Name)) { return $script:FunnelCache[$Name] }
    $userFile = Join-Path (Join-Path (Get-BucketsSystemPath) "funnels") "$Name.json"
    if (Test-Path $userFile) {
        $def = Get-Content -Path $userFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($def.Filter -and -not $def.Transform) {
            $def | Add-Member -NotePropertyName Transform -NotePropertyValue $def.Filter
        }
        $script:FunnelCache[$Name] = $def
        return $def
    }
    $builtinFile = Join-Path $script:BuiltinFunnelsDir "$Name.json"
    if (Test-Path $builtinFile) {
        $def = Get-Content -Path $builtinFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($def.Filter -and -not $def.Transform) {
            $def | Add-Member -NotePropertyName Transform -NotePropertyValue $def.Filter
        }
        $script:FunnelCache[$Name] = $def
        return $def
    }
    return $null
}