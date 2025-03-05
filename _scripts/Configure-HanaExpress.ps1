$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

$docker = Get-Command 'docker' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path

if (-not $docker) {
    Write-Host ">>> Not applicable: Docker not installed"
    exit 0
} elseif (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Configure-DockerDesktop.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

# ==============================================================================

$images = New-Item -Path (Join-Path $env:DEVBOX_HOME 'Artifacts\Docker\Images') -ItemType Directory -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
$image = Join-Path $images 'hanaexpress.tar'

if (Test-IsPacker) {

    Invoke-ScriptSection -Title "Preload HANA Express" -ScriptBlock {
        
        Write-Host ">>> Pulling SAP HANA Express Docker image ..."
        Invoke-CommandLine -Command $docker -Arguments "pull saplabs/hanaexpress" | Select-Object -ExpandProperty Output | Write-Host

        Write-Host ">>> Saving SAP HANA Express Docker image ..."
        Invoke-CommandLine -Command $docker -Arguments "save saplabs/hanaexpress --output '$image'" | Select-Object -ExpandProperty Output | Write-Host

    }

} else {

    Invoke-ScriptSection -Title "Import HANA Express" -ScriptBlock {
        
        if (Test-Path $image) {
            Write-Host ">>> Loading SAP HANA Express Docker image ..."
            Invoke-CommandLine -Command $docker -Arguments "load -i '$image'" | Select-Object -ExpandProperty Output | Write-Host
        } else {
            Write-Host ">>> Pulling SAP HANA Express Docker image ..."
            Invoke-CommandLine -Command $docker -Arguments "pull saplabs/hanaexpress" | Select-Object -ExpandProperty Output | Write-Host
        }
    }

    Invoke-ScriptSection -Title "Configuring HANA Express" -ScriptBlock {
  
        $hanaHome = New-Item -Path (Join-Path [Environment]::GetFolderPath("MyDocuments") 'HANA Express') -ItemType Directory -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        $hanaSettings = Join-Path $hanaHome 'settings.json'

        Write-Host ">>> Configuring HANA Express ..."
        @{ "master_password" = "HXEHana1" } | ConvertTo-Json | Set-Content -Path $hanaSettings -Force

        Write-Host ">>> Starting HANA Express ..."
        Invoke-CommandLine -Command $docker -Arguments "run -p 39013:39013 -p 39017:39017 -p 39041-39045:39041-39045 -p 1128-1129:1128-1129 -p 59013-59014:59013-59014 -d -v ${$hanaHome}:/hana/mounts --ulimit nofile=1048576:1048576 --sysctl kernel.shmmax=1073741824 --sysctl net.ipv4.ip_local_port_range='40000 60999' --sysctl kernel.shmmni=524288 --sysctl kernel.shmall=8388608 --name "HANA-Express" store/saplabs/hanaexpress:2.00.045.00.20200121.1 --passwords-url file:///hana/mounts/settings.json --agree-to-sap-license" | Select-Object -ExpandProperty Output | Write-Host
    
    }
}