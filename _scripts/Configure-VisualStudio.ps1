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

Invoke-ScriptSection -Title "Configure Visual Studio" -ScriptBlock {

	$vswhereExe = Get-Command 'vswhere.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty path
	if ($vswhereExe) {
	
		$instances = [array](Invoke-CommandLine -Command $vswhereExe -Arguments '-all -prerelease -utf8 -format json' | Select-Object -ExpandProperty Output | ConvertFrom-Json)
		$instances | ForEach-Object { 

			$_ | ConvertTo-Json -Compress | Write-Host

			$edition = "$($_.displayName) $(if ($_.isPrerelease) {'PRE'} else {''})".Trim()
			$installer = Join-Path -Path ($_.enginePath) -ChildPath 'VSIXInstaller.exe'
			
			Write-Host ">>> $edition ($installer)"

			$visxFolder = Join-Path -Path $env:DEVBOX_HOME -ChildPath "Artifacts/$edition"
			if (Test-Path -Path $vsixHome -PathType Container) {

				Get-ChildItem -Path $visxFolder -Filter '*.visx' | Select-Object -ExpandProperty FullName | ForEach-Object {
					Write-Host "- Installing Extension: $_"
					Invoke-CommandLine -Command $installer -Argument "$(if ($Packer) { '/a' }) /q `"$visx`"".Trim() | Select-Object -ExpandProperty Output
				}

			} else {

				Write-Host "!!! Missing Visual Studio Extension folder: $visxFolder"
			}
		}

	} else {

		Write-Host "!!! Missing VSWhere to identify installed Visual Studio versions - please install"
	}
}	
