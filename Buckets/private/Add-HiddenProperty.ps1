function Add-HiddenProperty {
    param([PSObject]$Target, [string]$Name, $Value)
    $prop = [System.Management.Automation.PSNoteProperty]::new($Name, $Value)
    $script:IsHiddenProp.SetValue($prop, $true)
    $Target.PSObject.Properties.Add($prop)
}