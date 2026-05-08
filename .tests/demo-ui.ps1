#!/usr/bin/env pwsh
<#
.SYNOPSIS
    UI/UX showcase for the Buckets module.
.DESCRIPTION
    End-to-end walkthrough demonstrating all cmdlets and their visual output
    — colored summaries, tree views, stats, filtering, and pipeline operations.
#>

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

$demoDir = Join-Path $HOME ".buckets-demo"
if (Test-Path $demoDir) { Remove-Item $demoDir -Recurse -Force }

$sw = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Blue
Write-Host "║      Buckets Module — UI/UX Demo         ║" -ForegroundColor Blue
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Blue

# Set demo path
Set-BucketRoot $demoDir

# ============================================================
# 1. New-BucketObject — bulk save with output summary
# ============================================================
Write-Host "`n── 1. New-BucketObject ──────────────────────" -ForegroundColor Blue

Write-Host "`n  Saving users (hashtables, keyed by Name):" -ForegroundColor DarkGray
$users = @(
    @{ Name = "Alice";   Email = "alice@example.com";   Role = "admin";   Active = $true }
    @{ Name = "Bob";     Email = "bob@example.com";     Role = "user";    Active = $true }
    @{ Name = "Charlie"; Email = "charlie@example.com"; Role = "user";    Active = $false }
    @{ Name = "Diana";   Email = "diana@example.com";   Role = "manager"; Active = $true }
    @{ Name = "Eve";     Email = "eve@example.com";     Role = "user";    Active = $true }
)
New-BucketObject -Bucket users -InputObject $users -KeyProperty Name

Write-Host "`n  Saving nested orders (PSCustomObject):" -ForegroundColor DarkGray
$orders = @(
    [PSCustomObject]@{
        OrderId  = "ORD-001"; Customer = "Alice"
        Items    = @([PSCustomObject]@{ Product = "Widget"; Qty = 3; Price = 9.99 })
        Shipping = [PSCustomObject]@{ Method = "Express"; Address = "Portland, OR" }
    }
    [PSCustomObject]@{
        OrderId  = "ORD-002"; Customer = "Bob"
        Items    = @([PSCustomObject]@{ Product = "Gadget"; Qty = 1; Price = 49.99 })
        Shipping = [PSCustomObject]@{ Method = "Standard"; Address = "Austin, TX" }
    }
)
New-BucketObject -Bucket orders -InputObject $orders -KeyProperty OrderId

Write-Host "`n  Saving compressed config (binary + GZip):" -ForegroundColor DarkGray
$config = [PSCustomObject]@{
    _Id = "app-config"; Version = "2.1.0"
    Database = [PSCustomObject]@{ Host = "localhost"; Port = 5432; Name = "app_db" }
    Cache    = [PSCustomObject]@{ Provider = "Redis"; TTL = 3600 }
}
New-BucketObject -Bucket config -InputObject $config -KeyProperty _Id -Compress

Write-Host "`n  Saving JSON config (explicit -AsJson):" -ForegroundColor DarkGray
$jsonConfig = [PSCustomObject]@{
    _Id = "web-config"; Theme = "dark"; Language = "en"
}
New-BucketObject -Bucket config -InputObject $jsonConfig -KeyProperty _Id -AsJson

# ============================================================
# 2. Get-Bucket — tree view
# ============================================================
Write-Host "`n── 2. Get-Bucket ──────────────────────────" -ForegroundColor Blue
Write-Host "`n  Table view:" -ForegroundColor DarkGray
Get-Bucket | Format-Table -AutoSize

Write-Host "  Tree view:" -ForegroundColor DarkGray
Get-Bucket -AsTree

# ============================================================
# 3. Get-BucketObject — retrieval
# ============================================================
Write-Host "── 3. Get-BucketObject ─────────────────────" -ForegroundColor Blue

Write-Host "`n  All users:" -ForegroundColor DarkGray
Get-BucketObject -Bucket users | Format-Table Name, Email, Role, Active

