# Buckets Module Demo — Interactive To-Do Application
# A command-line to-do manager backed by Buckets

$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot "../Buckets"

if (-not (Get-Module Buckets)) {
    Import-Module $modulePath -Force
}

# --- Project data (pre-seeded if missing) ---
function Initialize-Data {
    $existing = @(Get-BucketObject -Bucket projects -WarningAction SilentlyContinue)
    if ($existing.Count -eq 0) {
        @(
            [PSCustomObject]@{ Id = "proj-001"; Name = "Website Redesign"; Active = $true }
            [PSCustomObject]@{ Id = "proj-002"; Name = "Q3 Report"; Active = $true }
            [PSCustomObject]@{ Id = "proj-003"; Name = "Archive Project"; Active = $false }
        ) | New-BucketObject -Bucket projects -Key Id -Quiet
    }
}
Initialize-Data

function Show-Header {
    Write-Host "`n  === Buckets To-Do ===" -ForegroundColor Cyan
}

function Show-Menu {
    Write-Host "`n  [1] List todos" -ForegroundColor White
    Write-Host "  [2] Add todo" -ForegroundColor White
    Write-Host "  [3] Edit todo" -ForegroundColor White
    Write-Host "  [4] Delete todo" -ForegroundColor White
    Write-Host "  [5] Filter by status" -ForegroundColor White
    Write-Host "  [6] Filter by project" -ForegroundColor White
    Write-Host "  [7] Filter by priority" -ForegroundColor White
    Write-Host "  [q] Quit" -ForegroundColor White
    Write-Host "`n  > " -ForegroundColor Yellow -NoNewline
}

function Format-Todo {
    param([PSObject]$Todo)
    $project = Get-BucketObject -Key $Todo.ProjectId -Bucket projects -WarningAction SilentlyContinue
    $projName = if ($project) { $project.Name } else { "(unknown)" }

    $icon = switch ($Todo.Status) {
        "done"        { "[x]" }
        "in-progress" { "[~]" }
        default       { "[ ]" }
    }
    $priColor = switch ($Todo.Priority) {
        "high"   { "Red" }
        "medium" { "Yellow" }
        "low"    { "DarkGray" }
    }

    Write-Host "  $icon " -ForegroundColor DarkGray -NoNewline
    Write-Host "$($Todo.Id.ToString().PadLeft(3)) " -ForegroundColor DarkGray -NoNewline
    Write-Host "$($Todo.Title)" -ForegroundColor White -NoNewline
    Write-Host " ($projName)" -ForegroundColor DarkGray
    Write-Host "      Status: $($Todo.Status)" -NoNewline
    Write-Host "  Priority: " -NoNewline
    Write-Host "$($Todo.Priority)" -ForegroundColor $priColor
    Write-Host ""
}

function Get-NextId {
    $all = @(Get-BucketObject -Bucket todos -WarningAction SilentlyContinue)
    if ($all.Count -eq 0) { return 1 }
    return ($all | ForEach-Object { $_.Id } | Measure-Object -Maximum).Maximum + 1
}

function Action-List {
    $todos = @(Get-BucketObject -Bucket todos -WarningAction SilentlyContinue) | Sort-Object Id
    if ($todos.Count -eq 0) {
        Write-Host "`n  No todos yet." -ForegroundColor DarkGray
        return
    }
    Write-Host "`n  All todos ($($todos.Count)):" -ForegroundColor Cyan
    foreach ($t in $todos) { Format-Todo $t }
}

function Action-Add {
    Write-Host "`n  --- Add Todo ---" -ForegroundColor Cyan

    Write-Host "  Projects:" -ForegroundColor Yellow
    $projects = @(Get-BucketObject -Bucket projects -WarningAction SilentlyContinue | Where-Object { $_.Active }) | Sort-Object Id
    foreach ($p in $projects) {
        Write-Host "    $($p.Id) - $($p.Name)" -ForegroundColor DarkGray
    }

    $projId = Read-Host "`n  Project ID"
    $projExists = Get-BucketObject -Key $projId -Bucket projects -WarningAction SilentlyContinue
    if (-not $projExists) {
        Write-Host "  Unknown project." -ForegroundColor Red
        return
    }

    $title = Read-Host "  Title"
    if ([string]::IsNullOrWhiteSpace($title)) {
        Write-Host "  Title required." -ForegroundColor Red
        return
    }

    Write-Host "  Priority (high/medium/low): " -NoNewline
    $priority = Read-Host ""
    if ($priority -notin @("high", "medium", "low")) { $priority = "medium" }

    $newTodo = [PSCustomObject]@{
        Id        = Get-NextId
        ProjectId = $projId
        Title     = $title
        Status    = "todo"
        Priority  = $priority
        Tags      = @()
        Created   = [DateTimeOffset]::Now
    }

    $newTodo | New-BucketObject -Bucket todos -Key Id -Quiet
    Write-Host "  Added todo #$($newTodo.Id)" -ForegroundColor Green
}

