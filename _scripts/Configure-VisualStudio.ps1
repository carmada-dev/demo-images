Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Configure-VSWhere.ps1'
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

			$edition = "$($_.displayName) $(if ($_.isPrerelease) {'PRE'} else {''})".Trim()
			$vsixInstaller = Join-Path -Path ($_.enginePath) -ChildPath 'VSIXInstaller.exe'
			$vsixArtifacts = Join-Path -Path $env:DEVBOX_HOME -ChildPath "Artifacts/$edition"
			
			Get-ChildItem -Path $vsixArtifacts -Filter '*.visx' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName | ForEach-Object {
				Write-Host ">>> Installing extension for $($edition): $_"
				Invoke-CommandLine -Command $vsixInstaller -Argument "$(if (Test-IsPacker) { '/a' }) /q `"$_`"".Trim() | Select-Object -ExpandProperty Output
			}

		}

	} else {

		Write-Host "!!! Missing VSWhere to identify installed Visual Studio versions - please install"
	}
}	
