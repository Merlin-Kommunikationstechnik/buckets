#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generates realistic multi-datacenter sysadmin dataset across 18 nested buckets.
.DESCRIPTION
    Creates a hierarchical bucket structure with ~200+ objects simulating
    a medium-sized infrastructure. All records include cross-bucket reference
    fields (_ServerRef, _GroupRefs, _CertRef, etc.) enabling relationship queries.

    Hierarchy:
      infra/     — servers, services, storage, backups, scheduled,
                    containers, incidents, monitoring
      network/   — vlans, dns, firewall, interfaces
      org/       — users, groups, roles
      security/  — certificates, audit
      ops/       — packages, configs
#>

[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$PassThru
)

if ($Quiet -or $PassThru) {
    function Write-Host { param($Object, [switch]$NoNewline, $ForegroundColor, $BackgroundColor, $Separator) }
}

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$date = [DateTime]::Now

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
        Write-Host " Sysadmin Data" -ForegroundColor DarkGray
        Write-Host " $startTs" -NoNewline -ForegroundColor DarkGray
        Write-Host " * " -NoNewline -ForegroundColor DarkGray
        Write-Host $pwsh -NoNewline -ForegroundColor Cyan
        Write-Host " * " -NoNewline -ForegroundColor DarkGray
        Write-Host $os -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray
    }
    else {
        $elapsed = $sw.ElapsedMilliseconds
        $endTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host $sep -ForegroundColor DarkGray
        Write-Host " Done" -NoNewline -ForegroundColor Blue
        Write-Host " * " -NoNewline -ForegroundColor DarkGray
        Write-Host "${elapsed}ms" -ForegroundColor Magenta
        Write-Host " $endTs" -NoNewline -ForegroundColor DarkGray
        Write-Host " * " -NoNewline -ForegroundColor DarkGray
        Write-Host $pwsh -NoNewline -ForegroundColor Cyan
        Write-Host " * " -NoNewline -ForegroundColor DarkGray
        Write-Host $os -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray
    }
}

if (-not $PassThru) { Write-InfoBlock -Mode top }

# ============================================================
# infra/servers — 18 servers across 2 datacenters
# ============================================================
Write-Host "`n[infra/servers]" -ForegroundColor Blue

$servers = @(
    [PSCustomObject]@{ _Id = "srv-web-01"; Hostname = "srv-web-01"; OS = "Ubuntu 22.04 LTS"; CPU = "Intel Xeon Gold 5418Y @ 2.1GHz x 4"; Cores = 8; Threads = 16; RAM_GB = 32; Disk_GB = 500; IP = "10.0.1.10"; Role = "Web Server"; Location = "dc1-rack-a-01"; Status = "production"; LastBoot = $date.AddDays(-12); Manufacturer = "Dell"; Model = "PowerEdge R750"; Serial = "DL-7X9K1R3"; PurchaseDate = $date.AddDays(-730); WarrantyEnd = $date.AddDays(365); PowerW = 450; UPosition = "U01"; Virtualization = "VMware"; MonitoringProfile = "critical"; InterfaceCount = 4; _CertRef = "cert-web-01" },
    [PSCustomObject]@{ _Id = "srv-web-02"; Hostname = "srv-web-02"; OS = "Ubuntu 22.04 LTS"; CPU = "Intel Xeon Gold 5418Y @ 2.1GHz x 4"; Cores = 8; Threads = 16; RAM_GB = 32; Disk_GB = 500; IP = "10.0.1.11"; Role = "Web Server"; Location = "dc1-rack-a-02"; Status = "production"; LastBoot = $date.AddDays(-8); Manufacturer = "Dell"; Model = "PowerEdge R750"; Serial = "DL-7X9K1R4"; PurchaseDate = $date.AddDays(-730); WarrantyEnd = $date.AddDays(365); PowerW = 450; UPosition = "U02"; Virtualization = "VMware"; MonitoringProfile = "critical"; InterfaceCount = 4 },
    [PSCustomObject]@{ _Id = "srv-db-01"; Hostname = "srv-db-01"; OS = "CentOS 8 Stream"; CPU = "AMD EPYC 7713 64-Core @ 2.0GHz x 2"; Cores = 64; Threads = 128; RAM_GB = 128; Disk_GB = 2000; IP = "10.0.2.10"; Role = "Database"; Location = "dc1-rack-b-01"; Status = "production"; LastBoot = $date.AddDays(-45); Manufacturer = "Supermicro"; Model = "AS-4125GS-TNRT2"; Serial = "SM-9K2L7M1"; PurchaseDate = $date.AddDays(-365); WarrantyEnd = $date.AddDays(730); PowerW = 1200; UPosition = "U05"; Virtualization = "None"; MonitoringProfile = "critical"; InterfaceCount = 6 },
    [PSCustomObject]@{ _Id = "srv-db-02"; Hostname = "srv-db-02"; OS = "CentOS 8 Stream"; CPU = "AMD EPYC 7713 64-Core @ 2.0GHz x 2"; Cores = 64; Threads = 128; RAM_GB = 128; Disk_GB = 2000; IP = "10.0.2.11"; Role = "Database"; Location = "dc2-rack-b-01"; Status = "standby"; LastBoot = $date.AddDays(-45); Manufacturer = "Supermicro"; Model = "AS-4125GS-TNRT2"; Serial = "SM-9K2L7M2"; PurchaseDate = $date.AddDays(-365); WarrantyEnd = $date.AddDays(730); PowerW = 1200; UPosition = "U06"; Virtualization = "None"; MonitoringProfile = "critical"; InterfaceCount = 6 },
    [PSCustomObject]@{ _Id = "srv-cache-01"; Hostname = "srv-cache-01"; OS = "Ubuntu 22.04 LTS"; CPU = "Intel Xeon Silver 4314 @ 2.2GHz x 2"; Cores = 16; Threads = 32; RAM_GB = 64; Disk_GB = 256; IP = "10.0.3.10"; Role = "Redis Cache"; Location = "dc1-rack-c-01"; Status = "production"; LastBoot = $date.AddDays(-3); Manufacturer = "HP"; Model = "ProLiant DL360 Gen11"; Serial = "HP-4B8T2N9"; PurchaseDate = $date.AddDays(-180); WarrantyEnd = $date.AddDays(545); PowerW = 600; UPosition = "U10"; Virtualization = "None"; MonitoringProfile = "standard"; InterfaceCount = 4 },
    [PSCustomObject]@{ _Id = "srv-mail-01"; Hostname = "srv-mail-01"; OS = "Debian 12"; CPU = "Intel Xeon Gold 5418Y @ 2.1GHz x 4"; Cores = 8; Threads = 16; RAM_GB = 16; Disk_GB = 1000; IP = "10.0.4.10"; Role = "Mail Server"; Location = "dc2-rack-a-01"; Status = "production"; LastBoot = $date.AddDays(-21); Manufacturer = "Dell"; Model = "PowerEdge R650"; Serial = "DL-5T3P1K8"; PurchaseDate = $date.AddDays(-540); WarrantyEnd = $date.AddDays(180); PowerW = 350; UPosition = "U15"; Virtualization = "VMware"; MonitoringProfile = "standard"; InterfaceCount = 4; _CertRef = "cert-mail-01" },
    [PSCustomObject]@{ _Id = "srv-dc-01"; Hostname = "srv-dc-01"; OS = "Windows Server 2022"; CPU = "Intel Xeon Gold 5418Y @ 2.1GHz x 4"; Cores = 8; Threads = 16; RAM_GB = 64; Disk_GB = 500; IP = "10.0.10.10"; Role = "Domain Controller"; Location = "dc1-rack-a-10"; Status = "production"; LastBoot = $date.AddDays(-60); Manufacturer = "HP"; Model = "ProLiant DL380 Gen11"; Serial = "HP-8M2N5K1"; PurchaseDate = $date.AddDays(-600); WarrantyEnd = $date.AddDays(180); PowerW = 500; UPosition = "U20"; Virtualization = "Hyper-V"; MonitoringProfile = "critical"; InterfaceCount = 4 },
    [PSCustomObject]@{ _Id = "srv-dc-02"; Hostname = "srv-dc-02"; OS = "Windows Server 2022"; CPU = "Intel Xeon Gold 5418Y @ 2.1GHz x 4"; Cores = 8; Threads = 16; RAM_GB = 64; Disk_GB = 500; IP = "10.0.10.11"; Role = "Domain Controller"; Location = "dc2-rack-a-10"; Status = "production"; LastBoot = $date.AddDays(-60); Manufacturer = "HP"; Model = "ProLiant DL380 Gen11"; Serial = "HP-8M2N5K2"; PurchaseDate = $date.AddDays(-600); WarrantyEnd = $date.AddDays(180); PowerW = 500; UPosition = "U21"; Virtualization = "Hyper-V"; MonitoringProfile = "critical"; InterfaceCount = 4 },
    [PSCustomObject]@{ _Id = "srv-dns-01"; Hostname = "srv-dns-01"; OS = "Ubuntu 22.04 LTS"; CPU = "Intel Xeon Silver 4314 @ 2.2GHz x 2"; Cores = 16; Threads = 32; RAM_GB = 8; Disk_GB = 50; IP = "10.0.11.10"; Role = "DNS/NTP"; Location = "dc1-rack-c-10"; Status = "production"; LastBoot = $date.AddDays(-30); Manufacturer = "Dell"; Model = "PowerEdge R250"; Serial = "DL-2N6T8P3"; PurchaseDate = $date.AddDays(-900); WarrantyEnd = $date.AddDays(-180); PowerW = 200; UPosition = "U30"; Virtualization = "None"; MonitoringProfile = "standard"; InterfaceCount = 2 },
    [PSCustomObject]@{ _Id = "srv-backup-01"; Hostname = "srv-backup-01"; OS = "Ubuntu 22.04 LTS"; CPU = "Intel Xeon Silver 4314 @ 2.2GHz x 4"; Cores = 16; Threads = 32; RAM_GB = 32; Disk_GB = 16000; IP = "10.0.12.10"; Role = "Backup Server"; Location = "dc1-rack-d-01"; Status = "production"; LastBoot = $date.AddDays(-7); Manufacturer = "HP"; Model = "ProLiant DL380 Gen11"; Serial = "HP-8M9K1L4"; PurchaseDate = $date.AddDays(-400); WarrantyEnd = $date.AddDays(330); PowerW = 800; UPosition = "U35"; Virtualization = "None"; MonitoringProfile = "standard"; InterfaceCount = 6 },
    [PSCustomObject]@{ _Id = "srv-lb-01"; Hostname = "srv-lb-01"; OS = "Debian 12"; CPU = "Intel Xeon Silver 4314 @ 2.2GHz x 2"; Cores = 16; Threads = 32; RAM_GB = 16; Disk_GB = 100; IP = "10.0.1.5"; Role = "Load Balancer"; Location = "dc1-rack-a-03"; Status = "production"; LastBoot = $date.AddDays(-20); Manufacturer = "Dell"; Model = "PowerEdge R650"; Serial = "DL-5T3P1K9"; PurchaseDate = $date.AddDays(-300); WarrantyEnd = $date.AddDays(400); PowerW = 350; UPosition = "U03"; Virtualization = "None"; MonitoringProfile = "critical"; InterfaceCount = 6 },
    [PSCustomObject]@{ _Id = "srv-mon-01"; Hostname = "srv-mon-01"; OS = "Ubuntu 22.04 LTS"; CPU = "Intel Xeon Silver 4314 @ 2.2GHz x 4"; Cores = 16; Threads = 32; RAM_GB = 32; Disk_GB = 500; IP = "10.0.5.10"; Role = "Monitoring"; Location = "dc1-rack-c-05"; Status = "production"; LastBoot = $date.AddDays(-5); Manufacturer = "Dell"; Model = "PowerEdge R650"; Serial = "DL-5T3P1L1"; PurchaseDate = $date.AddDays(-200); WarrantyEnd = $date.AddDays(500); PowerW = 350; UPosition = "U12"; Virtualization = "None"; MonitoringProfile = "critical"; InterfaceCount = 4; _CertRef = "cert-mon-01" },
    [PSCustomObject]@{ _Id = "srv-container-01"; Hostname = "srv-container-01"; OS = "Ubuntu 22.04 LTS"; CPU = "AMD EPYC 7713 64-Core @ 2.0GHz x 2"; Cores = 64; Threads = 128; RAM_GB = 256; Disk_GB = 2000; IP = "10.0.6.10"; Role = "Container Host"; Location = "dc2-rack-b-02"; Status = "production"; LastBoot = $date.AddDays(-2); Manufacturer = "Supermicro"; Model = "AS-4125GS-TNRT2"; Serial = "SM-9K2L7M3"; PurchaseDate = $date.AddDays(-150); WarrantyEnd = $date.AddDays(580); PowerW = 1500; UPosition = "U40"; Virtualization = "Docker"; MonitoringProfile = "critical"; InterfaceCount = 6 },
    [PSCustomObject]@{ _Id = "srv-container-02"; Hostname = "srv-container-02"; OS = "Ubuntu 22.04 LTS"; CPU = "AMD EPYC 7713 64-Core @ 2.0GHz x 2"; Cores = 64; Threads = 128; RAM_GB = 256; Disk_GB = 2000; IP = "10.0.6.11"; Role = "Container Host"; Location = "dc2-rack-b-03"; Status = "production"; LastBoot = $date.AddDays(-1); Manufacturer = "Supermicro"; Model = "AS-4125GS-TNRT2"; Serial = "SM-9K2L7M4"; PurchaseDate = $date.AddDays(-150); WarrantyEnd = $date.AddDays(580); PowerW = 1500; UPosition = "U41"; Virtualization = "Docker"; MonitoringProfile = "critical"; InterfaceCount = 6 },
    [PSCustomObject]@{ _Id = "srv-vpn-01"; Hostname = "srv-vpn-01"; OS = "Alpine 3.18"; CPU = "Intel Xeon Silver 4314 @ 2.2GHz x 2"; Cores = 16; Threads = 32; RAM_GB = 4; Disk_GB = 20; IP = "10.0.7.10"; Role = "VPN Gateway"; Location = "dc1-rack-c-15"; Status = "production"; LastBoot = $date.AddDays(-90); Manufacturer = "Dell"; Model = "PowerEdge R250"; Serial = "DL-2N6T8P4"; PurchaseDate = $date.AddDays(-1000); WarrantyEnd = $date.AddDays(-365); PowerW = 200; UPosition = "U15"; Virtualization = "None"; MonitoringProfile = "basic"; InterfaceCount = 2 },
    [PSCustomObject]@{ _Id = "srv-ansible-01"; Hostname = "srv-ansible-01"; OS = "Rocky 9"; CPU = "Intel Xeon Silver 4314 @ 2.2GHz x 2"; Cores = 16; Threads = 32; RAM_GB = 16; Disk_GB = 200; IP = "10.0.8.10"; Role = "Automation"; Location = "dc1-rack-a-05"; Status = "production"; LastBoot = $date.AddDays(-14); Manufacturer = "HP"; Model = "ProLiant DL360 Gen11"; Serial = "HP-4B8T2N1"; PurchaseDate = $date.AddDays(-250); WarrantyEnd = $date.AddDays(450); PowerW = 400; UPosition = "U04"; Virtualization = "None"; MonitoringProfile = "standard"; InterfaceCount = 2 },
    [PSCustomObject]@{ _Id = "srv-log-01"; Hostname = "srv-log-01"; OS = "Debian 12"; CPU = "Intel Xeon Gold 5418Y @ 2.1GHz x 4"; Cores = 8; Threads = 16; RAM_GB = 64; Disk_GB = 2000; IP = "10.0.5.11"; Role = "Log Aggregator"; Location = "dc2-rack-c-01"; Status = "production"; LastBoot = $date.AddDays(-30); Manufacturer = "Dell"; Model = "PowerEdge R750"; Serial = "DL-7X9K1R5"; PurchaseDate = $date.AddDays(-300); WarrantyEnd = $date.AddDays(400); PowerW = 500; UPosition = "U14"; Virtualization = "None"; MonitoringProfile = "standard"; InterfaceCount = 4 },
    [PSCustomObject]@{ _Id = "srv-storage-01"; Hostname = "srv-storage-01"; OS = "FreeBSD 14"; CPU = "Intel Xeon Gold 5418Y @ 2.1GHz x 4"; Cores = 8; Threads = 16; RAM_GB = 64; Disk_GB = 16000; IP = "10.0.12.5"; Role = "Storage Controller"; Location = "dc1-rack-d-02"; Status = "decommissioned"; LastBoot = $date.AddDays(-365); Manufacturer = "HP"; Model = "ProLiant DL380 Gen11"; Serial = "HP-8M9K1L5"; PurchaseDate = $date.AddDays(-1095); WarrantyEnd = $date.AddDays(-365); PowerW = 800; UPosition = "U36"; Virtualization = "None"; MonitoringProfile = "basic"; InterfaceCount = 4; _CertRef = "cert-internal-01" }
)
if (-not $PassThru) { $servers | New-BucketObject -Bucket infra/servers -KeyProperty _Id -Quiet }
Write-Host "  $($servers.Count) server records" -ForegroundColor DarkGray

