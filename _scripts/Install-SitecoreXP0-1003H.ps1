Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if ((Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V' | Select-Object -ExpandProperty State) -ne 'Enabled') {
	Write-Host "!!! Hyper-V must be enabled"
	exit 1
} elseif (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup -Path $MyInvocation.MyCommand.Path -Name 'Install-Sidecore.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

