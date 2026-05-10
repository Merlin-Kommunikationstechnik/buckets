#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Buckets Modul — Interaktives Tutorial
.DESCRIPTION
    Kapitelweise Einfuehrung in das Buckets-Modul. Jedes Kapitel
    stellt ein Konzept vor, erklaert das Warum und zeigt das Wie.
    Das gesamte Skript ausfuehren oder mit $chapter ein Kapitel anspringen.
#>

param(
    [int]$Chapter = 1
)

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../../Buckets" -Force

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$createdBuckets = [System.Collections.ArrayList]::new()

function Use-Bucket {
    param([string]$Bucket)
    $null = $createdBuckets.Add($Bucket)
}

function Write-ChapterHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Blue
    Write-Host "║  $($Title.PadRight(40))║" -ForegroundColor Blue
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Blue
}

function Write-Section {
    param([string]$Number, [string]$Title)
    Write-Host ""
    Write-Host "── $Number $Title ────────────────────────" -ForegroundColor Blue
}

# ============================================================
# Kapitel 1: Einfuehrung
# ============================================================
$mod = Get-Module Buckets
$pwsh = "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
$os = if ($IsMacOS) { "macOS" } elseif ($IsLinux) { "Linux" } else { "Windows" }
$sep = "=" * 52

Write-Host $sep -ForegroundColor DarkGray
Write-Host " Buckets Module" -NoNewline -ForegroundColor Blue
Write-Host " v$($mod.Version)" -NoNewline -ForegroundColor Magenta
Write-Host " Tutorium" -ForegroundColor DarkGray
Write-Host " $startTs" -NoNewline -ForegroundColor DarkGray
Write-Host " · " -NoNewline -ForegroundColor DarkGray
Write-Host $pwsh -NoNewline -ForegroundColor Cyan
Write-Host " · " -NoNewline -ForegroundColor DarkGray
Write-Host $os -ForegroundColor DarkGray
Write-Host $sep -ForegroundColor DarkGray

Write-ChapterHeader "Kapitel 1: Einfuehrung"

Write-Section "1.1" "Was ist Buckets?"

Write-Host ""
Write-Host "  Buckets ist ein PowerShell-Modul zur dateibasierten Ablage von" -ForegroundColor White
Write-Host "  PSObjects. Jedes Objekt ist eine Datei, jeder Bucket ein Ordner." -ForegroundColor DarkGray
Write-Host "  Keine Datenbank, kein Dienst, keine Konfigurationsdatei —" -ForegroundColor DarkGray
Write-Host "  nur das Dateisystem." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  ┌─────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
Write-Host "  │" -NoNewline -ForegroundColor DarkGray
Write-Host "  Speichert PSObjects als Dateien" -NoNewline -ForegroundColor White
Write-Host "                 │" -ForegroundColor DarkGray
Write-Host "  │" -NoNewline -ForegroundColor DarkGray
Write-Host "  Liest sie als Objekte zurueck " -NoNewline -ForegroundColor White
Write-Host "                 │" -ForegroundColor DarkGray
Write-Host "  │" -NoNewline -ForegroundColor DarkGray
Write-Host "  Organisiert in verzeichnisbasierten Buckets" -NoNewline -ForegroundColor White
Write-Host "       │" -ForegroundColor DarkGray
Write-Host "  │" -NoNewline -ForegroundColor DarkGray
Write-Host "  Teilbar durch Kopieren des Ordners " -NoNewline -ForegroundColor White
Write-Host "                │" -ForegroundColor DarkGray
Write-Host "  └─────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Zwei Speicherformate:" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Binary" -NoNewline -ForegroundColor Cyan
Write-Host "  —  " -NoNewline -ForegroundColor DarkGray
Write-Host ".dat" -NoNewline -ForegroundColor Magenta
Write-Host "  ueber PSSerializer (Standard, schnell, komplexe Objekte)" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "JSON" -NoNewline -ForegroundColor Cyan
Write-Host "   —  " -NoNewline -ForegroundColor DarkGray
Write-Host ".json" -NoNewline -ForegroundColor Magenta
Write-Host " via " -NoNewline -ForegroundColor DarkGray
Write-Host "-AsJson" -NoNewline -ForegroundColor Cyan
Write-Host " (lesbar, portabel)" -ForegroundColor DarkGray

