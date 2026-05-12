<#
.SYNOPSIS
    A PowerShell module for file-based PSObject storage using directory-backed buckets.
.DESCRIPTION
    Buckets provides a simple way to store, retrieve, and manage PowerShell objects
    in directory-based collections called "buckets". Objects are automatically serialized
    to JSON (default) or binary format, with auto-depth adjustment for JSON (up to depth
    100) and automatic fallback to binary when JSON cannot faithfully represent the object.
    Use -AsBinary for full .NET type preservation via PSSerializer.
#>

# --- Provider compilation ---
$script:ProviderCsPath = Join-Path $PSScriptRoot "BucketsProvider.cs"
$script:ProviderDllPath = Join-Path $PSScriptRoot "BucketsProvider.dll"
$script:ProviderFormatPath = Join-Path $PSScriptRoot "BucketsProvider.format.ps1xml"

if (-not (Test-Path $script:ProviderDllPath)) {
    $csCode = Get-Content -Path $script:ProviderCsPath -Raw
    Add-Type -TypeDefinition $csCode -OutputAssembly $script:ProviderDllPath -Language CSharp -ErrorAction Stop
}
Import-Module $script:ProviderDllPath

if (Test-Path $script:ProviderFormatPath) {
    Update-FormatData -PrependPath $script:ProviderFormatPath -ErrorAction SilentlyContinue
}

Update-TypeData -TypeName Buckets.Provider.BucketItemInfo `
    -DefaultDisplayPropertySet Type, LastWriteTime, CreationTime, Size, Name `
    -ErrorAction SilentlyContinue

# --- State ---
$script:BucketPathCache = @{}
$script:LastPWD = $PWD.Path
$script:BucketRoot = $null
$script:FunnelCache = @{}
$script:BuiltinFunnelsDir = Join-Path $PSScriptRoot "funnels"
$script:ClearCache = { $script:BucketPathCache.Clear(); $script:LastPWD = $PWD.Path }

# --- Output colors ---
$script:CPath   = 'Cyan'
$script:CNum    = 'Magenta'
$script:CAction = 'Blue'
$script:CMuted  = 'DarkGray'
$script:CError  = 'Red'
$script:CSkip   = 'Yellow'

# --- Hidden property helper ---
$script:HiddenFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Public
$script:IsHiddenProp = [System.Management.Automation.PSNoteProperty].GetProperty('IsHidden', $script:HiddenFlags)
function Add-HiddenProperty {
    param([PSObject]$Target, [string]$Name, $Value)
    $prop = [System.Management.Automation.PSNoteProperty]::new($Name, $Value)
    $script:IsHiddenProp.SetValue($prop, $true)
    $Target.PSObject.Properties.Add($prop)
}

function Resolve-ObjectType {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$FileInfo)
    $isCompressed = $false
    if ($FileInfo.Extension -eq ".json") {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($FileInfo.FullName)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes).TrimStart()
            if ($text.StartsWith("[")) { return @{ Type = "Array"; IsCompressed = $false } }
            if ($text.StartsWith("{")) { return @{ Type = "Object"; IsCompressed = $false } }
            return @{ Type = "Value"; IsCompressed = $false }
        } catch {
            return @{ Type = "Object"; IsCompressed = $false }
        }
    }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($FileInfo.FullName)
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0x1F -and $bytes[1] -eq 0x8B) {
            $isCompressed = $true
            try {
                $ms = [System.IO.MemoryStream]::new($bytes)
                $gz = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
                $buf = [byte[]]::new(2048)
                $null = $gz.Read($buf, 0, 2048)
                $gz.Close(); $ms.Close()
                $text = [System.Text.Encoding]::UTF8.GetString($buf).TrimStart()
                if ($text -match '<T>\s*\[.*?\]') { return @{ Type = "Array"; IsCompressed = $true } }
                if ($text -match '<T>\s*System\.Collections\.(ArrayList|Generic\.List)') { return @{ Type = "Array"; IsCompressed = $true } }
                if ($text -match '<T>\s*System\.(String|Int\d+|Boolean|Double|Single|Decimal|Long|Float|Byte)') { return @{ Type = "Value"; IsCompressed = $true } }
                return @{ Type = "Object"; IsCompressed = $true }
            } catch {
                return @{ Type = "Object"; IsCompressed = $true }
            }
        }
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        if ($text -match '<T>\s*\[.*?\]') { return @{ Type = "Array"; IsCompressed = $false } }
        if ($text -match '<T>\s*System\.Collections\.(ArrayList|Generic\.List)') { return @{ Type = "Array"; IsCompressed = $false } }
        if ($text -match '<T>\s*System\.(String|Int\d+|Boolean|Double|Single|Decimal|Long|Float|Byte)') { return @{ Type = "Value"; IsCompressed = $false } }
        return @{ Type = "Object"; IsCompressed = $false }
    } catch {
        return @{ Type = "Object"; IsCompressed = $false }
    }
}

# --- Core infrastructure (internal helpers) ---

function Get-DefaultPath {
    if ($script:BucketRoot) { return $script:BucketRoot }
    if ($env:BUCKETS_ROOT) { return $env:BUCKETS_ROOT }
    return Join-Path $HOME ".buckets"
}

function Resolve-SafePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    try { return [System.IO.Path]::GetFullPath($Path) }
    catch { throw "Invalid path '$Path': $_" }
}

function Get-BucketsSystemPath {
    [CmdletBinding()]
    param()
    $systemRoot = Join-Path $HOME ".buckets-system"
    if (-not (Test-Path $systemRoot)) { New-Item -ItemType Directory -Path $systemRoot -Force | Out-Null }
    return $systemRoot
}

function Get-FunnelDefinition {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($script:FunnelCache.ContainsKey($Name)) { return $script:FunnelCache[$Name] }
    $userFile = Join-Path (Join-Path (Get-BucketsSystemPath) "funnels") "$Name.json"
    if (Test-Path $userFile) {
        $def = Get-Content -Path $userFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:FunnelCache[$Name] = $def
        return $def
    }
    $builtinFile = Join-Path $script:BuiltinFunnelsDir "$Name.json"
    if (Test-Path $builtinFile) {
        $def = Get-Content -Path $builtinFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:FunnelCache[$Name] = $def
        return $def
    }
    throw "Funnel '$Name' not found"
}

function Resolve-Funnel {
    param([object]$Funnel)
    if (-not $Funnel) { return $null }
    if ($Funnel -is [scriptblock]) {
        return @{ Filter = $Funnel }
    }
    $def = Get-FunnelDefinition -Name $Funnel
    $result = @{ Filter = [scriptblock]::Create($def.Filter) }
    if ($def.AppliesTo) {
        $at = $def.AppliesTo.Trim()
        if ($at -match '^\[.+\]$') { $result.AppliesTo = [scriptblock]::Create("`$_ -is $at") }
        else { $result.AppliesTo = [scriptblock]::Create($at) }
    }
    return $result
}

function Get-BucketPath {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Path
    )

    if ($script:LastPWD -ne $PWD.Path) { & $script:ClearCache }
    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $cacheKey = "${Path}|${Name}"
    if ($script:BucketPathCache.ContainsKey($cacheKey)) {
        return $script:BucketPathCache[$cacheKey]
    }
    $bucketPath = Resolve-SafePath -Path (Join-Path $Path $Name)
    $script:BucketPathCache[$cacheKey] = $bucketPath
    return $bucketPath
}

function Get-BucketFilename {
    param($Item, [string]$Key, [string]$KeyProperty, [bool]$AsTimestamp, [int]$Index, [string]$Extension)

    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $safeKey = $Key -replace '[\\/:\*\?"<>\|\[\]]', '_'
        if ([string]::IsNullOrWhiteSpace($safeKey) -or $safeKey -match '^_+$') {
            Write-Verbose "Key is empty after sanitization ('$Key' -> '$safeKey'), skipping"
            return $null
        }
        return [PSCustomObject]@{ Filename = "${safeKey}${Extension}"; Sanitized = $safeKey -ne $Key; OriginalKey = $Key }
    }

    if (-not [string]::IsNullOrWhiteSpace($KeyProperty)) {
        $keyValue = $Item.$KeyProperty
        if ($null -eq $keyValue) {
            Write-Verbose "Property '$KeyProperty' not found on object, skipping"
            return $null
        }
        $safeKey = $keyValue -replace '[\\/:\*\?"<>\|\[\]]', '_'
        if ([string]::IsNullOrWhiteSpace($safeKey) -or $safeKey -match '^_+$') {
            Write-Verbose "Key for object is empty after sanitization ('$keyValue' -> '$safeKey'), skipping"
            return $null
        }
        return [PSCustomObject]@{ Filename = "${safeKey}${Extension}"; Sanitized = $safeKey -ne "$keyValue"; OriginalKey = "$keyValue" }
    }

    if ($AsTimestamp) {
        return [PSCustomObject]@{ Filename = "$(Get-Date -Format 'yyyyMMddHHmmssfff')_${Index}${Extension}"; Sanitized = $false; OriginalKey = $null }
    }

    return [PSCustomObject]@{ Filename = "$([Guid]::NewGuid())${Extension}"; Sanitized = $false; OriginalKey = $null }
}

function Resolve-ItemKey {
    param($Item, [string]$Key, [string]$KeyProperty, [int]$Index)

    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $safeKey = $Key -replace '[\\/:\*\?"<>\|\[\]]', '_'
        if ([string]::IsNullOrWhiteSpace($safeKey) -or $safeKey -match '^_+$') { return $null }
        return $safeKey
    }

    if (-not [string]::IsNullOrWhiteSpace($KeyProperty)) {
        $keyValue = $Item.$KeyProperty
        if ($null -eq $keyValue) { return $null }
        $safeKey = $keyValue -replace '[\\/:\*\?"<>\|\[\]]', '_'
        if ([string]::IsNullOrWhiteSpace($safeKey) -or $safeKey -match '^_+$') { return $null }
        return $safeKey
    }

    return "$Index"
}

function Save-BucketFile {
    param(
        [string]$Path, $Item, [string]$Extension, [bool]$AsBinary, [bool]$Compress,
        [int]$Depth = 20, [int]$BinaryDepth = 5, [bool]$Overwrite,
        [string]$BucketPath, [string]$Bucket
    )

    $result = @{ Success = $false; Skipped = $false; Fallback = $false; FormatFallback = $false; Overwritten = $false }
    $fileExisted = [System.IO.File]::Exists($Path)

    if ($fileExisted -and -not $Overwrite) {
        Write-Verbose "Object with key '$([System.IO.Path]::GetFileNameWithoutExtension($Path))' already exists in bucket '$Bucket'. Use -Overwrite to replace."
        $result.Skipped = $true
        return $result
    }

    $writeSuccess = $false
    if ($AsBinary) {
        $currentDepth = $BinaryDepth
        while ($currentDepth -le 10) {
            try {
                $xml = [System.Management.Automation.PSSerializer]::Serialize($Item, $currentDepth)
                $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                if ($Compress) {
                    $ms = [System.IO.MemoryStream]::new()
                    $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
                    $cs.Write($rawBytes, 0, $rawBytes.Length)
                    $cs.Close()
                    [System.IO.File]::WriteAllBytes($Path, $ms.ToArray())
                }
                else {
                    [System.IO.File]::WriteAllBytes($Path, $rawBytes)
                }
                if ($currentDepth -gt $BinaryDepth) { $result.Fallback = $true }
                $writeSuccess = $true
                break
            }
            catch { $currentDepth++ }
        }
    }
    else {
        try {
            $json = ConvertTo-Json -InputObject $Item -Depth $Depth -Compress -WarningAction SilentlyContinue
            [System.IO.File]::WriteAllText($Path, $json, [System.Text.Encoding]::UTF8)
            $writeSuccess = $true
        }
        catch {
            try {
                $xml = [System.Management.Automation.PSSerializer]::Serialize($Item, $BinaryDepth)
                $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                $finalPath = [System.IO.Path]::ChangeExtension($Path, ".dat")
                if ($Compress) {
                    $ms = [System.IO.MemoryStream]::new()
                    $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
                    $cs.Write($rawBytes, 0, $rawBytes.Length)
                    $cs.Close()
                    [System.IO.File]::WriteAllBytes($finalPath, $ms.ToArray())
                }
                else {
                    [System.IO.File]::WriteAllBytes($finalPath, $rawBytes)
                }
                $result.Fallback = $true
                $result.FormatFallback = $true
                $writeSuccess = $true
                Write-Warning "Object '$([System.IO.Path]::GetFileNameWithoutExtension($Path))' too complex for JSON, saved as binary instead"
            }
            catch {
                Write-Verbose "Failed to serialize object '$([System.IO.Path]::GetFileNameWithoutExtension($Path))' as binary: $_"
            }
        }
    }

    $result.Success = $writeSuccess
    if ($writeSuccess -and $fileExisted) { $result.Overwritten = $true }
    return $result
}

function Ensure-BucketExists {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $rootPath = Resolve-SafePath -Path $Path
    $bucketPath = Get-BucketPath -Name $Name -Path $rootPath
    if (-not $bucketPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Bucket path '$bucketPath' resolves outside of root '$rootPath'. Path traversal not allowed."
    }
    if (-not [System.IO.Directory]::Exists($bucketPath)) {
        $null = [System.IO.Directory]::CreateDirectory($bucketPath)
    }
    return $bucketPath
}

# --- File operations (internal helpers) ---

function Read-BucketFile {
    param([System.IO.FileInfo]$File)

    if ($null -eq $File -or -not [System.IO.File]::Exists($File.FullName)) { return $null }

    $extension = $File.Extension
    $rawBytes = [System.IO.File]::ReadAllBytes($File.FullName)

    if ($extension -eq ".dat") {
        try {
            $decoded = $null
            $isCompressed = $rawBytes.Length -ge 2 -and $rawBytes[0] -eq 0x1F -and $rawBytes[1] -eq 0x8B
            if ($isCompressed) {
                try {
                    $ms = [System.IO.MemoryStream]::new($rawBytes)
                    $decompressed = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
                    $reader = [System.IO.StreamReader]::new($decompressed)
                    $decoded = $reader.ReadToEnd()
                    $reader.Close()
                    $decompressed.Close()
                }
                catch {
                    Write-Warning "Failed to decompress '$($File.Name)': $_"
                    return $null
                }
            }
            else {
                $decoded = [System.Text.Encoding]::UTF8.GetString($rawBytes)
                if (-not $decoded.StartsWith('<Objs') -and -not $decoded.StartsWith('<?xml')) {
                    $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($decoded))
                }
            }
            $obj = [System.Management.Automation.PSSerializer]::Deserialize($decoded)
            # Convert hashtables to PSCustomObject
            if ($obj -is [hashtable]) {
                $ordered = [ordered]@{}
                foreach ($kvp in $obj.GetEnumerator()) { $ordered[$kvp.Key] = $kvp.Value }
                return [PSCustomObject]$ordered
            }
            return $obj
        }
        catch {
            Write-Warning "Failed to deserialize '$($File.Name)': $_"
            return $null
        }
    }
    else {
        try {
            $content = [System.Text.Encoding]::UTF8.GetString($rawBytes)
            if ($content.StartsWith([char]0xFEFF)) { $content = $content.Substring(1) }
            $obj = $content | ConvertFrom-Json
            # Convert hashtables to PSCustomObject
            if ($obj -is [hashtable]) {
                $ordered = [ordered]@{}
                foreach ($kvp in $obj.GetEnumerator()) { $ordered[$kvp.Key] = $kvp.Value }
                return [PSCustomObject]$ordered
            }
            return $obj
        }
        catch {
            Write-Warning "Failed to parse JSON '$($File.Name)': $_"
            return $null
        }
    }
}

