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
                                Code = @'
# Show the root directory where all bucket data lives
Get-BucketRoot
'@
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
# Create a sample user hashtable to store in a bucket
$alice = @{ Name = "Alice"; Role = "admin"; Score = 95 }
'@
                                Code = @'
# Save the hashtable as an object in the "users" bucket with key "Alice"
New-BucketObject -InputObject $alice -Bucket users -Key "Alice"
'@
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
# Three user records — the "Name" value will serve as each object's key
$users = @(
    @{ Name = "Alice"; Role = "Developer" }
    @{ Name = "Bob";   Role = "Designer" }
    @{ Name = "Carol"; Role = "PM" }
)
'@
                                Code = @'
# Pipe the array to fill; -KeyProperty "Name" auto-extracts the key from each object
$users | fill -Bucket team -KeyProperty Name
'@
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
# Sample config object for JSON format demo
$alice = @{ Name = "Alice"; Role = "admin"; Score = 95 }
'@
                                Code = @'
# Store as human-readable JSON (.json) instead of binary (.dat)
New-BucketObject -InputObject $alice -Bucket config -Key "app-config" -AsJson -Quiet
# List the .json file on disk to confirm the format
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
# Two versions of "Alice" — same key name, different property values
$alice  = @{ Name = "Alice"; Role = "admin";  Score = 95 }
$alice2 = @{ Name = "Alice"; Role = "manager"; Score = 99 }
'@
                                Code = @'
# First save succeeds — key "Alice" doesn't exist yet
New-BucketObject -InputObject $alice  -Bucket users -Key "Alice" -Quiet
# Second save WITHOUT -Overwrite is silently skipped (key already exists)
New-BucketObject -InputObject $alice2 -Bucket users -Key "Alice" -Quiet
# Third save WITH -Overwrite replaces the existing object
New-BucketObject -InputObject $alice2 -Bucket users -Key "Alice" -Overwrite -Quiet
# Verify the overwritten data: Role=manager, Score=99
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
                                Title = "Querying multiple objects"
                                Body = @'
  The counterpart to fill is scoop (short for Get-BucketObject). With -Bucket you
  can target specific buckets and their objects.
'@
                                SetupCode = @'
# Team members for one department
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3 }
    @{ Name="Bob";     Role="Designer";   Level=2 }
    @{ Name="Carol";   Role="PM";         Level=3 }
    @{ Name="Frank";   Role="Developer";  Level=4 }
)
# Staff members for another department
$staffData = @(
    @{ Name="Dana";  Role="HR";        Level=2 }
    @{ Name="Eric";  Role="Finance";   Level=3 }
    @{ Name="Gina";  Role="Marketing"; Level=1 }
)
# Store each dataset in its own bucket, keyed by the "Name" property
$teamData | fill -Bucket team -KeyProperty Name -Quiet
$staffData | fill -Bucket staff -KeyProperty Name -Quiet
'@
                                Code = @'
