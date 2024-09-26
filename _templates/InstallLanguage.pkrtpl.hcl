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

	Invoke-ScriptSection -Title "Installing addtional language packs" -ScriptBlock {

		$languageAdditional | Select-Object -Unique | ForEach-Object {
			if ($installedLanguages -contains $_) {
				Write-Host ">>> Language Pack already installed: $_"
			} else {
				Write-Host ">>> Installing Language Pack: $_"
				$installationJobs += Install-Language -LanguageId $_ -AsJob
			}
		}

		if ($installationJobs) {
			Write-Host ">>> Waiting for $($installationJobs.Length) Language Pack/s to be installed"
			Wait-Job -Job $installationJobs -Force
		}	
	}

	if ($languagePreferred) {

		Invoke-ScriptSection -Title "Setting preferred language" -ScriptBlock {
			if ($languagePreferred -eq $languageCurrent) {
				Write-Host ">>> Preferred language already set: $languagePreferred"
			} else {
				Write-Host ">>> Setting preferred language: $languagePreferred"
				Set-PreferredLanguage -Language $languagePreferred
			}
		}

	}
}