function Get-ObjectFiles {
    param([string]$BucketPath, [string]$Key)

    $di = [System.IO.DirectoryInfo]::new($BucketPath)
    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $results = [System.Collections.ArrayList]::new()
        $target = $Key.ToLowerInvariant()
        foreach ($f in @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))) {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            $baseLower = $base.ToLowerInvariant()
            if ($baseLower -eq $target -or $baseLower.StartsWith("${target}_") -or $baseLower.StartsWith("${target}.")) {
                $null = $results.Add($f)
            }
        }
        return $results.ToArray()
    }
    else {
        return @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))
    }
}

function Find-ObjectFile {
    param([string]$BucketPath, [string]$Key)

    if ([string]::IsNullOrWhiteSpace($Key) -or -not [System.IO.Directory]::Exists($BucketPath)) { return $null }

    $di = [System.IO.DirectoryInfo]::new($BucketPath)
    $target = $Key.ToLowerInvariant()

    foreach ($f in @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $baseLower = $base.ToLowerInvariant()
        if ($baseLower -eq $target -or $baseLower.StartsWith("${target}_") -or $baseLower.StartsWith("${target}.")) { return $f }
    }

    return $null
}

function Get-ObjectProperty {
    param([PSObject]$Object, [string]$PropertyName)

    $hasValue = $false
    $value = $null

    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($PropertyName)) { $hasValue = $true; $value = $Object[$PropertyName] }
    }
    elseif ($null -ne $Object.PSObject.Properties[$PropertyName]) {
        $hasValue = $true; $value = $Object.$PropertyName
    }

    return @{ HasValue = $hasValue; Value = $value }
}

function Get-BucketFiles {
    param([string]$BucketPath)
    $di = [System.IO.DirectoryInfo]::new($BucketPath)
    @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))
}

function Sanitize-Key {
    param([string]$Key)
    $safe = $Key -replace '[\\/:\*\?"<>\|\[\]]', '_'
    if ([string]::IsNullOrWhiteSpace($safe) -or $safe -match '^_+$') { return $null }
    return $safe
}

function Test-MatchFilter {
    param([PSObject]$Object, [hashtable]$Match)
    foreach ($kvp in $Match.GetEnumerator()) {
        $prop = Get-ObjectProperty -Object $Object -PropertyName $kvp.Name
        $matchesValue = if ($null -eq $kvp.Value) { -not $prop.HasValue }
        elseif (-not $prop.HasValue) { $false }
        else { $prop.Value -eq $kvp.Value }
        if (-not $matchesValue) { return $false }
    }
    return $true
}

# --- Public cmdlets (alphabetical) ---

function Copy-BucketObject {
    <#
    .SYNOPSIS
    Copies an object within or between buckets.
    .DESCRIPTION
    Duplicates an object file from one bucket to another, optionally changing the key.
    Preserves the original serialization format (JSON or binary).
    .PARAMETER Bucket
    Source bucket name.
    .PARAMETER DestinationBucket
    Destination bucket name. Defaults to the same as -Bucket if omitted.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Key
    Source object key to copy.
    .PARAMETER DestinationKey
    Destination object key. Defaults to the source key if omitted.
    .PARAMETER PassThru
    Return metadata for the copied object.
    .EXAMPLE
    Copy-BucketObject -Bucket users -Key "Alice" -DestinationBucket archive
    .EXAMPLE
    Copy-BucketObject -Bucket config -Key "app-config" -DestinationKey "app-config-backup"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Bucket,
        [string]$DestinationBucket,
        [string]$Path,
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$DestinationKey,
        [switch]$PassThru,
        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    $sourceBucketPath = Get-BucketPath -Name $Bucket -Path $Path
    if (-not [System.IO.Directory]::Exists($sourceBucketPath)) {
        throw "Source bucket '$Bucket' not found at '$sourceBucketPath'"
    }

    if ([string]::IsNullOrWhiteSpace($DestinationBucket)) { $DestinationBucket = $Bucket }
    if ([string]::IsNullOrWhiteSpace($DestinationKey)) { $DestinationKey = $Key }

    $safeDestKey = $DestinationKey -replace '[\\/:\*\?"<>\|\[\]]', '_'
    if ([string]::IsNullOrWhiteSpace($safeDestKey) -or $safeDestKey -match '^_+$') {
        throw "Destination key '$DestinationKey' is invalid after sanitization"
    }

    $sourceFile = Find-ObjectFile -BucketPath $sourceBucketPath -Key $Key
    if ($null -eq $sourceFile) {
        throw "Object with key '$Key' not found in bucket '$Bucket'"
    }

    $destBucketPath = Ensure-BucketExists -Name $DestinationBucket -Path $Path
    $destJsonPath = Join-Path $destBucketPath "${safeDestKey}.json"
    $destDatPath = Join-Path $destBucketPath "${safeDestKey}.dat"

    if ([System.IO.File]::Exists($destJsonPath) -or [System.IO.File]::Exists($destDatPath)) {
        throw "Object with key '$safeDestKey' already exists in bucket '$DestinationBucket'. Use a different key."
    }

    $ext = $sourceFile.Extension
    $destFile = Join-Path $destBucketPath "${safeDestKey}${ext}"
    [System.IO.File]::Copy($sourceFile, $destFile)
    Write-Verbose "Copied [$Bucket/$Key] to [$DestinationBucket/$safeDestKey]"

    if ($PassThru) {
        [PSCustomObject]@{
            SourceBucket = $Bucket; SourceKey = $Key; DestinationBucket = $DestinationBucket
            DestinationKey = $safeDestKey
        }
    }
    elseif (-not $Quiet) {
        Write-Host "$Bucket/$Key" -NoNewline -ForegroundColor $script:CPath
        Write-Host " → " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "$DestinationBucket/$safeDestKey" -ForegroundColor $script:CPath
    }
}

function Export-Bucket {
    <#
    .SYNOPSIS
    Exports a bucket to a single archive file.
    .DESCRIPTION
    Serializes all objects in a bucket to a single JSON or CLIXML archive file.
    Includes object metadata (_BucketName, _BucketKey) for easy restoration.
    Default format is JSON. Use -AsBinary for CLIXML/PSSerializer format with full .NET type preservation.
    .PARAMETER Bucket
    Bucket name to export. Supports wildcards.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER OutputFile
    Path to the output archive file.
    .PARAMETER AsBinary
    Export as CLIXML/PSSerializer binary archive (default is JSON).
    .PARAMETER Compress
    Enable GZip compression for CLIXML archives. Only effective with -AsBinary.
    .PARAMETER Quiet
    Suppress all output.
    .EXAMPLE
    Export-Bucket -Bucket users -OutputFile "./users-backup.json"
    .EXAMPLE
    Export-Bucket -Bucket "config*" -OutputFile "./config-backup.clixml" -AsBinary
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$Bucket,
        [string]$Path,
        [Parameter(Mandatory = $true)][string]$OutputFile,
        [switch]$AsBinary,
        [switch]$Compress,
        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    $allObjects = @()
    $exportedBuckets = 0
    $exportedObjects = 0

    foreach ($b in $Bucket) {
        $objects = Get-BucketObject -Bucket $b -Path $Path
        if ($objects) {
            $allObjects += $objects
            $exportedBuckets++
            $exportedObjects += @($objects).Count
        }
    }

    if ($allObjects.Count -eq 0) {
        Write-Warning "No objects found to export for buckets: $($Bucket -join ', ')"
        return
    }

    $outputDir = [System.IO.Path]::GetDirectoryName((Resolve-SafePath -Path $OutputFile))
    if (-not [System.IO.Directory]::Exists($outputDir)) {
        $null = [System.IO.Directory]::CreateDirectory($outputDir)
    }

    if ($AsBinary) {
        $xml = [System.Management.Automation.PSSerializer]::Serialize($allObjects, 10)
        $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
        if ($Compress) {
            $ms = [System.IO.MemoryStream]::new()
            $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
            $cs.Write($rawBytes, 0, $rawBytes.Length)
            $cs.Close()
            [System.IO.File]::WriteAllBytes($OutputFile, $ms.ToArray())
        }
        else {
            [System.IO.File]::WriteAllBytes($OutputFile, $rawBytes)
        }
    }
    else {
        $json = ConvertTo-Json -InputObject $allObjects -Depth 20 -Compress
        [System.IO.File]::WriteAllText($OutputFile, $json, [System.Text.Encoding]::UTF8)
    }

    if (-not $Quiet) {
        $bucketArg = if ($Bucket -is [array]) { $Bucket -join ', ' } else { $Bucket }
        Write-Host "$bucketArg" -NoNewline -ForegroundColor $script:CPath
        Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
        Write-Host $exportedObjects -NoNewline -ForegroundColor $script:CNum
        Write-Host " objects → " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "$([System.IO.Path]::GetFileName($OutputFile))" -ForegroundColor $script:CAction
    }
}

