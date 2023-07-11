# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$ProgressPreference = 'SilentlyContinue'	# hide any progress output

$adminWinGetConfig = @"
{
	"`$schema": "https://aka.ms/winget-settings.schema.json",
	"installBehavior": {
		"preferences": {
			"scope": "machine"
		}
	}
}
"@

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType] 'Ssl3 , Tls12'

function Get-IsPacker() {
	return ((Get-ChildItem env:packer_* | Measure-Object).Count -gt 0)
}

function Get-IsAdmin() {
	$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
	return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LatestLink($match) {
	$uri = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
	$get = Invoke-RestMethod -uri $uri -Method Get -ErrorAction stop
	$data = $get[0].assets | Where-Object name -Match $match
	return $data.browser_download_url
}

function Invoke-FileDownload() {
	param(
		[Parameter(Mandatory=$true)][string] $url,
		[Parameter(Mandatory=$false)][string] $name,
		[Parameter(Mandatory=$false)][boolean] $expand		
	)

	$path = Join-Path -path $env:temp -ChildPath (Split-Path $url -leaf)
	if ($name) { $path = Join-Path -path $env:temp -ChildPath $name }
	
	Write-Host ">>> Downloading $url > $path"
	Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
	
	if ($expand) {
		$arch = Join-Path -path $env:temp -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($path))

        Write-Host ">>> Expanding $path > $arch"
		Expand-Archive -Path $path -DestinationPath $arch -Force

		return $arch
	}
	
	return $path
}

if (-not (Get-IsPacker)) {
	Write-Host ">>> Starting transcript ..."
	Start-Transcript -Path ([System.IO.Path]::ChangeExtension($MyInvocation.MyCommand.Path, 'log')) -Append | Out-Null
}

Write-Host ">>> Downloading WinGet Packages ..."
$xamlPath = Invoke-FileDownload -url "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.7.1" -name 'Microsoft.UI.Xaml.nuget.zip' -expand $true
$msixPath = Invoke-FileDownload -url "https://cdn.winget.microsoft.com/cache/source.msix"
$wingetPath = Invoke-FileDownload -url (Get-LatestLink("msixbundle"))

if ([Environment]::Is64BitOperatingSystem) {

	$vclibs = Invoke-FileDownload -url "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"

	Write-Host ">>> Installing WinGet pre-requisites (64bit) ..."
	Add-AppxPackage -Path $vclibs -ErrorAction Stop
	Add-AppxPackage -Path (Join-Path -path $xamlPath -ChildPath 'tools\AppX\x64\Release\Microsoft.UI.Xaml.2.7.appx') -ErrorAction SilentlyContinue

} else {

	$vclibs = Invoke-FileDownload -url "https://aka.ms/Microsoft.VCLibs.x86.14.00.Desktop.appx"

	Write-Host ">>> Installing WinGet pre-requisites (32bit) ..."
	Add-AppxPackage -Path $vclibs -ErrorAction Stop
	Add-AppxPackage -Path (Join-Path -path $xamlPath -ChildPath 'tools\AppX\x86\Release\Microsoft.UI.Xaml.2.7.appx') -ErrorAction SilentlyContinue
}

Write-Host ">>> Installing WinGet (user scope) ..."
Add-AppxPackage -Path $wingetPath -ErrorAction Stop

if (Get-IsAdmin) {
	Write-Host ">>> Resetting WinGet Sources ..."
	Start-Process winget -ArgumentList "source reset --force --disable-interactivity" -NoNewWindow -Wait -RedirectStandardError "NUL" | Out-Null
}

Write-Host ">>> Adding WinGet Source Cache Package ..."
Add-AppxPackage -Path $msixPath -ErrorAction Stop

if (Get-IsPacker) {

	$settingsInfo = @(winget --info) | Where-Object { $_.StartsWith('User Settings') } | Select-Object -First 1
	$settingsPath = $settingsInfo.Split(' ') | Select-Object -Last 1 
	$settingsPath = [Environment]::ExpandEnvironmentVariables($settingsPath.Trim())

	Write-Host ">>> Patching WinGet Config ..."
	$adminWinGetConfig | Out-File $settingsPath -Encoding ASCII
}
