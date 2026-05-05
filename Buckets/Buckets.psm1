<#
.SYNOPSIS
    A PowerShell module for file-based PSObject storage using directory-backed buckets.
.DESCRIPTION
    Buckets provides a simple way to store, retrieve, and manage PowerShell objects
    in directory-based collections called "buckets". Objects are automatically serialized
    to binary (default) or JSON format, with auto-fallback to binary when JSON depth
    limits are exceeded.
#>

$script:DefaultPath = Join-Path $PWD.Path ".buckets"

function Get-BucketPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Path = $script:DefaultPath
    )

    return Join-Path $Path $Name
}

function Ensure-BucketExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Path = $script:DefaultPath
    )

    $bucketPath = Get-BucketPath -Name $Name -Path $Path
    if (-not (Test-Path $bucketPath)) {
        $null = New-Item -Path $bucketPath -ItemType Directory -Force
    }
    return $bucketPath
}

function Test-BucketSecretSupport {
    [CmdletBinding()]
    param(
        [string]$Vault,
        [string]$Operation
    )

    $requiredCommands = @("Get-SecretInfo", "Get-Secret", "Set-Secret", "Remove-Secret", "Get-SecretVault")
    $missingCommands = @()
    foreach ($commandName in $requiredCommands) {
        if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
            $missingCommands += $commandName
        }
    }

    if ($missingCommands.Count -gt 0) {
        throw "Secure bucket operation '$Operation' requires Microsoft.PowerShell.SecretManagement and Microsoft.PowerShell.SecretStore. Missing command(s): $($missingCommands -join ', ')"
    }

    if (-not [string]::IsNullOrWhiteSpace($Vault)) {
        try {
            Get-SecretVault -Name $Vault -ErrorAction Stop | Out-Null
        }
        catch {
            throw "Vault '$Vault' is not available: $($_.Exception.Message)"
        }
    }
}

function Convert-BucketSecureStringToPlainText {
    param(
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$SecureString
    )

    $bstr = [IntPtr]::Zero
    try {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Convert-BucketPasswordToSecureString {
    param(
        [AllowNull()]
        [string]$Pass
    )

    if ([string]::IsNullOrEmpty($Pass)) {
        return Read-Host -Prompt "Enter vault password" -AsSecureString
    }

    return ConvertTo-SecureString -String $Pass -AsPlainText -Force
}

function Get-BucketVaultNames {
    Test-BucketSecretSupport -Operation "vault discovery"
    return @(Get-SecretVault -ErrorAction Stop | ForEach-Object { $_.Name })
}

function Get-BucketProjectVaultBaseName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedPath = $Path
    try {
        $resolvedPath = (Resolve-Path -Path $Path -ErrorAction Stop).Path
    }
    catch {
        $resolvedPath = $Path
    }

    $projectRoot = Split-Path -Path $resolvedPath -Parent
    $projectName = Split-Path -Path $projectRoot -Leaf
    if ([string]::IsNullOrWhiteSpace($projectName)) {
        $projectName = "project"
    }

    $safeProjectName = ($projectName -replace '[^a-zA-Z0-9_-]', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safeProjectName)) {
        $safeProjectName = "project"
    }

    return "buckets-$($safeProjectName.ToLowerInvariant())"
}

function Get-BucketUniqueVaultName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseName,

        [Parameter(Mandatory = $true)]
        [string[]]$ExistingVaultNames
    )

    $candidate = $BaseName
    $index = 2
    while ($ExistingVaultNames -contains $candidate) {
        $candidate = "$BaseName-$index"
        $index++
    }

    return $candidate
}

function New-BucketVault {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultName
    )

    Register-SecretVault -Name $VaultName -ModuleName "Microsoft.PowerShell.SecretStore" -ErrorAction Stop | Out-Null
    return $VaultName
}

function Read-BucketVaultChoice {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ExistingVaultNames,

        [Parameter(Mandatory = $true)]
        [string]$SuggestedVaultName
    )

    if ($ExistingVaultNames.Count -eq 0) {
        $createdVault = New-BucketVault -VaultName $SuggestedVaultName
        return [PSCustomObject]@{
            VaultName = $createdVault
            IsNew     = $true
        }
    }

    Write-Host "Select secure vault option:"
    Write-Host "  [1] Create new vault '$SuggestedVaultName'"
    Write-Host "  [2] Use existing vault"
    $mode = Read-Host "Choice"

    if ($mode -eq "1") {
        $createdVault = New-BucketVault -VaultName $SuggestedVaultName
        return [PSCustomObject]@{
            VaultName = $createdVault
            IsNew     = $true
        }
    }

    if ($mode -eq "2") {
        for ($i = 0; $i -lt $ExistingVaultNames.Count; $i++) {
            Write-Host "  [$($i + 1)] $($ExistingVaultNames[$i])"
        }

        $selected = Read-Host "Select existing vault index"
        $selectedIndex = 0
        if (-not [int]::TryParse($selected, [ref]$selectedIndex)) {
            throw "Invalid vault selection '$selected'."
        }

        if ($selectedIndex -lt 1 -or $selectedIndex -gt $ExistingVaultNames.Count) {
            throw "Vault selection '$selectedIndex' is out of range."
        }

        return [PSCustomObject]@{
            VaultName = $ExistingVaultNames[$selectedIndex - 1]
            IsNew     = $false
        }
    }

    throw "Invalid choice '$mode'. Enter 1 or 2."
}

