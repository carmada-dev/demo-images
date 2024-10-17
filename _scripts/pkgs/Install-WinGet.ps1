Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Install-WinGet.ps1'
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

	$offlineDirectory =	New-Item -Path (Join-Path $env:DEVBOX_HOME 'Offline\WinGet') -ItemType Directory -Force | Select-Object -ExpandProperty FullName
	Write-Host "- Offline directory: $offlineDirectory"

	$osType = (&{ if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' } })
	Write-Host "- OS Type: $osType"
	
	$wingetInstalled = [bool](Get-Command -Name 'winget' -ErrorAction SilentlyContinue)

	$url = "https://aka.ms/Microsoft.VCLibs.$osType.14.00.Desktop.appx"
	$loc = Join-Path $offlineDirectory ([IO.Path]::GetFileName($url))

	if (-not (Test-Path $loc -PathType Leaf)) {
		Write-Host ">>> Downloading WinGet pre-requisites ($osType) - Microsoft.VCLibs ..."
		$path = Invoke-FileDownload -Url $url -Name ([IO.Path]::GetFileName($loc))
		Move-Item -Path $path -Destination $loc -Force | Out-Null
	}

	Write-Host ">>> Installing WinGet pre-requisites ($osType) - Microsoft.VCLibs ..."
	$Error.Clear(); if (not($wingetInstalled)) { Add-AppxPackage -Path $loc -ForceApplicationShutdown -ErrorAction SilentlyContinue }

	if ($Error.Count -gt 0) {
		Write-Host ">>> Error installing WinGet pre-requisites ($osType) - Microsoft.VCLibs ..."
		$Error | Write-Warning
	}

	$url = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6"
	$loc = Join-Path $offlineDirectory 'Microsoft.UI.Xaml.2.8.appx'

	if (-not (Test-Path $loc -PathType Leaf)) {
		Write-Host ">>> Downloading WinGet pre-requisites ($osType) - Microsoft.UI.Xaml ..."
		$path = Invoke-FileDownload -Url $url -Name 'Microsoft.UI.Xaml.zip' -Expand $true
		Move-Item -Path (Join-Path $path "tools\AppX\$osType\Release\Microsoft.UI.Xaml.2.8.appx") -Destination $loc -Force | Out-Null
	}

	Write-Host ">>> Installing WinGet pre-requisites ($osType) - Microsoft.UI.Xaml ..."
	$Error.Clear(); if (not($wingetInstalled)) { Add-AppxPackage -Path $loc -ForceApplicationShutdown -ErrorAction SilentlyContinue }

	if ($Error.Count -gt 0) {
		Write-Host ">>> Error installing WinGet pre-requisites ($osType) - Microsoft.UI.Xaml ..."
		$Error | Write-Warning
	}

	$url = Get-GitHubLatestReleaseDownloadUrl -Organization 'microsoft' -Repository 'winget-cli' -Asset 'msixbundle'
	$loc = Join-Path $offlineDirectory ([IO.Path]::GetFileName($url))

	if (-not (Test-Path $loc -PathType Leaf)) {
		Write-Host ">>> Downloading WinGet CLI ..."
		$path = Invoke-FileDownload -Url $url -Name ([IO.Path]::GetFileName($loc))
		Move-Item -Path $path -Destination $loc -Force | Out-Null
	}

	Write-Host ">>> Installing WinGet CLI..."
	$Error.Clear(); if (not($wingetInstalled)) { Add-AppxPackage -Path $loc -ForceApplicationShutdown -ErrorAction SilentlyContinue }

	if ($Error.Count -gt 0) {
		Write-Host ">>> Error installing WinGet CLI..."
		$Error | Write-Warning
	}

	if (Test-IsElevated) {
		Write-Host ">>> Resetting WinGet Sources ..."
		Invoke-CommandLine -Command 'winget' -Arguments "source reset --force --disable-interactivity" | Select-Object -ExpandProperty Output | Write-Host
	}

	$url = "https://cdn.winget.microsoft.com/cache/source.msix"
	$loc = Join-Path $offlineDirectory ([IO.Path]::GetFileName($url))

	if (-not (Test-Path $loc -PathType Leaf)) {
		Write-Host ">>> Downloading WinGet Source Cache Package ..."
		$path = Invoke-FileDownload -Url $url -Name ([IO.Path]::GetFileName($loc)) -Retries 5
		Move-Item -Path $path -Destination $loc -Force | Out-Null
	}

	Write-Host ">>> Installing WinGet Source Cache Package ..."	
	$Error.Clear(); Add-AppxPackage -Path $loc -ForceApplicationShutdown -ErrorAction SilentlyContinue

	if ($Error.Count -gt 0) {
		Write-Host ">>> Error installing WinGet Source Cache Package ..."	
		$Error | Write-Warning
	}
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