Write-Host "  Filter by Role = 'admin':" -ForegroundColor DarkGray
Get-BucketObject -Bucket users -Filter { $_.Role -eq "admin" } | Format-Table Name, Email, Role

Write-Host "  Match hashtable (Active = false):" -ForegroundColor DarkGray
Get-BucketObject -Bucket users -Match @{ Active = $false } | Format-Table Name, Email

Write-Host "  Exact key lookup:" -ForegroundColor DarkGray
$alice = Get-BucketObject -Bucket users -Key "Alice"
Write-Host "    " -NoNewline
Write-Host "$($alice.Name)" -NoNewline -ForegroundColor Cyan
Write-Host " <$($alice.Email)> — " -NoNewline
Write-Host "$($alice.Role)" -ForegroundColor Yellow

# ============================================================
# 4. Get-BucketStats
# ============================================================
Write-Host "`n── 4. Get-BucketStats ──────────────────────" -ForegroundColor Blue
Write-Host ""
foreach ($b in (Get-Bucket)) {
    $stats = Get-BucketStats -Bucket $b.Name
    Write-Host "  " -NoNewline
    Write-Host "$($b.Name)" -NoNewline -ForegroundColor Cyan
    Write-Host " · $($stats.ObjectCount) objects" -NoNewline -ForegroundColor Magenta
    Write-Host " · $([math]::Round($stats.SizeBytes / 1KB, 1)) KB" -ForegroundColor DarkGray
}

# ============================================================
# 5. Copy, Rename, Move
# ============================================================
Write-Host "`n── 5. Copy / Rename / Move ───────────────────" -ForegroundColor Blue

Write-Host "`n  Copy-BucketObject (cross-bucket):" -ForegroundColor DarkGray
Copy-BucketObject -Bucket users -Key "Alice" -DestinationBucket backup

Write-Host "`n  Rename-BucketObject (in-place):" -ForegroundColor DarkGray
Rename-BucketObject -Bucket backup -Key "Alice" -NewKey "alice-backup"

Write-Host "`n  Move-BucketObject:" -ForegroundColor DarkGray
New-BucketObject -Bucket staging -InputObject ([PSCustomObject]@{ _Id = "tmp-item"; Value = "move me" }) -KeyProperty _Id -Quiet
Move-BucketObject -Bucket staging -Key "tmp-item" -DestinationBucket archive

Write-Host "`n  Tree after moves:" -ForegroundColor DarkGray
Get-Bucket -AsTree

# ============================================================
# 6. Export / Import
# ============================================================
Write-Host "── 6. Export / Import ────────────────────────" -ForegroundColor Blue

$exportFile = Join-Path $PSScriptRoot "demo-export.clixml"
$exportJson = Join-Path $PSScriptRoot "demo-export.json"

Write-Host "`n  Export-Bucket (CLIXML):" -ForegroundColor DarkGray
Export-Bucket -Bucket users -OutputFile $exportFile

Write-Host "`n  Export-Bucket (JSON):" -ForegroundColor DarkGray
Export-Bucket -Bucket users -OutputFile $exportJson -AsJson

Write-Host "`n  Import-Bucket (restore):" -ForegroundColor DarkGray
Import-Bucket -Bucket restored-users -InputFile $exportFile

Remove-Item $exportFile, $exportJson -Force

# ============================================================
# 7. Remove-BucketObject
# ============================================================
Write-Host "── 7. Remove-BucketObject ───────────────────" -ForegroundColor Blue

Write-Host "`n  Remove single key:" -ForegroundColor DarkGray
Remove-BucketObject -Bucket staging -Key "tmp-item" -WarningAction SilentlyContinue

Write-Host "`n  Remove-All with WhatIf:" -ForegroundColor DarkGray
Remove-BucketObject -Bucket staging -All -WhatIf -WarningAction SilentlyContinue

Write-Host "`n  Remove-All (actual):" -ForegroundColor DarkGray
Remove-BucketObject -Bucket staging -All -WarningAction SilentlyContinue