function Get-Bucket {
    <#
    .SYNOPSIS
    Lists available buckets with object counts.
    .DESCRIPTION
    Scans the storage path for bucket directories and returns information about each,
    including name, path, and total object count (JSON + binary files). Supports nested
    buckets — any directory containing serialized objects is a bucket.

    By default only top-level buckets are shown with aggregated object counts (including
    all descendants). Use -Recurse to list all nested buckets with direct (non-aggregated)
    counts. The HasSubBuckets property indicates whether a bucket contains nested sub-buckets.

    Use -Tree to render a beautiful colorized tree view of all buckets.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Name
    Filter buckets by name pattern (substring match on full nested path).
    .PARAMETER Tree
    Render a tree view of all buckets and directories.
    .PARAMETER Objects
    Show individual objects in tree view. Only bucket directories are shown by default.
    .PARAMETER Raw
    Return structured tree objects instead of formatted text (for -Tree mode).
    .PARAMETER MaxFiles
    Maximum files to display per bucket in tree view. Truncated files shown as "... N more". Default: 5.
    .PARAMETER Depth
    Maximum depth to display in tree view.
    .PARAMETER Recurse
    List all nested buckets with direct (non-aggregated) object counts.
    .OUTPUTS
    PSCustomObject with Name, Path, ObjectCount, and HasSubBuckets properties, or tree output.
    .EXAMPLE
    Get-Bucket
    .EXAMPLE
    Get-Bucket "user"
    .EXAMPLE
    Get-Bucket -Recurse
    .EXAMPLE
    Get-Bucket -Tree
    .EXAMPLE
    Get-Bucket -Tree -Objects
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Name,
        [string]$Path,
        [switch]$Tree,
        [switch]$Objects,
        [switch]$Raw,
        [switch]$Recurse,
        [int]$MaxFiles = 5,
        [int]$Depth = [int]::MaxValue
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    if (-not [System.IO.Directory]::Exists($Path)) {
        if ($Tree) { Write-Host "No bucket storage found at '$Path'" -ForegroundColor DarkGray }
        return
    }

    if ($Tree) {
        function TreeSize {
            param([long]$Bytes)
            if ($Bytes -eq 0) { return "0 B" }
            $units = @("B", "KB", "MB", "GB", "TB")
            $unit = 0
            $size = [double]$Bytes
            while ($size -ge 1024 -and $unit -lt $units.Length - 1) {
                $size /= 1024
                $unit++
            }
            $rounded = [math]::Round($size)
            "$rounded $($units[$unit])"
        }

        function TreeItemCount {
            param([int]$Count)
            if ($Count -eq 1) { "1 item" } else { "$Count items" }
        }

        function ScanDir {
            param([string]$Dir, [string]$Root)
            $stats = @{ ObjectCount = 0; SizeBytes = 0; BucketCount = 0 }
            if (-not [System.IO.Directory]::Exists($Dir)) { return $stats }
            $di = [System.IO.DirectoryInfo]::new($Dir)
            $stats.ObjectCount += $di.GetFiles("*.dat").Length + $di.GetFiles("*.json").Length
            $di.GetFiles("*.dat") | ForEach-Object { $stats.SizeBytes += $_.Length }
            $di.GetFiles("*.json") | ForEach-Object { $stats.SizeBytes += $_.Length }

            foreach ($sub in $di.GetDirectories()) {
                if ($sub.Name -eq ".buckets") { continue }
                $childStats = ScanDir -Dir $sub.FullName -Root $Root
                $stats.ObjectCount += $childStats.ObjectCount
                $stats.SizeBytes += $childStats.SizeBytes
                $stats.BucketCount += $childStats.BucketCount
                if ($childStats.ObjectCount -gt 0) { $stats.BucketCount++ }
            }

            $isBucket = $stats.ObjectCount -gt 0
            if ($Dir -ne $Root -and -not $isBucket -and $stats.BucketCount -gt 0) { $isBucket = $true }

            if ($Dir -eq $Root) {
                $stats.IsBucket = $true
                $stats.IsRoot = $true
            }
            else {
                $stats.IsBucket = $isBucket
                $stats.IsRoot = $false
            }
            $stats
        }

        function BuildTree {
            param([string]$Dir, [string]$Root, [int]$CurrentDepth)

            $relPath = if ($Dir -eq $Root) {
                ""
            }
            else {
                $Dir.Substring($Root.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
            }

            $displayName = if ($Dir -eq $Root) {
                Split-Path $Root -Leaf
            }
            else {
                Split-Path $Dir -Leaf
            }

            $stats = ScanDir -Dir $Dir -Root $Root
            $type = if ($stats.IsRoot) { "Root" } else { "Bucket" }

            $node = [PSCustomObject]@{
                Name         = $displayName
                Type         = $type
                Path         = $relPath
                ObjectCount  = $stats.ObjectCount
                SizeBytes    = $stats.SizeBytes
                Depth        = $CurrentDepth
                Children     = [System.Collections.ArrayList]::new()
                _BucketName  = if ($stats.IsBucket -and -not $stats.IsRoot) { $relPath } else { "" }
                _BucketKey   = ""
            }
            $node.PSObject.TypeNames.Insert(0, "Buckets.Tree")

            $di = [System.IO.DirectoryInfo]::new($Dir)

            $subDirs = @()
            foreach ($sub in ($di.GetDirectories() | Sort-Object Name)) {
                if ($sub.Name -eq ".buckets") { continue }
                $subRelPath = $sub.FullName.Substring($Root.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
                if (-not [string]::IsNullOrWhiteSpace($script:TreeNameFilter)) {
                    $subRelPathSlash = $subRelPath.TrimEnd('/') + '/'
                    $filterSlash = $script:TreeNameFilter.TrimEnd('/') + '/'
                    $subContainedInFilter = $filterSlash.StartsWith($subRelPathSlash)
                    $filterContainedInSub = $subRelPathSlash.StartsWith($filterSlash)
                    if (-not $subContainedInFilter -and -not $filterContainedInSub) { continue }
                }
                $subHasFiles = $sub.Exists -and ($sub.GetFiles("*.dat").Length -gt 0 -or $sub.GetFiles("*.json").Length -gt 0)
                $subStats = if ($sub.Exists) { ScanDir -Dir $sub.FullName -Root $Root } else { @{ ObjectCount = 0; SizeBytes = 0; BucketCount = 0 } }
                if ($subHasFiles -or $subStats.BucketCount -gt 0) {
                    $subDirs += $sub
                }
            }

            foreach ($sub in $subDirs) {
                if ($CurrentDepth + 1 -lt $Depth -or $Objects) {
                    $child = BuildTree -Dir $sub.FullName -Root $Root -CurrentDepth ($CurrentDepth + 1)
                    $null = $node.Children.Add($child)
                }
            }

            if ($Objects) {
                foreach ($f in ($di.GetFiles("*.dat") + $di.GetFiles("*.json") | Sort-Object Name)) {
                    $keyName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                    $fNode = [PSCustomObject]@{
                        Name         = $keyName
                        Type         = "Object"
                        Path         = "$relPath/$keyName"
                        ObjectCount  = 1
                        SizeBytes    = $f.Length
                        Depth        = $CurrentDepth + 1
                        Children     = [System.Collections.ArrayList]::new()
                    }
                    $fNode.PSObject.TypeNames.Insert(0, "Buckets.Tree")
                    $null = $node.Children.Add($fNode)
                }
            }

            $node
        }

        function RenderTree {
            param([PSCustomObject]$Node, [string]$Prefix, [bool]$IsLast, [bool]$IsRoot)

            if ($IsRoot) {
                $sizeStr = "$(TreeItemCount $Node.ObjectCount), $(TreeSize $Node.SizeBytes)"
                Write-Host "$($Node.Name) " -NoNewline -ForegroundColor $script:CAction
                Write-Host "($sizeStr)" -ForegroundColor DarkGray
            }
            else {
                $linePrefix = if ($IsLast) { "$Prefix└── " } else { "$Prefix├── " }

                if ($Node.Type -eq "Object") {
                    Write-Host "$linePrefix" -NoNewline -ForegroundColor DarkGray
                    Write-Host $Node.Name -ForegroundColor White
                }
                else {
                    $sizeStr = "$(TreeItemCount $Node.ObjectCount), $(TreeSize $Node.SizeBytes)"
                    Write-Host "$linePrefix" -NoNewline -ForegroundColor DarkGray
                    Write-Host "$($Node.Name) " -NoNewline -ForegroundColor Cyan
                    Write-Host "($sizeStr)" -ForegroundColor DarkGray
                }
            }

            $children = @($Node.Children)
            $bucketChildren = @($children | Where-Object { $_.Type -ne "Object" })
            $fileChildren = @($children | Where-Object { $_.Type -eq "Object" })

            $allItems = @()
            $allItems += $bucketChildren

            $truncatedFileCount = 0
            $childPrefix = if ($IsRoot) { "" } elseif ($IsLast) { "$Prefix    " } else { "$Prefix│   " }
            if ($fileChildren.Count -gt $MaxFiles) {
                $allItems += $fileChildren[0..($MaxFiles - 1)]
                $truncatedFileCount = $fileChildren.Count - $MaxFiles
            }
            else {
                $allItems += $fileChildren
            }

            for ($i = 0; $i -lt $allItems.Count; $i++) {
                $child = $allItems[$i]
                $childIsLast = $i -eq ($allItems.Count - 1)
                RenderTree -Node $child -Prefix $childPrefix -IsLast $childIsLast -IsRoot $false
            }

            if ($truncatedFileCount -gt 0) {
                Write-Host "$childPrefix└── " -NoNewline -ForegroundColor DarkGray
                Write-Host "... $truncatedFileCount more" -ForegroundColor $script:CNum
            }
        }

        $script:TreeNameFilter = $Name
        try {
            $root = BuildTree -Dir $Path -Root $Path -CurrentDepth 0
            if ($Raw) { return $root }
            RenderTree -Node $root -Prefix "" -IsLast $false -IsRoot $true
        }
        finally {
            $script:TreeNameFilter = $null
        }
        return
    }

    $results = [System.Collections.ArrayList]::new()

    if ($Recurse) {
        # Recursive mode: all directories, direct counts
        function Scan-Recurse {
            param([string]$Dir)
            $di = [System.IO.DirectoryInfo]::new($Dir)
            $directCount = $di.GetFiles("*.dat").Length + $di.GetFiles("*.json").Length
            $hasSubBuckets = $false

            foreach ($child in $di.GetDirectories()) {
                if ($child.Name -eq ".buckets") { continue }
                $hasSubBuckets = $true
                Scan-Recurse -Dir $child.FullName
            }

            $relPath = $Dir.Substring($Path.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
            if ($directCount -gt 0 -or $hasSubBuckets) {
                $obj = [PSCustomObject]@{ Name = $relPath; ObjectCount = $directCount; HasSubBuckets = $hasSubBuckets }
                Add-HiddenProperty -Target $obj -Name 'Path' -Value $Dir
                $null = $results.Add($obj)
            }
        }

        $rootDi = [System.IO.DirectoryInfo]::new($Path)
        foreach ($subDir in $rootDi.GetDirectories()) {
            if ($subDir.Name -eq ".buckets") { continue }
            Scan-Recurse -Dir $subDir.FullName
        }
    }
    else {
        # Non-recursive mode: top-level only, aggregated counts
        function Get-AggregatedStats {
            param([string]$Dir)
            $di = [System.IO.DirectoryInfo]::new($Dir)
            $count = $di.GetFiles("*.dat").Length + $di.GetFiles("*.json").Length
            $hasSubBuckets = $false

            foreach ($child in $di.GetDirectories()) {
                if ($child.Name -eq ".buckets") { continue }
                $hasSubBuckets = $true
                $childStats = Get-AggregatedStats -Dir $child.FullName
                $count += $childStats.TotalCount
            }

            [PSCustomObject]@{ TotalCount = $count; HasSubBuckets = $hasSubBuckets }
        }

        $rootDi = [System.IO.DirectoryInfo]::new($Path)
        foreach ($subDir in $rootDi.GetDirectories()) {
            if ($subDir.Name -eq ".buckets") { continue }
            $stats = Get-AggregatedStats -Dir $subDir.FullName
            $obj = [PSCustomObject]@{ Name = $subDir.Name; ObjectCount = $stats.TotalCount; HasSubBuckets = $stats.HasSubBuckets }
            Add-HiddenProperty -Target $obj -Name 'Path' -Value $subDir.FullName
            $null = $results.Add($obj)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $results = $results | Where-Object { $_.Name -like "*$Name*" }
    }

    $results
}

function Get-BucketKeys {
    <#
    .SYNOPSIS
    Lists object keys in a bucket without deserializing objects.
    .DESCRIPTION
    Fast key enumeration that reads filenames only, avoiding the overhead of
    deserializing object data. Returns only Bucket and Key per object.
    For detailed per-object statistics (format, size, type, timestamps, compression),
    use Get-BucketObjectStats.
    .PARAMETER Bucket
    Bucket name to scan. If omitted, scans all buckets under -Path. Supports wildcards.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Match
    Filter keys by pattern (wildcard). Case-insensitive.
    .OUTPUTS
    PSCustomObject with Bucket and Key properties.
    .EXAMPLE
    Get-BucketKeys -Bucket users
    .EXAMPLE
    Get-BucketKeys -Match "*admin*"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Bucket,
        [string]$Path,
        [string]$Match
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    $bucketPaths = @()
    if (-not [string]::IsNullOrWhiteSpace($Bucket)) {
        if ($Bucket -match '[\*\?]') {
            $cachedBuckets = Get-Bucket -Path $Path -Recurse
            $matched = $cachedBuckets | Where-Object { $_.Name -like $Bucket }
            $bucketPaths += $matched | ForEach-Object { $_.Path }
        }
        else {
            $bucketPaths += Get-BucketPath -Name $Bucket -Path $Path
        }
    }
    else {
        if ([System.IO.Directory]::Exists($Path)) {
            $bucketPaths += [System.IO.DirectoryInfo]::new($Path).GetDirectories() | ForEach-Object { $_.FullName }
        }
    }

    foreach ($bucketPath in $bucketPaths) {
        if (-not [System.IO.Directory]::Exists($bucketPath)) { continue }
        $bucketName = $bucketPath.Substring($Path.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
        $di = [System.IO.DirectoryInfo]::new($bucketPath)
        $files = @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))
        foreach ($f in $files) {
            $key = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if (-not [string]::IsNullOrWhiteSpace($Match) -and $key -notlike $Match) { continue }
            [PSCustomObject]@{
                Bucket = $bucketName
                Key    = $key
            }
        }
    }
}

function Get-BucketObjectStats {
    <#
    .SYNOPSIS
    Returns detailed per-object statistics for objects in a bucket.
    .DESCRIPTION
    Enumerates objects and reads lightweight metadata (format, size, type, timestamps,
    compression status) without full deserialization. Peeks at file content to determine
    object type (Object, Array, or Value) from the first bytes.
    .PARAMETER Bucket
    Bucket name to scan. If omitted, scans all buckets under -Path. Supports wildcards.
    .PARAMETER Key
    Exact object key to look up. When specified, returns stats for a single object only.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Match
    Filter keys by pattern (wildcard). Case-insensitive.
    .OUTPUTS
    PSCustomObject with Bucket, Key, Format, Type, Size, LastWriteTime, and IsCompressed
    properties. Path is included as a hidden property.
    .EXAMPLE
    Get-BucketObjectStats -Bucket users
    .EXAMPLE
    Get-BucketObjectStats -Bucket users -Match "*admin*"
    .EXAMPLE
    Get-BucketObjectStats -Bucket users -Key "alice"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Bucket,
        [Parameter(Position = 1)][string]$Key,
        [string]$Path,
        [string]$Match
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    $bucketPaths = @()
    if (-not [string]::IsNullOrWhiteSpace($Bucket)) {
        if ($Bucket -match '[\*\?]') {
            $cachedBuckets = Get-Bucket -Path $Path -Recurse
            $matched = $cachedBuckets | Where-Object { $_.Name -like $Bucket }
            $bucketPaths += $matched | ForEach-Object { $_.Path }
        }
        else {
            $bucketPaths += Get-BucketPath -Name $Bucket -Path $Path
        }
    }
    else {
        if ([System.IO.Directory]::Exists($Path)) {
            $bucketPaths += [System.IO.DirectoryInfo]::new($Path).GetDirectories() | ForEach-Object { $_.FullName }
        }
    }

    $results = [System.Collections.ArrayList]::new()

    foreach ($bucketPath in $bucketPaths) {
        if (-not [System.IO.Directory]::Exists($bucketPath)) { continue }
        $bucketName = $bucketPath.Substring($Path.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
        $di = [System.IO.DirectoryInfo]::new($bucketPath)

        if (-not [string]::IsNullOrWhiteSpace($Key)) {
            $jsonFile = [System.IO.Path]::Combine($bucketPath, "$Key.json")
            $datFile = [System.IO.Path]::Combine($bucketPath, "$Key.dat")
            $found = $false
            foreach ($filePath in @($datFile, $jsonFile)) {
                if ([System.IO.File]::Exists($filePath)) {
                    $f = [System.IO.FileInfo]::new($filePath)
                    $info = Resolve-ObjectType -FileInfo $f
                    $entry = [PSCustomObject]@{
                        Bucket        = $bucketName
                        Key           = $Key
                        Format        = if ($f.Extension -eq ".json") { "JSON" } else { "Binary" }
                        Type          = $info.Type
                        Size          = $f.Length
                        LastWriteTime = $f.LastWriteTime
                        IsCompressed  = $info.IsCompressed
                    }
                    Add-HiddenProperty -Target $entry -Name 'Path' -Value $f.FullName
                    $null = $results.Add($entry)
                    $found = $true
                    break
                }
            }
            if (-not $found) {
                Write-Warning "Key '$Key' not found in bucket '$bucketName'"
            }
            continue
        }

        $files = @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))
        foreach ($f in $files) {
            $fKey = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if (-not [string]::IsNullOrWhiteSpace($Match) -and $fKey -notlike $Match) { continue }
            $info = Resolve-ObjectType -FileInfo $f
            $entry = [PSCustomObject]@{
                Bucket        = $bucketName
                Key           = $fKey
                Format        = if ($f.Extension -eq ".json") { "JSON" } else { "Binary" }
                Type          = $info.Type
                Size          = $f.Length
                LastWriteTime = $f.LastWriteTime
                IsCompressed  = $info.IsCompressed
            }
            Add-HiddenProperty -Target $entry -Name 'Path' -Value $f.FullName
            $null = $results.Add($entry)
        }
    }

    $results
}

function Get-BucketObject {
    <#
    .SYNOPSIS
    Retrieves objects from one or more buckets.
    .DESCRIPTION
    Reads serialized objects from bucket directories. When no bucket is specified,
    searches all buckets under the storage path. Supports exact-match hashtable
    filtering (-Match) and arbitrary scriptblock filtering (-Filter).
    Retrieved objects include metadata properties: _BucketName, _BucketKey, _BucketFile.
    .PARAMETER Bucket
    Bucket name(s) to search (Position 0). If omitted, searches all buckets under -Path. Supports wildcards.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Key
    Object key to retrieve (Position 1). Case-insensitive prefix match. Looks for both JSON and binary files.
    .PARAMETER Match
    Hashtable of property-value pairs for exact-match filtering. All pairs must match. Supports $null values.
    .PARAMETER Filter
    ScriptBlock for custom filtering. Use $_ to reference object properties (e.g., { $_.Age -gt 30 }).
    .PARAMETER Recurse
    Included for backward compatibility. No longer needed — recursion is now the default.
    .PARAMETER NoRecurse
    Suppress recursion into nested sub-buckets. Only returns objects from the specified bucket directory.
    .PARAMETER First
    Return only the first N objects.
    .PARAMETER Skip
    Skip the first N objects before returning results.
    .OUTPUTS
    Deserialized PSObjects with _BucketName, _BucketKey, and _BucketFile metadata.
    .EXAMPLE
    Get-BucketObject users
    .EXAMPLE
    Get-BucketObject users "Alice"
    .EXAMPLE
    Get-BucketObject -Bucket users -Match @{ Role = "admin" }
    .EXAMPLE
    Get-BucketObject -Bucket users -Match @{ Deleted = $null }
    .EXAMPLE
    Get-BucketObject -Filter { $_.Status -eq "shipped" -and $_.Shipping.Method -eq "Express" }
    .EXAMPLE
    Get-BucketObject -Bucket users, orders
    .EXAMPLE
    Get-BucketObject -Bucket org
    .EXAMPLE
    Get-BucketObject -Bucket org -NoRecurse
    .EXAMPLE
    Get-BucketObject -First 10 -Skip 20
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string[]]$Bucket,
        [string]$Path,
        [Parameter(Position = 1)][string]$Key,
        [hashtable]$Match,
        [scriptblock]$Filter,
        [switch]$Recurse,
        [switch]$NoRecurse,
        [int]$First,
        [int]$Skip,
        [object]$Funnel
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    $bucketPaths = @()
    if ($Bucket -and $Bucket.Count -gt 0) {
        $cachedBuckets = $null
        foreach ($b in $Bucket) {
            if ($b -match '[\*\?]') {
                if ($null -eq $cachedBuckets) { $cachedBuckets = Get-Bucket -Path $Path -Recurse }
                $matched = $cachedBuckets | Where-Object { $_.Name -like $b }
                $bucketPaths += $matched | ForEach-Object { $_.Path }
            }
            else {
                $bp = Get-BucketPath -Name $b -Path $Path
                $bucketPaths += $bp
                if ($Recurse -or -not $NoRecurse) {
                    $nested = Get-Bucket -Path $Path -Recurse | Where-Object { $_.Name -like "$b/*" }
                    $bucketPaths += $nested | ForEach-Object { $_.Path }
                }
            }
        }
    }
    else {
        $bucketPaths += Get-Bucket -Path $Path -Recurse | ForEach-Object { $_.Path }
    }

    $funnelDef = Resolve-Funnel $Funnel

    $allObjects = [System.Collections.ArrayList]::new()

    foreach ($bucketPath in $bucketPaths) {
        if (-not [System.IO.Directory]::Exists($bucketPath)) { continue }
        $bucketName = Split-Path $bucketPath -Leaf
        $files = Get-ObjectFiles -BucketPath $bucketPath -Key $Key

        foreach ($file in $files) {
            if ($null -eq $file -or -not [System.IO.File]::Exists($file.FullName)) { continue }
            $obj = Read-BucketFile -File $file
            if ($null -eq $obj) { continue }

            if ($Match -and -not (Test-MatchFilter -Object $obj -Match $Match)) { continue }

            if ($Filter) {
                if ($null -eq ($obj | Where-Object $Filter)) { continue }
            }

            if ($funnelDef) {
                $matchesAppliesTo = -not $funnelDef.ContainsKey('AppliesTo') -or ($null -ne ($obj | Where-Object $funnelDef.AppliesTo))
                if ($matchesAppliesTo) {
                    $obj = $obj | ForEach-Object $funnelDef.Filter
                    if ($null -eq $obj) { continue }
                }
            }

            $relativePath = $file.FullName.Substring($bucketPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
            $keyWithoutExt = [System.IO.Path]::ChangeExtension($relativePath, $null).TrimEnd('.')
            Add-HiddenProperty -Target $obj -Name '_BucketName' -Value $bucketName
            Add-HiddenProperty -Target $obj -Name '_BucketKey' -Value $keyWithoutExt
            Add-HiddenProperty -Target $obj -Name '_BucketFile' -Value $file.FullName
            $null = $allObjects.Add($obj)
        }
    }

    $emitted = 0; $skipped = 0
    foreach ($obj in $allObjects) {
        if ($Skip -gt 0 -and $skipped -lt $Skip) { $skipped++; continue }
        if ($First -gt 0 -and $emitted -ge $First) { break }
        Write-Output $obj; $emitted++
    }
}

function Get-BucketStats {
    <#
    .SYNOPSIS
    Shows statistics for a bucket.
    .DESCRIPTION
    Returns object count, total storage size, and oldest/newest object timestamps
    for the specified bucket. Returns $null if the bucket does not exist.
    .PARAMETER Bucket
    Name of the bucket to analyze.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .OUTPUTS
    PSCustomObject with Name, Path, ObjectCount, TotalSize, OldestObject, and NewestObject
    properties. TotalSizeBytes is included as a hidden property.
    .EXAMPLE
    Get-BucketStats -Bucket users
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Bucket,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path
    if (-not [System.IO.Directory]::Exists($bucketPath)) {
        Write-Warning "Bucket '$Bucket' not found at '$bucketPath'"
        return
    }

    $di = [System.IO.DirectoryInfo]::new($bucketPath)
    $datFiles = @($di.GetFiles("*.dat"))
    $jsonFiles = @($di.GetFiles("*.json"))

    $fileObjects = $datFiles + $jsonFiles
    $totalSize = ($fileObjects | Measure-Object -Property Length -Sum).Sum
    $oldest = $null; $newest = $null
    foreach ($f in $fileObjects) {
        if ($null -eq $oldest -or $f.CreationTime -lt $oldest) { $oldest = $f.CreationTime }
        if ($null -eq $newest -or $f.CreationTime -gt $newest) { $newest = $f.CreationTime }
    }

    $obj = [PSCustomObject]@{
        Name         = $Bucket
        Path         = $bucketPath
        ObjectCount  = $fileObjects.Count
        TotalSize    = if ($totalSize) { "$([math]::Round($totalSize / 1KB, 2)) KB" } else { "0 KB" }
        OldestObject = $oldest
        NewestObject = $newest
    }
    Add-HiddenProperty -Target $obj -Name 'TotalSizeBytes' -Value $(if ($totalSize) { $totalSize } else { 0 })
    $obj
}

function Import-Bucket {
    <#
    .SYNOPSIS
    Imports objects from an archive file into a bucket.
    .DESCRIPTION
    Reads objects from a JSON or CLIXML archive file and stores them in a bucket.
    Format is auto-detected by file extension (.json = JSON, otherwise = CLIXML/binary).
    Use -AsBinary to force CLIXML/binary format regardless of extension.
    Preserves original keys if objects have _BucketKey metadata; otherwise generates new keys.
    .PARAMETER Bucket
    Destination bucket name. Creates the bucket if it doesn't exist.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER InputFile
    Path to the archive file to import.
    .PARAMETER AsBinary
    Force import from CLIXML/binary format (auto-detected by file extension if omitted).
    .PARAMETER Overwrite
    Overwrite existing objects with the same key.
    .PARAMETER Quiet
    Suppress all output.
    .EXAMPLE
    Import-Bucket -Bucket users -InputFile "./users-backup.json"
    .EXAMPLE
    Import-Bucket -Bucket config -InputFile "./config-backup.clixml" -AsBinary
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Bucket,
        [Parameter(Mandatory = $true)][string]$InputFile,
        [string]$Path,
[switch]$AsBinary,
        [switch]$Overwrite,
        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    if (-not [System.IO.File]::Exists($InputFile)) {
        throw "Input file '$InputFile' not found"
    }

    $rawBytes = [System.IO.File]::ReadAllBytes($InputFile)
    $useJson = -not $AsBinary -and $InputFile -like "*.json"

    if ($useJson) {
        $content = [System.IO.File]::ReadAllText($InputFile, [System.Text.Encoding]::UTF8)
        $objects = $content | ConvertFrom-Json
    }
    else {
        try {
            $isCompressed = $rawBytes.Length -ge 2 -and $rawBytes[0] -eq 0x1F -and $rawBytes[1] -eq 0x8B
            if ($isCompressed) {
                $ms = [System.IO.MemoryStream]::new($rawBytes)
                $decompressed = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
                $reader = [System.IO.StreamReader]::new($decompressed)
                $content = $reader.ReadToEnd()
                $reader.Close()
                $decompressed.Close()
                $objects = [System.Management.Automation.PSSerializer]::Deserialize($content)
            }
            else {
                $objects = [System.Management.Automation.PSSerializer]::Deserialize([System.Text.Encoding]::UTF8.GetString($rawBytes))
            }
        }
        catch {
            throw "Failed to deserialize archive file '$InputFile': $_"
        }
    }

    if ($null -eq $objects) { throw "Failed to deserialize archive file '$InputFile'" }

    $objectArray = @($objects)
    Write-Verbose "Loaded $($objectArray.Count) objects from '$InputFile'"

    $bucketPath = Ensure-BucketExists -Name $Bucket -Path $Path
    $importedCount = 0; $skippedCount = 0

    foreach ($obj in $objectArray) {
        $key = if ($obj.PSObject.Properties['_BucketKey']) { $obj._BucketKey } else { [Guid]::NewGuid().ToString() }
        $safeKey = $key -replace '[\\/:\*\?"<>\|\[\]]', '_'
        if ([string]::IsNullOrWhiteSpace($safeKey) -or $safeKey -match '^_+$') { $safeKey = [Guid]::NewGuid().ToString() }

        $jsonPath = Join-Path $bucketPath "${safeKey}.json"
        $datPath = Join-Path $bucketPath "${safeKey}.dat"
        $filePath = $null
        if ([System.IO.File]::Exists($jsonPath)) { $filePath = $jsonPath }
        elseif ([System.IO.File]::Exists($datPath)) { $filePath = $datPath }

        if ($filePath -and -not $Overwrite) {
            Write-Verbose "Object with key '$safeKey' already exists in bucket '$Bucket'. Use -Overwrite to replace."
            $skippedCount++
            continue
        }

        $ext = if ($filePath) { [System.IO.Path]::GetExtension($filePath) } else { ".dat" }
        $finalPath = Join-Path $bucketPath "${safeKey}${ext}"

        if ($ext -eq ".json") {
            $json = ConvertTo-Json -InputObject $obj -Depth 20 -Compress
            [System.IO.File]::WriteAllText($finalPath, $json, [System.Text.Encoding]::UTF8)
        }
        else {
            $xml = [System.Management.Automation.PSSerializer]::Serialize($obj, 5)
            $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
            [System.IO.File]::WriteAllBytes($finalPath, $rawBytes)
        }
        $importedCount++
    }

    if (-not $Quiet) {
        Write-Host "$([System.IO.Path]::GetFileName($InputFile))" -NoNewline -ForegroundColor $script:CAction
        Write-Host " → " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "$Bucket" -NoNewline -ForegroundColor $script:CPath
        Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
        Write-Host $importedCount -NoNewline -ForegroundColor $script:CNum
        Write-Host " objects" -ForegroundColor $script:CMuted
        if ($skippedCount -gt 0) {
            Write-Host "  " -NoNewline
            Write-Host $skippedCount -NoNewline -ForegroundColor $script:CNum
            Write-Host " skipped (existing keys)" -ForegroundColor $script:CSkip
        }
    }
}

function Move-BucketObject {
    <#
    .SYNOPSIS
    Moves an object within or between buckets.
    .DESCRIPTION
    Moves an object file from one bucket to another (or within the same bucket),
    optionally changing the key. Deletes the source file after successful copy.
    Preserves the original serialization format (JSON or binary).
    .PARAMETER Bucket
    Source bucket name.
    .PARAMETER DestinationBucket
    Destination bucket name. Defaults to the same as -Bucket if omitted.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Key
    Source object key to move.
    .PARAMETER DestinationKey
    Destination object key. Defaults to the source key if omitted.
    .PARAMETER PassThru
    Return metadata for the moved object.
    .PARAMETER Quiet
    Suppress all output.
    .EXAMPLE
    Move-BucketObject -Bucket logs -Key "log-004" -DestinationBucket archive
    .EXAMPLE
    Move-BucketObject -Bucket orders -Key "ORD-001" -DestinationKey "ORD-legacy-001"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Bucket,
        [string]$DestinationBucket,
        [string]$Path,
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$DestinationKey,
        [switch]$PassThru,
        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    $sourceBucketPath = Get-BucketPath -Name $Bucket -Path $Path
    if (-not [System.IO.Directory]::Exists($sourceBucketPath)) {
        throw "Source bucket '$Bucket' not found at '$sourceBucketPath'"
    }

    if ([string]::IsNullOrWhiteSpace($DestinationBucket)) { $DestinationBucket = $Bucket }
    if ([string]::IsNullOrWhiteSpace($DestinationKey)) { $DestinationKey = $Key }

    $safeDestKey = $DestinationKey -replace '[\\/:\*\?"<>\|\[\]]', '_'
    if ([string]::IsNullOrWhiteSpace($safeDestKey) -or $safeDestKey -match '^_+$') {
        throw "Destination key '$DestinationKey' is invalid after sanitization"
    }

    $sourceFile = Find-ObjectFile -BucketPath $sourceBucketPath -Key $Key
    if ($null -eq $sourceFile) {
        throw "Object with key '$Key' not found in bucket '$Bucket'"
    }

    $destBucketPath = Ensure-BucketExists -Name $DestinationBucket -Path $Path
    $destJsonPath = Join-Path $destBucketPath "${safeDestKey}.json"
    $destDatPath = Join-Path $destBucketPath "${safeDestKey}.dat"
    if ([System.IO.File]::Exists($destJsonPath) -or [System.IO.File]::Exists($destDatPath)) {
        throw "Object with key '$safeDestKey' already exists in bucket '$DestinationBucket'. Use a different key."
    }

    $ext = $sourceFile.Extension
    $destFile = Join-Path $destBucketPath "${safeDestKey}${ext}"
    [System.IO.File]::Copy($sourceFile, $destFile)
    [System.IO.File]::Delete($sourceFile)
    Write-Verbose "Moved [$Bucket/$Key] to [$DestinationBucket/$safeDestKey]"

    if ($PassThru) {
        [PSCustomObject]@{
            SourceBucket = $Bucket; SourceKey = $Key; DestinationBucket = $DestinationBucket
            DestinationKey = $safeDestKey
        }
    }
    elseif (-not $Quiet) {
        Write-Host "$Bucket/$Key" -NoNewline -ForegroundColor $script:CPath
        Write-Host " → " -NoNewline -ForegroundColor $script:CNum
        Write-Host "$DestinationBucket/$safeDestKey" -NoNewline -ForegroundColor $script:CPath
        Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "moved" -ForegroundColor $script:CMuted
    }
}

function New-BucketObject {
    <#
    .SYNOPSIS
    Saves a PSObject to a bucket. Creates the bucket if it doesn't exist.
    .DESCRIPTION
    Serializes one or more PowerShell objects and stores them in a bucket directory.
    Arrays are stored as individual files. By default objects are serialized to JSON
    format for human readability and interoperability. Use -AsBinary for .NET type
    preservation via PSSerializer. JSON depth is auto-incremented up to 100 to avoid
    truncation. If JSON still cannot faithfully represent the object, it falls back
    to binary format and emits a warning.
    .PARAMETER InputObject
    The object(s) to store. Accepts pipeline input. Arrays are stored as individual files.
    .PARAMETER Bucket
    Name of the bucket to save to. Creates the bucket if it doesn't exist. Default: "default".
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Key
    Literal filename (without extension).
    .PARAMETER KeyProperty
    Property name whose value becomes the filename. Special characters (/, :, *, ?, ", <, >, |, [, ]) are sanitized to underscores.
    .PARAMETER Depth
    Maximum depth for JSON serialization. Default: 20.
    .PARAMETER BinaryDepth
    Maximum depth for binary (PSSerializer) serialization. Default: 5.
    .PARAMETER AsTimestamp
    Use a timestamp-based filename (yyyyMMddHHmmssfff_index) instead of a GUID. Ignored if -Key or -KeyProperty is also specified.
    .PARAMETER AsBinary
    Store objects as binary (.dat) instead of JSON (.json). Use for full .NET type preservation.
    .PARAMETER Compress
    Enable GZip compression for binary files to reduce disk usage. Only effective with -AsBinary.
    .PARAMETER Quiet
    Suppress all output. No progress indicator, no summary.
    .PARAMETER Overwrite
    Overwrite existing objects with the same key. Default: $false.
    .PARAMETER PassThru
    Emit a metadata object with details of the operation (StoredKeys, SkippedKeys, SanitizedKeys, OverwrittenKeys, counts, format).
    .OUTPUTS
    By default, a progress indicator and summary are shown.
    Use -PassThru to also get a metadata object. Use -Quiet for silent operation.
    .EXAMPLE
    New-BucketObject -Bucket users -InputObject $users -KeyProperty Name
    .EXAMPLE
    New-BucketObject -Bucket config -InputObject $config -Key "app-settings"
    .EXAMPLE
    New-BucketObject -Bucket users -InputObject $user -KeyProperty Name -AsBinary
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][PSObject]$InputObject,
        [string]$Bucket = "default",
        [string]$Path,
        [string]$Key,
        [string]$KeyProperty,
        [ValidateRange(1, 100)][int]$Depth = 20,
        [ValidateRange(1, 100)][int]$BinaryDepth = 5,
        [switch]$AsTimestamp,
        [switch]$AsBinary,
        [switch]$Compress,
        [switch]$Overwrite,
        [switch]$Quiet,
        [switch]$PassThru,
        [object]$Funnel
    )

    begin {
        $bucketPath = Ensure-BucketExists -Name $Bucket -Path $Path
        $extension = if ($AsBinary) { ".dat" } else { ".json" }
        $savedCount = 0; $skippedCount = 0; $fallbackCount = 0; $formatFallbackCount = 0; $failedCount = 0
        $overwrittenCount = 0; $sanitizedCount = 0
        $storedKeys = [System.Collections.ArrayList]::new()
        $skippedKeys = [System.Collections.ArrayList]::new()
        $sanitizedKeys = [System.Collections.ArrayList]::new()
        $overwrittenKeys = [System.Collections.ArrayList]::new()
        $useVerbose = $VerbosePreference -eq 'Continue'
        $useQuiet = $Quiet.IsPresent
        $showProgress = -not $useVerbose -and -not $useQuiet
        $pipeline = [System.Collections.ArrayList]::new()

        $funnelDef = Resolve-Funnel $Funnel

        if ($AsTimestamp -and (-not [string]::IsNullOrWhiteSpace($Key) -or -not [string]::IsNullOrWhiteSpace($KeyProperty))) {
            Write-Verbose "Both -Key/-KeyProperty and -AsTimestamp specified. -Key/-KeyProperty takes precedence, -AsTimestamp ignored."
        }
    }

    process {
        if ($null -eq $InputObject) { return }

        $isCollection = $InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string] -and $InputObject -isnot [hashtable] -and $InputObject -isnot [System.Collections.IDictionary]

        if ($isCollection) {
            $totalForItems = $InputObject.Count
            $index = 0
            foreach ($raw in $InputObject) {
                $item = $raw
                if ($funnelDef) {
                    $matchesAppliesTo = -not $funnelDef.ContainsKey('AppliesTo') -or ($null -ne ($item | Where-Object $funnelDef.AppliesTo))
                    if ($matchesAppliesTo) {
                        $item = $item | ForEach-Object $funnelDef.Filter
                        if ($null -eq $item) { $skippedCount++; $index++; continue }
                    }
                }
                $itemFilename = Get-BucketFilename -Item $item -Key $Key -KeyProperty $KeyProperty -AsTimestamp:$AsTimestamp.IsPresent -Index $index -Extension $extension
                if ($null -eq $itemFilename) { $skippedCount++; $index++; continue }
                $keyName = if ($itemFilename.OriginalKey) { $itemFilename.OriginalKey } else { [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename) }
                if ($itemFilename.Sanitized) { $sanitizedCount++; $null = $sanitizedKeys.Add([PSCustomObject]@{ Original = $itemFilename.OriginalKey; Sanitized = [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename) }) }
                $itemFilePath = Join-Path $bucketPath $itemFilename.Filename
                $writeResult = Save-BucketFile -Path $itemFilePath -Item $item -Extension $extension -AsBinary:$AsBinary.IsPresent -Compress:$Compress.IsPresent -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite.IsPresent -BucketPath $bucketPath -Bucket $Bucket
                if ($writeResult.Success) {
                    $savedCount++
                    $null = $storedKeys.Add($keyName)
                    if ($writeResult.Overwritten) { $overwrittenCount++; $null = $overwrittenKeys.Add($keyName) }
                    if ($showProgress -and $totalForItems -gt 50) {
                        $percent = if ($totalForItems -gt 0) { [math]::Round(($savedCount / $totalForItems) * 100) } else { 0 }
                        Write-Progress -Activity "Saving to '$Bucket'" -Status "$savedCount object(s) saved" -PercentComplete $percent -CurrentOperation ([System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename))
                    }
                }
                elseif ($writeResult.Skipped) { $skippedCount++; $null = $skippedKeys.Add($keyName) }
                else { $failedCount++ }
                if ($writeResult.Fallback) { $fallbackCount++ }
                if ($writeResult.FormatFallback) { $formatFallbackCount++ }
                $index++
            }
        }
        else {
            $null = $pipeline.Add($InputObject)
        }
    }

    end {
        if ($pipeline.Count -gt 0) {
            $totalForItems = $pipeline.Count
            $index = 0
            foreach ($raw in $pipeline) {
                $item = $raw
                if ($funnelDef) {
                    $matchesAppliesTo = -not $funnelDef.ContainsKey('AppliesTo') -or ($null -ne ($item | Where-Object $funnelDef.AppliesTo))
                    if ($matchesAppliesTo) {
                        $item = $item | ForEach-Object $funnelDef.Filter
                        if ($null -eq $item) { $skippedCount++; $index++; continue }
                    }
                }
                $itemFilename = Get-BucketFilename -Item $item -Key $Key -KeyProperty $KeyProperty -AsTimestamp:$AsTimestamp.IsPresent -Index $index -Extension $extension
                if ($null -eq $itemFilename) { $skippedCount++; $index++; continue }
                $keyName = if ($itemFilename.OriginalKey) { $itemFilename.OriginalKey } else { [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename) }
                if ($itemFilename.Sanitized) { $sanitizedCount++; $null = $sanitizedKeys.Add([PSCustomObject]@{ Original = $itemFilename.OriginalKey; Sanitized = [System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename) }) }
                $itemFilePath = Join-Path $bucketPath $itemFilename.Filename
                $writeResult = Save-BucketFile -Path $itemFilePath -Item $item -Extension $extension -AsBinary:$AsBinary.IsPresent -Compress:$Compress.IsPresent -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite.IsPresent -BucketPath $bucketPath -Bucket $Bucket
                if ($writeResult.Success) {
                    $savedCount++
                    $null = $storedKeys.Add($keyName)
                    if ($writeResult.Overwritten) { $overwrittenCount++; $null = $overwrittenKeys.Add($keyName) }
                    if ($showProgress -and $totalForItems -gt 50) {
                        $percent = if ($totalForItems -gt 0) { [math]::Round(($savedCount / $totalForItems) * 100) } else { 0 }
                        Write-Progress -Activity "Saving to '$Bucket'" -Status "$savedCount object(s) saved" -PercentComplete $percent -CurrentOperation ([System.IO.Path]::GetFileNameWithoutExtension($itemFilename.Filename))
                    }
                }
                elseif ($writeResult.Skipped) { $skippedCount++; $null = $skippedKeys.Add($keyName) }
                else { $failedCount++ }
                if ($writeResult.Fallback) { $fallbackCount++ }
                if ($writeResult.FormatFallback) { $formatFallbackCount++ }
                $index++
            }
        }

        if ($showProgress -or $useVerbose) { Write-Progress -Activity "Saving to '$Bucket'" -Completed }
        if (-not $useQuiet) {
            $compressStr = if ($Compress) { " · compressed" } else { "" }
            Write-Host "$Bucket" -NoNewline -ForegroundColor $script:CPath
            Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
            Write-Host $savedCount -NoNewline -ForegroundColor $script:CNum
            Write-Host " objects" -NoNewline -ForegroundColor $script:CMuted
            if ($compressStr) { Write-Host $compressStr -NoNewline -ForegroundColor $script:CMuted }
            Write-Host ""
            if ($overwrittenCount -gt 0) {
                Write-Host "  " -NoNewline
                Write-Host $overwrittenCount -NoNewline -ForegroundColor $script:CNum
                Write-Host " overwritten" -ForegroundColor $script:CSkip
            }
            if ($sanitizedCount -gt 0) {
                Write-Host "  " -NoNewline
                Write-Host $sanitizedCount -NoNewline -ForegroundColor $script:CNum
                Write-Host " key name(s) sanitized" -ForegroundColor $script:CSkip
            }
            if ($skippedCount -gt 0) {
                Write-Host "  " -NoNewline
                Write-Host $skippedCount -NoNewline -ForegroundColor $script:CNum
                Write-Host " skipped (existing or missing key)" -ForegroundColor $script:CSkip
            }
            if ($fallbackCount -gt 0) {
                Write-Host "  " -NoNewline
                Write-Host $fallbackCount -NoNewline -ForegroundColor $script:CNum
                Write-Host " depth fallback" -ForegroundColor $script:CSkip
            }
            if ($formatFallbackCount -gt 0) {
                Write-Warning "$formatFallbackCount object(s) too complex for JSON, saved as binary instead"
            }
            if ($failedCount -gt 0) {
                Write-Host "  " -NoNewline
                Write-Host $failedCount -NoNewline -ForegroundColor $script:CNum
                Write-Host " failed to serialize" -ForegroundColor $script:CError
            }
        }
        if ($PassThru) {
            Write-Output ([PSCustomObject]@{
                Bucket      = $Bucket
                Saved       = $savedCount
                Skipped     = $skippedCount
                Overwritten = $overwrittenCount
                Sanitized   = $sanitizedCount
                Failed      = $failedCount
                Total       = $savedCount + $skippedCount + $failedCount
                Format      = if ($AsBinary) { "Binary" } else { "JSON" }
                Compressed  = $Compress.IsPresent
                StoredKeys   = [string[]]$storedKeys
                SkippedKeys  = [string[]]$skippedKeys
                SanitizedKeys = [PSCustomObject[]]$sanitizedKeys
                OverwrittenKeys = [string[]]$overwrittenKeys
            })
        }
    }
}

