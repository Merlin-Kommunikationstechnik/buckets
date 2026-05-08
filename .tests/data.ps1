#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generates realistic sysadmin data across multiple buckets.
.DESCRIPTION
    Creates diverse buckets simulating daily sysadmin workload:
    - Server inventory
    - Network configs
    - User/AD accounts
    - SSL certificates
    - Backup jobs
    - Services/daemons
    - Disk usage
    - DNS records
    - Firewall rules
    - Installed packages
#>

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$startTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$createdBuckets = [System.Collections.ArrayList]::new()

function Use-Bucket {
    param([string]$Name)
    $null = $createdBuckets.Add($Name)
}

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

# ============================================================
# 1. Server Inventory
# ============================================================
Write-Host "`n[1] Server Inventory" -ForegroundColor Blue

$servers = @(
    [PSCustomObject]@{ _Id = "srv-web-01"; Hostname = "srv-web-01"; OS = "Ubuntu 22.04 LTS"; CPU = "Intel Xeon Gold 5418Y @ 2.1GHz x 4"; RAM_GB = 32; Disk_GB = 500; IP = "10.0.1.10"; Role = "Web Server"; Location = "dc1-rack-a-01"; Status = "production"; LastBoot = [DateTime]::Now.AddDays(-12) },
    [PSCustomObject]@{ _Id = "srv-web-02"; Hostname = "srv-web-02"; OS = "Ubuntu 22.04 LTS"; CPU = "Intel Xeon Gold 5418Y @ 2.1GHz x 4"; RAM_GB = 32; Disk_GB = 500; IP = "10.0.1.11"; Role = "Web Server"; Location = "dc1-rack-a-02"; Status = "production"; LastBoot = [DateTime]::Now.AddDays(-8) },
    [PSCustomObject]@{ _Id = "srv-db-01"; Hostname = "srv-db-01"; OS = "CentOS 8 Stream"; CPU = "AMD EPYC 7713 64-Core @ 2.0GHz x 2"; RAM_GB = 128; Disk_GB = 2000; IP = "10.0.2.10"; Role = "Database"; Location = "dc1-rack-b-01"; Status = "production"; LastBoot = [DateTime]::Now.AddDays(-45) },
    [PSCustomObject]@{ _Id = "srv-db-02"; Hostname = "srv-db-02"; OS = "CentOS 8 Stream"; CPU = "AMD EPYC 7713 64-Core @ 2.0GHz x 2"; RAM_GB = 128; Disk_GB = 2000; IP = "10.0.2.11"; Role = "Database"; Location = "dc1-rack-b-02"; Status = "standby"; LastBoot = [DateTime]::Now.AddDays(-45) },
    [PSCustomObject]@{ _Id = "srv-cache-01"; Hostname = "srv-cache-01"; OS = "Ubuntu 22.04 LTS"; CPU = "Intel Xeon Silver 4314 @ 2.2GHz x 2"; RAM_GB = 64; Disk_GB = 256; IP = "10.0.3.10"; Role = "Redis Cache"; Location = "dc1-rack-c-01"; Status = "production"; LastBoot = [DateTime]::Now.AddDays(-3) },
    [PSCustomObject]@{ _Id = "srv-mail-01"; Hostname = "srv-mail-01"; OS = "Debian 12"; CPU = "Intel Xeon Gold 5418Y @ 2.1GHz x 4"; RAM_GB = 16; Disk_GB = 1000; IP = "10.0.4.10"; Role = "Mail Server"; Location = "dc2-rack-a-01"; Status = "production"; LastBoot = [DateTime]::Now.AddDays(-21) },
    [PSCustomObject]@{ _Id = "srv-dc-01"; Hostname = "srv-dc-01"; OS = "Windows Server 2022"; CPU = "Intel Xeon Gold 5418Y @ 2.1GHz x 4"; RAM_GB = 64; Disk_GB = 500; IP = "10.0.10.10"; Role = "Domain Controller"; Location = "dc1-rack-a-10"; Status = "production"; LastBoot = [DateTime]::Now.AddDays(-60) },
    [PSCustomObject]@{ _Id = "srv-dc-02"; Hostname = "srv-dc-02"; OS = "Windows Server 2022"; CPU = "Intel Xeon Gold 5418Y @ 2.1GHz x 4"; RAM_GB = 64; Disk_GB = 500; IP = "10.0.10.11"; Role = "Domain Controller"; Location = "dc2-rack-a-10"; Status = "production"; LastBoot = [DateTime]::Now.AddDays(-60) },
    [PSCustomObject]@{ _Id = "srv-dns-01"; Hostname = "srv-dns-01"; OS = "Ubuntu 22.04 LTS"; CPU = "Intel Xeon Silver 4314 @ 2.2GHz x 2"; RAM_GB = 8; Disk_GB = 50; IP = "10.0.11.10"; Role = "DNS/NTP"; Location = "dc1-rack-c-10"; Status = "production"; LastBoot = [DateTime]::Now.AddDays(-30) },
    [PSCustomObject]@{ _Id = "srv-backup-01"; Hostname = "srv-backup-01"; OS = "Ubuntu 22.04 LTS"; CPU = "Intel Xeon Silver 4314 @ 2.2GHz x 4"; RAM_GB = 32; Disk_GB = 16000; IP = "10.0.12.10"; Role = "Backup Server"; Location = "dc1-rack-d-01"; Status = "production"; LastBoot = [DateTime]::Now.AddDays(-7) }
)
$servers | New-BucketObject -Bucket servers/inventory -KeyProperty _Id -Quiet
Use-Bucket "servers/inventory"
Write-Host "  Created $($servers.Count) server records" -ForegroundColor DarkGray

