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

function Invoke-7zipDownload() {

	$7zipHome = Join-Path -path $env:temp -ChildPath "7zip"
	$7zipTool = Join-Path -path $7zipHome -ChildPath "7z.exe"

	if (-not( Test-Path -Path $7zipTool -PathType Leaf )) {

		New-Item -Path $7zipHome -ItemType Directory -Force | Out-Null

		$baseUrl = 'https://www.7-zip.org'
		$page = Invoke-WebRequest -Uri "$baseUrl/download.html" -UseBasicParsing

		$path = $page.Links | Where-Object { $_.href -like '*/7za*.zip' } | Select-Object -First 1 | Select-Object -ExpandProperty href	
		$7za = Join-Path -Path (Invoke-FileDownload -url ("$baseUrl/$path") -name "7zipA.zip" -expand $true) -ChildPath '7za.exe'

		$path = $page.Links | Where-Object { $_.href -like '*/7z*-x64.exe' } | Select-Object -First 1 | Select-Object -ExpandProperty href	
		$arch = Invoke-FileDownload -url ("$baseUrl/$path") -name "7zip.exe"

		$process = Start-Process $7za -ArgumentList "x $arch -o$7zipHome" -RedirectStandardOutput "NUL" -NoNewWindow -Wait -PassThru
		if ($process.ExitCode -ne 0) { exit $process.ExitCode }
	}

	if (Test-Path -Path $7zipTool -PathType Leaf) {	
		Write-Host ">>> 7zip location: $7zipTool"
		return $7zipTool 
	}

	throw "Could not find 7zip command line tool at $7zipTool"
}

Write-Host ">>> Downloading 7zip ..."
$7zip = Invoke-7zipDownload

Write-Host ">>> Downloading WuT COM Redirector ..."
$archive = Invoke-FileDownload -url "https://www.wut.de/download/tools/e-00111-ww-swww-441.exe" -name "COMRedirector.zip"
$extract = Join-Path (Split-Path -Path $archive) -ChildPath ([io.path]::GetFileNameWithoutExtension($archive))

Write-Host ">>> Extracting WuT COM Redirector ..."
$process = Start-Process $7zip -ArgumentList "x $archive -o$extract" -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) { exit $process.ExitCode }

Write-Host ">>> Extracting WuT COM Redirector (Installer) ..."
$source = Get-ChildItem -Path $extract -Filter '302' -Recurse | Select-Object -Last 1 -ExpandProperty Fullname
$installer = [System.IO.Path]::ChangeExtension($archive, ".msi")
Copy-Item $source -Destination $installer -Force -Verbose

Write-Host ">>> Installing WuT COM Redirector ..."
$process = Start-Process msiexec.exe -ArgumentList "/I $installer /qn" -NoNewWindow -Wait -PassThru
exit $process.ExitCode
