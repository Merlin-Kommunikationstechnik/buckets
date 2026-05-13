#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Output pattern test — demonstrates every distinct console output of the Buckets module.
.DESCRIPTION
    Each section creates isolated buckets, runs the relevant commands, then cleans up.
    Designed to be read visually — not pass/fail assertions.
#>

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-output-$(Get-Random)"
Set-BucketRoot $testRoot

$createdBuckets = [System.Collections.ArrayList]::new()
function Use-Bucket {
    param([string]$Name)
    $null = $createdBuckets.Add($Name)
}
function Clean-Bucket {
    param([string]$Name)
    Remove-Bucket $Name -Force -Confirm:$false -Recurse -WarningAction SilentlyContinue -Quiet -ErrorAction SilentlyContinue
}

# ============================================================
# 1. New-BucketObject
# ============================================================
Write-Host "`n[1] New-BucketObject" -ForegroundColor Blue

# Normal save
Write-Host "`n  --- Normal save ---" -ForegroundColor DarkGray
New-BucketObject -Bucket out-new -InputObject @(
    @{ _Id = "a"; Val = 1 },
    @{ _Id = "b"; Val = 2 }
) -KeyProperty _Id -Quiet
Use-Bucket "out-new"
New-BucketObject -Bucket out-new -InputObject @(
    @{ _Id = "c"; Val = 3 },
    @{ _Id = "d"; Val = 4 }
) -KeyProperty _Id

# Overwrite
Write-Host "`n  --- Overwrite ---" -ForegroundColor DarkGray
New-BucketObject -Bucket out-new -InputObject @{ _Id = "c"; Val = 33 } -KeyProperty _Id -Overwrite

# Skip (duplicate without -Overwrite)
Write-Host "`n  --- Skip (duplicate, no -Overwrite) ---" -ForegroundColor DarkGray
New-BucketObject -Bucket out-new -InputObject @{ _Id = "a"; Val = 100 } -KeyProperty _Id

# AutoIndex
Write-Host "`n  --- AutoIndex (within-batch + pre-existing) ---" -ForegroundColor DarkGray
New-BucketObject -Bucket out-ai -InputObject @(
    [PSCustomObject]@{ Name = "x"; N = 1 },
    [PSCustomObject]@{ Name = "x"; N = 2 },
    [PSCustomObject]@{ Name = "x"; N = 3 }
) -KeyProperty Name -AutoIndex
Use-Bucket "out-ai"
New-BucketObject -Bucket out-ai -InputObject @{ Name = "x"; N = 4 } -KeyProperty Name -AutoIndex

# AutoIndex + Overwrite
Write-Host "`n  --- AutoIndex + Overwrite ---" -ForegroundColor DarkGray
New-BucketObject -Bucket out-ai2 -InputObject @{ _Id = "k"; V = 99 } -KeyProperty _Id -Quiet
$items = @(
    [PSCustomObject]@{ _Id = "k"; V = 10 },
    [PSCustomObject]@{ _Id = "k"; V = 20 }
)
$items | New-BucketObject -Bucket out-ai2 -KeyProperty _Id -AutoIndex -Overwrite

# Key sanitization
Write-Host "`n  --- Key sanitization ---" -ForegroundColor DarkGray
New-BucketObject -Bucket out-sanitize -InputObject @{ Name = "file:special*key"; Val = 1 } -KeyProperty Name

# AsBinary + Compress
Write-Host "`n  --- AsBinary + Compress ---" -ForegroundColor DarkGray
New-BucketObject -Bucket out-bin -InputObject @{ _Id = "comp"; Data = "x" * 500 } -KeyProperty _Id -AsBinary -Compress
Use-Bucket "out-bin"

# PassThru
Write-Host "`n  --- PassThru ---" -ForegroundColor DarkGray
$r = New-BucketObject -Bucket out-pt -InputObject @(
    @{ _Id = "p1"; V = 1 },
    @{ _Id = "p2"; V = 2 }
) -KeyProperty _Id -PassThru
$r | Format-List

# Quiet
Write-Host "`n  --- Quiet (no output) ---" -ForegroundColor DarkGray
New-BucketObject -Bucket out-pt -InputObject @{ _Id = "p3"; V = 3 } -KeyProperty _Id -Quiet
Write-Host "  (no output above — only this line)" -ForegroundColor DarkGray