# ============================================================
# 2. Network Configuration
# ============================================================
Write-Host "[2] Network Configuration" -ForegroundColor Blue

$networks = @(
    [PSCustomObject]@{ _Id = "net-dmz"; Name = "DMZ"; Subnet = "10.0.0.0/24"; Gateway = "10.0.0.1"; VLAN = 10; Description = "Public-facing services" },
    [PSCustomObject]@{ _Id = "net-web"; Name = "Web Tier"; Subnet = "10.0.1.0/24"; Gateway = "10.0.1.1"; VLAN = 11; Description = "Web servers" },
    [PSCustomObject]@{ _Id = "net-app"; Name = "App Tier"; Subnet = "10.0.2.0/24"; Gateway = "10.0.2.1"; VLAN = 12; Description = "Application servers" },
    [PSCustomObject]@{ _Id = "net-data"; Name = "Data Tier"; Subnet = "10.0.3.0/24"; Gateway = "10.0.3.1"; VLAN = 13; Description = "Databases and cache" },
    [PSCustomObject]@{ _Id = "net-mgmt"; Name = "Management"; Subnet = "10.0.10.0/24"; Gateway = "10.0.10.1"; VLAN = 99; Description = "Admin access and monitoring" },
    [PSCustomObject]@{ _Id = "net-backup"; Name = "Backup"; Subnet = "10.0.12.0/24"; Gateway = "10.0.12.1"; VLAN = 14; Description = "Backup traffic isolation" }
)
$networks | New-BucketObject -Bucket network/vlans -KeyProperty _Id -Quiet
Use-Bucket "network/vlans"
Write-Host "  Created $($networks.Count) VLANs" -ForegroundColor DarkGray

$firewall = @(
    [PSCustomObject]@{ _Id = "fw-001"; Source = "any"; Dest = "srv-web-01:443"; Port = 443; Protocol = "TCP"; Action = "ALLOW"; Rule = "Allow HTTPS to web servers" },
    [PSCustomObject]@{ _Id = "fw-002"; Source = "10.0.1.0/24"; Dest = "srv-db-01:5432"; Port = 5432; Protocol = "TCP"; Action = "ALLOW"; Rule = "Web to DB" },
    [PSCustomObject]@{ _Id = "fw-003"; Source = "10.0.10.0/24"; Dest = "any"; Port = "22,3389"; Protocol = "TCP"; Action = "ALLOW"; Rule = "Management access" },
    [PSCustomObject]@{ _Id = "fw-004"; Source = "any"; Dest = "any"; Port = "25,587"; Protocol = "SMTP"; Action = "ALLOW"; Rule = "Mail relay" },
    [PSCustomObject]@{ _Id = "fw-005"; Source = "any"; Dest = "any"; Port = "53"; Protocol = "UDP"; Action = "ALLOW"; Rule = "DNS" },
    [PSCustomObject]@{ _Id = "fw-006"; Source = "any"; Dest = "any"; Port = "any"; Protocol = "any"; Action = "DENY"; Rule = "Default deny" }
)
$firewall | New-BucketObject -Bucket network/firewall -KeyProperty _Id -Quiet
Use-Bucket "network/firewall"
Write-Host "  Created $($firewall.Count) firewall rules" -ForegroundColor DarkGray

