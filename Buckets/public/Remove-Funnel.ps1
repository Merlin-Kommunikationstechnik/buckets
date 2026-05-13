function Remove-Funnel {
    <#
    .SYNOPSIS
    Deletes a named funnel definition.
    .DESCRIPTION
    Removes a funnel JSON file from the user funnels directory ($HOME/.buckets-system/funnels/)
    and clears it from the session cache. Built-in funnels shipped with the module cannot be
    removed unless a user override with the same name exists.
    .PARAMETER Name
    Name of the funnel to remove.
    .PARAMETER Quiet
    Suppress success output.
    .EXAMPLE
    Remove-Funnel -Name admins
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$Quiet
    )

    $userDir = Join-Path (Get-BucketsSystemPath) "funnels"
    $userFile = Join-Path $userDir "$Name.json"
    $builtinFile = Join-Path $script:BuiltinFunnelsDir "$Name.json"

    if (-not (Test-Path $userFile)) {
        if (Test-Path $builtinFile) {
            throw "Funnel '$Name' is a built-in funnel and cannot be removed. Create a user funnel with the same name to override it."
        }
        throw "Funnel '$Name' not found."
    }

    if ($PSCmdlet.ShouldProcess("funnel '$Name'", "Remove-Funnel")) {
        [System.IO.File]::Delete($userFile)
        $script:FunnelCache.Remove($Name)
        if (-not $Quiet) {
            Write-Host "$Name" -NoNewline -ForegroundColor $script:CPath
            Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
            Write-Host "funnel removed" -ForegroundColor $script:CNum
        }
    }
}