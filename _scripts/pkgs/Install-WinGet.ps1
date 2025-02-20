param (
	[Parameter(Mandatory = $false)]
	[switch] $ScheduledTask
)

if (([System.Threading.Thread]::CurrentThread.ApartmentState) -ne 'MTA') {
	# re-launch the script in a new thread with the MTA apartment state to avoid any issues with COM objects
	powershell.exe -NoLogo -Mta -ExecutionPolicy $(Get-ExecutionPolicy) -File $($MyInvocation.MyCommand.Path)
	exit $LastExitCode
}

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Install-WinGet.ps1'
} elseif ($ScheduledTask) {
    Write-Host ">>> Initializing transcript (Scheduled Task)"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".task.log")) -Force - -IncludeInvocationHeader; 
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

function Get-ActivityIdFromException {
    param (
        [Parameter(Mandatory = $true)]
        [System.Exception]$Exception
    )

    if ($Exception -is [System.AggregateException]) {
        foreach ($innerException in $Exception.InnerExceptions) {
            $activityId = Get-ActivityIdFromException -Exception $innerException
            if ($activityId) { return $activityId }
        }
    } else {
        while ($Exception) {
            if ($Exception.PSObject.Properties['ActivityId']) { return $Exception.ActivityId }
            $Exception = $Exception.InnerException
        }
    }

    return $null  # Return null if no ActivityId is found
}