# ============================================================
# 3. User Accounts / AD
# ============================================================
Write-Host "[3] User Accounts" -ForegroundColor Blue

$adUsers = @(
    [PSCustomObject]@{ _Id = "u-alice"; SamAccountName = "alice"; DisplayName = "Alice Anderson"; Email = "alice@example.com"; Department = "IT"; Title = "Systems Administrator"; Manager = "bob"; Enabled = $true; LastLogon = [DateTime]::Now.AddHours(-2) },
    [PSCustomObject]@{ _Id = "u-bob"; SamAccountName = "bob"; DisplayName = "Bob Barker"; Email = "bob@example.com"; Department = "IT"; Title = "IT Manager"; Manager = $null; Enabled = $true; LastLogon = [DateTime]::Now.AddDays(-1) },
    [PSCustomObject]@{ _Id = "u-carol"; SamAccountName = "carol"; DisplayName = "Carol Chen"; Email = "carol@example.com"; Department = "Finance"; Title = "Accountant"; Manager = "david"; Enabled = $true; LastLogon = [DateTime]::Now.AddHours(-5) },
    [PSCustomObject]@{ _Id = "u-david"; SamAccountName = "david"; DisplayName = "David Drake"; Email = "david@example.com"; Department = "Finance"; Title = "Finance Director"; Manager = $null; Enabled = $true; LastLogon = [DateTime]::Now.AddDays(-3) },
    [PSCustomObject]@{ _Id = "u-emma"; SamAccountName = "emma"; DisplayName = "Emma Edwards"; Email = "emma@example.com"; Department = "HR"; Title = "HR Manager"; Manager = $null; Enabled = $true; LastLogon = [DateTime]::Now.AddHours(-8) },
    [PSCustomObject]@{ _Id = "u-frank"; SamAccountName = "frank"; DisplayName = "Frank Foster"; Email = "frank@example.com"; Department = "Engineering"; Title = "Software Engineer"; Manager = "grace"; Enabled = $true; LastLogon = [DateTime]::Now.AddHours(-1) },
    [PSCustomObject]@{ _Id = "u-grace"; SamAccountName = "grace"; DisplayName = "Grace Gibson"; Email = "grace@example.com"; Department = "Engineering"; Title = "Engineering Manager"; Manager = $null; Enabled = $true; LastLogon = [DateTime]::Now.AddDays(-2) },
    [PSCustomObject]@{ _Id = "u-henry"; SamAccountName = "henry"; DisplayName = "Henry Harris"; Email = "henry@example.com"; Department = "Sales"; Title = "Sales Rep"; Manager = "iris"; Enabled = $true; LastLogon = [DateTime]::Now.AddDays(-4) },
    [PSCustomObject]@{ _Id = "u-iris"; SamAccountName = "iris"; DisplayName = "Iris Ingram"; Email = "iris@example.com"; Department = "Sales"; Title = "Sales Director"; Manager = $null; Enabled = $true; LastLogon = [DateTime]::Now.AddDays(-1) },
    [PSCustomObject]@{ _Id = "u-jack"; SamAccountName = "jack"; DisplayName = "Jack Jackson"; Email = "jack@example.com"; Department = "IT"; Title = "Help Desk Tech"; Manager = "alice"; Enabled = $false; LastLogon = [DateTime]::Now.AddDays(-90) }
)
$adUsers | New-BucketObject -Bucket ad/users -KeyProperty _Id -Quiet
Use-Bucket "ad/users"
Write-Host "  Created $($adUsers.Count) AD user accounts" -ForegroundColor DarkGray