# Grab all objects from the team and staff buckets
scoop -Bucket team, staff
'@
                            }
                            @{
                                Key = "02-by-key"
                                Title = "Retrieving a single object"
                                Body = @'
  scoop with -Key returns one specific object. Use this when you know
  the exact key — much faster than filtering.
'@
                                SetupCode = @'
# Team data with scores — used for both by-key and filtering exercises
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
    @{ Name="Carol";   Role="PM";         Level=3; Score=88 }
    @{ Name="Frank";   Role="Developer";  Level=4; Score=91 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Retrieve exactly one object by its key — much faster than filtering all objects
scoop -Bucket team -Key "Alice"
'@
                            }
                            @{
                                Key = "03-match"
                                Title = "Filtering with -Match"
                                Body = @'
  -Match takes a hashtable and returns objects where all specified
  properties match (AND logic). Great for quick lookups.
'@
                                SetupCode = @'
# Sample team with varied roles and levels for -Match demos
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
    @{ Name="Carol";   Role="PM";         Level=3; Score=88 }
    @{ Name="Frank";   Role="Developer";  Level=4; Score=91 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# All developers (2 results)
scoop -Bucket team -Match @{ Role = "Developer" }
# All level-3 members (2 results)
scoop -Bucket team -Match @{ Level = 3 }
# AND logic: developer AND level 3 (1 result)
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
# Same team data used for -Match, now demonstrating -Filter comparisons
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
    @{ Name="Carol";   Role="PM";         Level=3; Score=88 }
    @{ Name="Frank";   Role="Developer";  Level=4; Score=91 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Scriptblock filter: members whose Level is greater than 2
scoop -Bucket team -Filter { $_.Level -gt 2 }
# Members whose Score is greater than or equal to 90
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
# Team data for the pipeline update exercise
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
    @{ Name="Carol";   Role="PM";         Level=3; Score=88 }
    @{ Name="Frank";   Role="Developer";  Level=4; Score=91 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Retrieve Bob, modify properties, then pipe back to Set-BucketObject
scoop -Bucket team -Key "Bob" | ForEach-Object {
    $_.Score = 99       # Update Score in place
    $_.Role = "Lead"    # Promote Bob to Lead
    $_                  # Pass the modified object downstream
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
# Smaller dataset for the partial-update demo
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Partial update: only Role changes; Level, Score stay untouched
Set-BucketObject -Bucket team -Key "Bob" -InputObject @{ Role = "Lead" } -PassThru
# Confirm Bob now has Role=Lead while other properties remain unchanged
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
# Sample data to safely preview deletion with -WhatIf
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3 }
    @{ Name="Bob";     Role="Designer";   Level=2 }
    @{ Name="Carol";   Role="PM";         Level=3 }
    @{ Name="Frank";   Role="Developer";  Level=4 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Preview what would be deleted — no actual removal, perfectly safe
Remove-BucketObject -Bucket team -Key "Bob" -WhatIf
'@
                            }
                            @{
                                Key = "02-all"
                                Title = "Removing all objects with -All"
                                Body = @'
  -All removes every object from a bucket in one go. The bucket directory
  stays. Always safe to preview with -WhatIf first.
'@
                                SetupCode = @'
# Three objects to demonstrate bulk removal with -All
$teamData = @(
    @{ Name="Alice"; Role="Developer"; Level=3 }
    @{ Name="Bob";   Role="Designer";  Level=2 }
    @{ Name="Carol"; Role="PM";        Level=3 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Preview: shows exactly what -All would delete (dry run, nothing removed)
Remove-BucketObject -Bucket team -All -WhatIf
# Actually delete everything in the bucket (the bucket directory stays on disk)
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
# Mix of active and archived records for targeted deletion by status
$teamData = @(
    @{ Name="Alice"; Role="Developer"; Level=3; Status="active" }
    @{ Name="Bob";   Role="Designer";  Level=2; Status="archived" }
    @{ Name="Carol"; Role="PM";        Level=3; Status="active" }
    @{ Name="Frank"; Role="Developer"; Level=4; Status="archived" }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Preview: only archived objects would be removed, active ones kept
Remove-BucketObject -Bucket team -Match @{ Status = "archived" } -WhatIf
# Actually remove archived objects, showing which keys were deleted
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
# Team data to demonstrate copy operations within a bucket
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3 }
    @{ Name="Bob";     Role="Designer";   Level=2 }
    @{ Name="Carol";   Role="PM";         Level=3 }
    @{ Name="Frank";   Role="Developer";  Level=4 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Copy Alice's object to a new key "Alice-Backup" — original stays untouched
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "Alice-Backup" -Quiet
# Retrieve the copy to confirm it holds the same data as the original
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
# Seed a sample config bucket so there is something to list with dip
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
'@
                                Code = @'
# dip (Get-Bucket) shows all buckets with object counts and timestamps
dip
'@
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
# Two records to export to a CLIXML archive
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3 }
    @{ Name="Bob";     Role="Designer";   Level=2 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
# Create a temp directory for the export file
$exportDir = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-tutorial-export"
$null = New-Item -ItemType Directory -Path $exportDir -Force -ErrorAction SilentlyContinue
'@
                                Code = @'
# Export the entire "team" bucket to a CLIXML archive file
Export-Bucket -Bucket team -OutputFile (Join-Path $exportDir "team.clixml") -Quiet
# Show the exported file on disk
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
                                Code = @'
# The module registers "buckets:" as a PSDrive for filesystem-style navigation
Get-PSDrive -Name buckets
'@
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
# German cities in a nested path: org > eu > de > cities
$deCities = @(
    @{ Name = "Berlin"; Population = 3600000; Country = "DE" }
    @{ Name = "Munich"; Population = 1500000; Country = "DE" }
)
New-BucketObject -InputObject $deCities -Bucket "org/eu/de/cities" -KeyProperty Name -Quiet

# UK cities in org/eu/uk/cities
$ukCities = @(
    @{ Name = "London"; Population = 8900000; Country = "UK" }
    @{ Name = "Manchester"; Population = 550000; Country = "UK" }
)
$ukCities | fill -Bucket "org/eu/uk/cities" -KeyProperty Name -Quiet

# US cities in org/us/cities
$usCities = @(
    @{ Name = "New York"; Population = 8300000; Country = "US" }
)
$usCities | fill -Bucket "org/us/cities" -KeyProperty Name -Quiet

# Departments under org/eu/de/depts — different entity type in same hierarchy
$deDepts = @(
    @{ Dept = "Engineering"; Lead = "Alice" }
    @{ Dept = "Marketing"; Lead = "Bob" }
)
$deDepts | fill -Bucket "org/eu/de/depts" -KeyProperty Dept -Quiet
# Show the full hierarchy as a tree
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
# Generate 5 items on the fly, pipe each directly into a bucket
1..5 | ForEach-Object { @{ Name = "item-$_"; Value = $_ * 10 } } |
    fill -Bucket "dir-listing" -KeyProperty Name -Quiet
# Retrieve everything from the new bucket
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
# Define a realistic server inventory as an array of hashtables
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
# Store inventory in the "servers" bucket, keyed by hostname
$servers | fill -Bucket servers -KeyProperty Hostname -Quiet
'@
                            }
                        )
                    }
                )
            }
            @{
                Name = "05-funnels"
                Title = "Funnels"
                Sections = @(
                    @{
                        Name = "01-using-funnels"
                        Title = "Using Funnels"
                        Lessons = @(
                            @{
                                Key = "01-what-is-a-funnel"
                                Title = "What is a Funnel?"
                                Body = @'
  A Funnel is a named, reusable filter or transform scriptblock stored
  outside your bucket data. Think of it as a saved query or mapping that
  you can apply on-the-fly.

  On fill (New-BucketObject):  Funnels transform objects before storage.
                               Return the modified object, or $null to skip.
  On scoop (Get-BucketObject): Funnels transform or filter results.
                               Return the object to keep it, $null to drop it.

  Funnels are stored as JSON files in $HOME/.buckets-system/funnels/,
  keeping them separate from your data. They are cached in memory for
  the duration of your session.
'@
                            }
                            @{
                                Key = "02-creating-a-funnel"
                                Title = "Creating a Funnel"
                                Body = @'
  Use New-Funnel to create a named funnel. The -Filter parameter takes
  a scriptblock that uses $_ for the pipeline object. Return the object
  to keep it, or $null to drop it. For fill, return a modified object
  to transform it before storage.

  Adding -Description lets you document what the funnel does.
'@
                                SetupCode = @'
$team = @(
    @{ Name="Alice";   Role="Developer"; Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";  Level=2; Score=72 }
    @{ Name="Carol";   Role="PM";        Level=3; Score=88 }
    @{ Name="Frank";   Role="Developer"; Level=4; Score=91 }
)
$team | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Create a funnel that filters for senior members (Level > 2)
New-Funnel -Name "seniors" -Filter { $_.Level -gt 2 } -Description "Team members above level 2"

# List all funnels to confirm
Get-Funnel
'@
                            }
                            @{
                                Key = "03-funnel-on-scoop"
                                Title = "Funnels on scoop (filter)"
                                Body = @'
  Pass a funnel name to scoop's -Funnel parameter to filter results.
  Funnels combine with -Match and -Filter — all conditions apply.
'@
                                Code = @'
# Use the "seniors" funnel to get only senior team members
scoop -Bucket team -Funnel "seniors"
'@
                            }
                            @{
                                Key = "04-funnel-on-fill"
                                Title = "Funnels on fill (transform)"
                                Body = @'
  On fill, a funnel transforms each object before storage. Return the
  modified object from the scriptblock, or $null to skip that object.

  Here we add a "Seniority" property based on Level before storing.
'@
                                SetupCode = @'
$newTeam = @(
    @{ Name="Grace";  Role="Developer"; Level=5 }
    @{ Name="Heidi";  Role="Designer";  Level=1 }
    @{ Name="Ivan";   Role="PM";        Level=3 }
)
'@
                                Code = @'
# Create a transform funnel that adds a Seniority label
New-Funnel -Name "add-seniority" -Filter {
    if ($_.Level -ge 4) { $_.Seniority = "Senior"; $_ }
    elseif ($_.Level -ge 2) { $_.Seniority = "Mid"; $_ }
    else { $null }
}

# Apply the funnel during fill
$newTeam | fill -Bucket team -KeyProperty Name -Funnel "add-seniority" -Quiet

# Check the results — Heidi (Level 1) was skipped
scoop -Bucket team -Key "Grace", "Heidi", "Ivan"
'@
                            }
                            @{
                                Key = "05-managing-funnels"
                                Title = "Managing Funnels"
                                Body = @'
  Funnels are fully manageable with dedicated cmdlets:

    Get-Funnel      — list all funnels or retrieve a specific one
    Set-Funnel      — update a funnel's filter or description
    Remove-Funnel   — delete a funnel (supports -WhatIf)

  Funnels persist between sessions — they live on disk in
  $HOME/.buckets-system/funnels/. Each funnel is a single JSON file.
'@
                                SetupCode = @'
New-Funnel -Name "demo-funnel" -Filter { $_.Active -eq $true } -Description "Active items only" -Force
'@
                                Code = @'
# List all funnels (should include "demo-funnel")
Get-Funnel

# Update an existing funnel
Set-Funnel -Name "demo-funnel" -Description "Only active items please"

# Preview removal
Remove-Funnel -Name "demo-funnel" -WhatIf

# Actually remove it
Remove-Funnel -Name "demo-funnel" -Quiet

# Confirm it's gone
Get-Funnel -Name "demo-funnel"
'@
                            }
                            @{
                                Key = "06-adhoc-scriptblock"
                                Title = "Ad-hoc scriptblock funnels"
                                Body = @'
  -Funnel also accepts a scriptblock directly (without creating a named
  funnel). Use this for one-off filters or transforms that don't need
  to be saved.
'@
                                SetupCode = @'
$items = @(
    @{ Name="Jack";  Role="Developer"; Level=3 }
    @{ Name="Kate";  Role="Designer";  Level=4 }
    @{ Name="Leo";   Role="PM";        Level=2 }
)
$items | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Ad-hoc filter — no named funnel needed
scoop -Bucket team -Funnel { $_.Level -ge 3 }
'@
                            }
                        )
                    }
                )
            }
            @{
                Name = "06-full-course"
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
    05 · Funnels — named reusable filters and transforms
    06 · Full Course — complete walkthrough of all features

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
            @{
                Name = "01-intro"
                Title = "Einführung"
                Sections = @(
                    @{
                        Name = "01-what-why-how"
                        Title = "Was, Warum, Wie"
                        Lessons = @(
                            @{
                                Key = "01-what-is-buckets"
                                Title = "Was ist Buckets?"
                                Body = @'
  Buckets ist ein PowerShell-Modul zur dateibasierten PSObject-Speicherung.
  Jedes Objekt ist eine Datei, jeder Bucket ist ein Ordner. Es gibt keine
  Datenbank, keinen Dienst, keine Konfigurationsdatei — nur das Dateisystem.

  Zwei Speicherformate:
    Binary (.dat) — über PSSerializer. Schnell, bewahrt vollständige .NET-Typ-
                    informationen. Beherrscht komplexe Objekte, zirkuläre Referenzen.
    JSON    (.json) — über -AsJson. Lesbar, portabel, in jedem Editor editierbar.
'@
                            }
                            @{
                                Key = "02-why-buckets"
                                Title = "Warum Buckets?"
                                Body = @'
  Dauerhaft       — Objekte überleben die PowerShell-Sitzung
  Teilbar         — Buckets sind Ordner auf der Platte; kopieren, syncen, committen
  Kombinierbar    — Pipeline rein, Pipeline raus; einfach weiterleiten
  Durchsuchbar    — Get-Bucket -Tree zeigt die gesamte Hierarchie
  Selbstbeschreibend — Dateinamen sind Schlüssel, JSON-Dateien sind lesbar
  Auf-/Zuklappen  — verschachtelte Strukturen als durchsuchbare Verzeichnisbäume
  Plattformunabhängig — PowerShell 7+ auf Windows, macOS, Linux
'@
                            }
                            @{
                                Key = "03-how-it-works"
                                Title = "Wie funktioniert es?"
                                Body = @'
  Jeder Bucket ist ein Verzeichnis unter einem Wurzelpfad. Der Standardpfad ist:

  Jedes Objekt ist eine Datei — .dat (binär, Standard) oder .json (optional).
  Der Dateiname (ohne Erweiterung) ist der Schlüssel des Objekts.

  Die sechs Kern-Cmdlets:
    fill   · New-BucketObject      Objekte schreiben
    scoop  · Get-BucketObject      Objekte lesen
    spill  · Remove-BucketObject   Objekt löschen
    dip    · Get-Bucket            Buckets auflisten
    drain  · Remove-Bucket         Bucket löschen

  Standardeinstellungen: Binary-Tiefe 5, JSON-Tiefe 20, Pfad $HOME/.buckets
  Überschreibbar mit -BinaryDepth, -Depth oder -Path.
'@
                                Code = @'
# Zeige das Wurzelverzeichnis, in dem alle Bucket-Daten gespeichert sind
Get-BucketRoot
'@
                            }
                        )
                    }
                )
            }
            @{
                Name = "02-beginner"
                Title = "Anfänger"
                Sections = @(
                    @{
                        Name = "01-create"
                        Title = "Erstellen"
                        Lessons = @(
                            @{
                                Key = "01-first-object"
                                Title = "Dein erstes Objekt speichern"
                                Body = @'
  Speichern wir dein erstes Objekt — eine einfache Hashtable, die einen Benutzer
  beschreibt. Mit -Key geben wir den expliziten Schlüssel "Alice" an, der zum
  Dateinamen wird. Standardmäßig verwendet Buckets das Binärformat, das die
  vollständigen .NET-Typinformationen bewahrt — Hashtables, benutzerdefinierte
  Objekte, selbst FileInfo überstehen den Rundlauf.
'@
                                SetupCode = @'
# Erstelle eine Beispiel-Hashtable für einen Benutzer
$alice = @{ Name = "Alice"; Role = "admin"; Score = 95 }
'@
                                Code = @'
# Speichere die Hashtable als Objekt im Bucket "users" mit dem Schlüssel "Alice"
New-BucketObject -InputObject $alice -Bucket users -Key "Alice"
'@
                            }
                            @{
                                Key = "02-keyproperty"
                                Title = "Automatische Schlüssel mit -KeyProperty"
                                Body = @'
  -KeyProperty verwendet einen Eigenschaftswert als Schlüssel, anstatt -Key manuell
  anzugeben. Übergib den Eigenschaftsnamen, und der Wert jedes Objekts für diese
  Eigenschaft wird zum Dateinamen. Nützlich, wenn deine Daten bereits eine
  natürliche ID haben.
'@
                                SetupCode = @'
# Drei Benutzerdatensätze — der Wert von "Name" dient als Objektschlüssel
$users = @(
    @{ Name = "Alice"; Role = "Developer" }
    @{ Name = "Bob";   Role = "Designer" }
    @{ Name = "Carol"; Role = "PM" }
)
'@
                                Code = @'
# Leite das Array an fill weiter; -KeyProperty "Name" extrahiert den Schlüssel
$users | fill -Bucket team -KeyProperty Name
'@
                            }
                            @{
                                Key = "03-asjson"
                                Title = "JSON-Format mit -AsJson"
                                Body = @'
  -AsJson speichert Objekte als .json-Dateien statt binärer .dat. JSON-Dateien
  sind lesbar und in jedem Texteditor editierbar. Ideal für Konfigurationen,
  Logs oder Daten, die du inspizieren oder diffen möchtest.
'@
                                SetupCode = @'
# Beispiel-Konfigurationsobjekt für die JSON-Format-Demo
$alice = @{ Name = "Alice"; Role = "admin"; Score = 95 }
'@
                                Code = @'
# Speichere als lesbares JSON (.json) statt binärem (.dat)
New-BucketObject -InputObject $alice -Bucket config -Key "app-config" -AsJson -Quiet
# Zeige die .json-Datei auf der Platte zur Bestätigung
Get-ChildItem (Join-Path (Get-BucketRoot) "config")
'@
                            }
                            @{
                                Key = "04-overwrite"
                                Title = "Vorhandene Objekte überschreiben"
                                Body = @'
  Standardmäßig überspringt fill vorhandene Schlüssel, um versehentliches
  Überschreiben zu verhindern. Mit -Overwrite kannst du ein vorhandenes Objekt
  ersetzen. Versuche zweimal zu speichern — beim zweiten Mal ohne -Overwrite
  wird übersprungen, mit -Overwrite wird ersetzt.
'@
                                SetupCode = @'
# Zwei Versionen von "Alice" — gleicher Schlüsselname, unterschiedliche Werte
$alice  = @{ Name = "Alice"; Role = "admin";  Score = 95 }
$alice2 = @{ Name = "Alice"; Role = "manager"; Score = 99 }
'@
                                Code = @'
# Erster Speichervorgang erfolgreich — Schlüssel "Alice" existiert noch nicht
New-BucketObject -InputObject $alice  -Bucket users -Key "Alice" -Quiet
# Zweiter Speichervorgang OHNE -Overwrite wird still übersprungen (existiert bereits)
New-BucketObject -InputObject $alice2 -Bucket users -Key "Alice" -Quiet
# Dritter Speichervorgang MIT -Overwrite ersetzt das vorhandene Objekt
New-BucketObject -InputObject $alice2 -Bucket users -Key "Alice" -Overwrite -Quiet
# Überprüfe die überschriebenen Daten: Role=manager, Score=99
scoop -Bucket users -Key "Alice" | Select-Object Name, Role, Score
'@
                            }
                        )
                    }
                    @{
                        Name = "02-read"
                        Title = "Lesen"
                        Lessons = @(
                            @{
                                Key = "01-scoop-all"
                                Title = "Mehrere Objekte abfragen"
                                Body = @'
  Das Gegenstück zu fill ist scoop (Kurzform für Get-BucketObject). Mit -Bucket
  kannst du gezielt Buckets und ihre Objekte abfragen.
'@
                                SetupCode = @'
# Teammitglieder für eine Abteilung
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3 }
    @{ Name="Bob";     Role="Designer";   Level=2 }
    @{ Name="Carol";   Role="PM";         Level=3 }
    @{ Name="Frank";   Role="Developer";  Level=4 }
)
# Mitarbeiter für eine andere Abteilung
$staffData = @(
    @{ Name="Dana";  Role="HR";        Level=2 }
    @{ Name="Eric";  Role="Finance";   Level=3 }
    @{ Name="Gina";  Role="Marketing"; Level=1 }
)
# Speichere jeden Datensatz in seinem eigenen Bucket, keyed by "Name"
$teamData | fill -Bucket team -KeyProperty Name -Quiet
$staffData | fill -Bucket staff -KeyProperty Name -Quiet
'@
                                Code = @'
# Alle Objekte aus den Buckets team und staff abrufen
scoop -Bucket team, staff
'@
                            }
                            @{
                                Key = "02-by-key"
                                Title = "Einzelnes Objekt abrufen"
                                Body = @'
  scoop mit -Key gibt ein bestimmtes Objekt zurück. Verwende dies, wenn du
  den genauen Schlüssel kennst — viel schneller als Filtern.
'@
                                SetupCode = @'
# Teamdaten mit Bewertungen — für Schlüsselabruf- und Filterübungen
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
    @{ Name="Carol";   Role="PM";         Level=3; Score=88 }
    @{ Name="Frank";   Role="Developer";  Level=4; Score=91 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Ein Objekt genau über seinen Schlüssel abrufen — viel schneller als Filtern
scoop -Bucket team -Key "Alice"
'@
                            }
                            @{
                                Key = "03-match"
                                Title = "Filtern mit -Match"
                                Body = @'
  -Match erwartet eine Hashtable und gibt Objekte zurück, bei denen alle
  angegebenen Eigenschaften übereinstimmen (UND-Logik). Ideal für schnelle
  Nachschlagen.
'@
                                SetupCode = @'
# Beispieldaten mit verschiedenen Rollen und Stufen für -Match-Demos
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
    @{ Name="Carol";   Role="PM";         Level=3; Score=88 }
    @{ Name="Frank";   Role="Developer";  Level=4; Score=91 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Alle Entwickler (2 Ergebnisse)
scoop -Bucket team -Match @{ Role = "Developer" }
# Alle Mitglieder der Stufe 3 (2 Ergebnisse)
scoop -Bucket team -Match @{ Level = 3 }
# UND-Logik: Entwickler UND Stufe 3 (1 Ergebnis)
scoop -Bucket team -Match @{ Role = "Developer"; Level = 3 }
'@
                            }
                            @{
                                Key = "04-filter"
                                Title = "Filtern mit -Filter"
                                Body = @'
  -Filter verwendet einen PowerShell-Skriptblock mit $_ für das aktuelle
  Objekt. Flexibler als -Match — unterstützt Vergleiche, Operatoren,
  beliebige Logik.
'@
                                SetupCode = @'
# Gleiche Teamdaten wie bei -Match, jetzt für -Filter-Vergleiche
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
    @{ Name="Carol";   Role="PM";         Level=3; Score=88 }
    @{ Name="Frank";   Role="Developer";  Level=4; Score=91 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Skriptblock-Filter: Mitglieder mit Level größer als 2
scoop -Bucket team -Filter { $_.Level -gt 2 }
# Mitglieder mit Score größer oder gleich 90
scoop -Bucket team -Filter { $_.Score -ge 90 }
'@
                            }
                        )
                    }
                    @{
                        Name = "03-update"
                        Title = "Aktualisieren"
                        Lessons = @(
                            @{
                                Key = "01-pipeline-update"
                                Title = "Pipeline-Update mit Set-BucketObject"
                                Body = @'
  Set-BucketObject aktualisiert ein vorhandenes Objekt direkt. Wenn es aus
  der Pipeline von scoop kommt, erkennt es automatisch Bucket und Schlüssel
  aus den _BucketName- und _BucketKey-Metadaten — keine erneute Angabe nötig.
'@
                                SetupCode = @'
# Teamdaten für die Pipeline-Update-Übung
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
    @{ Name="Carol";   Role="PM";         Level=3; Score=88 }
    @{ Name="Frank";   Role="Developer";  Level=4; Score=91 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Rufe Bob ab, ändere Eigenschaften, leite zurück an Set-BucketObject
scoop -Bucket team -Key "Bob" | ForEach-Object {
    $_.Score = 99       # Aktualisiere Score direkt
    $_.Role = "Lead"    # Befördere Bob zum Lead
    $_                  # Gib das geänderte Objekt weiter
} | Set-BucketObject -PassThru
'@
                            }
                            @{
                                Key = "02-patch"
                                Title = "Teilaktualisierung mit -InputObject"
                                Body = @'
  Übergib eine Hashtable an -InputObject, um nur bestimmte Eigenschaften
  zu aktualisieren. Andere Eigenschaften bleiben unberührt — wie ein
  partielles PATCH in REST-APIs.
'@
                                SetupCode = @'
# Kleinere Datenmenge für die Teilaktualisierungs-Demo
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";   Level=2; Score=72 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Teilaktualisierung: nur Role ändert sich; Level, Score bleiben erhalten
Set-BucketObject -Bucket team -Key "Bob" -InputObject @{ Role = "Lead" } -PassThru
# Bestätige: Bob hat jetzt Role=Lead, andere Eigenschaften unverändert
scoop -Bucket team -Key "Bob"
'@
                            }
                        )
                    }
                    @{
                        Name = "04-delete"
                        Title = "Löschen"
                        Lessons = @(
                            @{
                                Key = "01-preview-whatif"
                                Title = "Vorschau mit -WhatIf"
                                Body = @'
  -WhatIf zeigt eine Vorschau, was gelöscht würde, ohne tatsächlich etwas
  zu entfernen. Immer sicher, vor dem Löschen auszuprobieren.
'@
                                SetupCode = @'
# Beispieldaten für die sichere Löschvorschau mit -WhatIf
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3 }
    @{ Name="Bob";     Role="Designer";   Level=2 }
    @{ Name="Carol";   Role="PM";         Level=3 }
    @{ Name="Frank";   Role="Developer";  Level=4 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Zeige Vorschau, was gelöscht würde — keine tatsächliche Löschung, völlig sicher
Remove-BucketObject -Bucket team -Key "Bob" -WhatIf
'@
                            }
                            @{
                                Key = "02-all"
                                Title = "Alle Objekte mit -All entfernen"
                                Body = @'
  -All entfernt alle Objekte aus einem Bucket auf einmal. Das Bucket-Verzeichnis
  bleibt erhalten. Immer sicher, zuerst mit -WhatIf eine Vorschau anzuzeigen.
'@
                                SetupCode = @'
# Drei Objekte für die Demo der Massenlöschung mit -All
$teamData = @(
    @{ Name="Alice"; Role="Developer"; Level=3 }
    @{ Name="Bob";   Role="Designer";  Level=2 }
    @{ Name="Carol"; Role="PM";        Level=3 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Vorschau: zeigt, was -All löschen würde (Probelauf, nichts wird entfernt)
Remove-BucketObject -Bucket team -All -WhatIf
# Lösche tatsächlich alles im Bucket (das Bucket-Verzeichnis bleibt erhalten)
Remove-BucketObject -Bucket team -All -Quiet
'@
                            }
                            @{
                                Key = "03-match"
                                Title = "Gezieltes Löschen mit -Match"
                                Body = @'
  -Match funktioniert auch bei Remove-BucketObject. Es löscht nur Objekte,
  deren Eigenschaften mit der Hashtable übereinstimmen. Nützlich für
  gezielte Bereinigung.
'@
                                SetupCode = @'
# Mischung aus aktiven und archivierten Datensätzen für gezieltes Löschen
$teamData = @(
    @{ Name="Alice"; Role="Developer"; Level=3; Status="active" }
    @{ Name="Bob";   Role="Designer";  Level=2; Status="archived" }
    @{ Name="Carol"; Role="PM";        Level=3; Status="active" }
    @{ Name="Frank"; Role="Developer"; Level=4; Status="archived" }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Vorschau: nur archivierte Objekte würden entfernt, aktive bleiben
Remove-BucketObject -Bucket team -Match @{ Status = "archived" } -WhatIf
# Entferne tatsächlich archivierte Objekte, zeige welche gelöscht wurden
Remove-BucketObject -Bucket team -Match @{ Status = "archived" } -PassThru
'@
                            }
                        )
                    }
                )
            }
            @{
                Name = "03-advanced"
                Title = "Fortgeschritten"
                Sections = @(
                    @{
                        Name = "01-copy-rename"
                        Title = "Kopieren, Umbenennen, Verschieben"
                        Lessons = @(
                            @{
                                Key = "01-copy-within-bucket"
                                Title = "Innerhalb eines Buckets kopieren"
                                Body = @'
  Kopiere ein Objekt innerhalb desselben Buckets mit einem anderen Schlüssel.
  Das Original bleibt unberührt — dies ist eine echte Kopie, kein Verschieben.
'@
                                SetupCode = @'
# Teamdaten für die Kopieroperationen innerhalb eines Buckets
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3 }
    @{ Name="Bob";     Role="Designer";   Level=2 }
    @{ Name="Carol";   Role="PM";         Level=3 }
    @{ Name="Frank";   Role="Developer";  Level=4 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Kopiere Alices Objekt unter neuem Schlüssel "Alice-Backup" — Original bleibt
Copy-BucketObject -Bucket team -Key "Alice" -DestinationKey "Alice-Backup" -Quiet
# Rufe die Kopie ab, um zu bestätigen, dass sie die gleichen Daten enthält
scoop -Bucket team -Key "Alice-Backup"
'@
                            }
                        )
                    }
                    @{
                        Name = "02-management"
                        Title = "Verwaltung"
                        Lessons = @(
                            @{
                                Key = "01-list-buckets"
                                Title = "Buckets auflisten mit dip"
                                Body = @'
  dip (Kurzform für Get-Bucket) listet alle deine Buckets mit Objektanzahl
  und Zeitstempeln auf. Es ist der erste Befehl, wenn du einen Überblick
  haben möchtest.
'@
                                SetupCode = @'
# Erzeuge einen Beispiel-Config-Bucket, damit es etwas aufzulisten gibt
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -AsJson -Quiet
'@
                                Code = @'
# dip (Get-Bucket) zeigt alle Buckets mit Objektanzahlen und Zeitstempeln
dip
'@
                            }
                        )
                    }
                    @{
                        Name = "03-export-import"
                        Title = "Export / Import"
                        Lessons = @(
                            @{
                                Key = "01-export-clixml"
                                Title = "Nach CLIXML exportieren"
                                Body = @'
  Export speichert einen gesamten Bucket in einer Archivdatei. CLIXML (der
  Standard) bewahrt .NET-Typinformationen für perfekte Rundlauftreue.
'@
                                SetupCode = @'
# Zwei Datensätze für den Export in ein CLIXML-Archiv
$teamData = @(
    @{ Name="Alice";   Role="Developer";  Level=3 }
    @{ Name="Bob";     Role="Designer";   Level=2 }
)
$teamData | fill -Bucket team -KeyProperty Name -Quiet
# Erstelle ein temporäres Verzeichnis für die Exportdatei
$exportDir = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-tutorial-export"
$null = New-Item -ItemType Directory -Path $exportDir -Force -ErrorAction SilentlyContinue
'@
                                Code = @'
# Exportiere den gesamten "team"-Bucket in eine CLIXML-Archivdatei
Export-Bucket -Bucket team -OutputFile (Join-Path $exportDir "team.clixml") -Quiet
# Zeige die exportierte Datei auf der Platte
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
                                Title = "Das buckets:-Laufwerk"
                                Body = @'
  Buckets registriert ein eigenes PSDrive namens "buckets:". Du kannst es
  mit cd, Get-ChildItem, Get-Content navigieren — genau wie jedes andere
  Laufwerk.
'@
                                Code = @'
# Das Modul registriert "buckets:" als PSDrive für dateisystemähnliche Navigation
Get-PSDrive -Name buckets
'@
                            }
                        )
                    }
                    @{
                        Name = "05-nested"
                        Title = "Verschachtelte Buckets"
                        Lessons = @(
                            @{
                                Key = "01-create-nested"
                                Title = "Verschachtelte Buckets erstellen"
                                Body = @'
  Bucket-Namen mit Schrägstrichen erzeugen verschachtelte Verzeichnisstrukturen
  auf der Platte. So organisierst du Daten hierarchisch — wie Ordner in
  Ordnern, jede Ebene ein echtes Unterverzeichnis.
'@
                                Code = @'
# Deutsche Städte in einem verschachtelten Pfad: org > eu > de > cities
$deCities = @(
    @{ Name = "Berlin"; Population = 3600000; Country = "DE" }
    @{ Name = "Munich"; Population = 1500000; Country = "DE" }
)
New-BucketObject -InputObject $deCities -Bucket "org/eu/de/cities" -KeyProperty Name -Quiet

# Britische Städte in org/eu/uk/cities
$ukCities = @(
    @{ Name = "London"; Population = 8900000; Country = "UK" }
    @{ Name = "Manchester"; Population = 550000; Country = "UK" }
)
$ukCities | fill -Bucket "org/eu/uk/cities" -KeyProperty Name -Quiet

# US-Städte in org/us/cities
$usCities = @(
    @{ Name = "New York"; Population = 8300000; Country = "US" }
)
$usCities | fill -Bucket "org/us/cities" -KeyProperty Name -Quiet

# Abteilungen unter org/eu/de/depts — anderer Entitätstyp in gleicher Hierarchie
$deDepts = @(
    @{ Dept = "Engineering"; Lead = "Alice" }
    @{ Dept = "Marketing"; Lead = "Bob" }
)
$deDepts | fill -Bucket "org/eu/de/depts" -KeyProperty Dept -Quiet
# Zeige die vollständige Hierarchie als Baum an
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
                                Title = "Erzeugen und füllen"
                                Body = @'
  Buckets ist für die Pipeline-Nutzung konzipiert. Die meisten Cmdlets
  akzeptieren Pipeline-Eingaben und geben Objekte mit Metadaten aus.
  Hier siehst du, wie sie zusammenwirken.
'@
                                Code = @'
# Erzeuge 5 Objekte direkt und leite jedes in einen Bucket weiter
1..5 | ForEach-Object { @{ Name = "item-$_"; Value = $_ * 10 } } |
    fill -Bucket "dir-listing" -KeyProperty Name -Quiet
# Rufe alle Objekte aus dem neuen Bucket ab
scoop -Bucket "dir-listing"
'@
                            }
                        )
                    }
                    @{
                        Name = "07-tips"
                        Title = "Tipps & Abkürzungen"
                        Lessons = @(
                            @{
                                Key = "01-aliases-reference"
                                Title = "Alias-Referenz"
                                Body = @'
  Drei Aliase werden vom Modul exportiert:

    fill   = New-BucketObject     — Objekte speichern
    scoop  = Get-BucketObject     — Objekte abrufen
    dip    = Get-Bucket            — Buckets auflisten

  Pipeline-Parameterbindung über Metadaten:

    _BucketName   → -Bucket   (bei Set-BucketObject)
    _BucketKey    → -Key      (bei Set-BucketObject)
    _BucketFile   → vollständiger Pfad zur gespeicherten Datei
'@
                            }
                        )
                    }
                )
            }
            @{
                Name = "04-sysadmin"
                Title = "Systemadministration"
                Sections = @(
                    @{
                        Name = "01-server-inventory"
                        Title = "Serverinventar"
                        Lessons = @(
                            @{
                                Key = "01-storing-inventory"
                                Title = "Serverinventar speichern"
                                Body = @'
  Dieser Abschnitt lehrt Buckets von Grund auf mit realen Daten:
  Serverinventar, Vorfallprotokolle, Gesundheitsberichte und
  bucketübergreifende Korrelation. Jede Lektion baut auf der vorherigen
  auf, beginnt einfach und wächst an Komplexität.

  Der Alias fill (Kurzform für New-BucketObject) speichert Objekte in
  benannten Speicherbereichen (Buckets). Hier speichern wir unser
  Serverinventar — jeder Serverdatensatz wird ein Objekt, keyed by
  Hostname über -KeyProperty. Der Schalter -Quiet unterdrückt die
  Zusammenfassungsausgabe.
'@
                                Code = @'
# Definiere ein realistisches Serverinventar als Array von Hashtables
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
# Speichere das Inventar im Bucket "servers", keyed by Hostname
$servers | fill -Bucket servers -KeyProperty Hostname -Quiet
'@
                            }
                        )
                    }
                )
            }
            @{
                Name = "05-funnels"
                Title = "Funnels"
                Sections = @(
                    @{
                        Name = "01-using-funnels"
                        Title = "Funnels verwenden"
                        Lessons = @(
                            @{
                                Key = "01-what-is-a-funnel"
                                Title = "Was ist ein Funnel?"
                                Body = @'
  Ein Funnel ist ein benannter, wiederverwendbarer Filter- oder
  Transformations-Skriptblock, der außerhalb deiner Bucket-Daten
  gespeichert ist. Stell dir einen Funnel wie eine gespeicherte
  Abfrage oder Abbildung vor, die du spontan anwenden kannst.

Bei fill (New-BucketObject): Funnels transformieren Objekte vor
                               dem Speichern. Gib das modifizierte
                               Objekt zurück oder $null zum Überspringen.
  Bei scoop (Get-BucketObject): Funnels transformieren oder filtern
                                Ergebnisse. Gib das Objekt zurück zum
                                Behalten, $null zum Verwerfen.

  Funnels werden als JSON-Dateien in $HOME/.buckets-system/funnels/
  gespeichert, getrennt von deinen Daten. Sie werden für die Dauer
  deiner Sitzung im Arbeitsspeicher zwischengespeichert.
'@
                            }
                            @{
                                Key = "02-creating-a-funnel"
                                Title = "Einen Funnel erstellen"
                                Body = @'
  Verwende New-Funnel, um einen benannten Funnel zu erstellen. Der
  Parameter -Filter erwartet einen Skriptblock, der $_ für das
  Pipeline-Objekt verwendet. Gib das Objekt zurück zum Behalten,
  oder $null zum Verwerfen. Für fill gib ein modifiziertes Objekt
  zurück, um es vor dem Speichern zu transformieren.

  Mit -Description kannst du dokumentieren, was der Funnel tut.
'@
                                SetupCode = @'
$team = @(
    @{ Name="Alice";   Role="Developer"; Level=3; Score=95 }
    @{ Name="Bob";     Role="Designer";  Level=2; Score=72 }
    @{ Name="Carol";   Role="PM";        Level=3; Score=88 }
    @{ Name="Frank";   Role="Developer"; Level=4; Score=91 }
)
$team | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Erstelle einen Funnel, der nach Senior-Mitgliedern filtert (Level > 2)
New-Funnel -Name "seniors" -Filter { $_.Level -gt 2 } -Description "Teammitglieder über Level 2"

# Liste alle Funnels zur Bestätigung auf
Get-Funnel
'@
                            }
                            @{
                                Key = "03-funnel-on-scoop"
                                Title = "Funnels bei scoop (Filter)"
                                Body = @'
  Übergib einen Funnel-Namen an scoops -Funnel-Parameter, um
  Ergebnisse zu filtern. Funnels kombinieren sich mit -Match und
  -Filter — alle Bedingungen werden angewendet.
'@
                                Code = @'
# Verwende den "seniors"-Funnel, um nur Senior-Teammitglieder zu erhalten
scoop -Bucket team -Funnel "seniors"
'@
                            }
                            @{
                                Key = "04-funnel-on-fill"
                                Title = "Funnels bei fill (Transformation)"
                                Body = @'
  Bei fill transformiert ein Funnel jedes Objekt vor dem Speichern.
  Gib das modifizierte Objekt aus dem Skriptblock zurück oder $null,
  um das Objekt zu überspringen.

  Hier fügen wir eine "Seniority"-Eigenschaft basierend auf Level
  hinzu, bevor wir speichern.
'@
                                SetupCode = @'
$newTeam = @(
    @{ Name="Grace";  Role="Developer"; Level=5 }
    @{ Name="Heidi";  Role="Designer";  Level=1 }
    @{ Name="Ivan";   Role="PM";        Level=3 }
)
'@
                                Code = @'
# Erstelle einen Transformations-Funnel, der ein Seniority-Label hinzufügt
New-Funnel -Name "add-seniority" -Filter {
    if ($_.Level -ge 4) { $_.Seniority = "Senior"; $_ }
    elseif ($_.Level -ge 2) { $_.Seniority = "Mid"; $_ }
    else { $null }
}

# Wende den Funnel während fill an
$newTeam | fill -Bucket team -KeyProperty Name -Funnel "add-seniority" -Quiet

# Überprüfe die Ergebnisse — Heidi (Level 1) wurde übersprungen
scoop -Bucket team -Key "Grace", "Heidi", "Ivan"
'@
                            }
                            @{
                                Key = "05-managing-funnels"
                                Title = "Funnels verwalten"
                                Body = @'
  Funnels können mit eigenen Cmdlets verwaltet werden:

    Get-Funnel      — alle Funnels auflisten oder einen bestimmten abrufen
    Set-Funnel      — einen Funnel-Ausdruck oder Beschreibung aktualisieren
    Remove-Funnel   — einen Funnel löschen (unterstützt -WhatIf)

  Funnels bleiben zwischen Sitzungen erhalten — sie leben auf der
  Platte in $HOME/.buckets-system/funnels/. Jeder Funnel ist eine
  einzelne JSON-Datei.
'@
                                SetupCode = @'
New-Funnel -Name "demo-funnel" -Filter { $_.Active -eq $true } -Description "Nur aktive Elemente" -Force
'@
                                Code = @'
# Liste alle Funnels auf (sollte "demo-funnel" enthalten)
Get-Funnel

# Aktualisiere einen vorhandenen Funnel
Set-Funnel -Name "demo-funnel" -Description "Nur aktive Elemente bitte"

# Vorschau der Löschung
Remove-Funnel -Name "demo-funnel" -WhatIf

# Entferne den Funnel tatsächlich
Remove-Funnel -Name "demo-funnel" -Quiet

# Bestätige, dass er weg ist
Get-Funnel -Name "demo-funnel"
'@
                            }
                            @{
                                Key = "06-adhoc-scriptblock"
                                Title = "Ad-hoc-Skriptblock-Funnels"
                                Body = @'
  -Funnel akzeptiert auch direkt einen Skriptblock (ohne einen
  benannten Funnel zu erstellen). Verwende dies für einmalige
  Filter oder Transformationen, die nicht gespeichert werden müssen.
'@
                                SetupCode = @'
$items = @(
    @{ Name="Jack";  Role="Developer"; Level=3 }
    @{ Name="Kate";  Role="Designer";  Level=4 }
    @{ Name="Leo";   Role="PM";        Level=2 }
)
$items | fill -Bucket team -KeyProperty Name -Quiet
'@
                                Code = @'
# Ad-hoc-Filter — kein benannter Funnel nötig
scoop -Bucket team -Funnel { $_.Level -ge 3 }
'@
                            }
                        )
                    }
                )
            }
            @{
                Name = "06-full-course"
                Title = "Vollständiger Kurs"
                Sections = @(
                    @{
                        Name = "01-course-overview"
                        Title = "Kursübersicht"
                        Lessons = @(
                            @{
                                Key = "01-what-you-will-learn"
                                Title = "Was du lernen wirst"
                                Body = @'
  Dieser Kurs führt dich durch alle Funktionen von Buckets — von deinem
  ersten Objekt bis zu fortgeschrittenen Pipelines und Sysadmin-Szenarien.

  Kapitel:
    01 · Einführung — Kernkonzepte und das Dateisystemmodell
    02 · Anfänger — CRUD-Operationen (erstellen, lesen, aktualisieren, löschen)
    03 · Fortgeschritten — kopieren, umbenennen, PSDrive, verschachtelte Buckets, Pipelines
    04 · Systemadministration — reale Szenarien: Inventar, Logs, Vorfälle
    05 · Funnels — benannte wiederverwendbare Filter und Transformationen
    06 · Vollständiger Kurs — komplette Durchlauf aller Funktionen

  Jedes Kapitel ist in Abschnitte unterteilt, und jeder Abschnitt enthält
  fokussierte Lektionen mit Erklärungen und Codebeispielen zum Ausführen.
'@
                            }
                        )
                    }
                )
            }
        )
    }
}
