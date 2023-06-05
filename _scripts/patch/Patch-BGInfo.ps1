# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
$ErrorActionPreference = 'SilentlyContinue'	# resume on error

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
function Set-Shortcut() {
	param( 
		[Parameter(Mandatory=$true)][string]$Path,
		[Parameter(Mandatory=$true)][string]$TargetPath,
		[Parameter(Mandatory=$false)][string]$TargetArguments
	)

	$Shell = New-Object -ComObject ("WScript.Shell")
	$Shortcut = $Shell.CreateShortcut($Path)
	$Shortcut.TargetPath = $TargetPath
	$Shortcut.Arguments = $TargetArguments
	$Shortcut.Save()
}

$bgInfoArtifact = Join-Path -Path $env:DEVBOX_HOME -ChildPath 'Artifacts\Bginfo.bgi'
if (Test-Path -Path $bgInfoArtifact -PathType Leaf) {

	Write-Host ">>> Downloading BGInfo ..."
	$bgInfoArchive = Invoke-FileDownload -url 'https://download.sysinternals.com/files/BGInfo.zip' -expand $true
	$bgInfoHome = Join-Path -Path ([Environment]::GetEnvironmentVariable("ProgramFiles")) -ChildPath (Split-Path $bgInfoArchive -Leaf)

	Write-Host ">>> Installing BGInfo Tool ..."
    New-Item -Path $bgInfoHome -ItemType Directory -Force | Out-Null
	Get-ChildItem -Path $bgInfoArchive -Filter '*.exe' | Move-Item -Destination $bgInfoHome -Force | Out-Null

	Write-Host ">>> Installing BGInfo Config ..."
	Move-item -Path $bgInfoArtifact -Destination (Join-Path -Path $bgInfoHome -ChildPath (Split-Path $bgInfoArtifact -Leaf)) -Force | Out-Null

	Write-Host ">>> Updating BGInfo ACLs ..."
	$bgInfoACR = New-Object System.Security.AccessControl.FileSystemAccessRule("everyone", "FullControl", "Allow")
	$bgInfoACL = Get-Acl -Path $bgInfoHome
	$bgInfoACL.SetAccessRule($bgInfoACR)
	$bgInfoACL | Set-Acl -Path $bgInfoHome

	$bgInfoTool = Join-Path -Path $bgInfoHome -ChildPath 'Bginfo64.exe'
	$bgInfoConfig = Join-Path -Path $bgInfoHome -ChildPath (Split-Path $bgInfoArtifact -Leaf) 
	$bgInfoTarget = "`"$bgInfoTool`""
	$bgInfoArguments = "`"$bgInfoConfig`" /SILENT /NOLICPROMPT /TIMER:0"
	$bgInfoCommand = "$bgInfoTarget $bgInfoArguments"

	Write-Host ">>> Register BGInfo ..."
	Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name BGInfo -Value $bgInfoCommand "$bgInfoTarget $bgInfoArguments" -type String	
	Set-Shortcut -Path (Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) -ChildPath "BGInfo.lnk") -TargetPath $bgInfoTarget -TargetArguments $bgInfoArguments
}

