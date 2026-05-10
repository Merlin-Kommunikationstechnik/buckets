# Buckets Tutorial (Deutsch)


## 0. Einfuehrung
---

### 0.1 Was ist Buckets?
---

Buckets ist ein PowerShell-Modul zur dateibasierten Ablage von
PSObjects. Jedes Objekt ist eine Datei, jeder Bucket ein Ordner.
Keine Datenbank, kein Dienst, keine Konfigurationsdatei —
nur das Dateisystem.

Zwei Speicherformate:
  Binary (.dat) — ueber PSSerializer. Schnell, erhaelt vollstaendige
                  .NET-Typinformationen. Komplexe Objekte, Zirkelbezüge.
  JSON    (.json) — via -AsJson. Lesbar, portabel, in jedem
                  Texteditor aenderbar.

### 0.2 Warum Buckets?
---

Dauerhaft       — Objekte ueberdauern die PowerShell-Sitzung
Teilbar         — Buckets sind Ordner; kopieren, syncen, einchecken
Komponierbar    — Pipeline rein, Pipeline raus; einfach uebergeben
Durchsuchbar    — Get-Bucket -Tree zeigt die ganze Hierarchie
Selbstbeschreibend — Dateinamen sind Schluessel, JSON ist lesbar
Expand/Collapse — verschachtelte Strukturen als Verzeichnisbaeume
Plattformunabhaengig — PowerShell 7+ auf Windows, macOS, Linux

### 0.3 Wie funktioniert es?
---

Jeder Bucket ist ein Verzeichnis unter einem Wurzelpfad. Der Standard ist:


```powershell
Get-BucketRoot
```



Jedes Objekt ist eine Datei — .dat (Binary, Standard) oder .json (optional).
Der Dateiname (ohne Erweiterung) ist der Schluessel des Objekts.

Aktuelle Buckets:
.buckets (0 items, 0 B)
  (noch keine Buckets)

Die sechs Kern-Cmdlets:

  fill   · New-BucketObject      Objekte schreiben
  spill  · Get-BucketObject      Objekte lesen
  dip    · Get-Bucket            Buckets auflisten
  drain  · Remove-BucketObject   Objekt loeschen
  toss   · Remove-Bucket         Bucket loeschen

Standardwerte: Binary-Tiefe 5, JSON-Tiefe 20, Pfad C:\Users\berfelde/.buckets
Alles ueber -BinaryDepth, -Depth oder -Path aenderbar.

## 1. Erstellen
---

### 1.1 Ihr erstes Objekt speichern
---

Speichern wir Ihr erstes Objekt — eine einfache Hashtable, die einen Benutzer beschreibt. Wir vergeben
einen expliziten Schlüssel "Alice" mit -Key. Standardmäßig verwendet
Buckets ein Binärformat, das die vollständigen .NET-Typinformationen bewahrt, sodass
Hashtables, benutzerdefinierte Objekte und sogar FileInfo den Round-Trip überstehen.


```powershell
$alice = @{ Name = "Alice"; Role = "admin"; Score = 95 }
New-BucketObject -InputObject $alice -Bucket users -Key "Alice"
```

users · 1 objects

1.2 -KeyProperty für automatische Benennung
---

-Key für jedes Objekt zu tippen wird mühsam. -KeyProperty weist Buckets an,
eine bestimmte Eigenschaft Ihres Objekts zu verwenden. Hier enthält die
Eigenschaft Name den Wert "Bob", also wird der Schlüssel automatisch zu "Bob".


```powershell
$bob = @{ Name = "Bob"; Role = "user"; Score = 72 }
$bob | fill -Bucket users -KeyProperty Name
```

users · 1 objects

### 1.3 Mehrere Objekte über die Pipeline
---

Eine der Superkräfte von Buckets: mehrere Objekte auf einmal über die Pipeline. Senden Sie sie einzeln
durch die Pipeline und Buckets speichert jedes. Kombinieren Sie -KeyProperty mit Pipeline-Eingabe
für Batch-Inserts — der schnellste Weg, Daten zu laden.


```powershell
$users = @(
  @{ Name = "Carol"; Role = "manager"; Score = 88 }
  @{ Name = "Dave"; Role = "user"; Score = 61 }
)
$users | fill -Bucket users -KeyProperty Name
```

users · 2 objects

### 1.4 Expliziter -Key für unabhängige Benennung
---

Was, wenn Sie einen Schlüssel benötigen, der keine Eigenschaft des Objekts ist? Dafür gibt es
den -Key-Parameter — Sie bestimmen den Schlüssel, unabhängig von den Daten im Objekt.


```powershell
$data = @{ Source = "import"; Items = 42 }
$data | fill -Bucket users -Key "external-ref"
```

users · 1 objects

### 1.5 JSON-Ausgabe mit -AsJson
---

Der JSON-Modus ist für menschenlesbare Dateien gedacht — Konfigurationen, Einstellungen, alles,
was Sie von Hand bearbeiten möchten. Mit -AsJson speichert Buckets eine .json-Datei statt .dat.
Sie können sie in jedem Texteditor öffnen.


```powershell
$config = @{ Host = "localhost"; Port = 5432 }
$config | fill -Bucket config -Key "app-config" -AsJson
```

config · 1 objects

### 1.6 Zeitstempel-Schlüssel mit -AsTimestamp
---

Für Logs, Metriken oder Zeitreihendaten erzeugt -AsTimestamp automatisch einen eindeutigen Schlüssel
aus dem aktuellen Datum und der Uhrzeit. Keine zwei Objekte erhalten denselben Namen, und die
chronologische Reihenfolge ist integriert.


```powershell
$events = @(
  @{ Event = "login"; User = "alice" }
  @{ Event = "logout"; User = "bob" }
)
$events | fill -Bucket events -AsTimestamp
```

events · 2 objects

### 1.7 überschreiben verhindern mit -Overwrite
---

Bereits ein Objekt mit demselben Schlüssel vorhanden? Ohne -Overwrite überspringt Buckets es stillschweigend.
Mit -Overwrite ersetzen Sie das vorhandene Objekt durch das neue.


```powershell
$alice = @{ Name = "Alice"; Role = "admin"; Score = 99 }
New-BucketObject -InputObject $alice -Bucket users -Key "Alice" -Overwrite
```

users · 1 objects

### 1.8 Kompression mit -Compress
---

Wiederholende Daten — Logs, Heartbeats, Sensorwerte — lassen sich extrem gut komprimieren. Das
-Compress-Flag wendet GZip vor dem Schreiben an, und Buckets erkennt komprimierte Dateien
beim Lesen automatisch, sodass Sie sich nie darum kümmern müssen.


```powershell
$logs = 1..30 | ForEach-Object { @{ Seq = $_; Msg = "Heartbeat OK" } }
fill -Bucket logs -InputObject $logs -Compress
```

logs · 30 objects · compressed

## 1b. Erstellen — leise, ausführlich und Randfälle
---

### 1b.1 Leise und ausführliche Ausgabe
---

Standardmäßig zeigt fill eine Fortschrittsanzeige und eine Zusammenfassung beim Speichern. Wenn Sie
Skripte schreiben oder Stille wünschen, unterdrückt -Quiet jegliche Ausgabe. Zum Debuggen gibt
-Verbose Details pro Objekt aus.


```powershell
$data = @{ Msg = "test" }
$data | fill -Bucket demo -Key "verbosity-demo" -Quiet
```


### 1b.2 PSCustomObject vs. Hashtable
---

Sowohl Hashtables als auch PSCustomObject funktionieren mit Buckets. Der Unterschied: PSCustomObject
bewahrt die Reihenfolge Ihrer Eigenschaften, während eine normale Hashtable keine Reihenfolge garantiert.


```powershell
$custom = [PSCustomObject]@{ Type = "PSCustomObject"; Ordered = $true }
$custom | fill -Bucket types -Key "custom"
$hash = @{ Type = "Hashtable" }
$hash | fill -Bucket types -Key "hash"
```

types · 1 objects
types · 1 objects

### 1b.3 Tief verschachtelte Objekte
---

Buckets verarbeitet tief verschachtelte Objekte mühelos. Der binäre Serialisierer bewahrt den
vollständigen Objektgraphen — verschachtelte PSCustomObjects, Arrays und alles. Genau hier
würde JSON an seine Grenzen stoßen.


```powershell
$nested = [PSCustomObject]@{
  Id = "deep"
  Metadata = [PSCustomObject]@{ App = "test"; Version = "1.0" }
  Items = @(
      [PSCustomObject]@{ Sku = "ABC"; Qty = 5 }
      [PSCustomObject]@{ Sku = "XYZ"; Qty = 3 }
  )
}
$nested | fill -Bucket nested -Key "deep"
```

nested · 1 objects

### 1b.4 Sonderzeichen in Schlüsseln
---

Manche Zeichen — wie /, :, *, ? — sind in Dateinamen nicht erlaubt. Wenn Sie sie in einem
Schlüssel verwenden, ersetzt Buckets sie automatisch durch Unterstriche, damit das Dateisystem zufrieden ist.


```powershell
$data = @{ Data = "sanitized key" }
$data | fill -Bucket special -Key "my/file:name*test"
```

special · 1 objects

### 1b.5 Leere Schlüssel nach Bereinigung
---

Schlüssel, die nach Bereinigung nur aus Unterstrichen bestehen (wie Punkte oder Sonderzeichen), werden
stillschweigend übersprungen. Verwenden Sie -Verbose, um die Erklärung des Moduls zu sehen.


```powershell
@{ X = 1 } | fill -Bucket demo -Key "..." -Quiet -Verbose
@{ X = 1 } | fill -Bucket demo -Key ". ." -Quiet -Verbose
```


## 2. Lesen — spill / Get-BucketObject
---

### 2.1 Alle Objekte anzeigen (spill)
---

Das Gegenstück zu fill ist spill (Kurzform von Get-BucketObject). Ohne Argumente
gibt es jedes Objekt aus jedem Bucket zurück — nützlich, um sich einen überblick zu verschaffen.


```powershell
spill
```

```

Port Host
---- ----
5432 localhost
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   
   

```

### 2.2 Nach Bucket filtern
---

Meistens möchten Sie Objekte aus einem bestimmten Bucket. Mit -Bucket schränken Sie
die Suche auf einen einzelnen Bucket ein.


```powershell
spill -Bucket team
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 72
Role   : Designer
Skills : {Figma, CSS, HTML}
Joined : 11.11.2025 19:14:01
Level  : 2
Name   : Bob
Active : True

Score  : 88
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 2.3 Bucket-Suche mit Positionsparameter
---

Das erste Positionsargument ist der Bucket-Name. Ohne -Key werden
alle Objekte aus diesem Bucket abgerufen.


```powershell
spill team
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 72
Role   : Designer
Skills : {Figma, CSS, HTML}
Joined : 11.11.2025 19:14:01
Level  : 2
Name   : Bob
Active : True

Score  : 88
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 2.4 Schlüsselsuche nach Name
---

übergeben Sie einen Schlüssel als zweites Positionsargument (oder mit -Key). Schlüssel werden
standardmäßig ohne Berücksichtigung der Groß-/Kleinschreibung und als Präfixe gefunden.


```powershell
spill team "Alice"
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True
```

### 2.5 Exakte Schlüsselsuche
---

Geben Sie den exakten vollständigen Schlüsselnamen an, um genau dieses eine Objekt abzurufen.


```powershell
spill team -Key "Frank"
```