Write-Section "1.2" "Warum Buckets?"

Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Dauerhaft" -NoNewline -ForegroundColor Green
Write-Host "  — Objekte ueberdauern die PowerShell-Sitzung" -ForegroundColor DarkGray
Write-Host "            heute schreiben, morgen lesen, naechste Woche immer noch" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Teilbar" -NoNewline -ForegroundColor Green
Write-Host "     — Buckets sind Ordner auf der Platte; kopieren, syncen," -ForegroundColor DarkGray
Write-Host "            in die Versionskontrolle einchecken" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Komponierbar" -NoNewline -ForegroundColor Green
Write-Host "  — Pipeline rein, Pipeline raus" -ForegroundColor DarkGray
Write-Host "            " -NoNewline
Write-Host "Get-Process | fill -Bucket procs" -NoNewline -ForegroundColor Cyan
Write-Host "  funktioniert sofort" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Durchsuchbar" -NoNewline -ForegroundColor Green
Write-Host "  — " -NoNewline -ForegroundColor DarkGray
Write-Host "Get-Bucket -Tree" -NoNewline -ForegroundColor Cyan
Write-Host "  zeigt die gesamte Hierarchie auf einen Blick" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Selbstbeschreibend" -NoNewline -ForegroundColor Green
Write-Host "  — Dateinamen sind Schluessel, Verzeichnisse strukturieren" -ForegroundColor DarkGray
Write-Host "            Ihre Daten, JSON-Dateien sind lesbar" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Expand / Collapse" -NoNewline -ForegroundColor Green
Write-Host "  — verschachtelte Strukturen in durchsuchbare" -ForegroundColor DarkGray
Write-Host "            Verzeichnisbaeume zerlegen, beim Lesen rekonstruieren" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Plattformunabhaengig" -NoNewline -ForegroundColor Green
Write-Host "  — PowerShell 7+ unter Windows, macOS, Linux" -ForegroundColor DarkGray
Write-Host "            gleiches Verhalten ueberall" -ForegroundColor DarkGray

Write-Section "1.3" "Wie funktioniert es?"

