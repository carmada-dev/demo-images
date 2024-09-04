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

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

Invoke-ScriptSection -Title "Configure Docker Desktop" -ScriptBlock {

    $dockerExe = Get-Command 'docker.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path

    if ( -not($dockerExe) ) {
        Write-ErrorMessage '!!! Docker could not be found.'
        exit 1
    }

    # $dockerComposeExe = Get-ChildItem -Path $dockerApp.Location -Filter "docker-compose.exe" -Recurse | Select-Object -First 1 -ExpandProperty Fullname
    # $dockerDaemonExe = Get-ChildItem -Path $dockerApp.Location -Filter "dockerd.exe" -Recurse | Select-Object -First 1 -ExpandProperty Fullname
    
    if (Test-IsPacker) {
        
        $dockerUsersMembers = Get-LocalGroupMember -Group "docker-users" 
        if ($dockerUsersMembers -and -not ($dockerUsersMembers -like "NT AUTHORITY\Authenticated Users")) {
            Write-Host ">>> Adding 'Authenticated Users' to docker-users group ..."
            Add-LocalGroupMember -Group "docker-users" -Member "NT AUTHORITY\Authenticated Users"
        }

        $dockerHostEndpoint = 'tcp://127.0.0.1:2375'
        $dockerDaemonCfg = Join-Path $env:ProgramData 'Docker\config\daemon.json'
        $dockerDaemonHosts = @( "npipe:////./pipe/docker_engine", $dockerHostEndpoint )
        $dockerDaemonGroup = "docker-users"

        if (Test-Path -Path $dockerDaemonCfg -PathType Leaf) {
            $config = Get-Content $dockerDaemonCfg | ConvertFrom-Json
        } else {
            $config = [PSCustomObject]@{}
        }
        
        if (-not($config | Get-Member -Name hosts -MemberType NoteProperty)) {
            $config | Add-Member -Name hosts -MemberType NoteProperty -Value $dockerDaemonHosts
        } else {
            $config.hosts = $dockerDaemonHosts
        }

        if (-not($config | Get-Member -Name group -MemberType NoteProperty)) {
            $config | Add-Member -Name group -MemberType NoteProperty -Value $dockerDaemonGroup
        } else {
            $config.group = $dockerDaemonGroup
        }

        Write-Host ">>> Patching Docker Host configuration"
        New-Item -ItemType Directory -Force -Path (Split-Path $dockerDaemonCfg -Parent) | Out-Null
        $config | ConvertTo-Json | Set-Content -Path $dockerDaemonCfg -Force
    
        Write-Host ">>> Register Docker Host endpoint"
        [System.Environment]::SetEnvironmentVariable('DOCKER_HOST', $dockerHostEndpoint, [System.EnvironmentVariableTarget]::Machine)

        $dockerSvc = Get-Service -Name 'docker' -ErrorAction SilentlyContinue
        if ($dockerSvc) {

            Write-Host ">>> Ensure Docker services are in running state"
            Restart-Service *docker* -PassThru -Force
    
        } else {
            
            $dockerDaemonExe = Join-Path (Split-Path (Split-Path $dockerExe)) 'dockerd.exe'
            if (Test-Path -Path $dockerDaemonExe -PathType Leaf) {

                Write-Host ">>> Register Docker Daemon as service"
                Invoke-CommandLine -Command $dockerDaemonExe -Arguments "--register-service" | Select-Object -ExpandProperty Output | Write-Host   

            } else {

                Write-ErrorMessage "!!! Could not find docker daemon at $dockerDaemonExe"
                exit 1
            }
        }	
    } 
}