Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Install-WinGet.ps1' -Elevate
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

$adminWinGetConfig = @"
{
	"`$schema": "https://aka.ms/winget-settings.schema.json",
	"installBehavior": {
		"preferences": {
			"scope": "machine"
		}
	},
	"experimentalFeatures": {
		"configuration": true
	}
}
"@

Invoke-ScriptSection -Title "Installing WinGet Package Manager" -ScriptBlock {

	$osType = (&{ if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' } })

	Write-Host ">>> Installing WinGet pre-requisites ($osType) - Microsoft.VCLibs ..."
	$path = Invoke-FileDownload -Url "https://aka.ms/Microsoft.VCLibs.$osType.14.00.Desktop.appx"
	Add-AppxPackage -Path $path -ErrorAction Stop
	
	Write-Host ">>> Installing WinGet pre-requisites ($osType) - Microsoft.UI.Xaml ..."
	$path = Invoke-FileDownload -Url "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6" -Name 'Microsoft.UI.Xaml.zip' -Expand $true
	Add-AppxPackage -Path (Join-Path -path $path -ChildPath "tools\AppX\$osType\Release\Microsoft.UI.Xaml.2.8.appx") -ErrorAction Stop

	Write-Host ">>> Installing WinGet CLI..."
	$path = Invoke-FileDownload -Url "$(Get-GitHubLatestReleaseDownloadUrl -Organization 'microsoft' -Repository 'winget-cli' -Asset 'msixbundle')"
	Add-AppxPackage -Path $path -ErrorAction Stop

	if (Test-IsElevated) {
		Write-Host ">>> Resetting WinGet Sources ..."
		Invoke-CommandLine -Command 'winget' -Arguments "source reset --force --disable-interactivity" | Select-Object -ExpandProperty Output | Write-Host
	}

	Write-Host ">>> Adding WinGet Source Cache Package ..."
	$path = Invoke-FileDownload -Url "https://cdn.winget.microsoft.com/cache/source.msix" -Retries 5
	Add-AppxPackage -Path $path -ErrorAction Stop
}

if (Test-IsPacker) {
	Invoke-ScriptSection -Title "Patching WinGet Config for Packer Mode" -ScriptBlock {

		$wingetPackageFamilyName = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' | Select-Object -ExpandProperty PackageFamilyName

		$settingsPaths = @(

			"%LOCALAPPDATA%\Packages\$wingetPackageFamilyName\LocalState\settings.json",
			"%LOCALAPPDATA%\Microsoft\WinGet\Settings\settings.json"

		) | ForEach-Object { [System.Environment]::ExpandEnvironmentVariables($_) } | Where-Object { Test-Path (Split-Path -Path $_ -Parent) -PathType Container } | ForEach-Object { 

			Write-Host ">>> Patching WinGet Settings: $_"
			$adminWinGetConfig | Out-File $_ -Encoding ASCII -Force 
			
		}

	}
}