```

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 2.6 Groß-/Kleinschreibung ignorieren
---

Groß-/Kleinschreibung spielt keine Rolle. "alice" findet "Alice", weil die Schlüsselsuche
ohne Berücksichtigung der Groß-/Kleinschreibung erfolgt. Kein Raten mehr.


```powershell
spill team -Key "alice"
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True
```

### 2.7 Fehlende Schlüssel behandeln
---

Was passiert bei fehlender übereinstimmung? Buckets gibt nichts zurück, mit einer Warnung —
kein Absturz, nur ein hilfreicher Hinweis, dass nichts gefunden wurde.


```powershell
spill -Bucket team -Key "Zoe"
```


### 2.8 Platzhalter in Bucket-Namen
---

Auch in Bucket-Namen können Sie Platzhalter verwenden. "t*" findet jeden Bucket, der mit
"t" beginnt — praktisch für die Suche in Gruppen verwandter Buckets.


```powershell
spill -Bucket "t*"
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 72
Role   : Designer
Skills : {Figma, CSS, HTML}
Joined : 11.11.2025 19:14:01
Level  : 2
Name   : Bob
Active : True

Score  : 88
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True

Type    : PSCustomObject
Ordered : True

Type : Hashtable
```

### 2.9 Mehrere Buckets abfragen
---

übergeben Sie mehrere Bucket-Namen als Array. Buckets durchsucht jeden und kombiniert
die Ergebnisse in einer einzigen Liste.


```powershell
spill -Bucket "team", "staff"
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 72
Role   : Designer
Skills : {Figma, CSS, HTML}
Joined : 11.11.2025 19:14:01
Level  : 2
Name   : Bob
Active : True

Score  : 88
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 72
Role   : Designer
Skills : {Figma, CSS, HTML}
Joined : 11.11.2025 19:14:01
Level  : 2
Name   : Bob
Active : True

Score  : 88
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 2.10 Metadaten-Eigenschaften
---

Jedes von Buckets abgerufene Objekt enthält Metadaten: _BucketName, _BucketKey und
_BucketFile. Sie zeigen genau, woher das Objekt stammt — nützlich für
Pipeline-Operationen, bei denen der Kontext wichtig ist.


```powershell
spill -Bucket team -Key "Bob" | Select _BucketName, _BucketKey, _BucketFile
```

```

_BucketName _BucketKey _BucketFile
----------- ---------- -----------
team        Bob        C:\Users\berfelde\.buckets\team\Bob.dat
```

### 2.11 An Select-Object übergeben
---

Da spill normale PowerShell-Objekte zurückgibt, können Sie sie an Select-Object,
Sort-Object, Group-Object übergeben — alles, was Sie mit jedem anderen PowerShell-Objekt tun würden.


```powershell
spill -Bucket team | Sort Score -Descending | Select Name, Role, Score
```

```

Name  Role      Score
----  ----      -----
Alice Developer    95
Frank Developer    91
Carol PM           88
Bob   Designer     72
```

### 2.12 Zugriff mit Punktnotation
---

Greifen Sie mit der Standard-Punktnotation auf einzelne Eigenschaften zu. Speichern Sie das Ergebnis in einer
Variablen und arbeiten Sie damit wie mit jedem anderen PowerShell-Objekt.


```powershell
$dev = spill -Bucket team -Key "Frank"
$dev.Name
$dev.Role
$dev.Level
$dev.Score
```


## 2a. Lesen — filtern mit -Match
---

### 2a.1 Exakte übereinstimmung
---

-Match ist Buckets eigener Filter für exakte Gleichheit. übergeben Sie eine Hashtable mit Eigenschaftsnamen
und -werten, und Buckets gibt nur Objekte zurück, bei denen alle Eigenschaften exakt übereinstimmen.


```powershell
spill -Bucket team -Match @{ Role = "Developer" }
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 2a.2 Null-Werte abgleichen
---

Sonderfall: Abgleich mit . Wenn eine Eigenschaft  ist oder gar nicht existiert,
gilt sie als übereinstimmung für . Nützlich zum Auffinden von Objekten mit fehlenden Feldern.


```powershell
spill -Bucket team -Match @{ Deleted = $null }
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 72
Role   : Designer
Skills : {Figma, CSS, HTML}
Joined : 11.11.2025 19:14:01
Level  : 2
Name   : Bob
Active : True

Score  : 88
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 2a.3 Mehrere Eigenschaften abgleichen
---

Sie können mehrere Eigenschaften gleichzeitig abgleichen — wie UND-Logik. Alle Bedingungen
müssen zutreffen, damit ein Objekt zurückgegeben wird.


```powershell
spill -Bucket team -Match @{ Level = 3; Active = $true }
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 88
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True
```

### 2a.4 Gemischte Typen abgleichen
---

Erstellen wir frische Daten, um -Match mit gemischten Typen zu demonstrieren. Zeichenketten, Zahlen
und Boolesche Werte funktionieren alle als Vergleichskriterien.


```powershell
$data = @(
  @{ Name = "A"; Count = 5; Active = $true }
  @{ Name = "B"; Count = 10; Active = $false }
  @{ Name = "C"; Count = 5; Active = $true }
)
New-BucketObject -InputObject $data -Bucket match-demo -KeyProperty Name
spill -Bucket match-demo -Match @{ Count = 5; Active = $true }
```

```

Active Count Name
------ ----- ----
True     5 A
True     5 C
```

### 2a.5 Groß-/Kleinschreibung bei Zeichenketten
---

Der Zeichenkettenabgleich mit -Match ist exakt und ignoriert die Groß-/Kleinschreibung. "red" findet "red",
aber auch "Red", "RED" und so weiter.


```powershell
$items = @(
  @{ Name = "alpha"; Color = "red" }
  @{ Name = "beta"; Color = "blue" }
  @{ Name = "gamma"; Color = "red" }
)
$items | fill -Bucket match-demo -KeyProperty Name
spill -Bucket match-demo -Match @{ Color = "red" }
```

```

Name  Color
----  -----
alpha red
gamma red
```

### 2a.6 Nur oberste Eigenschaften
---

-Match betrachtet nur Eigenschaften der obersten Ebene. Wenn Sie in verschachtelte Daten wie
.Settings.Enabled eintauchen müssen, verwenden Sie stattdessen -Filter.


```powershell
$data = @{ Id = "a"; Meta = @{ Name = "inner" } }
$data | fill -Bucket nested-match -KeyProperty Id
spill -Bucket nested-match -Match @{ Meta = $null }
```


## 2b. Lesen — vergleichen mit -Filter
---

### 2b.1 Filtern mit Scriptblock
---

Für alles über die exakte Gleichheit hinaus greifen Sie zu -Filter. Er akzeptiert einen Scriptblock, in dem
 jedes Objekt repräsentiert. Sie können jeden PowerShell-Operator verwenden: -gt, -lt, -match,
-like, -and, -or und mehr.


```powershell
spill -Bucket team -Filter { $_.Score -gt 80 }
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 88
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 2b.2 Kleiner-oder-gleich-Vergleich
---

Kleiner oder gleich funktioniert genauso. Stellen Sie sich -Filter wie eine Where-Object-Klausel vor,
die innerhalb von Buckets statt in der Pipeline ausgeführt wird.


```powershell
spill -Bucket team -Filter { $_.Score -le 90 }
```

```

Score  : 72
Role   : Designer
Skills : {Figma, CSS, HTML}
Joined : 11.11.2025 19:14:01
Level  : 2
Name   : Bob
Active : True

Score  : 88
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True
```

### 2b.3 Regex-Mustervergleich
---

Der Mustervergleich mit -match verwendet reguläre Ausdrücke. Hier finden wir Namen, die mit
A oder E beginnen, mit dem Regex "^[AE]".


```powershell
spill -Bucket team -Filter { $_.Name -match "^[AE]" }
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True
```

### 2b.4 Platzhaltersuche mit -like
---

Der -like-Operator verwendet Platzhaltermuster. "*e*" findet jeden Namen, der den
Buchstaben "e" an beliebiger Stelle enthält.


```powershell
spill -Bucket team -Filter { $_.Name -like "*e*" }
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True
```

### 2b.5 Bedingungen mit -and kombinieren
---

Kombinieren Sie Bedingungen mit -and. Beide müssen zutreffen: Punktzahl über 80 UND Rolle ist
"Developer".


```powershell
spill -Bucket team -Filter { $_.Score -gt 80 -and $_.Role -eq "Developer" }
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 2b.6 Bedingungen mit -or kombinieren
---

Kombinieren Sie Bedingungen mit -or. Eine muss zutreffen: Rolle ist "Designer" ODER Level über 3.


```powershell
spill -Bucket team -Filter { $_.Role -eq "Designer" -or $_.Level -gt 3 }
```

```

Score  : 72
Role   : Designer
Skills : {Figma, CSS, HTML}
Joined : 11.11.2025 19:14:01
Level  : 2
Name   : Bob
Active : True

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 2b.7 Zeichenkettenlängen prüfen
---

Längenprüfungen funktionieren, weil Sie echte PowerShell-Ausdrücke schreiben. Hier
finden wir Objekte, deren Value-Eigenschaft länger als 5 Zeichen ist.


```powershell
$items = @(
  @{ Name = "short"; Value = "abc" }
  @{ Name = "long";  Value = "abcdefghijk" }
)
$items | fill -Bucket str-test -KeyProperty Name
spill -Bucket str-test -Filter { $_.Value.Length -gt 5 }
```

```

Name Value
---- -----
long abcdefghijk
```

### 2b.8 Datumsvergleiche
---

Auch Datumsvergleiche — keine spezielle Syntax nötig. Vergleichen Sie DateTime-Eigenschaften mit
-gt, -lt oder jedem anderen Operator, genau wie in normalem PowerShell.


```powershell
$cutoff = (Get-Date).AddDays(-100)
spill -Bucket team -Filter { $_.Joined -gt $cutoff }
```

```

Score  : 88
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True
```

### 2b.9 Zugriff auf verschachtelte Eigenschaften
---

Verschachtelte Eigenschaften sind über die Standard-Punktnotation im Scriptblock zugänglich.
Hier prüfen wir, ob eine Array-Eigenschaft einen Wert mit -contains enthält.


```powershell
spill -Bucket team -Filter { $_.Skills -contains "Rust" }
```

```

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 2b.10 Bucket-übergreifendes Filtern
---

Ohne -Bucket wird -Filter gegen alle Buckets gleichzeitig ausgeführt. Dies ist eine
bucket-übergreifende Abfrage — nützlich, um Objekte überall in Ihren Daten zu finden.


```powershell
@{ Name = "HighScore"; Score = 90 } | fill -Bucket config -Key "app-config"
spill -Filter { $_.Score -gt 80 }
```

```

Name      Score
----      -----
HighScore    90
Alice        95
Carol        88
Frank        91
Alice        95
Carol        88
Frank        91
Alice        99
Carol        88
```

## 2c. Lesen — Seitenwechsel mit -First / -Skip
---

### 2c.1 Ergebnisse begrenzen mit -First
---

Seitenwechsel ist integriert. -First begrenzt die Anzahl der zurückgegebenen Ergebnisse. Nützlich
für die Vorschau großer Datensätze, ohne alles zu laden.


```powershell
spill -Bucket team -First 3
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 72
Role   : Designer
Skills : {Figma, CSS, HTML}
Joined : 11.11.2025 19:14:01
Level  : 2
Name   : Bob
Active : True

Score  : 88
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True
```

### 2c.2 Ergebnisse überspringen mit -Skip
---

Kombinieren Sie -Skip mit -First, um vorzuspringen. -Skip 1 -First 3 überspringt das erste Ergebnis und
gibt die nächsten drei zurück — ein klassisches Seitenwechselmuster.


```powershell
spill -Bucket team -Skip 1 -First 3
```

```

Score  : 72
Role   : Designer
Skills : {Figma, CSS, HTML}
Joined : 11.11.2025 19:14:01
Level  : 2
Name   : Bob
Active : True

Score  : 88
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 2c.3 Filtern mit Seitenwechsel
---

-First und -Skip arbeiten auch mit -Filter zusammen. Hier filtern wir nach Punktzahlen über 70
und nehmen nur die ersten 3 Ergebnisse.


```powershell
spill -Bucket team -Filter { $_.Score -gt 70 } -First 3
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 72
Role   : Designer
Skills : {Figma, CSS, HTML}
Joined : 11.11.2025 19:14:01
Level  : 2
Name   : Bob
Active : True

