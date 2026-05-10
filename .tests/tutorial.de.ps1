#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Interaktives Tutorial für das Buckets PowerShell-Modul.
    Führt durch alle CRUD-Operationen, Filterung, Pipelines, Aliase,
    PSDrive, verschachtelte Buckets, Export/Import und Bucket-Verwaltung.
.PARAMETER GenerateMarkdown
    Im nicht-interaktiven Modus ausführen und tutorial.de.md im Repository-Stammverzeichnis generieren.
#>

param([switch]$GenerateMarkdown)

$ErrorActionPreference = "Stop"

$Sep = '─' * 55

# Markdown-Generierungsmodus — überschreibt Write-Host/Out-Host, um Ausgabe als Klartext zu erfassen
if ($GenerateMarkdown) {
    $PSStyle.OutputRendering = 'PlainText'
    $script:mdOutput = [System.Text.StringBuilder]::new()
    [void]$script:mdOutput.AppendLine("# Buckets Tutorial (Deutsch)")
    [void]$script:mdOutput.AppendLine("")

    # Aliase entfernen, bevor Funktionen definiert werden (Alias hat höhere Priorität)
    Remove-Item Alias:cls -Force -ErrorAction SilentlyContinue
    Remove-Item Alias:Clear-Host -Force -ErrorAction SilentlyContinue

    function Write-Host {
        param(
            [string]$Object,
            [string]$ForegroundColor,
            [switch]$NoNewline
        )
        if ($NoNewline) {
            [void]$script:mdOutput.Append($Object)
        } else {
            [void]$script:mdOutput.AppendLine($Object)
        }
    }

    function Out-Host {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline=$true)][PSObject]$InputObject)
        begin { $items = [System.Collections.ArrayList]::new() }
        process { if ($null -ne $InputObject) { [void]$items.Add($InputObject) } }
        end {
            if ($items.Count -gt 0) {
                [void]$script:mdOutput.AppendLine('```')
                $str = $items | Out-String -Width 4096
                $str = $str.TrimEnd([char]13, [char]10)
                $str = $str -replace "(\r?\n){3,}", "`n`n"
                $str = $str -replace '(?m)[\t ]+$', ''
                [void]$script:mdOutput.Append($str)
                [void]$script:mdOutput.AppendLine('')
                [void]$script:mdOutput.AppendLine('```')
            }
        }
    }

    function cls {}
    function Clear-Host {}
}

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

function tut-pause {
    if ($GenerateMarkdown) { return }
    Write-Host ""
    Write-Host "  $Sep" -ForegroundColor DarkGray
    $hasCode = $null -ne $script:lastCode -and $script:lastCode -ne ""
    if ($hasCode) {
        Write-Host "  [Enter] weiter · [c] Code kopieren · [q] beenden > " -NoNewline -ForegroundColor DarkGray
    } else {
        Write-Host "  [Enter] weiter · [q] beenden > " -NoNewline -ForegroundColor DarkGray
    }
    $r = Read-Host
    if ($r -eq "c" -and $hasCode) {
        $script:lastCode | Set-Clipboard
        Write-Host "  Code in die Zwischenablage kopiert." -ForegroundColor Green
        tut-pause
        return
    }
    if ($r -eq "q") { Write-Host ""; exit }
    tut-wipe
    cls
}

function tut-write-code($Code) {
    $script:lastCode = $Code
    $clean = $Code -replace "`r`n", "`n"
    if ($GenerateMarkdown) {
        [void]$script:mdOutput.AppendLine("")
        [void]$script:mdOutput.AppendLine('```powershell')
        [void]$script:mdOutput.AppendLine($clean)
        [void]$script:mdOutput.AppendLine('```')
        [void]$script:mdOutput.AppendLine("")
        return
    }
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
    $cm[[System.Management.Automation.Language.TokenKind]::Comment] = 'DarkGreen'
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
    Write-Host "output:" -ForegroundColor DarkGray
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

$script:Team = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Skills=@("PowerShell","C#","Azure");        Active=$true;  Score=95; Joined=(Get-Date).AddDays(-365) }
    @{ Name="Bob";     Role="Designer";   Level=2; Skills=@("Figma","CSS","HTML");              Active=$true;  Score=72; Joined=(Get-Date).AddDays(-180) }
    @{ Name="Carol";   Role="PM";         Level=3; Skills=@("Agile","Jira","Confluence");       Active=$true;  Score=88; Joined=(Get-Date).AddDays(-90)  }
    @{ Name="Frank";   Role="Developer";  Level=4; Skills=@("Rust","Go","Kubernetes");          Active=$true;  Score=91; Joined=(Get-Date).AddDays(-500) }
)

if ($GenerateMarkdown) {
    $mode = "4"
} else {
    while ($true) {
        Write-Host ""
        Write-Host "  $Sep" -ForegroundColor DarkGray
        Write-Host "  Buckets Tutorial  v$ver" -ForegroundColor White
        Write-Host "  dateibasierte PSObject-Speicherung für PowerShell" -ForegroundColor DarkGray
        Write-Host "  $Sep" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Wählen Sie einen Pfad:" -ForegroundColor White
        Write-Host "    [0] Einführung  — Was, Warum, Wie" -ForegroundColor Yellow
        Write-Host "    [1] Einsteiger  — CRUD-Grundlagen (erstellen, lesen, aktualisieren, loeschen)" -ForegroundColor Yellow
        Write-Host "    [2] Fortgeschritten  — Kopieren, Umbenennen, PSDrive, verschachtelte Buckets, Pipelines" -ForegroundColor Yellow
        Write-Host "    [3] Sysadmin  — Serverinventar, Logs, Vorfaelle, Berichte" -ForegroundColor Yellow
        Write-Host "    [4] Komplett  — alles" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Geben Sie 'q' ein, um das Tutorial zu beenden" -ForegroundColor DarkGray
        Write-Host ""
        do {
            $mode = (Read-Host "  Eingabe [0/1/2/3/4]").Trim()
        } while ($mode -notin @("0","1","2","3","4"))

        if ($mode -eq "0" -or $mode -eq "4") {
            break  # exit menu to run introduction below
        }
        break
    }
}

