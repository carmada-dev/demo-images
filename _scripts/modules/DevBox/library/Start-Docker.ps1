function Wait-DockerInfo() {

    param (
        [Parameter(Mandatory=$false)]
        [timespan] $Timeout = (New-TimeSpan -Minutes 5)
    )

    Write-Host ">>> Waiting for Docker CLI to be functional ..."
    $timeoutEnd = (Get-Date).Add($Timeout)

    while ($true) {

        $docker = Get-Command 'docker' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path
        $result = Invoke-CommandLine -Command $docker -Arguments 'info' -Silent -ErrorAction SilentlyContinue 

        if ($result.ExitCode -eq 0) { 
            Write-Host ">>> Docker CLI is now functional"
            break 
        } elseif ((Get-Date) -le $timeoutEnd) { 
            Write-Host ">>> Waiting for Docker CLI to be functional ..."
            Start-Sleep -Seconds 5
        } else { 
            # we reach our timeout - blow it up
            throw "Docker CLI did not become functional within $Timeout"                
        }
    } 
}

function  Start-DockerDesktop() {
    
    $dockerKey = Get-ChildItem 'HKLM:\SOFTWARE\Docker Inc.\Docker' -ErrorAction SilentlyContinue | Select-Object -Last 1
    $dockerDesktop = Join-Path ($dockerKey | Get-ItemPropertyValue -Name AppPath -ErrorAction SilentlyContinue) 'docker desktop.exe' -ErrorAction SilentlyContinue

    if (Test-Path $dockerDesktop -ErrorAction SilentlyContinue) {

        $dockerDesktopSettings = Join-Path $env:APPDATA 'Docker\settings-store.json'

        if (-not (Test-Path $dockerDesktopSettings -ErrorAction SilentlyContinue)) { 

            Write-Host ">>> Preconfigure Docker Desktop ..."

            @{
                'AutoStart' = $true
                'DisplayedOnboarding' = $true

            } | ConvertTo-Json -Depth 100 | Set-Utf8Content -Path $dockerDesktopSettings
        }

        Write-Host ">>> Starting Docker Desktop ..."
        Invoke-CommandLine -Command $dockerDesktop -NoWait
        Wait-DockerInfo

        return $true

    } else {

        Write-Host "!!! Docker Desktop is not available"
        return $false
    }
}

function Start-Podman() {

    Write-Host ">>> Starting Podman is not supported yet ..."
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
    if (-not $docker) { throw "Could not find docker" }

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

            $dockerDesktopSettings = Join-Path $env:APPDATA 'Docker\settings-store.json'
            $dockerDesktopSettingsJson = Get-Content -Path $dockerDesktopSettings -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue

            if ($dockerDesktopSettingsJson) {
                try {
                    $dockerDesktopUseWindowsContainers = [bool] ($dockerDesktopSettingsJson.UseWindowsContainers)
                } catch {
                    $dockerDesktopUseWindowsContainers = $false
                } 
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