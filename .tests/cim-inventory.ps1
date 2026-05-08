#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Simulates a CIM-based inventory tool storing Windows client/server data in Buckets.
.DESCRIPTION
    Creates a multi-site inventory with ~50 workstations and servers, each storing
    summary details, memory DIMMs, physical disks, volumes, and NICs in nested buckets.
#>

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

# Remove previous run
Remove-Bucket "inventory" -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

$rng = [System.Random]::new()

# --- Data pools ---

$sites = @(
    @{ Name = "nyc"; Subnet = "10.11" }
    @{ Name = "ams"; Subnet = "10.12" }
    @{ Name = "syd"; Subnet = "10.13" }
)

$wsModels = @(
    @{ Model = "Dell OptiPlex 7090";      CPU = "Intel Core i5-11400" }
    @{ Model = "Dell OptiPlex 7490";      CPU = "Intel Core i7-11700" }
    @{ Model = "HP EliteDesk 800 G6";     CPU = "Intel Core i5-10500" }
    @{ Model = "HP EliteDesk 805 G6";     CPU = "AMD Ryzen 5 5600"    }
    @{ Model = "Lenovo ThinkCentre M75s"; CPU = "AMD Ryzen 7 5800"    }
    @{ Model = "Dell OptiPlex 7000";      CPU = "Intel Core i5-12500" }
)

$srvModels = @(
    @{ Model = "Dell PowerEdge R750xs";       CPU = "Intel Xeon Silver 4314"  }
    @{ Model = "HP ProLiant DL380 Gen10";     CPU = "Intel Xeon Gold 5418Y"   }
    @{ Model = "Lenovo ThinkSystem SR650 V3"; CPU = "Intel Xeon Silver 4410Y" }
    @{ Model = "Dell PowerEdge R660xs";       CPU = "Intel Xeon Silver 4314"  }
)

$wsOS = @("Microsoft Windows 11 Pro", "Microsoft Windows 10 Pro")
$srvOS = @("Microsoft Windows Server 2022 Standard", "Microsoft Windows Server 2022 Datacenter",
           "Microsoft Windows Server 2025 Standard", "Microsoft Windows Server 2025 Datacenter")

$wsRAM = @(8192, 16384, 32768)     # per-DIMM: 8GB, 16GB, 32GB sticks
$srvRAM = @(16384, 32768, 65536)   # per-DIMM: 16GB, 32GB, 64GB sticks
$ramSpeeds = @(2666, 2933, 3200, 3600, 4800)

$wsDisks = @(
    @{ Model = "SK hynix BC711 256GB";         SizeGB = 256; Media = "SSD" }
    @{ Model = "SK hynix BC711 512GB";         SizeGB = 512; Media = "SSD" }
    @{ Model = "Samsung PM9A1 256GB";          SizeGB = 256; Media = "SSD" }
    @{ Model = "Samsung PM9A1 512GB";          SizeGB = 512; Media = "SSD" }
    @{ Model = "WDC SN730 256GB";              SizeGB = 256; Media = "SSD" }
    @{ Model = "WDC SN730 512GB";              SizeGB = 512; Media = "SSD" }
)

$srvDisks = @(
    @{ Model = "Samsung PM9A3 480GB";          SizeGB = 480;  Media = "SSD" }
    @{ Model = "Samsung PM9A3 960GB";          SizeGB = 960;  Media = "SSD" }
    @{ Model = "Samsung PM9A3 1.92TB";         SizeGB = 1920; Media = "SSD" }
    @{ Model = "Seagate Exos X20 2TB";         SizeGB = 2000; Media = "HDD" }
    @{ Model = "Seagate Exos X20 4TB";         SizeGB = 4000; Media = "HDD" }
    @{ Model = "WD Gold WD4004FZWX 4TB";       SizeGB = 4000; Media = "HDD" }
    @{ Model = "Toshiba MG10ACA 1TB";          SizeGB = 1000; Media = "HDD" }
)