# Format fallback warning (circular ref triggers binary fallback)
Write-Host "`n  --- Format fallback warning (circular ref) ---" -ForegroundColor DarkGray
$circ = [PSCustomObject]@{ _Id = "circ"; Name = "loop" }
$circ | Add-Member -NotePropertyName "Self" -NotePropertyValue $circ
New-BucketObject -Bucket out-new -InputObject $circ -KeyProperty _Id

# Path traversal
Write-Host "`n  --- Path traversal protection ---" -ForegroundColor DarkGray
try { New-BucketObject -Bucket "../../etc" -InputObject @{ _Id = "x" } -KeyProperty _Id -ErrorAction Stop } catch { Write-Host "  $_" -ForegroundColor Red }

# ============================================================
# 2. Get-Bucket
# ============================================================
Write-Host "`n[2] Get-Bucket" -ForegroundColor Blue

Write-Host "`n  --- Table view ---" -ForegroundColor DarkGray
Get-Bucket | Format-Table -AutoSize

Write-Host "`n  --- Tree view ---" -ForegroundColor DarkGray
New-BucketObject -Bucket out-org/eu/de -InputObject @{ _Id = "info"; Country = "Germany" } -KeyProperty _Id -Quiet
Use-Bucket "out-org"
Get-Bucket -Tree

Write-Host "`n  --- Tree with Objects ---" -ForegroundColor DarkGray
Get-Bucket -Tree -Objects -MaxFiles 3

Write-Host "`n  --- Filter by name (substring) ---" -ForegroundColor DarkGray
Get-Bucket -Name "out-new" | Format-Table -AutoSize

Write-Host "`n  --- Filter by name (wildcard) ---" -ForegroundColor DarkGray
Get-Bucket -Name "out-new*" | Format-Table -AutoSize

Write-Host "`n  --- Missing root ---" -ForegroundColor DarkGray
Get-Bucket -Tree -Path "/nonexistent/path/buckets"

# ============================================================
# 3. Get-BucketStats
# ============================================================
Write-Host "`n[3] Get-BucketStats" -ForegroundColor Blue

Write-Host "`n  --- Single bucket ---" -ForegroundColor DarkGray
Get-BucketStats -Bucket out-new | Format-List

Write-Host "`n  --- Missing bucket (warning) ---" -ForegroundColor DarkGray
Get-BucketStats -Bucket nonexistent-xyz -WarningAction SilentlyContinue

# ============================================================
# 4. Get-BucketKeys
# ============================================================
Write-Host "`n[4] Get-BucketKeys" -ForegroundColor Blue

Write-Host "`n  --- All keys in bucket ---" -ForegroundColor DarkGray
Get-BucketKeys -Bucket out-new | Format-Table

Write-Host "`n  --- Wildcard bucket ---" -ForegroundColor DarkGray
Get-BucketKeys -Bucket "out-*" | Format-Table

# ============================================================
# 5. Get-BucketObjectStats
# ============================================================
Write-Host "`n[5] Get-BucketObjectStats" -ForegroundColor Blue

Write-Host "`n  --- Per-object stats ---" -ForegroundColor DarkGray
Get-BucketObjectStats -Bucket out-new | Format-Table

Write-Host "`n  --- Single key ---" -ForegroundColor DarkGray
Get-BucketObjectStats -Bucket out-new -Key "a" | Format-List

Write-Host "`n  --- Missing key (warning) ---" -ForegroundColor DarkGray
Get-BucketObjectStats -Bucket out-new -Key "nonexistent" -WarningAction SilentlyContinue

# ============================================================
# 6. Get-BucketObject
# ============================================================
Write-Host "`n[6] Get-BucketObject" -ForegroundColor Blue

Write-Host "`n  --- All in bucket ---" -ForegroundColor DarkGray
Get-BucketObject -Bucket out-new | Format-Table _Id, Val

Write-Host "`n  --- Single key ---" -ForegroundColor DarkGray
Get-BucketObject -Bucket out-new -Key "a" | Format-List

Write-Host "`n  --- Match filter ---" -ForegroundColor DarkGray
Get-BucketObject -Bucket out-new -Match @{ Val = 3 } | Format-Table _Id, Val

Write-Host "`n  --- Scriptblock filter ---" -ForegroundColor DarkGray
Get-BucketObject -Bucket out-new -Filter { $_.Val -gt 2 } | Format-Table _Id, Val