function Action-Edit {
    Write-Host "`n  --- Edit Todo ---" -ForegroundColor Cyan
    $key = Read-Host "  Todo ID"

    $todo = Get-BucketObject -Key $key -Bucket todos -WarningAction SilentlyContinue
    if (-not $todo) {
        Write-Host "  Todo #$key not found." -ForegroundColor Red
        return
    }

    Write-Host "`n  Current: $($todo.Title) [status: $($todo.Status), priority: $($todo.Priority)]" -ForegroundColor DarkGray
    Write-Host "  Leave blank to keep current value." -ForegroundColor DarkGray

    $title = Read-Host "  Title ($($todo.Title))"
    if (-not [string]::IsNullOrWhiteSpace($title)) { $todo.Title = $title }

    $status = Read-Host "  Status (todo/in-progress/done)"
    if ($status -in @("todo", "in-progress", "done")) { $todo.Status = $status }

    $priority = Read-Host "  Priority (high/medium/low)"
    if ($priority -in @("high", "medium", "low")) { $todo.Priority = $priority }

    $todo | Set-BucketObject -Bucket todos -Key Id -Quiet
    Write-Host "  Updated #$($todo.Id)" -ForegroundColor Green
}

function Action-Delete {
    Write-Host "`n  --- Delete Todo ---" -ForegroundColor Cyan
    $key = Read-Host "  Todo ID to delete"

    $todo = Get-BucketObject -Key $key -Bucket todos -WarningAction SilentlyContinue
    if (-not $todo) {
        Write-Host "  Todo #$key not found." -ForegroundColor Red
        return
    }

    $confirm = Read-Host "  Delete '$($todo.Title)'? (y/n)"
    if ($confirm -eq "y") {
        Remove-BucketObject -Bucket todos -Key $key -Quiet
        Write-Host "  Deleted #$key" -ForegroundColor Green
    }
}

function Action-FilterStatus {
    Write-Host "`n  Filter by status (todo/in-progress/done): " -ForegroundColor Cyan -NoNewline
    $status = Read-Host ""
    if ($status -notin @("todo", "in-progress", "done")) {
        Write-Host "  Invalid status." -ForegroundColor Red
        return
    }

    $todos = @(Get-BucketObject -Bucket todos -Match @{ Status = $status } -WarningAction SilentlyContinue) | Sort-Object Id
    if ($todos.Count -eq 0) {
        Write-Host "  No todos with status '$status'." -ForegroundColor DarkGray
        return
    }
    Write-Host "`n  Status: $status ($($todos.Count))" -ForegroundColor Cyan
    foreach ($t in $todos) { Format-Todo $t }
}

function Action-FilterProject {
    Write-Host "`n  Projects:" -ForegroundColor Cyan
    $projects = @(Get-BucketObject -Bucket projects -WarningAction SilentlyContinue) | Sort-Object Id
    foreach ($p in $projects) {
        Write-Host "    $($p.Id) - $($p.Name)" -ForegroundColor DarkGray
    }

    $projId = Read-Host "`n  Project ID"
    $todos = @(Get-BucketObject -Bucket todos -Match @{ ProjectId = $projId } -WarningAction SilentlyContinue) | Sort-Object Id
    if ($todos.Count -eq 0) {
        Write-Host "  No todos for project '$projId'." -ForegroundColor DarkGray
        return
    }
    $proj = $projects | Where-Object { $_.Id -eq $projId }
    Write-Host "`n  Project: $($proj.Name) ($($todos.Count))" -ForegroundColor Cyan
    foreach ($t in $todos) { Format-Todo $t }
}

function Action-FilterPriority {
    Write-Host "`n  Filter by priority (high/medium/low): " -ForegroundColor Cyan -NoNewline
    $priority = Read-Host ""
    if ($priority -notin @("high", "medium", "low")) {
        Write-Host "  Invalid priority." -ForegroundColor Red
        return
    }

    $todos = @(Get-BucketObject -Bucket todos -Match @{ Priority = $priority } -WarningAction SilentlyContinue) | Sort-Object Id
    if ($todos.Count -eq 0) {
        Write-Host "  No todos with priority '$priority'." -ForegroundColor DarkGray
        return
    }
    Write-Host "`n  Priority: $priority ($($todos.Count))" -ForegroundColor Cyan
    foreach ($t in $todos) { Format-Todo $t }
}

# --- Main loop ---
Show-Header
Write-Host "  Buckets-powered to-do manager" -ForegroundColor DarkGray

while ($true) {
    Show-Menu
    $choice = Read-Host ""
    Write-Host ""

    switch ($choice) {
        "1" { Action-List }
        "2" { Action-Add }
        "3" { Action-Edit }
        "4" { Action-Delete }
        "5" { Action-FilterStatus }
        "6" { Action-FilterProject }
        "7" { Action-FilterPriority }
        "q" { Write-Host "`n  Bye!`n" -ForegroundColor Cyan; break }
        default { Write-Host "  Unknown option." -ForegroundColor Red }
    }
}
