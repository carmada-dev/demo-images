$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

$dockerKey = Get-ChildItem 'HKLM:\SOFTWARE\Docker Inc.\Docker' -ErrorAction SilentlyContinue | Select-Object -Last 1
$dockerAppPath = $dockerKey | Get-ItemPropertyValue -Name AppPath -ErrorAction SilentlyContinue
$dockerBinPath = $dockerKey | Get-ItemPropertyValue -Name BinPath -ErrorAction SilentlyContinue

$docker = Join-Path $dockerBinPath 'docker.exe' -ErrorAction SilentlyContinue
$dockerDesktop = Join-Path $dockerAppPath 'docker desktop.exe' -ErrorAction SilentlyContinue
$dockerDesktopSettings = Get-ChildItem (Join-Path $env:APPDATA 'Docker') -Filter 'settings-store.json' -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Fullname

if (-not $docker) {
    Write-Host ">>> Not applicable: Docker not installed"
    exit 0
} elseif (-not $dockerDesktop) {
    Write-Host ">>> Not applicable: Docker Desktop not installed"
    exit 0
} elseif (Test-IsPacker) {
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

        if ($dockerDesktopSettings) {

            $dockerDesktopSettingsJson = Get-Content -Path $dockerDesktopSettings -Raw | ConvertFrom-Json
            $dockerDesktopSettingsJson.AutoStart = $true
            $dockerDesktopSettingsJson.DisplayedOnboarding = $true
        
            $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
            $dockerDesktopSettingsContent = $dockerDesktopSettingsJson | ConvertTo-Json -Depth 100
        
            Write-Host ">>> Patching Docker Desktop config ..."
            [System.IO.File]::WriteAllLines($dockerDesktopSettings, $dockerDesktopSettingsContent, $utf8NoBomEncoding)
            $dockerDesktopSettingsContent | Write-Host    
        }

        $dockerDesktopService = Get-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue
        if ($dockerDesktopService) {

            Write-Host ">>> Setting Docker Desktop Service to start automatically ..."
            $dockerDesktopService | Set-Service -StartupType 'Automatic' -ErrorAction SilentlyContinue | Out-Null
        
            Write-Host ">>> Starting Docker Desktop Service ..."
            $dockerDesktopService | Start-Service -ErrorAction SilentlyContinue | Out-Null
        }

        Write-Host ">>> Starting Docker Desktop ..."
        Invoke-CommandLine -Command 'start' -Arguments "`"`" `"$dockerDesktop`"" | Select-Object -ExpandProperty Output | Write-Host

        $timeout = (get-date).AddMinutes(5)

        while ($true) {

            $result = Invoke-CommandLine -Command $docker -Arguments 'info' -ErrorAction SilentlyContinue 

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
}