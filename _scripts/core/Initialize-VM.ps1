
$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ([string]::IsNullOrEmpty($Env:ADMIN_USERNAME)) 	{ Throw "Env:ADMIN_USERNAME must be set" }
if ([string]::IsNullOrEmpty($Env:ADMIN_PASSWORD)) 	{ Throw "Env:ADMIN_PASSWORD must be set" }
if ([string]::IsNullOrEmpty($Env:DEVBOX_HOME)) 		{ Throw "Env:DEVBOX_HOME must be set" }

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

function Get-ShortcutTargetPath() {
	param( 
		[Parameter(Mandatory=$true)][string]$Path
	)

	$Shell = New-Object -ComObject ("WScript.Shell")
	$Shortcut = $Shell.CreateShortcut($Path)

	return $Shortcut.TargetPath
}

$downloadKeyVaultArtifact = {
	param([string] $Source, [string] $Destination, [string] $TokenEndpoint)

	Write-Host ">>> Connecting to Azure"
	Connect-AzAccount -Identity -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null

	Write-Host ">>> Acquire KeyVault Access Token"
	$KeyVaultToken = Get-AzAccessToken -ResourceUrl $TokenEndpoint -ErrorAction Stop -WarningAction SilentlyContinue

	Write-Host ">>> Downloading KeyVault Artifact $Source"
	$KeyVaultHeaders = @{"Authorization" = "Bearer $($KeyVaultToken.Token)"}
	$KeyVaultResponse = Invoke-RestMethod -Uri "$($Source)?api-version=7.1" -Headers $KeyVaultHeaders -ErrorAction Stop
		
	Write-Host ">>> Decoding KeyVault Artifact $Source"
	[System.Convert]::FromBase64String($KeyVaultResponse.value) | Set-Content -Path $Destination -Encoding Byte -Force
}

$downloadStorageArtifact = {
	param([string] $Source, [string] $Destination)

	Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
		Import-Module -Name $_
	} 

	$azcopy = Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Tools') -Recurse -Filter 'azcopy.exe' | Select-Object -ExpandProperty FullName -First 1
	if (-not $azcopy) { throw "AzCopy not found" } 

	Write-Host ">>> Downloading Storage Artifact $Source" 
	Invoke-CommandLine -Command $azcopy -Arguments "copy `"$Source`" `"$Destination`" --output-level=quiet" | Select-Object -ExpandProperty Output | Write-Host
}

$downloadArtifact = {
	param([string] $Source, [string] $Destination)

	Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
		Import-Module -Name $_
	} 

	# no need to add output here - the Invoke-FileDownload function will do that
	Invoke-FileDownload -Url $Source -Name ([System.IO.Path]::GetFileName($Destination)) | Move-Item -Destination $Destination -Force
}

Invoke-ScriptSection -Title 'Setting DevBox environment variables' -ScriptBlock {

	[Environment]::SetEnvironmentVariable("DEVBOX_HOME", $devboxHome, [System.EnvironmentVariableTarget]::Machine)
	Get-ChildItem -Path Env:DEVBOX_* | ForEach-Object { [Environment]::SetEnvironmentVariable($_.Name, $_.Value, [System.EnvironmentVariableTarget]::Machine) }
	Get-ChildItem -Path Env:DEVBOX_* | Out-String | Write-Host
}

Invoke-ScriptSection -Title 'Enable AutoLogon' -ScriptBlock {

	Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoAdminLogon -Value 1 -type String
	Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultUsername -Value "$Env:ADMIN_USERNAME" -type String
	Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultPassword -Value "$Env:ADMIN_PASSWORD" -type String
	Write-Host "done"
}

Invoke-ScriptSection -Title 'Disable User Access Control' -ScriptBlock {

	Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -Value 0 -type DWord
	Write-Host "done"
}