Score  : 88
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True
```

## 3. Aktualisieren — Set-BucketObject
---

### 3.1 Aktualisierung über die Pipeline
---

Set-BucketObject aktualisiert ein vorhandenes Objekt direkt. Wenn es von spill über die Pipeline kommt,
erkennt es Bucket und Schlüssel automatisch aus den Metadaten _BucketName und _BucketKey —
kein erneutes Angeben nötig.


```powershell
spill -Bucket team -Key "Bob" | ForEach-Object {
  $_.Score = 99
  $_.Role = "Lead"
  $_
} | Set-BucketObject -Quiet
```


### 3.2 Expliziter Bucket und Schlüssel
---

Ohne Pipeline-Metadaten geben Sie -Bucket und -Key explizit an. übergeben Sie das modifizierte
Objekt über -InputObject.


```powershell
$obj = spill -Bucket team -Key "Carol"
$obj.Score = 100
Set-BucketObject -Bucket team -Key "Carol" -InputObject $obj -Quiet
```


### 3.3 Teilaktualisierung mit Hashtable
---

Nur ein Feld aktualisieren? übergeben Sie eine Hashtable mit nur den Eigenschaften, die Sie
ändern möchten. Buckets führt sie mit dem vorhandenen Objekt zusammen — Teilaktualisierungen
funktionieren nahtlos.


```powershell
$patch = @{ Email = "alice@contoso.com" }
$patch | Set-BucketObject -Bucket team -Key "Alice" -Quiet
```


### 3.4 Neue Eigenschaften hinzufügen
---

Neue Eigenschaften werden automatisch hinzugefügt. Wenn die Eigenschaft im Originalobjekt nicht
existiert, wird sie angehängt, ohne vorhandene Felder zu beeinträchtigen.


```powershell
$patch = @{ Phone = "555-0100" }
$patch | Set-BucketObject -Bucket team -Key "Alice" -Quiet
```


### 3.5 Unveränderte Eigenschaften bewahren
---

Eigenschaften, die Sie in der Aktualisierung nicht erwähnen, bleiben unberührt. Nur die Schlüssel in Ihrer
Patch-Hashtable werden geändert.


```powershell
$patch = @{ City = "Portland" }
$patch | Set-BucketObject -Bucket team -Key "Alice" -Quiet
```


### 3.6 Formaterhaltung
---

Formaterhaltung: JSON-Objekte bleiben .json, binäre Objekte bleiben .dat.
Set-BucketObject schreibt immer im Originalformat zurück.


```powershell
$config = @{ Host = "localhost"; Port = 5432 }
$config | fill -Bucket config -Key "db-settings" -AsJson
$patch = @{ UpdatedAt = Get-Date; Host = "prod-server" }
$patch | Set-BucketObject -Bucket config -Key "db-settings" -Quiet
```


### 3.7 Warnung bei fehlenden Metadaten
---

Was passiert, wenn Sie ohne Metadaten UND ohne explizite -Bucket/-Key an Set-BucketObject übergeben?
Es gibt einen Fehler aus — es weiß nicht, wohin es speichern soll.


```powershell
try { @{ X = 1 } | Set-BucketObject -Quiet -ErrorAction Stop }
catch { Write-Host "    Fehler: -Bucket und -Key erforderlich" -ForegroundColor Green }
```

  Fehler: -Bucket und -Key erforderlich

## 4. Löschen — Remove-BucketObject
---

### 4.1 Vorschau mit -WhatIf
---

-WhatIf zeigt eine Vorschau dessen, was gelöscht würde, ohne tatsächlich etwas zu entfernen.
Immer sicher, es vor dem Löschen auszuprobieren.


```powershell
Remove-BucketObject -Bucket team -Key "Bob" -WhatIf
```


### 4.2 Nach Schlüssel löschen
---

Das Löschen nach Schlüssel ist einfach. Geben Sie den Schlüssel des Objekts an, das Sie entfernen möchten.


```powershell
Remove-BucketObject -Bucket team -Key "Bob" -Quiet
spill -Bucket team
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True
Email  : alice@contoso.com
Phone  : 555-0100
City   : Portland

Score  : 100
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 4.3 Nicht existenten Schlüssel löschen
---

Der Versuch, einen nicht existierenden Schlüssel zu löschen, gibt eine Warnung aus, aber keinen Fehler.
Buckets ist nachsichtig bei fehlenden Objekten.


```powershell
Remove-BucketObject -Bucket team -Key "Zoe"
```


### 4.4 Schlüssel-oder-alle-Erfordernis
---

Sie müssen entweder -Key, -All oder einen Filter angeben. Ohne eines davon lehnt die
Parametersatzvalidierung den Befehl ab.


```powershell
Remove-BucketObject -Bucket team -ErrorAction SilentlyContinue
```


### 4.5 Löschen mit -Match
---

-Match funktioniert auch beim Löschen. Löschen Sie alle Objekte, die bestimmte Kriterien erfüllen,
mit einem Befehl.


```powershell
Remove-BucketObject -Bucket team -Match @{ Role = "QA" } -Quiet
spill -Bucket team
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True
Email  : alice@contoso.com
Phone  : 555-0100
City   : Portland

Score  : 72
Role   : Designer
Skills : {Figma, CSS, HTML}
Joined : 11.11.2025 19:14:01
Level  : 2
Name   : Bob
Active : True

Score  : 100
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 4.6 Löschen mit -Filter
---

-Filter funktioniert genauso — löschen Sie Objekte, die die Scriptblock-Bedingung erfüllen.
Hier wird jedes inaktive Mitglied entfernt.


```powershell
Remove-BucketObject -Bucket team -Filter { $_.Active -eq $false } -Quiet
spill -Bucket team
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True
Email  : alice@contoso.com
Phone  : 555-0100
City   : Portland

Score  : 72
Role   : Designer
Skills : {Figma, CSS, HTML}
Joined : 11.11.2025 19:14:01
Level  : 2
Name   : Bob
Active : True

Score  : 100
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True

Score  : 91
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 4.7 Alles löschen mit -All
---

-All löscht jedes Objekt im Bucket. Eine saubere Ausgangslage.


```powershell
Remove-BucketObject -Bucket team -All -Quiet
spill -Bucket team
```


### 4.8 Passthru-Metadaten
---

-PassThru gibt Metadaten über das Gelöschte zurück. Nützlich für Protokollierung, Prüfung
oder Bestätigungsmeldungen.


```powershell
$tmp = @{ Data = "gone" }
$tmp | fill -Bucket temp -Key "bye-bye" -Quiet
Remove-BucketObject -Bucket temp -Key "bye-bye" -PassThru -Quiet
```

```

Bucket Key
------ ---
temp   bye-bye.dat
```

## 5. Objektoperationen — Kopieren, Umbenennen, Verschieben
---

### 5.1 Innerhalb eines Buckets kopieren
---

Kopieren Sie ein Objekt im selben Bucket mit einem anderen Schlüssel. Das Original bleibt
unberührt — dies ist eine echte Kopie, keine Verschiebung.


```powershell
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "Alice-Backup" -Quiet
spill -Bucket team -Key "Alice-Backup"
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True
```

### 5.2 Bucket-übergreifend kopieren
---

Kopieren Sie auch bucket-übergreifend. Geben Sie -DestinationBucket an, um in einen anderen Bucket zu kopieren.


```powershell
Copy-BucketObject -Bucket team -Key "Alice" -DestinationBucket archive -Quiet
spill -Bucket archive -Key "Alice"
```

```

Score  : 95
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True
```

### 5.3 Kopieren mit Passthru
---

-PassThru bei Copy-BucketObject gibt Metadaten zum Ziel zurück: Quelle, Ziel und neuen Schlüssel —
nützlich für die Pipeline-Protokollierung.


```powershell
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "Alice-pass" -PassThru -Quiet
Remove-BucketObject -Bucket team -Key "Alice-pass" -Quiet
```

```

SourceBucket SourceKey DestinationBucket DestinationKey
------------ --------- ----------------- --------------
team         Alice     team              Alice-pass
```

### 5.4 Ein Objekt umbenennen
---

Rename ändert den Schlüssel eines vorhandenen Objekts direkt. Das Format (binär oder JSON)
bleibt beim Umbenennen erhalten.


```powershell
$tmp = @{ Data = "rename me" }
$tmp | fill -Bucket tmp -Key "old-name" -Quiet
Rename-BucketObject -Bucket tmp -Key "old-name" -NewKey "new-name" -Quiet
```


### 5.5 Umbenennen erhält Format
---

Das Umbenennen eines JSON-Objekts erhält auch die .json-Erweiterung. Das Format wird immer
beibehalten — Sie müssen sich nie darum kümmern.


```powershell
$tmp = @{ Format = "json" }
$tmp | fill -Bucket tmp-json -Key "json-old" -AsJson -Quiet
Rename-BucketObject -Bucket tmp-json -Key "json-old" -NewKey "json-new" -PassThru -Quiet
```

```

Bucket   OldKey   NewKey
------   ------   ------
tmp-json json-old json-new
```

### 5.6 Zwischen Buckets verschieben
---

Move kombiniert Kopieren + Löschen in einem Vorgang. Das Objekt wird an das Ziel kopiert
und von der Quelle entfernt.


```powershell
$data = @(
  @{ Id = "obj1"; Value = "move me" }
)
$data | fill -Bucket source -KeyProperty Id -Quiet
Move-BucketObject -Bucket source -Key "obj1" -DestinationBucket dest -Quiet
```


### 5.7 Verschieben mit Umbenennung
---

Verschieben mit Umbenennung: Geben Sie einen anderen Schlüssel im Ziel-Bucket an, um
als Teil der Verschiebung umzubenennen.


```powershell
$tmp = @{ Data = "moved+renamed" }
$tmp | fill -Bucket origin -Key "orig-key" -Quiet
Move-BucketObject -Bucket origin -Key "orig-key" -DestinationBucket final -DestinationKey "new-key" -Quiet
```


### 5.8 Verschieben mit Passthru
---

-PassThru bei Move gibt Metadaten sowohl zum Quell- als auch zum Zielobjekt zurück.


```powershell
$tmp = @{ X = 1 }
$tmp | fill -Bucket move-src -Key "m-pass" -Quiet
Move-BucketObject -Bucket move-src -Key "m-pass" -DestinationBucket move-dst -PassThru -Quiet
```

```

SourceBucket SourceKey DestinationBucket DestinationKey
------------ --------- ----------------- --------------
move-src     m-pass    move-dst          m-pass
```

### 5.9 Passthru bei allen Operationen
---

Alle drei Operationen — Copy, Rename, Move — unterstützen -PassThru. Verketten Sie sie
für nachvollziehbares Objektmanagement.


```powershell
$tmp = @{ X = 1 }
$tmp | fill -Bucket pass -Key "src-key" -Quiet
Copy-BucketObject -Bucket pass -Key "src-key" -DestinationKey "cp-key" -PassThru -Quiet
Rename-BucketObject -Bucket pass -Key "cp-key" -NewKey "rn-key" -PassThru -Quiet
Move-BucketObject -Bucket pass -Key "src-key" -DestinationBucket pass -DestinationKey "mv-key" -PassThru -Quiet
```

```

SourceBucket SourceKey DestinationBucket DestinationKey
------------ --------- ----------------- --------------
pass         src-key   pass              cp-key
```
```

Bucket OldKey NewKey
------ ------ ------
pass   cp-key rn-key
```
```

SourceBucket SourceKey DestinationBucket DestinationKey
------------ --------- ----------------- --------------
pass         src-key   pass              mv-key
```

## 6. Bucket-Verwaltung — dip / Get-Bucket
---

### 6.1 Buckets mit dip auflisten
---

dip (Kurzform von Get-Bucket) listet alle Ihre Buckets mit Objektzahlen und Zeitstempeln auf.
Es ist der erste Befehl, wenn Sie eine übersicht möchten.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
dip
```

```

