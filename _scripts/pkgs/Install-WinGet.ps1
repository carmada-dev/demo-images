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
		Write-Host ">>> Dump ACLs for $Path ..."
		Get-Acl -Path $Path | Format-Table -Wrap -AutoSize | Out-Host

		if ($Dependencies) {
		
			$Dependencies | ForEach-Object {
				Write-Host ">>> Dump ACLs for $_ ..."
				Get-Acl -Path $_ | Format-Table -Wrap -AutoSize | Out-Host
			}

			Write-Host ">>> Installing Package: $Path (Dependencies: $($Dependencies -join ', '))"
			Add-AppxPackage -Path $Path -DependencyPath $Dependencies -ForceApplicationShutdown -ForceUpdateFromAnyVersion -ErrorAction Stop
	
		} else {

			Write-Host ">>> Installing Package: $Path"
			Add-AppxPackage -Path $Path -ErrorAction Stop
	
		}
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

	Invoke-ScriptSection -Title "Removing Provisioned WinGet Packages" -ScriptBlock {

		$offlineDirectory = Join-Path $env:DEVBOX_HOME 'Offline\WinGet'
		$packageNames = [System.Collections.Generic.List[String]]::new() 

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
						$packageName = ([xml](Get-Content $manifest)).Package.Identity.Name 
					} else {
						# extract the package name from the bundle manifest
						$manifest = Get-ChildItem -Path $destination -Filter 'AppxBundleManifest.xml' -Recurse | Select-Object -ExpandProperty FullName -First 1
						if ($manifest) { 	
							$packageName = ([xml](Get-Content $manifest)).Bundle.Identity.Name 
						}
					}

					# add the package name to the queue
					if ($packageName) {
						$packageNames.Add($packageName)
						Write-Host ">>> Identified package '$packageName' ($_)"
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

		Write-Host ">>> Removing $($packageNames.Count) provisioned packages "
		$packageNames | ForEach-Object { Write-Host "- $_" }
		$packageCount = $packageNames.Count

		while ($packageNames.Count -gt 0) {

			for ($i = $array.Count - 1; $i -ge 0 ; $i--) {

				$packageName = $packageNames[$i]
				Write-Host ">>> Removing package: $packageName"

				try {

					if ((Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Status) -eq 'Ok') {
						Write-Host "- Installed package"
						Remove-AppxPackage -PackageName $packageName -AllUsers -ErrorAction SilentlyContinue
					}

					Write-Host "- Provisioned package"
					Remove-AppxProvisionedPackage -PackageName $packageName -AllUsers -Online

					# remove the package from the list
					$packageNames.RemoveAt($i)
				}
				catch {

					Write-Warning $_.Exception.Message

				}
			}

			if ($packageCount -eq $packageNames.Count) {
				throw "Failed to remove any packages"
			} else {
				$packageCount = $packageNames.Count
			}

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

		if (Test-IsElevated) {
			Write-Host ">>> Resetting WinGet Sources ..."
			Invoke-CommandLine -Command 'winget' -Arguments "source reset --force --disable-interactivity" | Select-Object -ExpandProperty Output | Write-Host
		}

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