function Resolve-BucketSecureVault {
    param(
        [string]$Vault,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $existingVaultNames = @(Get-BucketVaultNames | Sort-Object)
    if (-not [string]::IsNullOrWhiteSpace($Vault)) {
        if ($existingVaultNames -notcontains $Vault) {
            throw "Vault '$Vault' is not available."
        }

        return [PSCustomObject]@{
            VaultName = $Vault
            IsNew     = $false
        }
    }

    $baseName = Get-BucketProjectVaultBaseName -Path $Path
    $suggestedVaultName = Get-BucketUniqueVaultName -BaseName $baseName -ExistingVaultNames $existingVaultNames
    return Read-BucketVaultChoice -ExistingVaultNames $existingVaultNames -SuggestedVaultName $suggestedVaultName
}

function Initialize-BucketSecretStoreSession {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$PassProvided,

        [AllowNull()]
        [string]$Pass,

        [Parameter(Mandatory = $true)]
        [bool]$IsNewVault
    )

    if (-not $PassProvided) {
        return
    }

    $requiredCommands = @("Unlock-SecretStore")
    if ($IsNewVault) {
        $requiredCommands += @("Get-SecretStoreConfiguration", "Set-SecretStoreConfiguration")
    }

    $missingCommands = @()
    foreach ($commandName in $requiredCommands) {
        if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
            $missingCommands += $commandName
        }
    }
    if ($missingCommands.Count -gt 0) {
        throw "Password handling requires command(s): $($missingCommands -join ', ')"
    }

    $securePassword = Convert-BucketPasswordToSecureString -Pass $Pass

    if ($IsNewVault) {
        try {
            $storeConfiguration = Get-SecretStoreConfiguration -ErrorAction Stop
            if ($storeConfiguration.Authentication -eq "None") {
                Set-SecretStoreConfiguration -Authentication Password -Password $securePassword -Confirm:$false -ErrorAction Stop | Out-Null
            }
        }
        catch {
            throw "Failed to configure SecretStore password: $($_.Exception.Message)"
        }
    }

    try {
        Unlock-SecretStore -Password $securePassword -ErrorAction Stop | Out-Null
    }
    catch {
        throw "Failed to unlock SecretStore: $($_.Exception.Message)"
    }
}

function Test-BucketCanAutoQuerySecrets {
    $configCommand = Get-Command -Name "Get-SecretStoreConfiguration" -ErrorAction SilentlyContinue
    if (-not $configCommand) {
        Import-Module -Name "Microsoft.PowerShell.SecretStore" -ErrorAction SilentlyContinue | Out-Null
        $configCommand = Get-Command -Name "Get-SecretStoreConfiguration" -ErrorAction SilentlyContinue
    }

    if (-not $configCommand) {
        return $false
    }

    try {
        $config = Get-SecretStoreConfiguration -ErrorAction Stop
        if ($config.Authentication -eq "Password" -and $config.Interaction -eq "Prompt") {
            return $false
        }
    }
    catch {
        return $true
    }

    return $true
}

function Get-BucketSecretName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $safeBucket = $Bucket -replace '[^a-zA-Z0-9_-]', '_'
    $safeKey = $Key -replace '[^a-zA-Z0-9_-]', '_'
    return "buckets__$safeBucket__$safeKey"
}

function Convert-BucketObjectToSerializedContent {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$InputObject,

        [Parameter(Mandatory = $true)]
        [bool]$AsJson,

        [Parameter(Mandatory = $true)]
        [int]$Depth,

        [Parameter(Mandatory = $true)]
        [int]$BinaryDepth,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($AsJson) {
        $warnVar = $null
        $json = ConvertTo-Json -InputObject $InputObject -Depth $Depth -Compress -WarningAction SilentlyContinue -WarningVariable warnVar
        if ($warnVar -and $warnVar[0] -like "*truncated*") {
            Write-Warning "Object '$Key' exceeds JSON depth $Depth, saved as binary (.dat)"
        }
        else {
            return [PSCustomObject]@{
                Format  = "json"
                Content = $json
            }
        }
    }

    try {
        $bytes = [System.Management.Automation.PSSerializer]::Serialize($InputObject, $BinaryDepth)
        $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bytes))
        return [PSCustomObject]@{
            Format  = "dat"
            Content = $encoded
        }
    }
    catch {
        throw "Failed to serialize object '$Key': $($_.Exception.Message)"
    }
}

function Convert-BucketSerializedContentToObject {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Format,

        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($Format -eq "dat") {
        try {
            $bytes = [System.Convert]::FromBase64String($Content)
            $xml = [System.Text.Encoding]::UTF8.GetString($bytes)
            return [System.Management.Automation.PSSerializer]::Deserialize($xml)
        }
        catch {
            throw "Failed to deserialize secure object '$Key' as binary: $($_.Exception.Message)"
        }
    }

    try {
        return $Content | ConvertFrom-Json
    }
    catch {
        throw "Failed to deserialize secure object '$Key' as JSON: $($_.Exception.Message)"
    }
}

