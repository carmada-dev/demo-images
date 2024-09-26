Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (-not(Test-SoftwareInstalled -Name 'Docker Desktop', 'Podman*')) {
	Write-Host "!!! Docker Desktop or Podman must be installed"
	exit 1
} elseif (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup -Path $MyInvocation.MyCommand.Path -Name 'Install-Sidecore.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

Invoke-ScriptSection -Title "Configure Sitecore XP0 10.03" -ScriptBlock {

	$dockerExe = Get-Command 'docker.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path
	$podmanExe = Get-Command 'podman.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path

	if ($dockerExe) {

		$dockerSvc = Get-ServiceInfo -Name 'docker'
		if (-not($dockerSvc)) {
			Write-ErrorMessage -Message "!!! Docker Desktop must run as service"
			exit 1
		}	

		Write-Host ">>> Starting Docker services "
		Restart-Service *docker* -Force -PassThru

		$path = Join-Path $env:APPDATA "Docker/settings.json" 
		if (Test-Path $path -PathType Leaf) {

			$json = Get-Content -Path $path -Raw | ConvertFrom-Json
			if (-not($json.useWindowsContainers)) {

				Write-Host ">>> Enabling Windows Container in Docker"
				$json.useWindowsContainers = $true
				$json | ConvertTo-Json | Set-Content -Path $path

				Write-Host ">>> Restarting Docker services"
				Restart-Service *docker* -Force -PassThru
			}
		}

	} elseif ($podmanExe) {


		
	} else {

		Write-ErrorMessage '!!! Neither Docker Desktop nor Podman could be found'
		exit 1
	}

	$sitecoreDeploymentDirectory = 'C:\Sitecore'

	if (Test-IsPacker) {
		
		$url = Get-GitHubLatestReleaseDownloadUrl -Organization 'Sitecore' -Repository 'container-deployment' -Release "SXP Sitecore Container Deployment 10.3..*" -Asset "SitecoreContainerDeployment.*.zip"
		$tmp = Invoke-FileDownload -Url $url -Name "SitecoreContainerDeployment.zip" -Expand

		Write-Host ">>> Assemble Sitecore Container Deployment"
		Remove-Item $sitecoreDeploymentDirectory -Recurse -Force -ErrorAction SilentlyContinue
		$xp0 = Get-ChildItem -Path "$tmp\compose\*\xp0" -Directory | Select-Object -Last 1 -ExpandProperty FullName
		Copy-Item -Path $xp0 -Destination "$sitecoreDeploymentDirectory\" -Recurse -Force | Select-Object -ExpandProperty FullName
		$lic = Join-Path -Path $env:DEVBOX_HOME -ChildPath 'Artifacts/Sitecore/license.zip'
		Expand-Archive -Path $lic -DestinationPath $sitecoreDeploymentDirectory -Force

	} elseif (Test-Path $sitecoreDeploymentDirectory -PathType Container) {

		try
		{
			Push-Location -Path $sitecoreDeploymentDirectory

			Write-Host ">>> Prepare Sitecore deployment"
			& (Join-Path $sitecoreDeploymentDirectory 'compose-init.ps1') -LicenseXmlPath (Join-Path $sitecoreDeploymentDirectory 'license.xml')

			Write-Host ">>> Run Docker Compose"
			Invoke-CommandLine -Command $dockerExe -Arguments "compose up --detach --force-recreate" -Capture StdErr | Select-Object -ExpandProperty Output | Write-Host
		}
		finally
		{
			Pop-Location -ErrorAction SilentlyContinue
		}

	} 
}