Write-Host ""
Write-Host "  Jeder Bucket ist ein Verzeichnis unter " -NoNewline -ForegroundColor DarkGray
Write-Host "`$HOME/.buckets" -NoNewline -ForegroundColor Cyan
Write-Host " (ueber " -NoNewline -ForegroundColor DarkGray
Write-Host "-Path" -NoNewline -ForegroundColor Cyan
Write-Host " aenderbar)." -ForegroundColor DarkGray
Write-Host "  Jedes Objekt ist eine Datei — " -NoNewline -ForegroundColor DarkGray
Write-Host ".dat" -NoNewline -ForegroundColor Magenta
Write-Host " (Binary, Standard) oder " -NoNewline -ForegroundColor DarkGray
Write-Host ".json" -NoNewline -ForegroundColor Magenta
Write-Host " (optional)." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  \$HOME/.buckets/" -ForegroundColor Cyan
Write-Host "    users/" -ForegroundColor Cyan
Write-Host "      Alice.dat" -NoNewline -ForegroundColor DarkGray
Write-Host "      ← Schluessel: Alice" -ForegroundColor DarkGray
Write-Host "      Bob.dat" -NoNewline -ForegroundColor DarkGray
Write-Host "        ← Schluessel: Bob" -ForegroundColor DarkGray
Write-Host "    config/" -ForegroundColor Cyan
Write-Host "      app.json" -NoNewline -ForegroundColor DarkGray
Write-Host "       ← JSON-Format, Schluessel: app" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Die vier Kern-Cmdlets:" -ForegroundColor DarkGray
Write-Host ""
Write-Host "    " -NoNewline
Write-Host "fill" -NoNewline -ForegroundColor Green
Write-Host "    · " -NoNewline -ForegroundColor DarkGray
Write-Host "New-BucketObject" -NoNewline -ForegroundColor Cyan
Write-Host "      Objekte in einen Bucket schreiben" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "spill" -NoNewline -ForegroundColor Green
Write-Host "   · " -NoNewline -ForegroundColor DarkGray
Write-Host "Get-BucketObject" -NoNewline -ForegroundColor Cyan
Write-Host "      Objekte aus einem Bucket lesen" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "dip" -NoNewline -ForegroundColor Green
Write-Host "    · " -NoNewline -ForegroundColor DarkGray
Write-Host "Set-BucketObject" -NoNewline -ForegroundColor Cyan
Write-Host "      ein vorhandenes Objekt aktualisieren" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "rmo" -NoNewline -ForegroundColor Green
Write-Host "   · " -NoNewline -ForegroundColor DarkGray
Write-Host "Remove-BucketObject" -NoNewline -ForegroundColor Cyan
Write-Host "  ein Objekt loeschen" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Weitere Cmdlets:" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Get-Bucket" -NoNewline -ForegroundColor Cyan
Write-Host "          Bucket-Liste / Baumansicht" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Get-BucketStats" -NoNewline -ForegroundColor Cyan
Write-Host "    Objektanzahl, Groesse, Zeitstempel" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Get-BucketKeys" -NoNewline -ForegroundColor Cyan
Write-Host "      Schluessel nach Muster suchen" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Copy-BucketObject" -NoNewline -ForegroundColor Cyan
Write-Host "  Objekte zwischen Buckets kopieren" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Rename-BucketObject" -NoNewline -ForegroundColor Cyan
Write-Host "  Objektschluessel umbenennen" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Export-Bucket" -NoNewline -ForegroundColor Cyan
Write-Host "      nach CLIXML oder JSON exportieren" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "Import-Bucket" -NoNewline -ForegroundColor Cyan
Write-Host "      aus CLIXML oder JSON importieren" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Standardpfad: " -NoNewline -ForegroundColor DarkGray
Write-Host "\$HOME/.buckets" -NoNewline -ForegroundColor Cyan
Write-Host "  ·  Ueberschreiben: " -NoNewline -ForegroundColor DarkGray
Write-Host "-Path" -NoNewline -ForegroundColor Cyan
Write-Host "  ·  Binary-Tiefe: " -NoNewline -ForegroundColor DarkGray
Write-Host "5" -NoNewline -ForegroundColor Magenta
Write-Host "  ·  JSON-Tiefe: " -NoNewline -ForegroundColor DarkGray
Write-Host "20" -ForegroundColor Magenta

Write-Section "Weiter"
Write-Host ""
Write-Host "  Damit ist die Einfuehrung abgeschlossen. Das naechste Kapitel" -ForegroundColor DarkGray
Write-Host "  behandelt das Schreiben der ersten Objekte mit " -NoNewline -ForegroundColor DarkGray
Write-Host "New-BucketObject" -NoNewline -ForegroundColor Cyan
Write-Host "." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Das Tutorium mit einem bestimmten Kapitel starten:" -ForegroundColor DarkGray
Write-Host "    " -NoNewline
Write-Host "pwsh .tests/demo/tutorial.de.ps1 -Chapter 2" -ForegroundColor Cyan

# Cleanup
foreach ($b in $createdBuckets) {
    Remove-Bucket $b -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse
}

$elapsed = $sw.Elapsed.TotalSeconds
$endTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host $sep -ForegroundColor DarkGray
Write-Host " Done" -NoNewline -ForegroundColor Blue
Write-Host " · " -NoNewline -ForegroundColor DarkGray
Write-Host "$([math]::Round($elapsed, 1))s" -ForegroundColor Magenta
Write-Host " $endTs" -NoNewline -ForegroundColor DarkGray
Write-Host " · " -NoNewline -ForegroundColor DarkGray
Write-Host $pwsh -NoNewline -ForegroundColor Cyan
Write-Host " · " -NoNewline -ForegroundColor DarkGray
Write-Host $os -ForegroundColor DarkGray
Write-Host $sep -ForegroundColor DarkGray
