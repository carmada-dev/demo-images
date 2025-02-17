
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

	$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source

	if (-not $winget) { 

		$lastRecordId = Get-WinEvent -ProviderName 'Microsoft-Windows-AppXDeployment-Server' `
			| Where-Object { $_.LogName -eq 'Microsoft-Windows-AppXDeploymentServer/Operational' } `
			| Measure-Object -Property RecordId -Maximum
		
		try {
			
			if ((Get-Service -Name AppXSvc).Status -eq 'Stopped') {
				Write-Host ">>> Starting AppX Deployment Service (AppXSVC)"
				Start-Service -Name AppXSvc
			}

			Write-Host ">>> Registering WinGet Package Manager"
			Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue

			$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
			if (-not $winget) { 
				
				Write-Host ">>> Repairing WinGet Package Manager (WinGet not found)"

				Write-Host "- Installing NuGet Package Provider"
				Install-PackageProvider -Name NuGet -Force | Out-Null
			
				Write-Host "- Installing Microsoft.Winget.Client"
				Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
			
				Write-Host "- Run WinGet Package Manager repair"
				Repair-WinGetPackageManager -Verbose

			}
			
			$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
			if (-not $winget) { throw "WinGet not unavailable" }

		} 
		finally {

			Write-Host ">>> Dump EventLog - Microsoft-Windows-AppXDeploymentServer/Operational ($lastRecordId)"
			Get-WinEvent -ProviderName 'Microsoft-Windows-AppXDeployment-Server' `
				| Where-Object { ($_.LogName -eq 'Microsoft-Windows-AppXDeploymentServer/Operational') -and ($_.RecordId -gt $lastRecordId) } `
				| Format-List TimeCreated, @{ name='Operation'; expression={ $_.OpcodeDisplayName } }, Message 
		}
	}

	return $winget
}

$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source

if ($winget) {

	Write-Host ">>> WinGet is already installed: $winget"

} else {

	Invoke-ScriptSection -Title "Installing WinGet Package Manager" -ScriptBlock {

		$retryCnt = 0
		$retryMax = 10
		$retryDelay = 30

		while (-not $winget) {
			
			try
			{
				$winget = Install-WinGet
			}
			catch
			{
				if (++$retryCnt -gt $retryMax) { 
					Write-Warning "!!! WinGet installation failed: $($_.Exception.Message)"
					throw 
				} else {
					Write-Warning "!!! WinGet installation failed: retrying in $retryDelay seconds"
					Start-Sleep -Seconds $retryDelay
				}
			}
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
