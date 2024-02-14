param(
    [Parameter(Mandatory=$false)]
    [boolean] $Packer = ((Get-ChildItem env:packer_* | Measure-Object).Count -gt 0)
)

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

Write-Host ">>> Downloading Radzio Modbus Master Simulator ..."
$archive = Invoke-FileDownload -url "https://en.radzio.dxp.pl/modbus-master-simulator/RMMS.zip" -expand $true

$source = Join-Path $archive -ChildPath "RMMS.exe"
$destination = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) -ChildPath "RMMS.exe"

Write-Host ">>> Copying Radzio Modbus Master Simulator to Desktop ..."
Copy-Item -Path $source -Destination $destination -Force | Out-Null