# ============================================================
# infra/services — 18 service/daemon records
# ============================================================
Write-Host "[infra/services]" -ForegroundColor Blue

$services = @(
    [PSCustomObject]@{ _Id = "svc-httpd"; Name = "httpd"; Server = "srv-web-01"; _ServerRef = "srv-web-01"; Status = "running"; CPU_Pct = 12.5; Mem_MB = 512; Uptime_Days = 45; Restarts = 0; LastCheck = $date.AddMinutes(-5) },
    [PSCustomObject]@{ _Id = "svc-mysqld"; Name = "mysqld"; Server = "srv-db-01"; _ServerRef = "srv-db-01"; Status = "running"; CPU_Pct = 25.0; Mem_MB = 8192; Uptime_Days = 30; Restarts = 1; LastCheck = $date.AddMinutes(-2) },
    [PSCustomObject]@{ _Id = "svc-redis"; Name = "redis-server"; Server = "srv-cache-01"; _ServerRef = "srv-cache-01"; Status = "running"; CPU_Pct = 3.2; Mem_MB = 4096; Uptime_Days = 15; Restarts = 0; LastCheck = $date.AddMinutes(-1) },
    [PSCustomObject]@{ _Id = "svc-postfix"; Name = "postfix"; Server = "srv-mail-01"; _ServerRef = "srv-mail-01"; Status = "running"; CPU_Pct = 5.8; Mem_MB = 128; Uptime_Days = 60; Restarts = 2; LastCheck = $date.AddMinutes(-10) },
    [PSCustomObject]@{ _Id = "svc-named"; Name = "named"; Server = "srv-dns-01"; _ServerRef = "srv-dns-01"; Status = "running"; CPU_Pct = 1.2; Mem_MB = 64; Uptime_Days = 90; Restarts = 0; LastCheck = $date.AddMinutes(-1) },
    [PSCustomObject]@{ _Id = "svc-ntpd"; Name = "ntpd"; Server = "srv-dns-01"; _ServerRef = "srv-dns-01"; Status = "stopped"; CPU_Pct = 0.0; Mem_MB = 0; Uptime_Days = 0; Restarts = 5; LastCheck = $date.AddHours(-2); Error = "Configuration invalid" },
    [PSCustomObject]@{ _Id = "svc-agent"; Name = "osqueryi"; Server = "srv-web-02"; _ServerRef = "srv-web-02"; Status = "running"; CPU_Pct = 0.5; Mem_MB = 32; Uptime_Days = 20; Restarts = 0; LastCheck = $date.AddMinutes(-3) },
    [PSCustomObject]@{ _Id = "svc-backup"; Name = "backup-agent"; Server = "srv-backup-01"; _ServerRef = "srv-backup-01"; Status = "running"; CPU_Pct = 8.0; Mem_MB = 256; Uptime_Days = 7; Restarts = 0; LastCheck = $date.AddMinutes(-15) },
    [PSCustomObject]@{ _Id = "svc-haproxy"; Name = "haproxy"; Server = "srv-lb-01"; _ServerRef = "srv-lb-01"; Status = "running"; CPU_Pct = 15.0; Mem_MB = 256; Uptime_Days = 60; Restarts = 0; LastCheck = $date.AddMinutes(-1) },
    [PSCustomObject]@{ _Id = "svc-prometheus"; Name = "prometheus"; Server = "srv-mon-01"; _ServerRef = "srv-mon-01"; Status = "running"; CPU_Pct = 18.5; Mem_MB = 2048; Uptime_Days = 14; Restarts = 0; LastCheck = $date.AddMinutes(-1) },
    [PSCustomObject]@{ _Id = "svc-grafana"; Name = "grafana"; Server = "srv-mon-01"; _ServerRef = "srv-mon-01"; Status = "running"; CPU_Pct = 6.2; Mem_MB = 512; Uptime_Days = 14; Restarts = 0; LastCheck = $date.AddMinutes(-2) },
    [PSCustomObject]@{ _Id = "svc-dockerd-01"; Name = "docker"; Server = "srv-container-01"; _ServerRef = "srv-container-01"; Status = "running"; CPU_Pct = 22.0; Mem_MB = 4096; Uptime_Days = 5; Restarts = 0; LastCheck = $date.AddMinutes(-1) },
    [PSCustomObject]@{ _Id = "svc-dockerd-02"; Name = "docker"; Server = "srv-container-02"; _ServerRef = "srv-container-02"; Status = "running"; CPU_Pct = 18.0; Mem_MB = 3072; Uptime_Days = 3; Restarts = 0; LastCheck = $date.AddMinutes(-1) },
    [PSCustomObject]@{ _Id = "svc-wireguard"; Name = "wireguard"; Server = "srv-vpn-01"; _ServerRef = "srv-vpn-01"; Status = "running"; CPU_Pct = 2.5; Mem_MB = 16; Uptime_Days = 90; Restarts = 0; LastCheck = $date.AddMinutes(-5) },
    [PSCustomObject]@{ _Id = "svc-ansible"; Name = "ansible-pull"; Server = "srv-ansible-01"; _ServerRef = "srv-ansible-01"; Status = "running"; CPU_Pct = 4.0; Mem_MB = 128; Uptime_Days = 30; Restarts = 3; LastCheck = $date.AddMinutes(-30) },
    [PSCustomObject]@{ _Id = "svc-elasticsearch"; Name = "elasticsearch"; Server = "srv-log-01"; _ServerRef = "srv-log-01"; Status = "running"; CPU_Pct = 45.0; Mem_MB = 16384; Uptime_Days = 10; Restarts = 0; LastCheck = $date.AddMinutes(-1) },
    [PSCustomObject]@{ _Id = "svc-kibana"; Name = "kibana"; Server = "srv-log-01"; _ServerRef = "srv-log-01"; Status = "running"; CPU_Pct = 8.0; Mem_MB = 2048; Uptime_Days = 10; Restarts = 0; LastCheck = $date.AddMinutes(-2) },
    [PSCustomObject]@{ _Id = "svc-nfs"; Name = "nfs-server"; Server = "srv-storage-01"; _ServerRef = "srv-storage-01"; Status = "stopped"; CPU_Pct = 0.0; Mem_MB = 0; Uptime_Days = 0; Restarts = 4; LastCheck = $date.AddDays(-30); Error = "Service decommissioned" }
)
if (-not $PassThru) { $services | New-BucketObject -Bucket infra/services -KeyProperty _Id -Quiet }
Write-Host "  $($services.Count) service records" -ForegroundColor DarkGray