$nicSpeedsWS  = @("1 Gbps")
$nicSpeedsSrv = @("1 Gbps", "10 Gbps")
$nicModelsWS  = @("Intel Ethernet Connection I219-LM", "Realtek PCIe GbE Family Controller")
$nicModelsSrv = @("Intel X710-DA2 10GbE", "Mellanox ConnectX-4 Lx 10GbE", "Broadcom NetXtreme BCM5720")

$vendors = @("Dell Inc.", "Hewlett-Packard", "Lenovo")

function New-Serial {
    $pools = @(
        { [char](65 + $rng.Next(26)) + [char](65 + $rng.Next(26)) + $rng.Next(100000, 999999) }
        { [char](65 + $rng.Next(26)) + $rng.Next(1000000, 9999999) }
        { $rng.Next(100000000, 999999999).ToString() }
    )
    return & $pools[$rng.Next($pools.Count)]
}

function New-MAC {
    return 1..6 | ForEach-Object { "{0:X2}" -f $rng.Next(0, 256) } | ForEach-Object { if ($_.Length -eq 1) { "0$_" } else { $_ } } | ForEach-Object { if ($_ -eq $null -or $_ -eq "") { "00" } else { $_ } } | ForEach-Object { if ($_.Length -eq 1) { "0$_" } else { $_ } } | ForEach-Object { $_.ToUpper() } | ForEach-Object { if ($_ -match "^[0-9A-F]{2}$") { $_ } else { "00" } } | ForEach-Object { $_ } | ForEach-Object { $_ } | ForEach-Object { $_ } -join ":"
}

function New-MAC2 {
    return (1..6 | ForEach-Object { "{0:X2}" -f $rng.Next(0, 256) }) -join ":"
}

function New-IP {
    param([string]$Subnet)
    return "$Subnet.$($rng.Next(2, 254)).$($rng.Next(2, 254))"
}

# --- Main ---

$deviceCount = 0
$objectCount = 0

