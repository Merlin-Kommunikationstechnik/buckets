function Get-BucketsSystemPath {
    [CmdletBinding()]
    param()
    $systemRoot = Join-Path $HOME ".buckets-system"
    if (-not (Test-Path $systemRoot)) { New-Item -ItemType Directory -Path $systemRoot -Force | Out-Null }
    return $systemRoot
}