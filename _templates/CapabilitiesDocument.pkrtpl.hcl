
function Has-Property() {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $InputObject,
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    return ($null -ne ($InputObject | Select -ExpandProperty $Name -ErrorAction SilentlyContinue))
}

function Get-PropertyValue() {
    param (
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

function Set-Shortcut() {
	param( 
		[Parameter(Mandatory=$true)][string]$Path,
		[Parameter(Mandatory=$true)][string]$TargetPath,
		[Parameter(Mandatory=$false)][string]$TargetArguments
	)

	$Shell = New-Object -ComObject ("WScript.Shell")
	$Shortcut = $Shell.CreateShortcut($Path)
	$Shortcut.TargetPath = $TargetPath
	$Shortcut.Arguments = $TargetArguments
	$Shortcut.Save()
}

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

function Convert-CapabilitiesMD2HTML() {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $MarkdownFile
    )
    
    $HtmlFile = [System.IO.Path]::ChangeExtension($MarkdownFile, 'html')

	$pandocUrl = (Invoke-WebRequest 'https://api.github.com/repos/jgm/pandoc/releases' | ConvertFrom-Json) `
                | Where-Object { $_.draft -eq $false -and $_.prerelease -eq $false } | Select-Object -First 1 -ExpandProperty assets `
                | Where-Object { $_.name.endswith('-windows-x86_64.zip') } | Select-Object -First 1 -ExpandProperty browser_download_url

	$pandocDir = Invoke-FileDownload -url $pandocUrl -expand $true
	$pandocExe = Get-ChildItem -Path $pandocDir -Filter 'pandoc.exe' -Recurse | Select-Object -First 1 -ExpandProperty 'Fullname'
    $pandocCss = Invoke-FileDownload -url 'https://raw.githubusercontent.com/SepCode/vscode-markdown-style/master/preview/github.css' -name 'pandoc.css'

    $pandocArgs = (
		"`"$MarkdownFile`"",
		"--standalone",
		"-c `"$pandocCss`"",
		"-o `"$HtmlFile`"",
		"--metadata title=`"DevBox Capabilities`""
    )

	$process = Start-Process $pandocExe -ArgumentList $pandocArgs -NoNewWindow -Wait -PassThru
	if ($process.ExitCode -ne 0) { Write-Warning "Pandoc exited with code $($process.ExitCode) !!!" }

	return $HtmlFile
}

function Extract-OutputValue() {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $InputObject,
        [Parameter(Mandatory = $true)]
        [string] $Header
    )

	$InputObject | Select-String -Pattern ("^(?:{0}) (.*)" -f $Header) | Select-Object -First 1 -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Last 1 | Select-Object -ExpandProperty Value | % Trim | Write-Output
}

function Parse-WinGetPackage() {
    param (
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

	$output = winget.exe ($arguments -join ' ')

	return [PSCustomObject]@{
		Title   	= $output | Extract-OutputValue -Header 'Found'
		Version 	= $output | Extract-OutputValue -Header 'Version:'
		Publisher   = $output | Extract-OutputValue -Header 'Publisher:'
		Description = $output | Extract-OutputValue -Header 'Description:'
		Homepage	= $output | Extract-OutputValue -Header 'Homepage:'
	}
}

[array] $packages = '${jsonencode(packages)}' | ConvertFrom-Json 
[array]	$results = @()

foreach ($package in $packages) {

	$source = $package | Get-PropertyValue -Name "source" -DefaultValue "winget"

	switch -exact ($source.ToLowerInvariant()) {

		'winget' {
			$results += $package | Parse-WinGetPackage
			Break
		}

		'msstore' {
			$results += $package | Parse-WinGetPackage
			Break
		}
	}
}

$capabilitiesMarkdown = Join-Path -Path $env:DEVBOX_HOME -ChildPath "Capabilities.md"

$results | Sort-Object Version | Sort-Object Title | ForEach-Object -Begin {

@"

# DevBox Capabilities
---

Image Name: $($DEVBOX_IMAGENAME)
Image Name: $($DEVBOX_IMAGEVERSION)

---
"@ | Write-Output


} -Process {

@"

## [$($_.Title)]($($_.Homepage)) 

Publisher: $($_.Publisher)
Version:   $($_.Version)

$($_.Description)
"@ | Write-Output

} | Out-File -FilePath $capabilitiesMarkdown -Encoding utf8

$capabilitiesHTMLURI = ([System.Uri]($capabilitiesMarkdown | Convert-CapabilitiesMD2HTML)).AbsoluteUri
$capabilitiesHTMLLNK = (Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) -ChildPath "DevBox Capabilities.lnk")

Set-Shortcut -Path $capabilitiesHTMLLNK -TargetPath $capabilitiesHTMLURI