Name         ObjectCount HasSubBuckets
----         ----------- -------------
archive                1         False
config                 3         False
demo                   2         False
dest                   1         False
events                 2         False
final                  1         False
logs                  30         False
match-demo             6         False
move-dst               1         False
move-src               0         False
nested                 1         False
nested-match           1         False
origin                 0         False
pass                   2         False
source                 0         False
special                1         False
staff                  4         False
str-test               2         False
team                   5         False
temp                   0         False
tmp                    1         False
tmp-json               1         False
types                  2         False
users                  5         False
```

### 6.2 Nach Namen filtern
---

Filtern Sie Buckets nach Namen mit einer Teilübereinstimmung. "team" findet "team" und jeden
anderen Bucket mit "team" im Namen.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
dip "team"
```

```

Name ObjectCount HasSubBuckets
---- ----------- -------------
team           5         False
```

### 6.3 Bucket-Statistiken
---

Get-BucketStats zeigt detaillierte Statistiken: Objektanzahl, Gesamtgröße auf der Platte und
Erstellungs-/änderungszeitstempel für einen bestimmten Bucket.


```powershell
Get-BucketStats -Bucket team
```

```

Name         : team
Path         : C:\Users\berfelde\.buckets\team
ObjectCount  : 5
TotalSize    : 5.68 KB
OldestObject : 10.05.2026 19:14:02
NewestObject : 10.05.2026 19:14:02
```

### 6.4 Schlüssel auflisten
---

Get-BucketKeys listet jeden Schlüssel in einem Bucket auf — nur die Schlüsselnamen,
kein Deserialisierungsaufwand. Für Format, Größe, Typ und Kompression
verwenden Sie Get-BucketObjectStats.


```powershell
Get-BucketKeys -Bucket team
```

```

Bucket Key
------ ---
team   Alice-Backup
team   Alice
team   Bob
team   Carol
team   Frank
```

### 6.5 Objekt-Statistiken
---

Get-BucketObjectStats gibt detaillierte Metadaten pro Objekt zurück: Format, Typ,
Größe, letzte änderung und Kompressionsstatus.


```powershell
Get-BucketObjectStats -Bucket team
```

```

Bucket        : team
Key           : Alice-Backup
Format        : Binary
Type          : Object
Size          : 1167
LastWriteTime : 10.05.2026 19:14:02
IsCompressed  : False

Bucket        : team
Key           : Alice
Format        : Binary
Type          : Object
Size          : 1167
LastWriteTime : 10.05.2026 19:14:02
IsCompressed  : False

Bucket        : team
Key           : Bob
Format        : Binary
Type          : Object
Size          : 1159
LastWriteTime : 10.05.2026 19:14:02
IsCompressed  : False

Bucket        : team
Key           : Carol
Format        : Binary
Type          : Object
Size          : 1162
LastWriteTime : 10.05.2026 19:14:02
IsCompressed  : False

Bucket        : team
Key           : Frank
Format        : Binary
Type          : Object
Size          : 1166
LastWriteTime : 10.05.2026 19:14:02
IsCompressed  : False
```

### 6.6 Schlüssel nach Muster filtern
---

Filtern Sie Schlüssel nach Muster mit -Match. "A*" findet alle Schlüssel, die mit "A" beginnen.


```powershell
Get-BucketKeys -Bucket team -Match "A*"
```

```

Bucket Key
------ ---
team   Alice-Backup
team   Alice
```

### 6.7 Schlüssel über alle Buckets
---

Get-BucketKeys über alle Buckets mit dem Platzhalter "*" — ein vollständiges Inventar
jedes gespeicherten Objekts.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-BucketKeys -Bucket "*"
```

```

Bucket       Key
------       ---
archive      Alice
config       app-config
config       db-settings
config       app-config
demo         verbosity-demo
demo         _ _
dest         obj1
events       20260510191402004_0
events       20260510191402007_1
final        new-key
logs         0695ab4c-336e-40b8-b3d1-45596872839f
logs         0d86e17d-b96d-4b0b-9b1a-a9d8ee636a5c
logs         0e327473-9184-411b-bba4-39a2bec7c8b4
logs         17895aa8-1df5-47cf-941d-673423d685e7
logs         1d31814b-c9fe-49cb-a24d-7014c173e0d3
logs         248fd341-6562-4bd6-af58-768325e8e63a
logs         264e15d6-9d02-4be2-b820-5d91742ed98d
logs         2e3353f5-cc71-4155-86cf-26cfb448d4a2
logs         32951437-a1b4-4ee6-9ac4-c7cc6d743904
logs         35d74435-fae1-4869-82d0-982de143686f
logs         3d14d601-d80b-4f0b-ba56-cf7b63f0de8c
logs         482e33d1-8a85-4c11-b9a0-82f920db2a95
logs         4f4dc087-2ff1-4fa2-b3a7-417a5725ba3a
logs         52e0c734-31a2-4543-8dbf-85072044c88c
logs         5b2cf5fc-6657-4666-b74c-b7d911de09bb
logs         732da2ca-d906-4ed0-aa2d-817173036b83
logs         7a92119c-65a1-469e-be1c-479ef0dea627
logs         7e957ccd-3f49-4ee5-8b44-bb5943ed2142
logs         83529cd4-83b2-4e8c-9e58-536041b50cd2
logs         86b9db63-6ac0-47ac-82bc-1e75df814061
logs         8ab77542-aa73-4f8a-a1f4-e01a4b0f2fb5
logs         91195a39-4393-4516-8d64-5e7473630ed2
logs         9d870a11-9eab-479b-b7b1-86644fd6e1e0
logs         9e891093-ef24-48fa-9d91-7231848a1dc0
logs         a63fa01e-1ddf-466d-b104-58e0ef68933b
logs         b10eaa6c-1e9e-4f61-adeb-ba842dd9c7c8
logs         ddcd3e6c-b960-42c3-9088-2d12af046a1a
logs         e0e4eeb0-d5be-479a-ace3-ce3360a61836
logs         ea4ab727-ad2f-4788-91d1-1e4f6ea9b1c3
logs         f74a4eaf-0ac6-4b03-b21e-ed223c6194a2
match-demo   A
match-demo   alpha
match-demo   B
match-demo   beta
match-demo   C
match-demo   gamma
move-dst     m-pass
nested       deep
nested-match a
pass         mv-key
pass         rn-key
special      my_file_name_test
staff        Alice
staff        Bob
staff        Carol
staff        Frank
str-test     long
str-test     short
team         Alice-Backup
team         Alice
team         Bob
team         Carol
team         Frank
tmp          new-name
tmp-json     json-new
types        custom
types        hash
users        Alice
users        Bob
users        Carol
users        Dave
users        external-ref
```

### 6.8 Baumansicht
---

Der Parameter -Tree stellt Ihre Buckets als visuellen Verzeichnisbaum dar. -MaxFiles
begrenzt die Anzahl der pro Bucket angezeigten Objekte.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -MaxFiles 10
```

.buckets (72 items, 31 KB)
├── archive (1 item, 1 KB)
├── config (3 items, 541 B)
├── demo (2 items, 653 B)
├── dest (1 item, 415 B)
├── events (2 items, 831 B)
├── final (1 item, 337 B)
├── logs (30 items, 7 KB)
├── match-demo (6 items, 3 KB)
├── move-dst (1 item, 326 B)
├── nested (1 item, 1 KB)
├── nested-match (1 item, 604 B)
├── pass (2 items, 652 B)
├── special (1 item, 337 B)
├── staff (4 items, 5 KB)
├── str-test (2 items, 835 B)
├── team (5 items, 6 KB)
├── tmp (1 item, 333 B)
├── tmp-json (1 item, 20 B)
├── types (2 items, 658 B)
└── users (5 items, 2 KB)

### 6.9 Nur-Bucket-Baum
---

Ohne -Objects zeigt der Baum nur Buckets — eine saubere Strukturansicht ohne
einzelne Objekte, die die Ausgabe überladen.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree
```

.buckets (72 items, 31 KB)
├── archive (1 item, 1 KB)
├── config (3 items, 541 B)
├── demo (2 items, 653 B)
├── dest (1 item, 415 B)
├── events (2 items, 831 B)
├── final (1 item, 337 B)
├── logs (30 items, 7 KB)
├── match-demo (6 items, 3 KB)
├── move-dst (1 item, 326 B)
├── nested (1 item, 1 KB)
├── nested-match (1 item, 604 B)
├── pass (2 items, 652 B)
├── special (1 item, 337 B)
├── staff (4 items, 5 KB)
├── str-test (2 items, 835 B)
├── team (5 items, 6 KB)
├── tmp (1 item, 333 B)
├── tmp-json (1 item, 20 B)
├── types (2 items, 658 B)
└── users (5 items, 2 KB)

### 6.10 Baum mit Objekten
---

Fügen Sie -Objects hinzu, um einzelne Objekte im Baum anzuzeigen. Jedes Blattobjekt ist sichtbar.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -Objects
```

.buckets (72 items, 31 KB)
├── archive (1 item, 1 KB)
│   └── Alice
├── config (3 items, 541 B)
│   ├── app-config
│   ├── app-config
│   └── db-settings
├── demo (2 items, 653 B)
│   ├── _ _
│   └── verbosity-demo
├── dest (1 item, 415 B)
│   └── obj1
├── events (2 items, 831 B)
│   ├── 20260510191402004_0
│   └── 20260510191402007_1
├── final (1 item, 337 B)
│   └── new-key
├── logs (30 items, 7 KB)
│   ├── 0695ab4c-336e-40b8-b3d1-45596872839f
│   ├── 0d86e17d-b96d-4b0b-9b1a-a9d8ee636a5c
│   ├── 0e327473-9184-411b-bba4-39a2bec7c8b4
│   ├── 17895aa8-1df5-47cf-941d-673423d685e7
│   └── 1d31814b-c9fe-49cb-a24d-7014c173e0d3
│   └── ... 25 more
├── match-demo (6 items, 3 KB)
│   ├── A
│   ├── alpha
│   ├── B
│   ├── beta
│   └── C
│   └── ... 1 more
├── move-dst (1 item, 326 B)
│   └── m-pass
├── nested (1 item, 1 KB)
│   └── deep
├── nested-match (1 item, 604 B)
│   └── a
├── pass (2 items, 652 B)
│   ├── mv-key
│   └── rn-key
├── special (1 item, 337 B)
│   └── my_file_name_test
├── staff (4 items, 5 KB)
│   ├── Alice
│   ├── Bob
│   ├── Carol
│   └── Frank
├── str-test (2 items, 835 B)
│   ├── long
│   └── short
├── team (5 items, 6 KB)
│   ├── Alice-Backup
│   ├── Alice
│   ├── Bob
│   ├── Carol
│   └── Frank
├── tmp (1 item, 333 B)
│   └── new-name
├── tmp-json (1 item, 20 B)
│   └── json-new
├── types (2 items, 658 B)
│   ├── custom
│   └── hash
└── users (5 items, 2 KB)
  ├── Alice
  ├── Bob
  ├── Carol
  ├── Dave
  └── external-ref

### 6.11 Rohe Baumausgabe
---

Der Schalter -Raw gibt Baumobjekte als pipeline-fähige Daten statt formatiertem Text zurück.
Nützlich für die weitere Verarbeitung oder benutzerdefinierte Anzeige.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -Raw | Select-Object -First 2
```

```

Name        : .buckets
Type        : Root
Path        : 
ObjectCount : 72
SizeBytes   : 31841
Depth       : 0
Children    : {@{Name=archive; Type=Bucket; Path=archive; ObjectCount=1; SizeBytes=1167; Depth=1; Children=System.Collections.ArrayList; _BucketName=archive; _BucketKey=}, @{Name=config; Type=Bucket; Path=config; ObjectCount=3; SizeBytes=541; Depth=1; Children=System.Collections.ArrayList; _BucketName=config; _BucketKey=}, @{Name=demo; Type=Bucket; Path=demo; ObjectCount=2; SizeBytes=653; Depth=1; Children=System.Collections.ArrayList; _BucketName=demo; _BucketKey=}, @{Name=dest; Type=Bucket; Path=dest; ObjectCount=1; SizeBytes=415; Depth=1; Children=System.Collections.ArrayList; _BucketName=dest; _BucketKey=}…}
_BucketName : 
_BucketKey  :
```

### 6.12 Tiefenbegrenzter Baum
---

-Depth begrenzt, wie viele Verschachtelungsebenen der Baum durchläuft. Tiefe 1 zeigt
nur Buckets der obersten Ebene.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -Depth 1
```

