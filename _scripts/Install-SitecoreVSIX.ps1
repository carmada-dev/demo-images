# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$ProgressPreference = 'SilentlyContinue'	# hide any progress output

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

function Invoke-VSIXInstaller() {

	$ErrorActionPreference = 'Stop'
	$vsixInstaller = vswhere -latest -prerelease -products * -property enginePath | Join-Path -ChildPath 'VSIXInstaller.exe'
  
	if (Test-Path $vsixInstaller) {

		Write-Host ">>> Executing VSIX Installer"
		Write-Host "${vsixInstaller} ${args}"

	    $process = Start-Process $vsixInstaller -ArgumentList $args -RedirectStandardOutput "NUL" -NoNewWindow -Wait -PassThru
	    if ($process.ExitCode -ne 0) { exit $process.ExitCode }
	}
  }

# Sitecore for VisualStudio Download: https://dev.sitecore.net/Downloads/Sitecore_for_Visual_Studio/5x/Sitecore_for_Visual_Studio_52113.aspx
$visx = Invoke-FileDownload -url "https://sitecoredev.azureedge.net/~/media/4615380121F643B5AE60B648FD829603.ashx?date=20230619T124351" -name "Sitecore.vsix"

# Install VisualStudio Extension
Invoke-VSIXInstaller /a /q "$visx"