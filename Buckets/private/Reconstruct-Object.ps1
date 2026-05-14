function Reconstruct-Object {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$DirPath)

    $di = [System.IO.DirectoryInfo]::new($DirPath)
    if (-not $di.Exists) { return $null }

    $props = [ordered]@{}
    $allNumeric = $true
    $hasEntries = $false

    $allFiles = @($di.GetFiles("*.json")) + @($di.GetFiles("*.dat"))
    foreach ($file in $allFiles) {
        $hasEntries = $true
        $key = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        if ($key -notmatch '^\d+$') { $allNumeric = $false; break }
    }

    if ($allNumeric) {
        foreach ($subDir in $di.GetDirectories()) {
            if ($subDir.Name -eq '.buckets') { continue }
            $hasEntries = $true
            if ($subDir.Name -notmatch '^\d+$') { $allNumeric = $false; break }
        }
    }

    if (-not $hasEntries) { return $null }

    if ($allNumeric) {
        $items = @{}
        foreach ($file in $allFiles) {
            $idx = [int][System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $value = Read-BucketFile -File $file
            if ($null -ne $value) { $items[$idx] = $value }
        }
        foreach ($subDir in $di.GetDirectories()) {
            if ($subDir.Name -eq '.buckets') { continue }
            $idx = [int]$subDir.Name
            $items[$idx] = Reconstruct-Object -DirPath $subDir.FullName
        }
        if ($items.Count -eq 0) { return $null }
        $sorted = $items.Keys | Sort-Object
        return [System.Collections.ArrayList]@($sorted | ForEach-Object { $items[$_] })
    }
    else {
        $result = [ordered]@{}
        foreach ($file in $allFiles) {
            $key = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $value = Read-BucketFile -File $file
            if ($null -ne $value) { $result[$key] = $value }
        }
        foreach ($subDir in $di.GetDirectories()) {
            if ($subDir.Name -eq '.buckets') { continue }
            $result[$subDir.Name] = Reconstruct-Object -DirPath $subDir.FullName
        }
        if ($result.Count -eq 0) { return $null }
        return [PSCustomObject]$result
    }
}