.buckets (72 items, 31 KB)

### 6.13 Baum als JSON
---

Leiten Sie die rohe Baumausgabe an ConvertTo-Json für eine strukturierte JSON-Darstellung Ihrer
Bucket-Hierarchie weiter.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-Bucket -Tree -Raw | ConvertTo-Json -Depth 5 | Select-Object -First 5
```

```
{
"Name": ".buckets",
"Type": "Root",
"Path": "",
"ObjectCount": 72,
"SizeBytes": 31841,
"Depth": 0,
"Children": [
  {
    "Name": "archive",
    "Type": "Bucket",
    "Path": "archive",
    "ObjectCount": 1,
    "SizeBytes": 1167,
    "Depth": 1,
    "Children": [],
    "_BucketName": "archive",
    "_BucketKey": ""
  },
  {
    "Name": "config",
    "Type": "Bucket",
    "Path": "config",
    "ObjectCount": 3,
    "SizeBytes": 541,
    "Depth": 1,
    "Children": [],
    "_BucketName": "config",
    "_BucketKey": ""
  },
  {
    "Name": "demo",
    "Type": "Bucket",
    "Path": "demo",
    "ObjectCount": 2,
    "SizeBytes": 653,
    "Depth": 1,
    "Children": [],
    "_BucketName": "demo",
    "_BucketKey": ""
  },
  {
    "Name": "dest",
    "Type": "Bucket",
    "Path": "dest",
    "ObjectCount": 1,
    "SizeBytes": 415,
    "Depth": 1,
    "Children": [],
    "_BucketName": "dest",
    "_BucketKey": ""
  },
  {
    "Name": "events",
    "Type": "Bucket",
    "Path": "events",
    "ObjectCount": 2,
    "SizeBytes": 831,
    "Depth": 1,
    "Children": [],
    "_BucketName": "events",
    "_BucketKey": ""
  },
  {
    "Name": "final",
    "Type": "Bucket",
    "Path": "final",
    "ObjectCount": 1,
    "SizeBytes": 337,
    "Depth": 1,
    "Children": [],
    "_BucketName": "final",
    "_BucketKey": ""
  },
  {
    "Name": "logs",
    "Type": "Bucket",
    "Path": "logs",
    "ObjectCount": 30,
    "SizeBytes": 7448,
    "Depth": 1,
    "Children": [],
    "_BucketName": "logs",
    "_BucketKey": ""
  },
  {
    "Name": "match-demo",
    "Type": "Bucket",
    "Path": "match-demo",
    "ObjectCount": 6,
    "SizeBytes": 2741,
    "Depth": 1,
    "Children": [],
    "_BucketName": "match-demo",
    "_BucketKey": ""
  },
  {
    "Name": "move-dst",
    "Type": "Bucket",
    "Path": "move-dst",
    "ObjectCount": 1,
    "SizeBytes": 326,
    "Depth": 1,
    "Children": [],
    "_BucketName": "move-dst",
    "_BucketKey": ""
  },
  {
    "Name": "nested",
    "Type": "Bucket",
    "Path": "nested",
    "ObjectCount": 1,
    "SizeBytes": 1039,
    "Depth": 1,
    "Children": [],
    "_BucketName": "nested",
    "_BucketKey": ""
  },
  {
    "Name": "nested-match",
    "Type": "Bucket",
    "Path": "nested-match",
    "ObjectCount": 1,
    "SizeBytes": 604,
    "Depth": 1,
    "Children": [],
    "_BucketName": "nested-match",
    "_BucketKey": ""
  },
  {
    "Name": "pass",
    "Type": "Bucket",
    "Path": "pass",
    "ObjectCount": 2,
    "SizeBytes": 652,
    "Depth": 1,
    "Children": [],
    "_BucketName": "pass",
    "_BucketKey": ""
  },
  {
    "Name": "special",
    "Type": "Bucket",
    "Path": "special",
    "ObjectCount": 1,
    "SizeBytes": 337,
    "Depth": 1,
    "Children": [],
    "_BucketName": "special",
    "_BucketKey": ""
  },
  {
    "Name": "staff",
    "Type": "Bucket",
    "Path": "staff",
    "ObjectCount": 4,
    "SizeBytes": 4654,
    "Depth": 1,
    "Children": [],
    "_BucketName": "staff",
    "_BucketKey": ""
  },
  {
    "Name": "str-test",
    "Type": "Bucket",
    "Path": "str-test",
    "ObjectCount": 2,
    "SizeBytes": 835,
    "Depth": 1,
    "Children": [],
    "_BucketName": "str-test",
    "_BucketKey": ""
  },
  {
    "Name": "team",
    "Type": "Bucket",
    "Path": "team",
    "ObjectCount": 5,
    "SizeBytes": 5821,
    "Depth": 1,
    "Children": [],
    "_BucketName": "team",
    "_BucketKey": ""
  },
  {
    "Name": "tmp",
    "Type": "Bucket",
    "Path": "tmp",
    "ObjectCount": 1,
    "SizeBytes": 333,
    "Depth": 1,
    "Children": [],
    "_BucketName": "tmp",
    "_BucketKey": ""
  },
  {
    "Name": "tmp-json",
    "Type": "Bucket",
    "Path": "tmp-json",
    "ObjectCount": 1,
    "SizeBytes": 20,
    "Depth": 1,
    "Children": [],
    "_BucketName": "tmp-json",
    "_BucketKey": ""
  },
  {
    "Name": "types",
    "Type": "Bucket",
    "Path": "types",
    "ObjectCount": 2,
    "SizeBytes": 658,
    "Depth": 1,
    "Children": [],
    "_BucketName": "types",
    "_BucketKey": ""
  },
  {
    "Name": "users",
    "Type": "Bucket",
    "Path": "users",
    "ObjectCount": 5,
    "SizeBytes": 2429,
    "Depth": 1,
    "Children": [],
    "_BucketName": "users",
    "_BucketKey": ""
  }
],
"_BucketName": "",
"_BucketKey": ""
}
```

### 6.14 Saubere übersichtstabelle
---

Wählen Sie Name und ObjectCount von dip für eine saubere Tabelle der Buckets mit ihren
Objektanzahlen.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
dip | Select-Object Name, ObjectCount
```

```

Name         ObjectCount
----         -----------
archive                1
config                 3
demo                   2
dest                   1
events                 2
final                  1
logs                  30
match-demo             6
move-dst               1
move-src               0
nested                 1
nested-match           1
origin                 0
pass                   2
source                 0
special                1
staff                  4
str-test               2
team                   5
temp                   0
tmp                    1
tmp-json               1
types                  2
users                  5
```

## 6a. Remove-Bucket — Sicherheit und Platzhalter
---

### 6a.1 Entfernen Vorschau
---

-WhatIf zeigt eine Vorschau dessen, was entfernt würde, ohne tatsächlich etwas zu löschen.


```powershell
Remove-Bucket "team" -WhatIf
```


What if: Remove the following bucket(s)
  team (5 objects, 5.68 KB)


### 6a.2 Platzhalter-Vorschau
---

Platzhaltermuster funktionieren auch. Vorschau zum Entfernen aller Buckets, die einem Muster entsprechen.


```powershell
Remove-Bucket "t*" -WhatIf
```


What if: Remove the following bucket(s)
  team (5 objects, 5.68 KB)
  temp (0 objects, 0 KB)
  tmp (1 object, 0.33 KB)
  tmp-json (1 object, 0.02 KB)
  types (2 objects, 0.64 KB)


### 6a.3 Einzelnen Bucket entfernen
---

Entfernen Sie einen einzelnen Bucket. Stellen Sie sicher, dass er nur Bucket-Objektdateien enthält — Buckets
weigert sich, Verzeichnisse mit anderen Dateitypen zu entfernen.


```powershell
$tmp = @{ A = 1 }
$tmp | fill -Bucket temp-remove -Key "x" -Quiet
Remove-Bucket temp-remove -Force -Confirm:$false
```

temp-remove · 1 object removed

### 6a.4 Sicherheitsprüfung beim Entfernen
---

Sicherheit zuerst: Remove-Bucket prüft, ob ein Verzeichnis nur Bucket-Dateien enthält.
Wenn es unerwartete Dateitypen (wie .exe) findet, überspringt es das Verzeichnis mit einer
Warnung, anstatt es zu löschen.


```powershell
$badDir = Join-Path (Get-BucketRoot) "not-a-bucket"
$null = New-Item -ItemType Directory -Path $badDir -Force
Set-Content -Path (Join-Path $badDir "evil.exe") -Value "x" -NoNewline
Remove-Bucket "not-a-bucket" -Force -Confirm:$false -WarningAction SilentlyContinue 2>$null
Remove-Item $badDir -Recurse -Force -ErrorAction SilentlyContinue
```

not-a-bucket · contains 1 non-bucket file(s): evil.exe

## 7. Export / Import — Export-Bucket, Import-Bucket
---


### 7.1 Export nach CLIXML
---

Export speichert einen gesamten Bucket in einer Archivdatei. CLIXML (Standard) bewahrt
die .NET-Typinformationen für perfekte Round-Trip-Treue.


```powershell
Export-Bucket -Bucket team -OutputFile (Join-Path $exportDir "team.clixml") -Quiet
```


### 7.2 Export nach JSON
---

Export nach JSON für menschenlesbare Archive. Gleiche Daten, anderes Format —
nützlich, wenn Sie die Daten außerhalb von PowerShell prüfen oder teilen möchten.


```powershell
Export-Bucket -Bucket team -OutputFile (Join-Path $exportDir "team.json") -AsJson -Quiet
```


### 7.3 Platzhalter-Export
---

Platzhalter funktionieren für Batch-Exporte. Exportieren Sie mehrere Buckets, die einem Muster entsprechen,
in eine einzige Archivdatei.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Export-Bucket -Bucket "t*","config" -OutputFile (Join-Path $exportDir "multi-export.clixml") -Quiet
```


### 7.4 Import aus CLIXML
---

Import stellt aus einem CLIXML-Archiv in einem neuen Bucket wieder her. Objekte werden mit
ihren ursprünglichen Schlüsseln und Daten neu erstellt.


```powershell
Import-Bucket -Bucket restored -InputFile (Join-Path $exportDir "team.clixml") -Quiet
```


### 7.5 Import aus JSON
---

Der Import aus JSON funktioniert genauso. Die JSON-Datei wird analysiert und jedes Objekt
im angegebenen Bucket gespeichert.


```powershell
Import-Bucket -Bucket restored-json -InputFile (Join-Path $exportDir "team.json") -AsJson -Quiet
```


### 7.6 überschreiben beim Import
---

-Overwrite beim Import ersetzt vorhandene Schlüssel, anstatt sie zu überspringen. Mit
-Overwrite erzeugt ein zweiter Import keine Duplikate.


```powershell
Import-Bucket -Bucket import-over -InputFile (Join-Path $exportDir "team.clixml") -Quiet
Import-Bucket -Bucket import-over -InputFile (Join-Path $exportDir "team.clixml") -Overwrite -Quiet
```


### 7.7 JSON-Archive inspizieren
---

JSON-Archive sind Klartext. öffnen Sie sie in einem beliebigen Editor, um sie vor dem Import
zu prüfen oder zu ändern.


```powershell
Get-Content (Join-Path $exportDir "team.json") -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 5 | Select-Object -First 3
```

```
[
{
  "Score": 95,
  "Role": "Developer",
  "Skills": [
    "PowerShell",
    "C#",
    "Azure"
  ],
  "Joined": "2025-05-10T19:14:01.7772283+02:00",
  "Level": 3,
  "Name": "Alice",
  "Active": true
},
{
  "Score": 95,
  "Role": "Developer",
  "Skills": [
    "PowerShell",
    "C#",
    "Azure"
  ],
  "Joined": "2025-05-10T19:14:01.7772283+02:00",
  "Level": 3,
  "Name": "Alice",
  "Active": true
},
{
  "Score": 72,
  "Role": "Designer",
  "Skills": [
    "Figma",
    "CSS",
    "HTML"
  ],
  "Joined": "2025-11-11T19:14:01.7799107+01:00",
  "Level": 2,
  "Name": "Bob",
  "Active": true
},
{
  "Score": 88,
  "Role": "PM",
  "Skills": [
    "Agile",
    "Jira",
    "Confluence"
  ],
  "Joined": "2026-02-09T19:14:01.7800088+01:00",
  "Level": 3,
  "Name": "Carol",
  "Active": true
},
{
  "Score": 91,
  "Role": "Developer",
  "Skills": [
    "Rust",
    "Go",
    "Kubernetes"
  ],
  "Joined": "2024-12-26T19:14:01.7800708+01:00",
  "Level": 4,
  "Name": "Frank",
  "Active": true
}
]
```

## 8. PSDrive — Buckets wie ein Dateisystem durchsuchen
---

### 8.1 Das buckets:-Laufwerk
---

Buckets registriert ein benutzerdefiniertes PSDrive namens "buckets:". Sie können es mit
cd, Get-ChildItem, Get-Content durchsuchen — genau wie jedes andere Laufwerk.


```powershell
Get-PSDrive -Name buckets
```

```