# ============================================================
# infra/storage — 14 disk usage records
# ============================================================
Write-Host "[infra/storage]" -ForegroundColor Blue

$disks = @(
    [PSCustomObject]@{ _Id = "disk-web01-root"; Server = "srv-web-01"; _ServerRef = "srv-web-01"; Filesystem = "/"; Size_GB = 50; Used_GB = 22; Avail_GB = 28; Use_Pct = 44; Mount = "/" },
    [PSCustomObject]@{ _Id = "disk-web01-var"; Server = "srv-web-01"; _ServerRef = "srv-web-01"; Filesystem = "/var"; Size_GB = 100; Used_GB = 67; Avail_GB = 33; Use_Pct = 67; Mount = "/var" },
    [PSCustomObject]@{ _Id = "disk-db01-data"; Server = "srv-db-01"; _ServerRef = "srv-db-01"; Filesystem = "/data"; Size_GB = 2000; Used_GB = 1450; Avail_GB = 550; Use_Pct = 73; Mount = "/data" },
    [PSCustomObject]@{ _Id = "disk-db01-log"; Server = "srv-db-01"; _ServerRef = "srv-db-01"; Filesystem = "/var/log"; Size_GB = 200; Used_GB = 180; Avail_GB = 20; Use_Pct = 90; Mount = "/var/log"; Alert = "CRITICAL" },
    [PSCustomObject]@{ _Id = "disk-cache01-data"; Server = "srv-cache-01"; _ServerRef = "srv-cache-01"; Filesystem = "/data"; Size_GB = 256; Used_GB = 200; Avail_GB = 56; Use_Pct = 78; Mount = "/data"; Alert = "WARNING" },
    [PSCustomObject]@{ _Id = "disk-backup01-backup"; Server = "srv-backup-01"; _ServerRef = "srv-backup-01"; Filesystem = "/backup"; Size_GB = 16000; Used_GB = 8500; Avail_GB = 7500; Use_Pct = 53; Mount = "/backup" },
    [PSCustomObject]@{ _Id = "disk-dc01-c"; Server = "srv-dc-01"; _ServerRef = "srv-dc-01"; Filesystem = "C:"; Size_GB = 100; Used_GB = 65; Avail_GB = 35; Use_Pct = 65; Mount = "C:" },
    [PSCustomObject]@{ _Id = "disk-dc01-d"; Server = "srv-dc-01"; _ServerRef = "srv-dc-01"; Filesystem = "D:"; Size_GB = 400; Used_GB = 320; Avail_GB = 80; Use_Pct = 80; Mount = "D:"; Alert = "WARNING" },
    [PSCustomObject]@{ _Id = "disk-lb01-var"; Server = "srv-lb-01"; _ServerRef = "srv-lb-01"; Filesystem = "/var"; Size_GB = 50; Used_GB = 12; Avail_GB = 38; Use_Pct = 24; Mount = "/var" },
    [PSCustomObject]@{ _Id = "disk-mon01-data"; Server = "srv-mon-01"; _ServerRef = "srv-mon-01"; Filesystem = "/data"; Size_GB = 500; Used_GB = 120; Avail_GB = 380; Use_Pct = 24; Mount = "/data" },
    [PSCustomObject]@{ _Id = "disk-container01-docker"; Server = "srv-container-01"; _ServerRef = "srv-container-01"; Filesystem = "/var/lib/docker"; Size_GB = 2000; Used_GB = 1200; Avail_GB = 800; Use_Pct = 60; Mount = "/var/lib/docker" },
    [PSCustomObject]@{ _Id = "disk-container02-docker"; Server = "srv-container-02"; _ServerRef = "srv-container-02"; Filesystem = "/var/lib/docker"; Size_GB = 2000; Used_GB = 800; Avail_GB = 1200; Use_Pct = 40; Mount = "/var/lib/docker" },
    [PSCustomObject]@{ _Id = "disk-log01-data"; Server = "srv-log-01"; _ServerRef = "srv-log-01"; Filesystem = "/data"; Size_GB = 2000; Used_GB = 1650; Avail_GB = 350; Use_Pct = 83; Mount = "/data"; Alert = "WARNING" },
    [PSCustomObject]@{ _Id = "disk-storage01-export"; Server = "srv-storage-01"; _ServerRef = "srv-storage-01"; Filesystem = "/export"; Size_GB = 8000; Used_GB = 5200; Avail_GB = 2800; Use_Pct = 65; Mount = "/export" }
)
if (-not $PassThru) { $disks | New-BucketObject -Bucket infra/storage -KeyProperty _Id -Quiet }
Write-Host "  $($disks.Count) disk usage records" -ForegroundColor DarkGray

# ============================================================
# infra/backups — 9 backup job records
# ============================================================
Write-Host "[infra/backups]" -ForegroundColor Blue

$backups = @(
    [PSCustomObject]@{ _Id = "bkp-daily-users"; Name = "Daily Users Backup"; Type = "Incremental"; Schedule = "0 2 * * *"; Target = "backup-nas-01:/backups/users"; Retention = "30 days"; LastRun = $date.AddHours(-6); NextRun = $date.AddHours(18); Status = "success"; Size_GB = 45; Duration_Min = 35; _ServerRefs = @("srv-dc-01", "srv-dc-02") },
    [PSCustomObject]@{ _Id = "bkp-weekly-fs"; Name = "Weekly Fileserver"; Type = "Full"; Schedule = "0 1 * * 0"; Target = "backup-nas-01:/backups/fileserver"; Retention = "90 days"; LastRun = $date.AddDays(-2); NextRun = $date.AddDays(5); Status = "success"; Size_GB = 850; Duration_Min = 420; _ServerRefs = @("srv-web-01", "srv-web-02") },
    [PSCustomObject]@{ _Id = "bkp-daily-sql"; Name = "Daily SQL Databases"; Type = "Differential"; Schedule = "0 3 * * *"; Target = "backup-nas-01:/backups/sql"; Retention = "14 days"; LastRun = $date.AddHours(-5); NextRun = $date.AddHours(19); Status = "success"; Size_GB = 120; Duration_Min = 55; _ServerRefs = @("srv-db-01", "srv-db-02") },
    [PSCustomObject]@{ _Id = "bkp-hourly-trans"; Name = "Hourly Transactions"; Type = "Log"; Schedule = "0 * * * *"; Target = "backup-nas-02:/backups/trans"; Retention = "7 days"; LastRun = $date.AddHours(-1); NextRun = $date.AddHours(1); Status = "running"; Size_GB = 2; Duration_Min = 8; _ServerRefs = @("srv-db-01") },
    [PSCustomObject]@{ _Id = "bkp-monthly-arch"; Name = "Monthly Archive"; Type = "Full"; Schedule = "0 0 1 * *"; Target = "backup-tape-01"; Retention = "7 years"; LastRun = $date.AddDays(-25); NextRun = $date.AddDays(5); Status = "success"; Size_GB = 2400; Duration_Min = 1800; _ServerRefs = @() },
    [PSCustomObject]@{ _Id = "bkp-failed-01"; Name = "Daily VM Snapshots"; Type = "Snapshot"; Schedule = "0 4 * * *"; Target = "backup-vsan-01:/snapshots"; Retention = "7 days"; LastRun = $date.AddDays(-1); NextRun = $date.AddHours(5); Status = "failed"; Size_GB = 0; Duration_Min = 0; Error = "ESXi host unreachable"; _ServerRefs = @("srv-web-01", "srv-db-01") },
    [PSCustomObject]@{ _Id = "bkp-containers"; Name = "Container Volume Backup"; Type = "Incremental"; Schedule = "0 3 * * *"; Target = "backup-nas-02:/backups/containers"; Retention = "14 days"; LastRun = $date.AddHours(-12); NextRun = $date.AddHours(12); Status = "success"; Size_GB = 180; Duration_Min = 45; _ServerRefs = @("srv-container-01", "srv-container-02") },
    [PSCustomObject]@{ _Id = "bkp-monitoring"; Name = "Grafana Dashboard Backup"; Type = "Full"; Schedule = "0 4 * * 6"; Target = "backup-nas-01:/backups/monitoring"; Retention = "90 days"; LastRun = $date.AddDays(-1); NextRun = $date.AddDays(5); Status = "success"; Size_GB = 0.5; Duration_Min = 2; _ServerRefs = @("srv-mon-01") },
    [PSCustomObject]@{ _Id = "bkp-configs"; Name = "Ansible Config Sync"; Type = "Log"; Schedule = "0 * * * *"; Target = "backup-nas-02:/backups/configs"; Retention = "30 days"; LastRun = $date.AddMinutes(-15); NextRun = $date.AddMinutes(45); Status = "success"; Size_GB = 0.1; Duration_Min = 1; _ServerRefs = @("srv-ansible-01") }
)
if (-not $PassThru) { $backups | New-BucketObject -Bucket infra/backups -KeyProperty _Id -Quiet }
Write-Host "  $($backups.Count) backup job records" -ForegroundColor DarkGray

# ============================================================
# infra/containers — 8 container specs on container hosts
# ============================================================
Write-Host "[infra/containers]" -ForegroundColor Blue

$containers = @(
    [PSCustomObject]@{ _Id = "ctr-web-01"; Name = "web-frontend"; Image = "nginx:1.25"; Host = "srv-container-01"; _HostRef = "srv-container-01"; Ports = "443:443"; Status = "running"; Restarts = 0; MemLimit_MB = 1024; CPUShares = 512; Created = $date.AddDays(-60); Health = "healthy" },
    [PSCustomObject]@{ _Id = "ctr-web-02"; Name = "web-backend"; Image = "nginx:1.25"; Host = "srv-container-02"; _HostRef = "srv-container-02"; Ports = "80:80"; Status = "running"; Restarts = 0; MemLimit_MB = 1024; CPUShares = 512; Created = $date.AddDays(-60); Health = "healthy" },
    [PSCustomObject]@{ _Id = "ctr-api-01"; Name = "api-gateway"; Image = "envoyproxy/envoy:v1.28"; Host = "srv-container-01"; _HostRef = "srv-container-01"; Ports = "8080:8080"; Status = "running"; Restarts = 2; MemLimit_MB = 2048; CPUShares = 1024; Created = $date.AddDays(-45); Health = "degraded" },
    [PSCustomObject]@{ _Id = "ctr-redis"; Name = "session-cache"; Image = "redis:7-alpine"; Host = "srv-container-02"; _HostRef = "srv-container-02"; Ports = "6379:6379"; Status = "running"; Restarts = 0; MemLimit_MB = 512; CPUShares = 256; Created = $date.AddDays(-30); Health = "healthy" },
    [PSCustomObject]@{ _Id = "ctr-pgsql"; Name = "user-db"; Image = "postgres:16"; Host = "srv-container-01"; _HostRef = "srv-container-01"; Ports = "5432:5432"; Status = "running"; Restarts = 1; MemLimit_MB = 4096; CPUShares = 2048; Created = $date.AddDays(-90); Health = "healthy" },
    [PSCustomObject]@{ _Id = "ctr-prom"; Name = "prometheus-sidecar"; Image = "prom/prometheus:v2.50"; Host = "srv-container-02"; _HostRef = "srv-container-02"; Ports = "9090:9090"; Status = "running"; Restarts = 0; MemLimit_MB = 2048; CPUShares = 1024; Created = $date.AddDays(-14); Health = "healthy" },
    [PSCustomObject]@{ _Id = "ctr-broken"; Name = "old-worker"; Image = "python:3.11-slim"; Host = "srv-container-01"; _HostRef = "srv-container-01"; Ports = ""; Status = "exited"; Restarts = 12; MemLimit_MB = 256; CPUShares = 128; Created = $date.AddDays(-120); Health = "unhealthy" },
    [PSCustomObject]@{ _Id = "ctr-cadvisor"; Name = "cadvisor"; Image = "gcr.io/cadvisor/cadvisor:latest"; Host = "srv-container-01"; _HostRef = "srv-container-01"; Ports = "8085:8085"; Status = "running"; Restarts = 0; MemLimit_MB = 256; CPUShares = 128; Created = $date.AddDays(-7); Health = "healthy" }
)
if (-not $PassThru) { $containers | New-BucketObject -Bucket infra/containers -KeyProperty _Id -Quiet }
Write-Host "  $($containers.Count) container records" -ForegroundColor DarkGray

