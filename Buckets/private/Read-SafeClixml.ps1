function Read-SafeClixml {
    param([string]$Clixml)

    if ([string]::IsNullOrWhiteSpace($Clixml)) { return $null }

    if ($Clixml -match '<SBK') {
        Write-Warning "CLIXML contains ScriptBlock elements — skipping potentially unsafe deserialization"
        return $null
    }

    if ($Clixml -match '<Obj RefId="[^"]*"><TN[^>]*><T>System\.Management\.Automation\.ScriptBlock</T>') {
        Write-Warning "CLIXML contains ScriptBlock object references — skipping potentially unsafe deserialization"
        return $null
    }

    if ($Clixml -match '<MS[^>]*><TN[^>]*><T>System\.Management\.Automation\.PSMethod</T>') {
        Write-Warning "CLIXML contains CodeMethod or ScriptMethod elements — skipping potentially unsafe deserialization"
        return $null
    }

    try {
        return [System.Management.Automation.PSSerializer]::Deserialize($Clixml)
    }
    catch {
        Write-Warning "Failed to deserialize CLIXML: $_"
        return $null
    }
}