Invoke-ScriptSection -Title "Register Powershell Gallery" -ScriptBlock {

	Write-Host ">>> Installing NuGet package provider" 
	Install-PackageProvider -Name NuGet -Force -Scope AllUsers | Out-Null

	try {

		Write-Host ">>> Trust the PSGallery repository temporarily"
		Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

		Write-Host ">>> Install PowershellGet module"
		Install-Module -Name PowerShellGet -Force -AllowClobber -Scope AllUsers -WarningAction SilentlyContinue

		# Start a new session to install the PowerShellGet module - this will cover the case where the module is already loaded in the current session
		powershell.exe -NoLogo -Mta -ExecutionPolicy $(Get-ExecutionPolicy) -Command '&{ Install-Module -Name PowerShellGet -Force -AllowClobber -Scope AllUsers }'

	} finally {

		Write-Host ">>> Rollback the PSGallery repository policy"
		Set-PSRepository -Name "PSGallery" -InstallationPolicy Untrusted
	}
}

Invoke-ScriptSection -Title 'Downloading Tools' -ScriptBlock {

	$tools = New-Item -Path (Join-Path $Env:DEVBOX_HOME 'Tools') -ItemType Directory -Force | Select-Object -ExpandProperty FullName

	Write-Host ">>> Download azcopy"
	$azcopyTemp = Invoke-FileDownload -Url "https://aka.ms/downloadazcopy-v10-windows$(&{ if ([Environment]::Is64BitOperatingSystem) { '' } else { '-32bit' } })" -Name "azcopy.zip" -Expand 
	Get-ChildItem -Path $azcopyTemp -Recurse -Filter 'azcopy.exe' `
		| Select-Object -ExpandProperty FullName -First 1 `
		| ForEach-Object { Move-Item -Path $_ -Destination $tools -Force | Out-Null	}

	Write-Host ">>> Downloading PsExec"
	$pstoolsTemp = Invoke-FileDownload -Url 'https://download.sysinternals.com/files/PSTools.zip' -Name "PSTools.zip" -Expand
	Get-ChildItem -Path $pstoolsTemp -Recurse -Filter 'PsExec*.exe' `
		| Select-Object -ExpandProperty FullName `
		| ForEach-Object { Move-Item -Path $_ -Destination $tools -Force | Out-Null	}
}

Invoke-ScriptSection -Title 'Disable Defrag Schedule' -ScriptBlock {

	Get-ScheduledTask ScheduledDefrag | Disable-ScheduledTask | Out-String | Write-Host
}

Invoke-ScriptSection -Title 'Disable OneDrive Folder Backup' -ScriptBlock {
	
	$OneDriveRegKeyPath = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
	if (-not(Test-Path -Path $OneDriveRegKeyPath)) { New-Item -Path $OneDriveRegKeyPath -ItemType Directory -Force | Out-Null }
	New-ItemProperty -Path $OneDriveRegKeyPath -Name KFMBlockOptIn -PropertyType DWORD -Value 1 -Force | Out-Null
	Write-Host "done"
}

Invoke-ScriptSection -Title 'Enable Teredo support' -ScriptBlock {
	
	Set-NetTeredoConfiguration -Type Enterpriseclient -ErrorAction SilentlyContinue
	Write-Host "done"
}

Invoke-ScriptSection -Title 'Enable Windows Developer Mode' -ScriptBlock {

	Invoke-CommandLine -Command 'reg' -Arguments 'add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1"' | Select-Object -ExpandProperty Output | Write-Host
	Invoke-CommandLine -Command 'reg' -Arguments 'add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Appx" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1"' | Select-Object -ExpandProperty Output | Write-Host
}