# ============================================================
# infra/incidents — 8 time-stamped incidents (-AsTimestamp)
# ============================================================
Write-Host "[infra/incidents]" -ForegroundColor Blue

$incidents = @(
    [PSCustomObject]@{ Severity = "CRIT"; Source = "srv-web-01"; Message = "HTTP latency spike to 5000ms"; Status = "resolved"; ResolvedBy = "alice"; _ServerRef = "srv-web-01" },
    [PSCustomObject]@{ Severity = "ERROR"; Source = "srv-db-01"; Message = "Connection pool exhausted on primary"; Status = "resolved"; ResolvedBy = "bob"; _ServerRef = "srv-db-01" },
    [PSCustomObject]@{ Severity = "WARN"; Source = "srv-cache-01"; Message = "Redis memory usage at 92%"; Status = "resolved"; ResolvedBy = "alice"; _ServerRef = "srv-cache-01" },
    [PSCustomObject]@{ Severity = "CRIT"; Source = "srv-db-01"; Message = "Disk /var/log at 90% capacity"; Status = "acknowledged"; ResolvedBy = $null; _ServerRef = "srv-db-01" },
    [PSCustomObject]@{ Severity = "ERROR"; Source = "srv-dns-01"; Message = "ntpd service failure — configuration invalid"; Status = "open"; ResolvedBy = $null; _ServerRef = "srv-dns-01" },
    [PSCustomObject]@{ Severity = "INFO"; Source = "srv-backup-01"; Message = "Weekly backup completed: 2.4 TB archived"; Status = "resolved"; ResolvedBy = "automation"; _ServerRef = "srv-backup-01" },
    [PSCustomObject]@{ Severity = "CRIT"; Source = "srv-container-01"; Message = "Container ctr-broken in crash loop (12 restarts)"; Status = "open"; ResolvedBy = $null; _ServerRef = "srv-container-01" },
    [PSCustomObject]@{ Severity = "WARN"; Source = "srv-log-01"; Message = "Elasticsearch disk watermark reached 83%"; Status = "acknowledged"; ResolvedBy = "grace"; _ServerRef = "srv-log-01" }
)
if (-not $PassThru) { $incidents | New-BucketObject -Bucket infra/incidents -AsTimestamp -Quiet }
Write-Host "  $($incidents.Count) incident records" -ForegroundColor DarkGray

# ============================================================
# infra/monitoring — 10 health check results
# ============================================================
Write-Host "[infra/monitoring]" -ForegroundColor Blue

$monChecks = @(
    [PSCustomObject]@{ _Id = "check-web-01"; Target = "srv-web-01"; _TargetRef = "srv-web-01"; CheckType = "HTTP"; Endpoint = "https://srv-web-01/health"; Status = "pass"; ResponseMs = 120; LastOk = $date.AddMinutes(-1); CheckInterval = 30 },
    [PSCustomObject]@{ _Id = "check-web-02"; Target = "srv-web-02"; _TargetRef = "srv-web-02"; CheckType = "HTTP"; Endpoint = "https://srv-web-02/health"; Status = "pass"; ResponseMs = 95; LastOk = $date.AddMinutes(-1); CheckInterval = 30 },
    [PSCustomObject]@{ _Id = "check-db-01"; Target = "srv-db-01"; _TargetRef = "srv-db-01"; CheckType = "TCP"; Endpoint = "srv-db-01:5432"; Status = "pass"; ResponseMs = 5; LastOk = $date.AddMinutes(-1); CheckInterval = 60 },
    [PSCustomObject]@{ _Id = "check-db-02"; Target = "srv-db-02"; _TargetRef = "srv-db-02"; CheckType = "TCP"; Endpoint = "srv-db-02:5432"; Status = "pass"; ResponseMs = 8; LastOk = $date.AddMinutes(-5); CheckInterval = 60 },
    [PSCustomObject]@{ _Id = "check-lb-01"; Target = "srv-lb-01"; _TargetRef = "srv-lb-01"; CheckType = "HTTP"; Endpoint = "http://srv-lb-01:8080/stats"; Status = "pass"; ResponseMs = 45; LastOk = $date.AddMinutes(-1); CheckInterval = 30 },
    [PSCustomObject]@{ _Id = "check-dns-01"; Target = "srv-dns-01"; _TargetRef = "srv-dns-01"; CheckType = "DNS"; Endpoint = "srv-dns-01:53"; Status = "degraded"; ResponseMs = 320; LastOk = $date.AddHours(-4); CheckInterval = 60; Error = "Query response time > 300ms" },
    [PSCustomObject]@{ _Id = "check-mail-01"; Target = "srv-mail-01"; _TargetRef = "srv-mail-01"; CheckType = "SMTP"; Endpoint = "srv-mail-01:25"; Status = "pass"; ResponseMs = 30; LastOk = $date.AddMinutes(-2); CheckInterval = 120 },
    [PSCustomObject]@{ _Id = "check-container-01"; Target = "srv-container-01"; _TargetRef = "srv-container-01"; CheckType = "Docker"; Endpoint = "unix:///var/run/docker.sock"; Status = "pass"; ResponseMs = 15; LastOk = $date.AddMinutes(-1); CheckInterval = 30 },
    [PSCustomObject]@{ _Id = "check-vpn-01"; Target = "srv-vpn-01"; _TargetRef = "srv-vpn-01"; CheckType = "ICMP"; Endpoint = "10.0.7.10"; Status = "pass"; ResponseMs = 3; LastOk = $date.AddMinutes(-1); CheckInterval = 30 },
    [PSCustomObject]@{ _Id = "check-storage-01"; Target = "srv-storage-01"; _TargetRef = "srv-storage-01"; CheckType = "NFS"; Endpoint = "10.0.12.5:/export"; Status = "fail"; ResponseMs = 0; LastOk = $date.AddDays(-30); CheckInterval = 60; Error = "NFS mount timeout — host decommissioned" }
)
if (-not $PassThru) { $monChecks | New-BucketObject -Bucket infra/monitoring -KeyProperty _Id -Quiet }
Write-Host "  $($monChecks.Count) monitoring check records" -ForegroundColor DarkGray

# ============================================================
# infra/scheduled — 8 cron/scheduled tasks
# ============================================================
Write-Host "[infra/scheduled]" -ForegroundColor Blue

$scheduledTasks = @(
    [PSCustomObject]@{ _Id = "cron-daily-maintenance"; Name = "Daily Maintenance"; User = "root"; Schedule = "0 3 * * *"; Command = "/usr/local/bin/maintenance.sh"; NextRun = $date.AddHours(4); LastRun = $date.AddDays(-1); Status = "active" },
    [PSCustomObject]@{ _Id = "cron-hourly-logs"; Name = "Hourly Log Rotate"; User = "root"; Schedule = "0 * * * *"; Command = "/usr/sbin/logrotate /etc/logrotate.conf"; NextRun = $date.AddHours(1); LastRun = $date.AddHours(-1); Status = "active" },
    [PSCustomObject]@{ _Id = "cron-weekly-updates"; Name = "Weekly Security Updates"; User = "root"; Schedule = "0 4 * * 0"; Command = "/usr/bin/apt update && /usr/bin/apt upgrade -y"; NextRun = $date.AddDays(4); LastRun = $date.AddDays(-3); Status = "active" },
    [PSCustomObject]@{ _Id = "cron-db-vacuum"; Name = "Database Vacuum"; User = "postgres"; Schedule = "0 2 * * *"; Command = "/usr/bin/vacuumdb --all --analyze"; NextRun = $date.AddHours(3); LastRun = $date.AddDays(-1); Status = "active" },
    [PSCustomObject]@{ _Id = "win-daily-backup"; Name = "Windows Backup Job"; User = "SYSTEM"; Schedule = "0 2 * * *"; Command = "wbadmin.exe start backup -backupTarget:D:"; NextRun = $date.AddHours(3); LastRun = $date.AddDays(-1); Status = "active"; Platform = "Windows" },
    [PSCustomObject]@{ _Id = "cron-disabled-old"; Name = "Old Cleanup Script"; User = "admin"; Schedule = "0 5 * * *"; Command = "/home/admin/cleanup.sh"; NextRun = $null; LastRun = $date.AddDays(-90); Status = "disabled" },
    [PSCustomObject]@{ _Id = "cron-container-cleanup"; Name = "Container Image Cleanup"; User = "root"; Schedule = "0 4 * * *"; Command = "/usr/bin/docker image prune -af --filter until=72h"; NextRun = $date.AddHours(5); LastRun = $date.AddDays(-1); Status = "active" },
    [PSCustomObject]@{ _Id = "cron-cert-renew"; Name = "Certificate Renewal Check"; User = "root"; Schedule = "0 6 * * *"; Command = "/usr/local/bin/check-certs.sh --renew"; NextRun = $date.AddHours(6); LastRun = $date.AddDays(-1); Status = "active" }
)
if (-not $PassThru) { $scheduledTasks | New-BucketObject -Bucket infra/scheduled -KeyProperty _Id -Quiet }
Write-Host "  $($scheduledTasks.Count) scheduled task records" -ForegroundColor DarkGray

# ============================================================
# network/vlans — 8 network definitions
# ============================================================
Write-Host "[network/vlans]" -ForegroundColor Blue