# Run introduction for track 0 or 4
if ($mode -eq "0" -or $mode -eq "4") {
    cls
    # ========== Einfuehrung ==========
    Write-Host ""
    Write-Host "  0. Einfuehrung" -ForegroundColor Gray
    Write-Host "  $Sep" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  0.1 Was ist Buckets?" -ForegroundColor DarkGray
    Write-Host "  $Sep" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host @"
  Buckets ist ein PowerShell-Modul zur dateibasierten Ablage von
  PSObjects. Jedes Objekt ist eine Datei, jeder Bucket ein Ordner.
  Keine Datenbank, kein Dienst, keine Konfigurationsdatei —
  nur das Dateisystem.
"@ -ForegroundColor White
    Write-Host ""
    Write-Host "  Zwei Speicherformate:" -ForegroundColor White
    Write-Host @"
    Binary (.dat) — ueber PSSerializer. Schnell, erhaelt vollstaendige
                    .NET-Typinformationen. Komplexe Objekte, Zirkelbezüge.
    JSON    (.json) — via -AsJson. Lesbar, portabel, in jedem
                    Texteditor aenderbar.
"@ -ForegroundColor DarkGray
    tut-pause

    Write-Host ""
    Write-Host "  0.2 Warum Buckets?" -ForegroundColor DarkGray
    Write-Host "  $Sep" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host @"
  Dauerhaft       — Objekte ueberdauern die PowerShell-Sitzung
  Teilbar         — Buckets sind Ordner; kopieren, syncen, einchecken
  Komponierbar    — Pipeline rein, Pipeline raus; einfach uebergeben
  Durchsuchbar    — Get-Bucket -Tree zeigt die ganze Hierarchie
  Selbstbeschreibend — Dateinamen sind Schluessel, JSON ist lesbar
  Expand/Collapse — verschachtelte Strukturen als Verzeichnisbaeume
  Plattformunabhaengig — PowerShell 7+ auf Windows, macOS, Linux
"@ -ForegroundColor White
    tut-pause

    Write-Host ""
    Write-Host "  0.3 Wie funktioniert es?" -ForegroundColor DarkGray
    Write-Host "  $Sep" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host @"
  Jeder Bucket ist ein Verzeichnis unter einem Wurzelpfad. Der Standard ist:
"@ -ForegroundColor White
    Write-Host ""
    tut-write-code @'
Get-BucketRoot
'@
    Get-BucketRoot | Write-Host -ForegroundColor Cyan
    Write-Host ""
    Write-Host @"
  Jedes Objekt ist eine Datei — .dat (Binary, Standard) oder .json (optional).
  Der Dateiname (ohne Erweiterung) ist der Schluessel des Objekts.
"@ -ForegroundColor White
    Write-Host ""
    Write-Host "  Aktuelle Buckets:" -ForegroundColor DarkGray
    $tree = Get-Bucket -Tree -ErrorAction SilentlyContinue
    if ($tree) { $tree | Out-Host } else { Write-Host "    (noch keine Buckets)" -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host @"
  Die sechs Kern-Cmdlets:
"@ -ForegroundColor White
    Write-Host ""
    Write-Host "    fill   · New-BucketObject      Objekte schreiben" -ForegroundColor Cyan
    Write-Host "    scoop  · Get-BucketObject      Objekte lesen" -ForegroundColor Cyan
    Write-Host "    spill  · Remove-BucketObject   Objekt loeschen" -ForegroundColor Cyan
    Write-Host "    dip    · Get-Bucket            Buckets auflisten" -ForegroundColor Cyan
    Write-Host "    drain  · Remove-Bucket         Bucket loeschen" -ForegroundColor Cyan
    Write-Host ""
    Write-Host @"
  Standardwerte: Binary-Tiefe 5, JSON-Tiefe 20, Pfad $HOME/.buckets
  Alles ueber -BinaryDepth, -Depth oder -Path aenderbar.
"@ -ForegroundColor DarkGray
    tut-pause
}
$Beg = $mode -in @("1","4")
$Adv = $mode -in @("2","4")
$Sys = $mode -in @("3","4")
cls

if ($Beg) {
# ---------- chapter 1: Create ----------

Write-Host ""
Write-Host "  1. Erstellen" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  1.1 Ihr erstes Objekt speichern" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Speichern wir Ihr erstes Objekt — eine einfache Hashtable, die einen Benutzer beschreibt. Wir vergeben
  einen expliziten Schlüssel "Alice" mit -Key. Standardmäßig verwendet
  Buckets ein Binärformat, das die vollständigen .NET-Typinformationen bewahrt, sodass
  Hashtables, benutzerdefinierte Objekte und sogar FileInfo den Round-Trip überstehen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$alice = @{ Name = "Alice"; Role = "admin"; Score = 95 }
New-BucketObject -InputObject $alice -Bucket users -Key "Alice"
'@
$alice = @{ Name = "Alice"; Role = "admin"; Score = 95 }
New-BucketObject -InputObject $alice -Bucket users -Key "Alice" | Out-Host
tut-pause

Write-Host ""
Write-Host "  1.2 -KeyProperty für automatische Benennung" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -Key für jedes Objekt zu tippen wird mühsam. -KeyProperty weist Buckets an,
  eine bestimmte Eigenschaft Ihres Objekts zu verwenden. Hier enthält die
  Eigenschaft Name den Wert "Bob", also wird der Schlüssel automatisch zu "Bob".
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$bob = @{ Name = "Bob"; Role = "user"; Score = 72 }
$bob | fill -Bucket users -KeyProperty Name
'@
$bob = @{ Name = "Bob"; Role = "user"; Score = 72 }
$bob | fill -Bucket users -KeyProperty Name | Out-Host
tut-pause

Write-Host ""
Write-Host "  1.3 Mehrere Objekte über die Pipeline" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Eine der Superkräfte von Buckets: mehrere Objekte auf einmal über die Pipeline. Senden Sie sie einzeln
  durch die Pipeline und Buckets speichert jedes. Kombinieren Sie -KeyProperty mit Pipeline-Eingabe
  für Batch-Inserts — der schnellste Weg, Daten zu laden.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$users = @(
    @{ Name = "Carol"; Role = "manager"; Score = 88 }
    @{ Name = "Dave"; Role = "user"; Score = 61 }
)
$users | fill -Bucket users -KeyProperty Name
'@
$users = @(
    @{ Name = "Carol"; Role = "manager"; Score = 88 }
    @{ Name = "Dave"; Role = "user"; Score = 61 }
)
$users | fill -Bucket users -KeyProperty Name | Out-Host
tut-pause

Write-Host ""
Write-Host "  1.4 Expliziter -Key für unabhängige Benennung" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Was, wenn Sie einen Schlüssel benötigen, der keine Eigenschaft des Objekts ist? Dafür gibt es
  den -Key-Parameter — Sie bestimmen den Schlüssel, unabhängig von den Daten im Objekt.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$data = @{ Source = "import"; Items = 42 }
$data | fill -Bucket users -Key "external-ref"
'@
$data = @{ Source = "import"; Items = 42 }
$data | fill -Bucket users -Key "external-ref" | Out-Host
tut-pause

Write-Host ""
Write-Host "  1.5 JSON-Ausgabe mit -AsJson" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Der JSON-Modus ist für menschenlesbare Dateien gedacht — Konfigurationen, Einstellungen, alles,
  was Sie von Hand bearbeiten möchten. Mit -AsJson speichert Buckets eine .json-Datei statt .dat.
  Sie können sie in jedem Texteditor öffnen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$config = @{ Host = "localhost"; Port = 5432 }
$config | fill -Bucket config -Key "app-config" -AsJson
'@
$config = @{ Host = "localhost"; Port = 5432 }
$config | fill -Bucket config -Key "app-config" -AsJson | Out-Host
tut-pause

Write-Host ""
Write-Host "  1.6 Zeitstempel-Schlüssel mit -AsTimestamp" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Für Logs, Metriken oder Zeitreihendaten erzeugt -AsTimestamp automatisch einen eindeutigen Schlüssel
  aus dem aktuellen Datum und der Uhrzeit. Keine zwei Objekte erhalten denselben Namen, und die
  chronologische Reihenfolge ist integriert.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$events = @(
    @{ Event = "login"; User = "alice" }
    @{ Event = "logout"; User = "bob" }
)
$events | fill -Bucket events -AsTimestamp
'@
$events = @(
    @{ Event = "login"; User = "alice" }
    @{ Event = "logout"; User = "bob" }
)
$events | fill -Bucket events -AsTimestamp | Out-Host
tut-pause

Write-Host ""
Write-Host "  1.7 überschreiben verhindern mit -Overwrite" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Bereits ein Objekt mit demselben Schlüssel vorhanden? Ohne -Overwrite überspringt Buckets es stillschweigend.
  Mit -Overwrite ersetzen Sie das vorhandene Objekt durch das neue.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$alice = @{ Name = "Alice"; Role = "admin"; Score = 99 }
New-BucketObject -InputObject $alice -Bucket users -Key "Alice" -Overwrite
'@
$alice = @{ Name = "Alice"; Role = "admin"; Score = 99 }
New-BucketObject -InputObject $alice -Bucket users -Key "Alice" -Overwrite | Out-Host
tut-pause

Write-Host ""
Write-Host "  1.8 Kompression mit -Compress" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Wiederholende Daten — Logs, Heartbeats, Sensorwerte — lassen sich extrem gut komprimieren. Das
  -Compress-Flag wendet GZip vor dem Schreiben an, und Buckets erkennt komprimierte Dateien
  beim Lesen automatisch, sodass Sie sich nie darum kümmern müssen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$logs = 1..30 | ForEach-Object { @{ Seq = $_; Msg = "Heartbeat OK" } }
fill -Bucket logs -InputObject $logs -Compress
'@
$logs = 1..30 | ForEach-Object { @{ Seq = $_; Msg = "Heartbeat OK" } }
fill -Bucket logs -InputObject $logs -Compress | Out-Host
tut-pause
}

if ($Beg) {
# section 1b

cls
Write-Host ""
Write-Host "  1b. Erstellen — leise, ausführlich und Randfälle" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  1b.1 Leise und ausführliche Ausgabe" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Standardmäßig zeigt fill eine Fortschrittsanzeige und eine Zusammenfassung beim Speichern. Wenn Sie
  Skripte schreiben oder Stille wünschen, unterdrückt -Quiet jegliche Ausgabe. Zum Debuggen gibt
  -Verbose Details pro Objekt aus.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$data = @{ Msg = "test" }
$data | fill -Bucket demo -Key "verbosity-demo" -Quiet
'@
$data = @{ Msg = "test" }
$data | fill -Bucket demo -Key "verbosity-demo" -Quiet
tut-pause

Write-Host ""
Write-Host "  1b.2 PSCustomObject vs. Hashtable" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Sowohl Hashtables als auch PSCustomObject funktionieren mit Buckets. Der Unterschied: PSCustomObject
  bewahrt die Reihenfolge Ihrer Eigenschaften, während eine normale Hashtable keine Reihenfolge garantiert.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$custom = [PSCustomObject]@{ Type = "PSCustomObject"; Ordered = $true }
$custom | fill -Bucket types -Key "custom"
$hash = @{ Type = "Hashtable" }
$hash | fill -Bucket types -Key "hash"
'@
$custom = [PSCustomObject]@{ Type = "PSCustomObject"; Ordered = $true }
$custom | fill -Bucket types -Key "custom" | Out-Host
$hash = @{ Type = "Hashtable" }
$hash | fill -Bucket types -Key "hash" | Out-Host
tut-pause

Write-Host ""
Write-Host "  1b.3 Tief verschachtelte Objekte" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Buckets verarbeitet tief verschachtelte Objekte mühelos. Der binäre Serialisierer bewahrt den
  vollständigen Objektgraphen — verschachtelte PSCustomObjects, Arrays und alles. Genau hier
  würde JSON an seine Grenzen stoßen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$nested = [PSCustomObject]@{
    Id = "deep"
    Metadata = [PSCustomObject]@{ App = "test"; Version = "1.0" }
    Items = @(
        [PSCustomObject]@{ Sku = "ABC"; Qty = 5 }
        [PSCustomObject]@{ Sku = "XYZ"; Qty = 3 }
    )
}
$nested | fill -Bucket nested -Key "deep"
'@
$nested = [PSCustomObject]@{
    Id = "deep"
    Metadata = [PSCustomObject]@{ App = "test"; Version = "1.0" }
    Items = @(
        [PSCustomObject]@{ Sku = "ABC"; Qty = 5 }
        [PSCustomObject]@{ Sku = "XYZ"; Qty = 3 }
    )
}
$nested | fill -Bucket nested -Key "deep" | Out-Host
tut-pause

Write-Host ""
Write-Host "  1b.4 Sonderzeichen in Schlüsseln" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Manche Zeichen — wie /, :, *, ? — sind in Dateinamen nicht erlaubt. Wenn Sie sie in einem
  Schlüssel verwenden, ersetzt Buckets sie automatisch durch Unterstriche, damit das Dateisystem zufrieden ist.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$data = @{ Data = "sanitized key" }
$data | fill -Bucket special -Key "my/file:name*test"
'@
$data = @{ Data = "sanitized key" }
$data | fill -Bucket special -Key "my/file:name*test" | Out-Host
tut-pause

Write-Host ""
Write-Host "  1b.5 Leere Schlüssel nach Bereinigung" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Schlüssel, die nach Bereinigung nur aus Unterstrichen bestehen (wie Punkte oder Sonderzeichen), werden
  stillschweigend übersprungen. Verwenden Sie -Verbose, um die Erklärung des Moduls zu sehen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ X = 1 } | fill -Bucket demo -Key "..." -Quiet -Verbose
@{ X = 1 } | fill -Bucket demo -Key ". ." -Quiet -Verbose
'@
@{ X = 1 } | fill -Bucket demo -Key "..." -Quiet -Verbose
@{ X = 1 } | fill -Bucket demo -Key ". ." -Quiet -Verbose
tut-pause
}

if ($Beg) {
# ---------- chapter 2: Read ----------

cls
Write-Host ""
Write-Host "  2. Lesen — scoop / Get-BucketObject" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  2.1 Alle Objekte anzeigen (scoop)" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Das Gegenstück zu fill ist scoop (Kurzform von Get-BucketObject). Ohne Argumente
  gibt es jedes Objekt aus jedem Bucket zurück — nützlich, um sich einen überblick zu verschaffen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop | Out-Host
tut-pause

Write-Host ""
Write-Host "  2.2 Nach Bucket filtern" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Meistens möchten Sie Objekte aus einem bestimmten Bucket. Mit -Bucket schränken Sie
  die Suche auf einen einzelnen Bucket ein.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team | Out-Host
tut-pause

Write-Host ""
Write-Host "  2.3 Bucket-Suche mit Positionsparameter" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Das erste Positionsargument ist der Bucket-Name. Ohne -Key werden
  alle Objekte aus diesem Bucket abgerufen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop team
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop team | Out-Host
tut-pause

Write-Host ""
Write-Host "  2.4 Schlüsselsuche nach Name" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  übergeben Sie einen Schlüssel als zweites Positionsargument (oder mit -Key). Schlüssel werden
  standardmäßig ohne Berücksichtigung der Groß-/Kleinschreibung und als Präfixe gefunden.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop team "Alice"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop team "Alice" | Out-Host
tut-pause

Write-Host ""
Write-Host "  2.5 Exakte Schlüsselsuche" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Geben Sie den exakten vollständigen Schlüsselnamen an, um genau dieses eine Objekt abzurufen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop team -Key "Frank"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop team -Key "Frank" | Out-Host
tut-pause

Write-Host ""
Write-Host "  2.6 Groß-/Kleinschreibung ignorieren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Groß-/Kleinschreibung spielt keine Rolle. "alice" findet "Alice", weil die Schlüsselsuche
  ohne Berücksichtigung der Groß-/Kleinschreibung erfolgt. Kein Raten mehr.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop team -Key "alice"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop team -Key "alice" | Out-Host
tut-pause

Write-Host ""
Write-Host "  2.7 Fehlende Schlüssel behandeln" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Was passiert bei fehlender übereinstimmung? Buckets gibt nichts zurück, mit einer Warnung —
  kein Absturz, nur ein hilfreicher Hinweis, dass nichts gefunden wurde.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Key "Zoe"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Key "Zoe" | Out-Host
tut-pause

Write-Host ""
Write-Host "  2.8 Platzhalter in Bucket-Namen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Auch in Bucket-Namen können Sie Platzhalter verwenden. "t*" findet jeden Bucket, der mit
  "t" beginnt — praktisch für die Suche in Gruppen verwandter Buckets.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket "t*"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
$script:Team | fill -Bucket staff -KeyProperty Name -Quiet
scoop -Bucket "t*" | Out-Host
tut-pause

Write-Host ""
Write-Host "  2.9 Mehrere Buckets abfragen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  übergeben Sie mehrere Bucket-Namen als Array. Buckets durchsucht jeden und kombiniert
  die Ergebnisse in einer einzigen Liste.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket "team", "staff"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
$script:Team | fill -Bucket staff -KeyProperty Name -Quiet
scoop -Bucket "team", "staff" | Out-Host
tut-pause

Write-Host ""
Write-Host "  2.10 Metadaten-Eigenschaften" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Jedes von Buckets abgerufene Objekt enthält Metadaten: _BucketName, _BucketKey und
  _BucketFile. Sie zeigen genau, woher das Objekt stammt — nützlich für
  Pipeline-Operationen, bei denen der Kontext wichtig ist.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Key "Bob" | Select _BucketName, _BucketKey, _BucketFile
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Key "Bob" | Select _BucketName, _BucketKey, _BucketFile | Out-Host
tut-pause

Write-Host ""
Write-Host "  2.11 An Select-Object übergeben" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Da scoop normale PowerShell-Objekte zurückgibt, können Sie sie an Select-Object,
  Sort-Object, Group-Object übergeben — alles, was Sie mit jedem anderen PowerShell-Objekt tun würden.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team | Sort Score -Descending | Select Name, Role, Score
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team | Sort Score -Descending | Select Name, Role, Score | Out-Host
tut-pause

Write-Host ""
Write-Host "  2.12 Zugriff mit Punktnotation" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Greifen Sie mit der Standard-Punktnotation auf einzelne Eigenschaften zu. Speichern Sie das Ergebnis in einer
  Variablen und arbeiten Sie damit wie mit jedem anderen PowerShell-Objekt.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$dev = scoop -Bucket team -Key "Frank"
$dev.Name
$dev.Role
$dev.Level
$dev.Score
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
$dev = scoop -Bucket team -Key "Frank"
$dev.Name
$dev.Role
$dev.Level
$dev.Score
tut-pause
}