function Write-RemovalSummary {
    param(
        [string]$Title,
        [string[]]$Names,
        [int[]]$Counts,
        [string[]]$Sizes,
        [string[][]]$Nested,
        [int]$MaxShow = 10
    )
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor $script:CPath
    for ($i = 0; $i -lt $Names.Count; $i++) {
        $count = if ($Counts[$i] -eq 1) { "1 object" } else { "$($Counts[$i]) objects" }
        Write-Host "    " -NoNewline
        Write-Host "$($Names[$i])" -NoNewline -ForegroundColor $script:CPath
        Write-Host " (" -NoNewline -ForegroundColor $script:CMuted
        Write-Host "$count" -NoNewline -ForegroundColor $script:CNum
        Write-Host ", " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "$($Sizes[$i])" -NoNewline -ForegroundColor $script:CNum
        Write-Host ")" -NoNewline -ForegroundColor $script:CMuted
        if ($Nested -and $Nested[$i] -and $Nested[$i].Count -gt 0) {
            Write-Host " [includes nested: $($Nested[$i] -join ', ')]" -ForegroundColor $script:CMuted
        } else {
            Write-Host ""
        }
    }
    if ($Names.Count -gt $MaxShow) {
        Write-Host "    ... and $($Names.Count - $MaxShow) more" -ForegroundColor $script:CMuted
    }
    Write-Host ""
}

