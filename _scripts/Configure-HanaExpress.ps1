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

$docker = Get-Command 'docker' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path
if (-not $docker) { throw "Could not find docker CLI" }

if (-not (Test-IsPacker) -and (Start-Docker)) {

    $containerImage = 'saplabs/hanaexpress:latest'
    $containerName = 'HANA-Express'
    $containerHome = (New-Item -Path (Join-Path $env:DEVBOX_HOME "Docker\$containerName") -ItemType Directory -Force).FullName

    $containerOptions = @(
        "-p 39013:39013",
        "-p 39017:39017", 
        "-p 39041-39045:39041-39045", 
        "-p 1128-1129:1128-1129", 
        "-p 59013-59014:59013-59014",
        "-d",
        "-v ${$containerHome}:/hana/mounts",
        "--ulimit nofile=1048576:1048576",
        "--sysctl kernel.shmmax=1073741824",
        "--sysctl net.ipv4.ip_local_port_range='40000 60999'",
        "--sysctl kernel.shmmni=524288",
        "--sysctl kernel.shmall=8388608",
        "--name '$containerName'"
    ) -join ' '

    $containerArguments = @(
        "--passwords-url file:///hana/mounts/settings.json",
        "--agree-to-sap-license"
    ) -join ' '

    Write-Host ">>> Starting HANA Express ..."
    Invoke-CommandLine -Command $docker -Arguments "run $containerOptions $containerImage $containerArguments" -NoWait
}
