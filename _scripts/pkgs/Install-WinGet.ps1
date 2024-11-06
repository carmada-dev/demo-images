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
		[string] $Path
	)

	try
	{
		Write-Host ">>> Installing Package: $Path"
		Add-AppxPackage -Path $Path -ForceApplicationShutdown -ForceUpdateFromAnyVersion -ErrorAction Stop
	}
	catch
	{
		if ($_.Exception.Message -match '0x80073D06') {
			Write-Warning ($_.Exception.Message)
		} else {

			$activityIdsPattern = '\b[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}\b'
			$activityIds = [regex]::Matches($_.Exception.Message, $activityIdsPattern) | ForEach-Object { $_.Value } | Select-Object -Unique

			$activityIds | ForEach-Object {
				Write-Warning ($_.Exception.Message)
				Write-Host "----------------------------------------------------------------------------------------------------------"
				Get-AppxLog -ActivityId $_ | Out-Host
			}

			throw
		}
	}
}

Invoke-ScriptSection -Title "Installing WinGet Package Manager" -ScriptBlock {

	$offlineDirectory =	New-Item -Path (Join-Path $env:DEVBOX_HOME 'Offline\WinGet') -ItemType Directory -Force | Select-Object -ExpandProperty FullName
	Write-Host "- Offline directory: $offlineDirectory"

	$osType = (&{ if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' } })
	Write-Host "- OS Type: $osType"

	$loc = Join-Path $offlineDirectory 'Dependencies'

	if (-not(Test-Path $loc -PathType Leaf)) {

		Write-Host ">>> Downloading WinGet dependencies ..."

		$url = Get-GitHubLatestReleaseDownloadUrl -Organization 'microsoft' -Repository 'winget-cli' -Asset 'DesktopAppInstaller_Dependencies.zip'
		$path = Join-Path (Invoke-FileDownload -Url $url -Expand -Retries 5) $osType
		
		Get-ChildItem -Path $path -Filter '*.*' | ForEach-Object {
			
			if (-not(Test-Path $loc -PathType Container)) {
				Write-Host ">>> Creating dependency directory: $loc"
				New-Item -Path $loc -ItemType Directory -Force | Out-Null
			}

			$destination = Join-Path $loc ([IO.Path]::GetFileName($_.FullName))

			Write-Host ">>> Moving $($_.FullName) > $destination"
			Move-Item -Path $_.FullName -Destination $destination -Force | Out-Null
		}
	}

	Write-Host ">>> Installing WinGet dependencies ..."
	Get-ChildItem -Path $loc -Filter '*.*' | ForEach-Object { Install-Package -Path $_.FullName }

	$url = Get-GitHubLatestReleaseDownloadUrl -Organization 'microsoft' -Repository 'winget-cli' -Asset 'msixbundle'
	$loc = Join-Path $offlineDirectory ([IO.Path]::GetFileName($url))

	if (-not (Test-Path $loc -PathType Leaf)) {

		Write-Host ">>> Downloading WinGet CLI ..."
		$path = Invoke-FileDownload -Url $url -Name ([IO.Path]::GetFileName($loc)) -Retries 5
		
		Write-Host ">>> Moving $path > $loc"
		Move-Item -Path $path -Destination $loc -Force | Out-Null
	}

	Write-Host ">>> Installing WinGet CLI..."
	Install-Package -Path $loc 

	if (Test-IsElevated) {
		Write-Host ">>> Resetting WinGet Sources ..."
		Invoke-CommandLine -Command 'winget' -Arguments "source reset --force --disable-interactivity" | Select-Object -ExpandProperty Output | Write-Host
	}

	$url = "https://cdn.winget.microsoft.com/cache/source.msix"
	$loc = Join-Path $offlineDirectory ([IO.Path]::GetFileName($url))

	if (-not(Test-Path $loc -PathType Leaf)) {
		Write-Host ">>> Downloading WinGet Source Cache Package ..."
		$path = Invoke-FileDownload -Url $url -Name ([IO.Path]::GetFileName($loc)) -Retries 5
		Move-Item -Path $path -Destination $loc -Force | Out-Null
	}

	Write-Host ">>> Installing WinGet Source Cache Package ..."	
	Install-Package -Path $loc 
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