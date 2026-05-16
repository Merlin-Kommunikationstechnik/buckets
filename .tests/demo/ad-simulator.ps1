#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generates a simulated Active Directory structure in a bucket.
.DESCRIPTION
    Creates a realistic AD-like hierarchy with tens of OUs, hundreds of users,
    groups, and computers stored in nested buckets.

    Structure:
    ad/
    ├── domain (domain object)
    ├── eu/
    │   ├── de/
    │   │   ├── berlin/
    │   │   │   ├── users/
    │   │   │   ├── groups/
    │   │   │   └── computers/
    │   │   ├── munich/
    │   │   │   ├── users/
    │   │   │   ├── groups/
    │   │   │   └── computers/
    │   │   └── frankfurt/
    │   │       ├── users/
    │   │       ├── groups/
    │   │       └── computers/
    │   ├── fr/
    │   │   ├── paris/
    │   │   │   ├── users/
    │   │   │   ├── groups/
    │   │   │   └── computers/
    │   │   └── lyon/
    │   │       ├── users/
    │   │       ├── groups/
    │   │       └── computers/
    │   └── uk/
    │       ├── london/
    │       │   ├── users/
    │       │   ├── groups/
    │       │   └── computers/
    │       └── manchester/
    │           ├── users/
    │           ├── groups/
    │           └── computers/
    ├── us/
    │   ├── east/
    │   │   ├── new-york/
    │   │   ├── washington/
    │   │   └── boston/
    │   ├── west/
    │   │   ├── los-angeles/
    │   │   ├── san-francisco/
    │   │   └── seattle/
    │   └── central/
    │       ├── chicago/
    │       ├── dallas/
    │       └── denver/
    └── apac/
        ├── jp/
        │   ├── tokyo/
        │   └── osaka/
        ├── au/
        │   ├── sydney/
        │   └── melbourne/
        └── sg/
            └── singapore/

    Each location has users, groups, and computers buckets with realistic data.
#>

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../../Buckets" -Force

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Write-InfoBlock {
    param([string]$Mode)
    $mod = Get-Module Buckets
    $pwsh = "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    $os = if ($IsMacOS) { "macOS" } elseif ($IsLinux) { "Linux" } else { "Windows" }
    $sep = "=" * 52
    if ($Mode -eq "top") {
        Write-Host $sep -ForegroundColor DarkGray
        Write-Host " Buckets Module" -NoNewline -ForegroundColor Blue
        Write-Host " v$($mod.Version)" -NoNewline -ForegroundColor Magenta
        Write-Host " AD Simulator" -ForegroundColor DarkGray
        Write-Host " $startTs" -NoNewline -ForegroundColor DarkGray
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host $pwsh -NoNewline -ForegroundColor Cyan
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host $os -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray
    }
    else {
        $elapsed = $sw.ElapsedMilliseconds
        $endTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host $sep -ForegroundColor DarkGray
        Write-Host " Done" -NoNewline -ForegroundColor Blue
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host "${elapsed}ms" -ForegroundColor Magenta
        Write-Host " $endTs" -NoNewline -ForegroundColor DarkGray
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host $pwsh -NoNewline -ForegroundColor Cyan
        Write-Host " · " -NoNewline -ForegroundColor DarkGray
        Write-Host $os -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray
    }
}

Write-InfoBlock -Mode top

$createdBuckets = [System.Collections.ArrayList]::new()
function Use-Bucket {
    param([string]$Bucket)
    $null = $createdBuckets.Add($Bucket)
}

# ============================================================
# Configuration
# ============================================================
$BucketRoot = "ad"
Use-Bucket $BucketRoot
$usersPerLocation = 8
$groupsPerLocation = 3
$computersPerLocation = 5

# ============================================================
# Data generators
# ============================================================
$firstNames = @("Alice","Bob","Charlie","Diana","Erik","Fiona","George","Hannah","Ivan","Julia",
    "Klaus","Laura","Max","Nina","Oscar","Paula","Quinn","Rita","Stefan","Tina",
    "Ulrich","Vera","Walter","Xenia","Yann","Zoe","Adam","Beth","Carl","Dora",
    "Emil","Faye","Gus","Helen","Igor","Jill","Kurt","Lena","Milo","Nora",
    "Otto","Pia","Ralf","Sara","Tom","Urs","Viktoria","Will","Yvonne","Zara")

