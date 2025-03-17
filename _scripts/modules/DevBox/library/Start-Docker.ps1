function  Start-DockerDesktop() {
    
    $dockerKey = Get-ChildItem 'HKLM:\SOFTWARE\Docker Inc.\Docker' -ErrorAction SilentlyContinue | Select-Object -Last 1
    $dockerDesktop = Join-Path ($dockerKey | Get-ItemPropertyValue -Name AppPath -ErrorAction SilentlyContinue) 'docker desktop.exe' -ErrorAction SilentlyContinue

    if (Test-Path $dockerDesktop -ErrorAction SilentlyContinue) {

        Write-Host ">>> Starting Docker Desktop ..."
        Invoke-CommandLine -Command $dockerDesktop -NoWait
        
        $timeout = (get-date).AddMinutes(5)
        Start-Sleep -Seconds 10 # give it a moment to start

        while ($true) {

            $docker = Get-Command 'docker' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path
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

        return $true

    } else {

        Write-Host "!!! Docker Desktop is not available"
        return $false
    }
}

function Start-Podman() {

    Write-Host ">>> Starting Podman ..."
    return $false
}

function Start-Docker() {

    param (
        [Parameter(Mandatory=$false)]
        [ValidateSet('DockerDesktop', 'Podman')]
        [string] $Tool,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Linux', 'Windows')]
        [string] $Container = 'Linux'
    )

    $docker = Get-Command 'docker' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path
    if (-not $docker) { throw "Could not find docker CLI" }

    $result = Invoke-CommandLine -Command $docker -Arguments 'info' -Silent -ErrorAction SilentlyContinue
    $started = ($result.ExitCode -eq 0)

    if  ($started) {

        Write-Host ">>> Docker is already running"

    } else {

        switch ($Tool) {
            'DockerDesktop' { 
                $started = Start-DockerDesktop 
            }
            'Podman' { 
                $started = Start-Podman 
            }
            default { 
                $started = (Start-Docker -Tool DockerDesktop -Container $Container) -or (Start-Docker -Tool Podman -Container $Container)
            }
        }
    }

    if ($started -and $Container) {

        if ($Tool -eq 'DockerDesktop') {

            $dockerDesktopUseWindowsContainers = $false 

            $dockerDesktopSettings = Get-ChildItem -Path (Join-Path $env:APPDATA 'Docker') -Include 'settings-store.json' -Include 'settings.json' -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
            if (-not $dockerDesktopSettings) { throw "Could not find Docker Desktop settings file" }
        
            Write-Host ">>> Loading Docker Desktop settings file: $dockerDesktopSettings"
            $dockerDesktopSettingsJson = Get-Content -Path $dockerDesktopSettings -Raw | ConvertFrom-Json

            try {
                $dockerDesktopUseWindowsContainers = [bool] ($dockerDesktopSettingsJson.UseWindowsContainers)
            } catch {
                $dockerDesktopUseWindowsContainers = $false
            } 

            if ((-not $dockerDesktopUseWindowsContainers -and $Container -eq 'Windows') -or ($dockerDesktopUseWindowsContainers -and $Container -eq 'Linux')) {

                $dockerKey = Get-ChildItem 'HKLM:\SOFTWARE\Docker Inc.\Docker' -ErrorAction SilentlyContinue | Select-Object -Last 1
                $dockerCli = Join-Path ($dockerKey | Get-ItemPropertyValue -Name AppPath -ErrorAction SilentlyContinue) 'dockercli.exe' -ErrorAction SilentlyContinue

                if (-not $dockerCli) { throw "Could not find docker CLI" }

                Write-Host ">>> Changing Docker Desktop to use $Container containers"
                Invoke-CommandLine -Command $dockerCli -Arguments '-SwitchDaemon' | select-Object -ExpandProperty Output | Write-Host
            }

        } elseif ($Container -ne 'Linux') {

            throw "$Tool does not support container types other than Linux"
        }
        
    }

    return $started
}

Export-ModuleMember -Function Start-Docker