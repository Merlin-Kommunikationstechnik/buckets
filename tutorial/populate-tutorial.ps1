param(
    [string]$Language = ""
)

$ErrorActionPreference = "Stop"

# Module setup
$mod = Join-Path $PSScriptRoot "..\Buckets"
Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module $mod -Force -WarningAction SilentlyContinue

# Load tutorial data
. (Join-Path $PSScriptRoot "tutorial-data.ps1")

$root = Get-BucketRoot
$tutorialDir = Join-Path $root "tutorials"

# Wipe existing tutorial data
if (Test-Path $tutorialDir) {
    Remove-Item $tutorialDir -Recurse -Force
}

# Determine languages to process
$languages = if ($Language) { @($Language) } else { @($TutorialData.Keys | Sort-Object) }

$totalChapters = 0
$totalSections = 0
$totalLessons = 0

foreach ($lang in $languages) {
    if (-not $TutorialData.ContainsKey($lang)) {
        Write-Warning "Language '$lang' not found in tutorial data"
        continue
    }
    $chapters = $TutorialData[$lang].Chapters
    if (-not $chapters -or $chapters.Count -eq 0) {
        Write-Host "  [$lang] no chapters to populate" -ForegroundColor DarkGray
        continue
    }
    $langChapters = 0
    $langSections = 0
    $langLessons = 0
    foreach ($chapter in $chapters) {
        $langChapters++
        foreach ($section in $chapter.Sections) {
            $langSections++
            $bucketPath = "tutorials/$lang/$($chapter.Name)/$($section.Name)"
            foreach ($lesson in $section.Lessons) {
                $props = [ordered]@{
                    Title = $lesson.Title
                    Body  = $lesson.Body
                }
                if ($lesson.ContainsKey("SetupCode") -and $null -ne $lesson.SetupCode -and $lesson.SetupCode -ne "") {
                    $props.SetupCode = $lesson.SetupCode
                }
                if ($lesson.ContainsKey("Code") -and $null -ne $lesson.Code -and $lesson.Code -ne "") {
                    $props.Code = $lesson.Code
                }
                $obj = [PSCustomObject]$props
                New-BucketObject -Bucket $bucketPath -InputObject $obj -Key $lesson.Key -AsJson -Overwrite -Quiet
                $langLessons++
            }
        }
    }
    $totalChapters += $langChapters
    $totalSections += $langSections
    $totalLessons += $langLessons
    Write-Host "  [$lang] $langChapters chapters, $langSections sections, $langLessons lessons" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Done: $totalChapters chapters, $totalSections sections, $totalLessons lessons" -ForegroundColor Green
