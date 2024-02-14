param(
    [Parameter(Mandatory=$false)]
    [boolean] $Packer = ((Get-ChildItem env:packer_* | Measure-Object).Count -gt 0)
)

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if ($Packer) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Configure-Podman.ps1' -Elevate
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

	if ($Packer) {

		$dockerExe = Get-Command 'docker.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path

		if ($dockerExe) {
			
			Write-Host "Podman and Docker Desktop installed -> skip registering docker alias for podman"

		} else {

			$macroDir = New-Item -Path (Join-Path $env:PUBLIC 'Macros') -PathType Directory -Force -PassThru | Select-Object -ExpandProperty Fullname
			$macroFile = New-Item -Path (Join-Path $macroDir 'macros.cmd') -PathType File -Force | Select-Object -ExpandProperty Fullname

			Add-Content -Path $macroFile -Value 'docker=podman $*' -Encoding UTF8 | Out-Null
			New-Item -Path 'HKEY_LOCAL_MACHINE\Software\Microsoft\Command Processor' -Name 'AutoRun' -Value "doskey /macrofile=`"$macroFile`"" | Out-Null
		}

	} else {



	}
}