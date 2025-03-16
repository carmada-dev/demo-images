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

$vswhere = Get-Command 'vswhere.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty path
if (-not $vswhere) { throw 'Could not find vswhere.exe' }

$instances = [array](Invoke-CommandLine -Command $vswhere -Arguments '-all -prerelease -utf8 -format json' | Select-Object -ExpandProperty Output | ConvertFrom-Json)
$instances | ForEach-Object { 

	$edition = "$($_.displayName) $(if ($_.isPrerelease) {'Preview'} else {''})".Trim()

	Invoke-ScriptSection -Title "Configure $edition" -ScriptBlock {

		$vsixInstaller = Join-Path -Path ($_.enginePath) -ChildPath 'VSIXInstaller.exe'
		if (-not (Test-Path -Path $vsixInstaller -PathType Leaf)) { throw "Could not find VSIXInstaller.exe in folder $($_.enginePath)" }

		$vsixArtifacts = New-Item -Path (Join-Path -Path $env:DEVBOX_HOME -ChildPath "Artifacts/$edition") -ItemType Directory -Force | Select-Object -ExpandProperty FullName
		Write-Host ">>> Installing VSIX extensions from folder $vsixArtifacts ..."

		Get-ChildItem -Path $vsixArtifacts -Filter '*.visx' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName | ForEach-Object {
			Write-Host "- Installing extension: $_"
			Invoke-CommandLine -Command $vsixInstaller -Argument "$(if (Test-IsPacker) { '/a' }) /q `"$_`"".Trim() | Select-Object -ExpandProperty Output | Write-Host
		}
	}
}	
