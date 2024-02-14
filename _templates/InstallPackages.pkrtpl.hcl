param(
    [Parameter(Mandatory=$false)]
    [boolean] $Packer = ((Get-ChildItem env:packer_* | Measure-Object).Count -gt 0)
)

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if ($Packer) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup -Path $MyInvocation.MyCommand.Path -Name 'Install-Packages.ps1' -Elevate
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
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

function Install-WinGetPackage {

    param(
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

	if ($Package | Has-Property -Name "options") { 
		$Package | Get-PropertyArray -Name "options" | ForEach-Object { $arguments += "$_" }
	}

	$result = Invoke-CommandLine -Command "winget.exe" -Arguments ($arguments -join ' ')
	
	$result.Output -split "\r?\n" | ForEach-Object {
		# remove progress output
		$_ -split "\r" | Select-Object -Last 1 | Write-Host
	}

	return $result.ExitCode
}

function Install-ChocoPackage {

	param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
		[object] $Package
    )

	$arguments = (
		"install", 
		$Package.name,	
		"--yes",
		"--acceptlicense",
		"--nocolor",
		"--no-progress"
		)

	$result = Invoke-CommandLine -Command "choco" -Arguments ($arguments -join ' ')
	
	$result.Output -split "\r?\n" | ForEach-Object {
		# remove progress output
		$_ -split "\r" | Select-Object -Last 1 | Write-Host
	}

	return $result.ExitCode
}

[array] $packages = '${jsonencode(packages)}' | ConvertFrom-Json
$allowedScopes = ('all', (&{ if ($Packer) { 'machine' } else { 'user' } }))

Invoke-ScriptSection -Title "Packages" -ScriptBlock { $packages | ConvertTo-Json | Write-Host }

Invoke-ScriptSection -Title "WinGet initialization" -ScriptBlock {

	if (Test-IsElevated) {
		Write-Host ">>> Reset WinGet Sources"
		Start-Process -FilePath "winget.exe" -ArgumentList ('source', 'reset', '--force') -NoNewWindow -Wait 
	}

	Write-Host ">>> Update WinGet Sources"
	Start-Process -FilePath "winget.exe" -ArgumentList ('source', 'update') -NoNewWindow -Wait 
}

$successExitCodes_winget = @(
	-1978335189 # APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE  
)

$successExitCodes_choco = @(

)

foreach ($package in $packages) {

	$package | Invoke-ScriptSection -Title "Install Package" -ScriptBlock {

		if ($allowedScopes -contains ($package | Get-PropertyValue -Name 'scope')) {

			$successExitCodes = @(0) + ($package | Get-PropertyArray -Name 'exitCodes')
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

				'choco' {
					$successExitCodes = $successExitCodes + $successExitCodes_choco | Select-Object -Unique | Sort-Object
					$exitCode = ($package | Install-ChocoPackage)
					Break
				}
			}

			if ($successExitCodes -notcontains $exitCode) {
				Write-ErrorMessage "Installing $($package.name) failed with exit code '$exitCode'." 
				exit $exitCode
			} elseif ($exitCode -ne 0) {
				Write-ErrorMessage "Installing $($package.name) failed with exit code '$exitCode', but was ignored (SUCCESS EXIT CODES: $($successExitCodes -join ', '))"
			}

		} else {

			Write-Host "Installation skipped - package scope not allowed"
		}
	}
}
