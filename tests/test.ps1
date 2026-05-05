#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test script for the Buckets module.
#>

Remove-Module Buckets -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../Buckets" -Force

Remove-Bucket "*" -Force 2>$null

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Buckets Module - Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$sw = [System.Diagnostics.Stopwatch]::StartNew()

# ============================================================
# 1. Simple objects (hashtables)
# ============================================================
Write-Host "[1] Simple hashtables" -ForegroundColor Yellow

$users = @(
    @{ Name = "Alice"; Email = "alice@example.com"; Role = "admin"; Active = $true }
    @{ Name = "Bob"; Email = "bob@example.com"; Role = "user"; Active = $true }
    @{ Name = "Charlie"; Email = "charlie@example.com"; Role = "user"; Active = $false }
    @{ Name = "Diana"; Email = "diana@example.com"; Role = "manager"; Active = $true }
)

Save-BucketObject -Bucket users -InputObject $users -Key Name
Write-Host "  Saved $($users.Count) users (keyed by Name)" -ForegroundColor DarkGray

# ============================================================
# 2. Nested PSCustomObjects
# ============================================================
Write-Host "`n[2] Nested PSCustomObjects" -ForegroundColor Yellow

$orders = @(
    [PSCustomObject]@{
        OrderId = "ORD-001"
        Customer = "Alice"
        Items = @(
            [PSCustomObject]@{ Product = "Widget"; Qty = 3; Price = 9.99 }
            [PSCustomObject]@{ Product = "Gadget"; Qty = 1; Price = 24.99 }
        )
        Shipping = [PSCustomObject]@{
            Method = "Express"
            Address = [PSCustomObject]@{ City = "Portland"; State = "OR" }
        }
        Status = "shipped"
    }
    [PSCustomObject]@{
        OrderId = "ORD-002"
        Customer = "Bob"
        Items = @(
            [PSCustomObject]@{ Product = "Doohickey"; Qty = 5; Price = 4.99 }
        )
        Shipping = [PSCustomObject]@{
            Method = "Standard"
            Address = [PSCustomObject]@{ City = "Seattle"; State = "WA" }
        }
        Status = "processing"
    }
)

Save-BucketObject -Bucket orders -InputObject $orders -Key OrderId
Write-Host "  Saved $($orders.Count) orders" -ForegroundColor DarkGray

# ============================================================
# 3. System objects (FileInfo) - triggers binary fallback
# ============================================================
Write-Host "`n[3] System objects (FileInfo - auto binary fallback)" -ForegroundColor Yellow

Get-ChildItem $PSScriptRoot | Where-Object { $_.Name -notmatch "^\." } | Save-BucketObject -Bucket files -Key Name
Write-Host "  Saved directory listing (complex objects fallback to .dat)" -ForegroundColor DarkGray

# ============================================================
# 4. Log entries with unique keys
# ============================================================
Write-Host "`n[4] Log entries" -ForegroundColor Yellow

$logEntries = @(
    @{ Id = "log-001"; Level = "INFO"; Message = "Application started" }
    @{ Id = "log-002"; Level = "DEBUG"; Message = "Loading configuration" }
    @{ Id = "log-003"; Level = "WARN"; Message = "Deprecated API call" }
    @{ Id = "log-004"; Level = "ERROR"; Message = "Connection timeout" }
)

Save-BucketObject -Bucket logs -InputObject $logEntries -Key Id
Write-Host "  Saved $($logEntries.Count) log entries" -ForegroundColor DarkGray

# ============================================================
# 5. Config (JSON format)
# ============================================================
Write-Host "`n[5] Config (JSON format)" -ForegroundColor Yellow

$config = [PSCustomObject]@{
    _Id = "app-config"
    Database = [PSCustomObject]@{ Host = "localhost"; Port = 5432; Name = "app_db" }
    Cache = [PSCustomObject]@{ Enabled = $true; TTL = 3600; Provider = "Redis" }
    Logging = [PSCustomObject]@{ Level = "Debug"; Outputs = @("Console", "File") }
    Version = "2.1.0"
}

