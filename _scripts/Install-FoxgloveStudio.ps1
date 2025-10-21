Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup -Path $MyInvocation.MyCommand.Path -Name 'Install-FoxgloveStudio.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

$artifactsFolder = New-Item -Path (Join-Path $env:DEVBOX_HOME 'Artifacts\Foxglove') -ItemType Directory -Force | Select-Object -ExpandProperty FullName
$foxgloveStudionInstallerPath = Join-Path $artifactsFolder 'foxglove-latest-win.exe'

if (Test-IsPacker) {

    Invoke-ScriptSection -Title "Downloading Foxglove Studio" -ScriptBlock {

        $temp = Invoke-FileDownload -Url 'https://get.foxglove.dev/desktop/latest/foxglove-latest-win.exe'
        $temp | Move-Item -Destination $foxgloveStudionInstallerPath -Force
        
    }

} else {

    Invoke-ScriptSection -Title "Install Foxglove Studio" -ScriptBlock {
        
        if (Test-Path $foxgloveStudionInstallerPath -PathType Leaf) {
            Invoke-CommandLine -Command $foxgloveStudionInstallerPath -Arguments "/S" | Select-Object -ExpandProperty Output
        } else {
            Write-Host ">>> Foxglove Studio installer not found at $foxgloveStudionInstallerPath. Skipping installation."
        }

    }
}