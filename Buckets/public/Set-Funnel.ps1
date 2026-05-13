function Set-Funnel {
    <#
    .SYNOPSIS
    Updates an existing named funnel's filter scriptblock or description.
    .DESCRIPTION
    Modifies a funnel definition in $HOME/.buckets-system/funnels/. The funnel must
    already exist. Omitting -Filter or -Description keeps the current value.
    .PARAMETER Name
    Name of the funnel to update.
    .PARAMETER Transform
    New scriptblock for the funnel. Uses $_ for the pipeline object.
    .PARAMETER Description
    New description for the funnel.
    .PARAMETER Quiet
    Suppress success output.
    .EXAMPLE
    Set-Funnel -Name admins -Transform { $_.Role -eq "admin" -and $_.Active -eq $true }
    .EXAMPLE
    Set-Funnel -Name admins -Description "Filters active admin users"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [scriptblock]$Transform,
        [string]$Description,
        [scriptblock]$AppliesTo,
        [switch]$Quiet
    )

    $funnelDir = Join-Path (Get-BucketsSystemPath) "funnels"
    $funnelFile = Join-Path $funnelDir "$Name.json"
    if (-not (Test-Path $funnelFile)) { throw "Funnel '$Name' not found. Use New-Funnel to create it." }

    $existing = Get-Content -Path $funnelFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $existing.Transform -and $existing.Filter) {
        $existing | Add-Member -NotePropertyName Transform -NotePropertyValue $existing.Filter
    }
    if ($Transform) { $existing.Transform = "$Transform" }
    if ($PSBoundParameters.ContainsKey('Description')) { $existing.Description = $Description }
    if ($PSBoundParameters.ContainsKey('AppliesTo')) { $existing.AppliesTo = "$AppliesTo" }

    $saveObj = @{ Transform = $existing.Transform; Description = $existing.Description }
    $cacheObj = @{ Transform = $existing.Transform; Description = $existing.Description }
    if ($existing.AppliesTo) { $saveObj.AppliesTo = $existing.AppliesTo; $cacheObj.AppliesTo = $existing.AppliesTo }
    $text = $saveObj | ConvertTo-Json
    [System.IO.File]::WriteAllText($funnelFile, $text, [System.Text.Encoding]::UTF8)
    $script:FunnelCache[$Name] = $cacheObj
    if (-not $Quiet) {
        Write-Host "$Name" -NoNewline -ForegroundColor $script:CPath
        Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "funnel updated" -ForegroundColor $script:CNum
    }
}