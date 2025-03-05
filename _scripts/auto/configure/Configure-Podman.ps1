$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

$podman = Get-Command 'podman.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path

if (-not $podman) {
	Write-Host ">>> Not applicable: Podman not installed"
	exit 0
} elseif (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Configure-Podman.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

# ==============================================================================

Invoke-ScriptSection -Title "Configure Podman" -ScriptBlock {

	if (Test-IsPacker) {

		$dockerExe = Get-Command 'docker.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path

		if ($dockerExe) {
			
			Write-Host "Podman and Docker Desktop installed -> skip registering docker alias for podman"

		} else {

			$path = New-Item -ItemType Directory -Path "C:\Program Files\docker\bin" -Force | Select-Object -ExpandProperty FullName

			Write-Host "Create docker alias for podman in '$path'"
			"@echo off && podman %*" | Out-File -FilePath "$path\docker.bat" -Force -Encoding ascii

			$MACHINE_PATH = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::Machine)
			[System.Environment]::SetEnvironmentVariable('PATH', "$MACHINE_PATH;$path", [System.EnvironmentVariableTarget]::Machine)
		}

	} else {

		$result = Invoke-Commandline -Command "$podman" -Arguments "machine init --cpus 2 --disk-size 100 --memory 8192 --now"
		$result.Output | Write-Host

		exit $result.ExitCode
	}
}