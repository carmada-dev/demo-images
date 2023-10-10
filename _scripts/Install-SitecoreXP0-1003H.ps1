# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$ProgressPreference = 'SilentlyContinue'	# hide any progress output

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Local folder to expand the installer package
$SitecoreResources = "C:\ResourceFiles"

# URL to download the Sitecore Installer Framework package (https://dev.sitecore.net/Downloads/Sitecore_Experience_Platform/93/Sitecore_Experience_Platform_103_Initial_Release.aspx)
$SitecoreInstaller = "https://sitecoredev.azureedge.net/~/media/88666D3532F24973939C1CC140E12A27.ashx"

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

Write-Host ">>> Installing NuGet as Package Provider"
Install-PackageProvider -Name NuGet -Force | Out-Null

$sitecoreGallery = Get-PSRepository -Name SitecoreGallery -ErrorAction SilentlyContinue
if (-not($sitecoreGallery)) { 
	Write-Host ">>> Registering Sitecore Gallery"
	Register-PSRepository -Name SitecoreGallery -SourceLocation https://sitecore.myget.org/F/sc-powershell/api/v2 -InstallationPolicy Trusted 
}

Write-Host ">>> Install required PowerShell modules"
Install-Module -Name SitecoreInstallFramework -Force -AllowClobber -ErrorAction Stop

Write-Host ">>> Create Sitecore resources folder"
Remove-Item $SitecoreResources -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host ">>> Download Sitecore Install Framework resources"
$SitecoreInstallerTemp = Invoke-FileDownload -url $SitecoreInstaller -name "$(Split-Path -Path $SitecoreResources -Leaf).zip" -expand $true

Write-Host ">>> Move Sitecore Install Framework resources to final location"
Move-Item -Path $SitecoreInstallerTemp -Destination (Split-Path -Path $SitecoreResources -Parent) -Force

Push-Location -Path $SitecoreResources

try 
{
    Write-Host ">>> Expanding XP0 configuration archive"
    Expand-Archive -Path (Get-ChildItem -Path . -Filter "XP0 Configuration files*.zip" | Select-Object -First 1 -ExpandProperty FullName) -DestinationPath . -Force -ErrorAction Stop

    Write-Host ">>> Expanding XP0 license archive"
    Expand-Archive -Path (Join-Path -Path $env:DEVBOX_HOME -ChildPath 'Artifacts/Sitecore/license.zip') -DestinationPath . -Force -ErrorAction Stop

    Write-Host ">>> Patching Sitecore config"
    $ConfigPath = ".\Prerequisites.json"
    $ConfigContent = Get-Content $ConfigPath -ErrorAction Stop
    $ConfigContent = $ConfigContent -ireplace "https://download.microsoft.com/download/C/F/F/CFF3A0B8-99D4-41A2-AE1A-496C08BEB904/WebPlatformInstaller_amd64_en-US.msi", "https://download.microsoft.com/download/8/4/9/849DBCF2-DFD9-49F5-9A19-9AEE5B29341A/WebPlatformInstaller_x64_en-US.msi"
    $ConfigContent | Set-Content $ConfigPath

    Write-Host ">>> Installing Sitecore prerequisites" 
    Install-SitecoreConfiguration -Path .\Prerequisites.json 

    # Write-Host ">>> Installing SOLR config" 
    # Install-SitecoreConfiguration -Path .\Solr-SingleDeveloper.json 

    #Write-Host ">>> Installing XConnect config" 
    #Install-SitecoreConfiguration -Path .\xconnect-xp0.json

    $singleDeveloperPrefix = "XP0"

    $singleDeveloperParams = @{
        Path = "$SitecoreResources\XP0-SingleDeveloper.json"
        SqlServer = "localhost"
        SqlAdminUser = "sa"
        SqlAdminPassword = "S!t3c0r3"
        SitecoreAdminPassword = "S!t3c0r3"
        SolrUrl = "https://localhost:8983/solr"
        SolrRoot = "C:\Solr-8.1.1"
        SolrService = "Solr-8.1.1"
        Prefix = $singleDeveloperPrefix
        XConnectCertificateName = "$singleDeveloperPrefix.xconnect"
        IdentityServerCertificateName = "$singleDeveloperPrefix.identityserver"
        IdentityServerSiteName = "$singleDeveloperPrefix.identityserver"
        LicenseFile = "$SitecoreResources\license.xml"
        XConnectPackage = (Get-ChildItem "$SitecoreResources\Sitecore 9* rev. * (OnPrem)_xp0xconnect.scwdp.zip").FullName
        SitecorePackage = (Get-ChildItem "$SitecoreResources\Sitecore 9* rev. * (OnPrem)_single.scwdp.zip").FullName
        IdentityServerPackage = (Get-ChildItem "$SitecoreResources\Sitecore.IdentityServer * rev. * (OnPrem)_identityserver.scwdp.zip").FullName
        XConnectSiteName = "$singleDeveloperPrefix.xconnect"
        SitecoreSitename = "$singleDeveloperPrefix.sc"
        PasswordRecoveryUrl = "https://$singleDeveloperPrefix.sc"
        SitecoreIdentityAuthority = "https://$singleDeveloperPrefix.identityserver"
        XConnectCollectionService = "https://$singleDeveloperPrefix.xconnect"
        ClientSecret = "S!t3c0r3"
        AllowedCorsOrigins = "https://$singleDeveloperPrefix.sc"
        SitePhysicalRoot = ""
    }

    # $singleDeveloperModules = @(
    #     "IISAdministration"
    #     "SQLServer"
    #     "WebAdministration"
    # )

    # Write-Host ">>> XP0 Single Developer Installer Parameters"
    # $singleDeveloperParams | Format-Table

    # Write-Host ">>> Lazy load additional PowerShell modules"
    # $singleDeveloperModules | ForEach-Object { 
    #     Write-Host "- $_"
    #     Install-Module -Name $_ -Force -AllowClobber -ErrorAction Continue
    # }

    # Write-Host ">>> Starting XP0 Single Developer Installer"
    # Install-SitecoreConfiguration @singleDeveloperParams *>&1 | Tee-Object XP0-SingleDeveloper.log
}
finally
{
    Pop-Location
}


