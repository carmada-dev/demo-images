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

function Install-WinGet {

	$PsInstallScope = "$(&{ if (Test-IsSystem) { 'AllUsers' } else { 'CurrentUser' } })"
	$wingetOffline = (Join-Path $env:DEVBOX_HOME 'Offline\WinGet')

	$nugetProviderVersion = "2.8.5.201"
	$wingetClientVersion = "1.9.2411"
	$wingetConfigVersion = "1.8.1911"

	Invoke-ScriptSection -Title "Installing WinGet Package Manager ($PsInstallScope)" -ScriptBlock {

		try
		{
			Write-Host ">>> Registering WinGet Package Manager"
			Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
		}
		catch
		{
			if (-not (Get-PackageProvider | Where-Object { $_.Name -eq "NuGet" -and $_.Version -gt $nugetProviderVersion })) {
				Write-Host ">>> Installing NuGet Package Provider: $nugetProviderVersion"
				Install-PackageProvider -Name NuGet -MinimumVersion $nugetProviderVersion -Force -Scope $PsInstallScope
			}

			Write-Host ">>> Set PSGallery as Trusted Repository"
			Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
			powershell.exe -MTA -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted"

			if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client | Where-Object { $_.Version -ge $wingetClientVersion })) {
				Write-Host ">>> Installing Microsoft.Winget.Client: $wingetClientVersion"
				Install-Module Microsoft.WinGet.Client -Scope $PsInstallScope -RequiredVersion $wingetClientVersion
				powershell.exe -MTA -Command "Install-Module Microsoft.WinGet.Client -Scope $PsInstallScope -RequiredVersion $wingetClientVersion"
			}

			Write-Host ">>> Installing/Repairing WinGet Package Manager"
			powershell.exe -MTA -Command "Repair-WinGetPackageManager -Verbose"

			Write-Host ">>> Revert PSGallery to Untrusted Repository"
			Set-PSRepository -Name "PSGallery" -InstallationPolicy Untrusted
			powershell.exe -MTA -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Untrusted"
		}

		$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
		if ($winget) {
			$wingetVersion = Invoke-CommandLine -Command $winget -Arguments "--version" | Select-Object -ExpandProperty Output 
			Write-Host ">>> WinGet Installed: $wingetVersion"
		}
	}

	if (Test-IsPacker) {

		# to ensure WinGet if prefering machine scope installers when running as Packer we nneed to patch the WinGet configuration
		Invoke-ScriptSection -Title "Patching WinGet Config for Packer Mode" -ScriptBlock {

			$wingetPackageFamilyName = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' | Select-Object -ExpandProperty PackageFamilyName

			$paths = @(
				"%LOCALAPPDATA%\Packages\$wingetPackageFamilyName\LocalState\settings.json",
				"%LOCALAPPDATA%\Microsoft\WinGet\Settings\settings.json"
			) 
			
			$paths | ForEach-Object { [System.Environment]::ExpandEnvironmentVariables($_) } | Where-Object { Test-Path (Split-Path -Path $_ -Parent) -PathType Container } | ForEach-Object { 

				Write-Host ">>> Patching WinGet ($winGetVersion) Settings: $_"
				$adminWinGetConfig | Out-File $_ -Encoding ASCII -Force 
				
			}
		} 

	} 
}

$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source

if ($winget) {

	Write-Host ">>> WinGet is already installed: $winget"

} else {

	if (Test-IsPacker) {

		# if executed by Packer elevate the script to SYSTEM and install WinGet for all users
		Invoke-CommandLine -Command "powershell" -Arguments "-NoLogo -Mta -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Path)`"" -AsSystem `
			| Select-Object -ExpandProperty Output `
			| Write-Host
		
		$paths = @(
			[System.Environment]::GetEnvironmentVariable("Path","Machine"),
			[System.Environment]::GetEnvironmentVariable("Path","User")
		)

		# update the PATH environment variable to include the WinGet installation path
		$env:Path = $paths -join ';'

		# get the WinGet executable path - this should be available after the PATH update
		$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
	}

	if (-not ($winget)) {

		# if WinGet is not installed install it for the current user
		Install-WinGet
	}
} 
