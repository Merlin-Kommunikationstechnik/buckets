#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Demonstrates multi-emit funnels — funnels that split one input into multiple stored objects.
.DESCRIPTION
    Shows: Transform rename, multi-emit on fill (splitting objects), multi-emit on scoop
    (expanding objects), within-batch key indexing, null skipping, and Expanded counter.

    Usage:  .tests/demo/multi-emit-demo.ps1
#>

$ErrorActionPreference = "Stop"

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../../Buckets" -Force

$root = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-demo-multi-emit"
Set-BucketRoot $root

# Clean slate from any prior failed run
Remove-BucketItem -Bucket orders, servers, events, reports, mixed, colors -Drop -Force -Confirm:$false -Recurse -Quiet -ErrorAction SilentlyContinue
Remove-Funnel -Name demo-split -Quiet -Confirm:$false -ErrorAction SilentlyContinue
Remove-Funnel -Name demo-index -Quiet -Confirm:$false -ErrorAction SilentlyContinue

Write-Host "========== Multi-emit funnel demo ==========" -ForegroundColor Cyan

# --- 1. Transform (was Filter) rename ---
Write-Host "`n[1]  New-Funnel uses -Transform (was -Filter)" -ForegroundColor Blue
Write-Host "  Creating a named funnel that splits Items array into individual objects" -ForegroundColor DarkGray
New-Funnel -Name "demo-split" -Transform {
    $orderId = $_.OrderId
    $_.Items | ForEach-Object { [PSCustomObject]@{ Item = $_; Order = $orderId } }
} -Description "Splits Items array into individual objects" -Force

$f = Get-Funnel -Name demo-split
Write-Host "  Name: $($f.Name)" -ForegroundColor DarkGray
Write-Host "  Transform: $($f.Transform)" -ForegroundColor DarkGray
Write-Host "  Description: $($f.Description)" -ForegroundColor DarkGray

# --- 2. Multi-emit on fill ---
Write-Host "`n[2]  Multi-emit on fill — split a compound object into parts" -ForegroundColor Blue

$order = @{
    OrderId = "ORD-2026-001"
    Customer = "Acme Corp"
    Items = @("Widget", "Gadget", "Doodad")
}
Write-Host "  Source object has 1 OrderId and 3 Items" -ForegroundColor DarkGray
Write-Host "  Funnel splits Items into individual stored objects" -ForegroundColor DarkGray
New-BucketObject -Bucket orders -InputObject $order -KeyProperty Item -Funnel demo-split -PassThru | Format-List Saved, Expanded, StoredKeys

Write-Host "  Objects stored:" -ForegroundColor DarkGray
Get-BucketObject -Bucket orders | Format-Table Item, Order, _BucketKey

# --- 3. Ad-hoc scriptblock on fill ---
Write-Host "`n[3]  Ad-hoc scriptblock on fill" -ForegroundColor Blue

$server = @{
    Host = "db-01"
    Services = @("postgresql", "redis", "nginx")
}
Write-Host "  Same shape as [2] but uses inline scriptblock instead of named funnel" -ForegroundColor DarkGray
New-BucketObject -Bucket servers -InputObject $server -KeyProperty Service -Funnel {
    $hostName = $_.Host
    $_.Services | ForEach-Object { [PSCustomObject]@{ Service = $_; Host = $hostName } }
} -PassThru | Format-List Saved, Expanded, StoredKeys

Write-Host "  Services stored:" -ForegroundColor DarkGray
Get-BucketObject -Bucket servers | Format-Table Service, Host, _BucketKey

# --- 4. Within-batch key indexing ---
Write-Host "`n[4]  Within-batch key indexing with literal -Key" -ForegroundColor Blue

$batch = @{ Type = "event"; Payload = @("start", "stop") }
Write-Host "  Funnel emits 2 items from a single input with -Key 'batch-run'" -ForegroundColor DarkGray
Write-Host "  Second item auto-gets _1 suffix to avoid key collision" -ForegroundColor DarkGray
New-Funnel -Name "demo-index" -Transform {
    $eventType = $_.Type
    $_.Payload | ForEach-Object { [PSCustomObject]@{ Event = $_; Type = $eventType } }
} -Force -Quiet

$result = New-BucketObject -Bucket events -InputObject $batch -Key "batch-run" -Funnel demo-index -PassThru
Write-Host "  Saved: $($result.Saved)  Expanded: $($result.Expanded)" -ForegroundColor DarkGray
Write-Host "  Keys: $($result.StoredKeys -join ', ')" -ForegroundColor DarkGray

# --- 5. Multi-emit on scoop ---
Write-Host "`n[5]  Multi-emit on scoop — expand stored object into parts" -ForegroundColor Blue

$compound = @{
    _Id = "report-Q1"
    Title = "Q1 Summary"
    Sections = @("Revenue", "Costs", "Headcount")
}
Write-Host "  Storing one compound report object, then expanding Sections on read" -ForegroundColor DarkGray
New-BucketObject -Bucket reports -InputObject $compound -KeyProperty _Id -Quiet

$sections = Get-BucketObject -Bucket reports -Key report-Q1 -Funnel {
    $title = $_.Title
    $_.Sections | ForEach-Object { [PSCustomObject]@{ Section = $_; ReportTitle = $title } }
}
Write-Host "  Scoop expanded $($sections.Count) items:" -ForegroundColor DarkGray
$sections | Format-Table Section, ReportTitle, _BucketKey, _BucketName

# --- 6. Null entries skipped ---
Write-Host "`n[6]  Null entries in emitted array are skipped" -ForegroundColor Blue

$mixed = @{ _Id = "mixed-input"; Values = @(1, $null, 2, $null, 3) }
Write-Host "  Array has 5 values including 2 nulls — funnel silently drops nulls" -ForegroundColor DarkGray
New-BucketObject -Bucket mixed -InputObject $mixed -KeyProperty _Id -Quiet

$clean = Get-BucketObject -Bucket mixed -Key mixed-input -Funnel {
    $src = $_.Id
    $_.Values | ForEach-Object { if ($_ -ne $null) { [PSCustomObject]@{ Value = $_; Source = $src } } else { $null } }
}
Write-Host "  Filters $($mixed.Values.Count - $clean.Count) null entries, keeps $($clean.Count) values" -ForegroundColor DarkGray
$clean | Format-Table Value, _BucketKey, _BucketName

# --- 7. Expanded counter in output ---
Write-Host "`n[7]  Expanded counter shown in summary" -ForegroundColor Blue

$obj = @{ Group = "Colors"; Members = @("Red", "Green", "Blue") }
Write-Host "  Summary line shows 'N expanded (multi-emit funnel)' when expansion occurs" -ForegroundColor DarkGray
New-BucketObject -Bucket colors -InputObject $obj -KeyProperty Color -Funnel {
    $grp = $_.Group
    $_.Members | ForEach-Object { [PSCustomObject]@{ Color = $_; Group = $grp } }
}

# --- cleanup ---
Write-Host "`n--- cleanup ---" -ForegroundColor DarkGray
Write-Host "  Removing funnels, buckets, and temp directory" -ForegroundColor DarkGray
Remove-Funnel -Name demo-split -Quiet -Confirm:$false
Remove-Funnel -Name demo-index -Quiet -Confirm:$false
Remove-BucketItem -Bucket orders, servers, events, reports, mixed, colors -Drop -Force -Confirm:$false -Recurse -Quiet
Set-BucketRoot (Join-Path $HOME ".buckets")
Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "done" -ForegroundColor Green