$groups = @(
    [PSCustomObject]@{ _Id = "g-it-admins"; Name = "IT-Admins"; Description = "Domain and server administrators"; Members = @("alice", "bob") },
    [PSCustomObject]@{ _Id = "g-finance"; Name = "Finance"; Description = "Finance department"; Members = @("carol", "david") },
    [PSCustomObject]@{ _Id = "g-hr"; Name = "HR"; Description = "Human resources"; Members = @("emma") },
    [PSCustomObject]@{ _Id = "g-engineering"; Name = "Engineering"; Description = "Engineering team"; Members = @("frank", "grace") },
    [PSCustomObject]@{ _Id = "g-sales"; Name = "Sales"; Description = "Sales department"; Members = @("henry", "iris") },
    [PSCustomObject]@{ _Id = "g-helpdesk"; Name = "HelpDesk"; Description = "Help desk staff"; Members = @("jack", "alice") }
)
$groups | New-BucketObject -Bucket ad/groups -KeyProperty _Id -Quiet
Use-Bucket "ad/groups"
Write-Host "  Created $($groups.Count) AD groups" -ForegroundColor DarkGray

# ============================================================
# 4. SSL Certificates
# ============================================================
Write-Host "[4] SSL Certificates" -ForegroundColor Blue

$date = [DateTime]::Now
$sslCerts = @(
    [PSCustomObject]@{ _Id = "cert-web-01"; Domain = "www.example.com"; Issuer = "Let's Encrypt"; Expiry = $date.AddDays(45); DaysLeft = 45; Type = "Wildcard"; KeySize = 4096; Algorithm = "RSA" },
    [PSCustomObject]@{ _Id = "cert-mail-01"; Domain = "mail.example.com"; Issuer = "DigiCert"; Expiry = $date.AddDays(180); DaysLeft = 180; Type = "SAN"; KeySize = 2048; Algorithm = "RSA" },
    [PSCustomObject]@{ _Id = "cert-api-01"; Domain = "api.example.com"; Issuer = "Let's Encrypt"; Expiry = $date.AddDays(30); DaysLeft = 30; Type = "Single"; KeySize = 4096; Algorithm = "RSA" },
    [PSCustomObject]@{ _Id = "cert-internal-01"; Domain = "internal.example.com"; Issuer = "Corp CA"; Expiry = $date.AddDays(365); DaysLeft = 365; Type = "Internal"; KeySize = 2048; Algorithm = "RSA" },
    [PSCustomObject]@{ _Id = "cert-wildcard-01"; Domain = "*.example.com"; Issuer = "GoDaddy"; Expiry = $date.AddDays(90); DaysLeft = 90; Type = "Wildcard"; KeySize = 4096; Algorithm = "ECC" },
    [PSCustomObject]@{ _Id = "cert-expired-01"; Domain = "old.example.com"; Issuer = "Comodo"; Expiry = $date.AddDays(-10); DaysLeft = -10; Type = "Single"; KeySize = 2048; Algorithm = "RSA" }
)
$sslCerts | New-BucketObject -Bucket certificates/ssl -KeyProperty _Id -Quiet
Use-Bucket "certificates/ssl"
Write-Host "  Created $($sslCerts.Count) SSL certificate records" -ForegroundColor DarkGray

# ============================================================
# 5. Backup Jobs
# ============================================================
Write-Host "[5] Backup Jobs" -ForegroundColor Blue

$backups = @(
    [PSCustomObject]@{ _Id = "bkp-daily-users"; Name = "Daily Users Backup"; Type = "Incremental"; Schedule = "0 2 * * *"; Target = "backup-nas-01:/backups/users"; Retention = "30 days"; LastRun = $date.AddHours(-6); NextRun = $date.AddHours(18); Status = "success"; Size_GB = 45; Duration_Min = 35 },
    [PSCustomObject]@{ _Id = "bkp-weekly-fs"; Name = "Weekly Fileserver"; Type = "Full"; Schedule = "0 1 * * 0"; Target = "backup-nas-01:/backups/fileserver"; Retention = "90 days"; LastRun = $date.AddDays(-2); NextRun = $date.AddDays(5); Status = "success"; Size_GB = 850; Duration_Min = 420 },
    [PSCustomObject]@{ _Id = "bkp-daily-sql"; Name = "Daily SQL Databases"; Type = "Differential"; Schedule = "0 3 * * *"; Target = "backup-nas-01:/backups/sql"; Retention = "14 days"; LastRun = $date.AddHours(-5); NextRun = $date.AddHours(19); Status = "success"; Size_GB = 120; Duration_Min = 55 },
    [PSCustomObject]@{ _Id = "bkp-hourly-trans"; Name = "Hourly Transactions"; Type = "Log"; Schedule = "0 * * * *"; Target = "backup-nas-02:/backups/trans"; Retention = "7 days"; LastRun = $date.AddHours(-1); NextRun = $date.AddHours(1); Status = "running"; Size_GB = 2; Duration_Min = 8 },
    [PSCustomObject]@{ _Id = "bkp-monthly-arch"; Name = "Monthly Archive"; Type = "Full"; Schedule = "0 0 1 * *"; Target = "backup-tape-01"; Retention = "7 years"; LastRun = $date.AddDays(-25); NextRun = $date.AddDays(5); Status = "success"; Size_GB = 2400; Duration_Min = 1800 },
    [PSCustomObject]@{ _Id = "bkp-failed-01"; Name = "Daily VM Snapshots"; Type = "Snapshot"; Schedule = "0 4 * * *"; Target = "backup-vsan-01:/snapshots"; Retention = "7 days"; LastRun = $date.AddDays(-1); NextRun = $date.AddHours(5); Status = "failed"; Size_GB = 0; Duration_Min = 0; Error = "ESXi host unreachable" }
)
$backups | New-BucketObject -Bucket backups/jobs -KeyProperty _Id -Quiet
Use-Bucket "backups/jobs"
Write-Host "  Created $($backups.Count) backup job records" -ForegroundColor DarkGray