$lastNames = @("Mueller","Schmidt","Schneider","Fischer","Weber","Meyer","Wagner","Becker",
    "Schulz","Hoffmann","Schaefer","Koch","Bauer","Richter","Klein","Wolf",
    "Schroeder","Neumann","Schwarz","Zimmermann","Braun","Krueger","Hofmann",
    "Hartmann","Lange","Schmitt","Werner","Schmitz","Krause","Meier",
    "Lehmann","Schmid","Huber","Mayer","Kaiser","Fritz","Voigt","Jung","Pohl","Roth")

$departments = @("IT","HR","Finance","Sales","Marketing","Engineering","Operations","Legal","Support","Research")
$jobTitles = @("Administrator","Analyst","Coordinator","Developer","Director","Engineer","Manager","Specialist","Technician","Consultant")
$groupTypes = @("Security","Distribution","Universal","Global","Domain-Local")
$groupRoles = @("Admins","Users","Readers","Editors","Reviewers","Auditors","Support","Developers","Managers","Operators")
$computerOS = @("Windows 11 Pro","Windows 10 Enterprise","Windows Server 2022","Windows Server 2019","macOS 14","Ubuntu 22.04")
$computerTypes = @("Desktop","Laptop","Server","Workstation","Thin-Client","VM")

function New-ADUser {
    param([string]$Location, [int]$Index)
    $fn = $firstNames[(Get-Random -Maximum $firstNames.Count)]
    $ln = $lastNames[(Get-Random -Maximum $lastNames.Count)]
    $sam = "${fn:0:1}.${ln}".ToLowerInvariant()
    @{
        _Id             = "user-${Location}-${Index}"
        sAMAccountName  = $sam
        displayName     = "${fn} ${ln}"
        givenName       = $fn
        sn              = $ln
        userPrincipalName = "${sam}@ad.example.com"
        mail            = "${fn:0:1}.${ln}@example.com"
        department      = $departments[(Get-Random -Maximum $departments.Count)]
        title           = $jobTitles[(Get-Random -Maximum $jobTitles.Count)]
        office          = $Location
        phone           = "+1-555-{0:D4}" -f (Get-Random -Minimum 0 -Maximum 10000)
        enabled         = (Get-Random -Maximum 10) -gt 0
        pwdLastSet      = [DateTimeOffset]::Now.AddDays(-(Get-Random -Maximum 180))
        created         = [DateTimeOffset]::Now.AddDays(-(Get-Random -Minimum 30 -Maximum 2000))
        memberOf        = @()
    }
}

function New-ADGroup {
    param([string]$Location, [int]$Index)
    $role = $groupRoles[(Get-Random -Maximum $groupRoles.Count)]
    $scope = $groupTypes[(Get-Random -Maximum $groupTypes.Count)]
    @{
        _Id             = "group-${Location}-${Index}"
        sAMAccountName  = "GRP-${Location}-${role:0:10}-${Index}".ToUpperInvariant()
        displayName     = "${Location} ${role} Group ${Index}"
        groupType       = $scope
        category        = if ((Get-Random -Maximum 2) -eq 0) { "Security" } else { "Distribution" }
        managedBy       = "user-${Location}-0"
        created         = [DateTimeOffset]::Now.AddDays(-(Get-Random -Minimum 100 -Maximum 2000))
        description     = "${scope} group for ${role} in ${Location}"
        members         = @()
    }
}

function New-ADComputer {
    param([string]$Location, [int]$Index)
    $ctype = $computerTypes[(Get-Random -Maximum $computerTypes.Count)]
    $os = $computerOS[(Get-Random -Maximum $computerOS.Count)]
    @{
        _Id             = "computer-${Location}-${Index}"
        sAMAccountName  = "WS-${Location:0:6}-${Index:D3}`$"
        dnsHostName     = "WS-${Location:0:6}-${Index:D3}.ad.example.com"
        operatingSystem = $os
        osVersion       = "Build $((Get-Random -Minimum 19041 -Maximum 26000))"
        type            = $ctype
        lastLogon       = [DateTimeOffset]::Now.AddDays(-(Get-Random -Maximum 90))
        created         = [DateTimeOffset]::Now.AddDays(-(Get-Random -Minimum 30 -Maximum 1500))
        enabled         = (Get-Random -Maximum 10) -gt 0
        managedBy       = "user-${Location}-0"
        ipv4Address     = "10.$(Get-Random -Minimum 1 -Maximum 254).$(Get-Random -Minimum 1 -Maximum 254).$(Get-Random -Minimum 10 -Maximum 254)"
    }
}