Write-Host "`n  --- Funnel filter ---" -ForegroundColor DarkGray
Get-BucketObject -Bucket out-new -Funnel { if ($_.Val -gt 2) { $_ } } | Format-Table _Id, Val

Write-Host "`n  --- Missing bucket (warning) ---" -ForegroundColor DarkGray
$r = Get-BucketObject -Bucket nonexistent-xyz
Write-Host "  Result: $($null -eq $r) ($(@($r).Count) items)"

# ============================================================
# 7. Set-BucketObject
# ============================================================
Write-Host "`n[7] Set-BucketObject" -ForegroundColor Blue

Write-Host "`n  --- Update full object ---" -ForegroundColor DarkGray
$updated = Get-BucketObject -Bucket out-new -Key "a"
$updated.Val = 999
$updated | Set-BucketObject

Write-Host "`n  --- Patch (partial update) ---" -ForegroundColor DarkGray
@{ Val = 42 } | Set-BucketObject -Bucket out-new -Key "a"

Write-Host "`n  --- Set-BucketObject PassThru ---" -ForegroundColor DarkGray
$r = @{ Val = 7 } | Set-BucketObject -Bucket out-new -Key "a" -PassThru
$r | Format-List

Write-Host "`n  --- Set-BucketObject Quiet ---" -ForegroundColor DarkGray
@{ Val = 8 } | Set-BucketObject -Bucket out-new -Key "a" -Quiet
Write-Host "  (no output above)" -ForegroundColor DarkGray

Write-Host "`n  --- Missing bucket/key (throw) ---" -ForegroundColor DarkGray
try { Set-BucketObject -InputObject @{ Val = 1 } -ErrorAction Stop } catch { Write-Host "  $_" -ForegroundColor Red }

Write-Host "`n  --- Format fallback on set (circular ref) ---" -ForegroundColor DarkGray
$circSet = [PSCustomObject]@{ Val = "loop" }
$circSet | Add-Member -NotePropertyName "Self" -NotePropertyValue $circSet
Set-BucketObject -Bucket out-new -Key "a" -InputObject $circSet -WarningAction Continue

# ============================================================
# 8. Remove-BucketObject
# ============================================================
Write-Host "`n[8] Remove-BucketObject" -ForegroundColor Blue

New-BucketObject -Bucket out-rm -InputObject @(
    @{ _Id = "del1"; V = 1 },
    @{ _Id = "del2"; V = 2 },
    @{ _Id = "del3"; V = 3 },
    @{ _Id = "del4"; V = 4 },
    @{ _Id = "del5"; V = 5 },
    @{ _Id = "extra"; V = 6 }
) -KeyProperty _Id -Quiet
Use-Bucket "out-rm"

Write-Host "`n  --- Single key ---" -ForegroundColor DarkGray
Remove-BucketObject -Bucket out-rm -Key "del1" -Quiet

Write-Host "`n  --- Remove with PassThru ---" -ForegroundColor DarkGray
Remove-BucketObject -Bucket out-rm -Key "del2" -PassThru | Format-Table

Write-Host "`n  --- -Match pre-confirmation summary ---" -ForegroundColor DarkGray
Remove-BucketObject -Bucket out-rm -Match @{ V = 3 } -WhatIf

Write-Host "`n  --- -Filter pre-confirmation summary ---" -ForegroundColor DarkGray
Remove-BucketObject -Bucket out-rm -Filter { $_.V -gt 4 } -WhatIf

Write-Host "`n  --- -All WhatIf ---" -ForegroundColor DarkGray
Remove-BucketObject -Bucket out-rm -All -WhatIf

Write-Host "`n  --- -All actual removal ---" -ForegroundColor DarkGray
Remove-BucketObject -Bucket out-rm -All -Confirm:$false

Write-Host "`n  --- Missing key (warning) ---" -ForegroundColor DarkGray
Remove-BucketObject -Bucket out-new -Key "nonexistent" -WarningVariable w -WarningAction SilentlyContinue
Write-Host "  Warning: $w" -ForegroundColor DarkGray

Write-Host "`n  --- No -Key or -All (throw) ---" -ForegroundColor DarkGray
try { Remove-BucketObject -Bucket out-new -ErrorAction Stop } catch { Write-Host "  $_" -ForegroundColor Red }

# ============================================================
# 9. Remove-Bucket
# ============================================================
Write-Host "`n[9] Remove-Bucket" -ForegroundColor Blue

