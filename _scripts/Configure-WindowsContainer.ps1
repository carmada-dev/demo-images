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

if (Test-IsPacker) {
        
    Invoke-ScriptSection -Title "Configure Docker Users" -ScriptBlock {

        $dockerUsersMembers = Get-LocalGroupMember -Group "docker-users" -ErrorAction SilentlyContinue
        if ($dockerUsersMembers -and -not ($dockerUsersMembers -like "NT AUTHORITY\Authenticated Users")) {
            Write-Host ">>> Adding 'Authenticated Users' to docker-users group ..."
            Add-LocalGroupMember -Group "docker-users" -Member "NT AUTHORITY\Authenticated Users"
        }

    } 
}

Invoke-ScriptSection -Title "Starting Docker Desktop" -ScriptBlock {

    Start-Docker -Tool 'DockerDesktop'
}

Invoke-ScriptSection -Title "Configure Docker Desktop" -ScriptBlock {

    $dockerDesktopSettings = Get-ChildItem -Path (Join-Path $env:APPDATA 'Docker') -Include 'settings-store.json' -Include 'settings.json' -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if (-not $dockerDesktopSettings) { throw "Could not find Docker Desktop settings file" }

    Write-Host ">>> Loading Docker Desktop settings file: $dockerDesktopSettings"
    $dockerDesktopSettingsJson = Get-Content -Path $dockerDesktopSettings -Raw | ConvertFrom-Json

    if ($dockerDesktopSettingsJson | Get-Member -Name 'AutoStart' -ErrorAction SilentlyContinue) {
        Write-Host "- Updating AutoStart property (true) in Docker Desktop settings file"
        $dockerDesktopSettingsJson.AutoStart = $true
    } else {
        Write-Host "- Adding AutoStart property (true) to Docker Desktop settings file"
        $dockerDesktopSettingsJson | Add-Member -MemberType NoteProperty -Name 'AutoStart' -Value $true
    }

    if ($dockerDesktopSettingsJson | Get-Member -Name 'DisplayedOnboarding' -ErrorAction SilentlyContinue) {
        Write-Host "- Updating DisplayedOnboarding property (true) in Docker Desktop settings file"
        $dockerDesktopSettingsJson.DisplayedOnboarding = $true
    } else {
        Write-Host "- Adding DisplayedOnboarding property (true) to Docker Desktop settings file"
        $dockerDesktopSettingsJson | Add-Member -MemberType NoteProperty -Name 'DisplayedOnboarding' -Value $true
    }

    if ($dockerDesktopSettingsJson | Get-Member -Name 'UseWindowsContainers' -ErrorAction SilentlyContinue) {
        Write-Host "- Updating UseWindowsContainers property (false) in Docker Desktop settings file"
        $dockerDesktopSettingsJson.UseWindowsContainers = $false
    } else {
        Write-Host "- Adding UseWindowsContainers property (false) to Docker Desktop settings file"
        $dockerDesktopSettingsJson | Add-Member -MemberType NoteProperty -Name 'UseWindowsContainers' -Value $false
    }

    Write-Host ">>> Updating Docker Desktop settings file: $dockerDesktopSettings"
    $dockerDesktopSettingsJson | ConvertTo-Json -Depth 100 | Set-Utf8Content -Path $dockerDesktopSettings -PassThru | Write-Host    
}