function Start-Services {

	Write-Host ">>> Starting Services"
	@( 'EventLog', 'AppXSVC', 'ClipSVC', 'StateRepository', 'wuauserv', 'InstallService' ) | ForEach-Object {
	
		$service = Get-Service -Name $_ -ErrorAction SilentlyContinue
		if ($service) {
	
			if ($service.Status -ne 'Running') {
				Write-Host "- Starting Service $($service.DisplayName) ($($service.Name))"
				Start-Service -Name $service.Name 
			} else {
				Write-Host "- Service $($service.DisplayName) ($($service.Name)) is already running"
			}
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
		$timestamp = Get-Date

		try {

			if (-not (Get-PackageProvider -Name NuGet -ListAvailable)) {

				# we should never get here, as the NuGet provider install is part of the 
				# Initialize-VM script that runs right after the Packer VM is created
				
				Write-Host ">>> Installing NuGet Package Provider"
				Install-PackageProvider -Name NuGet -Force | Out-Null
			}

			if (-not (Get-Module -Name Microsoft.Winget.Client -ListAvailable)) {

				try {

					Write-Host ">>> Trust the PSGallery repository temporarily"
					Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

					Write-Host ">>> Installing Microsoft.Winget.Client"
					Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Force | Out-Null
					
				} finally {

					Write-Host ">>> Reset the PSGallery repository to its original state"
					Set-PSRepository -Name "PSGallery" -InstallationPolicy Untrusted
				}
			}
			
			Write-Host ">>> Repairing WinGet Package Manager"
			Repair-WinGetPackageManager -Verbose -AllUsers:$(Test-IsElevated) 

			break # installation succeeded - exit the loop
		}
		catch {

			# by default we dump the original exception here - regardless of the retry count
			Write-Warning "!!! WinGet installation failed: $($_.Exception.Message)"
			
			if (Test-IsElevated) {
				
				$activityId = Get-ActivityIdFromException -Exception $_.Exception
				$dumpByTimestamp = (-not $activityId)

				Start-Sleep -Seconds 60 # wait a bit before dumping the logs - the event log might not be ready yet

				if ($activityId) {

					$eventRecords = Get-AppxLog -ActivityId $activityId 
					
					if ($eventRecords) {

						Write-Host '----------------------------------------------------------------------------------------------------------'
						Write-Host ">>> Dump Appx Logs for Activity ID: $activityId"
						Write-Host '----------------------------------------------------------------------------------------------------------'
						
						$eventRecords | Format-Table -AutoSize 

					} else {
						
						# fallback to the timestamp based dump if no records are found by the activity ID
						$dumpByTimestamp = $true
					}
				}

				if ($dumpByTimestamp) {

					Write-Host '----------------------------------------------------------------------------------------------------------'
					Write-Host ">>> Dump Event Log 'Microsoft-Windows-AppXDeployment/Operational' since: $timestamp"
					Write-Host '----------------------------------------------------------------------------------------------------------'

					Get-WinEvent -FilterHashtable @{
						LogName = 'Microsoft-Windows-AppXDeployment/Operational'
						StartTime = $timestamp
					} -ErrorAction SilentlyContinue | Format-Table -AutoSize
				}
			}

			# maximung retries exhausted - lets blow it up
			if ($retry -le $Retries) { 
				
				Write-Host '=========================================================================================================='
				Write-Host ">>> Retry: $retry / $Retries - Delay: $RetryDelay seconds"
				Write-Host '=========================================================================================================='

				# wait for the retry delay before trying again
				Start-Sleep -Seconds $RetryDelay

				# continue with the next iteration
				continue
			}

			throw # re-throw the exception to stop the script
		}
	}

	return Resolve-WinGet
}

$elevateInstallationAsSystem = $false
$resumeOnFailedSystemInstall = $true

$global:winget = Resolve-WinGet

if ($winget) {

	Write-Host ">>> WinGet is already installed"
	Write-Host "- Path: $winget"
	Write-Host "- Version: $(Invoke-CommandLine -Command $winget -Arguments '-v' -Silent | Select-Object -ExpandProperty Output)"

} else {

	try
	{
		if ($elevateInstallationAsSystem -and (Test-IsPacker) -and (-not $ScheduledTask)) {

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

				try {

					# install the WinGet package manager and assign the returned path to the global variable for further processing
					$global:winget = Install-WinGet -Retries 0 -RetryDelay 60
				
				} catch {

					$taskName = 'Install WinGet'
					$taskPath = '\'

					if (Test-IsPacker) {

						$taskAction = New-ScheduledTaskAction -Execute 'PowerShell' -Argument "-NoLogo -NonInteractive -WindowStyle Hidden -File $($MyInvocation.MyCommand.Path) -ScheduledTask"
						$taskPrincipal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Highest
						$taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew 
						$taskTriggers = @( New-ScheduledTaskTrigger -AtLogOn -RandomDelay (New-TimeSpan -Minutes 5) )
				
						Register-ScheduledTask -Force -TaskName $taskName -TaskPath $taskPath -Action $taskAction -Trigger $taskTriggers -Settings $taskSettings -Principal $taskPrincipal | Out-Null
					}

					$task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue

					if ($task) {

						Write-Host '=========================================================================================================='
						Write-Host ">>> Using Scheduled Task to install WinGet Package Manager"
						Write-Host '=========================================================================================================='

						Write-Host ">>> Executing task $taskName ..."
						Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
						
						$timeout = (Get-Date).AddMinutes(30) # wait for the task to finish for a
						$running = $false
	
						while ($true) {
						
							if ($timeout -lt (Get-Date)) { Throw "Timeout waiting for $taskName to finish" }
							$task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
							
							if (-not($task)) { 
								
								throw "Scheduled task $taskName does not exist anymore"
							
							} elseif ($running) {
	
								if ($task.State -ne 'Running') { break }
	
								Write-Host ">>> Waiting for $taskName to finish ..."
								Start-Sleep -Seconds 5
	
							} else {
	
								$running = $running -or ($task.State -eq 'Running')
								if ($running) { Write-Host ">>> Task $taskName starts running ..." }
							}
						}
						
						Write-Host ">>> Executing task $taskName completed"
						
						Write-Host '----------------------------------------------------------------------------------------------------------'
						Write-Host ">>> Dump Event Log 'Microsoft-Windows-AppXDeployment/Operational' since: $timestamp"
						Write-Host '----------------------------------------------------------------------------------------------------------'

						Get-Content -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".task.log")) | Write-Host

					} else {

						# re-throw the exception to stop the script
						throw
					}
				}
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