Name           Used (GB)     Free (GB) Provider      Root                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        CurrentLocation
----           ---------     --------- --------      ----                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ---------------
buckets                                Buckets       buckets:\
```

### 8.2 Buckets auflisten
---

Listen Sie alle Buckets mit Get-ChildItem im Laufwerksstammverzeichnis auf. Jeder Bucket erscheint als
Container (Verzeichnis).


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-ChildItem "buckets:\"
```

```

Type  LastWriteTime             CreationTime                      Size Name
----  -------------             ------------                      ---- ----
b--   10.05.2026 19:14:03       10.05.2026 19:14:03               1 KB archive
b--   10.05.2026 19:14:02       10.05.2026 19:14:01              541 B config
b--   10.05.2026 19:14:02       10.05.2026 19:14:02              653 B demo
b--   10.05.2026 19:14:03       10.05.2026 19:14:03              415 B dest
b--   10.05.2026 19:14:02       10.05.2026 19:14:02              831 B events
b--   10.05.2026 19:14:03       10.05.2026 19:14:03              337 B final
b--   10.05.2026 19:14:04       10.05.2026 19:14:04               5 KB import-over
b--   10.05.2026 19:14:02       10.05.2026 19:14:02               7 KB logs
b--   10.05.2026 19:14:02       10.05.2026 19:14:02               3 KB match-demo
b--   10.05.2026 19:14:03       10.05.2026 19:14:03              326 B move-dst
b--   10.05.2026 19:14:03       10.05.2026 19:14:03                0 B move-src
b--   10.05.2026 19:14:02       10.05.2026 19:14:02               1 KB nested
b--   10.05.2026 19:14:02       10.05.2026 19:14:02              604 B nested-match
b--   10.05.2026 19:14:03       10.05.2026 19:14:03                0 B origin
b--   10.05.2026 19:14:03       10.05.2026 19:14:03              652 B pass
b--   10.05.2026 19:14:04       10.05.2026 19:14:04               5 KB restored
b--   10.05.2026 19:14:04       10.05.2026 19:14:04               4 KB restored-json
b--   10.05.2026 19:14:03       10.05.2026 19:14:03                0 B source
b--   10.05.2026 19:14:02       10.05.2026 19:14:02              337 B special
b--   10.05.2026 19:14:02       10.05.2026 19:14:02               5 KB staff
b--   10.05.2026 19:14:02       10.05.2026 19:14:02              835 B str-test
b--   10.05.2026 19:14:03       10.05.2026 19:14:02               6 KB team
b--   10.05.2026 19:14:02       10.05.2026 19:14:02                0 B temp
b--   10.05.2026 19:14:03       10.05.2026 19:14:03              333 B tmp
b--   10.05.2026 19:14:03       10.05.2026 19:14:03               20 B tmp-json
b--   10.05.2026 19:14:02       10.05.2026 19:14:02              658 B types
b--   10.05.2026 19:14:01       10.05.2026 19:14:01               2 KB users
```

### 8.3 Bucket-Ausgabe formatieren
---

Formatieren Sie die Ausgabe mit Select-Object für eine sauberere Tabelle mit Bucket-Namen,
Größen und Zeitstempeln.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-ChildItem "buckets:\" | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
```

```

Name          Length LastWriteTime
----          ------ -------------
archive              10.05.2026 19:14:03
config               10.05.2026 19:14:02
demo                 10.05.2026 19:14:02
dest                 10.05.2026 19:14:03
events               10.05.2026 19:14:02
final                10.05.2026 19:14:03
import-over          10.05.2026 19:14:04
logs                 10.05.2026 19:14:02
match-demo           10.05.2026 19:14:02
move-dst             10.05.2026 19:14:03
move-src             10.05.2026 19:14:03
nested               10.05.2026 19:14:02
nested-match         10.05.2026 19:14:02
origin               10.05.2026 19:14:03
pass                 10.05.2026 19:14:03
restored             10.05.2026 19:14:04
restored-json        10.05.2026 19:14:04
source               10.05.2026 19:14:03
special              10.05.2026 19:14:02
staff                10.05.2026 19:14:02
str-test             10.05.2026 19:14:02
team                 10.05.2026 19:14:03
temp                 10.05.2026 19:14:02
tmp                  10.05.2026 19:14:03
tmp-json             10.05.2026 19:14:03
types                10.05.2026 19:14:02
users                10.05.2026 19:14:01
```

### 8.4 Objekte in einem Bucket durchsuchen
---

Betreten Sie einen Bucket und listen Sie seine Objekte auf. Jedes gespeicherte Objekt erscheint als Datei
im PSDrive.


```powershell
Get-ChildItem "buckets:\team" | Select-Object Name, Length, LastWriteTime
```

```

Name         Length LastWriteTime
----         ------ -------------
Alice-Backup        10.05.2026 19:14:02
Alice               10.05.2026 19:14:02
Bob                 10.05.2026 19:14:02
Carol               10.05.2026 19:14:02
Frank               10.05.2026 19:14:02
```

### 8.5 Container filtern
---

Filtern Sie mit PSIsContainer, um nur Buckets (Container) oder nur Blattobjekte zu sehen.


```powershell
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson
Get-ChildItem "buckets:\" | Where-Object { $_.PSIsContainer }
```

```

Type  LastWriteTime             CreationTime                      Size Name
----  -------------             ------------                      ---- ----
b--   10.05.2026 19:14:03       10.05.2026 19:14:03               1 KB archive
b--   10.05.2026 19:14:02       10.05.2026 19:14:01              541 B config
b--   10.05.2026 19:14:02       10.05.2026 19:14:02              653 B demo
b--   10.05.2026 19:14:03       10.05.2026 19:14:03              415 B dest
b--   10.05.2026 19:14:02       10.05.2026 19:14:02              831 B events
b--   10.05.2026 19:14:03       10.05.2026 19:14:03              337 B final
b--   10.05.2026 19:14:04       10.05.2026 19:14:04               5 KB import-over
b--   10.05.2026 19:14:02       10.05.2026 19:14:02               7 KB logs
b--   10.05.2026 19:14:02       10.05.2026 19:14:02               3 KB match-demo
b--   10.05.2026 19:14:03       10.05.2026 19:14:03              326 B move-dst
b--   10.05.2026 19:14:03       10.05.2026 19:14:03                0 B move-src
b--   10.05.2026 19:14:02       10.05.2026 19:14:02               1 KB nested
b--   10.05.2026 19:14:02       10.05.2026 19:14:02              604 B nested-match
b--   10.05.2026 19:14:03       10.05.2026 19:14:03                0 B origin
b--   10.05.2026 19:14:03       10.05.2026 19:14:03              652 B pass
b--   10.05.2026 19:14:04       10.05.2026 19:14:04               5 KB restored
b--   10.05.2026 19:14:04       10.05.2026 19:14:04               4 KB restored-json
b--   10.05.2026 19:14:03       10.05.2026 19:14:03                0 B source
b--   10.05.2026 19:14:02       10.05.2026 19:14:02              337 B special
b--   10.05.2026 19:14:02       10.05.2026 19:14:02               5 KB staff
b--   10.05.2026 19:14:02       10.05.2026 19:14:02              835 B str-test
b--   10.05.2026 19:14:03       10.05.2026 19:14:02               6 KB team
b--   10.05.2026 19:14:02       10.05.2026 19:14:02                0 B temp
b--   10.05.2026 19:14:03       10.05.2026 19:14:03              333 B tmp
b--   10.05.2026 19:14:03       10.05.2026 19:14:03               20 B tmp-json
b--   10.05.2026 19:14:02       10.05.2026 19:14:02              658 B types
b--   10.05.2026 19:14:01       10.05.2026 19:14:01               2 KB users
```

### 8.6 Objekte lesen
---

Lesen Sie ein Objekt mit Get-Content (oder cat). Es deserialisiert die gespeicherten Daten zurück
in ein lebendiges PowerShell-Objekt — kein manuelles Parsen nötig.


```powershell
Get-Content "buckets:\team\Alice" | Select-Object Name, Role, Score
```

```

Name  Role      Score
----  ----      -----
Alice Developer    95
```

### 8.7 Round-Trip: lesen, ändern, schreiben
---

Der vollständige Round-Trip im PSDrive: lesen mit Get-Content, Eigenschaft ändern,
zurückschreiben mit Set-Content. Funktioniert wie eine Datei, aber mit lebendigen Objekten.


```powershell
$obj = Get-Content "buckets:\team\Carol"
$obj.Score = 95
$obj | Set-Content "buckets:\team\Carol"
```


### 8.8 Objekte entfernen
---

Remove-Item funktioniert auch im PSDrive. Löschen Sie ein Objekt über seinen Pfad.


```powershell
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "psdrive-remove-test" -Quiet
Remove-Item "buckets:\team\psdrive-remove-test" -Force
```


### 8.9 Existenz prüfen
---

Test-Path prüft, ob ein Objekt im Laufwerk existiert. Nützlich für bedingte Logik.


```powershell
Test-Path "buckets:\team\Alice"
Test-Path "buckets:\team\NonExistent"
```


### 8.10 Objekte kopieren
---

Copy-Item funktioniert bucket-übergreifend im PSDrive. Kopieren Sie Objekte von einem Bucket
in einen anderen mit vertrauten Dateisystembefehlen.


```powershell
Copy-Item "buckets:\team\Alice" "buckets:\team\Alice-pscopy" -Force
Remove-BucketObject -Bucket team -Key "Alice-pscopy" -Quiet
```


### 8.11 Tab-Vervollständigung
---

Die Tab-Vervollständigung funktioniert im gesamten PSDrive. Versuchen Sie, "buckets:\" zu tippen und
Tab zu drücken — sie vervollständigt Bucket-Namen und Objektschlüssel.

## 9. Verschachtelte Buckets — Verzeichnishierarchie
---

### 9.1 Verschachtelte Buckets erstellen
---

Bucket-Namen mit Schrägstrichen erzeugen verschachtelte Verzeichnisstrukturen auf der Platte.
So organisieren Sie Daten hierarchisch — wie Ordner in Ordnern,
jede Ebene ein echtes Unterverzeichnis.


```powershell
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
```


### 9.2 Platzhalter in verschachtelten Pfaden
---

Platzhalter funktionieren in verschachtelten Pfaden. "org/eu/*/cities" findet Stadt-Buckets unter
jedem EU-Land — Deutschland, UK und so weiter.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
spill -Bucket "org/eu/*/cities"
```