Invoke-ScriptSection -Title 'Enable Hibernate Support' -ScriptBlock {

	Write-Host ">>> Enable Virtual Machine Platform feature ..." 
	Get-WindowsOptionalFeature -Online `
		| Where-Object { $_.FeatureName -like "*VirtualMachinePlatform*" -and $_.State -ne "Enabled" } `
		| Enable-WindowsOptionalFeature -Online -All -NoRestart `
		| Out-Null
	
	Write-Host ">>> Enable Hibernation ..."
	Invoke-CommandLine -Command 'powercfg' -Arguments '/hibernate on' | Select-Object -ExpandProperty Output | Write-Host   
}

Invoke-ScriptSection -Title 'Expand System Partition' -ScriptBlock {

	$partition = Get-Partition | Where-Object { -not($_.IsHidden) } | Sort-Object { $_.DriveLetter } | Select-Object -First 1
	$partitionSize = Get-PartitionSupportedSize -DiskNumber ($partition.DiskNumber) -PartitionNumber ($partition.PartitionNumber)
	if ($partition.Size -lt $partitionSize.SizeMax) {
		Write-Host ">>> Resizing System Partition to $([Math]::Round($partitionSize.SizeMax / 1GB,2)) GB" 
		Resize-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -Size $partitionSize.SizeMax
	} else {
		Write-Host ">>> No need to resize !!!"
	}
}

$Artifacts = Join-Path -Path $env:DEVBOX_HOME -ChildPath 'Artifacts'
if (Test-Path -Path $Artifacts -PathType Container) {

	$links = Get-ChildItem -Path $Artifacts -Filter '*.*.url' -Recurse | Select-Object -ExpandProperty FullName

	if ($links) { 

		Invoke-ScriptSection -Title "Download artifacts prepare" -ScriptBlock {

			@( 'Az.Accounts' ) `
			| ForEach-Object { 
				if (Get-Module -ListAvailable -Name $_) {
					Write-Host ">>> Upgrading Powershell Module: $_";
					Update-Module -Name $_ -AcceptLicense -Force -WarningAction SilentlyContinue -ErrorAction Stop
				} else {
					Write-Host ">>> Installing Powershell Module: $_";
					Install-Module -Name $_ -AcceptLicense -Repository PSGallery -Force -AllowClobber -WarningAction SilentlyContinue -ErrorAction Stop
				}
			}
		
			Write-Host ">>> Connect Azure"
			$timeout = (Get-Date).AddMinutes(5)
			while ($true) {
				try {
					Connect-AzAccount -Identity -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
					Write-Host "- Azure login succeeded"
					break
				} catch {
                    if ((Get-Date) -gt $timeout) { throw }
                    Write-Host "- Azure login failed - retry in 10 seconds"
                    Start-Sleep -Seconds 10
				}
			}
		}

		Invoke-ScriptSection -Title "Download artifacts" -ScriptBlock {

			$jobs = @()

			$links | ForEach-Object { 
			
				Write-Host ">>> Downloading artifact: $_" 
				$ArtifactUrl = Get-ShortcutTargetPath -Path $_ 
				$ArtifactFile = $_.TrimEnd([System.IO.Path]::GetExtension($_))

				if ($ArtifactUrl) {

					$KeyVaultEndpoint = (Get-AzEnvironment -Name AzureCloud | Select-Object -ExpandProperty AzureKeyVaultServiceEndpointResourceId)
					$KeyVaultPattern = $KeyVaultEndpoint.replace('://','://*.').trim() + '/*'
					
					$StorageEndpoint = (Get-AzEnvironment -Name AzureCloud | Select-Object -ExpandProperty StorageEndpointSuffix)
					$StoragePattern = "https://*.blob.$StorageEndpoint/*"

					if ($ArtifactUrl -like $KeyVaultPattern) {

						$jobs += Start-Job -Scriptblock $downloadKeyVaultArtifact -ArgumentList ("$ArtifactUrl", "$ArtifactFile", "$KeyVaultEndpoint")

					} elseif ($ArtifactUrl -like $StoragePattern) {

						$jobs += Start-Job -Scriptblock $downloadStorageArtifact -ArgumentList ("$ArtifactUrl", "$ArtifactFile")

					} else {
						
						$jobs += Start-Job -Scriptblock $downloadArtifact -ArgumentList ("$ArtifactUrl", "$ArtifactFile")
					}
				}

			} -End {

				if ($jobs) {
					Write-Host ">>> Waiting for downloads ..."
					$jobs | Wait-Job | Receive-Job
				}
			}
		}
	}
}