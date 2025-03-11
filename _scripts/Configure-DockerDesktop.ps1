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

function Start-DockerDesktop() {

    $dockerKey = Get-ChildItem 'HKLM:\SOFTWARE\Docker Inc.\Docker' -ErrorAction SilentlyContinue | Select-Object -Last 1
    $dockerDesktop = Join-Path ($dockerKey | Get-ItemPropertyValue -Name AppPath -ErrorAction SilentlyContinue) 'docker desktop.exe' -ErrorAction SilentlyContinue

    # if docker desktop could not be found, blow it up
    if (-not (Test-Path $dockerDesktop -ErrorAction SilentlyContinue)) { throw "Docker Desktop not installed"}

    Write-Host ">>> Starting Docker Desktop ..."
    Invoke-CommandLine -Command $dockerDesktop -NoWait
    
    $timeout = (get-date).AddMinutes(5)
    Start-Sleep -Seconds 10 # give it a moment to start

    while ($true) {

        $result = Invoke-CommandLine -Command $docker -Arguments 'info' -Silent -ErrorAction SilentlyContinue 

        if ($result.ExitCode -eq 0) { 
            Write-Host ">>> Docker Desktop is running"
            break 
        } elseif ((Get-Date) -le $timeout) { 
            Write-Host ">>> Waiting for Docker Desktop to start"
            Start-Sleep -Seconds 5
        } else { 
            # we reach our timeout - blow it up
            throw "Docker Desktop failed to start"                
        }
    } 
}

Invoke-ScriptSection -Title "Configure Docker Desktop" -ScriptBlock {

    if (Test-IsPacker) {
        
        $dockerUsersMembers = Get-LocalGroupMember -Group "docker-users" -ErrorAction SilentlyContinue
        if ($dockerUsersMembers -and -not ($dockerUsersMembers -like "NT AUTHORITY\Authenticated Users")) {

            Write-Host ">>> Adding 'Authenticated Users' to docker-users group ..."
            Add-LocalGroupMember -Group "docker-users" -Member "NT AUTHORITY\Authenticated Users"
        }

    } 

    $dockerDesktopService = Get-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue
    if ($dockerDesktopService) {

        Write-Host ">>> Setting Docker Desktop Service to start automatically ..."
        $dockerDesktopService | Set-Service -StartupType 'Automatic' -ErrorAction SilentlyContinue | Out-Null
    
        Write-Host ">>> Starting Docker Desktop Service ..."
        $dockerDesktopService | Start-Service -ErrorAction SilentlyContinue | Out-Null
    }

    $dockerDesktopSettings = Join-Path $env:APPDATA 'Docker\settings-store.json'

    # if the docker desktop settings file does not exist, start docker desktop to create it
    if (-not (Test-Path $dockerDesktopSettings -ErrorAction SilentlyContinue)) { Start-DockerDesktop }

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
    Start-DockerDesktop
}