function Get-BucketSecretInfo {
    param(
        [string]$Bucket,
        [string]$Key,
        [string]$Vault
    )

    Test-BucketSecretSupport -Vault $Vault -Operation "query"

    $queryParams = @{}
    if (-not [string]::IsNullOrWhiteSpace($Vault)) {
        $queryParams.Vault = $Vault
    }

    $infos = Get-SecretInfo @queryParams -ErrorAction Stop | Where-Object {
        $metadata = $_.Metadata
        $null -ne $metadata -and
        $metadata.Source -eq "Buckets" -and
        ([string]::IsNullOrWhiteSpace($Bucket) -or $metadata.Bucket -eq $Bucket) -and
        ([string]::IsNullOrWhiteSpace($Key) -or $metadata.Key -eq $Key)
    }

    return @($infos)
}

function Set-BucketSecureObject {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [PSObject]$InputObject,

        [Parameter(Mandatory = $true)]
        [bool]$AsJson,

        [Parameter(Mandatory = $true)]
        [int]$Depth,

        [Parameter(Mandatory = $true)]
        [int]$BinaryDepth,

        [string]$Vault
    )

    Test-BucketSecretSupport -Vault $Vault -Operation "write"

    $serialized = Convert-BucketObjectToSerializedContent -InputObject $InputObject -AsJson $AsJson -Depth $Depth -BinaryDepth $BinaryDepth -Key $Key
    $secretName = Get-BucketSecretName -Bucket $Bucket -Key $Key

    $metadata = @{
        Source    = "Buckets"
        Bucket    = $Bucket
        Key       = $Key
        Format    = $serialized.Format
        CreatedAt = [DateTime]::UtcNow.ToString("o")
    }

    $setParams = @{
        Name       = $secretName
        Secret     = $serialized.Content
        Metadata   = $metadata
        ErrorAction = "Stop"
    }
    if (-not [string]::IsNullOrWhiteSpace($Vault)) {
        $setParams.Vault = $Vault
    }

    Set-Secret @setParams

    $savedInfo = Get-BucketSecretInfo -Bucket $Bucket -Key $Key -Vault $Vault | Where-Object { $_.Name -eq $secretName } | Select-Object -First 1
    $vaultName = if ($savedInfo) { $savedInfo.VaultName } elseif (-not [string]::IsNullOrWhiteSpace($Vault)) { $Vault } else { "default" }

    return [PSCustomObject]@{
        Name      = $secretName
        VaultName = $vaultName
        Format    = $serialized.Format
    }
}

function Get-BucketSecureObjectFromInfo {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$SecretInfo
    )

    Test-BucketSecretSupport -Vault $SecretInfo.VaultName -Operation "read"

    $getParams = @{
        Name       = $SecretInfo.Name
        Vault      = $SecretInfo.VaultName
        ErrorAction = "Stop"
    }
    $secretValue = Get-Secret @getParams

    if ($secretValue -is [Security.SecureString]) {
        $secretValue = Convert-BucketSecureStringToPlainText -SecureString $secretValue
    }

    if ($secretValue -isnot [string]) {
        throw "Secure object '$($SecretInfo.Metadata.Key)' has unsupported payload type '$($secretValue.GetType().FullName)'."
    }

    return Convert-BucketSerializedContentToObject -Format $SecretInfo.Metadata.Format -Content $secretValue -Key $SecretInfo.Metadata.Key
}

function Remove-BucketSecretInfos {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$SecretInfos
    )

    foreach ($secretInfo in $SecretInfos) {
        Remove-Secret -Name $secretInfo.Name -Vault $secretInfo.VaultName -ErrorAction Stop
    }
}

function Test-BucketObjectFilterMatch {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$InputObject,

        [hashtable]$Match,

        [scriptblock]$Filter
    )

    if ($Match) {
        foreach ($kvp in $Match.GetEnumerator()) {
            if ($InputObject.$($kvp.Name) -ne $kvp.Value) {
                return $false
            }
        }
    }

    if ($Filter) {
        if ($null -eq ($InputObject | Where-Object $Filter)) {
            return $false
        }
    }

    return $true
}

