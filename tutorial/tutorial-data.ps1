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
    Binary (.dat) — via -AsBinary. Fast, preserves full .NET type
                    information. Handles complex objects, circular refs.
    JSON    (.json) — default format. Human-readable, portable, editable
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
                Name = "02-quickstart"
                Title = "Quick Start"
                Sections = @(
                    @{
                        Name = "01-old-way"
                        Title = "The Old Way"
                        Lessons = @(
                            @{
                                Key = "01-manual-json"
                                Title = "Manual JSON files — the painful way"
                                Body = @'
  Before Buckets, storing data meant managing files by hand. You would use
  Out-File or ConvertTo-Json to write JSON, then ConvertFrom-Json every time
  you needed the data back. Want to update a single field? Re-read, modify,
  re-write. Want to delete one record? Good luck finding the right file.

  Buckets does all of this for you — automatically. No more manual file
  management, no more parsing JSON by hand, no more tracking filenames.
  Just pipe objects in and out.
'@
                                SetupCode = @'
# Create a temp directory to demonstrate the old, manual way
$oldWayDir = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-tutorial-oldway"
$null = New-Item -ItemType Directory -Path $oldWayDir -Force -ErrorAction SilentlyContinue
'@
                                Code = @'
# The OLD way: manual JSON file management
$user = @{ Name = "Alice"; Role = "admin"; Score = 95 }
$user | ConvertTo-Json | Out-File (Join-Path $oldWayDir "alice.json")

# The OLD way: reading it back
Get-Content (Join-Path $oldWayDir "alice.json") | ConvertFrom-Json

# Clean up
Remove-Item -Path $oldWayDir -Recurse -Force -ErrorAction SilentlyContinue
'@
                            }
                            @{
                                Key = "02-buckets-rescue"
                                Title = "Buckets to the rescue"
                                Body = @'
  With Buckets, the same operation is one line. No files to create, no paths
  to manage, no JSON to parse. Objects go in, objects come out — the module
  handles the filesystem for you.

  Throughout this Quick Start, we will use the three aliases provided by
  the module:

    fill   = New-BucketObject    — store objects
    scoop  = Get-BucketObject    — retrieve objects
    dip    = Get-Bucket           — list buckets

  These are shorter and easier to type during interactive use.
'@
                                Code = @'
# The BUCKETS way: one command, no file management
$user = @{ Name = "Alice"; Role = "admin"; Score = 95 }
$user | fill -Bucket "quickstart" -Key "alice" -Quiet

# Read it back just as easily — no paths, no JSON parsing
scoop -Bucket "quickstart" -Key "alice"
'@
                            }
                        )
                    }
                    @{
                        Name = "02-basic-crud"
                        Title = "Basic CRUD"
                        Lessons = @(
                            @{
                                Key = "01-create"
                                Title = "Create: saving your first objects"
                                Body = @'
  The fill command (New-BucketObject) stores objects into a bucket. A bucket
  is just a directory on disk — no setup needed. Use -Key to give your object
  a name, or -KeyProperty to derive the key from a property value.

  When you pipe multiple objects, Buckets saves each one individually. The
  filename (minus extension) becomes the object's key.
'@
                                SetupCode = @'
# Some users to store in the "team" bucket
$users = @(
    @{ Name = "Alice"; Role = "Developer" }
    @{ Name = "Bob";   Role = "Designer" }
    @{ Name = "Carol"; Role = "PM" }
)
'@
                                Code = @'
# Fill with -KeyProperty: the "Name" value becomes each object's key
$users | fill -Bucket "team" -KeyProperty Name -Quiet

# Confirm the objects were saved — dip shows bucket contents
dip -Name "team"
'@
                            }
                            @{
                                Key = "02-read"
                                Title = "Read: retrieving objects"
                                Body = @'
  The scoop command (Get-BucketObject) retrieves objects. Without -Key, it
  returns everything in the bucket. With -Key, it returns a single object.

  Use -Match to filter by property values, or -Filter for custom script
  block logic. We will explore those in the Beginner chapter.
'@
                                SetupCode = @'
$users = @(
    @{ Name = "Alice"; Role = "Developer"; Score = 95 }
    @{ Name = "Bob";   Role = "Designer";  Score = 72 }
    @{ Name = "Carol"; Role = "PM";        Score = 88 }
)
$users | fill -Bucket "team" -KeyProperty Name -Quiet
'@
                                Code = @'
# Scoop all objects from the team bucket
scoop -Bucket "team"

# Scoop one specific object by key
scoop -Bucket "team" -Key "Alice"
'@
                            }
                            @{
                                Key = "03-update"
                                Title = "Update: modifying stored objects"
                                Body = @'
  Two ways to update an existing object:

  1. Re-save with -Overwrite to replace the entire object (simple but
     replaces all properties).
  2. Use Set-BucketObject for partial updates — only the properties you
     specify change, the rest stay untouched.
'@
                                SetupCode = @'
$users = @(
    @{ Name = "Alice"; Role = "Developer"; Score = 95 }
    @{ Name = "Bob";   Role = "Designer";  Score = 72 }
)
$users | fill -Bucket "team" -KeyProperty Name -Quiet
'@
                                Code = @'
# Method 1: Overwrite the entire object
@{ Name = "Alice"; Role = "Lead"; Score = 99 } |
    fill -Bucket "team" -Key "Alice" -Overwrite -Quiet

# Method 2: Partial update — update Score via pipeline
scoop -Bucket "team" -Key "Bob" | ForEach-Object {
    $_.Score = 100
    $_
} | Set-BucketObject -PassThru

# Check the results
scoop -Bucket "team" -Key "Alice", "Bob"
'@
                            }
                            @{
                                Key = "04-delete"
                                Title = "Delete: removing objects"
                                Body = @'
  Remove-BucketObject (also aliased as spill) removes objects. Always preview
  with -WhatIf before deleting — it shows what would be removed without
  actually deleting anything.

  Use -All to clear an entire bucket, or -Match to delete only objects
  matching specific property values.
'@
                                SetupCode = @'
$users = @(
    @{ Name = "Alice"; Role = "Developer"; Status = "active" }
    @{ Name = "Bob";   Role = "Designer";  Status = "archived" }
    @{ Name = "Carol"; Role = "PM";        Status = "active" }
)
$users | fill -Bucket "team" -KeyProperty Name -Quiet
'@
                                Code = @'
# Preview deletion of a single object
Remove-BucketObject -Bucket "team" -Key "Bob" -WhatIf

# Actually delete it
Remove-BucketObject -Bucket "team" -Key "Bob" -Quiet

# Confirm: Carol and Alice remain, Bob is gone
scoop -Bucket "team"
'@
                            }
                        )
                    }
                )
            }
            @{
                Name = "03-beginner"
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
                                Key = "03-json-default"
                                Title = "JSON format (default)"
                                Body = @'
  By default, Buckets stores objects as human-readable .json files.
  JSON files are editable in any text editor and great for config, logs, or any
  data you want to inspect or diff. Use -AsBinary for full .NET type preservation.
'@
                                SetupCode = @'
# Sample config object for JSON format demo
$alice = @{ Name = "Alice"; Role = "admin"; Score = 95 }
'@
                                Code = @'
# Store as human-readable JSON (.json) — this is the default format
New-BucketObject -InputObject $alice -Bucket config -Key "app-config" -Quiet
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
                Name = "04-advanced"
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
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -Quiet
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
                Name = "05-sysadmin"
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
                Name = "06-funnels"
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
  Use New-Funnel to create a named funnel. The -Transform parameter takes
  a scriptblock that uses $_ for the pipeline object. Return the object
  to keep it (optionally modified), or $null to drop it. For fill,
  return a modified object to transform it before storage.

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
New-Funnel -Name "seniors" -Transform { if ($_.Level -gt 2) { $_ } } -Description "Team members above level 2" -Force

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
New-Funnel -Name "add-seniority" -Transform {
    if ($_.Level -ge 4) { $_.Seniority = "Senior"; $_ }
    elseif ($_.Level -ge 2) { $_.Seniority = "Mid"; $_ }
    else { $null }
} -Force

# Apply the funnel during fill
$newTeam | fill -Bucket team -KeyProperty Name -Funnel "add-seniority" -Quiet

# Check the results — Grace and Ivan have Seniority, Heidi was skipped
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
New-Funnel -Name "demo-funnel" -Transform { if ($_.Active) { $_ } } -Description "Active items only" -Force
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
scoop -Bucket team -Funnel { if ($_.Level -ge 3) { $_ } }
'@
                            }
                        )
                    }
                )
            }
        @{
            Name = "07-expand"
            Title = "Expand"
            Sections = @(
                @{
                    Name = "01-basics"
                    Title = "Basics"
                    Lessons = @(
                        @{
                            Key = "expand-intro"
                            Title = "What is Expand?"
                            Body = @'
  The -Expand switch transforms nested PowerShell objects into filesystem
  directory trees. Each property becomes a file or subdirectory, and each
  array element becomes an indexed entry.

  On save (New-BucketObject -Expand):
    · scalars → leaf files    (.json or .dat)
    · containers → sub-bucket directories
    · arrays → numbered files  (0.json, 1.json, …)

  On retrieval (Get-BucketObject -Expand):
    · sub-buckets → nested properties
    · numbered files → arrays
    · leaf files → scalar values

  The process is fully reversible. What you save with -Expand reconstructs
  identically when you read with -Expand.
'@
                        }
                        @{
                            Key = "simple-hash"
                            Title = "Expanding a simple hashtable"
                            Body = @'
  A flat hashtable saved with -Expand creates one file per property.
  Retrieving with -Expand rebuilds the original hashtable as a PSObject.
'@
                            SetupCode = @'
$config = @{ host = "localhost"; port = 8080; ssl = $true }
'@
                            Code = @'
# Save the hashtable expanded — each property becomes its own file
$config | New-BucketObject -Bucket "expand-demo" -Expand -Quiet

# Show the files on disk
Get-ChildItem (Join-Path (Get-BucketRoot) "expand-demo")

# Retrieve and reconstruct the original object
Get-BucketObject -Bucket "expand-demo" -Expand
'@
                        }
                        @{
                            Key = "hashtable-type"
                            Title = "Hashtable type preservation"
                            Body = @'
  Saving a hashtable with -Expand creates files and subdirectories.
  Retrieving it with -Expand returns a PSCustomObject — not a hashtable.

  Buckets consistently normalizes hashtables to PSCustomObject for
  uniform property access. This happens for binary and JSON storage
  too, even without -Expand.

  If you need a real hashtable, convert it afterward:
    $hash = @{}
    $obj.PSObject.Properties | ForEach-Object { $hash[$_.Name] = $_.Value }
'@
                            SetupCode = @'
$config = @{ host = "localhost"; port = 8080; ssl = $true }
'@
                            Code = @'
# Save with expand
$config | New-BucketObject -Bucket "type-demo" -Expand -Quiet

# Scoop with expand — what type is it?
$r = Get-BucketObject -Bucket "type-demo" -Expand
"Reconstructed type: $($r.GetType().Name)"

# Save without expand (single file)
$config | New-BucketObject -Bucket "type-demo" -Key "raw" -Quiet
$r2 = Get-BucketObject -Bucket "type-demo" -Key "raw"
"Single-file type: $($r2.GetType().Name)"

# Both are PSCustomObject — convert to hashtable if needed
$hash = @{}
$r.PSObject.Properties | ForEach-Object { $hash[$_.Name] = $_.Value }
$hash.GetType().Name
$hash["host"]
'@
                        }
                        @{
                            Key = "nested-hash"
                            Title = "Expanding a nested hashtable"
                            Body = @'
  Nested hashtables become sub-bucket directories. The structure is
  preserved as a directory tree on disk, fully browseable.
'@
                            SetupCode = @'
$config = @{
    server = @{ host = "db01"; port = 5432 }
    logging = @{ level = "debug"; file = "/var/log/app.log" }
}
'@
                            Code = @'
# Each nested hashtable becomes a subdirectory
$config | New-BucketObject -Bucket "expand-nested" -Expand -Quiet

# Browse the directory tree
Get-ChildItem (Join-Path (Get-BucketRoot) "expand-nested") -Recurse

# Retrieve the full nested structure
$r = Get-BucketObject -Bucket "expand-nested" -Expand
"server host : $($r.server.host)"
"logging level : $($r.logging.level)"
'@
                        }
                        @{
                            Key = "expand-retrieve"
                            Title = "Retrieving expanded objects"
                            Body = @'
  Use -Expand on Get-BucketObject (scoop) to reconstruct expanded objects.
  The cmdlet reads the directory structure and rebuilds the original
  nested object — including arrays and nested containers.
'@
                            Code = @'
# Save a nested config for retrieval demo — store first!
@{ app = "myapp"; env = @{ region = "eu-west"; tier = "production" } } |
    New-BucketObject -Bucket "retrieve-demo" -Expand -Quiet

# Without -Expand: returns individual files as separate objects
scoop -Bucket "retrieve-demo"

# With -Expand: reconstructs the full nested structure
scoop -Bucket "retrieve-demo" -Expand
'@
                        }
                    )
                }
                @{
                    Name = "02-arrays"
                    Title = "Arrays"
                    Lessons = @(
                        @{
                            Key = "array-primitives"
                            Title = "Array of primitives"
                            Body = @'
  Arrays saved with -Expand and -Key become numbered files under a
  subdirectory named by the key. Retrieving with -Key and -Expand
  reconstructs the array.
'@
                            SetupCode = @'
$items = @("alpha", "beta", "gamma")
'@
                            Code = @'
# Save the array under key "items" — creates items/0.json, items/1.json, items/2.json
$items | New-BucketObject -Bucket "lists" -Key "items" -Expand -Quiet

# Show the directory structure
Get-ChildItem (Join-Path (Get-BucketRoot) "lists") -Recurse

# Retrieve and reconstruct the array
$r = Get-BucketObject -Bucket "lists" -Key "items" -Expand
"Count: $($r.Count)"
"First: $($r[0])"
'@
                        }
                        @{
                            Key = "array-objects"
                            Title = "Array of objects"
                            Body = @'
  Arrays of hashtables become indexed sub-buckets. Each array element
  gets its own subdirectory with the element's properties as files.
'@
                            SetupCode = @'
$users = @(
    @{ name = "Alice"; role = "admin" }
    @{ name = "Bob"; role = "user" }
)
'@
                            Code = @'
# Save as expanded array under key "users"
$users | New-BucketObject -Bucket "teams" -Key "users" -Expand -Quiet

# Show the directory tree
Get-ChildItem (Join-Path (Get-BucketRoot) "teams") -Recurse

# Retrieve and reconstruct
$r = Get-BucketObject -Bucket "teams" -Key "users" -Expand
"Users: $($r.Count)"
"$($r[0].name) : $($r[0].role)"
"$($r[1].name) : $($r[1].role)"
'@
                        }
                        @{
                            Key = "keyproperty-expand"
                            Title = "Expand with -KeyProperty"
                            Body = @'
  -KeyProperty with -Expand gives each object its own sub-bucket named
  by the property value, with the object's properties stored as files
  inside.
'@
                            SetupCode = @'
$items = @(
    @{ id = "srv-a"; host = "web01"; port = 443 }
    @{ id = "srv-b"; host = "web02"; port = 443 }
)
'@
                            Code = @'
# Each item goes into its own sub-bucket keyed by "id"
$items | New-BucketObject -Bucket "services" -KeyProperty "id" -Expand -Quiet

# Show the structure
Get-ChildItem (Join-Path (Get-BucketRoot) "services") -Recurse

# Retrieve one by its key
Get-BucketObject -Bucket "services" -Key "srv-a" -Expand
'@
                        }
                    )
                }
                @{
                    Name = "03-advanced"
                    Title = "Advanced"
                    Lessons = @(
                        @{
                            Key = "expand-depth"
                            Title = "Controlling recursion depth"
                            Body = @'
  -ExpandDepth limits how many levels of nesting are expanded into
  sub-buckets. At the depth limit, containers are serialized as files
  instead of being expanded further. This prevents explosion of
  deeply nested structures.
'@
                            SetupCode = @'
$config = @{
    level1 = @{
        level2 = @{ leaf = "deep" }
    }
}
'@
                            Code = @'
# With -ExpandDepth 1, only level1 becomes a sub-bucket
# level2 is stored as a file instead of expanding further
$config | New-BucketObject -Bucket "depth-demo" -Expand -ExpandDepth 1 -Quiet

# Show the filesystem — level1/ contains level2.json, not level2/ subdir
Get-ChildItem (Join-Path (Get-BucketRoot) "depth-demo") -Recurse

# Retrieve level1 — level2 is preserved as a serialized property
$r = Get-BucketObject -Bucket "depth-demo" -Key "level1" -Expand
"level2.leaf = $($r.level2.leaf)"
'@
                        }
                        @{
                            Key = "mixed-types"
                            Title = "Mixed scalar + container properties"
                            Body = @'
  Hashtables with both primitive values and nested containers
  expand correctly — scalars become files, containers become
  subdirectories, and the full structure is reconstructed.
'@
                            SetupCode = @'
$config = @{
    name = "myapp"
    version = 1.0
    config = @{ debug = $true; timeout = 30 }
    ports = @(80, 443)
}
'@
                            Code = @'
# Save with expand — scalars become files, containers become subdirs
$config | New-BucketObject -Bucket "mixed-demo" -Expand -Quiet

# Browse the tree
Get-ChildItem (Join-Path (Get-BucketRoot) "mixed-demo") -Recurse

# Retrieve — everything comes back as a single reconstructed object
$r = Get-BucketObject -Bucket "mixed-demo" -Expand
"$($r.name) v$($r.version)"
"config.debug = $($r.config.debug)"
"ports: $($r.ports -join ', ')"
'@
                        }
                    )
                }
            )
        }
        @{
            Name = "08-full-course"
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
     02 · Quick Start — your first bucket in 60 seconds
     03 · Beginner — CRUD operations (create, read, update, delete)
     04 · Advanced — copy, rename, PSDrive, nested buckets, pipelines
     05 · Sysadmin — real-world scenarios: inventory, logs, incidents
     06 · Funnels — named reusable filters and transforms
     07 · Expand — nested structures into browsable directory trees
     08 · Full Course — complete walkthrough of all features

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
    Binary (.dat) — über -AsBinary. Schnell, bewahrt vollständige .NET-Typ-
                    informationen. Beherrscht komplexe Objekte, zirkuläre Referenzen.
    JSON    (.json) — Standardformat. Lesbar, portabel, in jedem Editor editierbar.
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
                Name = "02-quickstart"
                Title = "Schnellstart"
                Sections = @(
                    @{
                        Name = "01-old-way"
                        Title = "Der alte Weg"
                        Lessons = @(
                            @{
                                Key = "01-manual-json"
                                Title = "Manuelle JSON-Dateien — der mühsame Weg"
                                Body = @'
  Vor Buckets bedeutete Datenspeicherung Dateiverwaltung von Hand. Du musstest
  Out-File oder ConvertTo-Json verwenden, um JSON zu schreiben, und dann jedes
  Mal ConvertFrom-Json, wenn du die Daten brauchtest. Ein Feld aktualisieren?
  Neu einlesen, ändern, neu schreiben. Einen Datensatz löschen? Viel Glück beim
  Finden der richtigen Datei.

  Buckets erledigt das alles automatisch für dich. Keine manuelle
  Dateiverwaltung mehr, kein manuelles JSON-Parsing, kein Verfolgen von
  Dateinamen. Einfach Objekte rein- und rauspipen.
'@
                                SetupCode = @'
# Erstelle ein temporäres Verzeichnis für die alte, manuelle Methode
$oldWayDir = Join-Path ([System.IO.Path]::GetTempPath()) "buckets-tutorial-oldway"
$null = New-Item -ItemType Directory -Path $oldWayDir -Force -ErrorAction SilentlyContinue
'@
                                Code = @'
# Der ALTE Weg: manuelle JSON-Dateiverwaltung
$user = @{ Name = "Alice"; Role = "admin"; Score = 95 }
$user | ConvertTo-Json | Out-File (Join-Path $oldWayDir "alice.json")

# Der ALTE Weg: Rückeinlesen
Get-Content (Join-Path $oldWayDir "alice.json") | ConvertFrom-Json

# Aufräumen
Remove-Item -Path $oldWayDir -Recurse -Force -ErrorAction SilentlyContinue
'@
                            }
                            @{
                                Key = "02-buckets-rescue"
                                Title = "Buckets zur Rettung"
                                Body = @'
  Mit Buckets ist derselbe Vorgang eine Zeile lang. Keine Dateien zu erstellen,
  keine Pfade zu verwalten, kein JSON zu parsen. Objekte rein, Objekte raus —
  das Modul kümmert sich um das Dateisystem.

  In diesem Schnellstart verwenden wir die drei Aliase des Moduls:

    fill   = New-BucketObject    — Objekte speichern
    scoop  = Get-BucketObject    — Objekte abrufen
    dip    = Get-Bucket           — Buckets auflisten

  Sie sind kürzer und leichter zu tippen.
'@
                                Code = @'
# Der BUCKETS-Weg: ein Befehl, keine Dateiverwaltung
$user = @{ Name = "Alice"; Role = "admin"; Score = 95 }
$user | fill -Bucket "quickstart" -Key "alice" -Quiet

# Genauso einfach wieder abrufen — keine Pfade, kein JSON-Parsing
scoop -Bucket "quickstart" -Key "alice"
'@
                            }
                        )
                    }
                    @{
                        Name = "02-basic-crud"
                        Title = "Einfaches CRUD"
                        Lessons = @(
                            @{
                                Key = "01-create"
                                Title = "Erstellen: erste Objekte speichern"
                                Body = @'
  Der fill-Befehl (New-BucketObject) speichert Objekte in einem Bucket.
  Ein Bucket ist einfach ein Verzeichnis auf der Platte — keine Einrichtung
  nötig. Mit -Key gibst du dem Objekt einen Namen, mit -KeyProperty wird
  der Schlüssel aus einem Eigenschaftswert abgeleitet.

  Wenn du mehrere Objekte pipest, speichert Buckets jedes einzelne. Der
  Dateiname (ohne Erweiterung) wird zum Schlüssel des Objekts.
'@
                                SetupCode = @'
# Einige Benutzer zum Speichern im Bucket "team"
$users = @(
    @{ Name = "Alice"; Role = "Developer" }
    @{ Name = "Bob";   Role = "Designer" }
    @{ Name = "Carol"; Role = "PM" }
)
'@
                                Code = @'
# fill mit -KeyProperty: der "Name"-Wert wird zum Schlüssel jedes Objekts
$users | fill -Bucket "team" -KeyProperty Name -Quiet

# Bestätige, dass die Objekte gespeichert wurden — dip zeigt Bucket-Inhalt
dip -Name "team"
'@
                            }
                            @{
                                Key = "02-read"
                                Title = "Lesen: Objekte abrufen"
                                Body = @'
  Der scoop-Befehl (Get-BucketObject) ruft Objekte ab. Ohne -Key gibt er
  alles im Bucket zurück. Mit -Key ein einzelnes Objekt.

  -Match filtert nach Eigenschaftswerten, -Filter verwendet benutzerdefinierte
  Skriptblöcke. Diese lernst du im Kapitel "Anfänger" kennen.
'@
                                SetupCode = @'
$users = @(
    @{ Name = "Alice"; Role = "Developer"; Score = 95 }
    @{ Name = "Bob";   Role = "Designer";  Score = 72 }
    @{ Name = "Carol"; Role = "PM";        Score = 88 }
)
$users | fill -Bucket "team" -KeyProperty Name -Quiet
'@
                                Code = @'
# Alle Objekte aus dem team-Bucket abrufen
scoop -Bucket "team"

# Ein einzelnes Objekt über seinen Schlüssel abrufen
scoop -Bucket "team" -Key "Alice"
'@
                            }
                            @{
                                Key = "03-update"
                                Title = "Aktualisieren: Objekte ändern"
                                Body = @'
  Zwei Möglichkeiten, ein vorhandenes Objekt zu aktualisieren:

  1. Erneutes Speichern mit -Overwrite ersetzt das gesamte Objekt
     (einfach, aber alle Eigenschaften werden ersetzt).
  2. Set-BucketObject für Teilaktualisierungen — nur die angegebenen
     Eigenschaften ändern sich, der Rest bleibt unberührt.
'@
                                SetupCode = @'
$users = @(
    @{ Name = "Alice"; Role = "Developer"; Score = 95 }
    @{ Name = "Bob";   Role = "Designer";  Score = 72 }
)
$users | fill -Bucket "team" -KeyProperty Name -Quiet
'@
                                Code = @'
# Methode 1: Komplett überschreiben
@{ Name = "Alice"; Role = "Lead"; Score = 99 } |
    fill -Bucket "team" -Key "Alice" -Overwrite -Quiet

# Methode 2: Teilaktualisierung — nur Score ändern
scoop -Bucket "team" -Key "Bob" | ForEach-Object {
    $_.Score = 100
    $_
} | Set-BucketObject -PassThru

# Ergebnisse überprüfen
scoop -Bucket "team" -Key "Alice", "Bob"
'@
                            }
                            @{
                                Key = "04-delete"
                                Title = "Löschen: Objekte entfernen"
                                Body = @'
  Remove-BucketObject (auch als spill bekannt) entfernt Objekte. Verwende
  immer -WhatIf für eine Vorschau vor dem Löschen — es zeigt, was entfernt
  würde, ohne tatsächlich etwas zu löschen.

  -All leert einen gesamten Bucket, -Match löscht nur Objekte mit
  bestimmten Eigenschaftswerten.
'@
                                SetupCode = @'
$users = @(
    @{ Name = "Alice"; Role = "Developer"; Status = "active" }
    @{ Name = "Bob";   Role = "Designer";  Status = "archived" }
    @{ Name = "Carol"; Role = "PM";        Status = "active" }
)
$users | fill -Bucket "team" -KeyProperty Name -Quiet
'@
                                Code = @'
# Vorschau: Löschen eines einzelnen Objekts
Remove-BucketObject -Bucket "team" -Key "Bob" -WhatIf

# Tatsächlich löschen
Remove-BucketObject -Bucket "team" -Key "Bob" -Quiet

# Bestätigen: Carol und Alice sind noch da, Bob ist weg
scoop -Bucket "team"
'@
                            }
                        )
                    }
                )
            }
            @{
                Name = "03-beginner"
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
                                Key = "03-json-default"
                                Title = "JSON-Format (Standard)"
                                Body = @'
  Standardmäßig speichert Buckets Objekte als lesbare .json-Dateien.
  JSON-Dateien sind in jedem Texteditor editierbar. Ideal für Konfigurationen,
  Logs oder Daten, die du inspizieren oder diffen möchtest. -AsBinary aktiviert das binäre Format.
'@
                                SetupCode = @'
# Beispiel-Konfigurationsobjekt für die JSON-Format-Demo
$alice = @{ Name = "Alice"; Role = "admin"; Score = 95 }
'@
                                Code = @'
# Speichere als lesbares JSON (.json) — das Standardformat
New-BucketObject -InputObject $alice -Bucket config -Key "app-config" -Quiet
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
                Name = "04-advanced"
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
@{ Host = "local"; Port = 5432 } | fill -Bucket config -Key "app-config" -Quiet
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
                Name = "05-sysadmin"
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
                Name = "06-funnels"
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
  Parameter -Transform erwartet einen Skriptblock, der $_ für das
  Pipeline-Objekt verwendet. Gib das Objekt zurück zum Behalten
  (optional modifiziert), oder $null zum Verwerfen. Für fill gib ein
  modifiziertes Objekt zurück, um es vor dem Speichern zu transformieren.

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
New-Funnel -Name "seniors" -Transform { if ($_.Level -gt 2) { $_ } } -Description "Teammitglieder über Level 2" -Force

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
New-Funnel -Name "add-seniority" -Transform {
    if ($_.Level -ge 4) { $_.Seniority = "Senior"; $_ }
    elseif ($_.Level -ge 2) { $_.Seniority = "Mid"; $_ }
    else { $null }
} -Force

# Wende den Funnel während fill an
$newTeam | fill -Bucket team -KeyProperty Name -Funnel "add-seniority" -Quiet

# Überprüfe die Ergebnisse — Grace und Ivan haben Seniority, Heidi wurde übersprungen
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
New-Funnel -Name "demo-funnel" -Transform { if ($_.Active) { $_ } } -Description "Nur aktive Elemente" -Force
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
scoop -Bucket team -Funnel { if ($_.Level -ge 3) { $_ } }
'@
                            }
                        )
                    }
                )
            }
        @{
            Name = "07-expand"
            Title = "Expand"
            Sections = @(
                @{
                    Name = "01-basics"
                    Title = "Grundlagen"
                    Lessons = @(
                        @{
                            Key = "expand-intro"
                            Title = "Was ist Expand?"
                            Body = @'
  Der -Expand-Schalter verwandelt verschachtelte PowerShell-Objekte in
  Verzeichnisbäume im Dateisystem. Jede Eigenschaft wird zu einer Datei
  oder einem Unterverzeichnis, jedes Array-Element zu einem nummerierten
  Eintrag.

  Beim Speichern (New-BucketObject -Expand):
    · Skalare → Blattdateien    (.json oder .dat)
    · Container → Unterverzeichnisse
    · Arrays → nummerierte Dateien  (0.json, 1.json, …)

  Beim Abrufen (Get-BucketObject -Expand):
    · Unterverzeichnisse → verschachtelte Eigenschaften
    · nummerierte Dateien → Arrays
    · Blattdateien → Skalarwerte

  Der Vorgang ist vollständig umkehrbar. Was mit -Expand gespeichert
  wird, wird beim Lesen mit -Expand identisch rekonstruiert.
'@
                        }
                        @{
                            Key = "simple-hash"
                            Title = "Eine einfache Hashtable expandieren"
                            Body = @'
  Eine flache Hashtable, die mit -Expand gespeichert wird, erstellt
  eine Datei pro Eigenschaft. Das Abrufen mit -Expand baut die
  ursprüngliche Hashtable als PSObject wieder auf.
'@
                            SetupCode = @'
$config = @{ host = "localhost"; port = 8080; ssl = $true }
'@
                            Code = @'
# Die Hashtable expandiert speichern — jede Eigenschaft wird eigene Datei
$config | New-BucketObject -Bucket "expand-demo" -Expand -Quiet

# Die Dateien auf der Platte anzeigen
Get-ChildItem (Join-Path (Get-BucketRoot) "expand-demo")

# Das ursprüngliche Objekt abrufen und rekonstruieren
Get-BucketObject -Bucket "expand-demo" -Expand
'@
                        }
                        @{
                            Key = "hashtable-type"
                            Title = "Hashtable-Typ bewahren"
                            Body = @'
  Wenn du eine Hashtable mit -Expand speicherst und mit -Expand
  abrufst, erhältst du ein PSCustomObject zurück — keine Hashtable.
  Das ist Absicht: Buckets normalisiert strukturierte Daten zu
  PSCustomObject für einheitlichen Eigenschaftszugriff.

  Dieselbe Normalisierung geschieht auch ohne -Expand. Eine Hashtable,
  die als einzelne Datei gespeichert wurde (binär oder JSON), wird
  ebenfalls als PSCustomObject zurückgegeben.

  Falls du eine echte Hashtable benötigst, konvertiere sie manuell:
    $hash = @{}
    $obj.PSObject.Properties | ForEach-Object { $hash[$_.Name] = $_.Value }
'@
                            SetupCode = @'
$config = @{ host = "localhost"; port = 8080; ssl = $true }
'@
                            Code = @'
# Mit Expand speichern
$config | New-BucketObject -Bucket "type-demo" -Expand -Quiet

# Mit Expand abrufen — welcher Typ?
$r = Get-BucketObject -Bucket "type-demo" -Expand
"Rekonstruierter Typ: $($r.GetType().Name)"

# Ohne Expand speichern (einzelne Datei)
$config | New-BucketObject -Bucket "type-demo" -Key "raw" -Quiet
$r2 = Get-BucketObject -Bucket "type-demo" -Key "raw"
"Einzeldatei-Typ: $($r2.GetType().Name)"

# Beide sind PSCustomObject — bei Bedarf in Hashtable umwandeln
$hash = @{}
$r.PSObject.Properties | ForEach-Object { $hash[$_.Name] = $_.Value }
$hash.GetType().Name
$hash["host"]
'@
                        }
                        @{
                            Key = "nested-hash"
                            Title = "Verschachtelte Hashtable expandieren"
                            Body = @'
  Verschachtelte Hashtables werden zu Unterverzeichnissen. Die Struktur
  bleibt als durchsuchbarer Verzeichnisbaum erhalten.
'@
                            SetupCode = @'
$config = @{
    server = @{ host = "db01"; port = 5432 }
    logging = @{ level = "debug"; file = "/var/log/app.log" }
}
'@
                            Code = @'
# Jede verschachtelte Hashtable wird zum Unterverzeichnis
$config | New-BucketObject -Bucket "expand-nested" -Expand -Quiet

# Den Verzeichnisbaum durchsuchen
Get-ChildItem (Join-Path (Get-BucketRoot) "expand-nested") -Recurse

# Die vollständige Struktur abrufen
$r = Get-BucketObject -Bucket "expand-nested" -Expand
"Server Host: $($r.server.host)"
"Logging Level: $($r.logging.level)"
'@
                        }
                        @{
                            Key = "expand-retrieve"
                            Title = "Expandierte Objekte abrufen"
                            Body = @'
  Verwende -Expand bei Get-BucketObject (scoop), um expandierte Objekte
  zu rekonstruieren. Das Cmdlet liest die Verzeichnisstruktur und baut
  das ursprüngliche Objekt wieder auf — einschließlich Arrays und
  verschachtelter Container.
'@
                            Code = @'
# Eine verschachtelte Konfiguration für die Abruf-Demo speichern — zuerst speichern!
@{ app = "myapp"; env = @{ region = "eu-west"; tier = "production" } } |
    New-BucketObject -Bucket "retrieve-demo" -Expand -Quiet

# Ohne -Expand: einzelne Dateien als separate Objekte
scoop -Bucket "retrieve-demo"

# Mit -Expand: vollständige verschachtelte Struktur
scoop -Bucket "retrieve-demo" -Expand
'@
                        }
                    )
                }
                @{
                    Name = "02-arrays"
                    Title = "Arrays"
                    Lessons = @(
                        @{
                            Key = "array-primitives"
                            Title = "Array von primitiven Werten"
                            Body = @'
  Arrays, die mit -Expand und -Key gespeichert werden, werden zu
  nummerierten Dateien in einem Unterverzeichnis. Der Abruf mit
  -Key und -Expand rekonstruiert das Array.
'@
                            SetupCode = @'
$items = @("alpha", "beta", "gamma")
'@
                            Code = @'
# Das Array unter dem Schlüssel "items" speichern
$items | New-BucketObject -Bucket "lists" -Key "items" -Expand -Quiet

# Die Verzeichnisstruktur anzeigen
Get-ChildItem (Join-Path (Get-BucketRoot) "lists") -Recurse

# Das Array abrufen und rekonstruieren
$r = Get-BucketObject -Bucket "lists" -Key "items" -Expand
"Anzahl: $($r.Count)"
"Erstes: $($r[0])"
'@
                        }
                        @{
                            Key = "array-objects"
                            Title = "Array von Objekten"
                            Body = @'
  Arrays von Hashtables werden zu indizierten Unterverzeichnissen.
  Jedes Array-Element erhält sein eigenes Verzeichnis mit den
  Eigenschaften als Dateien.
'@
                            SetupCode = @'
$users = @(
    @{ name = "Alice"; role = "admin" }
    @{ name = "Bob"; role = "user" }
)
'@
                            Code = @'
# Als expandiertes Array unter dem Schlüssel "users" speichern
$users | New-BucketObject -Bucket "teams" -Key "users" -Expand -Quiet

# Den Verzeichnisbaum anzeigen
Get-ChildItem (Join-Path (Get-BucketRoot) "teams") -Recurse

# Abrufen und rekonstruieren
$r = Get-BucketObject -Bucket "teams" -Key "users" -Expand
"Benutzer: $($r.Count)"
"$($r[0].name) : $($r[0].role)"
"$($r[1].name) : $($r[1].role)"
'@
                        }
                        @{
                            Key = "keyproperty-expand"
                            Title = "Expand mit -KeyProperty"
                            Body = @'
  -KeyProperty mit -Expand gibt jedem Objekt sein eigenes Unterverzeichnis,
  benannt nach dem Eigenschaftswert. Die Objekteigenschaften werden als
  Dateien im Verzeichnis gespeichert.
'@
                            SetupCode = @'
$items = @(
    @{ id = "srv-a"; host = "web01"; port = 443 }
    @{ id = "srv-b"; host = "web02"; port = 443 }
)
'@
                            Code = @'
# Jedes Objekt erhält sein eigenes Unterverzeichnis, benannt nach "id"
$items | New-BucketObject -Bucket "services" -KeyProperty "id" -Expand -Quiet

# Die Struktur anzeigen
Get-ChildItem (Join-Path (Get-BucketRoot) "services") -Recurse

# Ein Objekt über seinen Schlüssel abrufen
Get-BucketObject -Bucket "services" -Key "srv-a" -Expand
'@
                        }
                    )
                }
                @{
                    Name = "03-advanced"
                    Title = "Fortgeschritten"
                    Lessons = @(
                        @{
                            Key = "expand-depth"
                            Title = "Rekursionstiefe begrenzen"
                            Body = @'
  -ExpandDepth begrenzt die Anzahl der Ebenen, die in Unterverzeichnisse
  expandiert werden. An der Tiefengrenze werden Container als Dateien
  gespeichert, anstatt weiter expandiert zu werden. Das verhindert eine
  Explosion tief verschachtelter Strukturen.
'@
                            SetupCode = @'
$config = @{
    level1 = @{
        level2 = @{ leaf = "deep" }
    }
}
'@
                            Code = @'
# Mit -ExpandDepth 1 wird nur level1 zum Unterverzeichnis
# level2 wird als Datei gespeichert, nicht weiter expandiert
$config | New-BucketObject -Bucket "depth-demo" -Expand -ExpandDepth 1 -Quiet

# Dateisystem anzeigen — level1/ enthält level2.json, nicht level2/ Unterverzeichnis
Get-ChildItem (Join-Path (Get-BucketRoot) "depth-demo") -Recurse

# level1 abrufen — level2 bleibt als serialisierte Eigenschaft erhalten
$r = Get-BucketObject -Bucket "depth-demo" -Key "level1" -Expand
"level2.leaf = $($r.level2.leaf)"
'@
                        }
                        @{
                            Key = "mixed-types"
                            Title = "Gemischte Skalar- und Containereigenschaften"
                            Body = @'
  Hashtables mit sowohl primitiven Werten als auch verschachtelten
  Containern werden korrekt expandiert — Skalare werden zu Dateien,
  Container zu Unterverzeichnissen, und die vollständige Struktur
  wird rekonstruiert.
'@
                            SetupCode = @'
$config = @{
    name = "myapp"
    version = 1.0
    config = @{ debug = $true; timeout = 30 }
    ports = @(80, 443)
}
'@
                            Code = @'
# Mit Expand speichern — Skalare werden Dateien, Container Unterverzeichnisse
$config | New-BucketObject -Bucket "mixed-demo" -Expand -Quiet

# Den Baum durchsuchen
Get-ChildItem (Join-Path (Get-BucketRoot) "mixed-demo") -Recurse

# Abrufen — alles kommt als ein einziges rekonstruiertes Objekt zurück
$r = Get-BucketObject -Bucket "mixed-demo" -Expand
"$($r.name) v$($r.version)"
"config.debug = $($r.config.debug)"
"Ports: $($r.ports -join ', ')"
'@
                        }
                    )
                }
            )
        }
        @{
            Name = "08-full-course"
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
     02 · Schnellstart — dein erster Bucket in 60 Sekunden
     03 · Anfänger — CRUD-Operationen (erstellen, lesen, aktualisieren, löschen)
     04 · Fortgeschritten — kopieren, umbenennen, PSDrive, verschachtelte Buckets, Pipelines
     05 · Systemadministration — reale Szenarien: Inventar, Logs, Vorfälle
     06 · Funnels — benannte wiederverwendbare Filter und Transformationen
     07 · Expand — verschachtelte Strukturen als durchsuchbare Verzeichnisbäume
     08 · Vollständiger Kurs — komplette Durchlauf aller Funktionen

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