if ($Beg) {
# section 2a

cls
Write-Host ""
Write-Host "  2a. Lesen — filtern mit -Match" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  2a.1 Exakte übereinstimmung" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -Match ist Buckets eigener Filter für exakte Gleichheit. übergeben Sie eine Hashtable mit Eigenschaftsnamen
  und -werten, und Buckets gibt nur Objekte zurück, bei denen alle Eigenschaften exakt übereinstimmen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Match @{ Role = "Developer" }
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Match @{ Role = "Developer" } | Out-Host
tut-pause

Write-Host ""
Write-Host "  2a.2 Null-Werte abgleichen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Sonderfall: Abgleich mit $null. Wenn eine Eigenschaft $null ist oder gar nicht existiert,
  gilt sie als übereinstimmung für $null. Nützlich zum Auffinden von Objekten mit fehlenden Feldern.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Match @{ Deleted = $null }
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Match @{ Deleted = $null } | Out-Host
tut-pause

Write-Host ""
Write-Host "  2a.3 Mehrere Eigenschaften abgleichen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Sie können mehrere Eigenschaften gleichzeitig abgleichen — wie UND-Logik. Alle Bedingungen
  müssen zutreffen, damit ein Objekt zurückgegeben wird.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Match @{ Level = 3; Active = $true }
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Match @{ Level = 3; Active = $true } | Out-Host
tut-pause

Write-Host ""
Write-Host "  2a.4 Gemischte Typen abgleichen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Erstellen wir frische Daten, um -Match mit gemischten Typen zu demonstrieren. Zeichenketten, Zahlen
  und Boolesche Werte funktionieren alle als Vergleichskriterien.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$data = @(
    @{ Name = "A"; Count = 5; Active = $true }
    @{ Name = "B"; Count = 10; Active = $false }
    @{ Name = "C"; Count = 5; Active = $true }
)
New-BucketObject -InputObject $data -Bucket match-demo -KeyProperty Name
scoop -Bucket match-demo -Match @{ Count = 5; Active = $true }
'@
$data = @(
    @{ Name = "A"; Count = 5; Active = $true }
    @{ Name = "B"; Count = 10; Active = $false }
    @{ Name = "C"; Count = 5; Active = $true }
)
New-BucketObject -InputObject $data -Bucket match-demo -KeyProperty Name -Quiet
scoop -Bucket match-demo -Match @{ Count = 5; Active = $true } | Out-Host
tut-pause

Write-Host ""
Write-Host "  2a.5 Groß-/Kleinschreibung bei Zeichenketten" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Der Zeichenkettenabgleich mit -Match ist exakt und ignoriert die Groß-/Kleinschreibung. "red" findet "red",
  aber auch "Red", "RED" und so weiter.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$items = @(
    @{ Name = "alpha"; Color = "red" }
    @{ Name = "beta"; Color = "blue" }
    @{ Name = "gamma"; Color = "red" }
)
$items | fill -Bucket match-demo -KeyProperty Name
scoop -Bucket match-demo -Match @{ Color = "red" }
'@
$items = @(
    @{ Name = "alpha"; Color = "red" }
    @{ Name = "beta"; Color = "blue" }
    @{ Name = "gamma"; Color = "red" }
)
$items | fill -Bucket match-demo -KeyProperty Name -Quiet
scoop -Bucket match-demo -Match @{ Color = "red" } | Out-Host
tut-pause

Write-Host ""
Write-Host "  2a.6 Nur oberste Eigenschaften" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -Match betrachtet nur Eigenschaften der obersten Ebene. Wenn Sie in verschachtelte Daten wie
  $_.Settings.Enabled eintauchen müssen, verwenden Sie stattdessen -Filter.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$data = @{ Id = "a"; Meta = @{ Name = "inner" } }
$data | fill -Bucket nested-match -KeyProperty Id
scoop -Bucket nested-match -Match @{ Meta = $null }
'@
$data = @{ Id = "a"; Meta = @{ Name = "inner" } }
$data | fill -Bucket nested-match -KeyProperty Id -Quiet
scoop -Bucket nested-match -Match @{ Meta = $null } | Out-Host
tut-pause
}

if ($Beg) {
# section 2b

cls
Write-Host ""
Write-Host "  2b. Lesen — vergleichen mit -Filter" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  2b.1 Filtern mit Scriptblock" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Für alles über die exakte Gleichheit hinaus greifen Sie zu -Filter. Er akzeptiert einen Scriptblock, in dem
  $_ jedes Objekt repräsentiert. Sie können jeden PowerShell-Operator verwenden: -gt, -lt, -match,
  -like, -and, -or und mehr.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Filter { $_.Score -gt 80 }
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Filter { $_.Score -gt 80 } | Out-Host
tut-pause

Write-Host ""
Write-Host "  2b.2 Kleiner-oder-gleich-Vergleich" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Kleiner oder gleich funktioniert genauso. Stellen Sie sich -Filter wie eine Where-Object-Klausel vor,
  die innerhalb von Buckets statt in der Pipeline ausgeführt wird.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Filter { $_.Score -le 90 }
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Filter { $_.Score -le 90 } | Out-Host
tut-pause

Write-Host ""
Write-Host "  2b.3 Regex-Mustervergleich" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Der Mustervergleich mit -match verwendet reguläre Ausdrücke. Hier finden wir Namen, die mit
  A oder E beginnen, mit dem Regex "^[AE]".
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Filter { $_.Name -match "^[AE]" }
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Filter { $_.Name -match "^[AE]" } | Out-Host
tut-pause

Write-Host ""
Write-Host "  2b.4 Platzhaltersuche mit -like" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Der -like-Operator verwendet Platzhaltermuster. "*e*" findet jeden Namen, der den
  Buchstaben "e" an beliebiger Stelle enthält.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Filter { $_.Name -like "*e*" }
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Filter { $_.Name -like "*e*" } | Out-Host
tut-pause

Write-Host ""
Write-Host "  2b.5 Bedingungen mit -and kombinieren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Kombinieren Sie Bedingungen mit -and. Beide müssen zutreffen: Punktzahl über 80 UND Rolle ist
  "Developer".
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Filter { $_.Score -gt 80 -and $_.Role -eq "Developer" }
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Filter { $_.Score -gt 80 -and $_.Role -eq "Developer" } | Out-Host
tut-pause

Write-Host ""
Write-Host "  2b.6 Bedingungen mit -or kombinieren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Kombinieren Sie Bedingungen mit -or. Eine muss zutreffen: Rolle ist "Designer" ODER Level über 3.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Filter { $_.Role -eq "Designer" -or $_.Level -gt 3 }
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Filter { $_.Role -eq "Designer" -or $_.Level -gt 3 } | Out-Host
tut-pause

Write-Host ""
Write-Host "  2b.7 Zeichenkettenlängen prüfen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Längenprüfungen funktionieren, weil Sie echte PowerShell-Ausdrücke schreiben. Hier
  finden wir Objekte, deren Value-Eigenschaft länger als 5 Zeichen ist.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$items = @(
    @{ Name = "short"; Value = "abc" }
    @{ Name = "long";  Value = "abcdefghijk" }
)
$items | fill -Bucket str-test -KeyProperty Name
scoop -Bucket str-test -Filter { $_.Value.Length -gt 5 }
'@
$items = @(
    @{ Name = "short"; Value = "abc" }
    @{ Name = "long";  Value = "abcdefghijk" }
)
$items | fill -Bucket str-test -KeyProperty Name -Quiet
scoop -Bucket str-test -Filter { $_.Value.Length -gt 5 } | Out-Host
tut-pause

Write-Host ""
Write-Host "  2b.8 Datumsvergleiche" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Auch Datumsvergleiche — keine spezielle Syntax nötig. Vergleichen Sie DateTime-Eigenschaften mit
  -gt, -lt oder jedem anderen Operator, genau wie in normalem PowerShell.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$cutoff = (Get-Date).AddDays(-100)
scoop -Bucket team -Filter { $_.Joined -gt $cutoff }
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
$cutoff = (Get-Date).AddDays(-100)
scoop -Bucket team -Filter { $_.Joined -gt $cutoff } | Out-Host
tut-pause

Write-Host ""
Write-Host "  2b.9 Zugriff auf verschachtelte Eigenschaften" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Verschachtelte Eigenschaften sind über die Standard-Punktnotation im Scriptblock zugänglich.
  Hier prüfen wir, ob eine Array-Eigenschaft einen Wert mit -contains enthält.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Filter { $_.Skills -contains "Rust" }
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Filter { $_.Skills -contains "Rust" } | Out-Host
tut-pause

Write-Host ""
Write-Host "  2b.10 Bucket-übergreifendes Filtern" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Ohne -Bucket wird -Filter gegen alle Buckets gleichzeitig ausgeführt. Dies ist eine
  bucket-übergreifende Abfrage — nützlich, um Objekte überall in Ihren Daten zu finden.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Name = "HighScore"; Score = 90 } | fill -Bucket config -Key "app-config"
scoop -Filter { $_.Score -gt 80 }
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Name = "HighScore"; Score = 90 } | fill -Bucket config -Key "app-config" -Quiet
scoop -Filter { $_.Score -gt 80 } | Out-Host
tut-pause
}

if ($Beg) {
# section 2c

cls
Write-Host ""
Write-Host "  2c. Lesen — Seitenwechsel mit -First / -Skip" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  2c.1 Ergebnisse begrenzen mit -First" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Seitenwechsel ist integriert. -First begrenzt die Anzahl der zurückgegebenen Ergebnisse. Nützlich
  für die Vorschau großer Datensätze, ohne alles zu laden.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -First 3
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -First 3 | Out-Host
tut-pause

Write-Host ""
Write-Host "  2c.2 Ergebnisse überspringen mit -Skip" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Kombinieren Sie -Skip mit -First, um vorzuspringen. -Skip 1 -First 3 überspringt das erste Ergebnis und
  gibt die nächsten drei zurück — ein klassisches Seitenwechselmuster.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Skip 1 -First 3
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Skip 1 -First 3 | Out-Host
tut-pause

Write-Host ""
Write-Host "  2c.3 Filtern mit Seitenwechsel" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -First und -Skip arbeiten auch mit -Filter zusammen. Hier filtern wir nach Punktzahlen über 70
  und nehmen nur die ersten 3 Ergebnisse.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Filter { $_.Score -gt 70 } -First 3
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Filter { $_.Score -gt 70 } -First 3 | Out-Host
tut-pause
}