function Save-BucketObject {
    <#
    .SYNOPSIS
    Saves a PSObject to a bucket. Creates the bucket if it doesn't exist.
    .DESCRIPTION
    Serializes one or more PowerShell objects and stores them in a bucket directory.
    Arrays are stored as individual files. By default objects are serialized to binary
    (.dat) using PSSerializer. Use -AsJson for JSON format. If JSON serialization
    exceeds the depth limit, the object automatically falls back to binary format.
    .PARAMETER InputObject
    The object(s) to store. Accepts pipeline input. Arrays are stored as individual files.
    .PARAMETER Bucket
    Name of the bucket to save to. Creates the bucket if it doesn't exist. Default: "default".
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Key
    Property name whose value becomes the filename. Special characters (/, :, *, ?, ", <, >, |, ., []) are sanitized to underscores. If omitted, a GUID is used.
    .PARAMETER Depth
    Maximum depth for JSON serialization. Default: 20.
    .PARAMETER BinaryDepth
    Maximum depth for binary (PSSerializer) serialization. Default: 2.
    .PARAMETER AsTimestamp
    Use a timestamp-based filename (yyyyMMddHHmmssfff_index) instead of a GUID.
    .PARAMETER AsJson
    Store objects as JSON (.json) instead of binary (.dat).
    .PARAMETER Secure
    Store objects in SecretStore instead of writing files. Requires SecretManagement.
    .PARAMETER Vault
    Secret vault name to use for secure objects. If omitted, prompts to create or choose a vault.
    .PARAMETER Pass
    Optional secret store password. If passed with no value, prompts interactively.
    .OUTPUTS
    PSCustomObject with Bucket, Key, and FilePath properties.
    .EXAMPLE
    Save-BucketObject -InputObject @{ Name = "Alice"; Age = 30 } -Key Name
    .EXAMPLE
    $users | Save-BucketObject -Bucket users -Key Email -AsJson
    .EXAMPLE
    Get-Process | Save-BucketObject -Bucket processes -AsTimestamp
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]$InputObject,

        [string]$Bucket = "default",

        [string]$Path = $script:DefaultPath,

        [string]$Key,

        [int]$Depth = 20,

        [int]$BinaryDepth = 2,

        [switch]$AsTimestamp,

        [switch]$AsJson,

        [switch]$Secure,

        [string]$Vault,

        [AllowEmptyString()]
        [string]$Pass
    )

    begin {
        $bucketPath = Ensure-BucketExists -Name $Bucket -Path $Path
        $extension = if ($AsJson) { ".json" } else { ".dat" }
        $resolvedVault = $Vault
        $resolvedVaultInitialized = $false
        $passProvided = $PSBoundParameters.ContainsKey("Pass")
    }

    process {
        $isCollection = $InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string] -and $InputObject -isnot [hashtable] -and $InputObject -isnot [System.Collections.IDictionary]

        if ($isCollection) {
            $items = $InputObject
        }
        else {
            $items = [System.Collections.ArrayList]::new()
            $null = $items.Add($InputObject)
        }

        $index = 0
        foreach ($item in $items) {
            if (-not [string]::IsNullOrWhiteSpace($Key)) {
                $keyValue = $item.$Key
                if ($null -eq $keyValue) {
                    Write-Warning "Property '$Key' not found on object, skipping"
                    $index++
                    continue
                }
                $safeKey = $keyValue -replace '[\\/:\*\?"<>\|\.\[\]]', '_'
                $filename = "${safeKey}${extension}"
            }
            elseif ($AsTimestamp) {
                $filename = "$(Get-Date -Format 'yyyyMMddHHmmssfff')_${index}${extension}"
            }
            else {
                $filename = "$([Guid]::NewGuid())${extension}"
            }

            $filePath = Join-Path $bucketPath $filename
            $resolvedKey = [System.IO.Path]::GetFileNameWithoutExtension($filename)

            if ($Secure) {
                if (-not $resolvedVaultInitialized) {
                    $vaultResolution = Resolve-BucketSecureVault -Vault $Vault -Path $Path
                    $resolvedVault = $vaultResolution.VaultName
                    Initialize-BucketSecretStoreSession -PassProvided $passProvided -Pass $Pass -IsNewVault $vaultResolution.IsNew
                    $resolvedVaultInitialized = $true
                }

                try {
                    $savedSecret = Set-BucketSecureObject -Bucket $Bucket -Key $resolvedKey -InputObject $item -AsJson $AsJson.IsPresent -Depth $Depth -BinaryDepth $BinaryDepth -Vault $resolvedVault
                }
                catch {
                    Write-Warning "Failed to save secure object '$resolvedKey': $($_.Exception.Message)"
                    $index++
                    continue
                }

                [PSCustomObject]@{
                    Bucket   = $Bucket
                    Key      = $resolvedKey
                    FilePath = "secret://$($savedSecret.VaultName)/$($savedSecret.Name)"
                }

                $index++
                continue
            }

            if ($AsJson) {
                $warnVar = $null
                $json = ConvertTo-Json -InputObject $item -Depth $Depth -Compress -WarningAction SilentlyContinue -WarningVariable warnVar
            if ($warnVar -and $warnVar[0] -like "*truncated*") {
                    try {
                        $bytes = [System.Management.Automation.PSSerializer]::Serialize($item, $BinaryDepth)
                        $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bytes))
                        $filePath = [System.IO.Path]::ChangeExtension($filePath, ".dat")
                        [System.IO.File]::WriteAllText($filePath, $encoded, [System.Text.Encoding]::UTF8)
                        Write-Warning "Object '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' exceeds JSON depth $Depth, saved as binary (.dat)"
                    }
                    catch {
                        Write-Warning "Failed to serialize object '$([System.IO.Path]::GetFileNameWithoutExtension($filename))' as binary: $_"
                        $index++
                        continue
                    }
                }
                else {
                    [System.IO.File]::WriteAllText($filePath, $json, [System.Text.Encoding]::UTF8)
                }
            }
            else {
                try {
                    $bytes = [System.Management.Automation.PSSerializer]::Serialize($item, $BinaryDepth)
                    $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bytes))
                    [System.IO.File]::WriteAllText($filePath, $encoded, [System.Text.Encoding]::UTF8)
                }
                catch {
                    Write-Warning "Failed to serialize object with key '$([System.IO.Path]::GetFileNameWithoutExtension($filename))': $_"
                    $index++
                    continue
                }
            }

            [PSCustomObject]@{
                Bucket   = $Bucket
                Key      = $resolvedKey
                FilePath = $filePath
            }

            $index++
        }
    }
}