New-BucketObject -Bucket out-del1 -InputObject @{ _Id = "x"; V = 1 } -KeyProperty _Id -Quiet
New-BucketObject -Bucket out-del2 -InputObject @{ _Id = "y"; V = 2 } -KeyProperty _Id -Quiet
Use-Bucket "out-del1"
Use-Bucket "out-del2"

Write-Host "`n  --- -WhatIf ---" -ForegroundColor DarkGray
Remove-Bucket out-del1 -WhatIf

Write-Host "`n  --- -Force (no confirmation) ---" -ForegroundColor DarkGray
Remove-Bucket out-del1 -Force -Confirm:$false

Write-Host "`n  --- -Recurse ---" -ForegroundColor DarkGray
Remove-Bucket out-org -Recurse -Force -Confirm:$false

Write-Host "`n  --- Non-existent bucket (warning) ---" -ForegroundColor DarkGray
Remove-Bucket "nonexistent-xyz" -Force -Confirm:$false -WarningVariable w -WarningAction SilentlyContinue
Write-Host "  Warning: $w" -ForegroundColor DarkGray

Write-Host "`n  --- Bucket with non-bucket files (warning) ---" -ForegroundColor DarkGray
New-BucketObject -Bucket out-foreign -InputObject @{ _Id = "doc"; V = 1 } -KeyProperty _Id -Quiet
Use-Bucket "out-foreign"
$foreignPath = Join-Path (Get-BucketRoot) "out-foreign"
Set-Content -Path (Join-Path $foreignPath "readme.txt") -Value "foreign file" -ErrorAction SilentlyContinue
Remove-Bucket out-foreign -Confirm:$false -WarningVariable w -WarningAction SilentlyContinue 2>$null
Write-Host "  Warning: $w" -ForegroundColor DarkGray

# ============================================================
# 10. Copy-BucketObject
# ============================================================
Write-Host "`n[10] Copy-BucketObject" -ForegroundColor Blue

Write-Host "`n  --- Copy with key rename ---" -ForegroundColor DarkGray
Copy-BucketObject -Bucket out-new -Key "a" -DestinationBucket out-new -DestinationKey "a-copy" -PassThru | Format-Table

Write-Host "`n  --- Missing source bucket (throw) ---" -ForegroundColor DarkGray
try { Copy-BucketObject -Bucket nonexistent -Key "x" -DestinationBucket out-new -ErrorAction Stop } catch { Write-Host "  $_" -ForegroundColor Red }

# ============================================================
# 11. Move-BucketObject
# ============================================================
Write-Host "`n[11] Move-BucketObject" -ForegroundColor Blue

New-BucketObject -Bucket out-mvdst -InputObject @{ _Id = "placeholder"; V = 0 } -KeyProperty _Id -Quiet
Use-Bucket "out-mvdst"

Write-Host "`n  --- Move to another bucket ---" -ForegroundColor DarkGray
Move-BucketObject -Bucket out-new -Key "a-copy" -DestinationBucket out-mvdst -PassThru | Format-Table

# ============================================================
# 12. Rename-BucketObject
# ============================================================
Write-Host "`n[12] Rename-BucketObject" -ForegroundColor Blue

Write-Host "`n  --- Rename ---" -ForegroundColor DarkGray
Rename-BucketObject -Bucket out-new -Key "b" -NewKey "b-renamed" -PassThru | Format-Table

# ============================================================
# 13. Export-Bucket
# ============================================================
Write-Host "`n[13] Export-Bucket" -ForegroundColor Blue

$exportJson = Join-Path $testRoot "out-export.json"
$exportBin = Join-Path $testRoot "out-export.clixml"

Write-Host "`n  --- Export as JSON (default) ---" -ForegroundColor DarkGray
Export-Bucket -Bucket out-new -OutputFile $exportJson

Write-Host "`n  --- Export as binary (CLIXML) ---" -ForegroundColor DarkGray
Export-Bucket -Bucket out-new -OutputFile $exportBin -AsBinary

Write-Host "`n  --- Export empty bucket (warning) ---" -ForegroundColor DarkGray
New-BucketObject -Bucket out-empty -InputObject @() -KeyProperty _Id -Quiet -ErrorAction SilentlyContinue
Export-Bucket -Bucket nonexistent-xyz -OutputFile (Join-Path $testRoot "nope.json") -WarningVariable w -WarningAction SilentlyContinue

