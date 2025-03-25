$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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

# ==============================================================================

$offlineDirectory = Join-Path $env:DEVBOX_HOME 'Offline\WinGet'

if (Test-IsPacker) {

	Invoke-ScriptSection -Title "Downloading WinGet Package Manager" -ScriptBlock {

		Write-Host ">>> Creating WinGet Offline Directory"
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
		$path = Invoke-FileDownload -Url $url -Expand -Retries 5
		
		$os = "$(&{ if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' } })"
		$osPath = Get-ChildItem -Path $path -Filter $os -Recurse -Force `
			| Where-Object { $_.PSIsContainer } `
			| Select-Object -First 1 -ExpandProperty FullName

		if ($osPath) {
			Write-Host ">>> Found architecture specific files in $osPath"
			Get-ChildItem -Path $osPath -Filter '*.appx' -Force | ForEach-Object {
				$destination = Join-Path $offlineDirectory ([IO.Path]::GetFileName($_.FullName))
				Write-Host ">>> Moving $($_.FullName) > $destination"
				Move-Item -Path $_.FullName -Destination $destination -Force | Out-Null
			}
		} else {
			Write-Host ">>> No architecture specific files found in $path"
		}
	}

	Invoke-ScriptSection "Install WinGet Package Manager" -ScriptBlock {

		$taskScript = {

			$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
			if ($winget) { Write-Host ">>> WinGet is available at $winget"; exit 0 }

			if (Test-Path '[WINGETOFFLINE]' -PathType Container) {

				try {

					Get-ChildItem -Path '[WINGETOFFLINE]' -Filter '*.appx' | Select-Object -ExpandProperty FullName | ForEach-Object {
						Write-Host ">>> Installing WinGet Dependency: $_"

						Add-AppxProvisionedPackage `
							-Online  -SkipLicense `
							-PackagePath "$_" `
							-ErrorAction SilentlyContinue | Out-Null

						Add-AppxPackage -Path $_ -ForceTargetApplicationShutdown -ErrorAction SilentlyContinue
					}
				
					Get-ChildItem -Path '[WINGETOFFLINE]' -Filter '*.msixbundle' | Select-Object -ExpandProperty FullName -First 1 | ForEach-Object {
						Write-Host ">>> Installing WinGet Package Manager: $_"

						Add-AppxProvisionedPackage `
							-Online  -SkipLicense `
							-PackagePath "$_" `
							-DependencyPackagePath @(Get-ChildItem -Path '[WINGETOFFLINE]' -Filter '*.appx' | Select-Object -ExpandProperty FullName) `
							-ErrorAction SilentlyContinue | Out-Null

						Add-AppxPackage -Path $_ -ForceTargetApplicationShutdown -ErrorAction SilentlyContinue
					}
				
					Get-ChildItem -Path '[WINGETOFFLINE]' -Filter '*.msix' | Select-Object -ExpandProperty FullName -First 1 | ForEach-Object {
						Write-Host ">>> Installing WinGet Package Source: $_"

						Add-AppxProvisionedPackage `
							-Online  -SkipLicense `
							-PackagePath "$_" `
							-ErrorAction SilentlyContinue | Out-Null

						Add-AppxPackage -Path $_ -ForceTargetApplicationShutdown -ErrorAction SilentlyContinue
					}

				} catch {

					Write-Host $_.Exception

				} finally {

					$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
					if ($winget) { Write-Host ">>> WinGet is available at $winget"; exit 0 }
				}
			}

			Write-Host ">>> Installing Microsoft.WinGet.Client PowerShell module"
			Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery 
			
			Write-Host ">>> Repairing WinGet Package Manager"
			Repair-WinGetPackageManager -Verbose -errorAction SilentlyContinue

			$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
			if ($winget) { Write-Host ">>> WinGet is available at $winget"; exit 0 }
		}
		
		$exitCode = $taskScript | Invoke-ScheduledTask -ScriptTokens @{ 'WINGETOFFLINE' = $offlineDirectory } 
		if ($exitCode -ne 0) { throw "WinGet installation using Scheduled Task failed with exit code $exitCode" }

		$winget = (Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source) 
		if (-not $winget) { throw "WinGet is still not available - check logs" }

		$wingetVersion = (Invoke-CommandLine -Command 'winget' -Arguments '--version' -Silent | Select-Object -ExpandProperty Output) -replace ("`r?`n", '')
		Write-Host ">>> WinGet ($wingetVersion) is available at $winget"
	}

} else {

	Invoke-ScriptSection "Installing WinGet Package Manager" -ScriptBlock {

		if (Test-Path $offlineDirectory -PathType Container) {

			Get-ChildItem -Path $offlineDirectory -Filter '*.appx' | Select-Object -ExpandProperty FullName | ForEach-Object {
				Write-Host ">>> Installing WinGet Dependency: $_"
				Add-AppxPackage -Path $_ -ForceTargetApplicationShutdown -ErrorAction SilentlyContinue
			}
		
			Get-ChildItem -Path $offlineDirectory -Filter '*.msixbundle' | Select-Object -ExpandProperty FullName -First 1 | ForEach-Object {
				Write-Host ">>> Installing WinGet Package Manager: $_"
				Add-AppxPackage -Path $_ -ForceTargetApplicationShutdown -ErrorAction SilentlyContinue
			}
		
			Get-ChildItem -Path $offlineDirectory -Filter '*.msix' | Select-Object -ExpandProperty FullName -First 1 | ForEach-Object {
				Write-Host ">>> Installing WinGet Package Source: $_"
				Add-AppxPackage -Path $_ -ForceTargetApplicationShutdown -ErrorAction SilentlyContinue
			}

			# if winget is already installed - exit
			if (Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source) { exit 0 }
		}

		Write-Host ">>> Installing Microsoft.WinGet.Client PowerShell module"
		Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery 
		
		Write-Host ">>> Repairing WinGet Package Manager"
		Repair-WinGetPackageManager -Verbose

		$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
		
		# winget is still not available - lets blow it
		if (-not $winget) { throw "WinGet is not available - check logs" }

		Write-Host ">>> WinGet is available now: $winget"
	}
}