function Remove-Bucket {
    <#
    .SYNOPSIS
    Removes one or more buckets and all their objects.
    .DESCRIPTION
    Deletes bucket directories and their contents. Supports exact names, multiple
    buckets, and wildcard patterns (including nested bucket paths like "projects/myapp").
    Only removes directories containing bucket objects (or empty directories).
    Skips buckets with other file types.

    By default, only removes files in the target bucket and leaves nested bucket
    directories intact. Use -Recurse to remove the target and all nested buckets.

    Uses standard -Confirm/-WhatIf support (SupportsShouldProcess).
    -Force skips the confirmation prompt entirely.
    .PARAMETER Bucket
    Bucket name(s) or wildcard patterns to remove. Supports glob-style wildcards (*, ?).
    For nested buckets, use path notation like "projects/myapp".
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Recurse
    Remove the target bucket and all nested buckets beneath it. Without this flag,
    nested bucket directories are preserved.
    .PARAMETER Force
    Skip confirmation prompt and remove immediately.
    .PARAMETER WhatIf
    Preview which buckets would be removed without actually deleting them.
    .PARAMETER Quiet
    Suppress progress output.
    .EXAMPLE
    Remove-Bucket -Bucket users
    .EXAMPLE
    Remove-Bucket -Bucket "projects/myapp"
    .EXAMPLE
    Remove-Bucket -Bucket "temp*" -Force
    .EXAMPLE
    Remove-Bucket -Bucket projects -Recurse
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)][string[]]$Bucket,
        [string]$Path,
        [switch]$Recurse,
        [switch]$Force,
        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path

    function Find-MatchingBuckets {
        param([string]$Root, [string[]]$Patterns)

        function Scan-Dir {
            param([string]$Dir)
            $matched = @()
            if (-not [System.IO.Directory]::Exists($Dir)) { return $matched }
            $di = [System.IO.DirectoryInfo]::new($Dir)
            $relName = ""
            if ($Dir -ne $Root) {
                $relName = $Dir.Substring($Root.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
            }
            if ($Dir -ne $Root) {
                foreach ($pattern in $Patterns) {
                    if ($pattern -match '[\*\?]') {
                        if ($relName -like $pattern) {
                            $matched += [PSCustomObject]@{ Name = $relName; Path = $Dir }
                            break
                        }
                    }
                    elseif ($pattern -eq "*" -or $relName -eq $pattern -or ($relName -like "$pattern*") -or ($relName -like "*/$pattern") -or ($relName -like "*/$pattern/*") -or ($relName -like "$pattern/*")) {
                        $matched += [PSCustomObject]@{ Name = $relName; Path = $Dir }
                        break
                    }
                }
            }
            foreach ($subDir in $di.GetDirectories()) {
                if ($subDir.Name -eq ".buckets") { continue }
                $matched += Scan-Dir -Dir $subDir.FullName
            }
            $matched
        }

        if ([System.IO.Directory]::Exists($Root)) {
            Scan-Dir -Dir $Root
        }
    }

    $matched = Find-MatchingBuckets -Root $Path -Patterns $Bucket

    if ($matched.Count -eq 0) {
        Write-Warning "No buckets match the specified pattern(s)"
        return
    }

    $removable = @()
    $skippedBuckets = @()
    foreach ($m in $matched) {
        $resolvedRoot = Resolve-SafePath -Path $Path
        $resolvedBucket = Resolve-SafePath -Path $m.Path
        if (-not $resolvedBucket.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $skippedBuckets += [PSCustomObject]@{ Name = $m.Name; Reason = "path resolves outside root" }
            continue
        }

        $di = [System.IO.DirectoryInfo]::new($m.Path)
        $allFiles = @($di.GetFiles())
        $otherFiles = @($allFiles | Where-Object { $_.Extension -notin ".dat", ".json" })
        if ($otherFiles.Count -gt 0) {
            $skippedBuckets += [PSCustomObject]@{ Name = $m.Name; Reason = "contains $($otherFiles.Count) non-bucket file(s): $($otherFiles.Name -join ', ')" }
            continue
        }

        $nestedBuckets = @()
        foreach ($subDir in $di.GetDirectories()) {
            if ($subDir.Name -eq ".buckets") { continue }
            if ($subDir.GetFiles("*.dat").Length -gt 0 -or $subDir.GetFiles("*.json").Length -gt 0) {
                $nestedBuckets += $subDir.Name
            }
        }

        $stats = Get-BucketStats -Bucket $m.Name -Path $Path
        $hasNested = $nestedBuckets.Count -gt 0

        $removable += [PSCustomObject]@{
            Name = $m.Name
            Objects = if ($stats) { $stats.ObjectCount } else { 0 }
            Size = if ($stats) { $stats.TotalSize } else { "0 KB" }
            Path = $m.Path
            HasNestedBuckets = $hasNested
            NestedBucketNames = $nestedBuckets
        }
    }

    if ($removable.Count -eq 0 -and $skippedBuckets.Count -eq 0) { return }

    # When -Recurse, deduplicate: only keep buckets that aren't subdirectories of other matched buckets
    if ($Recurse -and $removable.Count -gt 1) {
        $sorted = @($removable | Sort-Object { $_.Path.Length })
        $topLevel = @()
        foreach ($r in $sorted) {
            $isChild = $false
            foreach ($existing in $topLevel) {
                if ($r.Path.StartsWith($existing.Path + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $isChild = $true
                    break
                }
            }
            if (-not $isChild) { $topLevel += $r }
        }
        $removable = $topLevel
    }

    if ($WhatIfPreference) {
        if ($removable.Count -gt 0) {
            Write-RemovalSummary -Title "What if: Remove the following bucket(s)" `
                -Names $removable.Name -Counts $removable.Objects -Sizes $removable.Size -Nested $removable.NestedBucketNames
        }
        if ($skippedBuckets.Count -gt 0) {
            Write-Host "  Skipped:" -ForegroundColor $script:CSkip
            foreach ($s in $skippedBuckets) {
                Write-Host "    " -NoNewline
                Write-Host "$($s.Name)" -NoNewline -ForegroundColor $script:CPath
                Write-Host " — " -NoNewline -ForegroundColor $script:CMuted
                Write-Host "$($s.Reason)" -ForegroundColor $script:CError
            }
        }
        return
    }

    if ($removable.Count -eq 0 -and $skippedBuckets.Count -eq 0) { return }

    # Pre-confirmation summary (unless -Force or -Quiet)
    if (-not $Force -and -not $Quiet -and $removable.Count -gt 0) {
        $preserved = @()
        foreach ($r in $removable) {
            if ($r.HasNestedBuckets -and -not $Recurse) {
                $preserved += @($r.NestedBucketNames)
            } else {
                $preserved += @()
            }
        }
        Write-RemovalSummary -Title "Remove $($removable.Count) bucket(s)?" `
            -Names $removable.Name -Counts $removable.Objects -Sizes $removable.Size -Nested $preserved
    }

    # Skipped buckets (always shown if any)
    if ($skippedBuckets.Count -gt 0 -and -not $Quiet) {
        foreach ($s in $skippedBuckets) {
            Write-Host "  " -NoNewline -ForegroundColor $script:CMuted
            Write-Host "$($s.Name)" -NoNewline -ForegroundColor $script:CPath
            Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
            Write-Host "$($s.Reason)" -ForegroundColor $script:CError
        }
    }

    $removedCount = 0
    # Sort deepest paths first so children are deleted before parents
    $removable = @($removable | Sort-Object { $_.Path.Length } -Descending)
    foreach ($r in $removable) {
        if (-not [System.IO.Directory]::Exists($r.Path)) { continue }
        $finalDi = [System.IO.DirectoryInfo]::new($r.Path)
        $finalFiles = @($finalDi.GetFiles())
        $finalOther = @($finalFiles | Where-Object { $_.Extension -notin ".dat", ".json" })
        if ($finalOther.Count -gt 0) {
            Write-Warning "Bucket '$($r.Name)' now contains non-bucket files, aborting: $($finalOther.Name -join ', ')"
            continue
        }

        $target = "bucket '$($r.Name)' ($($r.Objects) object(s), $($r.Size))"
        $shouldRemove = $Force
        if (-not $Force) {
            $shouldRemove = $PSCmdlet.ShouldProcess($target, "Remove-Bucket")
        }

        if ($shouldRemove) {
            if ($r.HasNestedBuckets -and -not $Recurse) {
                $finalDirs = @($finalDi.GetDirectories())
                foreach ($f in $finalFiles) { $f.Delete() }
                foreach ($d in $finalDirs) {
                    $hasBucketFiles = $d.GetFiles("*.dat").Length -gt 0 -or $d.GetFiles("*.json").Length -gt 0
                    if (-not $hasBucketFiles -and $d.GetDirectories().Length -eq 0) {
                        $d.Delete()
                    }
                }
                $remainingDirs = @($finalDi.GetDirectories())
                if ($remainingDirs.Count -eq 0 -and $finalDi.GetFiles().Length -eq 0) {
                    $finalDi.Delete()
                }
                $cacheKeys = @($script:BucketPathCache.Keys) | Where-Object { $_ -like "*|$($r.Name)" }
                foreach ($ck in $cacheKeys) { $script:BucketPathCache.Remove($ck) }
            }
            elseif ($Recurse) {
                [System.IO.Directory]::Delete($r.Path, $true)
                $cacheKeys = @($script:BucketPathCache.Keys) | Where-Object { $_ -like "*|$($r.Name)*" }
                foreach ($ck in $cacheKeys) { $script:BucketPathCache.Remove($ck) }
            }
            else {
                $finalDirs = @($finalDi.GetDirectories())
                if ($finalDirs.Count -gt 0) {
                    Write-Warning "Bucket '$($r.Name)' contains non-bucket subdirectories, aborting"
                    continue
                }
                [System.IO.Directory]::Delete($r.Path, $true)
                $cacheKeys = @($script:BucketPathCache.Keys) | Where-Object { $_ -like "*|$($r.Name)" }
                foreach ($ck in $cacheKeys) { $script:BucketPathCache.Remove($ck) }
            }

            $removedCount++
            if (-not $Quiet) {
                Write-Host "$($r.Name)" -NoNewline -ForegroundColor $script:CPath
                Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
                $objLabel = if ($r.Objects -eq 1) { "1 object" } else { "$($r.Objects) objects" }
                Write-Host $objLabel -NoNewline -ForegroundColor $script:CNum
                Write-Host " removed" -ForegroundColor $script:CMuted
            }
        }
    }

    if ($removedCount -gt 1 -and -not $Quiet) {
        Write-Host $removedCount -NoNewline -ForegroundColor $script:CNum
        Write-Host " buckets removed" -ForegroundColor $script:CMuted
    }
}

function Remove-BucketObject {
    <#
    .SYNOPSIS
    Removes an object from a bucket.
    .DESCRIPTION
    Deletes a specific object file from a bucket directory. Use -Key to remove a single
    object, -All to clear the entire bucket, or -Match/-Filter for bulk deletion.
    .PARAMETER Bucket
    Name of the bucket containing the object(s) to remove.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Key
    Object key to remove. Looks for both JSON and binary files. Case-insensitive.
    .PARAMETER All
    Remove all objects from the bucket.
    .PARAMETER Match
    Hashtable of property-value pairs for bulk deletion. All pairs must match. Supports $null values.
    .PARAMETER Filter
    ScriptBlock for custom bulk deletion. Use $_ to reference object properties.
    .PARAMETER PassThru
    Return metadata for removed objects.
    .PARAMETER Quiet
    Suppress progress output.
    .EXAMPLE
    Remove-BucketObject -Bucket logs -Key "log-003"
    .EXAMPLE
    Remove-BucketObject -Bucket temp -All -PassThru
    .EXAMPLE
    Remove-BucketObject -Bucket users -Match @{ Active = $false } -PassThru
    .EXAMPLE
    Remove-BucketObject -Bucket orders -Filter { $_.Status -eq "cancelled" }
    .EXAMPLE
    Remove-BucketObject -Bucket users -Key "Charlie" -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByKey')]
    param(
        [Parameter(Mandatory = $true)][string]$Bucket,
        [string]$Path,
        [Parameter(ParameterSetName = 'ByKey')][string]$Key,
        [Parameter(ParameterSetName = 'All')][switch]$All,
        [Parameter(ParameterSetName = 'ByFilter')][hashtable]$Match,
        [Parameter(ParameterSetName = 'ByFilter')][scriptblock]$Filter,
        [switch]$PassThru,
        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path

    if (-not [System.IO.Directory]::Exists($bucketPath)) {
        Write-Verbose "Bucket '$Bucket' not found at '$bucketPath'"
        return
    }

    if ($All) {
        $allFiles = @()
        $di = [System.IO.DirectoryInfo]::new($bucketPath)
        $allFiles += @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))

        if ($allFiles.Count -eq 0) { Write-Verbose "Bucket '$Bucket' is already empty"; return }

        $bucketSize = ($allFiles | Measure-Object -Property Length -Sum).Sum
        $sizeStr = if ($bucketSize) { "$([math]::Round($bucketSize / 1KB, 2)) KB" } else { "0 KB" }

        if ($WhatIfPreference) {
            Write-Host ""
            Write-Host "  What if: Remove all " -NoNewline -ForegroundColor $script:CMuted
            Write-Host $allFiles.Count -NoNewline -ForegroundColor $script:CNum
            Write-Host " object(s) from " -NoNewline -ForegroundColor $script:CMuted
            Write-Host $Bucket -NoNewline -ForegroundColor $script:CPath
            Write-Host " ($sizeStr)" -ForegroundColor $script:CMuted
            Write-Host ""
            return
        }

        $target = "$($allFiles.Count) object(s) from bucket '$Bucket'"
        if ($PSCmdlet.ShouldProcess($target, "Remove-BucketObject")) {
            $allFiles | ForEach-Object { [System.IO.File]::Delete($_.FullName) }
            foreach ($d in $di.GetDirectories()) {
                if ($d.Name -eq ".buckets") { continue }
                $remaining = @($d.GetFiles()) + @($d.GetDirectories())
                if ($remaining.Count -eq 0) { [System.IO.Directory]::Delete($d.FullName) }
            }
        }

        if ($PassThru) {
            foreach ($f in $allFiles) {
                $relPath = $f.FullName.Substring($bucketPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
                [PSCustomObject]@{ Bucket = $Bucket; Key = $relPath }
            }
        }
        elseif (-not $WhatIfPreference -and -not $Quiet) {
            Write-Host "$Bucket" -NoNewline -ForegroundColor $script:CPath
            Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
            $objLabel = if ($allFiles.Count -eq 1) { "1 object" } else { "$($allFiles.Count) objects" }
            Write-Host $objLabel -NoNewline -ForegroundColor $script:CNum
            Write-Host " removed" -ForegroundColor $script:CMuted
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Key)) {
        $file = Find-ObjectFile -BucketPath $bucketPath -Key $Key
        if ($null -eq $file) {
            Write-Warning "Object with key '$Key' not found in bucket '$Bucket'"
        }
        elseif ($PSCmdlet.ShouldProcess("object '$Key' from bucket '$Bucket'", "Remove-BucketObject")) {
            if ($PassThru) {
                $relPath = $file.FullName.Substring($bucketPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
                [PSCustomObject]@{ Bucket = $Bucket; Key = $relPath }
            }
            [System.IO.File]::Delete($file.FullName)
            $parentDir = [System.IO.Path]::GetDirectoryName($file.FullName)
            if ($parentDir -ne $bucketPath -and $parentDir.StartsWith($bucketPath)) {
                $parentDi = [System.IO.DirectoryInfo]::new($parentDir)
                $remaining = @($parentDi.GetFiles()) + @($parentDi.GetDirectories())
                if ($remaining.Count -eq 0) {
                    [System.IO.Directory]::Delete($parentDir)
                }
            }
            if (-not $PassThru -and -not $Quiet -and -not $WhatIfPreference) {
                Write-Host "$Bucket/$Key" -NoNewline -ForegroundColor $script:CPath
                Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
                Write-Host "removed" -ForegroundColor $script:CNum
            }
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'ByFilter') {
        $allFiles = @()
        $di = [System.IO.DirectoryInfo]::new($bucketPath)
        $allFiles += @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))

        if ($allFiles.Count -eq 0) { Write-Verbose "Bucket '$Bucket' is already empty"; return }

        $matchedFiles = @()
        $matchedKeys = @()
        foreach ($file in $allFiles) {
            $obj = Read-BucketFile -File $file
            if ($null -eq $obj) { continue }
            if ($Match -and -not (Test-MatchFilter -Object $obj -Match $Match)) { continue }
            if ($Filter) {
                if ($null -eq ($obj | Where-Object $Filter)) { continue }
            }
            $matchedFiles += $file
            $matchedKeys += [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        }

        if ($matchedFiles.Count -eq 0) { Write-Verbose "No objects matched the filter criteria in bucket '$Bucket'"; return }

        $matchSize = ($matchedFiles | Measure-Object -Property Length -Sum).Sum
        $sizeStr = if ($matchSize) { "$([math]::Round($matchSize / 1KB, 2)) KB" } else { "0 KB" }

        if ($WhatIfPreference) {
            Write-Host ""
            Write-Host "  What if: Remove " -NoNewline -ForegroundColor $script:CMuted
            Write-Host $matchedFiles.Count -NoNewline -ForegroundColor $script:CNum
            Write-Host " matching object(s) from " -NoNewline -ForegroundColor $script:CMuted
            Write-Host $Bucket -NoNewline -ForegroundColor $script:CPath
            Write-Host " ($sizeStr)" -ForegroundColor $script:CMuted
            $showKeys = $matchedKeys | Select-Object -First 5
            foreach ($k in $showKeys) {
                Write-Host "    $k" -ForegroundColor $script:CMuted
            }
            if ($matchedKeys.Count -gt 5) {
                Write-Host "    ... and $($matchedKeys.Count - 5) more" -ForegroundColor $script:CMuted
            }
            Write-Host ""
            return
        }

        # Pre-confirmation summary
        if (-not $Quiet) {
            Write-Host ""
            Write-Host "  Remove " -NoNewline -ForegroundColor $script:CMuted
            Write-Host $matchedFiles.Count -NoNewline -ForegroundColor $script:CNum
            Write-Host " matching object(s) from " -NoNewline -ForegroundColor $script:CMuted
            Write-Host $Bucket -NoNewline -ForegroundColor $script:CPath
            Write-Host " ($sizeStr)" -ForegroundColor $script:CMuted
            $showKeys = $matchedKeys | Select-Object -First 5
            foreach ($k in $showKeys) {
                Write-Host "    " -NoNewline
                Write-Host $k -ForegroundColor $script:CNum
            }
            if ($matchedKeys.Count -gt 5) {
                Write-Host "    ... and $($matchedKeys.Count - 5) more" -ForegroundColor $script:CMuted
            }
            Write-Host ""
        }

        $target = "$($matchedFiles.Count) matching object(s) from bucket '$Bucket'"
        if ($PSCmdlet.ShouldProcess($target, "Remove-BucketObject")) {
            foreach ($f in $matchedFiles) {
                if ($PassThru) {
                    $relPath = $f.FullName.Substring($bucketPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
                    [PSCustomObject]@{ Bucket = $Bucket; Key = $relPath }
                }
                [System.IO.File]::Delete($f.FullName)
            }
            if (-not $PassThru -and -not $Quiet) {
                Write-Host "$Bucket" -NoNewline -ForegroundColor $script:CPath
                Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
                $objLabel = if ($matchedFiles.Count -eq 1) { "1 object" } else { "$($matchedFiles.Count) objects" }
                Write-Host $objLabel -NoNewline -ForegroundColor $script:CNum
                Write-Host " removed (matched)" -ForegroundColor $script:CMuted
            }
        }
        elseif (-not $WhatIfPreference) { Write-Verbose "Would remove $($matchedFiles.Count) object(s) from bucket '$Bucket'" }
    }
    else {
        throw "Specify either -Key, -All, or -Match/-Filter"
    }
}

function Rename-BucketObject {
    <#
    .SYNOPSIS
    Renames an object key within a bucket.
    .DESCRIPTION
    Moves an object file to a new key within the same bucket without re-serialization.
    Preserves the original format (JSON or binary).
    .PARAMETER Bucket
    Bucket name.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Key
    Current object key.
    .PARAMETER NewKey
    New object key.
    .PARAMETER PassThru
    Return metadata for the renamed object.
    .EXAMPLE
    Rename-BucketObject -Bucket users -Key "Alice" -NewKey "alice-smith"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Bucket,
        [string]$Path,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$NewKey,
        [switch]$PassThru,
        [switch]$Quiet
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
    $Path = Resolve-SafePath -Path $Path
    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path
    if (-not [System.IO.Directory]::Exists($bucketPath)) {
        throw "Bucket '$Bucket' not found at '$bucketPath'"
    }

    $safeNewKey = $NewKey -replace '[\\/:\*\?"<>\|\[\]]', '_'
    if ([string]::IsNullOrWhiteSpace($safeNewKey) -or $safeNewKey -match '^_+$') {
        throw "New key '$NewKey' is invalid after sanitization"
    }

    $sourceFile = Find-ObjectFile -BucketPath $bucketPath -Key $Key
    if ($null -eq $sourceFile) {
        throw "Object with key '$Key' not found in bucket '$Bucket'"
    }

    $ext = $sourceFile.Extension
    $destJsonPath = Join-Path $bucketPath "${safeNewKey}.json"
    $destDatPath = Join-Path $bucketPath "${safeNewKey}.dat"
    if ([System.IO.File]::Exists($destJsonPath) -or [System.IO.File]::Exists($destDatPath)) {
        throw "Object with key '$safeNewKey' already exists in bucket '$Bucket'"
    }

    $destFile = Join-Path $bucketPath "${safeNewKey}${ext}"
    [System.IO.File]::Move($sourceFile, $destFile)
    Write-Verbose "Renamed [$Bucket/$Key] to [$Bucket/$safeNewKey]"

    if ($PassThru) {
        [PSCustomObject]@{ Bucket = $Bucket; OldKey = $Key; NewKey = $safeNewKey }
    }
    elseif (-not $Quiet) {
        Write-Host "$Bucket/$Key" -NoNewline -ForegroundColor $script:CPath
        Write-Host " → " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "$safeNewKey" -ForegroundColor $script:CPath
    }
}

function Set-BucketObject {
    <#
    .SYNOPSIS
    Updates an existing object in a bucket.
    .DESCRIPTION
    Automatically detects whether the pipeline input is a full object replacement or a partial update.

    If the piped object contains _BucketName and _BucketKey metadata (from Get-BucketObject),
    the entire object replaces the stored version. If the piped object lacks metadata, only
    its properties are merged into the existing object (partial update).

    Preserves the storage format (JSON or binary) of the existing file. If JSON serialization
    fails on complex types, falls back to binary format.
    .PARAMETER InputObject
    The object to store. Accepts pipeline input. If it has _BucketName and _BucketKey metadata,
    bucket and key are auto-resolved. Otherwise -Bucket and -Key are required.
    .PARAMETER Bucket
    Name of the bucket containing the object. Auto-resolved from pipeline metadata if omitted.
    Required when piping partial updates.
    .PARAMETER Key
    Object key to update. Auto-resolved from pipeline metadata if omitted.
    Required when piping partial updates.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER Depth
    Maximum depth for JSON serialization. Default: 20.
    .PARAMETER BinaryDepth
    Maximum depth for binary (PSSerializer) serialization. Default: 5.
    .PARAMETER AsBinary
    Force binary (.dat) format for the updated file. Default is JSON (.json).
    .PARAMETER Compress
    Enable GZip compression for binary files. Only effective with -AsBinary.
    .PARAMETER Quiet
    Suppress all output. No summary.
    .EXAMPLE
    $user = Get-BucketObject -Bucket users -Key "Alice"
    $user.Role = "manager"
    $user | Set-BucketObject
    .EXAMPLE
    Set-BucketObject -InputObject @{ Role = "admin" } -Bucket users -Key Name
    .EXAMPLE
    Get-BucketObject -Bucket logs -Key "log-001" | ForEach-Object { $_.Level = "INFO"; $_ } | Set-BucketObject -Quiet
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)][PSObject]$InputObject,
        [Parameter(ValueFromPipelineByPropertyName = $true)][Alias("_BucketName")][string]$Bucket,
        [Parameter(ValueFromPipelineByPropertyName = $true)][Alias("_BucketKey")][string]$Key,
        [string]$Path,
        [ValidateRange(1, 100)][int]$Depth = 20,
        [ValidateRange(1, 100)][int]$BinaryDepth = 5,
        [switch]$AsBinary,
        [switch]$Compress,
        [switch]$PassThru,
        [switch]$Quiet
    )

    begin {
        $bucketPath = $null; $savedCount = 0; $lastBucket = ''
        $useVerbose = $VerbosePreference -eq 'Continue'; $useQuiet = $Quiet.IsPresent
        $updatedKeys = [System.Collections.ArrayList]::new()
    }

    process {
        $isPatch = -not ($InputObject.PSObject.Properties['_BucketName'] -and $InputObject.PSObject.Properties['_BucketKey'])

        if ($null -eq $bucketPath) {
            if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
            $Path = Resolve-SafePath -Path $Path
        }

        if ($isPatch) {
            if ([string]::IsNullOrWhiteSpace($Bucket) -or [string]::IsNullOrWhiteSpace($Key)) {
                throw "When piping partial updates, you must specify -Bucket and -Key explicitly."
            }
        }
        else {
            if ([string]::IsNullOrWhiteSpace($Bucket) -or [string]::IsNullOrWhiteSpace($Key)) {
                if ($InputObject.PSObject.Properties['_BucketName']) { $Bucket = $InputObject._BucketName }
                if ($InputObject.PSObject.Properties['_BucketKey']) { $Key = $InputObject._BucketKey }
                if ([string]::IsNullOrWhiteSpace($Bucket) -or [string]::IsNullOrWhiteSpace($Key)) {
                    throw "Cannot determine bucket and key. Use -Bucket and -Key parameters, or pipe an object from Get-BucketObject."
                }
            }
        }

        if ($InputObject.PSObject.Properties[$Key]) {
            $resolvedKey = $InputObject.$Key
            if ($null -ne $resolvedKey) { $Key = $resolvedKey -replace '[\\/:\*\?"<>\|\[\]]', '_' }
        }

        if ($null -eq $bucketPath) {
            $bucketPath = Get-BucketPath -Name $Bucket -Path $Path
            if (-not [System.IO.Directory]::Exists($bucketPath)) {
                throw "Bucket '$Bucket' not found at '$bucketPath'"
            }
        }

        $file = Find-ObjectFile -BucketPath $bucketPath -Key $Key
        if ($null -eq $file) {
            throw "Object with key '$Key' not found in bucket '$Bucket'"
        }

        $filePath = $file.FullName
        $useJson = $file.Extension -eq ".json" -and -not $AsBinary

        if ($isPatch) {
            $existing = Read-BucketFile -File ([System.IO.FileInfo]::new($filePath))
            if ($null -eq $existing) { throw "Failed to read existing object '$Key' in bucket '$Bucket'" }
            if ($InputObject -is [hashtable]) {
                if ($existing -is [hashtable]) {
                    foreach ($kvp in $InputObject.GetEnumerator()) { $existing[$kvp.Key] = $kvp.Value }
                }
                else {
                    foreach ($kvp in $InputObject.GetEnumerator()) {
                        if ($existing.PSObject.Properties[$kvp.Key]) { $existing.PSObject.Properties[$kvp.Key].Value = $kvp.Value }
                        else { $existing | Add-Member -NotePropertyName $kvp.Key -NotePropertyValue $kvp.Value }
                    }
                }
            }
            else {
                foreach ($prop in $InputObject.PSObject.Properties) {
                    if ($prop.IsSettable) {
                        if ($existing -is [hashtable]) { $existing[$prop.Name] = $prop.Value }
                        elseif ($existing.PSObject.Properties[$prop.Name]) { $existing.PSObject.Properties[$prop.Name].Value = $prop.Value }
                        else { $existing | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value }
                    }
                }
            }
            $InputObject = $existing
        }

        $writeSuccess = $false
        if ($useJson) {
            try {
                $json = ConvertTo-Json -InputObject $InputObject -Depth $Depth -Compress -WarningAction SilentlyContinue
                [System.IO.File]::WriteAllText($filePath, $json, [System.Text.Encoding]::UTF8)
                $writeSuccess = $true
            }
            catch {
                try {
                    $xml = [System.Management.Automation.PSSerializer]::Serialize($InputObject, $BinaryDepth)
                    $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                    if (Test-Path $filePath) { Remove-Item $filePath -Force }
                    $filePath = [System.IO.Path]::ChangeExtension($filePath, ".dat")
                    if ($Compress) {
                        $ms = [System.IO.MemoryStream]::new()
                        $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
                        $cs.Write($rawBytes, 0, $rawBytes.Length)
                        $cs.Close()
                        [System.IO.File]::WriteAllBytes($filePath, $ms.ToArray())
                    }
                    else { [System.IO.File]::WriteAllBytes($filePath, $rawBytes) }
                    Write-Warning "Object '$Key' too complex for JSON, saved as binary instead"
                    $writeSuccess = $true
                }
                catch { throw "Failed to serialize object '$Key' as binary: $_" }
            }
        }
        else {
            $currentDepth = $BinaryDepth; $serialized = $false
            while (-not $serialized -and $currentDepth -le 10) {
                try {
                    $xml = [System.Management.Automation.PSSerializer]::Serialize($InputObject, $currentDepth)
                    $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
                    if ($Compress) {
                        $ms = [System.IO.MemoryStream]::new()
                        $cs = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
                        $cs.Write($rawBytes, 0, $rawBytes.Length)
                        $cs.Close()
                        [System.IO.File]::WriteAllBytes($filePath, $ms.ToArray())
                    }
                    else { [System.IO.File]::WriteAllBytes($filePath, $rawBytes) }
                    $serialized = $true
                    if ($currentDepth -gt $BinaryDepth) { Write-Verbose "Binary serialization required depth $currentDepth (default: $BinaryDepth)" }
                }
                catch { $currentDepth++ }
            }
            if (-not $serialized) { throw "Failed to serialize object '$Key' at any binary depth" }
            $writeSuccess = $true
        }

        if ($writeSuccess) {
            $savedCount++
            $lastBucket = $Bucket
            $null = $updatedKeys.Add($Key)
            if ($useVerbose) { Write-Verbose "Updated [$Bucket/$Key] -> $filePath" }
        }
    }

    end {
        if ($savedCount -gt 0 -and -not $useVerbose -and -not $useQuiet) {
            Write-Host "$lastBucket" -NoNewline -ForegroundColor $script:CPath
            Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
            Write-Host $savedCount -NoNewline -ForegroundColor $script:CNum
            Write-Host " updated" -ForegroundColor $script:CMuted
        }
        if ($PassThru -and $savedCount -gt 0) {
            Write-Output ([PSCustomObject]@{
                Bucket      = $lastBucket
                Saved       = $savedCount
                UpdatedKeys = [string[]]$updatedKeys
                Format      = if ($AsBinary) { "Binary" } else { "JSON" }
                Compressed  = $Compress.IsPresent
            })
        }
    }
}

# --- Funnel management ---

function New-Funnel {
    <#
    .SYNOPSIS
    Creates a named funnel (reusable filter/transform scriptblock).
    .DESCRIPTION
    Saves a named funnel definition to $HOME/.buckets-system/funnels/. Funnels can be
    referenced by name with the -Funnel parameter on fill and scoop.
    A funnel is a scriptblock operating on $_ that returns the object to keep it
    (optionally modified), or $null to drop it. This works identically on fill and scoop.
    .PARAMETER Name
    Name for the funnel. Used to reference it later via -Funnel.
    .PARAMETER Filter
    ScriptBlock defining the funnel logic. Use $_ for the pipeline object.
    .PARAMETER Description
    Optional human-readable description of what the funnel does.
    .PARAMETER Force
    Overwrite an existing funnel with the same name.
    .PARAMETER Quiet
    Suppress success output.
    .EXAMPLE
    New-Funnel -Name admins -Filter { if ($_.Role -eq "admin") { $_ } }
    .EXAMPLE
    New-Funnel -Name add-source -Filter { $_ | Add-Member -NotePropertyName "Source" -NotePropertyValue "import" -PassThru } -Description "Adds Source property"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Filter,
        [string]$Description = "",
        [scriptblock]$AppliesTo,
        [switch]$Force,
        [switch]$Quiet
    )

    $funnelDir = Join-Path (Get-BucketsSystemPath) "funnels"
    if (-not (Test-Path $funnelDir)) { New-Item -ItemType Directory -Path $funnelDir -Force | Out-Null }
    $funnelFile = Join-Path $funnelDir "$Name.json"
    if ((Test-Path $funnelFile) -and -not $Force) { throw "Funnel '$Name' already exists. Use -Force to overwrite." }

    $saveObj = @{ Filter = "$Filter"; Description = $Description }
    $cacheObj = @{ Filter = "$Filter"; Description = $Description }
    if ($AppliesTo) { $saveObj.AppliesTo = "$AppliesTo"; $cacheObj.AppliesTo = "$AppliesTo" }
    $text = $saveObj | ConvertTo-Json
    [System.IO.File]::WriteAllText($funnelFile, $text, [System.Text.Encoding]::UTF8)
    $script:FunnelCache[$Name] = $cacheObj
    if (-not $Quiet) {
        Write-Host "$Name" -NoNewline -ForegroundColor $script:CPath
        Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "funnel saved" -ForegroundColor $script:CNum
    }
}