function Read-BucketFile {
    param(
        [System.IO.FileInfo]$File
    )

    $extension = $File.Extension
    $content = [System.IO.File]::ReadAllText($File.FullName, [System.Text.Encoding]::UTF8)

    if ($extension -eq ".dat") {
        $bytes = [System.Convert]::FromBase64String($content)
        $xml = [System.Text.Encoding]::UTF8.GetString($bytes)
        return [System.Management.Automation.PSSerializer]::Deserialize($xml)
    }
    else {
        return $content | ConvertFrom-Json
    }
}

function Get-ObjectFiles {
    param(
        [string]$BucketPath,

        [string]$Key
    )

    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $jsonFile = Get-ChildItem -Path $BucketPath -Filter "$Key.json" -ErrorAction SilentlyContinue
        if ($jsonFile) { return $jsonFile }
        return Get-ChildItem -Path $BucketPath -Filter "$Key.dat" -ErrorAction SilentlyContinue
    }
    else {
        $jsonFiles = Get-ChildItem -Path $BucketPath -Filter "*.json" -ErrorAction SilentlyContinue
        $datFiles = Get-ChildItem -Path $BucketPath -Filter "*.dat" -ErrorAction SilentlyContinue
        return @($jsonFiles) + @($datFiles)
    }
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
    Bucket name(s) to search. If omitted, searches all buckets under -Path.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Key
    Specific object key to retrieve. Looks for both .json and .dat files.
    .PARAMETER Match
    Hashtable of property-value pairs for exact-match filtering. All pairs must match.
    .PARAMETER Filter
    ScriptBlock for custom filtering. Use $_ to reference object properties (e.g., { $_.Age -gt 30 }).
    .PARAMETER IncludeSecure
    Include secure objects from SecretStore in addition to file-backed objects.
    .OUTPUTS
    Deserialized PSObjects with _BucketName, _BucketKey, and _BucketFile metadata.
    .EXAMPLE
    Get-BucketObject -Bucket users -Match @{ Role = "admin" }
    .EXAMPLE
    Get-BucketObject -Filter { $_.Status -eq "shipped" -and $_.Shipping.Method -eq "Express" }
    .EXAMPLE
    Get-BucketObject -Bucket users, orders
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 1)]
        [string[]]$Bucket,

        [string]$Path = $script:DefaultPath,

        [Parameter(Position = 0)]
        [string]$Key,

        [hashtable]$Match,

        [scriptblock]$Filter,

        [switch]$IncludeSecure
    )

    $bucketPaths = @()
    if ($Bucket -and $Bucket.Count -gt 0) {
        foreach ($b in $Bucket) {
            if ($b -match '[\*\?]') {
                $matched = Get-Bucket -Path $Path | Where-Object { $_.Name -like $b }
                $bucketPaths += $matched | ForEach-Object { $_.Path }
            }
            else {
                $bucketPaths += Get-BucketPath -Name $b -Path $Path
            }
        }
    }
    else {
        $bucketPaths += Get-Bucket -Path $Path | ForEach-Object { $_.Path }
    }

    $canAutoQuerySecrets = $IncludeSecure.IsPresent -and (Test-BucketCanAutoQuerySecrets)
    foreach ($bucketPath in $bucketPaths) {
        $bucketName = Split-Path $bucketPath -Leaf

        if (Test-Path $bucketPath) {
            $files = Get-ObjectFiles -BucketPath $bucketPath -Key $Key
            foreach ($file in $files) {
                $obj = Read-BucketFile -File $file
                if (-not (Test-BucketObjectFilterMatch -InputObject $obj -Match $Match -Filter $Filter)) { continue }

                $obj | Add-Member -NotePropertyName "_BucketName" -NotePropertyValue $bucketName -Force
                $obj | Add-Member -NotePropertyName "_BucketKey" -NotePropertyValue ([System.IO.Path]::GetFileNameWithoutExtension($file.Name)) -Force
                $obj | Add-Member -NotePropertyName "_BucketFile" -NotePropertyValue $file.FullName -Force
                Write-Output $obj
            }
        }

        $secureInfos = @()
        if ($canAutoQuerySecrets) {
            try {
                $secureInfos = Get-BucketSecretInfo -Bucket $bucketName -Key $Key
            }
            catch {
                $secureInfos = @()
            }
        }

        foreach ($secureInfo in $secureInfos) {
            $obj = Get-BucketSecureObjectFromInfo -SecretInfo $secureInfo
            if (-not (Test-BucketObjectFilterMatch -InputObject $obj -Match $Match -Filter $Filter)) { continue }

            $obj | Add-Member -NotePropertyName "_BucketName" -NotePropertyValue $bucketName -Force
            $obj | Add-Member -NotePropertyName "_BucketKey" -NotePropertyValue $secureInfo.Metadata.Key -Force
            $obj | Add-Member -NotePropertyName "_BucketFile" -NotePropertyValue "secret://$($secureInfo.VaultName)/$($secureInfo.Name)" -Force
            Write-Output $obj
        }
    }
}