if ($Beg) {
# ---------- chapter 3: Update ----------

cls
Write-Host ""
Write-Host "  3. Aktualisieren — Set-BucketObject" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  3.1 Aktualisierung über die Pipeline" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Set-BucketObject aktualisiert ein vorhandenes Objekt direkt. Wenn es von scoop über die Pipeline kommt,
  erkennt es Bucket und Schlüssel automatisch aus den Metadaten _BucketName und _BucketKey —
  kein erneutes Angeben nötig.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Key "Bob" | ForEach-Object {
    $_.Score = 99
    $_.Role = "Lead"
    $_
} | Set-BucketObject -Quiet
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Key "Bob" | ForEach-Object {
    $_.Score = 99
    $_.Role = "Lead"
    $_
} | Set-BucketObject -Quiet
tut-pause

Write-Host ""
Write-Host "  3.2 Expliziter Bucket und Schlüssel" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Ohne Pipeline-Metadaten geben Sie -Bucket und -Key explizit an. übergeben Sie das modifizierte
  Objekt über -InputObject.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$obj = scoop -Bucket team -Key "Carol"
$obj.Score = 100
Set-BucketObject -Bucket team -Key "Carol" -InputObject $obj -Quiet
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
$obj = scoop -Bucket team -Key "Carol"
$obj.Score = 100
Set-BucketObject -Bucket team -Key "Carol" -InputObject $obj -Quiet
tut-pause

Write-Host ""
Write-Host "  3.3 Teilaktualisierung mit Hashtable" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Nur ein Feld aktualisieren? übergeben Sie eine Hashtable mit nur den Eigenschaften, die Sie
  ändern möchten. Buckets führt sie mit dem vorhandenen Objekt zusammen — Teilaktualisierungen
  funktionieren nahtlos.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$patch = @{ Email = "alice@contoso.com" }
$patch | Set-BucketObject -Bucket team -Key "Alice" -Quiet
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
$patch = @{ Email = "alice@contoso.com" }
$patch | Set-BucketObject -Bucket team -Key "Alice" -Quiet
tut-pause

Write-Host ""
Write-Host "  3.4 Neue Eigenschaften hinzufügen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Neue Eigenschaften werden automatisch hinzugefügt. Wenn die Eigenschaft im Originalobjekt nicht
  existiert, wird sie angehängt, ohne vorhandene Felder zu beeinträchtigen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$patch = @{ Phone = "555-0100" }
$patch | Set-BucketObject -Bucket team -Key "Alice" -Quiet
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
$patch = @{ Phone = "555-0100" }
$patch | Set-BucketObject -Bucket team -Key "Alice" -Quiet
tut-pause

Write-Host ""
Write-Host "  3.5 Unveränderte Eigenschaften bewahren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Eigenschaften, die Sie in der Aktualisierung nicht erwähnen, bleiben unberührt. Nur die Schlüssel in Ihrer
  Patch-Hashtable werden geändert.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$patch = @{ City = "Portland" }
$patch | Set-BucketObject -Bucket team -Key "Alice" -Quiet
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
$patch = @{ City = "Portland" }
$patch | Set-BucketObject -Bucket team -Key "Alice" -Quiet
tut-pause

Write-Host ""
Write-Host "  3.6 Formaterhaltung" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Formaterhaltung: JSON-Objekte bleiben .json, binäre Objekte bleiben .dat.
  Set-BucketObject schreibt immer im Originalformat zurück.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$config = @{ Host = "localhost"; Port = 5432 }
$config | fill -Bucket config -Key "db-settings" -AsJson
$patch = @{ UpdatedAt = Get-Date; Host = "prod-server" }
$patch | Set-BucketObject -Bucket config -Key "db-settings" -Quiet
'@
$config = @{ Host = "localhost"; Port = 5432 }
$config | fill -Bucket config -Key "db-settings" -AsJson -Quiet
$patch = @{ UpdatedAt = Get-Date; Host = "prod-server" }
$patch | Set-BucketObject -Bucket config -Key "db-settings" -Quiet
tut-pause

Write-Host ""
Write-Host "  3.7 Warnung bei fehlenden Metadaten" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Was passiert, wenn Sie ohne Metadaten UND ohne explizite -Bucket/-Key an Set-BucketObject übergeben?
  Es gibt einen Fehler aus — es weiß nicht, wohin es speichern soll.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
try { @{ X = 1 } | Set-BucketObject -Quiet -ErrorAction Stop }
catch { Write-Host "    Fehler: -Bucket und -Key erforderlich" -ForegroundColor Green }
'@
try { @{ X = 1 } | Set-BucketObject -Quiet -ErrorAction Stop }
catch { Write-Host "    Fehler: -Bucket und -Key erforderlich" -ForegroundColor Green }
tut-pause
}

if ($Beg) {
# ---------- chapter 4: Delete ----------

cls
Write-Host ""
Write-Host "  4. Löschen — Remove-BucketObject" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  4.1 Vorschau mit -WhatIf" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -WhatIf zeigt eine Vorschau dessen, was gelöscht würde, ohne tatsächlich etwas zu entfernen.
  Immer sicher, es vor dem Löschen auszuprobieren.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-BucketObject -Bucket team -Key "Bob" -WhatIf
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Remove-BucketObject -Bucket team -Key "Bob" -WhatIf
tut-pause

Write-Host ""
Write-Host "  4.2 Nach Schlüssel löschen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Das Löschen nach Schlüssel ist einfach. Geben Sie den Schlüssel des Objekts an, das Sie entfernen möchten.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-BucketObject -Bucket team -Key "Bob" -Quiet
scoop -Bucket team
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Remove-BucketObject -Bucket team -Key "Bob" -Quiet
scoop -Bucket team | Out-Host
tut-pause

Write-Host ""
Write-Host "  4.3 Nicht existenten Schlüssel löschen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Der Versuch, einen nicht existierenden Schlüssel zu löschen, gibt eine Warnung aus, aber keinen Fehler.
  Buckets ist nachsichtig bei fehlenden Objekten.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-BucketObject -Bucket team -Key "Zoe"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Remove-BucketObject -Bucket team -Key "Zoe"
tut-pause

Write-Host ""
Write-Host "  4.4 Schlüssel-oder-alle-Erfordernis" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Sie müssen entweder -Key, -All oder einen Filter angeben. Ohne eines davon lehnt die
  Parametersatzvalidierung den Befehl ab.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-BucketObject -Bucket team -ErrorAction SilentlyContinue
'@
Remove-BucketObject -Bucket team -ErrorAction SilentlyContinue
tut-pause

Write-Host ""
Write-Host "  4.5 Löschen mit -Match" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -Match funktioniert auch beim Löschen. Löschen Sie alle Objekte, die bestimmte Kriterien erfüllen,
  mit einem Befehl.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-BucketObject -Bucket team -Match @{ Role = "QA" } -Quiet
scoop -Bucket team
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Remove-BucketObject -Bucket team -Match @{ Role = "QA" } -Quiet
scoop -Bucket team | Out-Host
tut-pause

Write-Host ""
Write-Host "  4.6 Löschen mit -Filter" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -Filter funktioniert genauso — löschen Sie Objekte, die die Scriptblock-Bedingung erfüllen.
  Hier wird jedes inaktive Mitglied entfernt.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-BucketObject -Bucket team -Filter { $_.Active -eq $false } -Quiet
scoop -Bucket team
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Remove-BucketObject -Bucket team -Filter { $_.Active -eq $false } -Quiet
scoop -Bucket team | Out-Host
tut-pause

Write-Host ""
Write-Host "  4.7 Alles löschen mit -All" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -All löscht jedes Objekt im Bucket. Eine saubere Ausgangslage.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-BucketObject -Bucket team -All -Quiet
scoop -Bucket team
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Remove-BucketObject -Bucket team -All -Quiet
scoop -Bucket team | Out-Host
tut-pause

Write-Host ""
Write-Host "  4.8 Passthru-Metadaten" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -PassThru gibt Metadaten über das Gelöschte zurück. Nützlich für Protokollierung, Prüfung
  oder Bestätigungsmeldungen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ Data = "gone" }
$tmp | fill -Bucket temp -Key "bye-bye" -Quiet
Remove-BucketObject -Bucket temp -Key "bye-bye" -PassThru -Quiet
'@
$tmp = @{ Data = "gone" }
$tmp | fill -Bucket temp -Key "bye-bye" -Quiet
Remove-BucketObject -Bucket temp -Key "bye-bye" -PassThru -Quiet | Out-Host
tut-pause
}

if ($Adv) {
# ---------- chapter 5: Copy, Rename, Move ----------

cls
Write-Host ""
Write-Host "  5. Objektoperationen — Kopieren, Umbenennen, Verschieben" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  5.1 Innerhalb eines Buckets kopieren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Kopieren Sie ein Objekt im selben Bucket mit einem anderen Schlüssel. Das Original bleibt
  unberührt — dies ist eine echte Kopie, keine Verschiebung.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "Alice-Backup" -Quiet
scoop -Bucket team -Key "Alice-Backup"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "Alice-Backup" -Quiet
scoop -Bucket team -Key "Alice-Backup" | Out-Host
tut-pause

Write-Host ""
Write-Host "  5.2 Bucket-übergreifend kopieren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Kopieren Sie auch bucket-übergreifend. Geben Sie -DestinationBucket an, um in einen anderen Bucket zu kopieren.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Copy-BucketObject -Bucket team -Key "Alice" -DestinationBucket archive -Quiet
scoop -Bucket archive -Key "Alice"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Copy-BucketObject -Bucket team -Key "Alice" -DestinationBucket archive -Quiet
scoop -Bucket archive -Key "Alice" | Out-Host
tut-pause

Write-Host ""
Write-Host "  5.3 Kopieren mit Passthru" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -PassThru bei Copy-BucketObject gibt Metadaten zum Ziel zurück: Quelle, Ziel und neuen Schlüssel —
  nützlich für die Pipeline-Protokollierung.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "Alice-pass" -PassThru -Quiet
Remove-BucketObject -Bucket team -Key "Alice-pass" -Quiet
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "Alice-pass" -PassThru -Quiet | Out-Host
Remove-BucketObject -Bucket team -Key "Alice-pass" -Quiet
tut-pause

Write-Host ""
Write-Host "  5.4 Ein Objekt umbenennen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Rename ändert den Schlüssel eines vorhandenen Objekts direkt. Das Format (binär oder JSON)
  bleibt beim Umbenennen erhalten.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ Data = "rename me" }
$tmp | fill -Bucket tmp -Key "old-name" -Quiet
Rename-BucketObject -Bucket tmp -Key "old-name" -NewKey "new-name" -Quiet
'@
$tmp = @{ Data = "rename me" }
$tmp | fill -Bucket tmp -Key "old-name" -Quiet
Rename-BucketObject -Bucket tmp -Key "old-name" -NewKey "new-name" -Quiet
tut-pause

Write-Host ""
Write-Host "  5.5 Umbenennen erhält Format" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Das Umbenennen eines JSON-Objekts erhält auch die .json-Erweiterung. Das Format wird immer
  beibehalten — Sie müssen sich nie darum kümmern.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ Format = "json" }
$tmp | fill -Bucket tmp-json -Key "json-old" -AsJson -Quiet
Rename-BucketObject -Bucket tmp-json -Key "json-old" -NewKey "json-new" -PassThru -Quiet
'@
$tmp = @{ Format = "json" }
$tmp | fill -Bucket tmp-json -Key "json-old" -AsJson -Quiet
Rename-BucketObject -Bucket tmp-json -Key "json-old" -NewKey "json-new" -PassThru -Quiet | Out-Host
tut-pause

Write-Host ""
Write-Host "  5.6 Zwischen Buckets verschieben" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Move kombiniert Kopieren + Löschen in einem Vorgang. Das Objekt wird an das Ziel kopiert
  und von der Quelle entfernt.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$data = @(
    @{ Id = "obj1"; Value = "move me" }
)
$data | fill -Bucket source -KeyProperty Id -Quiet
Move-BucketObject -Bucket source -Key "obj1" -DestinationBucket dest -Quiet
'@
$data = @(
    @{ Id = "obj1"; Value = "move me" }
)
$data | fill -Bucket source -KeyProperty Id -Quiet
Move-BucketObject -Bucket source -Key "obj1" -DestinationBucket dest -Quiet
tut-pause

Write-Host ""
Write-Host "  5.7 Verschieben mit Umbenennung" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Verschieben mit Umbenennung: Geben Sie einen anderen Schlüssel im Ziel-Bucket an, um
  als Teil der Verschiebung umzubenennen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ Data = "moved+renamed" }
$tmp | fill -Bucket origin -Key "orig-key" -Quiet
Move-BucketObject -Bucket origin -Key "orig-key" -DestinationBucket final -DestinationKey "new-key" -Quiet
'@
$tmp = @{ Data = "moved+renamed" }
$tmp | fill -Bucket origin -Key "orig-key" -Quiet
Move-BucketObject -Bucket origin -Key "orig-key" -DestinationBucket final -DestinationKey "new-key" -Quiet
tut-pause

Write-Host ""
Write-Host "  5.8 Verschieben mit Passthru" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -PassThru bei Move gibt Metadaten sowohl zum Quell- als auch zum Zielobjekt zurück.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ X = 1 }
$tmp | fill -Bucket move-src -Key "m-pass" -Quiet
Move-BucketObject -Bucket move-src -Key "m-pass" -DestinationBucket move-dst -PassThru -Quiet
'@
$tmp = @{ X = 1 }
$tmp | fill -Bucket move-src -Key "m-pass" -Quiet
Move-BucketObject -Bucket move-src -Key "m-pass" -DestinationBucket move-dst -PassThru -Quiet | Out-Host
tut-pause

