#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Interactive tutorial for the Buckets PowerShell module.
    Walks through all CRUD operations, filtering, pipelines, aliases,
    PSDrive, nested buckets, export/import, and bucket management.
#>

Remove-Item Alias:cls -Force -ErrorAction SilentlyContinue
function cls {
    try {
        if (-not [Console]::IsInputRedirected) { Clear-Host }
    } catch {}
}

$ErrorActionPreference = "Stop"

$Sep = '─' * 55

# ---------- cleanup ----------

function tut-wipe {
    $root = Get-BucketRoot
    $current = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object Name
    $toRemove = $current | Where-Object { $_ -notin $script:userBuckets }
    if ($toRemove) {
        Remove-Bucket -Bucket $toRemove -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -Quiet
        $script:tutorialBuckets = ($script:tutorialBuckets + $toRemove) | Select-Object -Unique
        $script:tutorialBuckets | Set-Content (Join-Path $root ".tutorial-buckets") -Force
    }
}

# ---------- input ----------

function tut-pause {
    Write-Host ""
    Write-Host "  $Sep" -ForegroundColor DarkGray
    $hasCode = $null -ne $script:lastCode -and $script:lastCode -ne ""
    if ($hasCode) {
        Write-Host "  [Enter] next · [b] back · [c] copy code · [m] menu · [q] quit > " -NoNewline -ForegroundColor DarkGray
    } else {
        Write-Host "  [Enter] next · [b] back · [m] menu · [q] quit > " -NoNewline -ForegroundColor DarkGray
    }
    $r = Read-Host
    if ($r -eq "c" -and $hasCode) {
        $script:lastCode | Set-Clipboard
        Write-Host "  Code copied to clipboard." -ForegroundColor Green
        Start-Sleep -Milliseconds 500
        return (tut-pause)
    }
    if ($r -eq "q") { return "quit" }
    if ($r -eq "b") { return "back" }
    if ($r -eq "m") { return "menu" }
    return "next"
}

# ---------- syntax highlighting ----------

function tut-write-code($Code) {
    $script:lastCode = $Code
    $clean = $Code -replace "`r`n", "`n"
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($clean, [ref]$tokens, [ref]$errors)

    $cm = @{}
    $cm[[System.Management.Automation.Language.TokenKind]::Generic] = 'Yellow'
    $cm[[System.Management.Automation.Language.TokenKind]::Parameter] = 'Cyan'
    $cm[[System.Management.Automation.Language.TokenKind]::Variable] = 'Green'
    $cm[[System.Management.Automation.Language.TokenKind]::SplattedVariable] = 'Green'
    $cm[[System.Management.Automation.Language.TokenKind]::StringLiteral] = 'DarkYellow'
    $cm[[System.Management.Automation.Language.TokenKind]::StringExpandable] = 'DarkYellow'
    $cm[[System.Management.Automation.Language.TokenKind]::HereStringLiteral] = 'DarkYellow'
    $cm[[System.Management.Automation.Language.TokenKind]::HereStringExpandable] = 'DarkYellow'
    $cm[[System.Management.Automation.Language.TokenKind]::Comment] = 'DarkGray'
    $cm[[System.Management.Automation.Language.TokenKind]::Number] = 'Yellow'

    $tk = [System.Management.Automation.Language.TokenKind]
    foreach ($k in @('If','Else','ElseIf','ForEach','For','While','Do','Until','Function','Filter','Param','Begin','Process','End','Switch','Return','Break','Continue','Exit','Throw','Try','Catch','Finally','Using','Class','Enum','Var','Data','DynamicParam','Parallel','Sequence','InlineScript','Configuration','Workflow','From','In')) {
        $cm[$k -as $tk] = 'Cyan'
    }
    foreach ($k in @('Equals','Plus','Minus','Multiply','Divide','Rem','Format','PlusPlus','MinusMinus','PlusEquals','MinusEquals','MultiplyEquals','DivideEquals','And','Or','Xor','Band','Bor','Bxor','Bnot','Shl','Shr','Ieq','Ine','Igt','Ilt','Ige','Ile','Imatch','Inotmatch','Ilike','Inotlike','Icontains','Inotcontains','Iin','Inotin','Ireplace','Isplit','Ceq','Cne','Cgt','Clt','Cge','Cle','Cmatch','Cnotmatch','Clike','Cnotlike','Ccontains','Cnotcontains','Cin','Cnotin','Creplace','Csplit','Is','IsNot','As','Not','Join','DotDot','Pipe','Exclaim','Comma')) {
        $cm[$k -as $tk] = 'DarkGray'
    }

    $sorted = $tokens | Where-Object {
        $_.Kind -ne $tk::NewLine -and $_.Kind -ne $tk::LineBreak -and $_.Kind -ne $tk::EndOfInput
    } | Sort-Object { $_.Extent.StartOffset }

    $pos = 0
    foreach ($token in $sorted) {
        $start = $token.Extent.StartOffset
        $end = $token.Extent.EndOffset
        if ($start -gt $pos) {
            $len = [Math]::Min($start - $pos, $clean.Length - $pos)
            $lines = $clean.Substring($pos, $len) -split "`n", -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($i -gt 0) { Write-Host "" }
                Write-Host $lines[$i] -NoNewline
            }
        }
        $color = $cm[$token.Kind]
        $lines = $token.Extent.Text -split "`n", -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($i -gt 0) { Write-Host "" }
            if ($color) { Write-Host $lines[$i] -NoNewline -ForegroundColor $color }
            else { Write-Host $lines[$i] -NoNewline }
        }
        $pos = $end
    }
    if ($pos -lt $clean.Length) {
        $trailing = $clean.Substring($pos).TrimEnd("`r", "`n", " ", "`t")
        if ($trailing -ne "") { Write-Host $trailing }
    }
    Write-Host ""
    Write-Host ""
    Write-Host "  · Output" -ForegroundColor DarkGray
}

