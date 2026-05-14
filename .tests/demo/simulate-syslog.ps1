#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generates realistic RFC 3164 syslog lines for testing ingest-syslog.ps1.
.DESCRIPTION
    Emits raw syslog text lines to stdout with varied hosts, facilities,
    severities, tags, and realistic message bodies across a configurable
    time window. Pipe directly into ingest-syslog.ps1:

    .tests/demo/simulate-syslog.ps1 -Count 200 | .tests/demo/ingest-syslog.ps1

    Or redirect to a file for replay:

    .tests/demo/simulate-syslog.ps1 -Count 500 -Seed 42 > sample.log
.PARAMETER Count
    Total lines to generate. Default: 100.
.PARAMETER Hosts
    Hostnames to distribute events across. Default: web01,web02,db01,lb01.
.PARAMETER Hours
    Time window (hours) to backdate timestamps across. Default: 24.
.PARAMETER Seed
    Random seed for reproducible output. Default: none.
.PARAMETER Rate
    Fraction of lines that are error/critical (0.0-1.0). Default: 0.15.
#>

param(
    [int]$Count = 100,
    [string[]]$Hosts = @("web01", "web02", "db01", "lb01"),
    [int]$Hours = 24,
    [int]$Seed,
    [double]$Rate = 0.15
)

$ErrorActionPreference = "Stop"

if ($PSBoundParameters.ContainsKey('Seed')) { $Random = [System.Random]::new($Seed) }
else { $Random = [System.Random]::new() }

# facility * 8 = PRI base
$facilities = @(
    @{ Name = "kern";    PriBase = 0  }
    @{ Name = "user";    PriBase = 8  }
    @{ Name = "mail";    PriBase = 16 }
    @{ Name = "daemon";  PriBase = 24 }
    @{ Name = "auth";    PriBase = 32 }
    @{ Name = "syslog";  PriBase = 40 }
    @{ Name = "cron";    PriBase = 72 }
    @{ Name = "local0";  PriBase = 128 }
    @{ Name = "local1";  PriBase = 136 }
    @{ Name = "local2";  PriBase = 144 }
)

$severities = @(
    @{ Name = "emerg";   Code = 0; Weight = 0  }
    @{ Name = "alert";   Code = 1; Weight = 0  }
    @{ Name = "crit";    Code = 2; Weight = 5  }
    @{ Name = "err";     Code = 3; Weight = 10 }
    @{ Name = "warning"; Code = 4; Weight = 15 }
    @{ Name = "notice";  Code = 5; Weight = 20 }
    @{ Name = "info";    Code = 6; Weight = 45 }
    @{ Name = "debug";   Code = 7; Weight = 5  }
)

$now = Get-Date
$epoch = $now.AddHours(-$Hours)

# Normal-severity pool (weighted)
$sevPool = @()
foreach ($s in $severities) { for ($i = 0; $i -lt $s.Weight; $i++) { $sevPool += $s.Code } }

