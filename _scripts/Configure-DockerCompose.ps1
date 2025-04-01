$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Configure-DockerCompose.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

# ==============================================================================

$dockerCompose = Get-Command 'docker-compose' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
if (-not $dockerCompose) { throw 'Could not find docker-compose.exe' }

if (-not (Test-IsPacker) -and (Start-Docker)) {

    # ensure docker artifacts directory exists
    $dockerArtifacts = (New-Item -Path (Join-Path $env:DEVBOX_HOME 'Artifacts\Docker') -ItemType Directory -Force).FullName

    #process all docker-compose files in the artifacts directory
    $jobs = Get-ChildItem -Path $dockerArtifacts -Include "docker-compose.yml", "docker-compose.yaml" -File -Recurse -Depth 1 | Select-Object -ExpandProperty FullName | ForEach-Object { 
                
        Start-Job -ScriptBlock {

            param([string] $composeFile)

            Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	            Write-Host ">>> Importing PowerShell Module: $_"
	            Import-Module -Name $_
            } 

            Invoke-ScriptSection -Title "Processing: $composeFile" -ScriptBlock {

                Push-Location -Path (Split-Path $composeFile -Parent) -ErrorAction SilentlyContinue

                try{

                    $composeScript = [System.IO.Path]::ChangeExtension($composeFile, '.ps1')
                        
                    if (Test-Path -Path $composeScript -PathType Leaf) {
                        
                        Write-Host ">>> Running Docker Compose script: $composeScript"
                        Invoke-CommandLine -Command 'powershell' -Arguments "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -File `"$composeScript`"" -WorkingDirectory (Split-Path $composeFile -Parent) | select-Object -ExpandProperty Output | Write-Host
                        
                    } else {

                        $dockerCompose = Get-Command 'docker-compose' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
                        if (-not $dockerCompose) { throw 'Could not find docker-compose.exe' }

                        Write-Host ">>> Starting Docker Compose at $(Split-Path $composeFile -Parent) ..."
                        Invoke-CommandLine -Command $dockerCompose -Arguments "up --detach" -Capture 'StdErr'  -WorkingDirectory (Split-Path $composeFile -Parent) | select-Object -ExpandProperty Output | Clear-DockerProgress | Write-Host
                    }
                }
                finally {
                    
                    Pop-Location -ErrorAction SilentlyContinue
                }
            }

        } -ArgumentList $_ -ErrorAction SilentlyContinue 
    }

    if ($jobs) { 

        Write-Host ">>> Waiting for Docker Compose jobs to finish ..."
        $jobs | Wait-Job | Receive-Job -ErrorAction SilentlyContinue
    }
}