function New-ADOU {
    param([string]$Name, [string]$Parent)
    @{
        _Id             = "ou-${Name}"
        distinguishedName = "OU=${Name},${Parent}"
        description     = "Organizational Unit for ${Name}"
        created         = [DateTimeOffset]::Now.AddDays(-(Get-Random -Minimum 100 -Maximum 3000))
        protected       = (Get-Random -Maximum 5) -eq 0
    }
}

# ============================================================
# AD Structure definition
# ============================================================
$structure = @{
    regions = @(
        @{
            name = "eu"
            description = "European Operations"
            countries = @(
                @{ name = "de"; description = "Germany"; cities = @("berlin","munich","frankfurt") },
                @{ name = "fr"; description = "France"; cities = @("paris","lyon") },
                @{ name = "uk"; description = "United Kingdom"; cities = @("london","manchester") }
            )
        },
        @{
            name = "us"
            description = "United States Operations"
            countries = @(
                @{ name = "east"; description = "East Coast"; cities = @("new-york","washington","boston") },
                @{ name = "west"; description = "West Coast"; cities = @("los-angeles","san-francisco","seattle") },
                @{ name = "central"; description = "Central"; cities = @("chicago","dallas","denver") }
            )
        },
        @{
            name = "apac"
            description = "Asia-Pacific Operations"
            countries = @(
                @{ name = "jp"; description = "Japan"; cities = @("tokyo","osaka") },
                @{ name = "au"; description = "Australia"; cities = @("sydney","melbourne") },
                @{ name = "sg"; description = "Singapore"; cities = @("singapore") }
            )
        }
    )
}

# ============================================================
# Create domain root object
# ============================================================
Write-Host "[1/5] Creating domain root object..." -ForegroundColor Blue
New-BucketObject -Bucket $BucketRoot -InputObject @{
    _Id             = "domain"
    name            = "ad.example.com"
    domain          = "ad.example.com"
    netBIOS         = "AD"
    forest          = "ad.example.com"
    functionalLevel = "Windows2016Forest"
    created         = [DateTimeOffset]::Now.AddDays(-3650)
    dcCount         = 8
    sites           = $structure.regions.Count
} -Key "domain" -Quiet

# ============================================================
# Create region/country/city/location OUs
# ============================================================
Write-Host "[2/5] Creating organizational units..." -ForegroundColor Blue

$ouCount = 0
foreach ($region in $structure.regions) {
    $regionPath = $region.name
    $regionOU = New-ADOU -Name $region.name -Parent "DC=ad,DC=example,DC=com"
    $regionOU.description = $region.description
    New-BucketObject -Bucket "$BucketRoot/$regionPath" -InputObject $regionOU -Key "ou-info" -Quiet
    $ouCount++

    foreach ($country in $region.countries) {
        $countryPath = "$regionPath/$($country.name)"
        $countryOU = New-ADOU -Name $country.name -Parent "OU=$($region.name),DC=ad,DC=example,DC=com"
        $countryOU.description = $country.description
        New-BucketObject -Bucket "$BucketRoot/$countryPath" -InputObject $countryOU -Key "ou-info" -Quiet
        $ouCount++

        foreach ($city in $country.cities) {
            $cityPath = "$countryPath/$city"
            $cityOU = New-ADOU -Name $city -Parent "OU=$($country.name),OU=$($region.name),DC=ad,DC=example,DC=com"
            New-BucketObject -Bucket "$BucketRoot/$cityPath" -InputObject $cityOU -Key "ou-info" -Quiet
            $ouCount++

            # Create location-level OU object
            New-BucketObject -Bucket "$BucketRoot/$cityPath" -InputObject @{
                _Id             = "location"
                name            = $city
                country         = $country.name
                region          = $region.name
                timezone        = switch ($region.name) { "eu" { "UTC+1"; break } "us" { "UTC-5"; break } default { "UTC+8" } }
                address         = "$city, $($country.description)"
                contact         = "admin-$city@example.com"
            } -Key "location-info" -Quiet
            Use-Bucket "$BucketRoot/$cityPath"
        }
        Use-Bucket "$BucketRoot/$countryPath"
    }
    Use-Bucket "$BucketRoot/$regionPath"
}
Write-Host "  Created $ouCount OUs" -ForegroundColor DarkGray

