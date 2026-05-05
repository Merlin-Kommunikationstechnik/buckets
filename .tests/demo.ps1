# Buckets Module Demo — To-Do Application
# Shows practical usage of the module for a real-world scenario

$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot "../Buckets"

if (-not (Get-Module Buckets)) {
    Import-Module $modulePath -Force
}

# Clean slate
Remove-Bucket "todos" -Force -Confirm:$false -WarningAction SilentlyContinue
Remove-Bucket "projects" -Force -Confirm:$false -WarningAction SilentlyContinue
Remove-Bucket "archive" -Force -Confirm:$false -WarningAction SilentlyContinue

# ============================================================
# 1. Create projects
# ============================================================
Write-Host "`n--- Demo: Creating projects ---" -ForegroundColor Cyan

$projects = @(
    [PSCustomObject]@{ Id = "proj-001"; Name = "Website Redesign"; Owner = "Alice"; Deadline = [DateTime]"2026-06-15"; Active = $true }
    [PSCustomObject]@{ Id = "proj-002"; Name = "Q3 Report"; Owner = "Bob"; Deadline = [DateTime]"2026-04-01"; Active = $true }
    [PSCustomObject]@{ Id = "proj-003"; Name = "Archive Project"; Owner = "Charlie"; Deadline = [DateTime]"2025-01-01"; Active = $false }
)

$projects | New-BucketObject -Bucket projects -Key Id -Quiet
Write-Host "Created $($projects.Count) projects"

# ============================================================
# 2. Create to-do items
# ============================================================
Write-Host "`n--- Demo: Creating to-do items ---" -ForegroundColor Cyan

$todos = @(
    [PSCustomObject]@{ Id = 1; ProjectId = "proj-001"; Title = "Design homepage mockup"; Status = "done"; Priority = "high"; Tags = @("design", "ui"); Created = [DateTimeOffset]::Now }
    [PSCustomObject]@{ Id = 2; ProjectId = "proj-001"; Title = "Implement responsive navbar"; Status = "in-progress"; Priority = "high"; Tags = @("dev", "frontend"); Created = [DateTimeOffset]::Now }
    [PSCustomObject]@{ Id = 3; ProjectId = "proj-001"; Title = "Add contact form"; Status = "todo"; Priority = "medium"; Tags = @("dev", "backend"); Created = [DateTimeOffset]::Now }
    [PSCustomObject]@{ Id = 4; ProjectId = "proj-002"; Title = "Gather Q2 metrics"; Status = "done"; Priority = "high"; Tags = @("data"); Created = [DateTimeOffset]::Now }
    [PSCustomObject]@{ Id = 5; ProjectId = "proj-002"; Title = "Write executive summary"; Status = "todo"; Priority = "medium"; Tags = @("writing"); Created = [DateTimeOffset]::Now }
    [PSCustomObject]@{ Id = 6; ProjectId = "proj-002"; Title = "Create charts"; Status = "todo"; Priority = "low"; Tags = @("data", "design"); Created = [DateTimeOffset]::Now }
    [PSCustomObject]@{ Id = 7; ProjectId = "proj-003"; Title = "Organize old files"; Status = "todo"; Priority = "low"; Tags = @("admin"); Created = [DateTimeOffset]::Now }
)

$todos | New-BucketObject -Bucket todos -Key Id -Quiet
Write-Host "Created $($todos.Count) to-do items"

# ============================================================
# 3. Filter: all active project todos
# ============================================================
Write-Host "`n--- Active todos with high priority ---" -ForegroundColor Yellow

$activeTodos = Get-BucketObject -Bucket todos -Filter { $_.Status -ne "done" } |
    Where-Object { $_.Priority -eq "high" }

foreach ($t in $activeTodos) {
    Write-Host "  [$($t.Priority)] $($t.Title) ($($t.Status))" -ForegroundColor DarkGray
}

# ============================================================
# 4. Filter: todos by project using -Match
# ============================================================
Write-Host "`n--- Todos for Website Redesign ---" -ForegroundColor Yellow

$webTodos = Get-BucketObject -Bucket todos -Match @{ ProjectId = "proj-001" }
foreach ($t in $webTodos) {
    $statusIcon = switch ($t.Status) {
        "done" { "[x]" }
        "in-progress" { "[~]" }
        "todo" { "[ ]" }
    }
    Write-Host "  $statusIcon $($t.Title)" -ForegroundColor DarkGray
}