```

Country Population Name
------- ---------- ----
DE         3600000 Berlin
DE         1500000 Munich
UK         8900000 London
UK          550000 Manchester
```

### 9.3 Verschachtelte Buckets direkt abfragen
---

Fragen Sie einen verschachtelten Pfad direkt mit seinem vollständigen Bucket-Namen ab. Gleicher spill-Befehl,
nur ein tieferer Pfad.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
spill -Bucket "org/eu/de/cities"
```

```

Country Population Name
------- ---------- ----
DE         3600000 Berlin
DE         1500000 Munich
```

### 9.4 Mehrstufige Platzhalter
---

Platzhalter auf mehreren Ebenen für tiefe Abfragen. "org/*/de/*" findet alles
unter dem "de"-Unterbucket jedes Landes.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
spill -Bucket "org/*/de/*"
```

```

Country Population Name
------- ---------- ----
DE         3600000 Berlin
DE         1500000 Munich
                 

```

### 9.5 Rekursive Bucket-Auflistung
---

Get-Bucket mit -Recurse zeigt die vollständige verschachtelte Struktur. Es durchläuft alle
Unter-Buckets rekursiv.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-Bucket -Name "org" -Recurse
```

```

Name             ObjectCount HasSubBuckets
----             ----------- -------------
org/eu/de/cities           2         False
org/eu/de/depts            2         False
org/eu/de                  0          True
org/eu/uk/cities           2         False
org/eu/uk                  0          True
org/eu                     0          True
org/us/cities              1         False
org/us                     0          True
org                        0          True
```

### 9.6 Baumansicht verschachtelter Buckets
---

Die Baumansicht visualisiert die Verschachtelungshierarchie. Jede Ebene ist eingerückt, sodass
die Organisationsstruktur auf einen Blick erkennbar ist.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-Bucket -Name "org" -Tree -Objects -MaxFiles 10
```

.buckets (94 items, 48 KB)
└── org (7 items, 3 KB)
  ├── eu (6 items, 3 KB)
  │   ├── de (4 items, 2 KB)
  │   │   ├── cities (2 items, 1 KB)
  │   │   │   ├── Berlin
  │   │   │   └── Munich
  │   │   └── depts (2 items, 838 B)
  │   │       ├── Engineering
  │   │       └── Marketing
  │   └── uk (2 items, 1 KB)
  │       └── cities (2 items, 1 KB)
  │           ├── London
  │           └── Manchester
  └── us (1 item, 516 B)
      └── cities (1 item, 516 B)
          └── New York

### 9.7 PSDrive mit verschachtelten Pfaden
---

PSDrive unterstützt auch verschachtelte Pfade. Navigieren Sie mit Get-ChildItem in org/eu/de/cities,
genau wie bei einem Dateisystempfad.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-ChildItem "buckets:\org\eu\de\cities" | Select-Object Name
```

```

Name
----
Berlin
Munich
```

### 9.8 Rekursive PSDrive-Auflistung
---

Rekursive Auflistung im PSDrive mit dem Flag -Recurse. Zeigt alles unter
dem org-Baum.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-ChildItem "buckets:\org" -Recurse | Select-Object Name | Format-Table -AutoSize
```

```

Name
----
eu
de
cities
Berlin
Munich
depts
Engineering
Marketing
uk
cities
London
Manchester
us
cities
New York
```

### 9.9 Statistiken zu verschachtelten Buckets
---

Statistiken funktionieren auch bei verschachtelten Buckets. Get-BucketStats verarbeitet den vollständigen Pfad.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-BucketStats -Bucket "org/eu/de/cities"
```

```

Name         : org/eu/de/cities
Path         : C:\Users\berfelde\.buckets\org\eu\de\cities
ObjectCount  : 2
TotalSize    : 1 KB
OldestObject : 10.05.2026 19:14:04
NewestObject : 10.05.2026 19:14:04
```

### 9.10 Schlüssel in verschachtelten Buckets
---

Listen Sie Schlüssel in einem verschachtelten Bucket mit Get-BucketKeys auf. Gleicher Befehl, nur ein
tieferer Bucket-Pfad.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Get-BucketKeys -Bucket "org/eu/de/cities"
```

```

Bucket           Key
------           ---
org/eu/de/cities Berlin
org/eu/de/cities Munich
```

### 9.11 Bucket-übergreifendes Filtern mit Platzhaltern
---

Kombinieren Sie Platzhalter mit -Filter für bucket-übergreifende Abfragen in verschachtelten Hierarchien.
Finden Sie alle Städte mit mehr als 2 Millionen Einwohnern in allen Ländern.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
spill -Bucket "org/*/cities" -Filter { $_.Population -gt 2000000 }
```

```

Country Population Name
------- ---------- ----
DE         3600000 Berlin
UK         8900000 London
US         8300000 New York
```

### 9.12 Verschachtelte Bäume entfernen
---

Remove-Bucket mit -Recurse löscht einen ganzen verschachtelten Baum. Ein einziger Befehl
entfernt org und alles darunter.


```powershell
@{ Name="Berlin"; Population=3600000; Country="DE" } | fill -Bucket "org/eu/de/cities" -Key "Berlin"
@{ Name="London"; Population=8900000; Country="UK" } | fill -Bucket "org/eu/uk/cities" -Key "London"
@{ Name="New York"; Population=8300000; Country="US" } | fill -Bucket "org/us/cities" -Key "New York"
Remove-Bucket "org" -Recurse -Force -Confirm:$false
```

org · 0 objects removed

## 10. Eleganter Pipeline-Einsatz
---

### 10.1 Erzeugen und speichern
---

Buckets ist für den pipeline-orientierten Einsatz konzipiert. Die meisten Cmdlets akzeptieren
Pipeline-Eingaben und geben Objekte mit Metadaten aus. So verketten Sie sie.


```powershell
1..5 | ForEach-Object { @{ Name = "item-$_"; Value = $_ * 10 } } |
  fill -Bucket "dir-listing" -KeyProperty Name -Quiet
```


### 10.2 Filtern, ändern, speichern
---

Verketten Sie mehrere Operationen in einer Pipeline: filtern mit -Filter, ändern
mit ForEach-Object und zurückspeichern mit Set-BucketObject. Alles in einem Durchlauf.


```powershell
spill -Bucket team -Filter { $_.Role -eq "Developer" } |
  ForEach-Object { $_.Score = $_.Score + 5; $_ } |
  Set-BucketObject -PassThru
```

```

Bucket Key
------ ---
team   Alice-Backup
team   Alice
team   Frank
```

### 10.3 Filtern, sortieren, projizieren
---

Filtern, sortieren und projizieren in einer Pipeline. Where-Object filtert, Sort-Object
ordnet, Select-Object wählt die gewünschten Eigenschaften aus.


```powershell
spill -Bucket team | Where-Object { $_.Score -gt 80 } |
  Sort-Object Score -Descending |
  Select-Object Name, Role, Score
```

```

Name  Role      Score
----  ----      -----
Alice Developer   100
Alice Developer   100
Frank Developer    96
Carol PM           95
```

### 10.4 Bucket-übergreifende Iteration
---

Bucket-übergreifende Abfrage: mehrere Buckets durchlaufen, jeden filtern und
die Ergebnisse mit Bucket-Metadaten projizieren.


```powershell
@{ Name = "HighScore"; Score = 90 } | fill -Bucket config -Key "app-config"
@{ Name = "DemoItem"; Score = 85 } | fill -Bucket demo -Key "demo-score"
$buckets = @("team", "config", "demo")
$buckets | ForEach-Object { spill -Bucket $_ -Filter { $_.Score -gt 80 } } |
  Select-Object _BucketName, Name, Score
```

```

_BucketName Name      Score
----------- ----      -----
team        Alice       100
team        Alice       100
team        Carol        95
team        Frank        96
config      HighScore    90
demo        DemoItem     85
```

### 10.5 Nach Bucket gruppieren
---

Gruppieren Sie nach Bucket-Namen, um zu sehen, wie Objekte auf Ihre Buckets verteilt sind.


```powershell
@{ Name = "HighScore"; Score = 90 } | fill -Bucket config -Key "app-config"
spill | Group-Object _BucketName | Select-Object Name, Count
```

```

Name          Count
----          -----
archive           1
config            3
demo              3
dest              1
dir-listing       5
events            2
final             1
import-over       5
logs             30
match-demo        6
move-dst          1
nested            1
nested-match      1
pass              2
restored          5
restored-json     5
special           1
staff             4
str-test          2
team              5
tmp               1
tmp-json          1
types             2
users             5
```

### 10.6 Nach Eigenschaft gruppieren
---

Group-Object fasst Daten innerhalb eines Buckets zusammen. Hier zählen wir, wie viele
Teammitglieder welche Rolle haben.


```powershell
spill -Bucket team | Group-Object Role | Select-Object Name, Count
```

```

Name      Count
----      -----
Designer      1
Developer     3
PM            1
```

### 10.7 Statistiken mit Measure-Object
---

Measure-Object liefert Statistiken — Durchschnitt, Minimum, Maximum — für jede
numerische Eigenschaft Ihrer Objekte.


```powershell
$scores = spill -Bucket team | Measure-Object Score -Average -Minimum -Maximum
Write-Host "    Punktestatistik: ø=$([math]::Round($scores.Average,1)) min=$($scores.Minimum) max=$($scores.Maximum)"
```

  Punktestatistik: ø=92.6 min=72 max=100

### 10.8 Export nach CSV
---

Exportieren Sie gespillte Daten als CSV für Excel, Python oder jedes Tool, das
tabellarische Daten liest.


```powershell
$csvPath = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-team.csv"
spill -Bucket team | Select-Object Name, Role, Score | Export-Csv -Path $csvPath -NoTypeInformation
Remove-Item $csvPath -Force -ErrorAction SilentlyContinue
```


### 10.9 Filter-Vergleich
---

-Filter läuft innerhalb von Buckets (schneller), Where-Object in der Pipeline (flexibler).
Beide liefern das gleiche Ergebnis — wählen Sie nach Bedarf.


```powershell
spill -Bucket team -Filter { $_.Score -gt 80 }
spill -Bucket team | Where-Object { $_.Score -gt 80 }
```

```

Score  : 100
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 100
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 95
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True

Score  : 96
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```
```

