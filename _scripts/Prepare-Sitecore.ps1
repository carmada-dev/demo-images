Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup -Path $MyInvocation.MyCommand.Path -Name 'Prepare-Sidecore.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

Invoke-ScriptSection -Title "Starting Docker Desktop" -ScriptBlock {

    $started = Start-Docker -Tool 'DockerDesktop' -Container 'Windows'
	if (-not $started) { throw "Failed to start Docker Desktop with Windows Container support" }

}

if (Test-IsPacker) {

	Invoke-ScriptSection -Title "Prepare Sitecore Container" -ScriptBlock {

		$sitecoreHome = Join-Path -Path $env:DEVBOX_HOME -ChildPath 'Artifacts/Docker/Sitecore'
		if (-not (Test-Path -Path $sitecoreHome -PathType Container)) { throw "Sitecore home directory not found: $sitecoreHome" }
		
		$sitecoreLicenseXml = Join-Path -Path $sitecoreHome -ChildPath 'license.xml'
		if (-not (Test-Path -Path $sitecoreLicenseXml -PathType Leaf)) { 
		
			$sitecoreLicenseArchive = Join-Path -Path $sitecoreHome -ChildPath 'license.zip'
			if (-not (Test-Path -Path $sitecoreLicenseArchive -PathType Leaf)) { throw "Sitecore license archive not found: $sitecoreLicenseArchive" }

			Write-Host ">>> Unpacking Sitecore license archive: $sitecoreLicenseArchive"
			Expand-Archive -Path $sitecoreLicenseArchive -DestinationPath $sitecoreHome -Force
		}

		if (-not (Test-Path -Path $sitecoreLicenseXml -PathType Leaf)) { throw "Sitecore license file not found: $sitecoreLicenseXml" }

		$sitecoreInitScript = Join-Path -Path $sitecoreHome -ChildPath 'compose-init.ps1'
		if (-not (Test-Path -Path $sitecoreInitScript -PathType Leaf)) { throw "Sitecore init script not found: $sitecoreInitScript" }

		try
		{
			Push-Location -Path $sitecoreDeploymentDirectory

			Write-Host ">>> Prepare Sitecore deployment"
			& $sitecoreInitScript -LicenseXmlPath $sitecoreLicenseXml
		}
		finally
		{
			Pop-Location -ErrorAction SilentlyContinue
		}
	}
}
