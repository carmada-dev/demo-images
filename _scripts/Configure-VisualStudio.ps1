param(
    [Parameter(Mandatory=$false)]
    [boolean] $Packer = ((Get-ChildItem env:packer_* | Measure-Object).Count -gt 0)
)

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if ($Packer) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Configure-VSWhere.ps1' -Elevate
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

function Invoke-VSIXInstaller {

	param(
		[Parameter(Mandatory = $true)]
		[string] $Edition,
		[Parameter(Mandatory = $true)]
		[string] $Installer
	)

	$ErrorActionPreference = 'SilentlyContinue'

	$visxFolder = Join-Path -Path $env:DEVBOX_HOME -ChildPath "Artifacts/$Edition"
	if (Test-Path -Path $vsixHome -PathType Container) {
		Get-ChildItem -Path $visxFolder -Filter '*.visx' | Select-Object -ExpandProperty FullName | ForEach-Object -Begin { Write-Host ">>> $Edition" } -Process {
            Write-Host "- Installing Extension: $_"
            Invoke-CommandLine -Command $Installer -Argument "$(if ($Packer) { '/a' }) /q `"$visx`"".Trim() | Select-Object -ExpandProperty Output
		}
	}
}

Invoke-ScriptSection -Title "Configure Visual Studio" -ScriptBlock {

	$vswhereExe = Get-Command 'vswhere.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty path
	if ($vswhereExe) {
	
		$instances = [array](Invoke-CommandLine -Command $vswhereExe -Arguments '-all -prerelease -utf8 -format json' | Select-Object -ExpandProperty Output | ConvertFrom-Json)
		$instances | ForEach-Object { 
			$edition = "$($_.displayName) $(if ($_.isPrerelease) {'PRE'} else {''})".Trim()
			$installer = (Join-Path $($_.enginePath) 'VSIXInstaller.exe')
			Invoke-VSIXInstaller -Edition $edition -Installer $installer
		}

	} else {

		Write-Host "!!! Missing VSWhere to identify installed Visual Studio versions - please install"
	}
}	