# ---------- helpers ----------

function Get-DisplayTitle($Name) {
    ($Name -replace '^\d+-', '') -replace '-', ' '
}

$script:LangNames = @{
    "en" = "English"
    "de" = "Deutsch"
}

# ---------- language menu ----------

function Show-LanguageMenu {
    cls
    Write-Host ""
    Write-Host "  $Sep" -ForegroundColor DarkGray
    Write-Host "  Buckets Tutorial  v$ver" -ForegroundColor White
    Write-Host "  $Sep" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose your language:" -ForegroundColor White
    for ($i = 0; $i -lt $script:AvailableLanguages.Count; $i++) {
        $lang = $script:AvailableLanguages[$i]
        $name = if ($script:LangNames.ContainsKey($lang)) { $script:LangNames[$lang] } else { $lang }
        Write-Host "    [$($i+1)] $name" -ForegroundColor Yellow
    }
    Write-Host ""
    do {
        $raw = Read-Host "  Enter choice [1-$($script:AvailableLanguages.Count)]"
        if ($null -eq $raw) { return $null }
        $r = $raw.Trim()
        $n = 0
        $valid = [int]::TryParse($r, [ref]$n) -and $n -ge 1 -and $n -le $script:AvailableLanguages.Count
    } while (-not $valid)
    return $script:AvailableLanguages[$n - 1]
}

# ---------- chapter menu ----------

