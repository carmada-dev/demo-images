Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup -Path $MyInvocation.MyCommand.Path -Name 'Install-WSL2.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

Invoke-ScriptSection -Title "Installing WSL2" -ScriptBlock {

	if (-not(Get-Command wsl -ErrorAction SilentlyContinue)) {
		Write-Host "Could not find wsl.exe"
		exit 1
	}

	if (Test-IsPacker) {

		Write-Host ">>> Downloading WSL2 kernel update ..."
		$installer = Invoke-FileDownload -url "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi"

		Write-Host ">>> Installing WSL2 kernel update ..."
		Invoke-CommandLine -Command 'msiexec' -Arguments "/I $installer /quiet /norestart" | Select-Object -ExpandProperty Output | Write-Host

		Write-Host ">>> Setting default WSL version to 2 ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--set-default-version 2" | Select-Object -ExpandProperty Output | Write-Host

		Write-Host ">>> Enforcing WSL Update ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--update --web-download" | Select-Object -ExpandProperty Output | Write-Host
	} 

	Write-Host ">>> Installing WSL Default Distro (Ubuntu) ..."
	Invoke-CommandLine -Command 'wsl' -Arguments "--status" | Select-Object -ExpandProperty Output | Write-Host

	Write-Host ">>> Installing WSL Default Distro (Ubuntu) ..."
	Invoke-CommandLine -Command 'wsl' -Arguments "--install --distribution ubuntu --no-launch" | Select-Object -ExpandProperty Output | Write-Host

	Write-Host ">>> WSL Distro overview ..."
	Invoke-CommandLine -Command 'wsl' -Arguments "--list --verbose" | Select-Object -ExpandProperty Output | Write-Host
}