Save-BucketObject -Bucket config -InputObject $config -Key _Id -AsJson
Write-Host "  Saved config as JSON" -ForegroundColor DarkGray

# ============================================================
# 6. Metrics
# ============================================================
Write-Host "`n[6] Performance metrics (24 hours)" -ForegroundColor Yellow

$metrics = foreach ($hour in 0..23) {
    [PSCustomObject]@{
        Hour = $hour
        CPU = [math]::Round((Get-Random -Min 5 -Max 95), 2)
        Memory = [math]::Round((Get-Random -Min 40 -Max 85), 2)
        Requests = Get-Random -Min 100 -Max 5000
    }
}

Save-BucketObject -Bucket metrics -InputObject $metrics -Key Hour
Write-Host "  Saved 24 hourly records" -ForegroundColor DarkGray

# ============================================================
# 7. Mixed formats in same bucket
# ============================================================
Write-Host "`n[7] Mixed formats in same bucket" -ForegroundColor Yellow

Save-BucketObject -Bucket mixed -InputObject @{ _Id = "m1"; Type = "json"; Value = 1 } -Key _Id -AsJson
Save-BucketObject -Bucket mixed -InputObject @{ _Id = "m2"; Type = "binary"; Value = 2 } -Key _Id
Save-BucketObject -Bucket mixed -InputObject @{ _Id = "m3"; Type = "json-fallback" } -Key _Id -AsJson
Write-Host "  Saved 3 objects (2 JSON, 1 binary)" -ForegroundColor DarkGray

# ============================================================
# 8. Secure bucket objects (SecretStore)
# ============================================================
Write-Host "`n[8] Secure bucket objects (SecretStore)" -ForegroundColor Yellow

$secureCommands = @("Get-SecretInfo", "Get-Secret", "Set-Secret", "Remove-Secret", "Get-SecretVault")
$missingSecureCommands = @($secureCommands | Where-Object { -not (Get-Command -Name $_ -ErrorAction SilentlyContinue) })