function Show-ChapterMenu {
    cls
    Write-Host ""
    Write-Host "  $Sep" -ForegroundColor DarkGray
    Write-Host "  Buckets Tutorial  v$ver" -ForegroundColor White
    $langName = if ($script:LangNames.ContainsKey($script:Language)) { $script:LangNames[$script:Language] } else { $script:Language }
    Write-Host "  Language: $langName" -ForegroundColor DarkGray
    Write-Host "  $Sep" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choose a chapter:" -ForegroundColor White
    for ($i = 0; $i -lt $script:Chapters.Count; $i++) {
        Write-Host "    [$($i+1)] $(Get-DisplayTitle $script:Chapters[$i].Name)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  Type 'q' at any pause to quit" -ForegroundColor DarkGray
    Write-Host ""
    do {
        $raw = Read-Host "  Enter choice [1-$($script:Chapters.Count)]"
        if ($null -eq $raw) { return "q" }
        $r = $raw.Trim()
        if ($r -eq "q") { return "q" }
        $n = 0
        $valid = [int]::TryParse($r, [ref]$n) -and $n -ge 1 -and $n -le $script:Chapters.Count
    } while (-not $valid)
    return $n - 1
}

# ---------- setup ----------

cls
$mod = Join-Path $PSScriptRoot "../Buckets"
if (-not (Test-Path $mod)) { throw "Module not found at '$mod'" }
Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module $mod -Force
$ver = (Get-Module Buckets).Version
$root = Get-BucketRoot
$marker = Join-Path $root ".tutorial-buckets"
$script:tutorialBuckets = @()
if (Test-Path $marker) {
    $stale = Get-Content $marker
    if ($stale) {
        Remove-Bucket -Bucket $stale -Force -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -Quiet
    }
    Remove-Item $marker -Force -ErrorAction SilentlyContinue
}
$script:userBuckets = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object Name
tut-wipe

# Load chapters from the tutorial bucket tree
$script:Language = ""
$script:AvailableLanguages = @()
$script:LangNode = $null
$rootTree = Get-Bucket -Tree -Raw -ErrorAction SilentlyContinue
if ($rootTree -and $rootTree.Children) {
    $tutNode = $rootTree.Children | Where-Object Name -eq "tutorials"
    if ($tutNode -and $tutNode.Children) {
        $script:AvailableLanguages = $tutNode.Children | Sort-Object Name | ForEach-Object Name
    }
}
if ($script:AvailableLanguages.Count -eq 0) {
    Write-Host ""
    Write-Host "  No tutorial data found." -ForegroundColor Red
    Write-Host "  Run populate-tutorial.ps1 first." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
if ($script:AvailableLanguages.Count -eq 1) {
    $script:Language = $script:AvailableLanguages[0]
} else {
    $script:Language = Show-LanguageMenu
    if ($null -eq $script:Language) { exit }
    cls
}

# Load chapters for the selected language
$script:Chapters = @()
$rootTree = Get-Bucket -Tree -Raw -ErrorAction SilentlyContinue
if ($rootTree -and $rootTree.Children) {
    $tutNode = $rootTree.Children | Where-Object Name -eq "tutorials"
    if ($tutNode -and $tutNode.Children) {
        $script:LangNode = $tutNode.Children | Where-Object Name -eq $script:Language
        if ($script:LangNode -and $script:LangNode.Children) {
            $script:Chapters = $script:LangNode.Children | Sort-Object Name
        }
    }
}
if ($script:Chapters.Count -eq 0) {
    Write-Host ""
    Write-Host "  No chapters found for language '$($script:Language)'." -ForegroundColor Red
    Write-Host "  Run populate-tutorial.ps1 to install tutorial data." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Demo data available to all lesson code
$script:Team = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Skills=@("PowerShell","C#","Azure");        Active=$true;  Score=95; Joined=(Get-Date).AddDays(-365) }
    @{ Name="Bob";     Role="Designer";   Level=2; Skills=@("Figma","CSS","HTML");              Active=$true;  Score=72; Joined=(Get-Date).AddDays(-180) }
    @{ Name="Carol";   Role="PM";         Level=3; Skills=@("Agile","Jira","Confluence");       Active=$true;  Score=88; Joined=(Get-Date).AddDays(-90)  }
    @{ Name="Frank";   Role="Developer";  Level=4; Skills=@("Rust","Go","Kubernetes");          Active=$true;  Score=91; Joined=(Get-Date).AddDays(-500) }
)

$script:Staff = @(
    @{ Name="Dana";  Role="HR";        Level=2; Active=$true;  Score=70 }
    @{ Name="Eric";  Role="Finance";   Level=3; Active=$true;  Score=82 }
    @{ Name="Gina";  Role="Marketing"; Level=1; Active=$false; Score=65 }
)

# ---------- main loop ----------

while ($true) {
    $choice = Show-ChapterMenu
    if ($choice -eq "q") { tut-wipe; Write-Host ""; exit }

    $chapter = $script:Chapters[$choice]

    # Build flat lesson list from all sections in this chapter
    $allLessons = [System.Collections.ArrayList]@()
    $sectionTitles = [System.Collections.ArrayList]@()

    $sections = @()
    $chapterNode = $script:LangNode.Children | Where-Object Name -eq $chapter.Name
    if ($chapterNode -and $chapterNode.Children) {
        $sections = $chapterNode.Children | Sort-Object Name
    }
    if ($sections.Count -eq 0) {
        Write-Host "  No sections found in chapter '$(Get-DisplayTitle $chapter.Name)'" -ForegroundColor Red
        Start-Sleep -Milliseconds 1000
        continue
    }

    foreach ($section in $sections) {
        $bucketPath = "tutorials/$($script:Language)/$($chapter.Name)/$($section.Name)"
        $lessons = @(Get-BucketObject -Bucket $bucketPath -NoRecurse -ErrorAction SilentlyContinue)
        if ($lessons.Count -eq 0) { continue }
        $lessons = $lessons | Sort-Object { $_.PSObject.Properties['_BucketKey'].Value }
        foreach ($lesson in $lessons) {
            [void]$allLessons.Add($lesson)
            [void]$sectionTitles.Add((Get-DisplayTitle $section.Name))
        }
    }

    if ($allLessons.Count -eq 0) {
        Write-Host "  No lessons in chapter '$(Get-DisplayTitle $chapter.Name)'" -ForegroundColor Red
        Start-Sleep -Milliseconds 1000
        continue
    }

    $idx = 0
    while ($idx -ge 0 -and $idx -lt $allLessons.Count) {
        $lesson = $allLessons[$idx]
        $sectionTitle = $sectionTitles[$idx]

        cls
        Write-Host ""
        Write-Host "── Chapter: $(Get-DisplayTitle $chapter.Name) ──" -ForegroundColor DarkGray
        Write-Host "── Section: $sectionTitle ──" -ForegroundColor DarkGray
        Write-Host "── Lesson $($idx+1)/$($allLessons.Count): $($lesson.Title) ──" -ForegroundColor Cyan
        Write-Host ""
        Write-Host ""
        Write-Host $lesson.Body -ForegroundColor White
        Write-Host ""
        Write-Host ""

        $script:lastCode = $null
        $hasSetup = $lesson.PSObject.Properties['SetupCode'] -and $lesson.SetupCode
        $hasCode = $lesson.PSObject.Properties['Code'] -and $lesson.Code

        if ($hasSetup) {
            Write-Host "  · Setup demo data" -ForegroundColor DarkGray
            foreach ($line in ($lesson.SetupCode -split "`n")) {
                Write-Host $line -ForegroundColor DarkGray
            }
            Write-Host ""
            try {
                $null = Invoke-Expression $lesson.SetupCode 2>&1
            } catch {
                Write-Host "  Setup error: $_" -ForegroundColor Red
            }
        }

        if ($hasCode) {
            Write-Host "  · Lesson" -ForegroundColor DarkGray
            $script:lastCode = $lesson.Code
            tut-write-code $lesson.Code
            try {
                $codeTokens = $null; $codeErrors = $null
                $codeAst = [System.Management.Automation.Language.Parser]::ParseInput($lesson.Code, [ref]$codeTokens, [ref]$codeErrors)
                $statements = @($codeAst.EndBlock.Statements)
                if ($statements.Count -gt 1) {
                    $first = $true
                    foreach ($stmt in $statements) {
                        $output = Invoke-Expression $stmt.Extent.Text 2>&1
                        if ($output) {
                            if (-not $first) { Write-Host "" }
                            $first = $false
                            Write-Host ($output | Out-String).Trim()
                        }
                    }
                } else {
                    $output = Invoke-Expression $lesson.Code 2>&1
                    if ($output) {
                        Write-Host ($output | Out-String).Trim()
                    }
                }
            } catch {
                Write-Host "  Error: $_" -ForegroundColor Red
            }
        }

        $r = tut-pause
        if ($r -eq "quit") { tut-wipe; Write-Host ""; exit }

        tut-wipe
        cls

        switch ($r) {
            "next" { $idx++ }
            "back" { $idx-- }
            "menu" { $idx = -1 }
        }
    }
}