$networks = @(
    [PSCustomObject]@{ _Id = "net-dmz"; Name = "DMZ"; Subnet = "10.0.0.0/24"; Gateway = "10.0.0.1"; VLAN = 10; Description = "Public-facing services" },
    [PSCustomObject]@{ _Id = "net-web"; Name = "Web Tier"; Subnet = "10.0.1.0/24"; Gateway = "10.0.1.1"; VLAN = 11; Description = "Web servers and load balancers" },
    [PSCustomObject]@{ _Id = "net-app"; Name = "App Tier"; Subnet = "10.0.2.0/24"; Gateway = "10.0.2.1"; VLAN = 12; Description = "Application and database servers" },
    [PSCustomObject]@{ _Id = "net-data"; Name = "Data Tier"; Subnet = "10.0.3.0/24"; Gateway = "10.0.3.1"; VLAN = 13; Description = "Caching and in-memory data" },
    [PSCustomObject]@{ _Id = "net-mgmt"; Name = "Management"; Subnet = "10.0.10.0/24"; Gateway = "10.0.10.1"; VLAN = 99; Description = "Admin access and domain controllers" },
    [PSCustomObject]@{ _Id = "net-backup"; Name = "Backup"; Subnet = "10.0.12.0/24"; Gateway = "10.0.12.1"; VLAN = 14; Description = "Backup and storage traffic" },
    [PSCustomObject]@{ _Id = "net-container"; Name = "Container Network"; Subnet = "10.0.6.0/24"; Gateway = "10.0.6.1"; VLAN = 20; Description = "Container host interconnect" },
    [PSCustomObject]@{ _Id = "net-observability"; Name = "Observability"; Subnet = "10.0.5.0/24"; Gateway = "10.0.5.1"; VLAN = 15; Description = "Monitoring, logging, metrics" }
)
if (-not $PassThru) { $networks | New-BucketObject -Bucket network/vlans -KeyProperty _Id -Quiet }
Write-Host "  $($networks.Count) VLAN records" -ForegroundColor DarkGray

# ============================================================
# network/interfaces — 10 per-server interface definitions
# ============================================================
Write-Host "[network/interfaces]" -ForegroundColor Blue

$interfaces = @(
    [PSCustomObject]@{ _Id = "if-web-01-bond0"; Server = "srv-web-01"; _ServerRef = "srv-web-01"; Name = "bond0"; IP = "10.0.1.10"; Netmask = "255.255.255.0"; Gateway = "10.0.1.1"; MAC = "00:1a:2b:3c:4d:01"; Speed_Gbps = 10; Duplex = "full"; MTU = 1500 },
    [PSCustomObject]@{ _Id = "if-db-01-bond0"; Server = "srv-db-01"; _ServerRef = "srv-db-01"; Name = "bond0"; IP = "10.0.2.10"; Netmask = "255.255.255.0"; Gateway = "10.0.2.1"; MAC = "00:1a:2b:3c:4d:10"; Speed_Gbps = 25; Duplex = "full"; MTU = 9000 },
    [PSCustomObject]@{ _Id = "if-lb-01-eth0"; Server = "srv-lb-01"; _ServerRef = "srv-lb-01"; Name = "eth0"; IP = "10.0.1.5"; Netmask = "255.255.255.0"; Gateway = "10.0.1.1"; MAC = "00:1a:2b:3c:4d:20"; Speed_Gbps = 10; Duplex = "full"; MTU = 1500 },
    [PSCustomObject]@{ _Id = "if-lb-01-eth1"; Server = "srv-lb-01"; _ServerRef = "srv-lb-01"; Name = "eth1"; IP = "10.0.0.5"; Netmask = "255.255.255.0"; Gateway = $null; MAC = "00:1a:2b:3c:4d:21"; Speed_Gbps = 10; Duplex = "full"; MTU = 1500; Description = "DMZ interface" },
    [PSCustomObject]@{ _Id = "if-mon-01-bond0"; Server = "srv-mon-01"; _ServerRef = "srv-mon-01"; Name = "bond0"; IP = "10.0.5.10"; Netmask = "255.255.255.0"; Gateway = "10.0.5.1"; MAC = "00:1a:2b:3c:4d:30"; Speed_Gbps = 10; Duplex = "full"; MTU = 1500 },
    [PSCustomObject]@{ _Id = "if-container-01-bond0"; Server = "srv-container-01"; _ServerRef = "srv-container-01"; Name = "bond0"; IP = "10.0.6.10"; Netmask = "255.255.255.0"; Gateway = "10.0.6.1"; MAC = "00:1a:2b:3c:4d:40"; Speed_Gbps = 25; Duplex = "full"; MTU = 9000 },
    [PSCustomObject]@{ _Id = "if-container-02-bond0"; Server = "srv-container-02"; _ServerRef = "srv-container-02"; Name = "bond0"; IP = "10.0.6.11"; Netmask = "255.255.255.0"; Gateway = "10.0.6.1"; MAC = "00:1a:2b:3c:4d:41"; Speed_Gbps = 25; Duplex = "full"; MTU = 9000 },
    [PSCustomObject]@{ _Id = "if-vpn-01-eth0"; Server = "srv-vpn-01"; _ServerRef = "srv-vpn-01"; Name = "eth0"; IP = "10.0.7.10"; Netmask = "255.255.255.0"; Gateway = "10.0.7.1"; MAC = "00:1a:2b:3c:4d:50"; Speed_Gbps = 1; Duplex = "full"; MTU = 1500 },
    [PSCustomObject]@{ _Id = "if-vpn-01-wg0"; Server = "srv-vpn-01"; _ServerRef = "srv-vpn-01"; Name = "wg0"; IP = "10.200.0.1"; Netmask = "255.255.255.0"; Gateway = $null; MAC = "virtual"; Speed_Gbps = $null; Duplex = $null; MTU = 1420; Description = "WireGuard tunnel interface" },
    [PSCustomObject]@{ _Id = "if-log-01-bond0"; Server = "srv-log-01"; _ServerRef = "srv-log-01"; Name = "bond0"; IP = "10.0.5.11"; Netmask = "255.255.255.0"; Gateway = "10.0.5.1"; MAC = "00:1a:2b:3c:4d:60"; Speed_Gbps = 25; Duplex = "full"; MTU = 9000 }
)
if (-not $PassThru) { $interfaces | New-BucketObject -Bucket network/interfaces -KeyProperty _Id -Quiet }
Write-Host "  $($interfaces.Count) interface records" -ForegroundColor DarkGray

# ============================================================
# network/dns — 14 DNS records
# ============================================================
Write-Host "[network/dns]" -ForegroundColor Blue

$dnsRecords = @(
    [PSCustomObject]@{ _Id = "dns-a-web-01"; Name = "srv-web-01.example.com"; Type = "A"; Value = "10.0.1.10"; TTL = 3600; Zone = "example.com" },
    [PSCustomObject]@{ _Id = "dns-a-web-02"; Name = "srv-web-02.example.com"; Type = "A"; Value = "10.0.1.11"; TTL = 3600; Zone = "example.com" },
    [PSCustomObject]@{ _Id = "dns-a-db-01"; Name = "srv-db-01.example.com"; Type = "A"; Value = "10.0.2.10"; TTL = 3600; Zone = "example.com" },
    [PSCustomObject]@{ _Id = "dns-cname-www"; Name = "www.example.com"; Type = "CNAME"; Value = "srv-web-01.example.com"; TTL = 300; Zone = "example.com" },
    [PSCustomObject]@{ _Id = "dns-cname-mail"; Name = "mail.example.com"; Type = "CNAME"; Value = "srv-mail-01.example.com"; TTL = 300; Zone = "example.com" },
    [PSCustomObject]@{ _Id = "dns-mx-01"; Name = "example.com"; Type = "MX"; Value = "mail.example.com"; Priority = 10; TTL = 3600; Zone = "example.com" },
    [PSCustomObject]@{ _Id = "dns-mx-02"; Name = "example.com"; Type = "MX"; Value = "mail2.example.com"; Priority = 20; TTL = 3600; Zone = "example.com" },
    [PSCustomObject]@{ _Id = "dns-txt-spf"; Name = "example.com"; Type = "TXT"; Value = "v=spf1 mx -all"; TTL = 3600; Zone = "example.com" },
    [PSCustomObject]@{ _Id = "dns-a-api"; Name = "api.example.com"; Type = "A"; Value = "10.0.1.20"; TTL = 600; Zone = "example.com" },
    [PSCustomObject]@{ _Id = "dns-srv-cal"; Name = "_caldav._tcp.example.com"; Type = "SRV"; Value = "0 443 mail.example.com"; TTL = 3600; Zone = "example.com" },
    [PSCustomObject]@{ _Id = "dns-a-mon-01"; Name = "srv-mon-01.example.com"; Type = "A"; Value = "10.0.5.10"; TTL = 3600; Zone = "example.com" },
    [PSCustomObject]@{ _Id = "dns-a-container-01"; Name = "srv-container-01.example.com"; Type = "A"; Value = "10.0.6.10"; TTL = 3600; Zone = "example.com" },
    [PSCustomObject]@{ _Id = "dns-cname-api"; Name = "api.example.com"; Type = "CNAME"; Value = "srv-lb-01.example.com"; TTL = 300; Zone = "example.com" },
    [PSCustomObject]@{ _Id = "dns-srv-ldap"; Name = "_ldap._tcp.dc.example.com"; Type = "SRV"; Value = "0 389 srv-dc-01.example.com"; TTL = 3600; Zone = "dc.example.com" }
)
if (-not $PassThru) { $dnsRecords | New-BucketObject -Bucket network/dns -KeyProperty _Id -Quiet }
Write-Host "  $($dnsRecords.Count) DNS records" -ForegroundColor DarkGray

# ============================================================
# network/firewall — 9 firewall rules
# ============================================================
Write-Host "[network/firewall]" -ForegroundColor Blue

$firewall = @(
    [PSCustomObject]@{ _Id = "fw-001"; Source = "any"; Dest = "srv-web-01:443"; Port = 443; Protocol = "TCP"; Action = "ALLOW"; Rule = "Allow HTTPS to web servers" },
    [PSCustomObject]@{ _Id = "fw-002"; Source = "10.0.1.0/24"; Dest = "srv-db-01:5432"; Port = 5432; Protocol = "TCP"; Action = "ALLOW"; Rule = "Web to DB" },
    [PSCustomObject]@{ _Id = "fw-003"; Source = "10.0.10.0/24"; Dest = "any"; Port = "22,3389"; Protocol = "TCP"; Action = "ALLOW"; Rule = "Management access" },
    [PSCustomObject]@{ _Id = "fw-004"; Source = "any"; Dest = "any"; Port = "25,587"; Protocol = "SMTP"; Action = "ALLOW"; Rule = "Mail relay" },
    [PSCustomObject]@{ _Id = "fw-005"; Source = "any"; Dest = "any"; Port = "53"; Protocol = "UDP"; Action = "ALLOW"; Rule = "DNS" },
    [PSCustomObject]@{ _Id = "fw-006"; Source = "any"; Dest = "any"; Port = "any"; Protocol = "any"; Action = "DENY"; Rule = "Default deny" },
    [PSCustomObject]@{ _Id = "fw-007"; Source = "10.0.5.0/24"; Dest = "any"; Port = "9090,3000,9100"; Protocol = "TCP"; Action = "ALLOW"; Rule = "Monitoring probes" },
    [PSCustomObject]@{ _Id = "fw-008"; Source = "10.0.6.0/24"; Dest = "any"; Port = "2375,2376"; Protocol = "TCP"; Action = "ALLOW"; Rule = "Container API access" },
    [PSCustomObject]@{ _Id = "fw-009"; Source = "10.200.0.0/24"; Dest = "10.0.2.0/24"; Port = "5432,3306"; Protocol = "TCP"; Action = "ALLOW"; Rule = "VPN tunnel — database access" }
)
if (-not $PassThru) { $firewall | New-BucketObject -Bucket network/firewall -KeyProperty _Id -Quiet }
Write-Host "  $($firewall.Count) firewall rules" -ForegroundColor DarkGray

# ============================================================
# org/users — 14 user accounts
# ============================================================
Write-Host "[org/users]" -ForegroundColor Blue

