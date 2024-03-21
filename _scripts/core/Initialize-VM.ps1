
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

	Write-Host ">>> Downloading KeyVault Artifact $Source"
	$KeyVaultToken = Get-AzAccessToken -ResourceUrl $TokenEndpoint -ErrorAction Stop -WarningAction SilentlyContinue
	$KeyVaultHeaders = @{"Authorization" = "Bearer $($KeyVaultToken.Token)"}
	$KeyVaultResponse = Invoke-RestMethod -Uri "$($Source)?api-version=7.1" -Headers $KeyVaultHeaders -ErrorAction Stop
		
	Write-Host ">>> Decoding KeyVault Artifact $Source"
	[System.Convert]::FromBase64String($KeyVaultResponse.value) | Set-Content -Path $Destination -Encoding Byte -Force

	if (Test-Path -Path $Destination -PathType Leaf) {  
		Write-Host ">>> Resolved Artifact $Destination" 
	} else {
		Write-Error "!!! Missing Artifact $Destination"
	}
}

$downloadArtifact = {
	param([string] $Source, [string] $Destination)

	Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
		Import-Module -Name $_
	} 

	Move-Item -Path (Invoke-FileDownload -Url $Source -Name ([System.IO.Path]::GetFileName($Destination))) -Destination $Destination -Force

	if (Test-Path -Path $Destination -PathType Leaf) { 
		Write-Host ">>> Resolved Artifact $Destination" 
	} else {
		Write-Error "!!! Missing Artifact $Destination"
	}
}

Invoke-ScriptSection -Title 'Setting DevBox environment variables' -ScriptBlock {

	[Environment]::SetEnvironmentVariable("DEVBOX_HOME", $devboxHome, [System.EnvironmentVariableTarget]::Machine)
	Get-ChildItem -Path Env:DEVBOX_* | ForEach-Object { [Environment]::SetEnvironmentVariable($_.Name, $_.Value, [System.EnvironmentVariableTarget]::Machine) }
	Get-ChildItem -Path Env:DEVBOX_* | Out-String | Write-Host
}

Invoke-ScriptSection -Title 'Disable Defrag Schedule' -ScriptBlock {

	Get-ScheduledTask ScheduledDefrag | Disable-ScheduledTask | Out-String | Write-Host
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

Invoke-ScriptSection -Title 'Deleting Sysprep Logs' -ScriptBlock {

	Remove-Item -Path $env:SystemRoot\Panther -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
	Remove-Item -Path $env:SystemRoot\System32\Sysprep\Panther -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
	Remove-Item -Path $Env:SystemRoot\System32\Sysprep\unattend.xml -Force -ErrorAction SilentlyContinue | Out-Null
	Write-Host "done"
}

Invoke-ScriptSection -Title 'Disable OneDrive Folder Backup' -ScriptBlock {
	
	$OneDriveRegKeyPath = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
	if (-not(Test-Path -Path $OneDriveRegKeyPath)) { New-Item -Path $OneDriveRegKeyPath -ItemType Directory -Force | Out-Null }
	New-ItemProperty -Path $OneDriveRegKeyPath -Name KFMBlockOptIn -PropertyType DWORD -Value 1 -Force | Out-Null
	Write-Host "done"
}

Invoke-ScriptSection -Title 'Enable Windows Developer Mode' -ScriptBlock {

	$DevModeRegKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
	if (-not(Test-Path -Path $DevModeRegKeyPath)) { New-Item -Path $DevModeRegKeyPath -ItemType Directory -Force | Out-Null }
	New-ItemProperty -Path $DevModeRegKeyPath -Name AllowDevelopmentWithoutDevLicense -PropertyType DWORD -Value 1 -Force | Out-Null
	Write-Host "done"
}

Invoke-ScriptSection -Title 'Enable Hibernate Support' -ScriptBlock {

	Enable-WindowsOptionalFeature -FeatureName "VirtualMachinePlatform" -Online -All -NoRestart | Out-null
	$HypervisorEnforcedCodeIntegrityPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
	if (-not(Test-Path -Path $HypervisorEnforcedCodeIntegrityPath)) { New-Item -Path $HypervisorEnforcedCodeIntegrityPath -ItemType Directory -Force | Out-Null }
	New-ItemProperty -Path $HypervisorEnforcedCodeIntegrityPath -Name Enabled -PropertyType DWORD -Value 0 -Force | Out-Null
	Write-Host "done"
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

Invoke-ScriptSection -Title "Prepare Powershell Gallery" -ScriptBlock {

	Write-Host ">>> Installing NuGet package provider" 
	Install-PackageProvider -Name NuGet -Force | Out-Null

	Write-Host ">>> Register PSGallery"
	Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

	if (Get-Module -ListAvailable -Name PowerShellGet) {
		Write-Host ">>> Upgrading Powershell Module: PowerShellGet"
		Update-Module -Name PowerShellGet -AcceptLicense -Force -WarningAction SilentlyContinue -ErrorAction Stop
	} else {
		Write-Host ">>> Installing Powershell Module: PowerShellGet" 
		Install-Module -Name PowerShellGet -AcceptLicense -Force -AllowClobber -WarningAction SilentlyContinue -ErrorAction Stop
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

					if ($ArtifactUrl -like $KeyVaultPattern) {

						$jobs += Start-Job -Scriptblock $downloadKeyVaultArtifact -ArgumentList ("$ArtifactUrl", "$ArtifactFile", "$KeyVaultEndpoint")

					} else {
						
						$jobs += Start-Job -Scriptblock $downloadArtifact -ArgumentList ("$ArtifactUrl", "$ArtifactFile")
					}
				}

			} -End {

				if ($jobs) {
					Write-Host ">>> Waiting for downloads ..."
					$jobs | Receive-Job -Wait -AutoRemoveJob
				}
			}
		}
	}
}