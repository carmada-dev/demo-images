Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Configure-Podman.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

Invoke-ScriptSection -Title "Configure Podman" -ScriptBlock {

	$podmanExe = Get-Command 'podman.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path
	if (-not($podmanExe)) {
		Write-ErrorMessage '!!! Podman could not be found.'
		exit 1
	}

	if (Test-IsPacker) {

		$dockerExe = Get-Command 'docker.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path

		if ($dockerExe) {
			
			Write-Host "Podman and Docker Desktop installed -> skip registering docker alias for podman"

		} else {

			$path = New-Item -ItemType Directory -Path "C:\Program Files\docker\bin" -Force | Select-Object -ExpandProperty FullName
			"@echo off && podman %*" | Out-File -FilePath "$path\docker.bat" -Force -Encoding ascii

			$MACHINE_PATH = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::Machine)
			[System.Environment]::SetEnvironmentVariable('PATH', "$MACHINE_PATH;$path", [System.EnvironmentVariableTarget]::Machine)
		}

	} else {

		$result = Invoke-Commandline -Command "$podmanExe" -Arguments "machine init --cpus 2 --disk-size 100 --memory 8192 --now"
		$result.Output | Write-Host

		exit $result.ExitCode
	}
}