function Get-IsAdmin() {
	$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
	return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-IsPacker() {
	return ((Get-ChildItem env:packer_* | Measure-Object).Count -gt 0)
}

function Write-Header() {

	param (
		[string] $Package,
		[string] $Version,
		[string] $Source,
		[string] $Arguments
	)

	if ([string]::IsNullOrEmpty($Version)) 		{ $Version = "latest" }
	if ([string]::IsNullOrEmpty($Source)) 		{ $Source = "winget" }
	if ([string]::IsNullOrEmpty($Arguments)) 	{ $Arguments = "none" }

@"
==========================================================================================================
WinGet Package Manager Install
----------------------------------------------------------------------------------------------------------
Package:   {0}
Version:   {1}
Source:    {2}
Arguments: {3}
----------------------------------------------------------------------------------------------------------
"@ -f ($Package, $Version, $Source, $Arguments) | Write-Host

}

function Write-Footer() {

	param (
		[string] $Package
	)

@"
----------------------------------------------------------------------------------------------------------
Finished installing {0} 
==========================================================================================================
"@ -f ($Package) | Write-Host

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

function Get-Property() {
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

function Install-WinGetPackage() {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
		[object] $package
    )

	$arguments = ("install", ("--id {0}" -f $package.name),	"--exact")

	if ($package | Has-Property -Name "version") { 	
		$arguments += "--version {0}" -f $package.version
	}
	
	$arguments += "--source {0}" -f ($package | Get-Property -Name "source" -DefaultValue "winget")

	if ($package | Has-Property -Name "override") { 
		$arguments += "--override `"{0}`"" -f ($package | Get-Property -Name "override") 
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

Start-Process -FilePath "winget.exe" -ArgumentList ('source', 'reset', '--force') -NoNewWindow -Wait -ErrorAction SilentlyContinue
Start-Process -FilePath "winget.exe" -ArgumentList ('source', 'update', '--name', 'winget') -NoNewWindow -Wait -ErrorAction SilentlyContinue

foreach ($package in $packages) {

	Write-Header -Package $package.name -Version $package.version -Source $package.source -Arguments ($package.override -join " ").Trim()

	try
	{
		[string] $source = $package | Get-Property -Name "source" -DefaultValue "winget"
		[int] $exitCode = 0

		switch -exact ($source.ToLowerInvariant()) {

			'winget' {
				$exitCode = $package | Install-WinGetPackage
			}

			'msstore' {
				$exitCode = $package | Install-WinGetPackage
			}
		}
		
		if ($exitCode -ne 0) { exit $process.ExitCode }
	}
	finally
	{
		Write-Footer -Package $package.name 
	}
}
