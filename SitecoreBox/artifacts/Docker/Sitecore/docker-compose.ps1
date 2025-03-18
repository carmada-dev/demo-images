Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

$dockerCompose = Get-Command 'docker-compose' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
if (-not $dockerCompose) { throw 'Could not find docker-compose.exe' }

$sitecoreHome = (Get-Location | Select-Object -ExpandProperty Path)
$sitecoreLicenseXml = Join-Path -Path $sitecoreHome -ChildPath 'license.xml'
$sitecoreLicenseArchive = Join-Path -Path $sitecoreHome -ChildPath 'license.zip'
$sitecoreInitScript = Join-Path -Path $sitecoreHome -ChildPath 'compose-init.ps1'

if (-not (Test-Path -Path $sitecoreLicenseXml -PathType Leaf)) { 

	if (-not (Test-Path -Path $sitecoreLicenseArchive -PathType Leaf)) { throw "Sitecore license archive not found: $sitecoreLicenseArchive" }

	Write-Host ">>> Unpacking Sitecore license archive: $sitecoreLicenseArchive"
	Expand-Archive -Path $sitecoreLicenseArchive -DestinationPath $sitecoreHome -Force
}

if (-not (Test-Path -Path $sitecoreLicenseXml -PathType Leaf)) { throw "Sitecore license file not found: $sitecoreLicenseXml" }

if (-not (Test-Path -Path $sitecoreInitScript -PathType Leaf)) { throw "Sitecore init script not found: $sitecoreInitScript" }

Write-Host ">>> Prepare Sitecore deployment ..."
Invoke-CommandLine -Command 'powershell' -Arguments "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -File `"$sitecoreInitScript`" -LicenseXmlPath `"$sitecoreLicenseXml`"" | select-Object -ExpandProperty Output | Write-Host

Write-Host ">>> Starting Docker Compose at $sitecoreHome ..."
Invoke-CommandLine -Command $dockerCompose -Arguments "up --detach --yes" -Capture 'StdErr' | select-Object -ExpandProperty Output | Write-Host
