$TutorialData = @{
    en = @{
        Chapters = @(
            @{
                Name = "01-intro"
                Title = "Introduction"
                Sections = @(
                    @{
                        Name = "01-what-why-how"
                        Title = "What, Why, How"
                        Lessons = @(
                            @{
                                Key = "01-what-is-buckets"
                                Title = "What is Buckets?"
                                Body = @'
  Buckets is a PowerShell module for file-based PSObject storage.
  Every object is a file, every bucket is a folder. There is no
  database, no daemon, no config file — just the filesystem.

  Two storage formats:
    Binary (.dat) — via PSSerializer. Fast, preserves full .NET type
                    information. Handles complex objects, circular refs.
    JSON    (.json) — via -AsJson. Human-readable, portable, editable
                    in any text editor.
'@
                            }
                            @{
                                Key = "02-why-buckets"
                                Title = "Why Buckets?"
                                Body = @'
  Persistent       — objects outlive your PowerShell session
  Shareable        — buckets are folders on disk; copy, sync, commit
  Composable       — pipeline in, pipeline out; just pipe and go
  Browsable        — Get-Bucket -Tree shows the full hierarchy
  Self-describing  — filenames are keys, JSON files are readable
  Expand/Collapse  — nested structures into browsable directory trees
  Cross-platform   — PowerShell 7+ on Windows, macOS, Linux
'@
                            }
                            @{
                                Key = "03-how-it-works"
                                Title = "How does it work?"
                                Body = @'
  Every bucket is a directory under a root path. The default root is:

  Each object is one file — .dat (binary, default) or .json (opt-in).
  The filename (minus extension) is the object's key.

  The six core cmdlets:
    fill   · New-BucketObject      write objects
    scoop  · Get-BucketObject      read objects
    spill  · Remove-BucketObject   delete an object
    dip    · Get-Bucket            list buckets
    drain  · Remove-Bucket         delete a bucket

  Defaults: Binary depth 5, JSON depth 20, path $HOME/.buckets
  Override any of them with -BinaryDepth, -Depth, or -Path.
'@
                                Code = 'Get-BucketRoot'
                            }
                        )
                    }
                )
            }
            @{
                Name = "02-beginner"
                Title = "Beginner"
                Sections = @(
                    @{
                        Name = "01-create"
                        Title = "Create"
                        Lessons = @(
                            @{
                                Key = "01-first-object"
                                Title = "Saving your first object"
                                Body = @'
  Let's save your first object — a simple hashtable describing a user. We give it
  an explicit key "Alice" with -Key, which becomes its key. By default,
  Buckets uses a binary format that preserves the full .NET type information, so
  hashtables, custom objects, even FileInfo — all survive the round trip.
'@
                                SetupCode = @'
$alice = @{ Name = "Alice"; Role = "admin"; Score = 95 }
'@
                                Code = 'New-BucketObject -InputObject $alice -Bucket users -Key "Alice"'
                            }
                            @{
                                Key = "02-keyproperty"
                                Title = "Auto-keying with -KeyProperty"
                                Body = @'
  -KeyProperty uses a property value as the key instead of specifying -Key
  manually. Pass the property name, and each object's value for that property
  becomes its filename. Useful when your data already has a natural ID.
'@
                                SetupCode = @'
$users = @(
    @{ Name = "Alice"; Role = "Developer" }
    @{ Name = "Bob";   Role = "Designer" }
    @{ Name = "Carol"; Role = "PM" }
)
'@
                                Code = '$users | fill -Bucket team -KeyProperty Name'
                            }
                            @{
                                Key = "03-asjson"
                                Title = "JSON format with -AsJson"
                                Body = @'
  -AsJson stores objects as .json files instead of binary .dat. JSON files are
  human-readable and editable in any text editor. Great for config, logs, or any
  data you want to inspect or diff.
'@
                                SetupCode = @'
$alice = @{ Name = "Alice"; Role = "admin"; Score = 95 }
'@
                                Code = @'
New-BucketObject -InputObject $alice -Bucket config -Key "app-config" -AsJson -Quiet
Get-ChildItem (Join-Path (Get-BucketRoot) "config")
'@
                            }
                            @{
                                Key = "04-overwrite"
                                Title = "Overwriting existing objects"
                                Body = @'
  By default, fill skips existing keys to prevent accidental overwrites.
  Add -Overwrite to replace an existing object. Try saving twice — the
  second without -Overwrite skips, with -Overwrite replaces.
'@
                                SetupCode = @'
$alice  = @{ Name = "Alice"; Role = "admin";  Score = 95 }
$alice2 = @{ Name = "Alice"; Role = "manager"; Score = 99 }
'@
                                Code = @'
New-BucketObject -InputObject $alice  -Bucket users -Key "Alice" -Quiet
New-BucketObject -InputObject $alice2 -Bucket users -Key "Alice" -Quiet
New-BucketObject -InputObject $alice2 -Bucket users -Key "Alice" -Overwrite -Quiet
scoop -Bucket users -Key "Alice" | Select-Object Name, Role, Score
'@
                            }
                        )
                    }
                    @{
                        Name = "02-read"
                        Title = "Read"
                        Lessons = @(
                            @{
                                Key = "01-scoop-all"
                                Title = "Spilling all objects"
                                Body = @'
  The counterpart to fill is scoop (short for Get-BucketObject). With no arguments,
  it returns every object from every bucket — useful for getting the lay of the land.
'@
                                SetupCode = @'
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3 }
    @{ Name="Bob";     Role="Designer";   Level=2 }
    @{ Name="Carol";   Role="PM";         Level=3 }
    @{ Name="Frank";   Role="Developer";  Level=4 }
)
$staffData = @(
    @{ Name="Dana";  Role="HR";        Level=2 }
    @{ Name="Eric";  Role="Finance";   Level=3 }
    @{ Name="Gina";  Role="Marketing"; Level=1 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
$staffData | fill -Bucket staff -KeyProperty Name -Quiet
'@
                                Code = 'scoop'
                            }
                            @{
                                Key = "02-by-key"
                                Title = "Retrieving a single object"
                                Body = @'
  scoop with -Key returns one specific object. Use this when you know
  the exact key — much faster than filtering.
'@
                                SetupCode = @'
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
    @{ Name="Carol";   Role="PM";         Level=3; Score=88 }
    @{ Name="Frank";   Role="Developer";  Level=4; Score=91 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = 'scoop -Bucket team -Key "Alice"'
                            }
                            @{
                                Key = "03-match"
                                Title = "Filtering with -Match"
                                Body = @'
  -Match takes a hashtable and returns objects where all specified
  properties match (AND logic). Great for quick lookups.
'@
                                SetupCode = @'
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
    @{ Name="Carol";   Role="PM";         Level=3; Score=88 }
    @{ Name="Frank";   Role="Developer";  Level=4; Score=91 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
scoop -Bucket team -Match @{ Role = "Developer" }
scoop -Bucket team -Match @{ Level = 3 }
scoop -Bucket team -Match @{ Role = "Developer"; Level = 3 }
'@
                            }
                            @{
                                Key = "04-filter"
                                Title = "Filtering with -Filter"
                                Body = @'
  -Filter uses a PowerShell scriptblock with $_ for the current object.
  More flexible than -Match — supports comparisons, operators, any logic.
'@
                                SetupCode = @'
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
    @{ Name="Carol";   Role="PM";         Level=3; Score=88 }
    @{ Name="Frank";   Role="Developer";  Level=4; Score=91 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
scoop -Bucket team -Filter { $_.Level -gt 2 }
scoop -Bucket team -Filter { $_.Score -ge 90 }
'@
                            }
                        )
                    }
                    @{
                        Name = "03-update"
                        Title = "Update"
                        Lessons = @(
                            @{
                                Key = "01-pipeline-update"
                                Title = "Pipeline update with Set-BucketObject"
                                Body = @'
  Set-BucketObject updates an existing object in place. When piped from scoop, it
  auto-detects the bucket and key from the _BucketName and _BucketKey metadata —
  no need to specify them again.
'@
                                SetupCode = @'
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
    @{ Name="Carol";   Role="PM";         Level=3; Score=88 }
    @{ Name="Frank";   Role="Developer";  Level=4; Score=91 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
scoop -Bucket team -Key "Bob" | ForEach-Object {
    $_.Score = 99
    $_.Role = "Lead"
    $_
} | Set-BucketObject -PassThru
'@
                            }
                            @{
                                Key = "02-patch"
                                Title = "Partial update with -InputObject"
                                Body = @'
  Pass a hashtable to -InputObject to update only specific properties.
  Other properties stay untouched — like a partial PATCH in REST APIs.
'@
                                SetupCode = @'
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
Set-BucketObject -Bucket team -Key "Bob" -InputObject @{ Role = "Lead" } -PassThru
scoop -Bucket team -Key "Bob"
'@
                            }
                        )
                    }
                    @{
                        Name = "04-delete"
                        Title = "Delete"
                        Lessons = @(
                            @{
                                Key = "01-preview-whatif"
                                Title = "Preview with -WhatIf"
                                Body = @'
  -WhatIf previews what would be deleted without actually removing anything. Always
  safe to try before you delete.
'@
                                SetupCode = @'
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3 }
    @{ Name="Bob";     Role="Designer";   Level=2 }
    @{ Name="Carol";   Role="PM";         Level=3 }
    @{ Name="Frank";   Role="Developer";  Level=4 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = 'Remove-BucketObject -Bucket team -Key "Bob" -WhatIf'
                            }
                            @{
                                Key = "02-all"
                                Title = "Removing all objects with -All"
                                Body = @'
  -All removes every object from a bucket in one go. The bucket directory
  stays. Always safe to preview with -WhatIf first.
'@
                                SetupCode = @'
$teamData = @(
    @{ Name="Alice"; Role="Developer"; Level=3 }
    @{ Name="Bob";   Role="Designer";  Level=2 }
    @{ Name="Carol"; Role="PM";        Level=3 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
Remove-BucketObject -Bucket team -All -WhatIf
Remove-BucketObject -Bucket team -All -Quiet
'@
                            }
                            @{
                                Key = "03-match"
                                Title = "Filtered removal with -Match"
                                Body = @'
  -Match also works on Remove-BucketObject. Deletes only objects
  whose properties match the hashtable. Useful for bulk cleanup.
'@
                                SetupCode = @'
$teamData = @(
    @{ Name="Alice"; Role="Developer"; Level=3; Status="active" }
    @{ Name="Bob";   Role="Designer";  Level=2; Status="archived" }
    @{ Name="Carol"; Role="PM";        Level=3; Status="active" }
    @{ Name="Frank"; Role="Developer"; Level=4; Status="archived" }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
Remove-BucketObject -Bucket team -Match @{ Status = "archived" } -WhatIf
Remove-BucketObject -Bucket team -Match @{ Status = "archived" } -PassThru
'@
                            }
                        )
                    }
                )
            }
            @{
                Name = "03-advanced"
                Title = "Advanced"
                Sections = @(
                    @{
                        Name = "01-copy-rename"
                        Title = "Copy, Rename, Move"
                        Lessons = @(
                            @{
                                Key = "01-copy-within-bucket"
                                Title = "Copy within a bucket"
                                Body = @'
  Copy an object within the same bucket but with a different key. The original stays
  untouched — this is a true copy, not a move.
'@
                                SetupCode = @'
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3 }
    @{ Name="Bob";     Role="Designer";   Level=2 }
    @{ Name="Carol";   Role="PM";         Level=3 }
    @{ Name="Frank";   Role="Developer";  Level=4 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "Alice-Backup" -Quiet
scoop -Bucket team -Key "Alice-Backup"
'@
                            }
                        )
                    }
                    @{
                        Name = "02-management"
                        Title = "Management"
                        Lessons = @(
                            @{
                                Key = "01-list-buckets"
                                Title = "Listing buckets with dip"
                                Body = @'
  dip (short for Get-Bucket) lists all your buckets with their object counts and
  timestamps. It's the first command to run when you want an overview.
'@
                                SetupCode = @'
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
'@
                                Code = 'dip'
                            }
                        )
                    }
                    @{
                        Name = "03-export-import"
                        Title = "Export / Import"
                        Lessons = @(
                            @{
                                Key = "01-export-clixml"
                                Title = "Export to CLIXML"
                                Body = @'
  Export saves an entire bucket to an archive file. CLIXML (the default) preserves
  .NET type information for perfect round-trip fidelity.
'@
                                SetupCode = @'
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3 }
    @{ Name="Bob";     Role="Designer";   Level=2 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
$exportDir = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-tutorial-export"
$null = New-Item -ItemType Directory -Path $exportDir -Force -ErrorAction SilentlyContinue
'@
                                Code = @'
Export-Bucket -Bucket team -OutputFile (Join-Path $exportDir "team.clixml") -Quiet
Get-ChildItem $exportDir
'@
                            }
                        )
                    }
                    @{
                        Name = "04-psdrive"
                        Title = "PSDrive"
                        Lessons = @(
                            @{
                                Key = "01-buckets-drive"
                                Title = "The buckets: drive"
                                Body = @'
  Buckets registers a custom PSDrive called "buckets:". You can navigate it with
  cd, Get-ChildItem, Get-Content — just like any other drive.
'@
                                Code = 'Get-PSDrive -Name buckets'
                            }
                        )
                    }
                    @{
                        Name = "05-nested"
                        Title = "Nested Buckets"
                        Lessons = @(
                            @{
                                Key = "01-create-nested"
                                Title = "Creating nested buckets"
                                Body = @'
  Bucket names with forward slashes create nested directory structures on disk.
  This is how you organize data hierarchically — like folders within folders,
  each level a real subdirectory.
'@
                                Code = @'
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
Get-Bucket -Tree -Name "org" -Objects
'@
                            }
                        )
                    }
                    @{
                        Name = "06-pipelines"
                        Title = "Pipelines"
                        Lessons = @(
                            @{
                                Key = "01-generate-fill"
                                Title = "Generate and fill"
                                Body = @'
  Buckets is designed for pipeline-first usage. Most cmdlets accept pipeline
  input and emit objects with metadata. Here's how to chain them together.
'@
                                Code = @'
1..5 | ForEach-Object { @{ Name = "item-$_"; Value = $_ * 10 } } |
    fill -Bucket "dir-listing" -KeyProperty Name -Quiet
scoop -Bucket "dir-listing"
'@
                            }
                        )
                    }
                    @{
                        Name = "07-tips"
                        Title = "Tips & Shortcuts"
                        Lessons = @(
                            @{
                                Key = "01-aliases-reference"
                                Title = "Aliases & Shortcuts Reference"
                                Body = @'
  Three aliases are exported by the module:

    fill   = New-BucketObject     — save objects
    scoop  = Get-BucketObject     — retrieve objects
    dip    = Get-Bucket            — list buckets

  Pipeline parameter binding via metadata:

    _BucketName   → -Bucket   (on Set-BucketObject)
    _BucketKey    → -Key      (on Set-BucketObject)
    _BucketFile   → full path to the stored file
'@
                            }
                        )
                    }
                )
            }
            @{
                Name = "04-sysadmin"
                Title = "Sysadmin"
                Sections = @(
                    @{
                        Name = "01-server-inventory"
                        Title = "Server Inventory"
                        Lessons = @(
                            @{
                                Key = "01-storing-inventory"
                                Title = "Storing your server inventory"
                                Body = @'
  This section teaches Buckets from the ground up using real-world data:
  server inventory, incident logs, health reports, and cross-bucket
  correlation. Each lesson builds on the last, starting simple and growing
  in complexity.

  The fill alias (short for New-BucketObject) saves objects into named
  storage areas called buckets. Here we store our server inventory — each
  server record becomes an object keyed by its hostname via -KeyProperty.
  The -Quiet switch suppresses the summary output.
'@
                                Code = @'
$servers = @(
    @{ Hostname="web-01";   IP="10.0.1.10"; OS="Ubuntu 22.04";  Role="web";        CPU=4;  RAM=8;  Disk=120; Status="online";   Location="DC1" }
    @{ Hostname="web-02";   IP="10.0.1.11"; OS="Ubuntu 22.04";  Role="web";        CPU=4;  RAM=8;  Disk=120; Status="online";   Location="DC1" }
    @{ Hostname="db-01";    IP="10.0.1.20"; OS="Debian 12";     Role="database";   CPU=8;  RAM=32; Disk=500; Status="online";   Location="DC1" }
    @{ Hostname="db-02";    IP="10.0.2.20"; OS="Debian 12";     Role="database";   CPU=8;  RAM=32; Disk=500; Status="degraded"; Location="DC2" }
    @{ Hostname="cache-01"; IP="10.0.1.30"; OS="Alpine 3.18";   Role="cache";      CPU=2;  RAM=16; Disk=60;  Status="online";   Location="DC1" }
    @{ Hostname="mon-01";   IP="10.0.1.40"; OS="Ubuntu 22.04";  Role="monitoring"; CPU=2;  RAM=4;  Disk=250; Status="online";   Location="DC2" }
    @{ Hostname="app-01";   IP="10.0.2.50"; OS="Rocky 9";       Role="app";        CPU=8;  RAM=16; Disk=200; Status="offline";  Location="DC2" }
    @{ Hostname="backup-01";IP="10.0.1.1";  OS="FreeBSD 14";    Role="backup";     CPU=4;  RAM=8;  Disk=2000;Status="online";   Location="DC1" }
)
$servers | fill -Bucket servers -KeyProperty Hostname -Quiet
'@
                            }
                        )
                    }
                )
            }
            @{
                Name = "05-full-course"
                Title = "Full Course"
                Sections = @(
                    @{
                        Name = "01-course-overview"
                        Title = "Course Overview"
                        Lessons = @(
                            @{
                                Key = "01-what-you-will-learn"
                                Title = "What You Will Learn"
                                Body = @'
  This course takes you through all of Buckets' features — from your first
  object to advanced pipelines and sysadmin scenarios.

  Chapters:
    01 · Introduction — core concepts and the filesystem model
    02 · Beginner — CRUD operations (create, read, update, delete)
    03 · Advanced — copy, rename, PSDrive, nested buckets, pipelines
    04 · Sysadmin — real-world scenarios: inventory, logs, incidents
    05 · Full Course — complete walkthrough of all features

  Each chapter is divided into sections, and each section contains
  focused lessons with explanations and code examples you can run.
'@
                            }
                        )
                    }
                )
            }
        )
    }
    de = @{
        Chapters = @(
            # TODO: German translation
        )
    }
}