# Message templates keyed by tag
$messages = @{
    "sshd" = @(
        "Failed password for root from {IP} port {Port} ssh2"
        "Failed password for invalid user admin from {IP} port {Port} ssh2"
        "Accepted publickey for {User} from {IP} port {Port} ssh2: RSA SHA256:{Hash}"
        "session opened for user {User} by (uid=0)"
        "session closed for user {User}"
        "Did not receive identification string from {IP}"
        "Connection closed by authenticating user {User} {IP} port {Port}"
        "pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost={IP}"
        "Received disconnect from {IP} port {Port}:11: disconnected by user"
    )
    "postgres" = @(
        "connection received: host={IP} port={Port}"
        "connection authorized: user={User} database={DB}"
        "LOG:  checkpoint starting: time"
        "LOG:  checkpoint complete: wrote {KB} kB buffer ({Pct}%)"
        "LOG:  statement: SELECT * FROM {Table} WHERE id = {N}"
        "ERROR:  relation ""{Table}"" does not exist at character {N}"
        "ERROR:  duplicate key value violates unique constraint ""{Table}_pkey"""
        "LOG:  automatic vacuum of table ""{DB}.public.{Table}"": index scans: {N}"
        "FATAL:  terminating connection due to administrator command"
        "LOG:  unexpected EOF on client connection with an open transaction"
    )
    "nginx" = @(
        '{IP} - - [{Date}] "GET /{Path} HTTP/1.1" {Status} {Bytes} "-" "Mozilla/5.0"'
        '{IP} - - [{Date}] "POST /{Path} HTTP/1.1" {Status} {Bytes} "-" "curl/7.68"'
        '{IP} - - [{Date}] "GET /{Path} HTTP/2.0" {Status} {Bytes} "-" "Amazon CloudFront"'
        "upstream timed out (110: Connection timed out) while connecting to upstream, client: {IP}"
        "open() ""/var/www/{Path}"" failed (2: No such file or directory), client: {IP}"
        "{IP} - admin [Date] ""GET /{Path} HTTP/1.1"" 200 {Bytes} ""-"" ""python-requests"" - {Ms}ms"
        "recv() failed (104: Connection reset by peer) while reading response header from upstream"
    )
    "systemd" = @(
        "Started {Service} - high-performance HTTP server"
        "Stopping {Service} - high-performance HTTP server"
        "Started {Service} - PostgreSQL database server"
        "Reached target Multi-User System - graphical interface"
        "Starting Session {N} of user {User}"
        "Stopped {Service} - System Logging Service"
        "Failed to start {Service} - Docker Application Container Engine"
        "Reloading {Service} - sshd configuration"
        "Created slice User Slice of {User}"
        "Started Daily apt upgrade and clean activities"
    )
    "dockerd" = @(
        "container {Container} started (image: {Image}:latest)"
        "container {Container} exited with code {N}"
        "Image {Image}:latest pulled from registry-1.docker.io"
        "Health check for container {Container} passed: HTTP 200"
        "Health check for container {Container} failed: connection refused"
        "Layer already exists for {Image}:{Tag}"
        "Downloading layer {Bytes} MB / {Total} MB for {Image}:latest"
        "Container {Container} is restarting (exit code {N})"
    )
    "chronyd" = @(
        "Selected source {IP} {Stratum}"
        "System clock wrong by {Offset} seconds, adjustment started"
        "System clock wrong by {Offset} seconds, adjustment completed"
        "NTP response received from {IP} offset {Offset}"
        "Source {IP} replaced by {IP2}"
        "Frequency error {Ppm} ppm exceeds maximum {MaxPpm}"
        "Can't synchronize: no selectable sources"
    )
    "kernel" = @(
        "Out of memory: Killed process {PID} ({Process}) total-vm:{KB}kB"
        "usb {N}-{Bus}: new high-speed USB device number {Dev} using xhci_hcd"
        "device eth0 entered promiscuous mode"
        "TCP: time wait bucket table overflow"
        "EXT4-fs (sda{N}): mounted filesystem with ordered data mode. Opts: (null)"
        "{Interface}: NIC Link is Down"
        "{Interface}: NIC Link is Up 1000 Mbps Full Duplex"
        "SELinux:  {N} avc denied {Action} for pid={PID} comm=""{Process}"" path=""{Path}"" dev=sda{N} ino={Inode}"
    )
    "cron" = @(
        "(root) CMD ( /usr/lib/sa/sa1 {N} {N} )"
        "(root) CMD ( test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.daily ))"
        "({User}) CMD ( /opt/scripts/backup.sh --type {Type} >/dev/null 2>&1 )"
        "pam_unix(cron:session): session opened for user {User} by (uid=0)"
        "pam_unix(cron:session): session closed for user {User}"
        "FAILED to authorize user {User} with PAM (Authentication failure)"
    )
    "ftp" = @(
        "Connection from {IP} port {Port}"
        "USER {User} - - [{Date}] -> 331 Please specify the password"
        "FAIL LOGIN {User} from {IP}"
        "OK LOGIN {User} from {IP} - connected {Seconds}s"
        "FTP session closed for user {User}"
    )
}

$tags = @($messages.Keys)

$pidPool = 1000..65000
$userPool = @("root", "www-data", "postgres", "admin", "backup", "deploy", "monitoring", "ansible")
$pathPool = @("api/users", "api/orders", "status", "healthz", "metrics", "login", "static/js/app.js", "static/css/main.css", "robots.txt")
$dbPool = @("appdb", "logsdb", "metricsdb", "configdb")
$tablePool = @("users", "orders", "sessions", "audit_log", "inventory", "payments")
$servicePool = @("nginx", "postgresql", "docker", "sshd", "rsyslog", "prometheus", "grafana")
$imagePool = @("nginx", "postgres", "redis", "app-backend", "auth-service", "prom/prometheus")
$containerPool = @("web-frontend-1", "api-gateway-2", "db-primary", "cache-1", "worker-3")
$ipPool = @("10.0.0.1", "10.0.0.45", "10.0.1.100", "10.0.2.50", "192.168.1.10", "192.168.1.20", "172.16.0.1", "172.16.0.2")

$alpha = "abcdefghijklmnopqrstuvwxyz"

function Get-NextTimestamp {
    $span = $epoch + [TimeSpan]::FromSeconds($Random.NextDouble() * $Hours * 3600)
    $span.ToString("MMM dd HH:mm:ss")
}