if ($missingSecureCommands.Count -gt 0) {
    Write-Host "  Skipped secure tests (missing command(s): $($missingSecureCommands -join ', '))" -ForegroundColor Yellow
}
else {
    try {
        $availableVaults = @(Get-SecretVault -ErrorAction Stop)
        if ($availableVaults.Count -eq 0) {
            Write-Host "  Skipped secure tests (no registered vault available)" -ForegroundColor Yellow
        }
        else {
            $selectedVault = $availableVaults[0].Name
            $testSecretPassword = $env:BUCKETS_TEST_SECRET_PASSWORD
            if ([string]::IsNullOrWhiteSpace($testSecretPassword)) {
                Write-Host "  Skipped secure tests (set BUCKETS_TEST_SECRET_PASSWORD to enable secure flow)" -ForegroundColor Yellow
            }
            else {
                $secureItems = @(
                    [PSCustomObject]@{ Name = "secure-user-1"; Role = "admin"; Token = "alpha-token" }
                    [PSCustomObject]@{ Name = "secure-user-2"; Role = "user"; Token = "beta-token" }
                )

                $secureSaveParams = @{
                    Bucket = "secure-users"
                    InputObject = $secureItems
                    Key = "Name"
                    Secure = $true
                    Vault = $selectedVault
                }
                $secureMixedParams = @{
                    Bucket = "mixed"
                    InputObject = @{ _Id = "m4"; Type = "secure"; Value = 4 }
                    Key = "_Id"
                    Secure = $true
                    Vault = $selectedVault
                }

                $secureSaveParams.Pass = $testSecretPassword
                $secureMixedParams.Pass = $testSecretPassword
                Write-Host "  Using -Pass from BUCKETS_TEST_SECRET_PASSWORD" -ForegroundColor DarkGray

                Save-BucketObject @secureSaveParams | Out-Null
                Save-BucketObject @secureMixedParams | Out-Null

                $secureAdmin = Get-BucketObject -Bucket secure-users -IncludeSecure -Filter { $_.Role -eq "admin" } | Select-Object -First 1
                if ($secureAdmin) {
                    Write-Host "  Retrieved secure object: $($secureAdmin.Name)" -ForegroundColor DarkGray
                }

                $secureToUpdate = Get-BucketObject -Bucket secure-users -IncludeSecure -Key "secure-user-1" | Select-Object -First 1
                if ($secureToUpdate) {
                    $secureToUpdate.Token = "alpha-token-rotated"
                    $secureToUpdate.PSObject.Properties.Remove("_BucketName")
                    $secureToUpdate.PSObject.Properties.Remove("_BucketKey")
                    $secureToUpdate.PSObject.Properties.Remove("_BucketFile")
                    Update-BucketObject -Bucket secure-users -Key "secure-user-1" -InputObject $secureToUpdate | Out-Null
                }

                Remove-BucketObject -Bucket secure-users -Key "secure-user-2"
                $remainingSecureCount = @(Get-BucketObject -Bucket secure-users -IncludeSecure).Count
                Write-Host "  Secure objects after update/remove: $remainingSecureCount" -ForegroundColor DarkGray
            }
        }
    }
    catch {
        Write-Host "  Secure tests skipped due to SecretStore error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ============================================================
# VERIFICATION
# ============================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Verification" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "[Buckets]" -ForegroundColor Green
Get-Bucket | Format-Table -AutoSize

Write-Host "[Users] Filter Role = 'admin'" -ForegroundColor Green
Get-BucketObject -Bucket users -Filter { $_.Role -eq "admin" } | ForEach-Object { Write-Host "  $($_.Name) ($($_.Email))" }

Write-Host "`n[Orders] Shipped with Express shipping" -ForegroundColor Green
Get-BucketObject -Bucket orders -Filter { $_.Status -eq "shipped" -and $_.Shipping.Method -eq "Express" } | ForEach-Object { Write-Host "  $($_.OrderId) by $($_.Customer)" }

Write-Host "`n[Config] JSON verification" -ForegroundColor Green
$cfg = Get-BucketObject -Bucket config -Key "app-config"
Write-Host "  DB: $($cfg.Database.Host):$($cfg.Database.Port)/$($cfg.Database.Name)"
Write-Host "  Cache: $($cfg.Cache.Provider) (TTL: $($cfg.Cache.TTL)s)"

Write-Host "`n[Metrics] Hours with CPU > 80%" -ForegroundColor Green
Get-BucketObject -Bucket metrics -Filter { $_.CPU -gt 80 } | ForEach-Object { Write-Host "  Hour $($_.Hour): CPU=$($_.CPU)%, Mem=$($_.Memory)%" }

Write-Host "`n[Logs] Filter WARN/ERROR" -ForegroundColor Green
Get-BucketObject -Bucket logs -Filter { $_.Level -in @("WARN", "ERROR") } | ForEach-Object { Write-Host "  [$($_.Level)] $($_.Message)" }

Write-Host "`n[Mixed] Formats" -ForegroundColor Green
Get-BucketObject -Bucket mixed | ForEach-Object {
    $ext = [System.IO.Path]::GetExtension($_._BucketFile)
    Write-Host "  $($_.Type) ($ext)"
}

# ============================================================
# STATS
# ============================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Stats" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

foreach ($b in (Get-Bucket)) {
    $stats = Get-BucketStats -Bucket $b.Name
    Write-Host "  $($b.Name): $($stats.ObjectCount) objects, $($stats.TotalSize)"
}

$elapsed = $sw.ElapsedMilliseconds
Write-Host "`nTotal time: ${elapsed}ms" -ForegroundColor Cyan
