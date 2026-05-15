function Expand-Object {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][string]$BucketPath,
        [Parameter(Mandatory = $true)][string]$Extension,
        [bool]$AsBinary,
        [bool]$Compress,
        [int]$Depth = 20,
        [int]$BinaryDepth = 5,
        [bool]$Overwrite,
        [bool]$AutoIndex,
        [int]$CurrentDepth = 0,
        [int]$MaxDepth = 5,
        [string]$RootPath,
        [string]$BucketName
    )

    $result = @{
        Saved = 0; Failed = 0; Skipped = 0; Overwritten = 0
        Sanitized = 0; Indexed = 0; Branches = 0; Leaves = 0
        StoredKeys = [System.Collections.ArrayList]::new()
        SkippedKeys = [System.Collections.ArrayList]::new()
        SanitizedDetails = [System.Collections.ArrayList]::new()
        OverwrittenKeys = [System.Collections.ArrayList]::new()
    }

    if ($null -eq $Item) { return $result }

    $isDict = $Item -is [hashtable] -or $Item -is [System.Collections.IDictionary]
    $isArray = -not $isDict -and -not ($Item -is [string]) -and $Item -is [System.Collections.ICollection]

    if ($isDict) {
        $propNames = if ($Item -is [hashtable]) { $Item.Keys } else { $Item.Keys }
        $seenKeys = @{}
        foreach ($pname in $propNames) {
            $value = $Item[$pname]
            $safeKey = $pname -replace '[\\/:\*\?"<>\|\[\]]', '_'
            if ($safeKey -match '^_+$' -or [string]::IsNullOrWhiteSpace($safeKey)) { continue }
            $wasSanitized = $safeKey -ne $pname
            if ($AutoIndex -and $seenKeys.ContainsKey($safeKey)) {
                $idxVal = 1
                while ($seenKeys.ContainsKey("${safeKey}_${idxVal}")) { $idxVal++ }
                $safeKey = "${safeKey}_${idxVal}"
                $result.Indexed++
            }
            $seenKeys[$safeKey] = $true

            $valIsDict = $null -ne $value -and ($value -is [hashtable] -or $value -is [System.Collections.IDictionary])
            $valIsPSObj = $null -ne $value -and $value -is [PSCustomObject]
            $valIsArray = $null -ne $value -and -not ($value -is [string]) -and -not ($value -is [hashtable]) -and -not ($value -is [System.Collections.IDictionary]) -and $value -is [System.Collections.ICollection]

            if ($valIsDict -or $valIsPSObj -or $valIsArray) {
                if ($CurrentDepth + 1 -ge $MaxDepth) {
                    $filename = "${safeKey}${Extension}"
                    $filePath = Join-Path $BucketPath $filename
                    if ($wasSanitized) { $result.Sanitized++; $null = $result.SanitizedDetails.Add([PSCustomObject]@{ Original = $pname; Sanitized = $safeKey }) }
                    $writeResult = Save-BucketFile -Path $filePath -Item $value -Extension $Extension -AsBinary:$AsBinary -Compress:$Compress -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite -BucketPath $BucketPath -Bucket $BucketName
                    if ($writeResult.Success) { $result.Saved++; $result.Leaves++; $null = $result.StoredKeys.Add($safeKey); if ($writeResult.Overwritten) { $result.Overwritten++; $null = $result.OverwrittenKeys.Add($safeKey) } }
                    elseif ($writeResult.Skipped) { $result.Skipped++; $null = $result.SkippedKeys.Add($safeKey) }
                    else { $result.Failed++ }
                }
                else {
                    $subBucketPath = Join-Path $BucketPath $safeKey
                    $null = Ensure-BucketExists -Name "$BucketName/$safeKey" -Path $RootPath
                    $result.Branches++
                    $subResult = Expand-Object -Item $value -BucketPath $subBucketPath -Extension $Extension -AsBinary:$AsBinary -Compress:$Compress -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite -AutoIndex:$AutoIndex -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -RootPath $RootPath -BucketName "$BucketName/$safeKey"
                    $result.Saved += $subResult.Saved; $result.Failed += $subResult.Failed; $result.Skipped += $subResult.Skipped
                    $result.Overwritten += $subResult.Overwritten; $result.Sanitized += $subResult.Sanitized; $result.Indexed += $subResult.Indexed
                    $result.Branches += $subResult.Branches; $result.Leaves += $subResult.Leaves
                    foreach ($k in $subResult.StoredKeys) { $null = $result.StoredKeys.Add($k) }
                    foreach ($k in $subResult.SkippedKeys) { $null = $result.SkippedKeys.Add($k) }
                    foreach ($k in $subResult.SanitizedDetails) { $null = $result.SanitizedDetails.Add($k) }
                    foreach ($k in $subResult.OverwrittenKeys) { $null = $result.OverwrittenKeys.Add($k) }
                }
            }
            else {
                $filename = "${safeKey}${Extension}"
                $filePath = Join-Path $BucketPath $filename
                if ($wasSanitized) { $result.Sanitized++; $null = $result.SanitizedDetails.Add([PSCustomObject]@{ Original = $pname; Sanitized = $safeKey }) }
                $writeResult = Save-BucketFile -Path $filePath -Item $value -Extension $Extension -AsBinary:$AsBinary -Compress:$Compress -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite -BucketPath $BucketPath -Bucket $BucketName
                if ($writeResult.Success) { $result.Saved++; $result.Leaves++; $null = $result.StoredKeys.Add($safeKey); if ($writeResult.Overwritten) { $result.Overwritten++; $null = $result.OverwrittenKeys.Add($safeKey) } }
                elseif ($writeResult.Skipped) { $result.Skipped++; $null = $result.SkippedKeys.Add($safeKey) }
                else { $result.Failed++ }
            }
        }
    }
    elseif ($isArray) {
        for ($i = 0; $i -lt $Item.Count; $i++) {
            $element = $Item[$i]
            $idxKey = $i.ToString()
            $elemIsDict = $null -ne $element -and ($element -is [hashtable] -or $element -is [System.Collections.IDictionary])
            $elemIsPSObj = $null -ne $element -and $element -is [PSCustomObject]
            $elemIsArray = $null -ne $element -and -not ($element -is [string]) -and -not ($element -is [hashtable]) -and -not ($element -is [System.Collections.IDictionary]) -and $element -is [System.Collections.ICollection]
            if ($elemIsDict -or $elemIsPSObj -or $elemIsArray) {
                if ($CurrentDepth + 1 -ge $MaxDepth) {
                    $filename = "${idxKey}${Extension}"
                    $filePath = Join-Path $BucketPath $filename
                    $writeResult = Save-BucketFile -Path $filePath -Item $element -Extension $Extension -AsBinary:$AsBinary -Compress:$Compress -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite -BucketPath $BucketPath -Bucket $BucketName
                    if ($writeResult.Success) { $result.Saved++; $result.Leaves++; $null = $result.StoredKeys.Add($idxKey); if ($writeResult.Overwritten) { $result.Overwritten++; $null = $result.OverwrittenKeys.Add($idxKey) } }
                    elseif ($writeResult.Skipped) { $result.Skipped++; $null = $result.SkippedKeys.Add($idxKey) }
                    else { $result.Failed++ }
                }
                else {
                    $subBucketPath = Join-Path $BucketPath $idxKey
                    $null = Ensure-BucketExists -Name "$BucketName/$idxKey" -Path $RootPath
                    $result.Branches++
                    $subResult = Expand-Object -Item $element -BucketPath $subBucketPath -Extension $Extension -AsBinary:$AsBinary -Compress:$Compress -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite -AutoIndex:$AutoIndex -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -RootPath $RootPath -BucketName "$BucketName/$idxKey"
                    $result.Saved += $subResult.Saved; $result.Failed += $subResult.Failed; $result.Skipped += $subResult.Skipped
                    $result.Overwritten += $subResult.Overwritten; $result.Sanitized += $subResult.Sanitized; $result.Indexed += $subResult.Indexed
                    $result.Branches += $subResult.Branches; $result.Leaves += $subResult.Leaves
                    foreach ($k in $subResult.StoredKeys) { $null = $result.StoredKeys.Add($k) }
                    foreach ($k in $subResult.SkippedKeys) { $null = $result.SkippedKeys.Add($k) }
                    foreach ($k in $subResult.SanitizedDetails) { $null = $result.SanitizedDetails.Add($k) }
                    foreach ($k in $subResult.OverwrittenKeys) { $null = $result.OverwrittenKeys.Add($k) }
                }
            }
            else {
                $filename = "${idxKey}${Extension}"
                $filePath = Join-Path $BucketPath $filename
                $writeResult = Save-BucketFile -Path $filePath -Item $element -Extension $Extension -AsBinary:$AsBinary -Compress:$Compress -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite -BucketPath $BucketPath -Bucket $BucketName
                if ($writeResult.Success) { $result.Saved++; $result.Leaves++; $null = $result.StoredKeys.Add($idxKey); if ($writeResult.Overwritten) { $result.Overwritten++; $null = $result.OverwrittenKeys.Add($idxKey) } }
                elseif ($writeResult.Skipped) { $result.Skipped++; $null = $result.SkippedKeys.Add($idxKey) }
                else { $result.Failed++ }
            }
        }
    }
    else {
        $propNames = @($Item.PSObject.Properties | Where-Object { $_.MemberType -in @('Property', 'NoteProperty', 'ScriptProperty', 'CodeProperty', 'AliasProperty') } | ForEach-Object { $_.Name })
        if ($propNames.Count -eq 0) { return $result }
        $seenKeys = @{}
        foreach ($pname in $propNames) {
            $value = $Item.$pname
            $safeKey = $pname -replace '[\\/:\*\?"<>\|\[\]]', '_'
            if ($safeKey -match '^_+$' -or [string]::IsNullOrWhiteSpace($safeKey)) { continue }
            $wasSanitized = $safeKey -ne $pname
            if ($AutoIndex -and $seenKeys.ContainsKey($safeKey)) {
                $idxVal = 1
                while ($seenKeys.ContainsKey("${safeKey}_${idxVal}")) { $idxVal++ }
                $safeKey = "${safeKey}_${idxVal}"
                $result.Indexed++
            }
            $seenKeys[$safeKey] = $true

            $valIsDict = $null -ne $value -and ($value -is [hashtable] -or $value -is [System.Collections.IDictionary])
            $valIsPSObj = $null -ne $value -and $value -is [PSCustomObject]
            $valIsArray = $null -ne $value -and -not ($value -is [string]) -and -not ($value -is [hashtable]) -and -not ($value -is [System.Collections.IDictionary]) -and $value -is [System.Collections.ICollection]

            if ($valIsDict -or $valIsPSObj -or $valIsArray) {
                if ($CurrentDepth + 1 -ge $MaxDepth) {
                    $filename = "${safeKey}${Extension}"
                    $filePath = Join-Path $BucketPath $filename
                    if ($wasSanitized) { $result.Sanitized++; $null = $result.SanitizedDetails.Add([PSCustomObject]@{ Original = $pname; Sanitized = $safeKey }) }
                    $writeResult = Save-BucketFile -Path $filePath -Item $value -Extension $Extension -AsBinary:$AsBinary -Compress:$Compress -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite -BucketPath $BucketPath -Bucket $BucketName
                    if ($writeResult.Success) { $result.Saved++; $result.Leaves++; $null = $result.StoredKeys.Add($safeKey); if ($writeResult.Overwritten) { $result.Overwritten++; $null = $result.OverwrittenKeys.Add($safeKey) } }
                    elseif ($writeResult.Skipped) { $result.Skipped++; $null = $result.SkippedKeys.Add($safeKey) }
                    else { $result.Failed++ }
                }
                else {
                    $subBucketPath = Join-Path $BucketPath $safeKey
                    $null = Ensure-BucketExists -Name "$BucketName/$safeKey" -Path $RootPath
                    $result.Branches++
                    $subResult = Expand-Object -Item $value -BucketPath $subBucketPath -Extension $Extension -AsBinary:$AsBinary -Compress:$Compress -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite -AutoIndex:$AutoIndex -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -RootPath $RootPath -BucketName "$BucketName/$safeKey"
                    $result.Saved += $subResult.Saved; $result.Failed += $subResult.Failed; $result.Skipped += $subResult.Skipped
                    $result.Overwritten += $subResult.Overwritten; $result.Sanitized += $subResult.Sanitized; $result.Indexed += $subResult.Indexed
                    $result.Branches += $subResult.Branches; $result.Leaves += $subResult.Leaves
                    foreach ($k in $subResult.StoredKeys) { $null = $result.StoredKeys.Add($k) }
                    foreach ($k in $subResult.SkippedKeys) { $null = $result.SkippedKeys.Add($k) }
                    foreach ($k in $subResult.SanitizedDetails) { $null = $result.SanitizedDetails.Add($k) }
                    foreach ($k in $subResult.OverwrittenKeys) { $null = $result.OverwrittenKeys.Add($k) }
                }
            }
            else {
                $filename = "${safeKey}${Extension}"
                $filePath = Join-Path $BucketPath $filename
                if ($wasSanitized) { $result.Sanitized++; $null = $result.SanitizedDetails.Add([PSCustomObject]@{ Original = $pname; Sanitized = $safeKey }) }
                $writeResult = Save-BucketFile -Path $filePath -Item $value -Extension $Extension -AsBinary:$AsBinary -Compress:$Compress -Depth $Depth -BinaryDepth $BinaryDepth -Overwrite:$Overwrite -BucketPath $BucketPath -Bucket $BucketName
                if ($writeResult.Success) { $result.Saved++; $result.Leaves++; $null = $result.StoredKeys.Add($safeKey); if ($writeResult.Overwritten) { $result.Overwritten++; $null = $result.OverwrittenKeys.Add($safeKey) } }
                elseif ($writeResult.Skipped) { $result.Skipped++; $null = $result.SkippedKeys.Add($safeKey) }
                else { $result.Failed++ }
            }
        }
    }

    return $result
}