Write-Host ""
Write-Host "  5.9 Passthru bei allen Operationen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Alle drei Operationen — Copy, Rename, Move — unterstützen -PassThru. Verketten Sie sie
  für nachvollziehbares Objektmanagement.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ X = 1 }
$tmp | fill -Bucket pass -Key "src-key" -Quiet
Copy-BucketObject -Bucket pass -Key "src-key" -DestinationKey "cp-key" -PassThru -Quiet
Rename-BucketObject -Bucket pass -Key "cp-key" -NewKey "rn-key" -PassThru -Quiet
Move-BucketObject -Bucket pass -Key "src-key" -DestinationBucket pass -DestinationKey "mv-key" -PassThru -Quiet
'@
$tmp = @{ X = 1 }
$tmp | fill -Bucket pass -Key "src-key" -Quiet
Copy-BucketObject -Bucket pass -Key "src-key" -DestinationKey "cp-key" -PassThru -Quiet | Out-Host
Rename-BucketObject -Bucket pass -Key "cp-key" -NewKey "rn-key" -PassThru -Quiet | Out-Host
Move-BucketObject -Bucket pass -Key "src-key" -DestinationBucket pass -DestinationKey "mv-key" -PassThru -Quiet | Out-Host
tut-pause
}

if ($Adv) {
# ---------- chapter 6: Bucket Management ----------

cls
Write-Host ""
Write-Host "  6. Bucket-Verwaltung — dip / Get-Bucket" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  6.1 Buckets mit dip auflisten" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  dip (Kurzform von Get-Bucket) listet alle Ihre Buckets mit Objektzahlen und Zeitstempeln auf.
  Es ist der erste Befehl, wenn Sie eine übersicht möchten.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
dip
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
dip | Out-Host
tut-pause

Write-Host ""
Write-Host "  6.2 Nach Namen filtern" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Filtern Sie Buckets nach Namen mit einer Teilübereinstimmung. "team" findet "team" und jeden
  anderen Bucket mit "team" im Namen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
dip "team"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
dip "team" | Out-Host
tut-pause

Write-Host ""
Write-Host "  6.3 Bucket-Statistiken" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Get-BucketStats zeigt detaillierte Statistiken: Objektanzahl, Gesamtgröße auf der Platte und
  Erstellungs-/änderungszeitstempel für einen bestimmten Bucket.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-BucketStats -Bucket team
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Get-BucketStats -Bucket team | Out-Host
tut-pause

Write-Host ""
Write-Host "  6.4 Schlüssel auflisten" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Get-BucketKeys listet jeden Schlüssel in einem Bucket auf — nur die Schlüsselnamen,
  kein Deserialisierungsaufwand. Für Format, Größe, Typ und Kompression
  verwenden Sie Get-BucketObjectStats.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-BucketKeys -Bucket team
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Get-BucketKeys -Bucket team | Out-Host
tut-pause

Write-Host ""
Write-Host "  6.5 Objekt-Statistiken" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Get-BucketObjectStats gibt detaillierte Metadaten pro Objekt zurück: Format, Typ,
  Größe, letzte änderung und Kompressionsstatus.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-BucketObjectStats -Bucket team
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Get-BucketObjectStats -Bucket team | Out-Host
tut-pause

Write-Host ""
Write-Host "  6.6 Schlüssel nach Muster filtern" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Filtern Sie Schlüssel nach Muster mit -Match. "A*" findet alle Schlüssel, die mit "A" beginnen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-BucketKeys -Bucket team -Match "A*"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Get-BucketKeys -Bucket team -Match "A*" | Out-Host
tut-pause

Write-Host ""
Write-Host "  6.7 Schlüssel über alle Buckets" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Get-BucketKeys über alle Buckets mit dem Platzhalter "*" — ein vollständiges Inventar
  jedes gespeicherten Objekts.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-BucketKeys -Bucket "*"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
Get-BucketKeys -Bucket "*" | Out-Host
tut-pause

Write-Host ""
Write-Host "  6.8 Baumansicht" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Der Parameter -Tree stellt Ihre Buckets als visuellen Verzeichnisbaum dar. -MaxFiles
  begrenzt die Anzahl der pro Bucket angezeigten Objekte.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -MaxFiles 10
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
Get-Bucket -Tree -MaxFiles 10 | Out-Host
tut-pause

Write-Host ""
Write-Host "  6.9 Nur-Bucket-Baum" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Ohne -Objects zeigt der Baum nur Buckets — eine saubere Strukturansicht ohne
  einzelne Objekte, die die Ausgabe überladen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
Get-Bucket -Tree | Out-Host
tut-pause

Write-Host ""
Write-Host "  6.10 Baum mit Objekten" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Fügen Sie -Objects hinzu, um einzelne Objekte im Baum anzuzeigen. Jedes Blattobjekt ist sichtbar.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -Objects
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
Get-Bucket -Tree -Objects | Out-Host
tut-pause

Write-Host ""
Write-Host "  6.11 Rohe Baumausgabe" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Der Schalter -Raw gibt Baumobjekte als pipeline-fähige Daten statt formatiertem Text zurück.
  Nützlich für die weitere Verarbeitung oder benutzerdefinierte Anzeige.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -Raw | Select-Object -First 2
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
Get-Bucket -Tree -Raw | Select-Object -First 2 | Out-Host
tut-pause

Write-Host ""
Write-Host "  6.12 Tiefenbegrenzter Baum" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -Depth begrenzt, wie viele Verschachtelungsebenen der Baum durchläuft. Tiefe 1 zeigt
  nur Buckets der obersten Ebene.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -Depth 1
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
Get-Bucket -Tree -Depth 1 | Out-Host
tut-pause

Write-Host ""
Write-Host "  6.13 Baum als JSON" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Leiten Sie die rohe Baumausgabe an ConvertTo-Json für eine strukturierte JSON-Darstellung Ihrer
  Bucket-Hierarchie weiter.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -Raw | ConvertTo-Json -Depth 5 | Select-Object -First 5
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
Get-Bucket -Tree -Raw | ConvertTo-Json -Depth 5 | Select-Object -First 5 | Out-Host
tut-pause

Write-Host ""
Write-Host "  6.14 Saubere übersichtstabelle" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Wählen Sie Name und ObjectCount von dip für eine saubere Tabelle der Buckets mit ihren
  Objektanzahlen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
dip | Select-Object Name, ObjectCount
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
dip | Select-Object Name, ObjectCount | Out-Host
tut-pause
}

if ($Adv) {
# section 6a

cls
Write-Host ""
Write-Host "  6a. Remove-Bucket — Sicherheit und Platzhalter" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  6a.1 Entfernen Vorschau" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -WhatIf zeigt eine Vorschau dessen, was entfernt würde, ohne tatsächlich etwas zu löschen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-Bucket "team" -WhatIf
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Remove-Bucket "team" -WhatIf
tut-pause

Write-Host ""
Write-Host "  6a.2 Platzhalter-Vorschau" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Platzhaltermuster funktionieren auch. Vorschau zum Entfernen aller Buckets, die einem Muster entsprechen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Remove-Bucket "t*" -WhatIf
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Remove-Bucket "t*" -WhatIf
tut-pause

Write-Host ""
Write-Host "  6a.3 Einzelnen Bucket entfernen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Entfernen Sie einen einzelnen Bucket. Stellen Sie sicher, dass er nur Bucket-Objektdateien enthält — Buckets
  weigert sich, Verzeichnisse mit anderen Dateitypen zu entfernen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ A = 1 }
$tmp | fill -Bucket temp-remove -Key "x" -Quiet
Remove-Bucket temp-remove -Force -Confirm:$false
'@
$tmp = @{ A = 1 }
$tmp | fill -Bucket temp-remove -Key "x" -Quiet
Remove-Bucket temp-remove -Force -Confirm:$false | Out-Host
tut-pause

Write-Host ""
Write-Host "  6a.4 Sicherheitsprüfung beim Entfernen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Sicherheit zuerst: Remove-Bucket prüft, ob ein Verzeichnis nur Bucket-Dateien enthält.
  Wenn es unerwartete Dateitypen (wie .exe) findet, überspringt es das Verzeichnis mit einer
  Warnung, anstatt es zu löschen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$badDir = Join-Path (Get-BucketRoot) "not-a-bucket"
$null = New-Item -ItemType Directory -Path $badDir -Force
Set-Content -Path (Join-Path $badDir "evil.exe") -Value "x" -NoNewline
Remove-Bucket "not-a-bucket" -Force -Confirm:$false -WarningAction SilentlyContinue 2>$null
Remove-Item $badDir -Recurse -Force -ErrorAction SilentlyContinue
'@
$badDir = Join-Path (Get-BucketRoot) "not-a-bucket"
$null = New-Item -ItemType Directory -Path $badDir -Force
Set-Content -Path (Join-Path $badDir "evil.exe") -Value "x" -NoNewline
Remove-Bucket "not-a-bucket" -Force -Confirm:$false -WarningAction SilentlyContinue 2>$null | Out-Host
Remove-Item $badDir -Recurse -Force -ErrorAction SilentlyContinue
tut-pause
}

if ($Adv) {
# ---------- chapter 7: Export / Import ----------

cls
Write-Host ""
Write-Host "  7. Export / Import — Export-Bucket, Import-Bucket" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""

Write-Host ""
Write-Host "  7.1 Export nach CLIXML" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Export speichert einen gesamten Bucket in einer Archivdatei. CLIXML (Standard) bewahrt
  die .NET-Typinformationen für perfekte Round-Trip-Treue.
"@ -ForegroundColor White
Write-Host ""

$exportDir = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-tutorial-export"
$null = New-Item -ItemType Directory -Path $exportDir -Force -ErrorAction SilentlyContinue

tut-write-code @'
Export-Bucket -Bucket team -OutputFile (Join-Path $exportDir "team.clixml") -Quiet
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Export-Bucket -Bucket team -OutputFile (Join-Path $exportDir "team.clixml") -Quiet
tut-pause

Write-Host ""
Write-Host "  7.2 Export nach JSON" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Export nach JSON für menschenlesbare Archive. Gleiche Daten, anderes Format —
  nützlich, wenn Sie die Daten außerhalb von PowerShell prüfen oder teilen möchten.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Export-Bucket -Bucket team -OutputFile (Join-Path $exportDir "team.json") -AsJson -Quiet
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Export-Bucket -Bucket team -OutputFile (Join-Path $exportDir "team.json") -AsJson -Quiet
tut-pause

Write-Host ""
Write-Host "  7.3 Platzhalter-Export" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Platzhalter funktionieren für Batch-Exporte. Exportieren Sie mehrere Buckets, die einem Muster entsprechen,
  in eine einzige Archivdatei.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Export-Bucket -Bucket "t*","config" -OutputFile (Join-Path $exportDir "multi-export.clixml") -Quiet
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
Export-Bucket -Bucket "t*","config" -OutputFile (Join-Path $exportDir "multi-export.clixml") -Quiet
tut-pause

Write-Host ""
Write-Host "  7.4 Import aus CLIXML" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Import stellt aus einem CLIXML-Archiv in einem neuen Bucket wieder her. Objekte werden mit
  ihren ursprünglichen Schlüsseln und Daten neu erstellt.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Import-Bucket -Bucket restored -InputFile (Join-Path $exportDir "team.clixml") -Quiet
'@
Import-Bucket -Bucket restored -InputFile (Join-Path $exportDir "team.clixml") -Quiet
tut-pause

Write-Host ""
Write-Host "  7.5 Import aus JSON" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Der Import aus JSON funktioniert genauso. Die JSON-Datei wird analysiert und jedes Objekt
  im angegebenen Bucket gespeichert.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Import-Bucket -Bucket restored-json -InputFile (Join-Path $exportDir "team.json") -AsJson -Quiet
'@
Import-Bucket -Bucket restored-json -InputFile (Join-Path $exportDir "team.json") -AsJson -Quiet
tut-pause

Write-Host ""
Write-Host "  7.6 überschreiben beim Import" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -Overwrite beim Import ersetzt vorhandene Schlüssel, anstatt sie zu überspringen. Mit
  -Overwrite erzeugt ein zweiter Import keine Duplikate.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Import-Bucket -Bucket import-over -InputFile (Join-Path $exportDir "team.clixml") -Quiet
Import-Bucket -Bucket import-over -InputFile (Join-Path $exportDir "team.clixml") -Overwrite -Quiet
'@
Import-Bucket -Bucket import-over -InputFile (Join-Path $exportDir "team.clixml") -Quiet
Import-Bucket -Bucket import-over -InputFile (Join-Path $exportDir "team.clixml") -Overwrite -Quiet
tut-pause

Write-Host ""
Write-Host "  7.7 JSON-Archive inspizieren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  JSON-Archive sind Klartext. öffnen Sie sie in einem beliebigen Editor, um sie vor dem Import
  zu prüfen oder zu ändern.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-Content (Join-Path $exportDir "team.json") -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 5 | Select-Object -First 3
'@
Get-Content (Join-Path $exportDir "team.json") -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 5 | Select-Object -First 3 | Out-Host
tut-pause
}