# ============================================================
# 6. Services / Daemons
# ============================================================
Write-Host "[6] Services / Daemons" -ForegroundColor Blue

$services = @(
    [PSCustomObject]@{ _Id = "svc-httpd"; Name = "httpd"; Server = "srv-web-01"; Status = "running"; CPU_Pct = 12.5; Mem_MB = 512; Uptime_Days = 45; Restarts = 0; LastCheck = $date.AddMinutes(-5) },
    [PSCustomObject]@{ _Id = "svc-mysqld"; Name = "mysqld"; Server = "srv-db-01"; Status = "running"; CPU_Pct = 25.0; Mem_MB = 8192; Uptime_Days = 30; Restarts = 1; LastCheck = $date.AddMinutes(-2) },
    [PSCustomObject]@{ _Id = "svc-redis"; Name = "redis-server"; Server = "srv-cache-01"; Status = "running"; CPU_Pct = 3.2; Mem_MB = 4096; Uptime_Days = 15; Restarts = 0; LastCheck = $date.AddMinutes(-1) },
    [PSCustomObject]@{ _Id = "svc-postfix"; Name = "postfix"; Server = "srv-mail-01"; Status = "running"; CPU_Pct = 5.8; Mem_MB = 128; Uptime_Days = 60; Restarts = 2; LastCheck = $date.AddMinutes(-10) },
    [PSCustomObject]@{ _Id = "svc-named"; Name = "named"; Server = "srv-dns-01"; Status = "running"; CPU_Pct = 1.2; Mem_MB = 64; Uptime_Days = 90; Restarts = 0; LastCheck = $date.AddMinutes(-1) },
    [PSCustomObject]@{ _Id = "svc-ntpd"; Name = "ntpd"; Server = "srv-dns-01"; Status = "stopped"; CPU_Pct = 0.0; Mem_MB = 0; Uptime_Days = 0; Restarts = 5; LastCheck = $date.AddHours(-2); Error = "Configuration invalid" },
    [PSCustomObject]@{ _Id = "svc-agent"; Name = "osqueryi"; Server = "srv-web-02"; Status = "running"; CPU_Pct = 0.5; Mem_MB = 32; Uptime_Days = 20; Restarts = 0; LastCheck = $date.AddMinutes(-3) },
    [PSCustomObject]@{ _Id = "svc-backup"; Name = "backup-agent"; Server = "srv-backup-01"; Status = "running"; CPU_Pct = 8.0; Mem_MB = 256; Uptime_Days = 7; Restarts = 0; LastCheck = $date.AddMinutes(-15) }
)
$services | New-BucketObject -Bucket services/daemons -KeyProperty _Id -Quiet
Use-Bucket "services/daemons"
Write-Host "  Created $($services.Count) service records" -ForegroundColor DarkGray

# ============================================================
# 7. Disk Usage
# ============================================================
Write-Host "[7] Disk Usage" -ForegroundColor Blue

