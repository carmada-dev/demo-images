Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup -Path $MyInvocation.MyCommand.Path -Name 'Install-MSSQL.ps1' -Elevate
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

function Patch-ConfigFile() {
	param(
		[Parameter(Mandatory=$true, ValueFromPipeline=$true)][string] $Path
	)

	Write-Host ">>> Patching config: $Path ..."

	(Get-Content -Path $Path) `
		-replace "^(ACTION=)", "; $1" `
		-replace "^(QUIET=)", "; $1" `
		-replace "^(QUIETSIMPLE=)", "; $1" `
		-replace "^(UIMODE=)", "; $1" |
		Out-File -FilePath $Path -Force
}

if (Test-IsPacker) {

	Invoke-ScriptSection -Title "Prepare MSSQL Server" -ScriptBlock {

		Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Artifacts') -Filter "MSSQL*.iso" | 
			Select-Object -ExpandProperty FullName | 
			Where-Object { Test-Path -Path ([System.IO.Path]::ChangeExtension($_, ".ini")) } |
			ForEach-Object {

			$configPath = [System.IO.Path]::ChangeExtension($_, ".ini")
			$configPath | Patch-ConfigFile

			Write-Host ">>> Mounting ISO: $_ ..."
			Mount-DiskImage -ImagePath $_ -PassThru | ForEach-Object {

				$setupPath = "$($_ | Get-Volume | Select-Object -ExpandProperty DriveLetter)`:\setup.exe"

				try {

					Write-Host ">>> Prepare MSSQL Server ..."
					$result = Invoke-CommandLine -Command $setupPath -Arguments "/QUIET /ACTION=PrepareImage /IACCEPTSQLSERVERLICENSETERMS /CONFIGURATIONFILE=`"$configPath`"" 
					
					$result.Output | Write-Host
					if ($result.ExitCode -ne 0) { Throw "Prepare MSSQL Server failed: $($result.ExitCode)" } 

				} finally {

					Write-Host ">>> Unmounting ISO: $($_ | Select-Object -ExpandProperty ImagePath) ..."
					Dismount-DiskImage -ImagePath $_.ImagePath
				}
			}
		}
	}

} else {

	Invoke-ScriptSection -Title "Complete MSSQL Server" -ScriptBlock {

		Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Artifacts') -Filter "MSSQL*.iso" | 
			Select-Object -ExpandProperty FullName | 
			Where-Object { Test-Path -Path ([System.IO.Path]::ChangeExtension($_, ".ini")) } |
			ForEach-Object {
		
			$configPath = [System.IO.Path]::ChangeExtension($_, ".ini")
			$configPath | Patch-ConfigFile

			Write-Host ">>> Mounting ISO: $isoPath ..."
			Mount-DiskImage -ImagePath $isoPath -PassThru | ForEach-Object {

				$setupPath = "$($_ | Get-Volume | Select-Object -ExpandProperty DriveLetter)`:\setup.exe"

				try {

					Write-Host ">>> Complete MSSQL Server ..."
					# $result = Invoke-CommandLine -Command $setupPath -Arguments "/QUIET /ACTION=Install /IACCEPTSQLSERVERLICENSETERMS /CONFIGURATIONFILE=$configPath"

					# $result.Output | Write-Host
					# if ($result.ExitCode -ne 0) { Throw "Prepare MSSQL Server failed: $($result.ExitCode)" } 

				} finally {

					Write-Host ">>> Unmounting ISO: $($_ | Select-Object -ExpandProperty ImagePath) ..."
					Dismount-DiskImage -ImagePath $_.ImagePath

				}
			}
		}
	}
}