if ($exportDir) { Remove-Item $exportDir -Recurse -Force -ErrorAction SilentlyContinue }

if ($Adv) {
# ---------- chapter 8: PSDrive ----------

cls
Write-Host ""
Write-Host "  8. PSDrive — Buckets wie ein Dateisystem durchsuchen" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  8.1 Das buckets:-Laufwerk" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Buckets registriert ein benutzerdefiniertes PSDrive namens "buckets:". Sie können es mit
  cd, Get-ChildItem, Get-Content durchsuchen — genau wie jedes andere Laufwerk.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-PSDrive -Name buckets
'@
Get-PSDrive -Name buckets | Out-Host
tut-pause

Write-Host ""
Write-Host "  8.2 Buckets auflisten" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Listen Sie alle Buckets mit Get-ChildItem im Laufwerksstammverzeichnis auf. Jeder Bucket erscheint als
  Container (Verzeichnis).
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-ChildItem "buckets:\"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
Get-ChildItem "buckets:\" | Out-Host
tut-pause

Write-Host ""
Write-Host "  8.3 Bucket-Ausgabe formatieren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Formatieren Sie die Ausgabe mit Select-Object für eine sauberere Tabelle mit Bucket-Namen,
  Größen und Zeitstempeln.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-ChildItem "buckets:\" | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
Get-ChildItem "buckets:\" | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize | Out-Host
tut-pause

Write-Host ""
Write-Host "  8.4 Objekte in einem Bucket durchsuchen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Betreten Sie einen Bucket und listen Sie seine Objekte auf. Jedes gespeicherte Objekt erscheint als Datei
  im PSDrive.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-ChildItem "buckets:\team" | Select-Object Name, Length, LastWriteTime
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Get-ChildItem "buckets:\team" | Select-Object Name, Length, LastWriteTime | Out-Host
tut-pause

Write-Host ""
Write-Host "  8.5 Container filtern" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Filtern Sie mit PSIsContainer, um nur Buckets (Container) oder nur Blattobjekte zu sehen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-ChildItem "buckets:\" | Where-Object { $_.PSIsContainer }
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
Get-ChildItem "buckets:\" | Where-Object { $_.PSIsContainer } | Out-Host
tut-pause

Write-Host ""
Write-Host "  8.6 Objekte lesen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Lesen Sie ein Objekt mit Get-Content (oder cat). Es deserialisiert die gespeicherten Daten zurück
  in ein lebendiges PowerShell-Objekt — kein manuelles Parsen nötig.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Get-Content "buckets:\team\Alice" | Select-Object Name, Role, Score
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Get-Content "buckets:\team\Alice" | Select-Object Name, Role, Score | Out-Host
tut-pause

Write-Host ""
Write-Host "  8.7 Round-Trip: lesen, ändern, schreiben" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Der vollständige Round-Trip im PSDrive: lesen mit Get-Content, Eigenschaft ändern,
  zurückschreiben mit Set-Content. Funktioniert wie eine Datei, aber mit lebendigen Objekten.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$obj = Get-Content "buckets:\team\Carol"
$obj.Score = 95
$obj | Set-Content "buckets:\team\Carol"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
$obj = Get-Content "buckets:\team\Carol"
$obj.Score = 95
$obj | Set-Content "buckets:\team\Carol"
tut-pause

Write-Host ""
Write-Host "  8.8 Objekte entfernen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Remove-Item funktioniert auch im PSDrive. Löschen Sie ein Objekt über seinen Pfad.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "psdrive-remove-test" -Quiet
Remove-Item "buckets:\team\psdrive-remove-test" -Force
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "psdrive-remove-test" -Quiet
Remove-Item "buckets:\team\psdrive-remove-test" -Force
tut-pause

Write-Host ""
Write-Host "  8.9 Existenz prüfen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Test-Path prüft, ob ein Objekt im Laufwerk existiert. Nützlich für bedingte Logik.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Test-Path "buckets:\team\Alice"
Test-Path "buckets:\team\NonExistent"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Test-Path "buckets:\team\Alice"
Test-Path "buckets:\team\NonExistent"
tut-pause

Write-Host ""
Write-Host "  8.10 Objekte kopieren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Copy-Item funktioniert bucket-übergreifend im PSDrive. Kopieren Sie Objekte von einem Bucket
  in einen anderen mit vertrauten Dateisystembefehlen.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
Copy-Item "buckets:\team\Alice" "buckets:\team\Alice-pscopy" -Force
Remove-BucketObject -Bucket team -Key "Alice-pscopy" -Quiet
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
Copy-Item "buckets:\team\Alice" "buckets:\team\Alice-pscopy" -Force
Remove-BucketObject -Bucket team -Key "Alice-pscopy" -Quiet
tut-pause

Write-Host ""
Write-Host "  8.11 Tab-Vervollständigung" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Die Tab-Vervollständigung funktioniert im gesamten PSDrive. Versuchen Sie, "buckets:\" zu tippen und
  Tab zu drücken — sie vervollständigt Bucket-Namen und Objektschlüssel.
"@ -ForegroundColor White
tut-pause
}

if ($Adv) {
# ---------- chapter 9: Nested Buckets ----------

cls
Write-Host ""
Write-Host "  9. Verschachtelte Buckets — Verzeichnishierarchie" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  9.1 Verschachtelte Buckets erstellen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Bucket-Namen mit Schrägstrichen erzeugen verschachtelte Verzeichnisstrukturen auf der Platte.
  So organisieren Sie Daten hierarchisch — wie Ordner in Ordnern,
  jede Ebene ein echtes Unterverzeichnis.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$deCities = @(
    @{ Name = "Berlin"; Population = 3600000; Country = "DE" }
    @{ Name = "Munich"; Population = 1500000; Country = "DE" }
)
New-BucketObject -InputObject $deCities -Bucket "org/eu/de/cities" -KeyProperty Name -Quiet

$ukCities = @(
    @{ Name = "London"; Population = 8900000; Country = "UK" }
    @{ Name = "Manchester"; Population = 550000; Country = "UK" }
)
$ukCities | fill -Bucket "org/eu/uk/cities" -KeyProperty Name -Quiet

$usCities = @(
    @{ Name = "New York"; Population = 8300000; Country = "US" }
)
$usCities | fill -Bucket "org/us/cities" -KeyProperty Name -Quiet

$deDepts = @(
    @{ Dept = "Engineering"; Lead = "Alice" }
    @{ Dept = "Marketing"; Lead = "Bob" }
)
$deDepts | fill -Bucket "org/eu/de/depts" -KeyProperty Dept -Quiet
'@
$deCities = @(
    @{ Name = "Berlin"; Population = 3600000; Country = "DE" }
    @{ Name = "Munich"; Population = 1500000; Country = "DE" }
)
New-BucketObject -InputObject $deCities -Bucket "org/eu/de/cities" -KeyProperty Name -Quiet

$ukCities = @(
    @{ Name = "London"; Population = 8900000; Country = "UK" }
    @{ Name = "Manchester"; Population = 550000; Country = "UK" }
)
$ukCities | fill -Bucket "org/eu/uk/cities" -KeyProperty Name -Quiet

$usCities = @(
    @{ Name = "New York"; Population = 8300000; Country = "US" }
)
$usCities | fill -Bucket "org/us/cities" -KeyProperty Name -Quiet

$deDepts = @(
    @{ Dept = "Engineering"; Lead = "Alice" }
    @{ Dept = "Marketing"; Lead = "Bob" }
)
$deDepts | fill -Bucket "org/eu/de/depts" -KeyProperty Dept -Quiet
tut-pause

Write-Host ""
Write-Host "  9.2 Platzhalter in verschachtelten Pfaden" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Platzhalter funktionieren in verschachtelten Pfaden. "org/eu/*/cities" findet Stadt-Buckets unter
  jedem EU-Land — Deutschland, UK und so weiter.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
scoop -Bucket "org/eu/*/cities"
'@
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin" -Quiet
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London" -Quiet
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York" -Quiet
scoop -Bucket "org/eu/*/cities" | Out-Host
tut-pause

Write-Host ""
Write-Host "  9.3 Verschachtelte Buckets direkt abfragen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Fragen Sie einen verschachtelten Pfad direkt mit seinem vollständigen Bucket-Namen ab. Gleicher scoop-Befehl,
  nur ein tieferer Pfad.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
scoop -Bucket "org/eu/de/cities"
'@
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin" -Quiet
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London" -Quiet
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York" -Quiet
scoop -Bucket "org/eu/de/cities" | Out-Host
tut-pause

Write-Host ""
Write-Host "  9.4 Mehrstufige Platzhalter" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Platzhalter auf mehreren Ebenen für tiefe Abfragen. "org/*/de/*" findet alles
  unter dem "de"-Unterbucket jedes Landes.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
scoop -Bucket "org/*/de/*"
'@
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin" -Quiet
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London" -Quiet
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York" -Quiet
scoop -Bucket "org/*/de/*" | Out-Host
tut-pause

Write-Host ""
Write-Host "  9.5 Rekursive Bucket-Auflistung" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Get-Bucket mit -Recurse zeigt die vollständige verschachtelte Struktur. Es durchläuft alle
  Unter-Buckets rekursiv.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-Bucket -Name "org" -Recurse
'@
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin" -Quiet
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London" -Quiet
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York" -Quiet
Get-Bucket -Name "org" -Recurse | Out-Host
tut-pause

Write-Host ""
Write-Host "  9.6 Baumansicht verschachtelter Buckets" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Die Baumansicht visualisiert die Verschachtelungshierarchie. Jede Ebene ist eingerückt, sodass
  die Organisationsstruktur auf einen Blick erkennbar ist.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-Bucket -Name "org" -Tree -Objects -MaxFiles 10
'@
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin" -Quiet
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London" -Quiet
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York" -Quiet
Get-Bucket -Name "org" -Tree -Objects -MaxFiles 10 | Out-Host
tut-pause

Write-Host ""
Write-Host "  9.7 PSDrive mit verschachtelten Pfaden" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  PSDrive unterstützt auch verschachtelte Pfade. Navigieren Sie mit Get-ChildItem in org/eu/de/cities,
  genau wie bei einem Dateisystempfad.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-ChildItem "buckets:\org\eu\de\cities" | Select-Object Name
'@
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin" -Quiet
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London" -Quiet
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York" -Quiet
Get-ChildItem "buckets:\org\eu\de\cities" | Select-Object Name | Out-Host
tut-pause

Write-Host ""
Write-Host "  9.8 Rekursive PSDrive-Auflistung" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Rekursive Auflistung im PSDrive mit dem Flag -Recurse. Zeigt alles unter
  dem org-Baum.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-ChildItem "buckets:\org" -Recurse | Select-Object Name | Format-Table -AutoSize
'@
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin" -Quiet
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London" -Quiet
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York" -Quiet
Get-ChildItem "buckets:\org" -Recurse | Select-Object Name | Format-Table -AutoSize | Out-Host
tut-pause

Write-Host ""
Write-Host "  9.9 Statistiken zu verschachtelten Buckets" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Statistiken funktionieren auch bei verschachtelten Buckets. Get-BucketStats verarbeitet den vollständigen Pfad.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-BucketStats -Bucket "org/eu/de/cities"
'@
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin" -Quiet
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London" -Quiet
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York" -Quiet
Get-BucketStats -Bucket "org/eu/de/cities" | Out-Host
tut-pause

Write-Host ""
Write-Host "  9.10 Schlüssel in verschachtelten Buckets" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Listen Sie Schlüssel in einem verschachtelten Bucket mit Get-BucketKeys auf. Gleicher Befehl, nur ein
  tieferer Bucket-Pfad.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-BucketKeys -Bucket "org/eu/de/cities"
'@
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin" -Quiet
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London" -Quiet
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York" -Quiet
Get-BucketKeys -Bucket "org/eu/de/cities" | Out-Host
tut-pause

Write-Host ""
Write-Host "  9.11 Bucket-übergreifendes Filtern mit Platzhaltern" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Kombinieren Sie Platzhalter mit -Filter für bucket-übergreifende Abfragen in verschachtelten Hierarchien.
  Finden Sie alle Städte mit mehr als 2 Millionen Einwohnern in allen Ländern.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
scoop -Bucket "org/*/cities" -Filter { $_.Population -gt 2000000 }
'@
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin" -Quiet
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London" -Quiet
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York" -Quiet
scoop -Bucket "org/*/cities" -Filter { $_.Population -gt 2000000 } | Out-Host
tut-pause

Write-Host ""
Write-Host "  9.12 Verschachtelte Bäume entfernen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Remove-Bucket mit -Recurse löscht einen ganzen verschachtelten Baum. Ein einziger Befehl
  entfernt org und alles darunter.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Remove-Bucket "org" -Recurse -Force -Confirm:$false
'@
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin" -Quiet
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London" -Quiet
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York" -Quiet
Remove-Bucket "org" -Recurse -Force -Confirm:$false | Out-Host
tut-pause
}