$adUsers = @(
    [PSCustomObject]@{ _Id = "u-alice"; SamAccountName = "alice"; DisplayName = "Alice Anderson"; Email = "alice@example.com"; Department = "IT"; Title = "Systems Administrator"; Manager = "bob"; Enabled = $true; LastLogon = $date.AddHours(-2); _GroupRefs = @("g-it-admins", "g-helpdesk") },
    [PSCustomObject]@{ _Id = "u-bob"; SamAccountName = "bob"; DisplayName = "Bob Barker"; Email = "bob@example.com"; Department = "IT"; Title = "IT Manager"; Manager = $null; Enabled = $true; LastLogon = $date.AddDays(-1); _GroupRefs = @("g-it-admins", "g-engineering") },
    [PSCustomObject]@{ _Id = "u-carol"; SamAccountName = "carol"; DisplayName = "Carol Chen"; Email = "carol@example.com"; Department = "Finance"; Title = "Accountant"; Manager = "david"; Enabled = $true; LastLogon = $date.AddHours(-5); _GroupRefs = @("g-finance") },
    [PSCustomObject]@{ _Id = "u-david"; SamAccountName = "david"; DisplayName = "David Drake"; Email = "david@example.com"; Department = "Finance"; Title = "Finance Director"; Manager = $null; Enabled = $true; LastLogon = $date.AddDays(-3); _GroupRefs = @("g-finance") },
    [PSCustomObject]@{ _Id = "u-emma"; SamAccountName = "emma"; DisplayName = "Emma Edwards"; Email = "emma@example.com"; Department = "HR"; Title = "HR Manager"; Manager = $null; Enabled = $true; LastLogon = $date.AddHours(-8); _GroupRefs = @("g-hr") },
    [PSCustomObject]@{ _Id = "u-frank"; SamAccountName = "frank"; DisplayName = "Frank Foster"; Email = "frank@example.com"; Department = "Engineering"; Title = "Software Engineer"; Manager = "grace"; Enabled = $true; LastLogon = $date.AddHours(-1); _GroupRefs = @("g-engineering") },
    [PSCustomObject]@{ _Id = "u-grace"; SamAccountName = "grace"; DisplayName = "Grace Gibson"; Email = "grace@example.com"; Department = "Engineering"; Title = "Engineering Manager"; Manager = $null; Enabled = $true; LastLogon = $date.AddDays(-2); _GroupRefs = @("g-engineering") },
    [PSCustomObject]@{ _Id = "u-henry"; SamAccountName = "henry"; DisplayName = "Henry Harris"; Email = "henry@example.com"; Department = "Sales"; Title = "Sales Rep"; Manager = "iris"; Enabled = $true; LastLogon = $date.AddDays(-4); _GroupRefs = @("g-sales") },
    [PSCustomObject]@{ _Id = "u-iris"; SamAccountName = "iris"; DisplayName = "Iris Ingram"; Email = "iris@example.com"; Department = "Sales"; Title = "Sales Director"; Manager = $null; Enabled = $true; LastLogon = $date.AddDays(-1); _GroupRefs = @("g-sales") },
    [PSCustomObject]@{ _Id = "u-jack"; SamAccountName = "jack"; DisplayName = "Jack Jackson"; Email = "jack@example.com"; Department = "IT"; Title = "Help Desk Tech"; Manager = "alice"; Enabled = $false; LastLogon = $date.AddDays(-90); _GroupRefs = @("g-helpdesk") },
    [PSCustomObject]@{ _Id = "u-karen"; SamAccountName = "karen"; DisplayName = "Karen King"; Email = "karen@example.com"; Department = "Legal"; Title = "Legal Counsel"; Manager = $null; Enabled = $true; LastLogon = $date.AddHours(-12); _GroupRefs = @("g-legal") },
    [PSCustomObject]@{ _Id = "u-leo"; SamAccountName = "leo"; DisplayName = "Leo Lane"; Email = "leo@example.com"; Department = "Legal"; Title = "Compliance Officer"; Manager = "karen"; Enabled = $true; LastLogon = $date.AddDays(-1); _GroupRefs = @("g-legal") },
    [PSCustomObject]@{ _Id = "u-maria"; SamAccountName = "maria"; DisplayName = "Maria Martinez"; Email = "maria@example.com"; Department = "Marketing"; Title = "Marketing Lead"; Manager = $null; Enabled = $true; LastLogon = $date.AddHours(-4); _GroupRefs = @("g-marketing") },
    [PSCustomObject]@{ _Id = "u-nick"; SamAccountName = "nick"; DisplayName = "Nick Nelson"; Email = "nick@example.com"; Department = "Marketing"; Title = "Content Manager"; Manager = "maria"; Enabled = $true; LastLogon = $date.AddDays(-2); _GroupRefs = @("g-marketing") }
)
$firstNames = @(
    "Olivia", "Patrick", "Quinn", "Rachel", "Sam", "Tina", "Uma", "Victor", "Wendy", "Xander",
    "Yara", "Zack", "Amy", "Brian", "Cindy", "Derek", "Elena", "Felix", "Gina", "Hank",
    "Ivy", "Jake", "Kara", "Liam", "Mona", "Nate", "Opal", "Pete", "Rosa", "Sean",
    "Tara", "Umar", "Vera", "Wade", "Xena", "Yuki", "Zane", "Adam", "Beth", "Cory",
    "Diana", "Evan", "Faith", "Gary", "Holly", "Ivan", "Jade", "Kurt", "Lora", "Miles",
    "Nina", "Omar", "Paula", "Rex", "Sage", "Troy", "Ursa", "Vince", "Willa", "Xero",
    "Yolanda", "Zeke", "Abby", "Blake", "Cara", "Dean", "Erin", "Finn", "Greer", "Hugh",
    "Indy", "Jett", "Kira", "Lex", "Maya", "Noel", "Ozzy", "Piper", "Rue", "Seth",
    "Tess", "Vance", "Wren", "Zara"
)

$lastNames = @(
    "Adams", "Baker", "Clark", "Davis", "Evans", "Fisher", "Garcia", "Hill", "Irwin", "Jones",
    "Kim", "Lee", "Miller", "Nash", "Owen", "Park", "Quinn", "Reed", "Smith", "Taylor",
    "Underwood", "Vance", "Walker", "Xu", "Young", "Zhang", "Abbott", "Bishop", "Cole", "Dunn",
    "Ellis", "Ford", "Grant", "Hayes", "Ingram", "Jordan", "Knight", "Lopez", "Morgan", "Nelson",
    "Oliver", "Perez", "Ray", "Stone", "Torres", "Upton", "Vega", "Ward", "Xiao", "Yates",
    "Zimmerman", "Arnold", "Bautista", "Crane", "Dalton", "Erickson", "Fletcher", "Gibbs", "Hale", "Ibarra",
    "Jensen", "Keller", "Lam", "Mack", "Newman", "Ochoa", "Patel", "Riggs", "Saunders", "Tate",
    "Urena", "Voss", "Wallace", "Yu", "Zamora", "Austin", "Banks", "Choi", "Dawson", "England",
    "Fowler", "Garrison", "House", "Irvin"
)

$allDepartments = @("IT", "Engineering", "Finance", "HR", "Sales", "Legal", "Marketing", "Operations", "Support", "Product")

$deptTitles = @{
    "IT"          = @("Systems Administrator", "Network Engineer", "Security Analyst", "IT Support Specialist")
    "Engineering" = @("Software Engineer", "DevOps Engineer", "QA Engineer", "Data Engineer")
    "Finance"     = @("Accountant", "Financial Analyst", "Accounts Payable", "Payroll Specialist")
    "HR"          = @("HR Coordinator", "Recruiter", "Benefits Administrator", "Training Specialist")
    "Sales"       = @("Sales Rep", "Account Manager", "Sales Engineer", "Business Development")
    "Legal"       = @("Paralegal", "Compliance Analyst", "Contracts Manager", "Privacy Officer")
    "Marketing"   = @("Content Manager", "SEO Specialist", "Marketing Coordinator", "Brand Manager")
    "Operations"  = @("Facilities Manager", "Procurement Specialist", "Logistics Coordinator", "Office Manager")
    "Support"     = @("Support Engineer", "Customer Success Manager", "Technical Writer", "Solutions Architect")
    "Product"     = @("Product Manager", "Product Designer", "UX Researcher", "Product Analyst")
}

$deptGroup = @{
    "IT"          = "g-it-admins"
    "Engineering" = "g-engineering"
    "Finance"     = "g-finance"
    "HR"          = "g-hr"
    "Sales"       = "g-sales"
    "Legal"       = "g-legal"
    "Marketing"   = "g-marketing"
    "Operations"  = "g-operations"
    "Support"     = "g-helpdesk"
    "Product"     = "g-engineering"
}

$extraUsers = foreach ($i in 0..83) {
    $fn = $firstNames[$i]
    $ln = $lastNames[$i]
    $sam = "$($fn.Substring(0,1).ToLower())$($ln.ToLower())"
    $dept = $allDepartments[$i % $allDepartments.Count]
    $titles = $deptTitles[$dept]
    $title = $titles[$i % $titles.Count]
    $enabled = ($i % 10) -ne 0
    $lastLogon = $date.AddDays(-( ($i * 7 + 3) % 60 ))

    [PSCustomObject]@{
        _Id           = "u-$sam"
        SamAccountName = $sam
        DisplayName   = "$fn $ln"
        Email         = "$sam@example.com"
        Department    = $dept
        Title         = $title
        Manager       = if ($dept -in @("IT", "Engineering", "Finance", "HR", "Sales", "Legal", "Marketing")) {
            switch ($dept) {
                "IT"          { "bob" }
                "Engineering" { "grace" }
                "Finance"     { "david" }
                "HR"          { "emma" }
                "Sales"       { "iris" }
                "Legal"       { "karen" }
                "Marketing"   { "maria" }
            }
        } else { $null }
        Enabled       = $enabled
        LastLogon     = $lastLogon
        _GroupRefs    = @($deptGroup[$dept])
    }
}

if (-not $PassThru) { $adUsers | New-BucketObject -Bucket org/users -KeyProperty _Id -Quiet }
if (-not $PassThru) { $extraUsers | New-BucketObject -Bucket org/users -KeyProperty _Id -Quiet }
$adUsers += $extraUsers
Write-Host "  $($adUsers.Count) user accounts" -ForegroundColor DarkGray

# ============================================================
# org/groups — 8 AD group records
# ============================================================
Write-Host "[org/groups]" -ForegroundColor Blue

$groups = @(
    [PSCustomObject]@{ _Id = "g-it-admins"; Name = "IT-Admins"; Description = "Domain and server administrators"; Members = @("alice", "bob") },
    [PSCustomObject]@{ _Id = "g-finance"; Name = "Finance"; Description = "Finance department"; Members = @("carol", "david") },
    [PSCustomObject]@{ _Id = "g-hr"; Name = "HR"; Description = "Human resources"; Members = @("emma") },
    [PSCustomObject]@{ _Id = "g-engineering"; Name = "Engineering"; Description = "Engineering team"; Members = @("frank", "grace") },
    [PSCustomObject]@{ _Id = "g-sales"; Name = "Sales"; Description = "Sales department"; Members = @("henry", "iris") },
    [PSCustomObject]@{ _Id = "g-helpdesk"; Name = "HelpDesk"; Description = "Help desk staff"; Members = @("jack", "alice") },
    [PSCustomObject]@{ _Id = "g-legal"; Name = "Legal"; Description = "Legal and compliance"; Members = @("karen", "leo") },
    [PSCustomObject]@{ _Id = "g-marketing"; Name = "Marketing"; Description = "Marketing department"; Members = @("maria", "nick") },
    [PSCustomObject]@{ _Id = "g-operations"; Name = "Operations"; Description = "Operations department"; Members = @() }
)
if (-not $PassThru) { $groups | New-BucketObject -Bucket org/groups -KeyProperty _Id -Quiet }
Write-Host "  $($groups.Count) group records" -ForegroundColor DarkGray

