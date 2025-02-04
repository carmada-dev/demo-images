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

	$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
	if ($winget) {

		Write-Host ">>> WinGet is already installed"
		Write-Host ">>> Path: $winget"
		Write-Host ">>> Version: $((Invoke-CommandLine -Command $winget -Arguments "--version" | Select-Object -ExpandProperty Output) -replace '\r\n', '')"

	} else {

		Get-ChildItem -Path $dependenciesDirectory -Filter '*.*' | Select-Object -ExpandProperty FullName | ForEach-Object {
			Install-Package -Path $_ -ErrorAction Continue
		}

		Get-ChildItem -Path $offlineDirectory -Filter '*.*' | Select-Object -ExpandProperty FullName | ForEach-Object {
			Install-Package -Path $_ -ErrorAction Continue
		}

		Get-ChildItem -Path $sourceDirectory -Filter '*.*' | Select-Object -ExpandProperty FullName | ForEach-Object {
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