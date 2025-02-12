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

function Install-WinGet {

	$PsInstallScope = "$(&{ if (Test-IsSystem) { 'AllUsers' } else { 'CurrentUser' } })"
	$wingetOffline = (Join-Path $env:DEVBOX_HOME 'Offline\WinGet')

	$nugetProviderVersion = "2.8.5.201"
	$wingetClientVersion = "1.9.2411"
	$wingetConfigVersion = "1.8.1911"

	Invoke-ScriptSection -Title "Installing WinGet Package Manager ($PsInstallScope)" -ScriptBlock {

		if (-not (Get-PackageProvider | Where-Object { $_.Name -eq "NuGet" -and $_.Version -gt $nugetProviderVersion })) {
			Write-Host ">>> Installing NuGet Package Provider: $nugetProviderVersion"
			Install-PackageProvider -Name NuGet -MinimumVersion $nugetProviderVersion -Force -Scope $PsInstallScope
		}

		Write-Host ">>> Set PSGallery as Trusted Repository"
		Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
    	powershell.exe -MTA -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted"

		if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client | Where-Object { $_.Version -ge $wingetClientVersion })) {
			Write-Host ">>> Installing Microsoft.Winget.Client: $wingetClientVersion"
			Install-Module Microsoft.WinGet.Client -Scope $PsInstallScope -RequiredVersion $wingetClientVersion
			powershell.exe -MTA -Command "Install-Module Microsoft.WinGet.Client -Scope $PsInstallScope -RequiredVersion $wingetClientVersion"
		}

		# if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Configuration | Where-Object { $_.Version -ge $wingetConfigVersion })) {
		# 	Write-Host ">>> Installing Microsoft.Winget.Configuration: $wingetConfigVersion"
		# 	Install-Module Microsoft.WinGet.Configuration -Scope $PsInstallScope -RequiredVersion $wingetConfigVersion
		# 	powershell.exe -MTA -Command "Install-Module Microsoft.WinGet.Configuration -Scope $PsInstallScope -RequiredVersion $wingetConfigVersion"
		# }

		Write-Host ">>> Installing/Repairing WinGet Package Manager"
		powershell.exe -MTA -Command "Repair-WinGetPackageManager -Latest -Force -Verbose"

		if (-not (Test-IsSystem)) {

			if (Test-IsPacker -and -not (Test-Path -Path $wingetOffline)) {

				$osType = "$(&{ if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' } })"

				Write-Host ">>> Creating WinGet Offline Directory: $wingetOffline"
				New-Item -Path $wingetOffline -ItemType Directory -Force | Out-Null

				$url = Get-GitHubLatestReleaseDownloadUrl -Organization 'microsoft' -Repository 'winget-cli' -Asset 'msixbundle'
				$path = Invoke-FileDownload -Url $url -Name ([IO.Path]::GetFileName($url)) -Retries 5
				$destination = Join-Path $offlineDirectory ([IO.Path]::GetFileName($path))

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

			Get-ChildItem -Path $offlineDirectory -Filter '*.appx' | Select-Object -ExpandProperty FullName | ForEach-Object {

				Write-Host ">>> Installing WinGet Package Manager Dependency: $_"
				Add-AppxPackage -Path $_ -ForceApplicationShutdown -ErrorAction Continue
			}

			Get-ChildItem -Path $offlineDirectory -Filter '*.msixbundle' | Select-Object -ExpandProperty FullName | ForEach-Object {

				Write-Host ">>> Installing WinGet Package Manager: $_"
				Add-AppxPackage -Path $_ -ForceApplicationShutdown -ErrorAction Continue
			}
		}

		Write-Host ">>> Registering WinGet Package Manager"
		Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe

		Write-Host ">>> Revert PSGallery to Untrusted Repository"
		Set-PSRepository -Name "PSGallery" -InstallationPolicy Untrusted
    	powershell.exe -MTA -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Untrusted"
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

$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source

if ($winget) {

	Write-Host ">>> WinGet is already installed: $winget"

} else {

	if (Test-IsPacker) {

		Invoke-CommandLine -Command "powershell" -Arguments "-NoLogo -Mta -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Path)`"" -AsSystem `
			| Select-Object -ExpandProperty Output `
			| Write-Host
			
	}

	Install-WinGet
} 
