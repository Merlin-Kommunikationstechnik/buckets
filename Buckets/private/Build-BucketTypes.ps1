function Build-BucketTypes {
    param([PSObject]$InputObject)

    $typeMap = [ordered]@{}
    if ($null -eq $InputObject) { return $typeMap }

    $typeMap['~root'] = $InputObject.GetType().FullName

    Walk-ObjectTypes -InputObject $InputObject -TypeMap $typeMap -Prefix ''

    return $typeMap
}

function Walk-ObjectTypes {
    param([PSObject]$InputObject, [System.Collections.IDictionary]$TypeMap, [string]$Prefix)

    $props = if ($InputObject -is [hashtable]) {
        @($InputObject.GetEnumerator())
    } elseif ($InputObject -is [PSCustomObject]) {
        @($InputObject.PSObject.Properties)
    } else { return }

    foreach ($prop in $props) {
        $propName = if ($InputObject -is [hashtable]) { $prop.Key } else { $prop.Name }
        $propValue = if ($InputObject -is [hashtable]) { $prop.Value } else { $prop.Value }

        if ($propName -eq '_BucketTypes') { continue }
        if ($null -eq $propValue) { continue }

        $fullPath = if ($Prefix) { "${Prefix}.${propName}" } else { $propName }

        if ($propValue -is [Array]) {
            $arrayPath = "${fullPath}[]"
            $elementType = $null
            foreach ($item in $propValue) { if ($null -ne $item) { $elementType = $item.GetType(); break } }
            if ($null -ne $elementType) { $TypeMap[$arrayPath] = $elementType.FullName }
            for ($i = 0; $i -lt $propValue.Length; $i++) {
                $item = $propValue[$i]
                if ($null -ne $item -and ($item -is [PSCustomObject] -or $item -is [hashtable])) {
                    Walk-ObjectTypes -InputObject $item -TypeMap $TypeMap -Prefix "${fullPath}[$i]"
                }
            }
        }
        elseif ($propValue -is [PSCustomObject] -or $propValue -is [hashtable]) {
            Walk-ObjectTypes -InputObject $propValue -TypeMap $TypeMap -Prefix $fullPath
        }
        else {
            $TypeMap[$fullPath] = $propValue.GetType().FullName
        }
    }
}
