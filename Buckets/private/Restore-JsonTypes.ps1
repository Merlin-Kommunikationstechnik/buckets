function Restore-JsonTypes {
    param([PSObject]$InputObject)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -isnot [PSCustomObject] -and $InputObject -isnot [hashtable]) { return $InputObject }

    $typeMap = if ($InputObject -is [PSCustomObject]) {
        $p = $InputObject.PSObject.Properties['_BucketTypes']
        if ($p) { $p.Value } else { $null }
    } else {
        if ($InputObject.ContainsKey('_BucketTypes')) { $InputObject['_BucketTypes'] } else { $null }
    }

    if ($null -eq $typeMap) { return $InputObject }

    Apply-TypeMap -InputObject $InputObject -TypeMap $typeMap -Prefix ''

    $rootType = if ($typeMap -is [PSCustomObject]) {
        $p = $typeMap.PSObject.Properties['~root']
        if ($p) { $p.Value } else { $null }
    } elseif ($typeMap -is [hashtable]) {
        $typeMap['~root']
    }

    if ($InputObject -is [PSCustomObject]) {
        $p = $InputObject.PSObject.Properties['_BucketTypes']
        if ($p) { $InputObject.PSObject.Properties.Remove($p) }
    } else {
        $InputObject.Remove('_BucketTypes')
    }

    if ($rootType -eq 'System.Collections.Hashtable') {
        $ht = [ordered]@{}
        foreach ($p in $InputObject.PSObject.Properties) { $ht[$p.Name] = $p.Value }
        return $ht
    }

    return $InputObject
}

function Apply-TypeMap {
    param([PSObject]$InputObject, $TypeMap, [string]$Prefix)

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
        $arrayElemType = Get-TypeMapEntry -TypeMap $TypeMap -Key "${fullPath}[]"

        if ($null -ne $arrayElemType -and $propValue -is [Array]) {
            $targetType = [Type]::GetType($arrayElemType)
            if ($null -ne $targetType) {
                $arr = [System.Collections.ArrayList]::new()
                foreach ($elem in $propValue) {
                    if ($null -eq $elem -or $elem.GetType() -eq $targetType) { $null = $arr.Add($elem); continue }
                    $converted = Convert-ToType -Value $elem -TypeName $arrayElemType
                    $null = $arr.Add(if ($null -ne $converted) { $converted } else { $elem })
                }
                $typedArr = [Array]::CreateInstance($targetType, $arr.Count)
                $arr.CopyTo($typedArr, 0)
                if ($InputObject -is [hashtable]) { $InputObject[$propName] = $typedArr }
                else { $InputObject.PSObject.Properties[$propName].Value = $typedArr }
            }
        }
        else {
            $typeName = Get-TypeMapEntry -TypeMap $TypeMap -Key $fullPath
            if ($null -ne $typeName) {
                $converted = Convert-ToType -Value $propValue -TypeName $typeName
                if ($null -ne $converted) {
                    if ($InputObject -is [hashtable]) { $InputObject[$propName] = $converted }
                    else { $InputObject.PSObject.Properties[$propName].Value = $converted }
                }
            }
        }

        if ($propValue -is [PSCustomObject] -or $propValue -is [hashtable]) {
            Apply-TypeMap -InputObject $propValue -TypeMap $TypeMap -Prefix $fullPath
        }
        elseif ($propValue -is [Array]) {
            for ($i = 0; $i -lt $propValue.Length; $i++) {
                $item = $propValue[$i]
                if ($null -ne $item -and ($item -is [PSCustomObject] -or $item -is [hashtable])) {
                    Apply-TypeMap -InputObject $item -TypeMap $TypeMap -Prefix "${fullPath}[$i]"
                }
            }
        }
    }
}

function Get-TypeMapEntry {
    param($TypeMap, [string]$Key)
    if ($TypeMap -is [PSCustomObject]) {
        $p = $TypeMap.PSObject.Properties[$Key]
        return if ($p) { $p.Value } else { $null }
    }
    if ($TypeMap -is [hashtable] -and $TypeMap.ContainsKey($Key)) { return $TypeMap[$Key] }
    return $null
}

function Convert-ToType {
    param([object]$Value, [string]$TypeName)

    if ($null -eq $Value) { return $null }
    $currentType = $Value.GetType().FullName
    if ($currentType -eq $TypeName) { return $Value }

    try {
        $targetType = [Type]::GetType($TypeName)

        if ($null -eq $targetType -and $TypeName -match 'System\.Nullable`1\[\[(.+?),') {
            $targetType = [Type]::GetType($matches[1])
        }

        if ($null -eq $targetType) { return $null }
        if ($Value.GetType() -eq $targetType) { return $Value }

        if ($targetType -eq [datetime]) { return [datetime]::Parse($Value.ToString(), [System.Globalization.CultureInfo]::InvariantCulture) }
        if ($targetType -eq [datetimeoffset]) { return [datetimeoffset]::Parse($Value.ToString(), [System.Globalization.CultureInfo]::InvariantCulture) }
        if ($targetType -eq [timespan]) { return [timespan]::Parse($Value.ToString(), [System.Globalization.CultureInfo]::InvariantCulture) }
        if ($targetType -eq [guid]) { return [guid]::Parse($Value.ToString()) }

        if ($targetType.IsEnum) { return [Enum]::Parse($targetType, $Value.ToString()) }

        return [System.Convert]::ChangeType($Value, $targetType)
    }
    catch { return $null }
}