if ($Adv) {
# ---------- chapter 10: Pipeline & Sleek Patterns ----------

cls
Write-Host ""
Write-Host "  10. Eleganter Pipeline-Einsatz" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  10.1 Erzeugen und speichern" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Buckets ist für den pipeline-orientierten Einsatz konzipiert. Die meisten Cmdlets akzeptieren
  Pipeline-Eingaben und geben Objekte mit Metadaten aus. So verketten Sie sie.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
1..5 | ForEach-Object { @{ Name = "item-$_"; Value = $_ * 10 } } |
    fill -Bucket "dir-listing" -KeyProperty Name -Quiet
'@
1..5 | ForEach-Object { @{ Name = "item-$_"; Value = $_ * 10 } } |
    fill -Bucket "dir-listing" -KeyProperty Name -Quiet
tut-pause

Write-Host ""
Write-Host "  10.2 Filtern, ändern, speichern" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Verketten Sie mehrere Operationen in einer Pipeline: filtern mit -Filter, ändern
  mit ForEach-Object und zurückspeichern mit Set-BucketObject. Alles in einem Durchlauf.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Filter { $_.Role -eq "Developer" } |
    ForEach-Object { $_.Score = $_.Score + 5; $_ } |
    Set-BucketObject -PassThru
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Filter { $_.Role -eq "Developer" } |
    ForEach-Object { $_.Score = $_.Score + 5; $_ } |
    Set-BucketObject -PassThru | Out-Host
tut-pause

Write-Host ""
Write-Host "  10.3 Filtern, sortieren, projizieren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Filtern, sortieren und projizieren in einer Pipeline. Where-Object filtert, Sort-Object
  ordnet, Select-Object wählt die gewünschten Eigenschaften aus.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team | Where-Object { $_.Score -gt 80 } |
    Sort-Object Score -Descending |
    Select-Object Name, Role, Score
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team | Where-Object { $_.Score -gt 80 } |
    Sort-Object Score -Descending |
    Select-Object Name, Role, Score | Out-Host
tut-pause

Write-Host ""
Write-Host "  10.4 Bucket-übergreifende Iteration" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Bucket-übergreifende Abfrage: mehrere Buckets durchlaufen, jeden filtern und
  die Ergebnisse mit Bucket-Metadaten projizieren.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Name = "HighScore"; Score = 90 } | fill -Bucket config -Key "app-config"
@{ Name = "DemoItem"; Score = 85 } | fill -Bucket demo -Key "demo-score"
$buckets = @("team", "config", "demo")
$buckets | ForEach-Object { scoop -Bucket $_ -Filter { $_.Score -gt 80 } } |
    Select-Object _BucketName, Name, Score
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Name = "HighScore"; Score = 90 } | fill -Bucket config -Key "app-config" -Quiet
@{ Name = "DemoItem"; Score = 85 } | fill -Bucket demo -Key "demo-score" -Quiet
$buckets = @("team", "config", "demo")
$buckets | ForEach-Object { scoop -Bucket $_ -Filter { $_.Score -gt 80 } } |
    Select-Object _BucketName, Name, Score | Out-Host
tut-pause

Write-Host ""
Write-Host "  10.5 Nach Bucket gruppieren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Gruppieren Sie nach Bucket-Namen, um zu sehen, wie Objekte auf Ihre Buckets verteilt sind.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
@{ Name = "HighScore"; Score = 90 } | fill -Bucket config -Key "app-config"
scoop | Group-Object _BucketName | Select-Object Name, Count
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
@{ Name = "HighScore"; Score = 90 } | fill -Bucket config -Key "app-config" -Quiet
scoop | Group-Object _BucketName | Select-Object Name, Count | Out-Host
tut-pause

Write-Host ""
Write-Host "  10.6 Nach Eigenschaft gruppieren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Group-Object fasst Daten innerhalb eines Buckets zusammen. Hier zählen wir, wie viele
  Teammitglieder welche Rolle haben.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team | Group-Object Role | Select-Object Name, Count
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team | Group-Object Role | Select-Object Name, Count | Out-Host
tut-pause

Write-Host ""
Write-Host "  10.7 Statistiken mit Measure-Object" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Measure-Object liefert Statistiken — Durchschnitt, Minimum, Maximum — für jede
  numerische Eigenschaft Ihrer Objekte.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$scores = scoop -Bucket team | Measure-Object Score -Average -Minimum -Maximum
Write-Host "    Punktestatistik: ø=$([math]::Round($scores.Average,1)) min=$($scores.Minimum) max=$($scores.Maximum)"
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
$scores = scoop -Bucket team | Measure-Object Score -Average -Minimum -Maximum
Write-Host "    Punktestatistik: ø=$([math]::Round($scores.Average,1)) min=$($scores.Minimum) max=$($scores.Maximum)"
tut-pause

Write-Host ""
Write-Host "  10.8 Export nach CSV" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Exportieren Sie gescoopte Daten als CSV für Excel, Python oder jedes Tool, das
  tabellarische Daten liest.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$csvPath = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-team.csv"
scoop -Bucket team | Select-Object Name, Role, Score | Export-Csv -Path $csvPath -NoTypeInformation
Remove-Item $csvPath -Force -ErrorAction SilentlyContinue
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
$csvPath = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-team.csv"
scoop -Bucket team | Select-Object Name, Role, Score | Export-Csv -Path $csvPath -NoTypeInformation
Remove-Item $csvPath -Force -ErrorAction SilentlyContinue
tut-pause

Write-Host ""
Write-Host "  10.9 Filter-Vergleich" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -Filter läuft innerhalb von Buckets (schneller), Where-Object in der Pipeline (flexibler).
  Beide liefern das gleiche Ergebnis — wählen Sie nach Bedarf.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Filter { $_.Score -gt 80 }
scoop -Bucket team | Where-Object { $_.Score -gt 80 }
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Filter { $_.Score -gt 80 } | Out-Host
scoop -Bucket team | Where-Object { $_.Score -gt 80 } | Out-Host
tut-pause

Write-Host ""
Write-Host "  10.10 Benutzerdefinierte Formatierung" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Benutzerdefinierte Formatierung mit ForEach-Object. Wandeln Sie jedes Objekt in einen formatierten
  String für die Anzeige oder Protokollierung um.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team | ForEach-Object {
    "[$($_.Role)] $($_.Name) — Score: $($_.Score)"
}
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team | ForEach-Object {
    "[$($_.Role)] $($_.Name) — Score: $($_.Score)"
} | Out-Host
tut-pause

Write-Host ""
Write-Host "  10.11 Bedingte JSON-Ausgabe" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Bedingte Pipeline: zuerst filtern, dann nur passende Objekte in JSON konvertieren.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket team -Filter { $_.Score -gt 80 } | ConvertTo-Json -Depth 5
'@
$script:Team | fill -Bucket team -KeyProperty Name -Quiet
scoop -Bucket team -Filter { $_.Score -gt 80 } | ConvertTo-Json -Depth 5 | Out-Host
tut-pause

Write-Host ""
Write-Host "  10.12 Round-Trip-Verifikation" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Speichern Sie, lesen Sie sofort und verifizieren Sie die Round-Trip-Integrität. Was Sie schreiben,
  erhalten Sie genau so zurück.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$tmp = @{ Id = "smoke"; Value = 42 }
$tmp | fill -Bucket smoke-test -KeyProperty Id -Quiet
scoop -Bucket smoke-test | Select-Object Id, Value
'@
$tmp = @{ Id = "smoke"; Value = 42 }
$tmp | fill -Bucket smoke-test -KeyProperty Id -Quiet
scoop -Bucket smoke-test | Select-Object Id, Value | Out-Host
tut-pause
}

if ($Adv) {
# ---------- chapter 11: Aliases Quick Reference ----------

cls
Write-Host ""
Write-Host "  11. Aliase & Shortcuts Referenz" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""

Write-Host "  Drei Aliase werden vom Modul exportiert:" -ForegroundColor DarkGray
Write-Host @"

    fill   = New-BucketObject     — save objects
    scoop  = Get-BucketObject     — retrieve objects
    dip    = Get-Bucket            — list buckets

"@ -ForegroundColor Yellow

Write-Host "  Zusätzliche Shortcuts:" -ForegroundColor DarkGray
Write-Host @"
    ls     = Get-ChildItem         — overridden globally (used in buckets: drive)
    cat    = Get-Content           — built-in, works with buckets: drive

"@ -ForegroundColor Yellow

Write-Host "  Pipeline-Parameterbindung über Metadaten:" -ForegroundColor DarkGray
Write-Host @"
    _BucketName   → -Bucket   (on Set-BucketObject)
    _BucketKey    → -Key      (on Set-BucketObject)
    _BucketFile   → full path to the stored file

"@ -ForegroundColor White
tut-pause
}

# ---------- chapter 12: Sysadmin Scenarios ----------

