function Get-Funnel {
    <#
    .SYNOPSIS
    Lists named funnels or retrieves a specific funnel definition.
    .DESCRIPTION
    Returns funnel definitions from the user funnels directory ($HOME/.buckets-system/funnels/)
    and built-in funnels shipped with the module. User funnels with the same name override
    built-in ones. When no name is given, lists all funnels.
    .PARAMETER Name
    Optional funnel name to retrieve. Returns all funnels if omitted.
    .EXAMPLE
    Get-Funnel
    .EXAMPLE
    Get-Funnel -Name admins
    .EXAMPLE
    Get-Funnel -Name file-light
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Name
    )

    if ($Name) {
        $def = Get-FunnelDefinition -Name $Name
        if ($null -eq $def) { return }
        $out = [PSCustomObject]@{ Name = $Name; Transform = $def.Transform; Description = $def.Description }
        if ($def.AppliesTo) { $out | Add-Member -NotePropertyName AppliesTo -NotePropertyValue $def.AppliesTo }
        $out
        return
    }

    $seen = @{}

    $userDir = Join-Path (Get-BucketsSystemPath) "funnels"
    if (Test-Path $userDir) {
        foreach ($f in [System.IO.DirectoryInfo]::new($userDir).GetFiles("*.json")) {
            $fName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            $def = Get-FunnelDefinition -Name $fName
            $out = [PSCustomObject]@{ Name = $fName; Transform = $def.Transform; Description = $def.Description }
            if ($def.AppliesTo) { $out | Add-Member -NotePropertyName AppliesTo -NotePropertyValue $def.AppliesTo }
            $out
            $seen[$fName] = $true
        }
    }

    if (Test-Path $script:BuiltinFunnelsDir) {
        foreach ($f in [System.IO.DirectoryInfo]::new($script:BuiltinFunnelsDir).GetFiles("*.json")) {
            $fName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if (-not $seen.ContainsKey($fName)) {
                $def = Get-FunnelDefinition -Name $fName
                $out = [PSCustomObject]@{ Name = $fName; Transform = $def.Transform; Description = $def.Description }
                if ($def.AppliesTo) { $out | Add-Member -NotePropertyName AppliesTo -NotePropertyValue $def.AppliesTo }
                $out
            }
        }
    }
}