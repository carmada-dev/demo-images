
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

function Start-Services {

	Write-Host ">>> Starting Services"
	@( 'AppXSVC', 'ClipSVC', 'StateRepository', 'wuauserv', 'InstallService' ) | ForEach-Object {
	
		$service = Get-Service -Name $_ -ErrorAction SilentlyContinue
		if ($service -and ($service.Status -ne 'Running')) {
	
			Write-Host "- Service: $($service.DisplayName) ($($service.Name))"
			Start-Service -Name $service.Name 
		}
	}
}

function Resolve-WinGet {
	
	$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source

	if (-not $winget) { 
		$process = Invoke-CommandLine -Command "where" -Arguments "winget"
		if ($process.ExitCode -eq 0) { $winget = $process.Output }
	}

	return $winget
}

function Install-WinGet {

	Write-Host ">>> Installing NuGet Package Provider"
	Install-PackageProvider -Name NuGet -Force -WarningAction SilentlyContinue | Out-Null

	Write-Host ">>> Installing Microsoft.Winget.Client"
	Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -WarningAction SilentlyContinue | Out-Null

	Write-Host ">>> Repairing WinGet Package Manager"
	Repair-WinGetPackageManager -Verbose -Force -AllUsers:$(Test-IsSystem) 

	return Resolve-WinGet
}

$winget = Resolve-WinGet

if ($winget) {

	Write-Host ">>> WinGet is already installed: $winget"

} elseif (Test-IsSystem) {

	Invoke-ScriptSection -Title "Installing WinGet Package Manager - $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ScriptBlock {

		# ensure all required services are running
		Start-Services

		# install the WinGet package manager and publish the winget path to the global scope
		(Get-Variable -Name winget -Scope Global).Value = Install-WinGet
	}

} else {

	if (Test-IsPacker) {

		# invoke the script as SYSTEM to ensure the WinGet installation is available to all users
		$process = Invoke-CommandLine -Command "powershell" -Arguments "-NoLogo -Mta -ExecutionPolicy $(Get-ExecutionPolicy) -File `"$($MyInvocation.MyCommand.Path)`"" -AsSystem 
		$process.Output | Write-Host

		if ($process.ExitCode -ne 0) {
			# something went wrong - throw an exception to stop the script 
			throw "WinGet installation failed with exit code $($process.ExitCode)"
		} else {
			# retrieve the winget path 
			$winget = Resolve-WinGet
		}
	}

	if (-not $winget) {

		Invoke-ScriptSection -Title "Dump Context Information - $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ScriptBlock {
	
			Get-AppxPackage 'Microsoft.VCLibs.140.00.UWPDesktop' -AllUsers
		}

		Invoke-ScriptSection -Title "Installing WinGet Package Manager - $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ScriptBlock {

			$retryCnt = 0
			$retryMax = 10
			$retryDelay = 30

			# ensure all required services are running
			Start-Services

			while (-not $winget) {
				
				$lastRecordId = Get-WinEvent -ProviderName 'Microsoft-Windows-AppXDeployment-Server' `
					| Where-Object { $_.LogName -eq 'Microsoft-Windows-AppXDeploymentServer/Operational' } `
					| Measure-Object -Property RecordId -Maximum `
					| Select-Object -ExpandProperty Maximum

				try
				{
					$winget = Install-WinGet
					
					if ($winget) {
						Write-Host ">>> WinGet installed: $winget"
					} else { 
						throw "WinGet not unavailable" 
					}
				}
				catch
				{
					Write-Warning "!!! WinGet installation failed: $($_.Exception.Message)"

					$records = Get-WinEvent -ProviderName 'Microsoft-Windows-AppXDeployment-Server' `
						| Where-Object { ($_.LogName -eq 'Microsoft-Windows-AppXDeploymentServer/Operational') -and ($_.RecordId -gt $lastRecordId) }

					if ($records) {
						Write-Host '----------------------------------------------------------------------------------------------------------'
						$records | Format-List TimeCreated, @{ name='Operation'; expression={ $_.OpcodeDisplayName } }, Message 
					}

					if (++$retryCnt -gt $retryMax) { 
						throw 
					} else {
						Write-Host '----------------------------------------------------------------------------------------------------------'
						Start-Sleep -Seconds $retryDelay
					}

				}
			}
		}
	}
} 

if ($winget -and (Test-IsPacker -or Test-IsSystem)) {

	Invoke-ScriptSection -Title "Patching WinGet Config to prefer machine scope by default" -ScriptBlock {

		$wingetPackageFamilyName = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' | Select-Object -ExpandProperty PackageFamilyName

		$paths = @(
			"%LOCALAPPDATA%\Packages\$wingetPackageFamilyName\LocalState\settings.json",
			"%LOCALAPPDATA%\Microsoft\WinGet\Settings\settings.json"
		) 
		
		$paths | ForEach-Object { [System.Environment]::ExpandEnvironmentVariables($_) } | ForEach-Object { 
			$folder = Split-Path -Path $_ -Parent
			if (Test-Path $folder -PathType Container) {
				Write-Host ">>> Patching WinGet Settings: $_"
				$adminWinGetConfig | Out-File $_ -Encoding ASCII -Force 
			} else {
				Write-Warning "!!! Folder not found: $folder"
			}
		}
	} 
} 