# ============================================================
# 14. Import-Bucket
# ============================================================
Write-Host "`n[14] Import-Bucket" -ForegroundColor Blue

Write-Host "`n  --- Import from JSON ---" -ForegroundColor DarkGray
Import-Bucket -Bucket out-imported -InputFile $exportJson

Write-Host "`n  --- Import from binary (CLIXML) ---" -ForegroundColor DarkGray
Import-Bucket -Bucket out-imported-bin -InputFile $exportBin -AsBinary

Write-Host "`n  --- Import with Overwrite ---" -ForegroundColor DarkGray
Import-Bucket -Bucket out-imported -InputFile $exportJson -Overwrite

Write-Host "`n  --- Import with skip (existing keys) ---" -ForegroundColor DarkGray
Import-Bucket -Bucket out-imported-bin -InputFile $exportBin -AsBinary

Write-Host "`n  --- Missing file (throw) ---" -ForegroundColor DarkGray
try { Import-Bucket -Bucket out-imported -InputFile "/nonexistent/file.json" -ErrorAction Stop } catch { Write-Host "  $_" -ForegroundColor Red }

Clean-Bucket "out-imported"
Clean-Bucket "out-imported-bin"
Remove-Item $exportJson, $exportBin -Force -ErrorAction SilentlyContinue

# ============================================================
# 15. Funnels
# ============================================================
Write-Host "`n[15] Funnels" -ForegroundColor Blue

Write-Host "`n  --- New-Funnel ---" -ForegroundColor DarkGray
New-Funnel -Name "demo-filter" -Filter { if ($_.Val -gt 0) { $_ } } -Description "Filters positive values" -Force

Write-Host "`n  --- New-Funnel (duplicate, throw) ---" -ForegroundColor DarkGray
try { New-Funnel -Name "demo-filter" -Filter { $_ } -ErrorAction Stop } catch { Write-Host "  $_" -ForegroundColor Red }

Write-Host "`n  --- Get-Funnel (all) ---" -ForegroundColor DarkGray
Get-Funnel | Format-Table

Write-Host "`n  --- Get-Funnel (single) ---" -ForegroundColor DarkGray
Get-Funnel -Name "demo-filter" | Format-List

Write-Host "`n  --- Set-Funnel ---" -ForegroundColor DarkGray
Set-Funnel -Name "demo-filter" -Filter { if ($_.Val -ge 0) { $_ } } -Description "Updated filter"

Write-Host "`n  --- Remove-Funnel -WhatIf ---" -ForegroundColor DarkGray
Remove-Funnel -Name "demo-filter" -WhatIf

Write-Host "`n  --- Remove-Funnel ---" -ForegroundColor DarkGray
Remove-Funnel -Name "demo-filter" -Confirm:$false

Write-Host "`n  --- Built-in funnel (file-light) ---" -ForegroundColor DarkGray
Get-Funnel -Name "file-light" | Format-List

Write-Host "`n  --- Remove built-in (throw) ---" -ForegroundColor DarkGray
try { Remove-Funnel -Name "file-light" -Confirm:$false -ErrorAction Stop } catch { Write-Host "  $_" -ForegroundColor Red }

Write-Host "`n  --- Missing funnel (throw) ---" -ForegroundColor DarkGray
try { Remove-Funnel -Name "nonexistent" -Confirm:$false -ErrorAction Stop } catch { Write-Host "  $_" -ForegroundColor Red }

# ============================================================
# 16. Sync-BucketDrive & Get-BucketRoot
# ============================================================
Write-Host "`n[16] BucketRoot and Sync" -ForegroundColor Blue

Write-Host "`n  --- Get-BucketRoot ---" -ForegroundColor DarkGray
Get-BucketRoot

Write-Host "`n  --- Set-BucketRoot ---" -ForegroundColor DarkGray
Set-BucketRoot $testRoot
Write-Host "  Root is now: $(Get-BucketRoot)" -ForegroundColor DarkGray

# ============================================================
# Cleanup
# ============================================================
Write-Host "`n========================================" -ForegroundColor Blue
Write-Host " Cleanup" -ForegroundColor Blue
Write-Host "========================================`n" -ForegroundColor Blue

foreach ($b in $createdBuckets) { Remove-Bucket $b -Force -Confirm:$false -Recurse -WarningAction SilentlyContinue -Quiet -ErrorAction SilentlyContinue }
Set-BucketRoot (Join-Path $HOME ".buckets")
Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  Done" -ForegroundColor Green