function Get-RandomItem { param($Items) $Items[$Random.Next($Items.Count)] }

function Generate-Pri {
    param([int]$FacilityBase, [int]$SeverityCode)
    $FacilityBase + $SeverityCode
}

$sampleLineNumber = 0
while ($sampleLineNumber -lt $Count) {
    $hostname = Get-RandomItem $Hosts
    $nowTime = Get-NextTimestamp
    $tag = Get-RandomItem $tags
    $facility = Get-RandomItem $facilities
    $logPid = Get-RandomItem $pidPool

    # Roll for severity: error/crit at Rate, otherwise weighted pool
    if ($Random.NextDouble() -lt $Rate) {
        $sevCode = Get-RandomItem -Items @(2, 3)
    } else {
        $sevCode = Get-RandomItem $sevPool
    }

    $pri = Generate-Pri -FacilityBase $facility.PriBase -SeverityCode $sevCode

    # Build message from template
    $template = Get-RandomItem $messages[$tag]
    $msg = $template
    $msg = $msg.Replace('{IP}',  (Get-RandomItem $ipPool))
    $msg = $msg.Replace('{Port}', (Get-RandomItem @(1024..65535)))
    $msg = $msg.Replace('{User}', (Get-RandomItem $userPool))
    $msg = $msg.Replace('{DB}',   (Get-RandomItem $dbPool))
    $msg = $msg.Replace('{Table}', (Get-RandomItem $tablePool))
    $msg = $msg.Replace('{Path}', (Get-RandomItem $pathPool))
    $msg = $msg.Replace('{Service}', (Get-RandomItem $servicePool))
    $msg = $msg.Replace('{Image}', (Get-RandomItem $imagePool))
    $msg = $msg.Replace('{Container}', (Get-RandomItem $containerPool))
    $msg = $msg.Replace('{IP2}', (Get-RandomItem $ipPool))
    $msg = $msg.Replace('{Interface}', (Get-RandomItem @("eth0", "eth1", "ens192", "bond0")))
    $msg = $msg.Replace('{Process}', (Get-RandomItem @("nginx", "postgres", "python3", "java", "node", "prometheus", "sshd")))
    $msg = $msg.Replace('{Action}', (Get-RandomItem @("read", "write", "execmod", "create")))
    $msg = $msg.Replace('{Type}', (Get-RandomItem @("daily", "weekly", "incremental", "full")))
    $msg = $msg.Replace('{Stratum}', (Get-RandomItem @(1..5)))
    $msg = $msg.Replace('{Tag}', (Get-RandomItem @("v1.0", "v2.3", "latest", "stable")))
    $msg = $msg.Replace('{N}', $Random.Next(1, 9999))
    $msg = $msg.Replace('{N2}', $Random.Next(1, 999))
    $msg = $msg.Replace('{KB}', $Random.Next(4, 256))
    $msg = $msg.Replace('{Pct}', $Random.Next(10, 100))
    $msg = $msg.Replace('{Status}', (Get-RandomItem @("200", "201", "204", "301", "302", "304", "400", "401", "403", "404", "500", "502", "503")))
    $msg = $msg.Replace('{Bytes}', $Random.Next(100, 50000))
    $msg = $msg.Replace('{Ms}', $Random.Next(10, 30000))
    $msg = $msg.Replace('{Offset}', ($Random.NextDouble() * 200 - 100).ToString("F3"))
    $msg = $msg.Replace('{Ppm}', $Random.Next(1, 500))
    $msg = $msg.Replace('{MaxPpm}', $Random.Next(500, 1000))
    $msg = $msg.Replace('{Dev}', $Random.Next(1, 10))
    $msg = $msg.Replace('{Bus}', $Random.Next(1, 5))
    $msg = $msg.Replace('{Inode}', $Random.Next(100000, 999999))
    $msg = $msg.Replace('{PID}', $Random.Next(1000, 65000))
    $msg = $msg.Replace('{Dev}', $Random.Next(1, 10))
    $msg = $msg.Replace('{Total}', $Random.Next(10, 200))
    $msg = $msg.Replace('{Hash}', -join (1..16 | ForEach-Object { $alpha[$Random.Next(26)] }))
    $msg = $msg.Replace('{Seconds}', $Random.Next(1, 600))
    $msg = $msg.Replace('{Bus}', $Random.Next(1, 5))

    # Fill random Date placeholder
    $msg = $msg.Replace('{Date}', $nowTime)

    Write-Host "<${pri}>${nowTime} ${hostname} ${tag}[${logPid}]: ${msg}"
    $sampleLineNumber++
}
