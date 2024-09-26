Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

if (Test-IsPacker) {

	Invoke-ScriptSection -Title "Installing BGInfo" -ScriptBlock {

		$bgInfoConfig = Get-ChildItem -Path $env:DEVBOX_HOME -Filter 'devbox.bgi' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Fullname
		if ($bgInfoConfig) {

			Write-Host ">>> Installing BGInfo ..."
			$bgInfoArchive = Invoke-FileDownload -Url 'https://download.sysinternals.com/files/BGInfo.zip' -Expand
			$bgInfoHome = $bgInfoArchive | Move-Item -Destination $env:ProgramFiles -Force -PassThru | Select-Object -ExpandProperty Fullname
			$bgInfoExe = Join-Path $bgInfoHome "Bginfo$(&{ if ([Environment]::Is64BitOperatingSystem) { '64' } else { '' } }).exe"
			$bgInfoConfig = $bgInfoConfig | Move-item -Destination (Join-Path $bgInfoHome (Split-Path $bgInfoConfig -Leaf)) -Force -PassThru | Select-Object -ExpandProperty Fullname
			$bgInfoArguments = "`"$bgInfoConfig`" /SILENT /NOLICPROMPT /TIMER:0"

			Write-Host ">>> Updating BGInfo ACLs ..."
            $bgInfoUSR = New-Object -TypeName 'System.Security.Principal.SecurityIdentifier' -ArgumentList @([System.Security.Principal.WellKnownSidType]::AuthenticatedUserSid, $null)
			$bgInfoACR = New-Object System.Security.AccessControl.FileSystemAccessRule($bgInfoUSR, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
			$bgInfoACL = Get-Acl -Path $bgInfoHome
			$bgInfoACL.SetAccessRule($bgInfoACR)
			$bgInfoACL | Set-Acl -Path $bgInfoHome

			Write-Host ">>> Create BGInfo Shortcut ..."
			New-Shortcut -Path (Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) -ChildPath "BGInfo.lnk") -Target $bgInfoExe -Arguments $bgInfoArguments

			Write-Host ">>> Register BGInfo Scheduled Task ..."
			$taskAction = New-ScheduledTaskAction -Execute $bgInfoExe -Argument $bgInfoArguments
			$taskPrincipal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Highest
			$taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -Priority 0 -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -DontStopIfGoingOnBatteries -DontStopOnIdleEnd
			$taskTriggers = @( New-ScheduledTaskTrigger -AtLogOn )
			Register-ScheduledTask -Force -TaskName BackgroundInfo -TaskPath '\' -Action $taskAction -Trigger $taskTriggers -Settings $taskSettings -Principal $taskPrincipal | Out-Null

		} else {

			Write-Host ">>> Could not find 'devbox.bgi' file in folder '$($env:DEVBOX_HOME)'"
		}
	}
}