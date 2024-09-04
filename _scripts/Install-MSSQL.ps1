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

function Get-ConfigurationArguments() {
	param(
		[Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string] $Path,
        [Parameter(Mandatory=$true)]
        [ValidateSet('Prepare', 'Complete')]
        [string] $Sequence
	)

	$configBlacklist = ('ACTION', 'QUIET', 'QUIETSIMPLE', 'UIMODE', 'UpdateEnabled', 'UpdateSource', 'INDICATEPROGRESS')
	$configForceEnabled = ('SUPPRESSPRIVACYSTATEMENTNOTICE', 'SUPPRESSPAIDEDITIONNOTICE', 'ENU')
	$configForceDisabled = ('HELP', 'PRODUCTCOVEREDBYSA')

	$config = Get-Content -path $Path | Where-Object { -not([System.String]::IsNullOrEmpty($_)) -and -not("$_".StartsWith('[')) -and -not("$_".StartsWith(';')) -and -not($configBlacklist -contains ("$_".Split('=')[0])) } | ForEach-Object {
		$key = "$_".Split('=')[0]
		if ($configForceEnabled -contains $key) {
			"$key=`"True`""
		} elseif ($configForceDisabled -contains $key) {
			"$key=`"False`""
		} else {
			$_
		}
	}

	$prepareWhitelist = ('ENU', 'PRODUCTCOVEREDBYSA', 'SUPPRESSPRIVACYSTATEMENTNOTICE', 'SUPPRESSPAIDEDITIONNOTICE', 'FEATURES', 'HELP', 'INDICATEPROGRESS', 'INSTALLSHAREDDIR', 'INSTALLSHAREDWOWDIR', 'INSTANCEDIR', 'INSTANCEID')
    $completeBlacklist = ('ENU', 'PRODUCTCOVEREDBYSA', 'SUPPRESSPRIVACYSTATEMENTNOTICE', 'SUPPRESSPAIDEDITIONNOTICE', 'FEATURES', 'HELP', 'INDICATEPROGRESS', 'INSTALLSHAREDDIR', 'INSTALLSHAREDWOWDIR', 'INSTANCEDIR')		

    switch ($Sequence) {

        'Prepare' {

	        ($config | Where-Object { ($prepareWhitelist -contains ("$_".Split('=')[0])) } | ForEach-Object { "/$_" }) -join ' '
        }

        'Complete' {

            $configArgs = ($config | Where-Object { -not($completeBlacklist -contains ("$_".Split('=')[0])) } | ForEach-Object { "/$_" }) -join ' ' 

            if (-not(($config | Where-Object { "$_".Split('=')[0] }) -contains 'INSTANCEID')) {
                try {

                    $instanceId = ([Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\\Microsoft\\Microsoft SQL Server\\Instance Names\\SQL', $false).GetValueNames() | Select-Object -First 1 | Out-String).Trim()
                    $configArgs = "$configArgs /INSTANCEID=`"$instanceId`""

                } catch {
                    # swallow exception
                }
            }
            
            $configArgs
        }

        default {

            [System.String]::Empty
        }
    }
}

function Get-BootstrapPath() {

    (Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server' -Recurse | 
        Where-Object { ($_.Name.EndsWith('\Bootstrap')) -and ($_ | Get-ItemProperty -Name 'BootstrapDir' -ErrorAction SilentlyContinue) } | 
        Select-Object -First 1 | 
        Get-ItemPropertyValue -Name 'BootstrapDir' -ErrorAction SilentlyContinue |
        Out-String).Trim()
}

function Get-ProductId() {
    
	$editionType = (Get-ChildItem "hklm:\SOFTWARE\Microsoft\Microsoft SQL Server" -Recurse | 
		Where-Object { ($_.Name.EndsWith('\Setup')) -and ($_ | Get-ItemProperty -Name 'EditionType' -ErrorAction SilentlyContinue) } |
		Select-Object -First 1 |
		Get-ItemPropertyValue -Name 'EditionType' -ErrorAction SilentlyContinue | 
		Out-String).Trim()

    Switch ($editionType) {
            
        'Express Edition' { 
            '11111-00000-00000-00000-00000' 
        }
            
        'Developer Edition' { 
            '22222-00000-00000-00000-00000' 
        }

        default {
            
			$rootPath = Join-Path $env:DEVBOX_HOME 'Artifacts\MSSQL'
			
			$pidPath = Get-ChildItem -Path $rootPath -Filter "*.iso" -ErrorAction SilentlyContinue | 
				ForEach-Object { [System.IO.Path]::ChangeExtension($_.FullName, ".pid") } |
				Select-Object -First 1 |
				Out-String
				
            if (($pidPath) -and (Test-Path -Path $pidPath -PathType Leaf)) {

				Write-Host ">>> Resolving product id from pid file: $pidPath"
                (Get-Content -Path $pidPath | Out-String).Trim()
            }
        }
    }
}

function Get-Summary() {

    $bootstrapPath = Get-BootstrapPath

    if ($bootstrapPath) {
        
        $summaryPath = Get-ChildItem -Path $bootstrapPath -Filter 'Summary.txt' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if ($summaryPath) { Get-Content -Path $summaryPath -ErrorAction SilentlyContinue | Out-String }

    }
}

if (-not(Test-Path -Path (Join-Path $env:DEVBOX_HOME 'Artifacts\MSSQL') -PathType Container)) { 
	
	Throw "MSSQL Server artifacts not found" 

} elseif (Test-IsPacker) {

	Invoke-ScriptSection -Title "Prepare MSSQL Server" -ScriptBlock {

		$cfgPath = Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Artifacts\MSSQL') -Filter "PrepareImage.ini" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName 
		if (-not($cfgPath)) { Throw "MSSQL Server PrepareImage.ini not found in $rootPath" } 

		$isoPath = Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Artifacts\MSSQL') -Filter "*.iso" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName 
		if ($isoPath) {

			Write-Host ">>> Mounting ISO: $isoPath ..."
			$isoDrive = Mount-DiskImage -ImagePath $isoPath -ErrorAction Stop -PassThru

		}

		try {
			
			if ($isoDrive) {
		
				$setupRoot = ($isoDrive | Get-Volume -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DriveLetter | Out-String).Trim() + ":\"

				Write-Host ">>> Resolving setup.exe from mounted ISO at $setupRoot ..."
				$setupPath = Get-ChildItem -Path $setupRoot -Filter "setup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
								
			} else {

				$setupTemp = New-Item -Path $(Join-Path $env:DEVBOX_HOME 'Artifacts\MSSQL\Temp') -ItemType Directory -Force | Select-Object -ExpandProperty FullName
				Get-ChildItem -Path $setupTemp -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

				$setupRoot = New-Item -Path $(Join-Path $env:DEVBOX_HOME 'Artifacts\MSSQL\Express') -ItemType Directory -Force | Select-Object -ExpandProperty FullName
				Get-ChildItem -Path $setupRoot -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

				Write-Host "!!! MSSQL Server ISO not found - falling back to SQL Express Advanced ..."
				$temp = Invoke-FileDownload -Url 'https://download.microsoft.com/download/5/1/4/5145fe04-4d30-4b85-b0d1-39533663a2f1/SQL2022-SSEI-Expr.exe'

				Write-Host ">>> Downloading MSSQL Server Express installation media ..."
				Invoke-CommandLine -Command $temp -Arguments "/QUIET /ENU /ACTION=Download /MEDIATYPE=Advanced /MEDIAPATH=`"$setupTemp`"" | Select-Object -ExpandProperty Output | Write-Host

				$exprMedia = Get-ChildItem -Path $setupTemp -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
				if (-not($exprMedia)) { Throw "MSSQL Server Express media not found in $exprRoot" }

				Write-Host ">>> Extracting MSSQL Server Express installation media ..."
				Invoke-CommandLine -Command $exprMedia -Arguments "/q /x:`"$setupRoot`"" | Select-Object -ExpandProperty Output | Write-Host

				Write-Host ">>> Resolving setup.exe from unpacked media at $setupRoot ..."
				$setupPath = Get-ChildItem -Path $setupRoot -Filter "setup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
			}

			if ($setupPath) { 

				Write-Host ">>> Prepare MSSQL Server ..."
				$result = Invoke-CommandLine -Command $setupPath -Arguments "/QUIET /ACTION=PrepareImage /IACCEPTSQLSERVERLICENSETERMS $($cfgPath | Get-ConfigurationArguments -Sequence 'Prepare')" 
				$result.Output | Write-Host
				
				Write-Host ">>> Summary MSSQL Server ..."
				Get-Summary | Write-Host

				if ($result.ExitCode -ne 0) { Throw "Prepare MSSQL Server failed: $($result.ExitCode)" } 

			} else {

				Throw "MSSQL Server setup.exe not found in $setupRoot" 
			}

		} finally {

			if ($setupTemp) {

				Write-Host ">>> Deleting temp folder ..."
				Remove-Item -Path $setupTemp -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
			}

			if ($isoDrive) {

				Write-Host ">>> Unmounting ISO ..."
				$isoDrive | Dismount-DiskImage -ErrorAction SilentlyContinue | Out-Null
			}
		}
	}

} else {
    
    Invoke-ScriptSection -Title "Prepare Windows Firewall" -ScriptBlock {
        
        Write-Host ">>> Allow SQL Browser communication ..."
		New-NetFirewallRule -DisplayName "SQLServer Browser service" -Direction Inbound -LocalPort 1434 -Protocol UDP -Action Allow | Out-Null

        Write-Host ">>> Allow SQL engine communication ..."
		New-NetFirewallRule -DisplayName "SQLServer default instance" -Direction Inbound -LocalPort 1433 -Protocol TCP -Action Allow | Out-Null
	}

	Invoke-ScriptSection -Title "Complete MSSQL Server" -ScriptBlock {

		$cfgPath = Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Artifacts\MSSQL') -Filter "CompleteImage.ini" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
		if (-not($cfgPath)) { Throw "MSSQL Server PrepareImage.ini not found in $rootPath" }

		$setupPath = Get-ChildItem (Get-BootstrapPath) -Filter "setup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName | Out-String
		if (-not($setupPath)) { Throw "MSSQL Server setup.exe not found in $(Get-BootstrapPath)" }

		$productId = Get-ProductId
		if ($productId) { 
			$productArg = "/PID=`"$productId`"" 
		} else {
			Write-Host "!!! Product ID not found - falling back to Evaluation Edition ..."
		} 

		Write-Host ">>> Complete MSSQL Server ..."       
		$result = Invoke-CommandLine -Command $setupPath -Arguments "/QUIET /ACTION=`"CompleteImage`" /IACCEPTSQLSERVERLICENSETERMS $productArg $($cfgPath | Get-ConfigurationArguments -Sequence 'Complete')"
		$result.Output | Write-Host

		Write-Host ">>> Summary MSSQL Server ..."
		Get-Summary | Write-Host

		if ($result.ExitCode -ne 0) { Throw "Complete MSSQL Server failed: $($result.ExitCode)" } 
	}

	$setupBaks = Join-Path $env:DEVBOX_HOME 'Artifacts\MSSQL\Backups'
	if (Test-Path $setupBaks -PathType Container) {

		Invoke-ScriptSection -Title "Restore databases" -ScriptBlock {

			Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Artifacts\MSSQL\Backups') -Filter '*.bak' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName | Sort-Object | ForEach-Object {

				$databaseBackup = ($_ | Out-String).Trim()
				$databaseName = [System.IO.Path]::GetFileNameWithoutExtension($databaseBackup) -replace '\W', ''

				try {

					Write-Host ">>> Restoring database '$databaseName' from '$databaseBackup' ..."
					$restoreCommand = "RESTORE DATABASE $databaseName FROM DISK='$databaseBackup'"

					Write-Host ">>> Query default database file locations ..."
					$result = @(Invoke-Sqlcmd -Database 'master' -Query "SELECT SERVERPROPERTY('instancedefaultdatapath') AS [DefaultData], SERVERPROPERTY('instancedefaultlogpath') AS [DefaultLogs]") 
					$defaultDataPath = $result | Select-Object -ExpandProperty DefaultData
					$defaultLogsPath = $result | Select-Object -ExpandProperty DefaultLogs

					Write-Host ">>> Query logical files from backup ..."
					$result = @(Invoke-Sqlcmd -Database 'master' -Query "RESTORE FILELISTONLY FROM DISK='$databaseBackup'")
					$move = @($result | ForEach-Object { 
						$logicalName = $_ | Select-Object -ExpandProperty LogicalName
						switch ($_.Type) {
							'D' { "MOVE '$logicalName' TO '$(Join-Path $defaultDataPath "$logicalName.mdf")'" }
							'L' { "MOVE '$logicalName' TO '$(Join-Path $defaultLogsPath "$logicalName.ldf")'" }
							default { '' }
						}
					} | Where-Object { -not([String]::IsNullOrWhiteSpace("$_")) }) -join ', '

					if ($move) { $restoreCommand = "$restoreCommand WITH $move, REPLACE" }

					Write-Host ">>> Ensure database is detached (if exists) ..."
					Invoke-Sqlcmd -Database 'master' -Query "EXEC sp_detach_db '$databaseName', 'true'" -ErrorAction SilentlyContinue

					Write-Host ">>> Restore database: $databaseName ..."
					Invoke-Sqlcmd -Database 'master' -Query $restoreCommand | Write-Host

				}
				catch {

					Write-Host "!!! Error restoring database '$databaseName' from '$databaseBackup': $($Error[0])"
				}
			}

			Write-Host 'done'
		}
	}
}