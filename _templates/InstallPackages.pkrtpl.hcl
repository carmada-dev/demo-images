
function Get-IsAdmin() {
	$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
	return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-IsPacker() {
	return ((Get-ChildItem env:packer_* | Measure-Object).Count -gt 0)
}

function Write-Header() {

	param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $InputObject

	)

	$override = ($InputObject | Get-PropertyArray -Name 'override') -join ' '

	if ([string]::IsNullOrEmpty($overrides)) {
		$override = 'none'
	}

	$arguments = @(
		($InputObject.name),
		($InputObject | Get-PropertyValue -Name 'version' -DefaultValue 'latest'),
		($InputObject | Get-PropertyValue -Name 'source' -DefaultValue 'winget'),
		$override
	)

@"
==========================================================================================================
WinGet Package Manager Install
----------------------------------------------------------------------------------------------------------
Package:   {0}
Version:   {1}
Source:    {2}
Arguments: {3}
----------------------------------------------------------------------------------------------------------
"@ -f $arguments | Write-Host

}

function Write-Footer() {

	param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $InputObject
	)

	$arguments = @(
		($InputObject.name)
	)

@"
----------------------------------------------------------------------------------------------------------
Finished installing {0} 
==========================================================================================================
"@ -f $arguments | Write-Host

}

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

function Get-PropertyArray() {
    param (
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

function Install-WinGetPackage() {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
		[object] $Package
    )

	$arguments = ("install", ("--id {0}" -f $Package.name),	"--exact")

	if ($Package | Has-Property -Name "version") { 	
		$arguments += "--version {0}" -f $Package.version
	}
	
	$arguments += "--source {0}" -f ($Package | Get-PropertyValue -Name "source" -DefaultValue "winget")

	if ($Package | Has-Property -Name "override") { 
		$arguments += "--override `"{0}`"" -f (($Package | Get-PropertyArray -Name "override") -join ' ' )
	} else { 
		$arguments += "--silent" 
	} 

	$arguments += "--accept-package-agreements"
	$arguments += "--accept-source-agreements"
	$arguments += "--verbose-logs"

	$process = Start-Process -FilePath "winget.exe" -ArgumentList $arguments -NoNewWindow -Wait -PassThru
	return $process.ExitCode
}

if (-not (Get-IsPacker)) {
	Write-Host ">>> Starting transcript ..."
	Start-Transcript -Path ([System.IO.Path]::ChangeExtension($MyInvocation.MyCommand.Path, 'log')) -Append | Out-Null
}

[array] $packages = '${jsonencode(packages)}' | ConvertFrom-Json

@"
==========================================================================================================
Packages: {0} 
==========================================================================================================
"@ -f ($packages | ConvertTo-Json -Compress) | Write-Host

foreach ($package in $packages) {

	$package | Write-Header

	try
	{
		$successExitCodes = @(0) + ($package | Get-PropertyArray -Name 'exitCodes')
		$successExitCodes_winget = @(1)

		$source = $package | Get-PropertyValue -Name "source" -DefaultValue "winget"
		$exitCode = 0

		switch -exact ($source.ToLowerInvariant()) {

			'winget' {
				$successExitCodes = $successExitCodes + $successExitCodes_winget |  Select-Object -Unique | Sort-Object
				$exitCode = ($package | Install-WinGetPackage)
				Break
			}

			'msstore' {
				$successExitCodes = $successExitCodes + $successExitCodes_winget | Select-Object -Unique | Sort-Object
				$exitCode = ($package | Install-WinGetPackage)
				Break
			}
		}

		if ($successExitCodes -notcontains $exitCode) {
			Write-Warning "Installing $($package.name) failed with exit code '$exitCode' [$($successExitCodes -join ', ')]" 
			Exit $exitCode
		}
	}
	finally
	{
		$package | Write-Footer
	}
}