# ============================================================
# Create users, groups, computers per location
# ============================================================
Write-Host "[3/5] Creating users..." -ForegroundColor Blue
$userCount = 0
foreach ($region in $structure.regions) {
    foreach ($country in $region.countries) {
        foreach ($city in $country.cities) {
            $location = "$($region.name)/$($country.name)/$city"
            $users = @()
            for ($i = 0; $i -lt $usersPerLocation; $i++) {
                $u = New-ADUser -Location $location -Index $i
                # Populate memberOf
                $u.memberOf = @(
                    "CN=GRP-${city:0:8}-Admins,OU=$city,OU=$($country.name),OU=$($region.name),DC=ad,DC=example,DC=com",
                    "CN=GRP-${city:0:8}-Users,OU=$city,OU=$($country.name),OU=$($region.name),DC=ad,DC=example,DC=com"
                )
                $users += $u
            }
            $users | New-BucketObject -Bucket "$BucketRoot/$location/users" -KeyProperty _Id -Quiet
            Use-Bucket "$BucketRoot/$location/users"
            $userCount += $users.Count
        }
    }
}
Write-Host "  Created $userCount users" -ForegroundColor DarkGray

Write-Host "[4/5] Creating groups..." -ForegroundColor Blue
$groupCount = 0
foreach ($region in $structure.regions) {
    foreach ($country in $region.countries) {
        foreach ($city in $country.cities) {
            $location = "$($region.name)/$($country.name)/$city"
            $groups = @()
            for ($i = 0; $i -lt $groupsPerLocation; $i++) {
                $g = New-ADGroup -Location $location -Index $i
                # Add random members
                $memberCount = Get-Random -Minimum 1 -Maximum ([Math]::Min(4, $usersPerLocation))
                $g.members = @(1..$memberCount | ForEach-Object { "user-${location}-$(Get-Random -Maximum $usersPerLocation)" })
                $groups += $g
            }
            $groups | New-BucketObject -Bucket "$BucketRoot/$location/groups" -KeyProperty _Id -Quiet
            Use-Bucket "$BucketRoot/$location/groups"
            $groupCount += $groups.Count
        }
    }
}
Write-Host "  Created $groupCount groups" -ForegroundColor DarkGray

Write-Host "[5/5] Creating computers..." -ForegroundColor Blue
$computerCount = 0
foreach ($region in $structure.regions) {
    foreach ($country in $region.countries) {
        foreach ($city in $country.cities) {
            $location = "$($region.name)/$($country.name)/$city"
            $computers = @()
            for ($i = 0; $i -lt $computersPerLocation; $i++) {
                $computers += New-ADComputer -Location $location -Index $i
            }
            $computers | New-BucketObject -Bucket "$BucketRoot/$location/computers" -KeyProperty _Id -Quiet
            Use-Bucket "$BucketRoot/$location/computers"
            $computerCount += $computers.Count
        }
    }
}
Write-Host "  Created $computerCount computers" -ForegroundColor DarkGray

# ============================================================
# Summary
# ============================================================
$totalItems = $userCount + $groupCount + $computerCount + $ouCount + 2

Write-Host "  Regions:           $($structure.regions.Count)" -ForegroundColor DarkGray
Write-Host "  OUs:               $ouCount" -ForegroundColor DarkGray
Write-Host "  Users:             $userCount" -ForegroundColor DarkGray
Write-Host "  Groups:            $groupCount" -ForegroundColor DarkGray
Write-Host "  Computers:         $computerCount" -ForegroundColor DarkGray
Write-Host "  Total objects:     $totalItems" -ForegroundColor DarkGray

