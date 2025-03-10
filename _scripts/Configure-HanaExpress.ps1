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
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Configure-HanaExpress.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

# ==============================================================================

$dockerKey = Get-ChildItem 'HKLM:\SOFTWARE\Docker Inc.\Docker' -ErrorAction SilentlyContinue | Select-Object -Last 1
$dockerDesktop = Join-Path ($dockerKey | Get-ItemPropertyValue -Name AppPath -ErrorAction SilentlyContinue) 'docker desktop.exe' -ErrorAction SilentlyContinue

if ($dockerDesktop) {

    if (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue) {

        Write-Host ">>> Docker Desktop is already running"

    } else {

        Write-Host ">>> Starting Docker Desktop ..."
        Start-Process -FilePath $dockerDesktop -ErrorAction SilentlyContinue | Out-Null

        $timeout = (get-date).AddMinutes(5)
        Start-Sleep -Seconds 10 # give it a moment to start

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

$imageName = 'saplabs/hanaexpress:latest'
$imageArchive = Join-Path $env:DEVBOX_HOME ("Offline\Docker\Images\$imageName.tar".Replace('/', '\').Replace(':', '_'))
$imageHome = (Split-Path $imageArchive -Parent)

Write-Host ">>> Ensure Offline Docker Image folder exists ($imageHome) ..."
New-Item -Path $imageHome -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

if (Test-IsPacker) {

    Invoke-ScriptSection -Title "Preload HANA Express" -ScriptBlock {
        
        Write-Host ">>> Pulling SAP HANA Express Docker image ($imageName) ..."
        Invoke-CommandLine -Command $docker -Arguments "pull $imageName" | Select-Object -ExpandProperty Output | Write-Host

        Write-Host ">>> Saving SAP HANA Express Docker image ($imageArchive) ..."
        Invoke-CommandLine -Command $docker -Arguments "save $imageName --output `"$imageArchive`"" | Select-Object -ExpandProperty Output | Write-Host

        if (-not (Test-Path $imageArchive)) {
            # saving the image failed - blow it up
            throw "Failed to save HANA Express Docker image at $imageArchive"
        }

        $imageSize = (Get-Item $imageArchive).Length / 1GB
        Write-Host ">>> HANA Express Docker image saved ($imageArchive - $imageSize GB)"
    }

} else {

    Invoke-ScriptSection -Title "Import HANA Express" -ScriptBlock {
        
        if (Test-Path $imageArchive) {
            Write-Host ">>> Loading SAP HANA Express Docker image ($imageArchive) ..."
            Invoke-CommandLine -Command $docker -Arguments "load -i `"$imageArchive`"" | Select-Object -ExpandProperty Output | Write-Host
        } else {
            Write-Host ">>> Pulling SAP HANA Express Docker image ($imageName) ..."
            Invoke-CommandLine -Command $docker -Arguments "pull $imageName" | Select-Object -ExpandProperty Output | Write-Host
        }
    }

    Invoke-ScriptSection -Title "Configuring HANA Express" -ScriptBlock {
  
        $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False

        $hanaHome = New-Item -Path (Join-Path [Environment]::GetFolderPath("MyDocuments") 'HANA Express') -ItemType Directory -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        $hanaSettings = Join-Path $hanaHome 'settings.json'
        $hanaSettingsContent = @{ "master_password" = "$(New-Password)" } | ConvertTo-Json -Depth 100

        Write-Host ">>> Configure HANA Express ..."
        [System.IO.File]::WriteAllLines($hanaSettings, $hanaSettingsContent, $utf8NoBomEncoding)

        Write-Host ">>> Create configuration Shortcut ..."
        New-Shortcut -Path (Join-Path ([System.Environment]::GetFolderPath("Desktop")) -ChildPath "HANA Express Config.lnk") -Target $hanaSettings

        Write-Host ">>> Starting HANA Express ..."
        Invoke-CommandLine -Command $docker -Arguments "run -p 39013:39013 -p 39017:39017 -p 39041-39045:39041-39045 -p 1128-1129:1128-1129 -p 59013-59014:59013-59014 -d -v ${$hanaHome}:/hana/mounts --ulimit nofile=1048576:1048576 --sysctl kernel.shmmax=1073741824 --sysctl net.ipv4.ip_local_port_range='40000 60999' --sysctl kernel.shmmni=524288 --sysctl kernel.shmall=8388608 --name 'HANA-Express' $imageName --passwords-url file:///hana/mounts/settings.json --agree-to-sap-license" | Select-Object -ExpandProperty Output | Write-Host
    
    }
}