# ============================================================
# org/roles — 5 RBAC role definitions
# ============================================================
Write-Host "[org/roles]" -ForegroundColor Blue

$roles = @(
    [PSCustomObject]@{ _Id = "role-admin"; Name = "Administrator"; Permissions = @("infra:*", "org:*", "security:*", "ops:*"); AssignedTo = @("alice", "bob"); Priority = 1 },
    [PSCustomObject]@{ _Id = "role-operator"; Name = "Operator"; Permissions = @("infra:read", "infra:services:restart", "infra:backups:trigger", "ops:packages:read"); AssignedTo = @("grace", "frank"); Priority = 2 },
    [PSCustomObject]@{ _Id = "role-auditor"; Name = "Auditor"; Permissions = @("infra:read", "org:read", "security:read"); AssignedTo = @("karen", "leo"); Priority = 3 },
    [PSCustomObject]@{ _Id = "role-developer"; Name = "Developer"; Permissions = @("infra:containers:read", "infra:monitoring:read", "ops:packages:read"); AssignedTo = @("frank", "maria"); Priority = 4 },
    [PSCustomObject]@{ _Id = "role-helpdesk"; Name = "Help Desk"; Permissions = @("org:users:read", "org:users:reset-password", "infra:monitoring:read"); AssignedTo = @("jack"); Priority = 5 }
)
if (-not $PassThru) { $roles | New-BucketObject -Bucket org/roles -KeyProperty _Id -Quiet }
Write-Host "  $($roles.Count) role records" -ForegroundColor DarkGray

# ============================================================
# org/clients — 98 workstation records
# ============================================================
Write-Host "[org/clients]" -ForegroundColor Blue

$workstationModels = @(
    @{ Manufacturer = "Dell";      Model = "Latitude 5540" }
    @{ Manufacturer = "HP";        Model = "EliteBook 860" }
    @{ Manufacturer = "Lenovo";    Model = "ThinkPad X1 Carbon Gen 11" }
    @{ Manufacturer = "Microsoft"; Model = "Surface Laptop 5" }
)

$workstationOS = @("Windows 11 Pro", "Windows 10 Enterprise", "Ubuntu 22.04 LTS")
$locations = @("HQ-Floor1", "HQ-Floor2", "HQ-Floor3", "Remote", "Branch-East", "Branch-West")

$workstations = foreach ($i in 1..98) {
    $userIdx = ($i - 1) % $adUsers.Count
    $user = $adUsers[$userIdx]
    $model = $workstationModels[($i - 1) % $workstationModels.Count]
    $wsId = "WS-$("{0:D3}" -f $i)"

    [PSCustomObject]@{
        _Id            = $wsId
        Hostname       = $wsId
        AssignedUser   = $user.SamAccountName
        UserDisplayName = $user.DisplayName
        Department     = $user.Department
        Manufacturer   = $model.Manufacturer
        Model          = $model.Model
        Serial         = "SN-$("{0:D5}" -f $i)"
        OS             = $workstationOS[($i - 1) % $workstationOS.Count]
        CPU            = "Intel Core i7-1365U"
        RAM_GB         = 16 + ((($i - 1) % 3) * 16)
        Disk_GB        = 256 + ((($i - 1) % 4) * 256)
        IP             = "10.50.$([Math]::Floor(($i-1)/256)).$(($i-1) % 256)"
        Location       = $locations[($i - 1) % $locations.Count]
        LastLogonDate  = $date.AddDays(-((($i - 1) * 3) % 45))
        Status         = if ($i % 15 -eq 0) { "Inactive" } else { "Active" }
        _UserRef       = $user._Id
    }
}

if (-not $PassThru) { $workstations | New-BucketObject -Bucket org/clients -KeyProperty _Id -Quiet }
Write-Host "  $($workstations.Count) workstation records" -ForegroundColor DarkGray

# ============================================================
# security/certificates — 8 SSL certificate records
# ============================================================
Write-Host "[security/certificates]" -ForegroundColor Blue

$sslCerts = @(
    [PSCustomObject]@{ _Id = "cert-web-01"; Domain = "www.example.com"; Issuer = "Let's Encrypt"; Expiry = $date.AddDays(45); DaysLeft = 45; Type = "Wildcard"; KeySize = 4096; Algorithm = "RSA" },
    [PSCustomObject]@{ _Id = "cert-mail-01"; Domain = "mail.example.com"; Issuer = "DigiCert"; Expiry = $date.AddDays(180); DaysLeft = 180; Type = "SAN"; KeySize = 2048; Algorithm = "RSA" },
    [PSCustomObject]@{ _Id = "cert-api-01"; Domain = "api.example.com"; Issuer = "Let's Encrypt"; Expiry = $date.AddDays(30); DaysLeft = 30; Type = "Single"; KeySize = 4096; Algorithm = "RSA" },
    [PSCustomObject]@{ _Id = "cert-internal-01"; Domain = "internal.example.com"; Issuer = "Corp CA"; Expiry = $date.AddDays(365); DaysLeft = 365; Type = "Internal"; KeySize = 2048; Algorithm = "RSA" },
    [PSCustomObject]@{ _Id = "cert-wildcard-01"; Domain = "*.example.com"; Issuer = "GoDaddy"; Expiry = $date.AddDays(90); DaysLeft = 90; Type = "Wildcard"; KeySize = 4096; Algorithm = "ECC" },
    [PSCustomObject]@{ _Id = "cert-expired-01"; Domain = "old.example.com"; Issuer = "Comodo"; Expiry = $date.AddDays(-10); DaysLeft = -10; Type = "Single"; KeySize = 2048; Algorithm = "RSA" },
    [PSCustomObject]@{ _Id = "cert-lb-01"; Domain = "*.lb.example.com"; Issuer = "Let's Encrypt"; Expiry = $date.AddDays(60); DaysLeft = 60; Type = "Wildcard"; KeySize = 4096; Algorithm = "ECC" },
    [PSCustomObject]@{ _Id = "cert-vpn-01"; Domain = "vpn.example.com"; Issuer = "Corp CA"; Expiry = $date.AddDays(365); DaysLeft = 365; Type = "Single"; KeySize = 4096; Algorithm = "RSA" },
    [PSCustomObject]@{ _Id = "cert-mon-01"; Domain = "mon.example.com"; Issuer = "Let's Encrypt"; Expiry = $date.AddDays(25); DaysLeft = 25; Type = "Single"; KeySize = 4096; Algorithm = "RSA" }
)
if (-not $PassThru) { $sslCerts | New-BucketObject -Bucket security/certificates -KeyProperty _Id -Quiet }
Write-Host "  $($sslCerts.Count) certificate records" -ForegroundColor DarkGray

# ============================================================
# security/audit — 6 audit log entries
# ============================================================
Write-Host "[security/audit]" -ForegroundColor Blue

$auditLogs = @(
    [PSCustomObject]@{ _Id = "audit-001"; Timestamp = $date.AddDays(-2); User = "bob"; Action = "role.modify"; Target = "role-developer"; Detail = "Added frank to developer role"; Result = "success" },
    [PSCustomObject]@{ _Id = "audit-002"; Timestamp = $date.AddDays(-1); User = "alice"; Action = "user.disable"; Target = "u-jack"; Detail = "Disabled inactive user account jack"; Result = "success" },
    [PSCustomObject]@{ _Id = "audit-003"; Timestamp = $date.AddHours(-12); User = "svc-backup"; Action = "backup.start"; Target = "bkp-containers"; Detail = "Automated container volume backup started"; Result = "success" },
    [PSCustomObject]@{ _Id = "audit-004"; Timestamp = $date.AddHours(-6); User = "unknown"; Action = "login.failed"; Target = "srv-vpn-01"; Detail = "SSH brute force attempt from 185.220.101.0"; Result = "blocked" },
    [PSCustomObject]@{ _Id = "audit-005"; Timestamp = $date.AddHours(-3); User = "grace"; Action = "cert.renew"; Target = "cert-api-01"; Detail = "Manually triggered certificate renewal for api.example.com"; Result = "success" },
    [PSCustomObject]@{ _Id = "audit-006"; Timestamp = $date.AddMinutes(-30); User = "monitoring"; Action = "alert.trigger"; Target = "check-dns-01"; Detail = "DNS query response time degraded (>300ms)"; Result = "warning" }
)
if (-not $PassThru) { $auditLogs | New-BucketObject -Bucket security/audit -KeyProperty _Id -Quiet }
Write-Host "  $($auditLogs.Count) audit log records" -ForegroundColor DarkGray

# ============================================================
# ops/packages — 12 installed package records
# ============================================================
Write-Host "[ops/packages]" -ForegroundColor Blue

$packages = @(
    [PSCustomObject]@{ _Id = "pkg-apache2"; Server = "srv-web-01"; _ServerRef = "srv-web-01"; Name = "apache2"; Version = "2.4.52-1ubuntu4"; Architecture = "amd64"; Size_KB = 4800; Repo = "ubuntu jammy-security"; Installed = $date.AddDays(-90) },
    [PSCustomObject]@{ _Id = "pkg-php83"; Server = "srv-web-01"; _ServerRef = "srv-web-01"; Name = "php8.3"; Version = "8.3.0-1jammy1"; Architecture = "amd64"; Size_KB = 15000; Repo = "ondrej php"; Installed = $date.AddDays(-60) },
    [PSCustomObject]@{ _Id = "pkg-mysql84"; Server = "srv-db-01"; _ServerRef = "srv-db-01"; Name = "mysql-server-8.4"; Version = "8.4.0-1el8"; Architecture = "x86_64"; Size_KB = 95000; Repo = "mysql80-community"; Installed = $date.AddDays(-120) },
    [PSCustomObject]@{ _Id = "pkg-redis7"; Server = "srv-cache-01"; _ServerRef = "srv-cache-01"; Name = "redis-server"; Version = "7.0.15-1jammy1"; Architecture = "amd64"; Size_KB = 3200; Repo = "ubuntu jammy"; Installed = $date.AddDays(-30) },
    [PSCustomObject]@{ _Id = "pkg-bind9"; Server = "srv-dns-01"; _ServerRef = "srv-dns-01"; Name = "bind9"; Version = "9.18.18-0ubuntu1"; Architecture = "amd64"; Size_KB = 4800; Repo = "ubuntu jammy-updates"; Installed = $date.AddDays(-180) },
    [PSCustomObject]@{ _Id = "pkg-postfix3"; Server = "srv-mail-01"; _ServerRef = "srv-mail-01"; Name = "postfix"; Version = "3.7.6-0ubuntu1"; Architecture = "amd64"; Size_KB = 4200; Repo = "ubuntu jammy"; Installed = $date.AddDays(-150) },
    [PSCustomObject]@{ _Id = "pkg-haproxy"; Server = "srv-lb-01"; _ServerRef = "srv-lb-01"; Name = "haproxy"; Version = "2.8.5-1"; Architecture = "amd64"; Size_KB = 2400; Repo = "debian bookworm-backports"; Installed = $date.AddDays(-60) },
    [PSCustomObject]@{ _Id = "pkg-prometheus"; Server = "srv-mon-01"; _ServerRef = "srv-mon-01"; Name = "prometheus"; Version = "2.50.1+ds-1"; Architecture = "amd64"; Size_KB = 85000; Repo = "ubuntu jammy"; Installed = $date.AddDays(-14) },
    [PSCustomObject]@{ _Id = "pkg-docker-ce-01"; Server = "srv-container-01"; _ServerRef = "srv-container-01"; Name = "docker-ce"; Version = "25.0.3-1"; Architecture = "amd64"; Size_KB = 65000; Repo = "docker jammy"; Installed = $date.AddDays(-90) },
    [PSCustomObject]@{ _Id = "pkg-docker-ce-02"; Server = "srv-container-02"; _ServerRef = "srv-container-02"; Name = "docker-ce"; Version = "25.0.3-1"; Architecture = "amd64"; Size_KB = 65000; Repo = "docker jammy"; Installed = $date.AddDays(-60) },
    [PSCustomObject]@{ _Id = "pkg-elasticsearch"; Server = "srv-log-01"; _ServerRef = "srv-log-01"; Name = "elasticsearch"; Version = "8.12.0"; Architecture = "amd64"; Size_KB = 350000; Repo = "elastic 8.x"; Installed = $date.AddDays(-30) },
    [PSCustomObject]@{ _Id = "pkg-wireguard"; Server = "srv-vpn-01"; _ServerRef = "srv-vpn-01"; Name = "wireguard-tools"; Version = "1.0.20210914"; Architecture = "x86_64"; Size_KB = 380; Repo = "alpine main"; Installed = $date.AddDays(-180) }
)
if (-not $PassThru) { $packages | New-BucketObject -Bucket ops/packages -KeyProperty _Id -Quiet }
Write-Host "  $($packages.Count) package records" -ForegroundColor DarkGray