# ============================================================
# 5. Update: mark a todo as done
# ============================================================
Write-Host "`n--- Demo: Mark item 2 as done ---" -ForegroundColor Cyan

$todo2 = Get-BucketObject -Key 2 -Bucket todos
$todo2.Status = "done"
$todo2 | Set-BucketObject -Bucket todos -Key Id -Quiet
Write-Host "Item 2 status is now: $((Get-BucketObject -Key 2 -Bucket todos).Status)"

# ============================================================
# 6. Partial update: change priority via Set-BucketObject
# ============================================================
Write-Host "`n--- Demo: Partial update — change priority of item 3 to 'low' ---" -ForegroundColor Cyan

Set-BucketObject -InputObject ([PSCustomObject]@{ Id = 3; Priority = "low" }) -Bucket todos -Key Id -Quiet
$item3 = Get-BucketObject -Key 3 -Bucket todos
Write-Host "Item 3 priority is now: $($item3.Priority)"

# ============================================================
# 7. Rename a todo key
# ============================================================
Write-Host "`n--- Demo: Rename item 6 to 6b (reordered) ---" -ForegroundColor Cyan

Rename-BucketObject -Bucket todos -Key 6 -NewKey 6b -Quiet
$keys = Get-BucketObject -Bucket todos | Sort-Object Id | ForEach-Object { $_.Id }
Write-Host "Current keys: $($keys -join ', ')"

# ============================================================
# 8. Copy a todo to another bucket (archive)
# ============================================================
Write-Host "`n--- Demo: Copy completed items to archive bucket ---" -ForegroundColor Cyan

Remove-Bucket archive -Force -Confirm:$false -WarningAction SilentlyContinue
$doneItems = Get-BucketObject -Bucket todos -Match @{ Status = "done" }
$doneItems | ForEach-Object {
    Copy-BucketObject -Bucket todos -Key $_.Id -DestinationBucket archive -DestinationKey $_.Id -Quiet
}
$archiveCount = @(Get-BucketObject -Bucket archive).Count
Write-Host "Archived $archiveCount completed items"

# ============================================================
# 9. Get-Bucket — list all buckets
# ============================================================
Write-Host "`n--- Demo: All buckets ---" -ForegroundColor Cyan

Get-Bucket | ForEach-Object {
    $stats = Get-BucketStats -Bucket $_.Name
    Write-Host "  $($_.Name): $($stats.ObjectCount) objects, $($stats.TotalSizeFormatted)" -ForegroundColor DarkGray
}

# ============================================================
# 10. Export/Import — backup and restore
# ============================================================
Write-Host "`n--- Demo: Export and restore todos ---" -ForegroundColor Cyan

$exportPath = Join-Path $PSScriptRoot "todos-export.clixml"
Export-Bucket -Bucket todos -OutputFile $exportPath -Quiet
Write-Host "Exported to: $exportPath"

# Simulate restore: delete and re-import
Remove-Bucket todos -Force -Confirm:$false -WarningAction SilentlyContinue
$beforeCount = @(Get-BucketObject -Bucket todos -WarningAction SilentlyContinue).Count
Write-Host "After delete: $beforeCount items"

Import-Bucket -Bucket todos -InputFile $exportPath -Quiet
$afterCount = @(Get-BucketObject -Bucket todos).Count
Write-Host "After import: $afterCount items"

# Cleanup temp file
Remove-Item $exportPath -Force -ErrorAction SilentlyContinue

# ============================================================
# 11. Remove completed todos
# ============================================================
Write-Host "`n--- Demo: Remove all done items ---" -ForegroundColor Cyan

$doneIds = Get-BucketObject -Bucket todos -Match @{ Status = "done" } | ForEach-Object { $_.Id }
$doneIds | ForEach-Object {
    Remove-BucketObject -Bucket todos -Key $_ -Quiet
}
$remaining = @(Get-BucketObject -Bucket todos).Count
Write-Host "Removed $($doneIds.Count) done items, $remaining remaining"

# ============================================================
# 12. Final state
# ============================================================
Write-Host "`n--- Final todo list ---" -ForegroundColor Cyan

$finalTodos = Get-BucketObject -Bucket todos | Sort-Object Id
foreach ($t in $finalTodos) {
    $project = Get-BucketObject -Key $t.ProjectId -Bucket projects
    Write-Host "  [$($t.Priority.ToUpper())] $($t.Title) -> $($project.Name)" -ForegroundColor DarkGray
}

Write-Host "`nDemo complete." -ForegroundColor Green