function Get-Funnel {
    <#
    .SYNOPSIS
    Lists named funnels or retrieves a specific funnel definition.
    .DESCRIPTION
    Returns funnel definitions from the user funnels directory ($HOME/.buckets-system/funnels/)
    and built-in funnels shipped with the module. User funnels with the same name override
    built-in ones. When no name is given, lists all funnels.
    .PARAMETER Name
    Optional funnel name to retrieve. Returns all funnels if omitted.
    .EXAMPLE
    Get-Funnel
    .EXAMPLE
    Get-Funnel -Name admins
    .EXAMPLE
    Get-Funnel -Name file-light
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Name
    )

    if ($Name) {
        $def = Get-FunnelDefinition -Name $Name
        $out = [PSCustomObject]@{ Name = $Name; Filter = $def.Filter; Description = $def.Description }
        if ($def.AppliesTo) { $out | Add-Member -NotePropertyName AppliesTo -NotePropertyValue $def.AppliesTo }
        $out
        return
    }

    $seen = @{}

    $userDir = Join-Path (Get-BucketsSystemPath) "funnels"
    if (Test-Path $userDir) {
        foreach ($f in [System.IO.DirectoryInfo]::new($userDir).GetFiles("*.json")) {
            $fName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            $def = Get-FunnelDefinition -Name $fName
            $out = [PSCustomObject]@{ Name = $fName; Filter = $def.Filter; Description = $def.Description }
            if ($def.AppliesTo) { $out | Add-Member -NotePropertyName AppliesTo -NotePropertyValue $def.AppliesTo }
            $out
            $seen[$fName] = $true
        }
    }

    if (Test-Path $script:BuiltinFunnelsDir) {
        foreach ($f in [System.IO.DirectoryInfo]::new($script:BuiltinFunnelsDir).GetFiles("*.json")) {
            $fName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if (-not $seen.ContainsKey($fName)) {
                $def = Get-FunnelDefinition -Name $fName
                $out = [PSCustomObject]@{ Name = $fName; Filter = $def.Filter; Description = $def.Description }
                if ($def.AppliesTo) { $out | Add-Member -NotePropertyName AppliesTo -NotePropertyValue $def.AppliesTo }
                $out
            }
        }
    }
}
function Set-Funnel {
    <#
    .SYNOPSIS
    Updates an existing named funnel's filter scriptblock or description.
    .DESCRIPTION
    Modifies a funnel definition in $HOME/.buckets-system/funnels/. The funnel must
    already exist. Omitting -Filter or -Description keeps the current value.
    .PARAMETER Name
    Name of the funnel to update.
    .PARAMETER Filter
    New scriptblock for the funnel. Uses $_ for the pipeline object.
    .PARAMETER Description
    New description for the funnel.
    .PARAMETER Quiet
    Suppress success output.
    .EXAMPLE
    Set-Funnel -Name admins -Filter { $_.Role -eq "admin" -and $_.Active -eq $true }
    .EXAMPLE
    Set-Funnel -Name admins -Description "Filters active admin users"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [scriptblock]$Filter,
        [string]$Description,
        [scriptblock]$AppliesTo,
        [switch]$Quiet
    )

    $funnelDir = Join-Path (Get-BucketsSystemPath) "funnels"
    $funnelFile = Join-Path $funnelDir "$Name.json"
    if (-not (Test-Path $funnelFile)) { throw "Funnel '$Name' not found. Use New-Funnel to create it." }

    $existing = Get-Content -Path $funnelFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($Filter) { $existing.Filter = "$Filter" }
    if ($PSBoundParameters.ContainsKey('Description')) { $existing.Description = $Description }
    if ($PSBoundParameters.ContainsKey('AppliesTo')) { $existing.AppliesTo = "$AppliesTo" }

    $saveObj = @{ Filter = $existing.Filter; Description = $existing.Description }
    $cacheObj = @{ Filter = $existing.Filter; Description = $existing.Description }
    if ($existing.AppliesTo) { $saveObj.AppliesTo = $existing.AppliesTo; $cacheObj.AppliesTo = $existing.AppliesTo }
    $text = $saveObj | ConvertTo-Json
    [System.IO.File]::WriteAllText($funnelFile, $text, [System.Text.Encoding]::UTF8)
    $script:FunnelCache[$Name] = $cacheObj
    if (-not $Quiet) {
        Write-Host "$Name" -NoNewline -ForegroundColor $script:CPath
        Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
        Write-Host "funnel updated" -ForegroundColor $script:CNum
    }
}