# ============================================================
# ops/configs — 6 configuration profiles
# ============================================================
Write-Host "[ops/configs]" -ForegroundColor Blue

$configs = @(
    [PSCustomObject]@{ _Id = "cfg-ansible-main"; Service = "ansible"; _ServiceRef = "svc-ansible"; Type = "ansible.inventory"; Path = "/etc/ansible/hosts.ini"; LastModified = $date.AddDays(-7); Version = "v2.3.1"; ManagedBy = "bob" },
    [PSCustomObject]@{ _Id = "cfg-haproxy-main"; Service = "haproxy"; _ServiceRef = "svc-haproxy"; Type = "haproxy.config"; Path = "/etc/haproxy/haproxy.cfg"; LastModified = $date.AddDays(-14); Version = "v1.8.0"; ManagedBy = "alice" },
    [PSCustomObject]@{ _Id = "cfg-prometheus-rules"; Service = "prometheus"; _ServiceRef = "svc-prometheus"; Type = "prometheus.rules"; Path = "/etc/prometheus/rules.yml"; LastModified = $date.AddDays(-3); Version = "v3.0.1"; ManagedBy = "alice" },
    [PSCustomObject]@{ _Id = "cfg-nginx-default"; Service = "httpd"; _ServiceRef = "svc-httpd"; Type = "nginx.site"; Path = "/etc/nginx/sites-enabled/default"; LastModified = $date.AddDays(-30); Version = "v1.2.0"; ManagedBy = "frank" },
    [PSCustomObject]@{ _Id = "cfg-wireguard-tunnel"; Service = "wireguard"; _ServiceRef = "svc-wireguard"; Type = "wireguard.conf"; Path = "/etc/wireguard/wg0.conf"; LastModified = $date.AddDays(-90); Version = "v1.0.0"; ManagedBy = "alice" },
    [PSCustomObject]@{ _Id = "cfg-elasticsearch-yaml"; Service = "elasticsearch"; _ServiceRef = "svc-elasticsearch"; Type = "elasticsearch.yml"; Path = "/etc/elasticsearch/elasticsearch.yml"; LastModified = $date.AddDays(-5); Version = "v2.0.0"; ManagedBy = "grace" }
)
if (-not $PassThru) { $configs | New-BucketObject -Bucket ops/configs -KeyProperty _Id -Quiet }
Write-Host "  $($configs.Count) config records" -ForegroundColor DarkGray

# ============================================================
# Summary
# ============================================================
if ($PassThru) { return @{
    servers       = $servers
    services      = $services
    disks         = $disks
    backups       = $backups
    containers    = $containers
    incidents     = $incidents
    monChecks     = $monChecks
    scheduledTasks = $scheduledTasks
    networks      = $networks
    interfaces    = $interfaces
    dnsRecords    = $dnsRecords
    firewall      = $firewall
    adUsers       = $adUsers
    groups        = $groups
    roles         = $roles
    workstations  = $workstations
    sslCerts      = $sslCerts
    auditLogs     = $auditLogs
    packages      = $packages
    configs       = $configs
} }

Write-Host ""
$totalBuckets = @(
    "infra/servers",
    "infra/services",
    "infra/storage",
    "infra/backups",
    "infra/containers",
    "infra/incidents",
    "infra/monitoring",
    "infra/scheduled",
    "network/vlans",
    "network/interfaces",
    "network/dns",
    "network/firewall",
    "org/users",
    "org/groups",
    "org/roles",
    "org/clients",
    "security/certificates",
    "security/audit",
    "ops/packages",
    "ops/configs"
)

$totalObjects = (
    $servers.Count + $services.Count + $disks.Count + $backups.Count +
    $containers.Count + $incidents.Count + $monChecks.Count +
    $scheduledTasks.Count + $networks.Count + $interfaces.Count +
    $dnsRecords.Count + $firewall.Count + $adUsers.Count +
    $groups.Count + $roles.Count + $workstations.Count + $sslCerts.Count +
    $auditLogs.Count + $packages.Count + $configs.Count
)

if (-not $Quiet) {
    Write-Host "  Buckets created: $($totalBuckets.Count)" -ForegroundColor DarkGray
    Write-Host "  Objects created: $totalObjects" -ForegroundColor DarkGray

    Write-Host "`n[Bucket Overview]" -ForegroundColor Blue
    Get-Bucket -Tree | Select-Object -First 30 | Out-Host

    # ============================================================
    # Relationship Queries — cross-bucket examples
    # ============================================================
    Write-Host "`n[Relationship Queries]" -ForegroundColor Blue

    # 1. Services on non-production servers
    Write-Host "`n  Q1: Services on non-production servers" -ForegroundColor DarkGray
    $offline = spill -Bucket infra/servers -Filter { $_.Status -ne "production" }
    $offline | ForEach-Object {
        $svr = $_
        spill -Bucket infra/services -Match @{ _ServerRef = $svr._Id }
    } | Out-Host

    # 2. Critical disks (>80%) with server details
    Write-Host "`n  Q2: Critical disks with server details" -ForegroundColor DarkGray
    $critical = spill -Bucket infra/storage -Filter { $_.Use_Pct -ge 80 }
    $critical | ForEach-Object {
        $disk = $_
        $svr = spill -Bucket infra/servers -Key $disk._ServerRef
        [PSCustomObject]@{
            Server   = $svr.Hostname
            Mount    = $disk.Mount
            Used_Pct = $disk.Use_Pct
            Alert    = $disk.Alert
        }
    } | Format-Table -AutoSize | Out-Host

    # 3. Open incidents with source server details
    Write-Host "`n  Q3: Open incidents with server details" -ForegroundColor DarkGray
    $open = spill -Bucket infra/incidents -Filter { $_.Status -eq "open" }
    $open | ForEach-Object {
        $inc = $_
        $svr = spill -Bucket infra/servers -Key $inc._ServerRef
        [PSCustomObject]@{
            Severity = $inc.Severity
            Source   = $inc.Source
            Message  = $inc.Message
            Location = $svr.Location
        }
    } | Format-Table -AutoSize | Out-Host

    # 4. Failing monitoring checks with container details
    Write-Host "`n  Q4: Failing monitoring checks" -ForegroundColor DarkGray
    $failing = spill -Bucket infra/monitoring -Filter { $_.Status -ne "pass" }
    $failing | ForEach-Object {
        $check = $_
        $svr = spill -Bucket infra/servers -Key $check._TargetRef
        [PSCustomObject]@{
            CheckType = $check.CheckType
            Target    = $check.Target
            Status    = $check.Status
            Error     = $check.Error
            Location  = $svr.Location
        }
    } | Format-Table -AutoSize | Out-Host

    # 5. Containers by health status
    Write-Host "`n  Q5: Containers by health status" -ForegroundColor DarkGray
    spill -Bucket infra/containers | Group-Object Health | Select-Object Name, Count | Out-Host

    # 6. Users grouped by department
    Write-Host "`n  Q6: Users by department" -ForegroundColor DarkGray
    spill -Bucket org/users | Group-Object Department | Select-Object Name, Count | Out-Host

    # 7. Certificates expiring within 90 days
    Write-Host "`n  Q7: Certificates expiring within 90 days" -ForegroundColor DarkGray
    spill -Bucket security/certificates -Filter { $_.DaysLeft -le 90 -and $_.DaysLeft -gt 0 } | Out-Host

    # 8. Audit log entries grouped by result
    Write-Host "`n  Q8: Audit log by result" -ForegroundColor DarkGray
    spill -Bucket security/audit | Group-Object Result | Select-Object Name, Count | Out-Host

    # 9. Server resource totals by location
    Write-Host "`n  Q9: Server resource totals (infra/servers)" -ForegroundColor DarkGray
    spill -Bucket infra/servers | Measure-Object RAM_GB, Disk_GB -Sum | Out-Host

    # 10. Interfaces grouped by speed
    Write-Host "`n  Q10: Interfaces by speed" -ForegroundColor DarkGray
    spill -Bucket network/interfaces | Group-Object Speed_Gbps | Select-Object Name, Count | Out-Host

    # 11. Packages grouped by server
    Write-Host "`n  Q11: Packages by server" -ForegroundColor DarkGray
    spill -Bucket ops/packages | Group-Object _ServerRef | Select-Object Name, Count | Out-Host

    # 12. All services on container hosts
    Write-Host "`n  Q12: Services on container hosts" -ForegroundColor DarkGray
    $containerHosts = spill -Bucket infra/servers -Filter { $_.Role -eq "Container Host" }
    $containerHosts | ForEach-Object {
        $svr = $_
        spill -Bucket infra/services -Match @{ _ServerRef = $svr._Id }
    } | Out-Host

    # 13. Backups referencing database servers
    Write-Host "`n  Q13: Backups for database servers" -ForegroundColor DarkGray
    $dbKeys = (spill -Bucket infra/servers -Filter { $_.Role -eq "Database" })._Id
    spill -Bucket infra/backups | Where-Object {
        $found = $false
        foreach ($ref in $_._ServerRefs) { if ($dbKeys -contains $ref) { $found = $true; break } }
        $found
    } | Out-Host

    # 14. Servers with cert refs showing cert expiry
    Write-Host "`n  Q14: Servers with certificate expiry" -ForegroundColor DarkGray
    $hasCert = spill -Bucket infra/servers -Filter { $null -ne $_._CertRef }
    $hasCert | ForEach-Object {
        $svr = $_
        $cert = spill -Bucket security/certificates -Key $svr._CertRef
        [PSCustomObject]@{
            Server     = $svr.Hostname
            CertDomain = $cert.Domain
            Issuer     = $cert.Issuer
            DaysLeft   = $cert.DaysLeft
        }
    } | Format-Table -AutoSize | Out-Host

    # 15. Config profiles grouped by service
    Write-Host "`n  Q15: Configs by service" -ForegroundColor DarkGray
    spill -Bucket ops/configs | Group-Object Service | Select-Object Name, Count | Out-Host

    Write-Host ""
    Write-InfoBlock -Mode bottom
}
