function Set-Bucket {
    <#
    .SYNOPSIS
    Renames or moves a bucket.
    .DESCRIPTION
    Renames a bucket to a new name within the same parent, or moves it to a different
    parent path. All nested objects and sub-buckets are preserved — the underlying
    directory is moved on disk. Accepts pipeline input for bulk operations.
    .PARAMETER Bucket
    Current bucket name or path. Accepts pipeline input by property name.
    .PARAMETER NewName
    New bucket name or path. Accepts pipeline input by property name.
    .PARAMETER Path
    Root directory for bucket storage. Default: $HOME/.buckets.
    .PARAMETER PassThru
    Return metadata for the renamed bucket.
    .PARAMETER Quiet
    Suppress output.
    .EXAMPLE
    Set-Bucket -Bucket "inventory/ams" -NewName "inventory/ams-servers"
    .EXAMPLE
    Get-Bucket -Bucket "temp-*" | Select-Object Name, @{N="NewName";E={$_.Name -replace "^temp-", "archive-"}} | Set-Bucket
    .EXAMPLE
    Set-Bucket "org" "organization" -PassThru
    .EXAMPLE
    Set-Bucket "org" "organization" -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)][Alias('Name')][string]$Bucket,
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipelineByPropertyName = $true)][string]$NewName,
        [string]$Path,
        [switch]$PassThru,
        [switch]$Quiet
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultPath }
        $Path = Resolve-SafePath -Path $Path
        $renamedCount = 0; $lastOld = ''; $lastNew = ''
    }

    process {
        $oldBucketPath = Get-BucketPath -Name $Bucket -Path $Path
        $newBucketPath = Get-BucketPath -Name $NewName -Path $Path

        if (-not [System.IO.Directory]::Exists($oldBucketPath)) {
            Write-Warning "Bucket '$Bucket' not found at '$oldBucketPath'"
            return
        }

        if ([System.IO.Directory]::Exists($newBucketPath)) {
            Write-Warning "Bucket '$NewName' already exists at '$newBucketPath'"
            return
        }

        $parentDir = [System.IO.Path]::GetDirectoryName($newBucketPath)
        if (-not [System.IO.Directory]::Exists($parentDir)) {
            [System.IO.Directory]::CreateDirectory($parentDir) | Out-Null
        }

        $target = "'$Name' → '$NewName'"
        if ($PSCmdlet.ShouldProcess($target, "Set-Bucket")) {
            [System.IO.Directory]::Move($oldBucketPath, $newBucketPath)
            & $script:ClearCache
            $renamedCount++
            $lastOld = $Bucket
            $lastNew = $NewName
        }
    }

    end {
        if ($renamedCount -eq 0) { return }
        if ($PassThru) {
            [PSCustomObject]@{
                Name    = $lastNew
                OldName = $lastOld
                Path    = Get-BucketPath -Name $lastNew -Path $Path
            }
        }
        elseif (-not $Quiet) {
            $objLabel = if ($renamedCount -eq 1) { "1 bucket" } else { "$renamedCount buckets" }
            Write-Host "$lastOld" -NoNewline -ForegroundColor $script:CPath
            Write-Host " → " -NoNewline -ForegroundColor $script:CMuted
            Write-Host "$lastNew" -NoNewline -ForegroundColor $script:CPath
            Write-Host " · " -NoNewline -ForegroundColor $script:CMuted
            Write-Host "$objLabel renamed" -ForegroundColor $script:CMuted
        }
    }
}