function Update-BucketObject {
    <#
    .SYNOPSIS
    Updates an existing object in a bucket.
    .DESCRIPTION
    Replaces an existing object file with new data. Preserves the storage format (JSON or binary)
    of the existing file unless -AsJson forces a format change. If JSON serialization exceeds
    the depth limit, the object automatically falls back to binary format.
    .PARAMETER InputObject
    The updated object to store. Accepts pipeline input.
    .PARAMETER Bucket
    Name of the bucket containing the object.
    .PARAMETER Key
    Object key to update. Must exist in the bucket.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER IncludeSecure
    Include secure objects from SecretStore in statistics.
    .PARAMETER Depth
    Maximum depth for JSON serialization. Default: 20.
    .PARAMETER BinaryDepth
    Maximum depth for binary (PSSerializer) serialization. Default: 2.
    .PARAMETER AsJson
    Force JSON format for the updated file.
    .OUTPUTS
    PSCustomObject with Bucket, Key, and FilePath properties.
    .EXAMPLE
    Get-BucketObject -Bucket users -Key "Alice" | ForEach-Object { $_.Age = 31; $_ } | Update-BucketObject -Bucket users -Key "Alice"
    .EXAMPLE
    $user = Get-BucketObject -Bucket users -Key "Alice"
    $user.Email = "alice@new.com"
    Update-BucketObject -Bucket users -Key "Alice" -InputObject $user
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [string]$Path = $script:DefaultPath,

        [int]$Depth = 20,

        [int]$BinaryDepth = 2,

        [switch]$AsJson
    )

    begin {
        $bucketPath = Get-BucketPath -Name $Bucket -Path $Path
    }

    process {
        try {
            $secureInfos = Get-BucketSecretInfo -Bucket $Bucket -Key $Key
        }
        catch {
            $secureInfos = @()
        }

        if ($secureInfos.Count -gt 1) {
            throw "Multiple secure objects found for bucket '$Bucket' and key '$Key' across vaults. Remove duplicates before updating."
        }

        if ($secureInfos.Count -eq 1) {
            $existingSecure = $secureInfos[0]
            $useJsonForSecure = $AsJson.IsPresent -or $existingSecure.Metadata.Format -eq "json"
            $savedSecure = Set-BucketSecureObject -Bucket $Bucket -Key $Key -InputObject $InputObject -AsJson $useJsonForSecure -Depth $Depth -BinaryDepth $BinaryDepth -Vault $existingSecure.VaultName

            return [PSCustomObject]@{
                Bucket   = $Bucket
                Key      = $Key
                FilePath = "secret://$($savedSecure.VaultName)/$($savedSecure.Name)"
            }
        }

        if (-not (Test-Path $bucketPath)) {
            throw "Bucket '$Bucket' not found at '$bucketPath'"
        }

        $jsonPath = Join-Path $bucketPath "$Key.json"
        $datPath = Join-Path $bucketPath "$Key.dat"

        $filePath = if (Test-Path $jsonPath) { $jsonPath }
        elseif (Test-Path $datPath) { $datPath }
        else {
            throw "Object with key '$Key' not found in bucket '$Bucket'"
        }

        $useJson = $filePath -like "*.json" -or $AsJson

        if ($useJson) {
            $warnVar = $null
            $json = ConvertTo-Json -InputObject $InputObject -Depth $Depth -Compress -WarningAction SilentlyContinue -WarningVariable warnVar
            if ($warnVar -and $warnVar[0] -like "*truncated*") {
                try {
                    $bytes = [System.Management.Automation.PSSerializer]::Serialize($InputObject, $BinaryDepth)
                    $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bytes))
                    $filePath = [System.IO.Path]::ChangeExtension($filePath, ".dat")
                    [System.IO.File]::WriteAllText($filePath, $encoded, [System.Text.Encoding]::UTF8)
                    Write-Warning "Object '$Key' exceeds JSON depth $Depth, saved as binary (.dat)"
                }
                catch {
                    Write-Warning "Failed to serialize object '$Key' as binary: $_"
                    throw
                }
            }
            else {
                [System.IO.File]::WriteAllText($filePath, $json, [System.Text.Encoding]::UTF8)
            }
        }
        else {
            $bytes = [System.Management.Automation.PSSerializer]::Serialize($InputObject, $BinaryDepth)
            $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bytes))
            [System.IO.File]::WriteAllText($filePath, $encoded, [System.Text.Encoding]::UTF8)
        }

        return [PSCustomObject]@{
            Bucket   = $Bucket
            Key      = $Key
            FilePath = $filePath
        }
    }
}

function Remove-BucketObject {
    <#
    .SYNOPSIS
    Removes an object from a bucket.
    .DESCRIPTION
    Deletes a specific object file from a bucket directory. Use -Key to remove a single
    object or -All to clear the entire bucket.
    .PARAMETER Bucket
    Name of the bucket containing the object(s) to remove.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Key
    Object key to remove. Looks for both .json and .dat files.
    .PARAMETER All
    Remove all objects from the bucket.
    .EXAMPLE
    Remove-BucketObject -Bucket users -Key "Alice"
    .EXAMPLE
    Remove-BucketObject -Bucket temp -All
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [string]$Path = $script:DefaultPath,

        [string]$Key,

        [switch]$All
    )

    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path

    if (-not (Test-Path $bucketPath) -and -not $All -and [string]::IsNullOrWhiteSpace($Key)) {
        return
    }

    if ($All) {
        if (Test-Path $bucketPath) {
            Get-ChildItem -Path $bucketPath -Filter "*.json" -ErrorAction SilentlyContinue | Remove-Item -Force
            Get-ChildItem -Path $bucketPath -Filter "*.dat" -ErrorAction SilentlyContinue | Remove-Item -Force
        }

        try {
            $secureInfos = Get-BucketSecretInfo -Bucket $Bucket
            if ($secureInfos.Count -gt 0) {
                Remove-BucketSecretInfos -SecretInfos $secureInfos
            }
        }
        catch {
            Write-Warning "Failed to remove secure objects from bucket '$Bucket': $($_.Exception.Message)"
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Key)) {
        $removed = $false
        $jsonPath = Join-Path $bucketPath "$Key.json"
        $datPath = Join-Path $bucketPath "$Key.dat"
        if (Test-Path $jsonPath) {
            Remove-Item -Path $jsonPath -Force
            $removed = $true
        }
        elseif (Test-Path $datPath) {
            Remove-Item -Path $datPath -Force
            $removed = $true
        }

        try {
            $secureInfos = Get-BucketSecretInfo -Bucket $Bucket -Key $Key
            if ($secureInfos.Count -gt 0) {
                Remove-BucketSecretInfos -SecretInfos $secureInfos
                $removed = $true
            }
        }
        catch {
            Write-Warning "Failed to remove secure object with key '$Key' in bucket '$Bucket': $($_.Exception.Message)"
        }

        if (-not $removed) {
            Write-Warning "Object with key '$Key' not found in bucket '$Bucket'"
        }
    }
    else {
        throw "Specify either -Key or -All"
    }
}