# ============================================================
# 8. Remove-Bucket
# ============================================================
Write-Host "── 8. Remove-Bucket ─────────────────────────" -ForegroundColor Blue

Write-Host "`n  Remove empty bucket:" -ForegroundColor DarkGray
Remove-Bucket staging -Force -Confirm:$false -WarningAction SilentlyContinue

Write-Host "`n  Bucket overview after cleanup:" -ForegroundColor DarkGray
Get-Bucket -AsTree

# ============================================================
# 9. Set-BucketObject — partial update
# ============================================================
Write-Host "── 9. Set-BucketObject (partial update) ──────" -ForegroundColor Blue

Write-Host "`n  Patch email on Alice:" -ForegroundColor DarkGray
@{ Email = "alice@newdomain.com" } | Set-BucketObject -Bucket users -Key "Alice"
$updated = Get-BucketObject -Bucket users -Key "Alice"
Write-Host "    " -NoNewline -ForegroundColor DarkGray
Write-Host "Name: $($updated.Name)" -NoNewline -ForegroundColor Cyan
Write-Host ", Email: " -NoNewline -ForegroundColor DarkGray
Write-Host "$($updated.Email)" -NoNewline -ForegroundColor Yellow
Write-Host ", Role: $($updated.Role)" -ForegroundColor DarkGray

# ============================================================
# 10. Nested buckets (app logs simulation)
# ============================================================
Write-Host "`n── 10. Nested buckets (server logs) ─────────" -ForegroundColor Blue

Write-Host "`n  Generating server logs:" -ForegroundColor DarkGray
$servers = @("web-01", "web-02", "db-01")
foreach ($server in $servers) {
    $logBucket = "servers/$server/logs"
    $logs = 1..6 | ForEach-Object {
        $level = @("INFO", "INFO", "INFO", "WARN", "INFO", "ERROR")[$_ - 1]
        [PSCustomObject]@{
            _Id       = "log-$server-$_"
            Timestamp = [DateTime]::Now.AddMinutes(-$_)
            Level     = $level
            Message   = @("Request processed", "Health check OK", "Cache hit", "Slow query detected", "Session refreshed", "Connection timeout")[$_ - 1]
        }
    }
    New-BucketObject -Bucket $logBucket -InputObject $logs -KeyProperty _Id -Quiet
}
New-BucketObject -Bucket "servers" -InputObject ([PSCustomObject]@{ _Id = "overview"; ServerCount = $servers.Count }) -KeyProperty _Id -Quiet

Get-Bucket -AsTree -Name servers

Write-Host "`n  Server error queries:" -ForegroundColor DarkGray
foreach ($srv in $servers) {
    $errors = Get-BucketObject -Bucket "servers/$srv/logs" -Filter { $_.Level -eq "ERROR" }
    if ($errors) {
        Write-Host "  " -NoNewline
        Write-Host "$srv" -NoNewline -ForegroundColor Cyan
        Write-Host " errors:"
        foreach ($e in $errors) {
            Write-Host "    " -NoNewline -ForegroundColor DarkGray
            Write-Host "[$($e.Level)]" -NoNewline -ForegroundColor Red
            Write-Host " $($e.Message)" -ForegroundColor DarkGray
        }
    }
}

# ============================================================
# Summary
# ============================================================
$elapsed = $sw.Elapsed.TotalSeconds
Write-Host "`n╔══════════════════════════════════════════╗" -ForegroundColor Blue
Write-Host "║  Demo complete" -NoNewline
Write-Host " · $([math]::Round($elapsed, 1))s" -NoNewline -ForegroundColor Magenta
Write-Host "          ║" -ForegroundColor Blue
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Blue

Write-Host "`nExplore the data yourself:" -ForegroundColor DarkGray
Write-Host "  Get-Bucket -AsTree" -ForegroundColor Cyan
Write-Host "  Get-BucketObject -Bucket users" -ForegroundColor Cyan
Write-Host "  Get-BucketStats -Bucket users" -ForegroundColor Cyan

# Cleanup
Remove-Item $demoDir -Recurse -Force
