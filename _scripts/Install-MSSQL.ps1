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

function Split-Configuration() {
	param(
		[Parameter(Mandatory=$true, ValueFromPipeline=$true)][string] $Path
	)

	$configPath = $Path
	$configBlacklist = ('ACTION', 'QUIET', 'QUIETSIMPLE', 'UIMODE', 'UpdateEnabled', 'UpdateSource')
	$configForceEnabled = ('SUPPRESSPRIVACYSTATEMENTNOTICE', 'SUPPRESSPAIDEDITIONNOTICE', 'ENU')
	$configForceDisabled = ('HELP', 'INDICATEPROGRESS', 'PRODUCTCOVEREDBYSA')
	$config = Get-Content -path $configPath | Where-Object { -not([System.String]::IsNullOrEmpty($_)) -and -not("$_".StartsWith(';')) -and -not($configBlacklist -contains ("$_".Split('=')[0])) } | ForEach-Object {
		$key = "$_".Split('=')[0]
		if ($configForceEnabled -contains $key) {
			"$key=`"True`""
		} elseif ($configForceDisabled -contains $key) {
			"$key=`"False`""
		} else {
			$_
		}
	}
	
	Write-Host ">>> Preparing PrepareImage configuration ..."
	$prepareWhitelist = ('ENU', 'PRODUCTCOVEREDBYSA', 'SUPPRESSPRIVACYSTATEMENTNOTICE', 'SUPPRESSPAIDEDITIONNOTICE', 'FEATURES', 'HELP', 'INDICATEPROGRESS', 'INSTALLSHAREDDIR', 'INSTALLSHAREDWOWDIR', 'INSTANCEID', 'INSTANCEDIR')
	$config | Where-Object { ("$_".StartsWith('[')) -or ($prepareWhitelist -contains ("$_".Split('=')[0])) } | Out-File -FilePath ([System.IO.Path]::ChangeExtension($configPath, '.prepare.ini')) -Force
	
	Write-Host ">>> Preparing CompleteImage configuration ..."
	$completeBlacklist = ('ENU', 'PRODUCTCOVEREDBYSA', 'SUPPRESSPRIVACYSTATEMENTNOTICE', 'SUPPRESSPAIDEDITIONNOTICE', 'FEATURES', 'HELP', 'INDICATEPROGRESS', 'INSTALLSHAREDDIR', 'INSTALLSHAREDWOWDIR', 'INSTANCEID', 'INSTANCEDIR')
	$config | Where-Object { ("$_".StartsWith('[')) -or -not($completeBlacklist -contains ("$_".Split('=')[0])) } | Out-File -FilePath ([System.IO.Path]::ChangeExtension($configPath, '.complete.ini')) -Force	

	$Path
}

if (Test-IsPacker) {

	Invoke-ScriptSection -Title "Prepare MSSQL Server" -ScriptBlock {

		Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Artifacts') -Filter "MSSQL*.iso" | 
			Select-Object -ExpandProperty FullName | 
			Where-Object { Test-Path -Path ([System.IO.Path]::ChangeExtension($_, ".ini")) } |
			ForEach-Object {

			$configPath = [System.IO.Path]::ChangeExtension($_, ".ini") | Split-Configuration
			$preparePath = [System.IO.Path]::ChangeExtension($configPath, ".prepare.ini")

			Write-Host ">>> Mounting ISO: $_ ..."
			Mount-DiskImage -ImagePath $_ -PassThru | ForEach-Object {

				$setupPath = "$($_ | Get-Volume | Select-Object -ExpandProperty DriveLetter)`:\setup.exe"

				try {

					Write-Host ">>> Prepare MSSQL Server ..."
					$result = Invoke-CommandLine -Command $setupPath -Arguments "/QUIET /ACTION=PrepareImage /IACCEPTSQLSERVERLICENSETERMS /CONFIGURATIONFILE=`"$preparePath`"" 
					$result.Output | Write-Host
					
					$installPath = "$($config | Where-Object { "$_".StartsWith('INSTANCEDIR=') } | Select-Object -First 1)".Split('=') | Select-Object -Last 1
					$installPath = "$installPath".Trim().Trim('"')
					
					Get-ChildItem -Path $installPath -Filter 'Summary.txt' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 | Get-Content | Write-Host
					if ($result.ExitCode -ne 0) { Throw "Prepare MSSQL Server failed: $($result.ExitCode)" } 

				} finally {


					Write-Host ">>> Unmounting ISO: $($_ | Select-Object -ExpandProperty ImagePath) ..."
					Dismount-DiskImage -ImagePath $_.ImagePath
				}
			}
		}
	}
	
	Invoke-ScriptSection -Title "Prepare Windows Firewall" -ScriptBlock {

		New-NetFirewallRule -DisplayName "SQLServer default instance" -Direction Inbound -LocalPort 1433 -Protocol TCP -Action Allow
		New-NetFirewallRule -DisplayName "SQLServer Browser service" -Direction Inbound -LocalPort 1434 -Protocol UDP -Action Allow
	}

} else {

	Invoke-ScriptSection -Title "Complete MSSQL Server" -ScriptBlock {

		Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Artifacts') -Filter "MSSQL*.iso" | 
			Select-Object -ExpandProperty FullName | 
			Where-Object { Test-Path -Path ([System.IO.Path]::ChangeExtension($_, ".ini")) } |
			ForEach-Object {
		
			$configPath = [System.IO.Path]::ChangeExtension($_, ".ini") | Split-Configuration
			$completePath = [System.IO.Path]::ChangeExtension($configPath, ".complete.ini")

			Write-Host ">>> Mounting ISO: $_ ..."
			Mount-DiskImage -ImagePath $_ -PassThru | ForEach-Object {

				$setupPath = "$($_ | Get-Volume | Select-Object -ExpandProperty DriveLetter)`:\setup.exe"

				try {

					Write-Host ">>> Complete MSSQL Server ..."
					$result = Invoke-CommandLine -Command $setupPath -Arguments "/QUIET /ACTION=CompleteImage /IACCEPTSQLSERVERLICENSETERMS /CONFIGURATIONFILE=`"$completePath`""
					$result.Output | Write-Host

					$installPath = "$($config | Where-Object { "$_".StartsWith('INSTANCEDIR=') } | Select-Object -First 1)".Split('=') | Select-Object -Last 1
					$installPath = "$installPath".Trim().Trim('"')
					
					Get-ChildItem -Path $installPath -Filter 'Summary.txt' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 | Get-Content | Write-Host

					if ($result.ExitCode -ne 0) { Throw "Prepare MSSQL Server failed: $($result.ExitCode)" } 

				} finally {

					Write-Host ">>> Unmounting ISO: $($_ | Select-Object -ExpandProperty ImagePath) ..."
					Dismount-DiskImage -ImagePath $_.ImagePath

				}
			}
		}
	}
}