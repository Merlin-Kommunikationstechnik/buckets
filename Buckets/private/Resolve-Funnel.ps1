function Resolve-Funnel {
    param([object]$Funnel)
    if (-not $Funnel) { return $null }
    if ($Funnel -is [scriptblock]) {
        return @{ Transform = $Funnel }
    }
    $def = Get-FunnelDefinition -Name $Funnel
    $result = @{ Transform = [scriptblock]::Create($def.Transform) }
    if ($def.AppliesTo) {
        $at = $def.AppliesTo.Trim()
        if ($at -match '^\[.+\]$') { $result.AppliesTo = [scriptblock]::Create("`$_ -is $at") }
        else { $result.AppliesTo = [scriptblock]::Create($at) }
    }
    return $result
}