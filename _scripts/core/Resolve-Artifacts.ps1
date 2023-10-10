# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
$ErrorActionPreference = 'SilentlyContinue'	# resume on error

function Invoke-FileDownload() {
	param(
		[Parameter(Mandatory=$true)][string] $url,
		[Parameter(Mandatory=$false)][string] $name,
		[Parameter(Mandatory=$false)][boolean] $expand		
	)

	$path = Join-Path -path $env:temp -ChildPath (Split-Path $url -leaf)
	if ($name) { $path = Join-Path -path $env:temp -ChildPath $name }
	
	Write-Host "- Downloading $url > $path"
	Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
	
	if ($expand) {
		$arch = Join-Path -path $env:temp -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($path))

        Write-Host "- Expanding $path > $arch"
		Expand-Archive -Path $path -DestinationPath $arch -Force

		return $arch
	}
	
	return $path
}

function Get-ShortcutTargetPath() {
	param( 
		[Parameter(Mandatory=$true)][string]$Path
	)

	$Shell = New-Object -ComObject ("WScript.Shell")
	$Shortcut = $Shell.CreateShortcut($Path)

	return $Shortcut.TargetPath
}

$Artifacts = Join-Path -Path $env:DEVBOX_HOME -ChildPath 'Artifacts'
if (Test-Path -Path $Artifacts -PathType Container) {

	Get-ChildItem -Path $Artifacts -Filter '*.*.url' -Recurse | Select-Object -ExpandProperty FullName | ForEach-Object -Begin { 
	
		Write-Host ">>> Install Az PowerShell Module (PSVersion $($PSVersionTable.PSVersion))"
		Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

		Write-Host "- Installing NuGet package provider" 
		Install-PackageProvider -Name NuGet -Force | Out-Null

		Write-Host "- Register PSGallery"
		Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

		Write-Host "- Installing PowerShellGet module" 
		Install-Module -Name PowerShellGet -Force -AllowClobber

		Write-Host "- Installing Az module" 
		Install-Module -Name Az -Repository PSGallery -Force -AllowClobber
	
		Write-Host ">>> Connect Azure"
		(Connect-AzAccount -Identity -ErrorAction Stop).Context | Format-List
		
} -Process { 
	
		Write-Host ">>> Resolving Artifact: $_" 
		
		$ArtifactUrl = Get-ShortcutTargetPath -Path $_ 
		$Artifact = $_.TrimEnd([System.IO.Path]::GetExtension($_))

		if ($ArtifactUrl) {

			$KeyVaultEndpoint = (Get-AzEnvironment -Name AzureCloud | Select-Object -ExpandProperty AzureKeyVaultServiceEndpointResourceId)
			$KeyVaultPattern = $KeyVaultEndpoint.replace('://','://*.').trim() + '/*'

			if ($ArtifactUrl -like $KeyVaultPattern) {
				
				Write-Host "- Acquire KeyVault Token"
				$KeyVaultToken = Get-AzAccessToken -ResourceUrl $KeyVaultEndpoint -ErrorAction Stop

				Write-Host "- Fetching KeyVault Secret $ArtifactUrl"
				$KeyVaultHeaders = @{"Authorization" = "Bearer $($KeyVaultToken.Token)"}
				$KeyVaultResponse = Invoke-RestMethod -Uri "$($ArtifactUrl)?api-version=7.1" -Headers $KeyVaultHeaders -ErrorAction Stop
					
				Write-Host "- Decoding BASE64 encoded KeyVault Secret"
				[System.Convert]::FromBase64String($KeyVaultResponse.value) | Set-Content -Path $Artifact -Encoding Byte -Force

			} else {
				
				$Temp = Invoke-FileDownload -url $ArtifactUrl 
				Move-Item -Path $Temp -Destination $Artifact
			}

			if (Test-Path -Path $Artifact -PathType Leaf) {
				Write-Host "- Resolved Artifact: $_"
			}
		}
	}

}