Score  : 100
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 100
Role   : Developer
Skills : {PowerShell, C#, Azure}
Joined : 10.05.2025 19:14:01
Level  : 3
Name   : Alice
Active : True

Score  : 95
Role   : PM
Skills : {Agile, Jira, Confluence}
Joined : 09.02.2026 19:14:01
Level  : 3
Name   : Carol
Active : True

Score  : 96
Role   : Developer
Skills : {Rust, Go, Kubernetes}
Joined : 26.12.2024 19:14:01
Level  : 4
Name   : Frank
Active : True
```

### 10.10 Benutzerdefinierte Formatierung
---

Benutzerdefinierte Formatierung mit ForEach-Object. Wandeln Sie jedes Objekt in einen formatierten
String für die Anzeige oder Protokollierung um.


```powershell
spill -Bucket team | ForEach-Object {
  "[$($_.Role)] $($_.Name) — Score: $($_.Score)"
}
```

```
[Developer] Alice — Score: 100
[Developer] Alice — Score: 100
[Designer] Bob — Score: 72
[PM] Carol — Score: 95
[Developer] Frank — Score: 96
```

### 10.11 Bedingte JSON-Ausgabe
---

Bedingte Pipeline: zuerst filtern, dann nur passende Objekte in JSON konvertieren.


```powershell
spill -Bucket team -Filter { $_.Score -gt 80 } | ConvertTo-Json -Depth 5
```

```
[
{
  "Score": 100,
  "Role": "Developer",
  "Skills": [
    "PowerShell",
    "C#",
    "Azure"
  ],
  "Joined": "2025-05-10T19:14:01.7772283+02:00",
  "Level": 3,
  "Name": "Alice",
  "Active": true
},
{
  "Score": 100,
  "Role": "Developer",
  "Skills": [
    "PowerShell",
    "C#",
    "Azure"
  ],
  "Joined": "2025-05-10T19:14:01.7772283+02:00",
  "Level": 3,
  "Name": "Alice",
  "Active": true
},
{
  "Score": 95,
  "Role": "PM",
  "Skills": [
    "Agile",
    "Jira",
    "Confluence"
  ],
  "Joined": "2026-02-09T19:14:01.7800088+01:00",
  "Level": 3,
  "Name": "Carol",
  "Active": true
},
{
  "Score": 96,
  "Role": "Developer",
  "Skills": [
    "Rust",
    "Go",
    "Kubernetes"
  ],
  "Joined": "2024-12-26T19:14:01.7800708+01:00",
  "Level": 4,
  "Name": "Frank",
  "Active": true
}
]
```

### 10.12 Round-Trip-Verifikation
---

Speichern Sie, lesen Sie sofort und verifizieren Sie die Round-Trip-Integrität. Was Sie schreiben,
erhalten Sie genau so zurück.


```powershell
$tmp = @{ Id = "smoke"; Value = 42 }
$tmp | fill -Bucket smoke-test -KeyProperty Id -Quiet
spill -Bucket smoke-test | Select-Object Id, Value
```

```

Id    Value
--    -----
smoke    42
```

## 11. Aliase & Shortcuts Referenz
---

Drei Aliase werden vom Modul exportiert:

  fill   = New-BucketObject     — save objects
  spill  = Get-BucketObject     — retrieve objects
  dip    = Get-Bucket            — list buckets

Zusätzliche Shortcuts:
  ls     = Get-ChildItem         — overridden globally (used in buckets: drive)
  cat    = Get-Content           — built-in, works with buckets: drive

Pipeline-Parameterbindung über Metadaten:
  _BucketName   → -Bucket   (on Set-BucketObject)
  _BucketKey    → -Key      (on Set-BucketObject)
  _BucketFile   → full path to the stored file


## 12. Sysadmin-Szenarien
---


Dieser Abschnitt vermittelt Buckets von Grund auf mit realen Daten:
Serverinventar, Vorfallprotokolle, Gesundheitsberichte und bucket-übergreifende
Korrelation. Jede Lektion baut auf der vorherigen auf, beginnend einfach und
an Komplexität zunehmend.


### 12.1 Serverinventar speichern
---

Der fill-Alias (Kurzform von New-BucketObject) speichert Objekte in benannten
Speicherbereichen namens Buckets. Hier speichern wir unser Serverinventar — jeder
Serverdatensatz wird ein Objekt, das über -KeyProperty mit seinem Hostnamen verschlüsselt wird.
Der Schalter -Quiet unterdrückt die Zusammenfassungsausgabe.


```powershell
$script:Servers | fill -Bucket servers -KeyProperty Hostname -Quiet
```


### 12.2 Fehlerhafte Server finden
---

Der spill-Alias (Kurzform von Get-BucketObject) ruft gespeicherte Objekte ab.
-Filter akzeptiert einen Scriptblock, um Bedingungen zu erfüllen — wie Where-Object.
Finden Sie Server, die nicht vollständig online sind: -ne bedeutet "ungleich".


```powershell
spill -Bucket servers -Filter { $_.Status -ne "online" }
```

```

OS       : Rocky 9
Disk     : 200
Status   : offline
Role     : app
Hostname : app-01
Location : DC2
CPU      : 8
IP       : 10.0.2.50
RAM      : 16

OS       : Debian 12
Disk     : 500
Status   : degraded
Role     : database
Hostname : db-02
Location : DC2
CPU      : 8
IP       : 10.0.2.20
RAM      : 32
```

### 12.3 Server nach Rolle und Spezifikation filtern
---

Kombinieren Sie zwei Bedingungen in einem -Filter-Scriptblock mit -and. Finden Sie
Datenbankserver mit mindestens 16 GB RAM — ideal, um Hosts für eine bestimmte
Arbeitslast zu identifizieren.


```powershell
spill -Bucket servers -Filter { $_.RAM -ge 16 -and $_.Role -eq "database" }
```

```

OS       : Debian 12
Disk     : 500
Status   : online
Role     : database
Hostname : db-01
Location : DC1
CPU      : 8
IP       : 10.0.1.20
RAM      : 32

OS       : Debian 12
Disk     : 500
Status   : degraded
Role     : database
Hostname : db-02
Location : DC2
CPU      : 8
IP       : 10.0.2.20
RAM      : 32
```

### 12.4 Server nach Rechenzentrum gruppieren
---

Group-Object ist Ihr Freund für das Rechenzentrumsinventar. Gruppieren Sie Server nach
ihrer Location-Eigenschaft, um zu sehen, wie viele Hosts in jedem RZ leben.


```powershell
spill -Bucket servers | Group-Object Location
```

```

Count Name                      Group
----- ----                      -----
  5 DC1                       {@{OS=FreeBSD 14; Disk=2000; Status=online; Role=backup; Hostname=backup-01; Location=DC1; CPU=4; IP=10.0.1.1; RAM=8}, @{OS=Alpine 3.18; Disk=60; Status=online; Role=cache; Hostname=cache-01; Location=DC1; CPU=2; IP=10.0.1.30; RAM=16}, @{OS=Debian 12; Disk=500; Status=online; Role=database; Hostname=db-01; Location=DC1; CPU=8; IP=10.0.1.20; RAM=32}, @{OS=Ubuntu 22.04; Disk=120; Status=online; Role=web; Hostname=web-01; Location=DC1; CPU=4; IP=10.0.1.10; RAM=8}…}
  3 DC2                       {@{OS=Rocky 9; Disk=200; Status=offline; Role=app; Hostname=app-01; Location=DC2; CPU=8; IP=10.0.2.50; RAM=16}, @{OS=Debian 12; Disk=500; Status=degraded; Role=database; Hostname=db-02; Location=DC2; CPU=8; IP=10.0.2.20; RAM=32}, @{OS=Ubuntu 22.04; Disk=250; Status=online; Role=monitoring; Hostname=mon-01; Location=DC2; CPU=2; IP=10.0.1.40; RAM=4}}
```

### 12.5 Kapazitätsplanung Gesamtsummen
---

Measure-Object summiert die gesamten Computeresourcen aller Server. Praktisch
für die Kapazitätsplanung — wie viel CPU, RAM und Platte haben Sie insgesamt?


```powershell
spill -Bucket servers | Measure-Object CPU, RAM, Disk -Sum
```

```

Count             : 8
Average           : 
Sum               : 40
Maximum           : 
Minimum           : 
StandardDeviation : 
Property          : CPU

Count             : 8
Average           : 
Sum               : 124
Maximum           : 
Minimum           : 
StandardDeviation : 
Property          : RAM

Count             : 8
Average           : 
Sum               : 3750
Maximum           : 
Minimum           : 
StandardDeviation : 
Property          : Disk
```

### 12.6 Vorfälle mit Zeitstempeln protokollieren
---

-AsTimestamp gibt jedem Vorfall einen eindeutigen Schlüssel basierend auf der aktuellen Zeit —
perfekt für Zeitreihen-Ereignisprotokolle, bei denen Sie niemals Schlüsselkonflikte möchten.


```powershell
$script:Incidents | fill -Bucket incidents -AsTimestamp -Quiet
```


### 12.7 Kritische Vorfälle priorisieren
---

Konzentrieren Sie sich auf das Wesentliche: ERROR- und CRIT-Schweregrade. Der -in-Operator
im -Filter-Scriptblock gleicht mehrere Werte auf einmal ab.


```powershell
spill -Bucket incidents -Filter { $_.Severity -in @("ERROR","CRIT") }
```

```

Source Message                   Timestamp           Severity
------ -------                   ---------           --------
web-01 Connection pool exhausted 10.05.2026 17:14:04 ERROR
app-01 Service unreachable       10.05.2026 18:59:04 ERROR
app-01 Disk /dev/sda1 at 97%     10.05.2026 19:09:04 CRIT
web-01 Connection pool exhausted 10.05.2026 17:14:04 ERROR
app-01 Service unreachable       10.05.2026 18:59:04 ERROR
app-01 Disk /dev/sda1 at 97%     10.05.2026 19:09:04 CRIT
```

### 12.8 Batch-Wartungsmodus
---

Set-BucketObject aktualisiert vorhandene Objekte direkt. Spillen Sie die Webserver,
fügen Sie mit Add-Member eine Maintenance-Eigenschaft hinzu (deserialisierte Objekte akzeptieren
keine Punktzuweisung), und leiten Sie sie durch Set-BucketObject, um sie zu speichern.
Die Zusammenfassung bestätigt, wie viele aktualisiert wurden.


```powershell
spill -Bucket servers -Filter { $_.Role -eq "web" } |
  ForEach-Object { $_ | Add-Member Maintenance $true -Force; $_ } |
  Set-BucketObject
```

servers · 2 updated

### 12.9 Gesundheitsbericht
---

Erstellen Sie einen schnellen Gesundheitsbericht: sortieren Sie Server nach Status, damit
offline- und degradierte Maschinen nach oben kommen. Wählen Sie nur die relevanten Felder.


```powershell
spill -Bucket servers | Select Hostname, Status, Location | Sort Status
```

```

Hostname  Status   Location
--------  ------   --------
db-02     degraded DC2
app-01    offline  DC2
backup-01 online   DC1
cache-01  online   DC1
db-01     online   DC1
mon-01    online   DC2
web-01    online   DC1
web-02    online   DC1
```

### 12.10 Bucket-übergreifende Korrelation
---

Bucket-übergreifende Abfragen verbinden zusammenhängende Daten. Spillen Sie kritische
Vorfälle aus dem incidents-Bucket und schlagen Sie dann jeden betroffenen Server
mit -Key nach. Das verbindet Ihr Ereignisprotokoll mit Ihrem Inventar in einer Pipeline.


```powershell
$crit = spill -Bucket incidents -Filter { $_.Severity -eq "CRIT" }
$crit | ForEach-Object {
  $svr = spill -Bucket servers -Key $_.Source
  [PSCustomObject]@{ Incident = $_.Message; Server = $svr.Hostname; Status = $svr.Status }
}
```

```

Incident              Server Status
--------              ------ ------
Disk /dev/sda1 at 97% app-01 offline
Disk /dev/sda1 at 97% app-01 offline
Disk /dev/sda1 at 97% app-01 offline
```

Herzlichen Glückwunsch!
---

Sie haben das Buckets-Tutorial abgeschlossen. Alle Tutorial-Daten wurden
bereinigt — Ihr System ist genau so, wie es vor dem Start war.



Was Sie gelernt haben:

  fill / spill / dip / toss / drain
                               — speichern, lesen, auflisten, Buckets loeschen, Objekte loeschen
  -Key / -KeyProperty         — naming objects
  -Overwrite / -AsTimestamp    — replacement and timestamp keys
  -AsJson / -Compress          — storage formats
  -Match (exact)              — hashtable-based filtering
  -Filter (scriptblock)       — expression-based comparison (-gt, -like, -contains, -match)
  Nested property filtering   — $_.Settings.Enabled with -Filter
  -First / -Skip              — pagination
  Set-BucketObject             — update in place (pipeline + explicit)
  Partial update / patch       — add properties with hashtable pipe
  drain / toss                 — Objekte loeschen, Buckets loeschen
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
  Edge cases                   — $null values, special chars, empty keys, safety guards
  Format preservation          — JSON stays .json, binary stays .dat through Rename/Copy
  Server/event management      — inventory, incidents, health reports, cross-bucket correlation

Mehr erfahren: Get-Help <Cmdlet> -Full
Siehe auch:  README.md, .tests/demo/*.ps1


---

Viel Spaß mit Buckets!

