$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

function Convert-ScriptBlockToCommandString() {

    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [scriptblock] $ScriptBlock
    )

    # Convert the script block to a string
    $scriptString = $ScriptBlock.ToString()

    # Remove block comments (starting with <# and ending with #>)
    $scriptString = $scriptString -replace '(?s)<#.*?#>', ''

    # Remove single-line comments (starting with #)
    $scriptString = $scriptString -replace '(?m)^\s*#.*$', ''

    # Remove indentation
    $scriptString = $scriptString -replace '(?m)^\s*', ''

    # Remove emtpy lines
    $scriptString = $scriptString -replace '(?m)^\r\n', ''

    return $scriptString
}

$offlineDirectory = Join-Path $env:DEVBOX_HOME 'offline\winget'

if (Test-IsPacker) {

	$taskFullname = '\Install-WinGet'
	$taskName = $taskFullname | Split-Path -Leaf
	$taskPath = $taskFullname | Split-Path -Parent
	$taskLog = Join-Path $env:TEMP ("$taskFullname.log" -replace ' ', '_')

	if (-not (Test-Path -Path $offlineDirectory -PathType Container)) {

		Invoke-ScriptSection -Title "Downloading WinGet Package Manager" -ScriptBlock {

			Write-Host ">>> Creating WinGet Offline Directory"
			New-Item -Path $offlineDirectory -ItemType Directory -Force | Out-Null

			$url = Get-GitHubLatestReleaseDownloadUrl -Organization 'microsoft' -Repository 'winget-cli' -Asset 'msixbundle'
			$path = Invoke-FileDownload -Url $url -Name ([IO.Path]::GetFileName($url)) -Retries 5
			$destination = Join-Path $offlineDirectory ([IO.Path]::GetFileName($path))

			Write-Host ">>> Moving $path > $destination"
			Move-Item -Path $path -Destination $destination -Force | Out-Null

			$url = "https://cdn.winget.microsoft.com/cache/source.msix"
			$path = Invoke-FileDownload -Url $url -Name ([IO.Path]::GetFileName($url)) -Retries 5
			$destination = Join-Path $offlineDirectory ([IO.Path]::GetFileName($path))

			Write-Host ">>> Moving $path > $destination"
			Move-Item -Path $path -Destination $destination -Force | Out-Null

			$url = Get-GitHubLatestReleaseDownloadUrl -Organization 'microsoft' -Repository 'winget-cli' -Asset 'DesktopAppInstaller_Dependencies.zip'
			$path = Join-Path (Invoke-FileDownload -Url $url -Expand -Retries 5) "$(&{ if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' } })"
			
			Get-ChildItem -Path $path -Filter '*.*' | ForEach-Object {
				$destination = Join-Path $offlineDirectory ([IO.Path]::GetFileName($_.FullName))
				Write-Host ">>> Moving $($_.FullName) > $destination"
				Move-Item -Path $_.FullName -Destination $destination -Force | Out-Null
			}
		}
	} 

	Invoke-ScriptSection "Register Scheduled Task $taskFullname" -ScriptBlock {

		$taskScript = ({

			# if winget is already installed - exit
			if (Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source) { exit 0 }

			# ensure task log directory exists
			New-Item -Path (Split-Path '[TASKLOG]' -Parent) -ItemType Directory -Force | Out-Null

			# start task log using transcript
			Start-Transcript -Path '[TASKLOG]' -Force

			if (Test-Path '[WINGETOFFLINE]' -PathType Container) {

				Get-ChildItem -Path '[WINGETOFFLINE]' -Filter '*.appx' | Select-Object -ExpandProperty FullName | ForEach-Object {
					Write-Host ">>> Installing WinGet Dependency: $_"
					Add-AppxPackage -Path $_ -ForceTargetApplicationShutdown -ErrorAction SilentlyContinue
				}
			
				Get-ChildItem -Path '[WINGETOFFLINE]' -Filter '*.msixbundle' | Select-Object -ExpandProperty FullName -First 1 | ForEach-Object {
					Write-Host ">>> Installing WinGet Package Manager: $_"
					Add-AppxPackage -Path $_ -ForceTargetApplicationShutdown -ErrorAction SilentlyContinue
				}
			
				Get-ChildItem -Path '[WINGETOFFLINE]' -Filter '*.msix' | Select-Object -ExpandProperty FullName -First 1 | ForEach-Object {
					Write-Host ">>> Installing WinGet Package Source: $_"
					Add-AppxPackage -Path $_ -ForceTargetApplicationShutdown -ErrorAction SilentlyContinue
				}

				# if winget is already installed - exit
				if (Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source) { exit 0 }
			}

			Write-Host ">>> Installing Microsoft.WinGet.Client PowerShell module"
			Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery 
			
			Write-Host ">>> Repairing WinGet Package Manager"
			Repair-WinGetPackageManager -Verbose

		} | Convert-ScriptBlockToCommandString) -replace ('\[TASKLOG\]', $taskLog) -replace ('\[WINGETOFFLINE\]', $offlineDirectory)
		
		$taskScript | Write-Host
		$taskAction = New-ScheduledTaskAction -Execute 'PowerShell' -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $([Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($taskScript))))"
		$taskPrincipal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Highest
		$taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew 
		$taskTriggers = @( New-ScheduledTaskTrigger -AtLogOn )
		
		Register-ScheduledTask -Force -TaskName $taskName -TaskPath $taskPath -Action $taskAction -Trigger $taskTriggers -Settings $taskSettings -Principal $taskPrincipal		
	}

	Invoke-ScriptSection "Run Scheduled Task $taskFullname" -ScriptBlock {

		$task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue	
		if (-not $task) { throw "Scheduled task $taskFullname does not exist" }

		Write-Host ">>> Executing task $taskFullname ..."
		$task | Start-ScheduledTask -ErrorAction Stop
		
		$timeout = (Get-Date).AddMinutes(5)
		$running = $false
		$exitCode = 0

		while ($true) {
		
			# check if timeout is reached - if so, blow it up				
			if ($timeout -le (Get-Date)) { Throw "Timeout waiting for $taskFullname to finish" }

			$task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
			
			# check if task is still available - if not, blow it up 
			if (-not($task)) { throw "Scheduled task $taskFullname does not exist anymore" }
			
			if ($running) {

				if ($task.State -ne 'Running') { 
					$exitCode = $task | Get-ScheduledTaskInfo | Select-Object -ExpandProperty LastTaskResult
					Write-Host ">>> Task $taskFullname finished with exit code $exitCode"
					break # exit the loop
				}

				Write-Host ">>> Waiting for $taskFullname to finish ..."
				Start-Sleep -Seconds 5 # give the task some time to finish

			} else {

				$running = $running -or ($task.State -eq 'Running') # determine if we are in running state
				if ($running) { 
					Write-Host ">>> Task $taskFullname starts running ..." 
				} else {
					Write-Host ">>> Task $taskFullname is in state $($task.State) ..."
				}
			}
		}

		if ($task) {
			Write-Host ">>> Unregister Scheduled Task $taskFullname"
			$task | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
		}

		if (Test-Path -Path $taskLog -PathType Leaf) {
			Write-Host '----------------------------------------------------------------------------------------------------------'
			Write-Host ">>> Scheduled Task Transcript: $taskLog"
			Write-Host '----------------------------------------------------------------------------------------------------------'
			Get-Content -Path $taskLog | Write-Host
		} 

		# something went wrong - lets blow it up
		if ($exitCode -ne 0) { throw "WinGet installation using Scheduled Task $taskFullname failed with exit code $exitCode" } 
			
		$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
		
		# winget is still not available - lets blow it
		if (-not $winget) { throw "WinGet is not available - check logs" }

		Write-Host ">>> WinGet is available now: $winget"
	}

} else {

	Invoke-ScriptSection "Installing WinGet Package Manager" -ScriptBlock {

		if (Test-Path $offlineDirectory -PathType Container) {

			Get-ChildItem -Path $offlineDirectory -Filter '*.appx' | Select-Object -ExpandProperty FullName | ForEach-Object {
				Write-Host ">>> Installing WinGet Dependency: $_"
				Add-AppxPackage -Path $_ -ForceTargetApplicationShutdown -ErrorAction SilentlyContinue
			}
		
			Get-ChildItem -Path $offlineDirectory -Filter '*.msixbundle' | Select-Object -ExpandProperty FullName -First 1 | ForEach-Object {
				Write-Host ">>> Installing WinGet Package Manager: $_"
				Add-AppxPackage -Path $_ -ForceTargetApplicationShutdown -ErrorAction SilentlyContinue
			}
		
			Get-ChildItem -Path $offlineDirectory -Filter '*.msix' | Select-Object -ExpandProperty FullName -First 1 | ForEach-Object {
				Write-Host ">>> Installing WinGet Package Source: $_"
				Add-AppxPackage -Path $_ -ForceTargetApplicationShutdown -ErrorAction SilentlyContinue
			}

			# if winget is already installed - exit
			if (Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source) { exit 0 }
		}

		Write-Host ">>> Installing Microsoft.WinGet.Client PowerShell module"
		Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery 
		
		Write-Host ">>> Repairing WinGet Package Manager"
		Repair-WinGetPackageManager -Verbose

		$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
		
		# winget is still not available - lets blow it
		if (-not $winget) { throw "WinGet is not available - check logs" }

		Write-Host ">>> WinGet is available now: $winget"
	}
}