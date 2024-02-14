param(
    [Parameter(Mandatory=$false)]
    [boolean] $Packer = ((Get-ChildItem env:packer_* | Measure-Object).Count -gt 0)
)

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
			Enable-WindowsOptionalFeature `
				-FeatureName $_ `
				-Online -All -NoRestart -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-null
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
