Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Install-WinGet.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

$adminWinGetConfig = @"
{
	"`$schema": "https://aka.ms/winget-settings.schema.json",
	"installBehavior": {
		"preferences": {
			"scope": "machine"
		}
	},
	"experimentalFeatures": {
		"configuration": true
	}
}
"@

function Install-Package() {
	param (
		[Parameter()]
		[string] $Path,
		[Parameter(Mandatory = $false)]
		[string[]] $Dependencies = @()
	)

	try
	{
		# Write-Host ">>> Dump ACLs for $Path ..."
		# Get-Acl -Path $Path | Format-Table -Wrap -AutoSize | Out-Host

		# $Dependencies | ForEach-Object {
		# 	Write-Host ">>> Dump ACLs for $_ ..."
		# 	Get-Acl -Path $_ | Format-Table -Wrap -AutoSize | Out-Host
		# }

		Write-Host ">>> Installing Package: $Path (Dependencies: $($Dependencies -join ', '))"
		Add-AppxPackage -Path $Path -DependencyPath $Dependencies -ForceApplicationShutdown -ForceUpdateFromAnyVersion -ErrorAction Stop
	}
	catch
	{
		$exceptionMessage = $_.Exception.Message

		if ($exceptionMessage -match '0x80073D06') {

			Write-Warning $exceptionMessage

		} else {


			$activityIdsPattern = '\b[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}\b'
			$activityIds = [regex]::Matches($exceptionMessage, $activityIdsPattern) | ForEach-Object { $_.Value } | Select-Object -Unique

			$activityIds | ForEach-Object {
				Write-Warning $exceptionMessage
				Write-Host "----------------------------------------------------------------------------------------------------------"
				Get-AppxLog -ActivityId $_ | Out-Host
			}

			throw
		}
	}
}


