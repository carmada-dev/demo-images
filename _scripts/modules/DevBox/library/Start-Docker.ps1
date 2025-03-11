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
        [Validationset('DockerDesktop', 'Podman')]
        [string] $Tool
    )

    $docker = Get-Command 'docker' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path

    if (-not $docker) { 
        # docker CLI not found - assuming docker is not installed
        throw "Could not find docker CLI" 
    }

    $result = Invoke-CommandLine -Command $docker -Arguments 'info' -Silent -ErrorAction SilentlyContinue
    
    if ($result.ExitCode -eq 0) { 
        Write-Host ">>> Docker is already running"
        return $true 
    }

    switch ($Tool) {
        'DockerDesktop' { 
            return Start-DockerDesktop 
        }
        'Podman' { 
            return Start-Podman 
        }
        default { 
            return Start-DockerDesktop -or Start-Podman
        }
    }
}

Export-ModuleMember -Function Start-Docker