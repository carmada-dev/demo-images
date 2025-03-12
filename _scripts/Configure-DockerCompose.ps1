$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Configure-HanaExpress.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

# ==============================================================================

$dockerCompose = Get-Command 'docker-compose' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
if (-not $dockerCompose) { throw 'Could not find docker-compose.exe' }

if (-not (Test-IsPacker)) {

    Invoke-ScriptSection -Title "Configure Docker Compose" -ScriptBlock {

        if ( -and (Start-Docker)) {

            # ensure docker artifacts directory exists
            $dockerArtifacts = (New-Item -Path (Join-Path $env:DEVBOX_HOME 'Artifacts\Docker') -ItemType Directory -Force).FullName

            $dockerEnvironment = @{
                "ROOT" = "/$($workingDirectory.Replace('\', '/').Replace(':', ''))"
            }

            Get-ChildItem -Path $dockerArtifacts -Filter 'compose.yml' -Recurse -File | Select-Object -ExpandProperty FullName | ForEach-Object {

                $envFile = Join-Path (Split-Path $_ -Parent) '.env'
                $envVars = "$(Get-Content -Path $envFile -Raw -ErrorAction SilentlyContinue)"

                $envVars = (($envVars -split "`r?`n" | Where-Object { 
                    if ([string]::IsNullOrWhiteSpace($_)) { return $false }
                    $key = "$(($_ -split '=') | Select-Object -First 1 -ErrorAction SilentlyContinue)".Trim()
                    return (-not $dockerEnvironment.ContainsKey($key))
                }) + ($dockerEnvironment.Keys | ForEach-Object { "$_=$($dockerEnvironment[$_])" })) | Out-String
                
                Write-Host ">>> Writing environment variables to .env file: $envFile"
                $envVars | Set-Utf8Content -Path $envFile -ErrorAction SilentlyContinue

                Write-Host ">>> Starting Docker Compose at $(Split-Path $_ -Parent) ..."
                Invoke-CommandLine `
                    -Command $dockerCompose `
                    -Arguments "up --wait" `
                    -WorkingDirectory (Split-Path $_ -Parent) `
                    -NoWait
                
            }
        }
    }
}