if (Test-IsPacker) {
	
	Invoke-ScriptSection -Title "Downloading WinGet Package Manager" -ScriptBlock {

		$offlineDirectory = Join-Path $env:DEVBOX_HOME 'Offline\WinGet'
		$dependenciesDirectory = Join-Path $offlineDirectory 'Dependencies'
		$osType = (&{ if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' } })

		Write-Host ">>> Ensure offline directory: $offlineDirectory"
		New-Item -Path $offlineDirectory -ItemType Directory -Force | Out-Null

		$url = Get-GitHubLatestReleaseDownloadUrl -Organization 'microsoft' -Repository 'winget-cli' -Asset 'msixbundle'
		$path = Invoke-FileDownload -Url $url -Name ([IO.Path]::GetFileName($url)) -Retries 5
		$destination = Join-Path $offlineDirectory ([IO.Path]::GetFileName($path))

		Write-Host ">>> Moving $path > $destination"
		Move-Item -Path $path -Destination $destination -Force | Out-Null

		$url = "https://cdn.winget.microsoft.com/cache/source.msix"
		$path = Invoke-FileDownload -Url $url -Name ([IO.Path]::GetFileName($url)) -Retries 5
		$destination = Join-Path $offlineDirectory ([IO.Path]::GetFileName($path))

		Write-Host ">>> Moving $path > $destination"
		Move-Item -Path $path -Destination $destination -Force | Out-Null

		$url = Get-GitHubLatestReleaseDownloadUrl -Organization 'microsoft' -Repository 'winget-cli' -Asset 'DesktopAppInstaller_Dependencies.zip'
		$path = Join-Path (Invoke-FileDownload -Url $url -Expand -Retries 5) $osType
		
		Get-ChildItem -Path $path -Filter '*.*' | ForEach-Object {
			
			if (-not(Test-Path $dependenciesDirectory -PathType Container)) {
				Write-Host ">>> Creating dependency directory: $dependenciesDirectory"
				New-Item -Path $dependenciesDirectory -ItemType Directory -Force | Out-Null
			}

			$destination = Join-Path $dependenciesDirectory ([IO.Path]::GetFileName($_.FullName))

			Write-Host ">>> Moving $($_.FullName) > $destination"
			Move-Item -Path $_.FullName -Destination $destination -Force | Out-Null
		}
	}

	Invoke-ScriptSection -Title "Fix WinGet Package Permissions" -ScriptBlock {

		$offlineDirectory = Join-Path $env:DEVBOX_HOME 'Offline\WinGet'
		$packages = [System.Collections.Generic.List[PSCustomObject]]::new() 

		Get-ChildItem -Path $offlineDirectory -Recurse -File | Select-Object -ExpandProperty FullName | ForEach-Object {

			$temporary = [System.IO.Path]::ChangeExtension($_, '.zip')
			$destination = Join-Path $env:TEMP ([System.IO.Path]::GetFileNameWithoutExtension($_))
			
			# ensure destination folder does not exist
			Remove-Item $destination -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
		
			try {
				# expand the package to a temporary location (using the zip version of the package file)
				Expand-Archive `
					-Path (Move-Item -Path $_ -Destination $temporary -PassThru -Force | Select-Object -ExpandProperty FullName) `
					-DestinationPath $destination `
					-Force `
					-ErrorAction SilentlyContinue
			}
			finally
			{
				# rename the temporary file back to the original
				Move-Item -Path $temporary -Destination $_ -Force -ErrorAction SilentlyContinue
			}
		
			if (Test-Path -Path $destination -PathType Container) {
		
				try {
					# extract the package name from the manifest
					$manifest = Get-ChildItem -Path $destination -Filter 'AppxManifest.xml' -Recurse | Select-Object -ExpandProperty FullName -First 1
					if ($manifest) { 
						$xml = ([xml](Get-Content $manifest))	
						$packageName = $xml.Package.Identity.Name 
						$packageVersion = $xml.Package.Identity.Version
					} else {
						# extract the package name from the bundle manifest
						$manifest = Get-ChildItem -Path $destination -Filter 'AppxBundleManifest.xml' -Recurse | Select-Object -ExpandProperty FullName -First 1
						if ($manifest) { 	
							$xml = ([xml](Get-Content $manifest))	
							$packageName = $xml.Bundle.Identity.Name 
							$packageVersion = $xml.Bundle.Identity.Version
						}
					}

					# add the package name/version to the queue
					if ($packageName -and $packageVersion) {
						Write-Host ">>> Identified package '$packageName' ($packageVersion) in $_"
						$packages.Add([PSCustomObject]@{
							Name = $packageName
							Version = $packageVersion
						})
					}
				}
				catch {
					# ignore any errors	
				}					
				finally {
					# remove the temporary folder
					Remove-Item -Path $destination -Force -Recurse -ErrorAction SilentlyContinue
				}
			}
		}

		$packages | ForEach-Object -Begin {

				$paths = @(
					Join-Path $env:ProgramFiles 'WindowsApps'
				)

				$paths | ForEach-Object {

					Write-Host ">>> Grant fullcontrol to user $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name): $_"
					Invoke-CommandLine -AsSystem -Command 'icacls' -Arguments "`"$_`" /grant $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name):F /c" `
						| Select-Object -ExpandProperty Output `
						| Write-Host

					Write-Host ">>> Dump ACLs: $_"
					Get-Acl -Path $_ | Format-Table -Wrap -AutoSize | Out-Host
				}
				
			} -Process {

				$package = $_

				Get-AppxProvisionedPackage -Online | Where-Object { ($_.DisplayName -eq $package.Name) -and ($_.InstallLocation) } | ForEach-Object {

					# Write-Host ">>> Grant fullcontrol to user $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name): $_"
					# Invoke-CommandLine -AsSystem -Command 'icacls' -Arguments "`"$(Split-Path $_.InstallLocation -Parent)`" /grant $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name):F /c" `
					# 	| Select-Object -ExpandProperty Output `
					# 	| Write-Host

					Write-Host ">>> Dump ACLs for $($package.Name) ($($_.Version)): $(Split-Path $_.InstallLocation -Parent)"
					Get-Acl -Path (Split-Path $_.InstallLocation -Parent) | Format-Table -Wrap -AutoSize | Out-Host

					Write-Host ">>> Remove provisioned package $($package.Name) ($($_.Version)): $(Split-Path $_.InstallLocation -Parent)"
					# $_ | Remove-AppxProvisionedPackage -AllUsers -Online -ErrorAction Continue
					Invoke-CommandLine -AsSystem -Command 'powershell' -Arguments "-ExecutionPolicy Bypass -WindowStyle Hidden -Command `"Remove-AppxProvisionedPackage -PackageName '$($_.PackageName)' -AllUsers -Online`"" `
						| Select-Object -ExpandProperty Output `
						| Write-Host
				}

				Get-AppxPackage -AllUsers | Where-Object { ($_.Name -eq $package.Name) -and ($_.InstallLocation) } | ForEach-Object {

					# Write-Host ">>> Grant fullcontrol to user $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name): $_"
					# Invoke-CommandLine -AsSystem -Command 'icacls' -Arguments "`"$($_.InstallLocation)`" /grant $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name):F /c" `
					# 	| Select-Object -ExpandProperty Output `
					# 	| Write-Host

					Write-Host ">>> Dump ACLs for $($package.Name) ($($_.Version)): $($_.InstallLocation)"
					Get-Acl -Path $_.InstallLocation | Format-Table -Wrap -AutoSize | Out-Host

					Write-Host ">>> Remove installed package $($package.Name) ($($_.Version)): $($_.InstallLocation)"
					# $_ | Remove-AppxPackage -AllUsers -ErrorAction Continue
					Invoke-CommandLine -AsSystem -Command 'powershell' -Arguments "-ExecutionPolicy Bypass -WindowStyle Hidden -Command `"Remove-AppxPackage -Package '$($_.PackageName)' -AllUsers`"" `
						| Select-Object -ExpandProperty Output `
						| Write-Host
				}

			} -End {

				Write-Host ">>> Installed Packages (ALL) ..."
				Get-AppxPackage -AllUsers | Sort-Object -Property Name | Format-Table -Property Name, Version | Out-Host

				Write-Host ">>> Provisioned Packages (ALL) ..."
				Get-AppxProvisionedPackage -Online | Sort-Object -Property DisplayName | Format-Table -Property DisplayName, Version | Out-Host
			}

		if ($packages.Count -gt 0) {



			# Write-Host ">>> Removing $($packages.Count) provisioned packages "
			# $packages | ForEach-Object { Write-Host "- $($_.Name) ($($_.Version))" }
			# $packageCount = $packages.Count

			# while ($packages.Count -gt 0) {
			# 	for ($i = $packages.Count - 1; $i -ge 0 ; $i--) {

			# 		$package = $packages[$i]
			# 		Write-Host ">>> Removing package: $($package.Name) ($($package.Version))"

			# 		try {

			# 			Get-AppxPackage -Name $package.Name | Where-Object { $_.Version -eq $package.Version } | ForEach-Object {
			# 				Write-Host "- Installed package"
			# 				$_ | Remove-AppxPackage -AllUsers 
			# 			}

			# 			Get-AppxProvisionedPackage -Online | Where-Object { ($_.PackageName -eq $package.Name) -and ($_.Version -eq $package.Version) } | ForEach-Object {
			# 				Write-Host "- Provisioned package"	
			# 				$_ | Remove-AppxProvisionedPackage -AllUsers -Online
			# 			}

			# 			# remove the package from the list
			# 			$packages.RemoveAt($i)
			# 		}
			# 		catch {

			# 			Write-Warning $_.Exception.Message
			# 		}
			# 	}

			# 	if ($packageCount -eq $packages.Count) {
			# 		throw "Failed to remove packages: $(($packages | ForEach-Object { "$($_.Name) ($($_.Version))" }) -join ', ')"
			# 	} else {
			# 		$packageCount = $packages.Count
			# 	}
			# }
		}
	}
}

Invoke-ScriptSection -Title "Installing WinGet Package Manager" -ScriptBlock {

	$offlineDirectory = Join-Path $env:DEVBOX_HOME 'Offline\WinGet'
	$dependenciesDirectory = Join-Path $offlineDirectory 'Dependencies'

	Write-Host ">>> Starting AppXSvc ..."
	Start-Service -Name 'AppXSvc' -ErrorAction SilentlyContinue

	Write-Host ">>> Starting InstallService ..."
	Start-Service -Name 'InstallService' -ErrorAction SilentlyContinue

	$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
	if ($winget) {

		Write-Host ">>> WinGet is already installed"
		Write-Host ">>> Path: $winget"
		Write-Host ">>> Version: $((Invoke-CommandLine -Command $winget -Arguments "--version" | Select-Object -ExpandProperty Output) -replace '\r\n', '')"

	} else {

		$wingetPackage = Get-ChildItem -Path $offlineDirectory -Filter '*.msixbundle' | Select-Object -ExpandProperty FullName -First 1
		$wingetDependencies = Get-ChildItem -Path $dependenciesDirectory -Filter '*.*' | Select-Object -ExpandProperty FullName
		$wingetCache = Get-ChildItem -Path $offlineDirectory -Filter '*.msix' | Select-Object -ExpandProperty FullName -First 1

		Write-Host ">>> Installing Package: $wingetPackage"
		Install-Package -Path $wingetPackage -Dependencies @($wingetDependencies) -ErrorAction Stop		

		# if (Test-IsElevated) {
		# 	Write-Host ">>> Resetting WinGet Sources ..."
		# 	Invoke-CommandLine -Command 'winget' -Arguments "source reset --force --disable-interactivity" | Select-Object -ExpandProperty Output | Write-Host
		# }

		Write-Host ">>> Installing WinGet Source Cache Package ..."	
		Install-Package -Path $wingetCache -ErrorAction Stop
	}
}

if (Test-IsPacker) {
	Invoke-ScriptSection -Title "Patching WinGet Config for Packer Mode" -ScriptBlock {

		$wingetPackageFamilyName = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' | Select-Object -ExpandProperty PackageFamilyName

		@(

			"%LOCALAPPDATA%\Packages\$wingetPackageFamilyName\LocalState\settings.json",
			"%LOCALAPPDATA%\Microsoft\WinGet\Settings\settings.json"

		) | ForEach-Object { [System.Environment]::ExpandEnvironmentVariables($_) } | Where-Object { Test-Path (Split-Path -Path $_ -Parent) -PathType Container } | ForEach-Object { 

			Write-Host ">>> Patching WinGet Settings: $_"
			$adminWinGetConfig | Out-File $_ -Encoding ASCII -Force 
			
		}
	}
}