$disks = @(
    [PSCustomObject]@{ _Id = "disk-web01-root"; Server = "srv-web-01"; Filesystem = "/"; Size_GB = 50; Used_GB = 22; Avail_GB = 28; Use_Pct = 44; Mount = "/" },
    [PSCustomObject]@{ _Id = "disk-web01-var"; Server = "srv-web-01"; Filesystem = "/var"; Size_GB = 100; Used_GB = 67; Avail_GB = 33; Use_Pct = 67; Mount = "/var" },
    [PSCustomObject]@{ _Id = "disk-db01-data"; Server = "srv-db-01"; Filesystem = "/data"; Size_GB = 2000; Used_GB = 1450; Avail_GB = 550; Use_Pct = 73; Mount = "/data" },
    [PSCustomObject]@{ _Id = "disk-db01-log"; Server = "srv-db-01"; Filesystem = "/var/log"; Size_GB = 200; Used_GB = 180; Avail_GB = 20; Use_Pct = 90; Mount = "/var/log"; Alert = "CRITICAL" },
    [PSCustomObject]@{ _Id = "disk-cache01-data"; Server = "srv-cache-01"; Filesystem = "/data"; Size_GB = 256; Used_GB = 200; Avail_GB = 56; Use_Pct = 78; Mount = "/data"; Alert = "WARNING" },
    [PSCustomObject]@{ _Id = "disk-backup01-backup"; Server = "srv-backup-01"; Filesystem = "/backup"; Size_GB = 16000; Used_GB = 8500; Avail_GB = 7500; Use_Pct = 53; Mount = "/backup" },
    [PSCustomObject]@{ _Id = "disk-dc01-c"; Server = "srv-dc-01"; Filesystem = "C:"; Size_GB = 100; Used_GB = 65; Avail_GB = 35; Use_Pct = 65; Mount = "C:" },
    [PSCustomObject]@{ _Id = "disk-dc01-d"; Server = "srv-dc-01"; Filesystem = "D:"; Size_GB = 400; Used_GB = 320; Avail_GB = 80; Use_Pct = 80; Mount = "D:"; Alert = "WARNING" }
)
$disks | New-BucketObject -Bucket storage/disks -KeyProperty _Id -Quiet
Use-Bucket "storage/disks"
Write-Host "  Created $($disks.Count) disk usage records" -ForegroundColor DarkGray

# ============================================================
# 8. DNS Records
# ============================================================
Write-Host "[8] DNS Records" -ForegroundColor Blue

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
    [PSCustomObject]@{ _Id = "dns-srv-cal"; Name = "_caldav._tcp.example.com"; Type = "SRV"; Value = "0 443 mail.example.com"; TTL = 3600; Zone = "example.com" }
)
$dnsRecords | New-BucketObject -Bucket network/dns -KeyProperty _Id -Quiet
Use-Bucket "network/dns"
Write-Host "  Created $($dnsRecords.Count) DNS records" -ForegroundColor DarkGray

# ============================================================
# 9. Installed Packages
# ============================================================
Write-Host "[9] Installed Packages" -ForegroundColor Blue

$packages = @(
    [PSCustomObject]@{ _Id = "pkg-apache2"; Server = "srv-web-01"; Name = "apache2"; Version = "2.4.52-1ubuntu4"; Architecture = "amd64"; Size_KB = 4800; Repo = "ubuntu jammy-security"; Installed = [DateTime]::Now.AddDays(-90) },
    [PSCustomObject]@{ _Id = "pkg-php83"; Server = "srv-web-01"; Name = "php8.3"; Version = "8.3.0-1jammy1"; Architecture = "amd64"; Size_KB = 15000; Repo = "ondrej php"; Installed = [DateTime]::Now.AddDays(-60) },
    [PSCustomObject]@{ _Id = "pkg-mysql84"; Server = "srv-db-01"; Name = "mysql-server-8.4"; Version = "8.4.0-1el8"; Architecture = "x86_64"; Size_KB = 95000; Repo = "mysql80-community"; Installed = [DateTime]::Now.AddDays(-120) },
    [PSCustomObject]@{ _Id = "pkg-redis7"; Server = "srv-cache-01"; Name = "redis-server"; Version = "7.0.15-1jammy1"; Architecture = "amd64"; Size_KB = 3200; Repo = "ubuntu jammy"; Installed = [DateTime]::Now.AddDays(-30) },
    [PSCustomObject]@{ _Id = "pkg-bind9"; Server = "srv-dns-01"; Name = "bind9"; Version = "9.18.18-0ubuntu1"; Architecture = "amd64"; Size_KB = 4800; Repo = "ubuntu jammy-updates"; Installed = [DateTime]::Now.AddDays(-180) },
    [PSCustomObject]@{ _Id = "pkg-postfix3"; Server = "srv-mail-01"; Name = "postfix"; Version = "3.7.6-0ubuntu1"; Architecture = "amd64"; Size_KB = 4200; Repo = "ubuntu jammy"; Installed = [DateTime]::Now.AddDays(-150) }
)
$packages | New-BucketObject -Bucket packages/installed -KeyProperty _Id -Quiet
Use-Bucket "packages/installed"
Write-Host "  Created $($packages.Count) package records" -ForegroundColor DarkGray