if ($Sys) {

cls
Write-Host ""
Write-Host "  12. Sysadmin-Szenarien" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""

$script:Servers = @(
    @{ Hostname="web-01";   IP="10.0.1.10"; OS="Ubuntu 22.04";  Role="web";        CPU=4;  RAM=8;  Disk=120; Status="online";   Location="DC1" }
    @{ Hostname="web-02";   IP="10.0.1.11"; OS="Ubuntu 22.04";  Role="web";        CPU=4;  RAM=8;  Disk=120; Status="online";   Location="DC1" }
    @{ Hostname="db-01";    IP="10.0.1.20"; OS="Debian 12";     Role="database";   CPU=8;  RAM=32; Disk=500; Status="online";   Location="DC1" }
    @{ Hostname="db-02";    IP="10.0.2.20"; OS="Debian 12";     Role="database";   CPU=8;  RAM=32; Disk=500; Status="degraded"; Location="DC2" }
    @{ Hostname="cache-01"; IP="10.0.1.30"; OS="Alpine 3.18";   Role="cache";      CPU=2;  RAM=16; Disk=60;  Status="online";   Location="DC1" }
    @{ Hostname="mon-01";   IP="10.0.1.40"; OS="Ubuntu 22.04";  Role="monitoring"; CPU=2;  RAM=4;  Disk=250; Status="online";   Location="DC2" }
    @{ Hostname="app-01";   IP="10.0.2.50"; OS="Rocky 9";       Role="app";        CPU=8;  RAM=16; Disk=200; Status="offline";  Location="DC2" }
    @{ Hostname="backup-01";IP="10.0.1.1";  OS="FreeBSD 14";    Role="backup";     CPU=4;  RAM=8;  Disk=2000;Status="online";   Location="DC1" }
)

$script:Incidents = @(
    @{ Timestamp=(Get-Date).AddHours(-2);    Severity="ERROR"; Source="web-01";  Message="Connection pool exhausted" }
    @{ Timestamp=(Get-Date).AddHours(-1);    Severity="WARN";  Source="db-01";   Message="Replication lag 2.3s" }
    @{ Timestamp=(Get-Date).AddMinutes(-30); Severity="INFO";  Source="mon-01";  Message="Health check passed" }
    @{ Timestamp=(Get-Date).AddMinutes(-15); Severity="ERROR"; Source="app-01";  Message="Service unreachable" }
    @{ Timestamp=(Get-Date).AddMinutes(-5);  Severity="CRIT";  Source="app-01";  Message="Disk /dev/sda1 at 97%" }
)

Write-Host ""
Write-Host @"
  Dieser Abschnitt vermittelt Buckets von Grund auf mit realen Daten:
  Serverinventar, Vorfallprotokolle, Gesundheitsberichte und bucket-übergreifende
  Korrelation. Jede Lektion baut auf der vorherigen auf, beginnend einfach und
  an Komplexität zunehmend.
"@ -ForegroundColor White
Write-Host ""

# ---------- 12.1 ----------

Write-Host ""
Write-Host "  12.1 Serverinventar speichern" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Der fill-Alias (Kurzform von New-BucketObject) speichert Objekte in benannten
  Speicherbereichen namens Buckets. Hier speichern wir unser Serverinventar — jeder
  Serverdatensatz wird ein Objekt, das über -KeyProperty mit seinem Hostnamen verschlüsselt wird.
  Der Schalter -Quiet unterdrückt die Zusammenfassungsausgabe.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$script:Servers | fill -Bucket servers -KeyProperty Hostname -Quiet
'@
$script:Servers | fill -Bucket servers -KeyProperty Hostname -Quiet
tut-pause

# ---------- 12.2 ----------

Write-Host ""
Write-Host "  12.2 Fehlerhafte Server finden" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Der scoop-Alias (Kurzform von Get-BucketObject) ruft gespeicherte Objekte ab.
  -Filter akzeptiert einen Scriptblock, um Bedingungen zu erfüllen — wie Where-Object.
  Finden Sie Server, die nicht vollständig online sind: -ne bedeutet "ungleich".
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket servers -Filter { $_.Status -ne "online" }
'@
$script:Servers | fill -Bucket servers -KeyProperty Hostname -Quiet
scoop -Bucket servers -Filter { $_.Status -ne "online" } | Out-Host
tut-pause

# ---------- 12.3 ----------

Write-Host ""
Write-Host "  12.3 Server nach Rolle und Spezifikation filtern" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Kombinieren Sie zwei Bedingungen in einem -Filter-Scriptblock mit -and. Finden Sie
  Datenbankserver mit mindestens 16 GB RAM — ideal, um Hosts für eine bestimmte
  Arbeitslast zu identifizieren.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket servers -Filter { $_.RAM -ge 16 -and $_.Role -eq "database" }
'@
$script:Servers | fill -Bucket servers -KeyProperty Hostname -Quiet
scoop -Bucket servers -Filter { $_.RAM -ge 16 -and $_.Role -eq "database" } | Out-Host
tut-pause

# ---------- 12.4 ----------

Write-Host ""
Write-Host "  12.4 Server nach Rechenzentrum gruppieren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Group-Object ist Ihr Freund für das Rechenzentrumsinventar. Gruppieren Sie Server nach
  ihrer Location-Eigenschaft, um zu sehen, wie viele Hosts in jedem RZ leben.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket servers | Group-Object Location
'@
$script:Servers | fill -Bucket servers -KeyProperty Hostname -Quiet
scoop -Bucket servers | Group-Object Location | Out-Host
tut-pause

# ---------- 12.5 ----------

Write-Host ""
Write-Host "  12.5 Kapazitätsplanung Gesamtsummen" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Measure-Object summiert die gesamten Computeresourcen aller Server. Praktisch
  für die Kapazitätsplanung — wie viel CPU, RAM und Platte haben Sie insgesamt?
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket servers | Measure-Object CPU, RAM, Disk -Sum
'@
$script:Servers | fill -Bucket servers -KeyProperty Hostname -Quiet
scoop -Bucket servers | Measure-Object CPU, RAM, Disk -Sum | Out-Host
tut-pause

# ---------- 12.6 ----------

Write-Host ""
Write-Host "  12.6 Vorfälle mit Zeitstempeln protokollieren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  -AsTimestamp gibt jedem Vorfall einen eindeutigen Schlüssel basierend auf der aktuellen Zeit —
  perfekt für Zeitreihen-Ereignisprotokolle, bei denen Sie niemals Schlüsselkonflikte möchten.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$script:Incidents | fill -Bucket incidents -AsTimestamp -Quiet
'@
$script:Incidents | fill -Bucket incidents -AsTimestamp -Quiet
tut-pause

# ---------- 12.7 ----------

Write-Host ""
Write-Host "  12.7 Kritische Vorfälle priorisieren" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Konzentrieren Sie sich auf das Wesentliche: ERROR- und CRIT-Schweregrade. Der -in-Operator
  im -Filter-Scriptblock gleicht mehrere Werte auf einmal ab.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket incidents -Filter { $_.Severity -in @("ERROR","CRIT") }
'@
$script:Incidents | fill -Bucket incidents -AsTimestamp -Quiet
scoop -Bucket incidents -Filter { $_.Severity -in @("ERROR","CRIT") } | Out-Host
tut-pause

# ---------- 12.8 ----------

Write-Host ""
Write-Host "  12.8 Batch-Wartungsmodus" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Set-BucketObject aktualisiert vorhandene Objekte direkt. Spillen Sie die Webserver,
  fügen Sie mit Add-Member eine Maintenance-Eigenschaft hinzu (deserialisierte Objekte akzeptieren
  keine Punktzuweisung), und leiten Sie sie durch Set-BucketObject, um sie zu speichern.
  Die Zusammenfassung bestätigt, wie viele aktualisiert wurden.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket servers -Filter { $_.Role -eq "web" } |
    ForEach-Object { $_ | Add-Member Maintenance $true -Force; $_ } |
    Set-BucketObject
'@
$script:Servers | fill -Bucket servers -KeyProperty Hostname -Quiet
scoop -Bucket servers -Filter { $_.Role -eq "web" } |
    ForEach-Object { $_ | Add-Member Maintenance $true -Force; $_ } |
    Set-BucketObject | Out-Host
tut-pause

# ---------- 12.9 ----------

Write-Host ""
Write-Host "  12.9 Gesundheitsbericht" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Erstellen Sie einen schnellen Gesundheitsbericht: sortieren Sie Server nach Status, damit
  offline- und degradierte Maschinen nach oben kommen. Wählen Sie nur die relevanten Felder.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
scoop -Bucket servers | Select Hostname, Status, Location | Sort Status
'@
$script:Servers | fill -Bucket servers -KeyProperty Hostname -Quiet
scoop -Bucket servers | Select Hostname, Status, Location | Sort Status | Out-Host
tut-pause

# ---------- 12.10 ----------

Write-Host ""
Write-Host "  12.10 Bucket-übergreifende Korrelation" -ForegroundColor DarkGray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  Bucket-übergreifende Abfragen verbinden zusammenhängende Daten. Spillen Sie kritische
  Vorfälle aus dem incidents-Bucket und schlagen Sie dann jeden betroffenen Server
  mit -Key nach. Das verbindet Ihr Ereignisprotokoll mit Ihrem Inventar in einer Pipeline.
"@ -ForegroundColor White
Write-Host ""
tut-write-code @'
$crit = scoop -Bucket incidents -Filter { $_.Severity -eq "CRIT" }
$crit | ForEach-Object {
    $svr = scoop -Bucket servers -Key $_.Source
    [PSCustomObject]@{ Incident = $_.Message; Server = $svr.Hostname; Status = $svr.Status }
}
'@
$script:Servers | fill -Bucket servers -KeyProperty Hostname -Quiet
$script:Incidents | fill -Bucket incidents -AsTimestamp -Quiet
$crit = scoop -Bucket incidents -Filter { $_.Severity -eq "CRIT" }
$crit | ForEach-Object {
    $svr = scoop -Bucket servers -Key $_.Source
    [PSCustomObject]@{ Incident = $_.Message; Server = $svr.Hostname; Status = $svr.Status }
} | Out-Host
tut-pause

}

# ---------- congratulations ----------

cls
Write-Host ""
Write-Host "  Herzlichen Glückwunsch!" -ForegroundColor Gray
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""

Write-Host @"
  Sie haben das Buckets-Tutorial abgeschlossen. Alle Tutorial-Daten wurden
  bereinigt — Ihr System ist genau so, wie es vor dem Start war.

"@ -ForegroundColor White

Get-ChildItem (Get-BucketRoot) -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host @"

  Was Sie gelernt haben:

    fill / scoop / spill / dip / drain
                                 — speichern, lesen, Objekte loeschen, auflisten, Buckets loeschen
    -Key / -KeyProperty         — naming objects
    -Overwrite / -AsTimestamp    — replacement and timestamp keys
    -AsJson / -Compress          — storage formats
    -Match (exact)              — hashtable-based filtering
    -Filter (scriptblock)       — expression-based comparison (-gt, -like, -contains, -match)
    Nested property filtering   — `$_.Settings.Enabled with -Filter
    -First / -Skip              — pagination
    Set-BucketObject             — update in place (pipeline + explicit)
    Partial update / patch       — add properties with hashtable pipe
    scoop / spill / drain         — lesen, Objekte loeschen, Buckets loeschen
    -WhatIf / -PassThru          — safety preview and metadata capture
    Copy / Rename / Move         — object operations with and without pass-through
    PSDrive operations           — Get-Content, Set-Content, Copy-Item, Remove-Item, Test-Path
    Export / Import              — archive & restore with CLIXML and JSON
    Get-Bucket -Tree             — visual tree view with -Objects, -Raw, -Depth
    Get-BucketStats              — bucket statistics
    Get-BucketKeys               — object key listing
    Get-BucketObjectStats        — detailed per-object statistics
    Nested buckets               — org/eu/de/cities hierarchy with wildcards
    Pipeline patterns            — chain, group, measure, export-csv, expand, custom format
    Cross-bucket queries         — -Filter across all buckets
    Edge cases                   — `$null values, special chars, empty keys, safety guards
    Format preservation          — JSON stays .json, binary stays .dat through Rename/Copy
    Server/event management      — inventory, incidents, health reports, cross-bucket correlation

  Mehr erfahren: Get-Help <Cmdlet> -Full
  Siehe auch:  README.md, .tests/demo/*.ps1

"@ -ForegroundColor Cyan
Write-Host ""
Write-Host "  $Sep" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Viel Spaß mit Buckets!`n" -ForegroundColor Green

# Write tutorial.de.md in markdown generation mode
if ($GenerateMarkdown) {
    $outPath = Join-Path (Split-Path $PSScriptRoot -Parent) "tutorial.de.md"
    $raw = $script:mdOutput.ToString()

    # Strip leading whitespace (2 spaces) from each line
    $clean = $raw -replace "(?m)^  ", ""

    # Convert sub-section headings (e.g. "1.1 Speichern", "1b.3 Tief") to ###
    $clean = $clean -replace "(?m)^(\d+[a-z]?\.\d+\s+\w[^\n]*)", '### $1'

    # Convert main section headings (e.g. "1. Erstellen", "2a. Lesen") to ##
    $clean = $clean -replace "(?m)^(\d+[a-z]?\.\s+\w[^\n]*)", '## $1'

    # Convert horizontal rule lines to markdown ---
    $clean = $clean -replace "(?m)^─{20,}", "---"

    # Remove blank lines at start of output code fences
    $clean = $clean -replace '(?m)^```\n\n+', '```'

    # Collapse 3+ consecutive blank lines into 1 blank line
    $clean = $clean -replace '(?m)^\n{3,}', "`n`n"

    # Trim trailing whitespace per line
    $clean = $clean -replace '(?m)[\t ]+$', ''

    [System.IO.File]::WriteAllText($outPath, $clean, [System.Text.UTF8Encoding]::new($false))
    [Console]::WriteLine("Generated $outPath")
}
