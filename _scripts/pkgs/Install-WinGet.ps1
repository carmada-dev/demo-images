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

$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
$wingetStaged = [bool] (Get-AppxPackage -AllUsers | Where-Object { ($_.PackageUserInformation.InstallState -eq 'Staged') -and ($_.PackageFamilyName -eq 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe') })

if ($winget) {

	Write-Host ">>> WinGet is already installed: $winget"

} elseif ($wingetStaged) {

	Invoke-ScriptSection -Title "Register staged WinGet Package Manager" -ScriptBlock {

		try {

			Write-Host ">>> Register WinGet"
			Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
		
		} catch {

			write-Warning $_.Exception.Message
		}
		
		# retry to get the winget command
		$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source

		if (-not $winget) {

			Write-Host ">>> Repair WinGet"
			Invoke-CommandLine -Command 'powershell' -Arguments '-NoLogo -ExecutionPolicy ByPass -Command "& { Install-PackageProvider -Name NuGet -Force | Out-Null ; Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null ; Repair-WinGetPackageManager -AllUsers -Latest -Force }"' -AsSystem | Select-Object -ExpandProperty Output | Write-Host 
			
			# Write-Host "- Installing NuGet package provider"
			# Install-PackageProvider -Name NuGet -Force | Out-Null

			# Write-Host "- Installing WinGet Powershell Module"
			# Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null

			# Write-Host "- Repairing WinGet"
			# Repair-WinGetPackageManager -AllUsers -Latest -Force 
			
		}
	}

} else {

	$offlineDirectory = (New-Item -Path (Join-Path $env:DEVBOX_HOME 'Offline\WinGet') -ItemType Directory -Force).FullName
	$dependenciesDirectory = (New-Item -Path (Join-Path $offlineDirectory 'Dependencies') -ItemType Directory -Force).FullName
	$sourceDirectory = (New-Item -Path (Join-Path $offlineDirectory 'Source') -ItemType Directory -Force).FullName
	$osType = (&{ if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' } })

	if (Test-IsPacker) {
		
		Invoke-ScriptSection -Title "Downloading WinGet Package Manager" -ScriptBlock {

			$url = Get-GitHubLatestReleaseDownloadUrl -Organization 'microsoft' -Repository 'winget-cli' -Asset 'msixbundle'
			$path = Invoke-FileDownload -Url $url -Name ([IO.Path]::GetFileName($url)) -Retries 5
			$destination = Join-Path $offlineDirectory ([IO.Path]::GetFileName($path))

			Write-Host ">>> Moving $path > $destination"
			Move-Item -Path $path -Destination $destination -Force | Out-Null

			$url = "https://cdn.winget.microsoft.com/cache/source.msix"
			$path = Invoke-FileDownload -Url $url -Name ([IO.Path]::GetFileName($url)) -Retries 5
			$destination = Join-Path $sourceDirectory ([IO.Path]::GetFileName($path))

			Write-Host ">>> Moving $path > $destination"
			Move-Item -Path $path -Destination $destination -Force | Out-Null

			$url = Get-GitHubLatestReleaseDownloadUrl -Organization 'microsoft' -Repository 'winget-cli' -Asset 'DesktopAppInstaller_Dependencies.zip'
			$path = Join-Path (Invoke-FileDownload -Url $url -Expand -Retries 5) $osType
			
			Get-ChildItem -Path $path -Filter '*.*' | ForEach-Object {

				$destination = Join-Path $dependenciesDirectory ([IO.Path]::GetFileName($_.FullName))

				Write-Host ">>> Moving $($_.FullName) > $destination"
				Move-Item -Path $_.FullName -Destination $destination -Force | Out-Null
			}
		}
	}

	Invoke-ScriptSection -Title "Installing WinGet Package Manager" -ScriptBlock {

		Write-Host ">>> Installing WinGet Dependencies"
		Get-ChildItem -Path $dependenciesDirectory -Filter '*.*' `
			| Select-Object -ExpandProperty FullName `
			| ForEach-Object { 
				Write-Host "- $_"
				Install-Package -Path $_ -ErrorAction Continue 
			}

		Write-Host ">>> Installing WinGet Package Manager"
		Get-ChildItem -Path $offlineDirectory -Filter '*.*' `
			| Select-Object -ExpandProperty FullName `
			| ForEach-Object { 
				Write-Host "- $_"
				Install-Package -Path $_ -ErrorAction Continue 
			}

		Write-Host ">>> Installing WinGet Source"
		Get-ChildItem -Path $sourceDirectory -Filter '*.*' `
			| Select-Object -ExpandProperty FullName `
			| ForEach-Object { 
				Write-Host "- $_"
				Install-Package -Path $_ -ErrorAction Continue 
			}
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