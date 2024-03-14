
param(
    [Parameter(Mandatory=$false)]
    [boolean] $Packer = ((Get-ChildItem env:packer_* | Measure-Object).Count -gt 0)
)

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

function Has-Property() {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $InputObject,
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    return ($null -ne ($InputObject | Select -ExpandProperty $Name -ErrorAction SilentlyContinue))
}

function Get-PropertyValue() {
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

function Convert-Markdown2HTML() {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Markdown
    )

	$payload = [PSCustomObject]@{

		text = $Markdown
		mode = "markdown"

	} | ConvertTo-Json -Compress | Out-String

	$response = Invoke-WebRequest -Method Post -Uri 'https://api.github.com/markdown' -Body $payload 

return @"
<!doctype html>
<html lang=\"en\">
	<head>
		<meta charset=\"utf-8\">
		<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, minimal-ui\">
		<title>Microsoft DevBox Capabilities</title>
		<meta name=\"color-scheme\" content=\"light dark\">
		<link rel=\"stylesheet\" href=\"https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.5.1/github-markdown.css\">
		<style>
			body {
				box-sizing: border-box;
				min-width: 200px;
				max-width: 980px;
				margin: 0 auto;
				padding: 45px;
			}

			@media (prefers-color-scheme: dark) {
				body {
					background-color: #0d1117;
				}
			}
		</style>
	</head>
	<body>
		<article class=\"markdown-body\">$($response.Content | Out-String)</article>
	</body>
</html>
"@ | Out-String

}

function Extract-OutputValue() {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $InputObject,
        [Parameter(Mandatory = $true)]
        [string] $Header
    )

	$InputObject | Select-String -Pattern ("^(?:{0}) (.*)" -f $Header) | Select-Object -First 1 -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Last 1 | Select-Object -ExpandProperty Value | % Trim | Write-Output
}

function Parse-WinGetPackage() {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
		[object] $Package
    )

	$arguments = ("show", ("--id {0}" -f $Package.name), "--exact")

	if ($Package | Has-Property -Name "version") { 	
		$arguments += "--version {0}" -f $Package.version
	}
	
	$arguments += "--source {0}" -f ($Package | Get-PropertyValue -Name "source" -DefaultValue "winget")
	$arguments += "--accept-package-agreements"
	$arguments += "--accept-source-agreements"

	$output = winget ($arguments -join ' ')

	if ($output) {

		return [PSCustomObject]@{
			Title   	= $output | Extract-OutputValue -Header 'Found'
			Version 	= $output | Extract-OutputValue -Header 'Version:'
			Publisher   = $output | Extract-OutputValue -Header 'Publisher:'
			Description = $output | Extract-OutputValue -Header 'Description:'
			Homepage	= $output | Extract-OutputValue -Header 'Homepage:'
		}

	}
}


$capabilitiesMarkdown = @()

$capabilitiesMarkdown += @"
# DevBox Capabilities
---

Image Name: $($DEVBOX_IMAGENAME)
Image Name: $($DEVBOX_IMAGEVERSION)

---
"@

[array] $packages = '${jsonencode(packages)}' | ConvertFrom-Json 

$packages | ForEach-Object { 

	$source = $_ | Get-PropertyValue -Name "source" -DefaultValue "winget"

	switch -exact ($source.ToLowerInvariant()) {

		'winget' {
			$_ | Parse-WinGetPackage
			Break
		}

		'msstore' {
			$_ | Parse-WinGetPackage
			Break
		}
	}

} | Where-Object { $_ } | Sort-Object Version | Sort-Object Title | ForEach-Object {

$capabilitiesMarkdown += @"
## [$($_.Title)]($($_.Homepage)) 

Publisher: $($_.Publisher)
Version:   $($_.Version)

$($_.Description)
"@

} 

$capabilitiesFile = Join-Path -Path $env:DEVBOX_HOME -ChildPath "Capabilities.html"
$capabilitiesLink = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) -ChildPath "Capabilities.lnk"

$capabilitiesMarkdown -join '' | Convert-Markdown2HTML | Out-File -FilePath $capabilitiesFile -Encoding utf8 -Force
New-Shortcut -Path $capabilitiesLink -TargetPath $capabilitiesFile -
