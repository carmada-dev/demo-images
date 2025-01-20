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
		[string[]] $Dependencies
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
			Add-AppxPackage -Path $Path -DependencyPath $Dependencies -ErrorAction Stop
	
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
}

Invoke-ScriptSection -Title "Installing WinGet Package Manager" -ScriptBlock {

	$offlineDirectory = Join-Path $env:DEVBOX_HOME 'Offline\WinGet'
	$dependenciesDirectory = Join-Path $offlineDirectory 'Dependencies'

	Write-Host ">>> Starting AppXSvc ..."
	Start-Service -Name 'AppXSvc' -ErrorAction SilentlyContinue

	Write-Host ">>> Starting InstallService ..."
	Start-Service -Name 'InstallService' -ErrorAction SilentlyContinue

	$winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
	$wingetManifest = Get-AppxProvisionedPackage -Online | Where-Object -Property DisplayName -EQ 'Microsoft.DesktopAppInstaller' | Select-Object -ExpandProperty InstallLocation -Last 1

	if ($winget) {

		Write-Host ">>> WinGet is already installed: $winget"

	} elseif ($wingetManifest) {

		Write-Host ">>> Install WinGet package: $wingetManifest"
		Add-AppxPackage -Path $wingetManifest -Register -DisableDevelopmentMode -ErrorAction Stop

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