Write-InfoBlock -Mode bottom

Write-Host "`n[Bucket Tree]" -ForegroundColor Blue
Get-Bucket -Tree -Name $BucketRoot

Write-Host "`n[Sample Queries]" -ForegroundColor Blue
Write-Host "  Users in berlin:" -ForegroundColor DarkGray
Write-Host "    > Get-BucketObject -Bucket 'ad/eu/de/berlin/users' | Select-Object displayName, department, title -First 3" -ForegroundColor Cyan
Get-BucketObject -Bucket "ad/eu/de/berlin/users" | Select-Object displayName, department, title -First 3 | Format-Table

Write-Host "  Groups in london:" -ForegroundColor DarkGray
Write-Host "    > Get-BucketObject -Bucket 'ad/eu/uk/london/groups' | Select-Object displayName, groupType, category" -ForegroundColor Cyan
Get-BucketObject -Bucket "ad/eu/uk/london/groups" | Select-Object displayName, groupType, category | Format-Table

Write-Host "  Computers in tokyo:" -ForegroundColor DarkGray
Write-Host "    > Get-BucketObject -Bucket 'ad/apac/jp/tokyo/computers' | Select-Object sAMAccountName, operatingSystem, type" -ForegroundColor Cyan
Get-BucketObject -Bucket "ad/apac/jp/tokyo/computers" | Select-Object sAMAccountName, operatingSystem, type | Format-Table

Write-Host "`n  All users across all locations:" -ForegroundColor DarkGray
Write-Host "    > Get-BucketObject -Bucket 'ad/*/*/users'" -ForegroundColor Cyan
$allUsers = Get-BucketObject -Bucket "ad/*/*/users"
Write-Host "    Total: $($allUsers.Count) users" -ForegroundColor DarkGray

Write-Host "`n  All groups filtered by type 'Security':" -ForegroundColor DarkGray
Write-Host "    > Get-BucketObject -Filter { `$_.groupType -eq 'Security' } -Path '$HOME/.buckets'" -ForegroundColor Cyan
$secGroups = Get-BucketObject -Filter { $_.groupType -eq "Security" } -Path "$HOME/.buckets"
Write-Host "    Total: $($secGroups.Count) security groups" -ForegroundColor DarkGray

Write-Host "`n  Enabled computers running Windows 11:" -ForegroundColor DarkGray
Write-Host "    > Get-BucketObject -Filter { `$_.enabled -and `$_.operatingSystem -like '*Windows 11*' } -Path '$HOME/.buckets'" -ForegroundColor Cyan
$win11 = Get-BucketObject -Filter { $_.enabled -and $_.operatingSystem -like "*Windows 11*" } -Path "$HOME/.buckets"
Write-Host "    Total: $($win11.Count) Windows 11 computers" -ForegroundColor DarkGray

Write-Host "`n  All disabled user accounts:" -ForegroundColor DarkGray
Write-Host "    > Get-BucketObject -Bucket 'ad/*/*/users' | Where-Object { -not `$_.enabled }" -ForegroundColor Cyan
$disabledUsers = Get-BucketObject -Bucket "ad/*/*/users" | Where-Object { -not $_.enabled }
$disabledUsers | Select-Object displayName, sAMAccountName, department | Format-Table
Write-Host "    Total: $($disabledUsers.Count) disabled users" -ForegroundColor DarkGray

Write-Host "`n  Servers (Windows Server OS) across all regions:" -ForegroundColor DarkGray
Write-Host "    > Get-BucketObject -Bucket 'ad/*/*/computers' | Where-Object { `$_.operatingSystem -like '*Server*' -and `$_.enabled }" -ForegroundColor Cyan
$servers = Get-BucketObject -Bucket "ad/*/*/computers" | Where-Object { $_.operatingSystem -like "*Server*" -and $_.enabled }
$servers | Select-Object sAMAccountName, operatingSystem, type | Format-Table
Write-Host "    Total: $($servers.Count) active servers" -ForegroundColor DarkGray

foreach ($bucket in $createdBuckets) {
    Remove-BucketObject -Bucket $bucket -Drop -Force -Confirm:$false -WarningAction SilentlyContinue -Recurse
}

Write-InfoBlock -Mode bottom
