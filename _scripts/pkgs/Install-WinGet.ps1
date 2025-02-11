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

$scriptPath = $MyInvocation.MyCommand.Path
$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
$wingetOffline = (Join-Path $env:DEVBOX_HOME 'Offline\WinGet')

if ($winget) {

	Write-Host ">>> WinGet is already installed: $winget"

} elseif (Test-IsSystem) {

		# the only thing we do when running as SYSTEM is to install WinGet
		Invoke-ScriptSection -Title "Installing WinGet Package Manager (SYSTEM)" -ScriptBlock {

			Install-PackageProvider -Name NuGet -Force | Out-Null
			Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null

			Write-Host ">>> Installing WinGet Package Manager"
			Repair-WinGetPackageManager -AllUsers -Latest -Force
		}

} else {
	
	$staged = [bool] (Get-AppxPackage -AllUsers | Where-Object { ($_.PackageUserInformation.InstallState -eq 'Staged') -and ($_.PackageFamilyName -eq 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe') })

	if (Test-IsPacker) {
		if ($staged) {

			# if the script runs at Packer, it will elevates itself to run as SYSTEM first to install WinGet
			Invoke-CommandLine -Command "powershell" -Arguments "-NoLogo -Mta -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" -AsSystem `
				| Select-Object -ExpandProperty Output `
				| Write-Host

		} else {

			Invoke-ScriptSection -Title "Downloading WinGet Package Manager" -ScriptBlock {

				Write-Host ">>> Creating WinGet Offline Directory"
				New-Item -Path $wingetOffline -ItemType Directory -Force | Out-Null

				$url = Get-GitHubLatestReleaseDownloadUrl -Organization 'microsoft' -Repository 'winget-cli' -Asset 'xml'
				$path = Invoke-FileDownload -Url $url -Name 'License.xml' -Retries 5
				$destination = Join-Path $offlineDirectory ([IO.Path]::GetFileName($path))

				Write-Host ">>> Moving $path > $destination"
				Move-Item -Path $path -Destination $destination -Force | Out-Null

				$url = Get-GitHubLatestReleaseDownloadUrl -Organization 'microsoft' -Repository 'winget-cli' -Asset 'msixbundle'
				$path = Invoke-FileDownload -Url $url -Name ([IO.Path]::GetFileName($url)) -Retries 5
				$destination = Join-Path $offlineDirectory ([IO.Path]::GetFileName($path))

				Write-Host ">>> Moving $path > $destination"
				Move-Item -Path $path -Destination $destination -Force | Out-Null

				$url = "https://cdn.winget.microsoft.com/cache/source.msix"
				$path = Invoke-FileDownload -Url $url -Name ([IO.Path]::GetFileName($url)) -Retries 5
				$destination = Join-Path $wingetOffline ([IO.Path]::GetFileName($path))

				Write-Host ">>> Moving $path > $destination"
				Move-Item -Path $path -Destination $destination -Force | Out-Null

				$url = Get-GitHubLatestReleaseDownloadUrl -Organization 'microsoft' -Repository 'winget-cli' -Asset 'DesktopAppInstaller_Dependencies.zip'
				$path = Join-Path (Invoke-FileDownload -Url $url -Expand -Retries 5) $osType
				
				Get-ChildItem -Path $path -Filter '*.*' | ForEach-Object {

					$destination = Join-Path $wingetOffline ([IO.Path]::GetFileName($_.FullName))

					Write-Host ">>> Moving $($_.FullName) > $destination"
					Move-Item -Path $_.FullName -Destination $destination -Force | Out-Null
				}
			}
		}
	}

	if ($staged) {

		Invoke-ScriptSection -Title "Registering WinGet Package Manager" -ScriptBlock {

			Write-Host ">>> Registering WinGet Package Manager"
			Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe		
		}

	} elseif (Test-Path -Path $wingetOffline -PathType Container) {

		Invoke-ScriptSection -Title "Installing WinGet Package Manager (OFFLINE)" -ScriptBlock {

			$wingetPackage = Get-ChildItem -Path $offlineDirectory -Filter '*.msixbundle' | Select-Object -ExpandProperty FullName -First 1
			$wingetDependencies = @( Get-ChildItem -Path $offlineDirectory -Filter '*.appx' | Select-Object -ExpandProperty FullName )
			$wingetSource = Get-ChildItem -Path $offlineDirectory -Filter '*.msix' | Select-Object -ExpandProperty FullName -First 1
	
			if ($wingetPackage) {
	
				Write-Host ">>> Installing WinGet Package Manager with Dependencies"
				Add-AppxPackage `
					-Path $wingetPackage `
					-DependencyPath $wingetDependencies `
					-ForceTargetApplicationShutdown `
					-StubPackageOption UsePreference `
					-ErrorAction Stop
	
				if ($wingetSource) {
	
					Write-Host ">>> Installing WinGet Package Source"
					Add-AppxPackage `
						-Path $wingetSource `
						-ForceTargetApplicationShutdown `
						-StubPackageOption UsePreference `
						-ErrorAction Stop
						
				}
			}
		}
	}

	Invoke-ScriptSection -Title "Validating installed WinGet CLI" -ScriptBlock {

		$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
		Write-Host "- Path: $winget"

		if ($winget) {

			$wingetVersion = Invoke-CommandLine -Command $winget -Arguments '--version' -Capture StdOut -Silent | Select-Object -ExpandProperty Output 
			Write-Host "- Version: $wingetVersion"

		} 
	}

	if (Test-IsPacker) {

		# to ensure WinGet if prefering machine scope installers when running as Packer we nneed to patch the WinGet configuration
		Invoke-ScriptSection -Title "Patching WinGet Config for Packer Mode" -ScriptBlock {

			$wingetPackageFamilyName = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' | Select-Object -ExpandProperty PackageFamilyName

			@(

				"%LOCALAPPDATA%\Packages\$wingetPackageFamilyName\LocalState\settings.json",
				"%LOCALAPPDATA%\Microsoft\WinGet\Settings\settings.json"

			) | ForEach-Object { [System.Environment]::ExpandEnvironmentVariables($_) } | Where-Object { Test-Path (Split-Path -Path $_ -Parent) -PathType Container } | ForEach-Object { 

				Write-Host ">>> Patching WinGet ($winGetVersion) Settings: $_"
				$adminWinGetConfig | Out-File $_ -Encoding ASCII -Force 
				
			}
		} 

	} 
} 
