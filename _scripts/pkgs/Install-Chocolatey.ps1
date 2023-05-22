# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

function Get-IsPacker() {
	try 	{ return [System.Convert]::ToBoolean($Env:PACKER) }
	catch 	{ return $false }
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

$env:chocolateyUseWindowsCompression = 'false'

if (-not (Get-IsPacker)) {
	Write-Host ">>> Starting transcript ..."
	Start-Transcript -Path ([System.IO.Path]::ChangeExtension($MyInvocation.MyCommand.Path, 'log')) -Append | Out-Null
}

Write-Host ">>> Downloading Chocolatey ..."
$installer = Invoke-FileDownload -url 'https://chocolatey.org/install.ps1'

Write-Host ">>> Installing Chocolatey ..."
& $installer | Out-Null
