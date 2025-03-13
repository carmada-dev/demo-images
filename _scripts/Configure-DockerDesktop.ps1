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

    if (Test-IsPacker) {
        
        $dockerUsersMembers = Get-LocalGroupMember -Group "docker-users" -ErrorAction SilentlyContinue
        if ($dockerUsersMembers -and -not ($dockerUsersMembers -like "NT AUTHORITY\Authenticated Users")) {
            Write-Host ">>> Adding 'Authenticated Users' to docker-users group ..."
            Add-LocalGroupMember -Group "docker-users" -Member "NT AUTHORITY\Authenticated Users"
        }

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
        while ($true) {
            $processes = Get-Process -Name 'Docker Desktop' | Stop-Process -Force -PassThru -ErrorAction SilentlyContinue
            if ($processes.Count -eq 0) { break } else { Start-Sleep -Seconds 5 }
        } 
    }
}

Invoke-ScriptSection -Title "Starting Docker Desktop" -ScriptBlock {

    # start docker desktop
    Start-Docker -Tool 'DockerDesktop'
}