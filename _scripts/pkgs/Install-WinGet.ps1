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

function Repair-WinGet {

	Write-Host ">>> Repairing WinGet Package Manager"

	Write-Host "- Installing NuGet Package Provider"
	Install-PackageProvider -Name NuGet -Force | Out-Null

	Write-Host "- Installing Microsoft.Winget.Client"
	Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null

	Write-Host "- Repairing WinGet Package Manager"
	Repair-WinGetPackageManager -Verbose
}

function Install-WinGet {

	if (Test-IsSystem) {

		Invoke-ScriptSection -Title "Dump Automatic Services" -ScriptBlock {
			Get-Service | Where-Object { $_.StartType -like 'Automatic' } | Format-Table -Property DisplayName, Name, Status
			Get-Service | Where-Object { $_.StartType -like 'Automatic' -and $_.Status -eq 'Stopped' } | Start-Service -ErrorAction Continue
		}
	}

	Invoke-ScriptSection -Title "Installing WinGet Package Manager" -ScriptBlock {

		try
		{
			Write-Host ">>> Registering WinGet Package Manager"
			Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe

			$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
			if (-not $winget) { Repair-WinGet }
		}
		catch
		{
			Repair-WinGet
		}
		
		$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
		if (-not $winget) { Write-Warning "!!! WinGet still unavailable" }
	}
}

$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source

if ($winget) {

	Write-Host ">>> WinGet is already installed: $winget"

} else {

	if (Test-IsPacker) {

		# if executed by Packer elevate the script to SYSTEM and install WinGet for all users
		Invoke-CommandLine -Command "powershell" -Arguments "-NoLogo -Mta -File `"$($MyInvocation.MyCommand.Path)`"" -AsSystem `
			| Select-Object -ExpandProperty Output `
			| Write-Host
		
	}

	Install-WinGet

	if (Test-IsPacker) {

		# to ensure WinGet if prefering machine scope installers when running as Packer we nneed to patch the WinGet configuration
		Invoke-ScriptSection -Title "Patching WinGet Config for Packer Mode" -ScriptBlock {

			$wingetPackageFamilyName = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' | Select-Object -ExpandProperty PackageFamilyName

			$paths = @(
				"%LOCALAPPDATA%\Packages\$wingetPackageFamilyName\LocalState\settings.json",
				"%LOCALAPPDATA%\Microsoft\WinGet\Settings\settings.json"
			) 
			
			$paths | ForEach-Object { [System.Environment]::ExpandEnvironmentVariables($_) } | ForEach-Object { 

				if (Test-Path (Split-Path -Path $_ -Parent) -PathType Container) {
					Write-Host ">>> Patching WinGet Settings: $_"
					$adminWinGetConfig | Out-File $_ -Encoding ASCII -Force 
				} else {
					Write-Warning "!!! WinGet Settings not found: $_"
				}
			}
		} 
	} 
} 
