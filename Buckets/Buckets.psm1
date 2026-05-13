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

# --- Load private helpers ---
Get-ChildItem "$PSScriptRoot/private/*.ps1" | ForEach-Object { . $_.FullName }

# --- Load public cmdlets ---
Get-ChildItem "$PSScriptRoot/public/*.ps1" | ForEach-Object { . $_.FullName }

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
