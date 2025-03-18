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

if (-not (Test-IsPacker)) {

    Invoke-ScriptSection -Title "Running Docker Compose" -ScriptBlock {

        if (Start-Docker) {

            # ensure docker artifacts directory exists
            $dockerArtifacts = (New-Item -Path (Join-Path $env:DEVBOX_HOME 'Artifacts\Docker') -ItemType Directory -Force).FullName

            $jobs = Get-ChildItem -Path "$dockerArtifacts\*" -Include "docker-compose.yml", "docker-compose.yaml" -File | Select-Object -ExpandProperty FullName | ForEach-Object {
                
                Invoke-Command -AsJob -ScriptBlock {

                    param($dockerCompose, $composeFile)

                    $composeDirectory = Split-Path $composeFile -Parent
                    $composeEnvironment = @{ "ROOT" = "/$($composeDirectory.Replace('\', '/').Replace(':', ''))" }
    
                    $envFile = Join-Path $composeDirectory '.env'
                    $envVars = "$(Get-Content -Path $envFile -Raw -ErrorAction SilentlyContinue)"
    
                    $envVars = (($envVars -split "`r?`n" | Where-Object { 
                        if ([string]::IsNullOrWhiteSpace($_)) { return $false }
                        $key = "$(($_ -split '=') | Select-Object -First 1 -ErrorAction SilentlyContinue)".Trim()
                        return (-not $composeEnvironment.ContainsKey($key))
                    }) + ($composeEnvironment.Keys | ForEach-Object { "$_=$($composeEnvironment[$_])" })) | Out-String
                    
                    Write-Host ">>> Writing environment variables to .env file: $envFile"
                    $envVars | Set-Utf8Content -Path $envFile -ErrorAction SilentlyContinue
    
                    Write-Host ">>> Starting Docker Compose at $(Split-Path $_ -Parent) ..."
                    Invoke-CommandLine -Command $dockerCompose -Arguments "up --wait" -WorkingDirectory $composeDirectory | select-Object -ExpandProperty Output | Write-Host

                } -ArgumentList $dockerCompose, $_ -ErrorAction SilentlyContinue
                
            }

            Write-Host ">>> Waiting for Docker Compose jobs to finish ..."
            $jobs | Receive-Job -Wait -AutoRemoveJob
        }
    }
}