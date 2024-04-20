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
<html lang=`"en`">
	<head>
		<meta charset=`"utf-8`">
		<meta name=`"viewport`" content=`"width=device-width, initial-scale=1, minimal-ui`">
		<title>Microsoft DevBox Capabilities</title>
		<meta name=`"color-scheme`" content=`"light dark`">
		<link rel=`"stylesheet`" href=`"https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.5.1/github-markdown.css`">
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
		<article class=`"markdown-body`">$($response.Content | Out-String)</article>
	</body>
</html>
"@ | Out-String

}

function Parse-WinGetPackage() {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
		[object] $Package
    )

	$arguments = @(
		"show", 
		("--id {0}" -f $Package.name),
		("--source {0}" -f ($Package | Get-PropertyValue -Name "source" -DefaultValue "winget")), 
		"--exact",
		"--disable-interactivity"
	)

	if ($Package | Has-Property -Name "version") { 	
		$arguments += "--version {0}" -f $Package.version
	}
	
	$output = (Invoke-CommandLine -Command 'winget' -Arguments ($arguments -join ' ') | Select-Object -ExpandProperty Output | Out-String) -split [Environment]::NewLine

    if ($output) {

        $packageResult = $null 
        [string] $propertyName = $null
        [string[]] $propertyValue = $null

        foreach ($line in $output) {

            if ($line.Trim().Length -eq 0) { 
                
                # ignore empty lines
                continue 
            }
        
            if ($line.StartsWith("Found ")) {
            
                $packageResult = [PSCustomObject]@{
                    Title = $line.Substring($line.IndexOf(' ')).Trim()
                }

            } elseif ($packageResult) {

                if ($line.StartsWith('  ')) {

                    if ($propertyValue) {
                        $propertyValue += ( $line.Trim() )
                    } else {
                        $propertyValue = @( $line.Trim() )
                    }
            
                } else {
            
                    if ($propertyName) {
                                         
                        if ($propertyValue.Length -eq 1) {
                            $packageResult | Add-Member -MemberType NoteProperty -TypeName String -Name $propertyName -Value $propertyValue[0]
                        } else {
                            $packageResult | Add-Member -MemberType NoteProperty -TypeName String[] -Name $propertyName -Value $propertyValue
                        }

                        $propertyName = $null
                        $propertyValue = $null
                    }

                    if ($line.EndsWith(':')) {
            
                        $propertyName = $line.TrimEnd(':').Replace(' ', '')
                
                    } elseif ($line.Contains(':')) {

                        $segments = $line -split ':', 2
                        $propertyName = $segments[0].Trim().Replace(' ', '')
                        $propertyValue = $segments[1].Trim()
                    }
                }
            }
        }

        if ($packageResult -and $propertyName) {
            $packageResult | Add-Member -MemberType NoteProperty -Name $propertyName -Value $propertyValue
        }

        $packageResult | Write-Output
    }
}

function Render-HeaderMarkdown() {
	param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[string] $FilePath
	)

@"
# DevBox Capabilities

* Image Name:    $($env:DEVBOX_IMAGENAME)
* Image Version: $($env:DEVBOX_IMAGEVERSION)

---
"@ | Out-File -FilePath $FilePath -Encoding utf8 -Force

}

function Render-PackageMarkdown() {
	param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[string] $FilePath,
		[Parameter(Mandatory = $true)]
		[object] $Package
	)

@"

## [$($Package.Title)]($($Package.Homepage)) 

* Publisher: $($Package.Publisher)
* Version:   $($Package.Version)

$($Package.Description)

"@ | Out-File -FilePath $FilePath -Encoding utf8 -Append

}

[array] $packages = '${jsonencode(packages)}' | ConvertFrom-Json

if (Test-IsPacker) { 
    Invoke-ScriptSection -Title "Generate Capabilities Document" -ScriptBlock {

		$capabilitiesMarkdown = Join-Path -Path $env:DEVBOX_HOME -ChildPath "Capabilities.md"
		$capabilitiesMarkdown | Render-HeaderMarkdown

		$packageInfos = @()

		foreach ($package in $packages) { 

			$source = $package | Get-PropertyValue -Name "source" -DefaultValue "winget"
			$packageInfo = $null

			switch -exact ($source.ToLowerInvariant()) {

				'winget' {
					$packageInfo = $package | Parse-WinGetPackage
					Break
				}

				'msstore' {
					$packageInfo = $package | Parse-WinGetPackage
					Break
				}

			}

			if ($packageInfo) { $packageInfos += $packageInfo }
		} 
		
		$packageInfos `
			| Where-Object { $_ } `
			| Sort-Object Version `
			| Sort-Object Title `
			| ForEach-Object { $capabilitiesMarkdown | Render-PackageMarkdown -Package $_ }

		$capabilitiesHtml = Join-Path -Path $env:DEVBOX_HOME -ChildPath "Capabilities.html"
		Get-Content -Path $capabilitiesMarkdown | Out-String | Convert-Markdown2HTML | Out-File -FilePath $capabilitiesHtml -Encoding utf8 -Force

		$capabilitiesLink = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) -ChildPath "Capabilities.lnk"
		New-Shortcut -Path $capabilitiesLink -Target $capabilitiesHtml | Out-Null
	}
}