function Get-Bucket {
    <#
    .SYNOPSIS
    Lists available buckets with object counts.
    .DESCRIPTION
    Scans the storage path for bucket directories and returns information about each,
    including name, path, and total object count (JSON + binary files).
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Name
    Filter buckets by name pattern (substring match).
    .OUTPUTS
    PSCustomObject with Name, Path, and ObjectCount properties.
    .EXAMPLE
    Get-Bucket
    .EXAMPLE
    Get-Bucket -Name "user"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name,

        [string]$Path = $script:DefaultPath
    )

    $directoryBuckets = @()
    if (Test-Path $Path) {
        $directoryBuckets = @(Get-ChildItem -Path $Path -Directory)
    }

    $bucketNames = @($directoryBuckets | ForEach-Object { $_.Name } | Sort-Object -Unique)

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $bucketNames = $bucketNames | Where-Object { $_ -like "*$Name*" }
    }

    foreach ($bucketName in $bucketNames) {
        $bucketPath = Get-BucketPath -Name $bucketName -Path $Path
        $jsonCount = if (Test-Path $bucketPath) { (Get-ChildItem -Path $bucketPath -Filter "*.json" -ErrorAction SilentlyContinue).Count } else { 0 }
        $datCount = if (Test-Path $bucketPath) { (Get-ChildItem -Path $bucketPath -Filter "*.dat" -ErrorAction SilentlyContinue).Count } else { 0 }
        $count = $jsonCount + $datCount

        [PSCustomObject]@{
            Name        = $bucketName
            Path        = $bucketPath
            ObjectCount = if ($count) { $count } else { 0 }
        }
    }
}

function Get-BucketStats {
    <#
    .SYNOPSIS
    Shows statistics for a bucket.
    .DESCRIPTION
    Returns object count, total storage size, and oldest/newest object timestamps
    for the specified bucket.
    .PARAMETER Bucket
    Name of the bucket to analyze.
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .OUTPUTS
    PSCustomObject with Name, Path, ObjectCount, TotalSize, OldestObject, and NewestObject properties.
    .EXAMPLE
    Get-BucketStats -Bucket users
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [string]$Path = $script:DefaultPath,

        [switch]$IncludeSecure
    )

    $bucketPath = Get-BucketPath -Name $Bucket -Path $Path

    $secureInfos = @()
    $canAutoQuerySecrets = $IncludeSecure.IsPresent -and (Test-BucketCanAutoQuerySecrets)
    if ($canAutoQuerySecrets) {
        try {
            $secureInfos = Get-BucketSecretInfo -Bucket $Bucket
        }
        catch {
            $secureInfos = @()
        }
    }

    if (-not (Test-Path $bucketPath) -and $secureInfos.Count -eq 0) {
        throw "Bucket '$Bucket' not found at '$bucketPath'"
    }

    $jsonFiles = if (Test-Path $bucketPath) { Get-ChildItem -Path $bucketPath -Filter "*.json" -ErrorAction SilentlyContinue } else { @() }
    $datFiles = if (Test-Path $bucketPath) { Get-ChildItem -Path $bucketPath -Filter "*.dat" -ErrorAction SilentlyContinue } else { @() }
    $files = @($jsonFiles) + @($datFiles)
    $fileObjects = $files | ForEach-Object { $_ }

    $fileSize = ($fileObjects | Measure-Object -Property Length -Sum).Sum
    $secureSize = 0
    $secureTimes = @()
    foreach ($secureInfo in $secureInfos) {
        try {
            $secretValue = Get-Secret -Name $secureInfo.Name -Vault $secureInfo.VaultName -ErrorAction Stop
            if ($secretValue -is [Security.SecureString]) {
                $secretValue = Convert-BucketSecureStringToPlainText -SecureString $secretValue
            }
            if ($secretValue -is [string]) {
                $secureSize += [System.Text.Encoding]::UTF8.GetByteCount($secretValue)
            }
        }
        catch {
            Write-Warning "Failed to read secure object '$($secureInfo.Metadata.Key)' for stats: $($_.Exception.Message)"
        }

        $createdAt = $null
        if ($secureInfo.Metadata.CreatedAt) {
            [DateTime]::TryParse($secureInfo.Metadata.CreatedAt, [ref]$createdAt) | Out-Null
        }
        if ($createdAt) {
            $secureTimes += $createdAt
        }
    }
    $totalSize = $fileSize + $secureSize

    $allTimes = @()
    $allTimes += @($fileObjects | ForEach-Object { $_.CreationTime })
    $allTimes += $secureTimes

    [PSCustomObject]@{
        Name         = $Bucket
        Path         = $bucketPath
        ObjectCount  = $fileObjects.Count + $secureInfos.Count
        TotalSize    = if ($totalSize) { "$([math]::Round($totalSize / 1KB, 2)) KB" } else { "0 KB" }
        OldestObject = if ($allTimes.Count -gt 0) { ($allTimes | Sort-Object | Select-Object -First 1) } else { $null }
        NewestObject = if ($allTimes.Count -gt 0) { ($allTimes | Sort-Object -Descending | Select-Object -First 1) } else { $null }
    }
}

