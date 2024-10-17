Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

[array] $features = '${jsonencode(features)}' | ConvertFrom-Json
if ($features.Count -gt 0) {
	
	Invoke-ScriptSection -Title "Enable Windows Features" -ScriptBlock {
		$features | Foreach-Object {
			Write-Host "- $_"
			Get-WindowsOptionalFeature -Online `
				| Where-Object { $_.FeatureName -eq "$_" -and $_.State -ne "Enabled" } `
				| Enable-WindowsOptionalFeature -Online -All -NoRestart `
				| Out-Null
		}
	}
}

Invoke-ScriptSection -Title "Enabled Windows Features" -ScriptBlock {

	Get-WindowsOptionalFeature -Online `
		| Where-Object { $_.State -eq 'Enabled' } `
		| Select-Object -ExpandProperty FeatureName `
		| Sort-Object `
		| Format-Table -HideTableHeaders `
		| Out-String `
		| Write-Host
}
