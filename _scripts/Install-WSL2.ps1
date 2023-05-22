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

Write-Host ">>> Enabling Virtual Machine Platform and Windows Subsystem for Linux ..."
Enable-WindowsOptionalFeature `
      -FeatureName "VirtualMachinePlatform", "Microsoft-Windows-Subsystem-Linux" `
	  -Online -All -NoRestart | Out-null

Write-Host ">>> Downloading WSL2 kernel update ..."
$installer = Invoke-FileDownload -url "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi"

Write-Host ">>> Installing WSL2 kernel update ..."
Start-Process msiexec.exe -ArgumentList "/I $installer /quiet /norestart" -NoNewWindow -Wait 

Write-Host ">>> Setting default WSL version to 2 ..."
Start-Process wsl -ArgumentList "--set-default-version 2" -NoNewWindow -Wait -RedirectStandardOutput "NUL"
  