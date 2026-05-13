function Write-RemovalSummary {
    param(
        [string]$Title,
        [string[]]$Names,
        [int[]]$Counts,
        [string[]]$Sizes,
        [string[][]]$Nested,
        [int]$MaxShow = 10
    )
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor $script:CPath
    for ($i = 0; $i -lt $Names.Count; $i++) {
        $count = if ($Counts[$i] -eq 1) { "1 object" } else { "$($Counts[$i]) objects" }
        Write-Host "    " -NoNewline
        Write-Host "$($Names[$i])" -NoNewline -ForegroundColor $script:CPath
        Write-Host " (" -NoNewline -ForegroundColor $script:CMuted
        Write-Host "$count" -NoNewline -ForegroundColor $script:CNum
        Write-Host ", " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "$($Sizes[$i])" -NoNewline -ForegroundColor $script:CNum
        Write-Host ")" -NoNewline -ForegroundColor $script:CMuted
        if ($Nested -and $Nested[$i] -and $Nested[$i].Count -gt 0) {
            Write-Host " [includes nested: $($Nested[$i] -join ', ')]" -ForegroundColor $script:CMuted
        } else {
            Write-Host ""
        }
    }
    if ($Names.Count -gt $MaxShow) {
        Write-Host "    ... and $($Names.Count - $MaxShow) more" -ForegroundColor $script:CMuted
    }
    Write-Host ""
}