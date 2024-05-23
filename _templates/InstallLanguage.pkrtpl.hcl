Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

function Has-Property {

    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $InputObject,
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    return ($null -ne ($InputObject | Select -ExpandProperty $Name -ErrorAction SilentlyContinue))
}

function Get-PropertyValue {
    
	param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $InputObject,
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [string] $DefaultValue = [string]::Empty
    )

    $value = ($InputObject | Select -ExpandProperty $Name -ErrorAction SilentlyContinue)

    if ($value) { 
        if ($value -is [array]) { $value = $value -join " " } 
    } else { 
        $value = $DefaultValue 
    }

	return $value
}

function Get-PropertyArray {

    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $InputObject,
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $value = ($InputObject | Select -ExpandProperty $Name -ErrorAction SilentlyContinue)

    if ($value) {
        
        if ($value -is [array]) {
            Write-Output -NoEnumerate $value
        } else {
            Write-Output -NoEnumerate @($value)
        }
    
    } else {

        Write-Output -NoEnumerate @()    
    }
}

[object] $language = '${jsonencode(language)}' | ConvertFrom-Json

$installedLanguages = Get-InstalledLanguage | ForEach-Object { $_ | Select-Object -ExpandProperty LanguageId }
$installationJobs = @()

$languageCurrent = Get-PreferredLanguage
$languagePreferred = $language | Get-PropertyValue -Name 'preferred' -DefaultValue 'en-US'
$languageAdditional = $language | Get-PropertyArray -Name 'additional' 

if ($languagePreferred) {
	$languageAdditional += $languagePreferred
}

if ($languageAdditional) {

	# Invoke-ScriptSection -Title "Downloading language pack repository" -ScriptBlock {

	# 	[string] $languagePackUrl

	# 	if ((Get-WmiObject Win32_OperatingSystem).Caption -match 11) {
	# 		$languagePackUrl = 'https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66749/22621.1.220506-1250.ni_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso'
	# 	} else {
	# 		$languagePackUrl = 'https://software-download.microsoft.com/download/pr/19041.1.191206-1406.vb_release_CLIENTLANGPACKDVD_OEM_MULTI.iso'
	# 	}

	# 	Write-Host ">>> Downloading Language Pack ..."
	# 	$languagePackPath = Invoke-FileDownload -Url $languagePackUrl -Name "LanguagePack.iso"

	# 	Write-Host ">>> Mounting Language Pack ..."
	# 	$languagePackDrive = Mount-DiskImage -ImagePath $languagePackPath -PassThru
	# 	$languagePackDriveLetter = ($languagePackDrive | Get-Volume).DriveLetter

	# 	Write-Host ">>> Available Language Packs:"
	# 	Get-ChildItem -Path "$($languagePackDriveLetter):\" -Filter "*.*" -Recurse | Select-Object -ExpandProperty FullName
	# }

	Invoke-ScriptSection -Title "Installing addtional language packs" -ScriptBlock {

		# $languageAdditional | Select-Object -Unique | ForEach-Object {
		# 	if ($installedLanguages -contains $_) {
		# 		Write-Host ">>> Language Pack already installed: $_"
		# 	} else {
		# 		Write-Host ">>> Installing Language Pack: $_"
		# 		$installationJobs += Install-Language -LanguageId $_ -AsJob
		# 	}
		# }

		# if ($installationJobs) {
		# 	$installationJobs | Wait-Job | Receive-Job -ErrorAction Stop
		# }	

	}

	if ($languagePreferred) {

		# Invoke-ScriptSection -Title "Setting preferred language" -ScriptBlock {
		# 	if ($languagePreferred -eq $languageCurrent) {
		# 		Write-Host ">>> Preferred language already set: $languagePreferred"
		# 	} else {
		# 		Write-Host ">>> Setting preferred language: $languagePreferred"
		# 		Set-PreferredLanguage -Language $languagePreferred
		# 	}
		# }

	}
}