function Remove-Funnel {
    <#
    .SYNOPSIS
    Deletes a named funnel definition.
    .DESCRIPTION
    Removes a funnel JSON file from the user funnels directory ($HOME/.buckets-system/funnels/)
    and clears it from the session cache. Built-in funnels shipped with the module cannot be
    removed unless a user override with the same name exists.
    .PARAMETER Name
    Name of the funnel to remove.
    .PARAMETER Quiet
    Suppress success output.
    .EXAMPLE
    Remove-Funnel -Name admins
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$Quiet
    )

    $userDir = Join-Path (Get-BucketsSystemPath) "funnels"
    $userFile = Join-Path $userDir "$Name.json"
    $builtinFile = Join-Path $script:BuiltinFunnelsDir "$Name.json"

    if (-not (Test-Path $userFile)) {
        if (Test-Path $builtinFile) {
            throw "Funnel '$Name' is a built-in funnel and cannot be removed. Create a user funnel with the same name to override it."
        }
        throw "Funnel '$Name' not found."
    }

    if ($PSCmdlet.ShouldProcess("funnel '$Name'", "Remove-Funnel")) {
        [System.IO.File]::Delete($userFile)
        $script:FunnelCache.Remove($Name)
        if (-not $Quiet) {
            Write-Host "$Name" -NoNewline -ForegroundColor $script:CPath
            Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
            Write-Host "funnel removed" -ForegroundColor $script:CNum
        }
    }
}

