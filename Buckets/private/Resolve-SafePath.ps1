function Resolve-SafePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    try { return [System.IO.Path]::GetFullPath($Path) }
    catch { throw "Invalid path '$Path': $_" }
}