function Remove-Bucket {
    <#
    .SYNOPSIS
    Removes one or more buckets and all their objects.
    .DESCRIPTION
    Deletes bucket directories and their contents. Supports exact names, multiple
    buckets, and wildcard patterns. Only removes directories containing .dat/.json
    files (or empty directories). Skips buckets with other file types. Prompts for
    confirmation unless -Force is used.
    .PARAMETER Bucket
    Bucket name(s) or wildcard patterns to remove. Supports glob-style wildcards (*, ?).
    .PARAMETER Path
    Root directory for bucket storage. Default: $PWD/.buckets.
    .PARAMETER Force
    Skip confirmation prompt.
    .PARAMETER WhatIf
    Preview which buckets would be removed without actually deleting them.
    .EXAMPLE
    Remove-Bucket -Bucket users
    .EXAMPLE
    Remove-Bucket -Bucket "temp*" -Force
    .EXAMPLE
    Remove-Bucket * -WhatIf
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Bucket,

        [string]$Path = $script:DefaultPath,

        [switch]$Force,

        [switch]$WhatIf
    )

    $allBuckets = Get-Bucket -Path $Path

    $matched = @()
    foreach ($pattern in $Bucket) {
        if ($pattern -match '[\*\?]') {
            $found = $allBuckets | Where-Object { $_.Name -like $pattern }
            if (-not $found) {
                Write-Warning "No buckets match pattern '$pattern'"
            }
            $matched += $found
        }
        elseif ($pattern -eq "*") {
            $matched += $allBuckets
        }
        else {
            $exact = $allBuckets | Where-Object { $_.Name -eq $pattern }
            if ($exact) {
                $matched += $exact
            }
            else {
                Write-Warning "Bucket '$pattern' not found at '$Path'"
            }
        }
    }

    if ($matched.Count -eq 0) { return }

    if (-not $Force -and -not $WhatIf) {
        Write-Host "The following bucket(s) will be removed:"
        foreach ($m in $matched) {
            $jsonCount = if (Test-Path $m.Path) { (Get-ChildItem -Path $m.Path -Filter "*.json" -ErrorAction SilentlyContinue).Count } else { 0 }
            $datCount = if (Test-Path $m.Path) { (Get-ChildItem -Path $m.Path -Filter "*.dat" -ErrorAction SilentlyContinue).Count } else { 0 }
            $fileCount = $jsonCount + $datCount
            Write-Host "  '$($m.Name)' ($fileCount object(s)) at $($m.Path)"
        }
        $response = Read-Host "Proceed? (Y/N)"
        if ($response -notmatch '^[yY]') {
            Write-Host "Cancelled"
            return
        }
    }

    foreach ($m in $matched) {
        if (Test-Path $m.Path) {
            $allFiles = Get-ChildItem -Path $m.Path -File -ErrorAction SilentlyContinue
            $otherFiles = $allFiles | Where-Object { $_.Extension -notin ".dat", ".json" }
            if ($otherFiles) {
                Write-Warning "Bucket '$($m.Name)' contains non-bucket files, skipping:"
                foreach ($f in $otherFiles) {
                    Write-Warning "  $($f.Name)"
                }
                continue
            }
        }

        $jsonCount = if (Test-Path $m.Path) { (Get-ChildItem -Path $m.Path -Filter "*.json" -ErrorAction SilentlyContinue).Count } else { 0 }
        $datCount = if (Test-Path $m.Path) { (Get-ChildItem -Path $m.Path -Filter "*.dat" -ErrorAction SilentlyContinue).Count } else { 0 }
        $fileCount = $jsonCount + $datCount

        if ($WhatIf) {
            Write-Host "Removing bucket '$($m.Name)' ($fileCount object(s))"
            Write-Host "  Path: $($m.Path)"
            Write-Host "[WhatIf] Would remove: $($m.Path)"
            continue
        }

        Write-Host "Removing bucket '$($m.Name)' ($fileCount object(s))"
        Write-Host "  Path: $($m.Path)"

        if (Test-Path $m.Path) {
            Remove-Item -Path $m.Path -Recurse -Force
        }
        Write-Host "Bucket '$($m.Name)' removed"
    }
}

Remove-Item -Path Alias:Save-BucketObject -ErrorAction SilentlyContinue
Remove-Item -Path Alias:Get-BucketObject -ErrorAction SilentlyContinue