function Set-BucketRoot {
    <#
    .SYNOPSIS
    Change the default bucket storage directory for the current session.
    .DESCRIPTION
    Overrides the default $HOME/.buckets path. Persists only for the current session.
    For persistent overrides, set $env:BUCKETS_ROOT in your profile.
    Automatically updates the 'buckets:' PSDrive to point to the new location.
    .PARAMETER Path
    The directory to use as the new bucket root. Created if it doesn't exist.
    .EXAMPLE
    Set-BucketRoot /data/my-buckets
    .EXAMPLE
    Set-BucketRoot $env:HOME/.config/buckets
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)][string]$Path)

    $resolved = Resolve-SafePath $Path
    if (-not (Test-Path $resolved)) { New-Item -ItemType Directory -Path $resolved -Force | Out-Null }
    $script:BucketRoot = $resolved
    & $script:ClearCache
    Write-Verbose "Bucket root set to: $resolved"
    Sync-BucketDrive
}

function Get-BucketRoot {
    <#
    .SYNOPSIS
    Returns the current default bucket storage directory.
    .DESCRIPTION
    Returns the active bucket root in priority order:
    1. Session override (Set-BucketRoot)
    2. Environment variable ($env:BUCKETS_ROOT)
    3. Home directory fallback ($HOME/.buckets)
    .EXAMPLE
    Get-BucketRoot
    #>
    [CmdletBinding()]
    param()
    return Get-DefaultPath
}

# --- PSDrive integration ---

function Sync-BucketDrive {
    <#
    .SYNOPSIS
    Creates or updates the 'buckets:' PSDrive to point to the current bucket root.
    .DESCRIPTION
    Automatically called on module import and by Set-BucketRoot.
    Can also be called manually to refresh after changing $env:BUCKETS_ROOT.
    .EXAMPLE
    Sync-BucketDrive
    .EXAMPLE
    $env:BUCKETS_ROOT = "/data/buckets"
    Sync-BucketDrive
    #>
    [CmdletBinding()]
    param()

    $root = Get-DefaultPath
    $driveName = 'buckets'
    $existing = Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue
    if ($existing) { Remove-PSDrive -Name $driveName -Force -ErrorAction SilentlyContinue }
    try {
        Write-Verbose "Creating PSDrive '$driveName' -> $root"
        New-PSDrive -Name $driveName -PSProvider Buckets -Root $root -Scope Global | Out-Null
    }
    catch { Write-Warning "Failed to create PSDrive '$driveName': $_" }
}

# --- Module lifecycle ---

$moduleInfo = $MyInvocation.MyCommand.ScriptBlock.Module
$moduleInfo.OnRemove = { Remove-PSDrive -Name buckets -Force -ErrorAction SilentlyContinue }

# Map PSDrive on module import
Sync-BucketDrive

# --- Aliases ---

Set-Alias -Name fill -Value New-BucketObject
Set-Alias -Name scoop -Value Get-BucketObject
Set-Alias -Name spill -Value Remove-BucketObject
Set-Alias -Name dip -Value Get-Bucket
Set-Alias -Name drain -Value Remove-Bucket
Set-Alias -Name ls -Value Get-ChildItem -Scope Global -Force

# --- Argument completers ---

$script:CompleterBlock = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $path = if ($fakeBoundParameters.ContainsKey('Path')) { $fakeBoundParameters['Path'] } else { Get-DefaultPath }
    if (-not [System.IO.Directory]::Exists($path)) { return }

    function Find-BucketsForCompletion {
        param([string]$Dir, [string]$Root, [string]$Filter)
        $di = [System.IO.DirectoryInfo]::new($Dir)
        $hasFiles = $di.GetFiles("*.dat").Length -gt 0 -or $di.GetFiles("*.json").Length -gt 0
        $relName = ""
        if ($Dir -ne $Root) {
            $relName = $Dir.Substring($Root.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
        }
        if ($hasFiles) {
            if ($Filter -eq "*" -or $relName -like "$Filter*" -or ($relName -contains $Filter)) {
                $relName
            }
        }
        foreach ($subDir in $di.GetDirectories()) {
            if ($subDir.Name -eq ".buckets") { continue }
            Find-BucketsForCompletion -Dir $subDir.FullName -Root $Root -Filter $Filter
        }
    }

    $filter = if ($wordToComplete) { $wordToComplete } else { "*" }
    Find-BucketsForCompletion -Dir $path -Root $path -Filter $filter | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

$script:KeyCompleterBlock = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $bucket = $fakeBoundParameters['Bucket']
    if (-not $bucket) { return }
    $path = if ($fakeBoundParameters.ContainsKey('Path')) { $fakeBoundParameters['Path'] } else { Get-DefaultPath }
    $bucketPath = Join-Path $path $bucket
    if (-not [System.IO.Directory]::Exists($bucketPath)) { return }
    $di = [System.IO.DirectoryInfo]::new($bucketPath)
    $files = $di.GetFiles("$wordToComplete*.dat") + $di.GetFiles("$wordToComplete*.json")
    $files | ForEach-Object {
        $key = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        [System.Management.Automation.CompletionResult]::new($key, $key, 'ParameterValue', "$($_.Extension.TrimStart('.')) key")
    }
}

@('New-BucketObject', 'Get-BucketObject', 'Set-BucketObject', 'Remove-BucketObject',
  'Get-BucketStats', 'Remove-Bucket', 'Copy-BucketObject', 'Rename-BucketObject',
  'Move-BucketObject', 'Export-Bucket', 'Import-Bucket', 'fill', 'spill') | ForEach-Object {
    Register-ArgumentCompleter -CommandName $_ -ParameterName Bucket -ScriptBlock $script:CompleterBlock
}

Register-ArgumentCompleter -CommandName Copy-BucketObject -ParameterName DestinationBucket -ScriptBlock $script:CompleterBlock
Register-ArgumentCompleter -CommandName Move-BucketObject -ParameterName DestinationBucket -ScriptBlock $script:CompleterBlock

@('Get-Bucket', 'dip') | ForEach-Object {
    Register-ArgumentCompleter -CommandName $_ -ParameterName Name -ScriptBlock $script:CompleterBlock
}

@('Get-BucketObject', 'Set-BucketObject', 'Remove-BucketObject',
  'Copy-BucketObject', 'Rename-BucketObject', 'Move-BucketObject', 'spill') | ForEach-Object {
    Register-ArgumentCompleter -CommandName $_ -ParameterName Key -ScriptBlock $script:KeyCompleterBlock
}

$BucketsPathCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $word = $wordToComplete -replace '"$', ''
    if (-not $word.StartsWith('buckets:', [StringComparison]::OrdinalIgnoreCase)) { return }
    $lastSlash = $word.LastIndexOf('\')
    if ($lastSlash -lt 0) { $lastSlash = $word.LastIndexOf('/') }
    if ($lastSlash -lt 0) {
        $dir = 'buckets:\'
        $filter = $word.Substring($word.IndexOf(':') + 1).TrimStart('\', '/')
    } else {
        $dir = $word.Substring(0, $lastSlash + 1)
        $filter = $word.Substring($lastSlash + 1)
    }
    if (-not $dir.EndsWith('\')) { $dir = $dir + '\' }
    try {
        $items = Get-ChildItem -Path $dir -ErrorAction Stop
        foreach ($item in $items) {
            $name = $item.Name
            if ($filter -and -not $name.StartsWith($filter, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $isContainer = $item.PSIsContainer
            $completionText = $dir + $name
            $resultType = if ($isContainer) { 'ProviderContainer' } else { 'ProviderItem' }
            $toolTip = if ($isContainer) { "$name (bucket)" } else { "$name (object)" }
            [System.Management.Automation.CompletionResult]::new($completionText, $name, $resultType, $toolTip)
        }
    } catch {}
}

$script:FunnelCompleterBlock = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $seen = @{}

    $userDir = Join-Path (Get-BucketsSystemPath) "funnels"
    if (Test-Path $userDir) {
        [System.IO.DirectoryInfo]::new($userDir).GetFiles("$wordToComplete*.json") | ForEach-Object {
            $fName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            $seen[$fName] = $true
            [System.Management.Automation.CompletionResult]::new($fName, $fName, 'ParameterValue', "funnel: $fName")
        }
    }

    if (Test-Path $script:BuiltinFunnelsDir) {
        [System.IO.DirectoryInfo]::new($script:BuiltinFunnelsDir).GetFiles("$wordToComplete*.json") | ForEach-Object {
            $fName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            if (-not $seen.ContainsKey($fName)) {
                [System.Management.Automation.CompletionResult]::new($fName, $fName, 'ParameterValue', "funnel: $fName")
            }
        }
    }
}

@('New-BucketObject', 'Get-BucketObject', 'fill', 'scoop') | ForEach-Object {
    Register-ArgumentCompleter -CommandName $_ -ParameterName Funnel -ScriptBlock $script:FunnelCompleterBlock
}

$nativeCommands = @(
    'Get-ChildItem', 'Get-Item', 'Remove-Item', 'Copy-Item', 'Move-Item',
    'Resolve-Path', 'Test-Path', 'Set-Location'
)
foreach ($cmd in $nativeCommands) {
    Register-ArgumentCompleter -CommandName $cmd -ParameterName Path -ScriptBlock $BucketsPathCompleter
    Register-ArgumentCompleter -CommandName $cmd -ParameterName LiteralPath -ScriptBlock $BucketsPathCompleter
}

# --- Exports ---

Export-ModuleMember -Function @(
    'New-BucketObject', 'Get-BucketObject', 'Set-BucketObject',
    'Remove-BucketObject', 'Get-Bucket', 'Get-BucketStats',
    'Get-BucketKeys', 'Get-BucketObjectStats', 'Remove-Bucket', 'Copy-BucketObject',
    'Rename-BucketObject', 'Move-BucketObject', 'Export-Bucket',
    'Import-Bucket', 'Set-BucketRoot', 'Get-BucketRoot', 'Sync-BucketDrive',
    'New-Funnel', 'Get-Funnel', 'Set-Funnel', 'Remove-Funnel'
) -Alias 'fill', 'scoop', 'spill', 'dip', 'drain'
