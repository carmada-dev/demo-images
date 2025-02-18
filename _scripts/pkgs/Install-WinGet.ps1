
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
		$process = Invoke-CommandLine -Command "where" -Arguments "winget" -Silent
		if ($process.ExitCode -eq 0) { $winget = $process.Output }
	}

	return $winget
}

function Install-WinGet {

	param (
		[Parameter(Mandatory=$false)]
		[int] $Retries = 0,
		[Parameter(Mandatory=$false)]
		[int] $RetryDelay = 30
	)

	$retry = 0

	while ($retry++ -le $Retries) 
	{
		$lastEventRecordId = Get-WinEvent -ProviderName 'Microsoft-Windows-AppXDeployment-Server' `
			| Where-Object { $_.LogName -eq 'Microsoft-Windows-AppXDeploymentServer/Operational' } `
			| Measure-Object -Property RecordId -Maximum `
			| Select-Object -ExpandProperty Maximum

		try {

			Write-Host ">>> Installing NuGet Package Provider"
			Install-PackageProvider -Name NuGet -Force | Out-Null

			Write-Host ">>> Installing Microsoft.Winget.Client"
			Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Force | Out-Null

			Write-Host ">>> Repairing WinGet Package Manager"
			Repair-WinGetPackageManager -Verbose -Force -AllUsers:$(Test-IsSystem) 

			break # installation succeeded - exit the loop
		}
		catch {

			# as log as we are covered by the maximum number of retries, we just log the error as a warning
			if ($retry -le $Retries) { Write-Warning "!!! WinGet installation failed: $($_.Exception)" }

			$eventRecords = Get-WinEvent -ProviderName 'Microsoft-Windows-AppXDeployment-Server' `
				| Where-Object { ($_.LogName -eq 'Microsoft-Windows-AppXDeploymentServer/Operational') -and ($_.RecordId -gt $lastEventRecordId) }

			if ($eventRecords) {
				Write-Host '----------------------------------------------------------------------------------------------------------'
				$eventRecords | Format-List TimeCreated, @{ name='Operation'; expression={ $_.OpcodeDisplayName } }, Message 
			}

			# maximung retreis exhausted - lets blow it up
			if ($retry -gt $Retries) { throw }

			Write-Host '=========================================================================================================='
			Write-Host ">>> Retry: $retry / $Retries - Delay: $RetryDelay seconds"
			Write-Host '=========================================================================================================='
			Start-Sleep -Seconds $RetryDelay
		}
	}

	return Resolve-WinGet
}

$resumeOnFailedSystemInstall = $true
$global:winget = Resolve-WinGet

if ($winget) {

	Write-Host ">>> WinGet is already installed"
	Write-Host "- Path: $winget"
	Write-Host "- Version: $(Invoke-CommandLine -Command $winget -Arguments '-v' -Silent | Select-Object -ExpandProperty Output)"

} else {

	try
	{
		if (Test-IsPacker) {

			# invoke the script as SYSTEM to ensure the WinGet installation is available to all users
			$process = Invoke-CommandLine -Command "powershell" -Arguments "-NoLogo -Mta -ExecutionPolicy $(Get-ExecutionPolicy) -File `"$($MyInvocation.MyCommand.Path)`"" -AsSystem 
			$process.Output | Write-Host

			if ($process.ExitCode -eq 0) {
				# retrieve the winget path 
				$global:winget = Resolve-WinGet
			} elseif (-not $resumeOnFailedSystemInstall) {
				# something went wrong - throw an exception to stop the script 
				throw "WinGet installation failed as SYSTEM with exit code $($process.ExitCode)"
			}
		}

		if (-not $global:winget) {

			Invoke-ScriptSection -Title "Installing WinGet Package Manager - $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ScriptBlock {

				# ensure all required services are running
				Start-Services

				# install the WinGet package manager and assign the returned path to the global variable for further processing
				$global:winget = Install-WinGet -Retries 1 -RetryDelay 60

			}
		}
	}
	catch {

		Invoke-ScriptSection -Title "Dump Context Information - $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ScriptBlock {
			
			Write-Host ">>> Appx Packages for All Users" 
			Get-AppxPackage 'Microsoft.VCLibs.140.00.UWPDesktop' -AllUsers -ErrorAction SilentlyContinue | Format-List 
		}

		throw # re-throw the exception to stop the script
	}
}

if ($global:winget) {

	Write-Host ">>> WinGet is now installed"
	Write-Host "- Path: $winget"
	Write-Host "- Version: $(Invoke-CommandLine -Command $global:winget -Arguments '-v' -Silent | Select-Object -ExpandProperty Output)"

	if (Test-IsPacker -or Test-IsSystem) {

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
} 