# ============================================================
# 10. Scheduled Tasks / Cron
# ============================================================
Write-Host "[10] Scheduled Tasks" -ForegroundColor Blue

$scheduledTasks = @(
    [PSCustomObject]@{ _Id = "cron-daily-maintenance"; Name = "Daily Maintenance"; User = "root"; Schedule = "0 3 * * *"; Command = "/usr/local/bin/maintenance.sh"; NextRun = $date.AddHours(4); LastRun = $date.AddDays(-1); Status = "active" },
    [PSCustomObject]@{ _Id = "cron-hourly-logs"; Name = "Hourly Log Rotate"; User = "root"; Schedule = "0 * * * *"; Command = "/usr/sbin/logrotate /etc/logrotate.conf"; NextRun = $date.AddHours(1); LastRun = $date.AddHours(-1); Status = "active" },
    [PSCustomObject]@{ _Id = "cron-weekly-updates"; Name = "Weekly Security Updates"; User = "root"; Schedule = "0 4 * * 0"; Command = "/usr/bin/apt update && /usr/bin/apt upgrade -y"; NextRun = $date.AddDays(4); LastRun = $date.AddDays(-3); Status = "active" },
    [PSCustomObject]@{ _Id = "cron-db-vacuum"; Name = "Database Vacuum"; User = "postgres"; Schedule = "0 2 * * *"; Command = "/usr/bin/vacuumdb --all --analyze"; NextRun = $date.AddHours(3); LastRun = $date.AddDays(-1); Status = "active" },
    [PSCustomObject]@{ _Id = "win-daily-backup"; Name = "Windows Backup Job"; User = "SYSTEM"; Schedule = "0 2 * * *"; Command = "wbadmin.exe start backup -backupTarget:D:"; NextRun = $date.AddHours(3); LastRun = $date.AddDays(-1); Status = "active"; Platform = "Windows" },
    [PSCustomObject]@{ _Id = "cron-disabled-old"; Name = "Old Cleanup Script"; User = "admin"; Schedule = "0 5 * * *"; Command = "/home/admin/cleanup.sh"; NextRun = $null; LastRun = $date.AddDays(-90); Status = "disabled" }
)
$scheduledTasks | New-BucketObject -Bucket scheduled/tasks -KeyProperty _Id -Quiet
Use-Bucket "scheduled/tasks"
Write-Host "  Created $($scheduledTasks.Count) scheduled task records" -ForegroundColor DarkGray

# ============================================================
# Summary
# ============================================================
Write-Host ""
$totalBuckets = @(
    "servers/inventory",
    "network/vlans",
    "network/firewall",
    "network/dns",
    "ad/users",
    "ad/groups",
    "certificates/ssl",
    "backups/jobs",
    "services/daemons",
    "storage/disks",
    "packages/installed",
    "scheduled/tasks"
)

$totalObjects = ($servers.Count + $networks.Count + $firewall.Count + $adUsers.Count + $groups.Count + $sslCerts.Count + $backups.Count + $services.Count + $disks.Count + $dnsRecords.Count + $packages.Count + $scheduledTasks.Count)

Write-Host "  Buckets created: $($totalBuckets.Count)" -ForegroundColor DarkGray
Write-Host "  Objects created: $totalObjects" -ForegroundColor DarkGray

Write-Host "`n[Bucket Overview]" -ForegroundColor Blue
Get-Bucket -AsTree | Select-Object -First 20

foreach ($b in $createdBuckets) {
    Remove-Bucket $b -Force -Confirm:$false -WarningAction SilentlyContinue
}

Write-InfoBlock -Mode bottom
