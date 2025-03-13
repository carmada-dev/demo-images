$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Configure-DockerDesktop.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

# ==============================================================================

Invoke-ScriptSection -Title "Configure Docker Desktop" -ScriptBlock {

    $configureDockerDesktopServiceScriptBlock = {
        $dockerDesktopService = Get-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue
        if ($dockerDesktopService) {
            $dockerDesktopService | Set-Service -StartupType 'Automatic' -ErrorAction SilentlyContinue | Out-Null
            $dockerDesktopService | Start-Service -ErrorAction SilentlyContinue | Out-Null
        }
    }

    if (Test-IsPacker) {
        
        $dockerUsersMembers = Get-LocalGroupMember -Group "docker-users" -ErrorAction SilentlyContinue
        if ($dockerUsersMembers -and -not ($dockerUsersMembers -like "NT AUTHORITY\Authenticated Users")) {
            Write-Host ">>> Adding 'Authenticated Users' to docker-users group ..."
            Add-LocalGroupMember -Group "docker-users" -Member "NT AUTHORITY\Authenticated Users"
        }

        Write-Host ">>> Registering Docker Desktop Service Configuration task ..."
        $taskScript = $configureDockerDesktopServiceScriptBlock | Convert-ScriptBlockToString -EncodeBase64
        $taskAction = New-ScheduledTaskAction -Execute 'PowerShell' -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $taskScript"
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -Priority 0 -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -DontStopIfGoingOnBatteries -DontStopOnIdleEnd
        $taskTriggers = @( New-ScheduledTaskTrigger -AtLogOn )
        $task = Register-ScheduledTask -Force -TaskName 'Configure-DockerDesktopService' -TaskPath '\' -Action $taskAction -Trigger $taskTriggers -Settings $taskSettings -Principal $taskPrincipal

        Write-Host ">>> Triggering Docker Desktop Service Configuration task ..."
        $task | Start-ScheduledTask -ErrorAction Stop | Out-Null
        $task | Wait-ScheduledTask 
    } 

    $dockerDesktopSettings = Join-Path $env:APPDATA 'Docker\settings-store.json'

    # if the docker desktop settings file does not exist, start docker desktop to create it
    if (-not (Test-Path $dockerDesktopSettings -ErrorAction SilentlyContinue)) { Start-Docker -Tool 'DockerDesktop' }

    try {

        Write-Host ">>> Loading Docker Desktop settings file: $dockerDesktopSettings"
        $dockerDesktopSettingsJson = Get-Content -Path $dockerDesktopSettings -Raw | ConvertFrom-Json

        if ($dockerDesktopSettingsJson | Get-Member -Name 'AutoStart' -ErrorAction SilentlyContinue) {
            $dockerDesktopSettingsJson.AutoStart = $true
        } else {
            $dockerDesktopSettingsJson | Add-Member -MemberType NoteProperty -Name 'AutoStart' -Value $true
        }

        if ($dockerDesktopSettingsJson | Get-Member -Name 'DisplayedOnboarding' -ErrorAction SilentlyContinue) {
            $dockerDesktopSettingsJson.DisplayedOnboarding = $true
        } else {
            $dockerDesktopSettingsJson | Add-Member -MemberType NoteProperty -Name 'DisplayedOnboarding' -Value $true
        }

        Write-Host ">>> Updating Docker Desktop settings file: $dockerDesktopSettings"
        $dockerDesktopSettingsJson | ConvertTo-Json -Depth 100 | Set-Utf8Content -Path $dockerDesktopSettings -PassThru | Write-Host    
    }
    finally {
        
        Write-Host ">>> Kill all existing Docker Desktop processes ..."
        Get-Process -Name 'Docker Desktop' | Stop-Process -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

Invoke-ScriptSection -Title "Starting Docker Desktop" -ScriptBlock {

    # start docker desktop
    Start-Docker -Tool 'DockerDesktop'
}