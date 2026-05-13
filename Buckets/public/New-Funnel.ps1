function New-Funnel {
    <#
    .SYNOPSIS
    Creates a named funnel (reusable filter/transform scriptblock).
    .DESCRIPTION
    Saves a named funnel definition to $HOME/.buckets-system/funnels/. Funnels can be
    referenced by name with the -Funnel parameter on fill and scoop.
    A funnel is a scriptblock operating on $_ that returns the object to keep it
    (optionally modified), or $null to drop it. This works identically on fill and scoop.
    .PARAMETER Name
    Name for the funnel. Used to reference it later via -Funnel.
    .PARAMETER Transform
    ScriptBlock defining the funnel transform logic. Use $_ for the pipeline object.
    .PARAMETER Description
    Optional human-readable description of what the funnel does.
    .PARAMETER Force
    Overwrite an existing funnel with the same name.
    .PARAMETER Quiet
    Suppress success output.
    .EXAMPLE
    New-Funnel -Name admins -Transform { if ($_.Role -eq "admin") { $_ } }
    .EXAMPLE
    New-Funnel -Name add-source -Transform { $_ | Add-Member -NotePropertyName "Source" -NotePropertyValue "import" -PassThru } -Description "Adds Source property"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Transform,
        [string]$Description = "",
        [scriptblock]$AppliesTo,
        [switch]$Force,
        [switch]$Quiet
    )

    $funnelDir = Join-Path (Get-BucketsSystemPath) "funnels"
    if (-not (Test-Path $funnelDir)) { New-Item -ItemType Directory -Path $funnelDir -Force | Out-Null }
    $funnelFile = Join-Path $funnelDir "$Name.json"
    if ((Test-Path $funnelFile) -and -not $Force) { throw "Funnel '$Name' already exists. Use -Force to overwrite." }

    $saveObj = @{ Transform = "$Transform"; Description = $Description }
    $cacheObj = @{ Transform = "$Transform"; Description = $Description }
    if ($AppliesTo) { $saveObj.AppliesTo = "$AppliesTo"; $cacheObj.AppliesTo = "$AppliesTo" }
    $text = $saveObj | ConvertTo-Json
    [System.IO.File]::WriteAllText($funnelFile, $text, [System.Text.Encoding]::UTF8)
    $script:FunnelCache[$Name] = $cacheObj
    if (-not $Quiet) {
        Write-Host "$Name" -NoNewline -ForegroundColor $script:CPath
        Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "funnel saved" -ForegroundColor $script:CNum
    }
}