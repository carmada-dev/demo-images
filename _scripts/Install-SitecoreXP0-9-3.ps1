# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$ProgressPreference = 'SilentlyContinue'	# hide any progress output

$WindowsFeatures = @('IIS-WebServerRole',
              'IIS-WebServer',
              'IIS-CommonHttpFeatures',
              'IIS-HttpErrors',
              'IIS-HttpRedirect',
              'IIS-ApplicationDevelopment',
              'IIS-NetFxExtensibility',
              'IIS-NetFxExtensibility45',
              'IIS-HealthAndDiagnostics',
              'IIS-HttpLogging',
              'IIS-LoggingLibraries',
              'IIS-RequestMonitor',
              'IIS-Security',
              'IIS-RequestFiltering',
              'IIS-HttpCompressionDynamic',
              'IIS-Performance',
              'IIS-WebServerManagementTools',
              'IIS-ManagementScriptingTools',
              'IIS-DefaultDocument',
              'IIS-StaticContent',
              'IIS-DirectoryBrowsing',
              'IIS-WebSockets',
              'IIS-ASPNET',
              'IIS-ASPNET45',
              'IIS-ISAPIExtensions',
              'IIS-ISAPIFilter',
              'IIS-BasicAuthentication',
              'IIS-HttpCompressionStatic',
              'IIS-ManagementConsole',
              'IIS-ManagementService',
              'NetFx4-AdvSrvs',
              'NetFx4Extended-ASPNET45');

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

# Enforce TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host ">>> Installing Windows Features"
Enable-WindowsOptionalFeature –Online –FeatureName $WindowsFeatures -All -NoRestart

Write-Host ">>> Installing NuGet as Package Provider"
Install-PackageProvider -Name NuGet -Force | Out-Null

$sitecoreGallery = Get-PSRepository -Name SitecoreGallery -ErrorAction SilentlyContinue
if ($null -eq $sitecoreGallery) { 
	Write-Host ">>> Registering Sitecore Gallery"
	Register-PSRepository -Name SitecoreGallery -SourceLocation https://sitecore.myget.org/F/sc-powershell/api/v2 -InstallationPolicy Trusted 
}

Write-Host ">>> Installing Sitecore Installation Framework"
Install-Module SitecoreInstallFramework -Force

# Packages fro XPSingle (XP0): https://dev.sitecore.net/Downloads/Sitecore_Experience_Platform/93/Sitecore_Experience_Platform_93_Initial_Release.aspx
$temp = Invoke-FileDownload -url "https://sitecoredev.azureedge.net/~/media/88666D3532F24973939C1CC140E12A27.ashx" -name "Sitecore.zip" -expand $true

Write-Host ">>> Prepare Sitecore Installation Resources"
$resources = "C:\Sitecore"
Remove-Item $resources -Recurse -Force -ErrorAction SilentlyContinue
New-Item -Path $resources -ItemType Directory -Force | Select-Object -ExpandProperty Fullname
$sitecoreCfg = Get-ChildItem -Path $temp -Filter "XP0 Configuration files*.zip" | Select-Object -First 1 -ExpandProperty FullName

Write-Host "- Expanding configuration files"
Expand-Archive -Path $sitecoreCfg -DestinationPath $resources -Force

Write-Host "- Copying installation packages" 
Get-ChildItem -Path $temp -Exclude ([System.IO.Path]::GetFileName($sitecoreCfg)) | Copy-Item -Destination $resources -Recurse

try
{
	Push-Location -Path $resources

	Write-Host ">>> Patching prerequisites"
    $path = ".\Prerequisites.json"
    $content = Get-Content $path
    $content = $content -ireplace "https://download.microsoft.com/download/C/F/F/CFF3A0B8-99D4-41A2-AE1A-496C08BEB904/WebPlatformInstaller_amd64_en-US.msi", "https://download.microsoft.com/download/8/4/9/849DBCF2-DFD9-49F5-9A19-9AEE5B29341A/WebPlatformInstaller_x64_en-US.msi"
    $content | Set-Content $path

    Write-Host ">>> Installing prerequisites" 
    Install-SitecoreConfiguration -Path .\Prerequisites.json
}
finally
{
    Pop-Location
}