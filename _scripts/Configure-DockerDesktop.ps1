$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup -Path $MyInvocation.MyCommand.Path -Name 'Configure-DockerDesktop.ps1'
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

    $dockerDesktopSettings = Join-Path $env:APPDATA 'Docker\settings-store.json'
    if (Test-Path -Path $dockerDesktopSettings -PathType Leaf) {

        $dockerDesktopSettingsJson = Get-Content -Path $dockerDesktopSettings -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        $dockerDesktopSettingsHash = Get-FileHash -Path $dockerDesktopSettings -ErrorAction SilentlyContinue

        if ($dockerDesktopSettingsJson) { 

            Write-Host ">>> Configuring Docker Desktop ..."
            $dockerDesktopSettingsJson | Add-Member -MemberType NoteProperty -Name 'AutoStart' -Value $true -Force | Out-Null
            $dockerDesktopSettingsJson | Add-Member -MemberType NoteProperty -Name 'DisplayedOnboarding' -Value $true -Force | Out-Null
            $dockerDesktopSettingsJson | ConvertTo-Json -Depth 100 | Set-Utf8Content -Path $dockerDesktopSettings -Force -PassThru -ErrorAction SilentlyContinue | Write-Host

            if ($dockerDesktopSettingsHash -ne (Get-FileHash -Path $dockerDesktopSettings -ErrorAction SilentlyContinue)) {

                Write-Host ">>> Restarting Docker Desktop ..."
                do {
                    
                    $dockerProcesses = Get-Process -Name *Docker* | Where-Object { $_.SessionId -gt 0 } | Stop-Process -Force -Passthru -ErrorAction SilentlyContinue
                    if ($dockerProcesses.Count -gt 0) { Start-Sleep -Seconds 5 } # as long as there was a process to stop we give it a few seconds to finish

                } until ($dockerProcesses.Count -eq 0)

                Start-Docker -Tool 'DockerDesktop'
            }
        }
    }
}