foreach ($site in $sites) {
    $wsCount = $rng.Next(13, 16)
    $srvCount = $rng.Next(2, 5)

    foreach ($wsIdx in 1..$wsCount) {
        $deviceCount++
        $hostname = "{0}-WS-{1:D3}" -f $site.Name.ToUpper(), $wsIdx
        $model = $wsModels[$rng.Next($wsModels.Count)]
        $os = $wsOS[$rng.Next($wsOS.Count)]
        $ramSticks = @(2, 4)[$rng.Next(2)]
        $ramPerStick = $wsRAM[$rng.Next($wsRAM.Count)]
        $totalRAM = $ramSticks * $ramPerStick
        $diskCount = @(1, 2)[$rng.Next(2)]
        $volCount = @(1, 2)[$rng.Next(2)]
        $nicCount = 1

        $bucket = "inventory/$($site.Name)/workstations/$hostname"

        # Summary
        New-BucketObject -Bucket $bucket -InputObject ([PSCustomObject]@{
            _Id       = "summary"
            Hostname  = $hostname
            Model     = $model.Model
            Serial    = New-Serial
            Vendor    = $vendors[$rng.Next($vendors.Count)]
            OS        = $os
            CPU       = $model.CPU
            RAM_MB    = $totalRAM
            RAM_Sticks = $ramSticks
            LastBoot  = [DateTime]::Now.AddDays(-$rng.Next(3, 60))
            Site      = $site.Name
            Type      = "Workstation"
        }) -KeyProperty _Id -Quiet
        $objectCount++

        # Memory DIMMs
        $stickSizeLabel = if ($ramPerStick -ge 1024) { "{0}GB" -f ($ramPerStick / 1KB) } else { "{0}MB" -f $ramPerStick }
        # PowerShell arithmetic: 8192 / 1KB = 8, 16384 / 1KB = 16
        $stickSizeGB = $ramPerStick / 1KB
        $stickSizeLabel2 = "{0}GB" -f $stickSizeGB
        1..$ramSticks | ForEach-Object {
            New-BucketObject -Bucket "$bucket/memory" -InputObject ([PSCustomObject]@{
                _Id        = "DIMM-$_"
                BankLabel  = if ($ramSticks -eq 2) { @("A1", "B1")[$_ - 1] } else { @("A1", "A2", "B1", "B2")[$_ - 1] }
                CapacityMB = $ramPerStick
                Capacity   = $stickSizeLabel2
                Speed      = $ramSpeeds[$rng.Next($ramSpeeds.Count)]
                FormFactor = "DIMM"
                Type       = "DDR4"
            }) -KeyProperty _Id -Quiet
            $objectCount++
        }

        # Disks
        1..$diskCount | ForEach-Object {
            $disk = $wsDisks[$rng.Next($wsDisks.Count)]
            New-BucketObject -Bucket "$bucket/disks" -InputObject ([PSCustomObject]@{
                _Id        = "Disk-$_"
                Model      = $disk.Model
                MediaType  = $disk.Media
                SizeGB     = $disk.SizeGB
                Serial     = New-Serial
                Interface  = "NVMe"
                Firmware   = "CL1QF{$rng.Next(3, 7)}"
                Status     = if ($rng.Next(10) -eq 0) { "Predictive Failure" } else { "OK" }
            }) -KeyProperty _Id -Quiet
            $objectCount++
        }

        # Volumes
        $driveLetters = @("C", "D")
        1..$volCount | ForEach-Object {
            $dl = $driveLetters[$_ - 1]
            $totalSize = if ($dl -eq "C") { 237 } else { 475 }
            $freePct = [math]::Round((0.15 + $rng.NextDouble() * 0.55), 2)
            $freeSpace = [math]::Round($totalSize * $freePct, 0)
            New-BucketObject -Bucket "$bucket/volumes" -InputObject ([PSCustomObject]@{
                _Id          = "Volume-$dl"
                DriveLetter  = "$dl`:"
                Label        = if ($dl -eq "C") { "OS" } else { "Data" }
                SizeGB       = $totalSize
                FreeSpaceGB  = $freeSpace
                FreePct      = [math]::Round(($freeSpace / $totalSize) * 100, 0)
                FileSystem   = "NTFS"
                BlockSize    = 4096
            }) -KeyProperty _Id -Quiet
            $objectCount++
        }

        # NICs
        $nicModel = $nicModelsWS[$rng.Next($nicModelsWS.Count)]
        New-BucketObject -Bucket "$bucket/nics" -InputObject ([PSCustomObject]@{
            _Id       = "NIC-1"
            Name      = "Ethernet0"
            Model     = $nicModel
            MAC       = New-MAC2
            IP        = New-IP -Subnet $site.Subnet
            Speed     = $nicSpeedsWS[0]
            DHCP      = $true
            Status    = "Up"
        }) -KeyProperty _Id -Quiet
        $objectCount++
    }

    foreach ($srvIdx in 1..$srvCount) {
        $deviceCount++
        $hostname = "{0}-SRV-{1:D3}" -f $site.Name.ToUpper(), $srvIdx
        $model = $srvModels[$rng.Next($srvModels.Count)]
        $os = $srvOS[$rng.Next($srvOS.Count)]
        $ramSticks = @(4, 8)[$rng.Next(2)]
        $ramPerStick = $srvRAM[$rng.Next($srvRAM.Count)]
        $totalRAM = $ramSticks * $ramPerStick
        $diskCount = $rng.Next(2, 5)
        $volCount = $rng.Next(3, 5)
        $nicCount = @(2, 3)[$rng.Next(2)]

        $bucket = "inventory/$($site.Name)/servers/$hostname"

        # Summary
        New-BucketObject -Bucket $bucket -InputObject ([PSCustomObject]@{
            _Id        = "summary"
            Hostname   = $hostname
            Model      = $model.Model
            Serial     = New-Serial
            Vendor     = $vendors[$rng.Next($vendors.Count)]
            OS         = $os
            CPU        = $model.CPU
            CPU_Count  = @(2, 4)[$rng.Next(2)]
            RAM_MB     = $totalRAM
            RAM_Sticks = $ramSticks
            LastBoot   = [DateTime]::Now.AddDays(-$rng.Next(7, 180))
            Site       = $site.Name
            Type       = "Server"
        }) -KeyProperty _Id -Quiet
        $objectCount++

        # Memory
        $stickSizeGB = $ramPerStick / 1KB
        1..$ramSticks | ForEach-Object {
            New-BucketObject -Bucket "$bucket/memory" -InputObject ([PSCustomObject]@{
                _Id        = "DIMM-$_"
                BankLabel  = if ($ramSticks -eq 4) { @("A1", "A2", "B1", "B2")[$_ - 1] } else { @("A1", "A2", "B1", "B2", "C1", "C2", "D1", "D2")[$_ - 1] }
                CapacityMB = $ramPerStick
                Capacity   = "$stickSizeGB GB"
                Speed      = ($ramSpeeds | Where-Object { $_ -ge 3200 } | Sort-Object { -$_ } | Select-Object -First 1)
                FormFactor = "DIMM"
                Type       = "DDR5"
            }) -KeyProperty _Id -Quiet
            $objectCount++
        }

        # Disks
        1..$diskCount | ForEach-Object {
            $disk = $srvDisks[$rng.Next($srvDisks.Count)]
            New-BucketObject -Bucket "$bucket/disks" -InputObject ([PSCustomObject]@{
                _Id        = "Disk-$_"
                Model      = $disk.Model
                MediaType  = $disk.Media
                SizeGB     = $disk.SizeGB
                Serial     = New-Serial
                Interface  = if ($disk.Media -eq "SSD") { "SAS" } else { "SATA" }
                RPM        = if ($disk.Media -eq "HDD") { @(7200, 10000)[$rng.Next(2)] } else { $null }
                Firmware   = "V{0:D3}" -f $rng.Next(100, 500)
                Status     = "OK"
            }) -KeyProperty _Id -Quiet
            $objectCount++
        }

        # Volumes
        $letters = @("C", "D", "E", "L")
        1..$volCount | ForEach-Object {
            $dl = $letters[$_ - 1]
            $sizeMap = @{ "C" = 237; "D" = 950; "E" = 475; "L" = 1900 }
            $labelMap = @{ "C" = "OS"; "D" = "Data"; "E" = "Logs"; "L" = "Backup" }
            $totalSize = $sizeMap[$dl]
            $freePct = [math]::Round((0.05 + $rng.NextDouble() * 0.45), 2)
            $freeSpace = [math]::Max([math]::Round($totalSize * $freePct, 0), 1)
            New-BucketObject -Bucket "$bucket/volumes" -InputObject ([PSCustomObject]@{
                _Id          = "Volume-$dl"
                DriveLetter  = "$dl`:"
                Label        = $labelMap[$dl]
                SizeGB       = $totalSize
                FreeSpaceGB  = $freeSpace
                FreePct      = [math]::Round(($freeSpace / $totalSize) * 100, 0)
                FileSystem   = "NTFS"
                BlockSize    = 4096
            }) -KeyProperty _Id -Quiet
            $objectCount++
        }

        # NICs
        $teamId = 0
        $teamSlot = 0
        1..$nicCount | ForEach-Object {
            $teamId++
            $speed = $nicSpeedsSrv[$rng.Next($nicSpeedsSrv.Count)]
            $teamSlot++
            if ($nicCount -ge 3 -and $_ -eq 1) {
                $modelName = "Broadcom NetXtreme BCM5720"
                $speed = "1 Gbps"
            }
            else {
                $modelName = $nicModelsSrv[$rng.Next($nicModelsSrv.Count - 1)]
            }
            New-BucketObject -Bucket "$bucket/nics" -InputObject ([PSCustomObject]@{
                _Id       = "NIC-$_"
                Name      = "Ethernet$($teamSlot - 1)"
                Model     = $modelName
                MAC       = New-MAC2
                IP        = New-IP -Subnet $site.Subnet
                Speed     = $speed
                DHCP      = $false
                Status    = if ($rng.Next(20) -eq 0) { "Disconnected" } else { "Up" }
            }) -KeyProperty _Id -Quiet
            $objectCount++
        }
    }
}

Write-Host "Inventory generated:" -ForegroundColor Cyan
Write-Host "  Devices: $deviceCount" -ForegroundColor Magenta
Write-Host "  Objects: $objectCount" -ForegroundColor Magenta
